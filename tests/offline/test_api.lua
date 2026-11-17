local H = dofile("tests/helpers.lua")
local child = H.new_child()
local T = MiniTest.new_set(H.setup(child))
local eq = MiniTest.expect.equality

T["api.play only forwards valid body keys"] = function()
  local r = child.lua_get([[(function()
    local api_helpers = require("spoil.api_helpers")
    local captured
    api_helpers.put = function(url, data, callback)
      captured = { url = url, data = data, callback = callback }
      return "result"
    end

    local api = require("spoil.api")
    local result = api.play({
      device_id = "dev",
      context_uri = "spotify:album:1",
      uris = { "spotify:track:1" },
      offset = { position = 1 },
      position_ms = 0,
      bogus = "drop me",
    }, "cb")
    local first = vim.deepcopy(captured)

    api.play({ device_id = "dev" }, function() end)
    local empty = captured.data

    return {
      url = first.url,
      data = first.data,
      result = result,
      empty = empty,
    }
  end)()]])

  eq(r.url:find("device_id=dev", 1, true) ~= nil, true)
  eq(r.data, {
    context_uri = "spotify:album:1",
    uris = { "spotify:track:1" },
    offset = { position = 1 },
    position_ms = 0,
  })
  eq(r.result, "result")
  eq(r.empty, nil)
end

T["user.play does not mutate caller options"] = function()
  local r = child.lua_get([[(function()
    local user = require("spoil.user_api")
    local api = require("spoil.api")
    local captured

    user.ensure_device = function(cb) cb(nil, "auto-device") end
    user.notify_now_playing = function() end
    api.play = function(opts, cb)
      captured = opts
      cb(nil, {})
    end

    local auto = { context_uri = "ctx", uris = { "u" } }
    user.play(auto)
    local auto_capture = vim.deepcopy(captured)
    local auto_after = vim.deepcopy(auto)

    local explicit = { device_id = "explicit" }
    user.play(explicit)
    local explicit_capture = vim.deepcopy(captured)
    local explicit_after = vim.deepcopy(explicit)

    return {
      auto_capture = auto_capture,
      auto_after = auto_after,
      explicit_capture = explicit_capture,
      explicit_after = explicit_after,
    }
  end)()]])

  eq(r.auto_capture, { context_uri = "ctx", uris = { "u" }, device_id = "auto-device" })
  eq(r.auto_after, { context_uri = "ctx", uris = { "u" } })
  eq(r.explicit_capture, { device_id = "explicit" })
  eq(r.explicit_after, { device_id = "explicit" })
end

return T
