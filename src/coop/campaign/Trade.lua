-- The swap core of a trade between two players of one campaign (#23,
-- design A12.6; the Cable Club's trades, #60, are to share it).  It is
-- game-agnostic: it works on save tables (a window's live save and the
-- host's copy of a player's world alike) and on Pokémon rows as the game's
-- save holds them, each with its campaign uid (`coopUid`, Campaign.lua).
--
--   local text = Trade.encodeTeam(save.party)  -- the team's rows as save text
--   local team, why = Trade.decodeTeam(text)   -- the rows back, or nil and why
--   local i = Trade.find(save.party, row)      -- the team slot that row stands in
--   local how, why = Trade.swap(save, give, get)
--   local into = Trade.evolution(data, mon)    -- the species a trade evolves it into
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
-- Pikachu's mood, the movie, the evolution) are the game's
-- (src/coop/friends/TradeScreen.lua).
--
-- Who calls it (#23): the host when it commits a trade once
-- (`trade:<pair>`, src/coop/friends/HostFriends.lua), on both players'
-- worlds, and on every world or holdings a window sends until that window
-- shows the swap; each window on its own live save when the host says the
-- trade is done.

local SaveSerializer = require("src.core.SaveSerializer")
local Campaign = require("src.coop.campaign.Campaign")
local World = require("src.coop.campaign.World")

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
-- `get` takes its slot.  Returns "swapped", "already", or nil and "gone".
function Trade.swap(save, give, get)
  if type(save) ~= "table" or type(give) ~= "table" or type(get) ~= "table" then
    return nil, "gone"
  end
  local i = Trade.find(save.party, give)
  if not i then
    if holds(save, get) then return "already" end
    return nil, "gone"
  end
  local row = copy(get)
  row.traded = true -- boosted EXP for a foreign trainer id, as upstream's trade
  save.party[i] = row
  return "swapped", nil, i
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

return Trade
