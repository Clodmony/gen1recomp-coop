-- One trade core for direct trades and the Cable Club (#62), and a trade
-- whose yes never reached a window is owed, not lost (#63), ROM-free.
-- Covered: Trade.commit swaps both stored worlds once and owes each player
-- their side; the owed trades live in the campaign file (version 5); a
-- stale world or holdings cannot undo a trade; the window that never heard
-- the yes is sent its owed trade and applies it at its next rest point
-- (once, with the received row's uid), then the host owes nothing; the
-- window that did hear it changes nothing.  Both a Cable Club trade and a
-- direct trade, host and windows over loopback.
--   luajit tests/coop/trade_owed_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq
local F = require("tests.coop.support.campaign_fixture")
local Transport = require("src.coop.session.Transport")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local Campaign = require("src.coop.campaign.Campaign")
local CampaignFile = require("src.coop.campaign.CampaignFile")
local Window = require("src.coop.campaign.Window")
local World = require("src.coop.campaign.World")
local Trade = require("src.coop.campaign.Trade")
local Protocol = require("src.coop.session.Protocol")
local LinkProtocol = require("src.link.Protocol")
local Json = require("src.link.Json")

local SHA = ("ab"):rep(20)
local CID = "c0123456789abcdef"

local clock = 0
local function now() return clock end
local ids = 0
local function hex(n)
  ids = ids + 1
  return ("%0" .. n .. "x"):format(ids)
end

-- where a uid stands across every player's stored world (a clone stands twice)
local function standing(c, uid)
  local n = 0
  for _, p in ipairs(c.players) do
    for _, at in ipairs(p.world and World.mons(p.world) or {}) do
      if at.mon.coopUid == uid then n = n + 1 end
    end
  end
  return n
end

-- 1. the core on a campaign -------------------------------------------------------
do
  local c = Campaign.new({ id = CID, title = "T", game = "red" })
  c:addPlayer({ id = "p01", name = "RED", game = "red" })
  c:addPlayer({ id = "p02", name = "BLUE", game = "red" })
  c:setWorld("p01", F.save("RED", { party = { F.mon("KADABRA", 30), F.mon("PIDGEY", 7) } }))
  c:setWorld("p02", F.save("BLUE", { party = { F.mon("MACHOP", 9) } }))
  local ra, rb = c:player("p01").world.party[1], c:player("p02").world.party[1]
  local ua, ub = ra.coopUid, rb.coopUid
  local ok = Trade.commit(c, "cable:p01-p02:1", { player = "p01", give = ra },
                          { player = "p02", give = rb })
  eq(ok, true, "committed and moved")
  eq(c:player("p01").world.party[1].coopUid, ub, "RED's world has MACHOP in KADABRA's slot")
  eq(c:player("p02").world.party[1].coopUid, ua, "BLUE's world has KADABRA")
  eq(c:player("p02").world.pokedex.owned.KADABRA, true, "BLUE's Pokédex owns KADABRA")
  eq(#(c:player("p01").trades or {}), 1, "RED is owed the trade until a world shows it")
  eq(#(c:player("p02").trades or {}), 1, "and BLUE")
  local again, why = Trade.commit(c, "cable:p01-p02:1", { player = "p01", give = rb },
                                  { player = "p02", give = ra })
  eq(again, false, "a repeated commit")
  eq(why, "done", "is done already")
  eq(c:player("p01").world.party[1].coopUid, ub, "and moves nothing back")
  eq(#c:player("p01").trades, 1, "nor owes it twice")

  -- the file keeps what is owed (version 5)
  local text = CampaignFile.encode(c)
  local back = Campaign.fromSnapshot(CampaignFile.parse(text))
  eq(#(back:player("p02").trades or {}), 1, "the owed trade survives the file")
  eq(back:player("p02").trades[1].get.coopUid, ua, "with the row to receive")
  eq(CampaignFile.VERSION, 5, "campaign file version 5")
  local old = Json.decode(text)
  old.version = 4
  for _, entry in ipairs(old.players) do entry.trades = nil end
  local migrated = CampaignFile.parse(Json.encode(old))
  check(migrated and migrated.version == 5, "a version-4 file is brought up")
  eq(#(migrated.players[1].trades or { 0 }), 0, "owing nothing")

  -- a stale world laid over; the window's own shows it and it is owed no more
  local stale = F.save("BLUE", { party = { Trade.copy(rb) } })
  Trade.layOver(c, "p02", stale)
  eq(stale.party[1].coopUid, ua, "a stale world gets the trade laid over")
  c:setWorld("p02", stale)
  eq(#c:player("p02").trades, 1, "laid over is not shown: still owed")
  local evolved = Trade.copy(ra)
  evolved.species = "ALAKAZAM"
  local own = F.save("BLUE", { party = { evolved } })
  Trade.layOver(c, "p02", own)
  eq(own.party[1].species, "ALAKAZAM", "the window's evolution stands")
  eq(#c:player("p02").trades, 0, "the window shows the trade: owed no more")

  -- rows the host does not have: committed, nothing moved, nothing owed
  local none, nwhy = Trade.commit(c, "cable:p01-p02:2", { player = "p01", give = nil },
                                  { player = "p02", give = rb })
  eq(none, false, "no rows on the host")
  eq(nwhy, "unswapped", "is said")
  check(c:applied("cable:p01-p02:2"), "the trade still counts once")
  eq(#c:player("p01").trades, 1, "nothing more owed")
end

-- over the session ------------------------------------------------------------------
local function startHost()
  local c = Campaign.new({ id = CID, title = "KANTO", game = "red", sha1 = SHA })
  local host = Host.new({ campaign = { id = CID, title = "KANTO" },
                          cartridge = { game = "red", sha1 = SHA }, clock = now, hex = hex,
                          state = c, build = "test" })
  return host, host:serve(Transport.loopback())
end

local traded = {}
local function window(hub, name, device, known, save)
  local c = Client.new(hub:dial(), { name = name, game = "red", sha1 = SHA, build = "test",
                                     device = device, known = known, clock = now })
  c:join()
  local x = { c = c, w = Window.new(c), save = save, map = "PALLET_TOWN", name = name }
  traded[x] = {}
  return x
end

local function pump(host, wins, frames)
  for _ = 1, frames or 4 do
    clock = clock + 1 / 60
    for _, x in ipairs(wins) do x.c:update() end
    host:update()
    for _, x in ipairs(wins) do
      x.c:update()
      x.w:update({ save = x.save, busy = x.busy, map = x.map, still = true,
                   traded = function(row, gave) traded[x][#traded[x] + 1] = row.species end })
    end
  end
end

-- two windows with worlds the host has stamped
local function pairOfWindows(redMons, blueMons)
  local host, hub = startHost()
  local red = window(hub, "RED", "d1", nil, F.save("RED", { party = redMons, trainer = 1 }))
  local blue = window(hub, "BLUE", "d2", nil, F.save("BLUE", { party = blueMons, trainer = 2 }))
  pump(host, { red, blue }, 6)
  red.c:sendWorld(World.encode(red.save), false)
  blue.c:sendWorld(World.encode(blue.save), false)
  pump(host, { red, blue }, 8)
  return host, hub, red, blue
end

-- 2. a Cable Club trade whose yes never reached BLUE (#63) ------------------------
do
  local host, hub, red, blue = pairOfWindows(
    { F.mon("ABRA", 10, { ot = "RED", otId = 1 }), F.mon("PIDGEY", 7, { ot = "RED", otId = 1 }) },
    { F.mon("MACHOP", 9, { ot = "BLUE", otId = 2 }), F.mon("RATTATA", 6, { ot = "BLUE", otId = 2 }) })
  local all = { red, blue }
  local abra, rattata = red.save.party[1].coopUid, blue.save.party[2].coopUid
  check(abra and rattata, "the windows carry the host's uids")
  red.busy, blue.busy = "link", "link" -- behind the receptionist: no rest point
  red.c:cableEnter("trade")
  blue.c:cableEnter("trade")
  pump(host, all, 4)
  red.c:cableLink(1, { type = "party", mons = LinkProtocol.packParty(red.save.party) },
                  { red.save.party[1].coopUid, red.save.party[2].coopUid })
  blue.c:cableLink(1, { type = "party", mons = LinkProtocol.packParty(blue.save.party) },
                   { blue.save.party[1].coopUid, blue.save.party[2].coopUid })
  red.c:cableLink(1, { type = "pick", index = 1 })  -- ABRA
  blue.c:cableLink(1, { type = "pick", index = 2 }) -- RATTATA
  pump(host, all, 4)
  red.c:cableLink(1, { type = "confirm", ok = true })
  blue.c:cableLink(1, { type = "confirm", ok = true })
  -- both yeses reach the host, which commits and answers; BLUE's link
  -- drops before BLUE reads the answer
  red.c:update()
  blue.c:update()
  host:update()
  red.c:update()
  local got = red.c:takeCableLinks()
  blue.c.conn:close()
  pump(host, { red }, 4)
  local id = "cable:" .. red.c.player .. "-" .. blue.c.player .. ":1"
  check(host.state:applied(id), "the host committed the trade")
  -- RED heard the yes: its link screen swapped (LinkState's own trade,
  -- the received row stamped with its uid by CableClub's onTraded)
  local yes
  for _, m in ipairs(got) do if m.link.type == "confirm" then yes = m end end
  eq(yes and yes.uid, rattata, "RED heard BLUE's yes with RATTATA's uid")
  red.save.party[1] = Trade.copy(host.state:player(blue.c.player).world.party[2])
  red.save.party[1].coopUid, red.save.party[1].species = rattata, "RATTATA"
  red.save.party[1].traded = true
  red.busy = nil

  -- BLUE comes back with the world it had: RATTATA still in its team
  local bp = blue.c.player
  local back = window(hub, "BLUE", "d2", blue.c.known, blue.save)
  back.busy = "title" -- not at a rest point yet
  pump(host, { red, back }, 6)
  -- its game saves (or sends holdings) before it reached a rest point
  back.c:sendHoldings(World.split(Trade.copy(back.save)))
  pump(host, { red, back }, 4)
  eq(standing(host.state, rattata), 1, "no clone: RATTATA stands in one world")
  eq(standing(host.state, abra), 1, "nor ABRA")
  eq(host.state:player(bp).world.party[2].coopUid, abra, "the host keeps BLUE's side")
  back.busy = nil
  back.save.money = back.save.money + 1 -- a holdings change at its rest points
  pump(host, { red, back }, 12)
  eq(back.save.party[2].coopUid, abra, "BLUE's window applied the owed trade at a rest point")
  eq(back.save.party[2].species, "ABRA", "ABRA stands where RATTATA stood")
  eq(back.save.pokedex.owned.ABRA, true, "BLUE's Pokédex owns ABRA")
  eq(table.concat(traded[back], ","), "ABRA", "the game was told once (text, evolution)")
  eq(table.concat(traded[red], ","), "", "RED's window, which traded on screen, changes nothing")
  eq(red.save.party[1].coopUid, rattata, "RED keeps its RATTATA")
  pump(host, { red, back }, Window.HOLDINGS_EVERY + 4)
  eq(standing(host.state, rattata), 1, "still no clone")
  eq(standing(host.state, abra), 1, "for either")
  eq(#(host.state:player(bp).trades or {}), 0, "BLUE's world shows it: owed no more")
  eq(#(host.state:player(red.c.player).trades or {}), 0, "RED's too")
  eq(table.concat(traded[back], ","), "ABRA", "and nothing applied twice")
end

-- 3. a direct trade whose done never reached GREEN (#63, #23's same race) ----------
do
  local host, hub, red, green = pairOfWindows(
    { F.mon("KADABRA", 30, { ot = "RED", otId = 1 }), F.mon("PIDGEY", 7, { ot = "RED", otId = 1 }) },
    { F.mon("MACHOKE", 32, { ot = "BLUE", otId = 2 }) })
  local all = { red, green }
  local kadabra, machoke = red.save.party[1].coopUid, green.save.party[1].coopUid
  red.c:invite(green.c.player, "trade")
  pump(host, all, 4)
  local inv
  for _, i in pairs(green.c.invites or {}) do inv = i end
  check(inv ~= nil, "GREEN is invited")
  green.c:answerInvite(inv.id, true)
  pump(host, all, 4)
  local pid
  for k in pairs(host.friends.pairs) do pid = k end
  red.busy, green.busy = "trade", "trade"
  red.c:tradeTeam(pid, Trade.encodeTeam(red.save.party))
  green.c:tradeTeam(pid, Trade.encodeTeam(green.save.party))
  red.c:tradePick(pid, 1)
  green.c:tradePick(pid, 1)
  pump(host, all, 4)
  red.c:tradeConfirm(pid, true)
  green.c:tradeConfirm(pid, true)
  red.c:update()
  green.c:update()
  host:update()
  red.c:update()
  green.c.conn:close()
  pump(host, { red }, 4)
  check(host.state:applied("trade:" .. pid), "committed")
  eq(red.c.pairs[pid].done, true, "RED heard it is done")
  -- RED's screen swapped its own team (TradeScreen:_done)
  Trade.swap(red.save, red.save.party[1], host.state:player(red.c.player).world.party[1])
  red.busy = nil
  local gp = green.c.player
  local back = window(hub, "GREEN", "d2", green.c.known, green.save)
  back.busy = "title"
  pump(host, { red, back }, 6)
  back.c:sendHoldings(World.split(Trade.copy(back.save)))
  pump(host, { red, back }, 4)
  eq(standing(host.state, machoke), 1, "no clone: MACHOKE stands in one world")
  eq(standing(host.state, kadabra), 1, "nor KADABRA")
  back.busy = nil
  back.save.money = back.save.money + 1
  pump(host, { red, back }, 12)
  eq(back.save.party[1].coopUid, kadabra, "GREEN's window applied the owed trade")
  eq(table.concat(traded[back], ","), "KADABRA", "the game was told (KADABRA evolves by trade)")
  eq(table.concat(traded[red], ","), "", "RED changes nothing")
  pump(host, { red, back }, Window.HOLDINGS_EVERY + 4)
  eq(standing(host.state, machoke), 1, "still no clone")
  eq(standing(host.state, kadabra), 1, "for either")
  eq(#(host.state:player(gp).trades or {}), 0, "GREEN's world shows it: owed no more")
  eq(#(host.state:player(red.c.player).trades or {}), 0, "RED's too")
end

-- 4. the protocol -------------------------------------------------------------------
do
  check(Protocol.VERSION >= 18, "protocol 18: owed trades")
  local row = Trade.encodeTeam({ F.mon("ABRA", 10) })
  check(Protocol.sanitize({ type = "trades", list = { { id = "cable:p01-p02:1", give = row,
                                                        get = row } } }, "client"),
        "an owed trade passes")
  check(not Protocol.sanitize({ type = "trades", list = { { id = "not an id", give = row,
                                                            get = row } } }, "client"),
        "an odd commit id does not")
end

T.finish()
