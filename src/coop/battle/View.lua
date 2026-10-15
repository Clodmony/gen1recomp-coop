-- What a co-op battle shows in a window (#19, design A9): the cartridge's
-- own battle screen and menus, fed by the window's lockstep copy
-- (Replica.lua), with the co-op parts on top:
--
--   * who decides (A9.2): the other players' text box names the player the
--     battle asks, "<NAME> / decides", left of the menu;
--   * suggestions (A8.8, A9.3, A9.4): a player not asked walks the same
--     menus; the row their cursor rests on is suggested to the decider, and
--     A suggests it again rather than acting.  Every window marks a
--     partner's suggestion with a hollow ▷ on the main menu's entry and on
--     the exact row of the move list and the party, with the partner's
--     initial when three or more players are in; an idle decider's box
--     alternates with "<NAME> suggests / <choice>";
--   * the party list is the allied roster, six rows at a time, and its text
--     box names the owner of the row under the cursor (A9.1);
--   * the party balls under the HUD are this player's own team, not the
--     whole roster (A9.10);
--   * "<NAME> joined the battle!" when a team comes in (A9.11);
--   * after the battle is decided, every line moves on by itself, so the
--     battle closes after its last line without a press (A9.6);
--   * a ball asks whom the catch is for, each player with room once (A7.6,
--     A9.1).

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")

local View = {}

View.REST = 20       -- frames the cursor rests on a row before it is suggested
View.ALTERNATE = 90  -- frames each half of the decider's alternating box shows
View.IDLE = 120      -- frames without a press before the decider counts as idle
View.AUTO_LINE = 90  -- frames a line waits once the battle is decided

local function engine() return require("src.battle.BattleState") end

local function Replica() return require("src.coop.battle.Replica") end

function View.name(b, pid)
  return b.coop.names[pid] or "?"
end

-- the main menu entry a suggestion falls under: 1 FIGHT, 2 PKMN, 3 ITEM, 4 RUN
local ENTRY = { move = 1, fight = 1, struggle = 1, switch = 2, item = 3, ball = 3, run = 4 }
View.ENTRY = ENTRY

-- the words for a suggestion in the decider's box
function View.choiceText(b, cmd)
  if not cmd then return "" end
  local k = cmd.kind
  if k == "move" and cmd.slot and b.player then
    local mv = b.player.curMoves[cmd.slot]
    local def = mv and b.data.moves[mv.id]
    return def and def.name or Strings("FIGHT", "battle")
  elseif k == "fight" or k == "move" or k == "struggle" then
    return Strings("FIGHT", "battle")
  elseif k == "switch" or k == "replace" then
    local mon = cmd.index and b.coop.roster[cmd.index]
    if mon then return mon.nickname or b.data.pokemon[mon.species].name end
    return "<PK><MN>"
  elseif k == "item" or k == "ball" then
    local def = cmd.item and b.data.items[cmd.item]
    return def and def.name or Strings("ITEM", "battle")
  elseif k == "run" then
    return Strings("RUN", "battle")
  end
  return ""
end

-- the record's suggestions for the current question
function View.suggestions(b)
  local c = b.coop
  local rec = c.client and c.client.battles[c.id]
  if not rec or rec.rev ~= c.applied then return {} end
  return rec.suggestions or {}
end

-- a player not asked: what their cursor rests on goes to the decider
function View.suggest(b, cmd)
  local c = b.coop
  if not c.client then return end
  local key = cmd and (cmd.kind .. tostring(cmd.slot or cmd.index or cmd.item or "")) or "-"
  if c.suggested == c.applied .. key then return end
  c.suggested = c.applied .. key
  c.client:battleSuggest(c.id, c.applied, cmd)
end

-- the row the not-asked player's cursor stands on, as a suggestion
function View.cursorCmd(b)
  if b.phase == "moveSelect" then
    return { kind = "move", slot = b.moveIndex }
  end
  local kinds = { "fight", "switch", "item", "run" }
  local k = kinds[b.menuIndex or 1]
  return k and { kind = k } or nil
end

-- every frame of a player not asked at the menu: their cursor moves as in
-- the cartridge, a row it rests on is suggested, and A suggests again
function View.follow(b, dt)
  local c = b.coop
  local input = b.game.input
  local before = b.phase .. (b.menuIndex or 0) .. (b.moveIndex or 0)
  if b.phase == "menu" then
    local col = (b.menuIndex - 1) % 2
    local row = math.floor((b.menuIndex - 1) / 2)
    if input:wasPressed("left") then col = 0 elseif input:wasPressed("right") then col = 1
    elseif input:wasPressed("up") then row = 0 elseif input:wasPressed("down") then row = 1 end
    b.menuIndex = row * 2 + col + 1
    if input:wasPressed("a") then
      if b.menuIndex == 1 and b.player then
        b.phase = "moveSelect"
        b.moveIndex = math.min(b.moveIndex or 1, #b.player.curMoves)
      elseif b.menuIndex == 2 then
        View.openRoster(b, { suggest = true })
      elseif b.menuIndex == 4 and c.me ~= c.opener then
        -- RUN: a player whose world did not open the battle may leave it
        -- (design A9.5, A11.1)
        return Replica().askLeave(b)
      end
      View.again(b)
    end
  elseif b.phase == "moveSelect" then
    local n = b.player and #b.player.curMoves or 1
    if input:wasPressed("up") then b.moveIndex = b.moveIndex > 1 and b.moveIndex - 1 or n
    elseif input:wasPressed("down") then b.moveIndex = b.moveIndex < n and b.moveIndex + 1 or 1
    elseif input:wasPressed("b") then b.phase = "menu"
    elseif input:wasPressed("a") then View.again(b) end
  end
  local now = b.phase .. (b.menuIndex or 0) .. (b.moveIndex or 0)
  if now ~= before then c.restFrames = 0 else c.restFrames = (c.restFrames or 0) + 1 end
  if c.restFrames == View.REST or (c.suggested == nil and c.restFrames >= View.REST) then
    View.suggest(b, View.cursorCmd(b))
  end
end

-- A suggests the row again, at most once every AGAIN frames (a held or
-- mashed A must not flood the link)
View.AGAIN = 30
function View.again(b)
  local c = b.coop
  local now = b.frame or 0
  if c.againAt and now - c.againAt < View.AGAIN then return end
  c.againAt = now
  c.suggested = nil
end

-- the decider's own presses (for the idle alternation)
function View.noteInput(b)
  local input = b.game.input
  for _, k in ipairs({ "a", "b", "up", "down", "left", "right", "start", "select" }) do
    if input:wasPressed(k) then b.coop.lastPress = b.frame or 0 return end
  end
end

-- the roster in the party menu, six rows at a time; the text box names the
-- owner of the row under the cursor.  opts: forceSwitch, onPick(index),
-- suggest (a player not asked: a pick is a suggestion)
function View.openRoster(b, opts)
  local c = b.coop
  local roster = c.roster
  local page = 1
  local function slice()
    local out = {}
    for i = (page - 1) * 6 + 1, math.min(#roster, page * 6) do out[#out + 1] = roster[i] end
    return out
  end
  local pages = math.max(1, math.ceil(#roster / 6))
  local current = b.player and b.player.mon
  for i, m in ipairs(roster) do if m == current then page = math.ceil(i / 6) end end
  local menu
  menu = b:buildScreen("PartyMenu", {
    battle = b, party = slice(), keepOpen = true, forceSwitch = opts.forceSwitch,
    onSwitch = function(mon, m)
      local refusal
      if opts.forceSwitch then
        if mon.hp <= 0 then refusal = b:romText("_NoWillText", "There's no will\nto fight!") end
      elseif mon == current then
        refusal = b:romText("_AlreadyOutText", "%s is\nalready out!", b.player.name)
      elseif mon.hp <= 0 then
        refusal = b:romText("_NoWillText", "There's no will\nto fight!")
      end
      if refusal and not opts.suggest then
        if m then m:refuse(refusal) end
        return
      end
      if m then m:close() end
      local index = Replica().index(b, mon)
      if opts.suggest then
        View.suggest(b, { kind = opts.forceSwitch and "replace" or "switch", index = index })
      elseif opts.onPick then
        opts.onPick(index)
      end
    end,
  })
  menu.index = 1
  for i, m in ipairs(menu.party) do if m == current then menu.index = i end end
  local baseUpdate, baseDraw = menu.update, menu.draw
  menu.update = function(self, dt)
    local input = self.game.input
    if not self.submenu and not self.swapFrom and pages > 1 then
      if input:wasPressed("down") and self.index == #self.party then
        page = page % pages + 1
        self.party, self.index = slice(), 1
        return
      elseif input:wasPressed("up") and self.index == 1 then
        page = (page - 2) % pages + 1
        self.party = slice()
        self.index = #self.party
        return
      end
    end
    return baseUpdate(self, dt)
  end
  menu.draw = function(self)
    baseDraw(self)
    local mon = self.party[self.index]
    local owner = mon and c.owners[mon]
    local label = owner and View.name(b, owner) or ""
    if pages > 1 then label = label .. (" %d/%d"):format(page, pages) end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 8, 96, (#label + 2) * 8, 8)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(" " .. label .. " ", 8, 96)
    -- partners' suggestions on their rows
    for _, s in ipairs(View.suggestions(b)) do
      local cmd = s.cmd
      if cmd.index and (cmd.kind == "switch" or cmd.kind == "replace") then
        for i, m in ipairs(self.party) do
          if m == roster[cmd.index] and i ~= self.index then
            Font.drawCode(0xEC, 0, (i - 1) * 16 + 8)
          end
        end
      end
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
  b.game.stack:push(menu)
  return menu
end

-- the name list a ball asks: whom the catch is for, each player in the
-- battle with room once (A7.6); a lone one is named without a list
function View.askCatcher(b, ball, done)
  local c = b.coop
  local items = {}
  local with = Replica().withRoom(b)
  for _, pid in ipairs(with) do
    items[#items + 1] = { label = View.name(b, pid), onSelect = function() done(pid) end }
  end
  if #items == 0 then return done(c.me) end
  if #items == 1 then return done(with[1]) end
  local Menu = require("src.ui.Menu")
  local m = Menu.new(b.game, items, { tx = 0, ty = 0, tw = 12, th = #items * 2 + 2,
                                      onCancel = function() end })
  b.game.stack:push(m)
end

-- drawing ---------------------------------------------------------------

local function text(s, x, y)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(s, x, y)
end

local function clearLeft()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 8, 104, 56, 32)
end

-- after BattleState:draw: who decides, the suggestion marks, the
-- alternating box
function View.draw(b)
  local c = b.coop
  local R = Replica()
  local kind, by, owner = R.decider(b)
  if not kind or b.phase == "messages" then return end
  if by and owner and by ~= owner then
    -- a stand-in decides for an owner who is away: the view names both
    -- (design A11.6)
    local label = " " .. Strings("FOR %s", View.name(b, owner)) .. " "
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 8, 96, #label * 8, 8)
    text(label, 8, 96)
  end
  if not by then
    -- the owner dropped: the battle waits for them (design A11.5)
    clearLeft()
    text(View.name(b, owner), 8, 112)
    text(Strings("is away"), 8, 128)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  local mine = by == c.me
  local partners = 0
  for _ in pairs(c.names) do partners = partners + 1 end
  local marks = View.suggestions(b)
  if (kind == "menu") and (b.phase == "menu" or b.phase == "moveSelect") then
    if not mine then
      clearLeft()
      text(View.name(b, by), 8, 112)
      text(Strings("decides"), 8, 128)
    end
    -- the marks: a hollow ▷ on the entry and on the exact move row
    for _, s in ipairs(marks) do
      local entry = ENTRY[s.cmd.kind]
      local initial = partners >= 3 and View.name(b, s.by):sub(1, 1) or nil
      if b.phase == "menu" and entry and entry ~= b.menuIndex then
        local de = require("src.coop.game.German").layoutFor("battleMenu")
        local lx, rx = 80, 128
        if de then lx, rx = de.textX * 8, (de.rightCursorX + 1) * 8 end
        local col = (entry - 1) % 2
        local row = math.floor((entry - 1) / 2)
        local x = col == 0 and lx - 8 or rx - 8
        love.graphics.setColor(0, 0, 0, 1)
        Font.drawCode(0xEC, x, 112 + row * 16)
        if initial then Font.draw(initial, x, 104 + row * 16) end
      elseif b.phase == "moveSelect" and s.cmd.kind == "move" and s.cmd.slot
             and s.cmd.slot ~= b.moveIndex then
        love.graphics.setColor(0, 0, 0, 1)
        Font.drawCode(0xEC, 40, 96 + s.cmd.slot * 8)
        if initial then Font.draw(initial, 32, 96 + s.cmd.slot * 8) end
      end
    end
    -- the idle decider: the box alternates with "<NAME> suggests"
    if mine and #marks > 0 and b.phase == "menu"
       and (b.frame or 0) - (c.lastPress or 0) >= View.IDLE
       and math.floor((b.frame or 0) / View.ALTERNATE) % 2 == 1 then
      local s = marks[1]
      Font.drawBox(0, 12, 20, 6)
      text(Strings("%s suggests", View.name(b, s.by)), 8, 112)
      text(View.choiceText(b, s.cmd), 8, 128)
    end
  elseif not mine and kind ~= "menu" then
    -- a replacement, a move to learn, MIMIC or a YES/NO of another player
    if b.phase == "menu" then
      clearLeft()
      text(View.name(b, by), 8, 112)
      text(Strings("decides"), 8, 128)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- TAKE OVER (design A11.6): when the host offers it, a present player who
-- is not the owner is asked once, YES/NO
function View.offerTakeover(b)
  local c = b.coop
  local rec = c.client and c.client.battles[c.id]
  local owner = rec and rec.offer
  if not owner or owner == c.me or c.away then return end
  if c.offerAsked == owner .. ":" .. tostring(rec.rev) then return end
  c.offerAsked = owner .. ":" .. tostring(rec.rev)
  local TextBox = require("src.render.TextBox")
  c.real.stack:push(TextBox.new(c.real,
    Strings("%s is away.\nTAKE OVER?", View.name(b, owner)), nil, {
      defaultNo = true,
      choice = function(yes)
        if yes and c.client then c.client:battleTakeover(c.id, owner) end
      end,
    }))
end

-- the one line a player away from their battle gets when it ends (A11.3)
function View.endLine(b, result)
  local foe = b.enemy and b.enemy.name or "?"
  if b.kind == "trainer" and b.trainer then foe = b.trainer.name end
  if result == "win" then return Strings("The battle against %s was won.", foe) end
  if result == "lose" then return Strings("The battle against %s was lost.", foe) end
  if result == "caught" then return Strings("%s was caught.", foe) end
  return Strings("The battle against %s is over.", foe)
end

-- the party balls: this player's own team (A9.10)
function View.ownTeam(b)
  local c = b.coop
  local out = {}
  for _, mon in ipairs(c.roster) do
    if c.owners[mon] == c.me and #out < 6 then out[#out + 1] = mon end
  end
  return out
end

-- once the battle is decided, a line waiting for a press moves on by
-- itself after AUTO_LINE frames (A9.6)
function View.autoLines(b)
  local c = b.coop
  if not b.result or b.phase ~= "messages" then c.lineWait = 0 return false end
  if b.msgWaiting or b.msgPrompt then
    c.lineWait = (c.lineWait or 0) + 1
    if c.lineWait >= View.AUTO_LINE then
      c.lineWait = 0
      return true
    end
  else
    c.lineWait = 0
  end
  return false
end

-- the input a co-op copy reads: the window's, plus the self-moving lines
function View.input(b, real)
  return setmetatable({
    wasPressed = function(_, k)
      if k == "a" and b.coop.autoA then return true end
      return real:wasPressed(k)
    end,
  }, { __index = real })
end

-- the line for a team that came in (A9.11)
function View.joinLine(b, pid)
  b:say(Strings("%s joined\nthe battle!", View.name(b, pid)))
end

return View
