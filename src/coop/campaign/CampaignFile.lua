-- A co-op campaign's file on the hosting device (#13, design A3.4 to A3.6,
-- A3.8, A3.13): one versioned file per campaign with the campaign's
-- section and one section per player, `coop/campaigns/<game>/<id>.campaign`
-- in the save folder, beside the campaign's card (Campaigns.lua).
--
--   local ok, why = CampaignFile.write(fs, campaign)  -- a checkpoint
--   local c, info = CampaignFile.read(fs, game, id)   -- the journal applied
--   -- c nil: info.why is missing, unreadable or newer; info.backup names
--   -- the backup the launcher shows
--
-- Writing: the new text goes to `.tmp`, is read back and checked, then
-- takes the file's place; the file it replaces is kept as `.bak`, but only
-- when it still reads as a campaign; a write that fails leaves the old file
-- as it was.  Each checkpoint deletes the journal.
--
-- Journal (design A3.8): between checkpoints the host appends the whole
-- state as one line to `<id>.journal` (each PC left out while unchanged
-- since the checkpoint).  Reading takes the checkpoint, then the newest
-- whole line of the same campaign with a higher revision; a torn last line
-- is skipped.  Every line starts with a newline, so a line after a torn one
-- still reads.
--
-- Format: `format` names the file, `version` its layout.  A file of a newer
-- version is refused and left untouched; an older one is brought up one
-- step at a time (MIGRATIONS[n] takes version n to n + 1).

local Json = require("src.link.Json")
local Campaign = require("src.coop.campaign.Campaign")
local Protocol = require("src.coop.session.Protocol")
local Ownership = require("src.coop.campaign.Ownership")
local SaveSerializer = require("src.core.SaveSerializer")

local CampaignFile = {}

CampaignFile.FORMAT = "gen1recomp-coop campaign"
CampaignFile.VERSION = 2
CampaignFile.DIR = "coop/campaigns"
-- twelve full PCs and more; a campaign file is never this long
CampaignFile.MAX_FILE = 64 * 1024 * 1024

-- MIGRATIONS[n](data) brings a version-n file to n + 1
CampaignFile.MIGRATIONS = {}

