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
-- (Window.lua applies each once and drops it).  Pokémon (#17): the window
-- sends its holdings at rest points (c:sendHoldings(world, boxes), Window
-- decides when); c.uids lists the uids the host gave its rows, for the
-- window to stamp.  A new player's start (#57): c:sendStart(how, text), and
-- c.started holds the seq of the start the host kept.
--
-- Co-op battles (#18): c.battles holds each battle this player is in or
-- joining, as the host sent it: { id, seed, open, inputs, rev, players, ask,
-- by, suggestions, ended }; the inputs accumulate in order.  A battle the
-- host ended stays in c.battles with `ended` until the window drops it
-- (Client:dropBattle).  battleOpen/battleJoin/battleCmd/battleSuggest/
-- battleAt send the intentions.
--
-- Red and Blue (#9): c:sendWild(maps) sends this window's own wild slots
-- once a link (src/coop/game/WildMix.lua); c.wild is the other version's,
-- { game, maps }, once the host passed them (the campaign's switch on).
--
-- The Cable Club (#60): c.cable is this player's cable as the host last
-- said it ({ room, round, mate, name, lead }; nil before any), c.cableLinks
-- the mate's link-cable messages not yet taken ({ round, link, uid }, in
-- order); cableEnter and cableLink send the intentions.
--
-- Friend battles and trades (#23): c.invites holds the invitations this
-- player sent or got, by id, as the host last told them (`answer` once
-- settled); c.pairs the pairings this player is in, by id; c.relay the
-- partner's link battle messages per pairing, in order ({ n, list }).
-- invite/answerInvite/pairMsg/pairEnd/tradeTeam/tradePick/tradeConfirm
-- send the intentions.
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
    device = opts.device or "0", seat = opts.seat or 1, window = opts.window,
    start = opts.start, -- how a new player starts, said on hello (#66)
    known = opts.known or {}, via = opts.via,
    status = "idle", reason = nil,
    seq = 0, player = nil, campaign = nil,
    lobby = nil, state = nil,
    rejections = {}, -- { seq, reason } for intentions the host refused
    world = nil, -- the player's world from the campaign: { fresh, save, restart }
    saves = {}, -- `saved` messages not yet taken: { ok, by, you, reason }
    savedAt = nil, -- clock time the campaign was last saved, by the host's word
    story = nil, -- the shared story as the host last sent it (#14)
    storyApplied = 0, storyRev = 0,
    gifts = {}, -- items the host owes this player, oldest first (#16)
    uids = {}, -- uids the host gave this player's rows: { box, slot, uid, fp } (#17)
    battles = {}, -- battles this player is in or joining, by id (#18)
    wild = nil, -- the other version's wild slots: { game, maps } (#9)
    cable = nil, cableLinks = {}, -- the Cable Club (#60)
    invites = {}, pairs = {}, relay = {}, -- friend battles and trades (#23)
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
  local probe = self:_identity("probe")
  probe.device, probe.seat = self.device, self.seat
  self.conn:send(probe)
end

function Client:sharesLog()
  return self.log ~= nil and self.log.share == true
end

function Client:join()
  local hello = self:_identity("hello")
  hello.device, hello.seat, hello.via = self.device, self.seat, self.via
  hello.window = self.window
  hello.logs = { share = self:sharesLog() }
  hello.start = self.start
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

-- The player's holdings at a rest point (#17, design A7.2): the world
-- without the PC and the PC (World.split's texts), boxes nil when the PC
-- did not change.  Returns the seq, or nil when not joined.
function Client:sendHoldings(world, boxes)
  return self:send({ type = "holdings", world = world, boxes = boxes })
end

-- The opening (#22, design A4.4 to A4.6): this window plays it (done
-- false) or finished it (done true, chose: the starter it picked); rival:
-- the name it gave the rival.  Returns the seq, or nil when not joined.
function Client:sendOpening(done, rival, chose)
  return self:send({ type = "opening", done = done and true or false, rival = rival,
                     chose = chose })
end

-- A rival scene (#59, design A10.5): this window's world started the
-- scene `key` on `map` (on: a claim; the host refuses it `scene_taken`
-- when another player drives that map) or is past it (on false).  The
-- claims stand in state.scenes.  Returns the seq, or nil when not joined.
function Client:sendScene(map, key, on)
  return self:send({ type = "scene", map = map, key = key, on = on and true or false })
end

-- Red and Blue (#9, design A13.4): this window's own version's wild slots
-- (WildMix.tables).  Returns the seq, or nil when not joined.
function Client:sendWild(maps)
  return self:send({ type = "wild", maps = maps })
end

-- How a new player starts (#57, design A4.1 to A4.3): the world the
-- launcher started, whole (World.encode's text); how: "pallet" or "save".
-- The host answers `started` (c.started: that seq; c.seeded: it began the
-- campaign's story) or refuses it.  Returns the seq, or nil when not joined.
function Client:sendStart(how, text)
  return self:send({ type = "start", how = how, save = text })
end

-- The team's League run (#55, design A10.6): "lobby" (this window entered
-- the Indigo Plateau lobby) or "inducted" (it went through the Hall of
-- Fame).  Returns the seq, or nil when not joined.
function Client:sendLeague(event)
  return self:send({ type = "league", event = event })
end

-- The window restarts (#55, design A10.7): "hall" after the Hall of Fame,
-- "reset" otherwise; the host answers with this player's world (c.world
-- with `restart` = this seq).  Returns the seq, or nil when not joined.
function Client:sendRestart(kind)
  return self:send({ type = "restart", kind = kind })
end

-- co-op battles (#18, design A8) ----------------------------------------

-- a battle this window's world opened: opening = { kind, enemy, map,
-- trainer, hooked, foe }, team = the player's packed Pokémon
-- room: a catch fits in this player's team or PC (#17)
function Client:battleOpen(opening, team, otId, expAll, room)
  return self:send({ type = "battle_open", kind = opening.kind, enemy = opening.enemy,
                     map = opening.map, trainer = opening.trainer, hooked = opening.hooked,
                     foe = opening.foe, encounter = opening.encounter, team = team,
                     otId = otId, expAll = expAll, room = room })
end

function Client:battleJoin(id, team, otId, expAll, room)
  return self:send({ type = "battle_join", battle = id, team = team, otId = otId,
                     expAll = expAll, room = room })
end

function Client:battleCmd(id, rev, cmd)
  return self:send({ type = "battle_cmd", battle = id, rev = rev, cmd = cmd })
end

-- cmd nil takes the suggestion back
function Client:battleSuggest(id, rev, cmd)
  return self:send({ type = "battle_suggest", battle = id, rev = rev, cmd = cmd })
end

-- where this window's copy stands: ask/by at rev, or ended
function Client:battleAt(id, rev, ask, by, hash, ended)
  return self:send({ type = "battle_at", battle = id, rev = rev, ask = ask, by = by,
                     hash = hash, ended = ended })
end

-- LEAVE BATTLE (or call off a queued join), REJOIN, TAKE OVER (#20)
function Client:battleLeave(id)
  return self:send({ type = "battle_leave", battle = id })
end

function Client:battleRejoin(id)
  return self:send({ type = "battle_rejoin", battle = id })
end

function Client:battleTakeover(id, owner)
  return self:send({ type = "battle_takeover", battle = id, owner = owner })
end

-- the Cable Club (#60, design A12.7) -------------------------------------

-- enter a room behind the receptionist ("trade", "colosseum"; with: the
-- partner this player offered the cable to), or leave it ("none")
function Client:cableEnter(room, with)
  return self:send({ type = "cable", room = room, with = with })
end

-- a link-cable message for the mate, in the trade's round; uids: with a
-- party, each Pokémon's uid ("" for none)
function Client:cableLink(round, link, uids)
  return self:send({ type = "cable_link", round = round, link = link, uids = uids })
end

-- the mate's link messages since the last call, oldest first
function Client:takeCableLinks()
  local out = self.cableLinks
  self.cableLinks = {}
  return out
end

function Client:dropBattle(id)
  self.battles[id] = nil
end

-- friend battles and trades (#23, design A12) ------------------------------

function Client:invite(to, kind)
  return self:send({ type = "invite", to = to, kind = kind })
end

function Client:answerInvite(id, yes)
  return self:send({ type = "invite_answer", invite = id, yes = yes and true or false })
end

function Client:pairMsg(pair, n, msg)
  return self:send({ type = "pair_msg", pair = pair, n = n, msg = msg })
end

function Client:pairEnd(pair, result)
  return self:send({ type = "pair_end", pair = pair, result = result })
end

function Client:tradeTeam(pair, text)
  return self:send({ type = "trade_team", pair = pair, team = text })
end

function Client:tradePick(pair, slot)
  return self:send({ type = "trade_pick", pair = pair, slot = slot })
end

function Client:tradeConfirm(pair, yes)
  return self:send({ type = "trade_confirm", pair = pair, yes = yes and true or false })
end

-- the partner's link battle messages, kept in order once each
function Client:_pairMsg(msg)
  local r = self.relay[msg.pair]
  if not r then
    r = { n = 0, list = {} }
    self.relay[msg.pair] = r
  end
  if msg.n ~= r.n + 1 then return end
  r.n = msg.n
  r.list[#r.list + 1] = msg.msg
end

function Client:_battle(msg)
  local b = self.battles[msg.id]
  if msg.from == 1 or not b then
    if msg.from ~= 1 or not msg.open then return end -- a tail without its start
    b = { id = msg.id, open = msg.open, inputs = {} }
    self.battles[msg.id] = b
  end
  if msg.from ~= #b.inputs + 1 then return end -- out of order: a new link starts over
  for _, input in ipairs(msg.inputs) do b.inputs[#b.inputs + 1] = input end
  b.seed, b.rev, b.players = msg.seed, msg.rev, msg.players
  b.ask, b.by, b.suggestions, b.ended = msg.ask, msg.by, msg.suggestions or {}, msg.ended
  b.owner, b.offer, b.standins = msg.owner, msg.offer, msg.standins or {}
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
    self.world = { fresh = msg.fresh, save = msg.save, restart = msg.restart }
  elseif t == "story" then
    -- the whole story, or what changed since the last one
    if msg.base or not self.story then self.story = {} end
    for path, v in pairs(msg.set) do self.story[path] = v end
    for _, path in ipairs(msg.unset) do self.story[path] = nil end
    self.storyApplied, self.storyRev = msg.applied, msg.rev
  elseif t == "battle" then
    self:_battle(msg)
  elseif t == "cable" then
    -- another room, mate or round: the mate's messages still waiting
    -- belong to the cable before (a new pairing starts at round 1 again)
    local was = self.cable
    if not was or was.room ~= msg.room or was.mate ~= msg.mate or was.round ~= msg.round then
      self.cableLinks = {}
    end
    self.cable = msg
  elseif t == "cable_link" then
    self.cableLinks[#self.cableLinks + 1] = msg
  elseif t == "invite" then
    self.invites[msg.id] = msg
  elseif t == "pair" then
    self.pairs[msg.id] = msg
  elseif t == "pair_msg" then
    self:_pairMsg(msg)
  elseif t == "gifts" then
    for _, g in ipairs(msg.list) do self.gifts[#self.gifts + 1] = g end
  elseif t == "wild" then
    self.wild = { game = msg.game, maps = msg.maps } -- #9
  elseif t == "started" then
    self.started, self.seeded = msg.seq, msg.seeded -- #57
  elseif t == "uids" then
    for _, u in ipairs(msg.list) do self.uids[#self.uids + 1] = u end
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
