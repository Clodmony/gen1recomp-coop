-- The hosting device's co-op campaigns (#12, design A2.2, A2.3): one card
-- per campaign, `coop/campaigns/<id>.json` in the save folder, holding its
-- title, the game it was started on, when it was created and last hosted,
-- the players it has seen and the address a partner used last.  Campaign
-- state (story, players' progress) comes with the campaign files of #13;
-- until then each device keeps its own progress in a save slot per
-- campaign (CoopSettings).
--
--   local c = Campaigns.create({ title = "RED CO-OP", game = "red" })
--   Campaigns.list("red")        -- latest hosted first
--   Campaigns.rename(c.id, "KANTO")
--   Campaigns.delete(c.id)       -- keeps coop/campaigns/<id>.json.bak
--   Campaigns.restore(c.id)      -- the card back from its backup (#38)

local Json = require("src.link.Json")
local Protocol = require("src.coop.session.Protocol")
local Random = require("src.coop.session.Random")

local Campaigns = {}

Campaigns.DIR = "coop/campaigns"
Campaigns.MAX_FILE = 256 * 1024

-- the filesystem (love.filesystem's calls) and clock; tests replace them
Campaigns.fs = nil
Campaigns.now = os.time

local function fs() return Campaigns.fs or love.filesystem end

local function path(id) return Campaigns.DIR .. "/" .. id .. ".json" end

local function clean(data)
  if type(data) ~= "table" or not Protocol.campaignId(data.id) then return nil end
  local title = type(data.title) == "string" and data.title:gsub("[%z\1-\31\127]", "") or ""
  local c = {
    id = data.id,
    title = title:find("%S") and title:sub(1, Protocol.MAX_TITLE) or "CO-OP",
    game = Protocol.gameId(data.game) and data.game or nil,
    created = tonumber(data.created) or 0,
    hosted = tonumber(data.hosted),
    via = type(data.via) == "string" and data.via:sub(1, 64) or nil,
    players = {},
  }
  if not c.game then return nil end
  for _, p in ipairs(type(data.players) == "table" and data.players or {}) do
    if type(p) == "table" and Protocol.playerId(p.id) and Protocol.name(p.name) then
      c.players[#c.players + 1] = { id = p.id, name = p.name,
        game = Protocol.gameId(p.game) and p.game or nil }
    end
  end
  return c
end

function Campaigns.get(id)
  if not Protocol.campaignId(id) then return nil end
  local f = fs()
  if not f.getInfo(path(id)) then return nil end
  local text = f.read(path(id))
  if type(text) ~= "string" or #text > Campaigns.MAX_FILE then return nil end
  local ok, data = pcall(Json.decode, text)
  return ok and clean(data) or nil
end

function Campaigns.save(c)
  local f = fs()
  f.createDirectory(Campaigns.DIR)
  return f.write(path(c.id), Json.encode(c))
end

-- the campaigns of these games (a game id or a list), latest hosted first
function Campaigns.list(games)
  if type(games) == "string" then games = { games } end
  local want = {}
  for _, g in ipairs(games or {}) do want[g] = true end
  local out = {}
  local f = fs()
  if not f.getInfo(Campaigns.DIR) then return out end
  for _, item in ipairs(f.getDirectoryItems(Campaigns.DIR)) do
    local id = item:match("^(c[0-9a-f]+)%.json$")
    local c = id and Campaigns.get(id)
    if c and (not games or want[c.game]) then out[#out + 1] = c end
  end
  table.sort(out, function(a, b)
    local ta, tb = a.hosted or a.created, b.hosted or b.created
    if ta ~= tb then return ta > tb end
    return a.id < b.id
  end)
  return out
end

function Campaigns.create(opts)
  local c = {
    id = "c" .. (opts.hex or Random.hex)(16),
    title = (opts.title and opts.title ~= "") and opts.title or "CO-OP",
    game = opts.game, created = Campaigns.now(), players = {},
  }
  Campaigns.save(c)
  return c
end

function Campaigns.rename(id, title)
  local c = Campaigns.get(id)
  if not c or type(title) ~= "string" or not title:find("%S") then return nil end
  c.title = title:sub(1, Protocol.MAX_TITLE)
  Campaigns.save(c)
  return c
end

-- a hosting session's players and the last address a partner dialled
function Campaigns.record(id, roster)
  local c = Campaigns.get(id)
  if not c then return nil end
  local known = {}
  for i, p in ipairs(c.players) do known[p.id] = i end
  for _, p in ipairs(roster or {}) do
    if Protocol.playerId(p.id) and Protocol.name(p.name) then
      local entry = { id = p.id, name = p.name, game = p.game }
      if known[p.id] then
        c.players[known[p.id]] = entry
      else
        c.players[#c.players + 1] = entry
        known[p.id] = #c.players
      end
      if p.via and p.connected and p.via ~= "" then c.via = p.via end
    end
  end
  Campaigns.save(c)
  return c
end

function Campaigns.touch(id)
  local c = Campaigns.get(id)
  if not c then return nil end
  c.hosted = Campaigns.now()
  Campaigns.save(c)
  return c
end

-- Delete keeps the last state as <id>.json.bak; renaming it back to
-- <id>.json restores the card.  Returns the backup's path.
function Campaigns.delete(id)
  if not Protocol.campaignId(id) then return nil end
  local f = fs()
  local text = f.getInfo(path(id)) and f.read(path(id))
  if type(text) ~= "string" then return nil end
  local backup = path(id) .. ".bak"
  if not f.write(backup, text) then return nil end
  f.remove(path(id))
  return backup
end

-- co-op (#38): the card back from the backup delete kept; the backup is
-- removed once the card is written.  Returns the card, or nil.
function Campaigns.restore(id)
  if not Protocol.campaignId(id) then return nil end
  local f = fs()
  local backup = path(id) .. ".bak"
  local text = f.getInfo(backup) and f.read(backup)
  if type(text) ~= "string" or #text > Campaigns.MAX_FILE then return nil end
  local ok, data = pcall(Json.decode, text)
  local c = ok and clean(data) or nil
  if not c or c.id ~= id or f.getInfo(path(id)) then return nil end
  if not f.write(path(id), text) then return nil end
  f.remove(backup)
  return Campaigns.get(id)
end

return Campaigns
