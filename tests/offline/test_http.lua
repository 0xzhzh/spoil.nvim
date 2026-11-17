local H = dofile("tests/helpers.lua")
local child = H.new_child()
local T = MiniTest.new_set(H.setup(child))
local eq = MiniTest.expect.equality

T["uses the injected transport"] = function()
  local r = child.lua_get([[(function()
    local http = require("spoil.http")
    local seen
    http.set_transport(function(method, url, opts)
      seen = { method = method, url = url, header = opts.headers and opts.headers.X }
      return { status = 201, body = "hi" }
    end)
    local sync = http.get("https://example.test/x", { headers = { X = "y" } })

    local seen_async, async
    http.set_transport(function(method, url, opts)
      seen_async = { method = method, url = url }
      opts.callback({ status = 204, body = "" })
    end)
    http.post("https://example.test/y", { callback = function(resp) async = resp end })

    return { sync = sync, seen = seen, async = async, seen_async = seen_async }
  end)()]])

  eq(r.sync, { status = 201, body = "hi" })
  eq(r.seen, { method = "GET", url = "https://example.test/x", header = "y" })
  eq(r.async, { status = 204, body = "" })
  eq(r.seen_async, { method = "POST", url = "https://example.test/y" })
end

T["refreshes tokens on 401"] = function()
  local r = child.lua_get([[(function()
    local config = require("spoil.config")
    local state = require("spoil.state")
    local http = require("spoil.http")
    config.options.auth.client_id = "cid"

    state.load_tokens = function() return { access_token = "old", refresh_token = "refresh" } end
    local saved, cleared
    state.save_tokens = function(tokens) saved = tokens end
    state.clear_tokens = function() cleared = true end

    local calls = {}
    http.set_transport(function(method, url, opts)
      table.insert(calls, { method = method, url = url, auth = opts.headers and opts.headers.Authorization })
      if url:find("/api/token", 1, true) then
        return { status = 200, body = vim.fn.json_encode({ access_token = "new", refresh_token = "refresh2" }) }
      end
      if #calls == 1 then return { status = 401, body = "" } end
      return { status = 200, body = '{"ok":true}' }
    end)

    local data = require("spoil.api_helpers").get("https://api.spotify.com/v1/me")
    return { data = data, calls = calls, saved = saved, cleared = cleared }
  end)()]])

  eq(r.data, { ok = true })
  eq(#r.calls, 3)
  eq(r.calls[1].auth, "Bearer old")
  eq(r.calls[2].url:find("/api/token", 1, true) ~= nil, true)
  eq(r.calls[3].auth, "Bearer new")
  eq(r.saved.access_token, "new")
  eq(r.saved.refresh_token, "refresh2")
  eq(r.cleared, nil)
end

T["paginates and handles empty responses"] = function()
  local r = child.lua_get([[(function()
    local state = require("spoil.state")
    local http = require("spoil.http")
    state.load_tokens = function() return { access_token = "t" } end

    http.set_transport(function(_, url)
      if url:find("page=1", 1, true) then
        return {
          status = 200,
          body = vim.fn.json_encode({
            items = { { id = 1 } },
            next = "https://api.spotify.com/next?page=2",
            total = 2,
          }),
        }
      end
      return { status = 200, body = vim.fn.json_encode({ items = { { id = 2 } }, total = 2 }) }
    end)

    local data = require("spoil.api_helpers").paginate("https://api.spotify.com/start?page=1")

    http.set_transport(function() return { status = 204, body = "" } end)
    local empty = require("spoil.api_helpers").get("https://api.spotify.com/empty")

    return { data = data, empty = empty }
  end)()]])

  eq(r.data, { items = { { id = 1 }, { id = 2 } }, total = 2 })
  eq(r.empty, {})
end

T["returns centralized errors"] = function()
  local r = child.lua_get([[(function()
    local state = require("spoil.state")
    local http = require("spoil.http")
    state.load_tokens = function() return { access_token = "t" } end
    local H = require("spoil.api_helpers")

    http.set_transport(function() return { status = 429, body = "" } end)
    local rate = H.get("https://api.spotify.com/rate")

    http.set_transport(function() return { status = 200, body = "not json" } end)
    local parse = H.get("https://api.spotify.com/parse")

    http.set_transport(function() return { status = 500, body = '{"error":{"message":"boom","reason":"X"}}' } end)
    local api = H.get("https://api.spotify.com/error")

    return { rate = rate, parse = parse, api = api }
  end)()]])

  eq(r.rate.msg, "Rate limited by Spotify; try again shortly")
  eq(r.rate.status, 429)
  eq(r.parse.msg, "Failed to parse the Spotify response")
  eq(r.parse.status, 200)
  eq(r.api.msg, "boom")
  eq(r.api.status, 500)
  eq(r.api.reason, "X")
end

T["reports async auth errors"] = function()
  local r = child.lua_get([[(function()
    local state = require("spoil.state")
    state.load_tokens = function() return nil end
    local cb_err
    require("spoil.api_helpers").get("https://api.spotify.com/v1/me", function(err) cb_err = err end)
    vim.wait(1000, function() return cb_err ~= nil end)
    return cb_err
  end)()]])

  eq(r.msg, "Not authenticated. Run :Spoil login first")
  eq(r.status, 401)
end

return T
