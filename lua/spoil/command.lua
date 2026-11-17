--- The `:Spoil` user command and its subcommand dispatch.
local user_api = require("spoil.user_api")
local notify = require("spoil.notify")

local M = {}

--- Subcommand table: name -> { desc, run(args) }.
--- `args` is the list of arguments after the subcommand name.
local commands = {
  open_playlists = {
    desc = "Open the playlists view",
    run = function() user_api.open_playlists() end,
  },
  open = {
    desc = "Open a playlist by id or URI",
    run = function(args) user_api.open_playlist(args[1]) end,
  },
  play = {
    desc = "Resume playback",
    run = function() user_api.play() end,
  },
  pause = {
    desc = "Pause playback",
    run = function() user_api.pause() end,
  },
  toggle = {
    desc = "Toggle play/pause",
    run = function() user_api.toggle_playback() end,
  },
  next = {
    desc = "Skip to the next track",
    run = function() user_api.next_track() end,
  },
  now_playing = {
    desc = "Show the currently playing track",
    run = function() user_api.notify_now_playing() end,
  },
  prev = {
    desc = "Go to the previous track",
    run = function() user_api.previous_track() end,
  },
  auth = {
    desc = "Authenticate with Spotify",
    run = function() user_api.auth() end,
  },
  logout = {
    desc = "Clear credentials and tokens",
    run = function() user_api.logout() end,
  },
  search = {
    desc = "Search for songs/albums/artists",
    run = function() notify.error("Spoil: search is not implemented yet") end,
  },
}

commands.previous = commands.prev

function M.dispatch(args)
  local fargs = args.fargs
  if #fargs == 0 then
    return user_api.open_playlists()
  end
  local name = fargs[1]
  local cmd = commands[name]
  if not cmd then
    notify.error("Spoil: unknown command '" .. name .. "'")
    return
  end
  cmd.run(vim.list_slice(fargs, 2))
end

function M.complete(arglead, cmdline, _)
  local words = vim.split(cmdline, "%s+")
  if #words > 2 then return {} end
  local matches = {}
  for name in pairs(commands) do
    if name:sub(1, #arglead) == arglead then table.insert(matches, name) end
  end
  table.sort(matches)
  return matches
end

local registered = false

function M.setup()
  if registered then return end
  registered = true
  vim.api.nvim_create_user_command("Spoil", function(args) M.dispatch(args) end, {
    nargs = "*",
    complete = M.complete,
    desc = "Spoil: Spotify playlist manager",
  })
end

return M
