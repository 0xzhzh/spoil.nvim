local M = {}
local E = require("spoil.error")
local views = {}
local states = {}
local cache = {}

function M.register_view(name, view)
  views[name] = view
end

M.register_view("playlists", require("spoil.explorer.playlists"))
M.register_view("tracks", require("spoil.explorer.tracks"))

local function get_state()
  return states[vim.api.nvim_get_current_buf()]
end

local function current_view()
  local s = get_state()
  if not s or #s.stack == 0 then return nil end
  return s.stack[#s.stack]
end

local load_view

local function cache_key(name, ctx)
  return name .. ":" .. ((ctx and ctx.playlist_id) or "")
end

local function items_of(data)
  if type(data) ~= "table" then return {} end
  return data.items or {}
end

local function render(buf, view)
  local vd = views[view.name]
  if not vd then return end

  local lines = {}
  for _, item in ipairs(view.items) do
    table.insert(lines, vd.render(item))
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.bo[buf].filetype = vd.filetype

  local cursor = math.min(math.max(view.cursor, 1), #lines)
  if #lines > 0 then
    vim.api.nvim_win_set_cursor(0, { cursor, 0 })
  end
end

local function apply_keymaps(buf, view)
  local s = get_state()
  if not s then return end

  if s._keymap_keys then
    for _, key in ipairs(s._keymap_keys) do
      pcall(vim.api.nvim_buf_del_keymap, buf, "n", key)
    end
  end

  local keys = {}
  local vd = views[view.name]

  local ctx = {
    push_view = function(name, c)
      local s2 = get_state()
      if not s2 then return end
      if name == "tracks" then
        local pid = c and c.playlist_id
        if not pid then
          local p = M.get_selected_playlist()
          if p then pid = p.id end
        end
        if pid then
          return M.open_playlist(pid)
        end
      end
      if not views[name] then return E.notify(E.unknown_view(name)) end
      local new_view = { name = name, items = {}, cursor = 1, context = c or {} }
      table.insert(s2.stack, new_view)
      load_view(buf, new_view)
    end,
    pop_view = function()
      local s2 = get_state()
      if not s2 then return end
      if #s2.stack <= 1 then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
        return
      end
      table.remove(s2.stack)
      local prev = s2.stack[#s2.stack]
      render(buf, prev)
      apply_keymaps(buf, prev)
    end,
    close = function()
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end,
    refresh = function()
      local v = current_view()
      if v then load_view(buf, v) end
    end,
    selected_item = function()
      local v = current_view()
      if not v or not v.items or #v.items == 0 then return nil end
      local line = vim.api.nvim_win_get_cursor(0)[1]
      local idx = math.min(math.max(line, 1), #v.items)
      return v.items[idx]
    end,
  }

  for _, km in ipairs(vd.keymaps or {}) do
    local key = km[1]
    local fn = km[2]
    pcall(vim.keymap.set, "n", key, function() fn(current_view(), ctx) end, { buffer = buf, silent = true, noremap = true })
    table.insert(keys, key)
  end

  s._keymap_keys = keys
end

--- Render a view from cache immediately (if present), then fetch fresh data
--- in the background and re-render. Stale-while-revalidate.
load_view = function(buf, view)
  local vd = views[view.name]
  if not vd then return end

  local key = cache_key(view.name, view.context)
  local cached = cache[key]
  if cached then
    view.items = cached
  end
  render(buf, view)
  apply_keymaps(buf, view)

  vd.fetch(view.context, function(err, data)
    if err then
      E.notify(err)
      return
    end
    local items = items_of(data)
    cache[key] = items
    view.items = items
    local s = states[buf]
    if s and vim.api.nvim_buf_is_valid(buf) and s.stack[#s.stack] == view then
      render(buf, view)
    end
  end)
end

local function open_view(uri, view_name, context)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)

  vim.bo[buf].bufhidden = "wipe"
  vim.wo.cursorline = true
  vim.wo.number = false
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, uri)

  local s = { stack = {}, _keymap_keys = nil, uri = uri }
  states[buf] = s

  local group = vim.api.nvim_create_augroup("spoil_explorer_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = buf,
    callback = function()
      local v = current_view()
      if v then v.cursor = vim.api.nvim_win_get_cursor(0)[1] end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function() states[buf] = nil end,
  })

  local view = { name = view_name, items = {}, cursor = 1, context = context or {} }
  table.insert(s.stack, view)
  load_view(buf, view)
end

function M.open_playlists()
  open_view("spoil://playlists", "playlists", {})
end

function M.open_playlist(id)
  if not id or id == "" then
    E.notify(E.no_playlist_selected())
    return
  end
  open_view("spoil://playlist/" .. id, "tracks", { playlist_id = id })
end

function M.open()
  return M.open_playlists()
end

function M.get_selected_item()
  local s = get_state()
  if not s or not s.stack or #s.stack == 0 then return nil end
  local v = s.stack[#s.stack]
  if not v or not v.items or type(v.items) ~= "table" or #v.items == 0 then return nil end
  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, 0)
  local idx = (ok and cursor and cursor[1]) or v.cursor or 1
  if type(idx) ~= "number" or idx < 1 then idx = 1 end
  if idx > #v.items then idx = #v.items end
  return v.items[idx]
end

function M.get_selected_playlist()
  local p = M.get_selected_item()
  if p and type(p.id) == "string" then return p end
  return nil
end

return M
