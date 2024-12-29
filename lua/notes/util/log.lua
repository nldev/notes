local log = {}
local longest_scope = 15
local title = 'Notes'

--- Prints to messages only if debug is true.
---
---@param scope string The scope from where this function is called.
---@param str string The formatted string.
---@param ... any The arguments of the formatted string.
---@private
function log.debug (scope, str, ...)
  if _G.Notes.config.debug then
    return log.notify(scope, vim.log.levels.DEBUG, str, ...)
  end
end

--- Prints to messages.
---
---@param scope string The scope from where this function is called.
---@param level integer The log level of vim.notify.
---@param str string The formatted string.
---@param ... any The arguments of the formatted string.
---@private
function log.notify (scope, level, str, ...)
  if string.len(scope) > longest_scope then
    longest_scope = string.len(scope)
  end
  for i = longest_scope, string.len(scope), -1 do
    if i < string.len(scope) then
      scope = string.format('%s ', scope)
    else
      scope = string.format('%s', scope)
    end
  end
  vim.notify(
    string.format('[' .. title .. '@%s] %s', scope, string.format(str, ...)),
    level,
    { title = title }
  )
end

return log

