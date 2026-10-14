-- The CONTROLS page's model (#4), with no love.* calls: the Game Boy
-- buttons and the key and pad button each one answers to, and each
-- player's device for couch co-op.
--
-- Rebinds are written where upstream's Input reads them, options.bindings
-- in options.lua (`{ key = , pad = }` per button, layered over the defaults
-- by Input:applyBindings), so the game's own CONTROLS menu and this page
-- agree.  As there, a captured key that another button answers to is
-- swapped, never stolen: that button gets the key this one had.  Devices
-- are the launcher's own (CoopSettings.seats, read by Seats.lua).
--
-- env:
--   bindings()            -> the options.bindings table (a copy is fine)
--   saveBindings(overlay)    write it
--   settings                 a CoopSettings (its `seats`, `save`)
--   pads()                -> the connected pads as Seats.describe entries

local Seats = require("src.coop.game.Seats")
local Text = require("src.coop.launcher.Text")
local L = Text.get

local Controls = {}
Controls.__index = Controls

-- Input.lua's defaults, primary key first (as upstream's BindingsMenu shows them)
Controls.BUTTONS = {
  { id = "up", label = "UP", key = "up", pad = "dpup" },
  { id = "down", label = "DOWN", key = "down", pad = "dpdown" },
  { id = "left", label = "LEFT", key = "left", pad = "dpleft" },
  { id = "right", label = "RIGHT", key = "right", pad = "dpright" },
  { id = "a", label = "A", key = "z", pad = "a" },
  { id = "b", label = "B", key = "x", pad = "b" },
  { id = "start", label = "START", key = "escape", pad = "start" },
  { id = "select", label = "SELECT", key = "tab", pad = "back" },
}

local KEY_NAMES = {
  ["return"] = "ENTER", escape = "ESC", kpenter = "KP ENTER", backspace = "BACKSPACE",
  lshift = "L SHIFT", rshift = "R SHIFT", lctrl = "L CTRL", rctrl = "R CTRL",
  lalt = "L ALT", ralt = "R ALT", space = "SPACE", tab = "TAB",
}
local PAD_NAMES = {
  dpup = "D-PAD UP", dpdown = "D-PAD DOWN", dpleft = "D-PAD LEFT", dpright = "D-PAD RIGHT",
  leftshoulder = "L", rightshoulder = "R", triggerleft = "ZL", triggerright = "ZR",
  leftstick = "L STICK", rightstick = "R STICK", back = "BACK", start = "START", guide = "GUIDE",
}

function Controls.keyName(key) return KEY_NAMES[key] or tostring(key):upper() end
function Controls.padName(button) return PAD_NAMES[button] or tostring(button):upper() end

function Controls.new(env)
  return setmetatable({ env = env }, Controls)
end

local function overlayOf(self)
  local ok, b = pcall(self.env.bindings)
  return ok and type(b) == "table" and b or {}
end

-- the key or pad button `button` answers to now
local function effective(overlay, button, slot)
  local b = overlay[button.id]
  if type(b) == "table" and b[slot] then return b[slot] end
  if slot == "key" and type(b) == "string" then return b end
  return button[slot]
end

local function deviceName(d)
  if not d then return nil end
  if d.kind == "keyboard" then return L("KEYBOARD") end
  return (d.name and d.name ~= "" and d.name or L("PAD")):upper()
end
Controls.deviceName = deviceName

function Controls:seat(player)
  local d = self.env.settings and self.env.settings.seats and self.env.settings.seats[player]
  return d or nil
end

