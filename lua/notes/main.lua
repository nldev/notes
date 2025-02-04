local log = require'notes.util.log'
local sqlite = require'sqlite'



-- database
local tables = {
  topics = sqlite.tbl('topics', {
    id = { type = 'integer', primary = true, autoincrement = true },
    text = { type = 'text', required = true, unique = true },
    created = { type = 'date', required = true },
    updated = { type = 'date', required = true },
    description = 'text',
  }),
  headings = sqlite.tbl('headings', {
    id = { type = 'integer', primary = true, autoincrement = true },
    topic_id = { reference = 'topics.id', required = true, on_delete = 'cascade' },
    text = 'text',
  }),
}



-- config
-- FIXME: combine user config with defaults
-- FIXME: get default region from system
local config = {
  debug = true,
  notes_dir = vim.fn.expand'~/notes',
  data_dir = vim.fn.stdpath'data',
  cache_dir = vim.fn.stdpath'cache',
  inbox_file = vim.fn.expand'~/notes/inbox.md',
  toc_file = vim.fn.expand'~/notes/toc.md',
  bookmarks_file = vim.fn.stdpath'data' .. '/notes_bookmarks.lua',
  db_file = vim.fn.stdpath'data' .. '/notes_db.sqlite',
  region = 'America/Chicago',
}



-- state
local state = {
  last_topic_filename = config.inbox_file,
  writable_buffer = -1,
  help_window = 0,
  prompt_window = 0,
  prompt_buffer = 0,
  meta_window = 0,
  last_row = 0,
  is_opening_meta = false,
  is_opening_telescope = false,
  leader_pressed = false,
  help_queued = false,
  metadata = {},
  undo = {},
  last_prompt = {},
  bookmarks = {},
}



-- constants
local picker_options = {}



-- helpers
local function is_md_list_item (line)
  return line:match'^%s*[%*%-%+] ' or line:match'^%s*%d+%. '
end

local function trim (s)
  return s:match'^(.-)%s*$'
end

local function get_win_height ()
  local max = vim.o.lines - 10
  local height = vim.fn.line'$'
  if height >= max then
    return max
  end
  local saved_pos = vim.fn.winsaveview()
  local total_virtual_lines = 0
  local wrap_width = vim.api.nvim_win_get_width(0)
  for lnum = 1, vim.fn.line'$' do
    local line_text = vim.fn.getline(lnum)
    local line_width = vim.fn.strdisplaywidth(line_text)
    total_virtual_lines = total_virtual_lines + math.max(1, math.ceil(line_width / wrap_width))
  end
  vim.fn.winrestview(saved_pos)
  return total_virtual_lines
end

local function reset_leader ()
  if state.leader_pressed then
    vim.keymap.del('i', 't', { buffer = state.prompt_buffer })
    vim.keymap.del('i', 'h', { buffer = state.prompt_buffer })
    vim.keymap.del('i', 'd', { buffer = state.prompt_buffer })
    vim.keymap.del('i', 'l', { buffer = state.prompt_buffer })
    vim.keymap.del('i', 's', { buffer = state.prompt_buffer })
    vim.keymap.del('n', 't', { buffer = state.prompt_buffer })
    vim.keymap.del('n', 'h', { buffer = state.prompt_buffer })
    vim.keymap.del('n', 'd', { buffer = state.prompt_buffer })
    vim.keymap.del('n', 'l', { buffer = state.prompt_buffer })
    vim.keymap.del('n', 's', { buffer = state.prompt_buffer })
    vim.keymap.del('x', 's', { buffer = state.prompt_buffer })
    if vim.b.note_type == 'note' then
      vim.keymap.del('n', '1', { buffer = state.prompt_buffer })
      vim.keymap.del('n', '2', { buffer = state.prompt_buffer })
      vim.keymap.del('n', '3', { buffer = state.prompt_buffer })
      vim.keymap.del('n', '4', { buffer = state.prompt_buffer })
      vim.keymap.del('n', '5', { buffer = state.prompt_buffer })
      vim.keymap.del('n', 'f', { buffer = state.prompt_buffer })
      vim.keymap.del('n', 'i', { buffer = state.prompt_buffer })
      vim.keymap.del('x', '1', { buffer = state.prompt_buffer })
      vim.keymap.del('x', '2', { buffer = state.prompt_buffer })
      vim.keymap.del('x', '3', { buffer = state.prompt_buffer })
      vim.keymap.del('x', '4', { buffer = state.prompt_buffer })
      vim.keymap.del('x', '5', { buffer = state.prompt_buffer })
      vim.keymap.del('x', 'f', { buffer = state.prompt_buffer })
      vim.keymap.del('x', 'i', { buffer = state.prompt_buffer })
      vim.keymap.del('i', '1', { buffer = state.prompt_buffer })
      vim.keymap.del('i', '2', { buffer = state.prompt_buffer })
      vim.keymap.del('i', '3', { buffer = state.prompt_buffer })
      vim.keymap.del('i', '4', { buffer = state.prompt_buffer })
      vim.keymap.del('i', '5', { buffer = state.prompt_buffer })
      vim.keymap.del('i', 'f', { buffer = state.prompt_buffer })
      vim.keymap.del('i', 'i', { buffer = state.prompt_buffer })
    elseif vim.b.note_type == 'topic' then
      vim.keymap.del('n', 'm', { buffer = state.prompt_buffer })
      vim.keymap.del('x', 'm', { buffer = state.prompt_buffer })
      vim.keymap.del('i', 'm', { buffer = state.prompt_buffer })
    end
    state.leader_pressed = false
  end
end

