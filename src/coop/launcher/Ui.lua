-- The launcher's page description (#38): what a screen shows, as a list of
-- plain nodes with no love.* calls, so tests can read a page and Launcher.lua
-- only paints it.  Pixels are the launcher's own (one Plain Pixel glyph is
-- 6 wide); Launcher.lua scales them to the window in whole steps.
--
-- Nodes:
--   { kind = "rect",  x, y, w, h, colour, alpha }
--   { kind = "icon",  x, y, name, colour }         "check", "cross", "dot", "dash"
--   { kind = "frame", x, y, w, h, colour, thick }  a border inside the box
--   { kind = "text",  x, y, text, colour, scale, underline }
--   { kind = "hit",   x, y, w, h, key, act, enabled }  a focusable target
-- A node may carry `clip` = { x, y, w, h } (the scrolled content area).
-- Colours are Theme names ("ink", "muted", "accent", ...).
--
-- Focus moves between hit nodes by position (neighbour), so keyboard, pad,
-- mouse and touch share one order; the hit's `act` says what a press does.

local Ui = {}

Ui.CHAR = 6    -- glyph advance at scale 1
Ui.LINE = 14   -- a line of text at scale 1

-- glyphs drawn two cells wide in Plain Pixel
local WIDE = { [0x2190] = true, [0x2191] = true, [0x2192] = true, [0x2193] = true }

local function codepoints(s)
  local out = {}
  for ch in tostring(s):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
  return out
end
Ui.codepoints = codepoints

local function cells(ch)
  local b1, b2, b3 = ch:byte(1, 3)
  if b1 == 0xE2 and b2 and b3 then
    local cp = (b1 - 0xE0) * 4096 + (b2 - 0x80) * 64 + (b3 - 0x80)
    if WIDE[cp] then return 2 end
  end
  return 1
end

-- the width of `text` in launcher pixels
function Ui.width(text, scale)
  local n = 0
  for _, ch in ipairs(codepoints(text)) do n = n + cells(ch) end
  return n * Ui.CHAR * (scale or 1)
end

