-- A window's copy of a co-op battle (#18, design A8, decision G24).
--
-- Co-op battles are lockstep: every window in a battle runs the game's own
-- battle (src/battle/BattleState.lua) from the host's record (the opening,
-- a seed, the inputs in order; src/coop/battle/HostBattles.lua), and every
-- copy comes to the same state, as upstream's link battles do between two
-- machines (src/link/LinkBattle.lua).  The window shows its copy with the
-- cartridge's own screen, sounds and menus; no copy is the master.
--
-- What makes a BattleState a co-op battle (Replica.make):
--
--   * its game is a facade over the window's game (`proxy`): the save it
--     sees has the battle's roster as its party and money of its own, so
--     nothing the battle writes reaches the player's world until the end;
--   * its random numbers come from the battle's seed (Replica.rng);
--   * the enemy is the opening's (the clamped copies of upstream's link
--     codec, src/link/Protocol.lua, so every window holds the same);
--   * its party is the allied roster: each team that joined, in order,
--     each Pokémon with its owner (design A8.5);
--   * every decision is a question with an owner (design A8.6): the
--     command menu and a forced replacement are asked of the owner of the
--     Pokémon that is out, a move to learn, MIMIC's choice and "Use next
--     POKéMON?" of the Pokémon's owner.  The battle waits at a question
--     until the record has the next input; only the owner's window opens
--     the menus, and its choice goes to the host as a command, not into the
--     battle (Replica:send).  Turns locked in (recharge, THRASH, RAGE, a
--     charging move) take no command (A8.10);
--   * EXP.ALL works per team (A8.15), and a partner's Pokémon is traded or
--     not against its own owner's trainer id (A7.10);
--   * the battle style is SET (A8.18);
--   * at the end the window writes its own Pokémon back by reference (or
--     uid), pays its player the prize the battle paid (each participant
--     gets the full prize, A8.16), runs evolution for its own Pokémon
--     (A7.8), and a loss whites out every participant in their own world
--     (A8.17).
--
-- A window that joins an running battle builds its copy from the record
-- and plays every input so far without a screen or sound (Replica.catchUp),
-- so it sees no intro (design A9.8) and stands where the others stand.

local Strings = require("src.core.Strings")
local Logger = require("src.core.Logger")
local Protocol = require("src.coop.session.Protocol")

local Replica = {}

-- the battle engine of this world (split-screen keeps one per world)
local function engine() return require("src.battle.BattleState") end

-- Deterministic Park-Miller generator, as LinkBattle's: every copy rolls
-- the same stream.  owner.rngDraws counts the draws (the digest has it).
function Replica.rng(seed, owner)
  local s = math.floor(tonumber(seed) or 1) % 2147483647
  if s <= 0 then s = s + 2147483646 end
  owner.rngDraws = 0
  return function(a, b)
    owner.rngDraws = owner.rngDraws + 1
    s = (s * 16807) % 2147483647
    if a == nil then return s / 2147483647 end
    if b == nil then a, b = 1, a end
    return a + (s % (b - a + 1))
  end
end

-- a Pokémon for a battle message: the link codec's packed mon and its uid
function Replica.pack(mon)
  local packed = require("src.link.Protocol").packMon(mon)
  packed.uid = mon.coopUid
  if packed.extra and next(packed.extra) == nil then packed.extra = nil end
  return packed
end

