-- Wild Pokémon from both versions (#9, design A13.3, A13.4, the sibling
-- fork's D104), the window's side.  A per-campaign switch, off by default:
-- with it on, a Red window's wild encounter on the upper half of a 0-255
-- roll from the world's own encounter generator becomes Blue's Pokémon of
-- the same map and slot (and the other way round), at this cartridge's
-- level for the slot, but only where that Pokémon is one this version
-- never has in the wild.  So the switch adds the other version's wild
-- exclusives (Red's EKANS and ODDISH lines, MANKEY, GROWLITHE, HORSEA, ...;
-- Blue's SANDSHREW and BELLSPROUT lines, MEOWTH, VULPIX, KRABBY, ...), each
-- taking half of its slot; shared slots, slots that only shuffle shared
-- Pokémon and maps the other version has no table for keep the cartridge's
-- odds.  Fishing, Game Corner prizes and in-game trades stay each player's
-- own.
--
-- No cartridge data is shipped or cached: every window of a paired game
-- sends its own wild slots after each welcome (step), the host passes the
-- other version's to this window while the switch is on (Client.wild), and
-- the roll is drawn only while the window holds them and the slot has an
-- exclusive to offer, so a campaign without the switch keeps the
-- cartridge's encounter stream.
--
-- The hook: OverworldController's rollEncounter hands its encounter to
-- WildMix.encounter (marked `co-op (#9)`); Encounter.roll names the slot.

local Versions = require("src.coop.session.Versions")

local WildMix = {}

-- the roll at or above this takes the other version's Pokémon
WildMix.HALF = 128

local KINDS = { "grass", "water" }

-- This version's wild slots as a window sends them: per map, the grass
-- (or cave) and water slots in the cartridge's order, species and level.
function WildMix.tables(data)
  local maps = {}
  for mapId, def in pairs(data and data.encounters or {}) do
    local entry, any = {}, false
    for _, kind in ipairs(KINDS) do
      local t = type(def) == "table" and def[kind]
      if type(t) == "table" and type(t.slots) == "table" and #t.slots > 0 then
        local slots = {}
        for i, slot in ipairs(t.slots) do
          slots[i] = { species = slot.species, level = slot.level }
        end
        entry[kind], any = slots, true
      end
    end
    if any then maps[mapId] = entry end
  end
  return maps
end

-- every species of this version's grass and water tables
local ownCache = setmetatable({}, { __mode = "k" })
function WildMix.ownWild(data)
  local encounters = data and data.encounters or {}
  local set = ownCache[encounters]
  if set then return set end
  set = {}
  for _, def in pairs(encounters) do
    for _, kind in ipairs(KINDS) do
      local t = type(def) == "table" and def[kind]
      for _, slot in ipairs(type(t) == "table" and t.slots or {}) do set[slot.species] = true end
    end
  end
  ownCache[encounters] = set
  return set
end

-- The encounter `enc` ({ species, level, slot }) on `mapId`'s `terrain`
-- ("grass", "water", or "indoor", which rolls the grass table) with the
-- other version's slots `other` (WildMix.tables' shape): the other
-- version's Pokémon on the upper half of rng(0, 255) where this version
-- never has it in the wild, else `enc` as it was.
function WildMix.substitute(enc, mapId, terrain, other, data, rng)
  if not (enc and enc.slot and other) then return enc end
  local entry = other[mapId]
  local slots = entry and entry[terrain == "water" and "water" or "grass"]
  local theirs = slots and slots[enc.slot]
  if not theirs or theirs.species == enc.species then return enc end
  if WildMix.ownWild(data)[theirs.species] then return enc end
  if not (data and data.pokemon and data.pokemon[theirs.species]) then return enc end
  if rng(0, 255) < WildMix.HALF then return enc end
  local out = {}
  for k, v in pairs(enc) do out[k] = v end
  out.species = theirs.species
  out.mixed = true
  return out
end

-- the session of this world, with the other version's slots, or nil
local function otherTables()
  local Session = package.loaded["src.coop.session.Session"]
  local s = Session and Session.current
  local c = s and s.client
  if not (c and c.status == "joined" and c.wild) then return nil end
  return c.wild.maps
end

-- the hook in OverworldController:rollEncounter
function WildMix.encounter(enc, mapId, terrain)
  if not enc then return enc end
  local other = otherTables()
  if not other then return enc end
  local Game = require("src.core.Game")
  return WildMix.substitute(enc, mapId, terrain, other, Game.data, love.math.random)
end

-- Once a link, with the game's data at hand: this window's own wild slots
-- go to the host when its game has a pair (Red, Blue, Rot, Blau).
function WildMix.step(client, data)
  if not client or client.status ~= "joined" or client.wildSent then return end
  client.wildSent = true
  if not Versions.pair(client.game) then return end
  client:sendWild(WildMix.tables(data))
end

return WildMix
