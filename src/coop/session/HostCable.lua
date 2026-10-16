-- The Cable Club on the host (#60, design A12.7 to A12.9, decision G32):
-- who a player's cable reaches, the link-cable messages between the two,
-- and the one place a Cable Club trade happens.
--
--   HostCable.enter(host, p, msg)  -- `cable`: a room behind the receptionist, or "none"
--   HostCable.link(host, p, msg)   -- `cable_link`: a link message for the mate
--   HostCable.tick(host, now)      -- every frame: a stalled trade goes back to its lists
--   HostCable.left(host, p)        -- a player's link dropped
--   HostCable.room(host, id)       -- the room a player is in, for `state`
--
-- A window behind the receptionist runs upstream's link-cable screens
-- (src/link/LinkState.lua: the trade screen, the link battle) over the
-- session instead of a LAN cable; the host passes each message to the mate.
--
-- Partners (A12.7): a player enters the TRADE CENTER or the COLOSSEUM.
-- Among the players waiting in a room, an offer either side made pairs
-- first (a player who offered the cable to a partner who is connected and
-- free waits for them); the rest pair in id order, two by two.  A pair is
-- kept while both stay; a third player in a room of two gets no cable and
-- waits.  When one of a pair leaves the room or drops, the cable is gone
-- for both: both are out of the room (`cable` "none"), and the other
-- window's screen goes back to the receptionist's menu.
--
-- Trades (A12.7): the host reads the trade's party, pick and confirm
-- messages.  A confirm is held until both confirmed; then the host swaps
-- the two Pokémon once in the stored worlds (CableTrade.swap, uids kept),
-- saves the campaign and only then hands each window the other's confirm
-- with the uid of the Pokémon it receives.  So a trade is either in both
-- worlds or in neither.  No offer within OFFER_WAIT seconds of the first,
-- or no answer within ANSWER_WAIT seconds of both offers, and the host
-- moves the trade's round on: both screens go back to their lists, and
-- messages of the old round are dropped.
--
-- The Colosseum (A12.9): the link battle runs in both windows from the
-- lead's seed, each against a copy of the other's team; the host passes
-- its messages and keeps nothing (no co-op battle, no prize, no save).

local CableTrade = require("src.coop.campaign.CableTrade")

local HostCable = {}

HostCable.OFFER_WAIT = 30  -- seconds from the first offer to the second
HostCable.ANSWER_WAIT = 60 -- seconds from both offers to both answers

local function state(host)
  host.cable = host.cable or { players = {}, pairs = {} }
  return host.cable
end

local function freshTrade()
  return { uids = {}, mons = {}, picks = {}, confirms = {}, pickedAt = nil, bothAt = nil }
end

function HostCable.room(host, id)
  local e = host.cable and host.cable.players[id]
  return e and e.room or nil
end

local function send(host, id, msg)
  local p = host.byId[id]
  local link = p and p.connected and p.link
  if link and not link.conn.closed then host:_send(link, msg) end
end

local function tell(host, id)
  local e = state(host).players[id]
  if not e then
    return send(host, id, { type = "cable", room = "none", round = 0 })
  end
  local pair = e.pair
  local mate = pair and (pair.a == id and pair.b or pair.a)
  local mp = mate and host.byId[mate]
  send(host, id, { type = "cable", room = e.room, round = pair and pair.round or 0,
                   mate = mate, name = mp and mp.name or nil,
                   lead = pair and pair.a == id or nil })
end

local match

-- the cable between two players ends: both are out of their room
local function unpair(host, pair, why)
  local cs = state(host)
  cs.pairs[pair.id] = nil
  for _, id in ipairs({ pair.a, pair.b }) do
    cs.players[id] = nil
    tell(host, id)
  end
  host.dirty = true
  host:_log("cable_end", { pair = pair.id, why = why })
  match(host) -- an offer to one of them may stand no more
end

local function pairUp(host, x, y)
  local a, b = x, y
  if b < a then a, b = b, a end
  local cs = state(host)
  local pair = { id = a .. "-" .. b, a = a, b = b, room = cs.players[a].room,
                 round = 1, trades = 0, trade = freshTrade() }
  cs.pairs[pair.id] = pair
  cs.players[a].pair, cs.players[b].pair = pair, pair
  host:_log("cable_pair", { pair = pair.id, room = pair.room })
  tell(host, a)
  tell(host, b)
end

-- connected, and in no cable or waiting for one
local function free(host, id)
  local p = host.byId[id]
  if not (p and p.connected) then return false end
  local e = state(host).players[id]
  return e == nil or e.pair == nil
end

-- the waiting players of each room find their mates (A12.7)
function match(host)
  local cs = state(host)
  for _, room in ipairs({ "trade", "colosseum" }) do
    local waiting, at = {}, {}
    for id, e in pairs(cs.players) do
      if e.room == room and not e.pair and free(host, id) then waiting[#waiting + 1] = id end
    end
    table.sort(waiting)
    for _, id in ipairs(waiting) do at[id] = true end
    -- an offer either side made
    for _, id in ipairs(waiting) do
      local e = cs.players[id]
      if at[id] and e.with and at[e.with] and e.with ~= id then
        at[id], at[e.with] = nil, nil
        pairUp(host, id, e.with)
      end
    end
    -- the rest in id order; one whose offer still stands waits for its partner
    local rest = {}
    for _, id in ipairs(waiting) do
      local e = cs.players[id]
      local offered = e.with and e.with ~= id and free(host, e.with)
      if at[id] and not offered then rest[#rest + 1] = id end
    end
    for i = 1, #rest - 1, 2 do pairUp(host, rest[i], rest[i + 1]) end
  end
end

-- `cable`: enter a room (msg.with: the partner this player offered the
-- cable to), or leave it
function HostCable.enter(host, p, msg)
  local cs = state(host)
  local e = cs.players[p.id]
  if msg.room == "none" then
    if e and e.pair then
      unpair(host, e.pair, "left")
    elseif e then
      cs.players[p.id] = nil
      host.dirty = true
      tell(host, p.id)
      match(host)
    end
    return true
  end
  if e and e.pair then
    if e.room == msg.room then return true end -- kept while both stay
    unpair(host, e.pair, "moved")
  end
  cs.serial = (cs.serial or 0) + 1
  cs.players[p.id] = { room = msg.room, with = msg.with, since = cs.serial }
  host.dirty = true
  host:_log("cable_enter", { room = msg.room, with = msg.with }, p)
  match(host)
  if not cs.players[p.id].pair then tell(host, p.id) end
  return true
end

local function mateOf(pair, id)
  return pair.a == id and pair.b or pair.a
end

-- the trade's round moves on: both screens go back to their lists
local function reset(host, pair, why)
  pair.round = pair.round + 1
  pair.trade = freshTrade()
  host:_log("cable_reset", { pair = pair.id, round = pair.round, why = why })
  tell(host, pair.a)
  tell(host, pair.b)
end

-- both confirmed: the swap, once, then each window hears the other's yes
local function commit(host, pair)
  local t = pair.trade
  for _, id in ipairs({ pair.a, pair.b }) do
    local q = host.byId[id]
    if not (q and q.connected) then
      return unpair(host, pair, "dropped")
    end
  end
  -- the uid the window named, else the stored row the packed one was
  -- made from (a row whose uid the window has not stamped yet)
  local function uidOf(id)
    local pick = t.picks[id]
    if type(pick) ~= "number" then return "" end
    local uid = (t.uids[id] or {})[pick]
    if type(uid) == "string" and uid ~= "" and CableTrade.slotOf(host.state, id, uid) then
      return uid
    end
    return CableTrade.uidOf(host.state, id, (t.mons[id] or {})[pick])
  end
  local ua, ub = uidOf(pair.a), uidOf(pair.b)
  pair.trades = pair.trades + 1
  local id = ("cable:%s:%d"):format(pair.id, pair.trades)
  local swapped, why = CableTrade.swap(host.state, id, { player = pair.a, uid = ua },
                                       { player = pair.b, uid = ub })
  host:_log("cable_trade", { pair = pair.id, commit = id, a = ua, b = ub,
                             swapped = swapped, why = why })
  -- the campaign is saved with the trade in it (design A12.7)
  host:_autosave("link")
  local yes = { type = "confirm", ok = true }
  send(host, pair.a, { type = "cable_link", round = pair.round, link = yes, uid = ub })
  send(host, pair.b, { type = "cable_link", round = pair.round, link = yes, uid = ua })
  pair.trade = freshTrade()
end

-- the trade messages the host reads before passing them on; false when the
-- message is held (a confirm waiting for the other's)
local function readTrade(host, pair, p, msg)
  local t, link, now = pair.trade, msg.link, host.clock()
  local mate = mateOf(pair, p.id)
  if link.type == "party" then
    -- a new party starts this window's round over (the next trade)
    t.uids[p.id] = msg.uids or {}
    t.mons[p.id] = link.mons or {}
    t.picks[p.id], t.confirms[p.id] = nil, nil
  elseif link.type == "pick" then
    t.picks[p.id] = link.index
    if t.picks[mate] ~= nil then
      t.pickedAt, t.bothAt = nil, now
    else
      t.pickedAt = t.pickedAt or now
    end
  elseif link.type == "confirm" and link.ok == true then
    if t.picks[p.id] == nil or t.picks[mate] == nil then return false end
    t.confirms[p.id] = true
    if t.confirms[mate] then commit(host, pair) end
    return false
  elseif link.type == "bye" then
    pair.trade = freshTrade()
  end
  return true
end

-- `cable_link`: a link message for this player's mate
function HostCable.link(host, p, msg)
  local e = state(host).players[p.id]
  local pair = e and e.pair
  if not pair then return false, "no_cable" end
  if msg.round ~= pair.round then return false, "stale" end
  if pair.room == "trade" and not readTrade(host, pair, p, msg) then return true end
  send(host, mateOf(pair, p.id), { type = "cable_link", round = pair.round, link = msg.link })
  return true
end

-- a stalled trade goes back to its lists (A12.7)
function HostCable.tick(host, now)
  if not host.cable then return end
  for _, pair in pairs(host.cable.pairs) do
    local t = pair.trade
    if t.pickedAt and now - t.pickedAt >= HostCable.OFFER_WAIT then
      reset(host, pair, "no_offer")
    elseif t.bothAt and now - t.bothAt >= HostCable.ANSWER_WAIT then
      reset(host, pair, "no_answer")
    end
  end
end

-- a player's link dropped: their cable is gone, for their mate too
function HostCable.left(host, p)
  local cs = host.cable
  local e = cs and cs.players[p.id]
  if not e then return end
  if e.pair then return unpair(host, e.pair, "dropped") end
  cs.players[p.id] = nil
  host.dirty = true
  match(host)
end

return HostCable
