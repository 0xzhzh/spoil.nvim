local config = require("spoil.config")
local state = require("spoil.state")
local http = require("spoil.http")
local notify = require("spoil.notify")
local E = require("spoil.error")

local M = {}

local encode_form = http.encode_form

-- Encode raw bytes as base64url (RFC 4648 §5), without padding.
local function base64url_encode(bytes)
  return (vim.base64.encode(bytes):gsub("+", "-"):gsub("/", "_"):gsub("=+$", ""))
end

-- Read `n` cryptographically strong random bytes from the system CSPRNG.
-- `vim.uv.random()` is libuv-backed and cross-platform; /dev/urandom is a
-- fallback for older luv builds that lack the binding.
local function random_bytes(n)
  if vim.uv and vim.uv.random then
    local ok, bytes = pcall(vim.uv.random, n)
    if ok and type(bytes) == "string" and #bytes == n then
      return bytes
    end
  end

  local file = io.open("/dev/urandom", "rb")
  if file then
    local bytes = file:read(n)
    file:close()
    if bytes and #bytes == n then
      return bytes
    end
  end

  error("no cryptographically strong random source available")
end

-- PKCE code verifier: 48 random bytes -> 64 base64url chars (RFC 7636 allows 43-128).
local function generate_code_verifier()
  local verifier = base64url_encode(random_bytes(48))
  if #verifier < 43 or #verifier > 128 then
    error("failed to generate a valid PKCE code verifier")
  end
  return verifier
end

local function generate_code_challenge(verifier)
  local hex = vim.fn.sha256(verifier)
  local digest = hex:gsub("%x%x", function(pair)
    return string.char(tonumber(pair, 16))
  end)
  return base64url_encode(digest)
end

--- Random opaque value echoed back by Spotify and checked on the callback to
--- protect against CSRF / authorization-code injection.
local function generate_oauth_state()
  return base64url_encode(random_bytes(32))
end

local function parse_query(target)
  local params = {}
  local query = target:match("%?([^#]*)")
  if not query then return params end
  for pair in query:gmatch("[^&]+") do
    local key, value = pair:match("^([^=]+)=?(.*)$")
    if key then
      params[vim.uri_decode(key)] = vim.uri_decode(value)
    end
  end
  return params
end

--- Inspect a callback request. Returns nil while the request line is
--- incomplete, otherwise `{ code = ... }` on success or `{ error = ... }`.
local function evaluate_callback(request, expected_state)
  local target = request:match("^%a+%s+(%S+)%s+HTTP/")
  if not target then
    if request:find("\r\n\r\n") then
      return { error = "malformed callback request" }
    end
    return nil
  end

  local path = target:match("^[^?]*")
  if path ~= "/callback" then
    return { error = "unexpected callback path: " .. path }
  end

  local params = parse_query(target)
  if not params.code or params.code == "" then
    if request:find("\r\n\r\n") then
      return { error = "no authorization code in callback" }
    end
    return nil
  end

  if params.state ~= expected_state then
    return { error = "OAuth state mismatch (possible CSRF); authorization rejected" }
  end

  return { code = params.code }
end

local function escape_html(text)
  return (tostring(text)
    :gsub("&", "&amp;")
    :gsub("<", "&lt;")
    :gsub(">", "&gt;")
    :gsub('"', "&quot;"))
end

local function send_response(client, status, title, message)
  local body = ("<html><body><h1>%s</h1><p>%s</p></body></html>"):format(escape_html(title), escape_html(message))
  local resp = ("HTTP/1.1 %s\r\nContent-Length: %d\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n%s"):format(
    status,
    #body,
    body
  )
  client:write(resp, function()
    client:shutdown()
    client:close()
  end)
end

local function start_callback_server(port, expected_state, on_complete)
  local loop = vim.loop
  local server = assert(loop.new_tcp(), "failed to create TCP handle")

  local ok = server:bind("127.0.0.1", port)
  assert(ok, ("failed to bind to 127.0.0.1:%d"):format(port))

  server:listen(128, function(err)
    if err then
      vim.schedule(function() on_complete({ error = "server listen error: " .. tostring(err) }) end)
      return
    end

    local client = assert(loop.new_tcp())
    server:accept(client)

    local chunks = {}
    local finished = false
    client:read_start(function(read_err, data)
      if finished then return end

      if read_err then
        finished = true
        vim.schedule(function() on_complete({ error = "read error: " .. tostring(read_err) }) end)
        return
      end

      if not data then
        client:close()
        return
      end

      table.insert(chunks, data)
      local result = evaluate_callback(table.concat(chunks), expected_state)
      if not result then return end

      finished = true
      if result.code then
        send_response(client, "200 OK", "Authenticated!", "Return to Neovim.")
      else
        send_response(client, "400 Bad Request", "Authorization Error", result.error)
      end
      vim.schedule(function() on_complete(result) end)
    end)
  end)

  return server
