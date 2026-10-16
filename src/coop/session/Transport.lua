-- Co-op session transports (#10): one host, many clients, plain tables in
-- and out.  Two kinds, one API, so the host never knows which it runs over
-- (design A1.2):
--
--   loopback  in memory, in this process: the split-screen transport (both
--             local seats dial the in-process host this way) and the tests'
--   enet      direct UDP over lua-enet (bundled with LÖVE): LAN, a forwarded
--             port or a VPN (G5)
--
--   local hub = Transport.loopback()          -- or Transport.listen(port)
--   local conn = hub:dial()                   -- or Transport.dial("ip:port")
--   every frame: hub:update(); for _, c in ipairs(hub:accept()) do ... end
--   conn:update(); for _, msg in ipairs(conn:poll()) do ... end
--   conn:send({ type = "hello", ... }); conn:close()
--
-- Both kinds carry JSON text (src/link/Json.lua); a loopback message is
-- encoded and decoded like a network one, so a test over loopback sees what
-- a peer would.  A message longer than Protocol.MAX_MESSAGE or not valid
-- JSON is dropped and counted in conn.dropped.  Arriving text waits on the
-- link undecoded and poll decodes it, all of it or as much as a budget
-- allows, so the host can hold one link to a share of each frame (#32);
-- conn.receivedBytes and conn.receivedCount count what arrived.  Upstream's src/link/Net.lua
-- pairs exactly two ends and caps a message at 256 KB, so co-op has its own.

local Json = require("src.link.Json")
local Protocol = require("src.coop.session.Protocol")

local hasEnet, enet = pcall(require, "enet")
if not hasEnet then enet = nil end

local Transport = {}

Transport.DEFAULT_PORT = 24680 -- G8: upstream's link keeps 7777
Transport.MAX_PEERS = 32
Transport.CONNECT_TIMEOUT = 5

function Transport.available()
  return enet ~= nil
end

local function now()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

local function encode(msg)
  local ok, text = pcall(Json.encode, msg)
  if ok and #text <= Protocol.MAX_MESSAGE then return text end
  return nil
end

-- arriving text waits on the link; poll decodes it
local function arrive(conn, text)
  conn.receivedBytes = conn.receivedBytes + #text
  conn.receivedCount = conn.receivedCount + 1
  if #text > Protocol.MAX_MESSAGE then
    conn.dropped = conn.dropped + 1
    return
  end
  conn.wire[#conn.wire + 1] = text
end

-- one end of a link ------------------------------------------------------

local Conn = {}
Conn.__index = Conn

local function newConn(kind)
  return setmetatable({
    kind = kind, wire = {}, dropped = 0, closed = false, error = nil,
    address = nil, sent = 0, receivedBytes = 0, receivedCount = 0,
  }, Conn)
end

-- The messages that arrived, decoded.  With a budget ({ bytes, messages })
-- it stops before the message that would go over either, but always takes
-- one; the rest waits for the next poll.
function Conn:poll(budget)
  local wire, out = self.wire, {}
  local i, bytes = 1, 0
  while i <= #wire do
    local text = wire[i]
    if budget and i > 1 and (bytes + #text > budget.bytes or i > budget.messages) then
      break
    end
    bytes = bytes + #text
    local msg = Json.decode(text, Protocol.MAX_MESSAGE)
    if type(msg) == "table" then
      out[#out + 1] = msg
    else
      self.dropped = self.dropped + 1
    end
    i = i + 1
  end
  local rest = {}
  for j = i, #wire do rest[#rest + 1] = wire[j] end
  self.wire = rest
  return out
end

-- the undecoded text waiting on the link, dropped (a flooding link)
function Conn:discard()
  self.wire = {}
end

-- loopback ---------------------------------------------------------------

function Conn:_loopSend(text)
  local other = self.other
  if other and not other.closed then arrive(other, text) end
end

-- sends one message; false when it is too big to encode or the link is gone
function Conn:send(msg)
  if self.closed then return false end
  local text = encode(msg)
  if not text then return false end
  return self:sendRaw(text)
end

-- the wire text as it is (the fuzz test sends broken JSON this way)
function Conn:sendRaw(text)
  if self.closed then return false end
  if self.connecting then -- goes out once the host accepts
    self.outbox[#self.outbox + 1] = text
    return true
  end
  self.sent = self.sent + 1
  if self.kind == "loopback" then
    self:_loopSend(text)
    return true
  end
  local ok = pcall(self.peer.send, self.peer, text, 0, "reliable")
  if not ok then
    self.error = "send failed"
    self.closed = true
  end
  return ok
end

function Conn:update()
  if self.kind == "loopback" then
    if self.other and self.other.closed then self.closed = true end
    return
  end
  if self.client then self:_serviceClient() end
end

-- The host doubts this link is still there (a hello from the same seat of
-- the same device came on another link): a dead one closes soon.  ENet
-- times the peer out within a second or so unless it answers; a loopback
-- link whose other end is gone closes now.
function Conn:suspect()
  if self.closed then return end
  if self.kind == "loopback" then
    if not self.other then self:close() end
    return
  end
  if self.peer then
    pcall(self.peer.timeout, self.peer, 4, 300, 1200)
    pcall(self.peer.ping, self.peer)
  end
end

function Conn:close()
  if self.closed then return end
  self.closed = true
  if self.kind == "loopback" then
    if self.other then self.other.closed = true end
    return
  end
  if self.peer then pcall(self.peer.disconnect_later, self.peer) end
  if self.client and self.enetHost then
    -- deliver what is queued (a bye), then let go of the socket
    local deadline = now() + 0.5
    while now() < deadline do
      local ok, event = pcall(self.enetHost.service, self.enetHost, 10)
      if not ok or (event and event.type == "disconnect") then break end
    end
    pcall(self.enetHost.destroy, self.enetHost)
    self.enetHost = nil
  end
end

local Loopback = {}
Loopback.__index = Loopback

function Transport.loopback()
  return setmetatable({ pending = {}, closed = false, kind = "loopback" }, Loopback)
end

function Loopback:dial()
  local client, server = newConn("loopback"), newConn("loopback")
  client.other, server.other = server, client
  client.address, server.address = "loopback", "loopback"
  if self.closed then
    client.closed, server.closed = true, true
    client.error = "nobody is hosting"
  else
    self.pending[#self.pending + 1] = server
  end
  return client
end

function Loopback:update() end

function Loopback:accept()
  local out = self.pending
  self.pending = {}
  return out
end

function Loopback:close() self.closed = true end

-- ENet: the host side ----------------------------------------------------

local Listener = {}
Listener.__index = Listener

-- Opens UDP `port` on every interface.  Returns the listener, or nil and why.
function Transport.listen(port)
  if not enet then return nil, "co-op over the network needs LÖVE (lua-enet)" end
  port = tonumber(port) or Transport.DEFAULT_PORT
  local ok, h, err = pcall(enet.host_create, ("*:%d"):format(port),
                           Transport.MAX_PEERS, 1, 0, 0)
  if not ok or not h then
    return nil, ("can't open UDP port %d (%s)"):format(port, tostring(ok and err or h))
  end
  return setmetatable({
    enetHost = h, port = port, conns = {}, pending = {}, closed = false,
    kind = "enet",
  }, Listener)
end

function Listener:update()
  if self.closed then return end
  while true do
    local ok, event = pcall(self.enetHost.service, self.enetHost, 0)
    if not ok or not event then break end
    local key = tostring(event.peer)
    if event.type == "connect" then
      local conn = newConn("enet")
      conn.peer = event.peer
      conn.address = tostring(event.peer)
      self.conns[key] = conn
      self.pending[#self.pending + 1] = conn
    elseif event.type == "receive" then
      local conn = self.conns[key]
      if conn and not conn.closed then arrive(conn, event.data) end
    elseif event.type == "disconnect" then
      local conn = self.conns[key]
      if conn then conn.closed = true end
      self.conns[key] = nil
    end
  end
end

function Listener:accept()
  local out = self.pending
  self.pending = {}
  return out
end

function Listener:close()
  if self.closed then return end
  self.closed = true
  for _, conn in pairs(self.conns) do
    pcall(conn.peer.disconnect_later, conn.peer)
  end
  local deadline = now() + 0.5
  while next(self.conns) and now() < deadline do
    local ok, event = pcall(self.enetHost.service, self.enetHost, 10)
    if not ok then break end
    if event and event.type == "disconnect" then
      local conn = self.conns[tostring(event.peer)]
      if conn then conn.closed = true end
      self.conns[tostring(event.peer)] = nil
    end
  end
  pcall(self.enetHost.flush, self.enetHost)
  pcall(self.enetHost.destroy, self.enetHost)
end

-- ENet: the client side --------------------------------------------------

-- "host", "host:port", "[v6]:port"; returns host, port
function Transport.parseAddress(address)
  if type(address) ~= "string" then return nil end
  address = address:match("^%s*(.-)%s*$")
  local h, p = address:match("^%[(.+)%]:(%d+)$")
  if not h then h, p = address:match("^([^:]+):(%d+)$") end
  if not h then h = address:match("^%[(.+)%]$") or address end
  if h == "" then return nil end
  p = tonumber(p) or Transport.DEFAULT_PORT
  if p < 1 or p > 65535 then return nil end
  return h, p
end

-- Dials `address`; the connection is `connecting` until the host accepts.
-- Messages sent before that wait and go out once it is up.
function Transport.dial(address)
  local conn = newConn("enet")
  conn.client = true
  conn.outbox = {}
  if not enet then
    conn.closed, conn.error = true, "co-op over the network needs LÖVE (lua-enet)"
    return conn
  end
  local h, p = Transport.parseAddress(address)
  if not h then
    conn.closed, conn.error = true, "bad address"
    return conn
  end
  conn.address = ("%s:%d"):format(h, p)
  local ok, host = pcall(enet.host_create, nil, 1, 1, 0, 0)
  if not ok or not host then
    conn.closed, conn.error = true, "can't create a network socket"
    return conn
  end
  local okc, peer = pcall(host.connect, host, conn.address, 1)
  if not okc or not peer then
    pcall(host.destroy, host)
    conn.closed, conn.error = true, "bad address " .. conn.address
    return conn
  end
  conn.enetHost, conn.peer = host, peer
  conn.connecting = true
  conn.deadline = now() + Transport.CONNECT_TIMEOUT
  return conn
end

function Conn:_serviceClient()
  if self.closed or not self.enetHost then return end
  while true do
    local ok, event = pcall(self.enetHost.service, self.enetHost, 0)
    if not ok then
      self.error = self.connecting and ("no answer from " .. self.address)
        or tostring(event)
      self.closed = true
      return
    end
    if not event then break end
    if event.type == "connect" then
      self.connecting = false
      local queued = self.outbox
      self.outbox = {}
      for _, text in ipairs(queued) do self:sendRaw(text) end
    elseif event.type == "receive" then
      arrive(self, event.data)
    elseif event.type == "disconnect" then
      if self.connecting then self.error = "no answer from " .. self.address end
      self.closed = true
      return
    end
  end
  if self.connecting and now() > self.deadline then
    self.error = "no answer from " .. self.address
    self.closed = true
    pcall(self.peer.disconnect_now, self.peer)
  end
end

return Transport
