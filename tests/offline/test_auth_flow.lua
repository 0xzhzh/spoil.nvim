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
    state.save_tokens = function(tokens) saved = tokens return true end
    http.set_transport(function(method, url, opts)
      assert(method == "POST" and url == "https://accounts.spotify.com/api/token")
      token_body = opts.body
      return { status = 200, body = vim.json.encode({ access_token = "access", refresh_token = "refresh" }) }
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

T["resumes the pending explorer action after login"] = function()
  local r = child.lua_get([[(function()
    local config = require("spoil.config")
    local state = require("spoil.state")
    local http = require("spoil.http")
    local explorer = require("spoil.explorer")
    local user = require("spoil.user_api")

    local port = Support.free_port()
    config.options.auth.client_id = "cid"
    config.options.auth.port = port
    config.options.auth.open_browser = false
    config.options.auth.clipboard = false
    config.options.auth.auto_auth = true

    local tokens, opened
    state.load_tokens = function() return tokens end
    state.save_tokens = function(t) tokens = t return true end
    http.set_transport(function()
      return { status = 200, body = vim.json.encode({ access_token = "access", refresh_token = "refresh" }) }
    end)
    explorer.open_playlists = function() opened = true end

    user.open_explorer()
    local url
    for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if line:find("https://accounts.spotify.com/authorize?", 1, true) then url = line end
    end
    local state_value = url and vim.uri_decode(url:match("[?&]state=([^&]+)"))
    local response = ("GET /callback?code=test-code&state=%s HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"):format(
      state_value
    )
    Support.request(port, response)
    vim.wait(3000, function() return opened end)

    return { opened = opened, tokens = tokens }
  end)()]])

  eq(r.opened, true)
  eq(r.tokens, { access_token = "access", refresh_token = "refresh" })
end

T["times out the auth flow"] = function()
  local r = child.lua_get([[(function()
    local config = require("spoil.config")
    local auth = require("spoil.auth")
    local notify = require("spoil.notify")

    local messages = {}
    notify.backend = function(msg, level) messages[#messages + 1] = { msg = msg, level = level } end

    config.options.auth.client_id = "cid"
    config.options.auth.port = Support.free_port()
    config.options.auth.open_browser = false
    config.options.auth.clipboard = false
    config.options.auth.timeout = 0.05

    local before = #vim.api.nvim_list_wins()
    auth.auth()
    local opened = #vim.api.nvim_list_wins() > before
    vim.wait(2000, function()
      for _, message in ipairs(messages) do
        if message.msg:find("timed out", 1, true) then return true end
      end
      return false
    end)

    return { opened = opened, closed = #vim.api.nvim_list_wins() == before, messages = messages }
  end)()]])

  eq(r.opened, true)
  eq(r.closed, true)
  local timed_out = false
  for _, message in ipairs(r.messages) do
    if message.msg == "Spoil: Authentication timed out" then timed_out = true end
  end
  eq(timed_out, true)
end

T["guards reentrant auth and cancels on window close"] = function()
  local r = child.lua_get([[(function()
    local config = require("spoil.config")
    local auth = require("spoil.auth")
    local notify = require("spoil.notify")

    local messages = {}
    notify.backend = function(msg, level) messages[#messages + 1] = { msg = msg, level = level } end

    config.options.auth.client_id = "cid"
    config.options.auth.port = Support.free_port()
    config.options.auth.open_browser = false
    config.options.auth.clipboard = false
    config.options.auth.timeout = 60

    local before = #vim.api.nvim_list_wins()
    auth.auth()
    local first = #vim.api.nvim_list_wins()
    auth.auth()
    local second = #vim.api.nvim_list_wins()
    vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
    vim.wait(1000, function()
      for _, message in ipairs(messages) do
        if message.msg:find("Auth cancelled", 1, true) then return true end
      end
      return false
    end)

    return { before = before, first = first, second = second, after = #vim.api.nvim_list_wins(), messages = messages }
  end)()]])

  eq(r.first, r.before + 1)
  eq(r.second, r.first)
  eq(r.after, r.before)

  local warned_progress, cancelled = false, false
  for _, message in ipairs(r.messages) do
    if message.msg:find("already in progress", 1, true) then warned_progress = true end
    if message.msg == "Spoil: Auth cancelled" then cancelled = true end
  end
  eq(warned_progress, true)
  eq(cancelled, true)
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
    state.save_tokens = function(tokens) saved = tokens return true end
    http.set_transport(function()
      return { status = 200, body = vim.json.encode({ access_token = "access", refresh_token = "refresh" }) }
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
