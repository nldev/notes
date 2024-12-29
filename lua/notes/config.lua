---@alias NotesOptions { debug: boolean }

local config = {}

--- Notes configuration table with its default values.
---
---@type NotesOptions
config.options = {
  debug = false,
}

local defaults = vim.deepcopy(config.options)

--- Defaults Notes options by merging user provided options with the default
--- plugin values.
---
---@param options NotesOptions Notes configuration table.
---
---@private
function config.defaults(options)
  config.options =
    vim.deepcopy(vim.tbl_deep_extend('keep', options or {}, defaults or {}))
  assert(
    type(config.options.debug) == 'boolean',
    '`debug` must be a boolean (`true` or `false`).'
  )
  return config.options
end

--- Define your Notes setup.
---
---@param options NotesOptions Notes configuration table.
---
---@usage `require'notes'.setup()` (add `{}` with your |Notes.options| table)
function config.setup(options)
  config.options = config.defaults(options or {})
  return config.options
end

return config

