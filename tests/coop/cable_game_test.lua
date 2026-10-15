-- The Cable Club in the game (#60, design A12.7, A12.8, A14.4, decision
-- G32), ROM-free: the fixture overworld runs headless with this device
-- hosting a session in-process; BLUE is a partner on the loopback hub whose
-- side of the link cable this test plays with upstream's own trade code.
-- Covered: a solo receptionist opens upstream's LAN link menu; in a co-op
-- world she opens the cartridge's link menu, the room chosen pairs the two
-- players, and upstream's trade screen runs over the session; the trade
-- lands once, the received Pokémon carries its uid, the host's worlds hold
-- the swap; a partner in a Cable Club room is not drawn; leaving brings the
-- menu back, CANCEL the receptionist's goodbye; a world continued in a
-- Cable Club room opens at its center's counter.
--   luajit tests/coop/cable_game_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local check, eq = T.check, T.eq

local Data = T.fixtures.fresh()
Data.tilesets.FIX_OUT.tilesPerRow = 16
Data.field.flyWarps = Data.field.flyWarps or {}
Data.field.playerSprites = { walk = "SPRITE_FIX_PLAYER", bike = "SPRITE_FIX_NPC" }
Data.field.waterTilesets = {}
Data.field.forcedMovement = { tiles = {} }

local Game       = require("src.core.Game")
local Input      = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local Renderer   = require("src.render.Renderer")
local SaveData   = require("src.core.SaveData")
local Pokemon    = require("src.pokemon.Pokemon")
local OW         = require("src.world.OverworldController")
local TextBox    = require("src.render.TextBox")
local LinkState  = require("src.link.LinkState")
local LinkProtocol = require("src.link.Protocol")
local Handshake  = require("src.link.Handshake")

