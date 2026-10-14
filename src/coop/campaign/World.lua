-- A player's world as it travels to the host and in the campaign file
-- (#13, design A3.1, A1.4): the save table the window's game writes, as the
-- game's own save text (SaveSerializer, read back by its safe parser, never
-- run).  The host keeps it whole in the player's section; the shared keys
-- (flags, badges, script steps) move into the campaign's story with #14.
--
--   local save, why = World.decode(text)  -- a save table, or nil and why
--   local text = World.encode(save)       -- without the options
--   local rest, boxes = World.split(save) -- the PC apart, for the journal
--
-- Every world from a window is untrusted: it is kept only when it parses
-- and has a save's shape (a team of at most six, twelve boxes of at most
-- twenty, a current box among them, money a number, a player record).

local SaveSerializer = require("src.core.SaveSerializer")

local World = {}

-- a late-game save is about 40 KB of text; a full PC about a quarter of a
-- megabyte, so this leaves room under the protocol's 2 MiB message
World.MAX_TEXT = 1536 * 1024
World.TEAM = 6
World.BOXES = 12
World.BOX_SIZE = 20

local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isList(t, max)
  if type(t) ~= "table" then return false end
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then return false end
    n = n + 1
  end
  return n == #t and n <= max
end

local function monOk(mon)
  return type(mon) == "table"
    and (type(mon.species) == "string" or finite(mon.species))
    and finite(mon.level)
end

local function monsOk(list, max)
  if not isList(list, max) then return false end
  for _, mon in ipairs(list) do
    if not monOk(mon) then return false end
  end
  return true
end

-- the shape a save must have to be kept: nil when it fits, else why
function World.check(save)
  if type(save) ~= "table" then return "not a save" end
  if type(save.player) ~= "table" then return "no player" end
  if save.player.name ~= nil and type(save.player.name) ~= "string" then
    return "player name"
  end
  if save.party ~= nil and not monsOk(save.party, World.TEAM) then return "party" end
  if save.boxes ~= nil then
    if not isList(save.boxes, World.BOXES) then return "boxes" end
    for _, box in ipairs(save.boxes) do
      if not monsOk(box, World.BOX_SIZE) then return "box" end
    end
  end
  if save.currentBox ~= nil and not (finite(save.currentBox)
      and save.currentBox >= 1 and save.currentBox <= World.BOXES
      and save.currentBox == math.floor(save.currentBox)) then
    return "current box"
  end
  if save.money ~= nil and not (finite(save.money) and save.money >= 0) then
    return "money"
  end
  return nil
end

function World.decode(text)
  if type(text) ~= "string" then return nil, "not text" end
  if #text > World.MAX_TEXT then return nil, "too long" end
  local ok, save = pcall(SaveSerializer.decode, text)
  if not ok or type(save) ~= "table" then return nil, "not a save" end
  local why = World.check(save)
  if why then return nil, why end
  return save
end

-- the save as text, without the live options (options.lua is the device's)
function World.encode(save)
  local body = {}
  for k, v in pairs(save) do
    if k ~= "options" then body[k] = v end
  end
  return SaveSerializer.encode(body)
end

-- the save without its PC, and the PC (boxes) as text of its own: the
-- journal leaves a PC out while it is unchanged (design A3.8)
function World.split(save)
  local rest = {}
  for k, v in pairs(save) do
    if k ~= "options" and k ~= "boxes" then rest[k] = v end
  end
  return SaveSerializer.encode(rest), SaveSerializer.encode(save.boxes or {})
end

-- the two parts back into one save, or nil and why
function World.join(restText, boxesText)
  local ok, rest = pcall(SaveSerializer.decode, restText or "")
  if not ok or type(rest) ~= "table" then return nil, "not a save" end
  if boxesText then
    local okB, boxes = pcall(SaveSerializer.decode, boxesText)
    if not okB or type(boxes) ~= "table" then return nil, "not a PC" end
    rest.boxes = boxes
  end
  local why = World.check(rest)
  if why then return nil, why end
  return rest
end

-- every Pokémon of a save with where it is: { mon, box } (box 0: the team)
function World.mons(save)
  local out = {}
  for _, mon in ipairs(save.party or {}) do out[#out + 1] = { mon = mon, box = 0 } end
  for b, box in ipairs(save.boxes or {}) do
    for _, mon in ipairs(box) do out[#out + 1] = { mon = mon, box = b } end
  end
  return out
end

return World
