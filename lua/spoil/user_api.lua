local config = require("spoil.config")
local api = require("spoil.api")
local explorer = require("spoil.explorer")
local notify = require("spoil.notify")
local E = require("spoil.error")

local M = {}

--- Spotify returns a 403 "Restriction violated" player error when a command is
--- a no-op (e.g. resume while playing, pause while paused, skip past the end of
--- the context). It often reports these as reason "UNKNOWN" instead of the
--- specific reason (see spotify/web-api#1433), so treat those as benign too.
local benign_player_reasons = {
  ALREADY_PLAYING = true,
  ALREADY_PAUSED = true,
  NOT_PAUSED = true,
  NO_NEXT_TRACK = true,
  NO_PREV_TRACK = true,
}

local function is_benign_player_error(err)
  if not err or err.status ~= 403 then return false end
  return err.reason == nil or err.reason == "UNKNOWN" or benign_player_reasons[err.reason] == true
end

function M.is_authorized()
  return require("spoil.state").is_authorized()
end

function M.auth()
  require("spoil.auth").auth()
end

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
    require("spoil.auth").auth()
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

function M.statusline()
  local sl = config.options.statusline
  if not status_timer then
    status_timer = vim.uv.new_timer()
    assert(status_timer, "uv.new_timer() returned nil?")
    status_timer:start(0, sl.interval, vim.schedule_wrap(function()
      api.now_playing(nil, function(err, data)
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
    end))
  end

  if not status_item then return sl.not_playing end
  local components = {
    artist = status_item.artists and status_item.artists[1] and status_item.artists[1].name,
    title = status_item.name,
    album = status_item.album and status_item.album.name,
  }
  local parts = {}
  for _, key in ipairs(sl.fmt) do
    local val = components[key]
    if val then table.insert(parts, val) end
  end
  if #parts == 0 then return sl.not_playing end
  return table.concat(parts, sl.sep)
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
    notify.info(t.artists[1].name .. " | " .. t.name, {
      title = "Now Playing",
      icon = "▶",
    })
  end)
end

function M.next_track()
  api.next_track(nil, function(err)
    if err then
      if is_benign_player_error(err) then return end
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
      E.notify(err)
      return
    end
    vim.defer_fn(M.notify_now_playing, 500)
  end)
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
    local items = {}
    for _, d in ipairs(devices) do
      table.insert(items, { id = d.id, label = d.name .. "  (" .. (d.type or "?") .. ")" })
    end
    vim.ui.select(items, {
      prompt = "Select Spotify device",
      format_item = function(i) return i.label end,
    }, function(choice)
      if not choice then return cb(E.no_device_selected()) end
      cb(nil, choice.id)
    end)
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
