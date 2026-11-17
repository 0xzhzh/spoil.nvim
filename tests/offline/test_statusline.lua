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

T["keeps last item on transient errors and stops polling when unauthorized"] = function()
  local r = child.lua_get([[(function()
    local api = require("spoil.api")
    local user = require("spoil.user_api")
    local config = require("spoil.config")
    config.options.statusline = {
      sep = " | ",
      fmt = { "artist", "title" },
      not_playing = "",
      interval = 10,
      timeout = 1,
    }

    local calls, mode = 0, "item"
    api.now_playing = function(_, cb)
      calls = calls + 1
      if mode == "item" then
        cb(nil, { item = { name = "Song", artists = { { name = "Artist" } } } })
      elseif mode == "blip" then
        cb({ msg = "blip", status = 500 })
      else
        cb({ msg = "auth", status = 401 })
      end
    end
    user.is_authorized = function() return false end

    local initial = user.statusline()
    local got = vim.wait(500, function() return user.statusline() == "Artist | Song" end)
    local with_item = user.statusline()

    local before = calls
    mode = "blip"
    local polled = vim.wait(500, function() return calls > before end)
    local after_blip = user.statusline()

    before, mode = calls, "auth"
    local disabled = vim.wait(500, function() return calls > before and user.statusline() == "" end)
    local after_auth = user.statusline()
    local after_calls = calls
    for _ = 1, 20 do
      user.statusline()
    end

    return {
      initial = initial,
      got = got,
      with_item = with_item,
      polled = polled,
      after_blip = after_blip,
      disabled = disabled,
      after_auth = after_auth,
      churn = calls - after_calls,
    }
  end)()]])

  eq(r.initial, "")
  eq(r.got, true)
  eq(r.with_item, "Artist | Song")
  eq(r.polled, true)
  eq(r.after_blip, "Artist | Song")
  eq(r.disabled, true)
  eq(r.after_auth, "")
  eq(r.churn, 0)
end

return T
