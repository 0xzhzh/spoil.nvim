local M = {}

-- curl has no default deadline; without these, a stalled request freezes
-- the sync path forever. Per-request: `opts.timeout` / `opts.connect_timeout`.
local DEFAULT_CONNECT_TIMEOUT = 5
local DEFAULT_TIMEOUT = 10
local STATUS_MARKER = "__SPOIL_STATUS__"

---@alias spoil.HttpResponse { status: integer, body: string, exit_code?: integer }
---@class spoil.HttpOpts
---@field headers? table<string, string>
---@field body? string
---@field callback? fun(resp: spoil.HttpResponse)
---@field timeout? integer
---@field connect_timeout? integer
---@alias spoil.HttpTransport fun(method: string, url: string, opts: spoil.HttpOpts): spoil.HttpResponse?

function M.encode_form(params)
  local parts = {}
  for k, v in pairs(params) do
    table.insert(parts, k .. "=" .. vim.uri_encode(tostring(v)))
  end
  return table.concat(parts, "&")
end

local function build_curl(method, url, opts)
  opts = opts or {}
  local cmd = {
    "curl",
    "-s",
    "--connect-timeout",
    tostring(opts.connect_timeout or DEFAULT_CONNECT_TIMEOUT),
    "-X",
    method,
  }

  for k, v in pairs(opts.headers or {}) do
    table.insert(cmd, "-H")
    table.insert(cmd, k .. ": " .. tostring(v))
  end

  if opts.body then
    table.insert(cmd, "-d")
    table.insert(cmd, opts.body)
  end

  table.insert(cmd, "-w")
  table.insert(cmd, "\n" .. STATUS_MARKER .. "%{http_code}")
  table.insert(cmd, url)

  return cmd
end

local function from_process(result)
  local stdout = result.stdout or ""
  local body, status = stdout:match("^(.*)\n" .. STATUS_MARKER .. "(%d%d%d)$")
  if not body then
    body, status = stdout, "0"
  end

  local exit_code = result.code or 0
  if exit_code == 0 and (result.signal or 0) ~= 0 then
    exit_code = 128 + result.signal
  end

  return { status = tonumber(status) or 0, body = body, exit_code = exit_code }
end

local function spawn_error(err)
  return { status = 0, body = tostring(err), exit_code = 127 }
end

--- Default transport: shell out to curl.
---@type spoil.HttpTransport
local function curl_transport(method, url, opts)
  opts = opts or {}
  local cmd = build_curl(method, url, opts)
  local sys_opts = { text = true, timeout = (opts.timeout or DEFAULT_TIMEOUT) * 1000 }

  if opts.callback then
    local ok, err = pcall(vim.system, cmd, sys_opts, function(result)
      vim.schedule(function() opts.callback(from_process(result)) end)
    end)
    if not ok then
      vim.schedule(function() opts.callback(spawn_error(err)) end)
    end
  else
    local ok, result = pcall(function() return vim.system(cmd, sys_opts):wait() end)
    if not ok then return spawn_error(result) end
    return from_process(result)
  end
end

M.transport = nil

--- Replace the HTTP transport (used by tests). Pass nil to restore curl.
---@param transport? spoil.HttpTransport
function M.set_transport(transport)
  if transport ~= nil then
    assert(type(transport) == "function", "transport must be a function or nil")
  end
  M.transport = transport
end

local function request(method, url, opts)
  local transport = M.transport or curl_transport
  return transport(method, url, opts or {})
end

function M.get(url, opts) return request("GET", url, opts) end
function M.post(url, opts) return request("POST", url, opts) end
function M.put(url, opts) return request("PUT", url, opts) end
function M.delete(url, opts) return request("DELETE", url, opts) end

return M