-- 1 to 2 (#14): the shared story moves out of the players' worlds into the
-- campaign's section.  A flag any player set stands (the team rule); an
-- entry two worlds hold with two values takes the first player's.
CampaignFile.MIGRATIONS[1] = function(data)
  local worlds, rests = {}, {}
  for i, entry in ipairs(type(data.players) == "table" and data.players or {}) do
    if type(entry) == "table" and type(entry.world) == "string" then
      local ok, rest = pcall(SaveSerializer.decode, entry.world)
      if ok and type(rest) == "table" then
        worlds[#worlds + 1] = rest
        rests[i] = rest
      end
    end
  end
  if type(data.campaign) ~= "table" then return data end
  data.campaign.story = Ownership.merge(worlds)
  for i, rest in pairs(rests) do
    data.players[i].world = SaveSerializer.encode(Ownership.strip(rest))
  end
  return data
end

function CampaignFile.path(game, id)
  return CampaignFile.DIR .. "/" .. game .. "/" .. id .. ".campaign"
end

local function paths(game, id)
  local main = CampaignFile.path(game, id)
  return main, main .. ".bak", main .. ".tmp", CampaignFile.DIR .. "/" .. game .. "/" .. id .. ".journal"
end
CampaignFile.paths = paths

-- the file calls, over love.filesystem; the swap renames in the real save
-- folder, since love.filesystem has none.  Tests pass their own table with
-- read, write, append, remove, exists, mkdir and rename.
function CampaignFile.loveFs()
  local lfs = love.filesystem
  local function real(p) return lfs.getSaveDirectory() .. "/" .. p end
  return {
    read = function(p)
      if not lfs.getInfo(p) then return nil end
      return lfs.read(p)
    end,
    write = function(p, text) return lfs.write(p, text) end,
    append = function(p, text)
      if lfs.append then return lfs.append(p, text) end
      return lfs.write(p, (lfs.getInfo(p) and lfs.read(p) or "") .. text)
    end,
    remove = function(p) if lfs.getInfo(p) then return lfs.remove(p) end return true end,
    exists = function(p) return lfs.getInfo(p) ~= nil end,
    mkdir = function(p) return lfs.createDirectory(p) end,
    rename = function(a, b) return os.rename(real(a), real(b)) end,
  }
end

-- text ---------------------------------------------------------------------

function CampaignFile.encode(campaign)
  local data = campaign:snapshot()
  data.format = CampaignFile.FORMAT
  data.version = CampaignFile.VERSION
  data.saved = os.time()
  return Json.encode(data)
end

-- the file's data at the current version, or nil and why: "unreadable"
-- (not JSON, not a campaign file) or "newer"
function CampaignFile.parse(text)
  if type(text) ~= "string" or #text > CampaignFile.MAX_FILE then
    return nil, "unreadable"
  end
  local ok, data = pcall(Json.decode, text)
  if not ok or type(data) ~= "table" or data.format ~= CampaignFile.FORMAT
     or type(data.version) ~= "number" or data.version < 1
     or data.version ~= math.floor(data.version) then
    return nil, "unreadable"
  end
  if data.version > CampaignFile.VERSION then return nil, "newer" end
  while data.version < CampaignFile.VERSION do
    local step = CampaignFile.MIGRATIONS[data.version]
    if not step then return nil, "unreadable" end
    local okStep, out = pcall(step, data)
    if not okStep or type(out) ~= "table" then return nil, "unreadable" end
    data = out
    data.version = (data.version or 0) + 1
  end
  return data
end

function CampaignFile.decode(text)
  local data, why = CampaignFile.parse(text)
  if not data then return nil, why end
  local c, bad = Campaign.fromSnapshot(data)
  if not c then return nil, "unreadable", bad end
  return c
end

-- writing ------------------------------------------------------------------

-- A checkpoint: the campaign's file replaced through `.tmp`, the old one
-- kept as `.bak` when it still reads, the journal deleted.  Returns true,
-- or false and why; on false the old file is as it was.
function CampaignFile.write(fs, campaign)
  local main, bak, tmp, journal = paths(campaign.game, campaign.id)
  fs.mkdir(CampaignFile.DIR .. "/" .. campaign.game)
  local text = CampaignFile.encode(campaign)
  local ok = fs.write(tmp, text)
  if not ok then fs.remove(tmp); return false, "write failed" end
  -- read back: the bytes on disk must be this campaign at this revision
  local back = CampaignFile.decode(fs.read(tmp))
  if not back or back.id ~= campaign.id or back.revision ~= campaign.revision then
    fs.remove(tmp)
    return false, "read back failed"
  end
  if fs.exists(main) then
    if CampaignFile.decode(fs.read(main)) then
      fs.remove(bak)
      if not fs.rename(main, bak) then
        fs.write(bak, fs.read(main))
      end
    end
  end
  if not fs.rename(tmp, main) then
    -- no rename here: write the file itself, the checked .tmp as the witness
    if not fs.write(main, text) then return false, "write failed" end
    fs.remove(tmp)
  end
  fs.remove(journal)
  return true
end

-- The journal: one line of the whole state after the checkpoint.
-- `skipBoxes[id]` leaves a PC out that is unchanged since the checkpoint.
-- Returns the line's length.
function CampaignFile.appendJournal(fs, campaign, skipBoxes)
  local _, _, _, journal = paths(campaign.game, campaign.id)
  fs.mkdir(CampaignFile.DIR .. "/" .. campaign.game)
  local data = campaign:snapshot(skipBoxes)
  data.format = CampaignFile.FORMAT
  data.version = CampaignFile.VERSION
  local line = "\n" .. Json.encode(data)
  fs.append(journal, line)
  return #line
end

-- reading ------------------------------------------------------------------

-- the newest whole journal line of this campaign with a revision above
-- `base`'s, as a campaign (PCs left out come from `base`), or nil
local function fromJournal(text, base)
  if type(text) ~= "string" then return nil end
  local boxes = base:boxesTexts()
  local best
  for line in text:gmatch("[^\n]+") do
    local data = CampaignFile.parse(line)
    local cs = data and data.campaign
    if cs and cs.id == base.id and type(cs.revision) == "number"
       and cs.revision > (best and best.revision or base.revision) then
      local c = Campaign.fromSnapshot(data, function(id) return boxes[id] end)
      if c then best = c end
    end
  end
  return best
end

-- The campaign `id` of `game`: the checkpoint and the journal after it.
-- Returns the campaign and { recovered = "tmp" | nil, journal = true | nil },
-- or nil and { why = "missing" | "unreadable" | "newer", backup = path or nil }.
function CampaignFile.read(fs, game, id)
  if not Protocol.campaignId(id) or not Protocol.gameId(game) then
    return nil, { why = "missing" }
  end
  local main, bak, tmp, journal = paths(game, id)
  local info = {}
  local c, why
  if fs.exists(main) then
    c, why = CampaignFile.decode(fs.read(main))
  elseif fs.exists(tmp) then
    -- the swap was cut off between the backup and the rename: the checked
    -- .tmp is the newest checkpoint
    c, why = CampaignFile.decode(fs.read(tmp))
    if c then info.recovered = "tmp" end
  else
    why = "missing"
  end
  if not c then
    return nil, { why = why, backup = fs.exists(bak) and bak or nil }
  end
  if c.id ~= id then
    return nil, { why = "unreadable", backup = fs.exists(bak) and bak or nil }
  end
  local later = fromJournal(fs.read(journal), c)
  if later then
    info.journal = true
    c = later
  end
  return c, info
end

return CampaignFile
