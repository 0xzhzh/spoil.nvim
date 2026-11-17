local api = require("spoil.api")

return {
  name = "playlists",
  filetype = "spoil-playlists",
  fetch = function(_ctx, cb)
    return api.my_playlists(nil, cb)
  end,
  render = function(item)
    local items = type(item.items) == "table" and item.items.total or nil
    local tracks = type(item.tracks) == "table" and item.tracks.total or nil
    return item.name .. "  (" .. (items or tracks or "?") .. " tracks)"
  end,
  keymaps = {
    {
      "<CR>",
      function(view, ctx)
        local item = ctx.selected_item()
        if not item then return end
        ctx.push_view("tracks", { playlist_id = item.id })
      end,
    },
    {
      "o",
      function(view, ctx)
        local item = ctx.selected_item()
        if not item then return end
        require("spoil").play_context(item.uri)
      end,
    },
    {
      "r",
      function(view, ctx)
        ctx.refresh()
      end,
    },
    {
      "q",
      function(view, ctx)
        ctx.close()
      end,
    },
  },
}
