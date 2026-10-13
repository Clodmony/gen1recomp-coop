-- Session logs (#10, design A1.14): every device writes one JSON-lines file
-- per co-op session, in LÖVE's save folder under coop/logs.  A line holds the
-- unix time in ms, the frame, the device id, the player name, the seat, the
-- source (host or client), the player id, the kind and plain data.  The host
-- logs its start, every message with what became of it, joins, leaves,
-- refusals and its end.  The newest 30 files are kept, at most 256 MB.
--
-- Sharing (#31, design A1.14): with `share` on, a device's own lines (each
-- numbered `n`) also wait in an outbox that take() empties into a batch of
-- at most 64 KB; a line over 8 KB goes without its data, and lines that do
-- not fit are counted in a `stream_dropped` line.  Lines from other devices
-- are stored with `relay` added and never go into the outbox, so a line is
-- passed on once.  Logs contain names and addresses: they go to the other
-- players of the session and are never posted publicly.
--
--   local log = SessionLog.open({ fs = SessionLog.saveFolderFs(),
--                                 device = id.device, name = "RED", seat = 1,
--                                 share = true })
--   log:write("host", "joined", { name = "RED" }, playerId)
--   local lines = log:take()          -- own lines to send, every 2 s
--   log:writeRelayed(lines, "p…")     -- another device's lines
--   log:close()

local Json = require("src.link.Json")

local SessionLog = {}
SessionLog.__index = SessionLog

SessionLog.DIR = "coop/logs"
SessionLog.KEEP_FILES = 30
SessionLog.MAX_BYTES = 256 * 1024 * 1024

-- sharing (#31): one batch every SHARE_INTERVAL seconds, at most BATCH_BYTES
-- and BATCH_LINES; a line over LINE_BYTES goes without its data
SessionLog.SHARE_INTERVAL = 2
SessionLog.BATCH_BYTES = 64 * 1024
SessionLog.BATCH_LINES = 1024
SessionLog.LINE_BYTES = 8 * 1024
SessionLog.DROPPED = "stream_dropped"

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
    share = opts.share == true, n = 0,
    outbox = {}, outboxBytes = 0, unsent = 0, sentLines = 0, receivedLines = 0,
  }, SessionLog)
end

function SessionLog:_store(text)
  if not self.file then return end
  if self.bytes + #text + 1 > self.maxBytes then return end
  self.bytes = self.bytes + #text + 1
  self.file.write(text .. "\n")
end

-- a shared line waits for the next batch; one over LINE_BYTES without its
-- data, one that does not fit the batch is only counted
function SessionLog:_queue(line, size)
  if size > SessionLog.LINE_BYTES then
    local short = {}
    for k, v in pairs(line) do short[k] = v end
    short.data = { omitted_bytes = size }
    line = short
    size = #Json.encode(short)
  end
  if self.outboxBytes + size > SessionLog.BATCH_BYTES
     or #self.outbox >= SessionLog.BATCH_LINES then
    self.unsent = self.unsent + 1
    return
  end
  self.outbox[#self.outbox + 1] = line
  self.outboxBytes = self.outboxBytes + size
end

function SessionLog:write(source, kind, data, player)
  if not self.file and not self.share then return end
  self.n = self.n + 1
  local line = {
    t = self.clock(), frame = self.frame(), device = self.device,
    name = self.name, seat = self.seat, src = source, player = player,
    kind = kind, data = data, n = self.n,
  }
  local ok, text = pcall(Json.encode, line)
  if not ok then return end
  self:_store(text)
  if self.share and kind ~= SessionLog.DROPPED then self:_queue(line, #text) end
  return line
end

-- this device's lines since the last call, for the other players; lines that
-- did not fit are counted in a stream_dropped line at the end
function SessionLog:take()
  local out = self.outbox
  self.outbox, self.outboxBytes = {}, 0
  if self.unsent > 0 then
    local line = self:write("device", SessionLog.DROPPED, { lines = self.unsent })
    self.unsent = 0
    if line then out[#out + 1] = line end
  end
  self.sentLines = self.sentLines + #out
  return out
end

-- other devices' lines (sanitized), stored with who passed them on and when;
-- never queued, so they are not sent again
function SessionLog:writeRelayed(lines, via)
  local mark = { via = via, t = self.clock() }
  for _, line in ipairs(lines) do
    local copy = {}
    for k, v in pairs(line) do copy[k] = v end
    copy.relay = mark
    local ok, text = pcall(Json.encode, copy)
    if ok then self:_store(text) end
  end
  self.receivedLines = self.receivedLines + #lines
end

function SessionLog:close()
  if not self.file then return end
  if self.share then
    self:write("device", "close", { sent = self.sentLines, received = self.receivedLines,
                                    unsent = self.unsent })
  end
  self.file.flush()
  self.file.close()
  self.file = nil
end

return SessionLog
