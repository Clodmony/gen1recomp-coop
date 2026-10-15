-- Who owns each part of a Gen 1 world (#14, design A5.1, decision G21):
-- the campaign (one value for every player) or the player (their own).
--
-- The campaign's entries are the shared story.  They travel as a flat map
-- of paths to plain values, so two windows that set two flags at once both
-- survive (design A5.2):
--
--   flags/<EVENT>               true      story, gate and progress flags
--   objectToggles/<MAP>/<OBJ>   boolean   hidden (false) or shown objects
--   defeatedTrainers/<NPC>      true      beaten trainers and static Pokémon
--   itemsTaken/<NPC>            true      item balls picked up
--   inventory/<BADGE>           number    the eight badges (kept as items)
--   trashPuzzle/first|second    number    Vermilion Gym's trash-can locks
--
-- Everything else is the player's: team, PC, bag, money, Pokédex, position,
-- hidden items, the FLY list, step counters, the Safari game, the daycare,
-- the Hall of Fame, Yellow's PIKACHU.  A key nobody listed here is the
-- player's, so a new key never reaches a partner unclassified.
--
-- This engine keeps no per-map script bytes (pokered's wXxxCurScript): a
-- visit's progress lives on the live overworld and is never saved, so a
-- bystander never replays a leader's lines from a shared step (A5.9).
-- What the cartridge keeps in those bytes and this engine keeps in flags
-- that follow one player's walk is listed in PLAYER_FLAGS.
--
--   local view = Ownership.view(save)        -- the campaign's entries
--   Ownership.write(save, path, value)       -- one entry back (nil clears)
--   Ownership.strip(save)                    -- a player's world without them
--   Ownership.overlay(save, story)           -- the campaign's over a world

local Ownership = {}

Ownership.MAX_PATH = 96

-- the badges are inventory items in this engine (src/inventory/Badges.lua)
Ownership.BADGES = {
  BOULDERBADGE = true, CASCADEBADGE = true, THUNDERBADGE = true,
  RAINBOWBADGE = true, SOULBADGE = true, MARSHBADGE = true,
  VOLCANOBADGE = true, EARTHBADGE = true,
}

-- Event flags that are each player's: by default a flag is the campaign's
-- (the team rule, D91: a gate, unlock or progress flag one player clears
-- is cleared for both).
Ownership.PLAYER_FLAGS = {
  -- the Safari game: each player's 30 balls and 500 steps (A5.12, D81)
  EVENT_IN_SAFARI_ZONE = true, EVENT_SAFARI_GAME_OVER = true,
  -- Pokémon Tower's purified zone latches until that player steps off (D82)
  EVENT_IN_PURIFIED_ZONE = true,
  -- the Pokémon Mansion switch (D86)
  EVENT_MANSION_SWITCH_ON = true,
  -- the fossil lab: the fossil given and the two after it (D86)
  EVENT_GAVE_FOSSIL_TO_LAB = true, EVENT_LAB_STILL_REVIVING_FOSSIL = true,
  EVENT_LAB_HANDING_OVER_FOSSIL_MON = true,
  -- the Elite Four walk-ins and Lance's door lock (D93)
  EVENT_AUTOWALKED_INTO_LORELEIS_ROOM = true, EVENT_AUTOWALKED_INTO_BRUNOS_ROOM = true,
  EVENT_AUTOWALKED_INTO_AGATHAS_ROOM = true,
  EVENT_LANCES_ROOM_LOCK_DOOR = true,
  -- gift Pokémon, one per player (A7.9, D62); LAPRAS received (A5.15, D85)
  EVENT_GOT_EEVEE = true, EVENT_GOT_LAPRAS = true, EVENT_BOUGHT_MAGIKARP = true,
  EVENT_GOT_HITMONLEE = true, EVENT_GOT_HITMONCHAN = true,
  EVENT_DEFEATED_FIGHTING_DOJO = true,
  EVENT_GOT_BULBASAUR_IN_CERULEAN = true, EVENT_GOT_SQUIRTLE_FROM_OFFICER_JENNY = true,
  -- each player picks their own starter (the opening is #22)
  EVENT_GOT_STARTER = true, EVENT_CHOSE_BULBASAUR = true,
  EVENT_CHOSE_CHARMANDER = true, EVENT_CHOSE_SQUIRTLE = true,
  EVENT_CHOSE_PIKACHU = true,
}

-- the balls of gift Pokémon are each player's too (A7.9): map -> object
Ownership.PLAYER_OBJECTS = {
  CELADON_MANSION_ROOF_HOUSE = { CELADONMANSION_ROOF_HOUSE_EEVEE_POKEBALL = true },
  FIGHTING_DOJO = { FIGHTINGDOJO_HITMONLEE_POKE_BALL = true,
                    FIGHTINGDOJO_HITMONCHAN_POKE_BALL = true },
  OAKS_LAB = { OAKSLAB_EEVEE_POKE_BALL = true },
}

-- Walk flags the cartridge clears itself when the player walks out: kept by
-- nobody once the host opens a campaign (A5.13, D94).  `save.safari` stands
-- in for EVENT_IN_SAFARI_ZONE in this engine.
Ownership.WALK_FLAGS = { EVENT_IN_SAFARI_ZONE = true, EVENT_SAFARI_GAME_OVER = true }
Ownership.WALK_KEYS = { safari = true, safariGameOver = true, safariNags = true }

-- A pulled flag that changes the map it belongs to owes a window standing
-- there a reload (A5.7): the block swaps are stamped when a map loads.
local RELOADS = {
  EVENT_1ST_LOCK_OPENED = "VERMILION_GYM",
  EVENT_2ND_LOCK_OPENED = "VERMILION_GYM",
  EVENT_VICTORY_ROAD_1_BOULDER_ON_SWITCH = "VICTORY_ROAD_1F",
  EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH1 = "VICTORY_ROAD_2F",
  EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH2 = "VICTORY_ROAD_2F",
  EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH1 = "VICTORY_ROAD_3F",
  EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH2 = "VICTORY_ROAD_3F",
  EVENT_BEAT_LORELEIS_ROOM_TRAINER_0 = "LORELEIS_ROOM",
  EVENT_BEAT_BRUNOS_ROOM_TRAINER_0 = "BRUNOS_ROOM",
  EVENT_BEAT_AGATHAS_ROOM_TRAINER_0 = "AGATHAS_ROOM",
  EVENT_BEAT_LANCES_ROOM_TRAINER_0 = "LANCES_ROOM",
}
for i = 0, 5 do
  RELOADS["EVENT_CINNABAR_GYM_GATE" .. i .. "_UNLOCKED"] = "CINNABAR_GYM"
end
Ownership.RELOADS = RELOADS

-- Victory Road's switches: a window still on that floor keeps them open
-- until it leaves (A5.17, D89), so a clear waits there
local KEEP_ON_FLOOR = {}
for flag, map in pairs(RELOADS) do
  if flag:find("^EVENT_VICTORY_ROAD_") then KEEP_ON_FLOOR[flag] = map end
end

local SEGMENT = "[%w_%-%.]+"

local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- the parts of a path: family and keys, or nil
local function parts(path)
  if type(path) ~= "string" or #path > Ownership.MAX_PATH then return nil end
  local out = {}
  for seg in path:gmatch("[^/]+") do
    if not seg:find("^" .. SEGMENT .. "$") then return nil end
    out[#out + 1] = seg
  end
  if table.concat(out, "/") ~= path then return nil end
  return out
end

-- Families: where an entry lives in the save and what value it takes.
-- depth is the number of keys after the family name.
local FAMILIES = {
  flags = { depth = 1, value = function(v) return v == true end,
            owns = function(k) return not Ownership.PLAYER_FLAGS[k[1]] end },
  objectToggles = { depth = 2, value = function(v) return type(v) == "boolean" end,
                    owns = function(k)
                      local mine = Ownership.PLAYER_OBJECTS[k[1]]
                      return not (mine and mine[k[2]])
                    end },
  defeatedTrainers = { depth = 1, value = function(v) return v == true end },
  itemsTaken = { depth = 1, value = function(v) return v == true end },
  inventory = { depth = 1, value = function(v) return finite(v) and v >= 0 and v <= 255 end,
                owns = function(k) return Ownership.BADGES[k[1]] == true end },
  trashPuzzle = { depth = 1, value = function(v) return finite(v) and v >= 0 and v <= 15 end,
                  owns = function(k) return k[1] == "first" or k[1] == "second" end },
}

-- true when the campaign owns `path` (a well-formed path of a known family)
function Ownership.owns(path)
  local p = parts(path)
  local fam = p and FAMILIES[p[1]]
  if not fam or #p ~= fam.depth + 1 then return false end
  local keys = { unpack(p, 2) }
  return not fam.owns or fam.owns(keys)
end

-- true when `value` is what the entry at `path` may hold
function Ownership.valid(path, value)
  if not Ownership.owns(path) then return false end
  return FAMILIES[path:match("^[^/]+")].value(value)
end

-- the campaign's entries of a save, as a flat map
function Ownership.view(save)
  local out = {}
  if type(save) ~= "table" then return out end
  for name, fam in pairs(FAMILIES) do
    local t = save[name]
    if type(t) == "table" then
      for k, v in pairs(t) do
        if type(k) == "string" then
          if fam.depth == 1 then
            local path = name .. "/" .. k
            if Ownership.valid(path, v) then out[path] = v end
          elseif type(v) == "table" then
            for k2, v2 in pairs(v) do
              local path = name .. "/" .. k .. "/" .. tostring(k2)
              if type(k2) == "string" and Ownership.valid(path, v2) then out[path] = v2 end
            end
          end
        end
      end
    end
  end
  return out
end

-- one entry into the save (nil clears it); only campaign entries
function Ownership.write(save, path, value)
  if not Ownership.owns(path) then return false end
  if value ~= nil and not Ownership.valid(path, value) then return false end
  local p = parts(path)
  local t = save[p[1]]
  if type(t) ~= "table" then
    if value == nil then return true end
    t = {}
    save[p[1]] = t
  end
  if #p == 3 then
    local inner = t[p[2]]
    if type(inner) ~= "table" then
      if value == nil then return true end
      inner = {}
      t[p[2]] = inner
    end
    inner[p[3]] = value
    if value == nil and next(inner) == nil then t[p[2]] = nil end
  else
    t[p[2]] = value
  end
  return true
end

-- a player's world without the campaign's entries (the host keeps those in
-- the campaign's story)
function Ownership.strip(save)
  for path in pairs(Ownership.view(save)) do Ownership.write(save, path, nil) end
  return save
end

-- the campaign's story over a world: its entries replace the world's own
function Ownership.overlay(save, story)
  Ownership.strip(save)
  for path, value in pairs(story or {}) do Ownership.write(save, path, value) end
  return save
end

-- the walk flags a host drops when it opens a campaign (A5.13)
function Ownership.dropWalk(save)
  if type(save) ~= "table" then return save end
  if type(save.flags) == "table" then
    for flag in pairs(Ownership.WALK_FLAGS) do save.flags[flag] = nil end
  end
  for key in pairs(Ownership.WALK_KEYS) do save[key] = nil end
  return save
end

-- the differences from view `a` to view `b`: set (path -> value), unset
-- (a list of paths) and how many
function Ownership.diff(a, b)
  local set, unset, n = {}, {}, 0
  for path, v in pairs(b) do
    if a[path] ~= v then set[path] = v; n = n + 1 end
  end
  for path in pairs(a) do
    if b[path] == nil then unset[#unset + 1] = path; n = n + 1 end
  end
  table.sort(unset)
  return set, unset, n
end

-- the map an entry belongs to, or nil (a flag of no one map)
function Ownership.mapOf(path)
  local p = parts(path)
  if not p then return nil end
  if p[1] == "objectToggles" then return p[2] end
  if p[1] == "defeatedTrainers" or p[1] == "itemsTaken" then
    return p[2]:match("^(.-)_obj_%d+$")
  end
  if p[1] == "flags" then return RELOADS[p[2]] end
  if p[1] == "trashPuzzle" then return "VERMILION_GYM" end
  return nil
end

-- an object hidden or shown (an object toggle, an item ball): lands at once
-- even on the map a window stands on (A5.6)
function Ownership.isObject(path)
  return type(path) == "string"
    and (path:find("^objectToggles/") ~= nil or path:find("^itemsTaken/") ~= nil)
end

-- the map a window standing on it must reload for this entry, or nil (A5.7)
function Ownership.reloadFor(path)
  if type(path) ~= "string" then return nil end
  local flag = path:match("^flags/(.+)$")
  if flag then return RELOADS[flag] end
  -- a beaten Cinnabar Gym guard opens his gate too (story6.lua)
  if path:find("^defeatedTrainers/CINNABAR_GYM_obj_%d+$") then return "CINNABAR_GYM" end
  return nil
end

-- the floor on which a clear of this entry waits until the window leaves,
-- or nil (Victory Road's switches, A5.17)
function Ownership.keepOnFloor(path)
  local flag = type(path) == "string" and path:match("^flags/(.+)$")
  return flag and KEEP_ON_FLOOR[flag] or nil
end

-- A campaign's story built from players' worlds (a file from before #14,
-- whose worlds still carry the shared keys): the team rule, so a flag any
-- player set stands; for one entry held with two values, the first
-- player's.  Entries are never cleared by a world that lacks them.
function Ownership.merge(worlds)
  local story = {}
  for _, save in ipairs(worlds) do
    for path, v in pairs(Ownership.view(save)) do
      if story[path] == nil then story[path] = v end
    end
  end
  return story
end

return Ownership
