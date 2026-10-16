-- Unique encounters on the host (#21, design A10.1 to A10.4, A10.8),
-- ROM-free: three players over loopback, the windows' reports sent by
-- hand.  Covered: a battle names the encounter it is (a trainer or a
-- one-off wild Pokémon, by its map object) and `state` says which are
-- running (the sight gate); a second window walking into a running one
-- joins it, so there is one instance; a win or a catch makes it done for
-- the campaign, kept in the campaign file, and a window walking into a
-- done one hears `beaten` (it counts as won); a loss, a flight, an
-- abandoned battle or a shutdown release it; the League's rooms are kept
-- done while the team's run lasts (#55); a walk-in into a full battle
-- or while in another one is refused; a malformed encounter is dropped;
-- the Hall of Fame's Cerulean Cave guard stays the campaign's.
--   luajit tests/coop/encounters_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Transport = require("src.coop.session.Transport")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local Protocol = require("src.coop.session.Protocol")
local Campaign = require("src.coop.campaign.Campaign")
local Ownership = require("src.coop.campaign.Ownership")
local HostBattles = require("src.coop.battle.HostBattles")

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

local function mon(species, uid)
  return { species = species, level = 10, hp = 30, uid = uid, moves = { { id = "TACKLE", pp = 35 } } }
end
local function team(prefix, n)
  local out = {}
  for i = 1, n do out[i] = mon("PIDGEY", prefix .. i) end
  return out
end
local function lastRejection(c)
  local r = c.rejections[#c.rejections]
  return r and r.reason
end
local function battleCount()
  local n = 0
  for _, b in pairs(host.battles) do if not b.ended then n = n + 1 end end
  return n
end
local function opened(c)
  for id, rec in pairs(c.battles) do
    if rec.open and rec.open.by == c.player and not rec.ended then return id, rec end
  end
end
local function clear() for _, c in ipairs(all) do c.battles = {} end end

local BUG = "trainer:ROUTE_3_obj_5"
local TRAINER = { kind = "trainer", enemy = { mon("CATERPIE") }, map = "ROUTE_3", foe = "BUG CATCHER",
                  trainer = { class = "OPP_BUG_CATCHER", index = 1 }, encounter = BUG }

-- the opening names its encounter; `state` says it is running (A10.4) -----
red:battleOpen(TRAINER, team("r", 2), 1, false)
pump()
local id = opened(red)
check(id ~= nil, "RED's trainer battle runs on the host")
eq(red.battles[id].open.encounter, BUG, "the record names the encounter")
eq(green.state.battles[1] and green.state.battles[1].encounter, BUG,
   "state names the running encounter, for the partners' sight gate (A10.4)")

-- a second window walking into it joins the running fight (A10.1, A10.2) ----
green:battleOpen(TRAINER, team("g", 1), 2, false)
pump()
eq(lastRejection(green), nil, "GREEN's walk-in is not refused")
eq(battleCount(), 1, "one instance of the encounter (A10.1)")
eq(host.joins[green.player] and host.joins[green.player].battle, id,
   "GREEN's walk-in is queued as a join of RED's fight (A10.2)")
check(green.battles[id] ~= nil, "GREEN hears the battle it walked into")
red:battleAt(id, 1, "menu", red.player, "h1")
pump()
eq(#red.battles[id].inputs, 2, "GREEN's team went in at the move question")
eq(red.battles[id].inputs[2].player, green.player, "as GREEN's join")

-- walking in while in another battle is refused (A8.1) -------------------------
red:battleOpen(TRAINER, team("r", 2), 1, false)
pump()
eq(lastRejection(red), "in_battle", "a player in the fight cannot walk into it again")

-- a win: done for everybody, kept in the file (A10.1, A10.2) ------------------
red:battleAt(id, 2, nil, nil, nil, "win")
pump()
local e = host.state.encounters[BUG]
eq(e and e.state, "done", "the win marks the trainer done for the campaign")
check(host.state:applied("victory:" .. BUG), "once, as the victory's commit")
local snap = host.state:snapshot()
local back = Campaign.fromSnapshot(snap, function() return nil end)
eq(back.encounters[BUG] and back.encounters[BUG].state, "done", "the campaign file keeps it")
clear()
blue:battleOpen(TRAINER, team("b", 1), 3, false)
pump()
eq(lastRejection(blue), "beaten", "a window walking into a beaten trainer hears `beaten` (counts as won)")
eq(battleCount(), 0, "and no battle runs")
eq(blue.battles and next(blue.battles), nil, "BLUE has no battle")

-- a static Pokémon: a loss or a flight releases it, a catch makes it done (A10.3)
local SNORLAX = "static:ROUTE_12_obj_1"
local STATIC = { kind = "wild", enemy = { mon("SNORLAX") }, map = "ROUTE_12", foe = "SNORLAX",
                 encounter = SNORLAX }
red:battleOpen(STATIC, team("r", 2), 1, false)
pump()
id = opened(red)
red:battleAt(id, 1, "menu", red.player, "h1")
pump()
red:battleAt(id, 1, nil, nil, nil, "lose")
pump()
eq(host.state.encounters[SNORLAX], nil, "a loss releases it")
clear()
green:battleOpen(STATIC, team("g", 1), 2, false)
pump()
id = opened(green)
check(id ~= nil, "the next window opens it afresh, as its own fight")
green:battleAt(id, 1, nil, nil, nil, "run")
pump()
eq(host.state.encounters[SNORLAX], nil, "a flight releases it: it stays in the world")
clear()
blue:battleOpen(STATIC, team("b", 1), 3, false)
pump()
id = opened(blue)
blue:battleAt(id, 1, nil, nil, nil, "caught")
pump()
eq(host.state.encounters[SNORLAX] and host.state.encounters[SNORLAX].state, "done",
   "a catch makes it done for the campaign")
clear()
red:battleOpen(STATIC, team("r", 2), 1, false)
pump()
eq(lastRejection(red), "beaten", "and nobody meets it again")

-- an abandoned battle and a shutdown release theirs (A10.1, A11.7) -------------
local MEWTWO = "static:CERULEAN_CAVE_B1F_obj_1"
local M = { kind = "wild", enemy = { mon("MEWTWO") }, map = "CERULEAN_CAVE_B1F", foe = "MEWTWO",
            encounter = MEWTWO }
clear()
green:battleOpen(M, team("g", 1), 2, false)
pump()
id = opened(green)
local b = host.battles[id]
for _, p in ipairs(b.players) do p.present = false end
HostBattles.tick(host, clock)
HostBattles.tick(host, clock + HostBattles.ABANDON + 1)
pump()
eq(host.state.encounters[MEWTWO], nil, "an abandoned battle ends as fled and releases it")
clear()
blue:battleOpen(M, team("b", 1), 3, false)
pump()
check(opened(blue) ~= nil, "so it can be met again")
HostBattles.endAll(host)
pump()
eq(host.state.encounters[MEWTWO], nil, "a shutdown releases it too")

-- a battle nobody is present in, walked into: the walker fights it afresh
-- (found live: the rival's opener quit during the battle's intro, before
-- any question, and a partner meeting the rival waited two silent minutes
-- for the abandon, A11.7)
do
  local RIVAL = "trainer:ROUTE_22_obj_1"
  local R = { kind = "trainer", enemy = { mon("PIDGEY") }, map = "ROUTE_22", foe = "GARY",
              trainer = { class = "OPP_RIVAL1", index = 5 }, encounter = RIVAL }
  clear()
  green:battleOpen(R, team("g", 1), 2, false)
  pump()
  local gid = opened(green)
  for _, p in ipairs(host.battles[gid].players) do p.present = false end -- GREEN's link dropped
  blue.rejections = {}
  blue:battleOpen(R, team("b", 1), 3, false)
  pump()
  eq(lastRejection(blue), nil, "BLUE's meeting with him is not refused")
  eq(host.joins[blue.player], nil, "BLUE does not queue for a battle nobody is in")
  local bid = opened(blue)
  check(bid ~= nil and bid ~= gid, "BLUE's own fight against him opens at once")
  local why
  for _, l in ipairs(logLines) do
    if l.kind == "battle_end" and l.data.battle == gid then why = l.data.result .. "/" .. tostring(l.data.why) end
  end
  eq(why, "run/abandoned", "the battle nobody was in ends as fled (A11.7)")
  eq(battleCount(), 1, "still one instance of the encounter")
  HostBattles.endAll(host)
  pump()
end

-- a walk-in into a full battle is refused (A8.5) ------------------------------
clear()
local GIO = "trainer:VIRIDIAN_GYM_obj_1"
local G = { kind = "trainer", enemy = { mon("RHYHORN") }, map = "VIRIDIAN_GYM", foe = "GIOVANNI",
            trainer = { class = "OPP_GIOVANNI", index = 3 }, encounter = GIO }
red:battleOpen(G, team("r", 6), 1, false)
pump()
id = opened(red)
green:battleJoin(id, team("g", 6), 2, false)
pump()
red:battleAt(id, 1, "menu", red.player, "h1")
pump()
eq(HostBattles.rosterSize(host.battles[id]), 12, "the roster is full")
blue:battleOpen(G, team("b", 1), 3, false)
pump()
eq(lastRejection(blue), "roster_full", "a walk-in into a full fight is refused")
eq(battleCount(), 1, "and does not open a second instance")
red:battleAt(id, 2, nil, nil, nil, "run")
pump()

-- the League's rooms are one run for the team (#55, A10.6): kept done until
-- the run's clear (tests/coop/league_test.lua)
clear()
local LORELEI = "trainer:LORELEIS_ROOM_obj_1"
local L = { kind = "trainer", enemy = { mon("DEWGONG") }, map = "LORELEIS_ROOM", foe = "LORELEI",
            trainer = { class = "OPP_LORELEI", index = 1 }, encounter = LORELEI }
green:battleOpen(L, team("g", 1), 2, false)
pump()
id = opened(green)
check(id ~= nil, "LORELEI is one fight while it runs")
green:battleAt(id, 1, nil, nil, nil, "win")
pump()
eq(host.state.encounters[LORELEI] and host.state.encounters[LORELEI].state, "done",
   "won, she is done while the team's run lasts")
clear()
blue:battleOpen(L, team("b", 1), 3, false)
pump()
eq(lastRejection(blue), "beaten", "a partner arriving later counts her as won")

-- the protocol --------------------------------------------------------------------
do
  local raw = { type = "battle_open", seq = 1, kind = "wild", enemy = { mon("PIDGEY") },
                map = "ROUTE_1", team = team("x", 1) }
  raw.encounter = "static:ROUTE_1_obj_1"
  check(Protocol.sanitize(raw, "host") ~= nil, "an encounter rides the opening")
  raw.encounter = "rival:ROUTE_22"
  eq(Protocol.sanitize(raw, "host"), nil, "an unknown kind of encounter is dropped")
  raw.encounter = "trainer:" .. ("A"):rep(80)
  eq(Protocol.sanitize(raw, "host"), nil, "and one too long")
end

-- the Hall of Fame's Cerulean Cave guard stays the campaign's (A10.8) ----------
check(Ownership.owns("flags/EVENT_BEAT_CHAMPION_RIVAL"),
      "the Champion's beaten flag, which lets the cave guard go, is the campaign's")

T.finish()
