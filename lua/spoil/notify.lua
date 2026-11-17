--- Notification abstraction.
---
--- All user-facing notifications go through here so the backend can be swapped
--- without touching call sites. Call sites use backend-agnostic opts; `icon` is
--- the canonical option. Each backend translates to its own naming.
local M = {}

local levels = vim.log.levels

--- Fidget names the per-notification icon `annote` (native vim.notify uses `icon`).
local function to_fidget_opts(opts)
  if opts.icon then
    opts.annote = opts.icon
    opts.icon = nil
  end
  return opts
end

local backends = {
  native = function(msg, level, opts)
    vim.notify(msg, level, opts)
  end,
  fidget = function(msg, level, opts)
    require("fidget").notify(msg, level, to_fidget_opts(opts))
  end,
}

--- Backend signature: (msg, level, opts).
M.backend = backends.native

---@param opts? { backend?: string|fun(msg: string, level: integer, opts: table) }
function M.setup(opts)
  if not opts or not opts.backend then return end
  local backend = opts.backend
  if type(backend) == "string" then
    backend = assert(backends[backend], "unknown notify backend: " .. opts.backend)
  end
  M.backend = backend
end

function M.notify(msg, level, opts)
  opts = vim.tbl_extend("force", { group = "spoil.nvim" }, opts or {})
  return M.backend(msg, level, opts)
end

function M.info(msg, opts) return M.notify(msg, levels.INFO, opts) end
function M.warn(msg, opts) return M.notify(msg, levels.WARN, opts) end
function M.error(msg, opts) return M.notify(msg, levels.ERROR, opts) end

return M
