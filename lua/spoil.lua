local config = require("spoil.config")
local command = require("spoil.command")
local notify = require("spoil.notify")
local M = require("spoil.user_api")

function M.setup(opts)
  config.setup(opts)
  notify.setup(config.options.notify)
  command.setup()
end

return M
