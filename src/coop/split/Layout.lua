-- Where the two split-screen views go in the window (#11): side by side or
-- stacked, whichever lets each 160x144 view be drawn at the larger whole
-- scale (each view's renderer then fits the Game Boy screen into its own
-- rect, as it fits the whole window in solo play).  A tie goes to side by
-- side in a window wider than tall, else stacked.
--
--   local views, how = Layout.views(1280, 576)  -- views[1], views[2]: { x, y, width, height }

local Layout = {}

Layout.WIDTH, Layout.HEIGHT = 160, 144

-- the scale one view of w x h draws at: whole when it reaches 1
local function scale(w, h)
  local s = math.min(w / Layout.WIDTH, h / Layout.HEIGHT)
  if s >= 1 then return math.floor(s) end
  return s
end
Layout.scale = scale

-- the two views' rects in window units, and "side" or "stacked"
function Layout.views(w, h)
  w, h = math.max(2, math.floor(w)), math.max(2, math.floor(h))
  local half = math.floor(w / 2)
  local side = scale(half, h)
  local midY = math.floor(h / 2)
  local stacked = scale(w, midY)
  if side > stacked or (side == stacked and w >= h) then
    return { { x = 0, y = 0, width = half, height = h },
             { x = half, y = 0, width = w - half, height = h } }, "side"
  end
  return { { x = 0, y = 0, width = w, height = midY },
           { x = 0, y = midY, width = w, height = h - midY } }, "stacked"
end

-- A window size that shows both views side by side at `s` (the scale a
-- solo window had), within the desktop's w x h; nil when it already fits.
function Layout.grow(windowW, windowH, s, desktopW, desktopH)
  s = math.max(1, math.floor(s or 1))
  local views = Layout.views(windowW, windowH)
  if scale(views[1].width, views[1].height) >= s then return nil end
  local want = s
  while want > 1 and (2 * Layout.WIDTH * want > (desktopW or math.huge)
                      or Layout.HEIGHT * want > (desktopH or math.huge)) do
    want = want - 1
  end
  local w, h = 2 * Layout.WIDTH * want, math.max(windowH, Layout.HEIGHT * want)
  if w <= windowW then return nil end
  return w, h
end

return Layout
