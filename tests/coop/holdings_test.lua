-- Pokémon, party, PC and Pokédex (#17, design A7, decision G25), ROM-free:
-- uids matched to rows (an unchanged row first, then the row's place);
-- the holdings a window sends at its rest points (the world, the PC only
-- when it changed) and the uids the host hands back; a catch for the
-- player the thrower names, only players with room offered and a ball
-- kept when nobody has room; the Pokédex marks every species that
-- appeared for every participant; a gift Pokémon with six in the party
-- goes to the box.  Host and clients in one process over loopback.
--   luajit tests/coop/holdings_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq
local F = require("tests.coop.support.campaign_fixture")
local Transport = require("src.coop.session.Transport")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local Protocol = require("src.coop.session.Protocol")
local World = require("src.coop.campaign.World")
local Campaign = require("src.coop.campaign.Campaign")
local Window = require("src.coop.campaign.Window")

local SHA = ("ab"):rep(20)
local CID = "c0123456789abcdef"
local P1 = "p0123456789abcdef"

local function copyOf(save) return World.decode(World.encode(save)) end

-- uids: an unchanged row first, then the row's place (A7.3) ------------------------
do
  local c = Campaign.new({ id = CID, title = "T", game = "red" })
  c:addPlayer({ id = P1, name = "RED", game = "red" })
  local same = { attack = 2, defense = 2, speed = 2, special = 2 }
  local save = F.save("RED")
  save.boxes[1] = { F.mon("MAGIKARP", 5, { dvs = same }), F.mon("MAGIKARP", 5, { dvs = same }) }
  local ok, assigned = c:setWorld(P1, save)
  check(ok, "a world with twins is taken")
  local w = c:player(P1).world
  local a, b = w.boxes[1][1].coopUid, w.boxes[1][2].coopUid
  check(a and b and a ~= b, "the twins get two uids")
  eq(type(assigned) == "table" and #assigned, 3, "the host says which rows it gave a uid")
  local first = assigned and assigned[1]
  eq(first and first.box, 0, "the team's rows are box 0")
  eq(first and first.slot, 1, "in their slot")
  eq(first and first.fp, Campaign.fingerprint(w.party[1]), "with the row's fingerprint")

  -- the second twin levelled up and both lost their uids: the unchanged
  -- one keeps its own even though it moved to the other place
  local moved = copyOf(w)
  local x, y = moved.boxes[1][1], moved.boxes[1][2]
  x.coopUid, y.coopUid = nil, nil
  y.level, y.exp = 6, 200
  moved.boxes[1] = { y, x }
  c:setWorld(P1, moved)
  local now = c:player(P1).world.boxes[1]
  eq(now[2].coopUid, a, "the unchanged twin keeps its uid wherever it stands")
  eq(now[1].coopUid, b, "the changed one takes the other")

  -- both changed: each keeps the uid of the place it stands on
  local both = copyOf(c:player(P1).world)
  for _, m in ipairs(both.boxes[1]) do m.coopUid = nil; m.level = m.level + 1 end
  c:setWorld(P1, both)
  now = c:player(P1).world.boxes[1]
  eq(now[1].coopUid, b, "a changed twin keeps the uid of its place (first)")
  eq(now[2].coopUid, a, "and the other its own (second)")
end

-- holdings at rest points (A7.2, A7.4, A7.5) ------------------------------------------
local clock = 0
local function now() return clock end
local ids = 0
local function hex(n)
  ids = ids + 1
  return ("%0" .. n .. "x"):format(ids)
end

local function startHost()
  local c = Campaign.new({ id = CID, title = "KANTO", game = "red", sha1 = SHA })
  local host = Host.new({ campaign = { id = CID, title = "KANTO" },
                          cartridge = { game = "red", sha1 = SHA }, clock = now, hex = hex,
                          state = c, build = "test" })
  return host, host:serve(Transport.loopback())
end

local function window(hub, name, device)
  local c = Client.new(hub:dial(), { name = name, game = "red", sha1 = SHA, build = "test",
                                     device = device, clock = now })
  c:join()
  local x = { c = c, w = Window.new(c), save = F.save(name), map = "PALLET_TOWN", busy = nil,
              sent = {} }
  -- what the client sends of its holdings
  local send = c.send
  c.send = function(self, msg)
    if msg.type == "holdings" then x.sent[#x.sent + 1] = { boxes = msg.boxes ~= nil } end
    return send(self, msg)
  end
  return x
end

local function pump(host, wins, frames)
  for _ = 1, frames or 4 do
    clock = clock + 1 / 60
    for _, x in ipairs(wins) do x.c:update() end
    host:update()
    for _, x in ipairs(wins) do
      x.c:update()
      x.w:update({ save = x.save, busy = x.busy, map = x.map, still = true })
    end
  end
end

do
  local host, hub = startHost()
  local red = window(hub, "RED", "d1")
  pump(host, { red }, 8)
  eq(red.c.status, "joined", "RED joined")
  local pid = red.c.player
  eq(#red.sent, 0, "the first rest point sends nothing: the window opened as the host has it")
  eq(host.state:player(pid).world, nil, "a fresh player has no world yet")

  -- a scene hurt the team: at the next rest point the world goes to the
  -- host, the PC with it the first time
  red.busy = "script"
  red.save.party[1].hp = 3
  pump(host, { red }, 4)
  eq(#red.sent, 0, "nothing while the player is held")
  red.busy = nil
  pump(host, { red }, 6)
  eq(#red.sent, 1, "the change goes out at the next rest point")
  check(red.sent[1] and red.sent[1].boxes, "with the PC the first time")
  local hw = host.state:player(pid).world
  check(hw ~= nil, "the host keeps the world without a SAVE (A7.4)")
  eq(hw and hw.party[1].hp, 3, "with the hurt team")
  check(hw and hw.party[1].coopUid, "its Pokémon stamped with uids")

  -- a heal in the window goes to the host (A7.4)
  red.busy = "heal"
  red.save.party[1].hp = 20
  pump(host, { red }, 2)
  red.busy = nil
  pump(host, { red }, 6)
  eq(#red.sent, 2, "the heal goes out")
  eq(red.sent[2] and red.sent[2].boxes, false, "without the PC, which did not change")
  hw = host.state:player(pid).world
  eq(hw and hw.party[1].hp, 20, "the host has the healed team")
  pump(host, { red }, 6)
  eq(red.save.party[1].coopUid, hw and hw.party[1].coopUid,
     "the window's row took the uid the host gave it")
  local n0 = #red.sent

  -- a held window sends nothing; a deposit sends the PC
  red.busy = "pc"
  local mon = table.remove(red.save.party, 1)
  red.save.party[1] = F.mon("PIDGEY", 4)
  table.insert(red.save.boxes[3], mon)
  red.save.currentBox = 3
  pump(host, { red }, 8)
  eq(#red.sent, n0, "nothing while the player is held")
  red.busy = nil
  pump(host, { red }, 8)
  eq(#red.sent, n0 + 1, "the deposit goes out once")
  check(red.sent[n0 + 1] and red.sent[n0 + 1].boxes, "with the PC, which changed")
  hw = host.state:player(pid).world
  eq(hw.currentBox, 3, "the host has the box the player switched to (A7.5)")
  eq(hw.boxes[3][1] and hw.boxes[3][1].coopUid, mon.coopUid, "a deposit keeps its uid")
  check(hw.party[1].coopUid and hw.party[1].coopUid ~= mon.coopUid, "the new one has its own")
  pump(host, { red }, 6)
  eq(red.save.party[1].coopUid, hw.party[1].coopUid, "and the window has it")

  -- poison while walking (no hold): the team is looked at again within a second
  local n1 = #red.sent
  red.save.party[1].hp = red.save.party[1].hp - 1
  pump(host, { red }, Window.HOLDINGS_EVERY + 4)
  eq(#red.sent, n1 + 1, "a change while walking goes out within HOLDINGS_EVERY frames")
  eq(red.sent[n1 + 1] and red.sent[n1 + 1].boxes, false, "without the PC, which did not change")
  eq(host.state:player(pid).world.boxes[3][1].coopUid, mon.coopUid, "the host keeps the PC it had")

  -- a rejoin opens the world the host kept, though nobody saved
  local again = host.state:worldFor(pid)
  eq(again.party[1].hp, red.save.party[1].hp, "the kept team is what a rejoin opens (A7.4)")
  eq(again.boxes[3][1].species, mon.species, "and the kept PC")

  -- a new link sends the PC again with its first holdings
  red.c.conn:close()
  local c2 = Client.new(hub:dial(), { name = "RED", game = "red", sha1 = SHA, build = "test",
                                      device = "d1", clock = now, known = red.c.known })
  local send = c2.send
  c2.send = function(self, msg)
    if msg.type == "holdings" then red.sent[#red.sent + 1] = { boxes = msg.boxes ~= nil } end
    return send(self, msg)
  end
  c2:join()
  red.c, red.w.client = c2, c2
  pump(host, { red }, 8)
  eq(c2.status, "joined", "back in")
  local n2 = #red.sent
  red.save.money = red.save.money - 100
  pump(host, { red }, Window.HOLDINGS_EVERY + 4)
  eq(#red.sent, n2 + 1, "a change after the redial goes out")
  check(red.sent[n2 + 1] and red.sent[n2 + 1].boxes, "with the PC: a new link hears it whole")

  -- START > SAVE sends the world whole: the next rest point has nothing new
  local n3 = #red.sent
  red.save.party[1].hp = 1
  red.w:flush(red.save)
  c2:sendWorld(World.encode(red.save), false)
  pump(host, { red }, Window.HOLDINGS_EVERY + 4)
  eq(#red.sent, n3, "a world sent with a save is not sent again")
end

-- protocol: holdings and uids are checked like every message ----------------------------
do
  local ok = Protocol.sanitize({ type = "holdings", seq = 1, world = "x" }, "host")
  check(ok ~= nil, "holdings carry the world")
  check(Protocol.sanitize({ type = "holdings", seq = 1 }, "host") == nil, "not without it")
  local list = { { box = 0, slot = 1, uid = P1 .. ":1", fp = "1|RED|a=1|45" } }
  check(Protocol.sanitize({ type = "uids", list = list }, "client") ~= nil, "uids go to the window")
  check(Protocol.sanitize({ type = "uids", list = { { box = 13, slot = 1, uid = "x", fp = "" } } },
                          "client") == nil, "a row outside the PC is refused")
  check(Protocol.VERSION >= 8, "protocol 8: holdings")
end

-- battles: a catch for the player the thrower names (A7.6), the Pokédex (A7.7) -------
local H = require("tests.coop.support.battle_harness")
local Data = H.Data
local Pokemon = require("src.pokemon.Pokemon")
local Replica = require("src.coop.battle.Replica")
local View = require("src.coop.battle.View")

-- every box full
local function fillBoxes(save)
  save.boxes = {}
  for b = 1, 12 do
    save.boxes[b] = {}
    for i = 1, 20 do save.boxes[b][i] = Pokemon.new(Data, "FIXMON_C", 2) end
  end
  save.currentBox = 1
end

do
  local host, red, green = H.setup()
  local clients = { red, green }
  local redGame = H.newGame("RED", 1111, { Pokemon.new(Data, "FIXMON_A", 10) })
  local greenGame = H.newGame("GREEN", 2222, { Pokemon.new(Data, "FIXMON_C", 10) })
  greenGame.save.inventory.FIX_BALL = 50
  redGame.save.pokedex.seen, redGame.save.pokedex.owned = {}, {}
  greenGame.save.pokedex.seen, greenGame.save.pokedex.owned = {}, {}
  local games = { redGame, greenGame }
  redGame.expect = 2
  H.run(host, clients, {}, function() return red.status == "joined" and green.status == "joined" end, 10)
  local battle = H.openWild(red, redGame, "FIXMON_B", 3)
  local id = H.bindOpener(host, red, redGame, battle, clients, games)
  local gb = H.joinBattle(host, green, greenGame, id, clients, games)
  local switched = false
  redGame.decide = function()
    if switched then return nil end
    switched = true
    return { kind = "switch", index = 2 }
  end
  greenGame.decide = function() return { kind = "ball", item = "FIX_BALL", target = red.player } end
  local done = H.run(host, clients, games, function() return battle.coop.done and gb.coop.done end, 60000)
  check(done ~= nil, "the battle ends")
  eq(gb.result, "caught", "green's ball caught it")
  eq(#redGame.save.party, 2, "the catch went to the player green named (A7.6)")
  eq(redGame.save.party[2].species, "FIXMON_B", "the foe")
  eq(redGame.save.party[2].otId, 1111, "with red as its trainer")
  eq(#greenGame.save.party, 1, "not to the thrower")
  check(redGame.save.pokedex.owned.FIXMON_B, "red owns it in red's Pokédex")
  check(not greenGame.save.pokedex.owned.FIXMON_B, "green does not own it")
  -- A7.7: every species that appeared is seen by every participant,
  -- the partner's Pokémon too, the joiner credited with the whole battle
  check(greenGame.save.pokedex.seen.FIXMON_B, "the joiner saw the foe")
  check(greenGame.save.pokedex.seen.FIXMON_A, "the joiner saw red's Pokémon")
  check(redGame.save.pokedex.seen.FIXMON_C, "red saw green's Pokémon")
  eq(H.logged("battle_desync"), 0, "no desync")
end

-- room: the list offers only players with room; nobody has room: the ball is kept
do
  local host, red, green = H.setup()
  local clients = { red, green }
  local redGame = H.newGame("RED", 1111, { Pokemon.new(Data, "FIXMON_A", 10) })
  local greenGame = H.newGame("GREEN", 2222, { Pokemon.new(Data, "FIXMON_C", 10) })
  for i = 2, 6 do redGame.save.party[i] = Pokemon.new(Data, "FIXMON_C", 2) end
  fillBoxes(redGame.save)
  greenGame.save.inventory.FIX_BALL = 5
  local games = { redGame, greenGame }
  redGame.expect = 2
  H.run(host, clients, {}, function() return red.status == "joined" and green.status == "joined" end, 10)
  local battle = H.openWild(red, redGame, "FIXMON_B", 3)
  local id = H.bindOpener(host, red, redGame, battle, clients, games)
  local gb = H.joinBattle(host, green, greenGame, id, clients, games)
  eq(gb.coop.room[red.player], false, "the record says red has no room")
  eq(gb.coop.room[green.player], true, "and green has")

  local picked
  View.askCatcher(gb, "FIX_BALL", function(pid) picked = pid end)
  eq(picked, green.player, "the only player with room is named without a list")

  -- nobody has room: the throw is refused and the ball kept (A7.6)
  gb.coop.room[green.player] = false
  local balls = greenGame.save.inventory.FIX_BALL
  greenGame.save.inventory.FIX_BALL = balls - 1 -- the bag spent it, as BagMenu does
  local depth = #greenGame.stack.states
  local facade = Replica.facade(gb)
  facade.throwBall(facade, "FIX_BALL")
  local top = greenGame.stack:top()
  check(not (top and top.items), "no list is asked")
  eq(greenGame.save.inventory.FIX_BALL, balls, "the ball is back in the bag")
  eq(gb.coop.sent, nil, "nothing went to the host")
  check(gb.coop.refusal ~= nil, "the battle says the BOX is full")
  while #greenGame.stack.states > depth do greenGame.stack:pop() end
  gb.coop.room[green.player] = true

  -- the host refuses a catch for a player without room; green then fights
  local switched, threw = false, false
  redGame.decide = function()
    if switched then return nil end
    switched = true
    return { kind = "switch", index = 7 } -- green's lead, behind red's six
  end
  greenGame.decide = function()
    if threw then return nil end
    threw = true
    return { kind = "ball", item = "FIX_BALL", target = red.player }
  end
  local done = H.run(host, clients, games, function() return battle.coop.done and gb.coop.done end, 60000)
  check(done ~= nil and threw, "the battle ends after green tried")
  local refused = false
  for _, r in ipairs(green.rejections) do refused = refused or r.reason == "bad_cmd" end
  check(refused, "a catch for a player without room is refused")
  eq(#redGame.save.party, 6, "nothing reached red")
  eq(H.logged("battle_desync"), 0, "no desync")
end

-- a gift Pokémon with six in the party goes to the player's box (A7.9) ----------------
do
  local Commands = require("src.script.Commands")
  local save = H.newGame("RED", 1111, {}).save
  for i = 1, 6 do save.party[i] = Pokemon.new(Data, "FIXMON_A", 5) end
  save.boxes = nil
  local game = { data = Data, save = save, mods = nil, stack = H.newStack() }
  local ctx = { game = game, save = save }
  Commands.give_pokemon(ctx, "FIXMON_B", 25)
  eq(ctx.lastCheck, true, "the gift is given")
  eq(#save.party, 6, "the team stays at six")
  eq(save.boxes and save.boxes[save.currentBox][1] and save.boxes[save.currentBox][1].species,
     "FIXMON_B", "the gift went to the box")
end

T.finish()
