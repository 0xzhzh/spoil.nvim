local H = dofile("tests/helpers.lua")
local child = H.new_child()
local T = MiniTest.new_set(H.setup(child))
local eq = MiniTest.expect.equality

T["aligns columns and records highlight ranges"] = function()
  local r = child.lua_get([[(function()
    local lines, highlights = require("spoil.format").table({
      {
        { text = "Name", hl = "SpoilPlaylistName" },
        { text = "42", hl = "SpoilPlaylistCount", align = "right" },
      },
      {
        { text = "Long", hl = "SpoilPlaylistName" },
        { text = "7", hl = "SpoilPlaylistCount", align = "right" },
      },
    })
    return { lines = lines, highlights = highlights }
  end)()]])

  eq(r.lines, { "Name  42", "Long   7" })
  eq(r.highlights, {
    { line = 0, start_col = 0, end_col = 4, hl = "SpoilPlaylistName" },
    { line = 0, start_col = 6, end_col = 8, hl = "SpoilPlaylistCount" },
    { line = 1, start_col = 0, end_col = 4, hl = "SpoilPlaylistName" },
    { line = 1, start_col = 7, end_col = 8, hl = "SpoilPlaylistCount" },
  })
end

T["truncates by display width and uses byte offsets"] = function()
  local r = child.lua_get([[(function()
    local lines, highlights = require("spoil.format").table({
      {
        { text = "abcdefgh", hl = "SpoilTrackTitle" },
        { text = "界", hl = "SpoilTrackAlbum" },
      },
    }, { max_width = { 5, 5 } })
    return { lines = lines, highlights = highlights }
  end)()]])

  eq(r.lines, { "abcd…  界" })
  eq(r.highlights, {
    { line = 0, start_col = 0, end_col = 7, hl = "SpoilTrackTitle" },
    { line = 0, start_col = 9, end_col = 12, hl = "SpoilTrackAlbum" },
  })
end

T["defines overridable highlight groups"] = function()
  local r = child.lua_get([[(function()
    local format = require("spoil.format")
    local names = {
      "SpoilPlaylistName",
      "SpoilPlaylistCount",
      "SpoilPlaylistVisibility",
      "SpoilPlaylistOwner",
      "SpoilPlaylistCollaborators",
      "SpoilTrackTitle",
      "SpoilTrackArtist",
      "SpoilTrackAlbum",
      "SpoilTrackDuration",
      "SpoilMuted",
    }

    local missing = {}
    for _, name in ipairs(names) do
      if not next(vim.api.nvim_get_hl(0, { name = name })) then missing[#missing + 1] = name end
    end

    vim.api.nvim_set_hl(0, "SpoilTrackTitle", { fg = 0x123456 })
    format.define_highlights()
    return { missing = missing, fg = vim.api.nvim_get_hl(0, { name = "SpoilTrackTitle" }).fg }
  end)()]])

  eq(r.missing, {})
  eq(r.fg, 0x123456)
end

return T
