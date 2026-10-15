-- Co-op battles in the windows (#18, design A8, G24), ROM-free: the host
-- in-process, two players over loopback, each with a game of their own
-- (fixture data, a stack, an input that presses A every frame, so the
-- player whose Pokémon is out always fights with its first move).  The
-- battle is lockstep: every window runs the game's own battle from the
-- host's record.  Covered: the opener's battle becomes the co-op battle;
-- a partner joins mid-battle and catches up without a screen; both copies
-- report the same state at every revision (no desync); the decider is the
-- owner of the Pokémon that is out; the partner's menu does nothing;
-- experience goes to each player's own Pokémon; the prize to both; a
-- loss whites out both; a forced replacement is the fainted Pokémon's
-- owner's; locked-in turns take no command.
--   luajit tests/coop/battle_replica_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq
local H = require("tests.coop.support.battle_harness")
local Data = H.Data
local Pokemon = require("src.pokemon.Pokemon")
local BattleState = require("src.battle.BattleState")
local Replica = require("src.coop.battle.Replica")
local newGame, setup, logged, frame, run = H.newGame, H.setup, H.logged, H.frame, H.run
local openWild, bindOpener, joinBattle = H.openWild, H.bindOpener, H.joinBattle

-- 1. a wild battle, a partner joins, the battle is won ------------------------
do
  local host, red, green = setup()
  local clients = { red, green }
  local redGame = newGame("RED", 1111, { Pokemon.new(Data, "FIXMON_A", 12) })
  local greenGame = newGame("GREEN", 2222, { Pokemon.new(Data, "FIXMON_C", 12) })
  local games = { redGame, greenGame }
  redGame.expect = 2
  local greenExp0 = greenGame.save.party[1].exp
  run(host, clients, {}, function() return red.status == "joined" and green.status == "joined" end, 10)

  local battle = openWild(red, redGame, "FIXMON_B", 6)
  local id = bindOpener(host, red, redGame, battle, clients, games)
  check(battle.coop ~= nil, "the opener's battle is a co-op battle")
  eq(#battle.coop.roster, 1, "the roster holds the opener's team")
  check(battle.player.mon ~= redGame.save.party[1], "the battle fights a copy, not the world's Pokémon")
  eq(battle.player.mon.species, "FIXMON_A", "of the opener's lead")
  local hp0 = battle.enemy.mon.hp

  -- red's copy plays the intro and asks red for a move; green joins then
  local gb = joinBattle(host, green, greenGame, id, clients, games)
  check(gb.coop.entered, "the joiner's copy caught up without a screen")
  eq(#gb.coop.roster, 2, "the joiner's copy holds both teams")
  eq(Replica.hash(gb), Replica.hash(battle), "and stands where the opener's stands")
  eq(Replica.owner(gb, gb.player.mon), red.player, "the opener's Pokémon is out: red decides")
  local kind, by = Replica.question(gb)
  eq(kind, "menu", "the joiner's copy is at the menu")
  eq(by, red.player, "asked of red")

  local done = run(host, clients, games, function()
    return battle.coop.done and gb.coop.done
  end, 30000)
  check(done ~= nil, "the battle ends in both windows")
  for _ = 1, 3 do frame(host, clients, games) end
  eq(battle.result, gb.result, "with the same result")
  eq(battle.result, "win", "a win")
  check(hp0 > 0, "the foe had HP")
  eq(logged("battle_desync"), 0, "both copies reported the same state at every revision")
  check(logged("battle_ask") >= 2, "the host took the windows' questions")
  eq(host.battles[id], nil, "the host dropped the finished battle")
  local redMon, greenMon = redGame.save.party[1], greenGame.save.party[1]
  check(redMon.exp > 0 and redMon.exp == battle.coop.roster[1].exp,
    "red's own Pokémon got its experience (A8.14)")
  eq(greenMon.exp, gb.coop.roster[2].exp, "green's own Pokémon has what the battle gave it")
  eq(greenMon.exp, greenExp0, "a Pokémon that never fought gets nothing without EXP.ALL (A8.14)")
  eq(redGame.save.party[1].hp, battle.coop.roster[1].hp, "red's Pokémon's HP came back")
  eq(#redGame.save.party, 1, "nothing was added to red's party")
  eq(#greenGame.save.party, 1, "nor to green's")
end

-- 2. a trainer: both get the full prize; EXP.ALL in green's bag counts for
-- both teams, each split over its own Pokémon; a partner's own Pokémon is
-- not a traded one (A8.15, A8.16, A7.10) ----------------------------------
do
  local host, red, green = setup()
  local clients = { red, green }
  local redGame = newGame("RED", 1111, { Pokemon.new(Data, "FIXMON_A", 14), Pokemon.new(Data, "FIXMON_B", 9) })
  local greenGame = newGame("GREEN", 2222, { Pokemon.new(Data, "FIXMON_C", 12), Pokemon.new(Data, "FIXMON_A", 8) })
  local games = { redGame, greenGame }
  redGame.expect = 2
  run(host, clients, {}, function() return red.status == "joined" and green.status == "joined" end, 10)
  local before = {}
  for _, g in ipairs(games) do for _, m in ipairs(g.save.party) do before[m] = m.exp end end

  local battle = BattleState.newTrainer(redGame, "OPP_FIX_YOUNGSTER", 1)
  local enemy = {}
  for i, m in ipairs(battle.enemyParty) do enemy[i] = Replica.pack(m) end
  red:battleOpen({ kind = "trainer", enemy = enemy, map = "FIX_TOWN", foe = "FIX YOUNGSTER",
                   trainer = { class = "OPP_FIX_YOUNGSTER", index = 1, rival = "BLUE" } },
                 Replica.packTeam(redGame.save.party), 1111, false)
  local id = bindOpener(host, red, redGame, battle, clients, games)
  green:battleJoin(id, Replica.packTeam(greenGame.save.party), 2222, true)
  local rec
  run(host, clients, games, function()
    rec = green.battles[id]
    return rec and #rec.inputs >= 2
  end, 4000)
  local live = { greenGame.save.party[1], greenGame.save.party[2] }
  local gb = Replica.build(greenGame, rec, { client = green, id = id, me = green.player,
                                              real = greenGame, live = live })
  Replica.catchUp(gb, rec)
  greenGame.stack:push(gb)
  eq(gb.kind, "trainer", "the joiner's copy is the trainer battle")
  eq(#gb.enemyParty, 2, "with the trainer's party")
  local done = run(host, clients, games, function() return battle.coop.done and gb.coop.done end, 40000)
  check(done ~= nil, "the trainer battle ends in both windows")
  for _ = 1, 3 do frame(host, clients, games) end
  eq(battle.result, "win", "won")
  eq(gb.result, "win", "in both")
  eq(logged("battle_desync"), 0, "no desync")
  local prize = 15 * 5
  eq(redGame.save.money, 1000 + prize, "the opener got the full prize (A8.16)")
  eq(greenGame.save.money, 1000 + prize, "and the partner too")
  for _, g in ipairs(games) do
    for _, m in ipairs(g.save.party) do
      check(m.exp > before[m], g.save.player.name .. "'s " .. m.species
        .. " gained with EXP.ALL, fought or not (A8.15)")
    end
  end
  eq(greenGame.save.party[1].exp - before[greenGame.save.party[1]],
     gb.coop.roster[3].exp - before[greenGame.save.party[1]], "written back as the battle gave it")
end

-- 3. a loss whites out every participant: both see "lose" (A8.17) ----------
do
  local host, red, green = setup()
  local clients = { red, green }
  local redGame = newGame("RED", 1111, { Pokemon.new(Data, "FIXMON_A", 5) })
  local greenGame = newGame("GREEN", 2222, { Pokemon.new(Data, "FIXMON_C", 5) })
  local games = { redGame, greenGame }
  redGame.expect = 2
  run(host, clients, {}, function() return red.status == "joined" and green.status == "joined" end, 10)
  local battle = openWild(red, redGame, "FIXMON_B", 40)
  local ended = {}
  battle.onFinish = function(result) ended.red = result end
  local id = bindOpener(host, red, redGame, battle, clients, games)
  local gb = joinBattle(host, green, greenGame, id, clients, games)
  gb.coop.onEnd = function(_, result) ended.green = result end
  run(host, clients, games, function() return ended.red and ended.green end, 40000)
  eq(ended.red, "lose", "the opener's world hears the loss")
  eq(ended.green, "lose", "and the partner's window: both white out in their own world")
  eq(redGame.save.party[1].hp, 0, "red's Pokémon fell")
  eq(greenGame.save.party[1].hp, 0, "green's too")
  eq(logged("battle_desync"), 0, "no desync")
end

-- 4. switching to the partner's Pokémon hands them control (A8.6); a catch
-- goes to the thrower once (A7.6) ---------------------------------------------
do
  local host, red, green = setup()
  local clients = { red, green }
  local redGame = newGame("RED", 1111, { Pokemon.new(Data, "FIXMON_A", 10) })
  local greenGame = newGame("GREEN", 2222, { Pokemon.new(Data, "FIXMON_C", 10) })
  greenGame.save.inventory.FIX_BALL = 50
  local games = { redGame, greenGame }
  redGame.expect = 2
  run(host, clients, {}, function() return red.status == "joined" and green.status == "joined" end, 10)
  local battle = openWild(red, redGame, "FIXMON_B", 3)
  local id = bindOpener(host, red, redGame, battle, clients, games)
  local gb = joinBattle(host, green, greenGame, id, clients, games)
  local switched = false
  redGame.decide = function(b)
    if switched then return nil end
    switched = true
    return { kind = "switch", index = 2 }
  end
  local greenAsked = false
  greenGame.decide = function(b)
    greenAsked = true
    return { kind = "ball", item = "FIX_BALL" }
  end
  local done = run(host, clients, games, function() return battle.coop.done and gb.coop.done end, 60000)
  check(done ~= nil, "the battle ends")
  check(greenAsked, "after the switch the menu is asked of green, whose Pokémon is out (A8.6)")
  eq(gb.result, "caught", "green's ball caught it")
  eq(battle.result, "caught", "in both copies")
  eq(#greenGame.save.party, 2, "the catch is in the thrower's party")
  eq(greenGame.save.party[2].species, "FIXMON_B", "the foe")
  eq(greenGame.save.party[2].otId, 2222, "with the thrower as its trainer")
  eq(#redGame.save.party, 1, "and not in the partner's (never duplicated)")
  eq(logged("battle_desync"), 0, "no desync")
end

-- 5. a locked-in turn takes no command (A8.10): after a recharge move the
-- next turn runs by itself in every copy; an item comes from the acting
-- player's bag and works the same in every copy (A8.13) ---------------------------
do
  Data.moves.FIX_BEAM = { id = "FIX_BEAM", index = 5, name = "FIX BEAM", type = "NORMAL",
                          power = 20, accuracy = 100, pp = 5, effect = "HYPER_BEAM_EFFECT" }
  Data.items.POTION = { id = "POTION", index = 6, name = "POTION", price = 300 }
  Data.moves.FIX_GROWL = { id = "FIX_GROWL", index = 7, name = "FIX GROWL", type = "NORMAL",
                           power = 0, accuracy = 100, pp = 40, effect = "ATTACK_DOWN1_EFFECT" }
  local host, red, green = setup()
  local clients = { red, green }
  local beamer = Pokemon.new(Data, "FIXMON_A", 20)
  beamer.moves = { { id = "FIX_BEAM", pp = 5 } }
  local redGame = newGame("RED", 1111, { beamer })
  local greenGame = newGame("GREEN", 2222, { Pokemon.new(Data, "FIXMON_C", 12) })
  greenGame.save.inventory.POTION = 3
  local games = { redGame, greenGame }
  redGame.expect = 2
  run(host, clients, {}, function() return red.status == "joined" and green.status == "joined" end, 10)
  local battle = openWild(red, redGame, "FIXMON_B", 12, function(mon)
    mon.moves = { { id = "FIX_GROWL", pp = 40 } } -- the foe never hurts anyone
  end)
  local id = bindOpener(host, red, redGame, battle, clients, games)
  -- red fires the beam once; green stays out of it
  local sent = 0
  redGame.decide = function(b)
    if sent > 0 then return false end
    sent = sent + 1
    return { kind = "move", slot = 1 }
  end
  greenGame.decide = function() return false end
  local gb = joinBattle(host, green, greenGame, id, clients, games)
  run(host, clients, games, function()
    local b = host.battles[id]
    return b and #b.inputs >= 3 and b.ask and b.ask.rev == #b.inputs and b.ask.kind == "menu"
  end, 6000)
  local hb = host.battles[id]
  eq(#hb.inputs, 3, "the beam was one command, the recharge turn none (A8.10)")
  check(battle.turnCount >= 2, "and two turns went by (" .. tostring(battle.turnCount) .. ")")
  eq(battle.turnCount, gb.turnCount, "in both copies")
  eq(logged("battle_desync"), 0, "no desync")
  -- red hands over to green's Pokemon? no: red uses green's... green has
  -- the POTION: green cannot act while red decides, so red switches to
  -- green's Pokemon first
  local maxHp = battle.coop.roster[1].stats.hp
  battle.coop.roster[1].hp, gb.coop.roster[1].hp = 3, 3 -- (hurt alike in both copies)
  Replica.send(battle, { kind = "switch", index = 2 })
  run(host, clients, games, function()
    local b = host.battles[id]
    return b and b.ask and b.ask.rev == #b.inputs and b.ask.kind == "menu" and b.ask.by == green.player
  end, 6000)
  eq(host.battles[id].ask.by, green.player, "green decides now")
  -- green's bag: the facade works on scratch copies; the choice goes out
  local hp1 = gb.coop.roster[1].hp
  greenGame.save.inventory.POTION = greenGame.save.inventory.POTION - 1 -- the bag spends it
  Replica.send(gb, { kind = "item", item = "POTION", index = 1 })
  run(host, clients, games, function()
    local b = host.battles[id]
    return b and #b.inputs >= 5 and b.ask and b.ask.rev == #b.inputs
  end, 6000)
  eq(gb.coop.roster[1].hp, math.min(maxHp, hp1 + 20), "the POTION healed red's Pokémon in green's copy")
  eq(battle.coop.roster[1].hp, gb.coop.roster[1].hp, "and in red's")
  eq(greenGame.save.inventory.POTION, 2, "one POTION left green's bag")
  eq(redGame.save.inventory.POTION, nil, "red's bag is untouched")
  eq(logged("battle_desync"), 0, "no desync")
end

-- 6. the bag in battle works on scratch copies: what the player picks goes
-- to the host, nothing changes before the input comes back -----------------------
do
  local host, red, green = setup()
  local clients = { red, green }
  local redGame = newGame("RED", 1111, { Pokemon.new(Data, "FIXMON_A", 10) })
  local games = { redGame }
  redGame.expect = 99 -- nobody decides here
  run(host, clients, {}, function() return red.status == "joined" end, 10)
  local battle = openWild(red, redGame, "FIXMON_B", 3)
  bindOpener(host, red, redGame, battle, clients, games)
  run(host, clients, games, function()
    local k, by = Replica.question(battle)
    return k == "menu" and by == red.player
  end, 3000)
  battle.coop.roster[1].hp = 5
  local facade = Replica.facade(battle)
  check(facade ~= nil and facade ~= battle, "the bag works on a facade of the battle")
  local target = facade.playerParty[1]
  check(target ~= battle.coop.roster[1], "over scratch copies of the roster")
  target.hp = 25 -- what ItemEffects would do to the copy
  facade:itemUsed({ "healed" }, { item = "POTION", target = target })
  eq(battle.coop.sent and battle.coop.sent.cmd.kind, "item", "the choice went to the host")
  eq(battle.coop.sent.cmd.index, 1, "naming the roster row")
  eq(battle.coop.roster[1].hp, 5, "the battle is untouched until the input comes back")
end

-- 7. a move to learn is asked of the Pokemon's owner; their answer is an
-- input every copy applies (A8.6) -------------------------------------------------
do
  local host, red, green = setup()
  local clients = { red, green }
  local learner = Pokemon.new(Data, "FIXMON_A", 6)
  learner.moves = { { id = "FIX_TACKLE", pp = 35 }, { id = "FIX_SCRATCH", pp = 35 },
                    { id = "FIX_CUT", pp = 30 }, { id = "FIX_GROWL", pp = 40 } }
  learner.exp = require("src.pokemon.Growth").expForLevel("MEDIUM_SLOW", 7) - 5
  local redGame = newGame("RED", 1111, { learner })
  local greenGame = newGame("GREEN", 2222, { Pokemon.new(Data, "FIXMON_C", 12) })
  local games = { redGame, greenGame }
  redGame.expect = 2
  run(host, clients, {}, function() return red.status == "joined" and green.status == "joined" end, 10)
  local battle = openWild(red, redGame, "FIXMON_B", 3, function(mon) mon.hp = 1 end)
  local id = bindOpener(host, red, redGame, battle, clients, games)
  local gb = joinBattle(host, green, greenGame, id, clients, games)
  run(host, clients, games, function()
    local k = Replica.question(battle)
    return k == "learn" or battle.coop.done
  end, 20000)
  local kind, by = Replica.question(battle)
  eq(kind, "learn", "a fourth move to forget is a question")
  eq(by, red.player, "of the Pokémon's owner (A8.6)")
  eq(select(2, Replica.decider(gb)), red.player, "GREEN's copy waits for RED")
  run(host, clients, games, function()
    local b = host.battles[id]
    return b and b.ask and b.ask.kind == "learn"
  end, 200)
  battle.coop.picking = battle.coop.applied
  Replica.send(battle, { kind = "learn", forget = 2 })
  run(host, clients, games, function() return battle.coop.done and gb.coop.done end, 20000)
  eq(battle.coop.roster[1].moves[2].id, "FIX_EMBERISH", "RED's copy forgot the second move")
  eq(gb.coop.roster[1].moves[2].id, "FIX_EMBERISH", "and GREEN's copy too")
  eq(redGame.save.party[1].moves[2].id, "FIX_EMBERISH", "written back to RED's Pokémon")
  eq(redGame.save.party[1].level, 7, "which grew to level 7")
  eq(logged("battle_desync"), 0, "no desync")
end

-- 8. MIMIC's choice is the user's owner's (A8.6) ----------------------------------------
do
  Data.moves.FIX_MIMIC = { id = "FIX_MIMIC", index = 8, name = "FIX MIMIC", type = "NORMAL",
                           power = 0, accuracy = 100, pp = 10, effect = "MIMIC_EFFECT" }
  local host, red, green = setup()
  local clients = { red, green }
  local mimic = Pokemon.new(Data, "FIXMON_A", 12)
  mimic.moves = { { id = "FIX_MIMIC", pp = 10 } }
  local redGame = newGame("RED", 1111, { mimic })
  local greenGame = newGame("GREEN", 2222, { Pokemon.new(Data, "FIXMON_C", 12) })
  local games = { redGame, greenGame }
  redGame.expect = 2
  redGame.decide = function(b)
    if b.coop.mimicked then return false end
    b.coop.mimicked = true
    return { kind = "move", slot = 1 }
  end
  greenGame.decide = function() return false end
  run(host, clients, {}, function() return red.status == "joined" and green.status == "joined" end, 10)
  local battle = openWild(red, redGame, "FIXMON_B", 8, function(mon)
    mon.moves = { { id = "FIX_SCRATCH", pp = 35 }, { id = "FIX_GROWL", pp = 40 } }
  end)
  local id = bindOpener(host, red, redGame, battle, clients, games)
  local gb = joinBattle(host, green, greenGame, id, clients, games)
  run(host, clients, games, function()
    return Replica.question(battle) == "mimic" or battle.coop.done
  end, 20000)
  local kind, by = Replica.question(battle)
  eq(kind, "mimic", "MIMIC asks which move to copy")
  eq(by, red.player, "of the owner of the Pokémon using it (A8.6)")
  run(host, clients, games, function()
    local b = host.battles[id]
    return b and b.ask and b.ask.kind == "mimic"
  end, 200)
  Replica.send(battle, { kind = "mimic", index = 2 })
  run(host, clients, games, function()
    return Replica.question(battle) == "menu" and Replica.question(gb) == "menu"
  end, 20000)
  eq(battle.player.curMoves[1].id, "FIX_GROWL", "RED's copy copied the second move")
  eq(gb.player.curMoves[1].id, "FIX_GROWL", "and GREEN's copy too")
  eq(logged("battle_desync"), 0, "no desync")
end

T.finish()
