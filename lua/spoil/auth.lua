local config = require("spoil.config")
local state = require("spoil.state")
local http = require("spoil.http")
local notify = require("spoil.notify")
local E = require("spoil.error")
local pkce = require("spoil.pkce")
local oauth = require("spoil.oauth")

local M = {}

local auth_in_progress = false

local encode_form = http.encode_form

local function show_floating_window(url, on_cancel)
  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.max(1, math.min(100, vim.o.columns - 4))
  local height = math.max(1, math.min(10, vim.o.lines - 2))
  local row = math.max(0, math.floor((vim.o.lines - height) / 2))
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  local ok, win = pcall(vim.api.nvim_open_win, buf, true, {
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
  if not ok then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    return nil, nil, tostring(win)
  end

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

  return win, buf, nil
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

  if resp.exit_code and resp.exit_code ~= 0 then
    error(E.transport_failed(resp.exit_code).msg)
  end

  if resp.status ~= 200 then
    local description
    pcall(function()
      local body = vim.json.decode(resp.body)
      description = body.error_description
    end)
    error(E.token_exchange_failed(resp.status, description).msg)
  end

  return vim.json.decode(resp.body)
end

local function copy_to_clipboard(text)
  if vim.fn.has("clipboard") ~= 1 then return false end
  return pcall(function()
    vim.fn.setreg("+", text)
    vim.fn.setreg('"', text)
  end)
end

local function do_auth(client_id, open_browser, clipboard, on_success)
  local port = config.options.auth.port
  local redirect_uri = oauth.redirect_uri(port)

  -- Generate PKCE challenge and OAuth state
  local verifier, challenge, oauth_state
  local ok, err = pcall(function()
    verifier = pkce.code_verifier()
    challenge = pkce.code_challenge(verifier)
    oauth_state = pkce.oauth_state()
  end)
  if not ok then
    auth_in_progress = false
    E.notify(err)
    return
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
  local url = oauth.authorize_url(params)

  local copied = clipboard and copy_to_clipboard(url)

  -- Track state for cleanup
  local server
  local win
  local buf
  local timer
  local group
  local done = false

  local function cleanup()
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
    if server then pcall(function() server:close() end) end
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    if buf then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
    if group then
      pcall(vim.api.nvim_del_augroup_by_id, group)
      group = nil
    end
  end

  local function finish(cause)
    if done then return end
    done = true
    auth_in_progress = false
    cleanup()
    if cause then E.notify(cause) end
  end

  local function cancel()
    if done then return end
    finish()
    notify.warn("Spoil: Auth cancelled")
  end

  local function on_complete(result)
    if done then return end
    if result.error then
      finish(E.new("Auth failed — " .. result.error))
      return
    end
    finish()
    local tokens
    ok, err = pcall(function()
      tokens = exchange_code(result.code, verifier, redirect_uri, client_id)
    end)
    if not ok then
      E.notify(err)
      return
    end
    local saved, save_err = state.save_tokens(tokens)
    if not saved then
      E.notify(E.storage_failed("Spotify tokens", save_err))
      return
    end
    notify.info("Spoil: Authenticated successfully!")
    if on_success then on_success() end
  end

  -- Start callback server
  ok, err = pcall(function()
    server = oauth.start_server(port, oauth_state, on_complete)
  end)
  if not ok then
    auth_in_progress = false
    E.notify(err)
    return
  end

  timer = vim.uv.new_timer()
  timer:start((config.options.auth.timeout or 300) * 1000, 0, function()
    vim.schedule(function() finish(E.new("Authentication timed out")) end)
  end)

  -- Show floating window (always — status indicator + cancel)
  local open_err
  win, buf, open_err = show_floating_window(url, cancel)
  if open_err then
    finish(E.new("Could not open the authorization window: " .. open_err))
    return
  end

  group = vim.api.nvim_create_augroup("spoil_auth_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(win),
    callback = cancel,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = cancel,
  })

  if clipboard and not copied then
    notify.warn("Spoil: Could not copy the authorization URL to the clipboard")
  end

  -- Open browser if configured
  if open_browser then
    vim.ui.open(url)
    notify.info("Spoil: Browser opened for Spotify authorization (port " .. port .. ")")
  end
end

function M.auth(opts)
  opts = opts or {}
  if auth_in_progress then
    notify.warn("Spoil: Authentication already in progress")
    return
  end
  auth_in_progress = true

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
    do_auth(client_id, open_browser, clipboard, opts.on_success)
    return
  end
  vim.ui.input({ prompt = "Spotify Client ID: " }, function(input)
    if not input or input == "" then
      auth_in_progress = false
      notify.warn("Spoil: Auth cancelled")
      return
    end
    local saved, save_err = state.save_credentials(input)
    if not saved then
      auth_in_progress = false
      E.notify(E.storage_failed("Spotify Client ID", save_err))
      return
    end
    do_auth(input, open_browser, clipboard, opts.on_success)
  end)
end

return M
