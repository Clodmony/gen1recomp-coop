-- The team's League run on the host (#55, design A10.6, decision G30),
-- ROM-free: three players over loopback, the windows' messages sent by
-- hand.  Covered: a League fight won is done for the campaign while the run
-- lasts, so a partner walking into it hears `beaten` (counts as won); the
-- run's clear asked from the lobby waits while a connected player is in
-- the League or a League fight runs, and then erases the run's story
-- entries and forgets the League's encounters and victory commits (the
-- Champion's beaten flag stays); after the Champion fell it also waits
-- until every connected player is inducted; a disconnected player inside
-- holds nothing; the rooms' script flags are each player's; the protocol's
-- check.  The restart a window asks for (A10.7) is answered with its world.
--   luajit tests/coop/league_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Transport = require("src.coop.session.Transport")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local Protocol = require("src.coop.session.Protocol")
local Ownership = require("src.coop.campaign.Ownership")
local World = require("src.coop.campaign.World")

local SHA = ("ab"):rep(20)

local clock, idCounter = 0, 0
local logLines = {}
local host = Host.new({
  campaign = { id = "c0123456789abcdef", title = "RED CO-OP" }, cartridge = { game = "red", sha1 = SHA },
  clock = function() return clock end,
  hex = function(n) idCounter = idCounter + 1; return ("%0" .. n .. "x"):format(idCounter) end,
  log = { write = function(_, _, kind, data) logLines[#logLines + 1] = { kind = kind, data = data } end,
          close = function() end },
})
local hub = host:serve(Transport.loopback())

local function seat(name, n)
  local c = Client.new(hub:dial(), { name = name, game = "red", sha1 = SHA, device = "d" .. n,
                                     build = "test" })
  c:join()
  return c
end
local red, green, blue = seat("RED", 1), seat("GREEN", 2), seat("BLUE", 3)
local all = { red, green, blue }
local function pump(frames)
  for _ = 1, frames or 3 do
    clock = clock + 1 / 60
    for _, c in ipairs(all) do c:update() end
    host:update()
    for _, c in ipairs(all) do c:update() end
  end
end
pump()

local function mon(species)
  return { species = species, level = 50, hp = 150, moves = { { id = "TACKLE", pp = 35 } } }
end
local function team(n)
  local out = {}
  for i = 1, n do out[i] = mon("PIDGEOT") end
  return out
end
local function lastRejection(c)
  local r = c.rejections[#c.rejections]
  return r and r.reason
end
local function opened(c)
  for id, rec in pairs(c.battles) do
    if rec.open and rec.open.by == c.player and not rec.ended then return id, rec end
  end
end
local function goTo(c, map) c:move(map, 5, 5, "up", true, "walk") end
local function logged(kind)
  for _, l in ipairs(logLines) do if l.kind == kind then return l end end
  return nil
end

local LORELEI = "trainer:LORELEIS_ROOM_obj_1"
local CHAMPION = "trainer:CHAMPIONS_ROOM_obj_2"
local function fight(map, foe, class, enc)
  return { kind = "trainer", enemy = { mon("DEWGONG") }, map = map, foe = foe,
           trainer = { class = class, index = 1 }, encounter = enc }
end
local L = fight("LORELEIS_ROOM", "LORELEI", "OPP_LORELEI", LORELEI)
local C = fight("CHAMPIONS_ROOM", "BLUE", "OPP_RIVAL3", CHAMPION)

-- a win the window's world wrote: the story entries of the room
local function won(c, flag, npc)
  c:sendPatch({ ["flags/" .. flag] = true, ["defeatedTrainers/" .. npc] = true }, {})
end

-- the rooms' script flags are each player's; the beaten flags the campaign's -------
check(not Ownership.owns("flags/EVENT_STARTED_ELITE_4"),
      "the Elite Four's started bit is each player's (the lobby's reset reads it)")
check(not Ownership.owns("flags/EVENT_BEAT_CHAMPION_RIVAL_THIS_RUN"),
      "the Champion room's run flag is each player's: it readies their Champion room")
check(Ownership.owns("flags/EVENT_BEAT_LORELEIS_ROOM_TRAINER_0"),
      "a member's beaten flag is the campaign's while the run lasts")
check(Ownership.owns("flags/EVENT_BEAT_LANCE"), "and LANCE's")
check(Ownership.owns("defeatedTrainers/LORELEIS_ROOM_obj_1"), "and the room's beaten trainer")

-- a League fight won is done while the run lasts (A10.6) --------------------------
goTo(red, "LORELEIS_ROOM")
goTo(green, "INDIGO_PLATEAU_LOBBY")
goTo(blue, "VIRIDIAN_CITY")
pump()
red:battleOpen(L, team(2), 1, false)
pump()
local id = opened(red)
check(id ~= nil, "RED fights LORELEI")
red:battleAt(id, 1, nil, nil, nil, "win")
won(red, "EVENT_BEAT_LORELEIS_ROOM_TRAINER_0", "LORELEIS_ROOM_obj_1")
pump()
local e = host.state.encounters[LORELEI]
eq(e and e.state, "done", "LORELEI won is done for the campaign while the run lasts")
check(host.state:applied("victory:" .. LORELEI), "as the victory's commit")
eq(green.story["flags/EVENT_BEAT_LORELEIS_ROOM_TRAINER_0"], true,
   "her beaten flag reaches the partners, so their exit opens")
red.battles = {}
goTo(green, "LORELEIS_ROOM")
pump()
green:battleOpen(L, team(1), 2, false)
pump()
eq(lastRejection(green), "beaten", "a partner arriving later hears `beaten`: it counts as won")

-- the clear from the lobby waits while a connected player is in the League ---------
goTo(red, "BRUNOS_ROOM")
pump()
goTo(green, "INDIGO_PLATEAU_LOBBY") -- GREEN whited out
green:sendLeague("lobby")
pump()
eq(host.state.story["flags/EVENT_BEAT_LORELEIS_ROOM_TRAINER_0"], true,
   "RED is still in the League: the run stands")
check(host.state.encounters[LORELEI] ~= nil, "and LORELEI stays beaten")
check(logged("league") ~= nil, "the host logs the lobby's request")

-- a running League fight holds it too
host.state.story["flags/EVENT_BEAT_CHAMPION_RIVAL"] = true
host.state:touch()
goTo(red, "LORELEIS_ROOM")
pump()
goTo(red, "INDIGO_PLATEAU_LOBBY")
local B = fight("BRUNOS_ROOM", "BRUNO", "OPP_BRUNO", "trainer:BRUNOS_ROOM_obj_1")
blue:battleOpen(B, team(1), 3, false) -- BLUE's copy, reported from elsewhere
pump()
eq(host.state.story["flags/EVENT_BEAT_LORELEIS_ROOM_TRAINER_0"], true,
   "a League fight still runs: the run stands")
blue:battleAt(opened(blue), 1, nil, nil, nil, "run")
pump()

-- nobody left inside: the clear erases the run ---------------------------------------
eq(host.state.story["flags/EVENT_BEAT_LORELEIS_ROOM_TRAINER_0"], nil,
   "everybody out: the run's beaten flags are erased")
eq(host.state.story["defeatedTrainers/LORELEIS_ROOM_obj_1"], nil, "and its beaten trainers")
eq(host.state.encounters[LORELEI], nil, "the League's encounters are forgotten")
eq(host.state:applied("victory:" .. LORELEI), false, "and their victory commits")
eq(host.state.story["flags/EVENT_BEAT_CHAMPION_RIVAL"], true,
   "the Champion's beaten flag stays (the cave guard, A10.8)")
eq(red.story["flags/EVENT_BEAT_LORELEIS_ROOM_TRAINER_0"], nil, "the windows hear the clear")
check(logged("league_clear") ~= nil, "the host logs the clear")

-- the next run fights everyone again
blue.battles = {}
goTo(green, "LORELEIS_ROOM")
pump()
green:battleOpen(L, team(1), 2, false)
pump()
id = opened(green)
check(id ~= nil, "the next run fights LORELEI again")

-- after the Champion fell: held until every connected player is inducted ------------
green:battleAt(id, 1, nil, nil, nil, "win")
won(green, "EVENT_BEAT_LORELEIS_ROOM_TRAINER_0", "LORELEIS_ROOM_obj_1")
pump()
green.battles = {}
goTo(green, "CHAMPIONS_ROOM")
pump()
green:battleOpen(C, team(2), 2, false)
pump()
id = opened(green)
green:battleAt(id, 1, nil, nil, nil, "win")
pump()
green.battles = {}
goTo(green, "HALL_OF_FAME")
green:sendLeague("inducted")
pump()
eq(host.league and host.league.fell, true, "the Champion fell")
goTo(green, "PALLET_TOWN")
pump()
eq(host.state.story["flags/EVENT_BEAT_LORELEIS_ROOM_TRAINER_0"], true,
   "RED and BLUE are connected and not inducted: the run stands")
-- a late player meets the Champion: the host ends it at once as won
goTo(red, "CHAMPIONS_ROOM")
pump()
red:battleOpen(C, team(1), 1, false)
pump()
eq(lastRejection(red), "beaten", "a late player's Champion is won at once")
goTo(red, "HALL_OF_FAME")
red:sendLeague("inducted")
pump()
-- BLUE leaves: a player who is not connected holds nothing
blue:leave()
pump()
eq(host.state.story["flags/EVENT_BEAT_LORELEIS_ROOM_TRAINER_0"], true,
   "RED stands in the Hall of Fame: the run stands")
goTo(red, "PALLET_TOWN")
pump()
eq(host.state.story["flags/EVENT_BEAT_LORELEIS_ROOM_TRAINER_0"], nil,
   "every connected player inducted and out: the run is erased")
eq(host.state.encounters[CHAMPION], nil, "the Champion is forgotten too")
eq(host.league and host.league.fell, false, "a new run starts afresh")

-- a disconnected player inside holds nothing ------------------------------------------
blue = seat("BLUE", 3)
all[3] = blue
pump()
won(green, "EVENT_BEAT_LORELEIS_ROOM_TRAINER_0", "LORELEIS_ROOM_obj_1")
goTo(blue, "AGATHAS_ROOM")
pump()
goTo(green, "INDIGO_PLATEAU_LOBBY")
green:sendLeague("lobby")
pump()
eq(host.state.story["flags/EVENT_BEAT_LORELEIS_ROOM_TRAINER_0"], true, "BLUE is inside")
blue.conn:close()
pump()
eq(host.state.story["flags/EVENT_BEAT_LORELEIS_ROOM_TRAINER_0"], nil,
   "BLUE's link dropped: the run's clear goes through (the hold lives in host memory)")

-- a restart is answered with the player's world (A10.7) -------------------------------
do
  local save = { player = { name = "RED", map = "PALLET_TOWN", x = 5, y = 6, id = 1 }, money = 77,
                 party = {}, boxes = {}, currentBox = 1, flags = {} }
  for i = 1, 12 do save.boxes[i] = {} end
  red:sendWorld(World.encode(save), false, "hall")
  red.world = nil
  local seq = red:sendRestart("hall")
  pump()
  check(red.world ~= nil, "the host answers a restart with the player's world")
  eq(red.world.restart, seq, "naming the restart it answers")
  local back = World.decode(red.world.save)
  eq(back and back.money, 77, "the world the window sent before it")
  eq(back and back.flags and back.flags.EVENT_BEAT_CHAMPION_RIVAL, true,
     "with the story laid over it, as a Continue opens it")
  check(logged("restart") ~= nil, "the host logs the restart")
end

-- the protocol --------------------------------------------------------------------
check(Protocol.VERSION >= 11, "the League run is in the protocol (#55)")
check(Protocol.sanitize({ type = "league", seq = 1, event = "lobby" }, "host") ~= nil, "a league event")
eq(Protocol.sanitize({ type = "league", seq = 1, event = "won" }, "host"), nil, "an unknown one is dropped")
check(Protocol.sanitize({ type = "restart", seq = 1, kind = "reset" }, "host") ~= nil, "a restart")
eq(Protocol.sanitize({ type = "restart", seq = 1, kind = "title" }, "host"), nil, "of a known kind only")
check(Protocol.sanitize({ type = "world", fresh = true, restart = 4 }, "client") ~= nil,
      "the host's world names the restart it answers")

T.finish()
