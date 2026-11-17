local M = {}
local E = require("spoil.error")
local views = {}
local states = {}
local cache = {}
local saved_window_opts = {}

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

--- Find the Spoil view to read a selection from. Prefer the current buffer; if
--- invoked from elsewhere, use the only visible Spoil view (None if ambiguous).
local function visible_spoil_buf()
  local current = vim.api.nvim_get_current_buf()
  if states[current] then return current end

  local found
  for buf in pairs(states) do
    if vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) > 0 then
      if found then return nil end
      found = buf
    end
  end
  return found
end

local function window_for_buffer(buf)
  local current = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(current) == buf then return current end
  return vim.fn.win_findbuf(buf)[1]
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

  if #lines > 0 then
    -- Only in windows showing this buffer; window 0 may be an unrelated buffer.
    local line = math.min(math.max(view.cursor, 1), #lines)
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      vim.api.nvim_win_set_cursor(win, { line, 0 })
    end
  end
end

local function view_uri(view)
  if view.name == "tracks" and view.context and view.context.playlist_id then
    return "spoil://playlist/" .. view.context.playlist_id
  end
  return "spoil://" .. view.name
end

local function set_buffer_uri(buf, view)
  local uri = view_uri(view)
  if vim.api.nvim_buf_get_name(buf) == uri then return end
  pcall(vim.api.nvim_buf_set_name, buf, uri)
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
      if not views[name] then return E.notify(E.unknown_view(name)) end

      c = c or {}
      if name == "tracks" then
        local pid = c.playlist_id
        if not pid then
          local p = M.get_selected_playlist()
          if p then pid = p.id end
        end
        if not pid then return E.notify(E.no_playlist_selected()) end
        c = vim.tbl_extend("force", c, { playlist_id = pid })
      end

      local parent = s2.stack[#s2.stack]
      if parent then parent.cursor = vim.api.nvim_win_get_cursor(0)[1] end

      local new_view = { name = name, items = {}, cursor = 1, context = c }
      table.insert(s2.stack, new_view)
      set_buffer_uri(buf, new_view)
      load_view(buf, new_view)
    end,
    pop_view = function()
      local s2 = get_state()
      if not s2 then return end
      if #s2.stack <= 1 then
        local v = s2.stack[1]
        if v and v.name == "tracks" then return M.open_playlists() end
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
        return
      end
      table.remove(s2.stack)
      local prev = s2.stack[#s2.stack]
      set_buffer_uri(buf, prev)
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
    pcall(
      vim.keymap.set,
      "n",
      key,
      function() fn(current_view(), ctx) end,
      { buffer = buf, silent = true, noremap = true }
    )
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

local function save_window_opts(win)
  if saved_window_opts[win] then return end
  saved_window_opts[win] = {
    cursorline = vim.wo[win].cursorline,
    number = vim.wo[win].number,
  }
end

local function restore_window_opts(win)
  local saved = saved_window_opts[win]
  if not saved then return end
  saved_window_opts[win] = nil

  if not vim.api.nvim_win_is_valid(win) then return end
  vim.wo[win].cursorline = saved.cursorline
  vim.wo[win].number = saved.number
end

local function maybe_restore_window_opts(win)
  if not vim.api.nvim_win_is_valid(win) then
    saved_window_opts[win] = nil
    return
  end
  if not states[vim.api.nvim_win_get_buf(win)] then restore_window_opts(win) end
end

local window_group = vim.api.nvim_create_augroup("spoil_explorer_windows", { clear = true })

vim.api.nvim_create_autocmd("BufEnter", {
  group = window_group,
  callback = function()
    local win = vim.api.nvim_get_current_win()
    if saved_window_opts[win] then
      vim.schedule(function() maybe_restore_window_opts(win) end)
    end
  end,
})

vim.api.nvim_create_autocmd("WinClosed", {
  group = window_group,
  callback = function(args)
    local win = tonumber(args.match)
    if win then saved_window_opts[win] = nil end
  end,
})

local function open_view(uri, view_name, context)
  local win = vim.api.nvim_get_current_win()
  save_window_opts(win)

  -- Reuse an existing buffer for this URI instead of hitting E95.
  local existing = vim.fn.bufnr(uri)
  if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) and states[existing] then
    vim.api.nvim_set_current_buf(existing)
    vim.wo[win].cursorline = true
    vim.wo[win].number = false
    local s = states[existing]
    if #s.stack > 0 then load_view(existing, s.stack[#s.stack]) end
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)

  vim.bo[buf].bufhidden = "wipe"
  vim.wo[win].cursorline = true
  vim.wo[win].number = false
  vim.bo[buf].modifiable = false
  local named = pcall(vim.api.nvim_buf_set_name, buf, uri)
  if not named then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    restore_window_opts(win)
    return E.notify(E.new("Buffer already exists: " .. uri))
  end

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
    callback = function()
      states[buf] = nil
      vim.schedule(function() pcall(vim.api.nvim_del_augroup_by_id, group) end)
    end,
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
  local buf = visible_spoil_buf()
  local s = buf and states[buf]
  if not s or not s.stack or #s.stack == 0 then return nil end
  local v = s.stack[#s.stack]
  if not v or not v.items or type(v.items) ~= "table" or #v.items == 0 then return nil end

  local win = window_for_buffer(buf)
  if not win then return nil end
  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
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

function M.get_selected_track()
  local item = M.get_selected_item()
  if not item then return nil end
  local track = item.item or item.track
  if track and type(track.uri) == "string" then return track end
  return nil
end

return M
