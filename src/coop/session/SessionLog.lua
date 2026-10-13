-- Session logs (#10, design A1.14): every device writes one JSON-lines file
-- per co-op session, in LÖVE's save folder under coop/logs.  A line holds the
-- unix time in ms, the frame, the device id, the player name, the seat, the
-- source (host or client), the player id, the kind and plain data.  The host
-- logs its start, every message with what became of it, joins, leaves,
-- refusals and its end.  The newest 30 files are kept, at most 256 MB.
--
-- Logs contain names and addresses: they stay on the device (sharing them
-- with the other players is a later step, see docs/coop/session.md).
--
--   local log = SessionLog.open({ fs = SessionLog.saveFolderFs(),
--                                 device = id.device, name = "RED", seat = 1 })
--   log:write("host", "joined", { name = "RED" }, playerId)
--   log:close()

local Json = require("src.link.Json")

local SessionLog = {}
SessionLog.__index = SessionLog

SessionLog.DIR = "coop/logs"
SessionLog.KEEP_FILES = 30
SessionLog.MAX_BYTES = 256 * 1024 * 1024

-- file access on LÖVE's save folder; tests pass a table with the same calls
function SessionLog.saveFolderFs()
  local fs = love.filesystem
  return {
    mkdir = function(dir) fs.createDirectory(dir) end,
    list = function(dir) return fs.getDirectoryItems(dir) end,
    size = function(path)
      local info = fs.getInfo(path)
      return info and info.size or 0
    end,
    remove = function(path) fs.remove(path) end,
    open = function(path)
      local file = fs.newFile(path)
      if not file:open("w") then return nil end
      return {
        write = function(text) file:write(text) end,
        flush = function() file:flush() end,
        close = function() file:close() end,
      }
    end,
  }
end

-- unix time in ms that only goes forward: the wall clock read once, then
-- LÖVE's timer added on
local function unixClock()
  local timer = love and love.timer and love.timer.getTime
  if not timer then return function() return os.time() * 1000 end end
  local base = os.time() - timer()
  return function() return math.floor((base + timer()) * 1000) end
end

-- oldest files go first until at most keep - 1 remain under the byte cap
function SessionLog.prune(fs, dir, keep, maxBytes)
  local names = {}
  for _, name in ipairs(fs.list(dir) or {}) do
    if name:match("^session%-.*%.jsonl$") then names[#names + 1] = name end
  end
  table.sort(names) -- names start with a sortable timestamp
  local total = 0
  for _, name in ipairs(names) do total = total + fs.size(dir .. "/" .. name) end
  local i = 1
  while i <= #names and (#names - i + 1 > keep - 1 or total > maxBytes) do
    local path = dir .. "/" .. names[i]
    total = total - fs.size(path)
    fs.remove(path)
    i = i + 1
  end
end

function SessionLog.open(opts)
  local fs = opts.fs
  local dir = opts.dir or SessionLog.DIR
  fs.mkdir(dir)
  SessionLog.prune(fs, dir, opts.keep or SessionLog.KEEP_FILES,
                   opts.maxBytes or SessionLog.MAX_BYTES)
  local stamp = opts.stamp or os.date("!%Y%m%d-%H%M%S")
  local path = ("%s/session-%s-%s.jsonl"):format(dir, stamp, opts.device or "0")
  local file = fs.open(path)
  return setmetatable({
    file = file, path = path, device = opts.device, name = opts.name,
    seat = opts.seat, frame = opts.frame or function() return 0 end,
    clock = opts.clock or unixClock(), bytes = 0,
    maxBytes = opts.maxBytes or SessionLog.MAX_BYTES,
  }, SessionLog)
end

function SessionLog:write(source, kind, data, player)
  if not self.file then return end
  local ok, line = pcall(Json.encode, {
    t = self.clock(), frame = self.frame(), device = self.device,
    name = self.name, seat = self.seat, src = source, player = player,
    kind = kind, data = data,
  })
  if not ok then return end
  if self.bytes + #line + 1 > self.maxBytes then return end
  self.bytes = self.bytes + #line + 1
  self.file.write(line .. "\n")
end

function SessionLog:close()
  if not self.file then return end
  self.file.flush()
  self.file.close()
  self.file = nil
end

return SessionLog
