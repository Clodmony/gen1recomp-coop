-- Co-op battles on the host (#18, design A8, G24), ROM-free and without a
-- battle engine: the host is the sequencer.  Three players over loopback;
-- the windows' reports (`battle_at`) are sent by hand.  Covered: opening a
-- battle and the seed, one battle per player, joins queued until the
-- battle asks for a move and then put in behind the roster, trimmed to
-- twelve, `roster_full`; commands only for the current revision, from the
-- player asked, of the asked kind, RUN only by the opener; stale commands
-- after a join; suggestions apart from the inputs, not from the decider,
-- cleared by the next input; reports taken once, a different one logged
-- as a desync; the end, the queued join released, the battle dropped;
-- saves refused while a battle runs; who is in which battle in `state`.
--   luajit tests/coop/battle_host_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Transport = require("src.coop.session.Transport")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local Protocol = require("src.coop.session.Protocol")
local HostBattles = require("src.coop.battle.HostBattles")

local SHA = ("ab"):rep(20)
local CAMPAIGN = "c0123456789abcdef"

local clock, idCounter = 0, 0
local logLines = {}
local host = Host.new({
  campaign = { id = CAMPAIGN, title = "RED CO-OP" }, cartridge = { game = "red", sha1 = SHA },
  clock = function() return clock end,
  hex = function(n) idCounter = idCounter + 1; return ("%0" .. n .. "x"):format(idCounter) end,
  log = { write = function(_, src, kind, data) logLines[#logLines + 1] = { kind = kind, data = data } end,
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
local yellow = seat("YELLOW", 4)
local all = { red, green, blue, yellow }
local function pump(frames)
  for _ = 1, frames or 3 do
    clock = clock + 1 / 60
    for _, c in ipairs(all) do c:update() end
    host:update()
    for _, c in ipairs(all) do c:update() end
  end
end
pump()
for _, c in ipairs(all) do eq(c.status, "joined", c.name .. " joined") end

local function mon(species, uid, hp)
  return { species = species, level = 10, hp = hp or 30, uid = uid,
           moves = { { id = "TACKLE", pp = 35 } } }
end
local function team(prefix, n, hp)
  local out = {}
  for i = 1, n do out[i] = mon("PIDGEY", prefix .. i, hp) end
  return out
end
local function lastRejection(c)
  local r = c.rejections[#c.rejections]
  return r and r.reason
end
local function logged(kind)
  local n = 0
  for _, l in ipairs(logLines) do if l.kind == kind then n = n + 1 end end
  return n
end

local OPENING = { kind = "wild", enemy = { mon("RATTATA", nil) }, map = "ROUTE_1", foe = "RATTATA" }

-- opening -------------------------------------------------------------------
red:battleOpen(OPENING, team("r", 6), 1234, false)
pump()
local id = next(red.battles)
check(id ~= nil, "the opener hears its battle")
local rb = red.battles[id]
eq(rb.open.by, red.player, "the opening names who opened it")
eq(rb.open.map, "ROUTE_1", "and the map")
check(rb.seed >= 1 and rb.seed <= 2147483646, "the host dealt a seed")
eq(#rb.inputs, 1, "the opener's team is the first input")
eq(rb.inputs[1].kind, "join", "a join")
eq(#rb.inputs[1].team, 6, "with six Pokémon")
eq(rb.inputs[1].otId, 1234, "and the opener's trainer id")
eq(rb.rev, 1, "revision 1")
check(green.battles[id] == nil, "a player not in the battle hears nothing of its inputs")
local summary = green.state.battles and green.state.battles[1]
eq(summary and summary.id, id, "everyone sees the running battle in state")
eq(summary and summary.by, red.player, "who started it")
eq(summary and summary.foe, "RATTATA", "and against what")
eq(green:playerView(red.player).battle, id, "a player in a battle shows it")
eq(host:busy(), "battle_in_progress", "the campaign does not save while it runs (A3.7)")

red:battleOpen(OPENING, team("r", 6), 1234, false)
pump()
eq(lastRejection(red), "in_battle", "one battle per player (A8.1)")

green:battleOpen(OPENING, team("g", 2, 0), 99, false)
pump()
eq(lastRejection(green), "no_pokemon", "a team with nobody standing cannot fight")

-- commands before the battle asks anything --------------------------------
red:battleCmd(id, 1, { kind = "move", slot = 1 })
pump()
eq(lastRejection(red), "not_ready", "no command before a window reports the question")

-- the window reports: the menu, asked of red ------------------------------
red:battleAt(id, 1, "menu", red.player, "h1")
pump()
eq(red.battles[id].ask, "menu", "the ask goes out")
eq(red.battles[id].by, red.player, "of red")

-- a join is queued and goes in at once at a safe point ---------------------
green:battleJoin(id, team("g", 4), 77, true)
pump()
local gb = green.battles[id]
check(gb ~= nil, "the joiner hears the whole battle")
eq(#gb.inputs, 2, "its join is in at once: the battle waited for a move (A8.4)")
eq(gb.inputs[2].player, green.player, "behind the opener's team (A8.5)")
eq(gb.inputs[2].expAll, true, "with its EXP.ALL")
eq(gb.open.kind, "wild", "and the opening")
eq(red.battles[id].rev, 2, "the revision moved on")
eq(red.battles[id].ask, nil, "the old question is gone")

-- a command for the old revision is stale ---------------------------------
red:battleCmd(id, 1, { kind = "move", slot = 1 })
pump()
eq(lastRejection(red), "stale", "a command in flight for the old revision is refused (A8.4)")
red:battleAt(id, 2, "menu", red.player, "h2")
green:battleAt(id, 2, "menu", red.player, "h2")
pump()
eq(logged("battle_desync"), 0, "the same report twice is no desync")

-- who may answer ------------------------------------------------------------
green:battleCmd(id, 2, { kind = "move", slot = 1 })
pump()
eq(lastRejection(green), "not_yours", "only the player asked decides (A8.6)")
red:battleCmd(id, 2, { kind = "replace", index = 2 })
pump()
eq(lastRejection(red), "bad_cmd", "a command of another kind than asked is refused")
red:battleCmd(id, 2, { kind = "switch", index = 13 })
pump()
eq(lastRejection(red), "bad_cmd", "a switch past the roster is refused")

-- suggestions --------------------------------------------------------------
red:battleSuggest(id, 2, { kind = "move", slot = 2 })
pump()
eq(lastRejection(red), "not_yours", "the decider does not suggest to themself (A8.8)")
green:battleSuggest(id, 2, { kind = "switch", index = 7 })
pump()
local sugg = red.battles[id].suggestions
eq(#sugg, 1, "a partner's suggestion is shown to everyone")
eq(sugg[1].by, green.player, "with who made it")
eq(#red.battles[id].inputs, 2, "a suggestion is never an input (A8.8)")

-- an accepted command -------------------------------------------------------
red:battleCmd(id, 2, { kind = "move", slot = 1 })
pump()
eq(#green.battles[id].inputs, 3, "the command is the next input for everyone")
eq(green.battles[id].inputs[3].cmd.kind, "move", "as sent")
eq(#green.battles[id].suggestions, 0, "suggestions clear when the revision moves on")
red:battleCmd(id, 2, { kind = "move", slot = 1 })
pump()
eq(lastRejection(red), "stale", "the same command again is refused (A8.7)")

-- a differing report is a desync, logged --------------------------------------
red:battleAt(id, 3, "menu", green.player, "h3")
green:battleAt(id, 3, "menu", green.player, "h3-other")
pump()
eq(logged("battle_desync"), 1, "two reports that differ are logged as a desync")
eq(red.battles[id].by, green.player, "the first report is taken")

-- RUN only for the opener -----------------------------------------------------
green:battleCmd(id, 3, { kind = "run" })
pump()
eq(lastRejection(green), "run_initiator", "RUN flees only for the opener (A9.5)")

-- a forced replacement holds joins ------------------------------------------
green:battleCmd(id, 3, { kind = "move", slot = 1 })
pump()
red:battleAt(id, 4, "replace", green.player, "h4")
pump()
blue:battleJoin(id, team("b", 6), 5, false)
pump()
eq(#red.battles[id].inputs, 4, "a join waits while a replacement is asked (A8.4)")
check(blue.battles[id] ~= nil, "the queued player hears the battle")
eq(blue:playerView(blue.player).battle, nil, "a queued player is not in it yet")
blue:battleOpen(OPENING, team("b", 1), 5, false)
pump()
eq(lastRejection(blue), "in_battle", "a queued player starts nothing else (A8.1)")
yellow:battleJoin(id, team("y", 3), 6, false)
pump()
green:battleCmd(id, 4, { kind = "replace", index = 8 })
pump()
red:battleAt(id, 5, "menu", green.player, "h5")
pump()
local inputs = red.battles[id].inputs
eq(#inputs, 6, "at the next move question the queued teams go in")
eq(inputs[6].player, blue.player, "the first queued team first (A8.9)")
eq(#inputs[6].team, 2, "trimmed to the room left of twelve, in party order (A8.5)")
eq(inputs[6].team[1].uid, "b1", "its first Pokémon")
eq(lastRejection(yellow), "roster_full", "a team with no room left is refused (A8.5)")
eq(yellow.battles[id] and #yellow.battles[id].inputs or 0, 5,
  "the refused player is not in it")
eq(blue:playerView(blue.player).battle, id, "blue is in the battle now")

yellow:battleJoin(id, team("y", 3), 6, false)
pump()
eq(lastRejection(yellow), "roster_full", "a full roster refuses a join at once")

-- the end ---------------------------------------------------------------------
blue:battleAt(id, 6, nil, nil, nil, "win")
pump()
eq(red.battles[id].ended, "win", "everyone hears the end")
eq(blue.battles[id].ended, "win", "the late joiner too")
eq(host.battles[id], nil, "the host dropped the finished battle (A8.21)")
eq(host:busy(), nil, "the campaign may save again")
eq(#(green.state.battles or {}), 0, "no battle in state")
eq(green:playerView(red.player).battle, nil, "nobody shows a battle")
red:battleCmd(id, 6, { kind = "move", slot = 1 })
pump()
eq(lastRejection(red), "no_battle", "a command for a finished battle is refused")

-- a queued join is released when its battle ends (A11.8) ------------------------
red:battleOpen(OPENING, team("r", 1), 1234, false)
pump()
local id2
for k, b in pairs(red.battles) do if not b.ended then id2 = k end end
check(id2 ~= nil and id2 ~= id, "a new battle")
green:battleJoin(id2, team("g", 1), 77, false)
pump()
eq(host.joins[green.player] and host.joins[green.player].battle, id2,
  "a join before any report waits")
red:battleAt(id2, 1, nil, nil, nil, "run")
pump()
eq(host.joins[green.player], nil, "the queued join is released with the battle's end")
eq(green.battles[id2] and green.battles[id2].ended, "run", "and told the end")
eq(host:busy(), nil, "nothing holds the save")

-- a player who drops is absent, a returning one present again ---------------------
red:battleOpen(OPENING, team("r", 1), 1234, false)
pump()
local id3
for k, b in pairs(red.battles) do if not b.ended then id3 = k end end
red:battleAt(id3, 1, "menu", red.player, "x")
green:battleJoin(id3, team("g", 1), 77, false)
pump()
local present
for _, e in ipairs(red.battles[id3].players) do if e.id == green.player then present = e.present end end
eq(present, true, "the joiner is present")
local known = green.known
green.conn:close()
pump()
for _, e in ipairs(red.battles[id3].players) do if e.id == green.player then present = e.present end end
eq(present, false, "a dropped player is absent from the battle (A11.1)")
green = Client.new(hub:dial(), { name = "GREEN", game = "red", sha1 = SHA, device = "d2",
                                 known = known, build = "test" })
green:join()
all[2] = green
pump()
for _, e in ipairs(red.battles[id3].players) do if e.id == green.player then present = e.present end end
eq(present, true, "back on a new link, present again")
eq(green.battles[id3] and #green.battles[id3].inputs, 2, "and the new link hears the whole battle")
red:battleAt(id3, 2, nil, nil, nil, "run")
pump()
eq(host.battles[id3], nil, "(that battle ends)")

-- leaving, the absent decider, rejoining (#20, A11.1 to A11.5) ------------------------------
do
  red:battleOpen(OPENING, team("r", 2), 1234, false)
  pump()
  local id4
  for k, b in pairs(red.battles) do if not b.ended then id4 = k end end
  red:battleAt(id4, 1, "menu", red.player, "x")
  pump()
  yellow:battleJoin(id4, team("y", 2), 6, false)
  pump()
  eq(#red.battles[id4].inputs, 2, "YELLOW is in")
  red:battleLeave(id4)
  pump()
  eq(lastRejection(red), "opener_stays", "the opener cannot leave (A11.2)")
  yellow:battleLeave(id4)
  pump()
  local entry
  for _, e in ipairs(red.battles[id4].players) do if e.id == yellow.player then entry = e end end
  eq(entry and entry.left, true, "YELLOW left the battle (A11.1)")
  eq(entry and entry.present, false, "and is absent")
  -- YELLOW's Pokemon is out: the first present player decides at once (A11.5)
  red:battleAt(id4, 2, "menu", yellow.player, "y")
  pump()
  eq(red.battles[id4].owner, yellow.player, "the question is about YELLOW's Pokémon")
  eq(red.battles[id4].by, red.player, "RED decides for it at once")
  red:battleCmd(id4, 2, { kind = "move", slot = 1 })
  pump()
  eq(#red.battles[id4].inputs, 3, "and RED's command goes in")
  -- REJOIN: YELLOW decides for their own Pokemon again (A11.4)
  yellow:battleRejoin(id4)
  pump()
  for _, e in ipairs(red.battles[id4].players) do if e.id == yellow.player then entry = e end end
  eq(entry.present, true, "REJOIN: YELLOW is back in at once (A11.4)")
  red:battleAt(id4, 3, "menu", yellow.player, "z")
  pump()
  eq(red.battles[id4].by, yellow.player, "and decides for their Pokémon again")
  red:battleRejoin(id4)
  pump()
  eq(lastRejection(red), "not_away", "a player who never left has nothing to rejoin")

  -- YELLOW drops while asked: the battle waits; TAKE OVER after 30 s (A11.5, A11.6)
  local yKnown = yellow.known
  yellow.conn:close()
  pump()
  eq(red.battles[id4].by, nil, "a dropped decider pauses the battle")
  red:battleCmd(id4, 3, { kind = "move", slot = 1 })
  pump()
  eq(lastRejection(red), "not_yours", "nobody decides for them unasked")
  red:battleTakeover(id4, yellow.player)
  pump()
  eq(lastRejection(red), "not_ready", "TAKE OVER is not offered before 30 s")
  clock = clock + HostBattles.TAKEOVER
  pump()
  eq(red.battles[id4].offer, yellow.player, "after 30 s the present players are offered TAKE OVER")
  red:battleTakeover(id4, yellow.player)
  pump()
  eq(red.battles[id4].by, red.player, "RED stands in for YELLOW")
  eq(red.battles[id4].standins[1] and red.battles[id4].standins[1].owner, yellow.player,
    "the view names both")
  -- YELLOW comes back: their own decision again
  yellow = Client.new(hub:dial(), { name = "YELLOW", game = "red", sha1 = SHA, device = "d4",
                                    known = yKnown, build = "test" })
  yellow:join()
  all[4] = yellow
  pump()
  eq(red.battles[id4].by, yellow.player, "back: YELLOW takes back control (A11.6)")
  eq(#red.battles[id4].standins, 0, "no stand-in any more")
  eq(yellow.battles[id4] and #yellow.battles[id4].inputs, 3, "and hears the battle again")

  -- YELLOW drops again and the battle ends meanwhile: told once back (A11.8)
  yKnown = yellow.known
  yellow.conn:close()
  pump()
  red:battleAt(id4, 3, nil, nil, nil, "win")
  pump()
  eq(host.battles[id4], nil, "the battle is over")
  yellow = Client.new(hub:dial(), { name = "YELLOW", game = "red", sha1 = SHA, device = "d4",
                                    known = yKnown, build = "test" })
  yellow:join()
  all[4] = yellow
  pump()
  eq(yellow.battles[id4] and yellow.battles[id4].ended, "win",
    "a player away when it ended gets the end when back (A11.8)")
  eq(yellow.battles[id4] and #yellow.battles[id4].inputs, 3, "with the whole battle")
  eq(host.missed[yellow.player] and next(host.missed[yellow.player]), nil, "once")
end

-- a queued join is called off (A11.4) --------------------------------------------------------
do
  red:battleOpen(OPENING, team("r", 1), 1234, false)
  pump()
  local id5
  for k, b in pairs(red.battles) do if not b.ended then id5 = k end end
  blue:battleJoin(id5, team("b", 1), 5, false)
  pump()
  check(host.joins[blue.player] ~= nil, "BLUE's join waits")
  blue:battleLeave(id5)
  pump()
  eq(host.joins[blue.player], nil, "called off")
  -- nobody present for two minutes: the battle ends as fled (A11.7)
  local rKnown = red.known
  red.conn:close()
  pump()
  clock = clock + HostBattles.ABANDON
  pump()
  eq(host.battles[id5], nil, "a battle nobody is in ends after two minutes (A11.7)")
  red = Client.new(hub:dial(), { name = "RED", game = "red", sha1 = SHA, device = "d1",
                                 known = rKnown, build = "test" })
  red:join()
  all[1] = red
  pump()
  eq(red.battles[id5] and red.battles[id5].ended, "run", "as fled, told when back")
end

-- shutdown: battles still running end as fled before `ended` (A11.7) ---------------------------
do
  red:battleOpen(OPENING, team("r", 1), 1234, false)
  pump()
  local id6
  for k, b in pairs(red.battles) do if not b.ended then id6 = k end end
  host:shutdown("host_quit")
  pump()
  eq(red.battles[id6] and red.battles[id6].ended, "run", "a running battle ends as fled at shutdown")
  eq(red.status, "ended", "then the session ends")
end

T.finish()
