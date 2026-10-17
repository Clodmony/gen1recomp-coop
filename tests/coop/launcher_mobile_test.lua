-- The fork's launcher on a phone (#7), ROM-free: main.lua boots it as on
-- Android, at a phone's size.  The ROM, a save and a mod come in through
-- the system's file picker (love.system.pickFile, the vendored
-- love-android bridge: the picked file is copied into the save folder as
-- picked_rom.gb, picked_save.sav or picked_mod.zip, and a cancel or a
-- failed copy leaves pick_error.flag); the launcher takes the copy when it
-- is there, also after the app was restarted.  A finger drag scrolls a
-- long page and does not press what it started on; a tap still does.
--   luajit tests/coop/launcher_mobile_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

-- a phone: Android, portrait 1080x2400, the picker bridge
love.system.getOS = function() return "Android" end
love.graphics.getDimensions = function() return 1080, 2400 end
love.graphics.getPixelDimensions = function() return 1080, 2400 end
local picks = {}
love.system.pickFile = function(kind) picks[#picks + 1] = kind return true end

local env = { POKEPORT_DATA_DIR = "tests/fixture_data" }
local realGetenv = os.getenv
os.getenv = function(k)
  if env[k] ~= nil then return env[k] or nil end
  return realGetenv(k)
end

_G.arg = {}
dofile("main.lua")

local Launcher = require("src.coop.launcher.Launcher")
local RomImport = require("src.coop.launcher.RomImport")
local Screens = require("src.coop.launcher.Screens")
local ready = {}
RomImport.isReady = function(v) return ready[v] == true end

local function frames(n)
  for _ = 1, n or 1 do
    love.update(1 / 60)
    love.draw()
  end
end

-- the window position of the target for model row `id`, or of key `id`
local function target(l, id, game)
  local page = l:_page()
  local model = Screens.model(l.menu)
  for _, n in ipairs(page:targets()) do
    local act = n.act or {}
    local row = act.kind == "row" and model:items()[act.index]
    if (row and row.id == id and (game == nil or row.game == game)) or n.key == id then
      local scale, ox, oy = l:_layout()
      return ox + (n.x + n.w / 2) * scale, oy + (n.y + n.h / 2 - (l.ui.scroll or 0)) * scale
    end
  end
  return nil
end

local touchId = 0
local function tap(l, id, game)
  local x, y = target(l, id, game)
  if not x then return false end
  touchId = touchId + 1
  love.touchpressed(touchId, x, y, 0, 0, 1)
  -- Android's synthesized mouse twin is ignored (istouch)
  love.mousepressed(x, y, 1, true)
  love.touchreleased(touchId, x, y, 0, 0, 1)
  love.mousereleased(x, y, 1, true)
  return true
end

local function texts(l)
  love.draw()
  return table.concat(l.page and l.page:texts() or {}, " ")
end

love.load({})
frames(3)
local l = Launcher.current
check(l ~= nil, "the fork's launcher opens on a phone")
if not l then T.finish() end
eq(l.device, "touch", "it starts in touch mode")

-- 1. IMPORT ROM opens the system's picker; the copy it leaves is imported
do
  check(tap(l, "import"), "IMPORT ROM is on PLAY")
  eq(l.menu.screen, "import", "a tap opens the import screen")
  check(not texts(l):find("comes later", 1, true), "the import screen no longer says it comes later")
  check(tap(l, "pick"), "the import screen has a button that chooses the file")
  eq(picks[#picks], "rom", "which opens the picker for a ROM")
  -- the picker copies the file (here: no Game Boy ROM) and the app gets focus back
  love.filesystem.write("picked_rom.gb", "junk")
  love.focus(true)
  frames(2)
  check(l.menu.notice and l.menu.notice:find("1 MiB", 1, true) ~= nil,
    "the picked file is checked like a dropped one (" .. tostring(l.menu.notice) .. ")")
  eq(love.filesystem.getInfo("picked_rom.gb"), nil, "and the copy is removed")
  tap(l, "ok")
  love.touchpressed(99, 5, 5, 0, 0, 1)
  love.touchreleased(99, 5, 5, 0, 0, 1)
  eq(l.menu.notice, nil, "a tap closes the message")
end

-- 2. a cancelled pick leaves no message; a failed copy says so
do
  if l.menu.screen ~= "import" then tap(l, "import") end
  tap(l, "pick")
  love.filesystem.write("pick_error.flag", "cancelled:picked_rom.gb")
  frames(2)
  eq(l.menu.notice, nil, "a cancelled pick says nothing")
  eq(love.filesystem.getInfo("pick_error.flag"), nil, "and its flag is removed")
  tap(l, "pick")
  love.filesystem.write("pick_error.flag", "picked_rom.gb")
  frames(2)
  check(l.menu.notice ~= nil, "a pick that could not be copied is reported")
  eq(love.filesystem.getInfo("pick_error.flag"), nil, "and its flag is removed")
  love.touchpressed(98, 5, 5, 0, 0, 1)
  love.touchreleased(98, 5, 5, 0, 0, 1)
end

-- 3. a copy left by a picker the app was closed during is taken at start
do
  love.filesystem.write("picked_rom.gb", "junk again")
  local again = require("src.coop.launcher.Launcher").new(function() end, {})
  for _ = 1, 3 do again:update(1 / 60) end
  check(again.menu.notice and again.menu.notice:find("1 MiB", 1, true) ~= nil,
    "a new launcher imports a copy waiting in the save folder")
  eq(love.filesystem.getInfo("picked_rom.gb"), nil, "and removes it")
  Launcher.current = l
end

-- 4. a save and a mod come through the picker too
do
  ready.red = true
  l.readyCache = {}
  l.menu:openSaves("red")
  local imported
  l.menu.saves.importSav = function(file) imported = file.read() return false, "test" end
  check(tap(l, "import"), "SAVES has IMPORT .SAV")
  eq(l.menu.saves.screen, "import", "which opens its import screen")
  check(tap(l, "pick"), "with a button that chooses the file")
  eq(picks[#picks], "sav", "the picker opens for a save")
  love.filesystem.write("picked_save.sav", string.rep("\0", 32768))
  frames(2)
  eq(imported and #imported, 32768, "the picked save is imported")
  eq(love.filesystem.getInfo("picked_save.sav"), nil, "and its copy removed")
  l.menu.saves.notice = nil
  -- EXPORT hands the .sav to the system's "save as" screen
  -- (love.system.createFile copies pending_export.sav where the player picks
  -- and leaves export_done.flag)
  local created = {}
  love.system.createFile = function(name) created[#created + 1] = name return true end
  local saves = l.menu.saves
  saves:go("list")
  saves.saves = {
    listSlots = function() return { { id = "s1", exists = true, name = "ASH", meta = {} } } end,
    activeSlot = function() return "s1" end,
  }
  local rel = "exports/red/gen1recomp-red-s1.sav"
  love.filesystem.write(rel, "SRAM")
  saves.exportSlot = function() return true, love.filesystem.getSaveDirectory() .. "/" .. rel end
  check(texts(l):find("EXPORT asks where to put the file", 1, true) ~= nil,
    "SAVES says an export asks where the file goes")
  check(tap(l, "export"), "SAVES has EXPORT on the slot")
  eq(created[1], "gen1recomp-red-s1.sav", "it opens the system's save-as screen with the file's name")
  eq(love.filesystem.read("pending_export.sav"), "SRAM", "with the exported bytes staged")
  eq(saves.notice, nil, "and no message yet")
  love.filesystem.write("export_done.flag", "ok")
  frames(2)
  check(saves.notice and saves.notice:find("ASH", 1, true) ~= nil,
    "once the copy is written the page says so (" .. tostring(saves.notice) .. ")")
  eq(love.filesystem.getInfo("export_done.flag"), nil, "the flag is removed")
  eq(love.filesystem.getInfo("pending_export.sav"), nil, "and so is the staged copy")
  saves.notice = nil
  love.system.createFile = nil
  check(tap(l, "export"), "without the save-as screen (an older app)")
  check(saves.notice and saves.notice:find(rel, 1, true) ~= nil,
    "the page names the file in the app's folder, as on a desktop")
  saves.notice = nil
  l.menu:openTab("settings")
  l.menu:openMods("red")
  local installed
  l._installModZip = function(_, data) installed = data end
  check(tap(l, "install"), "MODS has INSTALL")
  check(tap(l, "pick"), "its install screen has a button that chooses the file")
  eq(picks[#picks], "mod", "the picker opens for a mod's .zip")
  love.filesystem.write("picked_mod.zip", "PK-zip")
  frames(2)
  eq(installed, "PK-zip", "the picked .zip is installed")
  eq(love.filesystem.getInfo("picked_mod.zip"), nil, "and its copy removed")
end

-- 5. a finger drag scrolls a long page and presses nothing; a tap presses
-- (the phone turned on its side: SETTINGS is longer than the screen)
do
  love.graphics.getDimensions = function() return 2400, 1080 end
  l.menu:openTab("settings")
  l.ui = { scroll = 0 }
  frames(1)
  local page = l:_page()
  check((page.maxScroll or 0) > 0, "SETTINGS is longer than a phone's screen on its side ("
    .. tostring(page.maxScroll) .. ")")
  local screen = l.menu.screen
  love.touchpressed(50, 1200, 900, 0, 0, 1)
  for i = 1, 10 do love.touchmoved(50, 1200, 900 - i * 60, 0, -60, 1) end
  love.touchreleased(50, 1200, 300, 0, 0, 1)
  check((l.ui.scroll or 0) > 0, "dragging up scrolls the page down (" .. tostring(l.ui.scroll) .. ")")
  eq(l.menu.screen, screen, "and presses nothing")
  local scrolled = l.ui.scroll
  love.touchpressed(51, 1200, 300, 0, 0, 1)
  for i = 1, 5 do love.touchmoved(51, 1200, 300 + i * 60, 0, 60, 1) end
  love.touchreleased(51, 1200, 600, 0, 0, 1)
  check(l.ui.scroll < scrolled, "dragging down scrolls back")
  l.ui.scroll = 0
  local x, y = target(l, "tab:play")
  love.touchpressed(52, x, y, 0, 0, 1)
  love.touchmoved(52, x + 3, y + 2, 3, 2, 1)
  love.touchreleased(52, x + 3, y + 2, 0, 0, 1)
  eq(l.menu.screen, "play", "a tap that wobbles a little still presses")
end

-- 6. SETTINGS has the on-screen controls on a phone: their layout opens
-- upstream's touch-controls editor and their look its skin studio (both
-- GPL, src/ui), each over the parked launcher, and each closes back to it
do
  love.graphics.getDimensions = function() return 1080, 2400 end
  l.menu:openTab("settings")
  l.ui = { scroll = 0 }
  frames(1)
  check(texts(l):find("ON-SCREEN CONTROLS", 1, true) ~= nil, "SETTINGS has the on-screen controls")
  check(tap(l, "touch_layout"), "with LAYOUT")
  frames(2)
  local Editor = package.loaded["src.ui.TouchControlsEditor"]
  check(Editor ~= nil and Editor.onClose ~= nil, "which opens the touch-controls editor")
  if Editor and Editor.onClose then Editor.onClose() end
  frames(2)
  eq(Launcher.current, l, "its close comes back to the same launcher")
  eq(l.menu.screen, "settings", "on SETTINGS")
  check(tap(l, "touch_skin"), "with SKIN")
  frames(2)
  local Studio = package.loaded["src.ui.SkinStudio"]
  check(Studio ~= nil and Studio.onClose ~= nil, "which opens the skin studio")
  if Studio and Studio.onClose then Studio.onClose() end
  frames(2)
  eq(Launcher.current, l, "its close comes back to the same launcher")
  eq(l.menu.screen, "settings", "on SETTINGS")
end

T.finish()
