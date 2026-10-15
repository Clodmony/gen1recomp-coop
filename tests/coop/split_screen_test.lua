-- Local split-screen co-op (#11), ROM-free:
--   * the view layout: side by side or stacked, whichever draws each
--     160x144 view larger, and the window grown to keep a solo scale;
--   * the input routing: each event goes to the seat whose device sent it;
--   * two worlds in one process (src/coop/split/Worlds.lua): each with its
--     own game modules, the shared ones one per process, a silent world
--     without love.audio / love.thread;
--   * the whole path: this device hosts, Split starts seat 2 in its own
--     world, seat 2 dials the loopback hub as seat 2, enters a save slot
--     of its own and plays a fixture overworld of its own; pad A walks
--     player 1, pad B player 2, through the window's (wrapped) events;
--   * seat 2's slot in CoopSettings, its log file, the --coop-split entry.
--   luajit tests/coop/split_screen_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local check, eq = T.check, T.eq

local Layout = require("src.coop.split.Layout")
local Worlds = require("src.coop.split.Worlds")
local Split = require("src.coop.split.Split")

-- a fake SDL gamepad: a GUID, a name and the buttons held right now
local function pad(guid, name)
  local p = { guid = guid, name = name, down = {} }
  function p:getGUID() return self.guid end
  function p:getName() return self.name end
  function p:isGamepad() return true end
  function p:isConnected() return true end
  function p:isGamepadDown(...)
    for _, b in ipairs({ ... }) do if self.down[b] then return true end end
    return false
  end
  function p:getGamepadAxis() return 0 end
  return p
end
local padA, padB = pad("guid-a", "Pad A"), pad("guid-b", "Pad B")
local connected = { padA, padB }
love.joystick = {
  getJoystickCount = function() return #connected end,
  getJoysticks = function() return connected end,
}

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

-- 1. the view layout -----------------------------------------------------
do
  local v, how = Layout.views(1280, 576)
  eq(how, "side", "a wide window puts the views side by side")
  eq(v[1].x .. "," .. v[1].width .. "/" .. v[2].x .. "," .. v[2].width .. "x" .. v[2].height,
     "0,640/640,640x576", "each half of 1280x576 is 640x576 (scale 4)")
  v, how = Layout.views(640, 1152)
  eq(how, "stacked", "a tall window stacks them")
  eq(v[1].y .. "," .. v[1].height .. "/" .. v[2].y .. "," .. v[2].height, "0,576/576,576",
     "each half of 640x1152 is 640x576")
  -- 1024x768: side by side gives scale 3 (512x768), stacked 2 (1024x384)
  v, how = Layout.views(1024, 768)
  eq(how, "side", "1024x768: side by side draws at scale 3, stacked at 2")
  eq(Layout.scale(v[1].width, v[1].height), 3, "and the side view's scale is 3")
  -- a tie: 320x288 halves are scale 1 either way
  eq(select(2, Layout.views(640, 288)), "side", "a tie in a wide window: side by side")
  eq(select(2, Layout.views(320, 576)), "stacked", "a tie in a tall window: stacked")
  check(Layout.scale(100, 100) < 1, "a view smaller than 160x144 draws below scale 1")
  eq(select(2, Layout.views(200, 100)), "side", "and the larger of two small views wins")
  -- a solo window at scale 4 (640x576) grows to show both at scale 4
  local w, h = Layout.grow(640, 576, 4, 1920, 1080)
  eq(tostring(w) .. "x" .. tostring(h), "1280x576", "a solo 640x576 window grows to 1280x576")
  w = Layout.grow(1280, 576, 4, 1920, 1080)
  eq(w, nil, "a window that already shows both at scale 4 stays")
  w, h = Layout.grow(800, 720, 5, 1366, 768)
  eq(tostring(w) .. "x" .. tostring(h), "1280x720", "a desktop too small for scale 5 gets scale 4")
end

-- 2. the input routing -----------------------------------------------------
do
  local Seats = require("src.coop.game.Seats")
  Seats.reset()
  Seats.setMode("couch")
  Seats.assign(1, Seats.describe(padA, connected))
  Seats.assign(2, { kind = "keyboard" })
  eq(Split.route(Seats, "gamepadpressed", padA), 1, "pad A's press goes to player 1")
  eq(Split.route(Seats, "gamepadaxis", padB), nil, "pad B, claimed by nobody, goes nowhere")
  eq(Split.route(Seats, "keypressed", "z"), 2, "the keyboard (player 2's) goes to player 2")
  eq(Split.route(Seats, "textinput", "a"), 2, "and so does typing")
  eq(Split.route(Seats, "joystickadded", padB), "both", "a pad plugged in: both games hear it")
  eq(Split.route(Seats, "focus", true), "both", "focus: both")
  eq(Split.route(Seats, "mousepressed", 1), 1, "the mouse stays player 1's")
  Seats.assign(2, Seats.describe(padB, connected))
  eq(Split.route(Seats, "gamepadpressed", padB), 2, "pad B once claimed: player 2")
  eq(Split.route(Seats, "keypressed", "z"), nil, "and the keyboard, now nobody's, goes nowhere")
  -- twins: two pads of one model are told apart by their order
  local t1, t2 = pad("guid-twin", "Twin"), pad("guid-twin", "Twin")
  local list = { t1, t2 }
  Seats.assign(1, Seats.describe(t1, list))
  Seats.assign(2, Seats.describe(t2, list))
  eq(tostring(Split.route(Seats, "gamepadpressed", t1, list)) .. ","
     .. tostring(Split.route(Seats, "gamepadpressed", t2, list)), "1,2",
     "twin pads: the first is player 1's, the second player 2's")
  Seats.reset()
end

-- 3. two worlds in one process ----------------------------------------------
do
  local homeInput = require("src.core.Input")
  local GameVersion = require("src.core.GameVersion")
  local home = Worlds.home()
  local w = Worlds.new("probe", { silent = true })
  local audio, thread = love.audio, love.thread
  love.audio, love.thread = love.audio or {}, love.thread or {}
  local seen = Worlds.run(w, function()
    return {
      input = require("src.core.Input"),
      version = require("src.core.GameVersion"),
      split = require("src.coop.split.Split"),
      audio = love.audio, thread = love.thread,
      lazy = (function() return require("src.core.Input") end)(),
    }
  end)
  check(seen.input ~= homeInput, "a world builds its own Input")
  check(seen.lazy == seen.input, "a require inside the world finds the world's module")
  check(seen.version == GameVersion, "the version is one per process")
  check(seen.split == Split, "and so is Split")
  check(seen.audio == nil and seen.thread == nil, "a silent world runs without love.audio and love.thread")
  check(love.audio ~= nil and love.thread ~= nil, "and they are back outside it")
  check(require("src.core.Input") == homeInput, "back home, home's Input")
  check(Worlds.run(w, function() return require("src.core.Input") end) == seen.input,
        "the world keeps its modules between runs")
  local ok, err = pcall(Worlds.run, w, function() error("boom", 0) end)
  check(not ok and err == "boom", "an error inside a world comes out")
  check(Worlds.current == home and require("src.core.Input") == homeInput,
        "after the way back home")
  Worlds.reset()
  check(require("src.core.Input") == homeInput, "a reset keeps home's modules")
  love.audio, love.thread = audio, thread
end

-- 4. CoopSettings: seat 2 plays in a slot of its own -------------------------
do
  local CoopSettings = require("src.coop.launcher.CoopSettings")
  local fs = memoryFs()
  local settings = CoopSettings.load(fs)
  local slots, active, n = {}, "slot1", 1
  local saves = {
    listSlots = function() local out = {} for id in pairs(slots) do out[#out + 1] = { id = id } end return out end,
    activeSlot = function() return active end,
    createSlot = function() n = n + 1 local id = "slot" .. n slots[id] = true return id end,
    renameSlot = function(_, id, name) slots[id] = name end,
    setActiveSlot = function(_, id) active = id end,
  }
  local CID = "c00000000000000aa"
  local s1 = settings:enterSlot(saves, "red", CID, "SUNDAY")
  local s2 = settings:enterSlot(saves, "red", CID, "SUNDAY P2", 2)
  check(s1 and s2 and s1 ~= s2, "seat 2 gets a slot of its own (" .. tostring(s1) .. ", " .. tostring(s2) .. ")")
  eq(slots[s2], "SUNDAY P2", "named after the campaign")
  eq(settings.restore.red, "slot1", "the solo slot to put back is the one before seat 1's")
  local again = CoopSettings.load(fs)
  eq(tostring(again.slots[CID].slot) .. "/" .. tostring(again.slots[CID].slot2), s1 .. "/" .. s2,
     "both slots are remembered")
  eq(again:enterSlot(saves, "red", CID, "SUNDAY P2", 2), s2, "and seat 2 plays in its slot again")
  -- a device that only ever had seat 2's slot (the development entry)
  local fs2 = memoryFs()
  local only = CoopSettings.load(fs2)
  local id = only:enterSlot(saves, "red", "c00000000000000bb", "X P2", 2)
  eq(CoopSettings.load(fs2).slots["c00000000000000bb"].slot2, id, "a slot2-only entry survives a reload")
end

-- 5. the development entry and seat 2's log file -------------------------------
do
  local Dev = require("src.coop.session.Dev")
  local function env(t) return function(k) return t[k] end end
  local cfg = Dev.parse({ "--coop-host", "--coop-split=BLUE" }, env({}))
  check(cfg.split == true and cfg.splitName == "BLUE", "--coop-split=BLUE adds player 2 named BLUE")
  cfg = Dev.parse({ "--coop-host" }, env({ POKEPORT_COOP_SPLIT = "1" }))
  check(cfg.split == true and cfg.splitName == nil, "POKEPORT_COOP_SPLIT=1 adds player 2 with the default name")
  cfg = Dev.parse({ "--coop-join=10.0.0.2" }, env({}))
  check(not cfg.split, "no split without asking")
  local SessionLog = require("src.coop.session.SessionLog")
  local opened = {}
  local logFs = {
    mkdir = function() end, list = function() return {} end, size = function() return 0 end,
    remove = function() end,
    open = function(path) opened[#opened + 1] = path return { write = function() end, flush = function() end, close = function() end } end,
  }
  SessionLog.open({ fs = logFs, device = "ab12", seat = 1, stamp = "20261015-120000" })
  SessionLog.open({ fs = logFs, device = "ab12", seat = 2, stamp = "20261015-120000" })
  eq(opened[1], "coop/logs/session-20261015-120000-ab12.jsonl", "seat 1's log keeps its name")
  eq(opened[2], "coop/logs/session-20261015-120000-ab12-seat2.jsonl", "seat 2 writes a file of its own")
end

-- 6. the whole path: host, seat 2's world, two pads, two avatars ---------------

-- a fixture overworld game in the current world (main.lua's game for
-- player 1, seat 2's in its own world)
local function fixtureGame(name)
  local Data = T.fixtures.fresh()
  Data.tilesets.FIX_OUT.tilesPerRow = 16
  -- Map reads walkable tiles as a list (the fixture's set walks nowhere)
  Data.tilesets.FIX_OUT.walkable = { 0, 1, 2 }
  Data.field.flyWarps = Data.field.flyWarps or {}
  Data.field.playerSprites = { walk = "SPRITE_FIX_PLAYER", bike = "SPRITE_FIX_NPC" }
  Data.field.waterTilesets = {}
  Data.field.forcedMovement = { tiles = {} }
  local Game = require("src.core.Game")
  local Input = require("src.core.Input")
  local StateStack = require("src.core.StateStack")
  local Renderer = require("src.render.Renderer")
  local SaveData = require("src.core.SaveData")
  local OW = require("src.world.OverworldController")
  Game.data = Data
  Game.input = Input; Input:init()
  Game.renderer = Renderer; Renderer:init()
  Game.stack = StateStack; StateStack:init()
  Game.save = SaveData.newGame()
  Game.save.player.name = name
  StateStack:push(OW, "FIX_TOWN", 5, 6, "down")
  Game.overworld = StateStack:top()
  -- main.lua's loop: one logic step per frame
  rawset(Game, "update", function(self, dt)
    self.input:step()
    self.stack:update(dt)
  end)
  rawset(Game, "draw", function() end)
  return Game
end

do
  local Identity = require("src.coop.session.Identity")
  local Session = require("src.coop.session.Session")
  local Seats = require("src.coop.game.Seats")
  local CoopSettings = require("src.coop.launcher.CoopSettings")
  local SHA = ("ab"):rep(20)
  local CID = "c00000000000000c2"
  local function memoryStore()
    local text
    return { read = function() return text end, write = function(t) text = t end }
  end

  Seats.reset()
  local game1 = fixtureGame("HOST")
  local s = Session.startHost({
    campaign = { id = CID, title = "Fix world" },
    cartridge = { game = "red", sha1 = SHA }, name = "HOST",
    listen = false, beacon = false, log = false, campaignFs = false,
    identity = Identity.load(memoryStore()),
  })
  for _ = 1, 3 do s:update(1 / 60, game1) end
  eq(s.status, "joined", "this device hosts and its own player is in")

  -- the launcher's settings: pad A is player 1's, pad B player 2's
  local fs = memoryFs()
  local settings = CoopSettings.load(fs)
  settings.seats = { Seats.describe(padA, connected), Seats.describe(padB, connected) }
  settings:save()

  -- main.lua's input handlers, as far as this test needs them
  local delivered = {}
  love.gamepadpressed = function(j, b) delivered[#delivered + 1] = "1:" .. b; game1:gamepadpressed(j, b) end
  love.gamepadreleased = function(j, b) game1:gamepadreleased(j, b) end

  local booted
  Split.request({ name = "BLUE", settings = CoopSettings.load(fs), boot = function(sp)
    booted = fixtureGame("BLUE")
    -- what Split's own boot does around Game:load
    local S2 = require("src.coop.split.Split") -- shared: the same table
    check(S2 == Split, "Split is the same inside seat 2's world")
    require("src.core.Input").seat = 2
    local Seats2 = require("src.coop.game.Seats")
    Seats2.load(CoopSettings.load(fs))
    Seats2.setMode("couch")
    check(Seats2 ~= Seats, "seat 2's world has its own Seats")
    return booted
  end })
  Split.frame(game1)
  local sp = Split.current
  check(sp ~= nil, "Split starts once player 1's game runs")
  eq(Seats.mode, "couch", "player 1's seats switch to couch co-op")

  -- frames: player 1's session and game (main.lua), which step seat 2's
  local function frames(n)
    for _ = 1, n do
      s:update(1 / 60, game1)
      game1:update(1 / 60)
    end
  end
  frames(10)
  eq(sp.status, "playing", "seat 2 joined and its game runs (" .. tostring(sp.reason) .. ")")
  check(sp.game == booted and booted ~= game1, "seat 2's game is a game of its own")
  local names, seat2 = {}, nil
  for _, p in ipairs(s.host.players) do
    names[#names + 1] = p.name
    if p.name == "BLUE" then seat2 = p end
  end
  table.sort(names)
  eq(table.concat(names, ","), "BLUE,HOST", "the host has both players")
  check(seat2 and seat2.seat == 2 and seat2.device == s.identity.device,
        "seat 2 is this device's second seat")
  check(sp.session.identity == s.identity, "both seats remember their players in one identity")
  eq(s.identity:known("loopback", 2)[CID], seat2 and seat2.id,
     "seat 2's player is remembered for seat 2 (for the next session)")
  local saved = CoopSettings.load(fs).slots[CID]
  check(saved and saved.slot2, "seat 2 entered a save slot of its own in the campaign")

  local function cell(game)
    local p = game.overworld.player
    return p.cellX .. "," .. p.cellY
  end
  local function hold(p, button, n)
    p.down[button] = true
    love.gamepadpressed(p, button)
    frames(n)
    p.down[button] = nil
    love.gamepadreleased(p, button)
    frames(20)
  end
  local a1, a2 = cell(game1), cell(booted)
  hold(padA, "dpleft", 30)
  local b1, b2 = cell(game1), cell(booted)
  check(b1 ~= a1, "pad A walks player 1 (" .. a1 .. " -> " .. b1 .. ")")
  eq(b2, a2, "and leaves player 2 standing")
  local count = #delivered
  hold(padB, "dpdown", 30)
  local c1, c2 = cell(game1), cell(booted)
  check(c2 ~= b2, "pad B walks player 2 (" .. b2 .. " -> " .. c2 .. ")")
  eq(c1, b1, "and leaves player 1 standing")
  eq(#delivered, count, "player 1's game never saw pad B's events")
  frames(5)
  local p2
  for _, p in ipairs(s.host.players) do if p.name == "BLUE" then p2 = p end end
  eq(p2 and (p2.x .. "," .. p2.y), c2, "the host sees player 2 where seat 2's game put them")

  -- stopping: seat 2 leaves, its world goes, the handlers come back
  local wrapped = love.gamepadpressed
  Split.stop()
  check(Split.current == nil, "Split stops")
  check(love.gamepadpressed ~= wrapped, "the window's handlers are put back")
  frames(3)
  local left
  for _, p in ipairs(s.host.players) do if p.name == "BLUE" then left = p end end
  check(left and left.connected == false, "seat 2 said goodbye to the host")
  eq(Seats.mode, "solo", "player 1's seats are back to solo")
  check(Worlds.homeWorld == nil, "the second world is gone")
end

T.finish()
