local H = dofile("tests/helpers.lua")
local child = H.new_child()
local T = MiniTest.new_set(H.setup(child))
local eq = MiniTest.expect.equality

T["challenge matches RFC 7636 vector"] = function()
  eq(
    child.lua_get([[require("spoil.pkce").code_challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")]]),
    "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
  )
end

T["verifier has valid PKCE shape"] = function()
  local r = child.lua_get([[(function()
    local p = require("spoil.pkce")
    local v1, v2 = p.code_verifier(), p.code_verifier()
    return {
      len = #v1,
      valid_chars = v1:match("^[A-Za-z0-9%-%._~]+$") ~= nil,
      challenge_len = #p.code_challenge(v1),
      unique = v1 ~= v2,
    }
  end)()]])

  eq(r.len, 64)
  eq(r.valid_chars, true)
  eq(r.challenge_len, 43)
  eq(r.unique, true)
end

T["state has valid shape"] = function()
  local r = child.lua_get([[(function()
    local p = require("spoil.pkce")
    local s1, s2 = p.oauth_state(), p.oauth_state()
    return { len = #s1, valid_chars = s1:match("^[A-Za-z0-9_-]+$") ~= nil, unique = s1 ~= s2 }
  end)()]])

  eq(r.len, 43)
  eq(r.valid_chars, true)
  eq(r.unique, true)
end

return T
