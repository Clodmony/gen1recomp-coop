-- A friend battle in the window (#23, design A12.3 to A12.5, decision
-- G31): upstream's lockstep link battle (src/link/LinkBattle.lua) between
-- two players of the campaign, over the co-op session (Relay.lua) instead
-- of a cable.  Each window runs the whole battle from its own side, so each
-- player sees their own team as allies and picks their own moves,
-- switches and replacements; the host deals the seed and passes the
-- messages on (HostFriends.lua) but runs nothing; nobody else sees it.
--
--   local wait = FriendBattle.start(game, pair, { client = fn, onEnd = fn })
--
-- The waiting box ("Waiting for BLUE...") stands over the map while the two
-- windows exchange what upstream's link session exchanges first (the
-- hello, which checks both games and mods, and each party); then the
-- battle comes in behind the battle transition, where the player stood.
-- B on the waiting box calls it off for both.
--
-- The cable's rules are upstream's: no items, no money, the copies take the
-- damage and the real team none.  On top of them (A12.3 to A12.5):
--   * RUN forfeits: the player who runs loses, the partner wins;
--   * a partner whose link dropped is waited for (the battle waits for
--     their turn); after the host's two minutes the pairing is released
--     and the battle ends as a draw ("<NAME> left the battle.");
--   * afterwards the team is healed (HP, PP, status) where it stood; no
--     prize, no story, no whiteout;
--   * each Pokémon gets the full trainer EXP and stat EXP of every distinct
--     opposing Pokémon it stood against, won or lost, not split among the
--     team; a traded Pokémon's boost, levels, moves to learn and evolution
--     as the engine does them.  A Pokémon "stood against" a foe when both
--     were out with HP left at the same time.

local Strings = require("src.core.Strings")
local Relay = require("src.coop.friends.Relay")

local FriendBattle = {}

-- the battle's tracker: which of my Pokémon (by party index) stood against
-- which of theirs
local function indexOf(list, item)
  for i, v in ipairs(list or {}) do if v == item then return i end end
  return nil
end

function FriendBattle.track(s)
  local p, e = s.player and s.player.mon, s.enemy and s.enemy.mon
  if not (p and e and (p.hp or 0) > 0 and (e.hp or 0) > 0) then return end
  local i, j = indexOf(s.playerParty, p), indexOf(s.enemyParty, e)
  if not (i and j) then return end
  s.faced = s.faced or {}
  s.faced[i] = s.faced[i] or {}
  s.faced[i][j] = true
end

