-- Local split-screen co-op (#11): two players on one device, two views in
-- one window, each on the device claimed for their seat on CONTROLS (#4).
-- Player 1's game is main.lua's; player 2's runs in a world of its own
-- (Worlds.lua), a second set of the game's modules.  Each seat is a client
-- of the session like any network player (design A1.3, G3): seat 2 dials
-- the in-process host's loopback hub when this device hosts, or the same
-- host as seat 1 when it joined one.
--
--   Split.request({ name = "BLUE" })  -- the launcher, before the game boots
--   Split.frame(game)                 -- every frame of player 1's game (Dev.update)
--   Split.stop()                      -- back to the launcher, or quitting
--
-- Once started, player 1's game steps and draws player 2's after its own
-- (its update and draw are wrapped), and the window's input events go to
-- the seat whose device sent them (Split.route).  Seat 2:
--   * remembers its own player per host and campaign (Identity, seat 2);
--   * plays in a save slot of its own, the campaign's slot for seat 2
--     (CoopSettings:enterSlot, design A3.14), filled from the host's file;
--   * writes a session log of its own (SessionLog, "-seat2");
--   * runs silent: the window has one mix, player 1's (decision G23).
-- Its game starts at the title like player 1's; CONTINUE enters its world.

local Worlds = require("src.coop.split.Worlds")
local Layout = require("src.coop.split.Layout")

local Split = { current = nil, pending = nil }

Split.NAME = "PLAYER2"

-- the window's input events, and whose device each one comes from
local KEYBOARD = { keypressed = true, keyreleased = true, textinput = true }
local PAD = {
  gamepadpressed = true, gamepadreleased = true, gamepadaxis = true,
  joystickpressed = true, joystickreleased = true, joystickaxis = true, joystickhat = true,
}
local BOTH = { joystickadded = true, joystickremoved = true, focus = true, visible = true }
Split.EVENTS = {}
for _, set in ipairs({ KEYBOARD, PAD, BOTH }) do
  for name in pairs(set) do Split.EVENTS[#Split.EVENTS + 1] = name end
end
table.sort(Split.EVENTS)

local function say(fmt, ...)
  print("co-op: split-screen: " .. fmt:format(...))
end

local function connected()
  local js = love and love.joystick
  if not (js and js.getJoysticks) then return {} end
  local ok, list = pcall(js.getJoysticks)
  return ok and type(list) == "table" and list or {}
end

-- Which seat an input event goes to: 1, 2, "both", or nil (a device no seat
-- claimed).  `seats` is a Seats in couch mode; the mouse and touch stay
-- player 1's (they are not wrapped).
function Split.route(seats, event, device, list)
  if BOTH[event] then return "both" end
  local desc
  if KEYBOARD[event] then
    desc = { kind = "keyboard" }
  elseif PAD[event] then
    desc = seats.describe(device, list or connected())
  else
    return 1
  end
  return desc and seats.player(desc) or nil
end

-- ------------------------------------------------------------ start

-- Ask for split-screen once the game runs.  opts: name (seat 2's trainer
-- name for a host that does not know it yet), settings (a CoopSettings;
-- loaded from the save folder when absent); a test passes boot(sp), which
-- builds seat 2's game inside its world instead of Game:load.
function Split.request(opts)
  Split.pending = opts or {}
end

-- seat 2's dial: the host's loopback hub, or the address seat 1 dialled
local function dialFor(home)
  if home.hub then
    local hub = home.hub
    return "loopback", function() return hub:dial() end
  end
  return home.address, nil
end

function Split.start(game, opts)
  if Split.current then return Split.current end
  opts = opts or {}
  local Session = require("src.coop.session.Session")
  local home = Session.current
  if not (home and home.cartridge) then
    say("no session to share")
    return nil
  end
  local CoopSettings = require("src.coop.launcher.CoopSettings")
  local settings = opts.settings
  if not settings then
    local ok, loaded = pcall(CoopSettings.load)
    settings = ok and loaded or nil
  end
  local Seats = require("src.coop.game.Seats")
  if settings then Seats.load(settings) end
  Seats.setMode("couch")
  local address, dial = dialFor(home)
  local sp = {
    game1 = game, seats = Seats, world = Worlds.new("seat2", { silent = true }),
    home = Worlds.home(), status = "dialling", reason = nil,
    version = home.cartridge.game, settingsFile = settings and settings.fs,
    name = opts.name or (settings and settings.name2) or Split.NAME,
    boot = opts.boot,
  }
  Split.current, Split.pending = sp, nil
  Worlds.run(sp.world, function()
    local S2 = require("src.coop.session.Session")
    sp.session = S2.startDial({
      address = address, dial = dial, seat = 2, name = sp.name,
      cartridge = home.cartridge, identity = home.identity,
      -- a log of its own, when seat 1 keeps one
      log = home.log ~= nil, shareLogs = home.log ~= nil and home.log.share,
    })
  end)
  Split._wrap(sp)
  Split._grow(game)
  say("seat 2 dials %s", tostring(address))
  return sp
end

-- every frame of player 1's game: start a requested split-screen
function Split.frame(game)
  if Split.pending and not Split.current and game then
    Split.start(game, Split.pending)
  end
end

-- ------------------------------------------------------------ seat 2

-- seat 2's world from the campaign into its own save slot (inside its world)
local function enterSlot(sp, s)
  local SaveData = require("src.core.SaveData")
  local CoopSettings = require("src.coop.launcher.CoopSettings")
  local ok, settings = pcall(CoopSettings.load, sp.settingsFile)
  if not ok then settings = nil end
  local campaign = s.client and s.client.campaign
  local title = (s.lobby and s.lobby.title or "CO-OP"):sub(1, 13) .. " P2"
  local slot = settings and campaign and settings:enterSlot(SaveData, sp.version, campaign, title, 2)
  if not slot then return false, "no save slot" end
  local save = s:takeWorld()
  if save then
    local wrote, err = SaveData.writeSlot(sp.version, slot, save)
    if not wrote then return false, tostring(err) end
  end
  return true
end

local function bootSeat2(sp)
  local Seats = require("src.coop.game.Seats")
  local CoopSettings = require("src.coop.launcher.CoopSettings")
  local ok, settings = pcall(CoopSettings.load, sp.settingsFile)
  if ok then Seats.load(settings) end
  Seats.setMode("couch")
  -- this world's Input is seat 2's: its filter takes seat 2's device only
  require("src.core.Input").seat = 2
  local Game = require("src.core.Game")
  Game:load({})
  -- a scripted run steps every logic frame itself (main.lua's bootGame)
  Game.speedOverride = sp.game1.speedOverride
  return Game
end

-- one step of seat 2: its session, then its game (inside its world)
local function stepSeat2(sp, dt)
  local Session = require("src.coop.session.Session")
  local s = sp.session
  if sp.game then
    if Session.tick(dt, sp.game) == "launcher" then
      sp.status, sp.reason = "ended", s.reason
      return
    end
    sp.game:update(dt)
    return
  end
  Session.tick(dt, nil)
  if s.status == "probed" then
    s:join()
  elseif s.status == "joined" and s:worldReady() then
    local ok, why = enterSlot(sp, s)
    if not ok then
      sp.status, sp.reason = "failed", why
      return
    end
    sp.game = (sp.boot or bootSeat2)(sp)
    sp.status = "playing"
    say("seat 2 joined as %s", tostring(s.name))
  elseif s.status == "refused" or s.status == "unreachable" or s.status == "ended"
      or s.status == "closed" then
    sp.status, sp.reason = s.status, s.reason
  end
end

function Split.step(dt)
  local sp = Split.current
  if not sp or sp.status == "failed" or sp.status == "ended" then return end
  local ok, err = pcall(Worlds.run, sp.world, stepSeat2, sp, dt)
  if not ok then
    sp.status, sp.reason = "failed", tostring(err)
    say("seat 2 stopped: %s", sp.reason)
  end
end

-- ------------------------------------------------------------ draw

local function waitingText(sp)
  if sp.status == "dialling" then return "PLAYER 2\n\nJOINING..." end
  return "PLAYER 2\n\n" .. string.upper(sp.status) .. "\n" .. tostring(sp.reason or "")
end

local function drawWaiting(sp, rect)
  local G = love.graphics
  G.push("all")
  G.origin()
  G.setScissor(rect.x, rect.y, rect.width, rect.height)
  G.clear(0, 0, 0, 1)
  G.setColor(1, 1, 1, 1)
  G.printf(waitingText(sp), rect.x + 8, rect.y + math.floor(rect.height / 2) - 24,
           rect.width - 16, "center")
  G.pop()
end

function Split.draw(drawGame1, game1)
  local sp = Split.current
  local w, h = love.graphics.getDimensions()
  local views = Layout.views(w, h)
  sp.views = views
  local VP = require("src.render.GameViewport")
  VP.forced = views[1]
  local ok, err = pcall(drawGame1, game1)
  VP.forced = nil
  if not ok then error(err, 0) end
  if sp.game and sp.status ~= "failed" then
    local drew, why = pcall(Worlds.run, sp.world, function()
      local VP2 = require("src.render.GameViewport")
      VP2.forced = views[2]
      local okDraw, e = pcall(sp.game.draw, sp.game)
      VP2.forced = nil
      if not okDraw then error(e, 0) end
    end)
    if not drew then
      sp.status, sp.reason = "failed", tostring(why)
      say("seat 2 stopped drawing: %s", sp.reason)
    end
  else
    drawWaiting(sp, views[2])
  end
end

-- ------------------------------------------------------------ input

local function deliver2(sp, event, ...)
  if not sp.game or sp.status ~= "playing" then return end
  local args = { n = select("#", ...), ... }
  pcall(Worlds.run, sp.world, function()
    local g = sp.game
    if event == "joystickadded" or event == "joystickremoved" then
      if g.input and g.input.joysticksChanged then g.input:joysticksChanged() end
    end
    local f = g[event]
    if f then f(g, unpack(args, 1, args.n)) end
  end)
end

function Split._wrap(sp)
  local game = sp.game1
  sp.wrapped = { update = rawget(game, "update"), draw = rawget(game, "draw"), love = {} }
  local update, draw = game.update, game.draw
  game.update = function(self, dt)
    update(self, dt)
    Split.step(dt)
  end
  game.draw = function(self)
    if Split.current ~= sp then return draw(self) end
    Split.draw(draw, self)
  end
  for _, event in ipairs(Split.EVENTS) do
    local original = love[event]
    sp.wrapped.love[event] = original or false
    love[event] = function(...)
      local seat = Split.route(sp.seats, event, (...))
      if (seat == 1 or seat == "both") and original then original(...) end
      if seat == 2 or seat == "both" then deliver2(sp, event, ...) end
    end
  end
end

-- a window that shows one game grows to show two at the same scale
function Split._grow(game)
  local win = love.window
  if not (win and win.getMode and win.setMode and win.getDesktopDimensions) then return end
  local okMode, w, h, flags = pcall(win.getMode)
  if not okMode or (flags and (flags.fullscreen or flags.maximized)) then return end
  local s = game and game.renderer and game.renderer.fitScale and game.renderer:fitScale() or 2
  local dw, dh = win.getDesktopDimensions(flags and flags.display or 1)
  local nw, nh = Layout.grow(w, h, s, dw, dh)
  if nw then pcall(win.setMode, nw, nh, flags) end
end

-- ------------------------------------------------------------ stop

-- Seat 2 leaves (its bye goes out) and its world is dropped; player 1's
-- game and the window's events are put back.
function Split.stop()
  Split.pending = nil
  local sp = Split.current
  if not sp then return end
  Split.current = nil
  pcall(Worlds.run, sp.world, function()
    require("src.coop.session.Session").shutdown()
  end)
  for event, original in pairs(sp.wrapped.love) do
    love[event] = original or nil
  end
  local game = sp.game1
  rawset(game, "update", sp.wrapped.update)
  rawset(game, "draw", sp.wrapped.draw)
  Worlds.reset()
  local VP = package.loaded["src.render.GameViewport"]
  if VP then VP.forced = nil end
  local Seats = package.loaded["src.coop.game.Seats"]
  if Seats then Seats.setMode("solo") end
  say("stopped")
end

return Split
