-- Co-op battles on the host (#18, design A8, decision G24).
--
-- The host runs no battle engine.  A co-op battle is lockstep, the way
-- upstream's link battles are (src/link/LinkBattle.lua): every window in
-- the battle runs the game's own battle (src/coop/battle/Replica.lua) from
-- the same opening, the same seed and the same inputs, in the same order,
-- so every copy comes to the same state.  The host keeps the battle's
-- record and decides what goes into it:
--
--   * the opening: what the opening window's world prepared (the enemy,
--     the trainer, the map; design A1.10 trusts it) and a seed it deals;
--   * the inputs, numbered: each team that joins (its Pokémon go behind the
--     roster, design A8.5) and each accepted command; a battle's revision
--     is how many inputs it has (A8.7);
--   * what the battle asks now and of whom: every window reports where its
--     copy stands (`battle_at`: a question at revision n for a player, or
--     the end); the first report of a revision is taken and later ones are
--     compared (a different one is a desync, logged);
--   * the suggestions to whoever decides (A8.8), cleared with each input.
--
-- A command is taken only for the revision the battle is at, from the
-- player the battle asks, of a kind that answers the question; anything
-- else is refused and changes nothing (A8.7).  A join waits in the queue
-- until the battle asks for a move (a forced replacement, a move to learn
-- or MIMIC's choice make it wait, A8.4) and then goes in at once, behind
-- the roster, trimmed to the room left of twelve (A8.5, A8.9).  A player
-- is in one battle at a time (A8.1).  A battle that ended is reported to
-- its players once and dropped, so nothing of it can be applied twice
-- (A8.21).
--
-- State lives on the host: host.battles (id -> battle) and host.joins
-- (player id -> queued join); Host:busy() reads both (design A3.7).

local Protocol = require("src.coop.session.Protocol")

local HostBattles = {}

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function healthy(team)
  for _, m in ipairs(team) do
    if (m.hp or 0) > 0 then return true end
  end
  return false
end

local function participant(b, pid)
  for _, e in ipairs(b.players) do
    if e.id == pid then return e end
  end
  return nil
end

-- the battle a player is in or queued for, or nil (design A8.1)
function HostBattles.of(host, pid)
  for id, b in pairs(host.battles) do
    if not b.ended and participant(b, pid) then return id end
  end
  local q = host.joins[pid]
  return q and q.battle or nil
end

-- the battle a player fights in (not a queued join), for `state`
function HostBattles.fighting(host, pid)
  for id, b in pairs(host.battles) do
    if not b.ended and participant(b, pid) then return id end
  end
  return nil
end

local function newId(host)
  for _ = 1, 64 do
    local id = "b" .. host.hex(8)
    if not host.battles[id] then return id end
  end
  error("no free battle id")
end

local function newSeed(host)
  return tonumber(host.hex(7), 16) % 2147483646 + 1
end

local function rosterSize(b)
  local n = 0
  for _, input in ipairs(b.inputs) do
    if input.kind == "join" then n = n + #input.team end
  end
  return n
end

local function push(host, b, input)
  b.inputs[#b.inputs + 1] = input
  b.ask = nil
  b.suggestions = {}
  host.dirty = true
end

local function joinInput(p, team, otId, expAll)
  return { kind = "join", player = p.id, name = p.name, team = team,
           otId = otId, expAll = expAll == true }
end

-- A battle the player's world opened (design A8.2): the opening and the
-- player's team as its first input.
function HostBattles.open(host, p, msg)
  if HostBattles.of(host, p.id) then return nil, "in_battle" end
  if not healthy(msg.team) then return nil, "no_pokemon" end
  local b = {
    id = newId(host), seed = newSeed(host),
    open = { kind = msg.kind, enemy = msg.enemy, map = msg.map, by = p.id,
             trainer = msg.trainer, hooked = msg.hooked, foe = msg.foe },
    inputs = {}, players = { { id = p.id, present = true } },
    ask = nil, suggestions = {}, ended = nil,
  }
  host.battles[b.id] = b
  push(host, b, joinInput(p, msg.team, msg.otId, msg.expAll))
  host:_log("battle_open", { battle = b.id, seed = b.seed, kind = b.open.kind,
                             map = b.open.map, foe = b.open.foe,
                             trainer = b.open.trainer, team = #msg.team }, p)
  return b
end

-- the queued joins waiting for this battle, oldest first
local function queued(host, b)
  local out = {}
  for pid, q in pairs(host.joins) do
    if q.battle == b.id then out[#out + 1] = { pid = pid, q = q } end
  end
  table.sort(out, function(x, y) return x.q.order < y.q.order end)
  return out
end

-- At a safe point (the battle asks for a move, design A8.4) the queued
-- joins go in, in the order they came, each trimmed to the room left
-- (A8.5); a team with no room is refused (`roster_full`).
local function applyJoins(host, b)
  for _, e in ipairs(queued(host, b)) do
    local q, p = e.q, host.byId[e.pid]
    host.joins[e.pid] = nil
    host.dirty = true
    local room = Protocol.MAX_ROSTER - rosterSize(b)
    if room <= 0 or not p then
      if p and p.link then host:_refuse(p.link, q.seq, "roster_full") end
      host:_log("battle_join_refused", { battle = b.id, why = "roster_full" }, p)
    else
      local team = {}
      for i = 1, math.min(room, #q.team) do team[i] = q.team[i] end
      b.players[#b.players + 1] = { id = p.id, present = p.connected == true }
      push(host, b, joinInput(p, team, q.otId, q.expAll))
      host:_log("battle_join", { battle = b.id, rev = #b.inputs, team = #team,
                                 sat_out = #q.team - #team }, p)
    end
  end
end

local function atSafePoint(b)
  return b.ask ~= nil and b.ask.rev == #b.inputs and b.ask.kind == "menu"
end

-- Join a running battle from anywhere (design A8.3): queued until the
-- battle asks for a move.
function HostBattles.join(host, p, msg)
  local b = host.battles[msg.battle]
  if not b or b.ended then return nil, "no_battle" end
  if HostBattles.of(host, p.id) then return nil, "in_battle" end
  if not healthy(msg.team) then return nil, "no_pokemon" end
  if rosterSize(b) >= Protocol.MAX_ROSTER then return nil, "roster_full" end
  host.joinOrder = (host.joinOrder or 0) + 1
  host.joins[p.id] = { battle = b.id, team = msg.team, otId = msg.otId,
                       expAll = msg.expAll, seq = msg.seq, order = host.joinOrder }
  host.dirty = true
  host:_log("battle_join_queued", { battle = b.id, team = #msg.team }, p)
  if atSafePoint(b) then applyJoins(host, b) end
  return b
end

-- A command at revision rev (design A8.6, A8.7): only for the battle's
-- current question, from the player it asks.
function HostBattles.cmd(host, p, msg)
  local b = host.battles[msg.battle]
  if not b or b.ended then return nil, "no_battle" end
  local me = participant(b, p.id)
  if not me or not me.present then return nil, "not_in_battle" end
  if msg.rev ~= #b.inputs then return nil, "stale" end
  local ask = b.ask
  if not ask or ask.rev ~= #b.inputs then return nil, "not_ready" end
  if ask.by ~= p.id then return nil, "not_yours" end
  local c = msg.cmd
  if Protocol.CMDS[c.kind] ~= ask.kind then return nil, "bad_cmd" end
  if (c.kind == "switch" or c.kind == "replace") and not (c.index and c.index <= rosterSize(b)) then
    return nil, "bad_cmd"
  end
  if (c.kind == "move" or c.kind == "mimic") and not (c.slot or c.index) then return nil, "bad_cmd" end
  if (c.kind == "item" or c.kind == "ball") and not c.item then return nil, "bad_cmd" end
  if c.kind == "choice" and c.yes == nil then return nil, "bad_cmd" end
  -- a catch is for a player in the battle (design A7.6)
  if c.target and not participant(b, c.target) then return nil, "bad_cmd" end
  -- RUN flees for the player whose world started the fight (design A9.5);
  -- leaving a battle is #20
  if c.kind == "run" and p.id ~= b.open.by then return nil, "run_initiator" end
  push(host, b, { kind = "cmd", player = p.id, cmd = c })
  host:_log("battle_cmd", { battle = b.id, rev = #b.inputs, cmd = c }, p)
  return b
end

-- A suggestion to whoever decides (design A8.8): kept apart from the
-- inputs, never applied, cleared when the revision moves on.  The player
-- who decides cannot suggest to themselves.
function HostBattles.suggest(host, p, msg)
  local b = host.battles[msg.battle]
  if not b or b.ended then return nil, "no_battle" end
  local me = participant(b, p.id)
  if not me or not me.present then return nil, "not_in_battle" end
  if msg.rev ~= #b.inputs then return nil, "stale" end
  local ask = b.ask
  if not ask or ask.rev ~= #b.inputs then return nil, "not_ready" end
  if ask.by == p.id then return nil, "not_yours" end
  if msg.cmd and Protocol.CMDS[msg.cmd.kind] ~= ask.kind then return nil, "bad_cmd" end
  b.suggestions[p.id] = msg.cmd
  host.dirty = true
  return b
end

local function finish(host, b, result, by)
  b.ended = result
  host.dirty = true
  host:_log("battle_end", { battle = b.id, result = result, rev = #b.inputs }, by)
  -- a join still queued is released (design A11.8), and hears the end
  b.released = {}
  for _, e in ipairs(queued(host, b)) do
    host.joins[e.pid] = nil
    b.released[e.pid] = true
  end
end

-- Where a window's copy of the battle stands (`battle_at`): the first
-- report of a revision is taken; one that differs is a desync, logged.
function HostBattles.at(host, p, msg)
  local b = host.battles[msg.battle]
  if not b or b.ended then return nil end
  if not participant(b, p.id) then return nil end
  if msg.rev ~= #b.inputs then return nil end -- an older revision: nothing to take
  if msg.ended then
    finish(host, b, msg.ended, p)
    return b
  end
  if not msg.ask or not msg.by or not participant(b, msg.by) then return nil end
  local ask = b.ask
  if ask and ask.rev == msg.rev then
    if ask.kind ~= msg.ask or ask.by ~= msg.by or (ask.hash and msg.hash and ask.hash ~= msg.hash) then
      host:_log("battle_desync", { battle = b.id, rev = msg.rev,
                                   taken = { ask = ask.kind, by = ask.by, hash = ask.hash, from = ask.from },
                                   seen = { ask = msg.ask, by = msg.by, hash = msg.hash } }, p)
    end
    return b
  end
  b.ask = { rev = msg.rev, kind = msg.ask, by = msg.by, hash = msg.hash, from = p.id }
  host.dirty = true
  host:_log("battle_ask", { battle = b.id, rev = msg.rev, ask = msg.ask, by = msg.by,
                            hash = msg.hash }, p)
  if atSafePoint(b) then applyJoins(host, b) end
  return b
end

-- A player's link went away: they are absent from their battle (design
-- A11.1, #20 adds the rest); a queued join is dropped.
function HostBattles.left(host, p)
  for _, b in pairs(host.battles) do
    local me = participant(b, p.id)
    if me and me.present then
      me.present = false
      host.dirty = true
    end
  end
  if host.joins[p.id] then
    host.joins[p.id] = nil
    host.dirty = true
  end
end

-- a player came back: present again in a battle still running
function HostBattles.back(host, p)
  for _, b in pairs(host.battles) do
    local me = participant(b, p.id)
    if me and not b.ended then
      me.present = true
      host.dirty = true
    end
  end
end

-- what the battle looks like to its players, apart from its inputs
local function signature(b)
  local parts = { tostring(b.ended), b.ask and (b.ask.rev .. b.ask.kind .. b.ask.by) or "-" }
  for _, e in ipairs(b.players) do parts[#parts + 1] = e.id .. tostring(e.present) end
  local by = {}
  for pid in pairs(b.suggestions) do by[#by + 1] = pid end
  table.sort(by)
  for _, pid in ipairs(by) do
    local c = b.suggestions[pid]
    parts[#parts + 1] = pid .. c.kind .. tostring(c.slot or c.index or c.item or c.yes)
  end
  return table.concat(parts, "|")
end

-- This link's player hears every battle they are in or queued for: the
-- inputs it has not had yet (the opening with the first), and the ask,
-- suggestions and players when they changed.
function HostBattles.sendTo(host, link, p)
  link.battles = link.battles or {}
  for id, b in pairs(host.battles) do
    local q = host.joins[p.id]
    if participant(b, p.id) or (q and q.battle == id) or (b.released and b.released[p.id]) then
      local sent = link.battles[id] or { n = 0 }
      link.battles[id] = sent
      local sig = signature(b)
      if sent.n < #b.inputs or sent.sig ~= sig then
        local from = sent.n + 1
        local inputs = {}
        for i = from, math.min(#b.inputs, sent.n + Protocol.MAX_INPUTS) do
          inputs[#inputs + 1] = b.inputs[i]
        end
        local players = {}
        for i, e in ipairs(b.players) do players[i] = { id = e.id, present = e.present } end
        local suggestions = {}
        for pid, c in pairs(b.suggestions) do suggestions[#suggestions + 1] = { by = pid, cmd = c } end
        local ask = b.ask and b.ask.rev == #b.inputs and b.ask or nil
        host:_send(link, {
          type = "battle", id = id, rev = #b.inputs, seed = b.seed, from = from,
          inputs = inputs, players = players, open = from == 1 and b.open or nil,
          ask = ask and ask.kind, by = ask and ask.by, suggestions = suggestions,
          ended = b.ended,
        })
        sent.n = sent.n + #inputs
        sent.sig = sent.n == #b.inputs and sig or nil
      end
    end
  end
end

-- after every link heard it, an ended battle is dropped (design A8.21)
function HostBattles.sweep(host)
  for id, b in pairs(host.battles) do
    if b.ended then
      host.battles[id] = nil
      for _, link in ipairs(host.links) do
        if link.battles then link.battles[id] = nil end
      end
    end
  end
end

-- the running battles for `state` (the CO-OP menu's JOIN rows, #34)
function HostBattles.summaries(host)
  local out = {}
  for id, b in pairs(host.battles) do
    if not b.ended then
      local players = {}
      for i, e in ipairs(b.players) do players[i] = e.id end
      out[#out + 1] = { id = id, by = b.open.by, kind = b.open.kind, foe = b.open.foe,
                        players = players, joinable = rosterSize(b) < Protocol.MAX_ROSTER }
    end
  end
  table.sort(out, function(x, y) return x.id < y.id end)
  return out
end

HostBattles.rosterSize = rosterSize
HostBattles.count = count

return HostBattles
