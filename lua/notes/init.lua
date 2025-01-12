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

--- Opens add text window.
---
---@public
function _G.Notes.add ()
  main.add()
end

--- 
---
---@public
function _G.Notes.refile (destination)
  main.refile(destination)
end

--- 
---
---@public
function _G.Notes.inbox ()
  main.inbox()
end

--- 
---
---@public
function _G.Notes.toggle ()
  main.toggle()
end

return _G.Notes