local Identity = require("src.coop.session.Identity")
local Session  = require("src.coop.session.Session")
local Client   = require("src.coop.session.Client")
local World    = require("src.coop.campaign.World")
local Presence = require("src.coop.game.Presence")
local CableClub = require("src.coop.game.CableClub")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.save.flags.EVENT_GOT_STARTER = true -- past the opening (#22)
Game.save.flags.EVENT_GOT_POKEDEX = true -- the receptionist links only then
Game.save.player.name, Game.save.player.id = "RED", 1111
Game.save.party = { Pokemon.new(Data, "FIXMON_A", 14), Pokemon.new(Data, "FIXMON_B", 8) }
for _, mon in ipairs(Game.save.party) do mon.ot, mon.otId = "RED", 1111 end
local stack = Game.stack
stack:push(OW, "FIX_TOWN", 5, 6, "down")
local ow = stack:top()
Game.overworld = ow

local SHA = ("ab"):rep(20)
local function memoryStore()
  local text
  return { read = function() return text end, write = function(t) text = t end }
end

local blue
local peer -- BLUE's side of the cable: upstream's trade session
local function step(n, press)
  for _ = 1, n or 1 do
    Input.pressed = {}
    if press then Input.pressed[press] = true end
    local s = Session.current
    if s then s:update(1 / 60, Game) end
    if blue then blue:update() end
    if peer then peer() end
    stack:update(1 / 60)
    Presence.step(Game)
    Input.pressed = {}
    press = nil
  end
end

local function partnerActors()
  local out = {}
  for _, e in ipairs(ow.entities) do
    if e.coopPartner then out[#out + 1] = e end
  end
  return out
end

-- the receptionist's YES: her text box closes and the choice runs
local function receptionistYes()
  ow:cableClubReceptionist(function() end)
  local box = stack:top()
  check(getmetatable(box) == TextBox and box.choice ~= nil, "the receptionist asks to apply")
  stack:pop()
  box.choice(true)
end

-- solo: upstream's LAN link menu -----------------------------------------------------
do
  eq(CableClub.open(Game), false, "solo: the co-op Cable Club stays out")
  receptionistYes()
  eq(getmetatable(stack:top()), LinkState, "solo: the receptionist opens the LAN link menu")
  stack:pop()
  Game.linkSession = nil
  eq(stack:top(), ow, "back on the map")
end

-- a session: this device hosts, BLUE joins ------------------------------------------
local s = Session.startHost({
  campaign = { id = "c0001", title = "Fix co-op" },
  cartridge = { game = "red", sha1 = SHA }, name = "Red",
  listen = false, beacon = false, log = false, campaignFs = false,
  identity = Identity.load(memoryStore()),
})
step(4)
eq(s.status, "joined", "the host's own player is in")
blue = Client.new(s.hub:dial(), { name = "BLUE", game = "red", sha1 = SHA, device = "b1", seat = 1 })
blue:join()
step(4)
blue:sendOpening(true)
blue:move("FIX_TOWN", 3, 6, "down", true, "walk")
local blueParty = { Pokemon.new(Data, "FIXMON_B", 9) }
blueParty[1].ot, blueParty[1].otId = "BLUE", 2222
blue:sendWorld(World.encode({ player = { name = "BLUE", id = 2222, map = "FIX_TOWN", x = 3, y = 6,
                                         facing = "down" },
                              party = blueParty, boxes = {}, currentBox = 1, money = 0 }), false)
step(200) -- rest points: this world's holdings and uids reach and come back
local me = s.client.player
local host = s.host
eq(host.state:player(me).world, nil, "this world never saved: the host has none yet")
local blueUid = host.state:player(blue.player).world.party[1].coopUid
check(blueUid ~= nil, "BLUE's Pokémon has a uid on the host")
eq(#partnerActors(), 1, "BLUE is drawn on the map")

-- the receptionist opens the cartridge's link menu --------------------------------
receptionistYes()
local club = stack:top()
eq(getmetatable(club), CableClub.State, "in a co-op world the cartridge's link menu opens")
step(2)
-- the receptionist's save reached the host; the rows get their uids only at
-- the next rest point, so the host finds the offered row by its content
local myUid = host.state:player(me).world and host.state:player(me).world.party[1].coopUid
check(myUid ~= nil, "her save gave this world's Pokémon uids on the host")
eq(Game.save.party[1].coopUid, nil, "not yet on this world's rows")
step(1, "down")
step(1, "up")
step(1, "a") -- TRADE CENTER
step(4)
eq(club.stage, "waiting", "waiting in the TRADE CENTER")
eq(host.cable.players[me].room, "trade", "the host has this player in the room")
eq(stack:top(), club, "nobody yet: the menu waits")

-- BLUE comes in: the cable is theirs, upstream's trade screen runs over it
blue:cableEnter("trade")
local blueHello = Handshake.hello(Game, nil)
blueHello.name = "BLUE"
local bt -- BLUE's TradeSession
local blueGot = {}
local blueRound = 1
local bluePicked, blueConfirmed, blueDone = false, false, false
peer = function()
  local cable = blue.cable
  if cable and cable.round and cable.round > blueRound then blueRound = cable.round end
  for _, m in ipairs(blue:takeCableLinks()) do
    blueGot[#blueGot + 1] = m
    local link = m.link
    if link.type == "hello" then
      blue:cableLink(blueRound, blueHello)
      bt = LinkProtocol.TradeSession.new(Data, blueParty, { peerName = "RED" })
      local opening = bt:opening()
      blue:cableLink(blueRound, opening, { "" }) -- no uid: the host finds the row
    elseif bt then
      bt:handle(link)
      if link.type == "confirm" then bt.lastUid = m.uid end
    end
  end
  if bt and bt.stage == "picking" and not bluePicked then
    bluePicked = true
    blue:cableLink(blueRound, bt:pick(1))
  elseif bt and bt.stage == "confirming" and not blueConfirmed then
    blueConfirmed = true
    blue:cableLink(blueRound, bt:confirm(true))
  elseif bt and bt.stage == "done" and not blueDone then
    blueDone = true
  end
end
step(6)
local ls = stack:top()
eq(getmetatable(ls), LinkState, "the trade screen runs")
eq(club.stage, "linked", "the menu waits under it")
eq(#partnerActors(), 0, "BLUE in a Cable Club room is not drawn (A14.4)")
eq(blue.cable.mate, me, "BLUE's cable reaches this player")
step(10)
eq(ls.stage, "trade", "the hellos agree: the trade starts")
check(ls.trade and ls.trade.theirParty and ls.trade.theirParty[1], "BLUE's party arrived")

-- this player offers FIXMON_A, BLUE FIXMON_B, both say yes
local firstTrade = ls.trade
for _ = 1, 60 do
  local t = ls.trade
  if t == firstTrade and t.stage == "picking" and not t.myPick then ls.net:send(t:pick(1)) end
  if t == firstTrade and t.stage == "confirming" and ls.confirmed == nil then
    ls.confirmed = true
    ls.net:send(t:confirm(true))
  end
  step(1)
  if t.stage == "done" or ls.roundBusy then break end
end
check(blueDone, "BLUE's side finished the trade")
eq(bt and bt.lastUid, myUid, "BLUE heard the uid of the Pokémon it receives")
eq(Game.save.party[1].species, "FIXMON_B", "this player received BLUE's Pokémon")
eq(Game.save.party[1].coopUid, blueUid, "with its uid (A12.7)")
eq(Game.save.party[1].otId, 2222, "and BLUE as its trainer")
local hw = host.state:player(me).world
eq(hw.party[1].species, "FIXMON_B", "the host's copy of this world has the swap")
eq(hw.party[1].coopUid, blueUid, "with the uid")
eq(host.state:player(blue.player).world.party[1].coopUid, myUid, "and BLUE's")
local pairId = me < blue.player and (me .. "-" .. blue.player) or (blue.player .. "-" .. me)
check(host.state:applied("cable:" .. pairId .. ":1"), "committed once")

-- the movie and the texts; the screen starts the next round
for _ = 1, 3000 do
  local top = stack:top()
  if top == ls and ls.trade ~= firstTrade then break end
  step(1, (top ~= ls) and ((_ % 2 == 0) and "a" or "start") or nil)
end
eq(stack:top(), ls, "after the movie the trade screen is back")
check(ls.trade ~= firstTrade, "for another round")
eq(host.state:player(me).world.party[1].coopUid, blueUid,
   "the save after the trade reached the host with the uid")

-- BLUE leaves the room: the screen closes, the menu is back
blue:cableLink(blueRound, { type = "bye" })
blue:cableEnter("none")
step(6)
for _ = 1, 200 do
  if stack:top() == club then break end
  step(1, "a")
end
eq(stack:top(), club, "the menu is back")
step(2)
eq(club.stage, "menu", "out of the room")
eq(host.cable.players[me], nil, "and the host has nobody in a room")
step(4)
eq(#partnerActors(), 1, "BLUE out of the room is drawn again")

-- CANCEL: the receptionist's goodbye
step(1, "b")
check(getmetatable(stack:top()) == TextBox, "B leaves with the receptionist's goodbye")
stack:pop()
eq(stack:top(), ow, "back on the map")

-- a world continued in a Cable Club room (A12.8) ------------------------------------
do
  local data = {
    maps = {
      TOWN = { label = "Town", warps = { { x = 5, y = 5, destMap = "TOWN_POKECENTER", destWarp = 1 } } },
      TOWN_POKECENTER = { label = "TownPokecenter", tileset = "POKECENTER",
                          objects = { { sprite = "SPRITE_NURSE", x = 3, y = 1, text = "TEXT_1" } } },
      TRADE_CENTER = { label = "TradeCenter", objects = {} },
      COLOSSEUM = { label = "Colosseum", objects = {} },
    },
  }
  local save = { player = { name = "RED", map = "TRADE_CENTER", x = 3, y = 4, facing = "left" },
                 lastOutdoor = { id = "TOWN" } }
  local spot = CableClub.settle(save, data)
  check(spot ~= nil, "a save in the TRADE CENTER moves")
  eq(save.player.map, "TOWN_POKECENTER", "to the Pokémon Center of its town")
  eq(save.player.x, 3, "before the counter")
  eq(save.player.y, 3, "two cells below the nurse")
  eq(save.player.facing, "up", "facing it")
  eq(save.player.name, "RED", "the rest of the player stays")
  local col = { player = { map = "COLOSSEUM", x = 1, y = 1 }, lastOutdoor = { id = "TOWN" } }
  CableClub.settle(col, data)
  eq(col.player.map, "TOWN_POKECENTER", "the COLOSSEUM too")
  local town = { player = { map = "TOWN", x = 1, y = 1 } }
  eq(CableClub.settle(town, data), nil, "a save elsewhere stays")
  eq(town.player.map, "TOWN", "where it is")
end

T.finish("cable_game_test")
