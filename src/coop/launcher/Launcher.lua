-- The fork's own launcher (#3, licence term 2 of upstream's LICENSE.MD): a
-- Game Boy style menu at the game's 160x144 resolution that picks Red, Blue
-- or Yellow, imports its ROM, continues or starts a game and shows the credit
-- line term 1 asks for on every screen.  Its co-op screens (#12) host and
-- join sessions (CoopMenu.lua); a session started here keeps running into
-- the game.
--
-- main.lua drives it through the same calls it makes on any launcher object
-- (update, draw and the input callbacks), so the hooks there stay small.
-- Text is drawn by the game's own Font renderer: with the cartridge's font
-- once a game is imported, before that with the bundled Plain Pixel face.
-- Nothing here loads upstream's launcher files (AGENTS.md lists them).

local GameVersion = require("src.core.GameVersion")
local GamepadMap = require("src.core.GamepadMap")
local Menu = require("src.coop.launcher.Menu")
local RomImport = require("src.coop.launcher.RomImport")
local CoopSettings = require("src.coop.launcher.CoopSettings")
local Session = require("src.coop.session.Session")

local Launcher = {}
Launcher.__index = Launcher

-- The launcher on screen, for tests and the frame driver.
Launcher.current = nil

local W, H = 160, 144
local COLS = W / 8
local FOOTER_ROW = 12        -- rows 12-17 hold the credit line
local ITEM_ROW = 2           -- first menu row inside the box
local STICK_ON = 0.5

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

-- Font pages of an imported game, served to Font through Assets.compose so
-- the launcher needs no mounted cache and never shares Assets' cache keys
-- with the game's own assets/generated paths.
local function cartFontDef(version)
  local CacheFs = require("src.import.CacheFs")
  local prefix = GameVersion.cachePrefix(version)
  local function read(rel)
    local saved = CacheFs.prefix
    CacheFs.prefix = ""
    local bytes = CacheFs.read(prefix .. rel)
    -- a developer checkout keeps Red's data unprefixed in the source tree
    if type(bytes) ~= "string" and version == "red" then bytes = CacheFs.read(rel) end
    CacheFs.prefix = saved
    return type(bytes) == "string" and bytes or nil
  end
  local source = read("data/generated/font.lua")
  if not source then return nil end
  -- sandboxed like Data's cache loads: the cache is user-writable
  local chunk = load(source, "@" .. prefix .. "data/generated/font.lua", "t", {})
  if not chunk then return nil end
  local ok, def = pcall(chunk)
  if not ok or type(def) ~= "table" then return nil end
  local Assets = require("src.render.Assets")
  for _, field in ipairs({ "image", "imageExtra", "imageFrames" }) do
    local path = def[field]
    if type(path) == "string" and path:find("^assets/generated/") then
      local bytes = read(path)
      if not bytes then return nil end
      local key = "coop-launcher/" .. version .. "/" .. path:sub(#"assets/generated/" + 1)
      Assets.compose(key, function()
        return love.image.newImageData(love.filesystem.newFileData(bytes, key))
      end)
      def[field] = key
    end
  end
  return def
end

-- With no game imported yet there is no cartridge font: text comes from the
-- bundled Plain Pixel instead.  Its glyphs are 5x11 and only crisp at their
-- 15px design size, so that mode draws on a canvas of twice the resolution,
-- where one line still fits a Game Boy text row.
local PLAIN_SIZE = 15

function Launcher.new(onBoot, opts)
  opts = opts or {}
  local self = setmetatable({
    onBoot = onBoot, bootOnImport = opts.bootOnImport == true,
    readyCache = {}, saveCache = {}, clock = 0, axis = {},
  }, Launcher)
  local initial = opts.initialTab
  if not RomImport.isGen1(initial) then initial = nil end
  -- co-op (#12): the cartridge last picked for co-op
  if not initial then
    local ok, settings = pcall(self._coopSettings, self)
    if ok and RomImport.isGen1(settings.pick) then initial = settings.pick end
  end
  self.menu = Menu.new({
    ready = function(v) return self:isReady(v) end,
    saveInfo = function(v) return self:saveInfo(v) end,
    canQuit = not mobile(),
    canType = not mobile(),
    initial = initial,
    coop = function(v) return self:_coopEnv(v) end,
  })
  self:_coopReturn()
  if opts.notice then self.menu:notify(opts.notice) end
  self:_loadFont()
  Launcher.current = self
  return self
end

-- ------------------------------------------------------------ co-op (#12)

function Launcher:_coopSettings()
  if not self.coopSettings then self.coopSettings = CoopSettings.load() end
  return self.coopSettings
end

-- After a session: the solo save slots come back, and the co-op screen
-- says why the session ended.
function Launcher:_coopReturn()
  if Session.current then return end
  local okSettings, settings = pcall(self._coopSettings, self)
  if okSettings then pcall(settings.restoreSlots, settings, require("src.core.SaveData")) end
  local note = Session.takeReturn()
  if note then
    local version = note.version
    if version and self:isReady(version) then
      self.menu:openCoop(version, note.notice)
    else
      self.menu:notify(note.notice)
    end
  end
end

-- what the co-op screens reach: this device's settings and campaigns, the
-- session, the LAN beacon and this device's addresses
function Launcher:_coopEnv(version)
  local settings = self:_coopSettings()
  settings:picked(version)
  local Campaigns = require("src.coop.Campaigns")
  local launcher = self
  return {
    version = version,
    ready = function(v) return launcher:isReady(v) end,
    settings = settings,
    campaigns = Campaigns,
    canOpenLogs = not mobile() and love.system ~= nil and love.system.openURL ~= nil,
    addresses = function() return require("src.coop.session.Addresses").mine() end,
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
    host = function(campaign, name, v)
      return Session.startHost({
        campaign = campaign, cartridge = Session.cartridge(v), name = name,
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
    self.menu:notify("The logs are in " .. dir)
  end
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
  local Font = require("src.render.Font")
  local version = RomImport.firstReady()
  local def = version and cartFontDef(version)
  self.cartFont = def ~= nil and pcall(Font.load, { font = def })
  self.res = self.cartFont and 1 or 2
  self.canvas = nil
  if not self.cartFont and not self.plainFont then
    local ok, font = pcall(love.graphics.newFont, Font.PLAINPIXEL, PLAIN_SIZE, "mono", 1)
    if ok and font then
      if font.setFilter then font:setFilter("nearest", "nearest") end
      self.plainFont = font
    end
  end
end

-- ------------------------------------------------------------ commands

function Launcher:_run(command)
  if not command then return end
  if command.kind == "quit" then
    love.event.quit()
  elseif command.kind == "import" then
    self:startPath(command.path)
  elseif command.kind == "boot" then
    if command.newGame then
      -- a new game gets its own slot; the old save stays on disk
      local SaveData = require("src.core.SaveData")
      local id = SaveData.createSlot(command.version)
      if id then SaveData.setActiveSlot(command.version, id) end
    end
    self:_boot(command.version)
  elseif command.kind == "coop_enter" then
    -- the campaign's own save slot on this device (until campaign files, #13)
    local SaveData = require("src.core.SaveData")
    self:_coopSettings():enterSlot(SaveData, command.version, command.campaign.id,
      command.campaign.title)
    if self.nearby then self.nearby:close() end
    self.nearby = nil
    self:_boot(command.version)
  elseif command.kind == "copy" then
    if love.system.setClipboardText then love.system.setClipboardText(command.text) end
  elseif command.kind == "open_logs" then
    self:_openLogs()
  end
end

function Launcher:_boot(version)
  if Launcher.current == self then Launcher.current = nil end
  self.booted = version
  if self.onBoot then self.onBoot(version) end
end

function Launcher:press(action)
  self:_run(self.menu:press(action))
end

-- ------------------------------------------------------------ import

function Launcher:importData(data, name)
  if self.job then return end
  local version, bytes, label, hash = RomImport.identify(data, name)
  if not version then
    self.menu:notify(bytes)
    return
  end
  self.job = RomImport.start(version, bytes, label, hash)
  self.menu:importStarted(version, label)
  self:_pollJob()
end

function Launcher:startPath(path)
  path = tostring(path or ""):gsub("^%s+", ""):gsub("%s+$", "")
  path = path:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
  path = path:gsub("^file://", "")
  local file = require("src.core.SaveData").openNative(path, "rb")
  if not file then
    self.menu:notify("Could not open " .. path)
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
    self.menu:importFailed("Import failed: " .. tostring(job.error))
    -- A scripted import-only run has nobody to read the menu.
    if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then
      io.stderr:write("Import failed: " .. tostring(job.error) .. "\n")
      love.event.quit(1)
    end
    return
  end
  if not self.cartFont then self:_loadFont() end
  if self.bootOnImport then return self:_boot(job.version) end
  self.menu:importDone(job.version)
end

-- ------------------------------------------------------------ frame

function Launcher:update(dt)
  self.swallowText = false
  self.clock = self.clock + (dt or 0)
  self:_pollJob()
  -- co-op (#12): the session runs while the launcher shows it
  Session.tick(dt, nil)
  self:_run(self.menu:update(dt))
end

-- One string at a text cell; every launcher string goes through here.
function Launcher:_text(str, col, row)
  if self.cartFont then
    require("src.render.Font").draw(str, col * 8, row * 8)
    return
  end
  local g = love.graphics
  local font = self.plainFont
  if not font then return end
  -- native size on the 2x canvas: undo the 2x layout scale for the glyphs
  g.push()
  g.scale(0.5)
  g.setFont(font)
  local baseline = font.getBaseline and font:getBaseline() or font:getHeight()
  g.print(str, col * 16, row * 16 + 14 - baseline)
  g.pop()
end

function Launcher:_box(col, row, w, h)
  if self.cartFont then
    require("src.render.Font").drawBox(col, row, w, h)
    return
  end
  local g = love.graphics
  local r, gr, b, a = g.getColor()
  g.setColor(1, 1, 1, 1)
  g.rectangle("fill", col * 8, row * 8, w * 8, h * 8)
  g.setColor(r, gr, b, a)
  g.rectangle("line", col * 8 + 2.5, row * 8 + 2.5, w * 8 - 5, h * 8 - 5)
end

function Launcher:_cursorGlyph() return self.cartFont and "▶" or ">" end
function Launcher:_moreGlyph() return self.cartFont and "▼" or "v" end

function Launcher:_centered(str, row)
  self:_text(str, math.floor((COLS - #str) / 2), row)
end

function Launcher:_drawItems(items, cursor)
  -- every other row while five fit in the box, else one per row
  local step = #items > 5 and 1 or 2
  for i, item in ipairs(items) do
    local row = ITEM_ROW + (i - 1) * step
    if i == cursor then self:_text(self:_cursorGlyph(), 1, row) end
    self:_text(item.label, 2, row)
    if item.detail then self:_text(item.detail, COLS - 1 - #item.detail, row) end
  end
end

-- the text entry's grid: characters two columns apart from column 2, the
-- special keys at fixed columns on the last row (#12)
local KEYPAD_ROW = 4
local KEYPAD_SPECIAL_ROW = 10
local KEYPAD_SPECIAL_COL = { SPACE = 2, DEL = 9, END = 15 }

local function keypadCell(rows, r, c)
  if r == #rows then return KEYPAD_SPECIAL_COL[rows[r][c]] or 2, KEYPAD_SPECIAL_ROW end
  return 2 + (c - 1) * 2, KEYPAD_ROW + r - 1
end

function Launcher:_drawCoop(coop)
  local v = coop:view()
  self:_centered(v.title, 0)
  self:_box(0, 1, COLS, 11)
  if v.keypad then
    local k = v.keypad
    -- the field: the text, then a line for each place left (the cartridge
    -- font has no "_")
    local shown = k.text
    if #shown > COLS - 3 then shown = shown:sub(-(COLS - 3)) end
    self:_text(shown, 2, 2)
    local blank = self.cartFont and "─" or "_"
    for i = #shown + 1, math.min(k.max, COLS - 3) do self:_text(blank, 1 + i, 2) end
    for r, row in ipairs(k.rows) do
      for c, key in ipairs(row) do
        local col, line = keypadCell(k.rows, r, c)
        self:_text(key, col, line)
        if r == k.row and c == k.col then self:_text(self:_cursorGlyph(), col - 1, line) end
      end
    end
  else
    for _, l in ipairs(v.lines) do self:_text(l.text, l.col, l.row) end
    for _, it in ipairs(v.items) do
      if it.index == v.cursor then self:_text(self:_cursorGlyph(), 1, it.row) end
      self:_text(it.label, 2, it.row)
      if it.detail then self:_text(it.detail, COLS - 1 - #it.detail, it.row) end
      if it.value then self:_text(it.value, 3, it.row + 1) end
    end
    if v.more then self:_text(self:_moreGlyph(), COLS - 2, 10) end
  end
  return coop.notice
end

function Launcher:_drawScreen()
  local menu = self.menu
  local screen = menu.screen
  local notice = menu.notice
  if screen == "coop" and menu.coop then
    notice = self:_drawCoop(menu.coop)
  elseif screen == "title" then
    self:_centered(Menu.TITLE, 0)
    self:_box(0, 1, COLS, 11)
    self:_drawItems(menu:items(), menu.cursor)
  elseif screen == "game" then
    self:_centered("POKEMON " .. Menu.gameLabel(menu.version), 0)
    self:_box(0, 1, COLS, 11)
    local items = menu:items()
    local info = self:saveInfo(menu.version)
    if info then items[1].detail = info.name:sub(1, 7) end
    self:_drawItems(items, menu.cursor)
    if info then self:_text(("BADGES %d  %s"):format(info.badges, info.time), 2, 10) end
  elseif screen == "import" then
    self:_centered("POKEMON " .. Menu.gameLabel(menu.version), 0)
    self:_box(0, 1, COLS, 11)
    local help = menu.canType
      and "Drop the ROM file on this window, or type its path and press ENTER."
      or "Importing a ROM on this device comes later."
    for i, line in ipairs(Menu.wrap(help, COLS - 2)) do self:_text(line, 1, 1 + i) end
    if menu.canType then
      local shown = menu.path
      if #shown > COLS - 3 then shown = shown:sub(-(COLS - 3)) end
      local blink = math.floor(self.clock * 2) % 2 == 0 and "-" or ""
      self:_text(shown .. blink, 1, 8)
    end
    self:_text("B: BACK", 1, 10)
  elseif screen == "importing" then
    local job = menu.importing or {}
    self:_centered("POKEMON " .. Menu.gameLabel(job.version), 0)
    self:_box(0, 1, COLS, 11)
    self:_text("IMPORTING...", 1, 3)
    for i, line in ipairs(Menu.wrap(job.stage or "", COLS - 2)) do
      if i <= 2 then self:_text(line, 1, 4 + i) end
    end
    local g = love.graphics
    g.rectangle("line", 8.5, 8 * 8 + 0.5, W - 17, 7)
    g.rectangle("fill", 10, 8 * 8 + 2, math.floor((W - 20) * (job.progress or 0)), 4)
  elseif screen == "credits" then
    self:_box(0, 0, COLS, 12)
    local lines = {}
    for _, para in ipairs(Menu.CREDITS) do
      for _, line in ipairs(Menu.wrap(para, COLS - 2)) do lines[#lines + 1] = line end
    end
    local visible = 10
    menu.scroll = math.max(0, math.min(menu.scroll, #lines - visible))
    for i = 1, visible do
      local line = lines[menu.scroll + i]
      if line then self:_text(line, 1, i) end
    end
    if menu.scroll + visible < #lines then self:_text(self:_moreGlyph(), COLS - 2, 10) end
  end
  if notice then
    self:_box(0, 3, COLS, 7)
    for i, line in ipairs(Menu.wrap(notice, COLS - 2)) do
      if i <= 5 then self:_text(line, 1, 3 + i) end
    end
  end
  for i, line in ipairs(Menu.wrap(Menu.CREDIT, COLS)) do
    self:_text(line, 0, FOOTER_ROW + i - 1)
  end
end

-- Game Boy pixels per screen pixel and the offset: whole canvas pixels per
-- screen pixel where the window allows it.
function Launcher:_layout()
  local w, h = love.graphics.getDimensions()
  local res = self.res or 1
  local fit = math.min(w / (W * res), h / (H * res))
  if fit >= 1 then fit = math.floor(fit) end
  local scale = fit * res
  return scale, math.floor((w - W * scale) / 2), math.floor((h - H * scale) / 2)
end

function Launcher:draw()
  local g = love.graphics
  local res = self.res or 1
  if not self.canvas then
    self.canvas = g.newCanvas(W * res, H * res, { dpiscale = 1 })
    if self.canvas.setFilter then self.canvas:setFilter("nearest", "nearest") end
  end
  g.push("all")
  g.setCanvas(self.canvas)
  g.clear(1, 1, 1, 1)
  g.setColor(0, 0, 0, 1)
  g.scale(res)
  self:_drawScreen()
  g.setCanvas()
  g.pop()
  g.clear(0.06, 0.06, 0.06, 1)
  local scale, ox, oy = self:_layout()
  g.setColor(1, 1, 1, 1)
  g.draw(self.canvas, ox, oy, 0, scale / res, scale / res)
end

-- ------------------------------------------------------------ input

function Launcher:keypressed(key)
  local menu = self.menu
  -- co-op (#12): a text field types; arrows still move on its grid
  local coop = menu.screen == "coop" and menu.coop
  if coop and coop:typing() then
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
    if key == "return" or key == "kpenter" then return self:press("a") end
    if key == "escape" then return self:press("b") end
    return
  end
  local action = KEYS[key]
  if not action then return end
  self:press(action)
  -- the key that opened the path field also arrives as text: drop it
  if menu.screen == "import" then self.swallowText = true end
  if menu.screen == "coop" and menu.coop and menu.coop:typing() then self.swallowText = true end
end

function Launcher:textinput(t)
  if self.swallowText then self.swallowText = false return end
  self.menu:text(t)
end

local PAD_ACTIONS = { up = true, down = true, left = true, right = true,
  a = true, b = true, start = true }

function Launcher:gamepadpressed(_, button)
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
  if held and not self.axis[key] then self:press(dir) end
  self.axis[key] = held
end

-- A joystick SDL knows as a gamepad sends gamepad events too; only the
-- unmapped ones are read raw.
local function rawOnly(joystick)
  return not (joystick and joystick.isGamepad and joystick:isGamepad())
end

function Launcher:joystickpressed(joystick, button)
  if not rawOnly(joystick) then return end
  local action = GamepadMap.mapRawButton(button)
  if PAD_ACTIONS[action] then self:press(action) end
end

function Launcher:joystickreleased() end
function Launcher:joystickaxis() end

function Launcher:joystickhat(joystick, _, direction)
  if not rawOnly(joystick) then return end
  local dir = ({ u = "up", d = "down", l = "left", r = "right" })[direction]
  if dir then self:press(dir) end
end

-- Mouse and touch: a tap on a menu row picks it, anywhere else on a message
-- or a text screen goes on, a right click goes back.
function Launcher:_cell(x, y)
  local scale, ox, oy = self:_layout()
  local px, py = (x - ox) / scale, (y - oy) / scale
  if px < 0 or py < 0 or px >= W or py >= H then return nil end
  return math.floor(px / 8), math.floor(py / 8)
end

function Launcher:_rowAt(row)
  if not row or row < ITEM_ROW then return nil end
  local index = math.floor((row - ITEM_ROW) / 2) + 1
  if index <= #self.menu:items() then return index end
  return nil
end

-- a tap on a co-op screen: a row picks it, a key of the text entry types it
function Launcher:_tapCoop(coop, col, row)
  if coop.notice then return self:press("a") end
  local v = coop:view()
  if v.keypad then
    local k = v.keypad
    for r, keys in ipairs(k.rows) do
      for c, key in ipairs(keys) do
        local kc, kr = keypadCell(k.rows, r, c)
        if row == kr and col >= kc - 1 and col < kc + math.max(2, #key) then
          coop.entry.keypad:pick(r, c)
          return self:press("a")
        end
      end
    end
    return
  end
  for _, it in ipairs(v.items) do
    if it.row == row or (it.value and it.row + 1 == row) then
      if it.enabled == false then return end
      coop.cursor = it.index
      return self:press("a")
    end
  end
end

function Launcher:_tap(x, y)
  local menu = self.menu
  local col, row = self:_cell(x, y)
  if not row then return end
  if menu.screen == "coop" and menu.coop then return self:_tapCoop(menu.coop, col, row) end
  if menu.notice or menu.screen == "credits" then return self:press("a") end
  if menu.screen == "import" then
    if row == 10 then self:press("b") end
    return
  end
  local index = self:_rowAt(row)
  if index then
    menu.cursor = index
    self:press("a")
  end
end

function Launcher:mousepressed(x, y, button, istouch)
  if istouch then return end
  if button == 2 then return self:press("b") end
  if button == 1 then self:_tap(x, y) end
end

function Launcher:mousereleased() end

function Launcher:mousemoved(x, y, _, _, istouch)
  if istouch then return end
  local menu = self.menu
  if menu.screen == "coop" and menu.coop and not menu.coop.notice then
    local _, row = self:_cell(x, y)
    for _, it in ipairs(menu.coop:view().items) do
      if row and (it.row == row or (it.value and it.row + 1 == row))
          and it.enabled ~= false then
        menu.coop.cursor = it.index
      end
    end
    return
  end
  if menu.notice or (menu.screen ~= "title" and menu.screen ~= "game") then return end
  local _, row = self:_cell(x, y)
  local index = self:_rowAt(row)
  if index then menu.cursor = index end
end

function Launcher:touchpressed(_, x, y) self:_tap(x, y) end
function Launcher:touchmoved() end
function Launcher:touchreleased() end

function Launcher:filedropped(file)
  if not (file and file.open) then return end
  local ok = file:open("r")
  if not ok then return self.menu:notify("The dropped file could not be read.") end
  local data = file:read(file:getSize())
  file:close()
  if type(data) ~= "string" and data and data.getString then data = data:getString() end
  local name = file.getFilename and file:getFilename() or nil
  self:importData(data, name and (name:match("[^/\\]+$") or name) or nil)
end

function Launcher:focus() end

return Launcher
