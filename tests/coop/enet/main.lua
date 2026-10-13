-- The co-op session core over real ENet sockets on this machine (#10), with
-- a loopback seat on the same host (G3): join, move, change maps, leave by
-- bye and by a dropped link, rejoin; protocol and cartridge refusals; 2 MiB
-- messages; broken JSON; shared session logs (#31); a flooding link dropped
-- while another player moves (#32); the LAN beacon on 127.0.0.1; a partner
-- who dials before the host listens is found by the retries (#12).  lua-enet ships with
-- LÖVE, so this suite runs under LÖVE, without a window:
--   love tests/coop/enet
-- It uses its own ports (never the game's 24680/24681) and sends nothing
-- beyond 127.0.0.1.

local root = love.filesystem.getSource():gsub("/tests/coop/enet/?$", "")
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Transport = require("src.coop.session.Transport")
local Protocol = require("src.coop.session.Protocol")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local Beacon = require("src.coop.session.Beacon")
local Session = require("src.coop.session.Session")
local Identity = require("src.coop.session.Identity")
local SessionLog = require("src.coop.session.SessionLog")

local PORT = 34680 + math.floor(love.timer.getTime() * 1000) % 500
local BEACON_PORT = PORT + 1000
local SHA = ("ab"):rep(20)
local CAMPAIGN = "c00000000000000e1"

-- pump everything until done() or the time runs out
local function pumpUntil(host, clients, done, seconds)
  local deadline = love.timer.getTime() + (seconds or 3)
  repeat
    host:update()
    for _, c in ipairs(clients) do c:update() end
    if done and done() then return true end
    love.timer.sleep(0.005)
  until love.timer.getTime() > deadline
  return done == nil
end

local function enetClient(name, opts)
  opts = opts or {}
  return Client.new(Transport.dial("127.0.0.1:" .. PORT), {
    name = name, game = "red", sha1 = opts.sha1 or SHA, device = opts.device or "e1",
    seat = 1, known = opts.known, build = "test",
  })
end

local function run()
  check(Transport.available(), "lua-enet is there under LÖVE")
  local host = Host.new({ campaign = { id = CAMPAIGN, title = "ENET" },
                          cartridge = { game = "red", sha1 = SHA }, port = PORT })
  local listener, err = Transport.listen(PORT)
  check(listener ~= nil, "the host opens its UDP port: " .. tostring(err))
  if not listener then return end
  host:serve(listener)
  local hub = host:serve(Transport.loopback())

  -- a loopback seat and two network players on one host
  local local1 = Client.new(hub:dial(), { name = "LOCAL", game = "red", sha1 = SHA,
                                          device = "f1", seat = 1 })
  local a = enetClient("ALICE", { device = "a1" })
  local b = enetClient("BOB", { device = "b1" })
  local all = { local1, a, b }
  local1:join(); a:join(); b:join() -- a and b queue until the link is up
  check(pumpUntil(host, all, function()
    return local1.status == "joined" and a.status == "joined" and b.status == "joined"
  end), "a loopback seat and two ENet players join")
  eq(#host.players, 3, "three players on the host")

  a:move("PALLET_TOWN", 3, 4, "down", true)
  b:move("PALLET_TOWN", 6, 4, "left", true)
  local1:move("PALLET_TOWN", 9, 9, "up", true)
  check(pumpUntil(host, all, function()
    local v = local1:playerView(a.player)
    return v and v.x == 3 and b:playerView(local1.player)
      and b:playerView(local1.player).y == 9
  end), "positions cross between ENet and loopback players")

  a:move("PALLET_TOWN", 3, 5, "down", false)
  a:move("ROUTE_1", 10, 35, "up", true)
  check(pumpUntil(host, all, function()
    local v = b:playerView(a.player)
    return v and v.map == "ROUTE_1" and v.y == 35
  end), "a map change over ENet reaches the others")
  eq(#a.rejections, 0, "nothing refused on the way")

  -- leave by bye, rejoin with the remembered player
  local aId, aKnown = a.player, a.known
  a:leave()
  check(pumpUntil(host, { local1, b }, function()
    local v = b:playerView(aId)
    return v and v.connected == false
  end), "a bye over ENet leaves the player")
  local a2 = enetClient("ALICE", { device = "a1", known = aKnown })
  a2:join()
  check(pumpUntil(host, { local1, b, a2 }, function() return a2.status == "joined" end),
    "the player rejoins over ENet")
  eq(a2.player, aId, "as themselves")
  eq(a2.seq, 4, "the sequence goes on after the bye (three moves and the bye)")
  a2:move("ROUTE_1", 10, 34, "up", false)
  check(pumpUntil(host, { local1, b, a2 }, function()
    local v = local1:playerView(aId)
    return v and v.connected and v.y == 34
  end), "and moves on")

  -- a dropped link (no bye) leaves the player too
  local bId = b.player
  b.conn.peer:disconnect_now()
  b.conn.closed = true
  check(pumpUntil(host, { local1, a2 }, function()
    local v = local1:playerView(bId)
    return v and v.connected == false
  end, 5), "a dropped ENet link leaves the player")

  -- another protocol version and another cartridge are refused with a reason
  local old = Transport.dial("127.0.0.1:" .. PORT)
  old:send({ type = "hello", protocol = Protocol.VERSION + 1, name = "OLD" })
  local answer
  check(pumpUntil(host, { local1 }, function()
    old:update()
    for _, m in ipairs(old:poll()) do answer = m end
    return answer ~= nil
  end), "an old client gets an answer")
  eq(answer and answer.reason, "protocol_mismatch", "protocol_mismatch over ENet")
  check(pumpUntil(host, { local1 }, function()
    old:update()
    return old.closed
  end, Host.GRACE + 2), "and the host drops it after the grace")

  local wrong = enetClient("WRONG", { sha1 = ("cd"):rep(20) })
  wrong:probe()
  check(pumpUntil(host, { local1, wrong }, function() return wrong.status == "probed" end),
    "a probe over ENet is answered")
  eq(wrong.lobby.refused, "content_mismatch", "the probe finds the cartridge mismatch")
  eq(#wrong.lobby.players, 3, "and lists the players")
  wrong:join()
  check(pumpUntil(host, { local1, wrong }, function() return wrong.status == "refused" end),
    "another cartridge is refused over ENet")
  eq(wrong.reason, "content_mismatch", "with content_mismatch")
  eq(#host.players, 3, "nobody was created")

  -- broken JSON on a live link is dropped and counted
  local dropsBefore = host.dropped
  a2.conn:sendRaw("{not json")
  a2.conn:sendRaw(("["):rep(100))
  check(pumpUntil(host, { local1, a2 }, function()
    return host.dropped >= dropsBefore + 2
  end), "broken JSON over ENet is dropped and counted")
  check(not a2.conn.closed, "the link stays up")

  -- shutdown reaches the ENet players
  host:shutdown("host_quit")
  check(pumpUntil(host, { local1, a2 }, function()
    return a2.status == "ended" and host.status == "ended"
  end, Host.GRACE + 2), "the ENet player is told the session ended")
  eq(a2.reason, "host_quit", "with the reason")

  -- 2 MiB messages over ENet, at the transport
  local l2 = Transport.listen(PORT + 1)
  local d = Transport.dial("127.0.0.1:" .. (PORT + 1))
  local s
  local deadline = love.timer.getTime() + 3
  while not s and love.timer.getTime() < deadline do
    l2:update(); d:update(); s = l2:accept()[1]
    love.timer.sleep(0.005)
  end
  check(s ~= nil, "a second listener accepts")
  if s then
    local big = ("x"):rep(Protocol.MAX_MESSAGE - 64)
    local t0 = love.timer.getTime()
    check(d:send({ type = "blob", data = big }), "a 2 MiB message is sent over ENet")
    check(not d:send({ type = "blob", data = big .. ("y"):rep(128) }),
      "a message over 2 MiB is not sent")
    local got
    deadline = love.timer.getTime() + 10
    while not got and love.timer.getTime() < deadline do
      l2:update(); d:update()
      got = s:poll()[1]
      love.timer.sleep(0.002)
    end
    eq(got and #got.data, #big, "and arrives whole")
    print(("2 MiB over ENet in %.2f s"):format(love.timer.getTime() - t0))
    d:sendRaw(("z"):rep(Protocol.MAX_MESSAGE + 1))
    deadline = love.timer.getTime() + 10
    while s.dropped == 0 and love.timer.getTime() < deadline do
      l2:update(); d:update(); s:poll()
      love.timer.sleep(0.002)
    end
    eq(s.dropped, 1, "an oversized wire text is dropped")
  end
  d:close(); l2:close()

  -- nobody listening: the dial gives up with a reason
  local saved = Transport.CONNECT_TIMEOUT
  Transport.CONNECT_TIMEOUT = 1
  local lost = Transport.dial("127.0.0.1:" .. (PORT + 2))
  Transport.CONNECT_TIMEOUT = saved
  deadline = love.timer.getTime() + 4
  while not lost.closed and love.timer.getTime() < deadline do
    lost:update(); love.timer.sleep(0.01)
  end
  check(lost.closed, "a dial with nobody listening closes")
  check(tostring(lost.error):find("no answer", 1, true) ~= nil,
    "and says no answer: " .. tostring(lost.error))

  -- shared logs and a flood over ENet, on a host of their own
  do
    local function memLog(device)
      local stored = {}
      local fs = {
        mkdir = function() end, list = function() return {} end,
        size = function() return 0 end, remove = function() end,
        open = function()
          return { write = function(text) stored[#stored + 1] = text end,
                   flush = function() end, close = function() end }
        end,
      }
      local log = SessionLog.open({ fs = fs, device = device, name = device, share = true })
      return log, stored
    end
    local h = Host.new({ campaign = { id = CAMPAIGN, title = "LIMITS" },
                         cartridge = { game = "red", sha1 = SHA }, port = PORT + 3 })
    local l3 = Transport.listen(PORT + 3)
    check(l3 ~= nil, "a third listener opens")
    h:serve(l3)
    local function dial(name, device, log)
      return Client.new(Transport.dial("127.0.0.1:" .. (PORT + 3)), {
        name = name, game = "red", sha1 = SHA, device = device, seat = 1, build = "test",
        log = log })
    end
    local logA = memLog("a1")
    local logB, storedB = memLog("b1")
    local ca, cb = dial("ANNA", "a1", logA), dial("BEN", "b1", logB)
    ca:join(); cb:join()
    check(pumpUntil(h, { ca, cb }, function()
      return ca.status == "joined" and cb.status == "joined"
    end), "two sharing ENet players join")
    logA:write("client", "over_enet", { n = 1 })
    check(pumpUntil(h, { ca, cb }, function()
      for _, text in ipairs(storedB) do
        if text:find('"over_enet"', 1, true) and text:find('"relay"', 1, true) then return true end
      end
      return false
    end, SessionLog.SHARE_INTERVAL + 3), "A's log line reaches B over ENet")

    -- B floods with 100 KB messages while A moves
    ca:move("ROUTE_1", 0, 10, "right", true)
    local pad = ("f"):rep(100 * 1024)
    local x, missed, moves = 0, 0, 0
    local deadline = love.timer.getTime() + 15
    while cb.status == "joined" and love.timer.getTime() < deadline do
      for _ = 1, 20 do cb.conn:send({ type = "move", seq = 1, pad = pad }) end
      x = 1 - x
      ca:move("ROUTE_1", x, 10, "right", false)
      for _ = 1, 3 do -- a few frames for the move to arrive
        h:update(); ca:update(); cb:update()
        love.timer.sleep(0.005)
      end
      moves = moves + 1
      if h:player(ca.player).x ~= x then missed = missed + 1 end
    end
    eq(cb.reason, "flood", "the flooding ENet player is dropped with the reason flood")
    check(missed <= 1, ("A's moves went through during the flood (%d of %d late)")
      :format(missed, moves))
    eq(ca.status, "joined", "A plays on")
    h:shutdown("host_quit")
    pumpUntil(h, { ca, cb }, function() return h.status == "ended" end, Host.GRACE + 2)
  end

  -- the launcher's session (#12): the partner presses Join before the host
  -- listens; the dial keeps trying and finds the host once it is up
  local function memoryIdentity()
    local text
    return Identity.load({ read = function() return text end,
                           write = function(t) text = t end })
  end
  local latePort = PORT + 2
  local partner = Session.startDial({ address = "127.0.0.1:" .. latePort, name = "ASH",
    cartridge = { game = "red", sha1 = SHA }, identity = memoryIdentity(), log = false })
  deadline = love.timer.getTime() + 1
  while love.timer.getTime() < deadline do partner:update(0.01); love.timer.sleep(0.01) end
  check(partner.status == "dialling" or partner.status == "waiting",
    "nobody listens yet: still dialling (" .. partner.status .. ")")
  local late = Session.startHost({ campaign = { id = CAMPAIGN, title = "LATE" },
    cartridge = { game = "red", sha1 = SHA }, name = "RED", port = latePort,
    identity = memoryIdentity(), log = false, beacon = false })
  check(late.listening, "the host opens its port a second later")
  deadline = love.timer.getTime() + 12
  while partner.status ~= "probed" and love.timer.getTime() < deadline do
    late:update(0.01); partner:update(0.01); love.timer.sleep(0.005)
  end
  eq(partner.status, "probed", "the partner's dial finds the late host")
  eq(partner.lobby and partner.lobby.title, "LATE", "and reads its lobby")
  partner:join()
  deadline = love.timer.getTime() + 3
  while partner.status ~= "joined" and love.timer.getTime() < deadline do
    late:update(0.01); partner:update(0.01); love.timer.sleep(0.005)
  end
  eq(partner.status, "joined", "and joins")
  eq(late:partners(), 1, "the host counts one partner")
  late:leave(nil)
  deadline = love.timer.getTime() + 3
  while partner.status == "joined" and love.timer.getTime() < deadline do
    partner:update(0.01); love.timer.sleep(0.005)
  end
  eq(partner.status, "ended", "the host's STOP reaches the partner")
  eq(partner.reason, "host_quit", "as the host closing the session")

  -- the LAN beacon, on 127.0.0.1 only
  check(Beacon.available(), "luasocket is there under LÖVE")
  local lobbyHost = Host.new({ campaign = { id = CAMPAIGN, title = "BEACON" },
                               cartridge = { game = "red", sha1 = SHA }, port = PORT })
  local listen, lerr = Beacon.listener({ port = BEACON_PORT, bind = "127.0.0.1" })
  check(listen ~= nil, "the beacon listener binds: " .. tostring(lerr))
  local second = Beacon.listener({ port = BEACON_PORT, bind = "127.0.0.1" })
  check(second == nil, "one beacon listener per device")
  local send = Beacon.sender({ port = BEACON_PORT, targets = { "127.0.0.1" },
                               lobby = function() return lobbyHost:lobby() end })
  if listen and send then
    deadline = love.timer.getTime() + 3
    local heard
    while not heard and love.timer.getTime() < deadline do
      send:update(0.1); listen:update()
      heard = listen:hosts()[1]
      love.timer.sleep(0.01)
    end
    eq(heard and heard.address, "127.0.0.1:" .. PORT, "the beacon names the host and game port")
    eq(heard and heard.lobby.title, "BEACON", "with the lobby view")
    send:close(); listen:close()
  end
end

local ok, err = xpcall(run, debug.traceback)
check(ok, "the suite ran to the end: " .. tostring(err))
T.finish("co-op ENet")
love.event.quit(T.failures == 0 and 0 or 1)
