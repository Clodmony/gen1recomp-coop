-- Shared helpers for the campaign tests (#13): an in-memory file store with
-- the calls CampaignFile uses, and save tables shaped like the game's.

local F = {}

-- files[path] = text; `failWrite[path]`, `noRename` and `failRenameTo`
-- let a test cut a write off where it wants
function F.memFs()
  local fs = { files = {}, failWrite = {}, noRename = false, writes = 0 }
  function fs.read(p) return fs.files[p] end
  function fs.write(p, text)
    if fs.failWrite[p] then return false end
    fs.writes = fs.writes + 1
    fs.files[p] = text
    return true
  end
  function fs.append(p, text) fs.files[p] = (fs.files[p] or "") .. text; return true end
  function fs.remove(p) fs.files[p] = nil; return true end
  function fs.exists(p) return fs.files[p] ~= nil end
  function fs.mkdir() return true end
  function fs.rename(a, b)
    if fs.noRename or fs.failRenameTo == b then return nil, "no rename" end
    if fs.files[a] == nil then return nil, "missing" end
    fs.files[b] = fs.files[a]
    fs.files[a] = nil
    return true
  end
  return fs
end

local serial = 0
function F.mon(species, level, opts)
  opts = opts or {}
  serial = serial + 1
  return {
    species = species, level = level or 5, exp = 135,
    dvs = opts.dvs or { attack = serial % 16, defense = 3, speed = 7, special = 9 },
    statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 },
    stats = { hp = 20, attack = 11, defense = 10, speed = 12, special = 10 },
    hp = 20, catchRate = 45, moves = { { id = "TACKLE", pp = 35 } },
    otId = opts.otId or 12345, ot = opts.ot or "RED",
  }
end

function F.save(name, opts)
  opts = opts or {}
  local boxes = {}
  for b = 1, 12 do boxes[b] = {} end
  return {
    version = "red",
    player = { name = name or "RED", rival = "BLUE", id = opts.trainer or 12345,
               map = opts.map or "PALLET_TOWN", x = 5, y = 6, facing = "down" },
    money = opts.money or 3000, coins = 0,
    party = opts.party or { F.mon("BULBASAUR", 5) },
    boxes = boxes, currentBox = 1,
    inventory = opts.inventory or { POTION = 1 },
    pokedex = { seen = { BULBASAUR = true }, owned = { BULBASAUR = true } },
    flags = opts.flags or { EVENT_GOT_STARTER = true },
    playTime = 600,
    options = { textSpeed = "fast" },
  }
end

return F
