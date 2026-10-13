-- LAN discovery for co-op (#10, design A1.11): a hosting device sends its
-- lobby view and game port as one JSON UDP datagram once a second to port
-- 24681 (broadcast, the LAN's .255 and 127.0.0.1); a joining device listens
-- and lists the hosts heard in the last four seconds.  Optional: joining by
-- address works without it.  Needs luasocket (bundled with LÖVE).
--
--   local b = Beacon.sender({ lobby = function() return host:lobby() end })
--   local l = Beacon.listener()
--   every frame: b:update(dt); l:update()
--   for _, h in ipairs(l:hosts()) do h.address, h.lobby.title end

local Json = require("src.link.Json")
local Protocol = require("src.coop.session.Protocol")

local hasSocket, socket = pcall(require, "socket")
if not hasSocket then socket = nil end

local Beacon = {}

Beacon.PORT = 24681
Beacon.INTERVAL = 1
Beacon.FRESH = 4
Beacon.MAX_DATAGRAM = 8192

local function now()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return socket and socket.gettime() or os.clock()
end

function Beacon.available() return socket ~= nil end

-- an IPv4 socket: LÖVE's luasocket 3 leaves a plain socket.udp() without a
-- family, and sendto on it is refused
local function udp4()
  return (socket.udp4 or socket.udp)()
end

-- broadcast, this machine's LAN as a.b.c.255, and this machine
function Beacon.defaultTargets()
  local targets = { "255.255.255.255", "127.0.0.1" }
  local ok, ip = pcall(function()
    local udp = udp4()
    udp:setpeername("192.0.2.1", 9) -- TEST-NET-1: picks the outbound interface, sends nothing
    local addr = udp:getsockname()
    udp:close()
    return addr
  end)
  local net = ok and type(ip) == "string" and ip:match("^(%d+%.%d+%.%d+)%.%d+$")
  if net and net ~= "127.0.0" then table.insert(targets, 2, net .. ".255") end
  return targets
end

local Sender = {}
Sender.__index = Sender

function Beacon.sender(opts)
  if not socket then return nil, "the LAN beacon needs luasocket (LÖVE)" end
  local udp = udp4()
  udp:settimeout(0)
  pcall(udp.setoption, udp, "broadcast", true)
  return setmetatable({
    udp = udp, lobby = opts.lobby, port = opts.port or Beacon.PORT,
    targets = opts.targets or Beacon.defaultTargets(),
    wait = 0, sent = 0,
  }, Sender)
end

function Sender:update(dt)
  self.wait = self.wait - (dt or 0)
  if self.wait > 0 then return end
  self.wait = Beacon.INTERVAL
  local ok, text = pcall(Json.encode, self.lobby())
  if not ok or #text > Beacon.MAX_DATAGRAM then return end
  for _, ip in ipairs(self.targets) do
    if self.udp:sendto(text, ip, self.port) then self.sent = self.sent + 1 end
  end
end

function Sender:close() pcall(self.udp.close, self.udp) end

local Listener = {}
Listener.__index = Listener

-- one listener per device: a second bind of the port fails and returns nil
function Beacon.listener(opts)
  opts = opts or {}
  if not socket then return nil, "the LAN beacon needs luasocket (LÖVE)" end
  local udp = udp4()
  udp:settimeout(0)
  local ok, err = udp:setsockname(opts.bind or "*", opts.port or Beacon.PORT)
  if not ok then
    udp:close()
    return nil, "port in use (" .. tostring(err) .. ")"
  end
  return setmetatable({ udp = udp, heard = {}, dropped = 0 }, Listener)
end

function Listener:update()
  for _ = 1, 64 do
    local data, ip = self.udp:receivefrom(Beacon.MAX_DATAGRAM)
    if not data then break end
    local lobby = Protocol.LOBBY(Json.decode(data, Beacon.MAX_DATAGRAM))
    if lobby then
      local address = ("%s:%d"):format(ip, lobby.port)
      self.heard[address] = { address = address, lobby = lobby, at = now() }
    else
      self.dropped = self.dropped + 1
    end
  end
end

-- the hosts heard in the last four seconds, by address
function Listener:hosts()
  local out, t = {}, now()
  for address, h in pairs(self.heard) do
    if t - h.at <= Beacon.FRESH then out[#out + 1] = h else self.heard[address] = nil end
  end
  table.sort(out, function(a, b) return a.address < b.address end)
  return out
end

function Listener:close() pcall(self.udp.close, self.udp) end

return Beacon
