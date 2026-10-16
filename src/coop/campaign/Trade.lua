-- The one trade core (#23, #60, #62; design A12.6, A12.7, G25): a trade
-- between two players of one campaign, direct (src/coop/friends) or at the
-- Cable Club (src/coop/session/HostCable.lua).  It works on save tables (a
-- window's live save and the host's copy of a player's world alike) and on
-- Pokémon rows as the game's save holds them, each with its campaign uid
-- (`coopUid`, Campaign.lua).
--
--   local text = Trade.encodeTeam(save.party)  -- the team's rows as save text
--   local team, why = Trade.decodeTeam(text)   -- the rows back, or nil and why
--   local i = Trade.find(save.party, row)      -- the team slot that row stands in
--   local how, why = Trade.swap(save, give, get)
--   local into = Trade.evolution(data, mon)    -- the species a trade evolves it into
--   -- the host:
--   local ok, why = Trade.commit(campaign, "cable:p01-p02:1",
--                                { player = "p01", give = row }, { player = "p02", give = row })
--   Trade.layOver(campaign, playerId, save)    -- a world or holdings a window sent
--   Trade.owed(campaign, playerId)             -- what that window still has to apply
--   -- the Cable Club's packed rows (src/link/Protocol.lua packMon):
--   Trade.key(packed), Trade.uidOf(campaign, id, packed), Trade.rowOf(campaign, id, uid)
--
-- A trade moves whole rows: the row a player gives leaves their team and
-- the row they get takes its slot, with its uid, its original trainer and
-- everything else it carried (design A3.2: a uid is kept through trades).
-- `Trade.swap` is idempotent, so the host and the window can both apply
-- one trade and apply it again after a dropped link without doubling it:
--
--   * "swapped": `give` stood in the team and `get` now stands in its slot;
--   * "already": the save holds `get` and not `give` (the swap is in);
--   * nil, "gone": neither, so nothing was done.
--
-- A row is found by its uid, else (a fresh catch the host has not stamped
-- yet) by its fingerprint, species and level.  The received row is marked
-- `traded` as upstream's link trade marks it (src/link/Protocol.lua
-- TradeSession:apply); the window's side effects of a trade (Pokédex,
-- Pikachu's mood, the movie, the evolution) are the game's.
--
-- Who writes what (one rule for both kinds, G25):
--   * The host commits a trade once (`Trade.commit` under a commit id,
--     `trade:<pair>` or `cable:<pair>:<n>`): both stored worlds get the
--     swap and the Pokédex mark, and each player is owed their side (the
--     campaign's `trades` per player, kept in the campaign file).
--   * Each window applies its side on its own save: on its trade screen
--     when it hears the host's yes, else at its next rest point from the
--     owed list the host sends it (#63: a window whose link dropped before
--     the yes, or that came back without its trade screen).
--   * Until a world or holdings from that window shows the trade, the host
--     lays the swap over every one it sends (`Trade.layOver`), so a copy
--     from before the window applied it cannot undo it or clone a row; a
--     copy that shows it ends the debt.

local SaveSerializer = require("src.core.SaveSerializer")
local Campaign = require("src.coop.campaign.Campaign")
local World = require("src.coop.campaign.World")
local LinkProtocol = require("src.link.Protocol")

local Trade = {}

Trade.UID = Campaign.UID_FIELD
-- a team's rows as text: six late-game rows are a few kilobytes
Trade.MAX_TEXT = 64 * 1024

local function copy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local out = {}
  seen[v] = out
  for k, x in pairs(v) do out[copy(k, seen)] = copy(x, seen) end
  return out
end
Trade.copy = copy

-- the team's rows (at most six) as the game's save text
function Trade.encodeTeam(party)
  local rows = {}
  for i, mon in ipairs(party or {}) do
    if i > World.TEAM then break end
    rows[i] = mon
  end
  return SaveSerializer.encode(rows)
end

-- the rows back from text: a list of at most six rows, or nil and why
function Trade.decodeTeam(text)
  if type(text) ~= "string" then return nil, "not text" end
  if #text > Trade.MAX_TEXT then return nil, "too long" end
  local ok, rows = pcall(SaveSerializer.decode, text)
  if not ok or type(rows) ~= "table" then return nil, "not a team" end
  local why = World.check({ player = {}, party = rows })
  if why then return nil, why end
  if #rows == 0 then return nil, "empty team" end
  return rows
end

local function same(a, b)
  local ua, ub = a[Trade.UID], b[Trade.UID]
  if Campaign.uid(ua) or Campaign.uid(ub) then return ua == ub end
  return a.species == b.species and a.level == b.level
    and Campaign.fingerprint(a) == Campaign.fingerprint(b)
end

-- the index of `row` in `list` (a team or a box), or nil
function Trade.find(list, row)
  if type(list) ~= "table" or type(row) ~= "table" then return nil end
  for i, mon in ipairs(list) do
    if type(mon) == "table" and same(mon, row) then return i end
  end
  return nil
end

-- true when any team or box row of `save` is `row`
local function holds(save, row)
  for _, at in ipairs(World.mons(save)) do
    if same(at.mon, row) then return true end
  end
  return false
end

-- One side of a trade on `save`: `give` leaves the team and a copy of
-- `get` takes its slot (a row deposited before the trade reached this
-- save, its PC slot).  Returns "swapped" (and the team slot), "already",
-- or nil and "gone".
function Trade.swap(save, give, get)
  if type(save) ~= "table" or type(give) ~= "table" or type(get) ~= "table" then
    return nil, "gone"
  end
  local list, i = save.party, Trade.find(save.party, give)
  if not i then
    if holds(save, get) then return "already" end
    for _, at in ipairs(World.mons(save)) do
      if at.box > 0 and same(at.mon, give) then list, i = save.boxes[at.box], at.slot break end
    end
    if not i then return nil, "gone" end
  end
  local row = copy(get)
  row.traded = true -- boosted EXP for a foreign trainer id, as upstream's trade
  list[i] = row
  return "swapped", nil, list == save.party and i or nil, row
end

-- the species a trade evolves `mon` into, or nil (KADABRA, MACHOKE,
-- GRAVELER, HAUNTER)
function Trade.evolution(data, mon)
  local def = data and data.pokemon and mon and data.pokemon[mon.species]
  for _, evo in ipairs(def and def.evolutions or {}) do
    if evo.method == "TRADE" then return evo.species end
  end
  return nil
end

-- the host's side --------------------------------------------------------------

-- the receiver's Pokédex: seen and owned
local function mark(save, species)
  if type(save.pokedex) ~= "table" then return end
  for _, key in ipairs({ "seen", "owned" }) do
    if type(save.pokedex[key]) == "table" then save.pokedex[key][species] = true end
  end
end
Trade.mark = mark

-- what `playerId` is owed: { id, give, get } a window of theirs has not
-- shown yet, oldest first
function Trade.owed(campaign, playerId)
  local p = campaign:player(playerId)
  return p and p.trades or {}
end

-- A trade committed once under `id` (a commit id): `a.give`, a row of
-- player `a.player`'s team, goes to `b.player` and `b.give` to `a.player`.
-- The stored worlds swap (a world that does not hold the row yet gets it
-- laid over when it comes), the receivers' Pokédexes mark the species and
-- each player is owed their side.  A row without a uid takes the one its
-- stored world gave it.  Returns true; false, "done" for a commit id
-- already applied; false, "unswapped" when a row is unknown (committed,
-- nothing moved or owed: the windows' saves carry the trade).
function Trade.commit(campaign, id, a, b)
  local moved = false
  local ok = campaign:commit(id, function(c)
    if type(a.give) ~= "table" or type(b.give) ~= "table" or a.player == b.player then return end
    local pa, pb = c:player(a.player), c:player(b.player)
    if not (pa and pb) then return end
    local ga, gb = copy(a.give), copy(b.give)
    for _, s in ipairs({ { pa, ga }, { pb, gb } }) do
      local world, row = s[1].world, s[2]
      local i = world and Trade.find(world.party, row)
      if i and not Campaign.uid(row[Trade.UID]) then row[Trade.UID] = world.party[i][Trade.UID] end
    end
    for _, s in ipairs({ { pa, ga, gb }, { pb, gb, ga } }) do
      local p, give, get = s[1], s[2], s[3]
      if p.world and Trade.swap(p.world, give, get) then mark(p.world, get.species) end
      p.trades = p.trades or {}
      p.trades[#p.trades + 1] = { id = id, give = give, get = get }
    end
    moved = true
  end)
  if not ok then return false, "done" end
  if not moved then return false, "unswapped" end
  return true
end

-- A world or holdings `playerId`'s window sent: each trade they are owed
-- is laid over it; one the save shows already (or holds neither row of)
-- is owed no more.  Returns the trades that ended, for the log.
function Trade.layOver(campaign, playerId, save)
  local p = campaign:player(playerId)
  if not (p and p.trades and #p.trades > 0) or type(save) ~= "table" then return {} end
  local keep, ended = {}, {}
  for _, t in ipairs(p.trades) do
    local how = Trade.swap(save, t.give, t.get)
    if how == "swapped" then
      mark(save, t.get.species)
      keep[#keep + 1] = t
    else
      ended[#ended + 1] = { id = t.id, how = how or "gone" }
    end
  end
  p.trades = keep
  if #ended > 0 then campaign:touch() end
  return ended
end

-- the Cable Club's packed rows --------------------------------------------------

-- what tells a Pokémon from another on the link cable: its packed form's
-- species, level, experience, original trainer, nickname and DVs
-- (src/link/Protocol.lua packMon)
function Trade.key(packed)
  if type(packed) ~= "table" then return "" end
  local d = type(packed.dvs) == "table" and packed.dvs or {}
  return table.concat({ tostring(packed.species), tostring(packed.level), tostring(packed.exp),
                        tostring(packed.otId), tostring(packed.ot), tostring(packed.nickname),
                        tostring(d.hp), tostring(d.attack), tostring(d.defense),
                        tostring(d.speed), tostring(d.special) }, "|")
end

-- the row of a player's stored team carrying `uid`, and its slot, or nil
function Trade.rowOf(campaign, playerId, uid)
  local p = campaign:player(playerId)
  local party = p and p.world and p.world.party
  if type(uid) ~= "string" or uid == "" or type(party) ~= "table" then return nil end
  for i, mon in ipairs(party) do
    if mon[Trade.UID] == uid then return mon, i end
  end
  return nil
end

-- the uid of the row in a player's stored team that `packed` was made
-- from, or "": for a window whose row had no uid yet (stamped at its next
-- rest point)
function Trade.uidOf(campaign, playerId, packed)
  local p = campaign:player(playerId)
  local party = p and p.world and p.world.party
  local want = Trade.key(packed)
  for _, mon in ipairs(type(party) == "table" and party or {}) do
    local ok, mine = pcall(LinkProtocol.packMon, mon)
    if ok and Trade.key(mine) == want and type(mon[Trade.UID]) == "string" then return mon[Trade.UID] end
  end
  return ""
end

return Trade
