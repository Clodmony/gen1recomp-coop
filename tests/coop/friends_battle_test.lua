-- Friend battles in the windows (#23, design A12.3 to A12.5, G31),
-- ROM-free: the host in-process, RED and GREEN over loopback, each with a
-- game of their own (fixture data, a stack, an input that presses A every
-- other frame).  Each window runs upstream's lockstep link battle from its
-- own side over the co-op session (src/coop/friends/Relay.lua).  Covered:
-- the mirrored view (each player's own team as allies) and one outcome in
-- both windows with no desync; the real teams untouched by the fight, then
-- healed, no money; the full trainer EXP and stat EXP for every distinct
-- foe each Pokémon stood against, won or lost; RUN forfeits, and the side
-- that forfeits gets no EXP (#67); a partner
-- whose link dropped is waited for and the battle goes on once they are
-- back; two minutes away release it, as a draw, and the team still heals;
-- B on the waiting box calls it off for both.
--   luajit tests/coop/friends_battle_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq
local H = require("tests.coop.support.battle_harness")
local Data = H.Data
local Pokemon = require("src.pokemon.Pokemon")
local Client = require("src.coop.session.Client")
local FriendBattle = require("src.coop.friends.FriendBattle")
local HostFriends = require("src.coop.friends.HostFriends")
require("src.render.Font").load(Data)
require("src.core.Logger").warn = function() end

-- a game whose player presses A every other frame, and DOWN once on a
-- forced replacement's party list (its first row has fainted)
local function game(name, otId, party)
  local g = H.newGame(name, otId, party)
  local tick = 0
  g.input = {
    wasPressed = function(_, k)
      if g.taps[k] then return true end
      if g.hold then return false end
      local top = g.stack:top()
      if top and top.forceSwitch and k == "down" and not top.coopDowned then
        top.coopDowned = true
        return true
      end
      return k == "a" and tick % 2 == 0
    end,
    isDown = function() return false end,
    wasReleased = function() return false end,
  }
  g.tick = function() tick = tick + 1 end
  return g
end

local function frame(host, clients, games)
  H.advance(1 / 60)
  for _, c in ipairs(clients) do c:update() end
  host:update()
  for _, c in ipairs(clients) do c:update() end
  for _, g in ipairs(games) do
    g.tick()
    local top = g.stack:top()
    if top and top.update then top:update(1 / 60) end
    g.taps = {}
  end
end

local function run(host, clients, games, fn, limit)
  for i = 1, limit or 20000 do
    if fn() then return i end
    frame(host, clients, games)
  end
  return nil
end

-- RED and GREEN paired for a battle; each window starts its side
local function meet(host, red, green, clients, games, redGame, greenGame)
  red:invite(green.player, "battle")
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
  local function opts(g, who)
    return { client = function() return who.c end,
             onEnd = function(result, awards) ends[g] = { result = result, awards = awards } end }
  end
  local rw = { c = red }
  local gw = { c = green }
  local rb = FriendBattle.start(redGame, red.pairs[pid], opts(redGame, rw))
  local gb = FriendBattle.start(greenGame, green.pairs[pid], opts(greenGame, gw))
  return pid, ends, rb, gb, rw, gw
end

local function setup(redParty, greenParty)
  local host, red, green = H.setup()
  local clients = { red, green }
  local redGame = game("RED", 1111, redParty)
  local greenGame = game("GREEN", 2222, greenParty)
  local games = { redGame, greenGame }
  run(host, clients, {}, function() return red.status == "joined" and green.status == "joined" end, 10)
  red:sendOpening(true)
  green:sendOpening(true)
  run(host, clients, {}, function() return false end, 3)
  return host, red, green, clients, redGame, greenGame, games
end

local function battleOf(g)
  local top = g.stack:top()
  return top and top.friend and top or nil
end

-- 1. a battle to the end ---------------------------------------------------------
do
  local host, red, green, clients, redGame, greenGame, games =
    setup({ Pokemon.new(Data, "FIXMON_A", 20) },
          { Pokemon.new(Data, "FIXMON_C", 5), Pokemon.new(Data, "FIXMON_B", 6) })
  local redMon, g1, g2 = redGame.save.party[1], greenGame.save.party[1], greenGame.save.party[2]
  redMon.hp = redMon.hp - 3 -- hurt before the battle
  local redHp, redExp0, g1Exp0, g2Exp0 = redMon.hp, redMon.exp, g1.exp, g2.exp
  local redStat0 = redMon.statExp.attack
  local pid, ends = meet(host, red, green, clients, games, redGame, greenGame)
  check(pid ~= nil, "paired")
  local rb, gb
  run(host, clients, games, function()
    rb, gb = rb or battleOf(redGame), gb or battleOf(greenGame)
    return rb and gb
  end, 400)
  check(rb ~= nil and gb ~= nil, "both windows run the battle")
  eq(rb.kind, "link", "upstream's link battle")
  eq(rb.player.mon.species, "FIXMON_A", "RED sees its own Pokémon as its side")
  eq(rb.enemy.mon.species, "FIXMON_C", "and GREEN's as the foe")
  eq(gb.player.mon.species, "FIXMON_C", "GREEN sees its own as its side (mirrored)")
  eq(gb.enemy.mon.species, "FIXMON_A", "and RED's as the foe")
  check(rb.player.mon ~= redMon, "the battle fights a copy, not RED's Pokémon")
  local done = run(host, clients, games, function() return ends[redGame] and ends[greenGame] end, 60000)
  check(done ~= nil, "the battle ends in both windows")
  eq(ends[redGame].result, "win", "RED won")
  eq(ends[greenGame].result, "lose", "GREEN lost")
  local mismatch = false
  for turn, h in pairs(rb.localHashes) do
    if gb.localHashes[turn] and gb.localHashes[turn] ~= h then mismatch = true end
  end
  check(not mismatch, "both windows agree at every turn")
  eq(redMon.hp, redHp, "RED's real Pokémon took no damage")
  eq(redGame.save.money, 1000, "no money")

  -- A12.5: EXP for every distinct foe each Pokémon stood against, healed
  local ra, ga = ends[redGame].awards, ends[greenGame].awards
  eq(#ra, 2, "RED's Pokémon stood against both of GREEN's")
  eq(ra[1].species .. "/" .. ra[2].species, "FIXMON_C/FIXMON_B", "in GREEN's order")
  eq(#ga, 2, "each of GREEN's stood against RED's")
  eq(ga[1].index .. "/" .. ga[2].index, "1/2", "GREEN's two Pokémon, each once")
  FriendBattle.heal(redGame)
  eq(redMon.hp, redMon.stats.hp, "healed after the battle")
  local Experience = require("src.battle.Experience")
  local want = Experience.gainFor(Data.pokemon.FIXMON_C, 5, true, 1, false)
             + Experience.gainFor(Data.pokemon.FIXMON_B, 6, true, 1, false)
  local finished = false
  FriendBattle.giveExp(redGame, ra, function() finished = true end)
  run(host, clients, games, function() return finished end, 3000)
  check(finished, "the EXP texts close")
  eq(redMon.exp - redExp0, want, "RED's Pokémon has the full trainer EXP of both foes, unsplit")
  eq(redMon.statExp.attack - redStat0,
     Data.pokemon.FIXMON_C.baseStats.attack + Data.pokemon.FIXMON_B.baseStats.attack,
     "and their stat EXP")
  finished = false
  FriendBattle.heal(greenGame)
  FriendBattle.giveExp(greenGame, ga, function() finished = true end)
  run(host, clients, games, function() return finished end, 3000)
  check(g1.exp > g1Exp0 and g2.exp > g2Exp0, "GREEN lost and still gets EXP for each Pokémon")
  eq(g1.exp - g1Exp0, Experience.gainFor(Data.pokemon.FIXMON_A, 20, true, 1, false),
     "the full award of RED's Pokémon")
  eq(g1.hp, g1.stats.hp, "GREEN's team healed too")

  red:pairEnd(pid, ends[redGame].result)
  green:pairEnd(pid, ends[greenGame].result)
  run(host, clients, games, function() return host.friends.pairs[pid] == nil end, 20)
  eq(host.friends.pairs[pid], nil, "the pairing is over")
  eq(H.logged("battle_desync"), 0, "no co-op battle record was involved")
end

-- 2. RUN forfeits ---------------------------------------------------------------
do
  local host, red, green, clients, redGame, greenGame, games =
    setup({ Pokemon.new(Data, "FIXMON_A", 20) }, { Pokemon.new(Data, "FIXMON_C", 30) })
  local pid, ends = meet(host, red, green, clients, games, redGame, greenGame)
  local rb
  run(host, clients, games, function()
    rb = battleOf(redGame)
    return rb and rb.phase == "menu"
  end, 3000)
  check(rb and rb.phase == "menu", "RED is at the battle menu")
  rb:tryRun()
  local done = run(host, clients, games, function() return ends[redGame] and ends[greenGame] end, 20000)
  check(done ~= nil, "RUN ends it for both")
  eq(ends[redGame].result, "forfeit", "RED forfeited")
  eq(ends[greenGame].result, "win", "GREEN won")
  -- #67 (owner, 2026-10-16): the side that forfeits gets no EXP, so starting
  -- and forfeiting friend battles farms nothing; the other side keeps A12.5's
  check(ends[redGame].awards ~= nil, "RED's battle began: the team still heals")
  eq(#ends[redGame].awards, 0, "RED forfeited: no EXP")
  eq(#ends[greenGame].awards, 1, "GREEN's Pokémon stood against RED's: its EXP")
end

-- 3. a partner away: waited for, then back; and released --------------------------
do
  local host, red, green, clients, redGame, greenGame, games =
    setup({ Pokemon.new(Data, "FIXMON_A", 20) }, { Pokemon.new(Data, "FIXMON_C", 30) })
  local pid, ends, _, _, rw, gw = meet(host, red, green, clients, games, redGame, greenGame)
  local rb, gb
  run(host, clients, games, function()
    rb, gb = battleOf(redGame), battleOf(greenGame)
    return rb and gb and rb.turnCount and rb.turnCount >= 1
  end, 6000)
  check(rb and rb.turnCount >= 1, "a turn was fought")
  -- GREEN's link drops: GREEN's window runs on and sends nothing
  green.conn:close()
  gw.c = nil
  clients = { red }
  run(host, clients, games, function() return false end, 600)
  check(ends[redGame] == nil, "RED's battle waits for GREEN")
  eq(red.pairs[pid].away, true, "RED's pairing says GREEN is away")
  -- GREEN back within two minutes on a new link
  local back = Client.new(green.conn.hub and green.conn.hub:dial() or host.hubs[1]:dial(),
                          { name = "GREEN", game = "red", sha1 = ("ab"):rep(20), device = "d2",
                            known = green.known })
  back:join()
  clients = { red, back }
  run(host, clients, games, function() return back.status == "joined" end, 20)
  back:sendOpening(true)
  gw.c = back
  local done = run(host, clients, games, function() return ends[redGame] and ends[greenGame] end, 60000)
  check(done ~= nil, "after the drop the battle goes on to its end")
  check(ends[redGame].result ~= "draw", "decided, not released")
  eq(ends[redGame].result == "win" and ends[greenGame].result or ends[redGame].result,
     ends[redGame].result == "win" and "lose" or ends[redGame].result,
     "one outcome in both windows")
  red:pairEnd(pid, ends[redGame].result)
  back:pairEnd(pid, ends[greenGame].result)
  run(host, clients, games, function() return false end, 3)

  -- again, and GREEN stays away
  green = back
  pid, ends, _, _, rw, gw = meet(host, red, green, clients, games, redGame, greenGame)
  run(host, clients, games, function()
    rb = battleOf(redGame)
    return rb and rb.turnCount and rb.turnCount >= 1
  end, 6000)
  green.conn:close()
  gw.c = nil
  clients = { red }
  H.advance(HostFriends.GRACE + 1)
  done = run(host, clients, { redGame }, function() return ends[redGame] end, 6000)
  check(done ~= nil, "two minutes away: RED's battle is released")
  eq(ends[redGame].result, "draw", "as a draw")
  check(#ends[redGame].awards >= 1, "the Pokémon that fought still get their EXP")
end

-- 4. B on the waiting box calls it off -------------------------------------------
do
  local host, red, green, clients, redGame, greenGame, games =
    setup({ Pokemon.new(Data, "FIXMON_A", 20) }, { Pokemon.new(Data, "FIXMON_C", 30) })
  greenGame.hold = true -- GREEN's window has not opened its side yet
  local pid, ends = meet(host, red, green, clients, { redGame }, redGame, greenGame)
  greenGame.stack:pop() -- (and never will)
  redGame.taps.b = true
  run(host, clients, { redGame }, function() return ends[redGame] end, 10)
  eq(ends[redGame] and ends[redGame].result, "cancel", "B calls it off")
  eq(ends[redGame].awards, nil, "no battle, no EXP")
  red:pairEnd(pid, "cancel")
  run(host, clients, { redGame }, function() return green.pairs[pid].ended end, 20)
  eq(green.pairs[pid].ended, "left", "GREEN hears it is off")
end

T.finish()
