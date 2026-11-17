local H = dofile("tests/helpers.lua")
local child = H.new_child()
local T = MiniTest.new_set(H.setup(child))
local eq = MiniTest.expect.equality

T["reuses an existing buffer for the same URI"] = function()
  local r = child.lua_get([[(function()
    local api = require("spoil.api")
    api.my_playlists = function(_, cb)
      cb(nil, {
        items = { { id = "p1", name = "Mix", uri = "spotify:playlist:p1", tracks = { total = 1 } } },
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
          if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == "spoil://playlists" then n = n + 1 end
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
  eq(r.reused.lines, { "Mix  (1 tracks)" })
  eq(r.reused.window_opts, { cursorline = true, number = false })
  eq(r.b_restored, true)
  eq(r.a_while_b_leaves, { cursorline = true, number = false })
end

return T
