local api = require("spoil.api")
local format = require("spoil.format")

local function track_of(item)
  return item.item or item.track
end

local function artists_of(track)
  local names = {}
  for _, artist in ipairs(track.artists or {}) do
    if artist.name then names[#names + 1] = artist.name end
  end
  return #names > 0 and table.concat(names, ", ") or "?"
end

local function duration_of(track)
  if type(track.duration_ms) ~= "number" then return "?" end
  local seconds = math.floor(track.duration_ms / 1000)
  return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

return {
  name = "tracks",
  filetype = "spoil-tracks",
  fetch = function(ctx, cb)
    return api.playlist_items({ playlist_id = ctx.playlist_id }, cb)
  end,
  format = function(items)
    local rows = {}
    for _, item in ipairs(items) do
      local track = track_of(item)
      if track then
        rows[#rows + 1] = {
          { text = track.name or "?", hl = "SpoilTrackTitle" },
          { text = duration_of(track), hl = "SpoilTrackDuration", align = "right" },
          { text = artists_of(track), hl = "SpoilTrackArtist" },
          { text = track.album and track.album.name or "?", hl = "SpoilTrackAlbum" },
        }
      else
        rows[#rows + 1] = { { text = "(unavailable)", hl = "SpoilMuted" } }
      end
    end

    local lines, highlights = format.table(rows, { max_width = { 40, 6, 24, 24 } })
    return { lines = lines, highlights = highlights }
  end,
  keymaps = {
    {
      "o",
      function(view, ctx)
        local track = track_of(ctx.selected_item() or {})
        if not track then return end
        if track.album and track.album.uri then
          require("spoil").play_context(track.album.uri)
        elseif track.uri then
          require("spoil").play_track(track)
        end
      end,
    },
    {
      "<CR>",
      function(view, ctx)
        local track = track_of(ctx.selected_item() or {})
        if not track or not track.uri then return end
        require("spoil").play_track(track)
      end,
    },
    {
      "<BS>",
      function(view, ctx)
        ctx.pop_view()
      end,
    },
    {
      "a",
      function(view, ctx)
        require("spoil").queue_selected()
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
