-- The Cable Club on the host (#60, design A12.7 to A12.9, decision G32),
-- ROM-free: who a player's cable reaches (an offer either side made, then
-- mates in id order, kept while both stay, a third player without a
-- cable), the link messages passed to the mate only, a trade swapped once
-- on the host with its uids kept before either window may finish it, a
-- stalled trade sent back to its lists after 30 s without an offer or 60 s
-- without an answer, a dropped or leaving mate taking the cable with them,
-- and who is in a room in `state`.  Host and clients over loopback.
--   luajit tests/coop/cable_host_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq
local F = require("tests.coop.support.campaign_fixture")
local Transport = require("src.coop.session.Transport")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local Campaign = require("src.coop.campaign.Campaign")
local Store = require("src.coop.campaign.Store")
local World = require("src.coop.campaign.World")
local Trade = require("src.coop.campaign.Trade")
local HostCable = require("src.coop.session.HostCable")
local LinkProtocol = require("src.link.Protocol")

local SHA = ("ab"):rep(20)
local CID = "c0123456789abcdef"

local clock = 0
local function now() return clock end
local ids = 0
local function hex(n)
  ids = ids + 1
  return ("%0" .. n .. "x"):format(ids)
end

local function startHost()
  local c = Campaign.new({ id = CID, title = "KANTO", game = "red", sha1 = SHA })
  local fs = F.memFs()
  local store = Store.new({ campaign = c, fs = fs, clock = now })
  local host = Host.new({ campaign = { id = CID, title = "KANTO" },
                          cartridge = { game = "red", sha1 = SHA }, clock = now, hex = hex,
                          state = c, store = store, build = "test" })
  return host, host:serve(Transport.loopback()), fs
end

local function join(hub, name, device)
  local c = Client.new(hub:dial(), { name = name, game = "red", sha1 = SHA, build = "test",
                                     device = device, clock = now })
  c:join()
  return c
end

local function pump(host, clients, frames, dt)
  for _ = 1, frames or 4 do
    clock = clock + (dt or 1 / 60)
    for _, c in ipairs(clients) do c:update() end
    host:update()
    for _, c in ipairs(clients) do c:update() end
  end
end

local function rejected(c, reason)
  for _, r in ipairs(c.rejections) do
    if r.reason == reason then return true end
  end
  return false
end

local function viewOf(c, id)
  for _, p in ipairs(c.state and c.state.players or {}) do
    if p.id == id then return p end
  end
  return nil
end

