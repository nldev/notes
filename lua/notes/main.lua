local state = require'notes.state'
local log = require'notes.util.log'

local main = {}

--- Toggles enabled state.
---
---@param scope string The scope from where this function is called.
---@private
function main.toggle (scope)
  if state.get_enabled(state) then
    log.debug(scope, 'notes is now disabled!')
    return main.disable(scope)
  end
  log.debug(scope, 'notes is now enabled!')
  main.enable(scope)
end


--- Sets state to enabled.
---
---@param scope string The scope from where this function is called.
---@private
function main.enable (scope)
  if state.get_enabled(state) then
    log.debug(scope, 'notes is already enabled')
    return
  end
  state.set_enabled(state)
  state.save(state)
end

--- Sets state to disabled.
---
---@param scope string The scope from where this function is called.
---@private
function main.disable (scope)
  if not state.get_enabled(state) then
    log.debug(scope, 'notes is already disabled')
    return
  end
  state.set_disabled(state)
  state.save(state)
end

return main

