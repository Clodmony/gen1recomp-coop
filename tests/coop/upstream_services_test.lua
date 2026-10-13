-- The fork's boot path never reaches upstream's services (#26): no self-update
-- check or payload chainload (src/update), no cloud sync (src/sync), even for a
-- device linked in upstream's launcher and a shortcut that asks for both; and
-- the fork keeps its saves under its own identity, not upstream's.  Headless.
--   luajit tests/coop/upstream_services_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local env = { POKEPORT_DATA_DIR = "tests/fixture_data" }
local realGetenv = os.getenv
os.getenv = function(k)
  if env[k] ~= nil then return env[k] or nil end
  return realGetenv(k)
end

-- spies on every way into upstream's updater and sync server
local calls = {}
local function count(name) calls[name] = (calls[name] or 0) + 1 end
local function noCalls(when)
  local seen = {}
  for name, n in pairs(calls) do seen[#seen + 1] = name .. "=" .. n end
  table.sort(seen)
  eq(table.concat(seen, ", "), "", "no updater or sync call " .. when)
  calls = {}
end

-- as a packaged build (a dev checkout never updates itself)
require("src.core.Version").isDev = function() return false end
local Boot = require("src.update.Boot")
Boot.run = function() count("Boot.run"); return false end
Boot.canUpdateInPlace = function() return true end
local Check = require("src.update.Check")
Check.start = function() count("Check.start") end
Check.download = function() count("Check.download") end
Check.state = function() return { status = "checking" } end
-- a device linked in upstream's launcher: an enabled, linked engine
local SyncEngine = require("src.sync.SyncEngine")
local linked = {
  state = { enabled = true }, phase = "idle",
  linked = function() return true end,
  busy = function() return false end,
  syncNow = function() count("syncNow") end,
  update = function() count("sync update") end,
  noteResumed = function() count("noteResumed") end,
  noteSaveWritten = function() count("noteSaveWritten") end,
  protectPlaythrough = function() end,
}
SyncEngine.new = function() count("SyncEngine.new"); return linked end
SyncEngine._shared = nil

_G.arg = {}
dofile("main.lua")

local Launcher = require("src.coop.launcher.Launcher")
require("src.coop.launcher.RomImport").isReady = function(v) return v == "red" end

local function frames(n)
  for _ = 1, n or 1 do
    love.update(1 / 60)
    love.draw()
  end
end

-- 1. a fresh start, a game booted from the launcher; the game's save, focus
--    and resume hooks all ask Game:syncEngine
do
  love.load({})
  frames(2)
  check(Launcher.current ~= nil, "a fresh start opens the fork's launcher")
  Launcher.current:_boot("red")
  frames(5)
  local Game = package.loaded["src.core.Game"]
  check(Game ~= nil, "Red is running")
  Game:focus(true)
  Game:onResume()
  Game:updateSync(1 / 60)
  eq(Game:syncEngine(), nil, "the game has no sync engine")
  frames(2)
  noCalls("on a fresh start and a game from the launcher")

  local HostShell = require("src.core.HostShell")
  local savedCan = HostShell.canRestart
  HostShell.canRestart = function() return false end
  love.quit()
  HostShell.canRestart = savedCan
  frames(2)
  check(Launcher.current ~= nil, "closing the game returns to the launcher")
end

-- 2. a shortcut that asks for an update check and a sync before the game
do
  Launcher.current = nil
  env.POKEPORT_GAME = "red"
  love.load({ "--update", "--sync" })
  env.POKEPORT_GAME = false
  frames(5)
  eq(Launcher.current, nil, "the shortcut boots Red without the launcher")
  local Game = package.loaded["src.core.Game"]
  check(Game ~= nil and Game.save ~= nil, "Red is running")
  noCalls("on a shortcut that asks for an update and a sync")
end

-- 3. the fork's own save folder (conf.lua)
do
  local function identity(argv, idEnv)
    env.POKEPORT_IDENTITY = idEnv or false
    _G.arg = argv
    love.filesystem.setSymlinksEnabled = love.filesystem.setSymlinksEnabled
      or function() end
    dofile("conf.lua")
    local t = { window = {}, modules = {}, audio = {} }
    love.conf(t)
    env.POKEPORT_IDENTITY = false
    return t.identity
  end
  eq(identity({}), "gen1recomp-coop", "the game saves under the fork's identity")
  eq(identity({ "--editor" }), "gen1recomp-coop", "the save editor reads the same folder")
  eq(identity({ "--display-companion=4000,abc" }), "gen1recomp-coop-companion",
    "the second display has its own folder too")
  eq(identity({}, "mod-dev"), "mod-dev", "POKEPORT_IDENTITY still overrides it")
end

T.finish()
