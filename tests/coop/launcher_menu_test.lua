-- The fork's launcher menu model (#3, laid out anew in #38): tabs, the
-- cartridge pick, solo, the import screen, settings, the credit line and ROM
-- identification, ROM-free.
--   luajit tests/coop/launcher_menu_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Menu = require("src.coop.launcher.Menu")
local Text = require("src.coop.launcher.Text")
Text.set("en")

local function ids(menu)
  local out = {}
  for _, row in ipairs(menu:items()) do out[#out + 1] = row.id end
  return table.concat(out, ",")
end

local function pick(menu, id, game)
  for i, row in ipairs(menu:items()) do
    if row.id == id and (game == nil or row.game == game) then
      menu.cursor = i
      return menu:press("a")
    end
  end
  error("no row " .. id)
end

local function row(menu, id)
  for _, r in ipairs(menu:items()) do if r.id == id then return r end end
  return nil
end

local function fakeSettings()
  local s = { saved = 0 }
  function s:save() self.saved = self.saved + 1 end
  function s:picked(v) self.pick = v end
  return s
end

local function newMenu(opts)
  opts = opts or {}
  return Menu.new({
    ready = function(v) return (opts.ready or {})[v] == true end,
    saveInfo = function(v) return (opts.saves or {})[v] end,
    canQuit = opts.canQuit, canType = opts.canType, initial = opts.initial,
    coop = opts.coop, settings = opts.settings or fakeSettings(),
    canOpenLogs = opts.canOpenLogs,
  })
end

-- the credit line is the licence's text, word for word, in every language
eq(Menu.CREDIT, "Based on the Pokemon Gen 1 Recompilation Project by BOIS CLUB "
  .. "GAMES, LLC (https://github.com/bryanthaboi/gen1recomp)",
  "credit line matches LICENSE.MD term 1")
for _, lang in ipairs({ "en", "de" }) do
  Text.set(lang)
  eq(Menu.credits()[1], Menu.CREDIT, "the HELP tab's credits start with the credit line (" .. lang .. ")")
end
Text.set("en")

-- PLAY: the five cartridges, solo, the three ways to play together
do
  local m = newMenu({ ready = { red = true } })
  eq(m.screen, "play", "the launcher opens on PLAY")
  eq(ids(m), "cart,cart,cart,cart,cart,solo,host,join,couch",
    "five cartridges (German Red and Blue too, #25), solo, host, join, couch co-op")
  eq(m.version, "red", "Red is picked by default")
  eq(m:items()[1].detail, "Ready", "an imported cartridge says so")
  eq(m:items()[2].detail, "Import ROM", "a cartridge without a ROM says so")
  eq(row(m, "couch").enabled, false, "couch co-op is planned, not offered (#4, #11)")
  eq(row(m, "host").enabled, false, "no hosting without the co-op screens")
  eq(newMenu({ initial = "yellow" }).version, "yellow", "the initial game is picked")
  pick(m, "cart", "blue")
  eq(m.version, "blue", "A on a cartridge picks it")
  eq(m.settings.pick, "blue", "and the pick is remembered")
  eq(ids(m), "cart,cart,cart,cart,cart,solo,host,join,couch,import",
    "a cartridge without a ROM adds IMPORT ROM")
  eq(row(m, "solo").enabled, false, "and cannot be played solo")
  m.cursor = 1
  m:press("up")
  eq(m:items()[m.cursor].id, "import", "the cursor wraps from the top to the last row")
  m:press("down")
  eq(m.cursor, 1, "and back")
end

-- a cartridge with no ROM: the import screen takes a path
do
  local m = newMenu()
  pick(m, "cart", "blue")
  pick(m, "import")
  eq(m.screen, "import", "IMPORT ROM opens the import screen")
  eq(m.version, "blue", "for that game")
  eq(m:press("a"), nil, "an empty path does nothing")
  m:text("/roms/Blue é")
  m:erase()
  eq(m.path, "/roms/Blue ", "erase removes a whole UTF-8 character")
  m:text("x.gb")
  local cmd = m:press("a")
  eq(cmd and cmd.kind, "import", "A on a path asks the host to import")
  eq(cmd and cmd.path, "/roms/Blue x.gb", "with the typed path")
  m:press("b")
  eq(m.screen, "play", "B goes back to PLAY")
  eq(m:items()[m.cursor].game, "blue", "with the cartridge under the cursor")
  m:text("ignored")
  eq(m.path, "/roms/Blue x.gb", "typing outside the import screen is ignored")
end

-- solo: continue or start
do
  local m = newMenu({ ready = { red = true } })
  pick(m, "solo")
  eq(m.screen, "solo", "PLAY SOLO opens the solo sheet")
  eq(ids(m), "new,reimport,back", "no CONTINUE without a save")
  local cmd = pick(m, "new")
  eq(cmd and cmd.kind, "boot", "NEW GAME boots")
  eq(cmd and cmd.newGame, false, "without a save, NEW GAME needs no new slot")
  pick(m, "reimport")
  eq(m.screen, "import", "IMPORT AGAIN opens the import screen for that game")
  eq(m.version, "red", "for Red")
end
do
  local m = newMenu({ ready = { red = true }, saves = { red = { name = "ASH", badges = 2, time = "3:04" } } })
  pick(m, "solo")
  eq(ids(m), "continue,new,reimport,back", "a save adds CONTINUE first")
  local cmd = pick(m, "continue")
  eq(cmd and cmd.kind .. ":" .. cmd.version, "boot:red", "CONTINUE boots Red")
  eq(cmd and cmd.newGame, false, "CONTINUE keeps the save")
  cmd = pick(m, "new")
  eq(cmd and cmd.newGame, true, "NEW GAME over a save asks for a new slot")
  m:press("b")
  eq(m.screen, "play", "B leaves the solo sheet")
  eq(m:items()[m.cursor].id, "solo", "back on PLAY SOLO")
  pick(m, "solo")
  pick(m, "back")
  eq(m.screen, "play", "BACK leaves it too")
end

-- tabs
do
  local m = newMenu({ ready = { red = true }, canOpenLogs = true })
  check(m:isTop(), "PLAY is a tab's page")
  m:openTab("settings")
  eq(m.screen, "settings", "the SETTINGS tab")
  eq(ids(m), "language,theme", "language and colours")
  eq(m:items()[1].detail, "ENGLISH", "the language shows")
  local cmd = pick(m, "language")
  eq(cmd and cmd.kind, "settings", "a changed setting tells the launcher")
  eq(Text.language, "de", "LANGUAGE switches to German")
  eq(m.settings.language, "de", "and is kept")
  eq(m:items()[1].label, "SPRACHE", "the menu is German at once")
  pick(m, "language")
  eq(Text.language, "en", "and back to English")
  pick(m, "theme")
  eq(m.settings.theme, "dark", "THEME switches to dark")
  m:openTab("help")
  eq(ids(m), "share,open", "HELP: the log-sharing switch and the logs folder")
  eq(m:items()[1].detail, "ON", "sharing is on by default")
  pick(m, "share")
  eq(m.settings.shareLogs, false, "and switches off")
  eq(pick(m, "open").kind, "open_logs", "OPEN LOGS FOLDER asks the launcher")
  m:openTab("controls")
  eq(ids(m), "", "CONTROLS has nothing to choose")
  m:press("b")
  eq(m.screen, "play", "B on a tab goes back to PLAY")
  eq(m.tab, "play", "and the PLAY tab")
  local nolog = newMenu({})
  nolog:openTab("help")
  eq(ids(nolog), "share", "no OPEN LOGS FOLDER where it cannot open (a phone)")
end

-- import progress and messages
do
  local ready = {}
  local m = Menu.new({ ready = function(v) return ready[v] == true end })
  m:importStarted("yellow", "y.gb")
  eq(m.screen, "importing", "an import shows its progress")
  eq(m:press("b"), nil, "buttons wait while importing")
  eq(m.screen, "importing", "and do not leave it")
  m:importProgress(0.5, "Maps")
  eq(m.importing.progress, 0.5, "progress is tracked")
  m:importFailed("bad")
  eq(m.screen, "import", "a failed first import goes back to the import screen")
  eq(m.notice, "bad", "with the reason")
  m:press("down")
  eq(m.notice, "bad", "a direction does not close a message")
  m:press("a")
  eq(m.notice, nil, "A closes it")
  m:importStarted("yellow", "y.gb")
  ready.yellow = true
  m:importDone("yellow")
  eq(m.screen, "play", "a finished import goes to PLAY")
  eq(m.version, "yellow", "with Yellow picked")
  eq(m:items()[m.cursor].id, "solo", "on PLAY SOLO")
  check(m.notice ~= nil, "and says it is ready")
end

-- ROM identification (no ROM: the hash and the version lookup are stubbed)
do
  local RomImport = require("src.coop.launcher.RomImport")
  local GameVersion = require("src.core.GameVersion")
  local savedData, savedFor = love.data, GameVersion.forSha1
  love.data = {
    hash = function() return "digest" end,
    encode = function() return "abc123" end,
  }
  local v, msg = RomImport.identify(("x"):rep(1000), "x.gb")
  eq(v, nil, "a wrong-sized file is refused")
  check(tostring(msg):find("1 MiB", 1, true) ~= nil, "with the expected size")
  GameVersion.forSha1 = function() return nil end
  v, msg = RomImport.identify(("x"):rep(1024 * 1024), "x.gb")
  check(v == nil and tostring(msg):find("abc123", 1, true) ~= nil,
    "an unknown ROM is refused with its SHA-1")
  GameVersion.forSha1 = function() return "gold" end
  v, msg = RomImport.identify(("x"):rep(1024 * 1024), "x.gb")
  check(v == nil and tostring(msg):find("Red, Blue and Yellow", 1, true) ~= nil,
    "a non-Gen 1 game is refused")
  Text.set("de")
  v, msg = RomImport.identify(("x"):rep(1024 * 1024), "x.gb")
  check(v == nil and tostring(msg):find("Rot, Blau und Gelb", 1, true) ~= nil,
    "and the reason is German in a German launcher (#41)")
  Text.set("en")
  GameVersion.forSha1 = function() return "blue" end
  local version, bytes, label, hash = RomImport.identify(("x"):rep(1024 * 1024), "x.gb")
  eq(version, "blue", "a known Gen 1 ROM is named by its SHA-1")
  eq(#bytes, 1024 * 1024, "its bytes are returned")
  eq(label, "x.gb", "with its name")
  eq(hash, "abc123", "and its SHA-1")
  love.data, GameVersion.forSha1 = savedData, savedFor
end

T.finish()
