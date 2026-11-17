local H = dofile("tests/helpers.lua")
local child = H.new_child()
local T = MiniTest.new_set(H.setup(child))
local eq = MiniTest.expect.equality

T["registers commands and dispatches playback actions"] = function()
  local r = child.lua_get([[(function()
    local spoil = require("spoil")
    local user = require("spoil.user_api")
    local command = require("spoil.command")

    local called = {}
    local auth_alias = spoil.auth == spoil.login
    for _, name in ipairs({ "login", "logout", "queue_selected", "select_device" }) do
      user[name] = function() called[#called + 1] = name end
    end

    command.setup()
    local completion = command.complete("", "Spoil ", 0)

    command.dispatch({ fargs = { "login" } })
    command.dispatch({ fargs = { "logout" } })
    command.dispatch({ fargs = { "queue" } })
    command.dispatch({ fargs = { "device" } })

    return {
      completion = completion,
      called = called,
      has_login = type(spoil.login) == "function",
      auth_alias = auth_alias,
    }
  end)()]])

  eq(vim.tbl_contains(r.completion, "login"), true)
  eq(vim.tbl_contains(r.completion, "logout"), true)
  eq(vim.tbl_contains(r.completion, "device"), true)
  eq(vim.tbl_contains(r.completion, "queue"), true)
  eq(vim.tbl_contains(r.completion, "auth"), false)
  eq(r.called, { "login", "logout", "queue_selected", "select_device" })
  eq(r.has_login, true)
  eq(r.auth_alias, true)
end

return T
