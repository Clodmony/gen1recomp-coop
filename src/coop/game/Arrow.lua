-- The partner arrow (#15, design A14.6, D106): a partner off the screen is
-- an 8x8 arrow in their colour, blinking, on the screen's edge two pixels
-- in, drawn over the map and under every box and menu, and only while the
-- player walks about (no menu, script, battle or screen of their own up).
-- It is drawn in the world pass, on the edges of the map the player sees
-- (the view is wider than the 160x144 UI on a wide window), and replayed
-- after the palette zones like the sprites, so it keeps its colour in every
-- COLORS mode.
--
-- Where it points comes from a breadth-first search of the maps from the
-- player's (Arrow.route, cached per map pair and last map):
--
--   * "exact": connections alone reach the partner's map, so the arrow
--     points at the partner;
--   * "door": past a door or stairs, it stands over (or points at) the last
--     warp on a map that can be placed (this map and the maps its
--     connections reach): a door the player can walk to on their own map
--     first, and of the doors into the partner's own map the one that lands
--     nearest them.  Indoors, "last map" exits lead to the player's own last
--     map, only until the search has left the building;
--   * "town": nothing joins the two (flown, across the sea), so it takes the
--     TOWN MAP's direction.

local Colors = require("src.coop.game.Colors")

local Arrow = { cache = {}, cacheData = nil, reach = nil }

Arrow.EDGE = 2           -- pixels in from the screen's edge
Arrow.BLINK = 40         -- frames of one blink
Arrow.BLINK_ON = 28      -- of which the arrow shows

-- the maps connections reach from `rootId`, with their pixel offsets
-- (OverworldState.computeNeighbors' arithmetic, without its hop limit)
function Arrow.placed(maps, rootId)
  local out = { [rootId] = { ox = 0, oy = 0 } }
  local root = maps[rootId]
  if not root then return out end
  local queue, qi = { { id = rootId, def = root, ox = 0, oy = 0 } }, 1
  while queue[qi] do
    local cur = queue[qi]
    qi = qi + 1
    for dir, conn in pairs(cur.def.connections or {}) do
      local dest = maps[conn.map]
      if dest and not out[conn.map] then
        local ox, oy
        if dir == "north" then
          ox, oy = conn.offset * 32, -dest.height * 32
        elseif dir == "south" then
          ox, oy = conn.offset * 32, cur.def.height * 32
        elseif dir == "west" then
          ox, oy = -dest.width * 32, conn.offset * 32
        else
          ox, oy = cur.def.width * 32, conn.offset * 32
        end
        ox, oy = cur.ox + ox, cur.oy + oy
        out[conn.map] = { ox = ox, oy = oy }
        queue[#queue + 1] = { id = conn.map, def = dest, ox = ox, oy = oy }
      end
    end
  end
  return out
end

-- where warp `w` leads: map id and landing cell, or nil; "last map" exits
-- only `inside` (the search has not left the building yet)
local function destination(maps, w, inside, lastMap)
  local destId = w.destMap
  if destId == "LAST_MAP" then
    if not (inside and lastMap) then return nil end
    destId = lastMap
  end
  local dest = maps[destId]
  if not dest then return nil end
  local dw = dest.warps and dest.warps[w.destWarp]
  return destId, dw and dw.x or 0, dw and dw.y or 0
end

-- maps from `startId` to `goalId` by connections and warps, avoiding
-- `avoid`; nil when nothing joins them
local function hops(maps, startId, goalId, inside, lastMap, outside, avoid)
  if startId == goalId then return 0 end
  local seen = { [startId .. (inside and "+" or "-")] = true }
  local queue, qi = { { id = startId, inside = inside, n = 0 } }, 1
  while queue[qi] do
    local cur = queue[qi]
    qi = qi + 1
    local def = maps[cur.id]
    local nexts = {}
    for _, conn in pairs(def and def.connections or {}) do nexts[#nexts + 1] = conn.map end
    for _, w in ipairs(def and def.warps or {}) do
      nexts[#nexts + 1] = (destination(maps, w, cur.inside, lastMap))
    end
    for _, id in ipairs(nexts) do
      if id and maps[id] and not avoid[id] then
        if id == goalId then return cur.n + 1 end
        local stillInside = cur.inside and not outside(maps[id])
        local key = id .. (stillInside and "+" or "-")
        if not seen[key] then
          seen[key] = true
          queue[#queue + 1] = { id = id, inside = stillInside, n = cur.n + 1 }
        end
      end
    end
  end
  return nil
end

-- The route from the player's map to the partner's (cached):
--   { kind = "exact", ox, oy }   the partner's map offset in pixels
--   { kind = "door", doors }     candidate warps: { x, y } cells in the
--                                player's map frame (pixels / 16), map,
--                                landX/landY on the partner's map when the
--                                warp leads straight into it
--   { kind = "town" }            nothing joins the two
-- `outside(def)` tells outdoor maps; `lastMap` is the player's last
-- outdoor map id (for "last map" exits).
function Arrow.route(maps, fromId, toId, lastMap, outside)
  if Arrow.cacheData ~= maps then Arrow.cache, Arrow.cacheData = {}, maps end
  local key = fromId .. ">" .. toId .. "@" .. tostring(lastMap)
  local hit = Arrow.cache[key]
  if hit then return hit end
  local placed = Arrow.placed(maps, fromId)
  local result
  if placed[toId] then
    result = { kind = "exact", ox = placed[toId].ox, oy = placed[toId].oy }
  else
    local fromDef = maps[fromId]
    local inside = fromDef ~= nil and not outside(fromDef)
    local best, doors = nil, {}
    for id, at in pairs(placed) do
      local def = maps[id]
      for _, w in ipairs(def.warps or {}) do
        local destId, lx, ly = destination(maps, w, inside and id == fromId, lastMap)
        if destId and not placed[destId] then
          local stillInside = inside and id == fromId and not outside(maps[destId])
          local n = hops(maps, destId, toId, stillInside, lastMap, outside, placed)
          if n and (not best or n <= best) then
            if not best or n < best then best, doors = n, {} end
            doors[#doors + 1] = {
              x = w.x + at.ox / 16, y = w.y + at.oy / 16, map = id,
              landX = destId == toId and lx or nil, landY = destId == toId and ly or nil,
            }
          end
        end
      end
    end
    -- the same order every run (pairs is not)
    table.sort(doors, function(a, b)
      if a.map ~= b.map then return a.map < b.map end
      if a.y ~= b.y then return a.y < b.y end
      return a.x < b.x
    end)
    result = best and { kind = "door", doors = doors } or { kind = "town" }
  end
  Arrow.cache[key] = result
  return result
end

-- the cells of `map` the player can walk to from (x, y), kept while the
-- player stays inside them
function Arrow.reachable(map, x, y)
  local r = Arrow.reach
  if r and r.map == map and r.cells[x .. "," .. y] then return r.cells end
  local cells = { [x .. "," .. y] = true }
  local queue, qi = { { x, y } }, 1
  local w, h = (map.width or 0) * 2, (map.height or 0) * 2
  while queue[qi] and qi < 20000 do
    local c = queue[qi]
    qi = qi + 1
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, ny = c[1] + d[1], c[2] + d[2]
      local k = nx .. "," .. ny
      if not cells[k] and nx >= 0 and ny >= 0 and nx < w and ny < h
         and map:isWalkableCell(nx, ny) then
        cells[k] = true
        queue[#queue + 1] = { nx, ny }
      end
    end
  end
  Arrow.reach = { map = map, cells = cells }
  return cells
end

local function nextTo(cells, x, y)
  return cells[x .. "," .. y] or cells[(x + 1) .. "," .. y] or cells[(x - 1) .. "," .. y]
    or cells[x .. "," .. (y + 1)] or cells[x .. "," .. (y - 1)]
end

-- The door of a "door" route this player is shown: into the partner's
-- own map the one that lands nearest them; otherwise a door on the player's
-- map they can walk to, then the nearest.
function Arrow.pickDoor(route, partner, player, cells, mapId)
  local doors = route.doors
  local direct = {}
  for _, d in ipairs(doors) do
    if d.landX then direct[#direct + 1] = d end
  end
  local function dist2(ax, ay, bx, by) return (ax - bx) ^ 2 + (ay - by) ^ 2 end
  if #direct > 0 then
    table.sort(direct, function(a, b)
      return dist2(a.landX, a.landY, partner.x, partner.y)
        < dist2(b.landX, b.landY, partner.x, partner.y)
    end)
    -- of the doors that land nearest, the one nearest the player
    local near = dist2(direct[1].landX, direct[1].landY, partner.x, partner.y)
    local tied = {}
    for _, d in ipairs(direct) do
      if dist2(d.landX, d.landY, partner.x, partner.y) == near then tied[#tied + 1] = d end
    end
    doors = tied
  end
  local own, reach = {}, {}
  for _, d in ipairs(doors) do
    if d.map == mapId then
      own[#own + 1] = d
      if cells and nextTo(cells, d.x, d.y) then reach[#reach + 1] = d end
    end
  end
  local pool = #reach > 0 and reach or #own > 0 and own or doors
  local best, bestD
  for _, d in ipairs(pool) do
    local dd = dist2(d.x, d.y, player.x, player.y)
    if not best or dd < bestD then best, bestD = d, dd end
  end
  return best
end

-- the eight directions, clockwise from right
local DIRS = { "right", "downright", "down", "downleft", "left", "upleft", "up", "upright" }
Arrow.DIRS = DIRS

local function direction(dx, dy)
  local a = math.atan2(dy, dx)
  local i = math.floor(a / (math.pi / 4) + 0.5) % 8
  return DIRS[i + 1], i
end

-- Where the arrow of one partner goes on a W x H screen, or nil:
--   target: { x, y } pixels on the screen (may lie off it), kind
--     "exact" / "door", or { dx, dy } with kind "town";
--   from: the player's centre on the screen.
-- Returns { x, y, dir }: the arrow's top-left corner and where it points.
function Arrow.layout(target, from, W, H)
  local e = Arrow.EDGE
  local minX, minY, maxX, maxY = e, e, W - 8 - e, H - 8 - e
  local tx, ty
  if target.kind == "town" then
    if (target.dx or 0) == 0 and (target.dy or 0) == 0 then return nil end
    tx, ty = from.x + target.dx * 10000, from.y + target.dy * 10000
  else
    tx, ty = target.x, target.y
    local onScreen = tx >= 0 and ty >= 0 and tx < W and ty < H
    if onScreen then
      if target.kind ~= "door" then return nil end
      -- standing over the door, pointing down; one in the top row stays on
      return { x = math.floor(tx - 4), y = math.max(minY, math.floor(ty - 8 - 2 - 8)), dir = "down" }
    end
  end
  local dx, dy = tx - from.x, ty - from.y
  if dx == 0 and dy == 0 then return nil end
  -- from the player towards the target until the arrow meets the edge
  local cx, cy = from.x - 4, from.y - 4
  local t = math.huge
  if dx > 0 then t = math.min(t, (maxX - cx) / dx) end
  if dx < 0 then t = math.min(t, (minX - cx) / dx) end
  if dy > 0 then t = math.min(t, (maxY - cy) / dy) end
  if dy < 0 then t = math.min(t, (minY - cy) / dy) end
  if t == math.huge or t < 0 then t = 0 end
  local x = math.max(minX, math.min(maxX, math.floor(cx + dx * t + 0.5)))
  local y = math.max(minY, math.min(maxY, math.floor(cy + dy * t + 0.5)))
  return { x = x, y = y, dir = (direction(dx, dy)) }
end

-- whether the player walks about: the overworld on top, nothing scripted
function Arrow.walking(game, ow)
  local top = game and game.stack and game.stack.top and game.stack:top()
  if not ow or top ~= ow or ow.transitioning then return false end
  if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then return false end
  if #(ow.scriptMoves or {}) > 0 then return false end
  if ow.engaging or ow.emote or ow.flyAnim or ow.flyArrive or ow.teleportOut
     or ow.spinArrive or ow.holeFall or ow.holeArrive or ow.cutAnim or ow.playerHidden then
    return false
  end
  return true
end

-- The arrows to show now: { { x, y, dir, place, id } } on the W x H view
-- of the world (camera pixels).
-- partners: Presence.partners(); game/ow: the running game and overworld.
function Arrow.arrows(game, ow, partners, W, H)
  local out = {}
  if not Arrow.walking(game, ow) then return out end
  local data = game.data
  local maps = data and data.maps
  if not maps then return out end
  local Map = require("src.world.Map")
  local FieldDefaults = require("src.world.FieldDefaults")
  local tilesets = FieldDefaults.field(data, "outsideTilesets")
  local function outside(def) return Map.isOutside(def, tilesets) end
  local cam = ow.camera or { x = 0, y = 0 }
  local p = ow.player
  local from = { x = (p.px - cam.x + 8), y = (p.py - cam.y + 8) }
  local last = ow.lastOutdoor and ow.lastOutdoor.id
  local towns = data.field and data.field.townMap and data.field.townMap.locations or {}
  for _, partner in ipairs(partners) do
    if partner.connected and partner.map then
      local target
      local actor = partner.actor
      if actor and actor.visible then
        target = { kind = "exact", x = (actor.px - cam.x + 8), y = (actor.py - cam.y + 8) }
      elseif maps[ow.map.id] and maps[partner.map] then
        local route = Arrow.route(maps, ow.map.id, partner.map, last, outside)
        if route.kind == "exact" then
          target = { kind = "exact",
                     x = (partner.x * 16 + route.ox - cam.x + 8),
                     y = (partner.y * 16 + route.oy - cam.y + 8) }
        elseif route.kind == "door" then
          local cells = ow.map.isWalkableCell and Arrow.reachable(ow.map, p.cellX, p.cellY)
          local d = Arrow.pickDoor(route, partner, { x = p.cellX, y = p.cellY }, cells, ow.map.id)
          if d then
            target = { kind = "door", x = (d.x * 16 - cam.x + 8), y = (d.y * 16 - cam.y + 8) }
          end
        end
      end
      if not target then
        local a, b = towns[ow.map.id], towns[partner.map]
        if a and b then target = { kind = "town", dx = b.x - a.x, dy = b.y - a.y } end
      end
      local at = target and Arrow.layout(target, from, W, H)
      if at then
        at.place, at.id = partner.place, partner.id
        out[#out + 1] = at
      end
    end
  end
  return out
end

-- the arrow shape pointing right, in an 8x8 box
local SHAPE = { 0.5, 2.5, 3.5, 2.5, 3.5, 0.5, 7.5, 4, 3.5, 7.5, 3.5, 5.5, 0.5, 5.5 }

-- one arrow as an image, per colour and direction (made once)
Arrow.images = {}
function Arrow.image(place, dir)
  local key = tostring(place) .. dir
  local img = Arrow.images[key]
  if img ~= nil then return img or nil end
  local g = love.graphics
  local ok, made = pcall(function()
    local index = 0
    for i, d in ipairs(DIRS) do
      if d == dir then index = i - 1 end
    end
    local canvas = g.newCanvas(8, 8)
    g.push("all")
    g.setCanvas(canvas)
    g.clear(0, 0, 0, 0)
    g.origin()
    g.translate(4, 4)
    g.rotate(index * math.pi / 4)
    g.translate(-4, -4)
    g.setColor(Colors.rgb(place or 1))
    g.polygon("fill", SHAPE)
    g.setColor(Colors.outline())
    g.setLineWidth(1)
    g.polygon("line", SHAPE)
    g.pop()
    return canvas
  end)
  Arrow.images[key] = ok and made or false
  return ok and made or nil
end

function Arrow.drawOne(a)
  local img = Arrow.image(a.place or 1, a.dir)
  if not img then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, a.x, a.y)
  -- over the palette zones in every COLORS mode, like the sprites
  require("src.render.PaletteFX").markSpriteRedraw(img, nil, a.x, a.y)
end

-- the overworld's world pass: the blinking arrows on the view's edges
function Arrow.draw(game, ow, partners, frame)
  if (frame or 0) % Arrow.BLINK >= Arrow.BLINK_ON then return end
  local W, H = 160, 144
  if game.renderer and game.renderer.worldViewSize then
    local w, h = game.renderer:worldViewSize()
    W, H = w or W, h or H
  end
  for _, a in ipairs(Arrow.arrows(game, ow, partners, W, H)) do Arrow.drawOne(a) end
end

return Arrow