-- the rows: one per Game Boy button, RESET, one per player, CLEAR
function Controls:rows()
  local rows = {}
  local overlay = overlayOf(self)
  for _, b in ipairs(Controls.BUTTONS) do
    rows[#rows + 1] = { id = "bind", button = b.id, label = L(b.label),
      detail = Controls.keyName(effective(overlay, b, "key")) .. " / "
        .. Controls.padName(effective(overlay, b, "pad")) }
  end
  rows[#rows + 1] = { id = "reset", label = L("RESET BINDINGS"), enabled = next(overlay) ~= nil }
  for n = 1, Seats.MAX do
    local d = self:seat(n)
    rows[#rows + 1] = { id = "seat", player = n, label = L("PLAYER %d", n),
      detail = deviceName(d) or (n == 1 and L("ANY DEVICE") or L("NO DEVICE")) }
  end
  local any = false
  for n = 1, Seats.MAX do if self:seat(n) then any = true end end
  rows[#rows + 1] = { id = "clear", label = L("CLEAR DEVICES"), enabled = any }
  return rows
end

-- the connected pads, each with the player it is claimed for
function Controls:padList()
  local ok, pads = pcall(self.env.pads)
  local out = {}
  for _, d in ipairs(ok and type(pads) == "table" and pads or {}) do
    local player
    for n = 1, Seats.MAX do
      if Seats.same(self:seat(n), d) then player = n end
    end
    out[#out + 1] = { device = d, name = deviceName(d), player = player }
  end
  return out
end

-- what the page asks for while a capture is on, or nil
function Controls:prompt()
  local c = self.capture
  if not c then return nil end
  if c.kind == "bind" then
    return L("Press a key or a pad button for %s. Esc cancels.", L(c.label))
  end
  return L("Player %d: press A on your pad, or Enter for the keyboard. Esc cancels.", c.player)
end

-- a row pressed
function Controls:press(row)
  if not row then return nil end
  if row.id == "bind" then
    for _, b in ipairs(Controls.BUTTONS) do
      if b.id == row.button then self.capture = { kind = "bind", button = b, label = b.label } end
    end
  elseif row.id == "reset" then
    self.env.saveBindings({})
    Seats.applyBindings({})
  elseif row.id == "seat" then
    self.capture = { kind = "seat", player = row.player }
  elseif row.id == "clear" then
    self:_setSeats({})
  end
  return nil
end

function Controls:_setSeats(seats)
  local settings = self.env.settings
  if not settings then return end
  -- a dense list with `false` for a player without a device, trimmed
  local list = {}
  local last = 0
  for n = 1, Seats.MAX do
    list[n] = seats[n] or false
    if seats[n] then last = n end
  end
  for n = Seats.MAX, last + 1, -1 do list[n] = nil end
  settings.seats = list
  if settings.save then pcall(settings.save, settings) end
  Seats.load(settings)
end

function Controls:_claim(player, device)
  local seats = {}
  for n = 1, Seats.MAX do
    local d = self:seat(n)
    if d and not Seats.same(d, device) then seats[n] = d end
  end
  seats[player] = device
  self:_setSeats(seats)
end

function Controls:_bind(slot, value)
  local button = self.capture.button
  local overlay = {}
  for k, v in pairs(overlayOf(self)) do overlay[k] = v end
  local function entry(id)
    local b = overlay[id]
    if type(b) ~= "table" then b = { key = type(b) == "string" and b or nil } end
    overlay[id] = b
    return b
  end
  local prev = effective(overlay, button, slot)
  if value ~= prev then
    for _, other in ipairs(Controls.BUTTONS) do
      if other.id ~= button.id and effective(overlay, other, slot) == value then
        entry(other.id)[slot] = prev
      end
    end
    entry(button.id)[slot] = value
  end
  -- an entry that only repeats the defaults is no entry
  for _, b in ipairs(Controls.BUTTONS) do
    local e = overlay[b.id]
    if type(e) == "table" then
      if e.key == b.key then e.key = nil end
      if e.pad == b.pad then e.pad = nil end
      if next(e) == nil then overlay[b.id] = nil end
    end
  end
  self.env.saveBindings(overlay)
  Seats.applyBindings(overlay)
end

-- A key or pad press while a capture is on:
--   { kind = "key", key = k } | { kind = "pad", button = b, device = desc } | { kind = "cancel" }
-- Returns true when the press was used (the capture ends or the device is
-- not the one asked for), false when the capture goes on.
function Controls:captured(ev)
  local c = self.capture
  if not c then return false end
  if ev.kind == "cancel" or (ev.kind == "key" and ev.key == "escape") then
    self.capture = nil
    return true
  end
  if c.kind == "bind" then
    if ev.kind == "key" and ev.key then
      self:_bind("key", ev.key)
    elseif ev.kind == "pad" and ev.button then
      self:_bind("pad", ev.button)
    else
      return false
    end
    self.capture = nil
    return true
  end
  -- a seat
  if ev.kind == "key" then
    if ev.key == "return" or ev.key == "kpenter" or ev.key == "z" or ev.key == "space" then
      self:_claim(c.player, { kind = "keyboard" })
      self.capture = nil
      return true
    end
    return false
  end
  if ev.kind == "pad" then
    if ev.button == "b" then
      self.capture = nil
      return true
    end
    if (ev.button == "a" or ev.button == "start") and ev.device then
      self:_claim(c.player, ev.device)
      self.capture = nil
      return true
    end
  end
  return false
end

function Controls:cancel() self.capture = nil end

return Controls