-- partners (A12.7) ----------------------------------------------------------------
do
  local host, hub = startHost()
  local red, blue, green = join(hub, "RED", "d1"), join(hub, "BLUE", "d2"), join(hub, "GREEN", "d3")
  local all = { red, blue, green }
  pump(host, all, 6)
  check(red.player < blue.player and blue.player < green.player, "ids in join order")

  -- RED waits alone in the TRADE CENTER
  red:cableEnter("trade")
  pump(host, all, 4)
  eq(red.cable and red.cable.room, "trade", "RED is in the TRADE CENTER")
  eq(red.cable and red.cable.mate, nil, "waiting alone: no cable yet")
  eq(viewOf(blue, red.player).cable, "trade", "the others see RED in a Cable Club room")
  eq(viewOf(blue, blue.player).cable, nil, "and nobody else")

  -- GREEN comes in: the one waiting there is GREEN's mate
  green:cableEnter("trade")
  pump(host, all, 4)
  eq(red.cable.mate, green.player, "RED's cable reaches GREEN")
  eq(green.cable.mate, red.player, "and GREEN's RED")
  eq(red.cable.lead, true, "the lower id leads the link")
  eq(green.cable.lead, nil, "the other follows")
  eq(green.cable.name, "RED", "with the mate's name")
  eq(red.cable.round, 1, "the first round")

  -- BLUE's id is between theirs: the pair is kept while both stay, and a
  -- third player in a room of two gets no cable
  blue:cableEnter("trade")
  pump(host, all, 4)
  eq(red.cable.mate, green.player, "the pair is kept")
  eq(blue.cable.room, "trade", "BLUE is in the room")
  eq(blue.cable.mate, nil, "but gets no cable")

  -- the link: messages reach the mate only, BLUE has nobody to send to
  red:cableLink(1, { type = "hello", name = "RED", mode = "trade" })
  pump(host, all, 4)
  local got = green:takeCableLinks()
  eq(#got, 1, "GREEN gets RED's link message")
  eq(got[1] and got[1].link.type, "hello", "as sent")
  eq(got[1] and got[1].link.name, "RED", "with its fields")
  eq(#blue:takeCableLinks() + #red:takeCableLinks(), 0, "and nobody else")
  blue:cableLink(1, { type = "hello", name = "BLUE" })
  pump(host, all, 4)
  check(rejected(blue, "no_cable"), "a player without a cable sends nothing")
  red:cableLink(2, { type = "hello", name = "RED" })
  pump(host, all, 4)
  check(rejected(red, "stale"), "a message of another round is dropped")
  eq(#green:takeCableLinks(), 0, "and never reaches the mate")

  -- GREEN leaves the room: the cable is gone for both; BLUE, still
  -- waiting, then gets RED once RED comes back
  green:cableEnter("none")
  pump(host, all, 4)
  eq(red.cable.room, "none", "RED's cable went with GREEN")
  eq(green.cable.room, "none", "GREEN is out")
  eq(viewOf(blue, red.player).cable, nil, "nobody sees RED in a room any more")
  red:cableEnter("trade")
  pump(host, all, 4)
  eq(red.cable.mate, blue.player, "RED and BLUE are mates now")

  -- an offer either side made comes first: GREEN offers RED the cable and
  -- waits for them; RED, coming back, pairs with GREEN, not with BLUE
  red:cableEnter("none")
  pump(host, all, 4)
  green:cableEnter("trade", red.player)
  pump(host, all, 4)
  eq(green.cable.mate, nil, "GREEN waits for RED, though BLUE waits too")
  eq(blue.cable.mate, nil, "BLUE waits")
  red:cableEnter("trade")
  pump(host, all, 4)
  eq(red.cable.mate, green.player, "the offer pairs RED with GREEN")
  eq(blue.cable.mate, nil, "BLUE still has no cable")

  -- rooms do not mix: the COLOSSEUM pairs its own
  blue:cableEnter("colosseum")
  pump(host, all, 4)
  eq(blue.cable.room, "colosseum", "BLUE moves to the COLOSSEUM")
  eq(blue.cable.mate, nil, "alone there")

  -- a dropped link takes the cable with it
  green.conn:close()
  pump(host, { red, blue }, 6)
  eq(red.cable.room, "none", "GREEN dropped: RED's cable is gone")
  eq(viewOf(blue, red.player).cable, nil, "and RED is out of the room")
end

-- a trade (A12.7): swapped once on the host, uids kept --------------------------
local function party(c, mons)
  local save = F.save(c.name, { party = mons })
  c:sendWorld(World.encode(save), false)
end

local function packed(mons)
  return LinkProtocol.packParty(mons)
end

do
  local host, hub, fs = startHost()
  local red, blue = join(hub, "RED", "d1"), join(hub, "BLUE", "d2")
  local all = { red, blue }
  pump(host, all, 6)
  local redMons = { F.mon("ABRA", 10, { ot = "RED", otId = 1 }), F.mon("PIDGEY", 7, { ot = "RED", otId = 1 }) }
  local blueMons = { F.mon("MACHOP", 9, { ot = "BLUE", otId = 2 }), F.mon("RATTATA", 6, { ot = "BLUE", otId = 2 }) }
  party(red, redMons)
  party(blue, blueMons)
  pump(host, all, 4)
  local rw, bw = host.state:player(red.player).world, host.state:player(blue.player).world
  local abra, pidgey = rw.party[1].coopUid, rw.party[2].coopUid
  local machop, rattata = bw.party[1].coopUid, bw.party[2].coopUid
  check(abra and machop, "the host stamped uids on both teams")

  red:cableEnter("trade")
  blue:cableEnter("trade")
  pump(host, all, 4)
  eq(red.cable.mate, blue.player, "paired")

  -- both parties with their uids, then the offers
  red:cableLink(1, { type = "party", mons = packed(redMons) }, { abra, pidgey })
  blue:cableLink(1, { type = "party", mons = packed(blueMons) }, { machop, rattata })
  pump(host, all, 4)
  eq(#red:takeCableLinks(), 1, "RED sees BLUE's party")
  eq(#blue:takeCableLinks(), 1, "BLUE sees RED's party")
  red:cableLink(1, { type = "pick", index = 1 }) -- ABRA
  blue:cableLink(1, { type = "pick", index = 2 }) -- RATTATA
  pump(host, all, 4)
  local rp, bp = red:takeCableLinks(), blue:takeCableLinks()
  eq(rp[1] and rp[1].link.index, 2, "RED sees BLUE's offer")
  eq(bp[1] and bp[1].link.index, 1, "BLUE sees RED's offer")

  -- RED says yes first: held until BLUE says yes too
  red:cableLink(1, { type = "confirm", ok = true })
  pump(host, all, 4)
  eq(#blue:takeCableLinks(), 0, "RED's yes is held")
  eq(host.state:applied("cable:" .. red.player .. "-" .. blue.player .. ":1"), false,
     "nothing committed on one yes")
  local writes = fs.writes
  blue:cableLink(1, { type = "confirm", ok = true })
  pump(host, all, 4)
  local ry, by = red:takeCableLinks(), blue:takeCableLinks()
  eq(ry[1] and ry[1].link.type, "confirm", "RED hears BLUE's yes")
  eq(by[1] and by[1].link.type, "confirm", "BLUE hears RED's yes")
  eq(ry[1] and ry[1].uid, rattata, "with the uid of the Pokémon RED receives")
  eq(by[1] and by[1].uid, abra, "and BLUE's")
  check(host.state:applied("cable:" .. red.player .. "-" .. blue.player .. ":1"),
        "the trade is committed once")
  rw, bw = host.state:player(red.player).world, host.state:player(blue.player).world
  eq(rw.party[1].species, "RATTATA", "RED's world has RATTATA where ABRA stood")
  eq(rw.party[1].coopUid, rattata, "with its uid kept")
  eq(bw.party[2].species, "ABRA", "BLUE's world has ABRA where RATTATA stood")
  eq(bw.party[2].coopUid, abra, "with its uid kept")
  eq(rw.party[2].coopUid, pidgey, "the rest stays")
  eq(bw.pokedex.owned.ABRA, true, "BLUE's Pokédex owns ABRA")
  check(fs.writes > writes, "the host saved the campaign with the trade")

  -- the commit is once: the same swap again changes nothing
  local again, why = Trade.commit(host.state, "cable:" .. red.player .. "-" .. blue.player .. ":1",
                                  { player = red.player, give = rw.party[1] },
                                  { player = blue.player, give = bw.party[2] })
  eq(again, false, "a repeated commit id")
  eq(why, "done", "is done already")
  eq(host.state:player(red.player).world.party[1].coopUid, rattata, "and moves nothing back")

  -- the windows save after the trade, as their game does: the host keeps
  -- the uids the windows' rows carry
  local redAfter = { F.mon("RATTATA", 6, { ot = "BLUE", otId = 2 }), redMons[2] }
  redAfter[1].dvs, redAfter[1].coopUid = blueMons[2].dvs, rattata
  redMons[2].coopUid = pidgey
  red:sendWorld(World.encode(F.save("RED", { party = redAfter })), true, "link")
  pump(host, all, 4)
  eq(host.state:player(red.player).world.party[1].coopUid, rattata,
     "RED's saved world keeps the traded uid")

  -- the next round: a stalled offer goes back to the lists after 30 s
  red:cableLink(1, { type = "party", mons = packed(redAfter) }, { rattata, pidgey })
  blue:cableLink(1, { type = "party", mons = packed(blueMons) }, { machop, abra })
  pump(host, all, 4)
  red:takeCableLinks(); blue:takeCableLinks()
  red:cableLink(1, { type = "pick", index = 2 })
  pump(host, all, 4)
  pump(host, all, 10, 2.5) -- 25 s
  eq(red.cable.round, 1, "25 s without BLUE's offer: still waiting")
  pump(host, all, 4, 2.5) -- past 30 s
  eq(red.cable.round, 2, "no offer within 30 s: the round moves on")
  eq(blue.cable.round, 2, "for both screens")
  red:cableLink(1, { type = "confirm", ok = true })
  pump(host, all, 4)
  check(rejected(red, "stale"), "the old round's messages are dropped")

  -- both offered, no answer within 60 s
  red:cableLink(2, { type = "party", mons = packed(redAfter) }, { rattata, pidgey })
  blue:cableLink(2, { type = "party", mons = packed(blueMons) }, { machop, abra })
  red:cableLink(2, { type = "pick", index = 1 })
  blue:cableLink(2, { type = "pick", index = 1 })
  pump(host, all, 4)
  pump(host, all, 20, 2.5) -- 50 s
  eq(red.cable.round, 2, "50 s without an answer: still waiting")
  pump(host, all, 5, 2.5)
  eq(red.cable.round, 3, "no answer within 60 s: the round moves on")

  -- a confirm before both offers is held, never committed
  red:cableLink(3, { type = "party", mons = packed(redAfter) }, { rattata, pidgey })
  blue:cableLink(3, { type = "party", mons = packed(blueMons) }, { machop, abra })
  red:cableLink(3, { type = "pick", index = 1 })
  red:cableLink(3, { type = "confirm", ok = true })
  blue:cableLink(3, { type = "confirm", ok = true })
  pump(host, all, 4)
  eq(host.state:applied("cable:" .. red.player .. "-" .. blue.player .. ":2"), false,
     "no trade without both offers")

  -- a mate who dropped before the second yes: no trade, the cable is gone
  blue:cableLink(3, { type = "pick", index = 1 })
  pump(host, all, 4)
  red:takeCableLinks()
  blue:cableLink(3, { type = "confirm", ok = true })
  pump(host, all, 4)
  blue.conn:close()
  pump(host, { red }, 6)
  eq(red.cable.room, "none", "BLUE dropped: RED's cable is gone")
  red:cableLink(3, { type = "confirm", ok = true })
  pump(host, { red }, 4)
  check(rejected(red, "no_cable"), "RED's yes reaches nobody")
  eq(host.state:applied("cable:" .. red.player .. "-" .. blue.player .. ":2"), false,
     "a mate who dropped trades nothing")
end

-- a trade whose rows the host does not have: committed, nothing moved ---------
do
  local c = Campaign.new({ id = CID, title = "T", game = "red" })
  c:addPlayer({ id = "p01", name = "RED", game = "red" })
  c:addPlayer({ id = "p02", name = "BLUE", game = "red" })
  local ok, why = Trade.commit(c, "cable:p01-p02:1", { player = "p01", give = nil },
                               { player = "p02", give = Trade.rowOf(c, "p02", "p02:1") })
  eq(ok, false, "no rows on the host")
  eq(why, "unswapped", "is said")
  check(c:applied("cable:p01-p02:1"), "the trade still counts once")
end

-- the Colosseum (A12.9): messages pass, nothing is read or kept ------------------
do
  local host, hub = startHost()
  local red, blue = join(hub, "RED", "d1"), join(hub, "BLUE", "d2")
  local all = { red, blue }
  pump(host, all, 6)
  red:cableEnter("colosseum")
  blue:cableEnter("colosseum")
  pump(host, all, 4)
  eq(red.cable.mate, blue.player, "paired in the COLOSSEUM")
  red:cableLink(1, { type = "party", seed = 77, mons = packed({ F.mon("ABRA", 10) }) }, { "" })
  red:cableLink(1, { type = "action", kind = "move", slot = 1 })
  red:cableLink(1, { type = "confirm", ok = true })
  pump(host, all, 4)
  local got = blue:takeCableLinks()
  eq(#got, 3, "every message reaches the mate")
  eq(got[1] and got[1].link.seed, 77, "the lead's seed")
  eq(got[2] and got[2].link.kind, "move", "the battle's actions")
  eq(HostCable.OFFER_WAIT, 30, "the offer wait")
end

-- a message of an earlier pairing never reaches the next one (the integrated
-- build's live run: RED left the TRADE CENTER with B, its bye reached BLUE
-- after BLUE's screen had closed, and BLUE's next link battle in the
-- COLOSSEUM, round 1 again, took it and ended at once as "RED left")
do
  local host, hub = startHost()
  local red, blue = join(hub, "RED", "d1"), join(hub, "BLUE", "d2")
  local all = { red, blue }
  pump(host, all, 6)
  red:cableEnter("trade")
  blue:cableEnter("trade")
  pump(host, all, 4)
  eq(blue.cable.mate, red.player, "paired in the TRADE CENTER")
  red:cableLink(blue.cable.round, { type = "bye" })
  red:cableEnter("none")
  pump(host, all, 4)
  eq(blue.cable.room, "none", "RED left: BLUE's cable is gone")
  -- BLUE's screen had closed: nothing took the bye
  red:cableEnter("colosseum")
  blue:cableEnter("colosseum")
  pump(host, all, 4)
  eq(blue.cable.room, "colosseum", "paired again in the COLOSSEUM")
  red:cableLink(blue.cable.round, { type = "hello" })
  pump(host, all, 4)
  local got = blue:takeCableLinks()
  eq(#got, 1, "only the new pairing's message is waiting")
  eq(got[1] and got[1].link.type, "hello", "the old bye was dropped")
end

T.finish("cable_host_test")
