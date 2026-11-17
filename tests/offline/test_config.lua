local H = dofile("tests/helpers.lua")
local child = H.new_child()
local T = MiniTest.new_set(H.setup(child))
local eq = MiniTest.expect.equality

T["default scopes include library and follow writes"] = function()
  local r = child.lua_get([[(function()
    local scopes = require("spoil.config").defaults.auth.scopes
    local seen, unique = {}, true
    for _, scope in ipairs(scopes) do
      if seen[scope] then unique = false end
      seen[scope] = true
    end
    return {
      count = #scopes,
      unique = unique,
      library_modify = seen["user-library-modify"] == true,
      follow_modify = seen["user-follow-modify"] == true,
    }
  end)()]])

  eq(r.unique, true)
  eq(r.library_modify, true)
  eq(r.follow_modify, true)
  eq(r.count >= 15, true)
end

T["setup merges overrides"] = function()
  local r = child.lua_get([[(function()
    local config = require("spoil.config")
    config.setup({ auth = { client_id = "cid" }, statusline = { sep = " - " } })
    return {
      client_id = config.options.auth.client_id,
      sep = config.options.statusline.sep,
      auto_auth = config.options.auth.auto_auth,
      scopes = #config.options.auth.scopes,
    }
  end)()]])

  eq(r.client_id, "cid")
  eq(r.sep, " - ")
  eq(r.auto_auth, true)
  eq(r.scopes >= 15, true)
end

return T
