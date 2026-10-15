-- What a co-op battle shows (#19, design A9), ROM-free: two windows' copies
-- over loopback (tests/coop/support/battle_harness.lua) with the drawing
-- calls caught.  Covered: the other window names who decides; a partner's
-- resting cursor suggests, the decider's menu marks it with a hollow ▷ and
-- an idle decider's box alternates with "<NAME> suggests"; "<NAME> joined
-- the battle!" in every copy; the party list is the roster six rows at a
-- time with the row's owner named; the party balls are the viewer's own
-- team; lines move on by themselves once the battle is decided; a ball
-- asks whom the catch is for.
--   luajit tests/coop/battle_view_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq
local H = require("tests.coop.support.battle_harness")
local Data = H.Data
local Pokemon = require("src.pokemon.Pokemon")
local BattleState = require("src.battle.BattleState")
local Replica = require("src.coop.battle.Replica")
local View = require("src.coop.battle.View")
local Font = require("src.render.Font")

-- what a draw call printed: text and glyph codes with their positions
local function capture(fn)
  local out = { texts = {}, codes = {} }
  local draw, drawCode = Font.draw, Font.drawCode
  Font.draw = function(text, x, y) out.texts[#out.texts + 1] = { text = text, x = x, y = y } end
  Font.drawCode = function(code, x, y) out.codes[#out.codes + 1] = { code = code, x = x, y = y } end
  local ok, err = pcall(fn)
  Font.draw, Font.drawCode = draw, drawCode
  assert(ok, err)
  return out
end
local function printed(out, text)
  for _, t in ipairs(out.texts) do if t.text == text then return t end end
  return nil
end
local function glyphAt(out, code, x, y)
  for _, c in ipairs(out.codes) do
    if c.code == code and c.x == x and c.y == y then return true end
  end
  return false
end

Data.moves.FIX_GROWL = Data.moves.FIX_GROWL or { id = "FIX_GROWL", index = 7, name = "FIX GROWL",
  type = "NORMAL", power = 0, accuracy = 100, pp = 40, effect = "ATTACK_DOWN1_EFFECT" }

local host, red, green = H.setup()
local clients = { red, green }
local function mons(n, species, level)
  local out = {}
  for i = 1, n do out[i] = Pokemon.new(Data, species, level) end
  return out
end
local redGame = H.newGame("RED", 1111, mons(4, "FIXMON_A", 20))
local greenGame = H.newGame("GREEN", 2222, mons(4, "FIXMON_C", 15))
local games = { redGame, greenGame }
redGame.expect, redGame.keepScreens, greenGame.keepScreens = 2, true, true
redGame.decide = function() return false end -- RED keeps the menu open
H.run(host, clients, {}, function() return red.status == "joined" and green.status == "joined" end, 10)

local joins = {}
local joinLine = View.joinLine
View.joinLine = function(b, pid)
  joins[#joins + 1] = { me = b.coop.me, pid = pid }
  return joinLine(b, pid)
end
local battle = H.openWild(red, redGame, "FIXMON_B", 30, function(mon)
  mon.moves = { { id = "FIX_GROWL", pp = 40 } }
end)
local id = H.bindOpener(host, red, redGame, battle, clients, games)
local gb = H.joinBattle(host, green, greenGame, id, clients, games)
View.joinLine = joinLine
H.run(host, clients, games, function()
  return Replica.question(battle) == "menu" and Replica.question(gb) == "menu"
end, 3000)

-- the join line, in every copy (A9.11) -------------------------------------------
local seenIn = {}
for _, j in ipairs(joins) do
  if j.pid == green.player then seenIn[j.me] = true end
end
check(seenIn[red.player], "RED's copy says GREEN joined the battle")
check(seenIn[green.player], "and GREEN's copy too (caught up without a screen)")

-- who decides (A9.2) --------------------------------------------------------------
eq(Replica.owner(gb, gb.player.mon), red.player, "RED's Pokémon is out")
local out = capture(function() View.draw(gb) end)
check(printed(out, "RED"), "GREEN's box names RED")
check(printed(out, "decides"), "who decides")
out = capture(function() View.draw(battle) end)
check(not printed(out, "decides"), "RED's own box does not")

-- GREEN suggests by resting the cursor (A9.4) -------------------------------------------
greenGame.taps.a = true -- FIGHT: GREEN walks into the move list
H.frame(host, clients, games)
eq(gb.phase, "moveSelect", "GREEN walks the same menus")
H.run(host, clients, games, function()
  local rec = red.battles[id]
  return rec and rec.suggestions and #rec.suggestions > 0
end, 200)
local rec = red.battles[id]
eq(rec.suggestions[1] and rec.suggestions[1].by, green.player, "the row GREEN's cursor rests on is suggested")
eq(rec.suggestions[1] and rec.suggestions[1].cmd.kind, "move", "a move")
eq(rec.suggestions[1] and rec.suggestions[1].cmd.slot, 1, "the first")
eq(#host.battles[id].inputs, 2, "a suggestion is no command: nothing happened")

-- RED's menu marks it (A9.3) -------------------------------------------------------
battle.menuIndex = 2 -- RED's cursor on PKMN
out = capture(function() View.draw(battle) end)
check(glyphAt(out, 0xEC, 72, 112), "a hollow ▷ on FIGHT, the entry GREEN suggests")
battle.phase, battle.moveIndex = "moveSelect", 2
out = capture(function() View.draw(battle) end)
check(glyphAt(out, 0xEC, 40, 104), "and on the exact move row")
battle.phase, battle.menuIndex = "menu", 2
battle.coop.lastPress, battle.frame = 0, View.ALTERNATE * 3 + 1
out = capture(function() View.draw(battle) end)
check(printed(out, "GREEN suggests"), "an idle decider's box says who suggests")
check(printed(out, Data.moves[battle.player.curMoves[1].id].name), "and what")
battle.frame = View.ALTERNATE * 2 + 1
out = capture(function() View.draw(battle) end)
check(not printed(out, "GREEN suggests"), "alternating with the menu")

-- the roster, six rows at a time (A9.1) -----------------------------------------------
eq(#battle.coop.roster, 8, "eight Pokémon in the roster")
local picked
local menu = View.openRoster(battle, { onPick = function(i) picked = i end })
eq(#menu.party, 6, "the first six rows")
out = capture(function() menu:draw() end)
check(printed(out, " RED 1/2 "), "the box names the row's owner and the page")
menu.index = 6
redGame.taps.down = true
menu:update(1 / 60)
redGame.taps = {}
eq(#menu.party, 2, "down past the sixth row: the next page")
eq(menu.party[1], battle.coop.roster[7], "rows seven and eight")
out = capture(function() menu:draw() end)
check(printed(out, " GREEN 2/2 "), "GREEN's Pokémon, named")
menu.onSwitch(menu.party[1], nil)
eq(picked, 7, "picking it answers with its roster row")
redGame.stack:pop()

-- the party balls are this player's own team (A9.10) -----------------------------------
local drawn
local base = BattleState.drawBallRow
BattleState.drawBallRow = function(_, party) drawn = party end
battle:drawBallRow(battle.coop.roster, 88, 80, 8)
BattleState.drawBallRow = base
eq(drawn and #drawn, 4, "RED's ball row shows RED's four")
for _, m in ipairs(drawn or {}) do eq(battle.coop.owners[m], red.player, "each RED's") end

-- whom the catch is for (A7.6) -------------------------------------------------------------
local catcher
View.askCatcher(battle, "FIX_BALL", function(pid) catcher = pid end)
local list = redGame.stack:top()
eq(list.items and #list.items, 2, "a ball asks whom the catch is for, each player once")
eq(list.items[2].label, "GREEN", "GREEN among them")
list.items[2].onSelect()
eq(catcher, green.player, "the pick names the catcher")
redGame.stack:pop()

-- lines move on by themselves once the battle is decided (A9.6) --------------------------
local b2 = setmetatable({ coop = {}, result = "win", phase = "messages", msgWaiting = true }, {})
local moved
for i = 1, View.AUTO_LINE do
  if View.autoLines(b2) then moved = i end
end
eq(moved, View.AUTO_LINE, "a waiting line moves on after a pause")
b2.result = nil
moved = nil
for _ = 1, View.AUTO_LINE * 2 do if View.autoLines(b2) then moved = true end end
eq(moved, nil, "but not before the battle is decided")

T.finish()
