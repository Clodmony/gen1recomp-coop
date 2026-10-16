-- Friend battles and trades in the running game (#23, design A12.1 to
-- A12.6, A14.8, decision G31).  A solo game never gets here.
--
--   Friends.talk(game, ow, x, y)  -- OverworldState:interact (marked hook)
--   Friends.rows(game, items)     -- the CO-OP menu's BATTLE and TRADE rows
--   Friends.step(game)            -- Session:update, every joined frame
--
-- Inviting (A12.1): talking to a partner opens BATTLE / TRADE / CANCEL; the
-- CO-OP menu lists BATTLE <NAME> and TRADE <NAME> for each partner free to
-- meet (connected, past the opening, in no battle and no other meeting).
-- Either sends the invitation; "Invitation sent." says it went.  A player
-- in the opening, away from a co-op battle or already meeting someone
-- invites nobody.
--
-- Answering (A12.2): the invited player's question ("RED wants to
-- battle!", YES / NO) shows only at a rest point on the map with nothing
-- open; NO, B or 30 s without an answer decline.  The sender hears how it
-- went in a notice (declined, no answer, busy, left).
--
-- Meeting: once the host pairs the two, each window opens the battle
-- (src/coop/friends/FriendBattle.lua) or the trade screen
-- (src/coop/friends/TradeScreen.lua) at its next rest point, where the
-- player stands.  After a battle the team is healed and its EXP paid
-- (A12.5).

local Strings = require("src.core.Strings")
local Notices = require("src.coop.game.Notices")

local Friends = { started = {}, told = {}, sent = {}, prompt = nil, running = nil }

Friends.ANSWER = 30 -- seconds the invited player has to answer (A12.2)

-- seconds, for the 30 s answer (a test sets its own)
function Friends.clock()
  return love and love.timer and love.timer.getTime and love.timer.getTime() or os.clock()
end
local function clock() return Friends.clock() end

local function session()
  return require("src.coop.game.Presence").session()
end

local function client()
  local s = session()
  return s and s.client or nil
end

local function nameOf(c, id)
  for _, p in ipairs(c and c.state and c.state.players or {}) do
    if p.id == id then return p.name end
  end
  return "?"
end

-- a partner the last state shows free to meet
function Friends.partnerFree(p)
  return p.connected == true and not p.battle and not p.meeting and not p.opening
end

-- this player may invite and be met: past the opening, not away from a
-- co-op battle, no meeting running
function Friends.free()
  if Friends.running then return false end
  if require("src.coop.game.Opening").active() then return false end
  if next(require("src.coop.game.Battles").away) then return false end
  return true
end

-- a rest point on the map with nothing open (A12.2)
function Friends.atRest(game)
  local s = session()
  if not s then return false end
  if require("src.coop.game.SharedWorld").busy(game) ~= nil then return false end
  return s.window == nil or s.window:resting()
end

local KIND_TEXT = {
  battle = function(name) return Strings("%s wants\nto battle!", name) end,
  trade = function(name) return Strings("%s wants\nto trade!", name) end,
}

function Friends.invite(game, id, kind, name)
  local c = client()
  -- this player's own invitation still waits: say so, send nothing
  for _, inv in pairs(c and c.invites or {}) do
    if inv.from == c.player and not inv.answer then
      Notices.push(Strings("Waiting for %s...", nameOf(c, inv.to)))
      return
    end
  end
  local seq = c and c:invite(id, kind)
  if not seq then return end
  Friends.sent[seq] = name or nameOf(c, id)
  Notices.push(Strings("Invitation sent."))
end

-- the CO-OP menu's rows (A14.8)
function Friends.rows(game, items)
  if not Friends.free() then return end
  local Presence = require("src.coop.game.Presence")
  for _, p in ipairs(Presence.partners()) do
    if Friends.partnerFree(p) then
      items[#items + 1] = { label = Strings("BATTLE %s", p.name), onSelect = function()
        Friends.invite(game, p.id, "battle", p.name)
      end }
      items[#items + 1] = { label = Strings("TRADE %s", p.name), onSelect = function()
        Friends.invite(game, p.id, "trade", p.name)
      end }
    end
  end
end

-- the partner standing on cell (x, y) of this player's map, or nil
function Friends.partnerAt(ow, x, y)
  local Presence = require("src.coop.game.Presence")
  for id, a in pairs(Presence.actors) do
    if a.visible and a.map == ow.map.id and ((a.cellX == x and a.cellY == y)
        or (a.targetX == x and a.targetY == y)) then
      return id, a
    end
  end
  return nil
end

