-- What a device remembers between co-op sessions (#10, design A1.9): its
-- own random id, and per host address and local seat, the player it was in
-- each of that host's campaigns.  A split-screen device has two seats, so
-- two remembered players per campaign.  The hello carries the seat's map
-- ({ [campaign id] = player id }); the host looks up its own campaign.
--
--   local id = Identity.load(store)           -- store: read()/write(text)
--   id.device                                 -- "3f9c…"
--   local known = id:known("192.168.1.20:24680", 1)
--   id:remember("192.168.1.20:24680", 1, campaignId, playerId)

local Json = require("src.link.Json")
local Protocol = require("src.coop.session.Protocol")
local Random = require("src.coop.session.Random")

local Identity = {}
Identity.__index = Identity

Identity.FILE = "coop/identity.json"

-- a store on LÖVE's save folder
function Identity.saveFolderStore(path)
  path = path or Identity.FILE
  return {
    read = function()
      if not love.filesystem.getInfo(path) then return nil end
      return love.filesystem.read(path)
    end,
    write = function(text)
      local dir = path:match("^(.*)/[^/]*$")
      if dir then love.filesystem.createDirectory(dir) end
      return love.filesystem.write(path, text)
    end,
  }
end

function Identity.load(store, hex)
  local self = setmetatable({ store = store, hosts = {} }, Identity)
  local text = store and store.read() or nil
  local data = type(text) == "string" and Json.decode(text) or nil
  if type(data) == "table" then
    if Protocol.deviceId(data.device) then self.device = data.device end
    if type(data.hosts) == "table" then
      for host, seats in pairs(data.hosts) do
        if type(host) == "string" and type(seats) == "table" then
          for seatKey, map in pairs(seats) do
            local seat = tonumber(seatKey)
            if seat == 1 or seat == 2 then
              self:_put(host, seat, map)
            end
          end
        end
      end
    end
  end
  if not self.device then
    self.device = (hex or Random.hex)(16)
    self:save()
  end
  return self
end

function Identity:_put(host, seat, map)
  if type(map) ~= "table" then return end
  for campaign, player in pairs(map) do
    if Protocol.campaignId(campaign) and Protocol.playerId(player) then
      self.hosts[host] = self.hosts[host] or {}
      self.hosts[host][seat] = self.hosts[host][seat] or {}
      self.hosts[host][seat][campaign] = player
    end
  end
end

-- the seat's { [campaign] = player } for this host (a copy)
function Identity:known(host, seat)
  local out = {}
  local map = self.hosts[host] and self.hosts[host][seat]
  for k, v in pairs(map or {}) do out[k] = v end
  return out
end

function Identity:remember(host, seat, campaign, player)
  self:_put(host, seat, { [campaign] = player })
  self:save()
end

function Identity:save()
  if not self.store then return end
  local hosts = {}
  for host, seats in pairs(self.hosts) do
    hosts[host] = {}
    for seat, map in pairs(seats) do hosts[host][tostring(seat)] = map end
  end
  self.store.write(Json.encode({ device = self.device, hosts = hosts }))
end

return Identity
