-- A co-op client (#10): one player's link to the host, over loopback (a
-- split-screen seat, or the hosting device's own player) or ENet.  It sends
-- numbered intentions and keeps what the host last told it; no game rule
-- runs here (design A1.1).
--
--   local c = Client.new(conn, { name = "RED", game = "red", sha1 = "…",
--                                device = "…", seat = 1, known = {…} })
--   c:probe()            -- optional: the lobby view, nobody is created
--   c:join()             -- hello; status becomes "joined" on welcome
--   every frame: c:update()
--   c:move("PALLET_TOWN", 5, 6, "down", false, "walk")
--   c:leave()
--
-- status: idle, probing, probed, joining, joined, refused, ended, closed.
-- A refusal or an end leaves its reason in c.reason.
--
-- With opts.log, a SessionLog that shares (#31), the client sends its
-- device's own lines in a `log` batch every SessionLog.SHARE_INTERVAL
-- seconds and a last one before its bye, and stores the other devices'
-- lines the host passes on.  One link per device carries the log: a second
-- seat of the same device gets no log.

local Protocol = require("src.coop.session.Protocol")
local SessionLog = require("src.coop.session.SessionLog")

local Client = {}
Client.__index = Client

local function defaultClock()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

function Client.new(conn, opts)
  opts = opts or {}
  return setmetatable({
    conn = conn,
    name = opts.name or "PLAYER",
    game = opts.game, sha1 = opts.sha1 or "",
    build = opts.build or "dev",
    device = opts.device or "0", seat = opts.seat or 1,
    known = opts.known or {}, via = opts.via,
    status = "idle", reason = nil,
    seq = 0, player = nil, campaign = nil,
    lobby = nil, state = nil,
    rejections = {}, -- { seq, reason } for intentions the host refused
    dropped = 0,
    onWelcome = opts.onWelcome,
    log = opts.log, clock = opts.clock or defaultClock, sharedAt = nil,
  }, Client)
end

function Client:_identity(kind)
  return {
    type = kind, protocol = Protocol.VERSION, build = self.build,
    name = self.name, game = self.game, sha1 = self.sha1, known = self.known,
  }
end

function Client:probe()
  self.status = "probing"
  self.conn:send(self:_identity("probe"))
end

function Client:sharesLog()
  return self.log ~= nil and self.log.share == true
end

function Client:join()
  local hello = self:_identity("hello")
  hello.device, hello.seat, hello.via = self.device, self.seat, self.via
  hello.logs = { share = self:sharesLog() }
  self.status = "joining"
  self.conn:send(hello)
end

-- an intention: numbered, sent only while joined; returns its seq
function Client:send(msg)
  if self.status ~= "joined" then return nil end
  self.seq = self.seq + 1
  msg.seq = self.seq
  self.conn:send(msg)
  return self.seq
end

function Client:move(map, x, y, facing, warp, travel)
  return self:send({ type = "move", map = map, x = x, y = y,
                     facing = facing, warp = warp and true or false,
                     travel = travel or "walk" })
end

-- this device's lines since the last batch, every SHARE_INTERVAL seconds
-- (or `now`); true when a batch went out
function Client:shareLog(now)
  if self.status ~= "joined" or not self:sharesLog() then return false end
  local t = self.clock()
  if not now and self.sharedAt and t - self.sharedAt < SessionLog.SHARE_INTERVAL then
    return false
  end
  self.sharedAt = t
  local lines = self.log:take()
  if #lines == 0 then return false end
  self.conn:send({ type = "log", lines = lines })
  return true
end

function Client:leave()
  if self.status == "joined" then
    self:shareLog(true)
    self:send({ type = "bye" })
  end
  self.conn:close()
  self.status = "closed"
end

function Client:_handle(msg)
  local t = msg.type
  if t == "probe" then
    self.lobby = msg
    if self.status == "probing" then self.status = "probed" end
  elseif t == "welcome" then
    self.player, self.campaign = msg.player, msg.campaign
    -- a rejoining player continues after the last number the host saw
    self.seq = math.max(self.seq, msg.last_seq)
    self.status = "joined"
    self.known[msg.campaign] = msg.player
    if self.onWelcome then self.onWelcome(self, msg) end
  elseif t == "state" then
    self.state = msg
  elseif t == "log" then
    -- other devices' lines; this device's own never come back
    if self.log then
      local lines = {}
      for _, line in ipairs(msg.lines) do
        if line.device ~= self.device then lines[#lines + 1] = line end
      end
      self.log:writeRelayed(lines, "host")
    end
  elseif t == "rejected" then
    -- a refused hello, or a joined link the host drops (a flood)
    if msg.seq == -1 and (self.status ~= "joined" or msg.reason == "flood") then
      self.status, self.reason = "refused", msg.reason
    else
      self.rejections[#self.rejections + 1] = { seq = msg.seq, reason = msg.reason }
    end
  elseif t == "ended" then
    self.status, self.reason = "ended", msg.reason
    self.conn:close()
  end
end

function Client:update()
  self.conn:update()
  for _, raw in ipairs(self.conn:poll()) do
    local msg = Protocol.sanitize(raw, "client")
    if msg then
      self:_handle(msg)
    else
      self.dropped = self.dropped + 1
    end
  end
  self:shareLog()
  if self.conn.closed and self.status ~= "refused" and self.status ~= "ended" then
    if self.status ~= "closed" then self.reason = self.conn.error end
    self.status = "closed"
  end
end

-- the public view of a player in the last state, or nil
function Client:playerView(id)
  for _, p in ipairs(self.state and self.state.players or {}) do
    if p.id == id then return p end
  end
  return nil
end

return Client
