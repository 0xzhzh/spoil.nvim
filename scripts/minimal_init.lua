-- Minimal startup file for mini.test runs and child Neovim processes.
local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)

local mini = vim.env.MINI_NVIM or vim.fs.joinpath(root, "deps", "mini.nvim")
vim.opt.runtimepath:append(mini)

if #vim.api.nvim_list_uis() == 0 then
  require("mini.test").setup()
end
