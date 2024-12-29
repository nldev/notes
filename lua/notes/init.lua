local config = require'notes.config'
local main = require'notes.main'

_G.Notes = {}

--- Setup Notes options and merge them with user provided ones.
---
---@param options NotesOptions Notes configuration table.
---@public
function _G.Notes.setup (options)
  _G.Notes.config = config.setup(options)
end

--- Toggles enabled state.
---
---@public
function _G.Notes.toggle ()
  main.toggle'public_api_toggle'
end

--- Sets state to enabled.
---
---@public
function _G.Notes.enable ()
  main.enable'public_api_enable'
end

--- Sets state to disabled.
---
---@public
function _G.Notes.disable ()
  main.disable'public_api_disable'
end

return _G.Notes

