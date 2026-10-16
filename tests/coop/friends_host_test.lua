-- Friend battles and trades on the host (#23, design A12.1 to A12.6, G31),
-- ROM-free: four players over loopback, the windows' messages sent by
-- hand.  Covered: an invitation reaches only the invited player; a busy,
-- away or opening partner, oneself and a second invitation are refused;
-- NO declines, a YES pairs the two with a seed, after a recheck of both
-- (busy); the host expires an invitation after 60 s, and one whose player
-- leaves; `meeting` in `state`; a friend battle is no co-op battle (not in
-- `state.battles`); the link battle's messages reach the partner in order,
-- once, and again from the first on a new link, a message heard twice
-- kept once; a partner away pauses nothing on the host, comes back within
-- two minutes, else the pairing is released and the one left hears it;
-- leaving on purpose ends it at once; a direct trade: teams, offers, the
-- swap committed once with the uids kept, laid over both worlds and over a
-- stale copy until the window shows it, CANCEL and a drop before the
-- commit ending it for both.
--   luajit tests/coop/friends_host_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Transport = require("src.coop.session.Transport")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local Protocol = require("src.coop.session.Protocol")
local World = require("src.coop.campaign.World")
local Trade = require("src.coop.campaign.Trade")
local HostFriends = require("src.coop.friends.HostFriends")

local SHA = ("ab"):rep(20)
local CAMPAIGN = "c0123456789abcdef"

local clock, idCounter = 0, 0
local logLines = {}
local host = Host.new({
  campaign = { id = CAMPAIGN, title = "RED CO-OP" }, cartridge = { game = "red", sha1 = SHA },
  clock = function() return clock end,
  hex = function(n) idCounter = idCounter + 1; return ("%0" .. n .. "x"):format(idCounter) end,
  log = { write = function(_, _, kind, data) logLines[#logLines + 1] = { kind = kind, data = data } end,
          close = function() end },
})
local hub = host:serve(Transport.loopback())

local all = {}
local function seat(name, n)
  local c = Client.new(hub:dial(), { name = name, game = "red", sha1 = SHA, device = "d" .. n,
                                     build = "test" })
  c:join()
  all[#all + 1] = c
  return c
end
local function pump(frames)
  for _ = 1, frames or 3 do
    clock = clock + 1 / 60
    for _, c in ipairs(all) do c:update() end
    host:update()
    for _, c in ipairs(all) do c:update() end
  end
end
local red, green, blue, yellow = seat("RED", 1), seat("GREEN", 2), seat("BLUE", 3), seat("YELLOW", 4)
pump()
for _, c in ipairs({ red, green, blue }) do c:sendOpening(true) end -- past the opening (#22)
pump()

local function lastRejection(c)
  local r = c.rejections[#c.rejections]
  return r and r.reason
end
local function logged(kind)
  local n = 0
  for _, l in ipairs(logLines) do if l.kind == kind then n = n + 1 end end
  return n
end
local function only(t)
  local id, v = next(t)
  return v, id
end
-- the invitation still open for a client
local function openInvite(c)
  for id, inv in pairs(c.invites) do
    if not inv.answer then return inv, id end
  end
end
local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end
local function viewOf(c, id)
  for _, p in ipairs(c.state.players) do if p.id == id then return p end end
end

-- invitations (A12.1, A12.2) -------------------------------------------------
do
  red:invite(red.player, "battle")
  pump()
  eq(lastRejection(red), "no_partner", "nobody invites themself")
  red:invite(yellow.player, "battle")
  pump()
  eq(lastRejection(red), "partner_busy", "a partner in the opening cannot be invited")

  red:invite(green.player, "battle")
  pump()
  local inv, id = openInvite(green)
  check(inv ~= nil and inv.from == red.player and inv.kind == "battle" and not inv.answer,
        "GREEN is asked: RED wants to battle")
  eq(count(blue.invites), 0, "nobody else hears of it")
  blue:invite(green.player, "trade")
  pump()
  eq(lastRejection(blue), "invite_pending", "one invitation per player at a time")
  blue:invite(red.player, "trade")
  pump()
  eq(lastRejection(blue), "invite_pending", "the sender is in one too")

  green:answerInvite(id, false)
  pump()
  eq(red.invites[id].answer, "declined", "NO: RED hears it was declined")
  eq(green.invites[id].answer, "declined", "and GREEN's question closes")
  eq(count(host.friends.pairs), 0, "nobody is paired")
  green:answerInvite(id, true)
  pump()
  eq(lastRejection(green), "no_invite", "a settled invitation takes no second answer")

  -- the host expires one after 60 s
  red:invite(green.player, "trade")
  pump()
  local _, id2 = only(host.friends.invites)
  clock = clock + 59
  pump()
  check(red.invites[id2].answer == nil, "still open after 59 s")
  clock = clock + 2
  pump()
  eq(red.invites[id2].answer, "timeout", "the host expires it after 60 s")
  eq(green.invites[id2].answer, "timeout", "and closes the question")
end

-- a YES rechecks both players (A12.2) ----------------------------------------
do
  red:invite(blue.player, "battle")
  pump()
  local _, id = only(host.friends.invites)
  -- BLUE starts a co-op battle before answering
  local mon = { species = "PIDGEY", level = 5, hp = 20, moves = { { id = "TACKLE", pp = 35 } } }
  blue:battleOpen({ kind = "wild", enemy = { mon }, map = "ROUTE_1", foe = "PIDGEY" }, { mon }, 3, false)
  pump()
  check(next(host.battles) ~= nil, "BLUE is in a co-op battle")
  blue:answerInvite(id, true)
  pump()
  eq(red.invites[id].answer, "busy", "the recheck on YES finds BLUE busy")
  eq(count(host.friends.pairs), 0, "no pairing")
  red:invite(blue.player, "trade")
  pump()
  eq(lastRejection(red), "partner_busy", "and BLUE cannot be invited meanwhile")
  local bid = next(host.battles)
  blue:battleAt(bid, #host.battles[bid].inputs, nil, nil, nil, "run")
  pump()
  eq(require("src.coop.battle.HostBattles").of(host, blue.player), nil, "BLUE's battle ended")
end

-- a friend battle: the pairing and the relay (A12.3, A12.4) ------------------
local pairId
do
  red:invite(green.player, "battle")
  pump()
  local _, id = openInvite(green)
  green:answerInvite(id, true)
  pump()
  eq(red.invites[id].answer, "accepted", "RED hears the YES")
  local _, pid = only(host.friends.pairs)
  local pr, pg = red.pairs[pid], green.pairs[pid]
  pairId = pid
  check(pr ~= nil and pg ~= nil, "both are paired")
  eq(pr.kind, "battle", "a battle")
  eq(pr.partner, green.player, "RED's partner is GREEN")
  eq(pg.partner, red.player, "and GREEN's RED")
  eq(pr.role, "host", "the inviter is the link battle's host side")
  eq(pg.role, "guest", "the invited its guest side")
  eq(pr.seed, pg.seed, "both have the host's seed")
  eq(pg.name, "RED", "GREEN's view names RED")
  eq(viewOf(blue, red.player).meeting, "battle", "state says RED meets someone for a battle")
  eq(viewOf(blue, green.player).meeting, "battle", "and GREEN")
  eq(#(blue.state.battles or {}), 0, "a friend battle is private: no co-op battle in state")
  blue:invite(red.player, "trade")
  pump()
  eq(lastRejection(blue), "partner_busy", "a paired player cannot be invited")

  red:pairMsg(pid, 1, { type = "hello", name = "RED" })
  red:pairMsg(pid, 2, { type = "party", mons = { { species = "PIDGEY" } }, seed = 5 })
  red:pairMsg(pid, 2, { type = "party", mons = {} }) -- heard twice
  red:pairMsg(pid, 4, { type = "action" }) -- past a gap: waits
  pump()
  local r = green.relay[pid]
  eq(r and #r.list, 2, "GREEN has RED's two messages")
  eq(r.list[1].type, "hello", "in order")
  eq(#r.list[2].mons, 1, "a message heard twice is kept once")
  eq(#(red.relay[pid] and red.relay[pid].list or {}), 0, "RED does not hear its own")
  red:pairMsg(pid, 999, { bad = true })
  pump()
  check(host.dropped > 0, "a link message without a type is dropped")

  -- GREEN's link drops and comes back: the messages again from the first
  green.conn:close()
  pump()
  eq(viewOf(red, green.player).connected, false, "GREEN dropped")
  eq(red.pairs[pid].away, true, "RED's pairing says GREEN is away")
  clock = clock + 100
  pump()
  check(host.friends.pairs[pid] and not host.friends.pairs[pid].ended, "100 s: still waiting")
  local back = Client.new(hub:dial(), { name = "GREEN", game = "red", sha1 = SHA, device = "d2",
                                         build = "test", known = green.known })
  back:join()
  all[2] = back
  green = back
  pump()
  green:sendOpening(true) -- the window says so on each link (#22)
  eq(green.player, pg.partner == red.player and green.player or nil, "GREEN came back")
  check(green.pairs[pid] ~= nil, "GREEN hears the pairing again")
  eq(#green.relay[pid].list, 2, "and RED's messages from the first")
  eq(red.pairs[pid].away, nil, "RED: GREEN is back")
  green:pairMsg(pid, 1, { type = "hello", name = "GREEN" })
  pump()
  eq(#red.relay[pid].list, 1, "RED has GREEN's message")

  -- away again past the grace: released
  green.conn:close()
  pump()
  clock = clock + HostFriends.GRACE + 1
  pump()
  eq(red.pairs[pid].ended, "released", "two minutes away: the pairing is released")
  eq(viewOf(blue, red.player).meeting, nil, "RED meets nobody now")
  red:pairEnd(pid, "draw")
  pump()
  check(host.friends.pairs[pid] ~= nil, "kept for GREEN, who has not heard")
  back = Client.new(hub:dial(), { name = "GREEN", game = "red", sha1 = SHA, device = "d2",
                                   build = "test", known = green.known })
  back:join()
  all[2] = back
  green = back
  pump()
  green:sendOpening(true) -- the window says so on each link (#22)
  eq(green.pairs[pid] and green.pairs[pid].ended, "released", "GREEN hears the release on return")
  pump()
  eq(host.friends.pairs[pid], nil, "then the pairing is dropped")
end

-- a battle both finish; leaving on purpose -------------------------------
do
  red:invite(green.player, "battle")
  pump()
  local _, id = openInvite(green)
  green:answerInvite(id, true)
  pump()
  local _, pid = only(host.friends.pairs)
  red:pairEnd(pid, "win")
  pump()
  check(host.friends.pairs[pid] ~= nil, "one side finished: kept")
  eq(viewOf(blue, red.player).meeting, nil, "RED, finished, is free")
  green:pairEnd(pid, "lose")
  pump()
  eq(host.friends.pairs[pid], nil, "both finished: dropped")
  eq(logged("pair_side"), 3, "each side's end is logged")

  red:invite(green.player, "battle")
  pump()
  _, id = openInvite(green)
  green:answerInvite(id, true)
  pump()
  _, pid = only(host.friends.pairs)
  red:pairEnd(pid, "cancel")
  pump()
  eq(green.pairs[pid].ended, "left", "a window with no battle any more ends it for both")
  green:pairEnd(pid, "draw")
  pump()
end

-- a direct trade (A12.6) -------------------------------------------------------
local function row(species, uid, level)
  return { species = species, level = level or 10, hp = 30, exp = 1000, otId = 1,
           ot = "X", dvs = { attack = 1, defense = 2, speed = 3, special = 4 },
           moves = { { id = "TACKLE", pp = 35 } }, coopUid = uid }
end
local function world(party)
  return { player = { name = "W", id = 1 }, party = party, boxes = { {} }, currentBox = 1,
           money = 0 }
end

do
  -- both players' worlds in the campaign
  red:sendWorld(World.encode(world({ row("KADABRA", red.player .. ":1", 30),
                                     row("PIDGEY", red.player .. ":2") })), false)
  green:sendWorld(World.encode(world({ row("MACHOKE", green.player .. ":1", 32) })), false)
  pump()
  red:invite(green.player, "trade")
  pump()
  local _, id = openInvite(green)
  green:answerInvite(id, true)
  pump()
  local _, pid = only(host.friends.pairs)
  local pr = red.pairs[pid]
  eq(pr.kind, "trade", "paired for a trade")
  eq(viewOf(blue, green.player).meeting, "trade", "state says GREEN trades")
  red:tradeTeam(pid, Trade.encodeTeam({ row("KADABRA", red.player .. ":1", 30),
                                        row("PIDGEY", red.player .. ":2") }))
  pump()
  check(green.pairs[pid].theirs ~= nil, "GREEN has RED's team")
  eq(#Trade.decodeTeam(green.pairs[pid].theirs), 2, "both rows")
  red:tradePick(pid, 1)
  pump()
  eq(green.pairs[pid].theirPick, 1, "GREEN sees RED's offer")
  red:tradeConfirm(pid, true)
  pump()
  eq(lastRejection(red), "bad_pick", "no TRADE before both offered")
  green:tradeTeam(pid, "return { 1, 2 }")
  pump()
  eq(lastRejection(green), "bad_team", "a team that is no team is refused")
  green:tradeTeam(pid, Trade.encodeTeam({ row("MACHOKE", green.player .. ":1", 32) }))
  green:tradePick(pid, 3)
  pump()
  eq(lastRejection(green), "bad_pick", "an offer past the team is refused")
  green:tradePick(pid, 1)
  pump()
  red:tradeConfirm(pid, true)
  pump()
  eq(red.pairs[pid].confirmed, true, "RED said TRADE")
  eq(red.pairs[pid].done, nil, "not done before both")
  green:tradeConfirm(pid, true)
  pump()
  eq(red.pairs[pid].done, true, "both said TRADE: the trade is done")
  eq(green.pairs[pid].done, true, "for both")
  check(host.state:applied("trade:" .. pid), "committed once (trade:<pair>)")
  local rw = host.state:player(red.player).world
  local gw = host.state:player(green.player).world
  eq(rw.party[1].species, "MACHOKE", "RED's world holds MACHOKE in KADABRA's slot")
  eq(rw.party[1].coopUid, green.player .. ":1", "with its uid")
  eq(gw.party[1].species, "KADABRA", "GREEN's world holds KADABRA")
  eq(gw.party[1].coopUid, red.player .. ":1", "with its uid")
  eq(rw.party[2].coopUid, red.player .. ":2", "RED's PIDGEY stays")
  green:tradeConfirm(pid, true)
  pump()
  eq(lastRejection(green), "no_pair", "a done trade takes no second TRADE")

  -- RED's window sends a copy from before it applied the swap: laid over
  red:sendHoldings(World.split(world({ row("KADABRA", red.player .. ":1", 30),
                                        row("PIDGEY", red.player .. ":2") })))
  pump()
  rw = host.state:player(red.player).world
  eq(rw.party[1].coopUid, green.player .. ":1", "a stale copy cannot undo the trade")
  eq(rw.party[1].species, "MACHOKE", "MACHOKE stays RED's")
  -- then the window's own: it evolved MACHOKE into MACHAMP, uid kept
  local evolved = row("MACHAMP", green.player .. ":1", 32)
  red:sendHoldings(World.split(world({ evolved, row("PIDGEY", red.player .. ":2") })))
  pump()
  rw = host.state:player(red.player).world
  eq(rw.party[1].species, "MACHAMP", "the window's evolution is kept")
  eq(#host.state:player(red.player).trades, 0, "the window shows the swap: nothing owed")
  eq(#host.state:player(green.player).trades, 1, "GREEN's window has not shown it yet")
  red:pairEnd(pid, "done")
  green:pairEnd(pid, "done")
  pump()
  eq(host.friends.pairs[pid], nil, "both done: dropped")
  eq(logged("trade"), 1, "one trade logged")
end

-- CANCEL and a drop before the commit end it for both --------------------------
do
  red:invite(green.player, "trade")
  pump()
  local _, id = openInvite(green)
  green:answerInvite(id, true)
  pump()
  local _, pid = only(host.friends.pairs)
  red:tradeTeam(pid, Trade.encodeTeam({ row("PIDGEY", red.player .. ":2") }))
  green:tradeTeam(pid, Trade.encodeTeam({ row("KADABRA", red.player .. ":1", 30) }))
  red:tradePick(pid, 1)
  green:tradePick(pid, 1)
  pump()
  green:tradeConfirm(pid, false)
  pump()
  eq(red.pairs[pid].ended, "cancel", "CANCEL ends the trade for both")
  check(not host.state:applied("trade:" .. pid), "nothing swapped")
  red:pairEnd(pid, "cancel")
  pump()

  red:invite(green.player, "trade")
  pump()
  _, id = openInvite(green)
  green:answerInvite(id, true)
  pump()
  _, pid = only(host.friends.pairs)
  red:pairEnd(pid, "cancel")
  pump()
  eq(green.pairs[pid].ended, "cancel", "CANCEL on the screen ends it too")
  green:pairEnd(pid, "cancel")

  red:invite(green.player, "trade")
  pump()
  _, id = openInvite(green)
  green:answerInvite(id, true)
  pump()
  _, pid = only(host.friends.pairs)
  green.conn:close()
  pump()
  eq(red.pairs[pid].ended, "left", "a disconnect ends the pairing")
end

-- an invitation whose player leaves ------------------------------------------
do
  red:invite(blue.player, "battle")
  pump()
  local _, id = only(host.friends.invites)
  blue:leave()
  pump()
  eq(red.invites[id].answer, "left", "the invited player left: settled")
end

check(Protocol.VERSION >= 11, "protocol 11 carries friend battles and trades")
T.finish()