-- the first characters of `text` that fit `width` (no ellipsis glyph in the
-- font: a cut ends in "..")
function Ui.fit(text, width, scale)
  text = tostring(text or "")
  if Ui.width(text, scale) <= width then return text end
  local out, w = {}, Ui.width("..", scale)
  for _, ch in ipairs(codepoints(text)) do
    local cw = cells(ch) * Ui.CHAR * (scale or 1)
    if w + cw > width then break end
    out[#out + 1] = ch
    w = w + cw
  end
  return table.concat(out) .. ".."
end

-- Word wrap to `width` pixels; a word longer than a line is split.
function Ui.wrap(text, width, scale)
  local lines = {}
  for para in (tostring(text) .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      local candidate = line == "" and word or (line .. " " .. word)
      if Ui.width(candidate, scale) <= width then
        line = candidate
      else
        if line ~= "" then lines[#lines + 1] = line end
        line = ""
        local part = {}
        for _, ch in ipairs(codepoints(word)) do
          if Ui.width(table.concat(part) .. ch, scale) > width and #part > 0 then
            lines[#lines + 1] = table.concat(part)
            part = {}
          end
          part[#part + 1] = ch
        end
        line = table.concat(part)
      end
    end
    lines[#lines + 1] = line
  end
  return lines
end

-- ------------------------------------------------------------ page

local Page = {}
Page.__index = Page

function Ui.page(w, h)
  return setmetatable({ w = w, h = h, nodes = {}, dy = 0, clip = nil }, Page)
end

function Page:add(node)
  node.y = node.y and node.y + self.dy or node.y
  node.clip = node.clip or self.clip
  self.nodes[#self.nodes + 1] = node
  return node
end

function Page:rect(x, y, w, h, colour, alpha)
  return self:add({ kind = "rect", x = x, y = y, w = w, h = h, colour = colour, alpha = alpha })
end

function Page:frame(x, y, w, h, colour, thick)
  return self:add({ kind = "frame", x = x, y = y, w = w, h = h, colour = colour,
                    thick = thick or 1 })
end

function Page:text(x, y, text, colour, scale, underline)
  return self:add({ kind = "text", x = x, y = y, text = tostring(text), colour = colour or "ink",
                    scale = scale or 1, underline = underline })
end

-- wrapped text from (x, y) in `width`; returns the height used
function Page:para(x, y, width, text, colour, scale, maxLines)
  local lh = Ui.LINE * (scale or 1)
  local n = 0
  for _, line in ipairs(Ui.wrap(text, width, scale)) do
    if maxLines and n >= maxLines then break end
    self:text(x, y + n * lh, line, colour, scale)
    n = n + 1
  end
  return n * lh
end

function Page:hit(x, y, w, h, key, act, enabled)
  return self:add({ kind = "hit", x = x, y = y, w = w, h = h, key = key, act = act,
                    enabled = enabled ~= false })
end

-- the hit nodes in page order
function Page:targets()
  local out = {}
  for _, n in ipairs(self.nodes) do
    if n.kind == "hit" then out[#out + 1] = n end
  end
  return out
end

function Page:find(key)
  for _, n in ipairs(self.nodes) do
    if n.kind == "hit" and n.key == key then return n end
  end
  return nil
end

-- every text on the page, in order (tests, the credit check)
function Page:texts()
  local out = {}
  for _, n in ipairs(self.nodes) do
    if n.kind == "text" then out[#out + 1] = n.text end
  end
  return out
end

-- the hit under a point, or nil
function Page:at(px, py)
  for i = #self.nodes, 1, -1 do
    local n = self.nodes[i]
    if n.kind == "hit" and px >= n.x and px < n.x + n.w and py >= n.y and py < n.y + n.h then
      local c = n.clip
      if not c or (px >= c.x and px < c.x + c.w and py >= c.y and py < c.y + c.h) then
        return n
      end
    end
  end
  return nil
end

-- ------------------------------------------------------------ focus

local function gap(a1, a2, b1, b2)
  if b1 >= a2 then return b1 - a2 end
  if a1 >= b2 then return a1 - b2 end
  return 0
end

-- The enabled hit in direction `dir` ("up", "down", "left", "right") from
-- the hit `from`: the nearest one past its edge, preferring targets in line
-- with it.  nil when there is none.
function Ui.neighbour(page, from, dir)
  local f = type(from) == "table" and from or page:find(from)
  if not f then return nil end
  local best, bestScore
  for _, c in ipairs(page:targets()) do
    if c ~= f and c.enabled then
      local primary, lateral
      if dir == "down" and c.y >= f.y + f.h - 1 and c.y > f.y then
        primary, lateral = c.y - (f.y + f.h), gap(f.x, f.x + f.w, c.x, c.x + c.w)
      elseif dir == "up" and c.y + c.h <= f.y + 1 and c.y < f.y then
        primary, lateral = f.y - (c.y + c.h), gap(f.x, f.x + f.w, c.x, c.x + c.w)
      elseif dir == "right" and c.x >= f.x + f.w - 1 and c.x > f.x then
        primary, lateral = c.x - (f.x + f.w), gap(f.y, f.y + f.h, c.y, c.y + c.h)
      elseif dir == "left" and c.x + c.w <= f.x + 1 and c.x < f.x then
        primary, lateral = f.x - (c.x + c.w), gap(f.y, f.y + f.h, c.y, c.y + c.h)
      end
      if primary then
        local score = math.max(0, primary) + lateral * 3
        -- tie: the one whose centre is nearest across the move
        local across = (dir == "up" or dir == "down")
          and math.abs((c.x + c.w / 2) - (f.x + f.w / 2))
          or math.abs((c.y + c.h / 2) - (f.y + f.h / 2))
        score = score * 1000 + across
        if not bestScore or score < bestScore then best, bestScore = c, score end
      end
    end
  end
  return best
end

return Ui
