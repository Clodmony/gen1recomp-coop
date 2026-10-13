-- Per-link limits against message floods (#32): one link that floods the
-- host does not hold up the others (each frame the host decodes at most a
-- budget of one link's messages, the rest waits) and is dropped with
-- `rejected` `flood` once it goes over its allowance; normal play, a full
-- 2 MiB message and a backlog of small ones are no flood.  ROM-free, over
-- loopback, on a frame clock.
--   luajit tests/coop/session_flood_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Transport = require("src.coop.session.Transport")
local Protocol = require("src.coop.session.Protocol")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")

local SHA = ("ef"):rep(20)
local now = 0
local host = Host.new({ campaign = { id = "c0000000000000002", title = "FLOOD" },
                        cartridge = { game = "red", sha1 = SHA },
                        clock = function() return now end })
local hub = host:serve(Transport.loopback())

-- what the host decodes per link and frame
local decoded = {}
local receive = host._receive
host._receive = function(self, link, raw)
  decoded[link] = (decoded[link] or 0) + 1
  return receive(self, link, raw)
end

local clients = {}
local function join(name, device)
  local c = Client.new(hub:dial(), { name = name, game = "red", sha1 = SHA, device = device })
  c:join()
  clients[#clients + 1] = c
  return c
end
local function frame()
  now = now + 1 / 60
  decoded = {}
  host:update()
  for _, c in ipairs(clients) do c:update() end
end
local function linkOf(c)
  for _, link in ipairs(host.links) do
    if link.player and link.player.id == c.player then return link end
  end
end

local walker, flooder = join("WALKER", "a1"), join("FLOOD", "b1")
for _ = 1, 3 do frame() end
eq(walker.status, "joined", "the walker joined")
eq(flooder.status, "joined", "the flooder joined")
walker:move("ROUTE_1", 0, 10, "right", true)
frame()

-- 1. normal play is no flood: a move every frame for 20 s
do
  for i = 1, 20 * 60 do
    walker:move("ROUTE_1", i % 2, 10, "right", false)
    frame()
  end
  eq(host.floods, 0, "a move every frame for 20 s is no flood")
  eq(walker.status, "joined", "the walker is still in")
end

-- 2. a full 2 MiB message and a backlog of small ones are no flood; the
--    backlog is decoded over several frames
do
  local big = { type = "move", seq = 1, pad = ("x"):rep(Protocol.MAX_MESSAGE - 200) }
  check(flooder.conn:send(big), "a message just under 2 MiB goes out")
  frame()
  eq(host.floods, 0, "one 2 MiB message is no flood")
  for _ = 1, 200 do flooder.conn:send({ type = "bye", seq = "x" }) end
  local link = linkOf(flooder)
  frame()
  local first = decoded[link] or 0
  check(first > 0 and first <= Host.FRAME_BUDGET.messages,
    ("the first frame decodes at most the budget (%d of 200)"):format(first))
  local rest = 0
  for _ = 1, 10 do frame(); rest = rest + (decoded[link] or 0) end
  eq(first + rest, 200, "the rest is decoded in the next frames")
  eq(host.floods, 0, "a backlog of 200 small messages is no flood")
  for _ = 1, 10 * 60 do frame() end -- the allowance refills
end

-- 2b. a 3 MB burst under the allowance: decoded a budget at a time over many
--     frames while the walker's moves go through every frame; no flood
do
  local pad = ("b"):rep(100 * 1024)
  for _ = 1, 30 do flooder.conn:send({ type = "move", seq = 1, pad = pad }) end
  local link = linkOf(flooder)
  local x, missed, frames, total, most = 0, 0, 0, 0, 0
  while total < 30 and frames < 120 do
    x = 1 - x
    walker:move("ROUTE_1", x, 10, "right", false)
    frame()
    frames = frames + 1
    total = total + (decoded[link] or 0)
    most = math.max(most, decoded[link] or 0)
    if host:player(walker.player).x ~= x then missed = missed + 1 end
  end
  eq(total, 30, "the burst is decoded")
  check(frames >= 10 and most <= 3,
    ("a budget at a time (%d frames, at most %d a frame)"):format(frames, most))
  eq(missed, 0, "the walker's move went through in every frame of it")
  eq(host.floods, 0, "a burst under the allowance is no flood")
  for _ = 1, 10 * 60 do frame() end
end

-- 3. a flood: 100 KB messages, 4 a frame (about 24 MB/s), while the walker
--    moves every frame; every move goes through, the flooder is dropped
do
  local pad = ("f"):rep(100 * 1024)
  local x, missed, budgetOk, frames = 0, 0, true, 0
  local link = linkOf(flooder)
  while frames < 300 and flooder.status == "joined" do
    for _ = 1, 4 do flooder.conn:send({ type = "move", seq = 1, pad = pad }) end
    x = 1 - x
    walker:move("ROUTE_1", x, 10, "right", false)
    frame()
    frames = frames + 1
    local p = host:player(walker.player)
    if p.x ~= x then missed = missed + 1 end
    if (decoded[link] or 0) > 3 then budgetOk = false end -- 256 KB is 2 or 3 of them
  end
  eq(missed, 0, "the walker's move went through in every frame of the flood")
  check(budgetOk, "the flooding link got at most its budget of each frame")
  eq(flooder.status, "refused", "the flooder is dropped")
  eq(flooder.reason, "flood", "with the reason flood")
  check(frames < 60, ("within a second (%d frames)"):format(frames))
  eq(host.floods, 1, "the host counts one flood")
  local p = host:player(flooder.player)
  eq(p and p.connected, false, "the others see the flooder gone")
  -- nothing it sends is read any more, and its link closes after the grace
  local seqBefore = p.lastSeq
  flooder.conn:send({ type = "move", seq = seqBefore + 1, map = "ROUTE_1", x = 5, y = 5,
                      facing = "up", warp = true, travel = "walk" })
  for _ = 1, 90 do
    walker:move("ROUTE_1", x, 10, "right", false)
    frame()
  end
  eq(p.lastSeq, seqBefore, "a dropped flooder's messages are not read")
  check(flooder.conn.closed, "its link is closed after the grace")
  eq(walker.status, "joined", "the walker plays on")
  local others = 0
  for _, q in ipairs(walker.state.players) do
    if q.id == flooder.player and not q.connected then others = others + 1 end
  end
  eq(others, 1, "the walker sees the flooder disconnected")
end

-- 4. too many small messages are a flood too
do
  local spammer = join("SPAM", "c1")
  for _ = 1, 3 do frame() end
  eq(spammer.status, "joined", "a third player joined")
  local frames = 0
  while frames < 300 and spammer.status == "joined" do
    for _ = 1, 50 do spammer.conn:send({ type = "bye", seq = "x" }) end
    frame()
    frames = frames + 1
  end
  eq(spammer.reason, "flood", "3000 messages a second are a flood")
end

T.finish()
