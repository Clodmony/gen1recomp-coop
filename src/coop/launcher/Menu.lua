-- The fork's launcher menu (#3), as a model with no drawing and no love.*:
-- screens, cursor and what a button press asks the host to do.  Launcher.lua
-- turns keys, pads, mouse and touch into the actions below and draws the
-- state; tests drive it directly.
--
-- Actions: "up", "down", "left", "right", "a", "b", "start".
-- A press may return a command for the host:
--   { kind = "boot", version = v, newGame = bool }
--   { kind = "import", path = p }          (a typed ROM path)
--   { kind = "quit" }

local Menu = {}
Menu.__index = Menu

-- The credit term 1 of upstream's LICENSE.MD asks every launcher to show.
Menu.CREDIT = "Based on the Pokemon Gen 1 Recompilation Project by BOIS CLUB "
  .. "GAMES, LLC (https://github.com/bryanthaboi/gen1recomp)"

Menu.TITLE = "GEN 1 RECOMP CO-OP"

Menu.CREDITS = {
  "CREDITS",
  "",
  Menu.CREDIT,
  "",
  "Co-op fork: github.com/Clodmony/gen1recomp-coop",
  "",
  "The co-op fork is written by AI coding agents directed by the "
    .. "repository owner.",
  "",
  "Plain Pixel font by Douglas Vautour, CC BY 4.0.",
  "",
  "Pokemon is a trademark of Nintendo, Creatures and GAME FREAK. This "
    .. "project is not affiliated with them.",
}

Menu.GAMES = {
  { id = "red", label = "RED" },
  { id = "blue", label = "BLUE" },
  { id = "yellow", label = "YELLOW" },
}

local function gameLabel(version)
  for _, g in ipairs(Menu.GAMES) do
    if g.id == version then return g.label end
  end
  return tostring(version):upper()
end
Menu.gameLabel = gameLabel

-- opts:
--   ready(version)    -> bool, the version's ROM is imported
--   saveInfo(version) -> nil or { name, badges, time }, the active save
--   canQuit           -> show QUIT (desktop; a phone closes the app itself)
--   canType           -> the import screen takes a typed path
--   initial           -> preselect this game
function Menu.new(opts)
  opts = opts or {}
  local self = setmetatable({
    ready = opts.ready or function() return false end,
    saveInfo = opts.saveInfo or function() return nil end,
    canQuit = opts.canQuit ~= false,
    canType = opts.canType ~= false,
    screen = "title", cursor = 1, scroll = 0, path = "",
  }, Menu)
  for i, g in ipairs(Menu.GAMES) do
    if g.id == opts.initial then self.cursor = i end
  end
  return self
end

