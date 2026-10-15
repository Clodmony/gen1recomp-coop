-- Wild Pokémon from both versions in the running game (#9, design A13.3,
-- A13.4), ROM-free: the fixture overworld runs headless with this device
-- hosting a Red session in-process; BLUE is a partner on the loopback hub.
-- Covered: the window sends its own wild slots once a link; with the
-- campaign's switch on it gets Blue's once a Blue player sent them; the
-- world's own grass roll then takes Blue's Pokémon of the same slot on
-- the upper half of a third 0-255 roll, at Red's level, only where Red has
-- no such wild Pokémon, and draws nothing more where the slot has none;
-- without the switch the encounter stream is the cartridge's.
--   luajit tests/coop/versions_game_test.lua

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

local GameVersion = require("src.core.GameVersion")
local Game       = require("src.core.Game")
local Input      = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local Renderer   = require("src.render.Renderer")
local SaveData   = require("src.core.SaveData")
local Pokemon    = require("src.pokemon.Pokemon")
local OW         = require("src.world.OverworldController")
require("src.battle.TypeChart").load(Data)

local Identity = require("src.coop.session.Identity")
local Session  = require("src.coop.session.Session")
local Client   = require("src.coop.session.Client")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.save.flags.EVENT_GOT_STARTER = true
Game.save.player.name, Game.save.player.id = "RED", 1111
Game.save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
local stack = Game.stack
stack:push(OW, "FIX_ROUTE", 5, 11, "up")
local ow = stack:top()
Game.overworld = ow

local SHA = { red = GameVersion.info("red").sha1, blue = GameVersion.info("blue").sha1 }
local function memoryStore()
  local text
  return { read = function() return text end, write = function(t) text = t end }
end

local partners = {}
local function step(n)
  for _ = 1, n or 1 do
    Input:step()
    local s = Session.current
    if s then s:update(1 / 60, Game) end
    for _, c in ipairs(partners) do c:update() end
  end
end

-- the world's generator, scripted: each draw takes the next number
local draws = 0
local function script(list)
  draws = 0
  love.math.random = function(lo, hi)
    draws = draws + 1
    assert(lo == 0 and hi == 255, "a 0-255 draw")
    return list[draws] or 255
  end
end

-- the fixture route: slot 1 FIXMON_A L3, slot 2 FIXMON_C L4 (buckets 51, 102)
local BLUE_WILD = { FIX_ROUTE = { grass = { { species = "FIXMON_A", level = 3 },
                                            { species = "FIXMON_B", level = 9 } } } }

local function host(mix)
  return Session.startHost({
    campaign = { id = "c0001", title = "Fix co-op", mix = mix },
    cartridge = { game = "red", sha1 = SHA.red }, name = "HOST",
    listen = false, beacon = false, log = false, campaignFs = false,
    identity = Identity.load(memoryStore()),
  })
end

do
  local s = host(true)
  step(3)
  local mine = s.host.wild.red
  check(mine and mine.FIX_ROUTE and mine.FIX_ROUTE.grass[2].species == "FIXMON_C",
    "RED's window sent its own wild slots once in")
  eq(s.host:wildWaiting(), "blue", "the host waits for a Blue player")
  local blue = Client.new(s.hub:dial(), { name = "BLUE", game = "blue", sha1 = SHA.blue,
                                          device = "b1", seat = 1 })
  partners = { blue }
  blue:join()
  step(3)
  eq(blue.status, "joined", "BLUE joins RED's campaign")
  eq(blue.wild and blue.wild.game, "red", "BLUE holds Red's tables")
  eq(s.client.wild, nil, "RED holds nothing before Blue's arrive")
  script({ 0, 60 })
  local enc = ow:rollEncounter(Data.encounters.FIX_ROUTE, "grass")
  eq(enc and enc.species, "FIXMON_C", "until then RED's world keeps its own")
  eq(draws, 2, "and draws only the cartridge's two numbers")
  blue:sendWild(BLUE_WILD)
  step(3)
  eq(s.client.wild and s.client.wild.game, "blue", "RED's window holds Blue's tables")

  script({ 0, 60, 200 })
  enc = ow:rollEncounter(Data.encounters.FIX_ROUTE, "grass")
  eq(enc and enc.species, "FIXMON_B", "an upper-half roll brings Blue's Pokémon of slot 2")
  eq(enc and enc.level, 4, "at Red's level for the slot")
  eq(draws, 3, "the world's own generator draws the third number")
  script({ 0, 60, 127 })
  enc = ow:rollEncounter(Data.encounters.FIX_ROUTE, "grass")
  eq(enc and enc.species, "FIXMON_C", "a lower-half roll keeps Red's")
  script({ 0, 10, 255 })
  enc = ow:rollEncounter(Data.encounters.FIX_ROUTE, "grass")
  eq(enc and enc.species, "FIXMON_A", "a shared slot keeps Red's")
  eq(draws, 2, "with no third draw")
  script({ 200 })
  enc = ow:rollEncounter(Data.encounters.FIX_ROUTE, "grass")
  eq(enc, nil, "no encounter on this step: nothing to stand in")
  eq(draws, 1, "one draw, as the cartridge's")
  s:leave()
  step(2)
end

do
  local s = host(false)
  step(3)
  local blue = Client.new(s.hub:dial(), { name = "BLUE", game = "blue", sha1 = SHA.blue,
                                          device = "b2", seat = 1 })
  partners = { blue }
  blue:join()
  step(3)
  blue:sendWild(BLUE_WILD)
  step(3)
  eq(s.client.wild, nil, "without the switch RED never gets Blue's tables")
  script({ 0, 60, 255 })
  local enc = ow:rollEncounter(Data.encounters.FIX_ROUTE, "grass")
  eq(enc and enc.species, "FIXMON_C", "and keeps the cartridge's encounter")
  eq(draws, 2, "and its stream")
  s:leave()
  step(2)
end

T.finish()
