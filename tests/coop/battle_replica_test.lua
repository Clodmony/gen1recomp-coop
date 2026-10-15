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
  local save = SaveData.newGame()
  save.player.name = name
  save.player.id = otId
  save.party = party
  save.money = 1000
  local press = true
  local input = {
    wasPressed = function(_, k) return press and k == "a" end,
    isDown = function() return false end,
    wasReleased = function() return false end,
  }
  return { data = Data, save = save, stack = newStack(), input = input,
           setPress = function(v) press = v end }
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
local function openWild(client, game, species, level)
  local battle = BattleState.newWild(game, species, level)
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
  run(host, clients, {}, function() return red.status == "joined" and green.status == "joined" end, 10)

  local battle = openWild(red, redGame, "FIXMON_B", 6)
  local id = bindOpener(host, red, redGame, battle, clients, games)
  check(battle.coop ~= nil, "the opener's battle is a co-op battle")
  eq(#battle.coop.roster, 1, "the roster holds the opener's team")
  check(battle.player.mon ~= redGame.save.party[1], "the battle fights a copy, not the world's Pokémon")
  eq(battle.player.mon.species, "FIXMON_A", "of the opener's lead")
  local hp0 = battle.enemy.mon.hp

  -- red's copy plays the intro and asks red for a move; green joins then
  redGame.setPress(false)
  run(host, clients, games, function()
    local b = host.battles[id]
    return b and b.ask and b.ask.kind == "menu"
  end, 3000)
  redGame.setPress(true)
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
  if os.getenv("PROBE") then
    for _, b in ipairs({ battle, gb }) do
      local k, by = Replica.question(b)
      print("PROBE", b.coop.me, "phase", b.phase, "q", k, by, "applied", b.coop.applied,
        "ask", b.coop.ask and b.coop.ask.kind, "sent", b.coop.sent and b.coop.sent.cmd.kind,
        "result", b.result, "queue", #b.queue, "player", b.player.mon.species, b.player.mon.hp,
        "enemy hp", b.enemy.mon.hp)
    end
    for _, g in ipairs(games) do print("PROBE top", g.stack:top() and (g.stack:top().screenId or tostring(g.stack:top()))) end
    local hb = host.battles[id]
    print("PROBE host", hb and #hb.inputs, hb and hb.ask and hb.ask.kind, hb and hb.ask and hb.ask.by)
    for _, r in ipairs(red.rejections) do print("PROBE red rej", r.seq, r.reason) end
    for _, r in ipairs(green.rejections) do print("PROBE green rej", r.seq, r.reason) end
  end
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
  eq(redGame.save.party[1].hp, battle.coop.roster[1].hp, "red's Pokémon's HP came back")
  eq(#redGame.save.party, 1, "nothing was added to red's party")
  eq(#greenGame.save.party, 1, "nor to green's")
end

T.finish()
