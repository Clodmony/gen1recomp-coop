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

-- 8. CONTROLS (#4): a rebind lands in options.lua, a pad claim in the
-- launcher's settings, both through the real event callbacks
do
  Launcher.current = nil
  love.filesystem.remove("options.lua")
  love.filesystem.remove("coop/launcher.json")
  local Seats = require("src.coop.game.Seats")
  local SaveData = require("src.core.SaveData")
  SaveData.invalidateOptionsCache()
  Seats.reset()
  local padB = { getGUID = function() return "guid-b" end, getName = function() return "Pad B" end,
                 isGamepad = function() return true end }
  love.joystick = { getJoysticks = function() return { padB } end,
                    getJoystickCount = function() return 1 end }
  love.load({})
  frames(2)
  local l = Launcher.current
  l.menu:openTab("controls")
  frames(1)
  check(table.concat(drawnText(), " "):find("CONNECTED PADS PAD B", 1, true), "CONTROLS lists the connected pad")
  click(l, "bind")  -- the first bind row: UP
  check(l.menu:capturing() ~= nil, "a click on UP waits for a press")
  love.keypressed("i")
  eq(l.menu:capturing(), nil, "the key ends the capture")
  eq((SaveData.loadOptions().bindings or {}).up and SaveData.loadOptions().bindings.up.key, "i",
    "options.lua binds UP to I, where the game reads it")
  love.keypressed("down")  -- the arrows walk again
  eq(l.menu:capturing(), nil, "a key after the capture is a launcher key again")
  -- player 2 claims the pad with A on it
  local seatRow
  for i, r in ipairs(l.menu:items()) do if r.id == "seat" and r.player == 2 then seatRow = i end end
  l.menu.cursor = seatRow
  l:_run(l.menu:press("a"))
  check(l.menu:capturing() ~= nil, "player 2's row waits for a press")
  love.gamepadpressed(padB, "b")
  eq(l.menu:capturing(), nil, "B on the pad cancels")
  l:_run(l.menu:press("a"))
  love.gamepadpressed(padB, "a")
  eq(l.menu:capturing(), nil, "A on the pad claims it")
  local CoopSettings = require("src.coop.launcher.CoopSettings")
  local saved = CoopSettings.load(love.filesystem)
  eq(saved.seats[2] and saved.seats[2].guid, "guid-b", "the claim is in coop/launcher.json")
  eq(saved.seats[1], false, "player 1 has none")
  eq(Seats.devices[2] and Seats.devices[2].guid, "guid-b", "and Seats knows it")
  check(table.concat(drawnText(), " "):find("PAD B", 1, true), "the page shows the pad as player 2's")
  love.gamepadpressed(padB, "dpdown")
  eq(l.menu:capturing(), nil, "the pad drives the launcher again")
  -- a click beside the rows cancels a capture
  click(l, "bind")
  love.mousepressed(1, 1, 1, false)
  eq(l.menu:capturing(), nil, "a click elsewhere cancels")
  love.joystick = nil
  Seats.reset()
  love.filesystem.remove("options.lua")
  love.filesystem.remove("coop/launcher.json")
  SaveData.invalidateOptionsCache()
end

-- 9. SETTINGS (#5): the game's options set on the page are the ones the
-- booted game applies
do
  Launcher.current = nil
  love.filesystem.remove("options.lua")
  local SaveData = require("src.core.SaveData")
  SaveData.invalidateOptionsCache()
  ready = { red = true }
  love.load({})
  frames(2)
  local l = Launcher.current
  l.menu:openTab("settings")
  frames(1)
  local function rowIndex(id)
    for i, r in ipairs(l.menu:items()) do if r.id == id then return i end end
    error("no row " .. id)
  end
  -- the lower rows sit under the fold at this size: the focus walks there
  -- (the page scrolls to it) and the keys act through the real callbacks
  local function focusRow(id)
    l.menu.cursor = rowIndex(id)
    l.ui.focus = "row:" .. rowIndex(id)
    l.ui.cursor = l.menu.cursor
    frames(1)
  end
  click(l, "scale")
  eq(l.menu:items()[rowIndex("scale")].detail, "1X", "a click on INTEGER SCALE moves it on")
  focusRow("textSpeed")
  love.keypressed("return")
  eq(l.menu:items()[rowIndex("textSpeed")].detail, "SLOW", "Enter on TEXT SPEED moves it on")
  focusRow("music")
  love.keypressed("left")
  love.keypressed("left")
  eq(l.menu:items()[rowIndex("music")].detail, "5", "left steps MUSIC down twice")
  focusRow("animations")
  love.keypressed("right")
  focusRow("battleStyle")
  love.keypressed("z")
  focusRow("scale")
  local pad = { isGamepad = function() return true end }
  love.gamepadpressed(pad, "a")
  local shown = {}
  for _, r in ipairs(l.menu:items()) do if r.option then shown[#shown + 1] = r.id .. "=" .. r.detail end end
  eq(table.concat(shown, " "), "window=WINDOWED scale=2X music=5 sound=7 textSpeed=SLOW animations=OFF battleStyle=SET",
    "the page shows what was set")
  local o = SaveData.loadOptions()
  eq(o.textSpeed .. "/" .. tostring(o.animations) .. "/" .. o.battleStyle .. "/" .. o.musicVol .. "/" .. o.faithfulRes,
    "5/false/set/5/2", "options.lua holds the game's keys")
  -- boot Red from the launcher: the game applies these very options
  l.menu:openTab("play")
  l.menu:select("red")
  l:_run({ kind = "boot", version = "red", newGame = false })
  frames(3)
  local Game = package.loaded["src.core.Game"]
  check(Game and Game.save and Game.save.options, "the game booted with options")
  local go = Game and Game.save and Game.save.options or {}
  eq(go.textSpeed, 5, "the game's text speed is SLOW")
  eq(go.animations, false, "battle animations are off")
  eq(go.battleStyle, "set", "the battle style is SET")
  eq(go.musicVol, 5, "the music volume is 5")
  eq(go.faithfulRes, 2, "the integer scale is 2X")
  love.quit()
  frames(2)
  love.filesystem.remove("options.lua")
  SaveData.invalidateOptionsCache()
end

-- 10. SAVES (#6): a .sav dropped on the launcher lands in a new slot of the
-- picked game, PLAY boots it, EXPORT writes a .sav, DELETE asks first
do
  Launcher.current = nil
  local SaveData = require("src.core.SaveData")
  local SaveConvert = require("src.save_convert.SaveConvert")
  local G1 = require("tests.fixtures.save.gen1_build")
  -- the codec's crosswalk from the fixture dataset (no ROM cache here)
  local stub = {}
  for _, name in ipairs({ "pokemon", "moves", "items", "maps", "encounters", "field",
                          "text_pointers", "trainer_headers", "tilesets" }) do
    local chunk = loadfile("tests/fixture_data/" .. name .. ".lua")
    if chunk then stub[name] = chunk() end
  end
  SaveConvert.setGen1DataStub(stub, "red")
  love.filesystem.remove("options.lua")
  SaveData.invalidateOptionsCache()
  SaveData.resetSlotState()
  ready = { red = true }
  love.load({})
  frames(2)
  local l = Launcher.current
  l.menu:select("red")
  local bytes = G1.build({ player = "BRIO", badges = 0x07 })
  local dropped = { open = function() return true end, getSize = function() return #bytes end,
                    read = function() return bytes end, close = function() end,
                    getFilename = function() return "/tmp/brio.sav" end }
  love.filedropped(dropped)
  frames(1)
  eq(l.menu.screen, "saves", "a dropped .sav opens the SAVES page of the picked game")
  check(l.menu:currentNotice() and l.menu:currentNotice():find("BRIO", 1, true), "and says what came in")
  love.keypressed("return")
  local slots = l.menu.saves:details().slots
  eq(#slots, 1, "one slot")
  eq(slots[1].name .. "/" .. tostring(slots[1].active), "BRIO/true", "the imported save, active")
  check(table.concat(drawnText(), " "):find("BRIO", 1, true), "the page shows it")
  -- EXPORT
  click(l, "export", nil)
  check(l.menu:currentNotice() and l.menu:currentNotice():find("exports/red/gen1recomp%-red%-" .. slots[1].id .. "%.sav"),
    "EXPORT names the file: " .. tostring(l.menu:currentNotice()))
  check(love.filesystem.read("exports/red/gen1recomp-red-" .. slots[1].id .. ".sav") ~= nil, "and wrote it")
  love.keypressed("return")
  -- DELETE asks, B says no
  click(l, "delete", nil)
  eq(l.menu.saves.screen, "delete", "DELETE asks first")
  love.keypressed("x")
  eq(l.menu.saves.screen, "list", "B keeps the save")
  eq(#l.menu.saves:details().slots, 1, "still there")
  -- PLAY boots the game on the slot (the game itself booted twice above; a
  -- third boot in one process trips the mod registry, so the boot is
  -- recorded and the save the game would load is read instead)
  local booted
  l.onBoot = function(version) booted = version end
  click(l, "play", nil)
  eq(booted, "red", "PLAY boots Red")
  eq(SaveData.activeSlot("red"), slots[1].id, "on the imported slot")
  local loaded = SaveData.load("red")
  eq(loaded and loaded.player and loaded.player.name, "BRIO", "whose save the game loads")
  Launcher.current = nil
  SaveConvert.setGen1DataStub(nil)
  love.filesystem.remove("options.lua")
  SaveData.invalidateOptionsCache()
end

T.finish()