end

local function show_floating_window(url, on_cancel)
  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.min(100, vim.o.columns - 4)
  local height = 10
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Spotify Authorization ",
    title_pos = "center",
  })

  vim.wo[win].winhl = "Normal:NormalFloat"

  local lines = {
    "Open this URL in your browser to authorize Spoil:",
    "",
    url,
    "",
    "Press q to cancel",
  }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.keymap.set("n", "q", on_cancel or function() end, { buffer = buf, nowait = true, silent = true })

  return win, buf
end

local function exchange_code(code, verifier, redirect_uri, client_id)
  local resp = http.post("https://accounts.spotify.com/api/token", {
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded",
    },
    body = encode_form({
      grant_type = "authorization_code",
      code = code,
      redirect_uri = redirect_uri,
      client_id = client_id,
      code_verifier = verifier,
    }),
  })

  if resp.status ~= 200 then
    local description
    pcall(function()
      local body = vim.fn.json_decode(resp.body)
      description = body.error_description
    end)
    error(E.token_exchange_failed(resp.status, description).msg)
  end

  return vim.fn.json_decode(resp.body)
end

local function copy_to_clipboard(text)
  if vim.fn.has("clipboard") == 1 then
    vim.fn.setreg('+', text)
    vim.fn.setreg('"', text)
  end
end

local function do_auth(client_id, open_browser, clipboard)
  local port = config.options.auth.port
  local redirect_uri = ("http://127.0.0.1:%d/callback"):format(port)

  -- Generate PKCE challenge and OAuth state
  local verifier, challenge, oauth_state
  local ok, err = pcall(function()
    verifier = generate_code_verifier()
    challenge = generate_code_challenge(verifier)
    oauth_state = generate_oauth_state()
  end)
  if not ok then
    return E.notify(err)
  end

  -- Build authorize URL
  local params = {
    client_id = client_id,
    response_type = "code",
    redirect_uri = redirect_uri,
    code_challenge_method = "S256",
    code_challenge = challenge,
    scope = table.concat(config.options.auth.scopes, " "),
    state = oauth_state,
  }
  local qs = {}
  for k, v in pairs(params) do
    table.insert(qs, k .. "=" .. vim.uri_encode(v))
  end
  local url = "https://accounts.spotify.com/authorize?" .. table.concat(qs, "&")

  if clipboard then
    copy_to_clipboard(url)
  end

  -- Track state for cleanup
  local server
  local win
  local buf
  local done = false

  local function cleanup()
    if server then pcall(function() server:close() end) end
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    if buf then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
  end

  local function cancel()
    if done then return end
    done = true
    cleanup()
    notify.warn("Spoil: Auth cancelled")
  end

  local function on_complete(result)
    if done then return end
    done = true
    cleanup()
    if result.error then
      return E.notify("Auth failed — " .. result.error)
    end
    local tokens
    ok, err = pcall(function()
      tokens = exchange_code(result.code, verifier, redirect_uri, client_id)
    end)
    if not ok then
      return E.notify(err)
    end
    state.save_tokens(tokens)
    notify.info("Spoil: Authenticated successfully!")
  end

  -- Start callback server
  ok, err = pcall(function()
    server = start_callback_server(port, oauth_state, on_complete)
  end)
  if not ok then
    return E.notify(err)
  end

  -- Show floating window (always — status indicator + cancel)
  win, buf = show_floating_window(url, cancel)

  -- Open browser if configured
  if open_browser then
    vim.ui.open(url)
    notify.info("Spoil: Browser opened for Spotify authorization (port " .. port .. ")")
  end
end

function M.auth(opts)
  opts = opts or {}

  local open_browser
  if opts.open_browser ~= nil then
    open_browser = opts.open_browser
  else
    open_browser = config.options.auth.open_browser
  end

  local clipboard
  if opts.clipboard ~= nil then
    clipboard = opts.clipboard
  else
    clipboard = config.options.auth.clipboard
  end

  local client_id = config.options.auth.client_id
  if not client_id then
    local creds = state.load_credentials()
    client_id = creds and creds.client_id or nil
  end
  if client_id then
    do_auth(client_id, open_browser, clipboard)
    return
  end
  vim.ui.input({ prompt = "Spotify Client ID: " }, function(input)
    if not input or input == "" then
      notify.warn("Spoil: Auth cancelled")
      return
    end
    state.save_credentials(input)
    do_auth(input, open_browser, clipboard)
  end)
end

return M
