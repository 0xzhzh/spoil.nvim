local H = dofile("tests/helpers.lua")
local child = H.new_child()
local T = MiniTest.new_set(H.setup(child))
local eq = MiniTest.expect.equality

T["selects from the Spoil window when invoked elsewhere"] = function()
  local r = child.lua_get([[(function()
    local api = require("spoil.api")
    api.my_playlists = function(_, cb)
      cb(nil, {
        items = {
          { id = "p1", name = "One", uri = "spotify:playlist:p1", tracks = { total = 1 } },
          { id = "p2", name = "Two", uri = "spotify:playlist:p2", tracks = { total = 2 } },
        },
        total = 2,
      })
    end
    api.playlist_items = function(_, cb) cb(nil, { items = {}, total = 0 }) end

    local explorer = require("spoil.explorer")
    explorer.open_playlists()
    local spoil_buf = vim.api.nvim_get_current_buf()
    local spoil_win = vim.api.nvim_get_current_win()

    vim.cmd("normal! j")
    vim.wait(20)
    local spoil_line = vim.api.nvim_win_get_cursor(spoil_win)[1]

    vim.cmd("split")
    vim.cmd("enew")
    local file_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    return {
      spoil_buf = spoil_buf,
      file_buf = file_buf,
      spoil_line = spoil_line,
      selected = explorer.get_selected_playlist(),
      item = explorer.get_selected_item(),
      current = vim.api.nvim_get_current_buf(),
    }
  end)()]])

  eq(r.spoil_line, 2)
  eq(r.current, r.file_buf)
  eq(r.selected.id, "p2")
  eq(r.item.id, "p2")
end

T["returns nothing when multiple Spoil views are visible"] = function()
  local r = child.lua_get([[(function()
    local api = require("spoil.api")
    api.my_playlists = function(_, cb)
      cb(nil, {
        items = { { id = "p1", name = "One", uri = "spotify:playlist:p1", tracks = { total = 1 } } },
        total = 1,
      })
    end
    api.playlist_items = function(_, cb) cb(nil, { items = {}, total = 0 }) end

    local explorer = require("spoil.explorer")
    explorer.open_playlists()
    local first = vim.api.nvim_get_current_buf()

    vim.cmd("split")
    vim.cmd("enew")
    explorer.open_playlist("p1")
    local second = vim.api.nvim_get_current_buf()

    vim.cmd("split")
    vim.cmd("enew")

    return {
      distinct = first ~= second,
      selected = explorer.get_selected_playlist(),
    }
  end)()]])

  eq(r.distinct, true)
  eq(r.selected, nil)
end

return T
