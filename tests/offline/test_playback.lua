local H = dofile("tests/helpers.lua")
local child = H.new_child()
local T = MiniTest.new_set(H.setup(child))
local eq = MiniTest.expect.equality

T["selects and transfers playback devices"] = function()
  local r = child.lua_get([[(function()
    local api = require("spoil.api")
    local user = require("spoil.user_api")
    local notify = require("spoil.notify")
    local E = require("spoil.error")

    local messages = {}
    notify.backend = function(msg, level) messages[#messages + 1] = { msg = msg, level = level } end
    local transferred
    api.transfer_playback = function(opts, cb)
      transferred = opts
      cb(nil, {})
    end

    api.get_devices = function(_, cb)
      cb(nil, {
        devices = {
          { id = "phone", name = "Phone", type = "Smartphone", is_active = false },
          { id = "laptop", name = "Laptop", type = "Computer", is_active = true },
        },
      })
    end
    local items
    vim.ui.select = function(list, _, on_choice)
      items = list
      on_choice(list[2])
    end
    user.select_device()
    local multiple = { transferred = transferred, items = items, message = messages[#messages] }

    transferred = nil
    vim.ui.select = function(_, _, on_choice) on_choice(nil) end
    user.select_device()
    local cancelled = { transferred = transferred }

    transferred = nil
    api.get_devices = function(_, cb) cb(nil, { devices = { { id = "only", name = "Only" } } }) end
    vim.ui.select = function() error("should not prompt for one device") end
    user.select_device()
    local single = { transferred = transferred }

    transferred = nil
    messages = {}
    api.get_devices = function(_, cb) cb(nil, { devices = {} }) end
    user.select_device()
    local none = { transferred = transferred, message = messages[#messages], expected = E.messages.no_devices }

    messages = {}
    api.get_devices = function(_, cb) cb({ msg = "boom", status = 500 }) end
    user.select_device()
    local failed = { message = messages[#messages] }

    return {
      multiple = multiple,
      cancelled = cancelled,
      single = single,
      none = none,
      failed = failed,
      ERROR = vim.log.levels.ERROR,
    }
  end)()]])

  eq(r.multiple.transferred, { device_id = "laptop", play = false })
  eq(#r.multiple.items, 2)
  eq(r.multiple.items[2].label, "Laptop  (Computer, active)")
  eq(r.multiple.message.msg, "Playback transferred to Laptop")
  eq(r.cancelled.transferred, nil)
  eq(r.single.transferred, { device_id = "only", play = false })
  eq(r.none.transferred, nil)
  eq(r.none.message.msg, "Spoil: " .. r.none.expected)
  eq(r.none.message.level, r.ERROR)
  eq(r.failed.message.msg, "Spoil: boom")
  eq(r.failed.message.level, r.ERROR)
end

T["queues selected tracks"] = function()
  local r = child.lua_get([[(function()
    local api = require("spoil.api")
    local explorer = require("spoil.explorer")
    local user = require("spoil.user_api")
    local notify = require("spoil.notify")
    local E = require("spoil.error")

    local messages = {}
    notify.backend = function(msg, level) messages[#messages + 1] = { msg = msg, level = level } end
    local queued
    api.add_to_queue = function(opts, cb)
      queued = opts
      cb(nil, {})
    end

    user.add_to_queue("spotify:track:abc")
    local success = { queued = queued, message = messages[#messages] }

    messages = {}
    api.add_to_queue = function(_, cb) cb({ msg = "queue full", status = 500 }) end
    user.add_to_queue("spotify:track:abc")
    local failed = { message = messages[#messages] }

    queued, messages = nil, {}
    explorer.get_selected_track = function() return nil end
    user.queue_selected()
    local missing = { queued = queued, message = messages[#messages], expected = E.messages.no_track_selected }

    explorer.get_selected_track = function() return { uri = "spotify:track:xyz" } end
    api.add_to_queue = function(opts, cb)
      queued = opts
      cb(nil, {})
    end
    user.queue_selected()
    local selected = { queued = queued }

    return { success = success, failed = failed, missing = missing, selected = selected, ERROR = vim.log.levels.ERROR }
  end)()]])

  eq(r.success.queued, { uri = "spotify:track:abc" })
  eq(r.success.message.msg, "Added to queue")
  eq(r.failed.message.msg, "Spoil: queue full")
  eq(r.failed.message.level, r.ERROR)
  eq(r.missing.queued, nil)
  eq(r.missing.message.msg, "Spoil: " .. r.missing.expected)
  eq(r.selected.queued, { uri = "spotify:track:xyz" })
end

T["surfaces ambiguous playback 403s"] = function()
  local r = child.lua_get([[(function()
    local api = require("spoil.api")
    local user = require("spoil.user_api")
    local notify = require("spoil.notify")
    local messages = {}
    notify.backend = function(msg, level) messages[#messages + 1] = { msg = msg, level = level } end
    local function last() return messages[#messages] end

    api.next_track = function(_, cb)
      cb({ status = 403, reason = "UNKNOWN", msg = "Player command failed: Restriction violated" })
    end
    user.next_track()
    local next_unknown = last()

    messages = {}
    api.next_track = function(_, cb) cb({ status = 403, reason = "NO_NEXT_TRACK", msg = "no next" }) end
    user.next_track()
    local next_benign = last()

    messages = {}
    api.pause = function(_, cb) cb({ status = 403, reason = nil, msg = "Restriction violated" }) end
    user.pause()
    local pause_unknown = last()

    messages = {}
    api.pause = function(_, cb) cb({ status = 403, reason = "ALREADY_PAUSED", msg = "already paused" }) end
    user.pause()
    local pause_known = last()

    messages = {}
    api.next_track = function(_, cb) cb({ status = 403, reason = "PREMIUM_REQUIRED", msg = "Premium required" }) end
    user.next_track()
    local other = last()

    return {
      next_unknown = next_unknown,
      next_benign = next_benign,
      pause_unknown = pause_unknown,
      pause_known = pause_known,
      other = other,
      WARN = vim.log.levels.WARN,
      INFO = vim.log.levels.INFO,
      ERROR = vim.log.levels.ERROR,
    }
  end)()]])

  eq(r.next_unknown.msg, "Spoil: Spotify ignored the playback command: Player command failed: Restriction violated")
  eq(r.next_unknown.level, r.WARN)
  eq(r.next_benign, nil)
  eq(r.pause_unknown.msg, "Spoil: Spotify ignored the playback command: Restriction violated")
  eq(r.pause_unknown.level, r.WARN)
  eq(r.pause_known.msg, "Paused")
  eq(r.pause_known.level, r.INFO)
  eq(r.other.msg, "Spoil: Premium required")
  eq(r.other.level, r.ERROR)
end

return T
