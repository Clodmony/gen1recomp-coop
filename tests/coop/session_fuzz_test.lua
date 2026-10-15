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

-- a log batch as SessionLog writes it (#31)
local function logBatch()
  return { type = "log", lines = {
    { t = 1760000000000, frame = 12, device = "d9", n = 3, src = "client", kind = "joined",
      name = "FUZZ", seat = 1, player = "p00000009",
      data = { name = "FUZZ", list = { 1, 2.5, true, "x" }, nested = { a = { b = "c" } } } },
    { t = 1760000000001, frame = 13, device = "d9", n = 4, src = "host", kind = "message" },
  } }
end

-- a Pokémon as a battle message carries it (#18)
local BATTLE_MON = { species = "PIDGEY", level = 12, hp = 30, exp = 1500, status = "PSN",
                     sleepTurns = 0, nickname = "BIRD", ot = "RED", otId = 4321, uid = "p0001:12",
                     dvs = { hp = 1, attack = 2, defense = 3, speed = 4, special = 5 },
                     statExp = { hp = 10, attack = 20, defense = 30, speed = 40, special = 50 },
                     moves = { { id = "GUST", pp = 35, ppUps = 1 }, { id = "SAND_ATTACK", pp = 15 } },
                     extra = { mod = { x = 1 } } }

-- one valid message of each type, per receiving side
local VALID = {
  host = {
    probe = { type = "probe", protocol = Protocol.VERSION, build = "t", name = "RED",
              game = "red", sha1 = SHA, known = { [CAMPAIGN] = "p00000001" } },
    hello = { type = "hello", protocol = Protocol.VERSION, build = "t", name = "FUZZ",
              game = "red", sha1 = SHA, device = "d9", seat = 1,
              known = { [CAMPAIGN] = "p00000009" }, via = "loopback",
              logs = { share = true } },
    move = { type = "move", seq = 1, map = "ROUTE_1", x = 3, y = 4,
             facing = "up", warp = true, travel = "walk" },
    bye = { type = "bye", seq = 1 },
    log = logBatch(),
    world = { type = "world", seq = 1, checkpoint = true, kind = "menu",
              save = 'return { player = { name = "FUZZ" }, money = 5, party = {} }\n' },
    holdings = { type = "holdings", seq = 2,
                 world = 'return { player = { name = "FUZZ" }, money = 5, party = {} }\n',
                 boxes = "return { {} }\n" },
    patch = { type = "patch", seq = 2, set = { ["flags/EVENT_GOT_POKEDEX"] = true,
              ["objectToggles/ROUTE_1/BALL"] = false, ["inventory/BOULDERBADGE"] = 1 },
              unset = { "flags/EVENT_X" },
              bag = { gained = { POTION = 1 }, lost = { OAKS_PARCEL = 1 }, spent = false } },
    battle_open = { type = "battle_open", seq = 3, kind = "trainer", map = "ROUTE_3",
                    enemy = { BATTLE_MON }, team = { BATTLE_MON }, foe = "LASS",
                    trainer = { class = "OPP_LASS", index = 2, rival = "BLUE" },
                    otId = 4321, expAll = true, hooked = false, room = true,
                    encounter = "trainer:ROUTE_3_obj_2" },
    battle_join = { type = "battle_join", seq = 4, battle = "b00000001", team = { BATTLE_MON },
                    otId = 1, expAll = false, room = false },
    battle_cmd = { type = "battle_cmd", seq = 5, battle = "b00000001", rev = 3,
                   cmd = { kind = "item", item = "POTION", index = 2, move = 1 } },
    battle_suggest = { type = "battle_suggest", seq = 6, battle = "b00000001", rev = 3,
                       cmd = { kind = "switch", index = 7 } },
    battle_at = { type = "battle_at", seq = 7, battle = "b00000001", rev = 3, ask = "menu",
                  by = "p00000001", hash = "abc123", ended = "win" },
    battle_leave = { type = "battle_leave", seq = 8, battle = "b00000001" },
    battle_rejoin = { type = "battle_rejoin", seq = 9, battle = "b00000001" },
    battle_takeover = { type = "battle_takeover", seq = 10, battle = "b00000001",
                        owner = "p00000002" },
    opening = { type = "opening", seq = 11, done = true, rival = "GARY", chose = "SQUIRTLE" },
    -- rival scenes (#59)
    scene = { type = "scene", seq = 12, map = "ROUTE_22", key = "route22_1", on = true },
    -- #9: a window's own wild slots
    wild = { type = "wild", seq = 12, maps = {
      ROUTE_4 = { grass = { { species = "RATTATA", level = 10 }, { species = "EKANS", level = 6 } } },
      SEAFOAM_ISLANDS_B4F = { water = { { species = "HORSEA", level = 30 } } } } },
    -- how a new player starts (#57)
    start = { type = "start", seq = 12, how = "save",
              save = 'return { player = { name = "FUZZ" }, money = 5, party = {} }\n' },
    -- the Cable Club (#60)
    cable = { type = "cable", seq = 12, room = "trade", with = "p00000002" },
    cable_link = { type = "cable_link", seq = 13, round = 1,
                   link = { type = "party", mons = { BATTLE_MON } }, uids = { "p0001:12" } },
    -- friend battles and trades (#23)
    invite = { type = "invite", seq = 12, to = "p00000002", kind = "battle" },
    invite_answer = { type = "invite_answer", seq = 13, invite = "i00000001", yes = true },
    pair_msg = { type = "pair_msg", seq = 14, pair = "t00000001", n = 3,
                 msg = { type = "action", kind = "move", slot = 2, parts = { actives = "ab" } } },
    pair_end = { type = "pair_end", seq = 15, pair = "t00000001", result = "forfeit" },
    trade_team = { type = "trade_team", seq = 16, pair = "t00000001",
                   team = 'return { { species = "PIDGEY", level = 12 } }\n' },
    trade_pick = { type = "trade_pick", seq = 17, pair = "t00000001", slot = 2 },
    trade_confirm = { type = "trade_confirm", seq = 18, pair = "t00000001", yes = false },
    league = { type = "league", seq = 12, event = "inducted" },
    restart = { type = "restart", seq = 13, kind = "hall" },
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
                            map = "ROUTE_1", x = 1, y = 2, facing = "down", travel = "bike",
                            battle = "b00000001", opening = false, cable = "trade",
                            meeting = "trade" } },
              saved_ago = 12, busy = "", rival = "GARY", chose = "BULBASAUR",
              battles = { { id = "b00000001", by = "p00000001", kind = "wild",
                            players = { "p00000001" }, foe = "PIDGEY", joinable = true,
                            encounter = "static:ROUTE_12_obj_1" } },
              scenes = { { map = "ROUTE_22", key = "route22_1", by = "p00000001" } } }, -- #59
    world = { type = "world", fresh = false, save = "return { player = {} }\n", restart = 13 },
    saved = { type = "saved", ok = false, by = "RED", you = true,
              reason = "battle_in_progress", kind = "menu" },
    rejected = { type = "rejected", seq = 4, reason = "duplicate" },
    started = { type = "started", seq = 12, seeded = true }, -- #57
    ended = { type = "ended", reason = "host_quit" },
    log = logBatch(),
    story = { type = "story", rev = 7, base = true, applied = 2,
              set = { ["flags/EVENT_GOT_POKEDEX"] = true, ["trashPuzzle/first"] = 4 },
              unset = { "itemsTaken/ROUTE_1_obj_2" } },
    gifts = { type = "gifts", list = { { seq = 1, item = "BICYCLE", qty = 1, once = true,
                                         from = "RED" },
                                       { seq = 2, item = "POTION", qty = -1, race = true } } },
    uids = { type = "uids", list = { { box = 0, slot = 1, uid = "p00000001:1",
                                       fp = "4321|RED|attack=1,defense=2|45" },
                                     { box = 12, slot = 20, uid = "p00000001:2", fp = "" } } },
    battle = { type = "battle", id = "b00000001", rev = 2, seed = 99, from = 1,
               inputs = { { kind = "join", player = "p00000001", name = "RED",
                            team = { BATTLE_MON }, otId = 4321, expAll = false, room = true },
                          { kind = "cmd", player = "p00000001",
                            cmd = { kind = "move", slot = 1 } } },
               players = { { id = "p00000001", present = true },
                           { id = "p00000002", present = false, left = true } },
               owner = "p00000002", offer = "p00000002",
               standins = { { owner = "p00000002", by = "p00000001" } },
               open = { kind = "wild", enemy = { BATTLE_MON }, map = "ROUTE_1",
                        by = "p00000001", hooked = true, foe = "PIDGEY" },
               ask = "replace", by = "p00000001",
               suggestions = { { by = "p00000002", cmd = { kind = "replace", index = 3 } } },
               ended = "lose" },
    -- #9: the other version's wild slots
    wild = { type = "wild", game = "blue", maps = {
      ROUTE_4 = { grass = { { species = "SANDSHREW", level = 6 } },
                  water = { { species = "KRABBY", level = 15 } } } } },
    -- the Cable Club (#60)
    cable = { type = "cable", room = "trade", round = 2, mate = "p00000002", name = "BLUE",
              lead = true },
    cable_link = { type = "cable_link", round = 2, link = { type = "confirm", ok = true },
                   uid = "p00000002:3" },
    -- friend battles and trades (#23)
    invite = { type = "invite", id = "i00000001", from = "p00000001", to = "p00000002",
               kind = "trade", answer = "timeout" },
    pair = { type = "pair", id = "t00000001", kind = "trade", partner = "p00000002",
             role = "guest", seed = 77, name = "BLUE", away = true, ended = "cancel",
             mine = 'return { { species = "PIDGEY", level = 12 } }\n',
             theirs = 'return { { species = "RATTATA", level = 9 } }\n',
             myPick = 1, theirPick = 1, confirmed = true, theirConfirmed = false, done = true },
    pair_msg = { type = "pair_msg", pair = "t00000001", n = 1,
                 msg = { type = "hello", name = "RED", mods = { { id = "x" } } } },
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

-- the host runs on a frame clock: each update is 1/60 s, so the per-link
-- limits (#32) see the fuzz's traffic at a real frame rate
local idN, frameTime = 0, 0
local function newHost()
  local h = Host.new({
    campaign = { id = CAMPAIGN, title = "FUZZ" }, cartridge = { game = "red", sha1 = SHA },
    hex = function(n) idN = idN + 1; return ("%0" .. n .. "x"):format(idN) end,
    clock = function() return frameTime end,
  })
  local update = h.update
  h.update = function(self)
    frameTime = frameTime + 1 / 60
    return update(self)
  end
  return h
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
eq(host.floods, 0, "the fuzz's pace is no flood (#32)")
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
