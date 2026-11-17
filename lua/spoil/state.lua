local M = {}

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
    vim.fn.mkdir(dir, "p")
  end
  return dir
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
  local path = data_dir("credentials.json")
  vim.fn.writefile({ vim.fn.json_encode({ client_id = client_id }) }, path)
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
  local path = data_dir("tokens.json")
  vim.fn.writefile({ vim.fn.json_encode(tokens) }, path)
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
