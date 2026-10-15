-- Direct trades (#23, design A12.6, G31), ROM-free.  The swap core
-- (src/coop/campaign/Trade.lua): a team as text and back, finding a row by
-- its uid or its fingerprint, a swap that keeps the rows' uids and is done
-- once however often it is applied, the trade evolution.  Then two
-- windows over loopback, each with the trade screen open
-- (src/coop/friends/TradeScreen.lua, drawn by upstream's link trade
-- screen): both offer and both say TRADE, the host commits once, each
-- window swaps on its own team (uids, original trainers, the Pokédex), the
-- received KADABRA-like Pokémon evolves by trade with its uid; CANCEL and
-- B return both with nothing traded; a dropped partner before the swap
-- ends it.
--   luajit tests/coop/friends_trade_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq
local H = require("tests.coop.support.battle_harness")
local Data = H.Data
local Pokemon = require("src.pokemon.Pokemon")
local Trade = require("src.coop.campaign.Trade")
local TradeScreen = require("src.coop.friends.TradeScreen")
require("src.render.Font").load(Data)
require("src.core.Logger").warn = function() end

-- FIXMON_C evolves by trade into FIXMON_B here, as KADABRA into ALAKAZAM
Data.pokemon.FIXMON_C.evolutions = { { method = "TRADE", species = "FIXMON_B" } }

local function mon(species, level, uid, ot, otId)
  local m = Pokemon.new(Data, species, level)
  m.coopUid, m.ot, m.otId = uid, ot, otId
  return m
end

-- the swap core -----------------------------------------------------------------
do
  local a = mon("FIXMON_C", 30, "p0a:1", "RED", 1111)
  local b = mon("FIXMON_A", 12, "p0a:2", "RED", 1111)
  local text = Trade.encodeTeam({ a, b })
  local rows = Trade.decodeTeam(text)
  eq(#rows, 2, "a team as text and back")
  eq(rows[1].coopUid, "p0a:1", "with its uids")
  eq(rows[1].species, "FIXMON_C", "and its rows whole")
  check(Trade.decodeTeam("return { 1 }") == nil, "a list of no Pokémon is no team")
  check(Trade.decodeTeam("os.exit()") == nil, "text that is no data is no team")
  check(Trade.decodeTeam("return {}") == nil, "an empty team is none")
  eq(Trade.find({ b, a }, rows[1]), 2, "a row is found by its uid")
  local fresh = mon("FIXMON_A", 7, nil, "RED", 1111)
  local twin = Trade.copy(fresh)
  eq(Trade.find({ a, fresh }, twin), 2, "a row without a uid by its fingerprint")
  local save = { party = { Trade.copy(a), Trade.copy(b) }, boxes = { {} } }
  local get = mon("FIXMON_B", 20, "p0b:7", "GREEN", 2222)
  local how, _, slot = Trade.swap(save, a, get)
  eq(how, "swapped", "the swap")
  eq(slot, 1, "into the slot of the Pokémon given")
  eq(save.party[1].coopUid, "p0b:7", "the received row keeps its uid")
  eq(save.party[1].ot, "GREEN", "and its original trainer")
  check(save.party[1] ~= get, "as a copy")
  eq(save.party[2].coopUid, "p0a:2", "the rest of the team stays")
  eq(Trade.swap(save, a, get), "already", "applied again: already in, nothing doubled")
  eq(#save.party, 2, "still two")
  eq(select(2, Trade.swap({ party = {} }, a, get)), "gone", "neither row: nothing done")
  eq(Trade.evolution(Data, a), "FIXMON_B", "a trade evolution")
  eq(Trade.evolution(Data, b), nil, "none for the others")
end

-- two windows --------------------------------------------------------------------
local function game(name, otId, party)
  local g = H.newGame(name, otId, party)
  g.input = {
    wasPressed = function(_, k)
      if g.taps[k] then return true end
      -- the text after the trade: A every other frame
      local top = g.stack:top()
      return k == "a" and top and not top.coopTrade and g.mash and g.mashTick % 2 == 0
    end,
    isDown = function() return false end,
    wasReleased = function() return false end,
  }
  g.mashTick = 0
  g.save.pokedex = { seen = {}, owned = {} }
  return g
end

local function frame(host, clients, games)
  H.advance(1 / 60)
  for _, c in ipairs(clients) do c:update() end
  host:update()
  for _, c in ipairs(clients) do c:update() end
  for _, g in ipairs(games) do
    g.mashTick = g.mashTick + 1
    local top = g.stack:top()
    if top and top.update then top:update(1 / 60) end
    g.taps = {}
  end
end

local function run(host, clients, games, fn, limit)
  for i = 1, limit or 2000 do
    if fn() then return i end
    frame(host, clients, games)
  end
  return nil
end

local function press(host, clients, games, g, key)
  g.taps[key] = true
  run(host, clients, games, function() return false end, 4)
end

local function setup()
  local host, red, green = H.setup()
  local clients = { red, green }
  local redGame = game("RED", 1111, { mon("FIXMON_C", 30, nil, "RED", 1111),
                                      mon("FIXMON_A", 12, nil, "RED", 1111) })
  local greenGame = game("GREEN", 2222, { mon("FIXMON_A", 8, nil, "GREEN", 2222) })
  local games = { redGame, greenGame }
  run(host, clients, {}, function() return red.status == "joined" and green.status == "joined" end, 10)
  -- the uids the host gives (#17)
  redGame.save.party[1].coopUid = red.player .. ":1"
  redGame.save.party[2].coopUid = red.player .. ":2"
  greenGame.save.party[1].coopUid = green.player .. ":1"
  red:sendOpening(true)
  green:sendOpening(true)
  run(host, clients, {}, function() return false end, 3)
  return host, red, green, clients, redGame, greenGame, games
end

local function meet(host, red, green, clients, games, redGame, greenGame)
  red:invite(green.player, "trade")
  local id
  run(host, clients, games, function()
    for k, inv in pairs(green.invites) do if not inv.answer then id = k end end
    return id ~= nil
  end, 20)
  green:answerInvite(id, true)
  local pid
  run(host, clients, games, function()
    for k, p in pairs(red.pairs) do if not p.ended and green.pairs[k] then pid = k end end
    return pid ~= nil
  end, 20)
  local ends = {}
  local function opts(g, c) return { client = function() return c end,
                                     onEnd = function(r) ends[g] = r or "none" end } end
  local rs = TradeScreen.open(redGame, red.pairs[pid], opts(redGame, red))
  local gs = TradeScreen.open(greenGame, green.pairs[pid], opts(greenGame, green))
  rs.coopTrade, gs.coopTrade = true, true
  run(host, clients, games, function()
    return rs.trade.stage == "picking" and gs.trade.stage == "picking"
  end, 60)
  return pid, ends, rs, gs
end

-- the trade, done once
do
  local host, red, green, clients, redGame, greenGame, games = setup()
  local pid, ends, rs, gs = meet(host, red, green, clients, games, redGame, greenGame)
  eq(rs.trade.stage, "picking", "RED's screen lists both teams")
  eq(#rs.theirs, 1, "GREEN's one Pokémon")
  eq(#gs.theirs, 2, "GREEN sees RED's two")
  -- RED: A on the first row, TRADE (right), A
  press(host, clients, games, redGame, "a")
  eq(rs.pickChoice, 1, "A opens STATS / TRADE")
  press(host, clients, games, redGame, "right")
  press(host, clients, games, redGame, "a")
  eq(red.pairs[pid].myPick, 1, "RED offers its first Pokémon")
  eq(rs.trade.stage, "waitPick", "and waits for GREEN's")
  press(host, clients, games, greenGame, "a")
  press(host, clients, games, greenGame, "right")
  press(host, clients, games, greenGame, "a")
  eq(rs.trade.stage, "confirming", "both offered")
  press(host, clients, games, redGame, "a")
  eq(red.pairs[pid].confirmed, true, "RED said TRADE")
  eq(redGame.save.party[1].species, "FIXMON_C", "nothing moves before both")
  redGame.mash, greenGame.mash = true, true
  press(host, clients, games, greenGame, "a")
  local done = run(host, clients, games, function() return ends[redGame] and ends[greenGame] end, 20000)
  check(done ~= nil, "both screens are done")
  eq(ends[redGame], "done", "RED traded")
  check(host.state:applied("trade:" .. pid), "the host committed the trade once")
  local got = redGame.save.party[1]
  eq(got.coopUid, green.player .. ":1", "RED holds GREEN's Pokémon with its uid")
  eq(got.ot, "GREEN", "its original trainer kept")
  eq(got.species, "FIXMON_A", "in the slot RED gave")
  eq(redGame.save.party[2].coopUid, red.player .. ":2", "RED's other Pokémon stays")
  check(redGame.save.pokedex.owned.FIXMON_A, "RED's Pokédex owns it")
  local gotG = greenGame.save.party[1]
  eq(gotG.coopUid, red.player .. ":1", "GREEN holds RED's Pokémon with its uid")
  eq(gotG.species, "FIXMON_B", "which evolved by trade")
  eq(gotG.ot, "RED", "its original trainer kept")
  check(greenGame.save.pokedex.owned.FIXMON_B, "GREEN's Pokédex owns the evolution")
  eq(#greenGame.save.party, 1, "GREEN still has one Pokémon")
  run(host, clients, games, function() return host.friends.pairs[pid] == nil end, 60)
  eq(host.friends.pairs[pid], nil, "both sides done: the pairing is over")
  -- the host's copy of the worlds: owed until each window shows it
  check(host.friends.owed[red.player] ~= nil, "RED owes the host a world with the swap")
end

-- CANCEL, B and a drop -------------------------------------------------------------
do
  local host, red, green, clients, redGame, greenGame, games = setup()
  local pid, ends, rs = meet(host, red, green, clients, games, redGame, greenGame)
  press(host, clients, games, redGame, "down")
  press(host, clients, games, redGame, "down")
  eq(rs.side, "cancel", "down past the party: CANCEL")
  press(host, clients, games, redGame, "a")
  run(host, clients, games, function() return ends[redGame] and ends[greenGame] end, 30)
  eq(ends[redGame], "cancel", "CANCEL closes RED's screen")
  eq(ends[greenGame], "cancel", "and GREEN's")
  eq(redGame.save.party[1].coopUid, red.player .. ":1", "nothing traded")
  check(not host.state:applied("trade:" .. pid), "nothing committed")

  pid, ends, rs = meet(host, red, green, clients, games, redGame, greenGame)
  press(host, clients, games, redGame, "a")
  press(host, clients, games, redGame, "right")
  press(host, clients, games, redGame, "a")
  press(host, clients, games, greenGame, "a")
  press(host, clients, games, greenGame, "right")
  press(host, clients, games, greenGame, "a")
  press(host, clients, games, greenGame, "b")
  run(host, clients, games, function() return ends[redGame] and ends[greenGame] end, 30)
  eq(ends[greenGame], "cancel", "B before TRADE returns GREEN")
  eq(ends[redGame], "cancel", "and RED")
  eq(greenGame.save.party[1].coopUid, green.player .. ":1", "nothing traded")

  pid, ends, rs = meet(host, red, green, clients, games, redGame, greenGame)
  green.conn:close()
  run(host, { red }, { redGame }, function() return ends[redGame] end, 30)
  eq(ends[redGame], "cancel", "a partner's drop before the swap ends it")
end

T.finish()
