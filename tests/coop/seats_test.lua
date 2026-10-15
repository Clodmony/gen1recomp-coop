-- Per-player input (#4), ROM-free: in solo play every pad and the keyboard
-- drive player 1 as before; in couch co-op each player's seat takes only
-- the device claimed for it, polled pads included, and twins (two pads of
-- one model) are told apart by their order.  The seats are remembered in
-- the launcher's settings by pad GUID, and the controls model writes
-- rebinds in the form upstream's Input reads (options.bindings).
--   luajit tests/coop/seats_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Input = require("src.core.Input")
local Seats = require("src.coop.game.Seats")
local CoopSettings = require("src.coop.launcher.CoopSettings")
local Controls = require("src.coop.launcher.Controls")
local SaveData = require("src.core.SaveData")

-- a fake SDL gamepad: a GUID, a name and the buttons held right now
local function pad(guid, name)
  local p = { guid = guid, name = name, down = {} }
  function p:getGUID() return self.guid end
  function p:getName() return self.name end
  function p:isGamepad() return true end
  function p:isConnected() return true end
  function p:isGamepadDown(button) return self.down[button] == true end
  function p:getGamepadAxis() return 0 end
  return p
end

local function memoryFs()
  local files = {}
  return {
    files = files,
    getInfo = function(name) if files[name] then return { type = "file" } end return nil end,
    read = function(name) return files[name] end,
    write = function(name, text) files[name] = text return true end,
    remove = function(name) files[name] = nil return true end,
    createDirectory = function() return true end,
  }
end

local padA, padB = pad("guid-a", "Pad A"), pad("guid-b", "Pad B")
local connected = { padA, padB }
love.joystick = {
  getJoystickCount = function() return #connected end,
  getJoysticks = function() return connected end,
}

local function held(input)
  local out = {}
  for _, b in ipairs({ "up", "down", "left", "right", "a", "b", "start", "select" }) do
    if input:isDown(b) then out[#out + 1] = b end
  end
  return table.concat(out, ",")
end

local function settle()
  for n = 1, Seats.MAX do Seats.input(n):step() end
end

-- an event on a pad, which the pad's state reflects (Input polls pads each
-- step and repairs a press the pad no longer holds)
local function padEvent(p, phase, button)
  p.down[button] = phase == "pressed" or nil
  Seats.dispatch(phase == "pressed" and "gamepadpressed" or "gamepadreleased", p, button)
end

-- 1. solo: every device drives player 1, as upstream does -----------------
do
  Seats.reset()
  Input:init()
  eq(Seats.mode, "solo", "the seats start in solo mode")
  check(Seats.input(1) == Input, "player 1 is upstream's Input singleton")
  check(Seats.input(2) ~= Input, "player 2 has an Input of its own")
  padEvent(padA, "pressed", "a")
  padEvent(padB, "pressed", "b")
  Seats.dispatch("keypressed", "up")
  settle()
  eq(held(Seats.input(1)), "up,a,b", "solo: both pads and the keyboard reach player 1")
  eq(held(Seats.input(2)), "", "solo: player 2 gets nothing")
  padEvent(padA, "released", "a")
  padEvent(padB, "released", "b")
  Seats.dispatch("keyreleased", "up")
  settle()
  eq(held(Seats.input(1)), "", "and releases arrive the same way")
  -- polled pads: a press the event path missed is picked up by step()
  padA.down.start = true
  settle()
  eq(held(Seats.input(1)), "start", "solo: a polled pad press reaches player 1")
  padA.down.start = nil
  settle()
  eq(held(Seats.input(1)), "", "and its release")
end

-- 2. couch co-op: each seat takes its own pad --------------------------------
do
  Seats.reset()
  Input:init()
  Seats.setMode("couch")
  Seats.assign(1, Seats.describe(padA, connected))
  Seats.assign(2, Seats.describe(padB, connected))
  padEvent(padA, "pressed", "a")
  padEvent(padB, "pressed", "b")
  padEvent(padB, "pressed", "dpleft")
  settle()
  eq(held(Seats.input(1)), "a", "couch: pad A drives player 1 only")
  eq(held(Seats.input(2)), "left,b", "couch: pad B drives player 2 only")
  padEvent(padB, "released", "b")
  settle()
  eq(held(Seats.input(2)), "left", "a release on pad B reaches player 2")
  eq(held(Seats.input(1)), "a", "and leaves player 1 alone")
  padEvent(padA, "released", "a")
  padEvent(padB, "released", "dpleft")
  settle()
  -- the keyboard is nobody's: it drives no one
  Seats.dispatch("keypressed", "z")
  settle()
  eq(held(Seats.input(1)) .. "|" .. held(Seats.input(2)), "|",
    "couch: an unclaimed keyboard drives nobody")
  Seats.dispatch("keyreleased", "z")
  -- polling stays apart too
  padA.down.start, padB.down.back = true, true
  settle()
  eq(held(Seats.input(1)), "start", "couch: polling pad A fills player 1")
  eq(held(Seats.input(2)), "select", "couch: polling pad B fills player 2")
  padA.down.start, padB.down.back = nil, nil
  settle()
  eq(held(Seats.input(1)) .. "|" .. held(Seats.input(2)), "|", "polled releases too")
  -- the keyboard claimed for player 1, the pad goes back to the pool
  Seats.assign(1, { kind = "keyboard" })
  Seats.dispatch("keypressed", "z")
  padEvent(padA, "pressed", "a")
  padEvent(padB, "pressed", "a")
  settle()
  eq(held(Seats.input(1)), "a", "couch: the keyboard seat takes the keys")
  eq(held(Seats.input(2)), "a", "pad B still drives player 2")
  Seats.dispatch("keyreleased", "z")
  padEvent(padA, "pressed", "b")
  settle()
  eq(held(Seats.input(1)) .. "|" .. held(Seats.input(2)), "|a", "an unclaimed pad drives nobody")
  padEvent(padA, "released", "a")
  padEvent(padA, "released", "b")
  padEvent(padB, "released", "a")
  settle()
  -- the same rebinds apply to every seat
  Seats.applyBindings({ a = { key = "k", pad = "y" } })
  Seats.dispatch("keypressed", "k")
  padEvent(padB, "pressed", "y")
  settle()
  eq(held(Seats.input(1)) .. "|" .. held(Seats.input(2)), "a|a", "a rebind reaches both seats")
  Seats.reset()
  Input:init()
end

-- 3. twins: two pads of one model are told apart by their order ------------
do
  local twinA, twinB = pad("same", "Twin"), pad("same", "Twin")
  local list = { padA, twinA, twinB }
  local dA, dB = Seats.describe(twinA, list), Seats.describe(twinB, list)
  eq(dA.guid .. "/" .. dA.twin, "same/1", "the first twin is twin 1")
  eq(dB.guid .. "/" .. dB.twin, "same/2", "the second is twin 2")
  eq(Seats.describe(padA, list).twin, 1, "a pad alone is twin 1")
  Seats.reset()
  Seats.setMode("couch")
  Seats.assign(1, dA)
  Seats.assign(2, dB)
  eq(Seats.player(dA), 1, "twin 1 is player 1's")
  eq(Seats.player(dB), 2, "twin 2 is player 2's")
  eq(Seats.player(Seats.describe(padA, list)), nil, "another pad is nobody's")
  Seats.reset()
end

-- 4. the seats are remembered in the launcher's settings by GUID -------------
do
  local fs = memoryFs()
  local s = CoopSettings.load(fs)
  eq(#s.seats, 0, "a fresh settings file has no seats")
  s.seats = { { kind = "keyboard" }, { kind = "pad", guid = "guid-b", twin = 2, name = "Pad B" } }
  s:save()
  local again = CoopSettings.load(fs)
  eq(again.seats[1].kind, "keyboard", "player 1's keyboard comes back")
  eq(again.seats[2].guid .. "/" .. again.seats[2].twin .. "/" .. again.seats[2].name,
    "guid-b/2/Pad B", "player 2's pad comes back with GUID, twin and name")
  -- a broken entry is dropped, not trusted
  fs.write(CoopSettings.FILE, '{"seats":[{"kind":"pad"},{"kind":"keyboard"},{"kind":"toaster"}]}')
  local broken = CoopSettings.load(fs)
  eq(broken.seats[1], false, "a pad without a GUID is no device")
  eq(broken.seats[2].kind, "keyboard", "the entries keep their player")
  eq(#broken.seats, 2, "an unknown kind is dropped")
  -- Seats takes them over
  Seats.reset()
  Seats.load(again)
  eq(Seats.devices[1].kind, "keyboard", "Seats.load takes the keyboard")
  eq(Seats.devices[2].guid, "guid-b", "and the pad")
  eq(Seats.mode, "solo", "loading seats does not start couch mode")
  Seats.reset()
end

-- 5. the controls model: rebinding and claiming devices ---------------------
do
  local fs = memoryFs()
  local saved = {}
  local settings = CoopSettings.load(fs)
  local pads = { Seats.describe(padA, connected), Seats.describe(padB, connected) }
  local c = Controls.new({
    bindings = function() return SaveData.loadOptions(fs).bindings or {} end,
    saveBindings = function(overlay)
      saved[#saved + 1] = overlay
      SaveData.saveOptions({ bindings = overlay }, fs)
    end,
    settings = settings,
    pads = function() return pads end,
  })
  local function row(id, key)
    for _, r in ipairs(c:rows()) do
      if r.id == id and (key == nil or r.button == key or r.player == key) then return r end
    end
    error("no row " .. id .. " " .. tostring(key))
  end
  eq(row("bind", "a").detail, "Z / A", "A shows its default key and pad button")
  eq(row("bind", "start").detail, "ESC / START", "START too")
  eq(row("bind", "up").detail, "UP / D-PAD UP", "and a direction")
  eq(row("seat", 1).detail, "ANY DEVICE", "player 1 has no device claimed yet")
  eq(row("seat", 2).detail, "NO DEVICE", "nor player 2")
  eq(c:prompt(), nil, "nothing is being captured")

  -- rebind A to K and the pad's Y
  c:press(row("bind", "a"))
  check(c:prompt() ~= nil, "a bind row waits for a key or pad button")
  check(c:captured({ kind = "key", key = "k" }), "a key is taken")
  eq(c:prompt(), nil, "and the capture ends")
  eq(row("bind", "a").detail, "K / A", "A now shows K")
  c:press(row("bind", "a"))
  c:captured({ kind = "pad", button = "y", device = pads[1] })
  eq(row("bind", "a").detail, "K / Y", "and the pad's Y")
  eq(#saved, 2, "each rebind is saved")
  eq(SaveData.loadOptions(fs).bindings.a.key, "k", "options.bindings holds the key")
  eq(SaveData.loadOptions(fs).bindings.a.pad, "y", "and the pad button, as Input reads them")
  -- the swap: X is B's key; binding it to A hands B the key A had
  c:press(row("bind", "a"))
  c:captured({ kind = "key", key = "x" })
  eq(row("bind", "a").detail, "X / Y", "A takes X")
  eq(row("bind", "b").detail, "K / B", "and B gets A's old key, never none")
  -- Input reads the result
  Input:init()
  Input:applyBindings(SaveData.loadOptions(fs).bindings)
  Input:keypressed("x")
  Input:step()
  check(Input:isDown("a") and not Input:isDown("b"), "Input presses A for X after the swap")
  Input:init()
  -- escape cancels
  c:press(row("bind", "select"))
  c:captured({ kind = "cancel" })
  eq(c:prompt(), nil, "cancel ends a capture")
  eq(row("bind", "select").detail, "TAB / BACK", "and changes nothing")
  -- reset
  c:press(row("reset"))
  eq(row("bind", "a").detail, "Z / A", "RESET puts the defaults back")
  eq(next(SaveData.loadOptions(fs).bindings or {}), nil, "and clears options.bindings")

  -- claim devices: player 2 presses A on pad B, player 1 takes the keyboard
  c:press(row("seat", 2))
  check(c:prompt() ~= nil, "a seat row waits for a press")
  check(not c:captured({ kind = "pad", button = "x", device = pads[2] }), "only A claims a pad")
  check(c:captured({ kind = "pad", button = "a", device = pads[2] }), "A on pad B claims it")
  eq(row("seat", 2).detail, "PAD B", "player 2 shows the pad's name")
  c:press(row("seat", 1))
  c:captured({ kind = "key", key = "return" })
  eq(row("seat", 1).detail, "KEYBOARD", "Enter claims the keyboard")
  eq(settings.seats[2].guid, "guid-b", "the claim is in the settings")
  eq(CoopSettings.load(fs).seats[1].kind, "keyboard", "and on disk")
  -- a pad another player holds moves over
  c:press(row("seat", 1))
  c:captured({ kind = "pad", button = "a", device = pads[2] })
  eq(row("seat", 1).detail, "PAD B", "player 1 takes pad B")
  eq(row("seat", 2).detail, "NO DEVICE", "and player 2 loses it")
  -- the connected pads are listed, a claimed one marked
  local list = c:padList()
  eq(#list, 2, "two pads connected")
  eq(list[2].player, 1, "pad B is player 1's")
  eq(list[1].player, nil, "pad A is free")
  -- clearing
  c:press(row("clear"))
  eq(row("seat", 1).detail .. "/" .. row("seat", 2).detail, "ANY DEVICE/NO DEVICE",
    "CLEAR forgets the devices")
  eq(#settings.seats, 0, "in the settings too")
end

T.finish()
