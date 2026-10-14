-- A window's side of the shared world (#14, design A5.2 to A5.7, A5.17):
-- what this player's game sends of the campaign's story and what it takes
-- from it.  The window is game-agnostic: each frame it is handed the save
-- table, whether the player is held, the map it stands on and how to reload
-- or refresh that map (src/coop/game/SharedWorld.lua builds that frame from
-- the running game; the tests build it by hand).
--
--   local w = Window.new(client)
--   every frame: w:update({ save = save, busy = why or nil, map = "PALLET_TOWN",
--                           still = true,  -- not between two cells
--                           reload = function(map) … end,
--                           refresh = function(map) … end })
--   w:flush(save)   -- START > SAVE: the scene so far goes out now
--
-- Rules:
--   * Rest points (A5.4, D72): a frame where nothing holds the player.  It
--     counts after REST_FRAMES such frames in a row.  Away from a rest
--     point the window sends and takes nothing (A5.5); a closed window or a
--     lost link sends nothing, so the host keeps the last resting state.
--     A step the player walks of their own does not hold them (the
--     cartridge opens START at the next cell), but a reload or refresh
--     waits for a frame between two cells.
--   * Opening (A5.2, A5.19): the first rest point takes the campaign's
--     story instead of pushing the window's own; only a campaign with no
--     story yet takes the window's entries (its first window starts it).
--   * Patches, not copies (A5.2): the window sends the difference between
--     what it last sent and its current entries, and applies the difference
--     between the host's story it last took and the newest.
--   * Unconfirmed patches (A5.3, D51): an entry this window sent in a patch
--     the host has not reported applied is left out of what it takes, so an
--     older story never rewinds its own change.
--   * The map it stands on (A5.6, A5.7, A5.17): this engine keeps no
--     per-map script steps (Ownership.lua), so a partner's entry lands at
--     once; a pulled object hide or show on the standing map refreshes that
--     map, a pulled flag the map is stamped from owes it a reload, and a
--     Victory Road switch cleared by a partner waits while this window
--     still stands on that floor.

local Ownership = require("src.coop.campaign.Ownership")

local Window = {}
Window.__index = Window

Window.REST_FRAMES = 3

function Window.new(client)
  return setmetatable({
    client = client,
    rest = 0,        -- frames in a row with nothing holding the player
    sent = nil,      -- the entries as last sent (nil: not opened yet)
    seen = {},       -- the host's story as last taken
    unconfirmed = {}, -- seq -> { path = true } for patches not yet applied
    patches = 0, taken = 0, reloads = 0, -- counters for the log and the tests
    owed = nil,      -- { map, reload } a reload or refresh owed to that map
  }, Window)
end

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

-- true when an unconfirmed patch of this window touched `path`
function Window:_mine(path)
  for _, paths in pairs(self.unconfirmed) do
    if paths[path] then return true end
  end
  return false
end

function Window:_ready()
  local c = self.client
  return c ~= nil and c.status == "joined" and c.story ~= nil
end

-- the patches the host has applied are confirmed (A5.3)
function Window:_confirm()
  local applied = self.client.storyApplied or 0
  for seq in pairs(self.unconfirmed) do
    if seq <= applied then self.unconfirmed[seq] = nil end
  end
end

-- this window's change since the last patch goes out; returns its seq
function Window:_send(save)
  local cur = Ownership.view(save)
  local set, unset, n = Ownership.diff(self.sent, cur)
  if n == 0 then return nil end
  local seq = self.client:sendPatch(set, unset)
  if not seq then return nil end
  local paths = {}
  for path in pairs(set) do paths[path] = true end
  for _, path in ipairs(unset) do paths[path] = true end
  self.unconfirmed[seq] = paths
  self.sent = cur
  self.patches = self.patches + 1
  return seq
end

-- The first rest point: the campaign's story over the window's entries
-- (A5.2: a window opened late takes the campaign).  A campaign without a
-- story yet keeps the window's entries, which its first patch sends.
function Window:_open(f)
  local story = self.client.story
  if next(story) == nil then
    self.sent = {}
    self.seen = {}
    return
  end
  local before = Ownership.view(f.save)
  Ownership.overlay(f.save, story)
  self.sent = Ownership.view(f.save)
  self.seen = copy(story)
  local _, _, n = Ownership.diff(before, self.sent)
  self.taken = self.taken + n
  if n > 0 then self:_owe(f.map, true) end
end

-- a reload (or a lighter refresh) owed to the map the window stands on
function Window:_owe(map, reload)
  if not map then return end
  if self.owed and self.owed.map == map then
    self.owed.reload = self.owed.reload or reload
  else
    self.owed = { map = map, reload = reload }
  end
end

-- what is owed, once the player stands between two cells on that map; a
-- map left since loaded fresh and owes nothing
function Window:_settle(f)
  local owed = self.owed
  if not owed then return end
  if f.map ~= owed.map then self.owed = nil; return end
  if f.still == false then return end
  self.owed = nil
  self.reloads = self.reloads + 1
  if owed.reload and f.reload then
    f.reload(owed.map)
  elseif f.refresh then
    f.refresh(owed.map)
  elseif f.reload then
    f.reload(owed.map)
  end
end

-- the host's changes since the last one taken, by the rules above
function Window:_take(f)
  local story = self.client.story
  local changed = {}
  for path, v in pairs(story) do
    if self.seen[path] ~= v then changed[path] = true end
  end
  for path in pairs(self.seen) do
    if story[path] == nil then changed[path] = true end
  end
  for path in pairs(changed) do
    local value = story[path]
    local wait = self:_mine(path)
      or (value == nil and f.map ~= nil and Ownership.keepOnFloor(path) == f.map)
    if not wait then
      Ownership.write(f.save, path, value)
      self.seen[path] = value
      self.sent[path] = value
      self.taken = self.taken + 1
      if f.map ~= nil and Ownership.reloadFor(path) == f.map then
        self:_owe(f.map, true)
      elseif f.map ~= nil and Ownership.isObject(path) and Ownership.mapOf(path) == f.map then
        self:_owe(f.map, false)
      end
    end
  end
end

function Window:update(f)
  if not self:_ready() or type(f.save) ~= "table" then return end
  self:_confirm()
  if f.busy then
    self.rest = 0
    return
  end
  self.rest = self.rest + 1
  if self.rest < Window.REST_FRAMES then return end
  if not self.sent then
    self:_open(f)
  else
    self:_send(f.save)
    self:_take(f)
  end
  self:_settle(f)
end

-- true once this window has a rest point behind it
function Window:resting()
  return self.rest >= Window.REST_FRAMES
end

-- START > SAVE sends the scene so far (A5.5), wherever the player stands
function Window:flush(save)
  if not self:_ready() or not self.sent or type(save) ~= "table" then return nil end
  self:_confirm()
  return self:_send(save)
end

return Window
