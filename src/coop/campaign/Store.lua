-- When the host writes its campaign (#13, design A3.7 to A3.9, A3.12): the
-- checkpoints and the journal between them.
--
--   local store = Store.new({ campaign = c, fs = CampaignFile.loveFs() })
--   store:checkpoint("menu")   -- a real SAVE; true, or false and why
--   every host poll: store:poll(busy)  -- busy: a battle runs or a join is pending
--   store:savedAgo()           -- seconds since the last checkpoint, or nil
--
-- Checkpoints only at a safe point: no battle running and no join pending
-- (the host checks before it asks).  The host saves by itself
-- (design A3.9): when its last running battle ends, at most every
-- AUTOSAVE seconds while something changed and no battle runs, when a
-- player leaves, on shutdown, and when the hosting app is paused.  Between
-- checkpoints, at the end of every poll in which the campaign's revision
-- moved, the whole state goes to the journal as one line.  A crash loses
-- at most the battle in progress.

local CampaignFile = require("src.coop.campaign.CampaignFile")

local Store = {}
Store.__index = Store

Store.AUTOSAVE = 30 -- seconds between saves while something changed

local function defaultClock()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

function Store.new(opts)
  local self = setmetatable({
    campaign = assert(opts.campaign, "Store needs a campaign"),
    fs = opts.fs or CampaignFile.loveFs(),
    clock = opts.clock or defaultClock,
    log = opts.log, -- function(kind, data), or nil
    interval = opts.autosave or Store.AUTOSAVE,
    savedRevision = nil, -- the revision of the last checkpoint
    journalRevision = nil, -- the revision of the last journal line
    savedAt = nil, -- clock time of the last checkpoint
    wasBusy = false,
    journalBytes = 0,
  }, Store)
  -- a campaign read from its file starts saved at that revision
  if opts.saved then
    self.savedRevision = self.campaign.revision
    self.journalRevision = self.campaign.revision
    self.pcAtCheckpoint = self.campaign:boxesTexts()
  end
  return self
end

function Store:_log(kind, data)
  if self.log then self.log(kind, data) end
end

function Store:changed()
  return self.savedRevision ~= self.campaign.revision
end

-- Write the campaign's file now.  Returns true, or false and why.
function Store:checkpoint(reason)
  local c = self.campaign
  local ok, why = CampaignFile.write(self.fs, c)
  self:_log("checkpoint", { reason = reason, revision = c.revision, ok = ok, why = why })
  if not ok then return false, why end
  self.savedRevision = c.revision
  self.journalRevision = c.revision
  self.savedAt = self.clock()
  self.lastReason = reason
  self.pcAtCheckpoint = c:boxesTexts()
  self.journalBytes = 0
  return true
end

-- a line of the whole state when the revision moved since the last
-- checkpoint or line; each PC unchanged since the checkpoint left out
function Store:_journal()
  local c = self.campaign
  if self.journalRevision == c.revision then return end
  local skip = {}
  local now = c:boxesTexts()
  for id, text in pairs(now) do
    if self.pcAtCheckpoint and self.pcAtCheckpoint[id] == text then skip[id] = true end
  end
  local ok, bytes = pcall(CampaignFile.appendJournal, self.fs, c, skip)
  if ok then
    self.journalRevision = c.revision
    self.journalBytes = self.journalBytes + bytes
    self.lastLine = bytes
  else
    self:_log("journal_failed", { why = tostring(bytes) })
  end
end

-- End of a host poll.  `busy`: a battle runs or a join is pending.
function Store:poll(busy)
  local now = self.clock()
  if self:changed() and not busy then
    if self.wasBusy then
      -- the last running battle ended
      self.wasBusy = busy
      if self:checkpoint("battle_end") then return end
    elseif now - (self.savedAt or -math.huge) >= self.interval then
      self.wasBusy = busy
      if self:checkpoint("autosave") then return end
    end
  end
  self.wasBusy = busy
  self:_journal()
end

-- seconds since the last checkpoint, or nil when there was none
function Store:savedAgo()
  if not self.savedAt then return nil end
  return math.max(0, self.clock() - self.savedAt)
end

return Store
