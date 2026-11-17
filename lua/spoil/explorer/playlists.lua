local api = require("spoil.api")

return {
  name = "playlists",
  filetype = "spoil-playlists",
  fetch = function(_ctx, cb)
    return api.my_playlists(nil, cb)
  end,
  render = function(item)
    local count = "?"
    if type(item.items) == "table" and item.items.total then
      count = item.items.total
    elseif type(item.tracks) == "table" and item.tracks.total then
      count = item.tracks.total
    end
    return item.name .. "  (" .. count .. " tracks)"
  end,
  keymaps = {
    { "<CR>", function(view, ctx)
      local item = ctx.selected_item()
      if not item then return end
      require("spoil.explorer").open_playlist(item.id)
    end },
    { "o", function(view, ctx)
      local item = ctx.selected_item()
      if not item then return end
      require("spoil").play_context(item.uri)
    end },
    { "r", function(view, ctx)
      ctx.refresh()
    end },
    { "q", function(view, ctx)
      ctx.close()
    end },
  },
}
