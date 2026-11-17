local config = require("spoil.config")
local api = require("spoil.api")
local explorer = require("spoil.explorer")
local notify = require("spoil.notify")
local E = require("spoil.error")

local M = {}

--- Known no-op 403 reasons. Unknown reasons are surfaced as a warning because
--- they can also mean restricted playback (e.g. missing Premium/allowlist).
local benign_player_reasons = {
  ALREADY_PLAYING = true,
  ALREADY_PAUSED = true,
  NOT_PAUSED = true,
  NO_NEXT_TRACK = true,
  NO_PREV_TRACK = true,
}

local function is_benign_player_error(err)
  if not err or err.status ~= 403 then return false end
  return benign_player_reasons[err.reason] == true
end

local function is_ambiguous_player_error(err)
  if not err or err.status ~= 403 then return false end
  return err.reason == nil or err.reason == "UNKNOWN"
end

local function notify_ignored_player_error(err)
  notify.warn("Spoil: Spotify ignored the playback command: " .. (err.msg or "HTTP 403"), { icon = "⚠" })
end

function M.is_authorized()
  return require("spoil.state").is_authorized()
end

function M.login()
  require("spoil.auth").auth()
end

--- Backwards-compatible alias for `login()`.
M.auth = M.login

function M.logout()
  require("spoil.state").clear_all()
  notify.info("Credentials and tokens cleared")
end

--- Ensure the user is authenticated before an explorer action.
--- Auto-starts the auth flow when configured, otherwise notifies.
---@return boolean ready
local function require_auth()
  if M.is_authorized() then return true end
  if config.options.auth.auto_auth ~= false then
    M.login()
  else
    E.notify(E.not_authenticated())
  end
  return false
end

function M.open_explorer()
  if not require_auth() then return end
  explorer.open_playlists()
end

function M.open_playlists()
  if not require_auth() then return end
  explorer.open_playlists()
end

function M.open_playlist(id)
  if not require_auth() then return end
  if id == nil then
    local p = explorer.get_selected_playlist()
    if p then id = p.id end
  end
  explorer.open_playlist(id)
end

local status_item = nil
local status_timer = nil

--- Format a now-playing item for the statusline.
---@param item table|nil
---@return string
function M.format_status(item)
  local sl = config.options.statusline
  if not item then return sl.not_playing end

  local components = {
    artist = item.artists and item.artists[1] and item.artists[1].name,
    title = item.name,
    album = item.album and item.album.name,
  }
  local parts = {}
  for _, key in ipairs(sl.fmt) do
    local val = components[key]
    if val then table.insert(parts, val) end
  end
  if #parts == 0 then return sl.not_playing end
  return table.concat(parts, sl.sep)
end

function M.statusline()
  local sl = config.options.statusline
  if not status_timer then
    status_timer = vim.uv.new_timer()
    assert(status_timer, "uv.new_timer() returned nil?")
    status_timer:start(
      0,
      sl.interval,
      vim.schedule_wrap(function()
        api.now_playing({ timeout = sl.timeout }, function(err, data)
          if err then
            if err.status == 401 then
              status_timer:stop()
              status_timer:close()
              status_timer = nil
            end
            status_item = nil
            return
          end
          if not data or not data.item then
            status_item = nil
            return
          end
          status_item = data.item
        end)
      end)
    )
  end

  return M.format_status(status_item)
end

local function now_playing_text(item)
  item = item or {}
  local artist = type(item.artists) == "table" and item.artists[1] and item.artists[1].name
  local show = type(item.show) == "table" and item.show.name
  local context = artist or show
  local title = item.name or item.uri or "Unknown"
  return context and (context .. " | " .. title) or title
end

function M.notify_now_playing()
  api.now_playing(nil, function(err, data)
    if err or not data then
      E.notify(err or E.new("No data received from Spotify"))
      return
    end
    local t = data.item
    if not t then
      notify.info("Nothing playing", { icon = "⏹" })
      return
    end
    notify.info(now_playing_text(t), {
      title = "Now Playing",
      icon = "▶",
    })
  end)
end

function M.next_track()
  api.next_track(nil, function(err)
    if err then
      if is_benign_player_error(err) then return end
      if is_ambiguous_player_error(err) then return notify_ignored_player_error(err) end
      E.notify(err)
      return
    end
    vim.defer_fn(M.notify_now_playing, 500)
  end)
end

function M.previous_track()
  api.previous_track(nil, function(err)
    if err then
      if is_benign_player_error(err) then return end
      if is_ambiguous_player_error(err) then return notify_ignored_player_error(err) end
      E.notify(err)
      return
    end
    vim.defer_fn(M.notify_now_playing, 500)
  end)
