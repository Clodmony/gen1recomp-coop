-- Co-op battle test harness (#18, #19): the host in-process, players over
-- loopback, each with a game of their own (fixture data, a stack, an input
-- that presses A for the text pages; the menus are answered by an
-- autopilot: a forced replacement takes the first standing Pokemon, a
-- YES/NO says YES, the command menu fights with the first move unless the
-- game's `decide` says otherwise, false to wait).

local T = require("tests.harness")
local H = {}
local Data = require("tests.modkit.fixtures").fresh()
H.Data = Data

local SaveData = require("src.core.SaveData")
local Pokemon = require("src.pokemon.Pokemon")
local BattleState = require("src.battle.BattleState")
local TypeChart = require("src.battle.TypeChart")
H.TypeChart = TypeChart
TypeChart.load(Data)

local Transport = require("src.coop.session.Transport")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local Replica = require("src.coop.battle.Replica")

local SHA = ("ab"):rep(20)
local clock, idCounter = 0, 0
H.logLines = {}

function H.newStack()
  local st = { states = {} }
  function st:push(s) self.states[#self.states + 1] = s; if s.enter then s:enter() end end
  function st:pop() return table.remove(self.states) end
  function st:top() return self.states[#self.states] end
  return st
end

function H.newGame(name, otId, party)
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
      if g and g.taps[k] then return true end -- a key the test taps for a frame
      if not press or k ~= "a" then return false end
      local b = g and g.stack:top()
      if b and b.coop then
        local q, by = Replica.decider(b)
        if q and by == b.coop.me then return false end
      end
      return true
    end,
    isDown = function() return false end,
    wasReleased = function() return false end,
  }
  g = { data = Data, save = save, stack = H.newStack(), input = input, taps = {},
        setPress = function(v) press = v end }
  return g
end

function H.setup()
  clock, H.logLines = 0, {}
  local host = Host.new({
    campaign = { id = "c0123456789abcdef", title = "T" }, cartridge = { game = "red", sha1 = SHA },
    clock = function() return clock end,
    hex = function(n) idCounter = idCounter + 1; return ("%0" .. n .. "x"):format(idCounter) end,
    log = { write = function(_, _, kind, data) H.logLines[#H.logLines + 1] = { kind = kind, data = data } end },
  })
  local hub = host:serve(Transport.loopback())
  local function seat(name, n)
    local c = Client.new(hub:dial(), { name = name, game = "red", sha1 = SHA, device = "d" .. n })
    c:join()
    return c
  end
  return host, seat("RED", 1), seat("GREEN", 2)
end

function H.logged(kind)
  local n = 0
  for _, l in ipairs(H.logLines) do if l.kind == kind then n = n + 1 end end
  return n
end

-- the player at a menu the always-A input cannot work: a forced
-- replacement picks the first standing Pokémon of the roster
function H.autopilot(g)
  local top = g.stack:top()
  if top and not top.coop and #g.stack.states > 1 and not g.keepScreens then g.stack:pop() end
  local b = g.stack:top()
  if not (b and b.coop) then return end
  Replica.step(b) -- the question goes to the host before its answer
  local kind, by = Replica.decider(b)
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
function H.frame(host, clients, games)
  clock = clock + 1 / 60
  for _, c in ipairs(clients) do c:update() end
  host:update()
  for _, c in ipairs(clients) do c:update() end
  for _, g in ipairs(games) do
    H.autopilot(g)
    local top = g.stack:top()
    if top and top.update then top:update(1 / 60) end
    g.taps = {}
    -- copies away from the screen go on (src/coop/game/Battles.lua does
    -- this in the game)
    for _, b in ipairs(g.away or {}) do
      if not b.coop.done then require("src.coop.battle.Replica").runAway(b) end
    end
  end
end

-- the clock the host reads, for timers (TAKE OVER, abandoned battles)
function H.advance(seconds) clock = clock + seconds end

function H.run(host, clients, games, untilFn, limit)
  for i = 1, limit or 20000 do
    if untilFn() then return i end
    H.frame(host, clients, games)
  end
  return nil
end

-- the opener's world opens a wild battle; it becomes a co-op battle
function H.openWild(client, game, species, level, prep)
  local battle = BattleState.newWild(game, species, level)
  if prep then prep(battle.enemy.mon) end
  local opening = { kind = "wild", enemy = { Replica.pack(battle.enemy.mon) },
                    map = "FIX_TOWN", foe = species }
  client:battleOpen(opening, Replica.packTeam(game.save.party), game.save.player.id, false,
                    Replica.room(game.save))
  return battle
end

function H.bindOpener(host, client, game, battle, clients, games)
  local id
  H.run(host, clients, games, function()
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

function H.joinBattle(host, client, game, id, clients, games)
  client:battleJoin(id, Replica.packTeam(game.save.party), game.save.player.id, false,
                    Replica.room(game.save))
  local rec
  local ok = H.run(host, clients, games, function()
    rec = client.battles[id]
    if not rec then return false end
    for _, input in ipairs(rec.inputs) do
      if input.kind == "join" and input.player == client.player then return true end
    end
    return false
  end, 4000)
  T.check(ok ~= nil, "the join goes in")
  local live = {}
  for i, m in ipairs(game.save.party) do live[i] = m end
  local b = Replica.build(game, rec, { client = client, id = id, me = client.player,
                                       real = game, live = live })
  Replica.catchUp(b, rec)
  game.stack:push(b)
  return b
end


return H
