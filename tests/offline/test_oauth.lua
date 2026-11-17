local H = dofile("tests/helpers.lua")
local child = H.new_child()
local T = MiniTest.new_set(H.setup(child))
local eq = MiniTest.expect.equality

T["evaluates callback requests"] = function()
  local r = child.lua_get([[(function()
    local o = require("spoil.oauth")
    local function req(q, p) return ("GET %s?%s HTTP/1.1\r\nHost: x\r\n\r\n"):format(p or "/callback", q) end
    return {
      valid = o.evaluate_callback(req("code=abc%2Fdef&state=STATE"), "STATE"),
      missing_state = o.evaluate_callback(req("code=abc"), "STATE"),
      wrong_state = o.evaluate_callback(req("code=abc&state=WRONG"), "STATE"),
      wrong_path = o.evaluate_callback(req("code=abc&state=STATE", "/evil"), "STATE"),
      no_code = o.evaluate_callback(req("state=STATE"), "STATE"),
      incomplete = o.evaluate_callback("GET /call", "STATE"),
      malformed = o.evaluate_callback("hello\r\n\r\n", "STATE"),
    }
  end)()]])

  eq(r.valid, { code = "abc/def" })
  eq(r.missing_state.error, "OAuth state mismatch (possible CSRF); authorization rejected")
  eq(r.wrong_state.error, "OAuth state mismatch (possible CSRF); authorization rejected")
  eq(r.wrong_path.error, "unexpected callback path: /evil")
  eq(r.no_code.error, "no authorization code in callback")
  eq(r.incomplete, nil)
  eq(r.malformed.error, "malformed callback request")
end

T["builds authorize URLs"] = function()
  local r = child.lua_get([[(function()
    local o = require("spoil.oauth")
    return {
      redirect = o.redirect_uri(12345),
      url = o.authorize_url({ client_id = "cid", state = "st ate", scope = "a b" }),
    }
  end)()]])

  eq(r.redirect, "http://127.0.0.1:12345/callback")
  eq(r.url:find("client_id=cid", 1, true) ~= nil, true)
  eq(r.url:find("state=st%20ate", 1, true) ~= nil, true)
  eq(r.url:find("scope=a%20b", 1, true) ~= nil, true)
end

T["serves valid callbacks"] = function()
  local r = child.lua_get([[(function()
    return Support.roundtrip("STATE", "GET /callback?code=ok&state=STATE HTTP/1.1\r\nHost: x\r\n\r\n")
  end)()]])

  eq(r.result, { code = "ok" })
  eq(r.response:find("HTTP/1.1 200 OK", 1, true) ~= nil, true)
end

T["rejects mismatched state"] = function()
  local r = child.lua_get([[(function()
    return Support.roundtrip("STATE", "GET /callback?code=ok&state=BAD HTTP/1.1\r\nHost: x\r\n\r\n")
  end)()]])

  eq(r.result.error, "OAuth state mismatch (possible CSRF); authorization rejected")
  eq(r.response:find("HTTP/1.1 400", 1, true) ~= nil, true)
end

T["rejects wrong paths and escapes HTML"] = function()
  local r = child.lua_get([[(function()
    return Support.roundtrip("STATE", "GET /evil<script>?code=ok&state=STATE HTTP/1.1\r\nHost: x\r\n\r\n")
  end)()]])

  eq(r.result.error, "unexpected callback path: /evil<script>")
  eq(r.response:find("HTTP/1.1 400", 1, true) ~= nil, true)
  eq(r.response:find("<script>", 1, true), nil)
  eq(r.response:find("&lt;script&gt;", 1, true) ~= nil, true)
end

return T
