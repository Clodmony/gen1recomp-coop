-- Co-op battles in the running game (#18, design A8, decision G24): the
-- world's battles become co-op battles, and a player joins a partner's
-- from the CO-OP menu.  A solo game never gets here.
--
--   Battles.take(game, battle)   -- OverworldState:pushBattle (marked hook)
--   Battles.joinRows(game, items, again) -- the CO-OP menu's JOIN rows
--
-- Opening (design A8.2): a wild or trainer battle the window's own world
-- opens (grass, a trainer's sight, a script, a static Pokémon) is sent to
-- the host as the battle's opening with this player's team; the world
-- keeps its trigger, its script branches and its `onFinish` (trainer
-- flags, whiteout).  The battle waits on the transition's last frame for
-- the host's record, then becomes the co-op copy (Replica.make).  A
-- refusal, or no link (A8.22), and it is fought in the world alone, as
-- the cartridge does.  Battles that stay in the window and cannot be
-- joined (A8.19): the Safari Zone, a GHOST without the SILPH SCOPE, the
-- old man's demo, and the starter rival in Oak's lab (the opening, #22).
--
-- Joining (design A8.3): JOIN <NAME> in the CO-OP menu sends this player's
-- team; the world stands still under a "joining" box until the host puts
-- the team in (at the battle's next move question), then the copy is
-- built from the record, catches up without a screen (no intro, A9.8) and
-- comes in behind the battle transition.  The return point is where the
-- player stood: their world never moved.
--
-- The end (design A8.14 to A8.17): the copy writes this player's Pokémon
-- back and pays the prize; a loss whites out the joiner here, as the
-- opener's world does in its own onFinish.

local Strings = require("src.core.Strings")
local Replica = require("src.coop.battle.Replica")

local Battles = {}

Battles.WAIT = 10 -- seconds the opener waits for the host before fighting alone

local function session()
  return require("src.coop.game.Presence").session()
end

local function clock()
  return love and love.timer and love.timer.getTime and love.timer.getTime() or os.clock()
end

-- a battle the host runs and partners may join (design A8.2, A8.19)
function Battles.joinable(battle)
  if not battle or battle.coop or battle.coopPending or battle.dead then return false end
  if battle.kind ~= "wild" and battle.kind ~= "trainer" then return false end
  if battle.safari or battle.ghost or battle.demo or battle.oakDemo then return false end
  if battle.kind == "trainer" and battle.oppClass == "OPP_RIVAL1"
     and require("src.battle.BattleState").isOaksLabStarterRival(battle) then
    return false
  end
  return true
end

-- what the world prepared, as the host's opening
function Battles.opening(game, battle)
  local ow = game.overworld
  local open = {
    kind = battle.kind,
    map = (ow and ow.map and ow.map.id) or (game.save.player and game.save.player.map) or "UNKNOWN",
  }
  if battle.kind == "trainer" then
    local enemy = {}
    for i, mon in ipairs(battle.enemyParty or {}) do enemy[i] = Replica.pack(mon) end
    open.enemy = enemy
    open.trainer = { class = battle.oppClass, index = battle.partyIndex or 1,
                     rival = game.save.player and game.save.player.rival }
    open.foe = battle.trainer and tostring(battle.trainer.name):sub(1, 20)
  else
    open.enemy = { Replica.pack(battle.enemy.mon) }
    open.foe = battle.enemy and tostring(battle.enemy.name):sub(1, 20)
  end
  return open
end

local function teamOf(game)
  local live = {}
  for i, mon in ipairs(game.save.party) do
    if i > 6 then break end
    live[i] = mon
  end
  local inv = game.save.inventory or {}
  return Replica.packTeam(live), live, game.save.player and game.save.player.id,
         (inv.EXP_ALL or 0) > 0
end

-- the end in this window: the record is dropped; a joiner who lost whites
-- out here (the opener's world does it in its own onFinish)
local function onEnd(game, joiner)
  return function(b, result)
    local c = b.coop
    if c.client then c.client:dropBattle(c.id) end
    if joiner and result == "lose" then
      local ow = game.overworld
      if ow and ow.afterBattle then ow:afterBattle("lose", b) end
    end
  end
end

-- the opener's battle becomes the co-op copy of the host's record
local function bind(game, battle, rec, p)
  battle.coopPending = nil
  battle.draw = nil
  Replica.make(battle, rec, { client = p.client, id = rec.id, me = p.me, real = game,
                              live = p.live, onEnd = onEnd(game, false) })
  if p.entered then battle:enter() end
end

-- no host battle: the world's own, alone (design A8.22)
local function solo(battle, p)
  battle.coopPending = nil
  battle.enter, battle.update, battle.draw = nil, nil, nil
  if p.entered then battle:enter() end
end

-- the host's record of a battle this player opened, not bound yet
local function recordFor(client, me)
  for _, rec in pairs(client.battles) do
    if rec.open and rec.open.by == me and not rec.ended and not rec.bound then return rec end
  end
  return nil
end

-- OverworldState:pushBattle's hook (design A8.2)
function Battles.take(game, battle)
  local s = session()
  if not s or not Battles.joinable(battle) then return end
  local client = s.client
  local team, live, otId, expAll = teamOf(game)
  if #team == 0 then return end
  local seq = client:battleOpen(Battles.opening(game, battle), team, otId, expAll)
  if not seq then return end
  local p = { seq = seq, client = client, me = client.player, live = live, since = clock() }
  battle.coopPending = p
  battle.enter = function() p.entered = true end
  battle.draw = function() end
  battle.update = function(b)
    local rec = recordFor(client, p.me)
    if rec then
      rec.bound = true
      return bind(game, b, rec, p)
    end
    for _, r in ipairs(client.rejections) do
      if r.seq == p.seq then return solo(b, p) end
    end
    if client.status ~= "joined" or clock() - p.since > Battles.WAIT then
      p.gaveUp = true
      Battles.stray = Battles.stray or {}
      Battles.stray[client] = true
      return solo(b, p)
    end
  end
end

-- a record that came after its opener gave up waiting ends at once
function Battles.step()
  local s = session()
  if not s or not (Battles.stray and Battles.stray[s.client]) then return end
  for id, rec in pairs(s.client.battles) do
    if rec.open and rec.open.by == s.client.player and not rec.bound and not rec.ended then
      rec.bound = true
      s.client:battleAt(id, #rec.inputs, nil, nil, nil, "run")
      s.client:dropBattle(id)
    end
  end
end

-- joining (design A8.3) --------------------------------------------------

local JoinWait = {}
JoinWait.__index = JoinWait

function JoinWait.new(game, id, seq, by)
  return setmetatable({ game = game, id = id, seq = seq, by = by, isOpaque = false,
                        frames = 0 }, JoinWait)
end

function JoinWait:update()
  local game = self.game
  local s = session()
  self.frames = self.frames + 1
  local function close(text)
    if game.stack:top() == self then
      game.stack:pop()
    else
      for i, st in ipairs(game.stack.states or {}) do
        if st == self then table.remove(game.stack.states, i) break end
      end
    end
    if text then
      local Notices = require("src.coop.game.Notices")
      Notices.push(text)
    end
  end
  if not s then return close() end
  local client = s.client
  for _, r in ipairs(client.rejections) do
    if r.seq == self.seq then
      return close(r.reason == "roster_full" and Strings("The battle is full.")
        or Strings("Could not join the battle."))
    end
  end
  local rec = client.battles[self.id]
  if not rec then
    if self.frames > 600 then return close(Strings("Could not join the battle.")) end
    return
  end
  if rec.ended then
    client:dropBattle(self.id)
    return close(Strings("The battle is over."))
  end
  local mine = false
  for _, input in ipairs(rec.inputs) do
    if input.kind == "join" and input.player == client.player then mine = true end
  end
  if not mine then return end
  if rec.bound then return close() end
  local b = Replica.build(game, rec, { client = client, id = self.id, me = client.player,
                                       real = game, live = self.live, onEnd = onEnd(game, true) })
  rec.bound = true
  Replica.catchUp(b, rec)
  close()
  local ow = game.overworld
  if ow and ow.pushBattle then ow:pushBattle(b) else game.stack:push(b) end
end

function JoinWait:draw()
  local Font = require("src.render.Font")
  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("Joining %s...", self.by), 8, 14 * 8)
  love.graphics.setColor(1, 1, 1, 1)
end

function Battles.join(game, summary, byName)
  local s = session()
  if not s then return end
  local team, live, otId, expAll = teamOf(game)
  local seq = s.client:battleJoin(summary.id, team, otId, expAll)
  if not seq then return end
  local w = JoinWait.new(game, summary.id, seq, byName or "?")
  w.live = live
  game.stack:push(w)
end

-- the battles this player may join, for the CO-OP menu (design A8.3)
function Battles.offers()
  local s = session()
  if not s then return {} end
  local state, me = s.client.state, s.client.player
  local names = {}
  for _, p in ipairs(state.players or {}) do names[p.id] = p.name end
  local out = {}
  for _, b in ipairs(state.battles or {}) do
    local inIt = false
    for _, pid in ipairs(b.players) do if pid == me then inIt = true end end
    if not inIt and b.joinable then
      out[#out + 1] = { summary = b, name = names[b.by] or "?" }
    end
  end
  return out
end

-- the CO-OP menu's JOIN <NAME> rows
function Battles.joinRows(game, items)
  for _, o in ipairs(Battles.offers()) do
    items[#items + 1] = { label = Strings("JOIN %s", o.name), onSelect = function()
      Battles.join(game, o.summary, o.name)
    end }
  end
end

return Battles
