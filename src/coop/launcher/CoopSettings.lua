-- What the launcher remembers on this device (#12, design A2.1, A2.8): the
-- player's name, the last address and the recent ones, the cartridge
-- picked, the last session (for the LAST SESSION row), the log-sharing
-- switch, the save slot each campaign plays in on this device, the
-- launcher's language and colours (#41, #38; nil: the system's language,
-- light colours) and each player's device for couch co-op (#4: the
-- keyboard, or a pad by GUID and order among twins; `false` marks a player
-- without one).  `coop/launcher.json` in the save folder.
--
-- Until the campaign files of #13, a player's progress in a campaign is a
-- save slot of their own device, named after the campaign.  Entering a
-- campaign makes its slot the game's active one and remembers the slot that
-- was active before; the launcher puts that one back when it opens again
-- (restoreSlots), so a solo CONTINUE never lands in a co-op save.

local Json = require("src.link.Json")
local Protocol = require("src.coop.session.Protocol")
local Seats = require("src.coop.game.Seats")

local CoopSettings = {}
CoopSettings.__index = CoopSettings

CoopSettings.FILE = "coop/launcher.json"
CoopSettings.MAX_RECENT = 4
CoopSettings.MAX_ADDRESS = 64

-- the filesystem (love.filesystem's calls); a test passes its own to load()
local function defaultFs() return love.filesystem end

local function address(v)
  if type(v) ~= "string" or #v == 0 or #v > CoopSettings.MAX_ADDRESS then return nil end
  if not v:find("^[%w%.%-:%[%]]+$") then return nil end
  return v
end
CoopSettings.validAddress = address

function CoopSettings.load(fs)
  local f = fs or defaultFs()
  local self = setmetatable({ fs = f, recent = {}, slots = {}, restore = {}, shareLogs = true,
                              seats = {} }, CoopSettings)
  local text = f.getInfo(CoopSettings.FILE) and f.read(CoopSettings.FILE)
  local ok, data = pcall(Json.decode, type(text) == "string" and text or "null")
  if not ok or type(data) ~= "table" then return self end
  if Protocol.name(data.name) then self.name = data.name end
  self.address = address(data.address)
  for _, a in ipairs(type(data.recent) == "table" and data.recent or {}) do
    if address(a) and #self.recent < CoopSettings.MAX_RECENT then
      self.recent[#self.recent + 1] = a
    end
  end
  if data.shareLogs == false then self.shareLogs = false end
  if data.language == "en" or data.language == "de" then self.language = data.language end
  if data.theme == "light" or data.theme == "dark" then self.theme = data.theme end
  if Protocol.gameId(data.pick) then self.pick = data.pick end
  local last = data.last
  if type(last) == "table" and Protocol.gameId(last.version) then
    if last.kind == "host" and Protocol.campaignId(last.campaign) then
      self.last = { kind = "host", campaign = last.campaign, version = last.version }
    elseif last.kind == "join" and address(last.address) then
      self.last = { kind = "join", address = last.address, version = last.version,
                    title = type(last.title) == "string" and last.title:sub(1, 40) or nil }
    end
  end
  for id, s in pairs(type(data.slots) == "table" and data.slots or {}) do
    if Protocol.campaignId(id) and type(s) == "table" and Protocol.gameId(s.version)
        and type(s.slot) == "string" and s.slot:match("^slot%d+$") then
      self.slots[id] = { version = s.version, slot = s.slot }
    end
  end
  for n, d in ipairs(type(data.seats) == "table" and data.seats or {}) do
    if n > Seats.MAX then break end
    local device = Seats.device(d)
    if device or d == false or type(d) == "table" and (d.kind == "pad" or d.kind == "keyboard") then
      self.seats[n] = device or false
    else
      break
    end
  end
  for version, slot in pairs(type(data.restore) == "table" and data.restore or {}) do
    if Protocol.gameId(version) and (slot == false
        or (type(slot) == "string" and slot:match("^slot%d+$"))) then
      self.restore[version] = slot
    end
  end
  return self
end

function CoopSettings:save()
  local f = self.fs
  f.createDirectory("coop")
  return f.write(CoopSettings.FILE, Json.encode({
    name = self.name, address = self.address, recent = self.recent,
    shareLogs = self.shareLogs, pick = self.pick, last = self.last, slots = self.slots,
    restore = self.restore, language = self.language, theme = self.theme,
    seats = self.seats,
  }))
end

-- the cartridge the co-op screens were opened for, preselected next time
function CoopSettings:picked(version)
  if self.pick == version or not Protocol.gameId(version) then return end
  self.pick = version
  self:save()
end

-- a dialled address goes to the front of the recent list
function CoopSettings:dialled(addr)
  if not address(addr) then return end
  self.address = addr
  local recent = { addr }
  for _, a in ipairs(self.recent) do
    if a ~= addr and #recent < CoopSettings.MAX_RECENT then recent[#recent + 1] = a end
  end
  self.recent = recent
end

-- Make the campaign's own save slot active for `version` (created and named
-- after the campaign the first time) and remember the slot that was active
-- before.  `saves` is SaveData's slot calls; returns the slot id.
function CoopSettings:enterSlot(saves, version, campaignId, title)
  local entry = self.slots[campaignId]
  local slot = entry and entry.version == version and entry.slot or nil
  if slot then
    local exists = false
    for _, s in ipairs(saves.listSlots(version) or {}) do
      if s.id == slot then exists = true end
    end
    if not exists then slot = nil end
  end
  if self.restore[version] == nil then
    self.restore[version] = saves.activeSlot(version) or false
  end
  if not slot then
    slot = saves.createSlot(version)
    if not slot then return nil end
    pcall(saves.renameSlot, version, slot, title)
    self.slots[campaignId] = { version = version, slot = slot }
  end
  saves.setActiveSlot(version, slot)
  self:save()
  return slot
end

-- put back the slots that were active before a campaign's slot (the
-- launcher opening again after a session); a game that had none gets a
-- fresh empty slot, so solo play never continues a campaign's save
function CoopSettings:restoreSlots(saves)
  local any = false
  for version, slot in pairs(self.restore) do
    if not slot then
      local ok, id = pcall(saves.createSlot, version)
      slot = ok and id or nil
    end
    if slot then pcall(saves.setActiveSlot, version, slot) end
    self.restore[version] = nil
    any = true
  end
  if any then self:save() end
  return any
end

return CoopSettings
