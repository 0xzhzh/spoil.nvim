-- Helpers loaded inside child Neovim processes.
local S = {}

function S.free_port()
  local tcp = assert(vim.uv.new_tcp())
  assert(tcp:bind("127.0.0.1", 0))
  local addr = tcp:getsockname()
  tcp:close()
  return type(addr) == "table" and addr.port or select(2, tcp:getsockname())
end

function S.request(port, request, timeout)
  timeout = timeout or 2000
  local response = {}
  local client = assert(vim.uv.new_tcp())
  local connected = false

  client:connect("127.0.0.1", port, function(err) connected = err == nil end)
  assert(vim.wait(1000, function() return connected end), "connect timed out")

  client:write(request)
  client:read_start(function(_, data)
    if data then
      table.insert(response, data)
    else
      client:close()
    end
  end)

  vim.wait(timeout, function() return #response > 0 end)
  pcall(function() client:close() end)
  return table.concat(response)
end

function S.attempt(expected_state, request)
  local port = S.free_port()
  local server = require("spoil.oauth").start_server(port, expected_state, function() end)
  local response = S.request(port, request)
  server:close()
  return response
end

function S.roundtrip(expected_state, request)
  local result
  local port = S.free_port()
  local server = require("spoil.oauth").start_server(port, expected_state, function(r) result = r end)
  local response = S.request(port, request)

  assert(vim.wait(2000, function() return result ~= nil end), "callback timed out")
  server:close()
  return { result = result, response = response }
end

return S
