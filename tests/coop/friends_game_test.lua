-- Friend battles and trades in the running game (#23, design A12.1,
-- A12.2, A14.8), ROM-free: the fixture overworld runs headless with this
-- device hosting a session in-process; BLUE is a partner on the loopback
-- hub whose answers this test sends.  Covered: nothing in a solo game; A on
-- the partner opens BATTLE / TRADE / CANCEL and BATTLE invites them
-- ("Invitation sent."); the sender hears a NO; a busy partner is said so;
-- the CO-OP menu's BATTLE and TRADE rows invite too, and a partner meeting
-- someone shows IN A BATTLE or TRADING and has no rows; an invitation to
-- this player waits for a rest point on the map with nothing open; B
-- declines it, 30 s without an answer decline it, an invitation the host
-- settled closes it; YES pairs the two and the battle's waiting box opens
-- where the player stands; B there calls it off for both.
--   luajit tests/coop/friends_game_test.lua

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
require("src.core.Logger").warn = function() end

local Identity = require("src.coop.session.Identity")
local Session  = require("src.coop.session.Session")
local Client   = require("src.coop.session.Client")
local Presence = require("src.coop.game.Presence")
local Notices  = require("src.coop.game.Notices")
local CoopMenu = require("src.coop.game.CoopMenu")
local Friends  = require("src.coop.game.Friends")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.save.flags.EVENT_GOT_STARTER = true -- past the opening (#22)
Game.save.player.name, Game.save.player.id = "RED", 1111
Game.save.party = { Pokemon.new(Data, "FIXMON_A", 20) }
local stack = Game.stack
stack:push(OW, "FIX_TOWN", 5, 6, "down")
local ow = stack:top()
Game.overworld = ow

local now = 0
Friends.clock = function() return now end

local SHA = ("ab"):rep(20)
local function memoryStore()
  local text
  return { read = function() return text end, write = function(t) text = t end }
end

local blue
local function step(n)
  for _ = 1, n or 1 do
    now = now + 1 / 60
    Input:step()
    local s = Session.current
    if s then s:update(1 / 60, Game) end
    if blue then blue:update() end
    stack:update(1 / 60)
    Presence.step(Game)
  end
end

local function press(key)
  Input:sourcePress(key, "test")
  step(1)
  Input:sourceRelease(key, "test")
  step(1)
end

local function labels(menu)
  local out = {}
  for i, it in ipairs(menu.items) do out[i] = it.label end
  return table.concat(out, ",")
end

local function lastNotice()
  local t = Notices.texts()
  return t[#t]
end

local function openInvite(c)
  for id, inv in pairs(c.invites) do if not inv.answer then return inv, id end end
end

-- solo -----------------------------------------------------------------------------
eq(Friends.talk(Game, ow, 5, 7), false, "solo: A talks to nobody new")
local soloItems = {}
Friends.rows(Game, soloItems)
eq(#soloItems, 0, "solo: no BATTLE or TRADE rows")

-- a session: BLUE stands below RED ---------------------------------------------------
local s = Session.startHost({
  campaign = { id = "c0001", title = "Fix co-op" },
  cartridge = { game = "red", sha1 = SHA }, name = "HOST",
  listen = false, beacon = false, log = false,
  identity = Identity.load(memoryStore()), clock = function() return now end,
})
step(3)
blue = Client.new(s.hub:dial(), { name = "BLUE", game = "red", sha1 = SHA, device = "b1", seat = 1 })
blue:join()
step(3)
blue:sendOpening(true) -- past the opening (#22)
blue:move("FIX_TOWN", 5, 7, "down", true, "walk")
step(40)
local me = s.client.player

-- A on BLUE: BATTLE / TRADE / CANCEL (A12.1) ------------------------------------------
do
  press("a")
  local menu = stack:top()
  check(menu and menu.coopFriends, "A on BLUE opens the partner menu")
  eq(labels(menu), "BATTLE,TRADE,CANCEL", "BATTLE / TRADE / CANCEL")
  menu.items[1].onSelect()
  step(3)
  eq(stack:top(), ow, "the menu closes")
  eq(lastNotice(), "Invitation sent.", "the invitation went")
  local inv, id = openInvite(blue)
  check(inv ~= nil and inv.from == me and inv.kind == "battle", "BLUE is invited to battle")
  blue:answerInvite(id, false)
  step(3)
  eq(lastNotice(), "BLUE declined.", "RED hears the NO")

  -- CANCEL sends nothing
  press("a")
  stack:top().items[3].onSelect()
  step(3)
  eq(stack:top(), ow, "CANCEL closes the menu")
  eq(openInvite(blue), nil, "and invites nobody")
end

-- the CO-OP menu's rows (A14.8) ---------------------------------------------------------
do
  local menu = CoopMenu.new(Game)
  local text = labels(menu)
  check(text:find("BATTLE BLUE,TRADE BLUE", 1, true), "the CO-OP menu has BATTLE BLUE and TRADE BLUE")
  for _, it in ipairs(menu.items) do
    if it.label == "TRADE BLUE" then it.onSelect() end
  end
  step(3)
  local inv, id = openInvite(blue)
  check(inv ~= nil and inv.kind == "trade", "TRADE BLUE invites BLUE to trade")
  -- asking again while it waits says so, and sends nothing (found in the
  -- integrated build's live run: it said "BLUE is busy.")
  for _, it in ipairs(CoopMenu.new(Game).items) do
    if it.label == "TRADE BLUE" then it.onSelect() end
  end
  step(3)
  eq(lastNotice(), "Waiting for BLUE...", "a second ask while one waits says so")
  local n = 0
  for _, i in pairs(blue.invites) do if not i.answer then n = n + 1 end end
  eq(n, 1, "and no second invitation went")
  -- the host's 60 s pass (A12.2)
  now = now + 61
  step(3)
  eq(blue.invites[id].answer, "timeout", "the host expires it")
  eq(lastNotice(), "BLUE did not answer.", "and RED hears so")
end

-- an invitation to RED: only at a rest point with nothing open (A12.2) -----------------
local function blueInvites(kind)
  blue:invite(me, kind)
  step(2)
end
do
  require("src.ui.Screens").push(Game, "StartMenu")
  blueInvites("trade")
  step(60)
  eq(Friends.prompt, nil, "not while the START menu is open")
  stack:pop()
  step(40)
  check(Friends.prompt ~= nil and stack:top() == Friends.prompt.box,
        "back on the map: the question shows")
  -- the text, then YES/NO; B there says NO
  for _ = 1, 200 do
    if stack:top().onChoose then break end
    press("a")
  end
  check(stack:top().onChoose ~= nil, "YES / NO")
  eq(stack:top().index, 1, "on YES")
  press("b")
  step(30)
  local answered
  for _, inv in pairs(blue.invites) do if inv.kind == "trade" and inv.answer == "declined" then answered = true end end
  check(answered, "B declines")
  eq(stack:top(), ow, "the question is gone")

  -- 30 s without an answer decline
  blueInvites("battle")
  step(40)
  check(Friends.prompt ~= nil, "asked again")
  now = now + Friends.ANSWER + 1
  step(3)
  eq(Friends.prompt, nil, "30 s: the question closes")
  local declined
  for _, inv in pairs(blue.invites) do if inv.kind == "battle" and inv.answer == "declined" then declined = true end end
  check(declined, "and says NO")
  eq(stack:top(), ow, "back on the map")
end

-- YES: the battle's waiting box opens where RED stands; B calls it off --------------
do
  blueInvites("battle")
  step(40)
  check(Friends.prompt ~= nil, "asked")
  local inv, id = openInvite(blue)
  -- the player says YES (the prompt's choice)
  Friends.prompt.box.choice(true)
  stack:pop()
  step(60)
  local pid
  for k, p in pairs(blue.pairs) do if not p.ended then pid = k end end
  check(pid ~= nil, "YES pairs RED and BLUE")
  local top = stack:top()
  check(top and top.pair and top.pair.id == pid, "RED's window opens the battle's waiting box")
  eq(top.pair.role, "guest", "RED was invited: the link battle's guest side")
  local blueView
  for _, p in ipairs(s.client.state.players) do if p.id == blue.player then blueView = p end end
  eq(blueView.meeting, "battle", "BLUE meets RED for a battle")
  local lines = table.concat(CoopMenu.lines(Game, s), "|")
  check(lines:find("IN A BATTLE", 1, true), "the CO-OP box says BLUE is IN A BATTLE")
  local items = {}
  Friends.rows(Game, items)
  eq(#items, 0, "no BATTLE or TRADE rows while meeting")
  check(#(blue.relay[pid] and blue.relay[pid].list or {}) >= 2, "RED's link battle sent its hello and party")
  press("b")
  step(5)
  eq(stack:top(), ow, "B on the waiting box: back on the map")
  eq(blue.pairs[pid].ended, "left", "and BLUE hears it is off")
end

-- a busy partner is said so --------------------------------------------------------
do
  local mon = { species = "FIXMON_B", level = 5, hp = 20, moves = { { id = "FIX_TACKLE", pp = 35 } } }
  blue:battleOpen({ kind = "wild", enemy = { mon }, map = "FIX_TOWN", foe = "FIXMON B" }, { mon }, 2222, false)
  step(5)
  press("a")
  eq(stack:top(), ow, "A on a partner in a battle opens nothing")
  eq(lastNotice(), "BLUE is busy.", "it says BLUE is busy")
  local items = {}
  Friends.rows(Game, items)
  eq(#items, 0, "and the CO-OP menu has no rows for BLUE")
end

T.finish()
