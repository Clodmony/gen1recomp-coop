-- The fork's boot path (#3): main.lua starts the fork's own launcher and
-- never loads upstream's proprietary launcher (LICENSE.MD term 2, AGENTS.md),
-- on a fresh start, a shortcut, a scripted import, a game boot from the
-- launcher (fixture dataset) and the return to the launcher.  Headless.
--   luajit tests/coop/launcher_boot_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

-- upstream's launcher (LICENSE.MD term 2), the launcher UI built on it (Box
-- panels) and the splash and theme videos that play assets/launcher files
local FORBIDDEN = {
  "src.import.LauncherView", "src.import.LauncherSettings",
  "src.import.OnlinePanel", "src.import.CartLabelArt", "src.import.CartShape",
  "src.mods.LauncherMods", "src.import.RomImporter",
  "src.import.LauncherSplash", "src.import.LauncherThemeVideo",
  "src.import.BoxPanel", "src.import.BoxUI",
}

local function launcherModulesLoaded()
  local found = {}
  for _, name in ipairs(FORBIDDEN) do
    if package.loaded[name] ~= nil then found[#found + 1] = name end
  end
  for name in pairs(package.loaded) do
    if name:find("^src%.import%.online%.") then found[#found + 1] = name end
  end
  table.sort(found)
  return table.concat(found, ", ")
end

local function noLauncherModules(when)
  eq(launcherModulesLoaded(), "", "no upstream launcher module loaded " .. when)
end

-- environment the test controls: the fixture dataset, optional overrides
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
local Menu = require("src.coop.launcher.Menu")
local ready = {}
RomImport.isReady = function(v) return ready[v] == true end

local function frames(n)
  for _ = 1, n or 1 do
    love.update(1 / 60)
    love.draw()
  end
end

-- every string the launcher draws in one frame
local function drawnText()
  love.draw()
  return Launcher.current and Launcher.current.page and Launcher.current.page:texts() or {}
end

local function showsCredit()
  local joined = table.concat(drawnText(), " "):gsub("%s", "")
  return joined:find(Menu.CREDIT:gsub("%s", ""), 1, true) ~= nil
end

-- the window position of the page target for the model row `id` (`game`
-- for a cartridge), or of the target with `key`
local function target(l, id, game)
  local page = l:_page()
  local model = require("src.coop.launcher.Screens").model(l.menu)
  for _, n in ipairs(page:targets()) do
    local act = n.act or {}
    local row = act.kind == "row" and model:items()[act.index]
    if (row and row.id == id and (game == nil or row.game == game)) or n.key == id then
      local scale, ox, oy = l:_layout()
      return ox + (n.x + n.w / 2) * scale, oy + (n.y + n.h / 2) * scale
    end
  end
  error("no target " .. tostring(id))
end

local function click(l, id, game, button)
  local x, y = target(l, id, game)
  love.mousepressed(x, y, button or 1, false)
end

-- 1. fresh start: the fork's launcher, credit on screen
do
  love.load({})
  frames(3)
  noLauncherModules("on a fresh start")
  local l = Launcher.current
  check(l ~= nil, "a fresh start opens the fork's launcher")
  if not l then T.finish() end
  eq(l.menu.screen, "play", "on PLAY")
  check(showsCredit(), "PLAY shows the credit line")
  eq(l.ui.focus, "row:1", "the focus starts on the first cartridge")
  love.keypressed("up")
  check(tostring(l.ui.focus):find("^tab:"), "up from the cartridges reaches the tabs")
  for _ = 1, 6 do love.keypressed("right") end
  love.keypressed("left")
  eq(l.ui.focus, "tab:help", "the arrows walk the tabs")
  love.keypressed("return")
  eq(l.menu.screen, "help", "the keyboard opens HELP")
  check(showsCredit(), "HELP shows the credit line")
  love.keypressed("x")
  eq(l.menu.screen, "play", "X goes back to PLAY")
  local pad = { isGamepad = function() return true end }
  love.gamepadpressed(pad, "dpright")
  love.gamepadpressed(pad, "a")
  eq(l.menu.version, "blue", "a pad picks Blue")
  local x, y = target(l, "import")
  love.mousemoved(x, y, 0, 0, false)
  love.keypressed("return")
  eq(l.menu.screen, "import", "IMPORT ROM opens the import screen")
  check(showsCredit(), "which shows the credit line")
  love.textinput("/no/such/rom.gb")
  eq(l.menu.path, "/no/such/rom.gb", "the path is typed")
  love.keypressed("return")
  check(l.menu.notice ~= nil and l.menu.notice:find("Could not open", 1, true) ~= nil,
    "a missing file is reported")
  check(showsCredit(), "the message keeps the credit line on screen")
  love.keypressed("return")
  love.keypressed("escape")
  eq(l.menu.screen, "play", "Escape goes back to PLAY")
  noLauncherModules("after using the launcher")
end

-- 2. the key that opens the path field is not typed into it
do
  local l = Launcher.current
  local x, y = target(l, "import")
  love.mousemoved(x, y, 0, 0, false)
  love.keypressed("z")
  love.textinput("z")
  eq(l.menu.screen, "import", "Z opens Blue's import screen")
  eq(l.menu.path, "", "and its text event is dropped")
  love.update(1 / 60)
  love.textinput("z")
  eq(l.menu.path, "z", "later typing goes in")
  love.keypressed("escape")
end

-- 2b. mouse, wheel and file drop
do
  local l = Launcher.current
  local x, y = target(l, "cart", "yellow")
  love.mousemoved(x, y, 0, 0, false)
  eq(l.menu:items()[l.menu.cursor].game, "yellow", "hovering a cartridge moves the cursor to it")
  love.mousepressed(x, y, 1, false)
  eq(l.menu.version, "yellow", "clicking it picks it")
  click(l, "import")
  eq(l.menu.screen, "import", "clicking IMPORT ROM opens the import screen")
  love.mousepressed(x, y, 2, false)
  eq(l.menu.screen, "play", "a right click goes back")
  click(l, "tab:help")
  eq(l.menu.screen, "help", "clicking a tab opens it")
  love.wheelmoved(0, -1)
  check(l.ui.scroll >= 0, "the wheel scrolls a page (no further than its end)")
  click(l, "tab:play")
  local junk = {
    open = function() return true end, close = function() end,
    getSize = function() return 4 end, read = function() return "junk" end,
    getFilename = function() return "/somewhere/junk.gb" end,
  }
  love.filedropped(junk)
  check(l.menu.notice and l.menu.notice:find("1 MiB", 1, true) ~= nil,
    "a dropped file that is no Game Boy ROM is refused")
  love.keypressed("return")
  eq(l.menu.notice, nil, "the message closes")
  noLauncherModules("after mouse and drop input")
end

-- 3. a game boots from the launcher (fixture dataset)
do
  ready.red = true
  local l = Launcher.current
  l.readyCache = {}
  click(l, "cart", "red")
  click(l, "solo")
  eq(l.menu.screen, "solo", "PLAY SOLO on an imported Red opens the solo sheet")
  love.keypressed("return")
  eq(l.booted, "red", "NEW GAME boots Red")
  eq(Launcher.current, nil, "the launcher is gone")
  frames(5)
  check(package.loaded["src.core.Game"] ~= nil, "the game is running")
  noLauncherModules("after booting a game from the launcher")
end

-- 4. closing the game returns to the fork's launcher (in process)
do
  local HostShell = require("src.core.HostShell")
  local savedCan = HostShell.canRestart
  HostShell.canRestart = function() return false end
  local blocked = love.quit()
  HostShell.canRestart = savedCan
  check(blocked == true, "closing the game window does not quit")
  frames(2)
  check(Launcher.current ~= nil, "it returns to the fork's launcher")
  check(showsCredit(), "which shows the credit line")
  noLauncherModules("after returning from a game")
end

-- 5. a restart into the launcher (the relaunch marker)
do
  Launcher.current = nil
  love.filesystem.write("relaunch_to_launcher.txt", "return { tab = \"yellow\" }\n")
  love.load({})
  frames(2)
  local l = Launcher.current
  check(l ~= nil, "a restart opens the fork's launcher")
  eq(l and l.menu.version, "yellow", "on the game it came from")
  noLauncherModules("after a restart")
end

-- 6. a shortcut to a game with no ROM opens the launcher on that game
do
  Launcher.current = nil
  ready = {}
  env.POKEPORT_GAME = "blue"
  love.load({})
  env.POKEPORT_GAME = false
  frames(2)
  local l = Launcher.current
  check(l ~= nil, "a shortcut to a game with no ROM opens the fork's launcher")
  eq(l and l.menu.version, "blue", "on Blue")
  noLauncherModules("on a shortcut")
end

-- 7. a scripted import (POKEPORT_IMPORT_ROM) runs through the fork's launcher
do
  Launcher.current = nil
  env.POKEPORT_IMPORT_ROM = "/no/such/rom.gb"
  love.load({})
  env.POKEPORT_IMPORT_ROM = false
  local l = Launcher.current
  check(l ~= nil and l.bootOnImport, "a scripted import uses the fork's launcher")
  check(l and l.menu.notice and l.menu.notice:find("Could not open", 1, true) ~= nil,
    "and reports the missing file")
  noLauncherModules("on a scripted import")
end

T.finish()
