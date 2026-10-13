-- Partners on the TOWN MAP (#15, design A14.7, D106): the TOWN MAP item, the
-- CO-OP menu's TOWN MAP row and the fly map show each partner's icon in
-- their colour, under the player's own; the Pokédex's area view does not.
-- TownMap:draw calls draw() through a marked hook just before it draws the
-- player's marker.

local Colors = require("src.coop.game.Colors")
local Presence = require("src.coop.game.Presence")
local SpriteRenderer = require("src.render.SpriteRenderer")
local FieldDefaults = require("src.world.FieldDefaults")

local TownMapMarks = { quads = {} }

-- the partners to mark: { place, loc } for each connected partner whose map
-- has a TOWN MAP place; `byMap` is the screen's map id -> place table
function TownMapMarks.marks(byMap)
  local out = {}
  if not Presence.session() then return out end
  for _, p in ipairs(Presence.partners()) do
    local loc = p.connected and p.map and byMap and byMap[p.map]
    if loc then out[#out + 1] = { place = p.place, loc = loc, id = p.id } end
  end
  return out
end

local function icon(data, place)
  local id = FieldDefaults.fieldValue(data, "playerSprites", "walk")
  local def = id and data and data.sprites and data.sprites[id]
  if not def then return nil end
  local colors, group = Colors.palette(place)
  local ok, img = pcall(SpriteRenderer.obpImage, def.image, colors, group)
  if not (ok and img) then return nil end
  local quad = TownMapMarks.quads[img]
  if not quad then
    quad = love.graphics.newQuad(0, 0, 16, 16, img:getDimensions())
    TownMapMarks.quads[img] = quad
  end
  return img, quad
end

-- screen: the TownMap state; markerXY(loc) -> x, y its marker cell
function TownMapMarks.draw(screen, markerXY)
  if screen.nestSpecies then return end
  local PaletteFX = require("src.render.PaletteFX")
  for _, m in ipairs(TownMapMarks.marks(screen.byMap)) do
    local x, y = markerXY(m.loc)
    local img, quad = icon(screen.game and screen.game.data, m.place)
    love.graphics.setColor(1, 1, 1, 1)
    if img then
      love.graphics.draw(img, quad, x - 4, y - 3)
      -- over the TOWNMAP palette zone in every COLORS mode
      PaletteFX.markUiSpriteRedraw(img, quad, x - 4, y - 3)
    else
      love.graphics.setColor(Colors.rgb(m.place))
      love.graphics.rectangle("fill", x + 1, y + 1, 6, 6)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
end

return TownMapMarks
