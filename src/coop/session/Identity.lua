-- What a device remembers between co-op sessions (#10, design A1.9): its
-- own random id, and per host address and local seat, the player it was in
-- each of that host's campaigns.  A split-screen device has two seats, so
-- two remembered players per campaign.  The hello carries the seat's map
-- ({ [campaign id] = player id }); the host looks up its own campaign.
-- A seat keeps the newest Protocol.MAX_KNOWN campaigns (#15): the hello's
-- map may not hold more, and the development entry hosts a new campaign on
-- every boot.
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
  local self = setmetatable({ store = store, hosts = {}, order = {} }, Identity)
  local text = store and store.read() or nil
  local ok, data = pcall(Json.decode, type(text) == "string" and text or "null")
  if not ok then data = nil end
  if type(data) == "table" then
    if Protocol.deviceId(data.device) then self.device = data.device end
    local recent = type(data.recent) == "table" and data.recent or {}
    if type(data.hosts) == "table" then
      for host, seats in pairs(data.hosts) do
        if type(host) == "string" and type(seats) == "table" then
          for seatKey, map in pairs(seats) do
            local seat = tonumber(seatKey)
            if (seat == 1 or seat == 2) and type(map) == "table" then
              -- oldest first: the saved order, then any campaign it lacks
              local order = type(recent[host]) == "table" and recent[host][seatKey] or nil
              local listed = {}
              for _, campaign in ipairs(type(order) == "table" and order or {}) do
                if map[campaign] ~= nil and not listed[campaign] then
                  listed[campaign] = true
                  self:_put(host, seat, { [campaign] = map[campaign] })
                end
              end
              local rest = {}
              for campaign in pairs(map) do
                if not listed[campaign] then rest[#rest + 1] = campaign end
              end
              table.sort(rest, function(a, b) return tostring(a) < tostring(b) end)
              for _, campaign in ipairs(rest) do
                self:_put(host, seat, { [campaign] = map[campaign] })
              end
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

-- one campaign (or a few, in no order) becomes the seat's newest; past
-- MAX_KNOWN the oldest gives way
function Identity:_put(host, seat, map)
  if type(map) ~= "table" then return end
  for campaign, player in pairs(map) do
    if Protocol.campaignId(campaign) and Protocol.playerId(player) then
      self.hosts[host] = self.hosts[host] or {}
      self.hosts[host][seat] = self.hosts[host][seat] or {}
      self.order[host] = self.order[host] or {}
      self.order[host][seat] = self.order[host][seat] or {}
      local known, order = self.hosts[host][seat], self.order[host][seat]
      for i = #order, 1, -1 do
        if order[i] == campaign then table.remove(order, i) end
      end
      order[#order + 1] = campaign
      known[campaign] = player
      while #order > Protocol.MAX_KNOWN do
        known[table.remove(order, 1)] = nil
      end
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
  local hosts, recent = {}, {}
  for host, seats in pairs(self.hosts) do
    hosts[host], recent[host] = {}, {}
    for seat, map in pairs(seats) do
      hosts[host][tostring(seat)] = map
      recent[host][tostring(seat)] = self.order[host] and self.order[host][seat] or {}
    end
  end
  self.store.write(Json.encode({ device = self.device, hosts = hosts, recent = recent }))
end

return Identity
