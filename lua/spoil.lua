local config = require("spoil.config")
local command = require("spoil.command")
local format = require("spoil.format")
local notify = require("spoil.notify")
local M = require("spoil.user_api")

function M.setup(opts)
  config.setup(opts)
  notify.setup(config.options.notify)
  command.setup()
  format.define_highlights()
end

return M
