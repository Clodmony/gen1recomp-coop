-- Leaving, coming back and taking over in the windows (#20, design A11),
-- ROM-free: two windows' copies over loopback
-- (tests/coop/support/battle_harness.lua).  Covered: LEAVE BATTLE takes
-- the player back to their world while their copy plays on out of sight;
-- the first present player decides for the absent owner's Pokémon; the
-- battle ends for the one who left with their Pokémon's results written
-- back and one line; REJOIN brings the copy back on screen, deciding for
-- their own Pokémon again; a dropped owner pauses the battle ("is away")
-- until TAKE OVER after 30 s; a battle nobody is present in ends as fled
-- and the copy away from the screen ends with it.
--   luajit tests/coop/battle_leave_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq
local H = require("tests.coop.support.battle_harness")
local Data = H.Data
local Pokemon = require("src.pokemon.Pokemon")
local Replica = require("src.coop.battle.Replica")
local HostBattles = require("src.coop.battle.HostBattles")
local View = require("src.coop.battle.View")
local Font = require("src.render.Font")

Data.moves.FIX_GROWL = Data.moves.FIX_GROWL or { id = "FIX_GROWL", index = 7, name = "FIX GROWL",
  type = "NORMAL", power = 0, accuracy = 100, pp = 40, effect = "ATTACK_DOWN1_EFFECT" }

local function harmless(mon) mon.moves = { { id = "FIX_GROWL", pp = 40 } } end

local function start(enemyLevel)
  local host, red, green = H.setup()
  local clients = { red, green }
  local redGame = H.newGame("RED", 1111, { Pokemon.new(Data, "FIXMON_A", 12) })
  local greenGame = H.newGame("GREEN", 2222, { Pokemon.new(Data, "FIXMON_C", 12) })
  local games = { redGame, greenGame }
  redGame.expect = 2
  H.run(host, clients, {}, function() return red.status == "joined" and green.status == "joined" end, 10)
  local battle = H.openWild(red, redGame, "FIXMON_B", enemyLevel or 30, harmless)
  local id = H.bindOpener(host, red, redGame, battle, clients, games)
  local gb = H.joinBattle(host, green, greenGame, id, clients, games)
  return host, red, green, clients, redGame, greenGame, games, battle, gb, id
end

-- 1. LEAVE BATTLE: GREEN's world again, the copy plays on, RED decides ------
do
  local host, red, green, clients, redGame, greenGame, games, battle, gb, id = start(30)
  -- RED holds the menu until GREEN is gone, then switches to GREEN's
  -- Pokemon and fights on with the first move
  local switched = false
  redGame.decide = function(b)
    if not gb.coop.away then return false end
    if not switched then switched = true; return { kind = "switch", index = 2 } end
    return nil
  end
  H.run(host, clients, games, function() return Replica.question(gb) == "menu" end, 3000)
  local ended
  gb.coop.onEnd = function(_, result) ended = result end
  Replica.leave(gb)
  greenGame.away = { gb }
  check(gb.coop.away, "GREEN left the battle (A11.1)")
  check(greenGame.stack:top() ~= gb, "and is back in their world")
  H.run(host, clients, games, function()
    local e
    for _, p in ipairs(red.battles[id].players) do if p.id == green.player then e = p end end
    return e and e.left
  end, 200)
  local greenAsked = false
  local deciderSeen
  H.run(host, clients, games, function()
    local kind, by, owner = Replica.decider(battle)
    if kind == "menu" and owner == green.player then deciderSeen = by end
    return battle.coop.done
  end, 40000)
  eq(deciderSeen, red.player, "GREEN's Pokémon out, GREEN away: RED decides for it (A11.5)")
  check(not greenAsked, "GREEN's copy never asked GREEN")
  H.run(host, clients, games, function() return gb.coop.done end, 2000)
  check(gb.coop.done, "GREEN's copy away from the screen played the battle to its end")
  eq(ended, battle.result, "with the same end (" .. tostring(battle.result) .. ")")
  eq(Replica.hash(gb), Replica.hash(battle), "and the same state")
  eq(greenGame.save.party[1].exp, gb.coop.roster[2].exp,
    "GREEN's Pokémon got what the battle gave it (A11.1)")
  eq(H.logged("battle_desync"), 0, "no desync")
end

-- 2. REJOIN: back on screen, deciding for their own Pokemon again (A11.4) ----
do
  local host, red, green, clients, redGame, greenGame, games, battle, gb, id = start(30)
  redGame.decide = function() return false end
  greenGame.decide = function() return false end
  H.run(host, clients, games, function() return Replica.question(gb) == "menu" end, 3000)
  Replica.leave(gb)
  greenGame.away = { gb }
  -- RED sends GREEN's Pokemon out while GREEN is away
  H.run(host, clients, games, function()
    local k, by = Replica.decider(battle)
    return k == "menu" and by == red.player
  end, 400)
  Replica.send(battle, { kind = "switch", index = 2 })
  H.run(host, clients, games, function()
    local k, by, owner = Replica.decider(battle)
    return k == "menu" and owner == green.player and by == red.player
  end, 3000)
  local _, by = Replica.decider(battle)
  eq(by, red.player, "GREEN's Pokémon is out and RED decides while GREEN is away")
  green:battleRejoin(id)
  gb.coop.away = false
  greenGame.away = {}
  greenGame.stack:push(gb)
  H.run(host, clients, games, function()
    local k, b2 = Replica.decider(gb)
    return k == "menu" and b2 == green.player
  end, 3000)
  local _, by2 = Replica.decider(gb)
  eq(by2, green.player, "REJOIN: GREEN decides for their own Pokémon again")
  check(Replica.mine(gb), "GREEN's window has the menu")
  eq(H.logged("battle_desync"), 0, "no desync")
end

-- 3. a dropped owner: the battle waits, "is away", TAKE OVER after 30 s (A11.5, A11.6)
do
  local host, red, green, clients, redGame, greenGame, games, battle, gb, id = start(30)
  redGame.decide = function(b)
    if b.player.mon == b.coop.roster[1] then return { kind = "switch", index = 2 } end
    return false
  end
  greenGame.decide = function() return false end
  H.run(host, clients, games, function()
    local k, by, owner = Replica.decider(battle)
    return k == "menu" and owner == green.player
  end, 4000)
  -- GREEN's link drops
  green.conn:close()
  local clients2 = { red }
  local games2 = { redGame }
  H.run(host, clients2, games2, function()
    local _, by = Replica.decider(battle)
    return by == nil
  end, 200)
  local kind, by, owner = Replica.decider(battle)
  eq(by, nil, "a dropped decider: nobody decides, the battle waits (A11.5)")
  eq(owner, green.player, "for GREEN")
  local drawn = {}
  local draw = Font.draw
  Font.draw = function(t) drawn[#drawn + 1] = t end
  View.draw(battle)
  Font.draw = draw
  check(table.concat(drawn, "|"):find("is away", 1, true), "RED's box says GREEN is away")
  H.run(host, clients2, games2, function() return host.battles[id].pausedAt ~= nil end, 200)
  H.advance(HostBattles.TAKEOVER)
  redGame.keepScreens = true -- (the question stays up to be seen)
  local asked
  H.run(host, clients2, games2, function()
    local top = redGame.stack:top()
    asked = top ~= battle and top or nil
    return asked ~= nil
  end, 200)
  check(asked ~= nil, "after 30 s RED is asked TAKE OVER? (A11.6)")
  redGame.stack:pop()
  red:battleTakeover(id, green.player)
  H.run(host, clients2, games2, function()
    local _, b2 = Replica.decider(battle)
    return b2 == red.player
  end, 200)
  local _, b3, o3 = Replica.decider(battle)
  eq(b3, red.player, "RED stands in for GREEN")
  eq(o3, green.player, "for GREEN's Pokémon")
  drawn = {}
  Font.draw = function(t) drawn[#drawn + 1] = t end
  View.draw(battle)
  Font.draw = draw
  check(table.concat(drawn, "|"):find("FOR GREEN", 1, true), "the view names both")
  check(Replica.mine(battle), "RED's window has the menu now")
end

-- 4. nobody present: the battle ends as fled, the copy away ends with it (A11.7)
do
  local host, red, green, clients, redGame, greenGame, games, battle, gb, id = start(30)
  redGame.decide = function() return false end
  greenGame.decide = function() return false end
  H.run(host, clients, games, function() return Replica.question(gb) == "menu" end, 3000)
  local ended
  gb.coop.onEnd = function(_, result) ended = result end
  Replica.leave(gb)
  greenGame.away = { gb }
  red.conn:close()
  local clients2, games2 = { green }, { greenGame }
  H.run(host, clients2, games2, function() return false end, 30)
  H.advance(HostBattles.ABANDON)
  H.run(host, clients2, games2, function() return ended ~= nil end, 300)
  eq(ended, "run", "a battle nobody is in ends as fled; GREEN's copy away ends with it")
end

T.finish()
