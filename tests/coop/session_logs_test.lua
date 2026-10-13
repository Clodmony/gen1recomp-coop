-- Shared session logs (#31, design A1.14): each device that shares sends its
-- own lines every 2 s in batches of at most 64 KB (a line over 8 KB without
-- its data); the host passes them on once to every other sharing device and
-- keeps a 256 KB backlog for one that joins later; a line passed on is never
-- sent again; a device that does not share sends and gets nothing.  ROM-free,
-- over loopback, on a frame clock.
--   luajit tests/coop/session_logs_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Transport = require("src.coop.session.Transport")
local Protocol = require("src.coop.session.Protocol")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local SessionLog = require("src.coop.session.SessionLog")
local Json = require("src.link.Json")

local SHA = ("cd"):rep(20)
local now = 0
local function clock() return now end

-- one in-memory folder per device; files[path] is a list of lines
local function memFs(files)
  return {
    mkdir = function() end,
    list = function() return {} end,
    size = function() return 0 end,
    remove = function() end,
    open = function(path)
      local lines = {}
      files[path] = lines
      return { write = function(text) lines[#lines + 1] = text end,
               flush = function() end, close = function() end }
    end,
  }
end

local devices = {}
local function device(id, name, share)
  local files = {}
  local log = SessionLog.open({ fs = memFs(files), device = id, name = name, seat = 1,
                                share = share, stamp = "s",
                                clock = function() return math.floor(now * 1000) end })
  local d = { id = id, files = files, log = log, path = log.path }
  devices[id] = d
  return d
end

-- the lines in a device's file, decoded
local function lines(d)
  local out = {}
  for _, text in ipairs(d.files[d.path] or {}) do out[#out + 1] = Json.decode(text) end
  return out
end

local function relayedFrom(d, origin)
  local out = {}
  for _, line in ipairs(lines(d)) do
    if line.relay and line.device == origin then out[#out + 1] = line end
  end
  return out
end

local hostDev = device("aaaa", "HOST", true)
local host = Host.new({ campaign = { id = "c0000000000000001", title = "LOGS" },
                        cartridge = { game = "red", sha1 = SHA }, log = hostDev.log,
                        clock = clock })
local hub = host:serve(Transport.loopback())

local clients = {}
local function join(d, name)
  local c = Client.new(hub:dial(), { name = name, game = "red", sha1 = SHA,
                                     device = d.id, log = d.log, clock = clock })
  c:join()
  clients[#clients + 1] = c
  return c
end

-- one frame of 1/60 s for everyone
local function frame()
  now = now + 1 / 60
  host:update()
  for _, c in ipairs(clients) do c:update() end
end
local function seconds(s) for _ = 1, math.floor(s * 60 + 0.5) do frame() end end

-- the host's own player shares no log (its lines are in the host's)
local own = Client.new(hub:dial(), { name = "HOST", game = "red", sha1 = SHA,
                                     device = hostDev.id, clock = clock })
own:join()
clients[#clients + 1] = own

-- 1. the hello carries whether the link shares
local a, b = device("a1", "ANNA", true), device("b1", "BEN", true)
local ca, cb = join(a, "ANNA"), join(b, "BEN")
seconds(0.1)
eq(ca.status, "joined", "A joined")
eq(cb.status, "joined", "B joined")
local hostLines = table.concat(hostDev.files[hostDev.path], "\n")
check(hostLines:find('"logs":true', 1, true) ~= nil, "the host logs that A and B share")
check(hostLines:find('"logs":false', 1, true) ~= nil, "and that its own player does not")

-- 2. A's and B's lines reach each other through the host, marked relay
a.log:write("client", "probe_a", { step = 1 })
b.log:write("client", "probe_b", { step = 1 })
seconds(2.5)
local function kinds(list)
  local out = {}
  for _, line in ipairs(list) do out[#out + 1] = line.kind end
  return "," .. table.concat(out, ",") .. ","
end
check(kinds(relayedFrom(b, "a1")):find(",probe_a,", 1, true), "A's line reached B")
check(kinds(relayedFrom(a, "b1")):find(",probe_b,", 1, true), "B's line reached A")
check(kinds(relayedFrom(hostDev, "a1")):find(",probe_a,", 1, true),
  "the host keeps A's line in its log")
check(#relayedFrom(b, "aaaa") > 0, "the host's own lines reach B")
eq(#relayedFrom(a, "a1"), 0, "A's lines never come back to A")
local relayMark = relayedFrom(b, "a1")[1].relay
eq(relayMark and relayMark.via, "host", "B notes who passed the lines on")
eq(#relayedFrom(hostDev, "a1") > 0 and relayedFrom(hostDev, "a1")[1].relay.via, ca.player,
  "the host notes the player who sent them")

-- 3. a third device that joins late gets the backlog: A's and B's lines
local c3 = device("c1", "CARL", true)
local cc = join(c3, "CARL")
seconds(0.1)
check(kinds(relayedFrom(c3, "a1")):find(",probe_a,", 1, true), "a late joiner gets A's lines")
check(kinds(relayedFrom(c3, "b1")):find(",probe_b,", 1, true), "and B's")
-- and from then on, live lines
a.log:write("client", "after_c", {})
seconds(2.5)
check(kinds(relayedFrom(c3, "a1")):find(",after_c,", 1, true), "then A's new lines")
eq(#relayedFrom(c3, "c1"), 0, "C's own lines never come back to C")

-- 4. no relayed line is sent on: C's batches hold only C's own lines
do
  local sentBy = {}
  local send = cc.conn.send
  cc.conn.send = function(conn, msg)
    if msg.type == "log" then
      for _, line in ipairs(msg.lines) do sentBy[line.device] = (sentBy[line.device] or 0) + 1 end
    end
    return send(conn, msg)
  end
  c3.log:write("client", "own_c", {})
  seconds(2.5)
  cc.conn.send = send
  check((sentBy.c1 or 0) > 0, "C sends its own lines")
  eq(sentBy.a1 or sentBy.b1 or sentBy.aaaa, nil, "C never sends lines it received")
end
-- a client that forges another device's lines: the host takes none of them
do
  local before = #relayedFrom(b, "a1")
  cc.conn:send({ type = "log", lines = {
    { t = 1, frame = 1, device = "a1", n = 999, src = "client", kind = "forged" } } })
  seconds(2.5)
  eq(#relayedFrom(b, "a1"), before, "a line of another device is not passed on")
  check(not kinds(relayedFrom(b, "a1")):find(",forged,", 1, true), "the forged line is gone")
end

-- 5. size caps: a line over 8 KB goes without its data; a batch is at most
--    64 KB, the rest is counted in a stream_dropped line
do
  local seen = {}
  local send = ca.conn.send
  ca.conn.send = function(conn, msg)
    if msg.type == "log" then seen[#seen + 1] = Json.encode(msg) end
    return send(conn, msg)
  end
  a.log:write("client", "big", { blob = ("x"):rep(20000) })
  for i = 1, 3000 do a.log:write("client", "many", { i = i, pad = ("y"):rep(40) }) end
  seconds(2.5)
  ca.conn.send = send
  eq(#seen, 1, "one batch went out in the interval")
  check(seen[1] and #seen[1] <= SessionLog.BATCH_BYTES + 2048,
    "the batch is at most 64 KB (" .. (seen[1] and #seen[1] or 0) .. " bytes)")
  local batch = Json.decode(seen[1] or "{}")
  local big, dropped
  for _, line in ipairs(batch.lines or {}) do
    if line.kind == "big" then big = line end
    if line.kind == SessionLog.DROPPED then dropped = line end
  end
  check(big and big.data and big.data.omitted_bytes and big.data.omitted_bytes > 20000
    and big.data.blob == nil, "the 20 KB line went without its data")
  check(dropped and dropped.data.lines > 0,
    "the lines that did not fit are counted (" .. tostring(dropped and dropped.data.lines) .. ")")
  local stored = 0
  for _, line in ipairs(lines(a)) do if line.kind == "many" then stored = stored + 1 end end
  eq(stored, 3000, "A's own file keeps every line")
  local bigOnB
  for _, line in ipairs(relayedFrom(b, "a1")) do if line.kind == "big" then bigOnB = line end end
  check(bigOnB and bigOnB.data.omitted_bytes ~= nil, "B got the line without its data")
end

-- 6. the backlog keeps at most 256 KB, oldest first out
do
  for round = 1, 8 do
    for i = 1, 400 do a.log:write("client", "fill", { r = round, i = i, pad = ("z"):rep(80) }) end
    seconds(2.1)
  end
  check(host.logBacklogBytes <= Host.LOG_BACKLOG,
    "the backlog is at most 256 KB (" .. host.logBacklogBytes .. ")")
  local d = device("d1", "DORA", true)
  local cd = join(d, "DORA")
  seconds(0.1)
  local got, bytes = relayedFrom(d, "a1"), 0
  for _, line in ipairs(got) do
    line.relay = nil
    bytes = bytes + #Json.encode(line)
  end
  check(#got > 0 and bytes <= Host.LOG_BACKLOG,
    ("a late joiner gets at most the backlog (%d lines, %d bytes)"):format(#got, bytes))
  check(not kinds(got):find(",probe_a,", 1, true), "the oldest lines are gone from it")
  local lastRound = 0
  for _, line in ipairs(got) do
    if line.kind == "fill" then lastRound = math.max(lastRound, line.data.r) end
  end
  eq(lastRound, 8, "the newest batch is in it")
  cd:leave()
end

-- 7. a device that does not share sends nothing and gets nothing
do
  local e = device("e1", "EVE", false)
  local ce = join(e, "EVE")
  local sent = 0
  local send = ce.conn.send
  ce.conn.send = function(conn, msg)
    if msg.type == "log" then sent = sent + 1 end
    return send(conn, msg)
  end
  e.log:write("client", "private", {})
  a.log:write("client", "to_all", {})
  seconds(2.5)
  eq(ce.status, "joined", "a device that does not share joins")
  eq(sent, 0, "it sends no lines")
  eq(#relayedFrom(e, "a1"), 0, "and gets none")
  -- a log batch it sends anyway is ignored
  ce.conn:send({ type = "log", lines = {
    { t = 1, frame = 1, device = "e1", n = 1, src = "client", kind = "unasked" } } })
  seconds(2.5)
  check(not kinds(relayedFrom(b, "e1")):find(",unasked,", 1, true),
    "lines from a device that does not share are not passed on")
end

-- 8. leaving sends the last lines first
do
  a.log:write("client", "last_words", {})
  ca:leave()
  seconds(0.5)
  check(kinds(relayedFrom(b, "a1")):find(",last_words,", 1, true),
    "a leaving client's last lines arrive before its bye")
end

-- 9. the host's last lines go out before `ended`
do
  hostDev.log:write("host", "closing_soon", {})
  host:shutdown("host_quit")
  seconds(1.5)
  check(kinds(relayedFrom(b, "aaaa")):find(",closing_soon,", 1, true),
    "the host's last lines arrive before it ends")
  eq(cb.status, "ended", "B saw the end")
end

check(Protocol.VERSION >= 2, "log sharing is protocol version 2")

T.finish()
