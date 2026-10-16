-- The launcher's MODS page (#30, design G34), ROM-free, with the stand-in
-- fixture mod (tests/coop/fixtures/mod_standin) in a memory save folder:
-- SETTINGS > MODS lists the installed mods of the picked game with what
-- they declare; ON/OFF is the flag the game's mod loader reads at boot; a
-- mod's folder or .zip installs into mods/<id>/ (an installed copy is
-- replaced); a mod's optional file is checked and stored in its folder.
-- Upstream's launcher (LauncherMods) is never loaded.
--   luajit tests/coop/launcher_mods_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")
local Text = require("src.coop.launcher.Text")
Text.set("en")
local Installed = require("src.coop.mods.Installed")
local Mods = require("src.coop.launcher.Mods")
local Menu = require("src.coop.launcher.Menu")
local Screens = require("src.coop.launcher.Screens")

local FIXTURE = "tests/coop/fixtures/mod_standin/"
local function readFile(path)
  local f = assert(io.open(path, "rb"))
  local text = f:read("*a")
  f:close()
  return text
end
local MANIFEST, MAIN = readFile(FIXTURE .. "manifest.json"), readFile(FIXTURE .. "main.lua")

-- a save folder in memory, as love.filesystem
local function memfs(files)
  local fs = { files = files }
  fs.write = function(path, content) files[path] = content return true end
  fs.read = function(path) return files[path] end
  fs.remove = function(path)
    files[path] = nil
    return true
  end
  fs.getInfo = function(path)
    if files[path] then return { type = "file", size = #files[path] } end
    local prefix = path .. "/"
    for key in pairs(files) do
      if key:sub(1, #prefix) == prefix then return { type = "directory" } end
    end
    return nil
  end
  fs.getDirectoryItems = function(path)
    local seen, items = {}, {}
    local prefix = path .. "/"
    for key in pairs(files) do
      if key:sub(1, #prefix) == prefix then
        local child = key:sub(#prefix + 1):match("^[^/]+")
        if child and not seen[child] then
          seen[child] = true
          items[#items + 1] = child
        end
      end
    end
    table.sort(items)
    return items
  end
  fs.createDirectory = function() return true end
  fs.getSaveDirectory = function() return "/fake/save" end
  fs.load = function(path)
    if not files[path] then return nil, "no file" end
    return load(files[path], "@" .. path)
  end
  return fs
end

local files = {
  ["mods/COOP_STANDIN/manifest.json"] = MANIFEST,
  ["mods/COOP_STANDIN/main.lua"] = MAIN,
}
local fs = memfs(files)
love.filesystem = fs
SaveData.invalidateOptionsCache()
GameVersion.set("red")

-- the installed mods ------------------------------------------------------

local list = Installed.list("red", fs)
eq(#list, 1, "one mod installed")
local m = list[1] or {}
eq(m.id, "COOP_STANDIN", "the stand-in")
eq(m.version, "1.0.0", "its version")
eq(m.enabled, true, "on by default, as the loader has it")
eq(m.engine, true, "it patches engine code (engine_internals)")
eq(m.link, false, "and does not change link play")
eq(m.imports[1] and m.imports[1].id, "standin_rom", "its optional file")
eq(m.imports[1] and m.imports[1].present, false, "not imported yet")

-- SETTINGS > MODS -----------------------------------------------------------

local menu = Menu.new({
  ready = function() return true end,
  mods = function(v) return Mods.new({ version = v }) end,
})
menu:openTab("settings")
local at
for i, r in ipairs(menu:items()) do if r.id == "mods" then at = i end end
check(at ~= nil, "SETTINGS has a MODS row")
eq(at and menu:items()[at].detail, "RED →", "for the picked game")
menu.cursor = at
menu:press("a")
eq(menu.screen, "mods", "which opens the MODS page")
local page = Screens.build(menu, { scroll = 0 }, { w = 480, h = 400 })
local texts = table.concat(page:texts(), " | ")
check(texts:find("Mods for RED", 1, true), "headed with the game")
check(texts:find("Co-op stand-in graphics mod · 1.0.0", 1, true), "a card with the mod's name and version")
check(texts:find("PATCHES ENGINE CODE", 1, true), "and what it declares")
check(texts:find("Optional: Stand-in optional ROM · NOT IMPORTED", 1, true), "and its optional file")
check(texts:find("+ INSTALL MOD", 1, true), "with + INSTALL MOD")
check(texts:find("Based on the Pokemon Gen 1 Recompilation Project", 1, true), "under the credit line")

-- ON/OFF: the flag the game's loader reads
local rows = menu:items()
eq(rows[1].id .. ":" .. rows[1].label, "toggle:ON", "the mod's row says ON")
menu.mods.cursor = 1 -- the page's own cursor (Screens follows it)
menu:press("a")
eq(menu:items()[1].label, "OFF", "a press turns it OFF")
SaveData.invalidateOptionsCache()
local options = SaveData.loadOptions(fs)
eq(SaveData.modEnabled(options, "COOP_STANDIN", SaveData.modScope("red")), false,
   "written to options.lua for this game")
local Loader = require("src.mods.Loader")
local loader = Loader.new({ fs = fs, generation = 1 })
loader:load(require("tests.modkit").fixtures.fresh())
eq(loader.mods.COOP_STANDIN and loader.mods.COOP_STANDIN.state, "disabled",
   "and the game's mod loader leaves it off")
menu:press("a")
eq(menu:items()[1].label, "ON", "a second press turns it back ON")

-- + INSTALL MOD: a typed path asks the launcher to install it
local installAt
for i, r in ipairs(menu:items()) do if r.id == "install" then installAt = i end end
menu.mods.cursor = installAt
menu:press("a")
eq(menu.mods.screen, "install", "+ INSTALL MOD opens the install screen")
menu:text("/somewhere/mod.zip")
local command = menu:press("a")
eq(command and command.kind, "install_mod", "ENTER asks the launcher to install the typed path")
eq(command and command.path, "/somewhere/mod.zip", "with the path")
menu:press("b")
eq(menu.mods.screen, "list", "B goes back to the list")

-- installing: a repository's .zip holds the mod in one folder ---------------

local function tree(entries)
  local t = memfs(entries)
  return {
    items = function(rel) return t.getDirectoryItems(rel == "" and "." or ("./" .. rel)) end,
    kind = function(rel)
      local info = t.getInfo("./" .. rel)
      return info and info.type or nil
    end,
    read = function(rel) return entries["./" .. rel] end,
  }
end
local second = MANIFEST:gsub('"COOP_STANDIN"', '"COOP_SECOND"'):gsub('"1.0.0"', '"2.0.0"')
local manifest, err = Installed.install(tree({
  ["./Second-main/manifest.json"] = second,
  ["./Second-main/main.lua"] = MAIN,
  ["./Second-main/lib/extra.lua"] = "return 1",
  ["./Second-main/.git/HEAD"] = "ref: x",
}), fs)
eq(manifest and manifest.id, "COOP_SECOND", "a mod in its repository folder installs: " .. tostring(err))
eq(files["mods/COOP_SECOND/lib/extra.lua"], "return 1", "every file goes to mods/<id>/")
eq(files["mods/COOP_SECOND/.git/HEAD"], nil, "a .git folder stays behind")
eq(#Installed.list("red", fs), 2, "the list has two mods")
manifest = Installed.install(tree({
  ["./manifest.json"] = second,
  ["./main.lua"] = MAIN,
}), fs)
eq(manifest and manifest.id, "COOP_SECOND", "a mod at the top of the .zip installs too")
eq(files["mods/COOP_SECOND/lib/extra.lua"], nil, "an installed copy is replaced")
local none, why = Installed.install(tree({ ["./readme.txt"] = "hi" }), fs)
eq(none, nil, "a .zip with no manifest is refused")
check(tostring(why):find("manifest.json", 1, true), "saying why")
local bad = MANIFEST:gsub('"COOP_STANDIN"', '"../escape"')
eq((Installed.install(tree({ ["./manifest.json"] = bad, ["./main.lua"] = MAIN }), fs)), nil,
   "an id that is no folder name is refused")

-- the install's answer on the page
menu.mods:done(true, "Installed COOP_SECOND 2.0.0. It runs when the game starts.")
eq(#menu.mods.mods, 2, "the page reads the mods again")
eq(menu:currentNotice(), "Installed COOP_SECOND 2.0.0. It runs when the game starts.",
   "and says what happened")
menu:press("a")

-- the optional file -------------------------------------------------------

local optionalAt
for i, r in ipairs(menu:items()) do
  if r.id == "optional" and r.mod == "COOP_STANDIN" then optionalAt = i end
end
check(optionalAt ~= nil, "IMPORT FILE for the stand-in's optional file")
menu.mods.cursor = optionalAt
menu:press("a")
eq(menu.mods.screen, "import", "which opens the import screen")
local mod, imp = menu.mods:pendingImport()
eq(mod and mod.id, "COOP_STANDIN", "for the mod")
eq(imp and imp.id, "standin_rom", "and its file")
local ZERO = ("0"):rep(32)
local function hash(data) return data == "standin-rom" and ZERO or ("f"):rep(32) end
local ok, detail = Installed.importOptional("COOP_STANDIN", "standin_rom", "wrong", fs, hash)
eq(ok, nil, "a file of another MD5 is refused")
check(tostring(detail):find("MD5", 1, true), "saying so")
ok = Installed.importOptional("COOP_STANDIN", "standin_rom", "standin-rom", fs, hash)
eq(ok, true, "the right file is taken")
eq(files["mods/COOP_STANDIN/baseroms/baserom.bin"], "standin-rom", "into the mod's baseroms/")
local again = Installed.list("red", fs)
eq(again[2] and again[2].id .. ":" .. tostring(again[2].imports[1].present), "COOP_STANDIN:true",
   "and the list shows it imported")

-- upstream's launcher stays out
eq(package.loaded["src.mods.LauncherMods"], nil, "LauncherMods was never loaded")
eq(package.loaded["src.import.RomImporter"], nil, "nor upstream's importer")

T.finish()
