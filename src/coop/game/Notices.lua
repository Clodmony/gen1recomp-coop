-- Notices over the world in a co-op session (#15, design A14.10): a partner
-- joins or leaves, a refusal; plain sentences in the cartridge's font, light
-- on a dark backdrop at the top of the screen, that fade after a few seconds.
-- Presence.step ages them every logic frame; the overworld draws them
-- (OverworldState:drawUI), under every box and menu.

local Font = require("src.render.Font")

local Notices = { list = {} }

Notices.SHOW = 180   -- frames a notice stays
Notices.FADE = 30    -- of which the last ones fade
Notices.MAX = 3      -- shown at once; an older one gives way
Notices.WIDTH = 18   -- characters on a line

-- the sentence in lines of at most WIDTH characters, broken at spaces
function Notices.wrap(text, width)
  width = width or Notices.WIDTH
  local lines, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    while #word > width do
      if line ~= "" then lines[#lines + 1] = line; line = "" end
      lines[#lines + 1] = word:sub(1, width)
      word = word:sub(width + 1)
    end
    if line == "" then
      line = word
    elseif #line + 1 + #word <= width then
      line = line .. " " .. word
    else
      lines[#lines + 1] = line
      line = word
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

function Notices.push(text)
  local list = Notices.list
  list[#list + 1] = { text = text, lines = Notices.wrap(text), age = 0 }
  while #list > Notices.MAX do table.remove(list, 1) end
end

function Notices.step()
  local keep = {}
  for _, n in ipairs(Notices.list) do
    n.age = n.age + 1
    if n.age < Notices.SHOW then keep[#keep + 1] = n end
  end
  Notices.list = keep
end

function Notices.clear()
  Notices.list = {}
end

-- the texts shown now, oldest first
function Notices.texts()
  local out = {}
  for i, n in ipairs(Notices.list) do out[i] = n.text end
  return out
end

-- glyphs are dark ink; this draws their ink in the current colour
local inkShader
local function lightInk()
  if inkShader == nil then
    local ok, shader = pcall(function()
      return love.graphics.newShader([[
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
          vec4 t = Texel(tex, tc);
          float ink = 1.0 - dot(t.rgb, vec3(0.299, 0.587, 0.114));
          return vec4(color.rgb, color.a * t.a * ink);
        }
      ]])
    end)
    inkShader = ok and shader or false
  end
  return inkShader or nil
end

function Notices.draw()
  local list = Notices.list
  if #list == 0 then return end
  local shader = love.graphics.newShader and lightInk()
  local y = 0
  for _, n in ipairs(list) do
    local alpha = math.min(1, (Notices.SHOW - n.age) / Notices.FADE)
    local h = #n.lines * 8 + 8
    if shader then
      love.graphics.setColor(0, 0, 0, 0.75 * alpha)
      love.graphics.rectangle("fill", 0, y, 160, h)
      love.graphics.setShader(shader)
      love.graphics.setColor(1, 1, 1, alpha)
      for i, line in ipairs(n.lines) do Font.draw(line, 8, y + 4 + (i - 1) * 8) end
      love.graphics.setShader()
    else
      -- no shaders here: the cartridge's own box
      Font.drawBox(0, y / 8, 20, #n.lines + 2)
      love.graphics.setColor(0, 0, 0, 1)
      for i, line in ipairs(n.lines) do Font.draw(line, 8, y + i * 8) end
      h = (#n.lines + 2) * 8
    end
    y = y + h
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Notices
