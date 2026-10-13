-- A frame driver (POKEPORT_DRIVER) that boots a game from the launcher (#28):
-- main.lua resumes the driver with the launcher, the driver boots Red, and
-- the frame must finish without touching the launcher it just closed.
-- Headless, fixture dataset.
--   luajit tests/coop/driver_launcher_boot_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local env = {
  POKEPORT_DATA_DIR = "tests/fixture_data",
  POKEPORT_DRIVER = "tests/coop/_driver_boot_from_launcher.lua",
}
local realGetenv = os.getenv
os.getenv = function(k)
  if env[k] ~= nil then return env[k] or nil end
  return realGetenv(k)
end

-- a driver error or end quits the program; record it instead
local quits = {}
love.event = love.event or {}
love.event.quit = function(code) quits[#quits + 1] = code or 0 end
local driverErrors = {}
local realPrint = print
print = function(...)
  local line = table.concat({ ... }, " ")
  if line:find("driver error", 1, true) then driverErrors[#driverErrors + 1] = line end
  realPrint(...)
end

_G.arg = {}
dofile("main.lua")

local Launcher = require("src.coop.launcher.Launcher")
require("src.coop.launcher.RomImport").isReady = function(v) return v == "red" end

-- a driver runs on the launcher only after a restart into it (the marker)
love.filesystem.write("relaunch_to_launcher.txt", "return { tab = \"red\" }\n")
love.load({})
check(Launcher.current ~= nil, "the restart opens the fork's launcher")

local ok, err = pcall(love.update, 1 / 60)
check(ok, "the frame the driver boots a game in finishes: " .. tostring(err))
eq(Launcher.current, nil, "the launcher is gone")
check(package.loaded["src.core.Game"] ~= nil, "the game is running")

-- until the driver ends (the stub's quit does not stop the loop)
for _ = 1, 10 do
  ok, err = pcall(love.update, 1 / 60)
  if not ok or #quits > 0 then break end
end
check(ok, "the game frames run: " .. tostring(err))
eq(table.concat(driverErrors, "; "), "", "no driver error")
eq(quits[1], 0, "the driver ends normally")

T.finish()
