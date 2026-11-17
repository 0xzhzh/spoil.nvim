--- Project test runner with tiered collection.
local function find_files()
  local files = vim.fn.globpath("tests/offline", "**/test_*.lua", true, true)

  if vim.env.SPOIL_TEST_LIVE == "1" then
    vim.list_extend(files, vim.fn.globpath("tests/live", "**/test_*.lua", true, true))
  end
  if vim.env.SPOIL_TEST_MUTATIONS == "1" then
    vim.list_extend(files, vim.fn.globpath("tests/mutation", "**/test_*.lua", true, true))
  end

  table.sort(files)
  return files
end

MiniTest.run({ collect = { find_files = find_files } })
