-- [x] nf = find topic
-- [x] nn = toggle last topic (similar to toggle terminal)
-- [x] refile to last
-- [x] ensure note/topic-specific actions are not doable from the wrong action
-- [ ] remove unused metadata (on save, on refile)
-- [ ] bookmark topic
-- [ ] bookmark heading
-- [ ] bookmark refile
-- [ ] save last heading as well as last_note_file

-- open options:
-- ni inbox
-- [count] nc count
-- n1 bookmarked topic/heading 1
-- n2 bookmarked topic/heading 2
-- n3 bookmarked topic/heading 3
-- n4 bookmarked topic/heading 4
-- n5 bookmarked topic/heading 5
-- nf fuzzy
-- ns subheading

local state = require'notes.state'
local log = require'notes.util.log'

local main = {
  ui = {},
  topics = {},
}

local last_note_file = ''
local last_writable_buffer = -1
local prompt_window = 0
local prompt_buffer = 0
local meta_window = 0
local last_row = 0
local is_opening_meta = false
local is_opening_telescope = false
local metadata = {}

vim.api.nvim_create_autocmd('BufEnter', {
  callback = function ()
    vim.defer_fn(function ()
      local name = vim.api.nvim_buf_get_name(0)
      if vim.fn.filereadable(name) == 1 then
        if name:match('^' .. vim.fn.expand('~/notes') .. '/') then
          local filename = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
          if filename ~= '/home/user/notes/inbox.md' then
            last_note_file = filename
          end
        else
          last_writable_buffer = vim.api.nvim_get_current_buf()
        end
      end
    end, 0)
  end,
})

--- Toggles between inbox and the last non-note file opened.
---
---@private
function main.inbox ()
  if vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()) == vim.fn.expand'~/notes/inbox.md' then
    vim.cmd'silent! w!'
    if last_writable_buffer > 0 and vim.api.nvim_buf_is_valid(last_writable_buffer) then
      vim.api.nvim_set_current_buf(last_writable_buffer)
    else
      last_writable_buffer = -1
    end
  else
    vim.cmd'e /home/user/notes/inbox.md'
  end
end

