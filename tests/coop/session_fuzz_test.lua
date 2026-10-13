-- Seeded fuzz of the co-op protocol (#10, design A1.4): every message type,
-- in both directions, is sent with fields removed, retyped, out of range,
-- oversized or nested, and as broken JSON.  A malformed message is dropped
-- whole and changes nothing; the host and the client never raise.  ROM-free.
--   luajit tests/coop/session_fuzz_test.lua [seed]

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Transport = require("src.coop.session.Transport")
local Protocol = require("src.coop.session.Protocol")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local Json = require("src.link.Json")

local SEED = tonumber(arg and arg[1]) or 20261013
local ROUNDS = 300 -- mutations per message type
math.randomseed(SEED)
print(("fuzz seed %d, %d rounds per type"):format(SEED, ROUNDS))

local SHA = ("ab"):rep(20)
local CAMPAIGN = "c00000000000000aa"

-- one valid message of each type, per receiving side
local VALID = {
  host = {
    probe = { type = "probe", protocol = Protocol.VERSION, build = "t", name = "RED",
              game = "red", sha1 = SHA, known = { [CAMPAIGN] = "p00000001" } },
    hello = { type = "hello", protocol = Protocol.VERSION, build = "t", name = "FUZZ",
              game = "red", sha1 = SHA, device = "d9", seat = 1,
              known = { [CAMPAIGN] = "p00000009" }, via = "loopback" },
    move = { type = "move", seq = 1, map = "ROUTE_1", x = 3, y = 4,
             facing = "up", warp = true },
    bye = { type = "bye", seq = 1 },
  },
  client = {
    probe = { type = "probe", kind = "coop", protocol = Protocol.VERSION, build = "t",
              campaign = CAMPAIGN, title = "T", game = "red", sha1 = SHA,
              host = "HOST", players = { { name = "RED", game = "red", connected = true } },
              refused = "", you = { player = "p00000001", name = "RED" }, port = 24680 },
    welcome = { type = "welcome", protocol = Protocol.VERSION, player = "p00000001",
                last_seq = 0, campaign = CAMPAIGN },
    state = { type = "state", you = "p00000001", last_seq = 3, nearby = { "p00000002" },
              players = { { id = "p00000001", name = "RED", game = "red", connected = true,
                            map = "ROUTE_1", x = 1, y = 2, facing = "down" } } },
    rejected = { type = "rejected", seq = 4, reason = "duplicate" },
    ended = { type = "ended", reason = "host_quit" },
  },
}

-- every type the protocol accepts has a valid sample here
for _, side in ipairs({ "host", "client" }) do
  for _, t in ipairs(Protocol.types(side)) do
    check(VALID[side][t] ~= nil, ("fuzz covers %s message %s"):format(side, t))
    local ok = Protocol.sanitize(VALID[side][t], side)
    check(ok ~= nil, ("the %s sample of %s is valid"):format(side, t))
  end
end

local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do out[k] = deepCopy(val) end
  return out
end

local function nested(depth)
  local t = {}
  local cur = t
  for _ = 1, depth do cur.x = {}; cur = cur.x end
  return t
end

local JUNK = {
  function() return nil end,
  function() return math.random(-1e6, 1e6) end,
  function() return math.random() end,
  function() return 1e309 end,     -- inf after JSON
  function() return -1e309 end,
  function() return 2 ^ 60 end,
  function() return -1 end,
  function() return 0 end,
  function() return "" end,
  function() return ("A"):rep(math.random(1, 5000)) end,
  function() return "a\1b" end,
  function() return "\255\254" end, -- not UTF-8
  function() return "ROUTE_1" end,
  function() return "p00000001" end,
  function() return true end,
  function() return false end,
  function() return {} end,
  function() return { 1, 2, 3 } end,
  function() return { a = 1 } end,
  function() return nested(math.random(2, 80)) end,
}

local function junk() return JUNK[math.random(#JUNK)]() end

-- the fields of a message and of the tables in it, as paths
local function paths(v, prefix, out)
  out = out or {}
  for k, val in pairs(v) do
    local p = { unpack(prefix) }
    p[#p + 1] = k
    out[#out + 1] = p
    if type(val) == "table" then paths(val, p, out) end
  end
  return out
end

local function setPath(msg, path, value)
  local cur = msg
  for i = 1, #path - 1 do cur = cur[path[i]] end
  cur[path[#path]] = value
end

local function mutate(msg)
  local m = deepCopy(msg)
  for _ = 1, math.random(1, 3) do
    local all = paths(m, {})
    local roll = math.random(10)
    if roll <= 7 and #all > 0 then
      setPath(m, all[math.random(#all)], junk())        -- retype or remove
    elseif roll <= 9 then
      m["extra" .. math.random(9)] = junk()               -- an unknown field
    else
      m = junk()                                           -- not a record at all
      break
    end
  end
  return m
end

-- a sanitized message holds only fields its sample has (nothing extra
-- survives) and no value of a wrong type
local function conforms(clean, sample)
  if type(clean) ~= "table" then return false end
  for k, v in pairs(clean) do
    local s = sample[k]
    if s == nil or type(v) ~= type(s) then return false end
  end
  return true
end

-- the host side ------------------------------------------------------------

local idN = 0
local function newHost()
  return Host.new({
    campaign = { id = CAMPAIGN, title = "FUZZ" }, cartridge = { game = "red", sha1 = SHA },
    hex = function(n) idN = idN + 1; return ("%0" .. n .. "x"):format(idN) end,
  })
end

local host = newHost()
local hub = host:serve(Transport.loopback())
local anchor = Client.new(hub:dial(), { name = "RED", game = "red", sha1 = SHA, device = "d1" })
anchor:join()
for _ = 1, 3 do host:update(); anchor:update() end
anchor:move("PALLET_TOWN", 5, 5, "down", true)
for _ = 1, 3 do host:update(); anchor:update() end
eq(anchor.status, "joined", "the anchor player joined")

local function snapshot()
  local out = {}
  for _, p in ipairs(host.players) do
    out[#out + 1] = table.concat({ p.id, p.name, tostring(p.connected), tostring(p.map),
      tostring(p.x), tostring(p.y), tostring(p.facing), tostring(p.lastSeq) }, "|")
  end
  return table.concat(out, ";")
end

-- what the receiver decodes: the JSON round trip (nil when the text is not
-- JSON the transport keeps, e.g. inf or nesting past the decoder's depth)
local function overWire(raw)
  local ok, text = pcall(Json.encode, raw)
  if not ok then return nil end
  local v = Json.decode(text, Protocol.MAX_MESSAGE)
  if type(v) ~= "table" then return nil end
  return v
end

local function otherVersion(v)
  return type(v) == "table" and (v.type == "probe" or v.type == "hello")
    and type(v.protocol) == "number" and v.protocol ~= Protocol.VERSION
end

local raised, accepted, dropped = 0, 0, 0
for _, t in ipairs(Protocol.types("host")) do
  for _ = 1, ROUNDS do
    local raw = mutate(VALID.host[t])
    local wire = overWire(raw)
    local clean = wire and Protocol.sanitize(wire, "host")
    -- probe and hello go on a link of their own (a refused hello's grace
    -- must not take the anchor), the others on the anchor's (they need a
    -- joined player)
    local before, droppedBefore = snapshot(), host.dropped
    local conn = (t == "probe" or t == "hello") and hub:dial() or anchor.conn
    conn:send(raw)
    local ok, err = pcall(function()
      for _ = 1, 2 do host:update() end
    end)
    if not ok then
      raised = raised + 1
      print("host raised on " .. t .. ": " .. tostring(err))
    end
    if clean then
      accepted = accepted + 1
      if not conforms(clean, VALID.host[t]) then
        check(false, "a sanitized " .. t .. " has only its schema's fields")
      end
    elseif not otherVersion(wire) then
      dropped = dropped + 1
      if snapshot() ~= before then
        check(false, "a malformed " .. t .. " changed the host: " .. snapshot())
      end
      if host.dropped <= droppedBefore then
        check(false, "a malformed " .. t .. " is dropped and counted")
      end
    end
    if conn ~= anchor.conn then
      conn:close()
      host:update() -- the host sees the link go before the next snapshot
    end
    anchor:update()
    -- keep the anchor joined: a valid bye takes it out
    if anchor.conn.closed or not host:player(anchor.player).connected then
      anchor = Client.new(hub:dial(), { name = "RED", game = "red", sha1 = SHA,
                                        device = "d1", known = anchor.known })
      anchor:join()
      for _ = 1, 3 do host:update(); anchor:update() end
    end
  end
end
eq(raised, 0, "the host never raises on a malformed message")
check(dropped > ROUNDS and accepted > 0, ("fuzz both dropped (%d) and kept (%d) messages")
  :format(dropped, accepted))
print(("host side: %d dropped, %d still valid"):format(dropped, accepted))

-- broken JSON on the wire
do
  local conn = hub:dial()
  local droppedBefore = host.dropped
  local texts = { "", "{", "[1,2", '{"type":', "nul", '{"type":"hello"', "\0\1\2",
                  ("["):rep(200) .. ("]"):rep(200), '"just a string"', "42", "null",
                  '{"type":"move","seq":1e999}' }
  for _ = 1, 50 do
    local s = {}
    for i = 1, math.random(1, 64) do s[i] = string.char(math.random(0, 255)) end
    texts[#texts + 1] = table.concat(s)
  end
  local before = snapshot()
  for _, text in ipairs(texts) do conn:sendRaw(text) end
  local ok = pcall(function() for _ = 1, 3 do host:update() end end)
  check(ok, "the host never raises on broken JSON")
  eq(snapshot(), before, "broken JSON changes nothing")
  check(host.dropped - droppedBefore >= #texts - 2,
    "broken JSON is dropped and counted (" .. (host.dropped - droppedBefore) .. ")")
  conn:close()
end

-- the client side ------------------------------------------------------------

local a = Transport.loopback()
local c = Client.new(a:dial(), { name = "RED", game = "red", sha1 = SHA })
local server = a:accept()[1]
c.status = "joined"
server:send(VALID.client.state)
c:update()
local goodState = c.state
check(goodState ~= nil, "the client keeps a valid state")
local craised, cdropped = 0, 0
for _, t in ipairs(Protocol.types("client")) do
  for _ = 1, ROUNDS do
    local raw = mutate(VALID.client[t])
    local wire = overWire(raw)
    local clean = wire and Protocol.sanitize(wire, "client")
    local stateBefore, droppedBefore = c.state, c.dropped
    server:send(raw)
    local ok, err = pcall(c.update, c)
    if not ok then
      craised = craised + 1
      print("client raised on " .. t .. ": " .. tostring(err))
    end
    if clean then
      if not conforms(clean, VALID.client[t]) then
        check(false, "a sanitized " .. t .. " has only its schema's fields")
      end
    elseif wire then -- (text that is not JSON never reaches the client)
      cdropped = cdropped + 1
      if c.dropped <= droppedBefore then
        check(false, "a malformed " .. t .. " is dropped by the client")
      end
      if c.state ~= stateBefore then
        check(false, "a malformed " .. t .. " replaced the client's state")
      end
    end
    -- an `ended` or `rejected` that passed changes the status; reset it
    c.status = "joined"
    if c.conn.closed then
      a = Transport.loopback()
      c.conn = a:dial()
      server = a:accept()[1]
    end
  end
end
eq(craised, 0, "the client never raises on a malformed message")
check(cdropped > 0, "the client dropped malformed messages (" .. cdropped .. ")")

T.finish()
