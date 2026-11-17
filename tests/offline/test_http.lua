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

T["shares query encoding"] = function()
  local r = child.lua_get([[(function()
    local http = require("spoil.http")
    local H = require("spoil.api_helpers")
    return {
      form = http.encode_form({ q = "a b" }),
      query = http.encode_query({ q = "a b", skipped = nil }),
      url = H.add_query("https://example.test", { q = "a b", skipped = nil }),
      empty = H.add_query("https://example.test", { skipped = nil }),
      oauth = require("spoil.oauth").authorize_url({ q = "a b", skipped = nil }),
    }
  end)()]])

  eq(r.form, "q=a%20b")
  eq(r.query, "q=a%20b")
  eq(r.url, "https://example.test?q=a%20b")
  eq(r.empty, "https://example.test")
  eq(r.oauth, "https://accounts.spotify.com/authorize?q=a%20b")
end

T["dispatches write helpers by HTTP method"] = function()
  local r = child.lua_get([=[(function()
    local state = require("spoil.state")
    local http = require("spoil.http")
    state.load_tokens = function() return { access_token = "t" } end
    local H = require("spoil.api_helpers")
    local seen = {}

    local function transport(method)
      return function(_, _, opts)
        table.insert(seen, method)
        local resp = { status = 204, body = "" }
        if opts.callback then opts.callback(resp) end
        return resp
      end
    end

    for _, case in ipairs({ { "post", "POST" }, { "put", "PUT" }, { "del", "DELETE" } }) do
      http.set_transport(transport(case[2]))
      H[case[1]]("https://api.spotify.com/sync")
      local async
      H[case[1]]("https://api.spotify.com/async", {}, function(err, data) async = { err = err, data = data } end)
      vim.wait(1000, function() return async ~= nil end)
    end

    return seen
  end)()]=])

  eq(r, { "POST", "POST", "PUT", "PUT", "DELETE", "DELETE" })
end

