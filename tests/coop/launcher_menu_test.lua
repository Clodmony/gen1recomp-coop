-- The fork's launcher menu model (#3): screens, cursor, commands, the credit
-- line and ROM identification, ROM-free.
--   luajit tests/coop/launcher_menu_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Menu = require("src.coop.launcher.Menu")

local function ids(menu)
  local out = {}
  for _, row in ipairs(menu:items()) do out[#out + 1] = row.id end
  return table.concat(out, ",")
end

local function newMenu(opts)
  opts = opts or {}
  return Menu.new({
    ready = function(v) return (opts.ready or {})[v] == true end,
    saveInfo = function(v) return (opts.saves or {})[v] end,
    canQuit = opts.canQuit, canType = opts.canType, initial = opts.initial,
  })
end

-- the credit line is the licence's text, word for word
eq(Menu.CREDIT, "Based on the Pokemon Gen 1 Recompilation Project by BOIS CLUB "
  .. "GAMES, LLC (https://github.com/bryanthaboi/gen1recomp)",
  "credit line matches LICENSE.MD term 1")
do
  local found = false
  for _, para in ipairs(Menu.CREDITS) do
    if para == Menu.CREDIT then found = true end
  end
  check(found, "the credits screen carries the credit line")
  local lines = Menu.wrap(Menu.CREDIT, 20)
  eq(#lines, 6, "credit line fits the 6-row footer at 20 columns")
  for _, line in ipairs(lines) do check(#line <= 20, "footer line fits: " .. line) end
  eq(table.concat(lines):gsub(" ", ""), Menu.CREDIT:gsub(" ", ""),
    "wrapping keeps every character of the credit line")
end

-- title screen
do
  local m = newMenu({ ready = { red = true } })
  eq(ids(m), "red,blue,yellow,credits,quit", "title lists the three games, credits, quit")
  eq(m:items()[1].detail, nil, "an imported game shows no NO ROM")
  eq(m:items()[2].detail, "NO ROM", "a game without a ROM says so")
  eq(ids(newMenu({ canQuit = false })), "red,blue,yellow,credits", "no QUIT on mobile")
  eq(newMenu({ initial = "yellow" }).cursor, 3, "initial game is preselected")
  m:press("up")
  eq(m.cursor, 5, "cursor wraps from the top to QUIT")
  m:press("down")
  eq(m.cursor, 1, "and back")
  m.cursor = 5
  eq(m:press("a").kind, "quit", "QUIT asks the host to quit")
  m.cursor = 4
  m:press("a")
  eq(m.screen, "credits", "CREDITS opens the credits")
  m:press("b")
  eq(m.screen, "title", "B leaves the credits")
  eq(m.cursor, 4, "back on CREDITS")
end

-- a game with no ROM: the import screen takes a path
do
  local m = newMenu()
  m.cursor = 2
  m:press("a")
  eq(m.screen, "import", "a game without a ROM opens the import screen")
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
  eq(m.screen, "title", "B goes back to the title")
  eq(m.cursor, 2, "with the game still selected")
  m:text("ignored")
  eq(m.path, "/roms/Blue x.gb", "typing outside the import screen is ignored")
end

-- an imported game: continue or start
do
  local m = newMenu({ ready = { red = true } })
  m:press("a")
  eq(m.screen, "game", "an imported game opens its game screen")
  eq(ids(m), "new,reimport,back", "no CONTINUE without a save")
  local cmd = m:press("a")
  eq(cmd and cmd.kind, "boot", "NEW GAME boots")
  eq(cmd and cmd.newGame, false, "without a save, NEW GAME needs no new slot")
  m.cursor = 2
  m:press("a")
  eq(m.screen, "import", "NEW ROM opens the import screen for that game")
  eq(m.version, "red", "for Red")
end
do
  local m = newMenu({ ready = { red = true }, saves = { red = { name = "ASH", badges = 2, time = "3:04" } } })
  m:press("a")
  eq(ids(m), "continue,new,reimport,back", "a save adds CONTINUE first")
  local cmd = m:press("a")
  eq(cmd and cmd.kind .. ":" .. cmd.version, "boot:red", "CONTINUE boots Red")
  eq(cmd and cmd.newGame, false, "CONTINUE keeps the save")
  m:press("down")
  cmd = m:press("a")
  eq(cmd and cmd.newGame, true, "NEW GAME over a save asks for a new slot")
  m:press("b")
  eq(m.screen, "title", "B leaves the game screen")
  m:press("a")
  m.cursor = 4
  m:press("a")
  eq(m.screen, "title", "BACK leaves the game screen")
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
  eq(m.screen, "game", "a finished import opens the game screen")
  eq(m.version, "yellow", "for Yellow")
  check(m.notice ~= nil, "and says it is ready")
end

-- wrap
do
  local lines = Menu.wrap("aaaaaaaaaaaaaaaaaaaaaaaaa bb", 10)
  eq(table.concat(lines, "|"), "aaaaaaaaaa|aaaaaaaaaa|aaaaa bb", "a long word is split")
  eq(#Menu.wrap("", 10), 1, "empty text is one empty line")
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
  GameVersion.forSha1 = function() return "blue" end
  local version, bytes, label, hash = RomImport.identify(("x"):rep(1024 * 1024), "x.gb")
  eq(version, "blue", "a known Gen 1 ROM is named by its SHA-1")
  eq(#bytes, 1024 * 1024, "its bytes are returned")
  eq(label, "x.gb", "with its name")
  eq(hash, "abc123", "and its SHA-1")
  love.data, GameVersion.forSha1 = savedData, savedFor
end

T.finish()
