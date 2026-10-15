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
local Data = require("tests.modkit.fixtures").fresh()

local SaveData = require("src.core.SaveData")
local Pokemon = require("src.pokemon.Pokemon")
local BattleState = require("src.battle.BattleState")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local Transport = require("src.coop.session.Transport")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local Replica = require("src.coop.battle.Replica")

local SHA = ("ab"):rep(20)
local clock, idCounter = 0, 0
local logLines = {}

local function newStack()
  local st = { states = {} }
  function st:push(s) self.states[#self.states + 1] = s; if s.enter then s:enter() end end
  function st:pop() return table.remove(self.states) end
  function st:top() return self.states[#self.states] end
  return st
end

local function newGame(name, otId, party)
  for _, m in ipairs(party) do m.otId, m.ot = otId, name end
  local save = SaveData.newGame()
  save.player.name = name
  save.player.id = otId
  save.party = party
  save.money = 1000
  local press = true
  local g
  local input = {
    -- A for the text pages; the menus are answered by the autopilot
    wasPressed = function(_, k)
      if not press or k ~= "a" then return false end
      local b = g and g.stack:top()
      if b and b.coop then
        local q, by = Replica.question(b)
        if q == "menu" and by == b.coop.me then return false end
      end
      return true
    end,
    isDown = function() return false end,
    wasReleased = function() return false end,
  }
  g = { data = Data, save = save, stack = newStack(), input = input,
        setPress = function(v) press = v end }
  return g
end

local function setup()
  clock, logLines = 0, {}
  local host = Host.new({
    campaign = { id = "c0123456789abcdef", title = "T" }, cartridge = { game = "red", sha1 = SHA },
    clock = function() return clock end,
    hex = function(n) idCounter = idCounter + 1; return ("%0" .. n .. "x"):format(idCounter) end,
    log = { write = function(_, _, kind, data) logLines[#logLines + 1] = { kind = kind, data = data } end },
  })
  local hub = host:serve(Transport.loopback())
  local function seat(name, n)
    local c = Client.new(hub:dial(), { name = name, game = "red", sha1 = SHA, device = "d" .. n })
    c:join()
    return c
  end
  return host, seat("RED", 1), seat("GREEN", 2)
end

local function logged(kind)
  local n = 0
  for _, l in ipairs(logLines) do if l.kind == kind then n = n + 1 end end
  return n
end

-- the player at a menu the always-A input cannot work: a forced
-- replacement picks the first standing Pokémon of the roster
local function autopilot(g)
  local top = g.stack:top()
  if top and not top.coop and #g.stack.states > 1 then g.stack:pop() end
  local b = g.stack:top()
  if not (b and b.coop) then return end
  Replica.step(b) -- the question goes to the host before its answer
  local kind, by = Replica.question(b)
  if kind == "menu" and by == b.coop.me and not b.coop.sent then
    -- wait for the partner to be in, then fight with the first move
    -- unless the scenario decides otherwise
    if #b.coop.roster >= (g.expect or 1) then
      local cmd = g.decide and g.decide(b)
      if cmd == nil then cmd = { kind = "move", slot = 1 } end
      if cmd then Replica.send(b, cmd) end
    end
  end
  if kind == "choice" and by == b.coop.me and not b.coop.sent then
    b.coop.picking = b.coop.applied
    Replica.send(b, { kind = "choice", yes = true })
  end
  if kind == "replace" and by == b.coop.me and not b.coop.sent then
    for i, m in ipairs(b.coop.roster) do
      if m.hp > 0 then
        b.coop.picking = b.coop.applied
        Replica.send(b, { kind = "replace", index = i })
        break
      end
    end
  end
end

-- one frame: links, host, and each game's top state
local function frame(host, clients, games)
  clock = clock + 1 / 60
  for _, c in ipairs(clients) do c:update() end
  host:update()
  for _, c in ipairs(clients) do c:update() end
  for _, g in ipairs(games) do
    autopilot(g)
    local top = g.stack:top()
    if top and top.update then top:update(1 / 60) end
  end
end

local function run(host, clients, games, untilFn, limit)
  for i = 1, limit or 20000 do
    if untilFn() then return i end
    frame(host, clients, games)
  end
  return nil
end

-- the opener's world opens a wild battle; it becomes a co-op battle
local function openWild(client, game, species, level, prep)
  local battle = BattleState.newWild(game, species, level)
  if prep then prep(battle.enemy.mon) end
  local opening = { kind = "wild", enemy = { Replica.pack(battle.enemy.mon) },
                    map = "FIX_TOWN", foe = species }
  client:battleOpen(opening, Replica.packTeam(game.save.party), game.save.player.id, false)
  return battle
end

local function bindOpener(host, client, game, battle, clients, games)
  local id
  run(host, clients, games, function()
    id = next(client.battles)
    return id ~= nil
  end, 20)
  local live = {}
  for i, m in ipairs(game.save.party) do live[i] = m end
  Replica.make(battle, client.battles[id], { client = client, id = id, me = client.player,
                                             real = game, live = live })
  game.stack:push(battle)
  return id
end

local function joinBattle(host, client, game, id, clients, games)
  client:battleJoin(id, Replica.packTeam(game.save.party), game.save.player.id, false)
  local rec
  local ok = run(host, clients, games, function()
    rec = client.battles[id]
    if not rec then return false end
    for _, input in ipairs(rec.inputs) do
      if input.kind == "join" and input.player == client.player then return true end
    end
    return false
  end, 4000)
  check(ok ~= nil, "the join goes in")
  local live = {}
  for i, m in ipairs(game.save.party) do live[i] = m end
  local b = Replica.build(game, rec, { client = client, id = id, me = client.player,
                                       real = game, live = live })
  Replica.catchUp(b, rec)
  game.stack:push(b)
  return b
end

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

T.finish()
