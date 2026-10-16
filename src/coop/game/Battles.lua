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
-- old man's demo, and the starter rival in Oak's lab; every battle of a
-- player who plays the opening (#22).
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
--
-- Away from a battle (#20, design A11.1 to A11.4, A11.8): a player who
-- left (RUN, then YES) is back in their world, which never moved; their
-- copy runs on out of sight (Battles.step), so their Pokémon get what the
-- battle does to them, and when it ends they get one line saying how it
-- went, their evolutions and, after a loss, their whiteout.  They start and
-- join nothing meanwhile: a fight their world opens waits under "REJOIN?"
-- until that battle ends.  REJOIN in the CO-OP menu takes them back in.
-- A battle this player is in that the window has no copy of (they came
-- back after a drop) is built from the record: one still running comes
-- back on screen, one that ended while they were away plays out of sight
-- and ends with its line.
--
-- Unique encounters (#21, design A10.1 to A10.4): a trainer or a one-off
-- wild Pokémon is an encounter, by its map object (Battles.encounterOf).
-- A world that walks into one a partner is fighting joins that fight: its
-- own battle becomes the copy of the partner's record once its team is
-- in, and keeps the world's onFinish (the trainer's flag, the whiteout).
-- One the campaign has beaten counts as won without a fight: the world's
-- onFinish hears a win.  A trainer the host names as in a battle spots
-- nobody (Battles.engaged, the sight gate); talking to it still joins.

local Strings = require("src.core.Strings")
local Replica = require("src.coop.battle.Replica")
local View = require("src.coop.battle.View")

-- live: every copy this window runs (on screen or away), by battle id
-- walking: the encounters a pending battle of this window opened (#21)
local Battles = { away = {}, held = nil, live = {}, walking = {} }

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

-- the unique encounter a battle is (#21, design A10.2, A10.3): a trainer
-- or a one-off wild Pokémon, by its map object; nil for anything else
function Battles.encounterOf(battle, npc)
  local key = battle.coopEncounter
  if not key then
    local id = npc and npc.id
    if type(id) ~= "string" or not id:find("^[A-Z0-9_]+_obj_%d+$") then return nil end
    key = (battle.kind == "trainer" and "trainer:" or "static:") .. id
  end
  return require("src.coop.session.Protocol").encounter(key)
end

-- the sight gate (#21, design A10.4): a trainer the host names as in a
-- battle spots nobody else; talking to it, or JOIN, still joins
function Battles.engaged(npc)
  local s = session()
  if not s or not npc or type(npc.id) ~= "string" then return false end
  local key = "trainer:" .. npc.id
  for _, b in ipairs(s.client.state.battles or {}) do
    if b.encounter == key then return true end
  end
  return false
end

-- what the world prepared, as the host's opening
function Battles.opening(game, battle, npc)
  local ow = game.overworld
  local open = {
    kind = battle.kind,
    map = (ow and ow.map and ow.map.id) or (game.save.player and game.save.player.map) or "UNKNOWN",
    encounter = Battles.encounterOf(battle, npc),
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
         (inv.EXP_ALL or 0) > 0, Replica.room(game.save)
end

-- the end in this window: the record is dropped; a joiner who lost whites
-- out here (the opener's world does it in its own onFinish); a copy that
-- ended away from the screen says how it went; a fight that waited for it
-- goes on (design A11.3)
local function onEnd(game, joiner)
  return function(b, result)
    local c = b.coop
    if c.client then c.client:dropBattle(c.id) end
    local wasAway = Battles.away[c.id] ~= nil
    Battles.away[c.id] = nil
    Battles.live[c.id] = nil
    if wasAway or c.forced and not c.real.stack:top() then
      require("src.coop.game.Notices").push(View.endLine(b, result))
    end
    if joiner and result == "lose" then
      local ow = game.overworld
      if ow and ow.afterBattle then ow:afterBattle("lose", b) end
    end
    Battles.release(game)
  end
end

local function onLeave(b)
  Battles.away[b.coop.id] = b
end

-- the fight the world opened while this player was away from another
-- one, once that one is over
function Battles.release(game)
  local h = Battles.held
  if not h or next(Battles.away) then return end
  Battles.held = nil
  if h.wait and game.stack:top() == h.wait then game.stack:pop() end
  local ow = game.overworld
  if ow and ow.pushBattle then ow:pushBattle(h.battle, h.npc) end
end

-- a pending battle is settled: bound, alone, or ended without a fight
local function settled(battle, p)
  battle.coopPending = nil
  if p.encounter then Battles.walking[p.encounter] = nil end
end

-- the opener's battle becomes the co-op copy of the host's record
local function bind(game, battle, rec, p)
  settled(battle, p)
  battle.draw = nil
  Replica.make(battle, rec, { client = p.client, id = rec.id, me = p.me, real = game,
                              live = p.live, onEnd = onEnd(game, false), onLeave = onLeave })
  Battles.live[rec.id] = battle
  if p.entered then battle:enter() end
end

-- no host battle: the world's own, alone (design A8.22)
local function solo(battle, p)
  settled(battle, p)
  battle.enter, battle.update, battle.draw = nil, nil, nil
  if p.entered then battle:enter() end
end

-- the world walked into a partner's fight (#21, A10.2): once this
-- player's team is in, its battle becomes the copy of that record, caught
-- up without a screen, and keeps the world's onFinish
local function walkIn(game, battle, rec, p)
  settled(battle, p)
  battle.draw = nil
  rec.bound = true
  Replica.make(battle, rec, { client = p.client, id = rec.id, me = p.me, real = game,
                              live = p.live, onEnd = onEnd(game, false), onLeave = onLeave })
  Battles.live[rec.id] = battle
  Replica.catchUp(battle, rec)
  if p.entered then battle:enter() end
end

-- a unique encounter the campaign has beaten counts as won (#21, A10.2):
-- no fight, and the world's onFinish hears a win
local function asWon(battle, p, foe)
  settled(battle, p)
  battle.enter, battle.update, battle.draw = nil, nil, nil
  battle.result = "win"
  battle.evolutionsChecked, battle.pikachuMoodChecked = true, true
  require("src.coop.game.Notices").push(Strings("%s was already beaten.", foe or "?"))
  if p.entered then battle:finish() else battle.enter = function(b) b.enter = nil; b:finish() end end
end

-- a walk-in that found no room ends as a flight: the encounter stays
local function turnedAway(battle, p, text)
  settled(battle, p)
  battle.enter, battle.update, battle.draw = nil, nil, nil
  battle.result = "run"
  battle.evolutionsChecked, battle.pikachuMoodChecked = true, true
  require("src.coop.game.Notices").push(text)
  if p.entered then battle:finish() else battle.enter = function(b) b.enter = nil; b:finish() end end
end

-- the record of the encounter this pending battle walked into, if any
local function walkedInto(client, p)
  if not p.encounter then return nil end
  for _, rec in pairs(client.battles) do
    if rec.open and rec.open.encounter == p.encounter and rec.open.by ~= p.me
       and not rec.ended and not rec.bound then
      return rec
    end
  end
  return nil
end

local function joinedIn(rec, me)
  for _, input in ipairs(rec.inputs) do
    if input.kind == "join" and input.player == me then return true end
  end
  return false
end

-- the host's record of a battle this player opened, not bound yet
local function recordFor(client, me)
  for _, rec in pairs(client.battles) do
    if rec.open and rec.open.by == me and not rec.ended and not rec.bound then return rec end
  end
  return nil
end

-- a fight the world opened while this player is away from another battle
-- waits under "REJOIN?" until that one ends (design A11.3)
local function hold(game, battle, npc)
  local id, old = next(Battles.away)
  local TextBox = require("src.render.TextBox")
  local foe = old.enemy and old.enemy.name or "?"
  if old.kind == "trainer" and old.trainer then foe = old.trainer.name end
  local wait = { isOpaque = false, update = function() end, draw = function()
    local Font = require("src.render.Font")
    Font.drawBox(0, 12, 20, 6)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings("Your battle against"), 8, 112)
    Font.draw(Strings("%s goes on...", foe), 8, 128)
    love.graphics.setColor(1, 1, 1, 1)
  end }
  Battles.held = { battle = battle, npc = npc, wait = wait }
  game.stack:push(wait)
  game.stack:push(TextBox.new(game, Strings("Your battle against\n%s goes on.\fREJOIN?", foe), nil, {
    choice = function(yes) if yes and Battles.away[id] then Battles.rejoin(game, Battles.away[id]) end end,
  }))
end

-- OverworldState:pushBattle's hook (design A8.2); "held" when the battle
-- waits for another one this player is away from (A11.3)
function Battles.take(game, battle, npc)
  if battle and battle.coop then return end
  -- the opening's battles stay in the window (#22, design A4.4)
  if require("src.coop.game.Opening").active() then return end
  if next(Battles.away) and session() then
    hold(game, battle, npc)
    return "held"
  end
  local s = session()
  if not s or not Battles.joinable(battle) then return end
  local client = s.client
  local team, live, otId, expAll, room = teamOf(game)
  if #team == 0 then return end
  -- the holdings so far reach the host before the battle holds the player (#17)
  if s.window then s.window:flushHoldings(game.save) end
  local opening = Battles.opening(game, battle, npc)
  local seq = client:battleOpen(opening, team, otId, expAll, room)
  if not seq then return end
  local p = { seq = seq, client = client, me = client.player, live = live, since = clock(),
              encounter = opening.encounter }
  battle.coopPending = p
  if p.encounter then Battles.walking[p.encounter] = true end
  battle.enter = function() p.entered = true end
  battle.draw = function() end
  battle.update = function(b)
    local rec = recordFor(client, p.me)
    if rec then
      rec.bound = true
      return bind(game, b, rec, p)
    end
    -- a partner's fight this world walked into (#21): wait for the team to
    -- go in, however long the battle takes to ask for a move
    local into = walkedInto(client, p)
    if into then
      p.since = clock()
      if joinedIn(into, p.me) then return walkIn(game, b, into, p) end
    end
    for _, r in ipairs(client.rejections) do
      if r.seq == p.seq then
        if r.reason == "beaten" then return asWon(b, p, opening.foe) end
        if r.reason == "roster_full" then return turnedAway(b, p, Strings("The battle is full.")) end
        return solo(b, p)
      end
    end
    if client.status ~= "joined" or clock() - p.since > Battles.WAIT then
      p.gaveUp = true
      Battles.stray = Battles.stray or {}
      Battles.stray[client] = true
      return solo(b, p)
    end
  end
end

-- every frame of a joined game: the copies away from the screen go on, a
-- record that came after its opener gave up waiting ends at once, and a
-- battle this player is in without a copy here is built (#20)
function Battles.step(game)
  local s = session()
  if not s then return end
  -- a link that came back (#20, A11.9): every copy follows the new one; a
  -- command sent on the old link may be lost, so the question is asked and
  -- answered again (the host refuses one it already took as stale)
  for _, b in pairs(Battles.live) do
    local c = b.coop
    if c.client ~= s.client then
      c.client = s.client
      c.sent, c.reported, c.picking, c.suggested = nil, nil, nil, nil
    end
  end
  for id, b in pairs(Battles.away) do
    Replica.runAway(b)
    if b.coop.done then Battles.away[id] = nil end
  end
  local stray = Battles.stray and Battles.stray[s.client]
  for id, rec in pairs(s.client.battles) do
    if stray and rec.open and rec.open.by == s.client.player and not rec.bound and not rec.ended then
      rec.bound = true
      s.client:battleAt(id, #rec.inputs, nil, nil, nil, "run")
      s.client:dropBattle(id)
    elseif game and not rec.bound and rec.open and Battles.rebuildable(s.client, rec) then
      Battles.rebuild(game, s.client, rec)
    end
  end
end

-- The game reopened its world (#55, design A10.7): this window's copies
-- went with the old one.  Finished battles are dropped; a running one this
-- player is in is built again from its record, as after a drop (#20).
function Battles.reopen(client)
  Battles.away, Battles.live, Battles.walking = {}, {}, {}
  Battles.held, Battles.joining, Battles.stray = nil, nil, nil
  for id, rec in pairs(client and client.battles or {}) do
    if rec.ended then client:dropBattle(id) else rec.bound = nil end
  end
end

-- a record this window has no copy of: this player is in it (not just a
-- queued join, not one they opened that is still being bound), and it has
-- inputs to play
function Battles.rebuildable(client, rec)
  if Battles.waitingFor(rec.id) or Battles.live[rec.id] then return false end
  -- a fight this window's pending battle walked into binds that battle (#21)
  if rec.open.encounter and Battles.walking[rec.open.encounter] then return false end
  if rec.open.by == client.player and not rec.ended then
    -- the opener's own record is bound by its pending battle; one with no
    -- pending battle came back after a drop
    for _, b in ipairs(Battles.pending or {}) do
      if b.coopPending then return false end
    end
  end
  for _, input in ipairs(rec.inputs) do
    if input.kind == "join" and input.player == client.player then return true end
  end
  return false
end

-- a joining box waits for this battle: it builds the copy itself
function Battles.waitingFor(id)
  return Battles.joining == id
end

-- Build a battle this player is in from its record (after coming back):
-- one still running comes on screen at the next quiet moment, one that
-- ended plays out of sight and says how it went (design A11.8)
function Battles.rebuild(game, client, rec)
  local ow = game.overworld
  local away = false
  for _, e in ipairs(rec.players or {}) do
    if e.id == client.player and e.left then away = true end
  end
  if not rec.ended and not away and not (ow and game.stack:top() == ow) then return end
  rec.bound = true
  local b = Replica.build(game, rec, { client = client, id = rec.id, me = client.player,
                                       real = game, onEnd = onEnd(game, true), onLeave = onLeave })
  Battles.live[rec.id] = b
  if rec.ended or away then
    b.coop.away = true
    Battles.away[rec.id] = b
    Replica.runAway(b)
    return
  end
  Replica.catchUp(b, rec)
  ow:pushBattle(b)
end

-- REJOIN (design A11.4): back into a battle this player left, at once
function Battles.rejoin(game, b)
  local c = b.coop
  if not c.client then return end
  c.client:battleRejoin(c.id)
  Battles.away[c.id] = nil
  c.away = false
  b:snapIdleBars()
  local ow = game.overworld
  if ow and ow.pushBattle then ow:pushBattle(b) else game.stack:push(b) end
end

-- the CO-OP menu's REJOIN rows
function Battles.rejoinRows(game, items)
  for _, b in pairs(Battles.away) do
    if not b.coop.done then
      local foe = b.kind == "trainer" and b.trainer and b.trainer.name
        or b.enemy and b.enemy.name or "?"
      -- (the second line, #34: against whom)
      items[#items + 1] = { label = Strings("REJOIN"), detail = Strings("VS %s", foe), onSelect = function()
        Battles.rejoin(game, b)
      end }
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
  Battles.joining = self.id
  local function close(text)
    Battles.joining = nil
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
  -- B calls a queued join off (design A11.4)
  if game.input and game.input:wasPressed("b") then
    client:battleLeave(self.id)
    return close()
  end
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
                                       real = game, live = self.live, onEnd = onEnd(game, true),
                                       onLeave = onLeave })
  Battles.live[self.id] = b
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
  local team, live, otId, expAll, room = teamOf(game)
  local seq = s.client:battleJoin(summary.id, team, otId, expAll, room)
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

-- the CO-OP menu's JOIN <NAME> rows; a player away from a battle starts
-- or joins nothing (design A11.3)
function Battles.joinRows(game, items)
  if next(Battles.away) then return Battles.rejoinRows(game, items) end
  if require("src.coop.game.Opening").active() then return end -- (#22)
  for _, o in ipairs(Battles.offers()) do
    items[#items + 1] = { label = Strings("JOIN %s", o.name),
                          detail = Strings("VS %s", o.summary.foe or "?"), -- #34: against whom
                          onSelect = function()
      Battles.join(game, o.summary, o.name)
    end }
  end
end

return Battles