--- Toggles between last topic and the last non-note file opened.
---
---@private
function main.toggle ()
  local name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  if name ~= vim.fn.expand'~/notes/inbox.md' and name:match('^' .. vim.fn.expand('~/notes') .. '/') then
    vim.cmd'silent! w!'
    if last_writable_buffer > -1 and vim.api.nvim_buf_is_valid(last_writable_buffer) then
      vim.api.nvim_set_current_buf(last_writable_buffer)
    else
      last_writable_buffer = -1
    end
  else
    if #last_note_file > 0 and vim.loop.fs_stat(last_note_file) then
      vim.cmd('e ' .. last_note_file)
    else
      last_note_file = ''
    end
  end
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
function main.refile (destination)
  if vim.b.note_type ~= 'note' then
    return
  end
  if vim.fn.line'$' == 1 and vim.fn.empty(vim.fn.getline(1)) == 1 and vim.b.note_type ~= 'todo' then
    vim.cmd'silent! bd!'
    vim.api.nvim_command'stopinsert'
    return
  end
  local filename = '/home/user/notes/inbox.md'
  local raw = vim.api.nvim_buf_get_lines(prompt_buffer, 0, -1, false)
  local prompt = {}
  for i = #raw, 1, -1 do
    table.insert(prompt, raw[i])
  end

  local function save ()
    local read = io.open(filename, 'r')
    if not read then
      return
    end
    local contents = {}
    for line in read:lines() do
      table.insert(contents, line)
    end
    read:close()
    -- FIXME: if non-list, add extra newline
    -- FIXME: if list, do not extra newline
    -- FIXME: ensure 1 space at bottom
    for i = #prompt, 1, -1 do
      table.insert(contents, prompt[i])
    end
    local title = filename:match'([^/]+)$'
    local tmp = vim.fn.stdpath'data' .. '/' .. title .. '.tmp.md'
    local out = io.open(tmp, 'w')
    if not out then
      return
    end
    for _, line in ipairs(contents) do
      out:write(line .. '\n')
    end
    out:close()
    os.remove(filename)
    os.rename(tmp, filename)
    vim.api.nvim_command'stopinsert'
    vim.api.nvim_win_close(prompt_window, true)
    vim.api.nvim_buf_delete(prompt_buffer, { force = true })
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buffer) == vim.fn.fnamemodify(filename, ':p') then
        vim.api.nvim_buf_call(buffer, function () vim.cmd'checktime' end)
        break
      end
    end
    vim.defer_fn(function () print('Saved note to ' .. filename:match'([^/]+)$') end, 0)
    vim.defer_fn(function () vim.cmd'echo ""' end, 1500)
    last_row = 0
    prompt_window = 0
    metadata = {}
    if filename ~= '/home/user/notes/inbox.md' then
      last_note_file = filename
    end
  end

  -- inbox
  if not destination or destination.type == 'inbox' then
    save()
    return
  end

  -- last
  if destination.type == 'last' then
    if #last_note_file > 0 and vim.loop.fs_stat(last_note_file) then
      filename = last_note_file
    else
      filename = '/home/user/notes/inbox.md'
    end
    save()
    return
  end

  -- fuzzy
  if destination.type == 'fuzzy' then
    local actions = require'telescope.actions'
    local action_state = require'telescope.actions.state'
    is_opening_telescope = true
    require'telescope.builtin'.find_files{
      cwd = '~/notes',
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

  -- history
  if destination.type == 'history' then
    return
  end

  -- bookmark
  if destination.type == 'bookmark' then
    return
  end

  -- subheading
  if destination.type == 'subheading' then
  end
end

--- Opens edit metadata window, returns window number and buffer number.
---
---@private
function main.ui.create_metadata_window ()
  if vim.b.note_type ~= 'topic' then
    return
  end
  is_opening_meta = true
  local config = vim.api.nvim_win_get_config(prompt_window)
  local width = config.width
  local col = (config.col or 0)
  local row = (config.row or 0) + (config.height or 0) + 2
  local buffer = vim.api.nvim_create_buf(false, true)
  meta_window = vim.api.nvim_open_win(buffer, false, {
    title = 'Metadata',
    relative = 'editor',
    width = width,
    height = #metadata or 1,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded',
  })
  vim.api.nvim_set_current_win(meta_window)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, metadata)
  vim.wo.winhl = 'FloatBorder:@lsp.type.property'
  vim.bo.filetype = 'yaml'
  vim.bo.buftype = 'nofile'
  vim.bo.buflisted = false
  vim.opt.wrap = false
  vim.opt.linebreak = false
  local function save ()
    metadata = {}
    for _, line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)) do
      table.insert(metadata, line)
    end
    vim.api.nvim_win_close(meta_window, true)
  end
  vim.api.nvim_create_autocmd({ 'BufLeave' }, {
    buffer = buffer,
    callback = function ()
      last_row = vim.fn.line'.'
      vim.api.nvim_win_close(meta_window, true)
    end
  })
  if last_row == 0 then
    last_row = vim.o.lines
  end
  vim.cmd('norm! ' .. last_row .. 'G')
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

