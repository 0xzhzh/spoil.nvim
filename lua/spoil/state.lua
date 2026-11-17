local M = {}

local private_file_mode = tonumber("600", 8)
local private_dir_mode = tonumber("700", 8)

local function data_dir(file)
  if file then
    return vim.fs.joinpath(vim.fn.stdpath("data"), "spoil", file)
  else
    return vim.fs.joinpath(vim.fn.stdpath("data"), "spoil")
  end
end

local function mkdir_p(path)
  local stat, stat_err = vim.uv.fs_stat(path)
  if stat then
    if stat.type == "directory" then return true end
    return nil, ("%s exists and is not a directory"):format(path)
  end
  if stat_err and not stat_err:find("ENOENT", 1, true) then
    return nil, stat_err
  end

  local parent = vim.fs.dirname(path)
  if parent and parent ~= path then
    local ok, err = mkdir_p(parent)
    if not ok then return nil, err end
  end

  local made, mkdir_err = vim.uv.fs_mkdir(path, private_dir_mode)
  if not made then
    -- Another process may have created it between the stat and mkdir.
    stat = vim.uv.fs_stat(path)
    if stat and stat.type == "directory" then return true end
    return nil, mkdir_err
  end
  return true
end

local function ensure_data_dir()
  local dir = data_dir()
  local ok, err = mkdir_p(dir)
  if not ok then return nil, err end
  return dir
end

--- Write a file readable only by the current user (0600).
--- Opens with `0600` so a newly created file is never briefly world-readable,
--- then chmods to tighten files left behind by older versions.
---@return boolean|nil ok
---@return string|nil err
local function write_private(path, contents)
  local fd, open_err = vim.uv.fs_open(path, "w", private_file_mode)
  if not fd then
    return nil, ("failed to open %s for writing: %s"):format(path, open_err)
  end

  local offset = 0
  while offset < #contents do
    local written, write_err = vim.uv.fs_write(fd, contents, offset)
    if not written or written == 0 then
      vim.uv.fs_close(fd)
      pcall(vim.uv.fs_unlink, path)
      return nil, ("failed to write %s: %s"):format(path, write_err or "no progress")
    end
    offset = offset + written
  end
  vim.uv.fs_close(fd)

  pcall(vim.uv.fs_chmod, path, private_file_mode)
  return true
end

local function write_json(path, value)
  return write_private(path, vim.json.encode(value) .. "\n")
end

local function read_file(path)
  local fd, open_err = vim.uv.fs_open(path, "r", 0)
  if not fd then return nil, open_err end

  local stat, stat_err = vim.uv.fs_fstat(fd)
  if not stat then
    vim.uv.fs_close(fd)
    return nil, stat_err
  end

  local data, read_err = vim.uv.fs_read(fd, stat.size, 0)
  vim.uv.fs_close(fd)
  if not data then return nil, read_err end
  return data
end

local function load_json(name)
  local data = read_file(data_dir(name))
  if not data or data == "" then return nil end
  local ok, decoded = pcall(vim.json.decode, data)
  if not ok then return nil end
  return decoded
end

function M.load_credentials()
  return load_json("credentials.json")
end

function M.save_credentials(client_id)
  local dir, dir_err = ensure_data_dir()
  if not dir then return nil, dir_err end
  return write_json(data_dir("credentials.json"), { client_id = client_id })
end

function M.load_tokens()
  return load_json("tokens.json")
end

function M.save_tokens(tokens)
  local dir, dir_err = ensure_data_dir()
  if not dir then return nil, dir_err end
  return write_json(data_dir("tokens.json"), tokens)
end

function M.is_authorized()
  return M.load_tokens() ~= nil
end

local function remove_file(path)
  local stat = vim.uv.fs_stat(path)
  if stat and stat.type == "file" then
    vim.uv.fs_unlink(path)
  end
end

function M.clear_tokens()
  remove_file(data_dir("tokens.json"))
end

function M.clear_all()
  for _, name in ipairs({ "credentials.json", "tokens.json" }) do
    remove_file(data_dir(name))
  end
end

return M
