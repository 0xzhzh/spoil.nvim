local H = dofile("tests/helpers.lua")
local child = H.new_child()
local T = MiniTest.new_set(H.setup(child))
local eq = MiniTest.expect.equality

T["formats now-playing items"] = function()
  local r = child.lua_get([[(function()
    local config = require("spoil.config")
    local user = require("spoil.user_api")

    local item = { name = "Song", artists = { { name = "Artist" } }, album = { name = "Album" } }
    local defaults = {
      nil_item = user.format_status(nil),
      full = user.format_status(item),
      partial = user.format_status({ artists = { { name = "Artist" } } }),
      empty = user.format_status({}),
    }

    config.options.statusline = {
      sep = " - ",
      fmt = { "title", "album", "artist" },
      not_playing = "nothing",
      interval = 5000,
    }
    local custom = {
      full = user.format_status(item),
      nil_item = user.format_status(nil),
      empty = user.format_status({}),
    }

    return { defaults = defaults, custom = custom }
  end)()]])

  eq(r.defaults.nil_item, "")
  eq(r.defaults.full, "Artist | Song")
  eq(r.defaults.partial, "Artist")
  eq(r.defaults.empty, "")
  eq(r.custom.full, "Song - Album - Artist")
  eq(r.custom.nil_item, "nothing")
  eq(r.custom.empty, "nothing")
end

T["notify_now_playing handles missing artists and episodes"] = function()
  local r = child.lua_get([[(function()
    local api = require("spoil.api")
    local user = require("spoil.user_api")
    local notify = require("spoil.notify")
    local messages = {}
    notify.backend = function(msg) messages[#messages + 1] = msg end

    local function run(item)
      api.now_playing = function(_, cb) cb(nil, { item = item }) end
      user.notify_now_playing()
      return messages[#messages]
    end

    return {
      track = run({ name = "Song", artists = { { name = "Artist" } } }),
      episode = run({ name = "Episode", show = { name = "Show" } }),
      empty_artists = run({ name = "Local", artists = {} }),
      missing_artists = run({ name = "Local" }),
    }
  end)()]])

  eq(r.track, "Artist | Song")
  eq(r.episode, "Show | Episode")
  eq(r.empty_artists, "Local")
  eq(r.missing_artists, "Local")
end

return T
