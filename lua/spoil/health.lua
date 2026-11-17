--- `:checkhealth spoil` — environment, config, auth, and data-dir checks.
local config = require("spoil.config")
local state = require("spoil.state")

local M = {}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function data_dir()
  return vim.fs.joinpath(vim.fn.stdpath("data"), "spoil")
end

local function is_windows()
  return package.config:sub(1, 1) == "\\"
end

local function check_neovim()
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim >= 0.10")
  else
    vim.health.error("Neovim >= 0.10 is required", {
      "Upgrade Neovim: https://github.com/neovim/neovim/releases",
    })
  end
end

local function check_curl()
  if vim.fn.executable("curl") ~= 1 then
    vim.health.error("curl is not executable", {
      "curl is required for all Spotify API requests",
      "Install curl and make sure it is on $PATH",
    })
    return
  end

  local ok, result = pcall(function() return vim.system({ "curl", "--version" }, { text = true }):wait() end)
  local version = ok and trim(result.stdout or ""):match("^([^\n]+)") or nil
  if ok and result.code == 0 and version and version ~= "" then
    vim.health.ok("curl found: " .. version)
  else
    vim.health.warn("curl is present but `curl --version` failed", {
      "Reinstall curl and make sure it runs correctly",
    })
  end
end

local function resolve_client_id()
  local id = config.options.auth.client_id
  if id and id ~= "" then return id, "config" end
  local creds = state.load_credentials()
  if creds and creds.client_id and creds.client_id ~= "" then
    return creds.client_id, "credentials.json"
  end
  return nil
end

local function check_config()
  local _, source = resolve_client_id()
  if source then
    vim.health.ok("Spotify client ID configured (from " .. source .. ")")
  else
    vim.health.warn("No Spotify client ID configured", {
      "Set `auth.client_id` in your spoil.nvim config, or run `:Spoil login` to be prompted",
    })
  end

  local port = config.options.auth.port
  if type(port) == "number" and port >= 1 and port <= 65535 then
    vim.health.info(
      ("OAuth redirect URI: http://127.0.0.1:%d/callback (must match the Spotify app's Redirect URI)"):format(port)
    )
  else
    vim.health.error("Invalid `auth.port`: " .. vim.inspect(port), {
      "Set `auth.port` to an integer between 1 and 65535",
    })
  end

  local scopes = config.options.auth.scopes
  if type(scopes) == "table" and #scopes > 0 then
    vim.health.ok(("%d OAuth scopes configured"):format(#scopes))
  else
    vim.health.error("No OAuth scopes configured", {
      "Set `auth.scopes` in your config",
    })
  end
end

local function check_auth()
  local tokens = state.load_tokens()
  if not tokens then
    vim.health.warn("Not authenticated", {
      "Run `:Spoil login` to sign in",
    })
    return
  end

  if tokens.access_token and tokens.access_token ~= "" then
    vim.health.ok("Access token present")
  else
    vim.health.error("Tokens file has no access token", {
      "Run `:Spoil logout` and then `:Spoil login` to sign in again",
    })
  end

  if tokens.refresh_token and tokens.refresh_token ~= "" then
    vim.health.ok("Refresh token present")
  else
    vim.health.warn("No refresh token stored", {
      "You may need to re-authenticate when the access token expires",
    })
  end
end

local function check_file_permissions(name)
  if is_windows() then return end

  local path = vim.fs.joinpath(data_dir(), name)
  if vim.fn.filereadable(path) ~= 1 then return end

  local perm = vim.fn.getfperm(path)
  if not perm or #perm < 9 then return end

  -- Only group/other permission bits matter; owner bits are expected.
  if perm:sub(4, 9) ~= "------" then
    vim.health.warn(("%s is accessible by other users (%s); expected 0600"):format(name, perm), {
      ("Run `chmod 600 %s`"):format(path),
    })
  else
    vim.health.ok(name .. " permissions are private (" .. perm .. ")")
  end
end

local function check_data_dir()
  local dir = data_dir()
  vim.health.info("Data directory: " .. dir)

  if vim.fn.isdirectory(dir) == 0 then
    vim.health.info("Data directory does not exist yet; it will be created on first save")
    return
  end

  local probe = vim.fs.joinpath(dir, ".health-probe")
  local ok, err = pcall(vim.fn.writefile, { "" }, probe)
  if ok then
    os.remove(probe)
    vim.health.ok("Data directory is writable")
  else
    vim.health.error("Data directory is not writable", {
      tostring(err),
      "Check ownership and permissions of " .. dir,
    })
  end

  check_file_permissions("tokens.json")
  check_file_permissions("credentials.json")
end

function M.check()
  vim.health.start("spoil.nvim")
  check_neovim()

  vim.health.start("spoil.nvim: dependencies")
  check_curl()

  vim.health.start("spoil.nvim: configuration")
  check_config()

  vim.health.start("spoil.nvim: authentication")
  check_auth()

  vim.health.start("spoil.nvim: data directory")
  check_data_dir()
end

return M
