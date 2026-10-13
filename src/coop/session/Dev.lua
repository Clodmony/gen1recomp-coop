-- The development entry to a co-op session (#10), until the launcher's
-- co-op screens exist (#12).  Start the game with
--
--   love . --coop-host[=PORT] [--coop-name=NAME] [--coop-logs=off]
--   love . --coop-join=ADDRESS[:PORT] [--coop-name=NAME] [--coop-logs=off]
--
-- (or POKEPORT_COOP_HOST=PORT, POKEPORT_COOP_JOIN=ADDRESS,
-- POKEPORT_COOP_NAME=NAME, POKEPORT_COOP_LOGS=off for scripted runs).
-- The session log is shared with the other players unless logs are off
-- (#31).  Once a game runs, the host
-- side starts the in-process host on UDP PORT (default 24680) with the LAN
-- beacon, and its own player dials it over loopback; the join side dials the
-- address.  Each player's position is reported to the host as it moves; the
-- console prints who joined, left and changed maps.  Nothing of the other
-- players is drawn yet (#15).

local Transport = require("src.coop.session.Transport")
local Protocol = require("src.coop.session.Protocol")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local Beacon = require("src.coop.session.Beacon")
local Identity = require("src.coop.session.Identity")
local SessionLog = require("src.coop.session.SessionLog")
local Random = require("src.coop.session.Random")

local Dev = { config = nil }

local function say(fmt, ...)
  print("co-op: " .. fmt:format(...))
end

-- reads the --coop-* arguments, then the environment; nil when neither asks
function Dev.parse(args, getenv)
  getenv = getenv or os.getenv
  local cfg = {}
  for _, a in ipairs(args or {}) do
    local key, value = tostring(a):match("^%-%-coop%-(%a+)=?(.*)$")
    if key == "host" then
      cfg.mode, cfg.port = "host", tonumber(value)
    elseif key == "join" and value ~= "" then
      cfg.mode, cfg.address = "join", value
    elseif key == "name" and value ~= "" then
      cfg.name = value
    elseif key == "logs" then
      cfg.logs = value
    end
  end
  if not cfg.mode then
    local hostPort, joinAddress = getenv("POKEPORT_COOP_HOST"), getenv("POKEPORT_COOP_JOIN")
    if hostPort and hostPort ~= "" then
      cfg.mode, cfg.port = "host", tonumber(hostPort)
    elseif joinAddress and joinAddress ~= "" then
      cfg.mode, cfg.address = "join", joinAddress
    end
  end
  if not cfg.mode then return nil end
  cfg.name = cfg.name or getenv("POKEPORT_COOP_NAME")
  if not Protocol.name(cfg.name) then cfg.name = cfg.mode == "host" and "HOST" or "GUEST" end
  cfg.port = cfg.port or Transport.DEFAULT_PORT
  -- sharing the session log defaults on (#31, design A1.14)
  local logs = (cfg.logs or getenv("POKEPORT_COOP_LOGS") or ""):lower()
  cfg.logs = nil
  cfg.shareLogs = not (logs == "off" or logs == "0" or logs == "no" or logs == "false")
  return cfg
end

function Dev.configure(args)
  Dev.config = Dev.parse(args)
  if Dev.config then
    say("%s requested (%s)", Dev.config.mode,
        Dev.config.mode == "host" and ("port " .. Dev.config.port) or Dev.config.address)
  end
end

local function cartridge()
  local GameVersion = require("src.core.GameVersion")
  local version = GameVersion.get()
  local info = GameVersion.info(version)
  return { game = version, sha1 = info and info.sha1 or "" }
end

function Dev.start(game)
  local cfg = Dev.config
  local s = { game = game, last = nil, names = {}, maps = {} }
  Dev.session = s
  local cart = cartridge()
  local identity = Identity.load(Identity.saveFolderStore())
  s.identity = identity
  s.frames = 0
  s.log = SessionLog.open({ fs = SessionLog.saveFolderFs(), device = identity.device,
                            name = cfg.name, seat = 1, share = cfg.shareLogs,
                            frame = function() return s.frames end })
  local conn, hostKey
  if cfg.mode == "host" then
    s.host = Host.new({
      campaign = { id = "c" .. Random.hex(16), title = cart.game:upper() .. " CO-OP" },
      cartridge = cart, hostName = cfg.name, port = cfg.port, log = s.log,
      device = identity.device,
    })
    local hub = s.host:serve(Transport.loopback())
    local listener, err = Transport.listen(cfg.port)
    if listener then
      s.host:serve(listener)
      say("hosting on UDP port %d (campaign %s)", cfg.port, s.host.campaign.id)
      s.beacon = Beacon.sender({ lobby = function() return s.host:lobby() end })
    else
      say("only local players: %s", tostring(err))
    end
    conn, hostKey = hub:dial(), "loopback"
  else
    conn, hostKey = Transport.dial(cfg.address), cfg.address
    say("dialling %s", conn.address or cfg.address)
  end
  s.client = Client.new(conn, {
    name = cfg.name, game = cart.game, sha1 = cart.sha1, device = identity.device,
    seat = 1, known = identity:known(hostKey, 1), via = cfg.address,
    -- the host's own player: its lines are already in the host's log
    log = cfg.mode == "join" and s.log or nil,
    onWelcome = function(c, msg)
      identity:remember(hostKey, 1, msg.campaign, msg.player)
      say("joined campaign %s as %s (%s)", msg.campaign, msg.player, c.name)
    end,
  })
  s.client:join()
end

-- The move to report for this player's cell `cur` ({ mapId, x, y,
-- facing }) after `last`, or nil when nothing is to be sent.  warp when the
-- map changed or the player jumped (a warp tile, fly, a whiteout) or after
-- a refused step.  A step through a map connection shows a cell off the map
-- for a frame (y = -1 on the next map); that one is skipped, so the settled
-- cell on the new map goes out as the map change.
function Dev.nextMove(last, cur, resync)
  if not cur or type(cur.x) ~= "number" or type(cur.y) ~= "number" then return nil end
  if cur.x < 0 or cur.y < 0 or cur.x > Protocol.MAX_CELL or cur.y > Protocol.MAX_CELL then
    return nil
  end
  local map = tostring(cur.mapId)
  local facing = cur.facing or "down"
  if last and last.map == map and last.x == cur.x and last.y == cur.y
     and last.facing == facing and not resync then
    return nil
  end
  local warp = not last or last.map ~= map
    or math.abs(last.x - cur.x) + math.abs(last.y - cur.y) > 2 or resync and true or false
  return { map = map, x = cur.x, y = cur.y, facing = facing, warp = warp }
end

local function report(s)
  local WorldAPI = require("src.world.WorldAPI")
  local m = Dev.nextMove(s.last, WorldAPI.new(s.game):current(), s.resync)
  if m and s.client:move(m.map, m.x, m.y, m.facing, m.warp) then
    s.last = m
    s.resync = false
  end
end

-- console lines for what changed among the other players
local function narrate(s)
  local state = s.client.state
  if not state or state == s.seenState then return end
  s.seenState = state
  for _, p in ipairs(state.players) do
    if p.id ~= s.client.player then
      local was = s.names[p.id]
      if p.connected and was ~= "on" then say("%s joined", p.name) end
      if not p.connected and was == "on" then say("%s left", p.name) end
      s.names[p.id] = p.connected and "on" or "off"
      if p.map and p.map ~= s.maps[p.id] then
        say("%s is on %s (%d,%d)", p.name, p.map, p.x or 0, p.y or 0)
        s.maps[p.id] = p.map
      end
    end
  end
end

function Dev.update(dt, game)
  if not Dev.config or not game then return end
  if not Dev.session then Dev.start(game) end
  local s = Dev.session
  s.frames = s.frames + 1
  if s.host then s.host:update() end
  if s.beacon then s.beacon:update(dt) end
  local c = s.client
  local before = c.status
  c:update()
  if c.status ~= before then
    if s.log then s.log:write("client", c.status, { reason = c.reason }, c.player) end
    if c.status == "refused" or c.status == "ended" or c.status == "closed" then
      say("%s (%s)", c.status, tostring(c.reason))
    end
  end
  for i = (s.seenRejections or 0) + 1, #c.rejections do
    if c.rejections[i].reason == "bad_step" then s.resync = true end
  end
  s.seenRejections = #c.rejections
  if c.status == "joined" then
    report(s)
    narrate(s)
  end
end

function Dev.shutdown()
  local s = Dev.session
  if not s then return end
  Dev.session = nil
  if s.client then s.client:leave() end
  if s.host then
    s.host:shutdown("host_quit")
    s.host:update()
    s.host:_finish()
  elseif s.log then
    s.log:close()
  end
  if s.beacon then s.beacon:close() end
end

return Dev
