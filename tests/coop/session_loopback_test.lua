-- The co-op session core over loopback (#10): two split-screen seats and a
-- third player join one in-process host, move, change maps, leave and
-- rejoin; another protocol version and another cartridge are refused with
-- a reason; the host shuts down cleanly.  ROM-free.
--   luajit tests/coop/session_loopback_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Transport = require("src.coop.session.Transport")
local Protocol = require("src.coop.session.Protocol")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")

local SHA_RED = ("ab"):rep(20)
local SHA_OTHER = ("cd"):rep(20)
local CAMPAIGN = "c0123456789abcdef"

local clock = 0
local idCounter = 0
local function newHost()
  clock = 0
  return Host.new({
    campaign = { id = CAMPAIGN, title = "RED CO-OP" },
    cartridge = { game = "red", sha1 = SHA_RED },
    hostName = "HOST", build = "test",
    clock = function() return clock end,
    hex = function(n)
      idCounter = idCounter + 1
      return ("%0" .. n .. "x"):format(idCounter)
    end,
  })
end

local function pump(host, clients, frames)
  for _ = 1, frames or 3 do
    for _, c in ipairs(clients) do c:update() end
    host:update()
    for _, c in ipairs(clients) do c:update() end
  end
end

local function seat(hub, name, opts)
  opts = opts or {}
  return Client.new(hub:dial(), {
    name = name, game = opts.game or "red", sha1 = opts.sha1 or SHA_RED,
    device = opts.device or "d1", seat = opts.seat or 1, known = opts.known,
    build = "test",
  })
end

local function lastRejection(c)
  local r = c.rejections[#c.rejections]
  return r and r.reason
end

-- two split-screen seats join the in-process host -------------------------
local host = newHost()
local hub = host:serve(Transport.loopback())
local red = seat(hub, "RED", { seat = 1 })
local green = seat(hub, "GREEN", { seat = 2 })
red:join(); green:join()
pump(host, { red, green })
eq(red.status, "joined", "seat 1 joins over loopback")
eq(green.status, "joined", "seat 2 joins over loopback")
check(red.player and green.player and red.player ~= green.player,
  "the two seats are two players")
eq(#host.players, 2, "the host holds two players")
eq(red.known[CAMPAIGN], red.player, "seat 1 remembers its player for the campaign")
eq(#red.state.players, 2, "the state lists both players")
eq(host:player(green.player).seat, 2, "the host records the seat")

-- moving and changing maps --------------------------------------------------
red:move("PALLET_TOWN", 5, 6, "down", true)
green:move("PALLET_TOWN", 8, 6, "left", true)
pump(host, { red, green })
local seen = red:playerView(green.player)
eq(seen and seen.map, "PALLET_TOWN", "seat 1 sees seat 2's map")
eq(seen and seen.x, 8, "seat 1 sees seat 2's cell")
eq(red.state.nearby[1], green.player, "players on one map are nearby")

red:move("PALLET_TOWN", 5, 7, "down", false)
pump(host, { red, green })
eq(green:playerView(red.player).y, 7, "a one-cell step is taken")
red:move("PALLET_TOWN", 5, 9, "down", false)
pump(host, { red, green })
eq(green:playerView(red.player).y, 9, "a two-cell ledge hop is taken")

red:move("PALLET_TOWN", 5, 12, "down", false)
pump(host, { red, green })
eq(lastRejection(red), "bad_step", "a three-cell jump without a warp is refused")
eq(green:playerView(red.player).y, 9, "a refused step changes nothing")

red:move("ROUTE_1", 5, 35, "up", false)
pump(host, { red, green })
eq(lastRejection(red), "bad_step", "another map without a warp is refused")

red:move("ROUTE_1", 5, 35, "up", true)
pump(host, { red, green })
eq(green:playerView(red.player).map, "ROUTE_1", "a reported warp changes the map")
eq(#green.state.nearby, 0, "players on two maps are not nearby")

-- sequence numbers ----------------------------------------------------------
local before = #red.rejections
red.conn:send({ type = "move", seq = red.seq, map = "ROUTE_1", x = 5, y = 34,
                facing = "up", warp = false, travel = "walk" })
pump(host, { red, green })
eq(#red.rejections, before + 1, "a repeated number is answered")
eq(lastRejection(red), "duplicate", "a repeated number is refused as duplicate")
eq(green:playerView(red.player).y, 35, "a duplicate changes nothing")

-- an intention before hello ------------------------------------------------
local early = hub:dial()
early:send({ type = "move", seq = 1, map = "ROUTE_1", x = 1, y = 1,
             facing = "up", warp = true, travel = "walk" })
pump(host, { red, green })
local got = early:poll()
eq(got[1] and got[1].reason, "hello_first", "a move before hello is refused")
eq(#host.players, 2, "and creates nobody")
early:close()

-- leaving and rejoining -----------------------------------------------------
local greenId, greenSeq = green.player, green.seq
local greenKnown = { [CAMPAIGN] = greenId }
green:leave()
pump(host, { red })
eq(red:playerView(greenId).connected, false, "the others see a player leave")
eq(host:player(greenId).map, "PALLET_TOWN", "a player who left keeps the position")

local back = seat(hub, "GREEN", { seat = 2, known = greenKnown })
back:join()
pump(host, { red, back })
eq(back.player, greenId, "a remembered player rejoins as themselves")
eq(back.seq, greenSeq + 1, "the welcome continues the sequence (the bye was one)")
eq(red:playerView(greenId).connected, true, "the others see the rejoin")
back:move("PALLET_TOWN", 8, 7, "down", false)
pump(host, { red, back })
eq(red:playerView(greenId).y, 7, "the rejoined player moves on")

-- a dropped link leaves like a bye
back.conn:close()
pump(host, { red })
eq(red:playerView(greenId).connected, false, "a dropped link leaves the player")

-- a device that lost its id is recognised by name
local byName = seat(hub, "GREEN", { seat = 2 })
byName:join()
pump(host, { red, byName })
eq(byName.player, greenId, "the same name gets the same player back")

-- a second window that remembers a connected player is someone new
local twin = seat(hub, "GREEN", { device = "d2", known = { [CAMPAIGN] = greenId } })
twin:join()
pump(host, { red, byName, twin })
eq(twin.status, "joined", "a second window joins")
check(twin.player ~= greenId, "a second window of a connected player is someone new")
eq(#host.players, 3, "three players now")

-- a second window of the same device and seat, while the first is still
-- there: the host makes sure of the first link (HOLD seconds), then the
-- second window is someone new (A1.9).  A host of its own.
do
  local saved = clock
  local h = newHost()
  local hb = h:serve(Transport.loopback())
  local first = seat(hb, "GREEN", { seat = 2 })
  first:join()
  pump(h, { first })
  local id = first.player
  local same = seat(hb, "GREEN", { seat = 2, known = { [CAMPAIGN] = id } })
  same:join()
  pump(h, { first, same })
  eq(same.status, "joining", "its hello waits while the first window's link is made sure of")
  clock = clock + Host.HOLD + 0.1
  pump(h, { first, same })
  eq(same.status, "joined", "then it joins")
  check(same.player ~= id, "as someone new: the first window is still there")
  eq(first.status, "joined", "and the first window keeps its player")
  clock = saved
end

-- probe: the lobby view, nobody created ------------------------------------
local prober = seat(hub, "GREEN", { known = { [CAMPAIGN] = greenId } })
twin:leave()
pump(host, { red, byName })
prober:probe()
pump(host, { red, byName, prober })
eq(prober.status, "probed", "a probe is answered")
eq(prober.lobby.campaign, CAMPAIGN, "the probe names the campaign")
eq(prober.lobby.refused, "", "a fitting device is not refused")
eq(#prober.lobby.players, 3, "the probe lists the players")
eq(prober.lobby.you.player, nil, "a remembered player who is connected is not offered")
eq(#host.players, 3, "a probe creates nobody")
local proberTwin = seat(hub, "X", { known = { [CAMPAIGN] = twin.player } })
proberTwin:probe()
pump(host, { red, proberTwin })
eq(proberTwin.lobby.you.player, twin.player, "the probe says whom this device gets back")
prober.conn:close(); proberTwin.conn:close()

-- another protocol version: refused with the reason, then dropped ----------
local old = hub:dial()
old:send({ type = "probe", protocol = Protocol.VERSION + 1, odd = true })
old:send({ type = "hello", protocol = Protocol.VERSION + 1, name = "OLD" })
pump(host, { red })
got = old:poll()
eq(got[1] and got[1].refused, "protocol_mismatch", "a probe of another version is told")
eq(got[2] and got[2].type, "rejected", "a hello of another version is rejected")
eq(got[2] and got[2].reason, "protocol_mismatch", "with protocol_mismatch")
eq(got[2] and got[2].seq, -1, "as a refused hello")
check(not old.closed, "the link stays for the grace")
clock = clock + Host.GRACE + 0.1
pump(host, { red })
check(old.closed, "then the link is dropped")
eq(#host.players, 3, "nobody was created")

-- another cartridge -------------------------------------------------------
local blue = seat(hub, "BLUE", { game = "blue", sha1 = SHA_OTHER })
blue:probe()
pump(host, { red, blue })
eq(blue.lobby.refused, "content_mismatch", "a probe finds the cartridge mismatch")
blue:join()
pump(host, { red, blue })
eq(blue.status, "refused", "a hello with another cartridge is refused")
eq(blue.reason, "content_mismatch", "with content_mismatch")
local redOther = seat(hub, "RED2", { sha1 = SHA_OTHER })
redOther:join()
pump(host, { red, redOther })
eq(redOther.reason, "content_mismatch", "the same game from another dump is refused")
clock = clock + Host.GRACE + 0.1
pump(host, { red, blue, redOther })
eq(blue.status, "refused", "the refusal stays readable after the drop")
eq(#host.players, 3, "nobody was created")

-- size limits -------------------------------------------------------------
do
  local a = Transport.loopback()
  local c = a:dial()
  local s = a:accept()[1]
  local big = ("x"):rep(Protocol.MAX_MESSAGE - 64)
  check(c:send({ type = "blob", data = big }), "a message near 2 MiB is sent")
  local m = s:poll()[1]
  eq(m and #m.data, #big, "and arrives whole")
  check(not c:send({ type = "blob", data = big .. ("y"):rep(128) }),
    "a message over 2 MiB is not sent")
  c:sendRaw(("z"):rep(Protocol.MAX_MESSAGE + 1))
  eq(#s:poll(), 0, "an oversized wire text is dropped")
  eq(s.dropped, 1, "and counted")
end

-- shutdown ----------------------------------------------------------------
host:shutdown("host_quit")
pump(host, { red, byName })
eq(red.status, "ended", "clients are told the session ended")
eq(red.reason, "host_quit", "with the reason")
eq(host.status, "ended", "the host closes once everyone has left")
local late = seat(hub, "LATE")
late:join()
pump(host, { late })
eq(late.status, "closed", "nobody joins a closed host")

T.finish()
