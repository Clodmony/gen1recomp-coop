-- Rival scenes in the running game (#59, design A10.5, decision G29),
-- ROM-free.  First the cartridge's own scenes as the hand-ported map
-- scripts start them (data/scripts): each of Route 22's two fights,
-- Cerulean's Nugget Bridge, the S.S. Anne 2F, Pokémon Tower 2F and Silph
-- Co. 7F is a rival scene, a beaten one is none, and the Champion's room
-- has no lock.  Then the fixture overworld with this device hosting a
-- session in-process and BLUE a partner on the loopback hub whose claims,
-- reports and commands this test sends:
--   * RED's world starts a scene: the window claims the map (again on a
--     link that came back); BLUE's claim
--     is refused; the scene's rival battle is the unique encounter of the
--     rival's map object, so BLUE's world starting it too joins RED's
--     fight (two at once); after the scene RED's window sends the result
--     and lets go at its next rest point, in that order;
--   * BLUE drives: RED's world waits at its next rest point under
--     "BLUE is facing the rival here…", which counts as resting; A in that
--     box joins BLUE's fight; BLUE's result lands in RED's world before
--     the box goes; BLUE changing map or dropping lets RED go; a claim on
--     another map holds nobody here.
--   luajit tests/coop/scenes_game_test.lua

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
Data.maps.FIX_ROUTE.encounters = nil

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
local Scenes   = require("src.coop.game.Scenes")
local SharedWorld = require("src.coop.game.SharedWorld")

Game.data = Data

-- the cartridge's scenes, as the map scripts start them (A10.5) ---------------------
do
  local story = require("data.scripts.story")
  local story5 = require("data.scripts.story5")
  -- what a map script hands the script runner when the player steps on (x, y)
  local function started(mod, map, x, y, flags)
    local rows
    local ow = { runner = { isRunning = function() return false end,
                            run = function(_, r) rows = r end },
                 player = {}, scriptMoves = {},
                 npcByIndex = function(_, i) return { id = map .. "_obj_" .. i } end }
    local save = { flags = flags or {} }
    mod[map].onStep({ data = Data, save = save }, ow, x, y)
    return rows, save
  end
  local cases = {
    { story5, "ROUTE_22", 29, 4, { EVENT_GOT_POKEDEX = true }, "route22_1",
      "EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE" },
    { story5, "ROUTE_22", 29, 5, { EVENT_BEAT_GIOVANNI = true, EVENT_BEAT_BROCK = true },
      "route22_2", "EVENT_BEAT_ROUTE22_RIVAL_2ND_BATTLE" },
    { story5, "CERULEAN_CITY", 20, 6, {}, "cerulean", "EVENT_BEAT_CERULEAN_RIVAL" },
    { story5, "SS_ANNE_2F", 36, 8, {}, "ss_anne", "EVENT_BEAT_SS_ANNE_RIVAL" },
    { story, "POKEMON_TOWER_2F", 15, 5, {}, "tower", "EVENT_BEAT_POKEMON_TOWER_RIVAL" },
    { story5, "SILPH_CO_7F", 3, 2, {}, "silph", "EVENT_BEAT_SILPH_CO_RIVAL" },
  }
  for _, c in ipairs(cases) do
    local mod, map, x, y, flags, key, flag = c[1], c[2], c[3], c[4], c[5], c[6], c[7]
    local rows, save = started(mod, map, x, y, flags)
    check(rows ~= nil, map .. ": the map script starts a scene at (" .. x .. "," .. y .. ")")
    local e = rows and Scenes.of(map, rows, save)
    eq(e and e.key, key, map .. ": the scene is " .. key)
    save.flags[flag] = true
    eq(rows and Scenes.of(map, rows, save), nil, map .. ": a beaten rival is no scene")
  end
  -- talking to the rival starts the same scene (Cerulean's, the tower's)
  local talk = story.CERULEAN_CITY.talk.TEXT_CERULEANCITY_RIVAL
  eq(Scenes.of("CERULEAN_CITY", talk, { flags = {} }).key, "cerulean", "talking to him at Cerulean too")
  eq(Scenes.of("VIRIDIAN_CITY", talk, { flags = {} }), nil, "a scene is its map's")
  -- the Champion's room has no lock
  eq(Scenes.of("CHAMPIONS_ROOM", story.CHAMPIONS_ROOM.talk.TEXT_CHAMPIONSROOM_RIVAL, { flags = {} }),
     nil, "the Champion's room is no scene (A10.5)")
  eq(Scenes.of("ROUTE_22", { { "show_text", "x" } }, { flags = {} }), nil,
     "a script without the rival's battle is none")