-- The rows of the current screen: { id, label, detail?, enabled }.
function Menu:items()
  if self.screen == "title" then
    local rows = {}
    for _, g in ipairs(Menu.GAMES) do
      rows[#rows + 1] = { id = g.id, label = g.label,
        detail = not self.ready(g.id) and "NO ROM" or nil }
    end
    rows[#rows + 1] = { id = "credits", label = "CREDITS" }
    if self.canQuit then rows[#rows + 1] = { id = "quit", label = "QUIT" } end
    return rows
  elseif self.screen == "game" then
    local rows = {}
    if self.saveInfo(self.version) then
      rows[#rows + 1] = { id = "continue", label = "CONTINUE" }
    end
    rows[#rows + 1] = { id = "new", label = "NEW GAME" }
    rows[#rows + 1] = { id = "reimport", label = "NEW ROM" }
    rows[#rows + 1] = { id = "back", label = "BACK" }
    return rows
  end
  return {}
end

function Menu:go(screen, version)
  self.screen = screen
  self.version = version or self.version
  self.cursor, self.scroll = 1, 0
end

-- A message box over the current screen; any button closes it.
function Menu:notify(text)
  self.notice = text
end

function Menu:importStarted(version, name)
  self.notice = nil
  self.importing = { version = version, name = name, progress = 0, stage = "Preparing" }
  self:go("importing", version)
end

function Menu:importProgress(progress, stage)
  if not self.importing then return end
  self.importing.progress = progress or self.importing.progress
  self.importing.stage = stage or self.importing.stage
end

function Menu:importDone(version)
  self.importing = nil
  self:go("game", version)
  self:notify(gameLabel(version) .. " is ready to play.")
end

function Menu:importFailed(message)
  local version = self.importing and self.importing.version or self.version
  self.importing = nil
  if version and self.ready(version) then
    self:go("game", version)
  else
    self:go("import", version)
  end
  self:notify(message)
end

local function move(self, delta)
  local count = #self:items()
  if count == 0 then return end
  self.cursor = (self.cursor - 1 + delta) % count + 1
end

local function choose(self, version)
  if self.ready(version) then
    self:go("game", version)
  else
    self.path = ""
    self:go("import", version)
  end
end

-- One button press.  Returns a command for the host, or nil.
function Menu:press(action)
  if self.notice then
    if action == "a" or action == "b" or action == "start" then
      self.notice = nil
    end
    return nil
  end
  local screen = self.screen
  if screen == "importing" then return nil end
  if screen == "credits" then
    if action == "up" then self.scroll = math.max(0, self.scroll - 1)
    elseif action == "down" then self.scroll = self.scroll + 1
    elseif action == "a" or action == "b" or action == "start" then
      self:go("title")
      self.cursor = #Menu.GAMES + 1
    end
    return nil
  end
  if screen == "import" then
    if action == "b" then
      self:go("title")
      for i, g in ipairs(Menu.GAMES) do
        if g.id == self.version then self.cursor = i end
      end
    elseif (action == "a" or action == "start") and self.path ~= "" then
      return { kind = "import", path = self.path }
    end
    return nil
  end

  if action == "up" then move(self, -1) return nil end
  if action == "down" then move(self, 1) return nil end
  local row = self:items()[self.cursor]
  if screen == "title" then
    if action ~= "a" and action ~= "start" then return nil end
    if row.id == "credits" then
      self:go("credits")
    elseif row.id == "quit" then
      return { kind = "quit" }
    else
      choose(self, row.id)
    end
    return nil
  end
  if screen == "game" then
    if action == "b" then
      local version = self.version
      self:go("title")
      for i, g in ipairs(Menu.GAMES) do
        if g.id == version then self.cursor = i end
      end
      return nil
    end
    if action ~= "a" and action ~= "start" then return nil end
    if row.id == "continue" then
      return { kind = "boot", version = self.version, newGame = false }
    elseif row.id == "new" then
      return { kind = "boot", version = self.version,
        newGame = self.saveInfo(self.version) ~= nil }
    elseif row.id == "reimport" then
      self.path = ""
      self:go("import", self.version)
    elseif row.id == "back" then
      return self:press("b")
    end
  end
  return nil
end

-- Typing on the import screen.
function Menu:text(t)
  if self.screen ~= "import" or self.notice or not self.canType then return end
  self.path = self.path .. t
end

function Menu:erase()
  if self.screen ~= "import" or self.notice then return end
  self.path = self.path:sub(1, -2)
  -- drop a whole UTF-8 sequence, not half of one
  while #self.path > 0 and self.path:byte(-1) >= 0x80
      and self.path:byte(-1) < 0xC0 do
    self.path = self.path:sub(1, -2)
  end
  if #self.path > 0 and self.path:byte(-1) >= 0xC0 then
    self.path = self.path:sub(1, -2)
  end
end

-- Word wrap to `width` columns; a word longer than a line is split.
function Menu.wrap(text, width)
  local lines, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    local candidate = line == "" and word or (line .. " " .. word)
    if #candidate <= width then
      line = candidate
    else
      if line ~= "" and #word <= width then
        lines[#lines + 1] = line
        line = word
      else
        -- fill the current line, then carry the rest of the long word
        local rest = candidate
        while #rest > width do
          lines[#lines + 1] = rest:sub(1, width)
          rest = rest:sub(width + 1)
        end
        line = rest
      end
    end
  end
  if line ~= "" or #lines == 0 then lines[#lines + 1] = line end
  return lines
end

return Menu
