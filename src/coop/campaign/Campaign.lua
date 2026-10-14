-- A co-op campaign's state on the host (#13, design A3.1 to A3.3): the
-- campaign's own section and one section per player, never a merged save.
--
--   local c = Campaign.new({ id = "c…", title = "KANTO", game = "red", sha1 = "…" })
--   local p = c:addPlayer({ id = "p…", name = "RED", game = "red" })
--   c:setWorld(p.id, save)          -- the player's world (World.lua), uids stamped
--   c:commit("gift:BICYCLE", function(c) … end)  -- once; a repeat returns false
--
-- Campaign: id, title, cartridge (game, SHA-1), the shared story (flags,
-- badges: filled by the world patches of #14), the unique-encounter
-- registry (encounter id -> { state = "active", battle = id } or "done";
-- #21), the set of applied commit ids and a revision that moves with every
-- change.  Player: id, name, game, in-game trainer id, the serial of the
-- last uid given out, and their world: team, PC and current box, bag,
-- money, map, cell and facing as their game saved them; the battle they are
-- in and their return point come with #18.  Connection is the session's.
--
-- Every Pokémon has a uid `<player id>:<serial>`, never reused, kept through
-- deposits, trades and evolutions (design A3.2): a world's Pokémon keep the
-- uid they carry; one without (a new catch the window has not heard of) is
-- matched to the player's last world by its fingerprint, else given the
-- next serial.  #17 refines the matching (an unchanged row first, the
-- window's hint).

local World = require("src.coop.campaign.World")

local Campaign = {}
Campaign.__index = Campaign

Campaign.UID_FIELD = "coopUid"
local UID_FIELD = Campaign.UID_FIELD

-- a commit id: a kind and a stable key (`victory:<encounter id>`,
-- `gift:<item>`), never an array position
function Campaign.commitId(id)
  return type(id) == "string" and #id <= 96 and id:find("^[a-z_]+:[%w_%-%.:]+$") ~= nil
end

function Campaign.uid(id)
  return type(id) == "string" and id:find("^p[0-9a-f]+:%d+$") ~= nil
end

function Campaign.new(opts)
  assert(type(opts) == "table" and opts.id, "Campaign.new needs an id")
  return setmetatable({
    id = opts.id, title = opts.title or "", game = opts.game,
    sha1 = opts.sha1 or "", created = opts.created or 0,
    revision = opts.revision or 0,
    story = opts.story or { flags = {}, badges = {} },
    encounters = opts.encounters or {},
    commits = opts.commits or {},
    players = {}, byId = {},
  }, Campaign)
end

function Campaign:player(id) return self.byId[id] end

-- a player's section, created the first time (name and game kept current)
function Campaign:addPlayer(info)
  local p = self.byId[info.id]
  if not p then
    p = { id = info.id, name = info.name, game = info.game, serial = 0 }
    self.players[#self.players + 1] = p
    self.byId[p.id] = p
    self:touch()
  end
  if info.name and info.name ~= p.name then p.name = info.name; self:touch() end
  if info.game and info.game ~= p.game then p.game = info.game; self:touch() end
  return p
end

-- something changed: the revision moves (design A3.8)
function Campaign:touch()
  self.revision = self.revision + 1
end

-- Exactly-once commits (design A3.3, D10, D30): every progression change
-- goes through here with a stable id; a repeat returns false and changes
-- nothing.  `apply(campaign)` makes the change.
function Campaign:commit(id, apply)
  assert(Campaign.commitId(id), "bad commit id " .. tostring(id))
  if self.commits[id] then return false end
  if apply then apply(self) end
  self.commits[id] = true
  self:touch()
  return true
end

function Campaign:applied(id) return self.commits[id] == true end

function Campaign:nextUid(playerId)
  local p = assert(self.byId[playerId], "no such player")
  p.serial = p.serial + 1
  self:touch()
  return playerId .. ":" .. p.serial
end

-- what tells two Pokémon apart without a uid: original trainer, DVs and the
-- catch data (design A7.3)
function Campaign.fingerprint(mon)
  local dvs = {}
  if type(mon.dvs) == "table" then
    local keys = {}
    for k in pairs(mon.dvs) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
      dvs[#dvs + 1] = k .. "=" .. tostring(mon.dvs[k] or mon.dvs[tonumber(k)])
    end
  else
    dvs[1] = tostring(mon.dvs)
  end
  return table.concat({ tostring(mon.otId), tostring(mon.ot), table.concat(dvs, ","),
                        tostring(mon.catchRate) }, "|")
end

-- stamp a uid on every Pokémon of `save` (design A3.2)
function Campaign:_stampUids(p, save)
  local before = {}
  if p.world then
    for _, at in ipairs(World.mons(p.world)) do
      local uid = at.mon[UID_FIELD]
      if Campaign.uid(uid) then
        local fp = Campaign.fingerprint(at.mon)
        before[fp] = before[fp] or {}
        table.insert(before[fp], uid)
      end
    end
  end
  local seen = {}
  local mons = World.mons(save)
  -- a uid the world carries stays, once
  for _, at in ipairs(mons) do
    local uid = at.mon[UID_FIELD]
    if Campaign.uid(uid) and not seen[uid] then
      seen[uid] = true
    else
      at.mon[UID_FIELD] = nil
    end
  end
  for _, at in ipairs(mons) do
    if not at.mon[UID_FIELD] then
      local uid
      for _, old in ipairs(before[Campaign.fingerprint(at.mon)] or {}) do
        if not seen[old] then uid = old; break end
      end
      uid = uid or self:nextUid(p.id)
      seen[uid] = true
      at.mon[UID_FIELD] = uid
    end
  end
end

-- the player's world, as their game saved it (World.check'ed); the uids are
-- stamped, the in-game trainer id taken from it
function Campaign:setWorld(playerId, save)
  local p = assert(self.byId[playerId], "no such player")
  local why = World.check(save)
  if why then return false, why end
  save.options = nil
  self:_stampUids(p, save)
  p.world = save
  p.trainer = type(save.player.id) == "number" and save.player.id or p.trainer
  self:touch()
  return true
end

-- file form ----------------------------------------------------------------

local function sortedKeys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out)
  return out
end

-- The campaign as plain data (CampaignFile writes it as JSON).  A player's
-- world is the game's save text, the PC apart (`boxes`); `skipBoxes[id]`
-- leaves that player's PC out (the journal, design A3.8).
function Campaign:snapshot(skipBoxes)
  local players = {}
  for i, p in ipairs(self.players) do
    local entry = { id = p.id, name = p.name, game = p.game, serial = p.serial,
                    trainer = p.trainer }
    if p.world then
      local rest, boxes = World.split(p.world)
      entry.world = rest
      if not (skipBoxes and skipBoxes[p.id]) then entry.boxes = boxes end
    end
    players[i] = entry
  end
  local encounters = {}
  for _, id in ipairs(sortedKeys(self.encounters)) do
    local e = self.encounters[id]
    encounters[id] = type(e) == "table" and { state = e.state, battle = e.battle } or e
  end
  return {
    campaign = {
      id = self.id, title = self.title, game = self.game, sha1 = self.sha1,
      created = self.created, revision = self.revision,
      story = self.story, encounters = encounters,
      commits = sortedKeys(self.commits),
    },
    players = players,
  }
end

-- the PC text of each player, to compare with later snapshots
function Campaign:boxesTexts()
  local out = {}
  for _, p in ipairs(self.players) do
    if p.world then
      local _, boxes = World.split(p.world)
      out[p.id] = boxes
    end
  end
  return out
end

local Protocol = require("src.coop.session.Protocol")

-- A campaign from its plain data, or nil and why.  `boxesOf(id)` gives the
-- PC text of a player whose entry left it out (a journal line).
function Campaign.fromSnapshot(data, boxesOf)
  if type(data) ~= "table" or type(data.campaign) ~= "table" then
    return nil, "no campaign section"
  end
  local cs = data.campaign
  if not Protocol.campaignId(cs.id) or not Protocol.gameId(cs.game) then
    return nil, "campaign id"
  end
  if type(cs.revision) ~= "number" then return nil, "revision" end
  local commits = {}
  for _, id in ipairs(type(cs.commits) == "table" and cs.commits or {}) do
    if Campaign.commitId(id) then commits[id] = true end
  end
  local story = type(cs.story) == "table" and cs.story or {}
  story.flags = type(story.flags) == "table" and story.flags or {}
  story.badges = type(story.badges) == "table" and story.badges or {}
  local c = Campaign.new({
    id = cs.id, title = type(cs.title) == "string" and cs.title or "",
    game = cs.game, sha1 = type(cs.sha1) == "string" and cs.sha1 or "",
    created = tonumber(cs.created) or 0, revision = cs.revision,
    story = story,
    encounters = type(cs.encounters) == "table" and cs.encounters or {},
    commits = commits,
  })
  if type(data.players) ~= "table" then return nil, "no players" end
  for _, entry in ipairs(data.players) do
    if type(entry) ~= "table" or not Protocol.playerId(entry.id)
       or not Protocol.name(entry.name) then
      return nil, "player"
    end
    local p = { id = entry.id, name = entry.name,
                game = Protocol.gameId(entry.game) and entry.game or nil,
                serial = tonumber(entry.serial) or 0,
                trainer = tonumber(entry.trainer) }
    if entry.world ~= nil then
      local boxes = entry.boxes
      if boxes == nil and boxesOf then boxes = boxesOf(entry.id) end
      local world, why = World.join(entry.world, boxes)
      if not world then return nil, "world of " .. entry.id .. ": " .. tostring(why) end
      p.world = world
    end
    c.players[#c.players + 1] = p
    c.byId[p.id] = p
  end
  return c
end

return Campaign