end

--- Add a track URI to the end of the playback queue.
---@param uri string
function M.add_to_queue(uri)
  api.add_to_queue({ uri = uri }, function(err)
    if err then return E.notify(err) end
    notify.info("Added to queue", { icon = "➕" })
  end)
end

--- Add the track selected in a spoil view to the end of the playback queue.
function M.queue_selected()
  local track = explorer.get_selected_track()
  if not track then return E.notify(E.no_track_selected()) end
  M.add_to_queue(track.uri)
end

--- Device entries for `vim.ui.select`, annotated with the active device.
local function device_items(devices)
  local items = {}
  for _, d in ipairs(devices) do
    local active = d.is_active and ", active" or ""
    table.insert(items, {
      id = d.id,
      name = d.name,
      label = ("%s  (%s%s)"):format(d.name, d.type or "?", active),
    })
  end
  return items
end

--- Resolve a device to play on. Calls cb(err) or cb(nil, device_id).
--- If a device is already active, device_id is nil (Spotify uses the active one),
--- so playback follows whatever device you last switched to.
--- Otherwise auto-selects the only device, or prompts when there are several.
function M.ensure_device(cb)
  api.get_devices(nil, function(err, data)
    if err then return cb(err) end
    local devices = (data and data.devices) or {}
    for _, d in ipairs(devices) do
      if d.is_active then return cb(nil, nil) end
    end
    if #devices == 0 then
      return cb(E.no_devices())
    end
    if #devices == 1 then
      return cb(nil, devices[1].id)
    end
    vim.ui.select(device_items(devices), {
      prompt = "Select Spotify device",
      format_item = function(i) return i.label end,
    }, function(choice)
      if not choice then return cb(E.no_device_selected()) end
      cb(nil, choice.id)
    end)
  end)
end

--- Prompt for a device and transfer playback to it.
function M.select_device()
  api.get_devices(nil, function(err, data)
    if err then return E.notify(err) end
    local devices = (data and data.devices) or {}
    if #devices == 0 then return E.notify(E.no_devices()) end

    local items = device_items(devices)
    if #items == 1 then return M.transfer_to_device(items[1]) end

    vim.ui.select(items, {
      prompt = "Select Spotify device",
      format_item = function(i) return i.label end,
    }, function(choice)
      if choice then M.transfer_to_device(choice) end
    end)
  end)
end

--- Transfer playback to a device without changing the playing/paused state.
---@param device { id: string, name: string }
function M.transfer_to_device(device)
  api.transfer_playback({ device_id = device.id, play = false }, function(err)
    if err then return E.notify(err) end
    notify.info("Playback transferred to " .. device.name, { icon = "🔀" })
  end)
end

function M.play(opts)
  M.ensure_device(function(derr, device_id)
    if derr then
      E.notify(derr)
      return
    end
    opts = opts or {}
    if device_id and not opts.device_id then opts.device_id = device_id end
    local resume = not (opts.context_uri or opts.uris)
    api.play(opts, function(err)
      if err then
        if resume and is_benign_player_error(err) then
          vim.defer_fn(M.notify_now_playing, 500)
          return
        end
        if resume and is_ambiguous_player_error(err) then return notify_ignored_player_error(err) end
        E.notify(err)
        return
      end
      vim.defer_fn(M.notify_now_playing, 500)
    end)
  end)
end

function M.pause()
  api.pause(nil, function(err)
    if err then
      if is_benign_player_error(err) then
        notify.info("Paused", { icon = "⏸" })
        return
      end
      if is_ambiguous_player_error(err) then return notify_ignored_player_error(err) end
      E.notify(err)
      return
    end
    notify.info("Paused", { icon = "⏸" })
  end)
end

function M.toggle_playback()
  api.get_playback_state(nil, function(err, data)
    if err or not data then
      E.notify(err or E.new("No playback state received"))
      return
    end
    if data.is_playing then
      M.pause()
    else
      M.play()
    end
  end)
end

function M.play_context(context_uri)
  M.play({ context_uri = context_uri })
end

--- Play a single track. The Spotify desktop client drops bare `uris` play
--- requests, so prefer playing the track's album as context with an offset.
---@param track table
function M.play_track(track)
  if not track or not track.uri then return end
  if track.album and track.album.uri then
    M.play({ context_uri = track.album.uri, offset = { uri = track.uri } })
  else
    M.play({ uris = { track.uri } })
  end
end

return M
