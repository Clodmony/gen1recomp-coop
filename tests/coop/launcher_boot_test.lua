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
  local saved, out = Launcher._text, {}
  Launcher._text = function(self, text, col, row)
    out[#out + 1] = text
    return saved(self, text, col, row)
  end
  love.draw()
  Launcher._text = saved
  return out
end

local function showsCredit()
  local joined = table.concat(drawnText(), " "):gsub("%s", "")
  return joined:find(Menu.CREDIT:gsub("%s", ""), 1, true) ~= nil
end

-- 1. fresh start: the fork's launcher, credit on screen
do
  love.load({})
  frames(3)
  noLauncherModules("on a fresh start")
  local l = Launcher.current
  check(l ~= nil, "a fresh start opens the fork's launcher")
  if not l then T.finish() end
  eq(l.menu.screen, "title", "on its title screen")
  check(showsCredit(), "the title screen shows the credit line")
  -- past every game row to CREDITS
  for _ = 1, #require("src.coop.launcher.Menu").GAMES do love.keypressed("down") end
  love.keypressed("return")
  eq(l.menu.screen, "credits", "keyboard reaches CREDITS")
  check(showsCredit(), "the credits screen shows the credit line")
  love.keypressed("x")
  love.gamepadpressed({ isGamepad = function() return true end }, "dpup")
  love.gamepadpressed({ isGamepad = function() return true end }, "dpup")
  love.gamepadpressed({ isGamepad = function() return true end }, "dpup")
  love.gamepadpressed({ isGamepad = function() return true end }, "a")
  eq(l.menu.screen, "import", "a pad picks Red, which has no ROM yet")
  love.textinput("/no/such/rom.gb")
  eq(l.menu.path, "/no/such/rom.gb", "the path is typed")
  love.keypressed("return")
  check(l.menu.notice ~= nil and l.menu.notice:find("Could not open", 1, true) ~= nil,
    "a missing file is reported")
  love.keypressed("return")
  love.keypressed("escape")
  eq(l.menu.screen, "title", "Escape goes back to the title")
  noLauncherModules("after using the launcher")
end

-- 2. the key that opens the path field is not typed into it
do
  local l = Launcher.current
  l.menu.cursor = 2
  love.keypressed("z")
  love.textinput("z")
  eq(l.menu.screen, "import", "Z opens Blue's import screen")
  eq(l.menu.path, "", "and its text event is dropped")
  love.update(1 / 60)
  love.textinput("z")
  eq(l.menu.path, "z", "later typing goes in")
  love.keypressed("escape")
end

-- 2b. mouse and file drop
do
  local l = Launcher.current
  local scale, ox, oy = l:_layout()
  -- the row of the second item (BLUE): text row 4, in Game Boy pixels
  local x, y = ox + 40 * scale, oy + (4 * 8 + 4) * scale
  love.mousemoved(x, y, 0, 0, false)
  eq(l.menu.cursor, 2, "hovering a row moves the cursor to it")
  love.mousepressed(x, y, 1, false)
  eq(l.menu.screen, "import", "clicking BLUE opens its import screen")
  love.mousepressed(x, y, 2, false)
  eq(l.menu.screen, "title", "a right click goes back")
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
  l.menu.cursor = 1
  love.keypressed("return")
  eq(l.menu.screen, "game", "an imported Red opens its game screen")
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
  eq(l and l.menu.cursor, 3, "on the game it came from")
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
  eq(l and l.menu.cursor, 2, "on Blue")
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