--- Opens add text window, returns window number and buffer number.
---
---@private
function main.ui.create_prompt_window ()
  local width = math.min(vim.o.columns - 10, 60)
  local row = math.floor((vim.o.lines - 1) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  prompt_buffer = vim.api.nvim_create_buf(false, true)
  prompt_window = vim.api.nvim_open_win(prompt_buffer, true, {
    relative = 'editor',
    width = width,
    height = 1,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
  })
  local function note_style ()
    vim.api.nvim_win_set_config(prompt_window, { title = 'Note' })
    vim.wo.winhl = 'FloatBorder:@lsp.type.property'
    vim.bo.filetype = 'markdown'
  end
  local function topic_style ()
    vim.api.nvim_win_set_config(prompt_window, { title = 'Topic' })
    vim.wo.winhl = 'FloatBorder:Keyword'
    vim.bo.filetype = 'markdown'
  end
  local function tag_style ()
    vim.api.nvim_win_set_config(prompt_window, { title = 'Tag' })
    vim.wo.winhl = 'FloatBorder:Number'
    vim.bo.filetype = 'markdown'
  end
  note_style()
  vim.b.note_type = 'note'
  vim.bo.buftype = 'nofile'
  vim.bo.buflisted = false
  vim.opt.wrap = false
  vim.opt.linebreak = false
  if vim.fn.mode(1):sub(1, 1) ~= 'i' then
    vim.api.nvim_feedkeys('i', 'n', true)
  end
  vim.api.nvim_create_autocmd({ 'BufLeave' }, {
    buffer = prompt_buffer,
    callback = function ()
      if (#vim.api.nvim_list_wins() > 1) and not is_opening_meta and not is_opening_telescope then
        vim.api.nvim_win_close(0, true)
      end
      is_opening_meta = false
      is_opening_telescope = false
    end
  })
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    buffer = prompt_buffer,
    callback = function ()
      if vim.b.note_type ~= 'todo' then
        vim.b.note_type = 'note'
      end
      local first_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
      local amount = math.max(1, vim.api.nvim_buf_line_count(0))
      local height = math.min(vim.o.lines - 10, amount)
      vim.api.nvim_win_set_config(prompt_window, {
        relative = 'editor',
        height = height,
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - width) / 2),
      })
      vim.cmd'Z'

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
          vim.api.nvim_win_set_config(prompt_window, { title = 'Todo' })
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
          vim.api.nvim_buf_set_lines(prompt_buffer, 0, -1, false, {})
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
            vim.api.nvim_buf_set_lines(prompt_buffer, 0, -1, false, texts)
            vim.api.nvim_win_set_cursor(prompt_window, { 1, 0 })
          end
        end
      end

      -- topic
      if vim.b.note_type ~= 'todo' then
        local is_topic = first_line:match'^#%s$' ~= nil
          or first_line:match'^#%s$' ~= nil
          or first_line:match'^#%s+' ~= nil
        if is_topic then
          vim.b.note_type = 'topic'
          topic_style()
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

      -- note
      if vim.b.note_type == 'note' then
        note_style()
      end
    end,
  })


  -- build metadata
  local date = vim.fn.strftime'%Y-%m-%dT%H:%M:%S%z'
  metadata = {
    'parent: ',
    'description: ',
    'tags: ',
  }

  -- save window buffer and close
  local filename = '/home/user/notes/inbox.md'
  local function save ()
    local title = ''
    if vim.b.note_type == 'topic' then
      local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
      local words = line:match'^#%s+(.+)'
      if words then
        title = words:gsub('[^%w%s]', ''):match'^%s*(.-)%s*$':gsub('%s+', '-'):lower()
        filename = '/home/user/notes/' .. title .. '.md'
      end
    end
    if vim.b.note_type == 'note' then
      main.refile{ type = 'last' }
    elseif vim.b.note_type == 'topic' then
      local contents = {}
      table.insert(contents, '---')
      table.insert(contents, 'id: ' .. string.format('%x', math.random(0, 0xFFFFFFFF)))
      table.insert(contents, 'created: ' .. date)
      table.insert(contents, 'updated: ' .. date)
      for i = #metadata, 1, -1 do
        table.insert(contents, metadata[#metadata - i + 1])
      end
      table.insert(contents, '---')
      table.insert(contents, '')
      local lines = vim.api.nvim_buf_get_lines(prompt_buffer, 0, -1, false)
      for i = #lines, 1, -1 do
        print(lines[#lines - i + 1])
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
      if filename ~= '/home/user/notes/inbox.md' then
        last_note_file = filename
      end
      last_row = 0
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
    local position = vim.api.nvim_win_get_cursor(prompt_window)
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
  vim.keymap.set({ 'n', 'x', 'i' }, '<c-k>', function () main.ui.create_metadata_window() end, { buffer = true, noremap = true })
  vim.keymap.set({ 'n', 'x', 'i' }, '<c-f>', function () main.refile{ type = 'fuzzy' } end, { buffer = true, noremap = true })
  vim.keymap.set({ 'n', 'x', 'i' }, '<c-i>', function () main.refile{ type = 'inbox' } end, { buffer = true, noremap = true })
  vim.keymap.set({ 'n', 'x', 'i' }, '<c-s>', function () save() end, { buffer = true, noremap = true })
  vim.keymap.set('i', '<c-w>', function () exit_todo_wrap('<c-w>', true) end, { buffer = true, noremap = true })
  vim.keymap.set('i', '<bs>', function () exit_todo_wrap('<bs>', true) end, { buffer = true, noremap = true })
  vim.keymap.set({ 'n', 'x' }, 'x', function () exit_todo_wrap'x' end, { buffer = true, noremap = true })
  vim.keymap.set({ 'n', 'x' }, 'X', function () exit_todo_wrap'X' end, { buffer = true, noremap = true })
  vim.keymap.set('i', '<c-c>', function ()
    vim.cmd'silent! bd!'
    last_row = 0
    vim.api.nvim_command'stopinsert'
  end, { buffer = true, noremap = true })
  vim.keymap.set('n', '<esc>', function ()
    if vim.fn.line'$' == 1 and vim.fn.empty(vim.fn.getline(1)) == 1 and vim.b.note_type ~= 'todo' then
      vim.cmd'silent! bd!'
      last_row = 0
    end
  end, { buffer = true, noremap = true })
end

function main.topics.find ()
end

function main.topics.create ()
end

return main

