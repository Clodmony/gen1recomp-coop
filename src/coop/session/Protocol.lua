-- The co-op session protocol (#10): message types, the protocol version and
-- one sanitizer per message type.  Every field that arrives from the other
-- end is untrusted (design A1.4, D35): a message is kept only when each field
-- has its schema's type and range, and the sanitized copy holds only the
-- schema's fields.  A message that fails is dropped whole, never clamped
-- into something the sender did not mean.
--
--   local msg, why = Protocol.sanitize(raw, "host")  -- raw from a client
--   local msg, why = Protocol.sanitize(raw, "client") -- raw from the host
--
-- Messages are plain tables with a `type`; on the wire they are JSON
-- (src/link/Json.lua), so an empty map arrives as an empty array.

local Protocol = {}

-- raised whenever a message's shape or meaning changes; a peer of another
-- version is refused with protocol_mismatch (design A1.6).  2: shared session
-- logs (#31) and the flood refusal (#32).  3: how a player travels
-- (`travel` on moves and players, #15).  4: campaign files (#13): a
-- window's `world` and save requests, the host's `world` and `saved`, and
-- the last save and the save gate in `state`.  5: the shared world (#14):
-- a window's `patch` and the host's `story`.  6: story items (#16): the
-- bag change on a `patch` and the host's `gifts`.  7: co-op battles (#18):
-- `battle_open`, `battle_join`, `battle_cmd`, `battle_suggest` and
-- `battle_at` to the host, `battle` to the client, and who is in which
-- battle in `state`.  8: Pokémon, party and PC (#17): a window's
-- `holdings` at its rest points, the host's `uids`, and each team's `room`
-- for a catch.  9: unique encounters (#21): the `encounter` a battle's
-- opening is, and in `state`; a walk-in joins the running one.
Protocol.VERSION = 9

-- one message, encoded, may be this long: a full PC is about a quarter of a
-- megabyte (design A1.4)
Protocol.MAX_MESSAGE = 2 * 1024 * 1024

Protocol.MAX_NAME = 10      -- characters; the cartridge allows 7
Protocol.MAX_BUILD = 40
Protocol.MAX_TITLE = 40
Protocol.MAX_REASON = 40
Protocol.MAX_PLAYERS = 16
Protocol.MAX_KNOWN = 64
Protocol.MAX_SEQ = 2 ^ 53 - 1
Protocol.MAX_CELL = 255

-- shared session logs (#31, design A1.14): a batch holds at most this many
-- lines; a line's data is plain JSON this deep, with tables this long and
-- text this long (the sender leaves out the data of a line over 8 KB)
Protocol.MAX_LOG_LINES = 1024
Protocol.MAX_LOG_KIND = 40
Protocol.MAX_LOG_DEPTH = 8
Protocol.MAX_LOG_ENTRIES = 256
Protocol.MAX_LOG_TEXT = 8 * 1024

-- refusal reasons the host sends in `rejected` and in a probe's `refused`
Protocol.REASONS = {
  protocol_mismatch = true, content_mismatch = true, duplicate = true,
  hello_first = true, already_joined = true, bad_step = true,
  session_full = true, shutting_down = true, flood = true,
  bad_world = true, battle_in_progress = true, save_failed = true,
  -- co-op battles (#18)
  in_battle = true, no_battle = true, not_in_battle = true, stale = true,
  not_ready = true, not_yours = true, bad_cmd = true, roster_full = true,
  no_pokemon = true, run_initiator = true,
  -- leaving and taking over (#20)
  opener_stays = true, not_away = true,
}

-- a player's world travels as the game's save text (World.lua checks it):
-- this long at most, newlines and all
Protocol.MAX_WORLD = 1536 * 1024
-- what asked for a save (design A3.11): START > SAVE, a box change, the
-- Hall of Fame, a link room, the quick save key
Protocol.SAVE_KINDS = { menu = true, box = true, hall = true, link = true, quick = true }

-- the shared story (#14, design A5.2): at most this many entries in one
-- patch or story message; a path names one entry (Ownership.lua), a value is
-- a boolean or a small whole number
Protocol.MAX_STORY = 8192
Protocol.MAX_PATH = 96

-- story items (#16, design A6): an item id, how many of one item a gift or
-- a bag change moves, and how many items one message names
Protocol.MAX_QTY = 999
Protocol.MAX_ITEMS = 256
-- the rows of a team and a PC (#17): 6 + 12 * 20
Protocol.MAX_ROWS = 246

-- co-op battles (#18, design A8): a team is at most six, the allied roster
-- at most twelve; one `battle` message carries at most MAX_INPUTS of the
-- battle's inputs (the rest follow in the next frames)
Protocol.MAX_TEAM = 6
Protocol.MAX_ROSTER = 12
Protocol.MAX_INPUTS = 256
-- what the battle waits for (the window's report, `battle_at`), and the
-- commands that answer each
Protocol.ASKS = { menu = true, replace = true, learn = true, mimic = true, choice = true }
Protocol.CMDS = {
  move = "menu", struggle = "menu", fight = "menu", switch = "menu", item = "menu",
  ball = "menu", run = "menu",
  replace = "replace", learn = "learn", mimic = "mimic", choice = "choice",
}
Protocol.RESULTS = { win = true, lose = true, run = true, caught = true }

local FACINGS = { up = true, down = true, left = true, right = true }
-- how a player moves: the sprite they wear and how fast their steps are
-- eased on the other screens (#15, design A14.5)
local TRAVELS = { walk = true, run = true, bike = true, surf = true }
Protocol.TRAVELS = TRAVELS

-- field checks: each returns the clean value, or nil and a reason ---------

local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function int(min, max)
  return function(v)
    if not finite(v) or v ~= math.floor(v) then return nil, "not an integer" end
    if v < min or v > max then return nil, "out of range" end
    return v
  end
end

-- UTF-8 text without control characters, at most maxChars characters
local function text(maxChars)
  return function(v)
    if type(v) ~= "string" then return nil, "not a string" end
    if #v > maxChars * 4 then return nil, "too long" end
    if v:find("[%z\1-\31\127]") then return nil, "control character" end
    local chars, i = 0, 1
    while i <= #v do
      local b = v:byte(i)
      local len = b < 0x80 and 1 or (b >= 0xF0 and b < 0xF8) and 4
        or (b >= 0xE0) and b < 0xF0 and 3 or (b >= 0xC2 and b < 0xE0) and 2 or nil
      if not len or i + len - 1 > #v then return nil, "not UTF-8" end
      for j = i + 1, i + len - 1 do
        local c = v:byte(j)
        if c < 0x80 or c >= 0xC0 then return nil, "not UTF-8" end
      end
      chars = chars + 1
      i = i + len
    end
    if chars > maxChars then return nil, "too long" end
    return v
  end
end

local function name(v)
  local s, why = text(Protocol.MAX_NAME)(v)
  if not s then return nil, why end
  if not s:find("%S") then return nil, "empty" end
  return s
end

local function pattern(p, maxLen)
  return function(v)
    if type(v) ~= "string" or #v > maxLen or not v:find(p) then
      return nil, "bad format"
    end
    return v
  end
end

-- text of any bytes, at most maxBytes long (a save's text; its own parser
-- reads it)
local function blob(maxBytes)
  return function(v)
    if type(v) ~= "string" then return nil, "not a string" end
    if #v > maxBytes then return nil, "too long" end
    return v
  end
end

local function bool(v)
  if type(v) ~= "boolean" then return nil, "not a boolean" end
  return v
end

local function enum(set)
  return function(v)
    if type(v) ~= "string" or not set[v] then return nil, "unknown value" end
    return v
  end
end

Protocol.playerId = pattern("^p[0-9a-f]+$", 17)  -- "p" and up to 16 hex digits
Protocol.campaignId = pattern("^c[0-9a-f]+$", 17)
Protocol.deviceId = pattern("^[0-9a-f]+$", 16)
Protocol.gameId = pattern("^[a-z][a-z0-9_]*$", 16)
Protocol.sha1 = pattern("^" .. ("[0-9a-f]"):rep(40) .. "$", 40)
Protocol.mapId = pattern("^[A-Z0-9_]+$", 40)
Protocol.name = name

local seq = int(1, Protocol.MAX_SEQ)
local cell = int(0, Protocol.MAX_CELL)

local function storyPath(v)
  if type(v) ~= "string" or #v > Protocol.MAX_PATH
     or not v:find("^[%w_]+/[%w_%-%./]+$") or v:find("//") or v:find("/$") then
    return nil, "bad path"
  end
  return v
end
local function storyValue(v)
  if type(v) == "boolean" then return v end
  if finite(v) and v == math.floor(v) and v >= 0 and v <= 255 then return v end
  return nil, "bad value"
end
Protocol.storyPath = storyPath
Protocol.itemId = pattern("^[A-Z0-9_]+$", 40)
Protocol.battleId = pattern("^b[0-9a-f]+$", 17)

-- a table whose every value passes fn; maps arrive as objects, an empty one
-- as an empty array
local function mapOf(keyCheck, valueCheck, maxN)
  return function(v)
    if type(v) ~= "table" then return nil, "not a table" end
    local out, n = {}, 0
    for k, val in pairs(v) do
      n = n + 1
      if n > maxN then return nil, "too many entries" end
      local ck = keyCheck(k)
      local cv = valueCheck(val)
      if ck == nil or cv == nil then return nil, "bad entry" end
      out[ck] = cv
    end
    return out
  end
end

local function listOf(fn, maxN)
  return function(v)
    if type(v) ~= "table" then return nil, "not a list" end
    local n = 0
    for k in pairs(v) do
      if type(k) ~= "number" then return nil, "not a list" end
      n = n + 1
    end
    if n > maxN or n ~= #v then return nil, "bad list" end
    local out = {}
    for i = 1, n do
      local entry, why = fn(v[i])
      if entry == nil then return nil, why end
      out[i] = entry
    end
    return out
  end
end

-- a record: required fields (schema[name] = check) and optional ones
-- (opt[name] = check); every other key is dropped
local function record(schema, opt)
  return function(v)
    if type(v) ~= "table" then return nil, "not a record" end
    local out = {}
    for field, check in pairs(schema) do
      local val, why = check(v[field])
      if val == nil then return nil, field .. ": " .. (why or "missing") end
      out[field] = val
    end
    for field, check in pairs(opt or {}) do
      if v[field] ~= nil then
        local val, why = check(v[field])
        if val == nil then return nil, field .. ": " .. (why or "bad") end
        out[field] = val
      end
    end
    return out
  end
end

-- a log line's data: plain JSON (no NaN or infinity), bounded in depth, table
-- length and text length; keys are text or list indices
local function plain(v, depth)
  depth = depth or 1
  local t = type(v)
  if t == "boolean" then return v end
  if t == "number" then
    if not finite(v) then return nil, "not finite" end
    return v
  end
  if t == "string" then
    if #v > Protocol.MAX_LOG_TEXT then return nil, "too long" end
    return v
  end
  if t ~= "table" then return nil, "not plain" end
  if depth > Protocol.MAX_LOG_DEPTH then return nil, "too deep" end
  local out, n = {}, 0
  for k, val in pairs(v) do
    n = n + 1
    if n > Protocol.MAX_LOG_ENTRIES then return nil, "too many entries" end
    if type(k) == "string" then
      if #k > 64 then return nil, "key too long" end
    elseif not (finite(k) and k == math.floor(k) and k >= 1) then
      return nil, "bad key"
    end
    local clean, why = plain(val, depth + 1)
    if clean == nil then return nil, why end
    out[k] = clean
  end
  return out
end
Protocol.plain = plain

local version = int(0, 65535)
local known = mapOf(Protocol.campaignId, Protocol.playerId, Protocol.MAX_KNOWN)

-- the player as everyone sees them (state.players); position only once the
-- player has reported one
local publicPlayer = record({
  id = Protocol.playerId, name = name, game = Protocol.gameId,
  connected = bool,
}, {
  map = Protocol.mapId, x = cell, y = cell, facing = enum(FACINGS),
  travel = enum(TRAVELS), battle = pattern("^b[0-9a-f]+$", 17),
})

-- the lobby view of a player (probe answers and the LAN beacon)
local lobbyPlayer = record({ name = name, game = Protocol.gameId, connected = bool })

local lobby = {
  kind = enum({ coop = true }), protocol = version,
  build = text(Protocol.MAX_BUILD),
  campaign = Protocol.campaignId, title = text(Protocol.MAX_TITLE),
  game = Protocol.gameId, sha1 = Protocol.sha1, host = name,
  players = listOf(lobbyPlayer, Protocol.MAX_PLAYERS),
}

local function withType(t, fields)
  local out = { type = enum({ [t] = true }) }
  for k, v in pairs(fields) do out[k] = v end
  return out
end

local function extend(base, extra)
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(extra) do out[k] = v end
  return out
end

-- one session log line (src/coop/session/SessionLog.lua): `n` numbers a
-- device's own lines; a line passed on is stored with `relay` added, which
-- is never sent (design A1.14)
local logLine = record({
  t = int(0, Protocol.MAX_SEQ), frame = int(0, Protocol.MAX_SEQ),
  device = Protocol.deviceId, n = int(1, Protocol.MAX_SEQ),
  src = enum({ host = true, client = true, device = true }),
  kind = text(Protocol.MAX_LOG_KIND),
}, { name = name, seat = int(1, 2), player = Protocol.playerId, data = plain })

local logBatch = record(withType("log", {
  lines = listOf(logLine, Protocol.MAX_LOG_LINES),
}))

-- what the host accepts from a client ------------------------------------

local identity = {
  protocol = version, build = text(Protocol.MAX_BUILD), name = name,
  game = Protocol.gameId, sha1 = Protocol.sha1,
}

local storySet = mapOf(storyPath, storyValue, Protocol.MAX_STORY)
local storyUnset = listOf(storyPath, Protocol.MAX_STORY)

-- a bag's change (item -> how many, at least one), and a gift the host
-- owes a player: qty < 0 takes (design A6.3, A6.7)
local itemCount = mapOf(Protocol.itemId, int(1, Protocol.MAX_QTY), Protocol.MAX_ITEMS)
local bagChange = record({ gained = itemCount, lost = itemCount }, { spent = bool })
local gift = record({
  seq = seq, item = Protocol.itemId, qty = function(v)
    local n, why = int(-Protocol.MAX_QTY, Protocol.MAX_QTY)(v)
    if n == 0 then return nil, "nothing" end
    return n, why
  end,
}, { once = bool, from = name, race = bool })
Protocol.gift = function(v)
  local ok, out = pcall(gift, v)
  return ok and out or nil
end


-- co-op battles (#18) -----------------------------------------------------

local cmdKinds = {}
for k in pairs(Protocol.CMDS) do cmdKinds[k] = true end
local dataId = pattern("^[A-Z0-9_]+$", 40)
local stats5 = function(max)
  local n = int(0, max)
  return record({ hp = n, attack = n, defense = n, speed = n, special = n })
end
-- a Pokémon as it rides a battle message: the link cable's packed mon
-- (src/link/Protocol.lua packMon), rebuilt and clamped by its unpackMon on
-- the receiving window, and its campaign uid (coopUid, #13)
local mon = record({
  species = dataId, level = int(1, 100), hp = int(0, 999),
  moves = listOf(record({ id = dataId, pp = int(0, 99) }, { ppUps = int(0, 3) }), 4),
}, {
  exp = int(0, 16777215), status = pattern("^[A-Z]+$", 8), sleepTurns = int(0, 7),
  nickname = text(11), dvs = stats5(15), statExp = stats5(65535), ot = text(11),
  otId = int(0, 65535), uid = pattern("^[%w_:%-]+$", 40), extra = plain,
})
local team = function(v)
  local out, why = listOf(mon, Protocol.MAX_TEAM)(v)
  if out and #out == 0 then return nil, "empty team" end
  return out, why
end
Protocol.battleMon = mon
-- a command: what answers the battle's question (Protocol.CMDS)
local cmd = record({ kind = enum(cmdKinds) }, {
  slot = int(1, 4), index = int(1, Protocol.MAX_ROSTER), item = Protocol.itemId,
  move = int(1, 4), yes = bool, forget = int(0, 4), target = Protocol.playerId,
})
-- the battle as the opening window's world prepared it (design A1.10:
-- the host trusts the enemies a window prepared)
local opening = {
  kind = enum({ wild = true, trainer = true }),
  enemy = listOf(mon, Protocol.MAX_TEAM), map = Protocol.mapId,
}
-- a unique encounter (#21, design A10.1 to A10.3): a trainer or a one-off
-- wild Pokémon, by its map object (`trainer:ROUTE_3_obj_5`)
local encounterPattern = pattern("^%l+:[%w_]+$", 48)
local function encounter(v)
  local s, why = encounterPattern(v)
  if not s then return nil, why end
  local kind = s:match("^(%l+):")
  if kind ~= "trainer" and kind ~= "static" then return nil, "encounter kind" end
  return s
end
Protocol.encounter = encounter
local openingOpt = {
  trainer = record({ class = dataId, index = int(1, 64) }, { rival = name }),
  hooked = bool, foe = text(20), encounter = encounter,
}
-- one input of a battle, in the order every window applies them: a team
-- that joined, or an accepted command
local input = record({ kind = enum({ join = true, cmd = true }), player = Protocol.playerId }, {
  name = name, team = team, otId = int(0, 65535), expAll = bool, room = bool, cmd = cmd,
})
-- a running battle in `state`: who started it, against what, who is in it
local battleSummary = record({
  id = Protocol.battleId, by = Protocol.playerId, kind = enum({ wild = true, trainer = true }),
  players = listOf(Protocol.playerId, Protocol.MAX_ROSTER),
}, { foe = text(20), joinable = bool, encounter = encounter })

Protocol.TO_HOST = {
  -- asked before hello on the same link: the host answers whatever the
  -- protocol and creates nobody (design A1.8)
  probe = record(withType("probe", identity), { known = known }),
  -- logs: whether this link carries the device's shared log lines (#31)
  hello = record(withType("hello", extend(identity, {
    device = Protocol.deviceId, seat = int(1, 2),
  })), { known = known, via = text(64), logs = record({ share = bool }) }),
  -- the client's own position; warp is true when its world changed map or
  -- jumped (a warp, a map connection, a fly); travel is how it moves (#15)
  move = record(withType("move", {
    seq = seq, map = Protocol.mapId, x = cell, y = cell,
    facing = enum(FACINGS), warp = bool, travel = enum(TRAVELS),
  })),
  -- leaving on purpose; a dropped link leaves the same way
  bye = record(withType("bye", { seq = seq })),
  -- the device's own session log lines since its last batch (#31)
  log = logBatch,
  -- the player's world as their game just saved it (#13); checkpoint: a
  -- real SAVE that asks the host to save the campaign (design A3.10, A3.11)
  world = record(withType("world", {
    seq = seq, save = blob(Protocol.MAX_WORLD), checkpoint = bool,
  }), { kind = enum(Protocol.SAVE_KINDS) }),
  -- the player's holdings at a rest point (#17, design A7.2): the world
  -- without the PC (World.split), and the PC when it changed
  holdings = record(withType("holdings", { seq = seq, world = blob(Protocol.MAX_WORLD) }),
                    { boxes = blob(Protocol.MAX_WORLD) }),
  -- a window's change to the shared story since its last patch (#14,
  -- design A5.2): entries set (path -> value) and cleared
  -- bag (#16): the window's bag change in the same rest-to-rest change
  patch = record(withType("patch", { seq = seq, set = storySet, unset = storyUnset }),
                 { bag = bagChange }),
  -- co-op battles (#18, design A8): a battle this window's world opened,
  -- with this player's team (otId: their trainer id; expAll: an EXP.ALL in
  -- their bag)
  -- room: a catch fits in their team or PC (#17, design A7.6)
  battle_open = record(withType("battle_open", extend(opening, { seq = seq, team = team })),
                       extend(openingOpt, { otId = int(0, 65535), expAll = bool, room = bool })),
  -- join a running battle with this team (applied at the next safe point)
  battle_join = record(withType("battle_join", { seq = seq, battle = Protocol.battleId,
                                                 team = team }),
                       { otId = int(0, 65535), expAll = bool, room = bool }),
  -- answer the battle's question at revision rev
  battle_cmd = record(withType("battle_cmd", { seq = seq, battle = Protocol.battleId,
                                               rev = int(0, Protocol.MAX_SEQ), cmd = cmd })),
  -- a suggestion to whoever decides (none: take it back)
  battle_suggest = record(withType("battle_suggest", { seq = seq, battle = Protocol.battleId,
                                                       rev = int(0, Protocol.MAX_SEQ) }),
                          { cmd = cmd }),
  -- the window's copy of the battle reached revision rev: it asks `ask` of
  -- player `by`, or it ended with `ended`; hash is its state's digest
  battle_at = record(withType("battle_at", { seq = seq, battle = Protocol.battleId,
                                             rev = int(0, Protocol.MAX_SEQ) }),
                     { ask = enum(Protocol.ASKS), by = Protocol.playerId, hash = text(64),
                       ended = enum(Protocol.RESULTS) }),
  -- LEAVE BATTLE, or call off a queued join (#20, design A11.1, A11.4)
  battle_leave = record(withType("battle_leave", { seq = seq, battle = Protocol.battleId })),
  -- REJOIN a battle this player left
  battle_rejoin = record(withType("battle_rejoin", { seq = seq, battle = Protocol.battleId })),
  -- TAKE OVER for `owner`, who dropped (design A11.6)
  battle_takeover = record(withType("battle_takeover", { seq = seq, battle = Protocol.battleId,
                                                         owner = Protocol.playerId })),
}

-- what a client accepts from the host ------------------------------------

Protocol.TO_CLIENT = {
  probe = record(withType("probe", lobby), {
    refused = text(Protocol.MAX_REASON),
    you = record({}, { player = Protocol.playerId, name = name }),
    port = int(1, 65535),
  }),
  welcome = record(withType("welcome", {
    protocol = version, player = Protocol.playerId,
    last_seq = int(0, Protocol.MAX_SEQ), campaign = Protocol.campaignId,
  })),
  -- saved_ago: seconds since the campaign was last saved (-1: never);
  -- busy: why a save would be refused now ("" when it would not), #13
  state = record(withType("state", {
    players = listOf(publicPlayer, Protocol.MAX_PLAYERS),
    you = Protocol.playerId, last_seq = int(0, Protocol.MAX_SEQ),
    nearby = listOf(Protocol.playerId, Protocol.MAX_PLAYERS),
  }), { saved_ago = int(-1, Protocol.MAX_SEQ), busy = text(Protocol.MAX_REASON),
         battles = listOf(battleSummary, Protocol.MAX_PLAYERS) }),
  -- the player's world from the campaign, once after welcome (#13); none
  -- for a player who never saved in this campaign
  world = record(withType("world", { fresh = bool }), { save = blob(Protocol.MAX_WORLD) }),
  -- a save of the campaign (#13, design A3.12): `you` when this player
  -- asked for it; ok false with the reason when it was refused
  saved = record(withType("saved", { ok = bool, by = name, you = bool }),
                 { reason = text(Protocol.MAX_REASON), kind = enum(Protocol.SAVE_KINDS) }),
  rejected = record(withType("rejected", {
    seq = int(-1, Protocol.MAX_SEQ), reason = text(Protocol.MAX_REASON),
  })),
  ended = record(withType("ended", { reason = text(Protocol.MAX_REASON) })),
  -- other devices' session log lines, passed on once by the host (#31)
  log = logBatch,
  -- the shared story (#14, design A5.2, A5.3): what changed since the last
  -- story this player was sent (`base`: the whole story, replacing what the
  -- window held), at revision `rev`; `applied` is the last of this player's
  -- patches the host has applied
  story = record(withType("story", {
    rev = int(0, Protocol.MAX_SEQ), base = bool, set = storySet, unset = storyUnset,
    applied = int(0, Protocol.MAX_SEQ),
  })),
  -- items owed to this player (#16, design A6): sent once per link, in
  -- order; the window applies each seq once
  gifts = record(withType("gifts", { list = listOf(gift, Protocol.MAX_ITEMS) })),
  -- the uids the host gave rows of this player's last holdings or world
  -- (#17, design A7.3): the row at box (0: the team) and slot, if it still
  -- has fingerprint fp
  uids = record(withType("uids", { list = listOf(record({
    box = int(0, 12), slot = int(1, 20), uid = pattern("^p[0-9a-f]+:%d+$", 40),
    fp = text(200),
  }), Protocol.MAX_ROWS) })),
  -- a battle this player is in or joining (#18): its inputs from `from`
  -- on (rev: how many there are in all), the opening with the first ones,
  -- what it asks of whom, the suggestions, its participants (present or
  -- not), and its end
  battle = record(withType("battle", {
    id = Protocol.battleId, rev = int(0, Protocol.MAX_SEQ), seed = int(1, 2147483646),
    from = int(1, Protocol.MAX_SEQ), inputs = listOf(input, Protocol.MAX_INPUTS),
    players = listOf(record({ id = Protocol.playerId, present = bool }, { left = bool }),
                     Protocol.MAX_ROSTER),
  }), {
    open = record(extend(opening, { by = Protocol.playerId }), openingOpt),
    -- by: who decides (the owner, a stand-in, or the first present player);
    -- owner: whose Pokemon the question is about; offer: an owner who
    -- dropped, whom the present players may take over for (#20)
    ask = enum(Protocol.ASKS), by = Protocol.playerId, owner = Protocol.playerId,
    offer = Protocol.playerId,
    standins = listOf(record({ owner = Protocol.playerId, by = Protocol.playerId }), Protocol.MAX_ROSTER),
    suggestions = listOf(record({ by = Protocol.playerId, cmd = cmd }), Protocol.MAX_PLAYERS),
    ended = enum(Protocol.RESULTS),
  }),
}

Protocol.LOBBY = record(extend(lobby, { port = int(1, 65535) }))

-- Returns the clean message, or nil and why it was dropped.  `side` is the
-- receiver: "host" for what clients send, "client" for what the host sends.
function Protocol.sanitize(raw, side)
  local schemas = side == "host" and Protocol.TO_HOST or Protocol.TO_CLIENT
  if type(raw) ~= "table" then return nil, "not an object" end
  local check = type(raw.type) == "string" and schemas[raw.type]
  if not check then return nil, "unknown type" end
  local ok, msg, why = pcall(check, raw)
  if not ok then return nil, "check failed" end
  if msg == nil then return nil, raw.type .. ": " .. tostring(why) end
  return msg
end

-- the message types each side accepts, sorted (the fuzz test walks them)
function Protocol.types(side)
  local out = {}
  for t in pairs(side == "host" and Protocol.TO_HOST or Protocol.TO_CLIENT) do
    out[#out + 1] = t
  end
  table.sort(out)
  return out
end

return Protocol
