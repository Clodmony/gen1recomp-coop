-- Network addresses for the launcher's co-op screens (#12, design A2.4,
-- A2.6): the addresses a hosting device can be reached at, each labelled by
-- the kind of network (a VPN first, then the home network), and what to
-- check when a partner's address cannot be reached.
--
--   Addresses.kind("192.168.1.20")   -- "home"
--   Addresses.mine()                 -- { { ip = "100.101.2.3", kind = "vpn" }, … }
--   Addresses.checklist("vpn")       -- lines to show after a failed dial
--
-- Needs luasocket (bundled with LÖVE) to find this device's addresses;
-- without it mine() returns an empty list.

local hasSocket, socket = pcall(require, "socket")
if not hasSocket then socket = nil end

local Addresses = {}

Addresses.LABELS = { vpn = "VPN", home = "HOME", public = "INTERNET", here = "THIS DEVICE",
                     name = "NAME" }

local function octets(ip)
  local a, b, c, d = tostring(ip):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  if not (a and a <= 255 and b <= 255 and c <= 255 and d <= 255) then return nil end
  return a, b, c, d
end

-- "here" (this machine), "vpn" (100.64.0.0/10, the shared range Tailscale
-- and carrier VPNs use), "home" (the private ranges), "public", or "name"
-- for a host name; nil for an address that never reaches a partner
function Addresses.kind(address)
  local host = tostring(address or ""):gsub(":%d+$", "")
  if host == "" then return nil end
  if host == "localhost" then return "here" end
  local a, b = octets(host)
  if not a then
    if host:find("^[%w][%w%.%-]*$") then return "name" end
    return nil
  end
  if a == 127 then return "here" end
  if a == 0 or a >= 224 or (a == 169 and b == 254) then return nil end
  if a == 100 and b >= 64 and b <= 127 then return "vpn" end
  if a == 10 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168) then
    return "home"
  end
  return "public"
end

local ORDER = { vpn = 1, home = 2, public = 3, name = 4, here = 5 }

-- this device's address towards `probe`: a UDP socket's own address once
-- the system has picked the route (nothing is sent)
local function routeTo(probe)
  local ok, ip = pcall(function()
    local udp = (socket.udp4 or socket.udp)()
    udp:setpeername(probe, 9)
    local addr = udp:getsockname()
    udp:close()
    return addr
  end)
  return ok and type(ip) == "string" and ip or nil
end

-- VPN first, then the home network, then public ones (in place)
function Addresses.sort(list)
  table.sort(list, function(x, y)
    local ox, oy = ORDER[x.kind] or 9, ORDER[y.kind] or 9
    if ox ~= oy then return ox < oy end
    return x.ip < y.ip
  end)
  return list
end

-- The addresses partners can dial, VPN first, then the home network, then
-- a public one.  Found from the routes to a few far addresses (the default
-- route; Tailscale's 100.100.100.100) and the host name's addresses.
-- `sources` replaces the lookups in tests.
function Addresses.mine(sources)
  sources = sources or {}
  local found = {}
  local function add(ip)
    local kind = Addresses.kind(ip)
    if kind and kind ~= "here" and kind ~= "name" and not found[ip] then
      found[ip] = kind
    end
  end
  local route = sources.route or (socket and routeTo)
  local names = sources.names
  if not names and socket and socket.dns then
    names = function()
      local okName, hostname = pcall(socket.dns.gethostname)
      if not okName or not hostname then return {} end
      local okIp, _, info = pcall(socket.dns.toip, hostname)
      return okIp and type(info) == "table" and info.ip or {}
    end
  end
  if route then
    for _, probe in ipairs({ "192.0.2.1", "100.100.100.100" }) do
      local ip = route(probe)
      if ip then add(ip) end
    end
  end
  for _, ip in ipairs(names and names() or {}) do add(ip) end
  local out = {}
  for ip, kind in pairs(found) do out[#out + 1] = { ip = ip, kind = kind } end
  return Addresses.sort(out)
end

-- What to check after a dial that got no answer, by the kind of address
-- (design A2.6): a VPN address gets VPN advice, a home address the same
-- network and the firewall, a public one port forwarding.
function Addresses.checklist(kind, port)
  port = port or 24680
  if kind == "vpn" then
    return {
      "Is the VPN on, on both devices?",
      "Are both in the same VPN network?",
      "Is the host still hosting?",
    }
  elseif kind == "home" then
    return {
      "Are both on the same Wi-Fi or network?",
      ("Does the host's firewall let UDP %d in?"):format(port),
      "Is the host still hosting?",
    }
  elseif kind == "public" then
    return {
      ("Does the host's router forward UDP %d to the host?"):format(port),
      "Is the address the host's current one?",
      "Is the host still hosting?",
    }
  elseif kind == "here" then
    return { "Is a game on this device hosting?" }
  end
  return {
    "Is the address spelled right?",
    "Is the host still hosting?",
  }
end

return Addresses
