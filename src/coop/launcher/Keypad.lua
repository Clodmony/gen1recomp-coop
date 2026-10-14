-- Text entry for the launcher's co-op screens (#12): a grid of characters
-- in the style of the cartridge's naming screen, so a pad, a touch screen
-- or a phone (design A2.9: an address opens a number pad) can type a name or
-- an address; a keyboard types into it directly.  A model with no love.*.
--
--   local k = Keypad.new({ kind = "address", text = "192.168.", max = 40 })
--   k:press("right") ... k:press("a")  -- "done" or "cancel" when finished
--   k:input("1"); k:erase()
--   k.text, k:rows()

local Keypad = {}
Keypad.__index = Keypad

Keypad.COLUMNS = 9

-- a name: the cartridge's capitals, digits and a few marks; an address: the
-- digits and marks first (the number pad), then the small letters of a
-- host name
Keypad.SETS = {
  name = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.",
  address = "0123456789.:-abcdefghijklmnopqrstuvwxyz",
}

-- the last row: SPACE (names only), DEL and END
local function specials(kind)
  if kind == "address" then return { "DEL", "END" } end
  return { "SPACE", "DEL", "END" }
end

function Keypad.new(opts)
  opts = opts or {}
  local kind = Keypad.SETS[opts.kind] and opts.kind or "name"
  local self = setmetatable({
    kind = kind, max = opts.max or 10, text = "",
    row = 1, col = 1,
  }, Keypad)
  self.chars = {}
  for c in Keypad.SETS[kind]:gmatch(".") do self.chars[#self.chars + 1] = c end
  self.keys = specials(kind)
  self:input(opts.text or "")
  return self
end

-- the grid: rows of characters, then the row of special keys
function Keypad:rows()
  local rows, row = {}, {}
  for _, c in ipairs(self.chars) do
    row[#row + 1] = c
    if #row == Keypad.COLUMNS then rows[#rows + 1] = row; row = {} end
  end
  if #row > 0 then rows[#rows + 1] = row end
  rows[#rows + 1] = self.keys
  return rows
end

function Keypad:current()
  local rows = self:rows()
  local row = rows[self.row]
  return row[math.min(self.col, #row)]
end

-- a character fits when it is in the set; an address keeps its case as
-- typed, a name is the cartridge's capitals
function Keypad:accepts(c)
  if self.kind == "name" then
    c = c:upper()
    if c == " " then return c end
  else
    c = c:lower()
  end
  for _, k in ipairs(self.chars) do
    if k == c then return c end
  end
  return nil
end

function Keypad:input(t)
  for c in tostring(t):gmatch(".") do
    local ok = self:accepts(c)
    if ok and #self.text < self.max then self.text = self.text .. ok end
  end
end

function Keypad:erase()
  self.text = self.text:sub(1, -2)
end

-- One button.  Returns "done" (END or START) or "cancel" (B on an empty
-- field), else nil.
function Keypad:press(action)
  local rows = self:rows()
  if action == "up" or action == "down" then
    self.row = (self.row - 1 + (action == "up" and -1 or 1)) % #rows + 1
    self.col = math.min(self.col, #rows[self.row])
  elseif action == "left" or action == "right" then
    local width = #rows[self.row]
    self.col = math.min(self.col, width)
    self.col = (self.col - 1 + (action == "left" and -1 or 1)) % width + 1
  elseif action == "start" then
    return "done"
  elseif action == "b" then
    if self.text == "" then return "cancel" end
    self:erase()
  elseif action == "a" then
    local key = self:current()
    if key == "END" then return "done" end
    if key == "DEL" then
      self:erase()
    elseif key == "SPACE" then
      self:input(" ")
    else
      self:input(key)
    end
  end
  return nil
end

-- the cell a tap at grid row r, column c picks (special keys spread over
-- the row); returns true when it moved the cursor there
function Keypad:pick(r, c)
  local rows = self:rows()
  if not rows[r] or c < 1 or c > #rows[r] then return false end
  self.row, self.col = r, c
  return true
end

return Keypad
