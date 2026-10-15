-- The co-op session this process takes part in (#12): started by the
-- launcher's co-op screens (or the development entry, Dev.lua), it keeps
-- running from the launcher into the game.  One per process.
--
--   local s = Session.startHost({ campaign = c, cartridge = cart, name = "RED" })
--   local s = Session.startDial({ address = "192.168.1.20", cartridge = cart, name = "BLUE" })
--   every frame: s:update(dt, game)   -- game nil while the launcher shows
--   s:join()                          -- a dialled session, once probed
--   s:leave("left")                   -- a bye, or the host ends the session
--
-- Hosting starts the in-process host on a loopback hub (the hosting
-- device's own player dials it like anyone else, design A1.3) and on UDP
-- (ENet) with the LAN beacon.  Dialling probes the host first (design A1.8)
-- and retries every RETRY seconds for DIAL_FOR seconds while nobody answers
-- (design A2.6): partners often press Join first.
--
-- status:
--   hosting side: "joined" once its own player is in, "ended" after leave
--   dialling side: "dialling" (an attempt is under way), "waiting" (for the
--   next attempt), "unreachable" (a minute without an answer), "probed"
--   (the host answered; s.lobby), "refused" (s.reason), "joining",
--   "joined", "ended" (the host closed it; s.reason), "closed" (the link
--   dropped; s.reason)
--
-- Once a game runs, each player's cell goes to the host as it changes
-- (nextMove); the console prints who joined, left and changed maps.  A
-- session that ends while the game runs asks main.lua to go back to the
-- launcher and leaves a note (takeReturn) for the co-op screen.
--
-- The campaign (#13): hosting reads the campaign's file
-- (src/coop/campaign/CampaignFile.lua), or starts it; a file that cannot be
-- read, or is of a newer build, is refused (startHost returns nil and why,
-- with the backup's name).  Once joined, the client holds this player's
-- world from the campaign (worldReady, takeWorld); each time the game
-- saves, its world goes to the host (sendWorld), a real SAVE asking the
-- host to save the campaign; saveRefusal says when the host would refuse.
--
-- The shared world (#14): once joined with a game running, the session's
-- window (src/coop/campaign/Window.lua) sends this player's share of the
-- story and takes the partners' at each rest point
-- (src/coop/game/SharedWorld.lua).  A link that came back keeps its window.
--
-- A dropped link in a running game (#20, design A11.9 to A11.11): the
-- joining side redials as the same player every REDIAL seconds for
-- REDIAL_FOR seconds ("reconnecting"); the world keeps running and sends
-- nothing until the host has the player back, and the first position after
-- that counts as a warp.  A game back from a pause longer than RESUME_AFTER
-- seconds closes its link and dials at once.  A session that ends under a
-- running game shows why over the world for END_SHOW seconds before the
-- launcher.  `linkNote` tells the game what to say ("lost", "back",
-- "ended"; src/coop/game/Presence.lua).

local Transport = require("src.coop.session.Transport")
local Protocol = require("src.coop.session.Protocol")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local Beacon = require("src.coop.session.Beacon")
local Identity = require("src.coop.session.Identity")
local SessionLog = require("src.coop.session.SessionLog")
local Json = require("src.link.Json")
local Campaign = require("src.coop.campaign.Campaign")
local CampaignFile = require("src.coop.campaign.CampaignFile")
local Store = require("src.coop.campaign.Store")
local World = require("src.coop.campaign.World")
local Window = require("src.coop.campaign.Window")

local Session = { current = nil }
Session.__index = Session

Session.RETRY = 3       -- seconds between dial attempts
Session.DIAL_FOR = 60   -- seconds of attempts before "could not reach"
Session.REDIAL = 2          -- seconds between redials of a dropped link (A11.9)
Session.REDIAL_FOR = 120    -- seconds a dropped game redials before it gives up
Session.RESUME_AFTER = 3    -- seconds of pause after which a joiner dials afresh (A11.10)
Session.END_SHOW = 3        -- seconds the end of a session shows over the world (A11.11)
Session.RETURN_FILE = "coop/return.json"
Session.RETURN_FRESH = 120 -- seconds a return note is shown for

local function say(fmt, ...)
  print("co-op: " .. fmt:format(...))
end

local function defaultClock()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

local function saveFs()
  return love and love.filesystem
end

-- the cartridge of the game `version` as the host compares it
function Session.cartridge(version)
  local GameVersion = require("src.core.GameVersion")
  version = version or GameVersion.get()
  local info = GameVersion.info(version)
  return { game = version, sha1 = info and info.sha1 or "" }
end

local function newSession(kind, opts)
  local s = setmetatable({
    kind = kind, opts = opts, name = opts.name,
    cartridge = opts.cartridge, clock = opts.clock or defaultClock,
    frames = 0, names = {}, maps = {}, last = nil,
    status = "idle", reason = nil, seat = opts.seat or 1,
  }, Session)
  s.identity = opts.identity or Identity.load(Identity.saveFolderStore())
  if opts.log ~= false then
    s.log = SessionLog.open({ fs = opts.logFs or SessionLog.saveFolderFs(),
                              device = s.identity.device, name = opts.name, seat = s.seat,
                              share = opts.shareLogs ~= false,
                              frame = function() return s.frames end })
  end
  return s
end

function Session:_client(conn, hostKey, via)
  local identity = self.identity
  self.hostKey = hostKey
  self.client = Client.new(conn, {
    name = self.name, game = self.cartridge.game, sha1 = self.cartridge.sha1,
    device = identity.device, seat = self.seat, known = identity:known(hostKey, self.seat), via = via,
    clock = self.opts.clock,
    -- the host's own player: its lines are already in the host's log; one
    -- link per device carries the log, the first seat's (#11)
    log = self.kind == "join" and self.seat == 1 and self.log or nil,
    onWelcome = function(c, msg)
      identity:remember(hostKey, self.seat, msg.campaign, msg.player)
      say("joined campaign %s as %s (%s)", msg.campaign, msg.player, c.name)
    end,
  })
  return self.client
end

-- The campaign's state from its file, or a new one; nil and
-- { why, backup } when the file is refused (design A3.5).  `fs` is
-- CampaignFile's file calls.
function Session.openCampaign(fs, campaign, cartridge)
  local state, info = CampaignFile.read(fs, cartridge.game, campaign.id)
  if state then return state, info end
  if info.why ~= "missing" then return nil, info end
  -- a new campaign's rival is the one its host named, if any (#22)
  return Campaign.new({ id = campaign.id, title = campaign.title, game = cartridge.game,
                        sha1 = cartridge.sha1, created = os.time(),
                        rival = campaign.rival }), { new = true }
end

-- Host a campaign ({ id, title, players }) with this device's cartridge.
-- opts: name, port, shareLogs, listen (false: loopback only), beacon
-- (false: none), onRoster(roster) when the players change, campaignFs
-- (CampaignFile's file calls; the save folder's by default, false: no
-- file); tests pass identity, logFs or log = false, clock, hex.  Returns
-- the session, or nil and { why, backup } when the campaign's file is
-- refused.
function Session.startHost(opts)
  local campaign = opts.campaign
  local state, store, info
  local campaignFs = opts.campaignFs
  if campaignFs == nil and love and love.filesystem then campaignFs = CampaignFile.loveFs() end
  if campaignFs then
    state, info = Session.openCampaign(campaignFs, campaign, opts.cartridge)
    if not state then
      say("campaign %s refused: %s", campaign.id, tostring(info.why))
      return nil, info
    end
  end
  local s = newSession("host", opts)
  s.port = opts.port or Transport.DEFAULT_PORT
  if state then
    store = Store.new({ campaign = state, fs = campaignFs, clock = opts.clock,
                        saved = not info.new,
                        log = s.log and function(kind, data) s.log:write("host", kind, data) end })
    -- a new campaign has its file from the start
    if info.new then store:checkpoint("new") end
  end
  s.host = Host.new({
    campaign = { id = campaign.id, title = campaign.title },
    players = campaign.players, state = state, store = store,
    cartridge = s.cartridge, hostName = opts.name, port = s.port, log = s.log,
    device = s.identity.device, clock = opts.clock, hex = opts.hex,
  })
  s.hub = s.host:serve(Transport.loopback())
  if opts.listen ~= false then
    local listener, err = (opts.listen or Transport.listen)(s.port)
    if listener then
      s.host:serve(listener)
      s.listening = true
      say("hosting on UDP port %d (campaign %s)", s.port, campaign.id)
      if opts.beacon ~= false then
        s.beacon = Beacon.sender({ lobby = function() return s.host:lobby() end })
      end
    else
      s.listenError = tostring(err)
      say("only local players: %s", s.listenError)
    end
  end
  s:_client(s.hub:dial(), "loopback", nil)
  s.client:join()
  s.status = "joining"
  Session.current = s
  return s
end

-- Dial a host at `address` and probe it; join() once it answered.
-- opts: name, shareLogs, dial (Transport.dial by default), seat (2: a
-- split-screen device's second player, #11); tests pass identity, logFs or
-- log = false, clock.
function Session.startDial(opts)
  local s = newSession("join", opts)
  s.address = opts.address
  s.dialFn = opts.dial or Transport.dial
  s.dialStarted = s.clock()
  s:_attempt()
  Session.current = s
  return s
end

function Session:_attempt()
  local conn = self.dialFn(self.address)
  self.attempts = (self.attempts or 0) + 1
  self.attemptAt = self.clock()
  self:_client(conn, self.address, self.address)
  self.client:probe()
  self.status = "dialling"
end

-- seconds left of the minute of attempts, and until the next attempt
function Session:dialTimes()
  local now = self.clock()
  local left = math.max(0, Session.DIAL_FOR - (now - (self.dialStarted or now)))
  local nextIn = 0
  if self.status == "waiting" then
    nextIn = math.max(0, (self.attemptAt or now) + Session.RETRY - now)
  end
  return left, nextIn
end

-- Try now: a new attempt at once (a new minute after "could not reach")
function Session:retryNow()
  if self.kind ~= "join" then return end
  if self.status == "unreachable" then self.dialStarted = self.clock() end
  if self.status ~= "waiting" and self.status ~= "unreachable"
      and self.status ~= "dialling" then
    return
  end
  if self.client then self.client.conn:close() end
  self:_attempt()
end

-- the hello on the probed link; `name` replaces the player's name (a new
-- player names themself)
function Session:join(name)
  if self.kind ~= "join" or self.status ~= "probed" then return false end
  if Protocol.name(name) then
    self.name = name
    self.client.name = name
  end
  self.client:join()
  self.status = "joining"
  return true
end

-- the campaign (#13) --------------------------------------------------------

-- true once the host has sent this player's world (or said there is none)
function Session:worldReady()
  return self.client ~= nil and self.client.world ~= nil
end

-- this player's world from the campaign: a save table, or nil for a player
-- who never saved in it (a fresh start); `false` when it did not read
function Session:takeWorld()
  local w = self.client and self.client.world
  if not w or w.fresh or not w.save then return nil end
  local save = World.decode(w.save)
  return save or false
end

-- why the host would refuse a save now ("battle_in_progress"), or nil
function Session:saveRefusal()
  local state = self.client and self.client.state
  if state and state.busy and state.busy ~= "" then return state.busy end
  return nil
end

-- The game saved `save` (its live save table): the world goes to the host.
-- checkpoint: a real SAVE, which asks the host to save the campaign
-- (design A3.10, A3.11); kind names it.  Returns the seq, or nil.
function Session:sendWorld(save, checkpoint, kind)
  local c = self.client
  if not (c and c.status == "joined") or type(save) ~= "table" then return nil end
  local ok, text = pcall(World.encode, save)
  if not ok or #text > Protocol.MAX_WORLD then
    say("world not sent: %s", ok and "too long" or tostring(text))
    return nil
  end
  return c:sendWorld(text, checkpoint, kind)
end

-- seconds since the campaign was last saved, by the host's word; nil when
-- it never was
function Session:savedAgo()
  local at = self.client and self.client.savedAt
  if not at then return nil end
  return math.max(0, self.clock() - at)
end

-- the `saved` messages since the last call (the notices take them)
function Session:takeSaves()
  return self.client and self.client:takeSaves() or {}
end

-- the hosting app is paused: the host saves (design A3.9); a joining app
-- notes when (design A11.10)
function Session.pause()
  local s = Session.current
  if s and not s.pausedAt then s.pausedAt = s.clock() end
  if s and s.host then return s.host:pause() end
  return false
end

-- the app is back: a joining game paused longer than RESUME_AFTER seconds
-- closes its link and dials at once, its link likely gone stale (A11.10)
function Session.resume()
  local s = Session.current
  if not (s and s.pausedAt) then return end
  local away = s.clock() - s.pausedAt
  s.pausedAt = nil
  if s.kind == "join" and s.inGame and away > Session.RESUME_AFTER
     and s.client and s.client.status == "joined" then
    s.client.conn:close()
    s.redialNow = true
  end
end

-- what the hosting screen shows: the players with the cartridge they play
function Session:roster()
  if self.host then return self.host:roster() end
  local out = {}
  for _, p in ipairs(self.client and self.client.state and self.client.state.players or {}) do
    out[#out + 1] = { id = p.id, name = p.name, game = p.game, connected = p.connected }
  end
  return out
end

-- partners in the session right now (not this device's own player)
function Session:partners()
  local n = 0
  local me = self.client and self.client.player
  for _, p in ipairs(self:roster()) do
    if p.connected and p.id ~= me then n = n + 1 end
  end
  return n
end

-- The move to report for this player's cell `cur` ({ mapId, x, y,
-- facing }) after `last`, or nil when nothing is to be sent.  warp when the
-- map changed or the player jumped (a warp tile, fly, a whiteout) or after
-- a refused step.  A step through a map connection shows a cell off the map
-- for a frame (y = -1 on the next map); that one is skipped, so the settled
-- cell on the new map goes out as the map change.
function Session.nextMove(last, cur, resync)
  if not cur or type(cur.x) ~= "number" or type(cur.y) ~= "number" then return nil end
  if cur.x < 0 or cur.y < 0 or cur.x > Protocol.MAX_CELL or cur.y > Protocol.MAX_CELL then
    return nil
  end
  local map = tostring(cur.mapId)
  local facing = cur.facing or "down"
  local travel = cur.travel or "walk"
  if last and last.map == map and last.x == cur.x and last.y == cur.y
     and last.facing == facing and last.travel == travel and not resync then
    return nil
  end
  local warp = not last or last.map ~= map
    or math.abs(last.x - cur.x) + math.abs(last.y - cur.y) > 2 or resync and true or false
  return { map = map, x = cur.x, y = cur.y, facing = facing, warp = warp, travel = travel }
end

-- This player's cell as the others see it: the cell a step heads for, so
-- their screens ease it while this one walks it (#15), and how the player
-- travels (walk, run, bike, surf); nil without an overworld.
function Session.position(game)
  local ow = require("src.world.WorldAPI").new(game):overworld()
  local p = ow and ow.player
  if not p then return nil end
  local travel = p.onBike and "bike" or p.surfing and "surf" or p.running and "run" or "walk"
  if game.save and game.save.onBike and not p.surfing then travel = "bike" end
  local x, y = p.cellX, p.cellY
  if p.moving and p.targetX then x, y = p.targetX, p.targetY end
  return { mapId = ow.map.id, x = x, y = y, facing = p.facing, travel = travel }
end

function Session:_report(game)
  local m = Session.nextMove(self.last, Session.position(game), self.resync)
  if m and self.client:move(m.map, m.x, m.y, m.facing, m.warp, m.travel) then
    self.last = m
    self.resync = false
  end
end

-- console lines for what changed among the other players
function Session:_narrate()
  local state = self.client.state
  if not state or state == self.seenState then return end
  self.seenState = state
  for _, p in ipairs(state.players) do
    if p.id ~= self.client.player then
      local was = self.names[p.id]
      if p.connected and was ~= "on" then say("%s joined", p.name) end
      if not p.connected and was == "on" then say("%s left", p.name) end
      self.names[p.id] = p.connected and "on" or "off"
      if p.map and p.map ~= self.maps[p.id] then
        say("%s is on %s (%d,%d)", p.name, p.map, p.x or 0, p.y or 0)
        self.maps[p.id] = p.map
      end
    end
  end
end

-- the players the host has seen, saved to the campaign card as they change
function Session:_watchRoster()
  local onRoster = self.opts.onRoster
  if not onRoster then return end
  local roster = self.host:roster()
  local parts = {}
  for _, p in ipairs(roster) do
    parts[#parts + 1] = p.id .. (p.connected and "+" or "-") .. tostring(p.via)
  end
  local key = table.concat(parts, ",")
  if key ~= self.rosterKey then
    self.rosterKey = key
    onRoster(roster)
  end
end

local ENDS = { refused = true, ended = true, closed = true }

-- One frame.  `game` is the running game, nil while the launcher shows.
-- Returns "launcher" when the session ended under a running game.
function Session:update(dt, game)
  if self.status == "ended" and not self.client then return nil end
  self.frames = self.frames + 1
  if self.host then self.host:update() end
  if self.beacon then self.beacon:update(dt) end
  local c = self.client
  if not c then return nil end
  local before = c.status
  c:update()
  if c.status ~= before and self.log then
    self.log:write("client", c.status, { reason = c.reason }, c.player)
  end
  if self.kind == "join" and (self.status == "dialling" or self.status == "waiting") then
    if c.status == "probed" then
      self.lobby = c.lobby
      if c.lobby.refused ~= "" then
        self.status, self.reason = "refused", c.lobby.refused
        c.conn:close()
      else
        self.status = "probed"
      end
    elseif c.status == "closed" then
      -- no answer: try again every RETRY seconds for DIAL_FOR seconds
      local now = self.clock()
      self.lastError = c.reason
      if now - self.dialStarted >= Session.DIAL_FOR then
        self.status, self.reason = "unreachable", c.reason
      elseif now - self.attemptAt >= Session.RETRY then
        self:_attempt()
      else
        self.status = "waiting"
      end
    end
    return nil
  end
  if self.status == "joining" and c.status == "joined" then self.status = "joined" end
  local live = self.status == "probed" or self.status == "joining" or self.status == "joined"
  if live and ENDS[c.status] and before ~= c.status then
    if c.status == "closed" and self.kind == "join" and self.inGame and not self.leaving then
      -- the link dropped under a running game: redial (design A11.9)
      self.status = "reconnecting"
      self.redialStarted, self.redialAt = self.clock(), self.clock()
      self.lostReason = c.reason
      self.linkNote = "lost"
      say("lost the host (%s): reconnecting", tostring(c.reason))
    else
      self.status, self.reason = c.status, c.reason
      if c.status == "refused" or c.status == "ended" or c.status == "closed" then
        say("%s (%s)", c.status, tostring(c.reason))
      end
    end
  end
  if self.status == "reconnecting" then
    self:_redial()
    c = self.client
  end
  for i = (self.seenRejections or 0) + 1, #c.rejections do
    if c.rejections[i].reason == "bad_step" then self.resync = true end
  end
  self.seenRejections = #c.rejections
  if self.host then self:_watchRoster() end
  if c.status == "joined" then
    -- a link that came back keeps its window (#20)
    if not self.window then self.window = Window.new(c) end
    if self.window.client ~= c then self.window.client = c end
    if game then
      self.inGame = true
      -- a co-op bag holds 40 rows while the session's world is open (#16, A6.8)
      require("src.coop.campaign.Items").openBag(game.data)
      self:_report(game)
      require("src.coop.game.SharedWorld").step(self.window, game)
      require("src.coop.game.Battles").step(game)
      require("src.coop.game.Friends").step(game) -- #23
    end
    self:_narrate()
  end
  if self.inGame and ENDS[self.status] then
    local notice = self.status == "ended" and "The host closed the session."
      or self.status == "refused" and ("The host turned this game away (" .. tostring(self.reason) .. ").")
      or "The connection to the host was lost."
    -- why, over the world, before the launcher (design A11.11)
    local now = self.clock()
    if game and self.kind == "join" and not self.leaving then
      if not self.endShowUntil then
        self.endShowUntil = now + Session.END_SHOW
        self.linkNote = "ended"
        return nil
      end
      if now < self.endShowUntil then return nil end
    end
    self:_stop()
    Session.writeReturn(notice, self.cartridge.game)
    return "launcher"
  end
  return nil
end

-- one frame of reconnecting (design A11.9): a new link every REDIAL
-- seconds, a hello as the same player, until REDIAL_FOR seconds are over
function Session:_redial()
  local c = self.client
  local now = self.clock()
  if c and c.status == "joined" then
    self.status = "joined"
    self.resync = true -- the first position after a reconnect is a warp
    self.redialStarted = nil
    self.linkNote = "back"
    say("back in the session")
    return
  end
  if c and c.status == "refused" then
    self.status, self.reason = "refused", c.reason
    return
  end
  if now - (self.redialStarted or now) >= Session.REDIAL_FOR then
    self.status, self.reason = "closed", self.lostReason or (c and c.reason)
    return
  end
  local waiting = c and (c.status == "joining") and now - self.redialAt < Session.REDIAL * 2
  if not waiting and (self.redialNow or now - self.redialAt >= Session.REDIAL) then
    self.redialNow = nil
    self.redialAt = now
    if c and not c.conn.closed then c.conn:close() end
    self:_client(self.dialFn(self.address), self.address, self.address)
    self.client:join()
  end
end

-- close everything without a note
function Session:_stop()
  if Session.current == self then Session.current = nil end
  require("src.coop.campaign.Items").closeBag()
  local c = self.client
  self.client = nil
  if c then c:leave() end
  if self.host then
    self.host:shutdown(self.endReason or "host_quit")
    self.host:update()
    self.host:_finish()
  elseif self.log then
    self.log:close()
  end
  if self.beacon then self.beacon:close() end
  self.beacon = nil
  if self.status ~= "refused" and self.status ~= "closed" and self.status ~= "unreachable" then
    self.status = "ended"
  end
end

-- Leave on purpose: a guest sends its bye, a host ends the session for
-- everyone.  In a running game the co-op screen says why afterwards.
function Session:leave(notice)
  if Session.current ~= self and not self.client then return end
  self.leaving = true
  self.status = "ended"
  self:_stop()
  if self.inGame and notice then Session.writeReturn(notice, self.cartridge.game) end
  -- a game that left (the CO-OP menu's LEAVE SESSION) goes back to the
  -- launcher too (#15)
  if self.inGame then Session.launcherWanted = true end
end

-- true once, after a running game left its session
function Session.takeLauncher()
  local want = Session.launcherWanted
  Session.launcherWanted = nil
  return want == true
end

-- A note for the co-op screen when the launcher opens again after a session
-- that ran in the game (the game's window closed, or the host ended it).
function Session.writeReturn(notice, version)
  local fs = saveFs()
  if not (fs and fs.write) then return end
  pcall(fs.createDirectory, "coop")
  pcall(fs.write, Session.RETURN_FILE, Json.encode({
    notice = notice, version = version, t = os.time(),
  }))
end

-- the note, once; nil when there is none or it is stale
function Session.takeReturn()
  local fs = saveFs()
  if not (fs and fs.getInfo and fs.getInfo(Session.RETURN_FILE)) then return nil end
  local text = fs.read(Session.RETURN_FILE)
  pcall(fs.remove, Session.RETURN_FILE)
  local ok, data = pcall(Json.decode, type(text) == "string" and text or "null")
  if not ok or type(data) ~= "table" or type(data.notice) ~= "string" then return nil end
  if type(data.t) ~= "number" or math.abs(os.time() - data.t) > Session.RETURN_FRESH then
    return nil
  end
  return { notice = data.notice:sub(1, 120),
           version = Protocol.gameId(data.version) and data.version or nil }
end

-- the running session, every frame (main.lua's hook and the launcher)
function Session.tick(dt, game)
  if game and Session.takeLauncher() then return "launcher" end
  local s = Session.current
  if not s then return nil end
  return s:update(dt, game)
end

-- the process quits: a running session says goodbye, and the co-op screen
-- says so when the launcher opens again
function Session.shutdown()
  -- a split-screen second player leaves first (design A11.13, #11)
  local Split = package.loaded["src.coop.split.Split"]
  if Split then Split.stop() end
  local s = Session.current
  if not s then return end
  s:leave(s.kind == "host" and "You closed the session." or "You left the session.")
end

return Session