end

-- the fixture overworld --------------------------------------------------------------
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.save.flags.EVENT_GOT_STARTER = true -- past the opening (#22)
Game.save.player.name, Game.save.player.id = "RED", 1111
Game.save.party = { Pokemon.new(Data, "FIXMON_A", 40) }
Game.save.money = 500
local stack = Game.stack
stack:push(OW, "FIX_ROUTE", 5, 11, "up")
local ow = stack:top()
Game.overworld = ow
local RIVAL = "trainer:FIX_ROUTE_obj_1" -- the fixture's rival is the route's map object

-- the fixture's scene: the route's NPC stands in for the rival
table.insert(Scenes.LIST, { key = "fix", map = "FIX_ROUTE", opp = "OPP_FIX_YOUNGSTER",
                            flag = "EVENT_FIX_RIVAL" })
local function sceneRows(flag)
  return {
    { "face_object", 1, "down" },
    { "rival_battle", "OPP_FIX_YOUNGSTER", 1 },
    { "jump_if_false", "leave" },
    { "set_flag", flag },
    { "label", "leave" },
  }
end

local SHA = ("ab"):rep(20)
local function memoryStore()
  local text
  return { read = function() return text end, write = function(t) text = t end }
end

local blue
local blueHold = false
local blueAnswers = {}
local function blueDecides()
  for id, rec in pairs(blue.battles) do
    if not blueHold and rec.ask == "menu" and rec.by == blue.player and not rec.ended
       and blueAnswers[id] ~= rec.rev then
      blueAnswers[id] = rec.rev
      blue:battleCmd(id, rec.rev, { kind = "move", slot = 1 })
    end
  end
end

local mash = true -- A every other frame over anything but the map and the waiting box
local tick = 0
local function step(n)
  for _ = 1, n or 1 do
    tick = tick + 1
    local top = stack:top()
    if mash and tick % 2 == 0 and top ~= ow and top ~= Scenes.waiting() then
      Input:sourcePress("a", "test")
    else
      Input:sourceRelease("a", "test")
    end
    Input:step()
    local s = Session.current
    if s then s:update(1 / 60, Game) end
    if blue and blue.status ~= "closed" then blue:update(); blueDecides() end
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
local function press(key)
  Input:sourcePress(key, "test"); Input:step()
  local s = Session.current
  if s then s:update(1 / 60, Game) end
  stack:update(1 / 60)
  Input:sourceRelease(key, "test"); Input:step()
end
local function lastRejection(c)
  local r = c.rejections[#c.rejections]
  return r and r.reason
end

local s = Session.startHost({
  campaign = { id = "c0001", title = "Fix co-op" },
  cartridge = { game = "red", sha1 = SHA }, name = "HOST",
  listen = false, beacon = false, log = false,
  identity = Identity.load(memoryStore()),
})
step(3)
local function newBlue()
  blue = Client.new(s.hub:dial(), { name = "BLUE", game = "red", sha1 = SHA, device = "b1", seat = 1 })
  blue:join()
  step(3)
  eq(blue.status, "joined", "BLUE joined")
  blue:sendOpening(true)
  blue:move("FIX_ROUTE", 5, 7, "down", true, "walk")
  step(3)
end
newBlue()
local red = s.client
until_(function() return s.window and s.window:resting() end, 60)
check(s.window and s.window:resting(), "RED's world rests")

local function blueTeam(level)
  local mon = Pokemon.new(Data, "FIXMON_C", level)
  mon.otId, mon.ot = 2222, "BLUE"
  return Replica.packTeam({ mon })
end
local function trainerOpening()
  local enemy = Replica.packTeam(BattleState.newTrainer(Game, "OPP_FIX_YOUNGSTER", 1).enemyParty)
  return { kind = "trainer", enemy = enemy, map = "FIX_ROUTE", foe = "YOUNGSTER",
           trainer = { class = "OPP_FIX_YOUNGSTER", index = 1 }, encounter = RIVAL }
end
local function hostBattles()
  local list = {}
  for id, b in pairs(s.host.battles) do if not b.ended then list[#list + 1] = id end end
  return list
end
local function forget(key)
  s.host.state.encounters[key] = nil
  s.host.state.commits["victory:" .. key] = nil
end

-- RED drives a scene (A10.5) ----------------------------------------------------------
do
  ow.runner:run(sceneRows("EVENT_FIX_RIVAL"))
  step(2)
  local claim = s.host.scenes and s.host.scenes.FIX_ROUTE
  check(claim ~= nil, "RED's window claims the scene on the host")
  eq(claim and claim.by, red.player, "RED drives")
  eq(claim and claim.key, "fix", "the fixture's scene")
  -- a link that came back claims the running scene again
  s.host.scenes.FIX_ROUTE = nil
  Scenes.driving.sentTo = "the old link"
  step(2)
  eq(s.host.scenes.FIX_ROUTE and s.host.scenes.FIX_ROUTE.by, red.player,
     "a new link claims the scene still running")
  blue:sendScene("FIX_ROUTE", "fix", true)
  step(3)
  eq(lastRejection(blue), "scene_taken", "BLUE's claim of the same map is refused")
  until_(function() return #hostBattles() > 0 end, 2000)
  local id = hostBattles()[1]
  local b = id and s.host.battles[id]
  eq(b and b.open.encounter, RIVAL, "the scene's battle is the rival's map object")
  -- two at once: BLUE's world started the scene too; its battle joins RED's
  blue:battleOpen(trainerOpening(), blueTeam(20), 2222, false)
  step(3)
  eq(#hostBattles(), 1, "BLUE's battle against the same rival is no second one")
  until_(function()
    for _, input in ipairs(b.inputs or {}) do
      if input.kind == "join" and input.player == blue.player then return true end
    end
  end, 3000)
  local joined = false
  for _, input in ipairs(b.inputs or {}) do
    if input.kind == "join" and input.player == blue.player then joined = true end
  end
  check(joined, "BLUE's team joined RED's fight against the rival")
  until_(function() return Game.save.flags.EVENT_FIX_RIVAL end, 40000)
  eq(Game.save.flags.EVENT_FIX_RIVAL, true, "RED won: the scene sets its flag")
  -- the result first, then the release, at RED's next rest point
  local storyAtRelease
  until_(function()
    if not (s.host.scenes and s.host.scenes.FIX_ROUTE) then
      storyAtRelease = s.host.state.story["flags/EVENT_FIX_RIVAL"]
      return true
    end
  end, 3000)
  eq(s.host.scenes and s.host.scenes.FIX_ROUTE, nil, "the scene is released after it")
  eq(storyAtRelease, true, "the scene's result reached the host before the release")
  eq(Scenes.waiting(), nil, "the driver never waits for itself")
  blue.battles = {}
  forget(RIVAL)
end

-- BLUE drives: RED waits, joins, and takes the result (A10.5) ------------------------
do
  step(10)
  check(s.window:resting(), "RED's world rests again")
  blue:sendScene("FIX_ROUTE", "fix", true)
  until_(function() return Scenes.waiting() ~= nil end, 60)
  local box = Scenes.waiting()
  check(box ~= nil, "RED's world waits at its next rest point")
  eq(stack:top(), box, "frozen under the box")
  local text = box and table.concat(box:lines(), " ") or ""
  check(text:find("BLUE is facing the rival here.", 1, true), "naming BLUE: " .. text)
  check(text:find("Wait, or join the battle...", 1, true), "and saying RED may join")
  step(5)
  eq(SharedWorld.busy(Game), nil, "the frozen world counts as resting")
  check(s.window:resting(), "so the window rests")
  -- BLUE's rival battle; A in the box joins it
  blueHold = true
  blue:battleOpen(trainerOpening(), blueTeam(20), 2222, false)
  step(3)
  local id
  for bid, rec in pairs(blue.battles) do if rec.open and rec.open.by == blue.player then id = bid end end
  check(id ~= nil, "BLUE fights the rival")
  blue:battleAt(id, 1, "menu", blue.player, "x")
  step(3)
  press("a")
  local battle
  until_(function()
    local top = stack:top()
    if top and top.coop then battle = top end
    return battle ~= nil
  end, 3000)
  blueHold = false
  check(battle ~= nil, "A in the box joined BLUE's fight")
  eq(battle and battle.coop.id, id, "the rival's")
  until_(function() return battle and battle.coop.done end, 40000)
  until_(function() return stack:top() == box end, 3000)
  eq(stack:top(), box, "after the fight RED waits again: BLUE's scene goes on")
  eq(Game.save.flags.EVENT_FIX_RIVAL2, nil, "BLUE's result has not come yet")
  -- BLUE's window sends its result at its rest point, then lets go
  blue:sendPatch({ ["flags/EVENT_FIX_RIVAL2"] = true }, {})
  blue:sendScene("FIX_ROUTE", "fix", false)
  local flagAtRelease
  until_(function()
    if Scenes.waiting() == nil then
      flagAtRelease = Game.save.flags.EVENT_FIX_RIVAL2
      return true
    end
  end, 600)
  eq(Scenes.waiting(), nil, "the release lets RED go")
  eq(flagAtRelease, true, "with BLUE's result already in RED's world")
  eq(stack:top(), ow, "RED is back on the map")
  blue.battles = {}
  forget(RIVAL)
end

-- a claim on another map holds nobody here ----------------------------------------------
do
  blue:move("FIX_TOWN", 5, 6, "down", true, "walk")
  blue:sendScene("FIX_TOWN", "fix", true)
  step(30)
  eq(Scenes.waiting(), nil, "a scene on FIX_TOWN does not hold RED on FIX_ROUTE")
  blue:sendScene("FIX_TOWN", "fix", false)
  blue:move("FIX_ROUTE", 5, 7, "down", true, "walk")
  step(3)
end

-- the driver changing map lets RED go (A10.5) ----------------------------------------
do
  blue:sendScene("FIX_ROUTE", "fix", true)
  until_(function() return Scenes.waiting() ~= nil end, 60)
  check(Scenes.waiting() ~= nil, "RED waits for BLUE again")
  blue:move("FIX_TOWN", 5, 6, "down", true, "walk")
  until_(function() return Scenes.waiting() == nil end, 60)
  eq(Scenes.waiting(), nil, "BLUE left the map: RED goes")
  eq(stack:top(), ow, "back on the map")
  blue:move("FIX_ROUTE", 5, 7, "down", true, "walk")
  step(3)
end

-- the driver dropping lets RED go (A10.5) --------------------------------------------
do
  blue:sendScene("FIX_ROUTE", "fix", true)
  until_(function() return Scenes.waiting() ~= nil end, 60)
  check(Scenes.waiting() ~= nil, "RED waits for BLUE once more")
  blue.conn:close()
  blue.status = "closed"
  until_(function() return Scenes.waiting() == nil end, 60)
  eq(Scenes.waiting(), nil, "BLUE's link dropped: RED goes")
  eq(Game.save.flags.EVENT_FIX_RIVAL2, true, "RED's world keeps what it took")
end

T.finish()
