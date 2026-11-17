local M = {}
local config = require("spoil.config")
local state = require("spoil.state")
local http = require("spoil.http")
local E = require("spoil.error")

local encode_form = http.encode_form

local function resolve_client_id()
  local id = config.options.auth.client_id
  if not id then
    local creds = state.load_credentials()
    id = creds and creds.client_id or nil
  end
  return id
end

local function refresh_access_token()
  local tokens = state.load_tokens()
  if not tokens or not tokens.refresh_token then
    return nil
  end

  local client_id = resolve_client_id()
  if not client_id then
    return nil
  end

  local resp = http.post("https://accounts.spotify.com/api/token", {
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
    body = encode_form({
      grant_type = "refresh_token",
      refresh_token = tokens.refresh_token,
      client_id = client_id,
    }),
  })

  if resp.status ~= 200 then
    return nil
  end

  local ok, new_tokens = pcall(vim.fn.json_decode, resp.body)
  if not ok then
    return nil
  end

  new_tokens.refresh_token = new_tokens.refresh_token or tokens.refresh_token
  state.save_tokens(new_tokens)
  return new_tokens.access_token
end

local function parse(resp)
  local ok, data = pcall(vim.fn.json_decode, resp.body)
  if not ok then
    return E.parse_failed(resp)
  end
  return data
end

function M.add_query(url, params)
  local parts = {}
  for k, v in pairs(params) do
    if v ~= nil then
      table.insert(parts, k .. "=" .. vim.uri_encode(tostring(v)))
    end
  end
  if #parts == 0 then return url end
  return url .. "?" .. table.concat(parts, "&")
end

local function build_opts(token, data)
  local opts = { headers = { Authorization = "Bearer " .. token } }
  if data then
    opts.headers["Content-Type"] = "application/json"
    opts.body = vim.fn.json_encode(data)
  end
  return opts
end

local function request(method, tokens, url, data)
  local f = http[method]
  local opts = build_opts(tokens.access_token, data)
  local resp = f(url, opts)

  if resp.status == 401 then
    local new_token = refresh_access_token()
    if not new_token then
      state.clear_tokens()
      return E.not_authenticated()
    end
    resp = f(url, build_opts(new_token, data))
  end

  if resp.status == 429 then return E.rate_limited() end
  return resp
end

--- Async counterpart of refresh_access_token. Calls cb(err, new_tokens).
local function refresh_token_async(refresh_token, cb)
  local client_id = resolve_client_id()
  if not client_id then
    return cb(E.not_authenticated())
  end
  http.post("https://accounts.spotify.com/api/token", {
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
    body = encode_form({
      grant_type = "refresh_token",
      refresh_token = refresh_token,
      client_id = client_id,
    }),
    callback = function(resp)
      if resp.status ~= 200 then
        return cb(E.not_authenticated())
      end
      local ok, tokens = pcall(vim.fn.json_decode, resp.body)
      if not ok then
        return cb(E.token_refresh_failed())
      end
      cb(nil, tokens)
    end,
  })
end

local function request_async(method, session, url, data, cb)
  local f = http[method]
  local opts = build_opts(session.access_token, data)

  local function run(retried)
    opts.callback = function(resp)
      if resp.status == 401 and not retried then
        refresh_token_async(session.refresh_token, function(err, nt)
          if err then
            state.clear_tokens()
            return cb(err, nil)
          end
          session.access_token = nt.access_token
          session.refresh_token = nt.refresh_token or session.refresh_token
          nt.refresh_token = session.refresh_token
          state.save_tokens(nt)
          opts.headers.Authorization = "Bearer " .. session.access_token
          run(true)
        end)
        return
      end
      if resp.status == 429 then
        cb(E.rate_limited(), nil)
        return
      end
      cb(nil, resp)
    end
    f(url, opts)
  end
  run(false)
end

local function api_error(resp)
  return E.from_api(resp.status, parse(resp))
end

local function check_write(resp)
  if resp.msg then return resp end
  if resp.status >= 200 and resp.status < 300 then
    if resp.body == "" then return {} end
    return parse(resp)
  end
  return api_error(resp)
