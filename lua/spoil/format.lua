local M = {}

local highlight_links = {
  SpoilPlaylistName = "Title",
  SpoilPlaylistCount = "Number",
  SpoilPlaylistVisibility = "Comment",
  SpoilPlaylistOwner = "Identifier",
  SpoilPlaylistCollaborators = "Special",
  SpoilTrackTitle = "Title",
  SpoilTrackArtist = "Identifier",
  SpoilTrackAlbum = "Comment",
  SpoilTrackDuration = "Number",
  SpoilMuted = "Comment",
}

function M.define_highlights()
  for name, link in pairs(highlight_links) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
end

M.define_highlights()

local highlight_group = vim.api.nvim_create_augroup("spoil_highlights", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", {
  group = highlight_group,
  callback = M.define_highlights,
})

local function display_width(text)
  return vim.fn.strdisplaywidth(text)
end

local function fit(text, max_width, ellipsis)
  if not max_width or display_width(text) <= max_width then return text end
  if max_width <= 0 then return "" end

  local ellipsis_width = display_width(ellipsis)
  if max_width < ellipsis_width then return vim.fn.strcharpart(ellipsis, 0, max_width) end
  if max_width == ellipsis_width then return ellipsis end

  local out = {}
  local used = 0
  local limit = max_width - ellipsis_width
  for i = 0, vim.fn.strchars(text) - 1 do
    local char = vim.fn.strcharpart(text, i, 1)
    local width = display_width(char)
    if used + width > limit then break end
    out[#out + 1] = char
    used = used + width
  end
  return table.concat(out) .. ellipsis
end

local function cell_of(value)
  if type(value) == "table" then
    return {
      text = value.text == nil and "" or tostring(value.text),
      hl = value.hl,
      align = value.align,
    }
  end
  return { text = value == nil and "" or tostring(value) }
end

local function max_width_for(opts, column)
  if type(opts.max_width) == "table" then return opts.max_width[column] end
  return opts.max_width
end

--- Format rows of cells into aligned lines and byte-based highlight ranges.
---@param rows table[][] Each cell is a string or `{ text, hl?, align? }`.
---@param opts? { gap?: integer, max_width?: integer|integer[], ellipsis?: string }
---@return string[] lines
---@return { line: integer, start_col: integer, end_col: integer, hl: string }[] highlights
function M.table(rows, opts)
  opts = opts or {}
  local gap = opts.gap or 2
  local ellipsis = opts.ellipsis or "…"
  local widths = {}
  local columns = 0

  for _, row in ipairs(rows) do
    columns = math.max(columns, #row)
    for column, value in ipairs(row) do
      local text = fit(cell_of(value).text, max_width_for(opts, column), ellipsis)
      widths[column] = math.max(widths[column] or 0, display_width(text))
    end
  end

  local lines, highlights = {}, {}
  for line_index, row in ipairs(rows) do
    local cells = {}
    local last = 0
    for column = 1, columns do
      local cell = cell_of(row[column])
      cell.text = fit(cell.text, max_width_for(opts, column), ellipsis)
      cells[column] = cell
      if cell.text ~= "" or cell.hl then last = column end
    end

    local line = {}
    local length = 0
    for column = 1, last do
      local cell = cells[column]
      local width = display_width(cell.text)
      local padding = widths[column] - width
      if cell.align == "right" then
        local spaces = string.rep(" ", padding)
        line[#line + 1] = spaces
        length = length + #spaces
      end

      local start_col = length
      line[#line + 1] = cell.text
      length = length + #cell.text
      if cell.hl and cell.text ~= "" then
        highlights[#highlights + 1] = {
          line = line_index - 1,
          start_col = start_col,
          end_col = length,
          hl = cell.hl,
        }
      end

      if column < last then
        if cell.align ~= "right" then
          local spaces = string.rep(" ", padding)
          line[#line + 1] = spaces
          length = length + #spaces
        end
        line[#line + 1] = string.rep(" ", gap)
        length = length + gap
      end
    end

    lines[line_index] = table.concat(line)
  end

  return lines, highlights
end

return M
