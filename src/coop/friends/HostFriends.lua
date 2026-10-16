-- Friend battles and trades on the host (#23, design A12.1 to A12.6,
-- decision G31).  The host runs no battle and no trade screen: it keeps the
-- invitations, pairs two players who agreed, passes the two windows' link
-- battle messages between them, and for a trade keeps both offers and
-- commits the swap once.
--
-- Invitations (A12.2):
--   * a player invites a partner to a BATTLE or a TRADE; a partner who is
--     away, in the opening, in a co-op battle (or joining one) or already
--     paired cannot be invited (`partner_away`, `partner_busy`), nor can
--     two invitations involve one player at once (`invite_pending`);
--   * the invited window shows the question at its next rest point and
--     answers YES or NO (NO, B and 30 s without an answer are its NO);
--   * the host expires an invitation after EXPIRE seconds (`timeout`),
--     settles it `left` when either player leaves, and checks both players
--     again on a YES (`busy` when either is not free any more);
--   * both players hear how it ended (`invite` with `answer`).
--
-- Pairings: an accepted invitation pairs the two (`pair`, by id "t…"),
-- with a seed the host deals for the link battle; the inviter is the link
-- battle's host side.  Each player hears the pairing as it stands.
--
-- Friend battle (A12.3 to A12.5): each window runs upstream's lockstep
-- link battle (src/link/LinkBattle.lua) from its own side; the host passes
-- each window's numbered messages (`pair_msg`) on to the other, keeping
-- them all, so a window that comes back after a drop hears them again from
-- the first (it keeps the ones it has not had) and sends its own again
-- (the host keeps the ones it has not had).  A partner whose link dropped
-- is `away`; after GRACE seconds the pairing is `released` and the other
-- window ends its battle.  Each window ends its side with `pair_end`; the
-- pairing is dropped once both sides did, or the other side is gone.
--
-- Direct trade (A12.6): each window sends its team as its trade screen
-- opens (`trade_team`), then the slot it offers (`trade_pick`) and its
-- TRADE or CANCEL (`trade_confirm`).  Two TRADEs commit the trade once
-- (`trade:<pair>`) with the one trade core the Cable Club uses too
-- (src/coop/campaign/Trade.lua, #62): both players' worlds in the campaign
-- get the swap, each player is owed their side until a world of theirs
-- shows it, and a window that never heard the trade was done applies it
-- at its next rest point (#63).  CANCEL, or either player leaving before
-- the commit, ends the pairing for both (`cancel`, `left`).

local Protocol = require("src.coop.session.Protocol")
local HostBattles = require("src.coop.battle.HostBattles")
local Trade = require("src.coop.campaign.Trade")

local HostFriends = {}

HostFriends.EXPIRE = 60  -- seconds an invitation waits for its answer (A12.2)
HostFriends.GRACE = 120  -- seconds a dropped partner has to come back (A12.4)

local function state(host)
  local f = host.friends
  if not f then
    f = { invites = {}, pairs = {} }
    host.friends = f
  end
  return f
end

local function now(host) return host.clock() end

local function newId(host, prefix, taken)
  for _ = 1, 64 do
    local id = prefix .. host.hex(8)
    if not taken[id] then return id end
  end
  error("no free id")
end

local function other(pair, pid)
  return pair.sides[1] == pid and pair.sides[2] or pair.sides[1]
end

local function side(pair, pid)
  return pair.sides[1] == pid or pair.sides[2] == pid
end

-- the live pairing `pid` is in (not ended, their side not over), or nil
function HostFriends.pairOf(host, pid)
  for _, pair in pairs(state(host).pairs) do
    if side(pair, pid) and not pair.ended and not pair.finished[pid] then return pair end
  end
  return nil
end

-- what `state` says this player meets a partner for, or nil (#23)
function HostFriends.meeting(host, pid)
  local pair = HostFriends.pairOf(host, pid)
  return pair and pair.kind or nil
end

local function inviteOf(host, pid)
  for _, inv in pairs(state(host).invites) do
    if inv.from == pid or inv.to == pid then return inv end
  end
  return nil
end

-- free to meet: connected, past the opening, in no co-op battle or join
-- and no pairing
function HostFriends.free(host, p)
  return p ~= nil and p.connected == true and not p.opening
    and HostBattles.of(host, p.id) == nil and HostFriends.pairOf(host, p.id) == nil
end

local function sendTo(host, pid, msg)
  local p = host.byId[pid]
  local link = p and p.link
  if link and not link.conn.closed then host:_send(link, msg) end
end

-- an invitation ended: both players hear how
local function settle(host, inv, answer)
  local f = state(host)
  if f.invites[inv.id] ~= inv then return end
  f.invites[inv.id] = nil
  local msg = { type = "invite", id = inv.id, from = inv.from, to = inv.to, kind = inv.kind,
                answer = answer }
  sendTo(host, inv.from, msg)
  sendTo(host, inv.to, msg)
  host:_log("invite_answer", { invite = inv.id, kind = inv.kind, answer = answer },
            host.byId[inv.to])
end

-- invite: the sender asks a free partner (A12.1, A12.2)
function HostFriends.invite(host, p, msg)
  local q = host.byId[msg.to]
  if not q or q == p then return false, "no_partner" end
  if not HostFriends.free(host, p) then return false, "in_battle" end
  if not q.connected then return false, "partner_away" end
  if not HostFriends.free(host, q) then return false, "partner_busy" end
  if inviteOf(host, p.id) or inviteOf(host, q.id) then return false, "invite_pending" end
  local f = state(host)
  local inv = { id = newId(host, "i", f.invites), from = p.id, to = q.id, kind = msg.kind,
                at = now(host) }
  f.invites[inv.id] = inv
  host:_log("invite", { invite = inv.id, kind = inv.kind, to = q.id }, p)
  local told = { type = "invite", id = inv.id, from = p.id, to = q.id, kind = inv.kind }
  sendTo(host, q.id, told)
  sendTo(host, p.id, told)
  return true
end

local function newPair(host, inv)
  local f = state(host)
  local pair = {
    id = newId(host, "t", f.pairs), kind = inv.kind, sides = { inv.from, inv.to },
    seed = 1 + (tonumber(host.hex(7), 16) or 1) % 2147483645,
    msgs = { [inv.from] = {}, [inv.to] = {} }, teams = {}, picks = {}, confirms = {},
    finished = {}, told = {}, at = now(host),
  }
  f.pairs[pair.id] = pair
  host.dirty = true
  host:_log("pair", { pair = pair.id, kind = pair.kind, sides = pair.sides }, host.byId[inv.from])
  return pair
end

-- the invited player's answer; a YES checks both players again
function HostFriends.answer(host, p, msg)
  local inv = state(host).invites[msg.invite]
  if not inv or inv.to ~= p.id then return false, "no_invite" end
  if not msg.yes then
    settle(host, inv, "declined")
    return true
  end
  if not (HostFriends.free(host, host.byId[inv.from]) and HostFriends.free(host, p)) then
    settle(host, inv, "busy")
    return true
  end
  settle(host, inv, "accepted")
  newPair(host, inv)
  return true
end

local function livePair(host, p, id)
  local pair = state(host).pairs[id]
  if not pair or not side(pair, p.id) or pair.ended then return nil end
  return pair
end

-- the pairing ends for both: `reason` (released, left, cancel)
local function endPair(host, pair, reason)
  if pair.ended then return end
  pair.ended = reason
  host.dirty = true
  host:_log("pair_end", { pair = pair.id, kind = pair.kind, reason = reason }, nil)
end

-- a window's link battle message, passed on to the partner in order
function HostFriends.msg(host, p, msg)
  local pair = livePair(host, p, msg.pair)
  if not pair or pair.kind ~= "battle" then return false, "no_pair" end
  local list = pair.msgs[p.id]
  -- a message heard before (sent again after a drop) changes nothing; one
  -- past a gap waits for the window to send the ones before it again
  if msg.n == #list + 1 then list[#list + 1] = msg.msg end
  return true
end

-- a window's side of the pairing ended (its battle's result, its trade
-- screen closed); a trade's CANCEL ends it for both
function HostFriends.finish(host, p, msg)
  local pair = state(host).pairs[msg.pair]
  if not pair or not side(pair, p.id) then return false, "no_pair" end
  if pair.finished[p.id] then return true end
  pair.finished[p.id] = msg.result
  host.dirty = true
  host:_log("pair_side", { pair = pair.id, kind = pair.kind, result = msg.result }, p)
  -- a trade cancelled before the swap, or a window that has no battle
  -- for this pairing any more (it was started again), ends it for both
  if pair.kind == "trade" and not pair.done and msg.result ~= "done" then
    endPair(host, pair, "cancel")
  elseif pair.kind == "battle" and msg.result == "cancel" then
    endPair(host, pair, "left")
  end
  return true
end

-- a trade: this player's team as their trade screen opened
function HostFriends.team(host, p, msg)
  local pair = livePair(host, p, msg.pair)
  if not pair or pair.kind ~= "trade" or pair.done then return false, "no_pair" end
  if pair.picks[p.id] then return false, "bad_team" end
  local rows = Trade.decodeTeam(msg.team)
  if not rows then return false, "bad_team" end
  pair.teams[p.id] = { text = msg.team, rows = rows }
  return true
end

function HostFriends.pick(host, p, msg)
  local pair = livePair(host, p, msg.pair)
  if not pair or pair.kind ~= "trade" or pair.done then return false, "no_pair" end
  local team = pair.teams[p.id]
  if not team or not team.rows[msg.slot] or pair.picks[p.id] then return false, "bad_pick" end
  pair.picks[p.id] = msg.slot
  return true
end

-- both offered and both said TRADE: the swap, once (A12.6)
local function commit(host, pair)
  local a, b = pair.sides[1], pair.sides[2]
  local rowA = pair.teams[a].rows[pair.picks[a]]
  local rowB = pair.teams[b].rows[pair.picks[b]]
  local campaign = host.state
  for _, pid in ipairs({ a, b }) do
    campaign:addPlayer({ id = pid, name = host.byId[pid] and host.byId[pid].name or "?" })
  end
  local done = Trade.commit(campaign, "trade:" .. pair.id, { player = a, give = rowA },
                            { player = b, give = rowB })
  pair.done = true
  host:_log("trade", { pair = pair.id, committed = done,
                       gave = { [a] = rowA.species, [b] = rowB.species },
                       uids = { [a] = rowA[Trade.UID], [b] = rowB[Trade.UID] } }, nil)
end

function HostFriends.confirm(host, p, msg)
  local pair = livePair(host, p, msg.pair)
  if not pair or pair.kind ~= "trade" or pair.done then return false, "no_pair" end
  local q = other(pair, p.id)
  if not (pair.picks[p.id] and pair.picks[q]) then return false, "bad_pick" end
  if not msg.yes then
    pair.finished[p.id] = "cancel"
    endPair(host, pair, "cancel")
    return true
  end
  pair.confirms[p.id] = true
  if pair.confirms[q] then commit(host, pair) end
  return true
end

-- a player's link dropped or they left (`why`: "bye" when on purpose):
-- their invitations end; a trade not yet committed ends; a battle ends
-- when they left on purpose, else waits GRACE seconds for them (tick)
function HostFriends.left(host, p, why)
  for _, inv in pairs(state(host).invites) do
    if inv.from == p.id or inv.to == p.id then settle(host, inv, "left") end
  end
  for _, pair in pairs(state(host).pairs) do
    if side(pair, p.id) and not pair.ended then
      if not pair.finished[p.id] and (pair.kind == "trade" and not pair.done
                                      or pair.kind == "battle" and why == "bye") then
        endPair(host, pair, "left")
      end
    end
  end
end

-- every frame: invitations expire; a battle whose partner stayed away
-- GRACE seconds is released; a pairing nobody waits on is dropped
function HostFriends.tick(host)
  local f = state(host)
  local t = now(host)
  for _, inv in pairs(f.invites) do
    if t - inv.at >= HostFriends.EXPIRE then settle(host, inv, "timeout") end
  end
  for id, pair in pairs(f.pairs) do
    local away = false
    for _, pid in ipairs(pair.sides) do
      local q = host.byId[pid]
      if not (q and q.connected) and not pair.finished[pid] then away = true end
    end
    if pair.kind == "battle" and not pair.ended then
      if away then
        pair.awayAt = pair.awayAt or t
        if t - pair.awayAt >= HostFriends.GRACE then endPair(host, pair, "released") end
      else
        pair.awayAt = nil
      end
    end
    -- dropped once every side is over: finished, or told of the end (a
    -- player away when it ended hears it when they come back)
    local open = false
    for _, pid in ipairs(pair.sides) do
      if not (pair.finished[pid] or (pair.ended and pair.told[pid])) then open = true end
    end
    if not open then
      f.pairs[id] = nil
      host.dirty = true
    end
  end
end

-- the pairing as `pid` sees it
local function view(host, pair, pid)
  local q = other(pair, pid)
  local partner = host.byId[q]
  local mine, theirs = pair.teams[pid], pair.teams[q]
  return {
    type = "pair", id = pair.id, kind = pair.kind, partner = q,
    role = pair.sides[1] == pid and "host" or "guest", seed = pair.seed,
    name = partner and partner.name or nil,
    away = not (partner and partner.connected) or nil,
    ended = pair.ended,
    mine = mine and mine.text or nil, theirs = theirs and theirs.text or nil,
    myPick = pair.picks[pid], theirPick = pair.picks[q],
    confirmed = pair.confirms[pid] or nil, theirConfirmed = pair.confirms[q] or nil,
    done = pair.done or nil,
  }
end

local function signature(v)
  return table.concat({ tostring(v.away), tostring(v.ended), tostring(v.mine and #v.mine),
                        tostring(v.theirs and #v.theirs), tostring(v.myPick),
                        tostring(v.theirPick), tostring(v.confirmed),
                        tostring(v.theirConfirmed), tostring(v.done) }, "|")
end

-- every frame, to each joined link: the pairings as they stand (when they
-- changed for this link) and the partner's messages this link has not had
function HostFriends.sendTo(host, link, p)
  link.pairSent = link.pairSent or {}
  link.pairRelayed = link.pairRelayed or {}
  for _, pair in pairs(state(host).pairs) do
    if side(pair, p.id) then
      local v = view(host, pair, p.id)
      local sig = signature(v)
      if link.pairSent[pair.id] ~= sig then
        link.pairSent[pair.id] = sig
        host:_send(link, v)
      end
      if pair.ended then pair.told[p.id] = true end
      local from = pair.msgs[other(pair, p.id)]
      local had = link.pairRelayed[pair.id] or 0
      for n = had + 1, #from do
        host:_send(link, { type = "pair_msg", pair = pair.id, n = n, msg = from[n] })
      end
      link.pairRelayed[pair.id] = #from
    end
  end
end

-- the host shuts down: nothing to finish (the windows hear `ended`)
function HostFriends.endAll(host)
  for _, inv in pairs(state(host).invites) do settle(host, inv, "left") end
end

HostFriends.RESULTS = Protocol.PAIR_RESULTS

return HostFriends