function Replica.packTeam(party)
  local out = {}
  for i, mon in ipairs(party) do
    if i > 6 then break end
    out[#out + 1] = Replica.pack(mon)
  end
  return out
end

local function unpack(data, packed)
  local mon = require("src.link.Protocol").unpackMon(data, packed)
  if mon then mon.coopUid = packed.uid end
  return mon
end

local function digest(text)
  local Fingerprint = require("src.link.Fingerprint")
  return Fingerprint.digest(text)
end

-- the state's digest: both actives, the roster, the enemy party, the draws
function Replica.hash(b)
  local parts = {}
  local function mon(m)
    if not m then return "-" end
    local pp = {}
    for i, mv in ipairs(m.moves or {}) do pp[i] = tostring(mv.id) .. "=" .. tostring(mv.pp) end
    return ("%s:%d:%d:%s:%s"):format(tostring(m.species), m.level or 0, m.hp or 0,
                                     tostring(m.status), table.concat(pp, ","))
  end
  parts[#parts + 1] = mon(b.player and b.player.mon) .. "/" .. mon(b.enemy and b.enemy.mon)
  for _, m in ipairs(b.coop.roster) do parts[#parts + 1] = mon(m) .. ":" .. tostring(m.exp) end
  for _, m in ipairs(b.enemyParty or {}) do parts[#parts + 1] = mon(m) end
  parts[#parts + 1] = "r" .. tostring(b.rngDraws or 0)
  return digest(table.concat(parts, "|"))
end

-- the facade game a co-op battle sees ------------------------------------

local AUTO_INPUT = {
  wasPressed = function(_, key) return key == "a" end,
  isDown = function() return false end,
  wasReleased = function() return false end,
}
setmetatable(AUTO_INPUT, { __index = function() return function() return false end end })

local function silentStack(b)
  return {
    -- a screen the battle opens while catching up is never shown
    push = function() end,
    pop = function() end,
    top = function() return b end,
  }
end

local function proxyGame(real, b)
  local save = setmetatable({}, { __index = real.save })
  local game = setmetatable({ save = save, input = real.input, stack = real.stack },
                            { __index = real })
  return game, save
end

-- Sound and music off while a copy catches up without a screen
local function muted(fn)
  local saved = {}
  for _, name in ipairs({ "src.core.Sound", "src.core.Music" }) do
    local m = package.loaded[name]
    if type(m) == "table" then
      saved[m] = {}
      for k, v in pairs(m) do
        if type(v) == "function" then
          saved[m][k] = v
          m[k] = function() return nil end
        end
      end
    end
  end
  local ok, err = pcall(fn)
  for m, fns in pairs(saved) do
    for k, v in pairs(fns) do m[k] = v end
  end
  if not ok then error(err, 0) end
end

-- the roster and its owners ----------------------------------------------

function Replica.owner(b, mon)
  return mon and b.coop.owners[mon] or nil
end

function Replica.index(b, mon)
  for i, m in ipairs(b.coop.roster) do
    if m == mon then return i end
  end
  return nil
end

local function playerName(b, pid)
  return b.coop.names[pid] or "?"
end

-- a join input: the team goes in behind the roster (design A8.5)
local function applyJoin(b, input)
  local c = b.coop
  local data = b.data
  c.names[input.player] = input.name or c.names[input.player]
  c.otIds[input.player] = input.otId
  c.expAll[input.player] = input.expAll == true
  local live = input.player == c.me and c.live or nil
  for i, packed in ipairs(input.team or {}) do
    local mon = unpack(data, packed)
    if mon then
      c.roster[#c.roster + 1] = mon
      c.owners[mon] = input.player
      if live and live[i] then c.liveOf[mon] = live[i] end
    end
  end
  if input.player == c.me then c.live = nil end
  if not b.player then
    local Party = require("src.pokemon.Party")
    local lead = Party.firstHealthy(c.roster)
    if lead then
      b.player = engine().makeBattler(data, lead, true, b.game.save)
      b.dead = nil
      b:syncSides()
    end
  end
end

-- the Pokémon this question is about, and so its owner
local function questionOf(b)
  local c = b.coop
  if c.ask then return c.ask.kind, c.ask.by end
  if b.result then return nil end
  if b.phase == "mimicSelect" then return "mimic", Replica.owner(b, b.player and b.player.mon) end
  if (b.phase == "menu" or b.phase == "moveSelect") and b.player and #b.queue == 0 then
    local by = Replica.owner(b, b.player.mon)
    if b.player.mon.hp <= 0 then return "replace", by end
    return "menu", by
  end
  return nil
end
Replica.question = questionOf

local STRUGGLE = function() return { id = "STRUGGLE", pp = 1, struggle = true } end

-- an accepted command, applied in every copy alike
local function applyCmd(b, input)
  local BattleState = engine()
  local c = b.coop
  local cmd = input.cmd
  local kind = cmd.kind
  if kind == "learn" or kind == "choice" then
    local ask = c.ask
    c.ask = nil
    if not ask then return end
    if kind == "choice" then
      if ask.fn then ask.fn(cmd.yes == true) end
      return
    end
    local mon, moveId = ask.mon, ask.moveId
    local mdef = b.data.moves[moveId]
    local name = mon.nickname or b.data.pokemon[mon.species].name
    b.nextInsert = 0
    if (cmd.forget or 0) > 0 and mon.moves[cmd.forget] and mdef then
      mon.moves[cmd.forget] = { id = moveId, pp = mdef.pp }
      require("src.mods.Runtime").emit("pokemon.move_learned", { mon = mon, moveId = moveId })
      b:sayNext(b:romText("_LearnedMove1Text", "%s learned\n%s!", name, mdef.name))
    elseif mdef then
      b:sayNext(b:romText("_DidNotLearnText", "%s\ndid not learn\v%s!", name, mdef.name))
    end
    return
  end
  if kind == "mimic" then
    BattleState.chooseMimic(b, cmd.index or cmd.slot)
    return
  end
  if kind == "replace" then
    local mon = c.roster[cmd.index]
    if not mon or mon.hp <= 0 then
      local Party = require("src.pokemon.Party")
      mon = Party.firstHealthy(c.roster)
    end
    b.phase, b.afterQueue = "messages", "menu"
    b:sendOutReplacement(mon)
    return
  end
  -- the command menu's answers (BattleState:chooseMenu, chooseMove)
  b:clearTurnFlinches()
  if kind == "move" then
    local mv = b.player.curMoves[cmd.slot]
    if not mv then mv = STRUGGLE() end
    b.moveIndex, b.playerMoveListIndex = cmd.slot, cmd.slot
    BattleState.resolveTurn(b, mv)
  elseif kind == "struggle" then
    b:say(Strings("%s has no\nmoves left!", b.player.name))
    BattleState.resolveTurn(b, STRUGGLE())
  elseif kind == "fight" then
    BattleState.resolveTurn(b, b:fightLockedAction(b.player) or STRUGGLE())
  elseif kind == "switch" then
    local mon = c.roster[cmd.index]
    if mon and mon.hp > 0 and mon ~= b.player.mon then
      BattleState.resolveSwitch(b, mon)
    else
      BattleState.resolveTurn(b, STRUGGLE())
    end
  elseif kind == "item" then
    -- as BattleState:openItems leaves it before the bag
    b.phase, b.afterQueue = "messages", "menu"
    local LinkItems = require("src.link.LinkItems")
    local lines = LinkItems.apply(b, { item = cmd.item, index = cmd.index, move = cmd.move }, {
      battler = b.player, party = c.roster, opponent = b.enemy,
      opponentParty = b.enemyParty or { b.enemy.mon }, name = playerName(b, input.player),
    })
    BattleState.itemUsed(b, lines, {})
  elseif kind == "ball" then
    c.catcher = input.player
    b.phase, b.afterQueue = "messages", "menu"
    BattleState.throwBall(b, cmd.item)
  elseif kind == "run" then
    BattleState.tryRun(b)
  end
end

local function applyInput(b, input)
  local c = b.coop
  c.applying = true
  local ok, err = pcall(function()
    if input.kind == "join" then applyJoin(b, input) else applyCmd(b, input) end
  end)
  c.applying = false
  c.applied = c.applied + 1
  -- a command answers the question; a team joining moves the revision on,
  -- so a command of this window in flight is sent again (design A8.4)
  if input.kind == "cmd" then c.sent = nil end
  if not ok then Logger.warn("co-op battle: input %d failed: %s", c.applied, tostring(err)) end
end

-- the queue drained: what BattleState:update does next (its message phase)
local function afterDrain(b)
  local destination = b.afterQueue
  b.afterQueue, b.nextInsert, b.waitFrames = nil, nil, nil
  if destination == "menu" then
    b.introSlide, b.msgHold, b.shown = nil, nil, nil
    b:enterCommandMenu()
  elseif destination == "finish" then
    b:finish()
  end
end

-- Apply the record's next inputs while the copy stands at a question; the
-- inputs are only ever made at questions (HostBattles), so a copy that
-- reached one takes the next.  Then the copy's place goes to the host.
function Replica.step(b)
  local c = b.coop
  local rec = c.client and c.client.battles[c.id]
  if not rec then return end
  while c.applied < #rec.inputs and questionOf(b) do
    applyInput(b, rec.inputs[c.applied + 1])
  end
  Replica.report(b)
  local sent = c.sent
  if sent then
    local kind, by = questionOf(b)
    for _, r in ipairs(c.client.rejections) do
      if r.seq == sent.seq and not sent.refused then sent.refused = r.reason end
    end
    if kind and by == c.me and Protocol.CMDS[sent.cmd.kind] == kind
       and (sent.rev < c.applied or sent.refused == "stale") then
      -- refused or overtaken by a join: the same answer for the new revision
      sent.rev, sent.refused = c.applied, nil
      sent.seq = c.client:battleCmd(c.id, c.applied, sent.cmd)
    elseif sent.refused or not kind or by ~= c.me then
      c.sent = nil -- refused for good: the player chooses again
    end
  end
end

function Replica.report(b)
  local c = b.coop
  if not c.client then return end
  local kind, by = questionOf(b)
  if not kind or not by then return end
  local key = c.applied .. kind .. by
  if c.reported == key then return end
  c.reported = key
  c.client:battleAt(c.id, c.applied, kind, by, Replica.hash(b))
end

-- Play every input the record holds without a screen or sound: a window
-- joining a running battle catches up to where the others stand.
function Replica.catchUp(b, rec)
  local c = b.coop
  local game = b.game
  local input, stack = game.input, game.stack
  game.input, game.stack = AUTO_INPUT, silentStack(b)
  c.silent = true
  muted(function()
    if not c.entered then
      c.entered = true
      engine().enter(b)
    end
    for _ = 1, 200000 do
      if c.done then break end
      if questionOf(b) then
        if c.applied >= #rec.inputs then break end
        applyInput(b, rec.inputs[c.applied + 1])
      elseif b.phase == "messages" then
        b:tickFx()
        if not b:updateQueue() then afterDrain(b) end
      elseif b.phase == "menu" and b.player and b.player.mon.hp > 0
             and b:menuLockedAction(b.player) then
        c.applying = true
        b:clearTurnFlinches()
        engine().resolveTurn(b, b:menuLockedAction(b.player))
        c.applying = false
      else
        break
      end
    end
    for _ = 1, 240 do b:tickFx() end
  end)
  c.silent = false
  game.input, game.stack = input, stack
  b:snapIdleBars()
  b.introSlide = nil
end

-- the menus of the player asked ----------------------------------------------

function Replica.mine(b)
  local kind, by = questionOf(b)
  return kind ~= nil and by == b.coop.me and b.coop.sent == nil, kind
end

-- this window's answer goes to the host; the copy waits for it as an input
function Replica.send(b, cmd)
  local c = b.coop
  if not c.client or c.sent then return end
  c.sent = { rev = c.applied, cmd = cmd }
  c.sent.seq = c.client:battleCmd(c.id, c.applied, cmd)
end

-- the bag and the party menu work on scratch copies: the choice goes to
-- the host, the effect comes back as an input
local function scratchFacade(b)
  local copies, index = {}, {}
  for i, mon in ipairs(b.coop.roster) do
    local copy = {}
    for k, v in pairs(mon) do copy[k] = v end
    copy.moves = {}
    for j, mv in ipairs(mon.moves or {}) do
      copy.moves[j] = {}
      for k, v in pairs(mv) do copy.moves[j][k] = v end
    end
    copies[i], index[copy] = copy, i
  end
  local p = b.player
  local stages = {}
  for k, v in pairs(p.stages or {}) do stages[k] = v end
  local player = setmetatable({ mon = copies[Replica.index(b, p.mon) or 1], stages = stages },
                              { __index = p })
  local facade = setmetatable({ playerParty = copies, player = player }, { __index = b })
  facade.itemUsed = function(_, _, o)
    o = o or {}
    Replica.send(b, { kind = "item", item = o.item, index = o.target and index[o.target] or nil,
                      move = o.moveIndex })
  end
  facade.throwBall = function(_, ball)
    Replica.send(b, { kind = "ball", item = ball })
  end
  return facade, copies, index
end

function Replica.openParty(b)
  local c = b.coop
  b.game.stack:push(b:buildScreen("PartyMenu", {
    battle = b, party = c.roster, keepOpen = true,
    onSwitch = function(mon, menu)
      local refusal
      if mon == b.player.mon then
        refusal = b:romText("_AlreadyOutText", "%s is\nalready out!", b.player.name)
      elseif mon.hp <= 0 then
        refusal = b:romText("_NoWillText", "There's no will\nto fight!")
      end
      if refusal then
        if menu then menu:refuse(refusal) end
        return
      end
      if menu then menu:close() end
      Replica.send(b, { kind = "switch", index = Replica.index(b, mon) })
    end,
  }))
end

function Replica.openReplacement(b)
  local c = b.coop
  c.picking = c.applied
  b.game.stack:push(b:buildScreen("PartyMenu", {
    battle = b, party = c.roster, forceSwitch = true, keepOpen = true,
    onSwitch = function(mon, menu)
      if mon.hp <= 0 then
        if menu then menu:refuse(b:romText("_NoWillText", "There's no will\nto fight!")) end
        return
      end
      if menu then menu:close() end
      Replica.send(b, { kind = "replace", index = Replica.index(b, mon) })
    end,
  }))
end

function Replica.openItems(b)
  local facade = scratchFacade(b)
  b.game.stack:push(b:buildScreen("BagMenu", { battle = facade }))
end

function Replica.openLearn(b)
  local c = b.coop
  local ask = c.ask
  c.picking = c.applied
  local mon = ask.mon
  local scratch = { moves = {} }
  for k, v in pairs(mon) do if k ~= "moves" then scratch[k] = v end end
  for j, mv in ipairs(mon.moves) do scratch.moves[j] = { id = mv.id, pp = mv.pp } end
  b.game.stack:push(b:buildScreen("MoveLearnMenu", scratch, ask.moveId, function(learned)
    local forget = 0
    if learned then
      for j, mv in ipairs(scratch.moves) do
        if mv.id == ask.moveId and (mon.moves[j] and mon.moves[j].id) ~= ask.moveId then forget = j end
      end
    end
    Replica.send(b, { kind = "learn", forget = forget })
  end, "Level_Up"))
end

function Replica.openChoice(b)
  local c = b.coop
  local ask = c.ask
  c.picking = c.applied
  local TextBox = require("src.render.TextBox")
  b.game.stack:push(TextBox.new(b.game, ask.text or "", nil, {
    choice = function(yes) Replica.send(b, { kind = "choice", yes = yes == true }) end,
  }))
end

-- making a co-op battle ----------------------------------------------------

-- The EXP.ALL split per team (design A8.15): the fighters share as the
-- cartridge shares; with an EXP.ALL in any participant's bag the fighters'
-- block is halved and each team gets the other half over its own Pokémon.
local function expAward(b, ctx)
  local c = b.coop
  local expAll = false
  for _, has in pairs(c.expAll) do expAll = expAll or has end
  for _, mon in ipairs(ctx.alive) do
    ctx.applyShare(mon, ctx.participants * (expAll and 2 or 1), true)
  end
  if not expAll then return end
  local teams, order = {}, {}
  for _, mon in ipairs(c.roster) do
    local pid = c.owners[mon]
    if not teams[pid] then teams[pid] = {}; order[#order + 1] = pid end
    table.insert(teams[pid], mon)
  end
  for _, pid in ipairs(order) do
    local team = teams[pid]
    for _, mon in ipairs(team) do
      if mon.hp > 0 then
        ctx.applyShare(mon, math.max(1, ctx.participants) * #team * 2, "expAll")
      end
    end
  end
end

-- the fields a battle changes on a Pokémon, written back to the player's own
local WRITEBACK = { "level", "exp", "hp", "status", "sleepTurns", "statExp", "stats" }

local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deepCopy(x) end
  return out
end

function Replica.findLive(save, uid)
  if not uid then return nil end
  for _, mon in ipairs(save.party or {}) do
    if mon.coopUid == uid then return mon end
  end
  return nil
end

-- This window's own Pokémon get what the battle did to them (design
-- A8.14); the prize the battle paid goes to this player (A8.16).
local function writeBack(b)
  local c = b.coop
  local real = c.real.save
  local leveled = {}
  for _, copy in ipairs(c.roster) do
    if c.owners[copy] == c.me then
      local live = c.liveOf[copy] or Replica.findLive(real, copy.coopUid)
      if live then
        for _, k in ipairs(WRITEBACK) do live[k] = deepCopy(copy[k]) end
        live.moves = deepCopy(copy.moves)
        if b.leveledUp and b.leveledUp[copy] then leveled[live] = true end
      end
    end
  end
  local paid = (c.save.money or 0) - c.money0
  if paid ~= 0 then real.money = math.max(0, math.min(999999, (real.money or 0) + paid)) end
  return leveled
end

-- Turn `b`, a BattleState, into a co-op battle on the record `rec`.
-- opts: client, id, me, real (the window's game), live (the player's own
-- party mons in the order their packed team was sent), onEnd(b, result)
function Replica.make(b, rec, opts)
  local BattleState = engine()
  local real = opts.real
  local game, save = proxyGame(real, b)
  b.game = game
  b.coop = {
    id = opts.id, client = opts.client, me = opts.me, real = real, save = save,
    roster = {}, owners = {}, names = {}, otIds = {}, expAll = {}, liveOf = {},
    live = opts.live, applied = 0, onEnd = opts.onEnd, opener = rec.open.by,
  }
  local c = b.coop
  save.party = c.roster
  save.money = real.save.money or 0
  c.money0 = save.money
  save.player = setmetatable({ rival = rec.open.trainer and rec.open.trainer.rival },
                             { __index = real.save.player })
  b.playerParty = c.roster
  b.rng = Replica.rng(rec.seed, b)
  b.coopBattle = true
  -- the enemy as the opening prepared it
  local enemy = {}
  for i, packed in ipairs(rec.open.enemy) do enemy[i] = unpack(b.data, packed) end
  if b.kind == "trainer" then
    b.enemyParty = enemy
    b.enemyIndex = 1
    b.enemy = BattleState.makeBattler(b.data, enemy[1], false)
    b.aiUses = b:aiUsesFor()
  elseif enemy[1] then
    b.enemy = BattleState.makeBattler(b.data, enemy[1], false)
  end
  b.player, b.participants = nil, {}
  b:syncSides()
  -- the methods a co-op battle answers in its own way
  b.battleStyle = function() return "set" end
  b.expTrainerId = function(s, mon) return s.coop.otIds[s.coop.owners[mon]] end
  b.expAward = expAward
  b.enterCommandMenu = function(s)
    s.coop.applying = true
    local ok, err = pcall(BattleState.enterCommandMenu, s)
    s.coop.applying = false
    if not ok then error(err, 0) end
  end
  b.resolveTurn = function(s, action)
    if s.coop.applying then return BattleState.resolveTurn(s, action) end
    local slot
    for i, mv in ipairs(s.player.curMoves) do if mv == action then slot = i end end
    if action.struggle then return Replica.send(s, { kind = "struggle" }) end
    if not slot then return Replica.send(s, { kind = "fight" }) end
    return Replica.send(s, { kind = "move", slot = slot })
  end
  b.chooseMenu = function(s, choice)
    if s.coop.applying then return BattleState.chooseMenu(s, choice) end
    if not Replica.mine(s) or s.phase ~= "menu" then return nil, "not yours" end
    if choice == "fight" then
      if s:fightLockedAction(s.player) then return Replica.send(s, { kind = "fight" }) end
      if not s:playerHasPP() then return Replica.send(s, { kind = "struggle" }) end
      s.phase = "moveSelect"
      s.moveIndex = math.min(s.moveIndex, #s.player.curMoves)
      s.moveSwapIndex = nil
    elseif choice == "run" then
      if s.kind == "trainer" then return BattleState.tryRun(s) end -- only says no
      if s.coop.me ~= s.coop.opener then
        s:say(Strings("Only %s can\nrun from this\nbattle!", playerName(s, s.coop.opener)))
        s.phase, s.afterQueue = "messages", "menu"
        return true
      end
      Replica.send(s, { kind = "run" })
    elseif choice == "item" then
      Replica.openItems(s)
    elseif choice == "party" then
      Replica.openParty(s)
    end
    return true
  end
  b.chooseMimic = function(s, index)
    if s.coop.applying then return BattleState.chooseMimic(s, index) end
    if not (s.mimicMoves and s.mimicMoves[index]) then return nil, "invalid mimic slot" end
    Replica.send(s, { kind = "mimic", index = index })
    return true
  end
  b.openReplacementMenu = function() end -- asked of the fainted Pokémon's owner
  b.sayChoice = function(s, text, fn)
    table.insert(s.queue, { text = text })
    table.insert(s.queue, { fn = function()
      s.coop.ask = { kind = "choice", by = Replica.owner(s, s.player and s.player.mon),
                     fn = fn, text = text }
    end })
  end
  b.learnMove = function(s, mon, moveId)
    local mdef = s.data.moves[moveId]
    local known = false
    for _, mv in ipairs(mon.moves) do if mv.id == moveId then known = true end end
    if not mdef or known or #mon.moves < 4 then return BattleState.learnMove(s, mon, moveId) end
    s.nextInsert = (s.nextInsert or 0) + 1
    table.insert(s.queue, s.nextInsert, { fn = function()
      s.coop.ask = { kind = "learn", by = Replica.owner(s, mon), mon = mon, moveId = moveId }
    end })
  end
  b.updateQueue = function(s)
    if s.coop.ask then return true end -- a question waits for its input
    return BattleState.updateQueue(s)
  end
  b.storeCaughtMon = function(s)
    -- the catch goes to the player who threw (design A7.6; naming another
    -- comes with #17)
    if s.coop.catcher == s.coop.me then
      s.game = s.coop.real
      local ok, err = pcall(BattleState.storeCaughtMon, s)
      s.game = game
      if not ok then error(err, 0) end
      return
    end
    s:restoreMimicked(s.enemy)
    s:sayNext(Strings("%s caught\n%s!", playerName(s, s.coop.catcher), s.enemy.name))
    s.result = "caught"
    s.afterQueue = "finish"
  end
  b.finish = function(s)
    local cc = s.coop
    if s.payDay and s.result == "win" then return BattleState.finish(s) end
    if not cc.done then
      cc.done = true
      if cc.client and not cc.silent then
        cc.client:battleAt(cc.id, cc.applied, nil, nil, Replica.hash(s), s.result or "run")
      end
      local leveled = writeBack(s)
      s.evolutionsChecked = true
      s.pikachuMoodChecked = true
      if next(leveled) then
        require("src.pokemon.Evolution").checkParty(cc.real, function() s:finish() end, leveled)
        return
      end
    end
    s.game = cc.real
    local onFinish = s.onFinish
    s.onFinish = function(result)
      if onFinish then onFinish(result) end
      if cc.onEnd then cc.onEnd(s, result) end
    end
    return BattleState.finish(s)
  end
  b.enter = function(s)
    if s.coop.entered then
      -- caught up without a screen: only what the screen needs
      s.isOpaque = s:bgMode() ~= "world"
      s:playBattleTheme()
      return
    end
    s.coop.entered = true
    return BattleState.enter(s)
  end
  b.update = function(s, dt)
    Replica.step(s)
    local mine, kind = Replica.mine(s)
    local cc = s.coop
    if cc.ask or (kind and not mine) or (cc.sent and kind) then
      s:tickFx()
      if s.phase == "menu" then s:snapIdleBars() end
      if mine and cc.ask and cc.picking ~= cc.applied then
        if cc.ask.kind == "learn" then Replica.openLearn(s) else Replica.openChoice(s) end
      end
      return
    end
    if mine and kind == "replace" then
      if cc.picking ~= cc.applied then Replica.openReplacement(s) end
      s:tickFx()
      return
    end
    if s.phase == "menu" and s.player and s.player.mon.hp > 0 then
      local locked = s:menuLockedAction(s.player)
      if locked then
        cc.applying = true
        s:clearTurnFlinches()
        BattleState.resolveTurn(s, locked)
        cc.applying = false
        return
      end
    end
    return BattleState.update(s, dt)
  end
  -- the opener's team is the record's first input
  if rec.inputs[1] then applyInput(b, rec.inputs[1]) end
  return b
end

-- A copy built from the record alone (a window joining the battle).
function Replica.build(real, rec, opts)
  local BattleState = engine()
  local open = rec.open
  local save = setmetatable({ party = real.save.party }, { __index = real.save })
  save.player = setmetatable({ rival = open.trainer and open.trainer.rival },
                             { __index = real.save.player })
  local game = setmetatable({ save = save }, { __index = real })
  local b
  if open.kind == "trainer" then
    b = BattleState.newTrainer(game, open.trainer.class, open.trainer.index)
  else
    local first = open.enemy[1]
    b = BattleState.newWild(game, first.species, first.level, { hooked = open.hooked })
  end
  return Replica.make(b, rec, opts)
end

return Replica
