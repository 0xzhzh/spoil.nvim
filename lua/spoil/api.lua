local H = require("spoil.api_helpers")
local M = {}

---@alias spoil.Callback fun(err: spoil.Error|nil, data: table|nil)

--- Get the currently playing track. Returns 204 if nothing is playing.
---@param _ nil
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.now_playing(_, callback)
  return H.get("https://api.spotify.com/v1/me/player/currently-playing", callback)
end

--- Get the current user's profile.
---@param _ nil
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.current_user(_, callback)
  return H.get("https://api.spotify.com/v1/me", callback)
end

--- List the current user's playlists (paginated).
---@param _ nil
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.my_playlists(_, callback)
  return H.paginate("https://api.spotify.com/v1/me/playlists", callback)
end

--- Get items in a playlist (paginated).
---@param opts { playlist_id: string }
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.playlist_items(opts, callback)
  return H.paginate("https://api.spotify.com/v1/playlists/" .. opts.playlist_id .. "/items", callback)
end

--- Get the current playback state, including track, progress, and device info.
---@param opts? { market?: string } ISO 3166-1 alpha-2 country code
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.get_playback_state(opts, callback)
  return H.get(H.add_query("https://api.spotify.com/v1/me/player", { market = opts and opts.market }), callback)
end

--- List available devices for playback.
---@param _ nil
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.get_devices(_, callback)
  return H.get("https://api.spotify.com/v1/me/player/devices", callback)
end

--- Get recently played tracks (paginated).
---@param opts? { limit?: integer } Max number of items (1-50)
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.get_recently_played(opts, callback)
  return H.paginate(H.add_query("https://api.spotify.com/v1/me/player/recently-played", { limit = opts and opts.limit }),
    callback)
end

--- Get the current user's playback queue.
---@param _ nil
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.get_queue(_, callback)
  return H.get("https://api.spotify.com/v1/me/player/queue", callback)
end

--- Transfer playback to the specified device.
---@param opts? { device_id: string, play?: boolean }
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.transfer_playback(opts, callback)
  opts = opts or {}
  return H.put("https://api.spotify.com/v1/me/player",
    { device_ids = { opts.device_id }, play = opts.play ~= false }, callback)
end

--- Start or resume playback. Pass context_uri, uris, offset, or position_ms in opts.
---@param opts? { device_id?: string, context_uri?: string, uris?: string[], offset?: table, position_ms?: integer }
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.play(opts, callback)
  opts = opts or {}
  local body = {}
  for k, v in pairs(opts) do
    if k ~= "device_id" then body[k] = v end
  end
  return H.put(H.add_query("https://api.spotify.com/v1/me/player/play", { device_id = opts.device_id }),
    next(body) ~= nil and body or nil, callback)
end

--- Pause playback.
---@param opts? { device_id?: string }
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.pause(opts, callback)
  return H.put(H.add_query("https://api.spotify.com/v1/me/player/pause", { device_id = opts and opts.device_id }), nil,
    callback)
end

--- Skip to the next track.
---@param opts? { device_id?: string }
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.next_track(opts, callback)
  return H.post(H.add_query("https://api.spotify.com/v1/me/player/next", { device_id = opts and opts.device_id }), nil,
    callback)
end

--- Skip to the previous track.
---@param opts? { device_id?: string }
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.previous_track(opts, callback)
  return H.post(H.add_query("https://api.spotify.com/v1/me/player/previous", { device_id = opts and opts.device_id }), nil,
    callback)
end

--- Seek to a position in the current track.
---@param opts { position_ms: integer, device_id?: string }
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.seek(opts, callback)
  opts = opts or {}
  return H.put(H.add_query("https://api.spotify.com/v1/me/player/seek",
    { position_ms = opts.position_ms, device_id = opts.device_id }), nil, callback)
end

--- Set the playback volume.
---@param opts { volume_percent: integer, device_id?: string }
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.set_volume(opts, callback)
  opts = opts or {}
  return H.put(H.add_query("https://api.spotify.com/v1/me/player/volume",
    { volume_percent = opts.volume_percent, device_id = opts.device_id }), nil, callback)
end