T["refreshes tokens on 401"] = function()
  local r = child.lua_get([[(function()
    local config = require("spoil.config")
    local state = require("spoil.state")
    local http = require("spoil.http")
    config.options.auth.client_id = "cid"

    state.load_tokens = function() return { access_token = "old", refresh_token = "refresh" } end
    local saved, cleared
    state.save_tokens = function(tokens) saved = tokens return true end
    state.clear_tokens = function() cleared = true end

    local calls = {}
    http.set_transport(function(method, url, opts)
      table.insert(calls, { method = method, url = url, auth = opts.headers and opts.headers.Authorization })
      if url:find("/api/token", 1, true) then
        return { status = 200, body = vim.json.encode({ access_token = "new", refresh_token = "refresh2" }) }
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
          body = vim.json.encode({
            items = { { id = 1 } },
            next = "https://api.spotify.com/next?page=2",
            total = 2,
          }),
        }
      end
      return { status = 200, body = vim.json.encode({ items = { { id = 2 } }, total = 2 }) }
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

T["reports transport failures"] = function()
  local r = child.lua_get([[(function()
    local config = require("spoil.config")
    local state = require("spoil.state")
    local http = require("spoil.http")
    config.options.auth.client_id = "cid"
    state.load_tokens = function() return { access_token = "t", refresh_token = "r" } end
    local H = require("spoil.api_helpers")

    http.set_transport(function() return { status = 0, body = "", exit_code = 7 } end)
    local sync = H.get("https://api.spotify.com/sync")

    http.set_transport(function(_, _, opts) opts.callback({ status = 0, body = "", exit_code = 28 }) end)
    local async
    H.get("https://api.spotify.com/async", function(err) async = err end)
    vim.wait(1000, function() return async ~= nil end)

    local cleared
    state.clear_tokens = function() cleared = true end
    http.set_transport(function(_, url, opts)
      if url:find("/api/token", 1, true) then
        opts.callback({ status = 0, body = "", exit_code = 28 })
      else
        opts.callback({ status = 401, body = "" })
      end
    end)
    local refresh
    H.get("https://api.spotify.com/refresh", function(err) refresh = err end)
    vim.wait(1000, function() return refresh ~= nil end)

    return { sync = sync, async = async, refresh = refresh, cleared = cleared }
  end)()]])

  eq(r.sync.msg, "curl failed (exit 7)")
  eq(r.sync.status, 0)
  eq(r.async.msg, "curl failed (exit 28)")
  eq(r.refresh.msg, "curl failed (exit 28)")
  eq(r.cleared, nil)
end

T["returns parse errors from async writes"] = function()
  local r = child.lua_get([[(function()
    local state = require("spoil.state")
    local http = require("spoil.http")
    state.load_tokens = function() return { access_token = "t" } end
    local H = require("spoil.api_helpers")
    local results = {}

    for _, method in ipairs({ "post", "put", "del" }) do
      http.set_transport(function(_, _, opts) opts.callback({ status = 200, body = "not json" }) end)
      local result
      H[method]("https://api.spotify.com/write", {}, function(err, data) result = { err = err, data = data } end)
      vim.wait(1000, function() return result ~= nil end)
      results[method] = result
    end

    return results
  end)()]])

  for _, method in ipairs({ "post", "put", "del" }) do
    eq(r[method].err.msg, "Failed to parse the Spotify response")
    eq(r[method].data, nil)
  end
end

T["surfaces token save failures"] = function()
  local r = child.lua_get([[(function()
    local config = require("spoil.config")
    local state = require("spoil.state")
    local http = require("spoil.http")
    config.options.auth.client_id = "cid"
    state.load_tokens = function() return { access_token = "old", refresh_token = "r" } end
    state.save_tokens = function() return nil, "disk full" end
    local H = require("spoil.api_helpers")

    http.set_transport(function(_, url)
      if url:find("/api/token", 1, true) then
        return { status = 200, body = vim.json.encode({ access_token = "new" }) }
      end
      return { status = 401, body = "" }
    end)
    local sync = H.get("https://api.spotify.com/v1/me")

    http.set_transport(function(_, url, opts)
      if url:find("/api/token", 1, true) then
        opts.callback({ status = 200, body = vim.json.encode({ access_token = "new" }) })
      else
        opts.callback({ status = 401, body = "" })
      end
    end)
    local async
    H.get("https://api.spotify.com/v1/me", function(err) async = err end)
    vim.wait(1000, function() return async ~= nil end)

    return { sync = sync, async = async }
  end)()]])

  eq(r.sync.msg, "Failed to save refreshed Spotify tokens: disk full")
  eq(r.async.msg, "Failed to save refreshed Spotify tokens: disk full")
end

T["uses vim.system without temp files"] = function()
  local r = child.lua_get([[(function()
    local real_system = vim.system
    local seen = {}
    vim.system = function(cmd, opts, cb)
      table.insert(seen, { cmd = cmd, opts = opts })
      local result = { code = 0, signal = 0, stdout = "BODY\n__SPOIL_STATUS__201", stderr = "" }
      if cb then
        cb(result)
        return {}
      end
      return { wait = function() return result end }
    end

    local http = require("spoil.http")
    local sync = http.get("https://example.test/x", {
      headers = { X = "Y" },
      body = "data",
      timeout = 4,
      connect_timeout = 2,
    })
    local async
    http.post("https://example.test/y", {
      callback = function(resp) async = resp end,
    })
    vim.wait(100, function() return async ~= nil end)

    local sync_seen, async_seen = seen[1], seen[2]
    vim.system = real_system
    return {
      sync = sync,
      async = async,
      sync_cmd = sync_seen.cmd,
      async_cmd = async_seen.cmd,
      sync_opts = sync_seen.opts,
      async_opts = async_seen.opts,
    }
  end)()]])

  eq(r.sync, { status = 201, body = "BODY", exit_code = 0 })
  eq(r.async, { status = 201, body = "BODY", exit_code = 0 })
  eq(r.sync_opts, { text = true, timeout = 4000 })
  eq(r.async_opts, { text = true, timeout = 10000 })

  for _, cmd in ipairs({ r.sync_cmd, r.async_cmd }) do
    eq(vim.tbl_contains(cmd, "-o"), false)
    eq(vim.tbl_contains(cmd, "--max-time"), false)
    eq(vim.tbl_contains(cmd, "--connect-timeout"), true)
    eq(vim.tbl_contains(cmd, "-w"), true)
    local has_marker = false
    for _, arg in ipairs(cmd) do
      if arg:find("__SPOIL_STATUS__", 1, true) then has_marker = true end
    end
    eq(has_marker, true)
  end

  eq(vim.tbl_contains(r.sync_cmd, "-H"), true)
  eq(vim.tbl_contains(r.sync_cmd, "X: Y"), true)
  eq(vim.tbl_contains(r.sync_cmd, "-d"), true)
  eq(vim.tbl_contains(r.sync_cmd, "data"), true)
  eq(vim.tbl_contains(r.sync_cmd, "2"), true)
end

T["decodes JSON nulls without vim.NIL"] = function()
  local r = child.lua_get([[(function()
    local state = require("spoil.state")
    local http = require("spoil.http")
    state.load_tokens = function() return { access_token = "t" } end

    http.set_transport(function()
      return { status = 200, body = '{"items":[],"next":null,"total":null,"owner":null}' }
    end)
    local data = require("spoil.api_helpers").get("https://api.spotify.com/v1/me")
    return { has_next = rawget(data, "next") ~= nil, has_total = rawget(data, "total") ~= nil }
  end)()]])

  eq(r.has_next, false)
  eq(r.has_total, false)
end

T["reports vim.system spawn failures"] = function()
  local r = child.lua_get([[(function()
    local real_system = vim.system
    vim.system = function()
      error("curl missing")
    end

    local http = require("spoil.http")
    local sync = http.get("https://example.test/x")
    local async
    http.get("https://example.test/y", { callback = function(resp) async = resp end })
    vim.wait(100, function() return async ~= nil end)
    vim.system = real_system

    return { sync = sync, async = async }
  end)()]])

  eq(r.sync.exit_code, 127)
  eq(r.sync.status, 0)
  eq(r.sync.body:find("curl missing", 1, true) ~= nil, true)
  eq(r.async.exit_code, 127)
  eq(r.async.status, 0)
end

return T
