local H = dofile("tests/helpers.lua")
local child = H.new_child()
local T = MiniTest.new_set(H.setup(child))
local eq = MiniTest.expect.equality

T["reuses an existing buffer for the same URI"] = function()
  local r = child.lua_get([[(function()
    local api = require("spoil.api")
    api.my_playlists = function(_, cb)
      cb(nil, {
        items = {
          {
            id = "p1",
            name = "Mix",
            uri = "spotify:playlist:p1",
            public = false,
            owner = { display_name = "alice" },
            tracks = { total = 1 },
          },
        },
        total = 1,
      })
    end
    api.playlist_items = function(_, cb) cb(nil, { items = {}, total = 0 }) end

    vim.wo.cursorline = false
    vim.wo.number = true
    local original = { cursorline = vim.wo.cursorline, number = vim.wo.number }

    local explorer = require("spoil.explorer")
    explorer.open_playlists()
    local existing = vim.api.nvim_get_current_buf()
    local win_a = vim.api.nvim_get_current_win()

    -- Put a normal buffer in another window, then open the same URI there.
    vim.cmd("split")
    vim.cmd("enew")
    local win_b = vim.api.nvim_get_current_win()
    vim.wo.cursorline = false
    vim.wo.number = true
    local original_b = { cursorline = vim.wo.cursorline, number = vim.wo.number }

    explorer.open_playlists()
    local reused = {
      current_is_existing = vim.api.nvim_get_current_buf() == existing,
      lines = vim.api.nvim_buf_get_lines(existing, 0, -1, false),
      window_opts = { cursorline = vim.wo.cursorline, number = vim.wo.number },
      count = (function()
        local n = 0
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == "spoil://playlist" then n = n + 1 end
        end
        return n
      end)(),
    }

    -- Leaving the reused view restores window B, while window A keeps it.
    vim.cmd("enew")
    local b_restored = vim.wait(1000, function()
      return vim.wo.cursorline == original_b.cursorline and vim.wo.number == original_b.number
    end)
    local a_while_b_leaves = { cursorline = vim.wo[win_a].cursorline, number = vim.wo[win_a].number }

    return {
      original = original,
      original_b = original_b,
      reused = reused,
      b_restored = b_restored,
      a_while_b_leaves = a_while_b_leaves,
    }
  end)()]])

  eq(r.reused.current_is_existing, true)
  eq(r.reused.count, 1)
  eq(r.reused.lines, { "Mix  1  private  alice" })
  eq(r.reused.window_opts, { cursorline = true, number = false })
  eq(r.b_restored, true)
  eq(r.a_while_b_leaves, { cursorline = true, number = false })
end

T["keeps buffers persistent and deduplicated by URI"] = function()
  local r = child.lua_get([[(function()
    local api = require("spoil.api")
    api.my_playlists = function(_, cb)
      cb(nil, {
        items = {
          {
            id = "p1",
            name = "Mix",
            uri = "spotify:playlist:p1",
            public = false,
            owner = { display_name = "alice" },
            tracks = { total = 1 },
          },
        },
        total = 1,
      })
    end
    api.playlist_items = function(_, cb) cb(nil, { items = {}, total = 0 }) end

    local explorer = require("spoil.explorer")
    explorer.open_playlists()
    local playlists_buf = vim.api.nvim_get_current_buf()
    explorer.open_playlist("p1")
    local tracks_buf = vim.api.nvim_get_current_buf()

    vim.cmd("enew")
    local persisted = {
      playlists = vim.api.nvim_buf_is_valid(playlists_buf),
      tracks = vim.api.nvim_buf_is_valid(tracks_buf),
      hidden = vim.bo[tracks_buf].bufhidden,
    }

    explorer.open_playlists()
    local reused_playlists = vim.api.nvim_get_current_buf() == playlists_buf
    explorer.open_playlist("p1")
    local reused_tracks = vim.api.nvim_get_current_buf() == tracks_buf

    local count = 0
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(buf)
      if name == "spoil://playlist" or name == "spoil://playlist/p1" then count = count + 1 end
    end

    return {
      persisted = persisted,
      reused_playlists = reused_playlists,
      reused_tracks = reused_tracks,
      count = count,
    }
  end)()]])

  eq(r.persisted, { playlists = true, tracks = true, hidden = "hide" })
  eq(r.reused_playlists, true)
  eq(r.reused_tracks, true)
  eq(r.count, 2)
end

T["opens spoil URIs with :edit"] = function()
  local r = child.lua_get([[(function()
    local api = require("spoil.api")
    api.my_playlists = function(_, cb)
      cb(nil, {
        items = {
          {
            id = "p1",
            name = "Mix",
            uri = "spotify:playlist:p1",
            public = false,
            owner = { display_name = "alice" },
            tracks = { total = 1 },
          },
        },
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

    require("spoil.explorer")
    vim.cmd("edit spoil://playlist")
    local playlists_buf = vim.api.nvim_get_current_buf()
    local playlists = {
      name = vim.api.nvim_buf_get_name(playlists_buf),
      filetype = vim.bo[playlists_buf].filetype,
      lines = vim.api.nvim_buf_get_lines(playlists_buf, 0, -1, false),
    }

    vim.cmd("edit spoil://playlist/p1")
    local tracks_buf = vim.api.nvim_get_current_buf()
    local tracks = {
      name = vim.api.nvim_buf_get_name(tracks_buf),
      filetype = vim.bo[tracks_buf].filetype,
      lines = vim.api.nvim_buf_get_lines(tracks_buf, 0, -1, false),
    }

    vim.cmd("edit spoil://playlist")
    local reused = vim.api.nvim_get_current_buf() == playlists_buf
    local count = 0
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(buf)
      if name == "spoil://playlist" or name == "spoil://playlist/p1" then count = count + 1 end
    end

    return { playlists = playlists, tracks = tracks, reused = reused, count = count }
  end)()]])

  eq(r.playlists, { name = "spoil://playlist", filetype = "spoil-playlists", lines = { "Mix  1  private  alice" } })
  eq(r.tracks, { name = "spoil://playlist/p1", filetype = "spoil-tracks", lines = { "Song  Artist  (Album)" } })
  eq(r.reused, true)
  eq(r.count, 2)
end

return T
