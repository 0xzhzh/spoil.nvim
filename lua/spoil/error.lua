--- Centralized error construction, user-facing messages, and notification levels.
---
--- Errors are plain tables: `{ msg, status?, reason?, body? }`. Construct them
--- here so wording stays consistent, and route user-facing failures through
--- `M.notify()` so severity is chosen in one place.
local notify = require("spoil.notify")
local levels = vim.log.levels

local M = {}

--- Canonical messages. Prefer the constructors below over hand-written text.
M.messages = {
  unknown = "Unknown error",
  not_authenticated = "Not authenticated. Run :Spoil login first",
  rate_limited = "Rate limited by Spotify; try again shortly",
  parse_failed = "Failed to parse the Spotify response",
  token_refresh_failed = "Failed to refresh the Spotify access token",
  api_error = "API error: HTTP %s",
  no_devices = "No devices available. Open Spotify on a device first.",
  no_device_selected = "No device selected",
  no_playlist_selected = "No playlist selected",
  no_track_selected = "No track selected",
  not_implemented = "%s is not implemented yet",
  unknown_view = "Unknown view: %s",
  unknown_command = "Unknown command '%s'",
  token_exchange_failed = "Token exchange failed (HTTP %s)",
}

---@class spoil.Error
---@field msg string
---@field status? integer HTTP status (0 for local failures)
---@field reason? string Spotify error reason, when provided
---@field body? string Raw response body, when relevant

---@param msg string
---@param fields? table
---@return spoil.Error
function M.new(msg, fields)
  local err = fields or {}
  err.msg = msg
  return err
end

---@return spoil.Error
function M.not_authenticated()
  return M.new(M.messages.not_authenticated, { status = 401 })
end

---@return spoil.Error
function M.rate_limited()
  return M.new(M.messages.rate_limited, { status = 429 })
end

---@param resp { status: integer, body?: string }
---@return spoil.Error
function M.parse_failed(resp)
  return M.new(M.messages.parse_failed, { status = resp.status, body = resp.body })
end

---@return spoil.Error
function M.token_refresh_failed()
  return M.new(M.messages.token_refresh_failed, { status = 0 })
end

--- Build an error from a Spotify API error response body.
---@param status integer
---@param parsed table Decoded response body (or a `parse_failed` error).
---@return spoil.Error
function M.from_api(status, parsed)
  local msg, reason
  if type(parsed) == "table" and not parsed.msg then
    local err = parsed.error
    if type(err) == "table" then
      msg = err.message
      reason = err.reason
    elseif type(err) == "string" then
      msg = err
    end
  end
  return M.new(msg or string.format(M.messages.api_error, tostring(status)), {
    status = status,
    reason = reason,
  })
end

---@param status integer
---@param description? string
---@return spoil.Error
function M.token_exchange_failed(status, description)
  local msg = string.format(M.messages.token_exchange_failed, tostring(status))
  if description then msg = msg .. ": " .. description end
  return M.new(msg, { status = status })
end

---@return spoil.Error
function M.no_devices()
  return M.new(M.messages.no_devices)
end

---@return spoil.Error
function M.no_device_selected()
  return M.new(M.messages.no_device_selected)
end

---@return spoil.Error
function M.no_playlist_selected()
  return M.new(M.messages.no_playlist_selected)
end

---@return spoil.Error
function M.no_track_selected()
  return M.new(M.messages.no_track_selected)
end

---@param feature string
---@return spoil.Error
function M.not_implemented(feature)
  return M.new(string.format(M.messages.not_implemented, feature))
end

---@param name string
---@return spoil.Error
function M.unknown_view(name)
  return M.new(string.format(M.messages.unknown_view, name))
end

---@param name string
---@return spoil.Error
function M.unknown_command(name)
  return M.new(string.format(M.messages.unknown_command, name))
end

--- Notification severity for an error: expected/recoverable conditions are
--- warnings; everything else is an error.
---@param err spoil.Error|string|nil
---@return integer
function M.level(err)
  local status = type(err) == "table" and err.status or nil
  if status == 401 or status == 429 then
    return levels.WARN
  end
  return levels.ERROR
end

--- Notify the user about an error, with a consistent prefix and the level
--- chosen by `M.level()`.
---@param err spoil.Error|string|nil
---@param opts? table
function M.notify(err, opts)
  if err == nil then return end
  local msg = type(err) == "table" and err.msg or tostring(err)
  if not msg or msg == "" then msg = M.messages.unknown end
  return notify.notify("Spoil: " .. msg, M.level(err), opts)
end

return M
