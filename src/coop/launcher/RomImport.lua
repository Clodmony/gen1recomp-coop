-- ROM import for the fork's launcher (#3): verify a dropped or typed ROM by
-- SHA-1 and fill that version's private cache: Red, Blue and Yellow, and
-- the German Rote, Blaue and Gelbe Edition (#25, #40).
--
-- Upstream's launcher keeps this flow inside src/import/RomImporter.lua next
-- to its proprietary UI, so the fork does not call that file.  The steps are
-- the same and use the same GPL modules: RomArchive unwraps a .zip/.7z,
-- GameVersion.forSha1 names the cartridge, ExtractThread (or a coroutine where
-- threads are missing) runs the extractor, and CacheContract.publish writes
-- the completion marker last, so isReady() never sees a half-filled cache.

local GameVersion = require("src.core.GameVersion")
local CacheContract = require("src.import.CacheContract")

local RomImport = {}

-- The launcher's games, in menu order.
RomImport.VERSIONS = { "red", "blue", "yellow", "red_de", "blue_de", "yellow_de" }

local GB_ROM_BYTES = 1024 * 1024
local PROGRESS_CHANNEL = "coop_rom_import_progress"
local RESULT_CHANNEL = "coop_rom_import_result"

local function isGen1(version)
  for _, v in ipairs(RomImport.VERSIONS) do
    if v == version then return true end
  end
  return false
end
RomImport.isGen1 = isGen1

local function sha1(data)
  local digest = love.data.hash("sha1", data)
  if type(digest) == "userdata" and digest.getString then
    digest = digest:getString()
  end
  return love.data.encode("string", "hex", digest)
end
RomImport.sha1 = sha1

-- A save-directory cache tree, removed before a fresh import fills it.
local function removeSaveDirTree(path)
  local info = love.filesystem.getInfo(path)
  if not info then return end
  if info.type == "directory" then
    for _, child in ipairs(love.filesystem.getDirectoryItems(path)) do
      removeSaveDirTree(path .. "/" .. child)
    end
  end
  love.filesystem.remove(path)
end

-- Whether a version's ROM has been imported and its cache is complete.
function RomImport.isReady(version)
  version = version or "red"
  local CacheFs = require("src.import.CacheFs")
  pcall(CacheFs.migrateLegacyRedCache)
  return CacheContract.isReady(version, CacheFs)
end

-- The first imported game in menu order, or nil.
function RomImport.firstReady()
  for _, version in ipairs(RomImport.VERSIONS) do
    if RomImport.isReady(version) then return version end
  end
  return nil
end

-- Check bytes from a drop or a path.  Returns version, romBytes, label, sha1
-- or nil and a message for the player.
function RomImport.identify(data, displayName)
  local L = require("src.coop.launcher.Text").get
  if type(data) ~= "string" then return nil, L("The file could not be read.") end
  local RomArchive = require("src.import.RomArchive")
  if RomArchive.kind(data) then
    if #data > RomArchive.MAX_ARCHIVE_BYTES then
      return nil, L("That archive is too big to hold one Game Boy ROM.")
    end
    local bytes, entry = RomArchive.unwrap(data, displayName, {
      prefer = function(candidate) return isGen1(GameVersion.forSha1(sha1(candidate))) end,
    })
    if not bytes then return nil, tostring(entry) end
    data = bytes
    displayName = displayName and (displayName .. " / " .. entry) or entry
  end
  if #data ~= GB_ROM_BYTES then
    return nil, L("Expected a 1 MiB Game Boy ROM; this file is %.2f MiB.",
      #data / 1024 / 1024)
  end
  local hash = sha1(data)
  local version = GameVersion.forSha1(hash)
  if not version then
    return nil, L("Unknown ROM. This needs a clean US Pokemon Red, Blue or Yellow dump, or a German Rote, Blaue or Gelbe Edition (SHA-1 %s).",
      hash)
  end
  if not isGen1(version) then
    return nil, L("%s is not playable here: this launcher plays Red, Blue and Yellow, in English or German.",
      GameVersion.info(version).displayName)
  end
  return version, data, displayName, hash
end

local Job = {}
Job.__index = Job

-- Start importing verified bytes.  The job is polled once a frame with
-- job:update(); job.state is "working", "done" or "failed" (job.error).
function RomImport.start(version, data, displayName, romSha1)
  local job = setmetatable({
    version = version, displayName = displayName, sha1 = romSha1,
    state = "working", progress = 0, stage = "Preparing",
  }, Job)
  local CacheFs = require("src.import.CacheFs")
  local prefix = GameVersion.cachePrefix(version)
  job.prefix = prefix
  -- Clear the old cache from both homes before anything writes.
  local savedPrefix = CacheFs.prefix
  CacheFs.prefix = prefix
  local cleared, clearError = pcall(function()
    removeSaveDirTree(prefix .. "data/generated")
    removeSaveDirTree(prefix .. "assets/generated")
    love.filesystem.remove(prefix .. CacheContract.MARKER_PATH)
    CacheFs.removeTree("data/generated")
    CacheFs.removeTree("assets/generated")
    CacheFs.remove(CacheContract.MARKER_PATH)
  end)
  CacheFs.prefix = savedPrefix
  if not cleared then return job:fail(clearError) end
  if not job:_startThread(data) then job:_startCoroutine(data) end
  return job
end

function Job:fail(message)
  self.state = "failed"
  self.error = tostring(message)
  return self
end

function Job:_startThread(data)
  if os.getenv("POKEPORT_NO_THREAD") == "1" then return false end
  if not (love.thread and love.thread.newThread) then return false end
  local ok, thread = pcall(love.thread.newThread, "src/import/ExtractThread.lua")
  if not ok or not thread then return false end
  local progress = love.thread.getChannel(PROGRESS_CHANNEL)
  local result = love.thread.getChannel(RESULT_CHANNEL)
  progress:clear()
  result:clear()
  local started, startResult = pcall(thread.start, thread, self.version,
    self.prefix, data, PROGRESS_CHANNEL, RESULT_CHANNEL, self.sha1)
  if not started or startResult == false then return false end
  self.thread, self.progressChannel, self.resultChannel = thread, progress, result
  return true
end

function Job:_startCoroutine(data)
  local version, prefix, romSha1 = self.version, self.prefix, self.sha1
  self.worker = coroutine.create(function()
    local CacheFs = require("src.import.CacheFs")
    CacheFs.prefix = prefix
    local manifest = require("src.import.RomManifest").decode(version)
    local extractor = require("src.import.RomExtractor").new(data, manifest,
      function(progress, total, stage)
        self.progress, self.stage = progress / total, stage
        coroutine.yield()
      end, romSha1)
    extractor:run()
    CacheFs.prefix = ""
  end)
end

function Job:_finish()
  local CacheFs = require("src.import.CacheFs")
  local savedPrefix = CacheFs.prefix
  CacheFs.prefix = self.prefix
  local ok, writeError = CacheContract.publish(self.version, CacheFs, self.sha1)
  CacheFs.prefix = savedPrefix
  if not ok then
    return self:fail("could not finish the game data: " .. tostring(writeError))
  end
  self.state, self.progress, self.stage = "done", 1, "Ready"
end

function Job:update()
  if self.state ~= "working" then return self.state end
  if self.thread then
    local msg = self.progressChannel:pop()
    while msg do
      self.progress, self.stage = msg.progress / msg.total, msg.stage
      msg = self.progressChannel:pop()
    end
    local res = self.resultChannel:pop()
    if not res then
      local threadError = self.thread.getError and self.thread:getError()
      if threadError then self:fail(threadError) end
      return self.state
    end
    if not res.ok then return self:fail(res.error).state end
    self:_finish()
    return self.state
  end
  local ok, err = coroutine.resume(self.worker)
  if not ok then
    require("src.import.CacheFs").prefix = ""
    return self:fail(err).state
  end
  if coroutine.status(self.worker) == "dead" then self:_finish() end
  return self.state
end

return RomImport
