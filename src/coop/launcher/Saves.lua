-- The SAVES page (#6) of one game, as a model with no love.* calls: the
-- game's save slots with trainer, badges, Pokédex and play time (what the
-- cartridge's own continue screen shows), the active one and a campaign's
-- marked; PLAY (the slot becomes the active one and the game boots to
-- continue), NEW SAVE, DELETE after a question, IMPORT .SAV (a file in the
-- cartridge's format, typed, pasted or dropped) and EXPORT per slot.  The
-- slots are upstream's (GPL SaveData), the codec upstream's SaveFileIO and
-- SaveConvert, so a .sav from a cartridge or an emulator comes and goes
-- the way it does in the game's own importer.
--
-- Screens: "list", "delete" (the question), "import" (a path to type or
-- a file to drop), "confirm" (an oversized .sav).
-- Actions as Menu's; a press may return { kind = "boot", version, newGame =
-- false } or { kind = "saves_exit" }.
--
-- env:
--   version          the game
--   saves            SaveData's slot calls (default: SaveData)
--   importSav(bytes, version, force)   (default: SaveFileIO.importToSlot)
--   exportSlot(version, slotId) -> ok, pathOrErr, note (default: Saves.exportSlot)
--   campaignOf(slotId) -> a campaign's title when the slot is its, or nil
--   canType          the import screen takes a typed path (default true)

local Text = require("src.coop.launcher.Text")
local L = Text.get

local Saves = {}
Saves.__index = Saves

Saves.SAV_SIZE = 32768

local function SaveData() return require("src.core.SaveData") end

-- any slot's .sav: the slot is made active for upstream's export (which
-- takes the active one, migrations included) and the active slot put back
function Saves.exportSlot(version, slotId)
  local SD = SaveData()
  local SaveFileIO = require("src.import.SaveFileIO")
  local before = SD.activeSlot(version)
  if before ~= slotId then
    local ok = SD.setActiveSlot(version, slotId)
    if not ok then return false, L("This slot cannot be exported.") end
  end
  local ok, pathOrErr, note = SaveFileIO.exportActiveSlot(version)
  if before ~= slotId then pcall(SD.setActiveSlot, version, before) end
  return ok, pathOrErr, note
end

function Saves.new(env)
  env = env or {}
  local self = setmetatable({
    env = env, version = env.version, screen = "list", cursor = 1, path = "",
    saves = env.saves or SaveData(),
    importSav = env.importSav or function(...) return require("src.import.SaveFileIO").importToSlot(...) end,
    exportSlot = env.exportSlot or Saves.exportSlot,
    campaignOf = env.campaignOf or function() return nil end,
    canType = env.canType ~= false,
  }, Saves)
  return self
end

-- the slots: { id, exists, name, badges, dex, time, active, campaign }
function Saves:details()
  local okL, list = pcall(self.saves.listSlots, self.version)
  local okA, active = pcall(self.saves.activeSlot, self.version)
  local slots = {}
  for _, s in ipairs(okL and type(list) == "table" and list or {}) do
    local meta = s.meta or {}
    slots[#slots + 1] = {
      id = s.id, exists = s.exists == true, name = s.exists and (s.name or s.label) or nil,
      label = s.label, badges = meta.badges or 0, dex = meta.dexCount or 0,
      time = meta.timeText or "0:00", active = okA and s.id == active,
      campaign = self.campaignOf(s.id),
    }
  end
  return { slots = slots, version = self.version }
end

function Saves:items()
  local rows = {}
  local function add(row) rows[#rows + 1] = row end
  local s = self.screen
  if s == "list" then
    for _, slot in ipairs(self:details().slots) do
      -- a campaign's slot is entered from its campaign, not here
      if not slot.campaign then add({ id = "play", slot = slot.id, label = L("PLAY →") }) end
      -- a campaign's world (its 40-row bag) never goes to a cartridge save (#16, A6.8)
      add({ id = "export", slot = slot.id, label = L("EXPORT"),
            enabled = slot.exists and not slot.campaign })
      add({ id = "delete", slot = slot.id, label = L("DELETE") })
    end
    add({ id = "new", label = L("+ NEW SAVE") })
    add({ id = "import", label = L("IMPORT .SAV") })
  elseif s == "delete" then
    add({ id = "confirm", label = L("DELETE") })
    add({ id = "cancel", label = L("CANCEL") })
  elseif s == "confirm" then
    add({ id = "confirm", label = L("IMPORT") })
    add({ id = "cancel", label = L("CANCEL") })
  end
  return rows
end

-- the question on the delete and confirm screens
function Saves:prompt()
  if self.screen == "delete" and self.pending then
    local slot = self.pending
    local what = slot.name or (slot.label and slot.label ~= "" and slot.label) or L("this empty slot")
    return L("Delete %s? The save is removed from this device for good.", what)
  elseif self.screen == "confirm" and self.pending then
    return L("%s is %d bytes; a cartridge save is %d. Import the first %d bytes?",
      self.pending.name, self.pending.size, Saves.SAV_SIZE, Saves.SAV_SIZE)
  end
  return nil
end

function Saves:notify(text) self.notice = text end

function Saves:typing() return self.screen == "import" and self.canType and not self.notice end

function Saves:go(screen)
  self.screen, self.cursor = screen, 1
end

local function move(self, delta)
  local rows = self:items()
  if #rows == 0 then return end
  for _ = 1, #rows do
    self.cursor = (self.cursor - 1 + delta) % #rows + 1
    if rows[self.cursor].enabled ~= false then break end
  end
end

local function slotOf(self, id)
  for _, slot in ipairs(self:details().slots) do
    if slot.id == id then return slot end
  end
  return nil
end

local function slotWord(slot)
  return slot.name or slot.label or slot.id
end

-- what the game applies: the slot becomes the active one, the game boots
local function boot(self, slotId)
  local ok = pcall(self.saves.setActiveSlot, self.version, slotId)
  if not ok then return nil end
  return { kind = "boot", version = self.version, newGame = false }
end

function Saves:press(action)
  if self.notice then
    if action == "a" or action == "b" or action == "start" then self.notice = nil end
    return nil
  end
  local s = self.screen
  if s == "import" then
    if action == "b" then self:go("list") return nil end
    if (action == "a" or action == "start") and self.path ~= "" then
      return { kind = "import_sav", path = self.path }
    end
    return nil
  end
  if action == "up" or action == "left" then move(self, -1) return nil end
  if action == "down" or action == "right" then move(self, 1) return nil end
  if action == "b" then
    if s == "list" then return { kind = "saves_exit" } end
    self.pending = nil
    self:go("list")
    return nil
  end
  if action ~= "a" and action ~= "start" then return nil end
  local row = self:items()[self.cursor]
  if not row or row.enabled == false then return nil end
  local id = row.id
  if s == "list" then
    if id == "play" then
      return boot(self, row.slot)
    elseif id == "new" then
      local okC, slotId = pcall(self.saves.createSlot, self.version)
      if not okC or not slotId then
        self:notify(L("This game has no room for another save."))
        return nil
      end
      return boot(self, slotId)
    elseif id == "delete" then
      self.pending = slotOf(self, row.slot)
      if self.pending then self:go("delete") end
    elseif id == "export" then
      local slot = slotOf(self, row.slot)
      local ok, pathOrErr, note = self.exportSlot(self.version, row.slot)
      if ok then
        self:notify(L("Exported %s to %s", slot and slotWord(slot) or row.slot, tostring(pathOrErr))
          .. (note and ("\n" .. tostring(note)) or ""))
      else
        self:notify(L("Could not export: %s", tostring(pathOrErr)))
      end
    elseif id == "import" then
      self.path = ""
      self:go("import")
    end
  elseif s == "delete" then
    local slot = self.pending
    self.pending = nil
    self:go("list")
    if id == "confirm" and slot then
      local ok, err = self.saves.deleteSlot(self.version, slot.id)
      if ok then
        self:notify(L("Deleted %s.", slotWord(slot)))
      else
        self:notify(L("Could not delete: %s", tostring(err)))
      end
    end
  elseif s == "confirm" then
    local pending = self.pending
    self.pending = nil
    self:go("list")
    if id == "confirm" and pending then self:_import(pending.bytes, pending.name, true) end
  end
  return nil
end

-- bytes of any length as the source SaveFileIO reads (a file-like table;
-- a bare string of another size would be taken for a path)
local function fileOf(bytes)
  return {
    open = function() return true end,
    getSize = function() return #bytes end,
    read = function() return bytes end,
    close = function() end,
  }
end

function Saves:_import(bytes, name, force)
  local ok, slotOrErr, extra = self.importSav(fileOf(bytes), self.version, force)
  if ok then
    self:go("list")
    local slot = slotOf(self, slotOrErr)
    self:notify(L("Imported %s into a new save slot.", slot and slotWord(slot) or name)
      .. (extra and extra.note and ("\n" .. tostring(extra.note)) or ""))
    return true
  end
  if extra and extra.needsConfirm then
    self.pending = { bytes = bytes, name = name, size = extra.size or #bytes }
    self:go("confirm")
    return true
  end
  self:notify(L("Could not import %s: %s", name, tostring(slotOrErr)))
  return true
end

-- The bytes of a file typed, pasted or dropped on the import screen (or
-- anywhere, for a file that is a cartridge save).  Always answers: an
-- import, a question or a reason.
function Saves:importData(bytes, name)
  if type(bytes) ~= "string" then return false end
  name = name or "the file"
  return self:_import(bytes, name, false)
end

-- a file is a cartridge save by its name or size
function Saves.looksLikeSav(bytes, name)
  if type(name) == "string" and name:lower():match("%.sav$") then return true end
  return type(bytes) == "string" and (#bytes == Saves.SAV_SIZE or #bytes == Saves.SAV_SIZE + 18)
end

function Saves:text(t)
  if not self:typing() then return end
  self.path = self.path .. t
end

function Saves:erase()
  if self.screen ~= "import" or self.notice then return end
  self.path = self.path:sub(1, -2)
  while #self.path > 0 and self.path:byte(-1) >= 0x80 and self.path:byte(-1) < 0xC0 do
    self.path = self.path:sub(1, -2)
  end
  if #self.path > 0 and self.path:byte(-1) >= 0xC0 then self.path = self.path:sub(1, -2) end
end

return Saves
