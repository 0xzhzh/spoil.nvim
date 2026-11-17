--- PKCE verifier/challenge and OAuth state generation.
local M = {}

-- Encode raw bytes as base64url (RFC 4648 §5), without padding.
local function base64url_encode(bytes)
  return (vim.base64.encode(bytes):gsub("+", "-"):gsub("/", "_"):gsub("=+$", ""))
end

-- Prefer libuv's system CSPRNG; fall back to /dev/urandom for older luv builds.
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

--- Generate a PKCE code verifier (RFC 7636 allows 43-128 characters).
---@return string
function M.code_verifier()
  local verifier = base64url_encode(random_bytes(48))
  if #verifier < 43 or #verifier > 128 then
    error("failed to generate a valid PKCE code verifier")
  end
  return verifier
end

--- Compute the S256 code challenge for a verifier.
---@param verifier string
---@return string
function M.code_challenge(verifier)
  local hex = vim.fn.sha256(verifier)
  local digest = hex:gsub("%x%x", function(pair)
    return string.char(tonumber(pair, 16))
  end)
  return base64url_encode(digest)
end

--- Generate the OAuth state value echoed back by Spotify.
---@return string
function M.oauth_state()
  return base64url_encode(random_bytes(32))
end

return M
