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

local Arrow = require("src.coop.game.Arrow")
local Colors = require("src.coop.game.Colors")
local Notices = require("src.coop.game.Notices")
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

-- notices for partners who joined or left since the last state
local function narrate(self, state, me)
  local now = {}
  for _, p in ipairs(state.players) do
    if p.id ~= me then now[p.id] = p.connected and p.name or false end
  end
  if self.seen then
    for id, name in pairs(now) do
      if name and not self.seen[id] then
        Notices.push(("%s joined the session."):format(name))
      end
    end
    for id, name in pairs(self.seen) do
      if name and not now[id] then
        Notices.push(("%s left the session."):format(name))
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
function Presence.step(game)
  local s = Presence.session()
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
  local ow = Presence.overworld(game)
  local offsetOf = function(mapId) return Presence.offsetOf(ow, mapId) end
  local keep = {}
  for place, p in ipairs(state.players) do
    if p.id == me then
      if ow then
        local colors, group = Colors.palette(place)
        tintOwn(ow, colors, group)
        Presence.tinted = true
      end
    elseif p.connected and p.map then
      local a = Presence.actors[p.id] or Actor.new(p.id)
      keep[p.id] = a
      a.colors, a.colorGroup = Colors.palette(place)
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
end

-- the overworld's UI pass (OverworldState:drawUI): the notices
function Presence.drawUI()
  if not Presence.state then return end
  Notices.draw()
end

-- the partners as the CO-OP menu and the arrow see them: { id, name,
-- place, connected, map, x, y } in session order, this player left out
function Presence.partners()
  local out = {}
  local state = Presence.state
  for place, p in ipairs(state and state.players or {}) do
    if p.id ~= Presence.me then
      out[#out + 1] = { id = p.id, name = p.name, place = place, connected = p.connected,
                        map = p.map, x = p.x, y = p.y, actor = Presence.actors[p.id] }
    end
  end
  return out
end

return Presence
