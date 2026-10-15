-- Story items and the co-op bag (#16, design A6, decision G22): which items
-- the shared story hands every player, and how a gift lands in a player's
-- world.  Game-agnostic but for the item table (`Items.data`, the Data
-- singleton by default) and the bag (src/inventory/Bag.lua).
--
--   Items.bag(save)                 -- the bag as item -> count (no badges)
--   Items.delta(before, after)      -- gained, lost (item -> count)
--   Items.giftId(item, set)         -- "gift:<item>" for the gift list, or nil
--   Items.give(save, item, qty, once) -- "bag", "pc", "held" or nil (no room)
--   Items.take(save, item, qty)     -- how many were taken (bag, then PC)
--   Items.openBag(game.data) / closeBag() -- the 40-row co-op bag (A6.8)
--
-- Rules (the campaign applies them, Campaign:patch):
--   * A6.2: an item gained in the window change that sets story entries is
--     given to every other player, in the same number.
--   * A6.3: a key item lost in that change is taken from every other
--     player (OAK's PARCEL, the BIKE VOUCHER, the GOLD TEETH); fossils are
--     each player's.
--   * A6.5: key items, HMs and gift TMs (given with their EVENT_GOT_TMxx
--     flag) are committed as `gift:<item>`; a player who joins later is
--     handed every one.
--   * A6.6: a gift that finds the bag full goes to the PC's items.
--   * A6.7: a key item or HM is given once (one a player holds, in the bag
--     or the PC, is not given again), and never taken back after a race.

local Bag = require("src.inventory.Bag")

local Items = {}

Items.BAG_ROWS = 40  -- a co-op bag (A6.8); a solo game keeps the cartridge's 20
Items.PC_ROWS = 50   -- the PC's items, as the cartridge has them

-- the late joiner's list (A6.5): key items and HMs every player needs to
-- follow the story; gift TMs join it by their flag (giftId).  Red, Blue and
-- Yellow name these items alike.
Items.LIST = {
  TOWN_MAP = true, BICYCLE = true, CARD_KEY = true, SECRET_KEY = true, LIFT_KEY = true,
  S_S_TICKET = true, COIN_CASE = true, ITEMFINDER = true, SILPH_SCOPE = true,
  POKE_FLUTE = true, EXP_ALL = true, OLD_ROD = true, GOOD_ROD = true, SUPER_ROD = true,
  HM_CUT = true, HM_FLY = true, HM_SURF = true, HM_STRENGTH = true, HM_FLASH = true,
}

-- each player revives their own (A6.3, A7.9)
Items.FOSSILS = { HELIX_FOSSIL = true, DOME_FOSSIL = true, OLD_AMBER = true }

local function data()
  return Items.data or require("src.core.Data")
end

function Items.def(id)
  local d = data()
  return d and d.items and d.items[id] or nil
end

-- a key item or an HM: one row, never two (given once, never taken back)
function Items.isKey(id)
  local def = Items.def(id)
  if not def then return Items.LIST[id] == true end
  return def.keyItem == true or (type(def.machine) == "table" and def.machine.kind == "HM")
end

function Items.isFossil(id)
  return Items.FOSSILS[id] == true
end

-- the commit id of an item on the gift list (A6.5), or nil; `set` is the
-- story entries the same change set (a gift TM's EVENT_GOT_TMxx flag)
function Items.giftId(id, set)
  if Items.LIST[id] then return "gift:" .. id end
  local def = Items.def(id)
  local m = def and def.machine
  if type(m) == "table" and m.kind == "TM" and type(m.number) == "number" then
    if (set or {})[("flags/EVENT_GOT_TM%02d"):format(m.number)] == true then
      return "gift:" .. id
    end
  end
  return nil
end

-- the bag as item -> count, badges left out (they are the story's)
function Items.bag(save)
  local out = {}
  local inv = type(save) == "table" and save.inventory
  if type(inv) ~= "table" then return out end
  for id, n in pairs(inv) do
    if type(id) == "string" and type(n) == "number" and n > 0 and not Bag.isBadge(id) then
      out[id] = n
    end
  end
  return out
end

-- what a bag gained and lost from `before` to `after`
function Items.delta(before, after)
  local gained, lost = {}, {}
  for id, n in pairs(after) do
    local was = before[id] or 0
    if n > was then gained[id] = n - was end
  end
  for id, n in pairs(before) do
    local now = after[id] or 0
    if now < n then lost[id] = n - now end
  end
  return gained, lost
end

local function held(save, id)
  local inv, pc = save.inventory, save.pcItems
  return (type(inv) == "table" and type(inv[id]) == "number" and inv[id] > 0)
    or (type(pc) == "table" and type(pc[id]) == "number" and pc[id] > 0)
end
Items.holds = held

-- a gift into the player's world: the bag, else the PC (A6.6); `once`
-- skips an item the player holds already.  nil when neither had room.
function Items.give(save, id, qty, once)
  if once and held(save, id) then return "held" end
  local d = data()
  if Bag.add(save, id, qty, d) then return "bag" end
  if Bag.pcAdd(save, id, qty, d, Items.PC_ROWS) then return "pc" end
  return nil
end

-- up to `qty` taken, from the bag first, then the PC; returns how many
function Items.take(save, id, qty)
  local d = data()
  local taken = 0
  local inv = type(save.inventory) == "table" and save.inventory[id]
  if type(inv) == "number" and inv > 0 then
    local n = math.min(qty, inv)
    Bag.remove(save, id, n, d)
    taken = n
  end
  local pc = type(save.pcItems) == "table" and save.pcItems[id]
  if taken < qty and type(pc) == "number" and pc > 0 then
    local n = math.min(qty - taken, pc)
    Bag.pcRemove(save, id, n, d)
    taken = taken + n
  end
  return taken
end

-- The co-op bag (A6.8): raised to BAG_ROWS while a session's world is open,
-- put back (a mod's own bagSize too) when it closes.  `d` is the running
-- game's item table (game.data); the rules here read it until the close.
function Items.openBag(d)
  d = d or data()
  local c = d and d.constants
  if type(c) ~= "table" then return end
  if not Items.solo then Items.solo = { constants = c, size = c.bagSize, data = Items.data } end
  Items.data = d
  c.bagSize = Items.BAG_ROWS
end

function Items.closeBag()
  local solo = Items.solo
  if not solo then return end
  solo.constants.bagSize = solo.size
  Items.data = solo.data
  Items.solo = nil
end

return Items
