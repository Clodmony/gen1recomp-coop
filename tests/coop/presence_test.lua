-- Partner presence (#15, design A14), ROM-free: the fixture overworld runs
-- headless with this device hosting a session in-process; a partner dials
-- the host's loopback hub like a second device.  Partners on this map are
-- solid, on a connected map drawn and passable, gone once they leave;
-- steps are eased by how the partner travels; every player wears the
-- colour of their place; the arrow's map search and placement; START >
-- CO-OP, SELECT and the CO-OP menu; notices; hold B to run; TOWN MAP marks.
--   luajit tests/coop/presence_test.lua

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
local Collision  = require("src.world.Collision")

local Protocol = require("src.coop.session.Protocol")
local Identity = require("src.coop.session.Identity")
local Session  = require("src.coop.session.Session")
local Client   = require("src.coop.session.Client")
local Presence = require("src.coop.game.Presence")
local Colors   = require("src.coop.game.Colors")
local Notices  = require("src.coop.game.Notices")
local Arrow    = require("src.coop.game.Arrow")
local CoopMenu = require("src.coop.game.CoopMenu")
local Marks    = require("src.coop.game.TownMapMarks")
local StartMenu = require("src.ui.StartMenu")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.save.flags.EVENT_GOT_STARTER = true -- past the opening (#22)
Game.save.party = { Pokemon.new(Data, "FIXMON_A", 20) }
local stack = Game.stack

stack:push(OW, "FIX_TOWN", 5, 6, "down")
local ow = stack:top()
Game.overworld = ow

local SHA = ("ab"):rep(20)
local function memoryStore()
  local text
  return { read = function() return text end, write = function(t) text = t end }
end

-- the protocol carries how a player travels (v3) ------------------------

check(Protocol.VERSION >= 3, "travel is protocol version 3")
eq(Protocol.sanitize({ type = "move", seq = 1, map = "FIX_TOWN", x = 1, y = 1,
                       facing = "up", warp = false }, "host"), nil,
   "a move without its travel is dropped")
eq(Protocol.sanitize({ type = "move", seq = 1, map = "FIX_TOWN", x = 1, y = 1,
                       facing = "up", warp = false, travel = "jog" }, "host"), nil,
   "and one with an unknown travel")

-- no session: nothing of co-op shows -----------------------------------

local function step(n)
  for _ = 1, n or 1 do
    local s = Session.current
    if s then s:update(1 / 60, Game) end
    if Presence.partner then Presence.partner:update() end
    stack:update(1 / 60)
    Presence.step(Game)
  end
end

local function partnerActors()
  local out = {}
  for _, e in ipairs(ow.entities) do
    if e.coopPartner then out[#out + 1] = e end
  end
  return out
end

local function labels(menu)
  local out = {}
  for i, it in ipairs(menu.items) do out[i] = it.label end
  return table.concat(out, ",")
end

step(2)
eq(#partnerActors(), 0, "solo: no partner actors")
check(not labels(StartMenu.new(Game)):find("CO-OP"), "solo: no CO-OP row in START")
Input:sourcePress("b", "test")
Input:step()
eq(ow.player:stepLength("left"), 16, "solo: holding B walks as the cartridge does")
Input:sourceRelease("b", "test")
Input:step()
eq(CoopMenu.select(Game), false, "solo: SELECT opens nothing")

-- a session: this device hosts, BLUE dials in -----------------------------

local s = Session.startHost({
  campaign = { id = "c0001", title = "Fix co-op" },
  cartridge = { game = "red", sha1 = SHA }, name = "HOST",
  listen = false, beacon = false, log = false,
  identity = Identity.load(memoryStore()),
})
step(3)
eq(s.status, "joined", "the host's own player is in")
local blue = Client.new(s.hub:dial(), { name = "BLUE", game = "red", sha1 = SHA,
                                        device = "b1", seat = 1 })
Presence.partner = blue
blue:join()
step(3)
eq(blue.status, "joined", "BLUE joined")
-- BLUE has no world in the campaign: a new player, in the opening (#22, A4.8)
eq(Notices.texts()[1], "BLUE joined the session in the opening.", "a notice says BLUE joined")
eq(#partnerActors(), 0, "a partner with no position yet is not drawn")

blue:move("FIX_TOWN", 3, 6, "down", true, "walk")
step(2)
eq(#partnerActors(), 0, "a partner in the opening is not drawn (#22, A4.4)")
eq(CoopMenu.lines(Game, s, "10.0.0.5")[7], " IN THE OPENING", "the CO-OP box says so (A4.8)")
blue:sendOpening(true)
step(2)
local actors = partnerActors()
eq(#actors, 1, "BLUE on this map is drawn")
local a = actors[1]
eq(a.cellX, 3, "at their cell x")
eq(a.cellY, 6, "at their cell y")
eq(a.px, 48, "at their pixel x (a warp lands at once)")
eq(a.passable, false, "solid on this map")

-- colours by place: the host's player is first, BLUE second, in every window
local own = Colors.palette(1)
local second = Colors.palette(2)
eq(a.colors[3][1], second[3][1], "BLUE wears the second place's colour")
check(ow.player.sprite.coopColors ~= nil, "this player wears a colour too")
eq(ow.player.sprite.coopColors[3][3], own[3][3], "the first place's")
check(Colors.palette(1)[3][1] ~= Colors.palette(2)[3][1], "places differ in colour")

-- easing: a walking step takes 16 frames, a running or riding one 8
blue:move("FIX_TOWN", 4, 6, "right", false, "walk")
local frames = 0
step(1) -- the state arrives
repeat frames = frames + 1; step(1) until a.px == 64 or frames > 40
eq(frames, 15, "a walked step is eased over 16 frames")
eq(a.cellX, 4, "and BLUE stands on the new cell")
blue:move("FIX_TOWN", 4, 7, "down", false, "run")
frames = 0
step(1)
repeat frames = frames + 1; step(1) until a.py == 112 or frames > 40
eq(frames, 7, "a run step over 8")
blue:move("FIX_TOWN", 4, 6, "up", false, "bike")
frames = 0
step(1)
check(a.py < 112 and a.py > 96, "a bike step is under way")
eq(a.targetX, 4, "mid-step, the cell left still blocks")
repeat frames = frames + 1; step(1) until a.py == 96 or frames > 40
eq(frames, 7, "a bike step over 8")
eq(a:pose().def.id, "SPRITE_FIX_NPC", "a riding partner wears the bike sheet")
blue:move("FIX_TOWN", 4, 6, "up", false, "surf")
step(2)
eq(a:pose().def.id, "SPRITE_FIX_PLAYER", "a sheet the cartridge lacks falls back to walking")

-- solid: the player's step and NPC wandering stop at BLUE ----------------

eq(ow.player.cellX, 5, "the player stands at (5,6)")
ow.player.facing = "left"
eq(ow.player:tryMove("left", ow.map, ow.entities), "blocked", "a step into BLUE is blocked")
blue:move("FIX_TOWN", 4, 5, "up", false, "walk")
step(20)
local greeter
for _, n in ipairs(ow.npcs) do if n.cellX == 4 and n.cellY == 4 then greeter = n end end
check(greeter ~= nil, "the fixture's NPC stands at (4,4)")
check(not Collision.canMove(ow.map, ow.entities, greeter, "down"),
      "an NPC's wandering step into BLUE is refused")
-- a scripted move passes through
blue:move("FIX_TOWN", 5, 5, "right", false, "walk")
step(20)
ow.player.turnTimer = 0
local doneScript = false
ow:scriptMove(ow.player, "up", 1, function() doneScript = true end)
step(40)
check(doneScript, "a scripted step onto BLUE's cell runs")
eq(ow.player.cellY, 5, "and passes through")
ow.player.cellX, ow.player.cellY = 5, 6
ow.player.px, ow.player.py = 80, 96

-- a connected map: drawn there, never solid ------------------------------

blue:move("FIX_ROUTE", 4, 16, "down", true, "walk")
step(2)
local ox, oy = Presence.offsetOf(ow, "FIX_ROUTE")
check(ox ~= nil, "the route north is a drawn neighbour")
actors = partnerActors()
eq(#actors, 1, "BLUE on the connected route is drawn")
eq(a.py, 16 * 16 + oy, "at the route's offset")
eq(a.passable, true, "and never solid there")
eq(a.cellX, nil, "with no cell on this map")

-- the arrow ------------------------------------------------------------

local function arrows()
  return Arrow.arrows(Game, ow, Presence.partners(), 160, 144)
end
blue:move("FIX_ROUTE", 4, 2, "up", true, "walk")
step(2)
local list = arrows()
eq(#list, 1, "BLUE far up the route: one arrow")
eq(list[1].dir, "up", "pointing up")
eq(list[1].y, Arrow.EDGE, "on the top edge, two pixels in")
eq(list[1].place, 2, "in BLUE's colour")
-- the world pass draws BLUE, the UI pass the arrow and a notice
Notices.push("A NOTICE")
local okDraw, drawErr = pcall(function()
  Renderer:beginFrame()
  ow:draw()
  Renderer:endFrame()
end)
check(okDraw, "the overworld draws with a partner, an arrow and a notice: " .. tostring(drawErr))
Notices.clear()
local Screens = require("src.ui.Screens")
Screens.push(Game, "StartMenu")
eq(#arrows(), 0, "no arrow while a menu is up")
stack:pop()
blue:move("FIX_TOWN", 7, 6, "down", true, "walk")
step(2)
eq(#arrows(), 0, "no arrow while BLUE is on the screen")

-- the route search, on maps of its own
local function map(w, h, extra)
  local m = { width = w, height = h, tileset = extra.indoor and "HOUSE" or "OVERWORLD",
              connections = extra.connections or {}, warps = extra.warps or {} }
  return m
end
local maps = {
  TOWN = map(10, 9, { connections = { north = { map = "ROUTE", offset = 0 } },
    warps = { { x = 3, y = 5, destMap = "HOUSE", destWarp = 1 },
              { x = 15, y = 5, destMap = "HOUSE", destWarp = 2 },
              { x = 9, y = 9, destMap = "MART", destWarp = 1 } } }),
  ROUTE = map(10, 18, { connections = { south = { map = "TOWN", offset = 0 } },
    warps = { { x = 5, y = 1, destMap = "GATE", destWarp = 1 } } }),
  HOUSE = map(4, 4, { indoor = true,
    warps = { { x = 1, y = 7, destMap = "LAST_MAP", destWarp = 1 },
              { x = 6, y = 7, destMap = "LAST_MAP", destWarp = 2 },
              { x = 7, y = 1, destMap = "HOUSE_2F", destWarp = 1 } } }),
  HOUSE_2F = map(4, 4, { indoor = true,
    warps = { { x = 7, y = 1, destMap = "HOUSE", destWarp = 3 } } }),
  MART = map(4, 4, { indoor = true, warps = { { x = 3, y = 7, destMap = "LAST_MAP", destWarp = 3 } } }),
  GATE = map(5, 4, { indoor = true, warps = { { x = 4, y = 7, destMap = "LAST_MAP", destWarp = 1 } } }),
  ISLAND = map(10, 9, {}),
}
local function outside(def) return def.tileset == "OVERWORLD" end
local r = Arrow.route(maps, "TOWN", "ROUTE", nil, outside)
eq(r.kind, "exact", "connections alone: exact")
eq(r.oy, -18 * 32, "with the route's offset")
r = Arrow.route(maps, "TOWN", "HOUSE_2F", nil, outside)
eq(r.kind, "door", "upstairs in a house: a door")
eq(#r.doors, 2, "the house's two doors are the candidates")
local d = Arrow.pickDoor(r, { x = 1, y = 1 }, { x = 14, y = 6 }, nil, "TOWN")
eq(d.x, 15, "two hops in, the door nearest the player")
r = Arrow.route(maps, "TOWN", "HOUSE", nil, outside)
d = Arrow.pickDoor(r, { x = 6, y = 6 }, { x = 2, y = 2 }, nil, "TOWN")
eq(d.x, 15, "into the partner's map: the door that lands nearest them")
d = Arrow.pickDoor(r, { x = 1, y = 6 }, { x = 18, y = 2 }, nil, "TOWN")
eq(d.x, 3, "the other one when they stand by the other door")
local cells = { ["3,6"] = true }
d = Arrow.pickDoor(Arrow.route(maps, "TOWN", "HOUSE_2F", nil, outside),
                   { x = 1, y = 1 }, { x = 14, y = 6 }, cells, "TOWN")
eq(d.x, 3, "a door the player can walk to wins over a nearer one")
r = Arrow.route(maps, "HOUSE_2F", "ROUTE", "TOWN", outside)
eq(r.kind, "door", "indoors, a last-map exit leads out")
eq(r.doors[1].x, 7, "via the stairs")
r = Arrow.route(maps, "HOUSE_2F", "ROUTE", nil, outside)
eq(r.kind, "town", "no last map known: the TOWN MAP's direction")
r = Arrow.route(maps, "TOWN", "ISLAND", "ISLAND", outside)
eq(r.kind, "town", "a last-map exit is not followed once the search left the building")
check(Arrow.route(maps, "TOWN", "ISLAND", "ISLAND", outside) == r, "routes are cached")

-- placement
local at = Arrow.layout({ kind = "exact", x = 400, y = 72 }, { x = 80, y = 72 }, 160, 144)
eq(at.x, 160 - 8 - Arrow.EDGE, "off to the right: on the right edge")
eq(at.dir, "right", "pointing right")
at = Arrow.layout({ kind = "exact", x = -300, y = -300 }, { x = 80, y = 72 }, 160, 144)
eq(at.dir, "upleft", "up and left: a diagonal")
at = Arrow.layout({ kind = "door", x = 40, y = 4 }, { x = 80, y = 72 }, 160, 144)
eq(at.dir, "down", "a door on the screen: the arrow stands over it")
eq(at.y, Arrow.EDGE, "one in the top row stays on the screen")
eq(at.x, 36, "centred on it")
at = Arrow.layout({ kind = "town", dx = 0, dy = 3 }, { x = 80, y = 72 }, 160, 144)
eq(at.dir, "down", "a TOWN MAP direction")
eq(at.y, 144 - 8 - Arrow.EDGE, "on the bottom edge")
eq(Arrow.layout({ kind = "town", dx = 0, dy = 0 }, { x = 80, y = 72 }, 160, 144), nil,
   "the same TOWN MAP place: no arrow")

-- START > CO-OP, SELECT, the CO-OP menu -----------------------------------

local start = StartMenu.new(Game)
local row = labels(start)
check(row:find("OPTION,CO%-OP"), "CO-OP follows OPTION in START (" .. row .. ")")
Input:sourcePress("select", "test")
Input:step()
stack:update(1 / 60)
Input:sourceRelease("select", "test")
Input:step()
check(stack:top().coopMenu, "SELECT on the map opens the CO-OP menu")
eq(labels(stack:top()), "TOWN MAP,LEAVE SESSION,CANCEL", "its rows without a TOWN MAP")
stack:pop()
Game.save.inventory = Game.save.inventory or {}
Game.save.inventory.TOWN_MAP = 1
eq(labels(CoopMenu.new(Game)), "LEAVE SESSION,CANCEL", "with the item, no TOWN MAP row")
Game.save.inventory.TOWN_MAP = nil
local lines = CoopMenu.lines(Game, s, "10.0.0.5")
eq(lines[1], "FIX CO-OP", "the box names the campaign")
eq(lines[2], "IP 10.0.0.5", "the host shows its address")
eq(lines[3], "SAVED JUST NOW", "when the campaign was last saved (#13)")
eq(lines[4], "AUTOSAVE: ON", "and that it saves itself")
eq(lines[5], "", "a blank line under the heading")
eq(lines[6], "BLUE", "each partner")
eq(lines[7], " FIX TOWN", "and where they are")

-- TOWN MAP marks
local marks = Marks.marks({ FIX_TOWN = { x = 4, y = 4 }, FIX_ROUTE = { x = 4, y = 3 } })
eq(#marks, 1, "the TOWN MAP marks BLUE")
eq(marks[1].loc.x, 4, "at BLUE's place")
eq(marks[1].place, 2, "in BLUE's colour")
local drawn = 0
local realDraw = love.graphics.draw
love.graphics.draw = function(...) drawn = drawn + 1 return realDraw(...) end
Marks.draw({ game = Game, byMap = { FIX_TOWN = { x = 4, y = 4 } } },
           function(loc) return loc.x * 8 + 16, loc.y * 8 + 8 end)
Marks.draw({ game = Game, nestSpecies = "FIXMON_A", byMap = { FIX_TOWN = { x = 4, y = 4 } } },
           function(loc) return loc.x * 8 + 16, loc.y * 8 + 8 end)
love.graphics.draw = realDraw
eq(drawn, 1, "an icon on the TOWN MAP, none in the Pokédex's area view")

-- hold B to run -----------------------------------------------------------

Input:sourcePress("b", "test")
Input:step()
eq(ow.player:stepLength("left"), 8, "in a session, holding B runs at the bike's pace")
check(ow.player.running, "and the step is a run")
Game.save.onBike = true
eq(ow.player:stepLength("left"), ow.player.bikeStepFrames, "the bike keeps its own")
check(not ow.player.running, "riding is no run")
Game.save.onBike = nil
ow.player.surfing = true
eq(ow.player:stepLength("left"), 16, "surfing keeps its own")
ow.player.surfing = nil
Input:sourceRelease("b", "test")
Input:step()
eq(ow.player:stepLength("left"), 16, "without B, a walk")

-- this player's report: the cell a step heads for, how they travel
ow.player.moving, ow.player.targetX, ow.player.targetY, ow.player.running = true, 6, 6, true
local pos = Session.position(Game)
eq(pos.x, 6, "a step under way reports the cell it heads for")
eq(pos.travel, "run", "and that it is a run")
ow.player.moving, ow.player.targetX, ow.player.targetY, ow.player.running = false, nil, nil, false
step(2)
local hostView = blue:playerView(s.client.player)
eq(hostView and hostView.travel, "walk", "the others see how this player travels")

-- BLUE leaves: gone, with a notice --------------------------------------

blue:leave()
step(3)
eq(#partnerActors(), 0, "a partner who left is not drawn")
local texts = Notices.texts()
eq(texts[#texts], "BLUE left the session.", "a notice says BLUE left")
check(Notices.wrap("BLUE left the session.")[2] ~= nil, "a notice breaks into lines")
step(Notices.SHOW)
eq(#Notices.texts(), 0, "notices fade after a few seconds")

-- LEAVE SESSION: the session ends, the game goes back to the launcher ----

check(labels(StartMenu.new(Game)):find("CO%-OP"), "still in the session")
CoopMenu.leave(s)
eq(s.status, "ended", "LEAVE SESSION ends it")
eq(Session.tick(1 / 60, Game), "launcher", "and the game goes back to the launcher")
step(2)
check(not labels(StartMenu.new(Game)):find("CO%-OP"), "no CO-OP row after the session")
eq(ow.player.sprite.coopColors, nil, "this player's colour is gone again")

T.finish("presence")
