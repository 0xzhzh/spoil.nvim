local H = dofile("tests/helpers.lua")
local child = H.new_child()
local T = MiniTest.new_set(H.setup(child))
local eq = MiniTest.expect.equality

T["runs the auth flow end to end"] = function()
  local r = child.lua_get([[(function()
    local config = require("spoil.config")
    local state = require("spoil.state")
    local http = require("spoil.http")
    local auth = require("spoil.auth")

    local port = Support.free_port()
    config.options.auth.client_id = "cid"
    config.options.auth.port = port
    config.options.auth.open_browser = false
    config.options.auth.clipboard = false

    local saved, token_body
    state.save_tokens = function(tokens) saved = tokens end
    http.set_transport(function(method, url, opts)
      assert(method == "POST" and url == "https://accounts.spotify.com/api/token")
      token_body = opts.body
      return { status = 200, body = vim.fn.json_encode({ access_token = "access", refresh_token = "refresh" }) }
    end)

    local ok, err = pcall(auth.auth)
    if not ok then return { error = tostring(err) } end

    local url
    for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if line:find("https://accounts.spotify.com/authorize?", 1, true) then url = line end
    end
    local state_value = url and vim.uri_decode(url:match("[?&]state=([^&]+)"))

    local response = Support.request(
      port,
      ("GET /callback?code=test-code&state=%s HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"):format(state_value)
    )
    vim.wait(3000, function() return saved ~= nil end)

    return {
      url = url,
      response = response,
      tokens = saved,
      token_body = token_body,
      redirect = ("http://127.0.0.1:%d/callback"):format(port),
    }
  end)()]])

  eq(r.error, nil)
  eq(r.tokens, { access_token = "access", refresh_token = "refresh" })
  eq(r.url:find("state=", 1, true) ~= nil, true)
  eq(r.url:find("code_challenge=", 1, true) ~= nil, true)
  eq(r.url:find("redirect_uri=" .. vim.uri_encode(r.redirect), 1, true) ~= nil, true)
  eq(r.response:find("HTTP/1.1 200 OK", 1, true) ~= nil, true)
  eq(r.token_body:find("grant_type=authorization_code", 1, true) ~= nil, true)
  eq(r.token_body:find("code=test%-code") ~= nil, true)
  eq(r.token_body:find("code_verifier=", 1, true) ~= nil, true)
end

T["warns when the clipboard is unavailable"] = function()
  local r = child.lua_get([[(function()
    local config = require("spoil.config")
    local state = require("spoil.state")
    local http = require("spoil.http")
    local auth = require("spoil.auth")
    local notify = require("spoil.notify")

    local port = Support.free_port()
    config.options.auth.client_id = "cid"
    config.options.auth.port = port
    config.options.auth.open_browser = false
    config.options.auth.clipboard = true

    local messages, saved = {}, nil
    notify.backend = function(msg, level) messages[#messages + 1] = { msg = msg, level = level } end
    state.save_tokens = function(tokens) saved = tokens end
    http.set_transport(function()
      return { status = 200, body = vim.fn.json_encode({ access_token = "access", refresh_token = "refresh" }) }
    end)

    local real_has = vim.fn.has
    vim.fn.has = function(name)
      if name == "clipboard" then return 0 end
      return real_has(name)
    end
    local ok, err = pcall(auth.auth)
    vim.fn.has = real_has
    if not ok then return { error = tostring(err) } end

    local url
    for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if line:find("https://accounts.spotify.com/authorize?", 1, true) then url = line end
    end
    local state_value = url and vim.uri_decode(url:match("[?&]state=([^&]+)"))
    Support.request(
      port,
      ("GET /callback?code=test-code&state=%s HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"):format(state_value)
    )
    vim.wait(3000, function() return saved ~= nil end)

    return { messages = messages, tokens = saved, WARN = vim.log.levels.WARN }
  end)()]])

  eq(r.error, nil)
  eq(r.tokens, { access_token = "access", refresh_token = "refresh" })

  local warning
  for _, message in ipairs(r.messages) do
    if message.msg:find("clipboard", 1, true) then warning = message end
  end
  eq(warning ~= nil, true)
  eq(warning.level, r.WARN)
  eq(warning.msg, "Spoil: Could not copy the authorization URL to the clipboard")
end

return T
