local M = {}

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
  local cmd = { "curl", "-s", "-X", method, "-o", tmp, "-w", "%{http_code}" }

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

local function request(method, url, opts)
  opts = opts or {}
  local cmd, tmp = build_curl(method, url, opts)

  if opts.callback then
    vim.fn.jobstart(cmd, {
      stdout_buffered = true,
      on_stdout = function(_, lines)
        local status = tonumber(lines[1]) or 0
        vim.schedule(function()
          opts.callback({ status = status, body = read_tmp(tmp) })
        end)
      end,
    })
  else
    local status_line = vim.fn.system(cmd)
    return { status = tonumber(status_line) or 0, body = read_tmp(tmp) }
  end
end

function M.get(url, opts) return request("GET", url, opts) end
function M.post(url, opts) return request("POST", url, opts) end
function M.put(url, opts) return request("PUT", url, opts) end
function M.delete(url, opts) return request("DELETE", url, opts) end

return M
