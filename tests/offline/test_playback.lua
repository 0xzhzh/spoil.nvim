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

return T
