local api = require("spoil.api")

local function track_of(item)
  return item.item or item.track
end

return {
  name = "tracks",
  filetype = "spoil-tracks",
  fetch = function(ctx, cb)
    return api.playlist_items({ playlist_id = ctx.playlist_id }, cb)
  end,
  render = function(item)
    local track = track_of(item)
    if not track then return "(unavailable)" end
    local artists = track.artists and #track.artists > 0 and track.artists[1].name or "?"
    return track.name .. "  " .. artists .. "  (" .. (track.album and track.album.name or "?") .. ")"
  end,
  keymaps = {
    { "o", function(view, ctx)
      local track = track_of(ctx.selected_item() or {})
      if not track then return end
      if track.album and track.album.uri then
        require("spoil").play_context(track.album.uri)
      elseif track.uri then
        require("spoil").play_track(track)
      end
    end },
    { "<CR>", function(view, ctx)
      local track = track_of(ctx.selected_item() or {})
      if not track or not track.uri then return end
      require("spoil").play_track(track)
    end },
    { "<BS>", function(view, ctx)
      require("spoil.explorer").open_playlists()
    end },
    { "a", function(view, ctx)
      require("spoil").queue_selected()
    end },
    { "r", function(view, ctx)
      ctx.refresh()
    end },
    { "q", function(view, ctx)
      ctx.close()
    end },
  },
}