local function get_headings (filename)
  local headings = {}
  local file = io.open(filename, 'r')
  if not file then
    return headings
  end
  local tmp = {}
  for line in file:lines() do
    local a = line:match'^(#+%s+.*)$'
    if a then
      local b = a:gsub('# ', '')
      local heading_text = b:gsub('#', ' ')
      table.insert(tmp, heading_text)
      print(heading_text)
    end
  end
  for i, _ in ipairs(tmp) do
    headings[#tmp - i + 1] = tmp[i]
  end
  file:close()
  return headings
end

local function format_time (str)
  local y,m,d,H,MM,S = str:match'(%d+)%-(%d+)%-(%d+)%s+@%s+(%d+):(%d+):(%d+)'
  if not y then
    return str
  end
  local cmd = str.format('TZ="%s" date -d "%s-%s-%s %s:%s:%s" +%%s', config.region, y,m,d,H,MM,S)
  local proc = io.popen(cmd)
  if not proc then
    return str
  end
  local epoch = proc:read'*a':gsub('\n', '')
  proc:close()
  local e = tonumber(epoch)
  if not e then
    return str
  end
  return os.date('!%Y-%m-%dT%H:%M:%SZ', e)
end

local function save_to_sql (filename)
  local file = io.open(filename, 'r')
  if not file then
    return
  end
  local lines = {}
  for line in file:lines() do
    table.insert(lines, line)
  end
  file:close()
  local in_yaml, meta, topic, subs = false, {}, nil, {}
  for _, l in ipairs(lines) do
    if l:match'^%-%-%-$' then
      in_yaml = not in_yaml
    elseif in_yaml then
      local k, v = l:match'^(%w+):%s*(.*)'
      if k and v then meta[k] = v end
    else
      local t1 = l:match'^#%s+(.*)'
      if t1 and not topic then topic = t1 end
      local sub = l:match'^(##+)%s+(.*)'
      if sub then table.insert(subs, l:match'^#+%s+(.*)') end
    end
  end
  if not meta or not meta.created or not meta.updated then
    return
  end
  local created = format_time(meta.created)
  local updated = format_time(meta.updated)
  local existing = tables.topics:where{ text = topic }
  if existing then
    tables.topics:update{
      where = { id = meta.id },
      set = {
        id = meta.id,
        text = meta.text,
        created = created,
        updated = updated,
        description = meta.description,
      },
    }
  else
    tables.topics:insert{
      id = meta.id,
      text = topic,
      created = created,
      updated = updated,
      description = meta.description,
    }
    existing = tables.topics:where{ text = topic }
  end
  -- if existing then
  --   existing:remove({ topic_id = existing.id })
  --   for _, sub in ipairs(subs) do
  --     existing:insert({ topic_id = existing.id, text = sub })
  --   end
  -- end
end



-- initialization
local function init ()
  -- ensure bookmarks file exists
  if vim.loop.fs_stat(config.bookmarks_file) then
    state.bookmarks = dofile(config.bookmarks_file) or {}
  end
  -- setup sqlite
  sqlite.new(config.db_file)
  sqlite{
    uri = config.db_file,
    topics = tables.topics,
    headings = tables.headings,
  }
  -- track last note and non-note
  vim.api.nvim_create_autocmd('BufEnter', {
    callback = function ()
      vim.defer_fn(function ()
        local name = vim.api.nvim_buf_get_name(0)
        if vim.fn.filereadable(name) ~= 1 then
          return
        end
        if name:match('^' .. config.notes_dir) then
          local filename = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
          state.last_topic_filename = filename
        else
          state.writable_buffer = vim.api.nvim_get_current_buf()
        end
      end, 0)
    end,
  })
  -- setup debug commands
  if config.debug then
    vim.api.nvim_create_user_command('NotesDebugBookmarksInspect', function ()
      print(vim.inspect(state.bookmarks))
    end, { nargs = 0 })
    vim.api.nvim_create_user_command('NotesDebugBookmarksLength', function ()
      print(#state.bookmarks)
    end, { nargs = 0 })
    vim.api.nvim_create_user_command('NotesDebugBookmarksForEach', function ()
      for i = 1, #state.bookmarks do
        if state.bookmarks[i] ~= nil then
          print(i .. ': ' .. state.bookmarks[i])
        end
      end
    end, { nargs = 0 })
  end
  -- listen for file changes 
  vim.loop.fs_event_start(vim.loop.new_fs_event(), config.notes_dir, { recursive = true }, function (error, filename)
    if not error and filename then
      local file = io.open(config.notes_dir .. '/' .. filename, 'r')
      if file then
        save_to_sql(config.notes_dir .. '/' .. filename)
        file:close()
      end
    end
  end)
end



-- api
local main = {
  ui = {},
}

--- Undo last refile and move prompt contents into clipboard.
---
---@private
function main.undo ()
  if #state.undo >= 1 then
    main.refile{ type = 'undo' }
  end
end

--- Toggles between table of contents and the last non-note file opened.
---
---@private
function main.toc ()
  if vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()) == config.toc_file then
    vim.cmd'silent! w!'
    if state.writable_buffer > 0 and vim.api.nvim_buf_is_valid(state.writable_buffer) then
      vim.api.nvim_set_current_buf(state.writable_buffer)
    else
      state.writable_buffer = -1
    end
  else
    vim.cmd('e ' .. config.toc_file)
  end
end

--- Toggles between inbox and the last non-note file opened.
---
---@private
function main.inbox ()
  if vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()) == config.inbox_file then
    vim.cmd'silent! w!'
    if state.writable_buffer > 0 and vim.api.nvim_buf_is_valid(state.writable_buffer) then
      vim.api.nvim_set_current_buf(state.writable_buffer)
    else
      state.writable_buffer = -1
    end
  else
    vim.cmd('e ' .. config.inbox_file)
  end
