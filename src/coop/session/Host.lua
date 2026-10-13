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
-- Clients send intentions; the host checks each one (Protocol.sanitize, then
-- its own rules) and answers every player with the state it may see.  This
-- issue covers joining, moving, leaving and rejoining; the campaign, world,
-- battles and saves build on it (#13 onward).

local Protocol = require("src.coop.session.Protocol")
local Random = require("src.coop.session.Random")

local Host = {}
Host.__index = Host

-- a refused link is dropped this long after its `rejected`, so the reason
-- reaches the client first (design A1.6); the same grace on shutdown
Host.GRACE = 1.0
Host.MAX_PLAYERS = 8

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
    hubs = {},
    links = {},
    players = {}, -- in join order
    byId = {},
    dirty = false,
    status = "running", -- running, ending, ended
    dropped = 0,
  }, Host)
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
-- (design A1.7, A13) is decided in #9.
function Host:cartridgeFits(game, sha1)
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
  local link = { conn = conn, player = nil, closeAt = nil }
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
  self.dirty = true
  self:_send(link, {
    type = "welcome", protocol = Protocol.VERSION, player = p.id,
    last_seq = p.lastSeq, campaign = self.campaign.id,
  })
  self:_log("joined", { name = p.name, seat = p.seat, device = p.device }, p)
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
  p.map, p.x, p.y, p.facing = msg.map, msg.x, msg.y, msg.facing
  self.dirty = true
end

function Host:_bye(link, msg)
  if not self:_sequence(link, msg) then return end
  self:_disconnect(link, "bye")
  link.conn:close()
end

local HANDLERS = { hello = Host._hello, move = Host._move, bye = Host._bye }

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
  self:_log("message", msg, link.player)
  if msg.type == "probe" then return self:_probe(link, msg, true) end
  return HANDLERS[msg.type](self, link, msg)
end

-- state -----------------------------------------------------------------

local function publicView(p)
  return { id = p.id, name = p.name, game = p.game, connected = p.connected,
           map = p.map, x = p.x, y = p.y, facing = p.facing }
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
    for _, raw in ipairs(link.conn:poll()) do
      self:_receive(link, raw)
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
  if self.status == "ending" and (#self.links == 0 or now >= self.endAt) then
    self:_finish()
  end
end

-- Clean shutdown (design A1, brief): every client is told `ended`, further
-- messages are ignored, the host closes once all have left or the grace
-- has passed.
function Host:shutdown(reason)
  if self.status ~= "running" then return end
  self.status = "ending"
  self.endAt = self.clock() + Host.GRACE
  for _, link in ipairs(self.links) do
    self:_send(link, { type = "ended", reason = reason or "host_quit" })
  end
  self:_log("shutdown", { reason = reason or "host_quit" })
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

return Host
