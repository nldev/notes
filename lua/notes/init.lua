local config = require'notes.config'
local main = require'notes.main'

_G.Notes = {}

--- Setup Notes options and merge them with user provided ones.
---
---@param options NotesOptions? Notes configuration table.
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

--- Refiles text to the given destination.
---
---@public
function _G.Notes.refile (destination)
  main.refile(destination)
end

--- Toggles between table of contents and the last non-note file opened.
---
---@public
function _G.Notes.toc ()
  main.toc()
end

--- Toggles between inbox and the last non-note file opened.
---
---@public
function _G.Notes.inbox ()
  main.inbox()
end

--- Opens picker for opening topic in a new buffer.
---
---@public
function _G.Notes.topics ()
  main.topics()
end

--- Toggles between last topic and the last non-note file opened.
---
---@public
function _G.Notes.toggle ()
  main.toggle()
end

--- Bookmarks current topic to a given index.
---
---@public
function _G.Notes.bookmark (index)
  main.bookmark(index)
end

--- Delete bookmark at a given index.
---
---@public
function _G.Notes.delete_bookmark (index)
  main.delete_bookmark(index)
end

--- Opens bookmark in a new buffer.
---
---@public
function _G.Notes.goto_bookmark (index)
  main.goto_bookmark(index)
end

--- Displays current bookmarks.
---
---@public
function _G.Notes.bookmarks ()
  main.bookmarks()
end

--- Undo last refile and move prompt contents into clipboard.
---
---@public
function _G.Notes.undo ()
  main.undo()
end

return _G.Notes

