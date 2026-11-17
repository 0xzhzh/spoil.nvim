local H = dofile("tests/helpers.lua")
local child = H.new_child()
local T = MiniTest.new_set(H.setup(child))
local eq = MiniTest.expect.equality

local stub_api = [[
  local api = require("spoil.api")
  api.my_playlists = function(_, cb) cb(nil, { items = {}, total = 0 }) end
  api.playlist_items = function(_, cb) cb(nil, { items = {}, total = 0 }) end
]]

T["restores window options when the view closes"] = function()
  local r = child.lua_get(([[(function()
      %s
      vim.wo.cursorline = false
      vim.wo.number = true
      vim.wo.wrap = true
      local original = { cursorline = vim.wo.cursorline, number = vim.wo.number, wrap = vim.wo.wrap }

      local explorer = require("spoil.explorer")
      explorer.open_playlists()
      local opened = { cursorline = vim.wo.cursorline, number = vim.wo.number, wrap = vim.wo.wrap }

      explorer.open_playlist("p1")
      local navigated = { cursorline = vim.wo.cursorline, number = vim.wo.number, wrap = vim.wo.wrap }

      vim.api.nvim_buf_delete(vim.api.nvim_get_current_buf(), { force = true })
      local restored = vim.wait(1000, function()
        return vim.wo.cursorline == original.cursorline
          and vim.wo.number == original.number
          and vim.wo.wrap == original.wrap
      end)

      return {
        original = original,
        opened = opened,
        navigated = navigated,
        restored = restored,
        final = { cursorline = vim.wo.cursorline, number = vim.wo.number, wrap = vim.wo.wrap },
      }
    end)()]]):format(stub_api))

  eq(r.opened, { cursorline = true, number = false, wrap = false })
  eq(r.navigated, { cursorline = true, number = false, wrap = false })
  eq(r.restored, true)
  eq(r.final, r.original)
end

return T