end

local function check(cb)
  cb = cb and vim.schedule_wrap(cb)
  local tokens = state.load_tokens()
  if not tokens or not tokens.access_token then
    local err = E.not_authenticated()
    if cb then cb(err, nil) end
    return err
  end
  return nil, tokens, cb
end

function M.get(url, callback)
  local auth_err, tokens, cb = check(callback)
  if auth_err then return auth_err end
  if cb then
    request_async("get", tokens, url, nil, function(err, resp)
      if err then return cb(err, nil) end
      if resp.status == 204 then return cb(nil, {}) end
      if resp.status ~= 200 then return cb(api_error(resp), nil) end
      local data = parse(resp)
      if data.msg then return cb(data, nil) end
      cb(nil, data)
    end)
  else
    local resp = request("get", tokens, url, nil)
    if resp.msg then return resp end
    if resp.status == 204 then return {} end
    if resp.status ~= 200 then return api_error(resp) end
    return parse(resp)
  end
end

function M.post(url, data, callback)
  local auth_err, tokens, cb = check(callback)
  if auth_err then return auth_err end
  if cb then
    request_async("post", tokens, url, data, function(err, resp)
      if err then return cb(err, nil) end
      if resp.status >= 200 and resp.status < 300 then
        if resp.body == "" then return cb(nil, {}) end
        local d = parse(resp)
        if d.msg then return cb(nil, { body = resp.body }) end
        return cb(nil, d)
      end
      cb(api_error(resp), nil)
    end)
  else
    return check_write(request("post", tokens, url, data))
  end
end

function M.put(url, data, callback)
  local auth_err, tokens, cb = check(callback)
  if auth_err then return auth_err end
  if cb then
    request_async("put", tokens, url, data, function(err, resp)
      if err then return cb(err, nil) end
      if resp.status >= 200 and resp.status < 300 then
        if resp.body == "" then return cb(nil, {}) end
        local d = parse(resp)
        if d.msg then return cb(nil, { body = resp.body }) end
        return cb(nil, d)
      end
      cb(api_error(resp), nil)
    end)
  else
    return check_write(request("put", tokens, url, data))
  end
end

function M.del(url, data, callback)
  local auth_err, tokens, cb = check(callback)
  if auth_err then return auth_err end
  if cb then
    request_async("delete", tokens, url, data, function(err, resp)
      if err then return cb(err, nil) end
      if resp.status >= 200 and resp.status < 300 then
        if resp.body == "" then return cb(nil, {}) end
        local d = parse(resp)
        if d.msg then return cb(nil, { body = resp.body }) end
        return cb(nil, d)
      end
      cb(api_error(resp), nil)
    end)
  else
    return check_write(request("delete", tokens, url, data))
  end
end

function M.paginate(url, callback)
  local auth_err, tokens, cb = check(callback)
  if auth_err then return auth_err end
  local all_items = {}
  local total

  local function collect(data)
    for _, item in ipairs(data.items or {}) do
      table.insert(all_items, item)
    end
    total = data.total ~= vim.NIL and data.total or nil
  end

  if cb then
    local function fetch()
      request_async("get", tokens, url, nil, function(err, resp)
        if err then return cb(err, nil) end
        if resp.status == 204 then return cb(nil, {}) end
        if resp.status ~= 200 then return cb(api_error(resp), nil) end
        local data = parse(resp)
        if data.msg then return cb(data, nil) end
        collect(data)
        url = data.next ~= vim.NIL and data.next or nil
        if url then fetch() else cb(nil, { items = all_items, total = total }) end
      end)
    end
    fetch()
  else
    while url do
      local resp = request("get", tokens, url, nil)
      if resp.msg then return resp end
      if resp.status ~= 200 then return api_error(resp) end
      local data = parse(resp)
      if data.msg then return data end
      collect(data)
      url = data.next ~= vim.NIL and data.next or nil
    end
    return { items = all_items, total = total }
  end
end

return M
