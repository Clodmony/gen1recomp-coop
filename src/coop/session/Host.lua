-- The co-op host (#10): host-authoritative, run in-process by the hosting
-- device (design A1.1, A1.3).  Its own players dial it like anyone else:
-- split-screen seats over a loopback hub, network players over ENet; the
-- host serves any number of hubs at once (G3).
--
--   local host = Host.new({ campaign = { id = "c…", title = "RED" },
--                           cartridge = { game = "red", sha1 = "…" } })
--   host:serve(Transport.loopback()); host:serve(Transport.listen(port))
--   every frame: host:update()
--   host:shutdown("host_quit")  -- clients get `ended`, links close
--
-- opts.players lists the campaign's known players ({ id, name, game }, the
-- launcher's campaign card, #12): they start disconnected, so a device that
-- remembers one, or types the same name, gets that player back.
--
-- Clients send intentions; the host checks each one (Protocol.sanitize, then
-- its own rules) and answers every player with the state it may see.  This
-- issue covers joining, moving, leaving and rejoining; the campaign, world,
-- battles and saves build on it (#13 onward).
--
-- Per-link limits (#32): each frame the host decodes at most FRAME_BUDGET of
-- one link's messages (the rest waits for the next frame), so one link cannot
-- take the frame from the others; a link that sends more than its allowance
-- (BURST, refilled at RATE per second) is refused with `flood` and dropped.
--
-- Shared session logs (#31, design A1.14): a client that shares sends its
-- device's own lines in `log` batches; the host keeps them in its log (when
-- it shares too) and passes each batch on once to every other sharing
-- device, keeping LOG_BACKLOG bytes of batches for a device that joins later.

local GameVersion = require("src.core.GameVersion")
local Json = require("src.link.Json")
local Protocol = require("src.coop.session.Protocol")
local Random = require("src.coop.session.Random")
local SessionLog = require("src.coop.session.SessionLog")

local Host = {}
Host.__index = Host

-- a refused link is dropped this long after its `rejected`, so the reason
-- reaches the client first (design A1.6); the same grace on shutdown
Host.GRACE = 1.0
Host.MAX_PLAYERS = 8

-- per link: decoded per frame at most; arriving per second on average, with
-- a burst on top (two 2 MiB messages); a full PC is about 256 KB, a log
-- batch 64 KB every 2 s, a move a few dozen bytes
Host.FRAME_BUDGET = { bytes = 256 * 1024, messages = 64 }
Host.RATE = { bytes = 1024 * 1024, messages = 120 }
Host.BURST = { bytes = 4 * 1024 * 1024, messages = 512 }

Host.LOG_BACKLOG = 256 * 1024

local function defaultClock()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end


function Host.new(opts)
  assert(type(opts) == "table", "Host.new needs options")
  assert(type(opts.campaign) == "table" and opts.campaign.id, "Host needs a campaign id")
  assert(type(opts.cartridge) == "table" and opts.cartridge.game
    and opts.cartridge.sha1, "Host needs a cartridge (game and SHA-1)")
  local self = setmetatable({
    campaign = { id = opts.campaign.id, title = opts.campaign.title or "" },
    cartridge = { game = opts.cartridge.game, sha1 = opts.cartridge.sha1:lower() },
    build = opts.build or "dev",
    hostName = opts.hostName or "HOST",
    port = opts.port,
    maxPlayers = opts.maxPlayers or Host.MAX_PLAYERS,
    clock = opts.clock or defaultClock,
    hex = opts.hex or Random.hex,
    log = opts.log, -- a SessionLog, or nil
    device = opts.device or (opts.log and opts.log.device), -- this device
    frameBudget = opts.frameBudget or Host.FRAME_BUDGET,
    rate = opts.rate or Host.RATE,
    burst = opts.burst or Host.BURST,
    logBacklog = {}, logBacklogBytes = 0, logBatches = 0, logDelivered = {},
    hubs = {},
    links = {},
    players = {}, -- in join order
    byId = {},
    dirty = false,
    status = "running", -- running, ending, ended
    dropped = 0,
    floods = 0,
  }, Host)
  for _, known in ipairs(type(opts.players) == "table" and opts.players or {}) do
    if type(known) == "table" and Protocol.playerId(known.id) and Protocol.name(known.name)
        and not self.byId[known.id] and #self.players < self.maxPlayers then
      local p = { id = known.id, name = known.name, lastSeq = 0, connected = false,
                  game = Protocol.gameId(known.game) and known.game or nil }
      self.players[#self.players + 1] = p
      self.byId[p.id] = p
    end
  end
  self.sharedAt = self.clock()
  self:_log("start", { campaign = self.campaign, cartridge = self.cartridge,
                       build = self.build, protocol = Protocol.VERSION })
  return self
end

function Host:serve(hub)
  self.hubs[#self.hubs + 1] = hub
  return hub
end

function Host:_log(kind, data, player)
  if self.log then self.log:write("host", kind, data, player and player.id) end
end

-- the cartridge rule: the same game and the same dump.  Red with Blue
-- (design A1.7, A13) is decided in #9.  Languages never mix (D95, #25):
-- German plays with German only, whatever #9 lets pair.
function Host:cartridgeFits(game, sha1)
  if GameVersion.language(game) ~= GameVersion.language(self.cartridge.game) then
    return false
  end
  return game == self.cartridge.game and sha1 == self.cartridge.sha1
end

-- lobby view: what a probe and the LAN beacon show
function Host:lobby()
  local players = {}
  for _, p in ipairs(self.players) do
    players[#players + 1] = { name = p.name, game = p.game, connected = p.connected }
  end
  return {
    kind = "coop", protocol = Protocol.VERSION, build = self.build,
    campaign = self.campaign.id, title = self.campaign.title,
    game = self.cartridge.game, sha1 = self.cartridge.sha1,
    host = self.hostName, players = players, port = self.port,
  }
end

-- identity (design A1.9): the player this device remembers for the campaign
-- unless that player is connected already (a second window is someone new),
-- else a disconnected player of the same name, else nobody (a new player)
function Host:resolve(known, name)
  local id = type(known) == "table" and known[self.campaign.id] or nil
  local p = id and self.byId[id]
  if p then
    if not p.connected then return p end
    return nil
  end
  for _, q in ipairs(self.players) do
    if not q.connected and q.name == name then return q end
  end
  return nil
end

function Host:_newPlayerId()
  for _ = 1, 64 do
    local id = "p" .. self.hex(8)
    if not self.byId[id] then return id end
  end
  error("no free player id")
end

local function connectedCount(self)
  local n = 0
  for _, p in ipairs(self.players) do if p.connected then n = n + 1 end end
  return n
end

-- links -----------------------------------------------------------------

function Host:_accept(conn)
  local link = {
    conn = conn, player = nil, closeAt = nil,
    allowance = { bytes = self.burst.bytes, messages = self.burst.messages },
    meteredAt = self.clock(), seenBytes = conn.receivedBytes or 0,
    seenCount = conn.receivedCount or 0,
  }
  self.links[#self.links + 1] = link
  self:_log("link", { address = conn.address })
end

function Host:_send(link, msg)
  if link.conn.closed then return end
  link.conn:send(msg)
end

function Host:_refuse(link, seq, reason)
  self:_send(link, { type = "rejected", seq = seq, reason = reason })
  self:_log("rejected", { seq = seq, reason = reason }, link.player)
end

-- refuse and drop the link after the grace (a refused hello)
function Host:_turnAway(link, reason)
  self:_refuse(link, -1, reason)
  link.closeAt = self.clock() + Host.GRACE
end

-- what arrived on the link since the last frame, against its allowance;
-- false when the link went over (#32)
function Host:_meter(link, now)
  local conn, a = link.conn, link.allowance
  local dt = math.max(0, now - link.meteredAt)
  link.meteredAt = now
  local bytes, count = conn.receivedBytes - link.seenBytes, conn.receivedCount - link.seenCount
  link.seenBytes, link.seenCount = conn.receivedBytes, conn.receivedCount
  a.bytes = math.min(self.burst.bytes, a.bytes + dt * self.rate.bytes) - bytes
  a.messages = math.min(self.burst.messages, a.messages + dt * self.rate.messages) - count
  return a.bytes >= 0 and a.messages >= 0
end

-- a link over its allowance: told why, its player leaves, nothing more it
-- sends is read, and the link closes after the grace
function Host:_flood(link, now)
  link.flooded = true
  link.conn:discard()
  self.floods = self.floods + 1
  self:_log("flood", { address = link.conn.address, received = link.conn.receivedBytes,
                       messages = link.conn.receivedCount }, link.player)
  self:_refuse(link, -1, "flood")
  self:_disconnect(link, "flood")
  link.closeAt = now + Host.GRACE
end

function Host:_disconnect(link, why)
  local p = link.player
  if not p then return end
  link.player = nil
  if p.link == link then
    p.link = nil
    p.connected = false
    self.dirty = true
    self:_log("left", { why = why }, p)
  end
end

-- messages --------------------------------------------------------------

function Host:_probe(link, msg, protocolOk)
  local view = self:lobby()
  view.type = "probe"
  view.refused = ""
  if not protocolOk then
    view.refused = "protocol_mismatch"
  elseif not self:cartridgeFits(msg.game, msg.sha1) then
    view.refused = "content_mismatch"
  end
  local you = protocolOk and self:resolve(msg.known, msg.name)
  view.you = you and { player = you.id, name = you.name } or {}
  self:_send(link, view)
end

function Host:_hello(link, msg)
  if link.player then return self:_refuse(link, -1, "already_joined") end
  if self.status ~= "running" then return self:_turnAway(link, "shutting_down") end
  if not self:cartridgeFits(msg.game, msg.sha1) then
    return self:_turnAway(link, "content_mismatch")
  end
  local p = self:resolve(msg.known, msg.name)
  if not p then
    if #self.players >= self.maxPlayers then
      return self:_turnAway(link, "session_full")
    end
    p = { id = self:_newPlayerId(), name = msg.name, lastSeq = 0 }
    self.players[#self.players + 1] = p
    self.byId[p.id] = p
    self:_log("new_player", { name = p.name }, p)
  elseif connectedCount(self) >= self.maxPlayers then
    return self:_turnAway(link, "session_full")
  end
  p.connected = true
  p.link = link
  p.game = msg.game
  p.device, p.seat, p.via = msg.device, msg.seat, msg.via
  link.player = p
  link.device = msg.device
  link.shareLogs = msg.logs ~= nil and msg.logs.share == true
  self.dirty = true
  self:_send(link, {
    type = "welcome", protocol = Protocol.VERSION, player = p.id,
    last_seq = p.lastSeq, campaign = self.campaign.id,
  })
  self:_log("joined", { name = p.name, seat = p.seat, device = p.device,
                        logs = link.shareLogs }, p)
  self:_sendLogBacklog(link)
end

-- per-player sequence numbers (design A1.5): strictly increasing; a number
-- seen before is refused and changes nothing
function Host:_sequence(link, msg)
  local p = link.player
  if not p then
    self:_refuse(link, msg.seq, "hello_first")
    return nil
  end
  if msg.seq <= p.lastSeq then
    self:_refuse(link, msg.seq, "duplicate")
    return nil
  end
  p.lastSeq = msg.seq
  return p
end

-- Windows are trusted (design A1.10, D72): the host checks only the step
-- length (up to two cells on the same map, a ledge hop) and takes a reported
-- warp as it is.
function Host:_move(link, msg)
  local p = self:_sequence(link, msg)
  if not p then return end
  if p.map and not msg.warp then
    local far = math.abs(msg.x - p.x) + math.abs(msg.y - p.y)
    if msg.map ~= p.map or far > 2 then
      return self:_refuse(link, msg.seq, "bad_step")
    end
  end
  p.map, p.x, p.y, p.facing, p.travel = msg.map, msg.x, msg.y, msg.facing, msg.travel
  self.dirty = true
end

function Host:_bye(link, msg)
  if not self:_sequence(link, msg) then return end
  self:_disconnect(link, "bye")
  link.conn:close()
end

-- shared session logs (#31) ---------------------------------------------

-- a joined link that shares, of another device than the host's own (whose
-- lines are already in the host's log); its last batch may arrive with its
-- bye, after the link closed
function Host:_streamsTo(link)
  return link.player ~= nil and link.shareLogs and link.device ~= self.device
    and not link.flooded
end

-- a batch of lines, once to every sharing device but the one they came from,
-- and into the backlog for devices that join later
function Host:_passLog(lines, fromDevice)
  if #lines == 0 then return end
  self.logBatches = self.logBatches + 1
  local batch = { serial = self.logBatches, lines = lines, bytes = #Json.encode(lines) }
  self.logBacklog[#self.logBacklog + 1] = batch
  self.logBacklogBytes = self.logBacklogBytes + batch.bytes
  while self.logBacklogBytes > Host.LOG_BACKLOG do
    self.logBacklogBytes = self.logBacklogBytes - table.remove(self.logBacklog, 1).bytes
  end
  local sent = {}
  for _, link in ipairs(self.links) do
    if self:_streamsTo(link) and not link.conn.closed and link.device ~= fromDevice
       and not sent[link.device] then
      sent[link.device] = true
      self:_send(link, { type = "log", lines = lines })
      self.logDelivered[link.device] = self.logBatches
    end
  end
end

-- what a device that shares from now on missed of the others' lines, as far
-- back as the backlog goes
function Host:_sendLogBacklog(link)
  if not self:_streamsTo(link) or link.conn.closed then return end
  local device = link.device
  for _, batch in ipairs(self.logBacklog) do
    if batch.serial > (self.logDelivered[device] or 0) then
      local lines = {}
      for _, line in ipairs(batch.lines) do
        if line.device ~= device then lines[#lines + 1] = line end
      end
      if #lines > 0 then self:_send(link, { type = "log", lines = lines }) end
    end
  end
  self.logDelivered[device] = self.logBatches
end

-- a client's own lines: only those of its device, up to a batch (a line
-- over LINE_BYTES is skipped); kept in the host's log when the host shares
-- and passed on
function Host:_logBatch(link, msg)
  local summary = { type = "log", lines = #msg.lines }
  if not self:_streamsTo(link) then
    summary.result = "ignored"
    return self:_log("message", summary, link.player)
  end
  local taken, bytes = {}, 0
  for _, line in ipairs(msg.lines) do
    if line.device == link.device then
      local size = #Json.encode(line)
      bytes = bytes + size
      if bytes > SessionLog.BATCH_BYTES + SessionLog.LINE_BYTES then break end
      if size <= SessionLog.LINE_BYTES then taken[#taken + 1] = line end
    end
  end
  summary.result = #taken .. " taken"
  self:_log("message", summary, link.player)
  if self.log and self.log.share then self.log:writeRelayed(taken, link.player.id) end
  self:_passLog(taken, link.device)
end

-- the host's own lines, every SHARE_INTERVAL seconds or when `now`
function Host:_shareOwnLog(now)
  if not (self.log and self.log.share) then return end
  local t = self.clock()
  if not now and t - self.sharedAt < SessionLog.SHARE_INTERVAL then return end
  self.sharedAt = t
  self:_passLog(self.log:take(), self.device)
end

local HANDLERS = { hello = Host._hello, move = Host._move, bye = Host._bye,
                   log = Host._logBatch }

function Host:_receive(link, raw)
  if self.status ~= "running" then return end -- ending: nothing counts
  -- another protocol version: answered with the reason before anything else
  -- is read, since its fields need not match ours (design A1.6)
  if type(raw) == "table" and (raw.type == "probe" or raw.type == "hello")
     and type(raw.protocol) == "number" and raw.protocol ~= Protocol.VERSION then
    self:_log("message", { type = raw.type, result = "protocol_mismatch",
                           protocol = raw.protocol }, link.player)
    if raw.type == "probe" then return self:_probe(link, {}, false) end
    return self:_turnAway(link, "protocol_mismatch")
  end
  local msg, why = Protocol.sanitize(raw, "host")
  if not msg then
    self.dropped = self.dropped + 1
    self:_log("dropped", { why = why }, link.player)
    return
  end
  -- a log batch is logged by its handler, as a summary
  if msg.type ~= "log" then self:_log("message", msg, link.player) end
  if msg.type == "probe" then return self:_probe(link, msg, true) end
  return HANDLERS[msg.type](self, link, msg)
end

-- state -----------------------------------------------------------------

local function publicView(p)
  return { id = p.id, name = p.name, game = p.game, connected = p.connected,
           map = p.map, x = p.x, y = p.y, facing = p.facing,
           travel = p.map and p.travel or nil }
end

function Host:_broadcast()
  local players = {}
  for i, p in ipairs(self.players) do players[i] = publicView(p) end
  for _, link in ipairs(self.links) do
    local p = link.player
    if p and not link.conn.closed then
      local nearby = {}
      for _, q in ipairs(self.players) do
        if q ~= p and q.connected and q.map and q.map == p.map then
          nearby[#nearby + 1] = q.id
        end
      end
      self:_send(link, { type = "state", players = players, you = p.id,
                         last_seq = p.lastSeq, nearby = nearby })
    end
  end
end

function Host:update()
  if self.status == "ended" then return end
  for _, hub in ipairs(self.hubs) do
    hub:update()
    for _, conn in ipairs(hub:accept()) do
      if self.status == "running" then
        self:_accept(conn)
      else
        conn:close()
      end
    end
  end
  local now = self.clock()
  local keep = {}
  for _, link in ipairs(self.links) do
    link.conn:update()
    if link.flooded then
      link.conn:discard()
    elseif not self:_meter(link, now) then
      self:_flood(link, now)
    else
      for _, raw in ipairs(link.conn:poll(self.frameBudget)) do
        self:_receive(link, raw)
      end
    end
    if link.conn.dropped and link.conn.dropped > (link.seenDropped or 0) then
      self.dropped = self.dropped + link.conn.dropped - (link.seenDropped or 0)
      link.seenDropped = link.conn.dropped
    end
    if link.closeAt and now >= link.closeAt then link.conn:close() end
    if link.conn.closed then
      self:_disconnect(link, "link_closed")
    else
      keep[#keep + 1] = link
    end
  end
  self.links = keep
  if self.dirty and self.status == "running" then
    self.dirty = false
    self:_broadcast()
  end
  if self.status == "running" then self:_shareOwnLog() end
  if self.status == "ending" and (#self.links == 0 or now >= self.endAt) then
    self:_finish()
  end
end

-- Clean shutdown (design A1, brief): every client is told `ended`, further
-- messages are ignored, the host closes once all have left or the grace
-- has passed.
function Host:shutdown(reason)
  if self.status ~= "running" then return end
  self:_log("shutdown", { reason = reason or "host_quit" })
  self:_shareOwnLog(true) -- the host's last lines go out before `ended`
  self.status = "ending"
  self.endAt = self.clock() + Host.GRACE
  for _, link in ipairs(self.links) do
    self:_send(link, { type = "ended", reason = reason or "host_quit" })
  end
end

function Host:_finish()
  for _, link in ipairs(self.links) do
    self:_disconnect(link, "shutdown")
    link.conn:close()
  end
  self.links = {}
  for _, hub in ipairs(self.hubs) do hub:close() end
  self.status = "ended"
  local players = {}
  for i, p in ipairs(self.players) do players[i] = publicView(p) end
  self:_log("end", { players = players })
  if self.log then self.log:close() end
end

function Host:player(id) return self.byId[id] end

-- every player the session has seen, for the campaign card (#12): id, name,
-- game, connected, and the address they dialled (`via`)
function Host:roster()
  local out = {}
  for i, p in ipairs(self.players) do
    out[i] = { id = p.id, name = p.name, game = p.game, connected = p.connected == true,
               via = p.via }
  end
  return out
end

return Host
