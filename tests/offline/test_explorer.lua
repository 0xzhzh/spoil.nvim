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
        items = { { id = "p1", name = "Mix", uri = "spotify:playlist:p1", items = { total = 2 } } },
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

return T
