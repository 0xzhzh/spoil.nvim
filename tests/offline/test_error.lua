local H = dofile("tests/helpers.lua")
local child = H.new_child()
local T = MiniTest.new_set(H.setup(child))
local eq = MiniTest.expect.equality

T["constructs messages and levels"] = function()
  local r = child.lua_get([[(function()
    local E = require("spoil.error")
    local a = E.from_api(404, { error = { status = 404, message = "Not found", reason = "NO_SUCH" } })
    local b = E.from_api(400, { error = "bad request" })
    local c = E.from_api(500, E.parse_failed({ status = 500, body = "html" }))
    return {
      auth = E.not_authenticated(),
      rate = E.rate_limited(),
      api = a,
      api_string = b,
      api_fallback = c,
      unknown_command = E.unknown_command("nope"),
      not_implemented = E.not_implemented("search"),
      no_track = E.no_track_selected(),
      warn = E.level(E.not_authenticated()),
      error = E.level({ status = 500 }),
      WARN = vim.log.levels.WARN,
      ERROR = vim.log.levels.ERROR,
    }
  end)()]])

  eq(r.auth.msg, "Not authenticated. Run :Spoil login first")
  eq(r.auth.status, 401)
  eq(r.rate.status, 429)
  eq(r.api.msg, "Not found")
  eq(r.api.reason, "NO_SUCH")
  eq(r.api_string.msg, "bad request")
  eq(r.api_fallback.msg, "API error: HTTP 500")
  eq(r.unknown_command.msg, "Unknown command 'nope'")
  eq(r.not_implemented.msg, "search is not implemented yet")
  eq(r.no_track.msg, "No track selected")
  eq(r.warn, r.WARN)
  eq(r.error, r.ERROR)
end

T["notifies with prefix and level"] = function()
  local r = child.lua_get([[(function()
    local E = require("spoil.error")
    local notify = require("spoil.notify")
    local captured
    notify.backend = function(msg, level, opts)
      captured = { msg = msg, level = level, group = opts.group }
      return "sent"
    end

    local returned = E.notify(E.rate_limited())
    local warn = captured
    E.notify("boom")
    local error = captured
    E.notify(nil)

    return {
      warn = warn,
      error = error,
      returned = returned,
      WARN = vim.log.levels.WARN,
      ERROR = vim.log.levels.ERROR,
    }
  end)()]])

  eq(r.warn.msg, "Spoil: Rate limited by Spotify; try again shortly")
  eq(r.warn.level, r.WARN)
  eq(r.warn.group, "spoil.nvim")
  eq(r.error.msg, "Spoil: boom")
  eq(r.error.level, r.ERROR)
  eq(r.returned, nil)
end

return T
