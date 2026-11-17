local M = {}
local E = require("spoil.error")
local views = {}
local states = {}
local buffers = {}
local cache = {}
local saved_window_opts = {}
local extmark_ns = vim.api.nvim_create_namespace("spoil.explorer")

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
  return s and s.view
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

local function buf_for_uri(uri)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == uri then return buf end
  end
  return -1
end

local load_view
local open_view

local function spec_for_uri(uri)
  local path = uri:match("^spoil://(.+)$")
  if path == "playlist" then
    return { name = "playlists", context = {} }
  end
  local id = path and path:match("^playlist/([^?]+)")
  if id and id ~= "" then
    return { name = "tracks", context = { playlist_id = vim.uri_decode(id) } }
  end
end

local function uri_for(name, context)
  if name == "playlists" then return "spoil://playlist" end
  if name == "tracks" then
    local id = context and context.playlist_id
    if not id then return nil end
    return "spoil://playlist/" .. id
  end
  return "spoil://" .. name
end

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

  local lines, highlights = {}, {}
  if vd.format then
    local formatted = vd.format(view.items)
    lines = formatted.lines or {}
    highlights = formatted.highlights or {}
  else
    for _, item in ipairs(view.items) do
      table.insert(lines, vd.render(item))
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, extmark_ns, 0, -1)
  for _, mark in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(buf, extmark_ns, mark.line, mark.start_col, {
      end_col = mark.end_col,
      hl_group = mark.hl,
    })
  end

  vim.bo[buf].filetype = vd.filetype

  if #lines > 0 then
    -- Only in windows showing this buffer; window 0 may be an unrelated buffer.
    local line = math.min(math.max(view.cursor, 1), #lines)
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      vim.api.nvim_win_set_cursor(win, { line, 0 })
    end
  end
end

local function apply_keymaps(buf, view)
  local s = states[buf]
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
      local state = states[buf]
      if not state then return end
      if not views[name] then
        E.notify(E.unknown_view(name))
        return
      end

      c = c or {}
      if name == "tracks" then
        local pid = c.playlist_id
        if not pid then
          local p = M.get_selected_playlist()
          if p then pid = p.id end
        end
        if not pid then
          E.notify(E.no_playlist_selected())
          return
        end
        c = vim.tbl_extend("force", c, { playlist_id = pid })
      end

      local target = uri_for(name, c)
      if not target or target == state.uri then return end

      local win = window_for_buffer(buf) or vim.api.nvim_get_current_win()
      state.view.cursor = vim.api.nvim_win_get_cursor(win)[1]
      open_view(target, name, c, state.uri)
    end,
    pop_view = function()
      local state = states[buf]
      if not state then return end
      local parent_uri = state.parent_uri
      if parent_uri then
        local spec = spec_for_uri(parent_uri)
        if spec then
          open_view(parent_uri, spec.name, spec.context)
          return
        end
      end
      if state.view and state.view.name == "tracks" then return M.open_playlists() end
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end,
    close = function()
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end,
    refresh = function()
      local state = states[buf]
      if state and state.view then load_view(buf, state.view) end
    end,
    selected_item = function()
      local state = states[buf]
      local v = state and state.view
      if not v or not v.items or #v.items == 0 then return nil end
      local win = window_for_buffer(buf)
      if not win then return nil end
      local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
      local idx = (ok and cursor and cursor[1]) or v.cursor or 1
      idx = math.min(math.max(idx, 1), #v.items)
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
      function() fn(states[buf] and states[buf].view, ctx) end,
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
    if s and vim.api.nvim_buf_is_valid(buf) and s.view == view then
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

local function prepare_window(win)
  save_window_opts(win)
  vim.wo[win].cursorline = true
  vim.wo[win].number = false
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

local function init_state(buf, uri, parent_uri)
  local s = states[buf]
  if s then
    s.uri = uri
    if parent_uri ~= nil then s.parent_uri = parent_uri end
    return s
  end

  s = { uri = uri, parent_uri = parent_uri, _keymap_keys = nil }
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
      local state = states[buf]
      if state and buffers[state.uri] == buf then buffers[state.uri] = nil end
      states[buf] = nil
      vim.schedule(function() pcall(vim.api.nvim_del_augroup_by_id, group) end)
    end,
  })

  return s
end

local function load_uri_into(buf, uri, parent_uri)
  local spec = spec_for_uri(uri)
  if not spec then return end

  local s = init_state(buf, uri, parent_uri)
  s.view = { name = spec.name, items = {}, cursor = 1, context = spec.context }

  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].modifiable = false
  load_view(buf, s.view)
end

open_view = function(uri, view_name, context, parent_uri)
  local existing = buffers[uri]
  if existing and (not vim.api.nvim_buf_is_valid(existing) or not states[existing]) then
    buffers[uri] = nil
    existing = nil
  end
  if not existing then
    local named = buf_for_uri(uri)
    if named ~= -1 and vim.api.nvim_buf_is_valid(named) then existing = named end
  end

  local win = vim.api.nvim_get_current_win()
  if existing then
    prepare_window(win)
    vim.api.nvim_win_set_buf(win, existing)
    local s = states[existing]
    if s then
      if parent_uri ~= nil then s.parent_uri = parent_uri end
      load_view(existing, s.view)
    else
      buffers[uri] = existing
      load_uri_into(existing, uri, parent_uri)
    end
    return existing
  end

  local buf = vim.api.nvim_create_buf(false, true)
  prepare_window(win)
  vim.api.nvim_win_set_buf(win, buf)
  vim.bo[buf].modifiable = false

  local named = pcall(vim.api.nvim_buf_set_name, buf, uri)
  if not named then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    restore_window_opts(win)
    E.notify(E.new("Buffer already exists: " .. uri))
    return
  end

  buffers[uri] = buf
  load_uri_into(buf, uri, parent_uri)
  return buf
end

local uri_group = vim.api.nvim_create_augroup("spoil_explorer_uri", { clear = true })

vim.api.nvim_create_autocmd({ "BufReadCmd", "BufNewFile" }, {
  group = uri_group,
  pattern = "spoil://*",
  callback = function(args)
    local uri = vim.api.nvim_buf_get_name(args.buf)
    if not spec_for_uri(uri) then return end

    local s = states[args.buf]
    if s and s.uri == uri then return end

    local existing = buffers[uri]
    if existing and existing ~= args.buf and vim.api.nvim_buf_is_valid(existing) and states[existing] then
      local win = vim.api.nvim_get_current_win()
      prepare_window(win)
      vim.api.nvim_win_set_buf(win, existing)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(args.buf) then
          pcall(vim.api.nvim_buf_delete, args.buf, { force = true })
        end
      end)
      return
    end

    buffers[uri] = args.buf
    prepare_window(vim.api.nvim_get_current_win())
    load_uri_into(args.buf, uri)
  end,
})

function M.open_playlists()
  open_view("spoil://playlist", "playlists", {})
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
  local v = s and s.view
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
