-- The fork's own launcher (#3, licence term 2 of upstream's LICENSE.MD; laid
-- out anew in #38): picks a cartridge, imports its ROM, plays solo, hosts
-- and joins co-op sessions (CoopMenu.lua, #12) and shows the credit line
-- term 1 asks for on every screen.  A session started here keeps running
-- into the game.
--
-- main.lua drives it through the same calls it makes on any launcher object
-- (update, draw and the input callbacks), so the hooks there stay small.
-- Menu.lua holds the state, Screens.lua lays it out as a page of nodes, and
-- this file paints the page and turns keys, pads, mouse and touch into one
-- focus order over the page's targets.  Text is the bundled Plain Pixel
-- face in the launcher's language (Text.lua, #41); no cartridge graphics.
-- Nothing here loads upstream's launcher files (AGENTS.md lists them).

local GamepadMap = require("src.core.GamepadMap")
local Menu = require("src.coop.launcher.Menu")
local RomImport = require("src.coop.launcher.RomImport")
local CoopSettings = require("src.coop.launcher.CoopSettings")
local Controls = require("src.coop.launcher.Controls")
local GameOptions = require("src.coop.launcher.GameOptions")
local Saves = require("src.coop.launcher.Saves")
local Mods = require("src.coop.launcher.Mods")
local Seats = require("src.coop.game.Seats")
local Screens = require("src.coop.launcher.Screens")
local Text = require("src.coop.launcher.Text")
local Theme = require("src.coop.launcher.Theme")
local Ui = require("src.coop.launcher.Ui")
local Session = require("src.coop.session.Session")
local L = Text.get


-- a typed or pasted path without its quotes, spaces and file:// prefix
local function cleanPath(path)
  path = tostring(path or ""):gsub("^%s+", ""):gsub("%s+$", "")
  path = path:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1"):gsub("^file://", "")
  return path
end
local Launcher = {}
Launcher.__index = Launcher

-- The launcher on screen, for tests and the frame driver.
Launcher.current = nil

-- the launcher's pixels are at least this many to a window, in whole steps
Launcher.MIN_W, Launcher.MIN_H = 480, 400

local STICK_ON = 0.5
local PLAIN_SIZE = 15     -- Plain Pixel's design size: one font pixel a pixel
local BASELINE = 11       -- the baseline inside a 14-pixel text line

local KEYS = {
  up = "up", w = "up", down = "down", s = "down",
  left = "left", a = "left", right = "right", d = "right",
  z = "a", ["return"] = "a", space = "a", kpenter = "start",
  x = "b", backspace = "b", escape = "b",
}

local function mobile()
  local name = love.system and love.system.getOS and love.system.getOS()
  return name == "Android" or name == "iOS"
end

-- co-op (#7): the system's file picker, a native bridge of the vendored
-- love-android (love.system.pickFile; no LÖVE build elsewhere has it).  It
-- copies the picked file into the save folder under a name per kind; a
-- cancel or a failed copy leaves PICK_ERROR ("cancelled:<name>" or <name>).
local function canPick()
  return mobile() and love.system ~= nil and love.system.pickFile ~= nil
end
local PICK_KIND = { rom = "rom", sav = "sav", mod = "mod", mod_file = "required_import" }
local PICKED = {
  { what = "rom", file = "picked_rom.gb" },
  { what = "sav", file = "picked_save.sav" },
  { what = "mod", file = "picked_mod.zip" },
  { what = "mod_file", file = "picked_required_import.bin" },
}
local PICK_ERROR = "pick_error.flag"
-- the system's save-as screen (love.system.createFile, same bridge) copies
-- PENDING_EXPORT where the player picks and leaves EXPORT_DONE
local PENDING_EXPORT, EXPORT_DONE = "pending_export.sav", "export_done.flag"
-- a finger that moves this far (launcher pixels) drags the page, no tap
local TOUCH_SLOP = 6

function Launcher.new(onBoot, opts)
  opts = opts or {}
  -- a split-screen second player ends with the game it played beside (#11)
  require("src.coop.split.Split").stop()
  local self = setmetatable({
    onBoot = onBoot, bootOnImport = opts.bootOnImport == true,
    onEditSave = opts.onEditSave,
    onTouchControls = opts.onTouchControls,
    readyCache = {}, saveCache = {}, clock = 0, axis = {},
    ui = { scroll = 0 }, device = mobile() and "touch" or "keys",
  }, Launcher)
  local settings = self:_coopSettings()
  -- the launcher's language: the setting, else the system's (#41)
  Text.set(settings.language or Text.systemLanguage())
  local initial = opts.initialTab
  if not RomImport.isGen1(initial) then initial = nil end
  if not initial and RomImport.isGen1(settings.pick) then initial = settings.pick end
  local canOpenLogs = not mobile() and love.system ~= nil and love.system.openURL ~= nil
  -- the CONTROLS page (#4): rebinds go where the game reads them
  -- (options.bindings, GPL SaveData), the players' devices into the
  -- launcher's own settings
  Seats.load(settings)
  self.controls = Controls.new({
    bindings = function()
      local ok, options = pcall(require("src.core.SaveData").loadOptions)
      return ok and type(options) == "table" and options.bindings or {}
    end,
    saveBindings = function(overlay)
      pcall(require("src.core.SaveData").saveOptions, { bindings = overlay })
    end,
    settings = settings,
    pads = function() return self:pads() end,
  })
  self.menu = Menu.new({
    ready = function(v) return self:isReady(v) end,
    saveInfo = function(v) return self:saveInfo(v) end,
    canQuit = not mobile(),
    canType = not mobile(),
    canPick = canPick(),
    touchControls = mobile() and opts.onTouchControls ~= nil,
    canOpenLogs = canOpenLogs,
    initial = initial,
    settings = settings,
    campaigns = require("src.coop.Campaigns"),
    coop = function(v) return self:_coopEnv(v) end,
    controls = self.controls,
    -- the game's options on SETTINGS (#5), in options.lua where the game reads them
    gameOptions = GameOptions.new({ fixedDisplay = require("src.core.VideoMode").fixedDisplay() }),
    saves = function(v) return Saves.new(self:_savesEnv(v)) end,
    -- the MODS page (#30), on the GPL mod modules (src/coop/mods/Installed.lua)
    mods = function(v) return Mods.new({ version = v, canType = not mobile(), canPick = canPick() }) end,
  })
  self:_coopReturn()
  if opts.notice then self.menu:notify(opts.notice) end
  self:_loadFont()
  Launcher.current = self
  return self
end

-- ------------------------------------------------------------ co-op (#12)

function Launcher:_coopSettings()
  if not self.coopSettings then
    local ok, settings = pcall(CoopSettings.load)
    self.coopSettings = ok and settings or CoopSettings.load({
      getInfo = function() return nil end, read = function() return nil end,
      write = function() return false end, createDirectory = function() end,
    })
  end
  return self.coopSettings
end

-- After a session: the solo save slots come back, and PLAY says why the
-- session ended.
function Launcher:_coopReturn()
  if Session.current then return end
  local settings = self:_coopSettings()
  pcall(settings.restoreSlots, settings, require("src.core.SaveData"))
  local note = Session.takeReturn()
  if note then
    local version = note.version
    if version and RomImport.isGen1(version) then self.menu:select(version) end
    local reason = tostring(note.notice):match("^The host turned this game away %((.-)%)%.$")
    self.menu:notify(reason and L("The host turned this game away (%s).", reason)
      or L(note.notice))
  end
end

-- The player's world from the campaign into the campaign's slot (#13).  A
-- player the campaign has no world for keeps what the slot holds: a new
-- game, or this device's progress from before campaign files, which goes to
-- the host with the first save.  Such a player who chose how they start
-- (#57, `start`) gets that world instead: in Pallet Town, or a solo save
-- brought along; a returning player always gets the campaign's (A4.3).
function Launcher:_coopWorld(SaveData, version, slot, start)
  local s = Session.current
  if not (s and slot and s.takeWorld) then return end
  local save = s:takeWorld()
  if save == nil and start then
    local why
    save, why = self:_startWorld(SaveData, version, start, s)
    if not save then
      self.menu:notify(L("Your start could not be made: %s", tostring(why)))
      return
    end
  end
  if save == false then
    self.menu:notify(L("Your world from the campaign could not be read."))
  elseif save then
    local ok, err = SaveData.writeSlot(version, slot, save)
    if not ok then self.menu:notify(L("Your world could not be written: %s", tostring(err))) end
  end
end

-- the world a new player starts with (#57): in Pallet Town with their
-- starter, or a solo save of this device; nil and why
function Launcher:_startWorld(SaveData, version, start, s)
  return require("src.coop.campaign.Start").make(SaveData, version, start, s)
end

-- This device's single-player saves of `version` for BRING A SAVE (#57):
-- every slot that holds a save and is no campaign's, as the SAVES page
-- lists them, and whether it is past Oak's lab
function Launcher:_soloSaves(version)
  local SaveData = require("src.core.SaveData")
  local Start = require("src.coop.campaign.Start")
  local details = Saves.new(self:_savesEnv(version)):details()
  local out = {}
  for _, slot in ipairs(details.slots) do
    if slot.exists and not slot.campaign then
      local text = SaveData.readSlotSource(version, slot.id)
      local ok, save = pcall(SaveData.decode, text or "")
      out[#out + 1] = { id = slot.id, name = slot.name or slot.label or slot.id,
                        badges = slot.badges, dex = slot.dex, time = slot.time,
                        bringable = ok and Start.bringable(save) or false }
    end
  end
  return out
end

-- what the co-op screens reach: this device's settings and campaigns, the
-- session, the LAN beacon and this device's addresses
function Launcher:_coopEnv(version)
  local settings = self:_coopSettings()
  local Campaigns = require("src.coop.Campaigns")
  local launcher = self
  return {
    version = version,
    ready = function(v) return launcher:isReady(v) end,
    settings = settings,
    campaigns = Campaigns,
    addresses = function() return require("src.coop.session.Addresses").mine() end,
    splitReady = function() return Seats.complete(2) end,
    -- this device's player 2 is one of that host's campaign's (#64)
    seat2Known = function(address, campaign)
      local s = Session.current
      local id = s and s.identity
      if not (id and address and campaign) then return false end
      local known = id:known(address, 2)
      return type(known) == "table" and known[campaign] ~= nil
    end,
    soloSaves = function(v) return launcher:_soloSaves(v) end,
    nearby = function()
      if not launcher.nearby and not launcher.nearbyError then
        local listener, why = require("src.coop.session.Beacon").listener()
        launcher.nearby, launcher.nearbyError = listener, why
      end
      return launcher.nearby, launcher.nearbyError
    end,
    closeNearby = function()
      if launcher.nearby then launcher.nearby:close() end
      launcher.nearby, launcher.nearbyError = nil, nil
    end,
    host = function(campaign, name, v, start)
      return Session.startHost({
        campaign = campaign, cartridge = Session.cartridge(v), name = name,
        start = start, -- how the host's own player starts (#66)
        shareLogs = settings.shareLogs,
        onRoster = function(roster) Campaigns.record(campaign.id, roster) end,
      })
    end,
    dial = function(address, v, name)
      return Session.startDial({ address = address, cartridge = Session.cartridge(v),
                                 name = name, shareLogs = settings.shareLogs })
    end,
  }
end

function Launcher:_openLogs()
  local fs = love.filesystem
  fs.createDirectory("coop/logs")
  local dir = fs.getSaveDirectory() .. "/coop/logs"
  if not love.system.openURL("file://" .. dir) then
    self.menu:notify(L("The logs are in %s", dir))
  end
end

-- the pads connected now, as Seats.describe entries (#4)
local function joysticks()
  local js = love.joystick
  if not (js and js.getJoysticks) then return {} end
  local ok, list = pcall(js.getJoysticks)
  return ok and type(list) == "table" and list or {}
end

function Launcher:pads()
  local out = {}
  local list = joysticks()
  for _, j in ipairs(list) do
    if not GamepadMap.isAccelerometer(j) then
      local d = Seats.describe(j, list)
      if d then out[#out + 1] = d end
    end
  end
  return out
end

-- a raw press while the CONTROLS page captures one (#4); true when it took it
function Launcher:_capture(ev)
  local menu = self.menu
  if not menu:capturing() then return false end
  menu:captured(ev)
  return true
end

-- the SAVES page's env (#6): upstream's slots and codec, a campaign's
-- slot named after its campaign
function Launcher:_savesEnv(version)
  local settings = self:_coopSettings()
  return {
    version = version,
    canType = not mobile(),
    canPick = canPick(),
    canEdit = self.onEditSave ~= nil,
    campaignOf = function(slotId)
      for id, entry in pairs(settings.slots or {}) do
        if entry.version == version and (entry.slot == slotId or entry.slot2 == slotId) then
          local card = require("src.coop.Campaigns").get(id)
          return card and card.title or L("a campaign")
        end
      end
      return nil
    end,
  }
end

function Launcher:isReady(version)
  local hit = self.readyCache[version]
  if hit == nil then
    hit = RomImport.isReady(version) and true or false
    self.readyCache[version] = hit
  end
  return hit
end

-- The active save slot's summary, or nil when it holds no save.
function Launcher:saveInfo(version)
  local hit = self.saveCache[version]
  if hit == nil then
    hit = false
    local SaveData = require("src.core.SaveData")
    local okSlots, slots = pcall(SaveData.listSlots, version)
    local okActive, active = pcall(SaveData.activeSlot, version)
    if okSlots and type(slots) == "table" then
      for _, slot in ipairs(slots) do
        if slot.exists and (slot.id == (okActive and active) or #slots == 1) then
          local meta = slot.meta or {}
          hit = { name = slot.name or "", badges = meta.badges or 0,
                  time = meta.timeText or "0:00" }
        end
      end
    end
    self.saveCache[version] = hit
  end
  return hit or nil
end

function Launcher:_loadFont()
  if self.font then return end
  local Font = require("src.render.Font")
  local ok, font = pcall(love.graphics.newFont, Font.PLAINPIXEL, PLAIN_SIZE, "mono", 1)
  if ok and font then
    if font.setFilter then font:setFilter("nearest", "nearest") end
    self.font = font
  end
end

-- ------------------------------------------------------------ commands

function Launcher:_run(command)
  if not command then return end
  if command.kind == "quit" then
    love.event.quit()
  elseif command.kind == "import" then
    self:startPath(command.path)
  elseif command.kind == "import_sav" then
    -- a typed path on the SAVES page (#6)
    local path = tostring(command.path or ""):gsub("^%s+", ""):gsub("%s+$", "")
    path = path:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1"):gsub("^file://", "")
    local file = require("src.core.SaveData").openNative(path, "rb")
    if not file then
      self.menu:notify(L("Could not open %s", path))
    else
      local data = file:read("*a")
      file:close()
      if self.menu.saves then self.menu.saves:importData(data, path:match("[^/\\]+$") or path) end
      self.saveCache = {}
    end
  elseif command.kind == "install_mod" then
    -- a typed .zip path on the MODS page (#30)
    local path = cleanPath(command.path)
    local file = require("src.core.SaveData").openNative(path, "rb")
    if not file then
      self.menu:notify(L("Could not open %s", path))
    else
      local data = file:read("*a")
      file:close()
      self:_installModZip(data, path:match("[^/\\]+$") or path)
    end
  elseif command.kind == "mod_import" then
    local path = cleanPath(command.path)
    local file = require("src.core.SaveData").openNative(path, "rb")
    if not file then
      self.menu:notify(L("Could not open %s", path))
    else
      local data = file:read("*a")
      file:close()
      self:_importModFile(data, path:match("[^/\\]+$") or path)
    end
  elseif command.kind == "pick" then
    -- a phone's file picker (#7); the copy is taken up in _pollPicked
    local ok, opened = pcall(love.system.pickFile, PICK_KIND[command.what])
    if ok and opened then
      self.picking = command.what
    else
      self.menu:notify(L("The file picker could not be opened."))
    end
  elseif command.kind == "touch_layout" or command.kind == "touch_skin" then
    -- co-op (#7): main.lua parks this launcher while the editor or studio
    -- runs and hands it back on their close
    self.onTouchControls(command.kind == "touch_skin" and "skin" or "layout", command.version)
  elseif command.kind == "export_sav" then
    self:_exportSav(command)
  elseif command.kind == "boot" then
    if command.newGame then
      -- a new game gets its own slot; the old save stays on disk
      local SaveData = require("src.core.SaveData")
      local id = SaveData.createSlot(command.version)
      if id then SaveData.setActiveSlot(command.version, id) end
    end
    self:_boot(command.version)
  elseif command.kind == "coop_enter" then
    -- the campaign's own save slot on this device, the scratch area the game
    -- plays and saves in; it holds the player's world from the host's
    -- campaign file (#13, design A3.14), and solo saves stay untouched
    local SaveData = require("src.core.SaveData")
    local slot = self:_coopSettings():enterSlot(SaveData, command.version, command.campaign.id,
      command.campaign.title)
    self:_coopWorld(SaveData, command.version, slot, command.start)
    if self.nearby then self.nearby:close() end
    self.nearby = nil
    -- two players on this device (#11): the second joins once the game runs
    if command.split then
      require("src.coop.split.Split").request({ settings = self:_coopSettings(),
                                                start = command.start2 }) -- #64
    end
    self:_boot(command.version)
  elseif command.kind == "edit_save" then
    -- the save editor (#27): main.lua's openEditor parks this launcher while
    -- it runs and hands it back on Close (savesChanged); a refusal is left
    -- in saveNotice, upstream's field for it
    self.saveNotice = nil
    self.onEditSave(command.version, command.slot)
    local refused = self.saveNotice and self.saveNotice[command.version]
    self.saveNotice = nil
    if refused then
      self.menu:notify(L("Could not open the save editor: %s", tostring(refused.text)))
    end
  elseif command.kind == "copy" then
    if love.system.setClipboardText then love.system.setClipboardText(command.text) end
  elseif command.kind == "open_logs" then
    self:_openLogs()
  end
end

-- main.lua's closeEditor: the editor may have changed what CONTINUE shows
function Launcher:savesChanged()
  self.saveCache = {}
end

-- ------------------------------------------------------------ mods (#30)

local INSTALL_MOUNT = "coop_mod_install"
local INSTALL_ARCHIVE = "coop_mod_install.zip"

-- install the mod in a mounted tree, then unmount it
function Launcher:_installMounted(source, name)
  local Installed = require("src.coop.mods.Installed")
  local manifest, err = Installed.install(Installed.mountedTree(INSTALL_MOUNT))
  pcall(love.filesystem.unmount, source)
  local mods = self.menu.mods
  local text = manifest and L("Installed %s %s. It runs when the game starts.",
      manifest.name or manifest.id, manifest.version or "")
    or L("Could not install %s: %s", name, tostring(err))
  if mods then mods:done(manifest ~= nil, text) else self.menu:notify(text) end
end

-- a mod's .zip (dropped, or a typed path): mounted from memory, copied
-- into the save folder's mods/
function Launcher:_installModZip(data, name)
  local ok, fileData = pcall(love.filesystem.newFileData, data, INSTALL_ARCHIVE)
  local okM, mounted = false, false
  if ok and fileData then
    okM, mounted = pcall(love.filesystem.mount, fileData, INSTALL_ARCHIVE, INSTALL_MOUNT)
  end
  if not (okM and mounted and love.filesystem.getInfo(INSTALL_MOUNT)) then
    pcall(love.filesystem.unmount, INSTALL_ARCHIVE)
    return self.menu:notify(L("Could not install %s: %s", name or "?", L("it is not a .zip this build opens")))
  end
  self:_installMounted(INSTALL_ARCHIVE, name)
end

-- a mod's folder, dropped on the window
function Launcher:directorydropped(path)
  if self.menu.screen ~= "mods" or not self.menu.mods then
    return self.menu:notify(L("To install a mod, open SETTINGS > MODS and drop it there."))
  end
  local ok = pcall(love.filesystem.mount, path, INSTALL_MOUNT)
  if not (ok and love.filesystem.getInfo(INSTALL_MOUNT)) then
    return self.menu:notify(L("Could not open %s", tostring(path)))
  end
  self:_installMounted(path, tostring(path):match("[^/\\]+$") or path)
end

-- the file a mod asks for (its optional import), checked and stored
function Launcher:_importModFile(data, name)
  local mods = self.menu.mods
  local m, imp = mods and mods:pendingImport()
  if not m then return end
  local ok, err = require("src.coop.mods.Installed").importOptional(m.id, imp.id, data)
  mods:done(ok == true, ok and L("Imported %s for %s.", imp.name, m.name)
    or L("Could not import %s: %s", name or imp.name, tostring(err)))
end

function Launcher:_boot(version)
  if Launcher.current == self then Launcher.current = nil end
  self.booted = version
  if self.onBoot then self.onBoot(version) end
end

-- ------------------------------------------------------------ import

function Launcher:importData(data, name)
  if self.job then return end
  -- on the MODS page (#30) a dropped file is a mod's .zip, or the file the
  -- mod asks for on its import screen
  local mods = self.menu.screen == "mods" and self.menu.mods
  if mods then
    if mods.screen == "import" then return self:_importModFile(data, name) end
    return self:_installModZip(data, name)
  end
  -- a cartridge save goes to the SAVES page of the picked game (#6)
  if Saves.looksLikeSav(data, name) then return self:_importSav(data, name) end
  return self:_importRom(data, name)
end

function Launcher:_importSav(data, name)
  if self.menu.savesOf then
    local menu = self.menu
    if menu.screen ~= "saves" then
      if not self:isReady(menu.version) then
        return menu:notify(L("Import the %s ROM before its saves.", Menu.gameLabel(menu.version)))
      end
      menu:openSaves(menu.version)
    end
    if menu.saves then menu.saves:importData(data, name) end
    self.saveCache = {}
    return
  end
  return self:_importRom(data, name)
end

function Launcher:_importRom(data, name)
  local version, bytes, label, hash = RomImport.identify(data, name)
  if not version then
    self.menu:notify(bytes)
    return
  end
  self.job = RomImport.start(version, bytes, label, hash)
  self.menu:importStarted(version, label)
  self:_pollJob()
end

-- co-op (#7): the copy a phone's file picker left in the save folder, also
-- one from before a restart (the system may close the app while its picker
-- is open).  Checked each frame while a pick is open, else once a second.
function Launcher:_pollPicked()
  if not canPick() or self.job then return end
  if not self.picking and self.clock < (self.nextPickPoll or 0) then return end
  self.nextPickPoll = self.clock + 1
  local fs = love.filesystem
  local flag = fs.getInfo(PICK_ERROR) and fs.read(PICK_ERROR)
  if flag then
    fs.remove(PICK_ERROR)
    self.picking = nil
    if not tostring(flag):find("^cancelled:") then
      self.menu:notify(L("The chosen file could not be copied to this device."))
    end
    return
  end
  for _, pick in ipairs(PICKED) do
    if fs.getInfo(pick.file) then
      local data = fs.read(pick.file)
      fs.remove(pick.file)
      self.picking = nil
      if type(data) ~= "string" then
        return self.menu:notify(L("The chosen file could not be read."))
      end
      local name = L("the chosen file")
      if pick.what == "rom" then return self:_importRom(data, name) end
      if pick.what == "sav" then
        if self.menu.screen == "saves" and self.menu.saves then
          self.menu.saves:importData(data, name)
          self.saveCache = {}
          return
        end
        return self:_importSav(data, name)
      end
      if pick.what == "mod" then return self:_installModZip(data, name) end
      return self:_importModFile(data, name)
    end
  end
end

-- co-op (#7): an exported .sav on a phone goes where the player picks; the
-- app's own folder is out of reach of the phone's file manager
function Launcher:_exportSav(command)
  local saves = self.menu.saves
  local function said(text)
    if saves then saves:notify(text) else self.menu:notify(text) end
  end
  local exported = L("Exported %s to %s", command.name, command.path)
    .. (command.note and ("\n" .. tostring(command.note)) or "")
  local fs = love.filesystem
  local base = fs.getSaveDirectory and fs.getSaveDirectory() or ""
  local rel = command.path
  if base ~= "" and rel:sub(1, #base + 1) == base .. "/" then rel = rel:sub(#base + 2) end
  local data = love.system.createFile and fs.read(rel)
  if type(data) ~= "string" or not fs.write(PENDING_EXPORT, data) then return said(exported) end
  fs.remove(EXPORT_DONE)
  local ok, opened = pcall(love.system.createFile, rel:match("[^/]+$"))
  if not (ok and opened) then return said(exported) end
  self.exporting = { name = command.name, note = command.note }
end

function Launcher:_pollExport()
  if not self.exporting then return end
  local fs = love.filesystem
  if not fs.getInfo(EXPORT_DONE) then return end
  fs.remove(EXPORT_DONE)
  fs.remove(PENDING_EXPORT)
  local e = self.exporting
  self.exporting = nil
  local text = L("Exported %s.", e.name) .. (e.note and ("\n" .. tostring(e.note)) or "")
  if self.menu.saves then self.menu.saves:notify(text) else self.menu:notify(text) end
end

function Launcher:startPath(path)
  path = tostring(path or ""):gsub("^%s+", ""):gsub("%s+$", "")
  path = path:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
  path = path:gsub("^file://", "")
  local file = require("src.core.SaveData").openNative(path, "rb")
  if not file then
    self.menu:notify(L("Could not open %s", path))
    return
  end
  local data = file:read("*a")
  file:close()
  self:importData(data, path:match("[^/\\]+$") or path)
end

function Launcher:_pollJob()
  local job = self.job
  if not job then return end
  local state = job:update()
  self.menu:importProgress(job.progress, job.stage)
  if state == "working" then return end
  self.job = nil
  self.readyCache = {}
  self.saveCache = {}
  if state == "failed" then
    self.menu:importFailed(L("Import failed: %s", tostring(job.error)))
    -- A scripted import-only run has nobody to read the menu.
    if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then
      io.stderr:write("Import failed: " .. tostring(job.error) .. "\n")
      love.event.quit(1)
    end
    return
  end
  if self.bootOnImport then return self:_boot(job.version) end
  self.menu:importDone(job.version)
end

-- ------------------------------------------------------------ frame

function Launcher:update(dt)
  self.swallowText = false
  self.clock = self.clock + (dt or 0)
  self.menu.clock = self.clock
  self:_pollJob()
  self:_pollPicked()
  self:_pollExport()
  -- co-op (#12): the session runs while the launcher shows it
  Session.tick(dt, nil)
  self:_run(self.menu:update(dt))
end

-- launcher pixels per screen pixel (whole steps) and the launcher's size
function Launcher:_layout()
  local w, h = love.graphics.getDimensions()
  local scale = math.max(1, math.floor(math.min(w / Launcher.MIN_W, h / Launcher.MIN_H)))
  local lw, lh = math.floor(w / scale), math.floor(h / scale)
  return scale, math.floor((w - lw * scale) / 2), math.floor((h - lh * scale) / 2), lw, lh
end

-- the page for the current state (built again for every frame and press)
function Launcher:_page()
  local _, _, _, lw, lh = self:_layout()
  self.page = Screens.build(self.menu, self.ui, { w = lw, h = lh, device = self.device })
  return self.page
end

local ICONS = {
  check = { "......#", ".....##", "#...##.", "##.##..", ".###...", "..#...." },
  cross = { "#....#", "##..##", ".####.", ".####.", "##..##", "#....#" },
  dot = { "......", "......", "..##..", "..##..", "......", "......" },
  dash = { "......", "......", "......", ".####.", "......", "......" },
}

function Launcher:_colour(name, alpha)
  local colours = Theme.get(self:_coopSettings().theme)
  local c
  if type(name) == "string" and name:find("^edition:") then
    c = Theme.edition(colours, name:sub(9))
  else
    c = colours[name] or colours.ink
  end
  love.graphics.setColor(c[1], c[2], c[3], alpha or 1)
end

function Launcher:_paint(page)
  local g = love.graphics
  local scale, ox, oy = self:_layout()
  local clip
  for _, n in ipairs(page.nodes) do
    if n.clip ~= clip then
      clip = n.clip
      if clip then
        g.setScissor(ox + clip.x * scale, oy + clip.y * scale, clip.w * scale, clip.h * scale)
      else
        g.setScissor()
      end
    end
    local k = n.kind
    if k == "rect" then
      self:_colour(n.colour, n.alpha)
      g.rectangle("fill", n.x, n.y, n.w, n.h)
    elseif k == "frame" then
      self:_colour(n.colour)
      local t = n.thick or 1
      g.rectangle("fill", n.x, n.y, n.w, t)
      g.rectangle("fill", n.x, n.y + n.h - t, n.w, t)
      g.rectangle("fill", n.x, n.y + t, t, n.h - 2 * t)
      g.rectangle("fill", n.x + n.w - t, n.y + t, t, n.h - 2 * t)
    elseif k == "text" and self.font then
      self:_colour(n.colour)
      g.setFont(self.font)
      local s = n.scale or 1
      local baseline = self.font.getBaseline and self.font:getBaseline() or 19
      g.print(n.text, n.x, n.y + (BASELINE - baseline) * s, 0, s, s)
      if n.underline then
        g.rectangle("fill", n.x, n.y + (BASELINE + 2) * s, Ui.width(n.text, s), s)
      end
    elseif k == "icon" then
      self:_colour(n.colour)
      for r, line in ipairs(ICONS[n.name] or {}) do
        for c = 1, #line do
          if line:sub(c, c) == "#" then g.rectangle("fill", n.x + c - 1, n.y + r - 1, 1, 1) end
        end
      end
    elseif k == "hit" and n.key == self.ui.focus and n.enabled then
      -- the focus: an accent outline just outside the target
      self:_colour("accent")
      g.rectangle("fill", n.x - 3, n.y - 3, n.w + 6, 2)
      g.rectangle("fill", n.x - 3, n.y + n.h + 1, n.w + 6, 2)
      g.rectangle("fill", n.x - 3, n.y - 1, 2, n.h + 2)
      g.rectangle("fill", n.x + n.w + 1, n.y - 1, 2, n.h + 2)
    end
  end
  g.setScissor()
end

function Launcher:draw()
  local g = love.graphics
  local scale, ox, oy = self:_layout()
  local page = self:_page()
  g.push("all")
  local colours = Theme.get(self:_coopSettings().theme)
  g.clear(colours.shell[1], colours.shell[2], colours.shell[3], 1)
  g.translate(ox, oy)
  g.scale(scale)
  self:_paint(page)
  g.pop()
end

-- ------------------------------------------------------------ focus

local DIRECTIONS = { up = true, down = true, left = true, right = true }

-- move the focus to a page target (and the model's cursor with it)
function Launcher:_focus(node)
  self.ui.focus = node.key
  local act = node.act
  if act and act.kind == "row" then
    local model = Screens.model(self.menu)
    model.cursor = act.index
    self.ui.cursor = act.index
  end
end

function Launcher:_activate(node)
  local act = node.act or {}
  local menu = self.menu
  if act.kind == "row" then
    self:_focus(node)
    return self:_run(menu:press("a"))
  elseif act.kind == "tab" then
    menu:openTab(act.tab)
    self.ui = { scroll = 0, focus = "tab:" .. act.tab }
  elseif act.kind == "back" then
    return self:press("b")
  elseif act.kind == "quit" then
    return self:_run({ kind = "quit" })
  elseif act.kind == "ok" then
    return self:_run(menu:press("a"))
  elseif act.kind == "key" then
    local coop = menu.coop
    if coop and coop.entry then
      coop.entry.keypad:pick(act.r, act.c)
      return self:_run(menu:press("a"))
    end
  end
end

-- the screen's model is typing (the text entry has a grid of its own)
function Launcher:_typing()
  local coop = self.menu.screen == "coop" and self.menu.coop
  return coop and coop:typing()
end

function Launcher:press(action)
  local menu = self.menu
  local screenBefore = menu.screen .. "/" .. tostring(menu.coop and menu.coop.screen)
  if menu:currentNotice() or self:_typing() then
    self:_run(menu:press(action))
  else
    local page = self:_page()
    local focused = self.ui.focus and page:find(self.ui.focus)
    local act = focused and focused.act
    local stepping = act and act.kind == "row" and (action == "left" or action == "right")
      and (Screens.model(menu):items()[act.index] or {}).option
    if stepping then
      -- left and right step a game option's value, never leave the row (#5)
      self:_focus(focused)
      self:_run(menu:press(action))
    elseif DIRECTIONS[action] then
      local target = focused and Ui.neighbour(page, focused, action)
      if target then
        self:_focus(target)
      elseif not focused then
        self:_run(menu:press(action))
      elseif action == "up" or action == "down" then
        -- nothing that way: scroll a long page instead
        local step = (action == "down" and 3 or -3) * Ui.LINE
        self.ui.scroll = math.max(0, math.min((self.ui.scroll or 0) + step, page.maxScroll or 0))
      end
    elseif (action == "a" or action == "start") and focused and focused.enabled then
      self:_activate(focused)
    else
      self:_run(menu:press(action))
    end
  end
  -- a new screen starts at its top
  local screenAfter = menu.screen .. "/" .. tostring(menu.coop and menu.coop.screen)
  if screenAfter ~= screenBefore then self.ui.scroll = 0 end
  -- the SAVES page changes what CONTINUE would open (#6)
  if menu.screen == "saves" or screenBefore:find("^saves/") then self.saveCache = {} end
end

-- ------------------------------------------------------------ input

function Launcher:keypressed(key)
  self.device = "keys"
  local menu = self.menu
  if self:_capture({ kind = "key", key = key }) then
    self.swallowText = #key == 1 or key == "space"
    return
  end
  -- co-op (#12): a text field types; arrows still move on its grid
  if self:_typing() then
    local coop = menu.coop
    local ctrl = love.keyboard and love.keyboard.isDown
      and love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")
    if key == "v" and ctrl and love.system.getClipboardText then
      coop:text((love.system.getClipboardText() or ""):gsub("[\r\n]", ""))
    elseif key == "backspace" then coop:erase()
    elseif key == "return" or key == "kpenter" then self:press("start")
    elseif key == "escape" then coop:cancelEntry()
    elseif key == "up" or key == "down" or key == "left" or key == "right" then
      self:press(key)
    end
    return
  end
  if menu.screen == "import" and menu.canType and not menu.notice then
    local ctrl = love.keyboard and love.keyboard.isDown
      and love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")
    if key == "v" and ctrl and love.system.getClipboardText then
      menu:text((love.system.getClipboardText() or ""):gsub("[\r\n]", ""))
      return
    end
    if key == "backspace" then return menu:erase() end
    if key == "return" or key == "kpenter" then return self:_run(menu:press("a")) end
    if key == "escape" then return self:press("b") end
    return
  end
  if key == "pageup" or key == "pagedown" then
    return self:wheelmoved(0, key == "pageup" and 6 or -6)
  end
  local action = KEYS[key]
  if not action then return end
  self:press(action)
  -- a letter key that opened a text field also arrives as text: drop it
  local typesText = #key == 1 or key == "space"
  if typesText and (menu.screen == "import" or self:_typing()) then self.swallowText = true end
end

function Launcher:textinput(t)
  if self.swallowText then self.swallowText = false return end
  self.menu:text(t)
end

local PAD_ACTIONS = { up = true, down = true, left = true, right = true,
  a = true, b = true, start = true }

function Launcher:gamepadpressed(joystick, button)
  self.device = "pad"
  if self:_capture({ kind = "pad", button = button, device = Seats.describe(joystick, joysticks()) }) then
    return
  end
  local action = GamepadMap.mapGamepadButton(button)
  if PAD_ACTIONS[action] then self:press(action) end
end

function Launcher:gamepadreleased() end

function Launcher:gamepadaxis(joystick, axis, value)
  local dir
  if axis == "lefty" then dir = value < 0 and "up" or "down"
  elseif axis == "leftx" then dir = value < 0 and "left" or "right"
  else return end
  local key = tostring(joystick) .. axis
  local held = math.abs(value) >= STICK_ON
  if held and not self.axis[key] then
    self.device = "pad"
    if not self.menu:capturing() then self:press(dir) end
  end
  self.axis[key] = held
end

-- A joystick SDL knows as a gamepad sends gamepad events too; only the
-- unmapped ones are read raw.
local function rawOnly(joystick)
  return not (joystick and joystick.isGamepad and joystick:isGamepad())
end

function Launcher:joystickpressed(joystick, button)
  if not rawOnly(joystick) then return end
  self.device = "pad"
  if self:_capture({ kind = "pad", button = GamepadMap.mapRawToGamepadButton(button) or ("joy" .. button),
      device = Seats.describe(joystick, joysticks()) }) then
    return
  end
  local action = GamepadMap.mapRawButton(button)
  if PAD_ACTIONS[action] then self:press(action) end
end

function Launcher:joystickreleased() end
function Launcher:joystickaxis() end

function Launcher:joystickhat(joystick, _, direction)
  if not rawOnly(joystick) or self.menu:capturing() then return end
  self.device = "pad"
  local dir = ({ u = "up", d = "down", l = "left", r = "right" })[direction]
  if dir then self:press(dir) end
end

-- the page target under a window position, or nil
function Launcher:_targetAt(x, y)
  local scale, ox, oy = self:_layout()
  local page = self:_page()
  local n = page:at((x - ox) / scale, (y - oy) / scale)
  if n and n.enabled then return n end
  return nil
end

function Launcher:_tap(x, y)
  -- a click or tap while CONTROLS waits for a press cancels it (#4)
  if self:_capture({ kind = "cancel" }) then return end
  local n = self:_targetAt(x, y)
  if n then return self:_activate(n) end
  -- a tap beside a message closes it
  if self.menu:currentNotice() then return self:press("a") end
end

function Launcher:mousepressed(x, y, button, istouch)
  if istouch then return end
  self.device = "mouse"
  if button == 2 then
    if self:_capture({ kind = "cancel" }) then return end
    return self:press("b")
  end
  if button == 1 then self:_tap(x, y) end
end

function Launcher:mousereleased() end

function Launcher:mousemoved(x, y, _, _, istouch)
  if istouch then return end
  local n = self:_targetAt(x, y)
  if n and n.key ~= self.ui.focus then
    self.device = "mouse"
    self:_focus(n)
  end
end

function Launcher:wheelmoved(_, dy)
  local page = self.page or self:_page()
  local step = -(dy or 0) * Ui.LINE * 2
  self.ui.scroll = math.max(0, math.min((self.ui.scroll or 0) + step, page.maxScroll or 0))
end

-- co-op (#7): a tap presses when the finger lifts; a finger that moved
-- drags a long page instead and presses nothing
function Launcher:touchpressed(id, x, y)
  self.device = "touch"
  self.touch = { id = id, x = x, y = y, scroll = self.ui.scroll or 0 }
end

function Launcher:touchmoved(id, x, y)
  local t = self.touch
  if not t or t.id ~= id then return end
  local scale = self:_layout()
  local dx, dy = (x - t.x) / scale, (y - t.y) / scale
  if not t.dragging and math.abs(dx) < TOUCH_SLOP and math.abs(dy) < TOUCH_SLOP then return end
  t.dragging = true
  local page = self.page or self:_page()
  self.ui.scroll = math.max(0, math.min(math.floor(t.scroll - dy + 0.5), page.maxScroll or 0))
end

function Launcher:touchreleased(id)
  local t = self.touch
  if not t or t.id ~= id then return end
  self.touch = nil
  if not t.dragging then self:_tap(t.x, t.y) end
end

function Launcher:filedropped(file)
  if not (file and file.open) then return end
  local ok = file:open("r")
  if not ok then return self.menu:notify(L("The dropped file could not be read.")) end
  local data = file:read(file:getSize())
  file:close()
  if type(data) ~= "string" and data and data.getString then data = data:getString() end
  local name = file.getFilename and file:getFilename() or nil
  self:importData(data, name and (name:match("[^/\\]+$") or name) or nil)
end

function Launcher:focus() end

return Launcher