-- A on a partner (A12.1): BATTLE / TRADE / CANCEL.  True when the press
-- was the partner's.
function Friends.talk(game, ow, x, y)
  if not session() then return false end
  local id, a = Friends.partnerAt(ow, x, y)
  if not id then return false end
  local name = a.name or "?"
  local view
  for _, p in ipairs(require("src.coop.game.Presence").partners()) do
    if p.id == id then view = p end
  end
  if not (view and Friends.partnerFree(view)) or not Friends.free() then
    Notices.push(Strings("%s is busy.", name))
    return true
  end
  local Menu = require("src.ui.Menu")
  local menu
  local function close()
    if game.stack:top() == menu then game.stack:pop() end
  end
  menu = Menu.new(game, {
    { label = Strings("BATTLE"), onSelect = function() close(); Friends.invite(game, id, "battle", name) end },
    { label = Strings("TRADE"), onSelect = function() close(); Friends.invite(game, id, "trade", name) end },
    { label = Strings("CANCEL"), onSelect = close },
  }, { tx = 11, ty = 0, tw = 9 })
  menu.coopFriends = true
  game.stack:push(menu)
  return true
end

-- the invited player's question ------------------------------------------

local function closePrompt(game)
  local p = Friends.prompt
  if not p then return end
  Friends.prompt = nil
  -- the question and its YES/NO are all that stands over the map
  local ow = game.overworld
  local stack = game.stack
  while stack:top() and stack:top() ~= ow and p.open do
    local top = stack:pop()
    if top == p.box then break end
  end
end

local function ask(game, c, inv)
  local TextBox = require("src.render.TextBox")
  local p = { id = inv.id, at = clock(), open = true }
  Friends.prompt = p
  local name = nameOf(c, inv.from)
  p.box = TextBox.new(game, KIND_TEXT[inv.kind](name), nil, {
    choice = function(yes)
      p.open = false
      if Friends.prompt == p then Friends.prompt = nil end
      local now = client()
      if now then now:answerInvite(inv.id, yes) end
    end,
  })
  game.stack:push(p.box)
end

-- notices for how an invitation this player sent ended, and refusals
local ANSWER_TEXT = {
  declined = function(n) return Strings("%s declined.", n) end,
  timeout = function(n) return Strings("%s did not answer.", n) end,
  busy = function(n) return Strings("%s is busy.", n) end,
  left = function(n) return Strings("%s left.", n) end,
}
local REFUSAL_TEXT = {
  partner_busy = ANSWER_TEXT.busy, invite_pending = ANSWER_TEXT.busy,
  partner_away = function(n) return Strings("%s is away.", n) end,
}

local function answers(c)
  for id, inv in pairs(c.invites) do
    if inv.answer and not Friends.told[id] then
      Friends.told[id] = true
      if inv.from == c.player and ANSWER_TEXT[inv.answer] then
        Notices.push(ANSWER_TEXT[inv.answer](nameOf(c, inv.to)))
      end
    end
  end
  for i = (Friends.rejectionsSeen[c] or 0) + 1, #c.rejections do
    local r = c.rejections[i]
    local name = Friends.sent[r.seq]
    if name then
      Friends.sent[r.seq] = nil
      Notices.push((REFUSAL_TEXT[r.reason] or ANSWER_TEXT.busy)(name))
    end
  end
  Friends.rejectionsSeen[c] = #c.rejections
end
Friends.rejectionsSeen = setmetatable({}, { __mode = "k" })

-- the pairings ---------------------------------------------------------------

local function after(game, pair)
  return function(result, awards)
    Friends.running = nil
    local c = client()
    if c and result then c:pairEnd(pair.id, result) end
    if awards then
      local FriendBattle = require("src.coop.friends.FriendBattle")
      FriendBattle.heal(game)
      FriendBattle.giveExp(game, awards)
    end
  end
end

local function start(game, pair)
  Friends.started[pair.id] = true
  Friends.running = pair.id
  local opts = { client = client }
  if pair.kind == "battle" then
    opts.onEnd = after(game, pair)
    require("src.coop.friends.FriendBattle").start(game, pair, opts)
  else
    opts.onEnd = function() Friends.running = nil end
    -- the holdings so far reach the host before the trade (#17)
    local s = session()
    if s and s.window then s.window:flushHoldings(game.save) end
    require("src.coop.friends.TradeScreen").open(game, pair, opts)
  end
end

function Friends.step(game)
  local c = client()
  if not c then return end
  answers(c)
  -- the question for an invitation to this player (A12.2)
  local p = Friends.prompt
  if p then
    local inv = c.invites[p.id]
    if not inv or inv.answer then
      closePrompt(game) -- settled by the host (expired, the sender left)
    elseif clock() - p.at >= Friends.ANSWER then
      closePrompt(game)
      c:answerInvite(p.id, false) -- 30 s without an answer is a NO
    end
  elseif Friends.atRest(game) and Friends.free() then
    for id, inv in pairs(c.invites) do
      if inv.to == c.player and not inv.answer and not Friends.told[id] then
        Friends.told[id] = "asked"
        ask(game, c, inv)
        break
      end
    end
  end
  -- a pairing opens at the next rest point, where the player stands
  for id, pair in pairs(c.pairs) do
    if not Friends.started[id] then
      if pair.ended then
        Friends.started[id] = true
        c:pairEnd(id, "cancel")
      elseif pair.done then
        -- a trade the host committed for a window that never had its screen
        -- (started again): the world it opened has the swap already
        Friends.started[id] = true
        c:pairEnd(id, "done")
      elseif not Friends.running and Friends.atRest(game) then
        start(game, pair)
      end
    end
  end
end

return Friends
