-- Per-player input (#4): one Input per seat, and which device each seat
-- listens to.  Upstream's src/core/Input.lua keeps all its state on `self`
-- and merges every pad into one set of buttons; player 1's seat is that
-- very table, so solo play is unchanged, and the other seats are instances
-- of it.  In couch co-op (#11) each seat takes only the device claimed for
-- it: the keyboard, or one pad told by its GUID and, between twins of one
-- model, its order among the connected pads.
--
--   Seats.setMode("couch")
--   Seats.assign(2, Seats.describe(joystick, love.joystick.getJoysticks()))
--   Seats.dispatch("gamepadpressed", joystick, "a")  -- reaches the right seat
--   Seats.input(2):isDown("a")
--
-- The claims live in the launcher's settings (CoopSettings.seats) and are
-- edited on the CONTROLS page (src/coop/launcher/Controls.lua).

local Input = require("src.core.Input")

local Seats = {}

Seats.MAX = 2
Seats.mode = "solo"
Seats.devices = {}   -- player -> { kind = "keyboard" } | { kind = "pad", guid, twin, name }

local inputs = { Input }

-- an instance inherits Input's functions only: its state (the cached pad
-- list, the held buttons) must never fall through to the singleton's
local function method(_, k)
  local v = Input[k]
  if type(v) == "function" then return v end
  return nil
end

-- a device entry that can be trusted (settings file, launcher)
function Seats.device(v)
  if type(v) ~= "table" then return nil end
  if v.kind == "keyboard" then return { kind = "keyboard" } end
  if v.kind == "pad" and type(v.guid) == "string" and v.guid ~= "" then
    local twin = tonumber(v.twin) or 1
    if twin < 1 or twin ~= math.floor(twin) then twin = 1 end
    return { kind = "pad", guid = v.guid:sub(1, 64), twin = twin,
             name = type(v.name) == "string" and v.name:sub(1, 48) or nil }
  end
  return nil
end

local function same(a, b)
  if not a or not b or a.kind ~= b.kind then return false end
  if a.kind == "keyboard" then return true end
  return a.guid == b.guid and (a.twin or 1) == (b.twin or 1)
end
Seats.same = same

-- The Input of player `n` (1 is upstream's singleton).
function Seats.input(n)
  local input = inputs[n]
  if not input then
    input = setmetatable({ seat = n }, { __index = method })
    input:init(Input.shoulderGameplay)
    if Input.keyBindings then
      input.keyBindings, input.padBindings, input.joyBindings = Input.keyBindings, Input.padBindings, Input.joyBindings
      input.padActions, input.explicitPadActions, input.joyActions = Input.padActions, Input.explicitPadActions, Input.joyActions
      input.padPoll = Input.padPoll
    end
    inputs[n] = input
  end
  return input
end

local function seatOf(input) return input.seat or 1 end

-- the launcher's view of a joystick: GUID, name and order among its twins
function Seats.describe(joystick, list)
  if type(joystick) ~= "table" then return nil end
  local okG, guid = pcall(function() return joystick:getGUID() end)
  if not okG or type(guid) ~= "string" or guid == "" then return nil end
  local okN, name = pcall(function() return joystick:getName() end)
  local twin = 1
  for _, j in ipairs(list or {}) do
    if j == joystick then break end
    local ok, g = pcall(function() return j:getGUID() end)
    if ok and g == guid then twin = twin + 1 end
  end
  return { kind = "pad", guid = guid, twin = twin, name = okN and type(name) == "string" and name or nil }
end

-- the player whose seat a device drives, or nil
function Seats.player(device)
  if Seats.mode ~= "couch" then return 1 end
  for n = 1, Seats.MAX do
    if same(Seats.devices[n], device) then return n end
  end
  return nil
end

-- the joysticks connected now (for describe's twin count)
local function connected()
  local js = love and love.joystick
  if not (js and js.getJoysticks) then return {} end
  local ok, list = pcall(js.getJoysticks)
  return ok and type(list) == "table" and list or {}
end

local lastSeen = setmetatable({}, { __mode = "k" })

-- Input.seatFilter: does `input` take this device's events?
function Seats.accepts(input, kind, joystick)
  local n = seatOf(input)
  if Seats.mode ~= "couch" then return n == 1 end
  if kind == "key" then
    local d = Seats.devices[n]
    return d ~= nil and d.kind == "keyboard"
  end
  if joystick == nil then return false end
  local desc = lastSeen[joystick]
  if not desc then
    desc = Seats.describe(joystick, connected())
    if not desc then return false end
    lastSeen[joystick] = desc
  end
  return same(Seats.devices[n], desc)
end

Input.seatFilter = function(input, kind, joystick)
  return Seats.accepts(input, kind, joystick)
end

function Seats.setMode(mode)
  Seats.mode = mode == "couch" and "couch" or "solo"
  for n = 1, Seats.MAX do
    local input = inputs[n]
    if input then input:joysticksChanged() end
  end
end

function Seats.assign(player, device)
  local d = Seats.device(device)
  if not d then return Seats.clear(player) end
  for n = 1, Seats.MAX do
    if n ~= player and same(Seats.devices[n], d) then Seats.devices[n] = nil end
  end
  Seats.devices[player] = d
  Seats.setMode(Seats.mode)
end

function Seats.clear(player)
  Seats.devices[player] = nil
  Seats.setMode(Seats.mode)
end

-- solo, no claims; player 1 keeps upstream's Input
function Seats.reset()
  Seats.devices = {}
  for n = 2, Seats.MAX do inputs[n] = nil end
  lastSeen = setmetatable({}, { __mode = "k" })
  Seats.setMode("solo")
end

-- the claims from the launcher's settings (CoopSettings.seats); mode untouched
function Seats.load(settings)
  Seats.devices = {}
  for n = 1, Seats.MAX do
    local d = settings and settings.seats and settings.seats[n]
    if d then Seats.devices[n] = Seats.device(d) end
  end
  Seats.setMode(Seats.mode)
end

-- every player's seat claimed (couch co-op can start)
function Seats.complete(players)
  for n = 1, players or Seats.MAX do
    if not Seats.devices[n] then return false end
  end
  return true
end

-- an input event for every seat; each one's filter keeps what is its own
function Seats.dispatch(method, ...)
  for n = 1, Seats.MAX do
    local input = Seats.input(n)
    local f = input[method]
    if f then f(input, ...) end
  end
end

-- the same rebinds (options.bindings) for every seat
function Seats.applyBindings(overlay)
  Input:applyBindings(overlay)
  for n = 2, Seats.MAX do
    local input = inputs[n]
    if input then
      input.keyBindings, input.padBindings, input.joyBindings = Input.keyBindings, Input.padBindings, Input.joyBindings
      input.padActions, input.explicitPadActions, input.joyActions = Input.padActions, Input.explicitPadActions, Input.joyActions
      input.padPoll = Input.padPoll
    end
  end
end

return Seats
