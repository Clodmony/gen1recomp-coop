-- The co-op development entry's arguments (#10): --coop-host[=PORT],
-- --coop-join=ADDRESS, --coop-name=NAME, --coop-logs=off (#31) and their
-- POKEPORT_COOP_* fallbacks.
--   luajit tests/coop/session_dev_entry_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq
local Dev = require("src.coop.session.Dev")
local Transport = require("src.coop.session.Transport")

local function env(map) return function(k) return map[k] end end
local none = env({})

eq(Dev.parse({ "--developer" }, none), nil, "no co-op argument, no session")
local c = Dev.parse({ "--coop-host" }, none)
eq(c.mode, "host", "--coop-host hosts")
eq(c.port, Transport.DEFAULT_PORT, "on the default port")
eq(c.name, "HOST", "with a default name")
c = Dev.parse({ "--coop-host=25000", "--coop-name=RED" }, none)
eq(c.port, 25000, "--coop-host=PORT picks the port")
eq(c.name, "RED", "--coop-name names the player")
c = Dev.parse({ "--coop-join=192.168.1.20:25000" }, none)
eq(c.mode, "join", "--coop-join joins")
eq(c.address, "192.168.1.20:25000", "the address as typed")
eq(c.name, "GUEST", "with a default name")
c = Dev.parse({ "--coop-join=10.0.0.2", "--coop-name=" .. ("X"):rep(30) }, none)
eq(c.name, "GUEST", "a name over the limit falls back")
c = Dev.parse({}, env({ POKEPORT_COOP_JOIN = "127.0.0.1", POKEPORT_COOP_NAME = "BLUE" }))
eq(c.mode, "join", "POKEPORT_COOP_JOIN joins")
eq(c.name, "BLUE", "POKEPORT_COOP_NAME names")
c = Dev.parse({ "--coop-host=1234" }, env({ POKEPORT_COOP_JOIN = "127.0.0.1" }))
eq(c.mode, "host", "an argument wins over the environment")
eq(c.shareLogs, true, "the session log is shared by default (#31)")
c = Dev.parse({ "--coop-join=10.0.0.2", "--coop-logs=off" }, none)
eq(c.shareLogs, false, "--coop-logs=off keeps it on this device")
c = Dev.parse({ "--coop-host" }, env({ POKEPORT_COOP_LOGS = "0" }))
eq(c.shareLogs, false, "and POKEPORT_COOP_LOGS=0")

-- what a game's position becomes on the wire
local function cell(map, x, y, facing) return { mapId = map, x = x, y = y, facing = facing } end
local m = Dev.nextMove(nil, cell("PALLET_TOWN", 5, 6, "down"))
eq(m and m.warp, true, "the first report is a warp")
local last = m
eq(Dev.nextMove(last, cell("PALLET_TOWN", 5, 6, "down")), nil, "no change, nothing sent")
m = Dev.nextMove(last, cell("PALLET_TOWN", 5, 6, "left"))
eq(m and m.warp, false, "turning on the spot is a move")
m = Dev.nextMove(last, cell("PALLET_TOWN", 5, 7, "down"))
eq(m and m.warp, false, "a step is no warp")
m = Dev.nextMove(last, cell("PALLET_TOWN", 5, 12, "down"))
eq(m and m.warp, true, "a jump on one map is a warp")
-- live check #10: walking from ROUTE_1 (10,35) down into PALLET_TOWN, the
-- overworld showed (10,-1) for a frame, the host dropped it, and the next
-- cell went out without a warp and was refused as bad_step
last = Dev.nextMove(nil, cell("ROUTE_1", 10, 35, "down"))
eq(Dev.nextMove(last, cell("PALLET_TOWN", 10, -1, "down")), nil,
  "a cell off the map during a connection step is not sent")
eq(Dev.nextMove(last, cell("ROUTE_1", 10, 256, "down")), nil, "nor one past the last cell")
m = Dev.nextMove(last, cell("PALLET_TOWN", 10, 0, "down"))
eq(m and m.warp, true, "the settled cell on the next map is the map change")
m = Dev.nextMove(last, cell("ROUTE_1", 10, 35, "down"), true)
eq(m and m.warp, true, "after a refused step the same cell is sent again as a warp")
eq(Dev.nextMove(last, nil), nil, "no overworld, nothing sent")

-- addresses the join side accepts
local h, p = Transport.parseAddress("192.168.1.20")
eq(h .. ":" .. p, "192.168.1.20:" .. Transport.DEFAULT_PORT, "an address without a port")
h, p = Transport.parseAddress(" host.lan:25000 ")
eq(h .. ":" .. p, "host.lan:25000", "a name and a port, trimmed")
h, p = Transport.parseAddress("[fe80::1]:25000")
eq(h .. ":" .. p, "fe80::1:25000", "an IPv6 address in brackets")
eq(Transport.parseAddress("host:70000"), nil, "a port out of range")
eq(Transport.parseAddress(""), nil, "nothing")

T.finish()
