local H = dofile("tests/helpers.lua")
local child = H.new_child()
local T = MiniTest.new_set(H.setup(child))
local eq = MiniTest.expect.equality

T["writes private JSON files"] = function()
  local r = child.lua_get([[(function()
    local state = require("spoil.state")
    local dir = vim.fs.joinpath(vim.fn.stdpath("data"), "spoil")
    local tokens_path = vim.fs.joinpath(dir, "tokens.json")
    local creds_path = vim.fs.joinpath(dir, "credentials.json")
    local function mode(path) return vim.uv.fs_stat(path).mode % 512 end

    state.save_tokens({ access_token = "a", refresh_token = "r" })
    local result = {
      dir_mode = mode(dir),
      tokens_mode = mode(tokens_path),
      tokens = state.load_tokens(),
    }

    state.save_credentials("client-id")
    result.creds_mode = mode(creds_path)
    result.creds = state.load_credentials()

    -- Older broad permissions get tightened on the next save.
    vim.uv.fs_chmod(tokens_path, tonumber("644", 8))
    result.wide_mode = mode(tokens_path)
    state.save_tokens({ access_token = "b" })
    result.tightened_mode = mode(tokens_path)
    result.reloaded = state.load_tokens()

    state.clear_tokens()
    result.tokens_after_clear = state.load_tokens()
    state.save_credentials("other")
    state.clear_all()
    result.creds_after_clear = state.load_credentials()

    return result
  end)()]])

  eq(r.dir_mode, tonumber("700", 8))
  eq(r.tokens_mode, tonumber("600", 8))
  eq(r.tokens, { access_token = "a", refresh_token = "r" })
  eq(r.creds_mode, tonumber("600", 8))
  eq(r.creds, { client_id = "client-id" })
  eq(r.wide_mode, tonumber("644", 8))
  eq(r.tightened_mode, tonumber("600", 8))
  eq(r.reloaded, { access_token = "b" })
  eq(r.tokens_after_clear, nil)
  eq(r.creds_after_clear, nil)
end

return T
