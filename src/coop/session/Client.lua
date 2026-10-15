-- A co-op client (#10): one player's link to the host, over loopback (a
-- split-screen seat, or the hosting device's own player) or ENet.  It sends
-- numbered intentions and keeps what the host last told it; no game rule
-- runs here (design A1.1).
--
--   local c = Client.new(conn, { name = "RED", game = "red", sha1 = "…",
--                                device = "…", seat = 1, known = {…} })
--   c:probe()            -- optional: the lobby view, nobody is created
--   c:join()             -- hello; status becomes "joined" on welcome
--   every frame: c:update()
--   c:move("PALLET_TOWN", 5, 6, "down", false, "walk")
--   c:sendWorld(text, true, "menu")  -- the game saved; ask for a campaign save
--   c:leave()
--
-- The campaign (#13): after the welcome the host sends this player's world
-- (c.world: { fresh, save }), the game's save text the window plays from;
-- each `saved` lands in c.saves (the notices take them) and the last
-- state's saved_ago sets c.savedAt.
--
-- The shared world (#14): c.story is the campaign's story as the host last
-- sent it (a flat map of Ownership paths, nil until the first `story`),
-- c.storyApplied the last of this player's patches the host applied;
-- c:sendPatch(set, unset, bag) sends this window's change (Window.lua decides
-- when).  Story items (#16): c.gifts lists what the host owes this player
-- (Window.lua applies each once and drops it).
--
-- status: idle, probing, probed, joining, joined, refused, ended, closed.
-- A refusal or an end leaves its reason in c.reason.
--
-- With opts.log, a SessionLog that shares (#31), the client sends its
-- device's own lines in a `log` batch every SessionLog.SHARE_INTERVAL
-- seconds and a last one before its bye, and stores the other devices'
-- lines the host passes on.  One link per device carries the log: a second
-- seat of the same device gets no log.

local Protocol = require("src.coop.session.Protocol")
local SessionLog = require("src.coop.session.SessionLog")

local Client = {}
Client.__index = Client

local function defaultClock()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

function Client.new(conn, opts)
  opts = opts or {}
  return setmetatable({
    conn = conn,
    name = opts.name or "PLAYER",
    game = opts.game, sha1 = opts.sha1 or "",
    build = opts.build or "dev",
    device = opts.device or "0", seat = opts.seat or 1,
    known = opts.known or {}, via = opts.via,
    status = "idle", reason = nil,
    seq = 0, player = nil, campaign = nil,
    lobby = nil, state = nil,
    rejections = {}, -- { seq, reason } for intentions the host refused
    world = nil, -- the player's world from the campaign: { fresh, save }
    saves = {}, -- `saved` messages not yet taken: { ok, by, you, reason }
    savedAt = nil, -- clock time the campaign was last saved, by the host's word
    story = nil, -- the shared story as the host last sent it (#14)
    storyApplied = 0, storyRev = 0,
    gifts = {}, -- items the host owes this player, oldest first (#16)
    dropped = 0,
    onWelcome = opts.onWelcome,
    log = opts.log, clock = opts.clock or defaultClock, sharedAt = nil,
  }, Client)
end

function Client:_identity(kind)
  return {
    type = kind, protocol = Protocol.VERSION, build = self.build,
    name = self.name, game = self.game, sha1 = self.sha1, known = self.known,
  }
end

function Client:probe()
  self.status = "probing"
  self.conn:send(self:_identity("probe"))
end

function Client:sharesLog()
  return self.log ~= nil and self.log.share == true
end

function Client:join()
  local hello = self:_identity("hello")
  hello.device, hello.seat, hello.via = self.device, self.seat, self.via
  hello.logs = { share = self:sharesLog() }
  self.status = "joining"
  self.conn:send(hello)
end

-- an intention: numbered, sent only while joined; returns its seq
function Client:send(msg)
  if self.status ~= "joined" then return nil end
  self.seq = self.seq + 1
  msg.seq = self.seq
  self.conn:send(msg)
  return self.seq
end

function Client:move(map, x, y, facing, warp, travel)
  return self:send({ type = "move", map = map, x = x, y = y,
                     facing = facing, warp = warp and true or false,
                     travel = travel or "walk" })
end

-- The player's world as the game just saved it (World.encode's text);
-- checkpoint asks the host to save the campaign (a real SAVE, design
-- A3.11), kind says which.  Returns the seq, or nil when not joined.
function Client:sendWorld(text, checkpoint, kind)
  return self:send({ type = "world", save = text, checkpoint = checkpoint and true or false,
                     kind = kind })
end

-- This window's change to the shared story (#14, design A5.2): entries
-- set (path -> value) and cleared (a list of paths), and the window's bag
-- change in the same change (#16; nil when the bag did not move).  Returns
-- the seq, or nil when not joined.
function Client:sendPatch(set, unset, bag)
  return self:send({ type = "patch", set = set or {}, unset = unset or {}, bag = bag })
end

-- the `saved` messages since the last call, oldest first
function Client:takeSaves()
  local out = self.saves
  self.saves = {}
  return out
end

-- this device's lines since the last batch, every SHARE_INTERVAL seconds
-- (or `now`); true when a batch went out
function Client:shareLog(now)
  if self.status ~= "joined" or not self:sharesLog() then return false end
  local t = self.clock()
  if not now and self.sharedAt and t - self.sharedAt < SessionLog.SHARE_INTERVAL then
    return false
  end
  self.sharedAt = t
  local lines = self.log:take()
  if #lines == 0 then return false end
  self.conn:send({ type = "log", lines = lines })
  return true
end

function Client:leave()
  if self.status == "joined" then
    self:shareLog(true)
    self:send({ type = "bye" })
  end
  self.conn:close()
  self.status = "closed"
end

function Client:_handle(msg)
  local t = msg.type
  if t == "probe" then
    self.lobby = msg
    if self.status == "probing" then self.status = "probed" end
  elseif t == "welcome" then
    self.player, self.campaign = msg.player, msg.campaign
    -- a rejoining player continues after the last number the host saw
    self.seq = math.max(self.seq, msg.last_seq)
    self.status = "joined"
    self.known[msg.campaign] = msg.player
    if self.onWelcome then self.onWelcome(self, msg) end
  elseif t == "state" then
    self.state = msg
    if msg.saved_ago and msg.saved_ago >= 0 then
      self.savedAt = self.clock() - msg.saved_ago
    end
  elseif t == "world" then
    self.world = { fresh = msg.fresh, save = msg.save }
  elseif t == "story" then
    -- the whole story, or what changed since the last one
    if msg.base or not self.story then self.story = {} end
    for path, v in pairs(msg.set) do self.story[path] = v end
    for _, path in ipairs(msg.unset) do self.story[path] = nil end
    self.storyApplied, self.storyRev = msg.applied, msg.rev
  elseif t == "gifts" then
    for _, g in ipairs(msg.list) do self.gifts[#self.gifts + 1] = g end
  elseif t == "saved" then
    if msg.ok then self.savedAt = self.clock() end
    self.saves[#self.saves + 1] = msg
  elseif t == "log" then
    -- other devices' lines; this device's own never come back
    if self.log then
      local lines = {}
      for _, line in ipairs(msg.lines) do
        if line.device ~= self.device then lines[#lines + 1] = line end
      end
      self.log:writeRelayed(lines, "host")
    end
  elseif t == "rejected" then
    -- a refused hello, or a joined link the host drops (a flood)
    if msg.seq == -1 and (self.status ~= "joined" or msg.reason == "flood") then
      self.status, self.reason = "refused", msg.reason
    else
      self.rejections[#self.rejections + 1] = { seq = msg.seq, reason = msg.reason }
    end
  elseif t == "ended" then
    self.status, self.reason = "ended", msg.reason
    self.conn:close()
  end
end

function Client:update()
  self.conn:update()
  for _, raw in ipairs(self.conn:poll()) do
    local msg = Protocol.sanitize(raw, "client")
    if msg then
      self:_handle(msg)
    else
      self.dropped = self.dropped + 1
    end
  end
  self:shareLog()
  if self.conn.closed and self.status ~= "refused" and self.status ~= "ended" then
    if self.status ~= "closed" then self.reason = self.conn.error end
    self.status = "closed"
  end
end

-- the public view of a player in the last state, or nil
function Client:playerView(id)
  for _, p in ipairs(self.state and self.state.players or {}) do
    if p.id == id then return p end
  end
  return nil
end

return Client