--- Toggle shuffle mode.
---@param opts { state: boolean, device_id?: string }
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.toggle_shuffle(opts, callback)
  opts = opts or {}
  return H.put(H.add_query("https://api.spotify.com/v1/me/player/shuffle",
    { state = opts.state, device_id = opts.device_id }), nil, callback)
end

--- Set the repeat mode.
---@param opts { state: ("track"|"context"|"off"), device_id?: string }
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.set_repeat(opts, callback)
  opts = opts or {}
  return H.put(H.add_query("https://api.spotify.com/v1/me/player/repeat",
    { state = opts.state, device_id = opts.device_id }), nil, callback)
end

--- Add a track to the playback queue.
---@param opts { uri: string, device_id?: string }
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.add_to_queue(opts, callback)
  opts = opts or {}
  return H.post(H.add_query("https://api.spotify.com/v1/me/player/queue",
    { uri = opts.uri, device_id = opts.device_id }), nil, callback)
end

--- Create a new playlist for the current user.
---@param opts { name: string, description?: string, public?: boolean }
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.create_playlist(opts, callback)
  opts = opts or {}
  local body = { name = opts.name }
  if opts.description then body.description = opts.description end
  if opts.public ~= nil then body["public"] = opts.public end
  return H.post("https://api.spotify.com/v1/me/playlists", body, callback)
end

--- Update a playlist's name, description, or public status.
---@param opts { playlist_id: string, name?: string, description?: string, public?: boolean }
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.update_playlist_details(opts, callback)
  opts = opts or {}
  local body = {}
  if opts.name then body.name = opts.name end
  if opts.description then body.description = opts.description end
  if opts.public ~= nil then body["public"] = opts.public end
  return H.put("https://api.spotify.com/v1/playlists/" .. opts.playlist_id, body, callback)
end

--- Unfollow (delete) a playlist. Does not need scopes for public playlists.
---@param opts { playlist_id: string }
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.unfollow_playlist(opts, callback)
  return H.del("https://api.spotify.com/v1/playlists/" .. opts.playlist_id .. "/followers", nil, callback)
end

--- Add tracks to a playlist.
---@param opts { playlist_id: string, uris: string[], position?: integer }
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.add_to_playlist(opts, callback)
  opts = opts or {}
  return H.post("https://api.spotify.com/v1/playlists/" .. opts.playlist_id .. "/items",
    { uris = opts.uris, position = opts.position }, callback)
end

--- Remove tracks from a playlist.
---@param opts { playlist_id: string, uris: string[], snapshot_id?: string }
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.remove_from_playlist(opts, callback)
  opts = opts or {}
  local tracks = {}
  for _, uri in ipairs(opts.uris) do
    table.insert(tracks, { uri = uri })
  end
  return H.del("https://api.spotify.com/v1/playlists/" .. opts.playlist_id .. "/items",
    { tracks = tracks, snapshot_id = opts.snapshot_id }, callback)
end

--- Reorder items in a playlist.
---@param opts { playlist_id: string, range_start: integer, insert_before: integer, range_length?: integer, snapshot_id?: string }
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.reorder_playlist_items(opts, callback)
  opts = opts or {}
  local body = { range_start = opts.range_start, insert_before = opts.insert_before }
  if opts.range_length then body.range_length = opts.range_length end
  if opts.snapshot_id then body.snapshot_id = opts.snapshot_id end
  return H.put("https://api.spotify.com/v1/playlists/" .. opts.playlist_id .. "/items", body, callback)
end

--- Replace all tracks in a playlist with the given URIs.
---@param opts { playlist_id: string, uris: string[] }
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.replace_playlist_tracks(opts, callback)
  opts = opts or {}
  return H.put("https://api.spotify.com/v1/playlists/" .. opts.playlist_id .. "/items", { uris = opts.uris }, callback)
end

--- Search for tracks, artists, albums, or playlists.
---@param opts { query: string, type: string, limit?: integer, offset?: integer }
---@param callback? spoil.Callback
---@return table|spoil.Error
function M.search(opts, callback)
  opts = opts or {}
  return H.get(H.add_query("https://api.spotify.com/v1/search", {
    q = opts.query, type = opts.type, limit = opts.limit, offset = opts.offset,
  }), callback)
end

return M
