-- The launcher's SETTINGS page for the game's options (#5), ROM-free: the
-- defaults when there is no options file, every row's values, a change
-- lands in options.lua where the game reads it (GPL SaveData, the same
-- keys the game's own OPTIONS menu writes), a broken file falls back to
-- the defaults, and the page's rows sit in the menu with the launcher's
-- own LANGUAGE and THEME.
--   luajit tests/coop/game_options_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq
local SaveData = require("src.core.SaveData")
local GameOptions = require("src.coop.launcher.GameOptions")
local Menu = require("src.coop.launcher.Menu")
local Text = require("src.coop.launcher.Text")
Text.set("en")

local function memoryFs()
  local files = {}
  return {
    files = files,
    getInfo = function(name) if files[name] then return { type = "file" } end return nil end,
    read = function(name) return files[name] end,
    write = function(name, text) files[name] = text return true end,
    remove = function(name) files[name] = nil return true end,
    createDirectory = function() return true end,
  }
end

local function details(g)
  local out = {}
  for _, r in ipairs(g:rows()) do out[#out + 1] = r.id .. "=" .. r.detail end
  return table.concat(out, " ")
end

local function row(g, id)
  for _, r in ipairs(g:rows()) do if r.id == id then return r end end
  error("no row " .. id)
end

-- 1. defaults, no file ------------------------------------------------------
do
  local fs = memoryFs()
  local g = GameOptions.new({ fs = fs })
  eq(details(g), "window=WINDOWED scale=OFF music=7 sound=7 textSpeed=MEDIUM animations=ON battleStyle=SHIFT",
    "the defaults are the game's (SaveData.defaultOptions)")
  eq(fs.files["options.lua"], nil, "reading writes nothing")
end

-- 2. every row steps, A cycles, and each change lands in options.lua -------
do
  local fs = memoryFs()
  local g = GameOptions.new({ fs = fs })
  g:step(row(g, "textSpeed"), 1)
  eq(row(g, "textSpeed").detail, "SLOW", "TEXT SPEED steps to SLOW")
  eq(SaveData.loadOptions(fs).textSpeed, 5, "and options.lua says 5, as the game reads it")
  g:step(row(g, "textSpeed"), 1)
  eq(row(g, "textSpeed").detail, "FAST", "and wraps to FAST")
  eq(SaveData.loadOptions(fs).textSpeed, 1, "options.lua says 1")
  g:step(row(g, "textSpeed"), -1)
  eq(row(g, "textSpeed").detail, "SLOW", "left wraps back")
  g:step(row(g, "animations"), 1)
  eq(row(g, "animations").detail, "OFF", "BATTLE ANIMATION switches off")
  eq(SaveData.loadOptions(fs).animations, false, "as `animations = false`")
  g:step(row(g, "battleStyle"), 1)
  eq(row(g, "battleStyle").detail, "SET", "BATTLE STYLE switches to SET")
  eq(SaveData.loadOptions(fs).battleStyle, "set", "as `battleStyle = \"set\"`")
  g:step(row(g, "music"), -1)
  g:step(row(g, "music"), -1)
  eq(row(g, "music").detail, "5", "MUSIC steps down")
  eq(SaveData.loadOptions(fs).musicVol, 5, "as musicVol")
  for _ = 1, 9 do g:step(row(g, "music"), -1) end
  eq(row(g, "music").detail, "OFF", "and stops at OFF, as the game's menu does")
  g:step(row(g, "music"), 1)
  eq(row(g, "music").detail, "1", "up from OFF is 1")
  for _ = 1, 9 do g:step(row(g, "sound"), 1) end
  eq(row(g, "sound").detail, "7", "SOUND stops at 7")
  eq(SaveData.loadOptions(fs).sfxVol, 7, "as sfxVol")
  g:step(row(g, "window"), 1)
  eq(row(g, "window").detail, "BORDERLESS", "WINDOW switches to BORDERLESS")
  eq(SaveData.loadOptions(fs).videoMode, "borderless", "as videoMode")
  g:step(row(g, "scale"), 1)
  eq(row(g, "scale").detail, "1X", "INTEGER SCALE steps to 1X")
  g:step(row(g, "scale"), 1)
  g:step(row(g, "scale"), 1)
  g:step(row(g, "scale"), 1)
  eq(row(g, "scale").detail, "4X", "up to 4X")
  eq(SaveData.loadOptions(fs).faithfulRes, 4, "as faithfulRes")
  g:step(row(g, "scale"), 1)
  eq(row(g, "scale").detail, "OFF", "and wraps to OFF")
  -- the file keeps what it had
  check(fs.files["options.lua"] ~= nil, "options.lua was written")
  eq(SaveData.loadOptions(fs).textSpeed, 5, "earlier changes stay")
  -- a fresh reader sees the same
  eq(details(GameOptions.new({ fs = fs })), "window=BORDERLESS scale=OFF music=1 sound=7 textSpeed=SLOW animations=OFF battleStyle=SET",
    "a new page reads the file back")
end

-- 3. a broken or odd file falls back to the defaults ---------------------
do
  local fs = memoryFs()
  fs.files["options.lua"] = "return { textSpeed = 9, musicVol = 99, videoMode = 'sideways', faithfulRes = -3, battleStyle = 'x' }"
  local g = GameOptions.new({ fs = fs })
  eq(details(g), "window=WINDOWED scale=OFF music=7 sound=7 textSpeed=MEDIUM animations=ON battleStyle=SHIFT",
    "odd values show as the defaults")
  fs.files["options.lua"] = "this is not lua {"
  SaveData.invalidateOptionsCache()
  g = GameOptions.new({ fs = fs })
  eq(row(g, "textSpeed").detail, "MEDIUM", "a file that does not parse shows the defaults")
  g:step(row(g, "textSpeed"), 1)
  eq(SaveData.loadOptions(fs).textSpeed, 5, "and a change writes a good file")
end

-- 4. a fixed display (phone, console) has no WINDOW row ---------------------
do
  local g = GameOptions.new({ fs = memoryFs(), fixedDisplay = true })
  check(details(g):find("window=", 1, true) == nil, "no WINDOW row on a fixed display")
end

-- 5. in the menu: the launcher's rows first, then the game's; A cycles,
-- left and right step ------------------------------------------------------
do
  local fs = memoryFs()
  local settings = { saved = 0, save = function(self) self.saved = self.saved + 1 end }
  local m = Menu.new({ settings = settings, gameOptions = GameOptions.new({ fs = fs }) })
  m:openTab("settings")
  local ids = {}
  for _, r in ipairs(m:items()) do ids[#ids + 1] = r.id end
  eq(table.concat(ids, ","), "language,theme,window,scale,music,sound,textSpeed,animations,battleStyle",
    "LANGUAGE and THEME, then video, audio and game")
  m.cursor = 7
  m:press("a")
  eq(m:items()[7].detail, "SLOW", "A on TEXT SPEED cycles it")
  eq(m:press("right") and false or m:items()[7].detail, "FAST", "right steps it on")
  m:press("left")
  eq(m:items()[7].detail, "SLOW", "left steps it back")
  eq(m.cursor, 7, "left and right do not move the cursor on a game option")
  eq(SaveData.loadOptions(fs).textSpeed, 5, "options.lua follows")
  m.cursor = 1
  m:press("right")
  eq(m.cursor, 2, "right on LANGUAGE still moves the cursor")
  eq(settings.saved, 0, "the game's options never touch the launcher's file")
end

T.finish()
