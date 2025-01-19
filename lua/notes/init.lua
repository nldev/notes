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
function _G.Notes.toc ()
  main.toc()
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

--- 
---
---@public
function _G.Notes.bookmark (index)
  main.bookmark(index)
end

--- 
---
---@public
function _G.Notes.delete_bookmark (index)
  main.delete_bookmark(index)
end

--- 
---
---@public
function _G.Notes.goto_bookmark (index)
  main.goto_bookmark(index)
end

--- 
---
---@public
function _G.Notes.bookmarks ()
  main.bookmarks()
end

--- 
---
---@public
function _G.Notes.undo ()
  main.undo()
end

return _G.Notes

