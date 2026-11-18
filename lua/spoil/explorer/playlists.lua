local api = require("spoil.api")
local format = require("spoil.format")

local function track_count(item)
  local items = type(item.items) == "table" and item.items.total or nil
  local tracks = type(item.tracks) == "table" and item.tracks.total or nil
  return items or tracks or "?"
end

local function visibility(item)
  if item.public == true then return "public" end
  if item.public == false then return "private" end
  return "?"
end

local function owner(item)
  return item.owner and item.owner.display_name or "?"
end

local function has_owner_ids(items)
  for _, item in ipairs(items) do
    if item.owner and item.owner.id then return true end
  end
  return false
end

local function readable_playlists(items, user_id)
  local readable = {}
  for _, item in ipairs(items) do
    local owner_id = item.owner and item.owner.id
    if not owner_id or owner_id == user_id or item.collaborative then
      readable[#readable + 1] = item
    end
  end
  return readable
end

return {
  name = "playlists",
  filetype = "spoil-playlists",
  fetch = function(_ctx, cb)
    api.my_playlists(nil, function(err, data)
      if err then return cb(err) end
      local items = data and data.items or {}
      if not has_owner_ids(items) then return cb(nil, data) end

      api.current_user(nil, function(user_err, me)
        if user_err then return cb(user_err) end
        if not me or not me.id then return cb(nil, data) end

        local readable = readable_playlists(items, me.id)
        cb(nil, { items = readable, total = #readable })
      end)
    end)
  end,
  format = function(items)
    local rows = {}
    for _, item in ipairs(items) do
      local row = {
        { text = item.name or "?", hl = "SpoilPlaylistName" },
        { text = track_count(item), hl = "SpoilPlaylistCount", align = "right" },
        { text = visibility(item), hl = "SpoilPlaylistVisibility" },
        { text = owner(item), hl = "SpoilPlaylistOwner" },
      }
      if item.collaborative then
        row[5] = { text = "shared", hl = "SpoilPlaylistCollaborators" }
      end
      rows[#rows + 1] = row
    end

    local lines, highlights = format.table(rows, { max_width = { 40, 8, 8, 24, 8 } })
    return { lines = lines, highlights = highlights }
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
