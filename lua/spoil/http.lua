local M = {}

-- curl has no default deadline; without these, a stalled request freezes
-- the sync path forever. Per-request: `opts.timeout` / `opts.connect_timeout`.
local DEFAULT_CONNECT_TIMEOUT = 5
local DEFAULT_TIMEOUT = 10

---@alias spoil.HttpResponse { status: integer, body: string, exit_code?: integer }
---@alias spoil.HttpOpts { headers?: table<string, string>, body?: string, callback?: fun(resp: spoil.HttpResponse), timeout?: integer, connect_timeout?: integer }
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
  local tmp = vim.fn.tempname()
  local cmd = {
    "curl", "-s",
    "--connect-timeout", tostring(opts.connect_timeout or DEFAULT_CONNECT_TIMEOUT),
    "--max-time", tostring(opts.timeout or DEFAULT_TIMEOUT),
    "-X", method, "-o", tmp, "-w", "%{http_code}",
  }

  for k, v in pairs(opts.headers or {}) do
    table.insert(cmd, "-H")
    table.insert(cmd, k .. ": " .. tostring(v))
  end

  if opts.body then
    table.insert(cmd, "-d")
    table.insert(cmd, opts.body)
  end

  table.insert(cmd, url)

  return cmd, tmp
end

local function read_tmp(tmp)
  if vim.fn.filereadable(tmp) ~= 1 then
    return ""
  end
  local body = table.concat(vim.fn.readfile(tmp), "\n")
  os.remove(tmp)
  return body
end

--- Default transport: shell out to curl.
---@type spoil.HttpTransport
local function curl_transport(method, url, opts)
  opts = opts or {}
  local cmd, tmp = build_curl(method, url, opts)

  if opts.callback then
    local status = 0
    vim.fn.jobstart(cmd, {
      stdout_buffered = true,
      on_stdout = function(_, lines)
        status = tonumber(lines[1]) or 0
      end,
      -- on_exit runs even when curl prints nothing, so the callback always fires.
      on_exit = function(_, code)
        vim.schedule(function()
          opts.callback({ status = status, body = read_tmp(tmp), exit_code = code })
        end)
      end,
    })
  else
    local status_line = vim.fn.system(cmd)
    return {
      status = tonumber(status_line) or 0,
      body = read_tmp(tmp),
      exit_code = vim.v.shell_error,
    }
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
