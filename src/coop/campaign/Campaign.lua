-- A co-op campaign's state on the host (#13, design A3.1 to A3.3): the
-- campaign's own section and one section per player, never a merged save.
--
--   local c = Campaign.new({ id = "c…", title = "KANTO", game = "red", sha1 = "…" })
--   local p = c:addPlayer({ id = "p…", name = "RED", game = "red" })
--   c:setWorld(p.id, save)          -- the player's world (World.lua), uids stamped
--   c:commit("gift:BICYCLE", function(c) … end)  -- once; a repeat returns false
--   c:patch(p.id, set, unset, bag)  -- a window's change to the shared story
--   c:player(p.id).gifts            -- the items owed to a player (#16)
--   c:worldFor(p.id)                -- their world with the story over it
--
-- Campaign: id, title, cartridge (game, SHA-1), the shared story (#14: a
-- flat map of Ownership paths to values, the campaign's entries of every
-- world, merged entry by entry from the windows' patches), the unique-encounter
-- registry (encounter id -> { state = "active", battle = id } or "done";
-- #21), the set of applied commit ids, the rival's name and the starter he
-- counters (#22: the first player to name him, the first to finish the
-- opening; nil until then) and a revision that moves with every change.  Player: id, name, game, in-game trainer id, the serial of the
-- last uid given out, and their world: team, PC and current box, bag,
-- money, map, cell and facing as their game saved them, without the
-- story's entries (Ownership.strip); the battle they are in and their
-- return point come with #18.  Connection is the session's.
--
-- Every Pokémon has a uid `<player id>:<serial>`, never reused, kept through
-- deposits, trades and evolutions (design A3.2): a world's Pokémon keep the
-- uid they carry; one without (a new catch the window has not heard of) is
-- matched to the player's last world by its fingerprint, else given the
-- next serial, preferring an unchanged row, then the row's place (#17,
-- design A7.3).  A window sends its holdings at its rest points
-- (setHoldings, #17) as well as its saves.
--
-- Story items (#16, design A6, Items.lua): a patch that moves the story
-- shares the items its window gained in that change and takes the key
-- items it lost; one that lost a gift race has its gains taken back.  What
-- a player is owed waits in their `gifts` ({ seq, item, qty, once, from,
-- race }, qty < 0 takes), numbered by their `giftSeq`, until a world they
-- save shows it taken (`coopGifts`, the last seq their window applied).

local SaveSerializer = require("src.core.SaveSerializer")
local World = require("src.coop.campaign.World")
local Ownership = require("src.coop.campaign.Ownership")
local Items = require("src.coop.campaign.Items")
local Protocol = require("src.coop.session.Protocol")

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
    story = opts.story or {},
    encounters = opts.encounters or {},
    commits = opts.commits or {},
    rival = Protocol.name(opts.rival) or nil,
    chose = Protocol.STARTERS[opts.chose] and opts.chose or nil,
    players = {}, byId = {},
  }, Campaign)
end

-- The rival's name (#22, design A4.5): the first to name him names him for
-- everyone.  Returns true when this name is now the campaign's.
function Campaign:nameRival(name)
  if self.rival or not Protocol.name(name) then return false end
  self.rival = name
  self:touch()
  return true
end

-- The starter the rival counters (design A4.6): the first player to finish
-- the opening sets it.  Returns true when it is now the campaign's.
function Campaign:setChose(starter)
  if self.chose or not Protocol.STARTERS[starter] then return false end
  self.chose = starter
  self:touch()
  return true
end

function Campaign:player(id) return self.byId[id] end

-- a player's section, created the first time (name and game kept current)
function Campaign:addPlayer(info)
  local p = self.byId[info.id]
  if not p then
    p = { id = info.id, name = info.name, game = info.game, serial = 0,
          gifts = {}, giftSeq = 0 }
    self.players[#self.players + 1] = p
    self.byId[p.id] = p
    -- a late joiner is handed the gift list (design A6.5)
    for _, id in ipairs(self:giftList()) do
      self:_owe(p, { item = id:match("^gift:(.+)$"), qty = 1, once = true })
    end
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

-- the gift list's commits (`gift:<item>`), sorted (design A6.5)
function Campaign:giftList()
  local out = {}
  for id in pairs(self.commits) do
    if id:find("^gift:") then out[#out + 1] = id end
  end
  table.sort(out)
  return out
end

-- an item owed to player `q` (a take when qty < 0)
function Campaign:_owe(q, gift)
  q.gifts = q.gifts or {}
  q.giftSeq = (q.giftSeq or 0) + 1
  gift.seq = q.giftSeq
  q.gifts[#q.gifts + 1] = gift
  self:touch()
end

-- Story items (design A6.2, A6.3, A6.5, A6.7).  `fresh` is how many of the
-- patch's set entries the story did not have yet.  `bag`: { gained, lost
-- (item -> count), spent (money went down in the same change) }.
function Campaign:_items(p, set, fresh, bag)
  if fresh > 0 then
    for id, n in pairs(bag.gained or {}) do
      local gift = Items.giftId(id, set)
      if gift then self:commit(gift) end
      for _, q in ipairs(self.players) do
        if q ~= p then self:_owe(q, { item = id, qty = n, once = Items.isKey(id), from = p.name }) end
      end
    end
    for id, n in pairs(bag.lost or {}) do
      if Items.isKey(id) and not Items.isFossil(id) then
        for _, q in ipairs(self.players) do
          if q ~= p then self:_owe(q, { item = id, qty = -n, from = p.name }) end
        end
      end
    end
  elseif not bag.spent then
    -- the race was lost: the winner's share stands in for this window's
    -- own gains; a key item was given once and stays
    for id, n in pairs(bag.gained or {}) do
      if not Items.isKey(id) then self:_owe(p, { item = id, qty = -n, race = true }) end
    end
  end
end

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

-- a row's content without its uid, to tell an unchanged row (design A7.3)
local function content(mon)
  local body = {}
  for k, v in pairs(mon) do
    if k ~= UID_FIELD then body[k] = v end
  end
  return SaveSerializer.encode(body)
end

-- Stamp a uid on every Pokémon of `save` (design A3.2, A7.3).  A row keeps
-- the uid it carries, once.  A row without one takes a uid of the player's
-- last world with its fingerprint that no row carries: first the one whose
-- row is unchanged, then the one that stood on its place (the window's
-- hint: twins keep their uids), then any; else the next serial.  Returns
-- the rows given a uid: { box, slot, uid, fp } (box 0: the team).
function Campaign:_stampUids(p, save)
  local before = {}
  if p.world then
    for _, at in ipairs(World.mons(p.world)) do
      local uid = at.mon[UID_FIELD]
      if Campaign.uid(uid) then
        local fp = Campaign.fingerprint(at.mon)
        before[fp] = before[fp] or {}
        table.insert(before[fp], { uid = uid, mon = at.mon, place = at.box .. ":" .. at.slot })
      end
    end
  end
  local seen = {}
  local mons = World.mons(save)
  -- a uid the world carries stays, once
  local open = {}
  for _, at in ipairs(mons) do
    local uid = at.mon[UID_FIELD]
    if Campaign.uid(uid) and not seen[uid] then
      seen[uid] = true
    else
      at.mon[UID_FIELD] = nil
      at.fp = Campaign.fingerprint(at.mon)
      open[#open + 1] = at
    end
  end
  local function take(at, ok)
    for _, old in ipairs(before[at.fp] or {}) do
      if not seen[old.uid] and ok(old) then
        seen[old.uid] = true
        at.mon[UID_FIELD] = old.uid
        return
      end
    end
  end
  for _, at in ipairs(open) do
    local text = content(at.mon)
    take(at, function(old) return content(old.mon) == text end)
  end
  for _, at in ipairs(open) do
    if not at.mon[UID_FIELD] then
      local place = at.box .. ":" .. at.slot
      take(at, function(old) return old.place == place end)
    end
  end
  local assigned = {}
  for _, at in ipairs(open) do
    if not at.mon[UID_FIELD] then take(at, function() return true end) end
    if not at.mon[UID_FIELD] then
      local uid = self:nextUid(p.id)
      seen[uid] = true
      at.mon[UID_FIELD] = uid
    end
    assigned[#assigned + 1] = { box = at.box, slot = at.slot, uid = at.mon[UID_FIELD], fp = at.fp }
  end
  return assigned
end

-- the player's world, as their game saved it (World.check'ed); the uids are
-- stamped, the in-game trainer id taken from it, the story's entries left
-- out (the windows' patches carry those, design A5.2)
function Campaign:setWorld(playerId, save)
  local p = assert(self.byId[playerId], "no such player")
  local why = World.check(save)
  if why then return false, why end
  save.options = nil
  Ownership.strip(save)
  local assigned = self:_stampUids(p, save)
  -- the gifts this world has taken are owed no more (design A6.2)
  local took = type(save.coopGifts) == "number" and save.coopGifts or 0
  local owed = {}
  for _, g in ipairs(p.gifts or {}) do
    if g.seq > took then owed[#owed + 1] = g end
  end
  p.gifts = owed
  p.world = save
  p.trainer = type(save.player.id) == "number" and save.player.id or p.trainer
  self:touch()
  return true, assigned
end

-- The player's holdings, as a window sends them at a rest point (#17,
-- design A7.2, A7.4): their world without the PC, and the PC only when it
-- changed (`world.boxes` nil keeps the PC the campaign has).  Taken as
-- setWorld takes a save; returns the same.
function Campaign:setHoldings(playerId, world)
  local p = assert(self.byId[playerId], "no such player")
  if world.boxes == nil and p.world then world.boxes = p.world.boxes end
  return self:setWorld(playerId, world)
end

-- A new player's start (#57, design A4.1 to A4.3, A4.6, A4.7, G28): the
-- world a window started with (in Pallet Town, or a brought solo save).
-- A player the campaign has a world for is never replaced ("returning").
-- A campaign with no story yet takes the world's entries as its story (a
-- brought run continues in co-op; a Pallet start brings what a played
-- opening leaves), and the late joiner's list the items of that story the
-- world holds (A6.5), owed to every other player too.  The world's starter
-- is the one the rival counters if nobody set it.  Returns ok, the uids
-- given (or why not) and whether the story was seeded.
function Campaign:start(playerId, save)
  local p = assert(self.byId[playerId], "no such player")
  if p.world then return false, "returning" end
  local why = World.check(save)
  if why then return false, why end
  save.coopStart = nil
  Ownership.dropWalk(save)
  local seeded = false
  if next(self.story) == nil then
    local view = Ownership.view(save)
    for path, value in pairs(view) do
      self.story[path] = value
      seeded = true
    end
    if seeded then
      self:touch()
      local items = {}
      for _, list in ipairs({ save.inventory, save.pcItems }) do
        for id, n in pairs(type(list) == "table" and list or {}) do
          if type(id) == "string" and type(n) == "number" and n > 0 then items[id] = true end
        end
      end
      for id in pairs(items) do
        local gift = Items.giftId(id, view)
        if gift and self:commit(gift) then
          for _, q in ipairs(self.players) do
            if q ~= p then self:_owe(q, { item = id, qty = 1, once = true, from = p.name }) end
          end
        end
      end
    end
  end
  local flags = type(save.flags) == "table" and save.flags or {}
  for _, starter in ipairs({ "BULBASAUR", "CHARMANDER", "SQUIRTLE" }) do
    if flags["EVENT_CHOSE_" .. starter] then self:setChose(starter) end
  end
  local ok, assigned = self:setWorld(playerId, save)
  if not ok then return false, assigned end
  return true, assigned, seeded
end

-- A window's change to the shared story (design A5.2): `set` (path ->
-- value) and `unset` (paths), applied entry by entry, so two windows' flags
-- set at once both stand.  An entry the campaign does not own, or with a
-- value it may not hold, is skipped.  `bag` is the window's bag change in
-- the same rest-to-rest change (#16, `_items`).  Returns how many entries
-- changed.
function Campaign:patch(playerId, set, unset, bag)
  local p = assert(self.byId[playerId], "no such player")
  local n, sets = 0, 0
  for path, value in pairs(set or {}) do
    if Ownership.valid(path, value) then
      sets = sets + 1
      if self.story[path] ~= value then
        self.story[path] = value
        n = n + 1
      end
    end
  end
  local fresh = n
  for _, path in ipairs(unset or {}) do
    if Ownership.owns(path) and self.story[path] ~= nil then
      self.story[path] = nil
      n = n + 1
    end
  end
  if n > 0 then self:touch() end
  if type(bag) == "table" and sets > 0 then self:_items(p, set, fresh, bag) end
  return n
end

-- a copy of the player's world with the story over it, as a window opens
-- it (design A5.19), or nil for a player without a world
function Campaign:worldFor(playerId)
  local p = self.byId[playerId]
  if not (p and p.world) then return nil end
  local save = World.decode(World.encode(p.world))
  if not save then return nil end
  return Ownership.overlay(save, self.story)
end

-- the walk flags nobody keeps once a host opens the campaign (design A5.13)
function Campaign:dropWalkFlags()
  for _, p in ipairs(self.players) do
    if p.world then Ownership.dropWalk(p.world) end
  end
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
                    trainer = p.trainer, giftSeq = p.giftSeq or 0, gifts = p.gifts or {} }
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
      rival = self.rival, chose = self.chose,
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
  local story = {}
  for path, value in pairs(type(cs.story) == "table" and cs.story or {}) do
    if Ownership.valid(path, value) then story[path] = value end
  end
  local c = Campaign.new({
    id = cs.id, title = type(cs.title) == "string" and cs.title or "",
    game = cs.game, sha1 = type(cs.sha1) == "string" and cs.sha1 or "",
    created = tonumber(cs.created) or 0, revision = cs.revision,
    story = story,
    encounters = type(cs.encounters) == "table" and cs.encounters or {},
    commits = commits,
    rival = cs.rival, chose = cs.chose,
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
                trainer = tonumber(entry.trainer),
                giftSeq = tonumber(entry.giftSeq) or 0, gifts = {} }
    for _, g in ipairs(type(entry.gifts) == "table" and entry.gifts or {}) do
      local gift = Protocol.gift(g)
      if gift and gift.seq <= p.giftSeq then p.gifts[#p.gifts + 1] = gift end
    end
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
