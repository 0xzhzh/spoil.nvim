--- OAuth helpers: authorize URL construction and the local callback server.
local M = {}

---@param port integer
---@return string
function M.redirect_uri(port)
  return ("http://127.0.0.1:%d/callback"):format(port)
end

---@param params table<string, string>
---@return string
function M.authorize_url(params)
  local qs = {}
  for k, v in pairs(params) do
    table.insert(qs, k .. "=" .. vim.uri_encode(tostring(v)))
  end
  return "https://accounts.spotify.com/authorize?" .. table.concat(qs, "&")
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
---@param request string
---@param expected_state string
---@return { code?: string, error?: string }|nil
function M.evaluate_callback(request, expected_state)
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
  if params.error and params.error ~= "" then
    local detail = params.error
    if params.error_description and params.error_description ~= "" then
      detail = detail .. ": " .. params.error_description
    end
    return { error = "Spotify authorization failed: " .. detail }
  end

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
  return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
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

--- Start a loopback server that accepts one OAuth callback.
---@param port integer
---@param expected_state string
---@param on_complete fun(result: { code?: string, error?: string })
function M.start_server(port, expected_state, on_complete)
  local loop = vim.uv or vim.loop
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
      local result = M.evaluate_callback(table.concat(chunks), expected_state)
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

return M