end

--- Toggles between last topic and the last non-note file opened.
---
---@private
function main.toggle ()
  local name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  if name == state.last_topic_filename and name:match('^' .. config.notes_dir) then
    vim.cmd'silent! w!'
    if state.writable_buffer > -1 and vim.api.nvim_buf_is_valid(state.writable_buffer) then
      vim.api.nvim_set_current_buf(state.writable_buffer)
    else
      state.writable_buffer = -1
    end
  else
    if #state.last_topic_filename > 0 and vim.loop.fs_stat(state.last_topic_filename) then
      vim.cmd('e ' .. state.last_topic_filename)
    else
      state.last_topic_filename = config.inbox_file
    end
  end
end

--- Bookmarks current topic to a given index.
---
---@private
function main.bookmark (index)
  local name = vim.api.nvim_buf_get_name(0)
  if name:find(config.notes_dir) then
    state.bookmarks[index] = name
  end
  if not vim.loop.fs_stat(config.bookmarks_file) then
    vim.cmd('!touch ' .. config.bookmarks_file)
  end
  local content = 'return ' .. vim.inspect(state.bookmarks)
  vim.fn.writefile({ content }, config.bookmarks_file)
end

--- Delete bookmark at a given index.
---
---@private
function main.delete_bookmark (index)
  local name = vim.api.nvim_buf_get_name(0)
  if name:find(config.notes_dir) then
    state.bookmarks[index] = nil
  end
  if not vim.loop.fs_stat(config.bookmarks_file) then
    vim.cmd('!touch ' .. config.bookmarks_file)
  end
  local content = 'return ' .. vim.inspect(state.bookmarks)
  vim.fn.writefile({ content }, config.bookmarks_file)
end

--- Opens bookmark in a new buffer.
---
---@private
function main.goto_bookmark (index)
  local name = state.bookmarks[index]
  if name and vim.loop.fs_stat(name) ~= nil then
    vim.cmd('e ' .. name)
  end
end

--- Displays current bookmarks.
---
---@private
function main.bookmarks ()
  if _G.Toast == nil then
    return
  end
  local formatted = {}
  local index = 1
  if state.last_topic_filename ~= '' then
    table.insert(formatted, '[n] ' .. vim.fs.basename(state.last_topic_filename))
    index = index + 1
  end
  for i = 1, #state.bookmarks do
    if state.bookmarks[i] ~= nil then
      table.insert(formatted, '[' .. i .. '] ' .. vim.fs.basename(state.bookmarks[i]))
      index = i + 1
    end
  end
  _G.Toast(formatted)
end

--- Opens add text window.
---
---@private
function main.add ()
  main.ui.create_prompt_window()
end

