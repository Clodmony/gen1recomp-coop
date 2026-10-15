-- The shared world in the game (#14, design A5.4 to A5.6, A5.11), ROM-free:
-- the fixture overworld runs headless with this device hosting a session
-- in-process and a partner window (a client and a plain save) on its
-- loopback hub.  What holds the player keeps the window from sending or
-- taking; a partner's hidden object leaves the live map at a rest point; the
-- game's own flag reaches the partner; START > SAVE sends the scene so far;
-- Vermilion keeps its trash-can locks while a partner is there.
--   luajit tests/coop/shared_world_game_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local check, eq = T.check, T.eq

local Data = T.fixtures.fresh()
Data.tilesets.FIX_OUT.tilesPerRow = 16
Data.field.flyWarps = Data.field.flyWarps or {}
Data.field.playerSprites = { walk = "SPRITE_FIX_PLAYER", bike = "SPRITE_FIX_NPC" }
Data.field.waterTilesets = {}
Data.field.forcedMovement = { tiles = {} }

local Game       = require("src.core.Game")
local Input      = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local Renderer   = require("src.render.Renderer")
local SaveData   = require("src.core.SaveData")
local Pokemon    = require("src.pokemon.Pokemon")
local OW         = require("src.world.OverworldController")
local TextBox    = require("src.render.TextBox")

local Identity = require("src.coop.session.Identity")
local Session  = require("src.coop.session.Session")
local Client   = require("src.coop.session.Client")
local Window   = require("src.coop.campaign.Window")
local SharedWorld = require("src.coop.game.SharedWorld")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.save.player.name = "HOST"
Game.save.party = { Pokemon.new(Data, "FIXMON_A", 20) }
local stack = Game.stack
stack:push(OW, "FIX_TOWN", 5, 6, "down")
Game.overworld = stack:top()
local ow = Game.overworld

local SHA = ("ab"):rep(20)
local CID = "c00000000000000c2"
local function memoryStore()
  local text
  return { read = function() return text end, write = function(t) text = t end }
end

local partner -- { c, w, save, map }
local function step(n)
  for _ = 1, n or 1 do
    local s = Session.current
    if s then s:update(1 / 60, Game) end
    if partner then
      partner.c:update()
      partner.w:update({ save = partner.save, map = partner.map, still = true })
    end
    stack:update(1 / 60)
  end
end

local function greeterShown()
  for _, npc in ipairs(ow.npcs) do
    if npc.def and npc.def.name == "FIXTOWN_GREETER" then return true end
  end
  return false
end

-- what holds the player (A5.4) ---------------------------------------------------
eq(SharedWorld.busy(Game), nil, "the overworld on top, nothing running: a rest point")
ow.transitioning = true
eq(SharedWorld.busy(Game), "map_load", "a warp holds the player")
ow.transitioning = nil
ow.scriptMoves[#ow.scriptMoves + 1] = { entity = ow.player, dir = "up", remaining = 1 }
eq(SharedWorld.busy(Game), "forced_walk", "a scripted walk holds the player")
table.remove(ow.scriptMoves)
ow.engaging = true
eq(SharedWorld.busy(Game), "trainer", "a trainer's approach holds the player")
ow.engaging = nil
ow.flyAnim = {}
eq(SharedWorld.busy(Game), "flyAnim", "an animation holds the player")
ow.flyAnim = nil
local box = TextBox.new(Game, "HELLO")
stack:push(box)
eq(SharedWorld.busy(Game), "above", "a text box above the overworld holds the player")
stack:pop()
local realRunning = ow.runner.isRunning
ow.runner.isRunning = function() return true end
eq(SharedWorld.busy(Game), "script", "a running script holds the player")
ow.runner.isRunning = realRunning
ow.player.moving = true
eq(SharedWorld.busy(Game), nil, "a step of the player's own does not")
eq(SharedWorld.frame(Game).still, false, "but the window knows the player is between cells")
ow.player.moving = false
eq(SharedWorld.busy(nil), "no_overworld", "no game: no rest point")

-- a session: this device hosts, BLUE's window dials in -----------------------------
local s = Session.startHost({
  campaign = { id = CID, title = "Fix world" },
  cartridge = { game = "red", sha1 = SHA }, name = "HOST",
  listen = false, beacon = false, log = false, campaignFs = false,
  identity = Identity.load(memoryStore()),
})
check(s, "hosting")
step(3)
eq(s.status, "joined", "the host's own player is in")
local c = Client.new(s.hub:dial(), { name = "BLUE", game = "red", sha1 = SHA, device = "b1" })
c:join()
partner = { c = c, w = Window.new(c), save = SaveData.newGame(), map = "FIX_ROUTE" }
partner.save.player.name = "BLUE"
step(8)
eq(c.status, "joined", "BLUE joined")
check(s.window and s.window:resting(), "the host's game has a window at a rest point")

-- the game's own flag reaches the partner ------------------------------------------
Game.save.flags.EVENT_FIX_STORY = true
step(8)
eq(s.host.state.story["flags/EVENT_FIX_STORY"], true, "the game's flag reached the campaign")
eq(partner.save.flags.EVENT_FIX_STORY, true, "and BLUE's world")

-- a partner's hidden object leaves the live map (A5.6) --------------------------------
check(greeterShown(), "the greeter stands in FIX TOWN")
stack:push(TextBox.new(Game, "WAIT"))
partner.save.objectToggles = { FIX_TOWN = { FIXTOWN_GREETER = false } }
step(8)
eq(Game.save.objectToggles and Game.save.objectToggles.FIX_TOWN
   and Game.save.objectToggles.FIX_TOWN.FIXTOWN_GREETER, nil,
   "while a text box holds the player, nothing is taken (A5.5)")
check(greeterShown(), "and the greeter stays")
stack:pop()
step(8)
eq(Game.save.objectToggles.FIX_TOWN.FIXTOWN_GREETER, false, "at the rest point the hide lands")
check(not greeterShown(), "and the greeter leaves the live map")
eq(ow.map.id, "FIX_TOWN", "the player stays where they were")
eq(ow.player.cellX, 5, "on their cell")

-- START > SAVE sends the scene so far (A5.5) --------------------------------------------
stack:push(TextBox.new(Game, "SAVING"))
Game.save.flags.EVENT_FIX_SAVED = true
step(4)
eq(s.host.state.story["flags/EVENT_FIX_SAVED"], nil, "held: the change waits")
Game:writeSave("menu")
step(4)
eq(s.host.state.story["flags/EVENT_FIX_SAVED"], true, "a save sends it at once")
stack:pop()

-- Vermilion's first lock (A5.11) ---------------------------------------------------------
local story = require("data.scripts.story")
local onEnter = story.VERMILION_CITY.onEnter
Game.save.trashPuzzle = { first = 6 }
local rolls = 0
local realRandom = love.math.random
love.math.random = function(...) rolls = rolls + 1 return 2 end
onEnter(Game, ow)
eq(Game.save.trashPuzzle.first, 4, "nobody else in Vermilion: entering rolls the lock (2 * 2)")
Game.save.trashPuzzle.first = 6
c:move("VERMILION_GYM", 3, 4, "up", true, "walk")
step(4)
onEnter(Game, ow)
eq(Game.save.trashPuzzle.first, 6, "a partner in the gym: entering keeps the campaign's locks")
c:move("VERMILION_CITY", 3, 4, "up", true, "walk")
step(4)
onEnter(Game, ow)
eq(Game.save.trashPuzzle.first, 6, "a partner in the city too")
c:leave()
partner = nil
step(4)
onEnter(Game, ow)
eq(Game.save.trashPuzzle.first, 4, "a dropped partner does not count")
love.math.random = realRandom
check(rolls >= 2, "the cartridge's roll ran when nobody kept the lock")

s:leave()
T.finish()
