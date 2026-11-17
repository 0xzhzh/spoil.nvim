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

local function ensure_data_dir()
  local dir = data_dir()
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p", private_dir_mode)
  end
  return dir
end

--- Write a file readable only by the current user (0600).
--- Opens with `0600` so a newly created file is never briefly world-readable,
--- then chmods to tighten files left behind by older versions.
local function write_private(path, contents)
  local fd, open_err = vim.uv.fs_open(path, "w", private_file_mode)
  if not fd then
    error(("failed to open %s for writing: %s"):format(path, open_err))
  end

  local offset = 0
  while offset < #contents do
    local written, write_err = vim.uv.fs_write(fd, contents, offset)
    if not written then
      vim.uv.fs_close(fd)
      error(("failed to write %s: %s"):format(path, write_err))
    end
    offset = offset + written
  end
  vim.uv.fs_close(fd)

  pcall(vim.uv.fs_chmod, path, private_file_mode)
end

local function write_json(path, value)
  write_private(path, vim.fn.json_encode(value) .. "\n")
end

function M.load_credentials()
  local path = data_dir("credentials.json")
  local ok, data = pcall(vim.fn.readfile, path)
  if not ok or not data or #data == 0 then
    return nil
  end
  local ok2, decoded = pcall(vim.fn.json_decode, table.concat(data, "\n"))
  if not ok2 then
    return nil
  end
  return decoded
end

function M.save_credentials(client_id)
  ensure_data_dir()
  write_json(data_dir("credentials.json"), { client_id = client_id })
end

function M.load_tokens()
  local path = data_dir("tokens.json")
  local ok, data = pcall(vim.fn.readfile, path)
  if not ok or not data or #data == 0 then
    return nil
  end
  local ok2, decoded = pcall(vim.fn.json_decode, table.concat(data, "\n"))
  if not ok2 then
    return nil
  end
  return decoded
end

function M.save_tokens(tokens)
  ensure_data_dir()
  write_json(data_dir("tokens.json"), tokens)
end

function M.is_authorized()
  return M.load_tokens() ~= nil
end

function M.clear_tokens()
  local path = data_dir("tokens.json")
  if vim.fn.filereadable(path) == 1 then
    os.remove(path)
  end
end

function M.clear_all()
  for _, name in ipairs({ "credentials.json", "tokens.json" }) do
    local path = data_dir(name)
    if vim.fn.filereadable(path) == 1 then
      os.remove(path)
    end
  end
end

return M
