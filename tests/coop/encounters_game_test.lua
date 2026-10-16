-- Unique encounters in the running game (#21, design A10.2 to A10.4),
-- ROM-free: the fixture overworld runs headless with this device hosting
-- a session in-process; BLUE is a partner on the loopback hub whose
-- reports and commands this test sends.  Covered: the encounter a battle
-- is (a trainer or a static Pokémon by its map object, nothing for grass);
-- the sight gate (a trainer BLUE is fighting does not spot RED, and spots
-- RED again once that fight was lost or fled); RED's world walking into
-- BLUE's trainer fight joins it, and the world's own battle becomes the
-- copy, keeps its onFinish and marks the trainer beaten after the win; a
-- trainer the campaign beat counts as won without a fight; a static
-- Pokémon's talk path names its encounter; a walk-in into a full fight
-- ends without one and leaves the encounter standing.
--   luajit tests/coop/encounters_game_test.lua

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
-- the fixture route's NPC is a trainer facing down, two cells of sight
local trainerDef = Data.maps.FIX_ROUTE.objects[1]
trainerDef.trainerClass, trainerDef.trainerParty = "OPP_FIX_YOUNGSTER", 1
-- and the town has a one-off wild Pokémon
table.insert(Data.maps.FIX_TOWN.objects, {
  index = 2, name = "FIXTOWN_STATIC", sprite = "SPRITE_FIX_NPC", movement = "STAY", range = "NONE",
  text = "TEXT_FIXTOWN_GREETER", x = 7, y = 7, pokemon = "FIXMON_B", level = 3,
})

local Game       = require("src.core.Game")
local Input      = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local Renderer   = require("src.render.Renderer")
local SaveData   = require("src.core.SaveData")
local Pokemon    = require("src.pokemon.Pokemon")
local OW         = require("src.world.OverworldController")
local BattleState = require("src.battle.BattleState")
require("src.battle.TypeChart").load(Data)

local Identity = require("src.coop.session.Identity")
local Session  = require("src.coop.session.Session")
local Client   = require("src.coop.session.Client")
local Replica  = require("src.coop.battle.Replica")
local Battles  = require("src.coop.game.Battles")
local Notices  = require("src.coop.game.Notices")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.save.flags.EVENT_GOT_STARTER = true -- past the opening (#22)
Game.save.player.name, Game.save.player.id = "RED", 1111
Game.save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
Game.save.money = 500
local stack = Game.stack
stack:push(OW, "FIX_ROUTE", 5, 11, "up")
local ow = stack:top()
Game.overworld = ow
local trainer = ow.npcPool["FIX_ROUTE_obj_1"]
trainer.facing = "down"
local KEY = "trainer:FIX_ROUTE_obj_1"

local SHA = ("ab"):rep(20)
local function memoryStore()
  local text
  return { read = function() return text end, write = function(t) text = t end }
end

local blue
local blueHold = false -- BLUE answers nothing while true
local others = {}
local blueAnswers = {}
-- BLUE answers its menu questions with its first move (it has no copy of
-- its own here; RED's copy reports where the battle stands)
local function blueDecides()
  for id, rec in pairs(blue.battles) do
    if not blueHold and rec.ask == "menu" and rec.by == blue.player and not rec.ended and blueAnswers[id] ~= rec.rev then
      blueAnswers[id] = rec.rev
      blue:battleCmd(id, rec.rev, { kind = "move", slot = 1 })
    end
  end
end

local tick = 0
local function step(n)
  for _ = 1, n or 1 do
    tick = tick + 1
    if tick % 2 == 0 and stack:top() ~= ow then
      Input:sourcePress("a", "test")
    else
      Input:sourceRelease("a", "test")
    end
    Input:step()
    local s = Session.current
    if s then s:update(1 / 60, Game) end
    if blue then blue:update(); blueDecides() end
    for _, c in ipairs(others) do c:update() end
    stack:update(1 / 60)
  end
end
local function until_(fn, limit)
  for i = 1, limit or 5000 do
    if fn() then return i end
    step(1)
  end
  return nil
end

-- the encounter a battle is ------------------------------------------------------
do
  local t = BattleState.newTrainer(Game, "OPP_FIX_YOUNGSTER", 1)
  eq(Battles.encounterOf(t, trainer), KEY, "a trainer is its map object")
  local w = BattleState.newWild(Game, "FIXMON_B", 2)
  eq(Battles.encounterOf(w, nil), nil, "a battle in the grass is no encounter")
  eq(Battles.encounterOf(w, { id = "FIX_TOWN_obj_2" }), "static:FIX_TOWN_obj_2",
     "a wild Pokémon a map object started is a static one")
  eq(Battles.encounterOf(t, { id = "rival_sprite" }), nil, "a sprite that is no map object is none")
end

-- the session ---------------------------------------------------------------------
local s = Session.startHost({
  campaign = { id = "c0001", title = "Fix co-op" },
  cartridge = { game = "red", sha1 = SHA }, name = "HOST",
  listen = false, beacon = false, log = false,
  identity = Identity.load(memoryStore()),
})
step(3)
blue = Client.new(s.hub:dial(), { name = "BLUE", game = "red", sha1 = SHA, device = "b1", seat = 1 })
blue:join()
step(3)
eq(blue.status, "joined", "BLUE joined")
blue:move("FIX_ROUTE", 5, 7, "down", true, "walk")
step(2)

local function blueTeam(level, n)
  local mons = {}
  for i = 1, n or 1 do
    mons[i] = Pokemon.new(Data, "FIXMON_C", level)
    mons[i].otId, mons[i].ot = 2222, "BLUE"
  end
  return Replica.packTeam(mons)
end
local function trainerOpening(map)
  local enemy = Replica.packTeam(BattleState.newTrainer(Game, "OPP_FIX_YOUNGSTER", 1).enemyParty)
  return { kind = "trainer", enemy = enemy, map = map or "FIX_ROUTE", foe = "YOUNGSTER",
           trainer = { class = "OPP_FIX_YOUNGSTER", index = 1 }, encounter = KEY }
end
local function blueOpens(opening, team)
  blue:battleOpen(opening, team or blueTeam(20), 2222, false)
  step(3)
  for id, rec in pairs(blue.battles) do
    if rec.open and rec.open.by == blue.player and not rec.ended then return id end
  end
end

-- the sight gate (A10.4) -------------------------------------------------------------
do
  ow:checkTrainerSight()
  check(ow.engaging, "the trainer spots RED when nobody fights it")
  -- undo the approach: a fresh look later
  ow.engaging, trainer.frozen = false, false
  while stack:top() ~= ow do stack:pop() end
  ow.scriptQueue, ow.script = nil, nil
  local id = blueOpens(trainerOpening())
  check(id ~= nil, "BLUE fights the trainer")
  eq(Battles.engaged(trainer), true, "the host names it in a battle")
  ow:checkTrainerSight()
  check(not ow.engaging, "so it does not spot RED (A10.4)")
  blue:battleAt(id, 1, nil, nil, nil, "run")
  step(3)
  eq(Battles.engaged(trainer), false, "BLUE's fight ended without a win: released")
  eq(s.host.state.encounters[KEY], nil, "and not done")
  blue.battles = {}
end

-- RED's world walks into BLUE's fight: it joins (A10.2) ------------------------------
do
  -- BLUE waits at its first question for RED (BLUE has no copy here to
  -- report the next one)
  blueHold = true
  local id = blueOpens(trainerOpening())
  blue:battleAt(id, 1, "menu", blue.player, "x")
  step(2)
  local done
  ow:engageTrainer(trainer, function() done = true end, nil, true)
  local battle
  until_(function()
    local top = stack:top()
    if top and top.coop then battle = top end
    return battle ~= nil
  end, 2000)
  blueHold = false
  check(battle ~= nil, "RED's own battle became a co-op copy")
  eq(battle and battle.coop.id, id, "of BLUE's fight, not a second one (A10.1)")
  eq(battle and #battle.coop.roster, 2, "BLUE's team and RED's")
  eq(battle and Replica.owner(battle, battle.coop.roster[2]), s.client.player, "RED's behind BLUE's")
  local n = 0
  for _ in pairs(s.host.battles) do n = n + 1 end
  eq(n, 1, "the host runs one battle")
  until_(function() return done end, 40000)
  check(done, "the world's own onFinish ran")
  eq(battle and battle.result, "win", "the fight was won")
  eq(Game.save.defeatedTrainers.FIX_ROUTE_obj_1, true, "RED's world marks the trainer beaten")
  eq(s.host.state.encounters[KEY] and s.host.state.encounters[KEY].state, "done",
     "done for the campaign")
  step(3)
  eq(stack:top(), ow, "RED is back on the map")
  blue.battles = {}
end

-- a trainer the campaign beat counts as won (A10.2) -----------------------------------
do
  Game.save.defeatedTrainers.FIX_ROUTE_obj_1 = nil -- the story has not reached RED yet
  local money = Game.save.money
  local done
  ow:engageTrainer(trainer, function() done = true end, nil, true)
  until_(function() return done end, 2000)
  check(done, "the world's onFinish ran without a fight")
  eq(Game.save.defeatedTrainers.FIX_ROUTE_obj_1, true, "and heard a win")
  eq(Game.save.money, money, "no prize")
  check(table.concat(Notices.texts(), "|"):find("YOUNGSTER was already beaten.", 1, true)
        or table.concat(Notices.texts(), "|"):find("was already beaten.", 1, true),
        "a notice says it was already beaten")
  eq(next(s.host.battles), nil, "no battle runs")
  until_(function() return stack:top() == ow end, 600)
  eq(stack:top(), ow, "RED is on the map")
end

-- a static Pokémon names its encounter (A10.3) ----------------------------------------
do
  local opened
  local take = Battles.take
  Battles.take = function(game, battle, npc)
    opened = Battles.encounterOf(battle, npc)
    battle.onFinish = function() end
    return "held"
  end
  ow:startWarpTo("FIX_TOWN", 7, 8, "up", function() end)
  until_(function() return ow.map.id == "FIX_TOWN" and stack:top() == ow end, 600)
  local static = ow.npcPool["FIX_TOWN_obj_2"]
  check(static ~= nil, "the town's static Pokémon stands there")
  if static then ow:talkTo(static) end
  until_(function() return opened ~= nil end, 300)
  Battles.take = take
  eq(opened, "static:FIX_TOWN_obj_2", "talking to it opens its encounter")
  while stack:top() ~= ow do stack:pop() end
end

-- a walk-in into a full fight ends without one (A8.5) ------------------------------------
do
  local yellow = Client.new(s.hub:dial(), { name = "YELLOW", game = "red", sha1 = SHA,
                                            device = "c1", seat = 1 })
  yellow:join()
  others[#others + 1] = yellow
  until_(function() return yellow.status == "joined" end, 300)
  eq(yellow.status, "joined", "YELLOW joined")
  s.host.state.encounters[KEY] = nil
  s.host.state.commits["victory:" .. KEY] = nil
  blueHold = true
  local id = blueOpens(trainerOpening("FIX_TOWN"), blueTeam(20, 6))
  blue:battleAt(id, 1, "menu", blue.player, "x")
  step(2)
  yellow:battleJoin(id, blueTeam(9, 6), 3333, false)
  step(3)
  eq(require("src.coop.battle.HostBattles").rosterSize(s.host.battles[id]), 12, "BLUE's and YELLOW's teams fill it")
  local result
  local battle = BattleState.newTrainer(Game, "OPP_FIX_YOUNGSTER", 1)
  battle.onFinish = function(r) result = r end
  ow:pushBattle(battle, trainer)
  until_(function() return result ~= nil end, 2000)
  eq(result, "run", "the world's battle ends without a fight")
  check(table.concat(Notices.texts(), "|"):find("The battle is full.", 1, true), "saying the battle is full")
  eq(s.host.state.encounters[KEY], nil, "the trainer is not beaten")
  check(s.host.battles[id] ~= nil, "and BLUE's fight goes on")
end

T.finish()
