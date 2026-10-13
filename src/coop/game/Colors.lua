-- Each player's colour in a co-op session (#15, design A14.3): a player is
-- drawn in one colour in every window, chosen by their place in the
-- session (the host's player list, which every client gets in the same
-- order).  A colour is a Gen 1 OBJ palette: colour 0 is transparent, then
-- the light shade (skin), the player's own colour and the outline, the way
-- the cartridge's GBC colouring dresses its trainer sprites.

local Colors = {}

local WHITE = { 255, 255, 255 }
local SKIN = { 248, 192, 152 }
local OUTLINE = { 24, 24, 32 }

-- the colour shade of each place; past the last the list starts again
Colors.SHADES = {
  { 224, 56, 40 },   -- red
  { 48, 104, 232 },  -- blue
  { 40, 160, 64 },   -- green
  { 168, 72, 208 },  -- purple
  { 240, 144, 24 },  -- orange
  { 24, 168, 176 },  -- teal
  { 216, 72, 152 },  -- pink
  { 136, 104, 56 },  -- brown
}

-- the OBJ palette of place `n` (1-based) and its bake group
function Colors.palette(n)
  n = math.max(1, math.floor(tonumber(n) or 1))
  local shade = Colors.SHADES[(n - 1) % #Colors.SHADES + 1]
  return { WHITE, SKIN, shade, OUTLINE }, "coop" .. ((n - 1) % #Colors.SHADES + 1)
end

-- the colour shade of place `n` as LÖVE colour components
function Colors.rgb(n)
  local pal = Colors.palette(n)
  local c = pal[3]
  return c[1] / 255, c[2] / 255, c[3] / 255
end

function Colors.outline()
  return OUTLINE[1] / 255, OUTLINE[2] / 255, OUTLINE[3] / 255
end

-- the place of player `id` in a state's player list, or nil
function Colors.place(players, id)
  for i, p in ipairs(players or {}) do
    if p.id == id then return i end
  end
  return nil
end

return Colors
