-- The other players of a co-op session on this player's map (#15, design
-- A14.1-A14.5).  Once a game runs, Game:step calls Presence.step every
-- logic frame; it reads the session's last state (Session.current) and
-- keeps one actor per partner in the overworld's entity list:
--
--   * a partner on this player's map is solid: the player's own steps and
--     NPC wandering stop at them, scripted moves pass through (they skip
--     collision);
--   * a partner on a map the connections reach (the next route or town)
--     is drawn there too, never solid;
--   * a partner elsewhere is not drawn (the arrow points to them, Arrow.lua),
--     nor is one who left the session.
--
-- A partner's steps are eased over 16 frames when they walk or surf and 8
-- when they run or ride (A14.5); each player wears their colour (Colors.lua)
-- in every window, this player too.  Notices.lua says who joins and leaves.
--
-- Battles (#34, design A14.3, A14.4, A14.10): a partner in a battle their
-- own world opened stands where it started under the "!" bubble; a partner
-- who joined a battle elsewhere is not drawn; a battle this player is free
-- to join is told in a notice.
--
-- The opening (#22, design A4.4, A4.8): a partner who plays the opening is
-- not drawn and gets no arrow or TOWN MAP mark, and while this player plays
-- it they see nobody and hear of no battle to join.  A partner who joins in
-- the opening is announced so.

local Arrow = require("src.coop.game.Arrow")
local Colors = require("src.coop.game.Colors")
local Notices = require("src.coop.game.Notices")
local CampaignSave = require("src.coop.game.CampaignSave")
local Strings = require("src.core.Strings")
local FieldDefaults = require("src.world.FieldDefaults")
local SpriteRenderer = require("src.render.SpriteRenderer")

local Presence = { actors = {}, seen = nil, tinted = nil, frame = 0 }

-- frames a partner's step is eased over, by how they travel (A14.5)
Presence.FRAMES = { walk = 16, surf = 16, run = 8, bike = 8 }

-- the session of this process once its player is in a running game, or nil
function Presence.session()
  local Session = package.loaded["src.coop.session.Session"]
  local s = Session and Session.current
  if s and s.client and s.client.status == "joined" and s.client.state then return s end
  return nil
end

-- the live overworld of `game`, or nil
function Presence.overworld(game)
  local ow = game and game.overworld
  if ow and ow.isOverworld and ow.map and ow.player and ow.entities then return ow end
  return nil
end

-- the pixel offset of map `mapId` from this player's map: (0, 0) on it, the
-- connection offset for a neighbour the overworld draws, nil otherwise
function Presence.offsetOf(ow, mapId)
  if not (ow and mapId) then return nil end
  if ow.map.id == mapId then return 0, 0 end
  for _, nb in ipairs(ow.neighbors or {}) do
    if nb.map and nb.map.id == mapId then return nb.ox, nb.oy end
  end
  return nil
end

-- an actor ----------------------------------------------------------------

local Actor = {}
Actor.__index = Actor
Actor.coopPartner = true
Presence.Actor = Actor

function Actor.new(id)
  return setmetatable({ id = id, facing = "down", travel = "walk",
                        animClock = 0, stepFlip = false, sprites = {},
                        visible = false, passable = true }, Actor)
end

-- the partner's last reported cell; `offsetOf(mapId)` places maps
function Actor:report(p, offsetOf)
  self.name = p.name
  self.facing = p.facing or self.facing
  self.travel = p.travel or "walk"
  if self.map ~= p.map then
    local ax, ay = offsetOf(self.map)
    local bx, by = offsetOf(p.map)
    if self.fx and ax and bx then
      -- through a connection: keep easing across the seam
      self.fx, self.fy = self.fx + ax - bx, self.fy + ay - by
    else
      self.fx, self.fy = p.x * 16, p.y * 16
    end
    self.map = p.map
  end
  -- a jump (a warp, a fly): more than two cells from where it is drawn
  if math.abs(self.fx - p.x * 16) + math.abs(self.fy - p.y * 16) > 32 then
    self.fx, self.fy = p.x * 16, p.y * 16
  end
  self.tx, self.ty = p.x, p.y
end

local function approach(v, target, speed)
  if v < target then return math.min(target, v + speed) end
  if v > target then return math.max(target, v - speed) end
  return v
end

-- one logic frame of easing
function Actor:tick()
  if not self.tx then return end
  local gx, gy = self.tx * 16, self.ty * 16
  self.moving = self.fx ~= gx or self.fy ~= gy
  if not self.moving then return end
  local speed = 16 / (Presence.FRAMES[self.travel] or 16)
  self.fx = approach(self.fx, gx, speed)
  self.fy = approach(self.fy, gy, speed)
  self.animClock = self.animClock + 1
  -- a cell reached: the next step leads with the other foot
  if self.fx % 16 == 0 and self.fy % 16 == 0 then self.stepFlip = not self.stepFlip end
end

-- where the actor stands on this player's screen; false when not drawn
function Actor:place(ow, offsetOf)
  local ox, oy = offsetOf(self.map)
  if not (ox and self.fx) then
    self.visible = false
    return false
  end
  self.px, self.py = self.fx + ox, self.fy + oy
  self.visible = true
  if self.map == ow.map.id then
    -- solid on this map: the cell it heads for and the one it leaves
    self.passable = false
    self.cellX, self.cellY = self.tx, self.ty
    local fromX, fromY = math.floor(self.fx / 16 + 0.5), math.floor(self.fy / 16 + 0.5)
    if fromX ~= self.tx or fromY ~= self.ty then
      self.targetX, self.targetY = fromX, fromY
    else
      self.targetX, self.targetY = nil, nil
    end
  else
    self.passable = true
    self.cellX, self.cellY, self.targetX, self.targetY = nil, nil, nil, nil
  end
  return true
end

local SHEETS = { walk = "walk", run = "walk", bike = "bike", surf = "surf" }

function Actor:sprite(data)
  local key = SHEETS[self.travel] or "walk"
  local s = self.sprites[key]
  if s == nil then
    local sprites = data and data.sprites or {}
    local def = sprites[FieldDefaults.fieldValue(data, "playerSprites", key) or ""]
      or sprites[FieldDefaults.fieldValue(data, "playerSprites", "walk") or ""]
    s = def and SpriteRenderer.new(def, self.id) or false
    self.sprites[key] = s
  end
  if s then s.coopColors, s.coopGroup = self.colors, self.colorGroup end
  return s or nil
end

function Actor:walkPhase()
  if not self.moving then return 0 end
  local t = self.animClock % 16
  return (t >= 4 and t < 12) and 1 or 0
end

function Actor:pose()
  return self:sprite(Presence.data), self.px, self.py, self.facing,
    self:walkPhase(), self.stepFlip, false
end

function Actor:update() end

function Actor:draw(camX, camY)
  local s = self:sprite(Presence.data)
  if s then s:draw(self.px, self.py, camX, camY, self.facing, self:walkPhase(), self.stepFlip) end
end

-- binding -----------------------------------------------------------------

local function removeActors(list)
  if not list then return end
  for i = #list, 1, -1 do
    if type(list[i]) == "table" and list[i].coopPartner then table.remove(list, i) end
  end
end

-- this player's own sprites wear their colour (nil puts the cartridge's back)
local function tintOwn(ow, colors, group)
  local p = ow and ow.player
  if not p then return end
  for _, key in ipairs({ "sprite", "bikeSprite", "surfSprite", "surfPikachuSprite" }) do
    local s = p[key]
    if type(s) == "table" then s.coopColors, s.coopGroup = colors, group end
  end
end

-- the battle a player fights in, as `state` says: its summary, or nil
local function battleOf(state, p)
  if not p.battle then return nil end
  for _, b in ipairs(state.battles or {}) do
    if b.id == p.battle then return b end
  end
  return nil
end
Presence.battleOf = battleOf

-- a partner's new battle this player is free to join (design A14.10)
local function narrateBattles(self, state, me)
  local now = {}
  if require("src.coop.game.Opening").active() then
    -- nothing to join from the opening (#22): its battles are not offered
    for _, b in ipairs(state.battles or {}) do now[b.id] = true end
    self.battlesSeen = now
    return
  end
  local busy = false
  for _, b in ipairs(state.battles or {}) do
    now[b.id] = true
    for _, pid in ipairs(b.players) do if pid == me then busy = true end end
  end
  if self.battlesSeen then
    local names = {}
    for _, p in ipairs(state.players) do names[p.id] = p.name end
    for _, b in ipairs(state.battles or {}) do
      if not self.battlesSeen[b.id] and b.by ~= me and b.joinable and not busy then
        local text = b.kind == "wild"
          and Strings("%s is in a battle against wild %s. START > CO-OP to join.",
                      names[b.by] or "?", b.foe or "?")
          or Strings("%s is in a battle against %s. START > CO-OP to join.",
                     names[b.by] or "?", b.foe or "?")
        Notices.push(text)
      end
    end
  end
  self.battlesSeen = now
end

-- notices for partners who joined or left since the last state
local function narrate(self, state, me)
  narrateBattles(self, state, me)
  local now, opening = {}, {}
  for _, p in ipairs(state.players) do
    if p.id ~= me then now[p.id] = p.connected and p.name or false end
    opening[p.id] = p.opening
  end
  if self.seen then
    for id, name in pairs(now) do
      if name and not self.seen[id] then
        Notices.push(opening[id] and Strings("%s joined the session in the opening.", name)
                     or Strings("%s joined the session.", name))
      end
    end
    for id, name in pairs(self.seen) do
      if name and not now[id] then
        Notices.push(Strings("%s left the session.", name))
      end
    end
  end
  self.seen = now
end

-- drop everything (no session, or it ended)
function Presence.clear(game)
  local ow = Presence.overworld(game)
  if ow then
    removeActors(ow.entities)
    if Presence.tinted then tintOwn(ow, nil, nil) end
  end
  Presence.actors, Presence.seen, Presence.tinted = {}, nil, nil
  Presence.state, Presence.read = nil, nil
end

-- one logic frame (Game:step)
-- what the session's link says over the world (#20, design A11.9, A11.11)
local function linkNotes()
  local S = package.loaded["src.coop.session.Session"]
  local cur = S and S.current
  if not (cur and cur.linkNote) then return cur end
  local n = cur.linkNote
  cur.linkNote = nil
  if n == "lost" then
    Notices.push(Strings("Lost the host: reconnecting..."))
  elseif n == "back" then
    Notices.push(Strings("Back in the session."))
  elseif n == "ended" then
    Notices.clear()
    if cur.status == "ended" then
      Notices.push(Strings("The host closed the session."))
    elseif cur.status == "refused" then
      Notices.push(Strings("The host turned this game away."))
    else
      Notices.push(Strings("The connection to the host was lost."))
    end
  end
  return cur
end

function Presence.step(game)
  local cur = linkNotes()
  local s = Presence.session()
  if not s and cur and (cur.endShowUntil or cur.status == "reconnecting") then
    -- the link is down: the notices still show over the world
    Notices.step()
    return
  end
  if not s then
    if Presence.state or Presence.tinted then
      Presence.clear(game)
      Notices.clear()
    end
    return
  end
  Presence.data = game.data
  Presence.frame = Presence.frame + 1
  local state, me = s.client.state, s.client.player
  Presence.state, Presence.me = state, me
  if state ~= Presence.read then
    Presence.read = state
    narrate(Presence, state, me)
  end
  -- who saved the campaign (#13)
  for _, msg in ipairs(s:takeSaves()) do
    local text = CampaignSave.notice(msg)
    if text then Notices.push(text) end
  end
  local ow = Presence.overworld(game)
  local offsetOf = function(mapId) return Presence.offsetOf(ow, mapId) end
  local keep = {}
  -- nobody is drawn to a player in the opening, and they see nobody (#22)
  local alone = require("src.coop.game.Opening").active()
  for place, p in ipairs(state.players) do
    if p.id == me then
      if ow then
        local colors, group = Colors.palette(place)
        tintOwn(ow, colors, group)
        Presence.tinted = true
      end
    elseif p.connected and p.map and not alone and not p.opening
           and not (p.battle and (battleOf(state, p) or {}).by ~= p.id) then
      -- (a partner who joined a battle elsewhere is not drawn, A14.4)
      local a = Presence.actors[p.id] or Actor.new(p.id)
      keep[p.id] = a
      a.colors, a.colorGroup = Colors.palette(place)
      a.inBattle = p.battle ~= nil -- the "!" where their battle started (A14.3)
      if ow then a:report(p, offsetOf) end
    end
  end
  Presence.actors = keep
  if ow then
    removeActors(ow.entities)
    for _, a in pairs(keep) do
      a:tick()
      if a:place(ow, offsetOf) then ow.entities[#ow.entities + 1] = a end
    end
  end
  Notices.step()
end

-- the overworld's world pass (OverworldState:draw): the arrows
function Presence.drawWorld(game, ow)
  if not Presence.state then return end
  Arrow.draw(game, ow, Presence.partners(), Presence.frame)
  for _, a in pairs(Presence.actors) do
    if a.inBattle and a.visible then Presence.drawBubble(game, ow, a) end
  end
end

-- the cartridge's "!" bubble over a partner in a battle (design A14.3)
function Presence.drawBubble(game, ow, a)
  local bubble = game.data and game.data.field and game.data.field.emotionBubbles
  local rect = bubble and bubble.bubbles and bubble.bubbles[1]
  if not (bubble and bubble.path and rect) then return end
  local ok, img = pcall(function()
    Presence.bubbleImg = Presence.bubbleImg
      or love.graphics.newImage(require("src.render.Assets").resolve(bubble.path))
    return Presence.bubbleImg
  end)
  if not (ok and img) then return end
  Presence.bubbleQuad = Presence.bubbleQuad
    or love.graphics.newQuad(rect.x, rect.y, rect.w, rect.h, img:getDimensions())
  local cam = ow.camera or { x = 0, y = 0 }
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, Presence.bubbleQuad, a.px - cam.x, a.py - cam.y - 20)
end

-- the overworld's UI pass (OverworldState:drawUI): the notices
function Presence.drawUI()
  if not Presence.state then return end
  Notices.draw()
end

-- the partners as the CO-OP menu and the arrow see them: { id, name,
-- place, connected, map, x, y, battle, opening, meeting, hidden } in session order,
-- this player left out; hidden: not shown on the map (an arrow, a TOWN MAP
-- mark) since one of the two plays the opening (#22)
function Presence.partners()
  local out = {}
  local state = Presence.state
  local alone = require("src.coop.game.Opening").active()
  for place, p in ipairs(state and state.players or {}) do
    if p.id ~= Presence.me then
      out[#out + 1] = { id = p.id, name = p.name, place = place, connected = p.connected,
                        map = p.map, x = p.x, y = p.y, actor = Presence.actors[p.id],
                        battle = p.battle, opening = p.opening,
                        meeting = p.meeting, -- #23: a friend battle or trade
                        hidden = alone or p.opening == true }
    end
  end
  return out
end

return Presence
