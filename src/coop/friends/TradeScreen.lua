-- A direct trade in the window (#23, design A12.6, decision G31): the
-- cartridge's trade screen where the player stands, drawn by upstream's
-- link trade screen (src/link/LinkState.lua, its "trade" stage: the two
-- party lists, the STATS / TRADE row, CANCEL, "Waiting...!"), with the
-- host in the middle instead of a cable: each window sends its team, its
-- offer and its TRADE to the host, which commits the swap once
-- (HostFriends.lua); then each window swaps on its own team
-- (src/coop/campaign/Trade.lua: the rows keep their uids), saves, plays
-- the trade movie and a trade evolution, and is back on the map.
--
--   local screen = TradeScreen.open(game, pair, { client = fn, onEnd = fn })
--
-- CANCEL (below the party), B before TRADE, or the partner's CANCEL return
-- both to the map where they stood, nothing traded; a disconnect before
-- the swap ends it the same way.  One trade per pairing.

local Strings = require("src.core.Strings")
local Trade = require("src.coop.campaign.Trade")

local TradeScreen = {}
TradeScreen.__index = function(t, k)
  local own = rawget(TradeScreen, k)
  if own ~= nil then return own end
  -- the drawing and the list labels are upstream's link trade screen's
  return require("src.link.LinkState")[k]
end
TradeScreen.isOpaque = true

-- the trade upstream's screen draws from: its stage and the partner's list
function TradeScreen:_session()
  local t = self.trade
  t.theirParty = self.theirs
  t.theirPick = self.view and self.view.theirPick
  return t
end

function TradeScreen:_remove()
  local stack = self.game.stack
  if stack:top() == self then stack:pop() return end
  for i, st in ipairs(stack.states or stack.list or {}) do
    if st == self then table.remove(stack.states or stack.list, i) return end
  end
end

-- back on the map: `text` said there, `result` for the host
function TradeScreen:close(text, result)
  if self.closed then return end
  self.closed = true
  self:_remove()
  local c = self.client()
  if c and result then c:pairEnd(self.pair.id, result) end
  if text then
    local TextBox = require("src.render.TextBox")
    self.game.stack:push(TextBox.new(self.game, text))
  end
  if self.opts.onEnd then self.opts.onEnd(result) end
end

local function cancelText() return Strings("The trade was\ncancelled.") end

-- the host committed the swap: this window's side of it, once
function TradeScreen:_done()
  local game, v = self.game, self.view
  local mine = Trade.decodeTeam(v.mine or "") or {}
  local theirs = self.theirs or {}
  local give, get = mine[v.myPick], theirs[v.theirPick]
  self.closed = true
  self:_remove()
  local c = self.client()
  local how, _, slot = Trade.swap(game.save, give or {}, get or {})
  if c then c:pairEnd(self.pair.id, "done") end
  if how ~= "swapped" then
    if self.opts.onEnd then self.opts.onEnd("done") end
    return
  end
  local received = game.save.party[slot]
  local Runtime = require("src.mods.Runtime")
  Runtime.emit("pokemon.received", { mon = received, from = "link", peerName = self.peerName })
  -- PIKAHAPPY_TRADE (engine/link/cable_club.asm:801)
  require("src.world.PikachuFollower").modifyHappiness(game.save, "TRADE", give)
  if game.save.pokedex then
    game.save.pokedex.seen[received.species] = true
    game.save.pokedex.owned[received.species] = true
  end
  local evoTo = Trade.evolution(game.data, received)
  Runtime.emit("trade.completed", { sent = give, received = received, evolveTo = evoTo })
  -- the trade is saved before its movie, as the Cable Club does
  -- (engine/link/cable_club.asm, SaveSAVtoSRAM)
  if game.writeSave then game:writeSave("link") end
  local def = game.data.pokemon[received.species]
  local name = received.nickname or (def and def.name) or received.species
  local Screens = require("src.ui.Screens")
  local TextBox = require("src.render.TextBox")
  local function finish()
    if self.opts.onEnd then self.opts.onEnd("done") end
  end
  Screens.push(game, "TradeAnim", {
    sent = give, received = received, enemyName = self.peerName,
    playerOt = game.save.player.name, playerOtId = give.otId or game.save.player.id,
    enemyOtId = received.otId,
    onDone = function()
      game.stack:push(TextBox.new(game,
        Strings("Trade completed!\f%s received\n%s!", game.save.player.name, name),
        function()
          if not evoTo then return finish() end
          -- a trade evolution cannot be cancelled (#213)
          require("src.pokemon.Evolution").evolve(game, received, evoTo, function()
            if game.writeSave then game:writeSave("link") end
            finish()
          end, "TRADE")
        end))
    end,
  })
end

function TradeScreen:update()
  if self.closed then return end
  local game, input = self.game, self.game.input
  local c = self.client()
  local v = c and c.pairs[self.pair.id]
  if c and c.state and not v then return self:close(cancelText(), nil) end
  if v then self.view = v end
  v = self.view
  if v.done then return self:_done() end
  if v.ended then
    return self:close(v.ended == "left" and Strings("The link was\nbroken.") or cancelText(), "cancel")
  end
  -- the team goes to the host once, as the screen opens
  if not self.teamSent and c then
    if c:tradeTeam(self.pair.id, Trade.encodeTeam(game.save.party)) then self.teamSent = true end
  end
  if v.theirs and not self.theirs then self.theirs = Trade.decodeTeam(v.theirs) end
  local t = self:_session()
  if not (self.theirs and v.mine) then
    t.stage = "waitParty"
  elseif not v.myPick then
    t.stage = "picking"
  elseif not v.theirPick then
    t.stage = "waitPick"
  else
    t.stage = "confirming"
  end
  local party = game.save.party
  -- B leaves before TRADE was said (the cart's B on the lists; once TRADE
  -- went out the host may commit, so B does nothing then)
  if t.stage == "picking" and self.pickChoice then
    if input:wasPressed("left") then
      self.pickChoice = 1
    elseif input:wasPressed("right") then
      self.pickChoice = 2
    elseif input:wasPressed("b") then
      self.pickChoice = nil
    elseif input:wasPressed("a") then
      if self.pickChoice == 1 then
        self.pickChoice = nil
        self:openStats(party[self.index])
      elseif c and c:tradePick(self.pair.id, self.index) then
        self.pickChoice = nil
        self.side = "mine"
      end
    end
  elseif t.stage == "picking" and input:wasPressed("up") then
    if self.side == "cancel" then
      self.side, self.index = "mine", math.max(1, #party)
    elseif self.side == "theirs" then
      self.theirIndex = math.max(1, self.theirIndex - 1)
    else
      self.index = math.max(1, self.index - 1)
    end
  elseif t.stage == "picking" and input:wasPressed("down") then
    if self.side == "theirs" then
      if self.theirIndex >= #(self.theirs or {}) then
        self.side = "cancel"
      else
        self.theirIndex = self.theirIndex + 1
      end
    elseif self.side ~= "cancel" then
      if self.index >= #party then self.side = "cancel" else self.index = self.index + 1 end
    end
  elseif t.stage == "picking" and input:wasPressed("right") then
    if self.theirs and #self.theirs > 0 then
      self.side = "theirs"
      self.theirIndex = math.min(self.theirIndex, #self.theirs)
    end
  elseif t.stage == "picking" and input:wasPressed("left") then
    self.side = "mine"
  elseif not v.confirmed and input:wasPressed("b") then
    if t.stage == "confirming" and c then c:tradeConfirm(self.pair.id, false) end
    return self:close(cancelText(), "cancel")
  elseif t.stage == "picking" and input:wasPressed("a") then
    if self.side == "cancel" then
      return self:close(cancelText(), "cancel")
    elseif self.side == "theirs" then
      self:openStats((self.theirs or {})[self.theirIndex])
    else
      self.pickChoice = 1
    end
  elseif t.stage == "confirming" and not v.confirmed and input:wasPressed("a") and c then
    c:tradeConfirm(self.pair.id, true)
  end
  self.confirmed = v.confirmed or nil
end

function TradeScreen:openStats(mon)
  if not mon then return end
  require("src.ui.Screens").push(self.game, "SummaryMenu", mon)
end

-- upstream's screen, and while both offers stand, what is about to be
-- traded and how to answer
function TradeScreen:draw()
  self.stage = "trade"
  require("src.link.LinkState").draw(self)
  local v, t = self.view, self.trade
  if t.stage == "confirming" and not v.confirmed then
    local Font = require("src.render.Font")
    local mine = self.game.save.party[v.myPick]
    local theirs = (self.theirs or {})[v.theirPick]
    local function label(mon)
      local def = mon and self.game.data.pokemon[mon.species]
      return (def and def.name) or (mon and mon.species) or "?"
    end
    Font.drawBox(0, 12, 20, 6)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings("TRADE %s", label(mine)), 8, 14 * 8)
    Font.draw(Strings("for %s?", label(theirs)), 8, 16 * 8)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

-- Open the trade screen for `pair` (the host's view of the pairing):
-- opts.client() is the session's client now, opts.onEnd(result) runs when
-- the screen is done (result nil when the host had forgotten the pairing).
function TradeScreen.open(game, pair, opts)
  local self = setmetatable({
    game = game, pair = pair, view = pair, opts = opts, client = opts.client,
    peerName = pair.name or "?", index = 1, theirIndex = 1, side = "mine",
    trade = { stage = "waitParty", canPick = function() return true end },
  }, TradeScreen)
  game.stack:push(self)
  return self
end

return TradeScreen
