-- Shared harness for offline mini.test specs.
local H = {}

function H.new_child()
  return MiniTest.new_child_neovim()
end

function H.restart(child)
  child.restart({ "-u", "scripts/minimal_init.lua" })
  child.lua([[
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.fn.setenv("XDG_DATA_HOME", root)
    _G.spoil_test_root = root
    _G.Support = dofile("tests/support.lua")
  ]])
end

function H.cleanup(child)
  if child.is_running() then
    pcall(child.lua, 'vim.fn.delete(_G.spoil_test_root, "rf")')
  end
end

--- Options for `MiniTest.new_set()` with a fresh child per case.
function H.setup(child)
  return {
    hooks = {
      pre_case = function() H.restart(child) end,
      post_case = function() H.cleanup(child) end,
      post_once = child.stop,
    },
  }
end

return H
