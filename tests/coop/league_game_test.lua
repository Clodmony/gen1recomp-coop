-- The team's League run and the Hall of Fame's continue in the game (#55,
-- design A10.6, A10.7), ROM-free: the fixture overworld runs headless with
-- this device hosting a session in-process and a partner on its loopback
-- hub.  The Indigo Plateau lobby's reset: solo it is the cartridge's; in a
-- co-op world it resets this player's part of the run and asks the host for
-- the rest, which waits while the partner is still in the League and then
-- reaches the window.  The Hall of Fame's end freezes the world, sends the
-- world it saved and the induction, and reopens the world from the host's
-- answer as a Continue; a player left in the Hall of Fame flies home; a
-- reset in a co-op window continues the same way, losing what was not
-- sent, and drops finished battles; a player with no world starts again.
--   luajit tests/coop/league_game_test.lua

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
local Commands   = require("src.script.Commands")
local Screens    = require("src.ui.Screens")
local Story6     = require("data.scripts.story6")

local Identity = require("src.coop.session.Identity")
local Session  = require("src.coop.session.Session")
local Client   = require("src.coop.session.Client")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.save.player.name = "HOST"
Game.save.party = { Pokemon.new(Data, "FIXMON_A", 50) }
Game.save.flags.EVENT_GOT_STARTER = true -- past the opening (#22)
Game.save.pcItems = {} -- the fixture has no POTION: a Continue would quarantine it
local stack = Game.stack
stack:push(OW, "FIX_TOWN", 5, 6, "down")
Game.overworld = stack:top()
local ow = Game.overworld

local SHA = ("ab"):rep(20)
local function memoryStore()
  local text
  return { read = function() return text end, write = function(t) text = t end }
end

local blue
local function step(n)
  for _ = 1, n or 1 do
    local s = Session.current
    if s then s:update(1 / 60, Game) end
    if blue then blue:update() end
    stack:update(1 / 60)
  end
end

local RUN_FLAGS = { "EVENT_STARTED_ELITE_4", "EVENT_AUTOWALKED_INTO_LORELEIS_ROOM",
                    "EVENT_LANCES_ROOM_LOCK_DOOR", "EVENT_BEAT_CHAMPION_RIVAL_THIS_RUN",
                    "EVENT_BEAT_LORELEIS_ROOM_TRAINER_0", "EVENT_BEAT_BRUNOS_ROOM_TRAINER_0" }
local function startRun(save)
  for _, f in ipairs(RUN_FLAGS) do save.flags[f] = true end
  save.defeatedTrainers = save.defeatedTrainers or {}
  save.defeatedTrainers.LORELEIS_ROOM_obj_1 = true
end
local function lobby() Story6.INDIGO_PLATEAU_LOBBY.onEnter(Game, ow) end

-- solo: the lobby erases the run, as the cartridge does --------------------------------
do
  local real = Game.save
  Game.save = SaveData.newGame()
  startRun(Game.save)
  lobby()
  eq(Game.save.flags.EVENT_BEAT_LORELEIS_ROOM_TRAINER_0, nil, "solo: the members' flags go")
  eq(Game.save.flags.EVENT_STARTED_ELITE_4, nil, "solo: and the started bit")
  eq(Game.save.defeatedTrainers.LORELEIS_ROOM_obj_1, nil, "solo: and the beaten trainers")
  Game.save = real
end

-- a session: this device hosts, BLUE joins ---------------------------------------------
local s = Session.startHost({
  campaign = { id = "c0055", title = "League" },
  cartridge = { game = "red", sha1 = SHA }, name = "Ash",
  listen = false, beacon = false, log = false, campaignFs = false,
  identity = Identity.load(memoryStore()),
})
step(4)
eq(s.status, "joined", "the host's own player is in")
blue = Client.new(s.hub:dial(), { name = "BLUE", game = "red", sha1 = SHA, device = "b1", seat = 1 })
blue:join()
step(4)
blue:sendOpening(true)
step(10)
local host = s.host
local me = s.client.player

-- the run: this window's entries seed the story ------------------------------------------
startRun(Game.save)
step(10)
eq(host.state.story["flags/EVENT_BEAT_LORELEIS_ROOM_TRAINER_0"], true, "LORELEI's beaten flag is the campaign's")
eq(host.state.story["flags/EVENT_STARTED_ELITE_4"], nil, "the started bit stays this player's")

-- the lobby with BLUE still in the League: this player's part resets, the run stands --
blue:move("AGATHAS_ROOM", 5, 5, "up", true, "walk")
step(4)
lobby()
eq(Game.save.flags.EVENT_STARTED_ELITE_4, nil, "co-op: the started bit resets")
eq(Game.save.flags.EVENT_AUTOWALKED_INTO_LORELEIS_ROOM, nil, "and the walk-in")
eq(Game.save.flags.EVENT_LANCES_ROOM_LOCK_DOOR, nil, "and Lance's door")
eq(Game.save.flags.EVENT_BEAT_CHAMPION_RIVAL_THIS_RUN, nil, "and the Champion room's run flag")
eq(Game.save.flags.EVENT_BEAT_LORELEIS_ROOM_TRAINER_0, true,
   "the members' flags stay: the team's run goes on")
eq(Game.save.defeatedTrainers.LORELEIS_ROOM_obj_1, true, "and the beaten trainers")
step(10)
eq(host.league and host.league.want, "lobby", "the host has the lobby's request")
eq(host.state.story["flags/EVENT_BEAT_LORELEIS_ROOM_TRAINER_0"], true, "held: BLUE is in the League")
eq(Game.save.flags.EVENT_BEAT_LORELEIS_ROOM_TRAINER_0, true, "this world still walks through")

-- BLUE whites out too: the clear reaches this window ------------------------------------
blue:move("INDIGO_PLATEAU_LOBBY", 5, 5, "up", true, "walk")
step(10)
eq(host.state.story["flags/EVENT_BEAT_LORELEIS_ROOM_TRAINER_0"], nil, "the run is erased")
eq(Game.save.flags.EVENT_BEAT_LORELEIS_ROOM_TRAINER_0, nil, "and this world hears it at a rest point")
eq(Game.save.defeatedTrainers.LORELEIS_ROOM_obj_1, nil, "LORELEI fights again")

-- the Hall of Fame's end continues the co-op world (A10.7) -----------------------------
local realPush = Screens.push
local screens = {}
Screens.push = function(game, id, done, theEnd)
  screens[#screens + 1] = id
  if id == "Credits" then theEnd() end
  done()
end
Game.save.party[1].hp = 1
Game.save.money = 4321
local writes = 0
local realWrite = SaveData.save
SaveData.save = function() writes = writes + 1; return true end
local ctx = { save = Game.save, game = Game, overworld = ow,
              runner = { yield = function() end, resume = function() end } }
Commands.record_hall_of_fame(ctx)
Screens.push = realPush
eq(table.concat(screens, ","), "HallOfFame,Credits", "the induction and the credits run")
check(writes > 0, "THE END saves the game")
local top = stack:top()
eq(top and top.screenId, "CoopRestart", "the world freezes: no boot movie, no title")
step(2)
check(host.league and host.league.inducted[me], "the host hears the induction")
step(10)
eq(stack:top(), ow, "the world reopens as a Continue")
eq(Game.save.player.map, "FIX_TOWN", "at the post-game home")
eq(Game.save.money, 4321, "from the world the Hall of Fame saved")
eq(Game.save.party[1].hp, Game.save.party[1].stats.hp, "healed")
eq(Game.save.player.facing, "down", "CONTINUE's facing")

-- a reset continues too, from what the host has: unsent changes are lost -----------------
Game.save.money = 1
s.client.battles.b0001 = { id = "b0001", open = { by = me }, inputs = {}, ended = "win" }
Game:returnToTitle()
top = stack:top()
eq(top and top.screenId, "CoopRestart", "a reset in a co-op window does not go to the title")
step(12)
eq(stack:top(), ow, "it continues the co-op world")
eq(Game.save.money, 4321, "what the window had not sent is lost, as on the cartridge")
eq(s.client.battles.b0001, nil, "finished battles are dropped")
step(10)
check(s.window.sent ~= nil, "the window opened again as a late one")

-- a player left in the Hall of Fame flies home ------------------------------------------
do
  local w = host.state:worldFor(me)
  w.player.map, w.player.x, w.player.y = "HALL_OF_FAME", 4, 2
  w.party[1].hp = 1
  host.state:setWorld(me, w)
  Game:returnToTitle()
  step(12)
  eq(Game.save.player.map, "FIX_TOWN", "a world left in the Hall of Fame reopens at home")
  eq(Game.save.party[1].hp, Game.save.party[1].stats.hp, "healed")
end

-- a dropped link: the world waits frozen, and the restart goes on the new link ----------
do
  Game:returnToTitle()
  local w = stack:top()
  local old = s.client
  old.conn:close()
  local c2 = Client.new(s.hub:dial(), { name = "Ash", game = "red", sha1 = SHA,
                                        device = s.identity.device, known = old.known })
  s.client = c2
  step(3)
  eq(stack:top(), w, "no link: the world stays frozen")
  c2:join()
  step(12)
  eq(c2.status, "joined", "the same player is back on a new link")
  eq(w.client, c2, "the restart went out on the new link")
  eq(stack:top(), ow, "and the world continues")
end

-- a player with no world in the campaign starts the opening again -------------------------
do
  local p = host.state:player(me)
  local keep = p.world
  p.world = nil
  local started = false
  local realNew = Game.startNewGame
  Game.startNewGame = function() started = true end
  Game:returnToTitle()
  step(12)
  check(started, "no world: NEW GAME, the opening again")
  Game.startNewGame = realNew
  p.world = keep
end

-- solo: a reset goes to the title, as the cartridge does --------------------------------
Session.current = nil
local titled = false
local realTitle = Game.makeTitleState
Game.makeTitleState = function() titled = true; return { update = function() end, draw = function() end } end
Game:returnToTitle()
check(titled, "solo: a reset shows the title")
Game.makeTitleState = realTitle
SaveData.save = realWrite

T.finish()
