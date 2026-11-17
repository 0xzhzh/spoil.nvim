local config = require("spoil.config")
local state = require("spoil.state")
local http = require("spoil.http")
local notify = require("spoil.notify")

local M = {}

local encode_form = http.encode_form

local function generate_code_verifier()
  local cmd = "openssl rand -base64 48"
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    error("openssl not available; cannot generate PKCE verifier")
  end
  result = result:gsub("\n", "")
  result = result:gsub("+", "-"):gsub("/", "_"):gsub("=+$", "")
  return result
end

local function generate_code_challenge(verifier)
  local cmd = ("echo -n '%s' | openssl dgst -sha256 -binary | openssl base64"):format(verifier)
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    error("openssl not available; cannot compute code challenge")
  end
  result = result:gsub("\n", "")
  result = result:gsub("+", "-"):gsub("/", "_"):gsub("=+$", "")
  return result
end

local function start_callback_server(port, on_complete)
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
    client:read_start(function(read_err, data)
      if read_err then
        vim.schedule(function() on_complete({ error = "read error: " .. tostring(read_err) }) end)
        return
      end

      if data then
        table.insert(chunks, data)
        local full = table.concat(chunks)
        local code = full:match("code=([^%s&]+)")
        if code then
          local decoded = vim.uri_decode(code)
          local body = "<html><body><h1>Authenticated!</h1><p>Return to Neovim.</p></body></html>"
          local resp = ("HTTP/1.1 200 OK\r\nContent-Length: %d\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n%s"):format(#body, body)
          client:write(resp, function() client:shutdown() client:close() end)
          vim.schedule(function() on_complete({ code = decoded }) end)
        elseif full:find("\r\n\r\n") then
          local body = "<html><body><h1>Error</h1><p>No authorization code found.</p></body></html>"
          local resp = ("HTTP/1.1 400 Bad Request\r\nContent-Length: %d\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n%s"):format(#body, body)
          client:write(resp, function() client:shutdown() client:close() end)
          vim.schedule(function() on_complete({ error = "no authorization code in callback" }) end)
        end
      else
        client:close()
      end
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
    local msg = "token exchange failed (HTTP " .. resp.status .. ")"
    pcall(function()
      local body = vim.fn.json_decode(resp.body)
      if body.error_description then
        msg = msg .. ": " .. body.error_description
      end
    end)
    error(msg)
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

  -- Generate PKCE challenge
  local verifier, challenge
  local ok, err = pcall(function()
    verifier = generate_code_verifier()
    challenge = generate_code_challenge(verifier)
  end)
  if not ok then
    return notify.error("Spoil: " .. err)
  end

  -- Build authorize URL
  local params = {
    client_id = client_id,
    response_type = "code",
    redirect_uri = redirect_uri,
    code_challenge_method = "S256",
    code_challenge = challenge,
    scope = table.concat(config.options.auth.scopes, " "),
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
      return notify.error("Spoil: Auth failed — " .. result.error)
    end
    local tokens
    ok, err = pcall(function()
      tokens = exchange_code(result.code, verifier, redirect_uri, client_id)
    end)
    if not ok then
      return notify.error("Spoil: " .. err)
    end
    state.save_tokens(tokens)
    notify.info("Spoil: Authenticated successfully!")
  end

  -- Start callback server
  ok, err = pcall(function()
    server = start_callback_server(port, on_complete)
  end)
  if not ok then
    return notify.error("Spoil: " .. err)
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
