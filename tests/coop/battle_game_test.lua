-- Co-op battles in the running game (#18, design A8), ROM-free: the
-- fixture overworld runs headless with this device hosting a session
-- in-process; BLUE is a partner on the loopback hub whose commands this
-- test sends.  Covered: a battle the world opens becomes the host's co-op
-- battle and keeps the world's own onFinish; a partner joins it and
-- decides when their Pokémon is out; the world's Pokémon get the battle's
-- result; a refused opening is fought alone (A8.22), and so is a battle
-- in a solo game; the CO-OP menu offers JOIN <NAME>, and joining builds
-- the battle, catches up without its intro and comes in on the world's
-- battle transition; RUN by the opener ends it for everyone.
--   luajit tests/coop/battle_game_test.lua

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
local BattleState = require("src.battle.BattleState")
require("src.battle.TypeChart").load(Data)

local Identity = require("src.coop.session.Identity")
local Session  = require("src.coop.session.Session")
local Client   = require("src.coop.session.Client")
local Presence = require("src.coop.game.Presence")
local CoopMenu = require("src.coop.game.CoopMenu")
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
Game.save.party = { Pokemon.new(Data, "FIXMON_A", 14) }
Game.save.money = 500
local stack = Game.stack
stack:push(OW, "FIX_TOWN", 5, 6, "down")
local ow = stack:top()
Game.overworld = ow

local SHA = ("ab"):rep(20)
local function memoryStore()
  local text
  return { read = function() return text end, write = function(t) text = t end }
end

-- BLUE answers what the battle asks of BLUE: the opener runs, a
-- replacement takes the first standing Pokémon, a choice says YES
local blue
local blueHold = false -- BLUE answers nothing while true
local others = {} -- more partners, updated every frame
local blueAnswers = {}
local function blueDecides()
  for id, rec in pairs(blue.battles) do
    local b = stack:top()
    -- (only once RED's copy runs it: BLUE has no copy of its own here)
    if not blueHold and b and b.coop and b.coop.id == id and rec.ask and rec.by == blue.player
       and not rec.ended and blueAnswers[id] ~= rec.rev then
      local cmd
      if rec.ask == "menu" then
        cmd = rec.open.by == blue.player and { kind = "run" } or { kind = "move", slot = 1 }
      elseif rec.ask == "choice" then
        cmd = { kind = "choice", yes = true }
      elseif rec.ask == "replace" and b and b.coop then
        for i, m in ipairs(b.coop.roster) do
          if m.hp > 0 then cmd = { kind = "replace", index = i }; break end
        end
      end
      if cmd then
        blueAnswers[id] = rec.rev
        blue:battleCmd(id, rec.rev, cmd)
      end
    end
  end
end

local tick = 0
local function step(n)
  for _ = 1, n or 1 do
    tick = tick + 1
    -- A every other frame: the text pages and the first menu row
    -- (not on the map: A there talks to the fixture's nothing)
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
    Presence.step(Game)
  end
end

local function until_(fn, limit)
  for i = 1, limit or 5000 do
    if fn() then return i end
    step(1)
  end
  return nil
end

local function topBattle()
  local t = stack:top()
  return t and t.isBattle ~= false and t.coop and t or nil
end

-- solo: a battle is the world's own -------------------------------------------
do
  local battle = BattleState.newWild(Game, "FIXMON_B", 2)
  Battles.take(Game, battle)
  eq(battle.coopPending, nil, "solo: nothing is sent, the battle stays the world's")
end

-- battles that stay in the window (A8.19) ----------------------------------------------
do
  local w = BattleState.newWild(Game, "FIXMON_B", 2)
  eq(Battles.joinable(w), true, "a wild battle is a co-op battle")
  w.safari = { balls = 30 }
  eq(Battles.joinable(w), false, "the Safari Zone stays in the window")
  w.safari, w.ghost = nil, true
  eq(Battles.joinable(w), false, "a GHOST without the SILPH SCOPE too")
  w.ghost, w.demo = nil, true
  eq(Battles.joinable(w), false, "and the old man's demo")
  local t = BattleState.newTrainer(Game, "OPP_FIX_YOUNGSTER", 1)
  eq(Battles.joinable(t), true, "a trainer battle is a co-op battle")
end

-- the session ---------------------------------------------------------------------
local s = Session.startHost({
  campaign = { id = "c0001", title = "Fix co-op" },
  cartridge = { game = "red", sha1 = SHA }, name = "HOST",
  listen = false, beacon = false, log = false,
  identity = Identity.load(memoryStore()),
})
step(3)
eq(s.status, "joined", "the host's own player is in")
blue = Client.new(s.hub:dial(), { name = "BLUE", game = "red", sha1 = SHA, device = "b1", seat = 1 })
blue:join()
step(3)
eq(blue.status, "joined", "BLUE joined")
blue:sendOpening(true) -- past the opening (#22)
blue:move("FIX_ROUTE", 3, 3, "down", true, "walk")
step(2)

local function blueTeam(level)
  local mons = { Pokemon.new(Data, "FIXMON_C", level) }
  mons[1].otId, mons[1].ot = 2222, "BLUE"
  return Replica.packTeam(mons)
end

-- the world opens a wild battle: it becomes the host's co-op battle -------------
do
  local finished
  local battle = BattleState.newWild(Game, "FIXMON_B", 4)
  battle.onFinish = function(result)
    finished = result
    ow:afterBattle(result, battle)
  end
  ow:pushBattle(battle)
  check(battle.coopPending ~= nil, "the opening went to the host")
  until_(function() return battle.coop ~= nil end, 200)
  check(battle.coop ~= nil, "the host's record made it a co-op battle")
  local id = battle.coop.id
  check(s.host.battles[id] ~= nil, "the host runs it")
  eq(s.host.battles[id].open.map, "FIX_TOWN", "opened on this map")
  eq(#blue.state.battles, 1, "BLUE sees it in state")
  eq(blue.state.battles[1].foe, "FIXMON B", "against what")
  until_(function()
    local b = s.host.battles[id]
    return b and b.ask and b.ask.kind == "menu"
  end, 2000)
  blue:battleJoin(id, blueTeam(12), 2222, false)
  until_(function() return #battle.coop.roster == 2 end, 400)
  eq(#battle.coop.roster, 2, "BLUE's team went in behind RED's")
  local exp0 = Game.save.party[1].exp
  until_(function() return finished ~= nil end, 30000)
  eq(finished, "win", "the world's own onFinish heard the win")
  eq(stack:top(), ow, "the world is back")
  check(Game.save.party[1].exp > exp0, "RED's Pokémon got its experience")
  step(3)
  eq(s.host.battles[id], nil, "the host dropped the battle")
  eq(next(blue.battles) and blue.battles[next(blue.battles)].ended, "win", "BLUE heard the end")
  blue.battles = {}
end

-- a refused opening is fought alone (A8.22) -----------------------------------------
do
  -- the host thinks RED is still joining another battle: `in_battle`
  s.host.joins[s.client.player] = { battle = "b0ff", team = {}, order = 0 }
  local finished
  local battle = BattleState.newWild(Game, "FIXMON_B", 2)
  battle.onFinish = function(result) finished = result; ow:afterBattle(result, battle) end
  ow:pushBattle(battle)
  until_(function() return battle.coopPending == nil end, 200)
  s.host.joins[s.client.player] = nil
  eq(battle.coop, nil, "refused: the world's own battle")
  until_(function() return finished ~= nil end, 30000)
  check(finished ~= nil, "fought to its end alone")
  eq(stack:top(), ow, "and back on the map")
end

-- partners in a battle, as the world shows them (#34, A14.3, A14.4, A14.8, A14.10)
do
  blue:move("FIX_TOWN", 3, 6, "down", true, "walk")
  local yellow = Client.new(s.hub:dial(), { name = "YELLOW", game = "red", sha1 = SHA,
                                            device = "c1", seat = 1 })
  yellow:join()
  others[#others + 1] = yellow
  step(3)
  yellow:sendOpening(true) -- past the opening (#22)
  yellow:move("FIX_TOWN", 8, 8, "down", true, "walk")
  step(3)
  check(Presence.actors[yellow.player] ~= nil, "YELLOW is drawn on RED's map")
  local enemy = Replica.packTeam({ Pokemon.new(Data, "FIXMON_B", 3) })
  blue:battleOpen({ kind = "wild", enemy = enemy, map = "FIX_TOWN", foe = "FIXMON B" },
                  blueTeam(20), 2222, false)
  step(3)
  local id = next(blue.battles)
  local texts = table.concat(Notices.texts(), "|")
  check(texts:find("BLUE is in a battle against wild FIXMON B. START > CO-OP to join.", 1, true),
    "a notice says BLUE's battle can be joined (A14.10)")
  check(Presence.actors[blue.player] and Presence.actors[blue.player].inBattle,
    "BLUE wears the \"!\" where the battle started (A14.3)")
  local lines = table.concat(CoopMenu.lines(Game, s), "|")
  check(lines:find("IN A BATTLE", 1, true), "the CO-OP box says BLUE is in a battle (A14.8)")
  blue:battleAt(id, 1, "menu", blue.player, "x")
  step(2)
  yellow:battleJoin(id, blueTeam(9), 3333, false)
  step(4)
  eq(Presence.actors[yellow.player], nil, "YELLOW joined it from elsewhere: not drawn (A14.4)")
  check(Presence.actors[blue.player] ~= nil, "BLUE, whose world opened it, still is")
  blue:battleAt(id, 2, nil, nil, nil, "run")
  step(4)
  check(Presence.actors[yellow.player] ~= nil, "after the battle YELLOW is back")
  check(not Presence.actors[blue.player].inBattle, "and BLUE's \"!\" is gone")
  yellow:leave()
  step(3)
  blue.battles = {}
  blue:move("FIX_ROUTE", 3, 3, "down", true, "walk")
  step(2)
end

-- JOIN BLUE from the CO-OP menu --------------------------------------------------------
do
  local enemy = Replica.packTeam({ Pokemon.new(Data, "FIXMON_B", 3) })
  blue:battleOpen({ kind = "wild", enemy = enemy, map = "FIX_ROUTE", foe = "FIXMON B" },
                  blueTeam(20), 2222, false)
  step(3)
  local id = next(blue.battles)
  check(id ~= nil, "BLUE opened a battle")
  blue:battleAt(id, 1, "menu", blue.player, "x")
  step(3)
  local menu = CoopMenu.push(Game)
  local row
  for i, it in ipairs(menu.items) do
    if it.label == "JOIN BLUE" then row = i end
  end
  check(row ~= nil, "the CO-OP menu offers JOIN BLUE (A8.3)")
  stack:pop()
  local offers = Battles.offers()
  Battles.join(Game, offers[1].summary, offers[1].name)
  until_(function() return topBattle() ~= nil end, 600)
  local b = topBattle()
  check(b ~= nil, "the joined battle came in")
  eq(b and #b.coop.roster, 2, "BLUE's team and RED's")
  eq(b and b.coop.roster[2].species, "FIXMON_A", "RED's behind BLUE's")
  eq(b and Replica.owner(b, b.player.mon), blue.player, "BLUE's Pokémon is out")
  eq(b and b.introSlide, nil, "no intro for a joiner (A9.8)")
  -- RED leaves it (RUN as a joiner, then YES): back on the map, the battle
  -- plays on out of sight (#20, A11.1)
  blueHold = true -- BLUE waits instead of running
  Replica.leave(b)
  eq(stack:top(), ow, "RED left the battle: back in their world")
  check(Battles.away[b.coop.id] == b, "the copy plays on out of sight")
  local labels = {}
  local m2 = CoopMenu.push(Game)
  for _, it in ipairs(m2.items) do labels[#labels + 1] = it.label end
  stack:pop()
  check(table.concat(labels, ","):find("REJOIN", 1, true), "the CO-OP menu offers REJOIN (A11.4)")
  check(not table.concat(labels, ","):find("JOIN BLUE", 1, true), "and joins nothing else (A11.3)")
  -- a fight RED's world opens now waits for that battle (A11.3)
  local held = BattleState.newWild(Game, "FIXMON_B", 2)
  ow:pushBattle(held)
  check(Battles.held and Battles.held.battle == held, "a new fight waits while RED is away")
  check(stack:top() ~= ow, "under REJOIN?")
  stack:pop() -- the YES/NO: no
  check(stack:top() == Battles.held.wait, "the box waits for the old battle to end")
  -- REJOIN from the box's own row: back in the old battle
  Battles.rejoin(Game, b)
  until_(function() return topBattle() == b end, 600)
  eq(topBattle(), b, "REJOIN: the battle is back on screen (A11.4)")
  eq(Battles.away[b.coop.id], nil, "no longer away")
  blueHold = false
  local money0 = Game.save.money
  until_(function() return stack:top() == ow end, 30000)
  eq(stack:top(), ow, "BLUE ran: the battle ended, RED is back where they stood")
  eq(b and b.result, "run", "as a run")
  eq(Game.save.money, money0, "no prize for a run")
  eq(ow.map.id, "FIX_TOWN", "on RED's map")
  -- the fight that waited comes now (A11.3)
  until_(function() return Battles.held == nil end, 600)
  eq(Battles.held, nil, "the fight that waited goes on once the old battle ended")
end

T.finish()