--- Refiles text to the given destination.
---
---@param destination table Data specifying where text should be moved to.
---@private
-- FIXME: should remove non-standard single / double quotes
function main.refile (destination)
  reset_leader()
  local filename = config.inbox_file
  local prompt = {}

  local function cleanup ()
    vim.api.nvim_command'stopinsert'
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buffer) == vim.fn.fnamemodify(filename, ':p') then
        vim.api.nvim_buf_call(buffer, function () vim.cmd'checktime' end)
        break
      end
    end
    if destination.type == 'undo' then
      vim.defer_fn(function () print('Reverted note from ' .. filename:match'([^/]+)$') end, 0)
    else
      vim.api.nvim_win_close(state.prompt_window, true)
      vim.api.nvim_buf_delete(state.prompt_buffer, { force = true })
      vim.defer_fn(function () print('Saved note to ' .. filename:match'([^/]+)$') end, 0)
    end
    vim.defer_fn(function () vim.cmd'echo ""' end, 1500)
    state.last_row = 0
    state.prompt_window = 0
    if state.help_window > 0 then
      vim.api.nvim_win_close(state.help_window, true)
      state.help_window = 0
    end
    state.metadata = {}
    -- FIXME: hack to make last_topic_file persist properly after saving prompt while a topic is open
    vim.defer_fn(function () state.last_topic_filename = filename end, 10)
  end

  local function save ()
    -- read existing file
    local existing = {}
    local read = io.open(filename, 'r')
    if not read then
      return
    end
    local contents = {}
    for line in read:lines() do
      table.insert(contents, line)
      table.insert(existing, line)
    end
    if destination.type == 'undo' then
      contents = state.undo
      local clipboard = ''
      for i, _ in ipairs(state.last_prompt) do
        local line = state.last_prompt[#state.last_prompt - i + 1]
        if i == #state.last_prompt then
          clipboard = clipboard .. line
        else
          clipboard = clipboard .. line .. '\n'
        end
      end
      vim.fn.setreg('+', clipboard)
      vim.fn.setreg('', clipboard)
      vim.fn.setreg('0', clipboard)
      state.undo = {}
      state.last_prompt = {}
    else
      state.undo = existing
      state.last_prompt = prompt
    end
    read:close()

    -- process text
    if destination.type ~= 'undo' then
      local raw = vim.api.nvim_buf_get_lines(state.prompt_buffer, 0, -1, false)
      for i = #raw, 1, -1 do
        table.insert(prompt, raw[i])
      end
      for i = #contents, 1, -1 do
        if trim(contents[i]) == '' then
          table.remove(contents, i)
        else
          break
        end
      end
      local first_prompt_item = trim(prompt[#prompt] or '')
      local last_content_item = trim(contents[#contents] or '')
      local add_extra_newline = false
      if first_prompt_item:match'^## ' then
        table.insert(contents, '')
        table.insert(contents, '')
        if trim(last_content_item) ~= '' then
          table.insert(contents, '')
        end
      elseif not is_md_list_item(first_prompt_item) then
        add_extra_newline = true
      elseif is_md_list_item(first_prompt_item) and is_md_list_item(last_content_item) then
        add_extra_newline = false
      else
        add_extra_newline = true
      end
      if add_extra_newline and trim(last_content_item) ~= '' then
        table.insert(contents, '')
      end
      for i = 1, #prompt do
        table.insert(contents, trim(prompt[#prompt - i + 1]))
      end
      while #contents > 0 and trim(contents[#contents]) == '' do
        table.remove(contents)
      end
      if #contents > 0 and trim(contents[#contents]) ~= '' then
        table.insert(contents, '')
      end
    end

    -- create tmp file
    local title = filename:match'([^/]+)$'
    local tmp = config.cache_dir .. '/' .. title .. '.tmp.md'
    local out = io.open(tmp, 'w')
    if not out then
      return
    end
    for _, line in ipairs(contents) do
      out:write(line .. '\n')
    end
    out:close()

    -- delete existing file and move tmp file to permanent location
    os.remove(filename)
    os.rename(tmp, filename)

    -- save to sql
    save_to_sql(filename)

    -- cleanup
    cleanup()
  end

  -- undo
  if destination.type == 'undo' then
    filename = state.last_topic_filename
    save()
    return
  end

  -- save to inbox
  if not destination or destination.type == 'inbox' then
    save()
    return
  end

  -- save to table of contents
  if not destination or destination.type == 'toc' then
    filename = config.toc_file
    save()
    return
  end

  -- save to last
  if destination.type == 'last' then
    if #state.last_topic_filename > 0 and vim.loop.fs_stat(state.last_topic_filename) then
      filename = state.last_topic_filename
    else
      filename = config.inbox_file
    end
    save()
    return
  end

  -- save to fuzzy
  if destination.type == 'fuzzy' then
    local actions = require'telescope.actions'
    local action_state = require'telescope.actions.state'
    state.is_opening_telescope = true
    if state.help_window > 0 then
      vim.api.nvim_win_close(state.help_window, true)
      state.help_window = 0
    end
    require'telescope.builtin'.find_files{
      cwd = config.notes_dir,
      prompt_title = 'Topic Refile',
      attach_mappings = function ()
        actions.select_default:replace(function (buffer)
          filename = action_state.get_selected_entry().path
          actions.close(buffer)
          save()
        end)
        return true
      end,
    }
    return
  end

  -- save to heading
  if destination.type == 'heading' then
    local actions = require'telescope.actions'
    local action_state = require'telescope.actions.state'
    local pickers = require'telescope.pickers'
    local finders = require'telescope.finders'
    local conf = require'telescope.config'.values
    state.is_opening_telescope = true
    if state.help_window > 0 then
      vim.api.nvim_win_close(state.help_window, true)
      state.help_window = 0
    end
    require'telescope.builtin'.find_files{
      cwd = config.notes_dir,
      prompt_title = 'Find Topic (Heading Refile)',
      attach_mappings = function ()
        actions.select_default:replace(function (a)
          filename = action_state.get_selected_entry().path
          actions.close(a)
          state.is_opening_telescope = true
          pickers.new(picker_options, {
            prompt_title = 'Heading Refile',
            finder = finders.new_table(get_headings(filename)),
            sorter = conf.generic_sorter(picker_options),
            attach_mappings = function ()
              actions.select_default:replace(function (b)
                local data = action_state.get_selected_entry()
                local heading = data[1]
                -- FIXME: open topic at heading
                print(heading)
                actions.close(b)
              end)
              return true
            end,
          }):find()
        end)
        return true
      end,
    }
    return
  end

  -- save to history
  if destination.type == 'history' then
    return
  end

  -- save to bookmark
  if destination.type == 'bookmark' then
    local name = state.bookmarks[destination.num]
    if name and vim.loop.fs_stat(name) then
      filename = name
      save()
    end
    return
  end
end

--- Opens edit metadata window, returns window number and buffer number.
---
---@private
function main.ui.create_metadata_window ()
  if vim.b.note_type ~= 'topic' then
    return
  end
  if state.help_window > 0 then
    vim.api.nvim_win_close(state.help_window, false)
  end
  state.is_opening_meta = true
  local config = vim.api.nvim_win_get_config(state.prompt_window)
  local width = config.width
  local col = (config.col or 0)
  local row = (config.row or 0) + (config.height or 0) + 2
  local buffer = vim.api.nvim_create_buf(false, true)
  state.meta_window = vim.api.nvim_open_win(buffer, false, {
    title = 'Metadata',
    relative = 'editor',
    width = width,
    height = #state.metadata or 1,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded',
  })
  vim.api.nvim_set_current_win(state.meta_window)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, state.metadata)
  vim.wo.winhl = 'FloatBorder:@lsp.type.property'
  vim.bo.filetype = 'yaml'
  vim.bo.buftype = 'nofile'
  vim.bo.buflisted = false
  vim.opt.wrap = false
  vim.opt.linebreak = false
  local function save ()
    state.metadata = {}
    for _, line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)) do
      table.insert(state.metadata, line)
    end
    vim.api.nvim_win_close(state.meta_window, true)
  end
  vim.api.nvim_create_autocmd({ 'BufLeave' }, {
    buffer = buffer,
    callback = function ()
      state.last_row = vim.fn.line'.'
      vim.api.nvim_win_close(state.meta_window, true)
    end
  })
  if state.last_row == 0 then
    state.last_row = vim.o.lines
  end
  vim.cmd('norm! ' .. state.last_row .. 'G')
  if vim.fn.mode(1):sub(1, 1) == 'i' then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<c-o>', true, false, true), 'i', true)
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('$', true, false, true), 'n', true)
  vim.keymap.set({ 'n', 'x', 'i' }, '<c-s>', function () save() end, { buffer = buffer, noremap = true })
  vim.keymap.set({ 'n', 'x', 'i' }, '<c-k>', function () save() end, { buffer = buffer, noremap = true })
  vim.keymap.set('n', '<esc>', function () vim.cmd'silent! bd' end, { buffer = buffer, noremap = true })
  vim.keymap.set('n', '<c-c>', function () vim.cmd'silent! bd' end, { buffer = buffer, noremap = true })
  vim.keymap.set('i', '<bs>', function ()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<bs>', true, false, true), 'n', true)
  end, { buffer = true, noremap = true })
end

--- Opens bookmark help window.
---
---@private
function main.ui.create_help_window ()
  if not vim.api.nvim_win_is_valid(state.prompt_window) then
    return
  end
  if state.help_window > 0 then
    vim.api.nvim_win_close(state.help_window, false)
  end
  local conf = vim.api.nvim_win_get_config(state.prompt_window)
  local width = conf.width
  local col = (conf.col or 0)
  local row = (conf.row or 0) + (conf.height or 0) + 2
  local buffer = vim.api.nvim_create_buf(false, true)
  local count = 0
  for i = 1, #state.bookmarks do
    if state.bookmarks[i] then
      count = count + 1
    end
  end
  local height = math.min(count, 5) + 1
  state.help_window = vim.api.nvim_open_win(buffer, false, {
    title = '<C-k>',
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded',
  })
  local formatted = {}
  local index = 1
  if state.last_topic_filename ~= '' then
    table.insert(formatted, '[s] ' .. vim.fs.basename(state.last_topic_filename))
    index = index + 1
  end
  for i = 1, #state.bookmarks do
    if state.bookmarks[i] ~= nil then
      table.insert(formatted, '[' .. i .. '] ' .. vim.fs.basename(state.bookmarks[i]))
      index = i + 1
    end
  end
  local full_path = vim.fn.expand'%:p'
  if full_path:sub(1, #config.notes_dir) == config.notes_dir then
    return full_path:sub(#config.notes_dir + 2)
  end
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, formatted)
  vim.api.nvim_win_set_option(state.help_window, 'winhl', 'FloatBorder:GitSignsDelete')
  vim.api.nvim_buf_set_option(buffer, 'wrap', false)
  vim.api.nvim_buf_set_option(buffer, 'linebreak', false)
  vim.api.nvim_buf_set_option(buffer, 'filetype', 'text')
  vim.api.nvim_buf_set_option(buffer, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buffer, 'buflisted', false)
  vim.api.nvim_create_autocmd({ 'BufLeave' }, {
    buffer = buffer,
    callback = function ()
      vim.api.nvim_win_close(state.help_window, true)
    end
  })
end

--- Opens add text window, returns window number and buffer number.
---
---@private
function main.ui.create_prompt_window ()
  local width = math.min(vim.o.columns - 10, 60)
  local row = math.max(1, (math.floor((vim.o.lines - 1) / 2) - 2))
  local col = math.floor((vim.o.columns - width) / 2)
  state.prompt_buffer = vim.api.nvim_create_buf(false, true)
  state.prompt_window = vim.api.nvim_open_win(state.prompt_buffer, true, {
    relative = 'editor',
    width = width,
    height = 1,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
  })
  local function note_style ()
    vim.api.nvim_win_set_config(state.prompt_window, { title = 'Note' })
    vim.wo.winhl = 'FloatBorder:@lsp.type.property'
    vim.bo.filetype = 'markdown'
  end
  local function topic_style ()
    vim.api.nvim_win_set_config(state.prompt_window, { title = 'Topic' })
    vim.wo.winhl = 'FloatBorder:Keyword'
    vim.bo.filetype = 'markdown'
  end
  local function tag_style ()
    vim.api.nvim_win_set_config(state.prompt_window, { title = 'Tag' })
    vim.wo.winhl = 'FloatBorder:Number'
    vim.bo.filetype = 'markdown'
  end
  note_style()
  vim.b.note_type = 'note'
  vim.bo.buftype = 'nofile'
  vim.bo.buflisted = false
  vim.opt.wrap = true
  vim.opt.linebreak = true
  if vim.fn.mode(1):sub(1, 1) ~= 'i' then
    vim.api.nvim_feedkeys('i', 'n', true)
  end
  local function on_change ()
    reset_leader()
    if state.help_window > 0 then
      vim.api.nvim_win_close(state.help_window, false)
      state.help_window = 0
    end
    local first_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ''
    local height = math.min(vim.o.lines - 10, get_win_height())
    vim.api.nvim_win_set_config(state.prompt_window, {
      relative = 'editor',
      height = height,
      row = math.max(1, (math.floor((vim.o.lines - height) / 2) - 2)),
      col = math.floor((vim.o.columns - width) / 2),
    })
    vim.cmd'Z'

    -- topic
    if vim.b.note_type ~= 'todo' then
      local is_topic = first_line:match'^#%s$' ~= nil
      or first_line:match'^#%s$' ~= nil
      or first_line:match'^#%s+' ~= nil
      if is_topic then
        vim.b.note_type = 'topic'
        topic_style()
      else
        vim.b.note_type = 'note'
      end
    end

    -- note
    if vim.b.note_type == 'note' then
      note_style()
    end

    -- todo
    local is_empty = vim.fn.line'$' == 1 and vim.fn.getline(1) == ''
    if not is_empty and vim.b.note_type ~= 'todo' then
      local is_todo = first_line:lower():match'^todo%s' ~= nil
      or first_line:lower():match'^tood%s' ~= nil
      or first_line:lower():match'^tdoo%s' ~= nil
      or first_line:lower():match'^otod%s' ~= nil
      or first_line:lower():match'^otdo%s' ~= nil
      or first_line:lower():match'^odto%s' ~= nil
      or first_line:lower():match'^tod%so' ~= nil
      or first_line:lower():match'^to%sdo' ~= nil
      or first_line:lower():match'^t%sodo' ~= nil
      or first_line:lower():match'^%stodo' ~= nil
      or first_line:lower():match'^todod%s' ~= nil
      if is_todo then
        vim.api.nvim_win_set_config(state.prompt_window, { title = 'Todo' })
        vim.wo.winhl = 'FloatBorder:String'
        vim.b.note_type = 'todo'
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local texts = {}
        local start_found = false
        for _, line in ipairs(lines) do
          if not start_found then
            local start = (#lines > 1 and line:lower():match'^todo%s$')
            or (#lines > 1 and line:lower():match'^tood%s$')
            or (#lines > 1 and line:lower():match'^tdoo%s$')
            or (#lines > 1 and line:lower():match'^otod%s$')
            or (#lines > 1 and line:lower():match'^otdo%s$')
            or (#lines > 1 and line:lower():match'^odto%s$')
            or (#lines > 1 and line:lower():match'^tod%so$')
            or (#lines > 1 and line:lower():match'^to%sdo$')
            or (#lines > 1 and line:lower():match'^t%sodo$')
            or (#lines > 1 and line:lower():match'^t%sodo$')
            or (#lines > 1 and line:lower():match'^%stodo$')
            or (#lines > 1 and line:lower():match'^todod%s$')
            or line:lower():match'^todo%s(.+)$'
            or line:lower():match'^tood%s(.+)$'
            or line:lower():match'^tdoo%s(.+)$'
            or line:lower():match'^otod%s(.+)$'
            or line:lower():match'^otdo%s(.+)$'
            or line:lower():match'^odto%s(.+)$'
            or line:lower():match'^tod%so(.+)$'
            or line:lower():match'^to%sdo(.+)$'
            or line:lower():match'^t%sodo(.+)$'
            or line:lower():match'^%stodo(.+)$'
            if start then
              table.insert(texts, start)
              start_found = true
            end
          elseif start_found then
            table.insert(texts, line)
          end
        end
        vim.api.nvim_buf_set_lines(state.prompt_buffer, 0, -1, false, {})
        if #lines > 1 then
          vim.defer_fn(function ()
            if vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]:match'^todo $' then
              vim.cmd'silent! norm! dd'
            elseif vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]:match'^todo ' then
              local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]:sub(6)
              vim.api.nvim_buf_set_lines(0, 0, 1, false, { line })
            end
          end, 0)
        end
        if #texts > 0 then
          vim.api.nvim_buf_set_lines(state.prompt_buffer, 0, -1, false, texts)
          vim.api.nvim_win_set_cursor(state.prompt_window, { 1, 0 })
        end
      end
    end

    -- tag
    if vim.b.note_type ~= 'todo' then
      local is_tag = first_line:lower():match'^#[%w-]+$'
      if is_tag then
        vim.b.note_type = 'tag'
        tag_style()
      end
    end
  end
  vim.api.nvim_create_autocmd({ 'BufLeave' }, {
    buffer = state.prompt_buffer,
    callback = function ()
      reset_leader()
      if state.help_window > 0 then
        vim.api.nvim_win_close(state.help_window, false)
        state.help_window = 0
      end
      if (#vim.api.nvim_list_wins() > 1) and not state.is_opening_meta and not state.is_opening_telescope then
        vim.api.nvim_win_close(0, true)
      end
      state.is_opening_meta = false
      state.is_opening_telescope = false
    end
  })

  -- on buffer change
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    buffer = state.prompt_buffer,
    callback = on_change,
  })
  vim.api.nvim_create_autocmd({ 'VimResized' }, {
    buffer = state.prompt_buffer,
    callback = on_change,
  })

  -- build metadata
  local date = vim.fn.strftime'%Y-%m-%d @ %H:%M:%S'
  state.metadata = {
    'parent: ',
    'description: ',
    'tags: ',
  }

  -- save window buffer and close
  local id = vim.fn.strftime'%Y%m%d%H%M%S'
  local filename = config.inbox_file
  local function save ()
    local title = ''
    if vim.b.note_type == 'topic' then
      local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
      local words = line:match'^#%s+(.+)'
      if words then
        title = id .. '-' .. words:gsub('[^%w%s]', ''):match'^%s*(.-)%s*$':gsub('%s+', '-'):lower()
        filename = config.notes_dir .. '/' .. title .. '.md'
      end
    end
    if vim.b.note_type == 'note' then
      main.refile{ type = 'last' }
    end
    if vim.b.note_type == 'topic' then
      local contents = {}
      table.insert(contents, '---')
      table.insert(contents, 'id: ' .. id)
      table.insert(contents, 'created: ' .. date)
      table.insert(contents, 'updated: ' .. date)
      for i = #state.metadata, 1, -1 do
        local line = trim(state.metadata[#state.metadata - i + 1])
        if line ~= 'parent:' and line ~= 'description:' and line ~= 'tags:' then
          table.insert(contents, line)
        end
      end
      table.insert(contents, '---')
      table.insert(contents, '')
      local lines = vim.api.nvim_buf_get_lines(state.prompt_buffer, 0, -1, false)
      for i = #lines, 1, -1 do
        table.insert(contents, lines[#lines - i + 1])
      end
      for i, str in ipairs(contents) do
        contents[i] = str:gsub('%s+$', '')
      end
      table.insert(contents, '')
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(b) == vim.fn.fnamemodify(filename, ':p') then
          vim.api.nvim_buf_delete(b, { force = true })
          break
        end
      end
      local buffer = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_lines(buffer, 0, -1, false, contents)
      vim.api.nvim_buf_call(buffer, function () vim.cmd('w! ' .. filename) end)
      vim.api.nvim_buf_delete(buffer, { force = true })
      vim.api.nvim_win_close(0, false)
      -- FIXME: hack to make last_topic_file persist properly after saving prompt while a topic is open
      if filename ~= config.inbox_file and filename ~= config.toc_file then
        vim.defer_fn(function ()
          state.last_topic_filename = filename
        end, 10)
      end
      state.last_row = 0
      vim.api.nvim_command'stopinsert'
      vim.defer_fn(function () print('Saved topic to ' .. filename:match'([^/]+)$') end, 0)
      vim.defer_fn(function () vim.cmd'echo ""' end, 1500)
    end
  end

  -- exit todo prompt
  local function exit_todo (check_is_beginning)
    if vim.b.note_type ~= 'todo' then
      return
    end
    local is_empty = vim.fn.line'$' <= 1 and vim.fn.getline(1) == ''
    local position = vim.api.nvim_win_get_cursor(state.prompt_window)
    local cursor_row = position[1]
    local cursor_col = position[2]
    local is_beginning = cursor_row == 1 and cursor_col == 0
    if (not check_is_beginning and is_empty) or (check_is_beginning and is_beginning) then
      local first_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ''
      local is_topic = first_line:match'^#%s$' ~= nil
        or first_line:match'^#%s$' ~= nil
        or first_line:match'^#%s+' ~= nil
      local is_tag = first_line:lower():match'^#[%w-]+$'
      if is_tag then
        vim.b.note_type = 'tag'
        tag_style()
      elseif is_topic then
        vim.b.note_type = 'topic'
        topic_style()
      else
        vim.b.note_type = 'note'
        note_style()
      end
    end
  end
  local function exit_todo_wrap (key, check_is_beginning)
    if vim.fn.line'$' == 1 and vim.fn.empty(vim.fn.getline(1)) == 1 and vim.b.note_type ~= 'todo' and not check_is_beginning then
      vim.cmd'silent! bd!'
    else
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), 'n', true)
      exit_todo(check_is_beginning)
    end
  end
  vim.keymap.set('i', '<c-w>', function () exit_todo_wrap('<c-w>', true) end, { buffer = true, noremap = true })
  vim.keymap.set('i', '<bs>', function () exit_todo_wrap('<bs>', true) end, { buffer = true, noremap = true })
  vim.keymap.set({ 'n', 'x' }, 'x', function () exit_todo_wrap'x' end, { buffer = true, noremap = true })
  vim.keymap.set({ 'n', 'x' }, 'X', function () exit_todo_wrap'X' end, { buffer = true, noremap = true })
  vim.keymap.set('i', '<c-e>', function ()
    if state.help_window > 0 then
      vim.api.nvim_win_close(state.help_window, true)
      state.help_window = 0
    end
    reset_leader()
  end, { buffer = true, noremap = true })
  vim.keymap.set('i', '<m-c>', function ()
    if state.help_window > 0 then
      vim.api.nvim_win_close(state.help_window, true)
      state.help_window = 0
    end
    reset_leader()
  end, { buffer = true, noremap = true })
  vim.keymap.set('i', '<c-c>', function ()
    if state.help_window > 0 then
      vim.api.nvim_win_close(state.help_window, true)
      state.help_window = 0
    end
    if not state.leader_pressed then
      vim.cmd'silent! bd!'
      state.last_row = 0
      vim.api.nvim_command'stopinsert'
    end
    reset_leader()
  end, { buffer = true, noremap = true })
  vim.keymap.set({ 'n', 'x', 'i' }, '<esc>', function ()
    if state.help_window > 0 then
      vim.api.nvim_win_close(state.help_window, true)
      state.help_window = 0
    end
    if not state.leader_pressed then
      if vim.fn.mode(1):sub(1, 1) == 'n'
        and vim.fn.line'$' == 1
        and vim.fn.empty(vim.fn.getline(1)) == 1
        and vim.b.note_type ~= 'todo'
      then
        vim.cmd'silent! bd!'
        state.last_row = 0
      end
      vim.api.nvim_feedkeys('\x1b', 'n', true)
    end
    reset_leader()
  end, { buffer = true, noremap = true })
  vim.keymap.set({ 'n', 'x', 'i' }, '<c-s>', function () save() end, { buffer = true, noremap = true })
  local session = 0
  vim.keymap.set({ 'n', 'x', 'i' }, '<c-k>', function ()
    if session <= 10 then
      session = session + 1
    else
      session = 0
    end
    local this_session = session
    if state.leader_pressed then
      reset_leader()
      if state.help_window > 0 then
        vim.api.nvim_win_close(state.help_window, true)
        state.help_window = 0
      end
      return
    end
    if not state.help_queued then
      vim.defer_fn(function ()
        state.help_queued = false
        if state.prompt_window > 0 and state.leader_pressed and this_session == session then
          main.ui.create_help_window()
        end
      end, 500)
    end
    state.leader_pressed = true
    state.help_queued = true
    vim.keymap.set({ 'n', 'i' }, 'h', function ()
      reset_leader()
      if state.help_window > 0 then
        vim.api.nvim_win_close(state.help_window, true)
        state.help_window = 0
      end
      local cursor_pos = vim.api.nvim_win_get_cursor(0)
      local line = vim.api.nvim_get_current_line()
      if line:sub(1, 3) == '## ' then
        vim.api.nvim_set_current_line(line:sub(4))
        cursor_pos[2] = math.max(1, cursor_pos[2] - 3)
      else
        vim.cmd 'norm! I## '
        cursor_pos[2] = math.max(cursor_pos[2] + 3)
      end
      vim.api.nvim_win_set_cursor(0, cursor_pos)
    end, { buffer = true, noremap = true })
    vim.keymap.set({ 'n', 'i' }, 'd', function ()
      reset_leader()
      if state.help_window > 0 then
        vim.api.nvim_win_close(state.help_window, true)
        state.help_window = 0
      end
      local cursor_pos = vim.api.nvim_win_get_cursor(0)
      local line = vim.api.nvim_get_current_line()
      if line:sub(1, 6) == '- [ ] ' then
        vim.api.nvim_set_current_line(line:sub(7))
        cursor_pos[2] = math.max(1, cursor_pos[2] - 6)
      else
        if line:sub(1, 2) == '- ' then
          vim.api.nvim_set_current_line(line:sub(3))
          cursor_pos[2] = math.max(cursor_pos[2] - 2)
        end
        vim.cmd 'norm! I- [ ] '
        cursor_pos[2] = math.max(cursor_pos[2] + 6)
      end
      vim.api.nvim_win_set_cursor(0, cursor_pos)
    end, { buffer = true, noremap = true })
    vim.keymap.set({ 'n', 'i' }, 't', function ()
      reset_leader()
      if state.help_window > 0 then
        vim.api.nvim_win_close(state.help_window, true)
        state.help_window = 0
      end
      local cursor_pos = vim.api.nvim_win_get_cursor(0)
      local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
      local is_first_line = vim.api.nvim_win_get_cursor(0)[1] == 1
      if line:sub(1, 2) == '# ' then
        vim.api.nvim_buf_set_lines(0, 0, 1, false, { line:sub(3) })
        if is_first_line then
          cursor_pos[2] = math.max(1, cursor_pos[2] - 2)
        end
      else
        vim.cmd 'norm! ggI# '
        if is_first_line then
          cursor_pos[2] = math.max(cursor_pos[2] + 2)
        end
      end
      vim.api.nvim_win_set_cursor(0, cursor_pos)
    end, { buffer = true, noremap = true })
    vim.keymap.set({ 'n', 'i' }, 'l', function ()
      reset_leader()
      if state.help_window > 0 then
        vim.api.nvim_win_close(state.help_window, true)
        state.help_window = 0
      end
      local cursor_pos = vim.api.nvim_win_get_cursor(0)
      local line = vim.api.nvim_get_current_line()
      if line:sub(1, 2) == '- ' then
        if line:sub(1, 6) == '- [ ] ' then
          vim.api.nvim_set_current_line(line:sub(7))
          cursor_pos[2] = math.max(cursor_pos[2] - 6)
          vim.cmd 'norm! I- '
          cursor_pos[2] = math.max(cursor_pos[2] + 2)
        else
          vim.api.nvim_set_current_line(line:sub(3))
          cursor_pos[2] = math.max(cursor_pos[2] - 2)
        end
      else
        vim.cmd 'norm! I- '
        cursor_pos[2] = math.max(cursor_pos[2] + 2)
      end
      vim.api.nvim_win_set_cursor(0, cursor_pos)
    end, { buffer = true, noremap = true })
    vim.keymap.set({ 'n', 'x', 'i' }, 's', function () save() end, { buffer = true, noremap = true })
    if vim.b.note_type == 'note' then
      vim.keymap.set({ 'n', 'x', 'i' }, '1', function () main.refile{ type = 'bookmark', num = 1 } end, { buffer = true, noremap = true })
      vim.keymap.set({ 'n', 'x', 'i' }, '2', function () main.refile{ type = 'bookmark', num = 2 } end, { buffer = true, noremap = true })
      vim.keymap.set({ 'n', 'x', 'i' }, '3', function () main.refile{ type = 'bookmark', num = 3 } end, { buffer = true, noremap = true })
      vim.keymap.set({ 'n', 'x', 'i' }, '4', function () main.refile{ type = 'bookmark', num = 4 } end, { buffer = true, noremap = true })
      vim.keymap.set({ 'n', 'x', 'i' }, '5', function () main.refile{ type = 'bookmark', num = 5 } end, { buffer = true, noremap = true })
      vim.keymap.set({ 'n', 'x', 'i' }, 'f', function () main.refile{ type = 'fuzzy' } end, { buffer = true, noremap = true })
      vim.keymap.set({ 'n', 'x', 'i' }, 'F', function () main.refile{ type = 'heading' } end, { buffer = true, noremap = true })
      vim.keymap.set({ 'n', 'x', 'i' }, 'i', function () main.refile{ type = 'inbox' } end, { buffer = true, noremap = true })
    elseif vim.b.note_type == 'topic' then
      vim.keymap.set({ 'n', 'x', 'i' }, 'm', function ()
        reset_leader()
        if state.help_window > 0 then
          vim.api.nvim_win_close(state.help_window, true)
          state.help_window = 0
        end
        main.ui.create_metadata_window()
      end, { buffer = true, noremap = true })
    end
  end, { buffer = true, noremap = true })
end

init()

return main

