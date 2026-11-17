local H = dofile("tests/helpers.lua")
local child = H.new_child()
local T = MiniTest.new_set(H.setup(child))
local eq = MiniTest.expect.equality

T["renders playlists and tracks and queues from the tracks view"] = function()
  local r = child.lua_get([==[(function()
    local api = require("spoil.api")
    local queued
    api.add_to_queue = function(opts, cb)
      queued = opts
      cb(nil, {})
    end
    api.my_playlists = function(_, cb)
      cb(nil, {
        items = { { id = "p1", name = "Mix", uri = "spotify:playlist:p1", tracks = { total = 2 } } },
        total = 1,
      })
    end
    api.playlist_items = function(_, cb)
      cb(nil, {
        items = {
          {
            track = {
              name = "Song",
              uri = "spotify:track:1",
              artists = { { name = "Artist" } },
              album = { name = "Album" },
            },
          },
        },
        total = 1,
      })
    end

    local explorer = require("spoil.explorer")
    explorer.open_playlists()
    local playlists_buf = vim.api.nvim_get_current_buf()
    local playlists = {
      name = vim.api.nvim_buf_get_name(playlists_buf),
      filetype = vim.bo[playlists_buf].filetype,
      lines = vim.api.nvim_buf_get_lines(playlists_buf, 0, -1, false),
      selected = explorer.get_selected_playlist(),
    }

    explorer.open_playlist("p1")
    local tracks_buf = vim.api.nvim_get_current_buf()
    local tracks = {
      name = vim.api.nvim_buf_get_name(tracks_buf),
      filetype = vim.bo[tracks_buf].filetype,
      lines = vim.api.nvim_buf_get_lines(tracks_buf, 0, -1, false),
      selected = explorer.get_selected_track(),
    }

    local keys = {}
    for _, km in ipairs(require("spoil.explorer.tracks").keymaps) do keys[km[1]] = km[2] end
    keys["a"]({}, {})

    return { playlists = playlists, tracks = tracks, has_a = keys["a"] ~= nil, queued = queued }
  end)()]==])

  eq(r.playlists.name, "spoil://playlists")
  eq(r.playlists.filetype, "spoil-playlists")
  eq(r.playlists.lines, { "Mix  (2 tracks)" })
  eq(r.playlists.selected.id, "p1")
  eq(r.playlists.selected.name, "Mix")

  eq(r.tracks.name, "spoil://playlist/p1")
  eq(r.tracks.filetype, "spoil-tracks")
  eq(r.tracks.lines, { "Song  Artist  (Album)" })
  eq(r.tracks.selected.uri, "spotify:track:1")
  eq(r.has_a, true)
  eq(r.queued, { uri = "spotify:track:1" })
end

T["renders playlist counts from items or tracks"] = function()
  local r = child.lua_get([[(function()
    local playlists = require("spoil.explorer.playlists")
    return {
      items = playlists.render({ name = "Items", items = { total = 3 } }),
      tracks = playlists.render({ name = "Tracks", tracks = { total = 4 } }),
      missing = playlists.render({ name = "Missing" }),
    }
  end)()]])

  eq(r.items, "Items  (3 tracks)")
  eq(r.tracks, "Tracks  (4 tracks)")
  eq(r.missing, "Missing  (? tracks)")
end

T["background re-render leaves other windows' cursors alone"] = function()
  local r = child.lua_get([==[(function()
    local api = require("spoil.api")
    local pending
    api.my_playlists = function(_, cb) pending = cb end

    local explorer = require("spoil.explorer")
    explorer.open_playlists()

    -- User switches to another split while the fetch is in flight
    vim.cmd("vsplit")
    local file_buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(file_buf, 0, -1, false, { "a", "b", "c", "d", "e" })
    vim.api.nvim_set_current_buf(file_buf)
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    local file_win = vim.api.nvim_get_current_win()

    -- Background fetch resolves while the file buffer is current
    pending(nil, {
      items = {
        { id = "p1", name = "One", uri = "spotify:playlist:p1", tracks = { total = 1 } },
        { id = "p2", name = "Two", uri = "spotify:playlist:p2", tracks = { total = 2 } },
      },
      total = 2,
    })

    local playlists_buf = vim.fn.bufnr("spoil://playlists")
    local spoil_wins = vim.fn.win_findbuf(playlists_buf)
    return {
      file_line = vim.api.nvim_win_get_cursor(file_win)[1],
      spoil_line = spoil_wins[1] and vim.api.nvim_win_get_cursor(spoil_wins[1])[1] or -1,
      spoil_lines = vim.api.nvim_buf_line_count(playlists_buf),
    }
  end)()]==])

  eq(r.file_line, 4)
  eq(r.spoil_line, 1)
  eq(r.spoil_lines, 2)
end

T["cleans up per-buffer autocmd groups"] = function()
  local r = child.lua_get([[(function()
    local api = require("spoil.api")
    api.my_playlists = function(_, cb) cb(nil, { items = {}, total = 0 }) end

    local explorer = require("spoil.explorer")
    explorer.open_playlists()
    local buf = vim.api.nvim_get_current_buf()
    local group = "spoil_explorer_" .. buf
    local before = #vim.api.nvim_get_autocmds({ group = group })

    vim.api.nvim_buf_delete(buf, { force = true })
    local deleted = vim.wait(1000, function()
      return not pcall(vim.api.nvim_get_autocmds, { group = group })
    end)

    return { before = before, deleted = deleted }
  end)()]])

  eq(r.before > 0, true)
  eq(r.deleted, true)
end

return T