-- The award list after the battle: { index, foe = { species, level } } in
-- party order, then the foe's order (A12.5)
function FriendBattle.awards(s)
  local out = {}
  for i = 1, #(s.playerParty or {}) do
    local seen = s.faced and s.faced[i]
    if seen then
      for j = 1, #(s.enemyParty or {}) do
        local foe = seen[j] and s.enemyParty[j]
        if foe then out[#out + 1] = { index = i, species = foe.species, level = foe.level } end
      end
    end
  end
  return out
end

-- the team is healed where it stands: HP, status, PP (A12.5)
function FriendBattle.heal(game)
  local moves = game.data.moves or {}
  for _, mon in ipairs(game.save.party or {}) do
    if mon.stats then mon.hp = mon.stats.hp end
    mon.status, mon.sleepTurns = nil, nil
    for _, mv in ipairs(mon.moves or {}) do
      local def = moves[mv.id]
      if def then mv.pp = def.pp + (mv.ppUps or 0) * math.floor(def.pp / 5) end
    end
  end
end

-- the EXP of `awards`, one text at a time over the map, the levels, the
-- moves learned at each, then the evolutions; onDone at the end
function FriendBattle.giveExp(game, awards, onDone)
  local TextBox = require("src.render.TextBox")
  local Experience = require("src.battle.Experience")
  local Evolution = require("src.pokemon.Evolution")
  local leveled = {}
  local i = 0
  local function nextAward()
    i = i + 1
    local award = awards[i]
    if not award then
      Evolution.checkParty(game, function() if onDone then onDone() end end, leveled)
      return
    end
    local mon = game.save.party[award.index]
    if not mon then return nextAward() end
    local def = game.data.pokemon[mon.species]
    local name = mon.nickname or (def and def.name) or mon.species
    local foe = game.data.pokemon[award.species]
    if not foe then return nextAward() end
    -- a trainer battle's EXP to one Pokémon that fought alone
    -- (experience.asm): the gain, the stat EXP, a traded Pokémon's boost
    local id = game.save.player and game.save.player.id
    local traded = id ~= nil and ((mon.otId ~= nil and mon.otId ~= id)
      or (mon.otId == nil and mon.traded == true))
    local _, gained, steps = Experience.apply(game.data, mon, foe, award.level, true, 1, traded,
                                              { defer = true })
    local text = traded and Strings.source("%s gained\na boosted\v%d EXP. Points!")
      or Strings.source("%s gained\n%d EXP. Points!")
    local k = 0
    local function nextLevel()
      k = k + 1
      local step = steps[k]
      if not step then return nextAward() end
      Experience.commit(game.data, mon, step)
      leveled[mon] = true
      game.stack:push(TextBox.new(game, Strings("%s grew\nto level %d!", name, step.level),
        function() Evolution.learnEvolutionMoves(game, mon, nextLevel) end,
        TextBox.soundOpts(game, "Level_Up")))
    end
    game.stack:push(TextBox.new(game, Strings(text, name, gained), nextLevel))
  end
  nextAward()
end

-- the waiting box ------------------------------------------------------------

local Wait = {}
Wait.__index = Wait

function Wait:update()
  local game = self.game
  local pair = self.pairNow()
  if not pair or pair.ended then
    return self:close(Strings("%s left the battle.", self.name), "draw")
  end
  if game.input and game.input:wasPressed("b") then
    self.net:send({ type = "bye" })
    return self:close(nil, "cancel")
  end
  self.net:update()
  local hello = not self.peerHello and self.net:take("hello")
  if hello then self.peerHello = hello end
  local party = not self.theirParty and self.net:take("party")
  if party then
    self.theirParty = party.mons
    if self.pair.role == "guest" then self.ruleset = party.ruleset end
  end
  if self.peerHello and self.theirParty then self:begin() end
end

function Wait:draw()
  local Font = require("src.render.Font")
  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("Waiting for %s...", self.name), 8, 14 * 8)
  love.graphics.setColor(1, 1, 1, 1)
end

-- off the stack wherever it is
function Wait:remove()
  local stack = self.game.stack
  if stack:top() == self then stack:pop() return end
  for i, st in ipairs(stack.states or stack.list or {}) do
    if st == self then table.remove(stack.states or stack.list, i) return end
  end
end

-- the battle never began: `result` for the host, a notice
function Wait:close(text, result)
  self:remove()
  if self.game.linkNet == self.net then self.game.linkNet = nil end
  self.net:close()
  if text then require("src.coop.game.Notices").push(text) end
  if self.opts.onEnd then self.opts.onEnd(result, nil) end
end

function Wait:begin()
  local game = self.game
  local Handshake = require("src.link.Handshake")
  local LinkBattle = require("src.link.LinkBattle")
  local verdict = Handshake.checkCompat(self.myHello, self.peerHello)
  local battle, why
  if Handshake.battleAllowed(verdict) then
    battle, why = LinkBattle.new(game, self.net, {
      role = self.pair.role, myParty = self.myParty, theirParty = self.theirParty,
      theirName = self.name, seed = self.pair.seed, verdict = verdict,
      strict = Handshake.strict(verdict), ruleset = self.ruleset,
    })
  else
    why = Strings("Link battle needs\nthe same version\nand mods.")
  end
  if not battle then
    self.net:send({ type = "bye" })
    self:remove()
    if game.linkNet == self.net then game.linkNet = nil end
    local TextBox = require("src.render.TextBox")
    game.stack:push(TextBox.new(game, why or Strings("Link battle\ncan't start.")))
    if self.opts.onEnd then self.opts.onEnd("cancel", nil) end
    return
  end
  FriendBattle.make(battle, self)
  self:remove()
  local ow = game.overworld
  if ow and ow.pushBattle and ow.isOverworld then ow:pushBattle(battle) else game.stack:push(battle) end
  self.battle = battle
