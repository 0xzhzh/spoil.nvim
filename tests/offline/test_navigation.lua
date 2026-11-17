local H = dofile("tests/helpers.lua")
local child = H.new_child()
local T = MiniTest.new_set(H.setup(child))
local eq = MiniTest.expect.equality

local stub_api = [[
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
  api.playlist_items = function(opts, cb)
    cb(nil, {
      items = {
        {
          track = {
            name = "Song " .. opts.playlist_id,
            uri = "spotify:track:" .. opts.playlist_id,
            artists = { { name = "Artist" } },
            album = { name = "Album" },
          },
        },
      },
      total = 1,
    })
  end
]]

local key_callback = [[
  local function key(buf, lhs)
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if map.lhs == lhs then return map.callback end
    end
    error("missing keymap: " .. lhs)
  end
]]

T["playlists push and pop the tracks view"] = function()
  local r = child.lua_get(([[(function()
      %s
      %s
      local explorer = require("spoil.explorer")
      explorer.open_playlists()
      local playlists_buf = vim.api.nvim_get_current_buf()
      local before = { name = vim.api.nvim_buf_get_name(playlists_buf), filetype = vim.bo[playlists_buf].filetype }

      vim.cmd("normal! j")
      vim.wait(20)
      local cursor_before = vim.api.nvim_win_get_cursor(0)[1]

      key(playlists_buf, "<CR>")()
      local tracks_buf = vim.api.nvim_get_current_buf()
      local pushed = {
        same_buf = tracks_buf == playlists_buf,
        name = vim.api.nvim_buf_get_name(tracks_buf),
        filetype = vim.bo[tracks_buf].filetype,
        track = explorer.get_selected_track(),
        lines = vim.api.nvim_buf_get_lines(tracks_buf, 0, -1, false),
      }

      key(tracks_buf, "<BS>")()
      local popped = {
        same_buf = vim.api.nvim_get_current_buf() == playlists_buf,
        name = vim.api.nvim_buf_get_name(0),
        filetype = vim.bo.filetype,
        cursor = vim.api.nvim_win_get_cursor(0)[1],
        playlist = explorer.get_selected_playlist(),
      }

      return { before = before, cursor_before = cursor_before, pushed = pushed, popped = popped }
    end)()]]):format(stub_api, key_callback))

  eq(r.before, { name = "spoil://playlists", filetype = "spoil-playlists" })
  eq(r.cursor_before, 2)
  eq(r.pushed.same_buf, false)
  eq(r.pushed.name, "spoil://playlist/p2")
  eq(r.pushed.filetype, "spoil-tracks")
  eq(r.pushed.track.uri, "spotify:track:p2")
  eq(r.pushed.lines, { "Song p2  Artist  (Album)" })
  eq(r.popped.same_buf, true)
  eq(r.popped.name, "spoil://playlists")
  eq(r.popped.filetype, "spoil-playlists")
  eq(r.popped.cursor, 2)
  eq(r.popped.playlist.id, "p2")
end

T["back from a directly opened playlist falls back to playlists"] = function()
  local r = child.lua_get(([[(function()
      %s
      %s
      local explorer = require("spoil.explorer")
      explorer.open_playlist("p1")
      local buf = vim.api.nvim_get_current_buf()
      key(buf, "<BS>")()
      return { name = vim.api.nvim_buf_get_name(0), filetype = vim.bo.filetype }
    end)()]]):format(stub_api, key_callback))

  eq(r.name, "spoil://playlists")
  eq(r.filetype, "spoil-playlists")
end

return T
