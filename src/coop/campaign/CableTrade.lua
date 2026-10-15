-- A Cable Club trade on the campaign (#60, design A12.7, decision G32): the
-- two Pokémon change hands exactly once, keeping their uids.
--
--   local ok, why = CableTrade.swap(campaign, "cable:p1-p2:3",
--                                   { player = "p1", uid = "p1:4" },
--                                   { player = "p2", uid = "p2:9" })
--
-- The host calls it once both windows confirmed, before it lets either
-- window finish the trade.  Under the commit id the swap happens once: a
-- repeat returns false, "done" and changes nothing.  Each player's stored
-- world gives up the row with its uid and gets the other's row in that
-- slot, as the cartridge puts the received Pokémon where the sent one stood
-- (TradeSession:apply); the rows keep their uids, the receiver's Pokédex
-- marks the species.  The windows then play the trade movie and any trade
-- evolution on their own copies (G25: the window is the only writer of its
-- player's holdings) and their next world says the same.
--
-- When a uid is unknown or its row is not in the giver's team (a window
-- whose world never reached the host), nothing moves on the host: the
-- commit still holds, and the windows' saves carry the trade.  The API is
-- the one place a direct trade (#23) can share: a pair of { player, uid }
-- and a stable commit id.

local Campaign = require("src.coop.campaign.Campaign")
local LinkProtocol = require("src.link.Protocol")

local CableTrade = {}

local UID = Campaign.UID_FIELD

-- what tells a Pokémon from another on the link cable: its packed form's
-- species, level, experience, original trainer, nickname and DVs
-- (src/link/Protocol.lua packMon)
function CableTrade.key(packed)
  if type(packed) ~= "table" then return "" end
  local d = type(packed.dvs) == "table" and packed.dvs or {}
  return table.concat({ tostring(packed.species), tostring(packed.level), tostring(packed.exp),
                        tostring(packed.otId), tostring(packed.ot), tostring(packed.nickname),
                        tostring(d.hp), tostring(d.attack), tostring(d.defense),
                        tostring(d.speed), tostring(d.special) }, "|")
end

-- the uid of the row in a player's stored team that `packed` was made
-- from, or "": for a window whose row had no uid yet (stamped at its next
-- rest point)
function CableTrade.uidOf(campaign, playerId, packed)
  local p = campaign:player(playerId)
  local party = p and p.world and p.world.party
  local want = CableTrade.key(packed)
  for _, mon in ipairs(type(party) == "table" and party or {}) do
    local ok, mine = pcall(LinkProtocol.packMon, mon)
    if ok and CableTrade.key(mine) == want and type(mon[UID]) == "string" then return mon[UID] end
  end
  return ""
end

-- the team slot of the row carrying `uid` in a player's stored world, or nil
function CableTrade.slotOf(campaign, playerId, uid)
  local p = campaign:player(playerId)
  local party = p and p.world and p.world.party
  if type(uid) ~= "string" or uid == "" or type(party) ~= "table" then return nil end
  for i, mon in ipairs(party) do
    if mon[UID] == uid then return i end
  end
  return nil
end

local function mark(world, species)
  if type(world.pokedex) ~= "table" then return end
  for _, key in ipairs({ "seen", "owned" }) do
    if type(world.pokedex[key]) == "table" then world.pokedex[key][species] = true end
  end
end

-- true when the commit went through and the rows moved; false and why
-- otherwise ("done": this trade was committed before; "unswapped": committed,
-- but a row was not on the host)
function CableTrade.swap(campaign, id, a, b)
  local moved = false
  local ok = campaign:commit(id, function(c)
    local sa = CableTrade.slotOf(c, a.player, a.uid)
    local sb = CableTrade.slotOf(c, b.player, b.uid)
    if not (sa and sb) or a.player == b.player then return end
    local wa, wb = c:player(a.player).world, c:player(b.player).world
    local ra, rb = wa.party[sa], wb.party[sb]
    wa.party[sa], wb.party[sb] = rb, ra
    mark(wa, rb.species)
    mark(wb, ra.species)
    moved = true
  end)
  if not ok then return false, "done" end
  if not moved then return false, "unswapped" end
  return true
end

return CableTrade