end

-- the co-op rules on upstream's link battle (A12.3 to A12.5)
function FriendBattle.make(battle, w)
  local game, relay = w.game, w.relay
  battle.friend = { pair = w.pair.id, name = w.name }
  local function decide(s, result, text)
    s.result = result
    s.afterQueue = "finish"
    s.phase = "messages"
    s:say(text)
  end
  -- RUN forfeits: this player loses, the partner hears it (A12.3)
  battle.tryRun = function(s)
    s.net:send({ type = "forfeit" })
    s.friend.forfeit = true
    decide(s, "lose", Strings("%s forfeited\nthe match!", game.save.player.name or "?"))
  end
  local linkUpdate = battle.update
  battle.update = function(s, dt)
    FriendBattle.track(s)
    if relay.forfeited and not s.result and not s.linkEnded then
      relay.forfeited = false
      decide(s, "win", Strings("%s forfeited\nthe match!", w.name))
      s.friend.theyForfeit = true
    end
    -- the host released the pairing: the partner stayed away too long
    -- (A12.4), or left on purpose
    local pair = w.pairNow()
    if (not pair or pair.ended) and not s.result and not s.friend.released then
      s.friend.released = true
      relay:inject({ type = "bye" })
    end
    return linkUpdate(s, dt)
  end
  local linkFinish = battle.finish
  battle.finish = function(s)
    if not s.friend.result then
      s.friend.result = s.friend.forfeit and "forfeit" or s.result or "draw"
      s.payDay = nil -- no money (A12.5)
      -- a loss here is no blackout: back to the map behind the fade
      if s.result == "lose" then s.result = "draw" end
    end
    return linkFinish(s)
  end
  battle.onFinish = function()
    if w.opts.onEnd then w.opts.onEnd(battle.friend.result or "draw", FriendBattle.awards(battle)) end
  end
end

-- Start a friend battle for `pair` (the host's view of the pairing):
-- opts.client() is the session's client now, opts.onEnd(result, awards)
-- runs when it is over (awards nil when it never began).
function FriendBattle.start(game, pair, opts)
  local Handshake = require("src.link.Handshake")
  local LinkProtocol = require("src.link.Protocol")
  local LinkSession = require("src.link.Session")
  local relay = Relay.new(pair.id, opts.client)
  local net = LinkSession.new(relay, { role = pair.role, kind = "link" })
  local party = {}
  for i, mon in ipairs(game.save.party or {}) do
    if i > 6 then break end
    party[i] = mon
  end
  local w = setmetatable({
    game = game, pair = pair, opts = opts, relay = relay, net = net,
    name = pair.name or "?", isOpaque = false,
    myParty = LinkProtocol.packParty(party),
  }, Wait)
  -- the pairing as the host last said, nil once the host has forgotten it;
  -- while the link is down (or a new one has not heard yet), as last known
  w.lastPair = pair
  w.pairNow = function()
    local c = opts.client()
    if not c then return w.lastPair end
    local now = c.pairs[pair.id]
    if now then
      w.lastPair = now
      return now
    end
    if c.state then return nil end
    return w.lastPair
  end
  w.myHello = Handshake.hello(game, pair.role == "host" and "battle" or nil)
  net:send(w.myHello)
  local msg = { type = "party", mons = w.myParty }
  if pair.role == "host" then
    w.ruleset = Handshake.ruleset(game)
    msg.ruleset = w.ruleset
  end
  net:send(msg)
  game.linkNet = net -- serviced every frame, whatever is on top (Game:step)
  game.stack:push(w)
  return w
end

FriendBattle.Wait = Wait

return FriendBattle
