-- The fork's launcher menu (#3, laid out anew in #38), as a model with no
-- drawing and no love.*: tabs, screens, the selected cartridge, cursor and
-- what a button press asks the host to do.  Screens.lua lays the state out,
-- Launcher.lua turns keys, pads, mouse and touch into the actions below and
-- paints it; tests drive it directly.
--
-- Tabs: PLAY (the cartridge, solo, host, join, couch co-op, the last
-- session), CAMPAIGNS, CONTROLS, SETTINGS, HELP.  Under them: the solo
-- sheet, the ROM import and the co-op flows (CoopMenu.lua, #12).
--
-- Actions: "up", "down", "left", "right", "a", "b", "start".
-- A press may return a command for the host:
--   { kind = "boot", version = v, newGame = bool }
--   { kind = "import", path = p }          (a typed ROM path)
--   { kind = "quit" }
--   { kind = "open_logs" }
--   { kind = "settings" }                  (language or theme changed)
-- and the co-op screens' commands (CoopMenu.lua).  The CONTROLS rows come
-- from Controls.lua (#4); while it captures a key or pad press the host
-- hands raw presses to Menu:captured instead of actions.

local CoopMenu = require("src.coop.launcher.CoopMenu")
local Games = require("src.coop.launcher.Games")
local Text = require("src.coop.launcher.Text")
local L = Text.get

local Menu = {}
Menu.__index = Menu

-- The credit term 1 of upstream's LICENSE.MD asks every launcher to show,
-- word for word in every language.
Menu.CREDIT = "Based on the Pokemon Gen 1 Recompilation Project by BOIS CLUB "
  .. "GAMES, LLC (https://github.com/bryanthaboi/gen1recomp)"

Menu.TITLE = "GEN1 CO·OP"

Menu.TABS = { "play", "campaigns", "controls", "settings", "help" }
Menu.TAB_LABELS = { play = "PLAY", campaigns = "CAMPAIGNS", controls = "CONTROLS",
                    settings = "SETTINGS", help = "HELP" }

-- the cartridges the launcher plays, with their names on the cartridge
Menu.GAMES = Games.LIST
Menu.gameLabel = Games.label
local gameLabel = Games.label

-- paragraphs of the credits block on the HELP tab
function Menu.credits()
  return {
    Menu.CREDIT,
    L("Co-op fork: github.com/Clodmony/gen1recomp-coop"),
    L("The co-op fork is written by AI coding agents directed by the repository owner."),
    L("Plain Pixel font by Douglas Vautour, CC BY 4.0."),
    L("Pokemon is a trademark of Nintendo, Creatures and GAME FREAK. This project is not affiliated with them."),
  }
end

-- opts:
--   ready(version)    -> bool, the version's ROM is imported
--   saveInfo(version) -> nil or { name, badges, time }, the active save
--   canQuit           -> offer QUIT (desktop; a phone closes the app itself)
--   canType           -> the import screen takes a typed path
--   initial           -> preselect this game
--   coop(version)     -> the co-op screens' env (CoopMenu.lua), or nil for
--                        no co-op
--   settings          -> a CoopSettings (language, theme, logs, last session)
--   campaigns         -> the campaign cards (Campaigns.lua), for the last
--                        session
--   canOpenLogs       -> the logs folder can be opened (desktop)
--   controls          -> the CONTROLS page's model (Controls.lua), or nil
function Menu.new(opts)
  opts = opts or {}
  local self = setmetatable({
    ready = opts.ready or function() return false end,
    saveInfo = opts.saveInfo or function() return nil end,
    canQuit = opts.canQuit ~= false,
    canType = opts.canType ~= false,
    canOpenLogs = opts.canOpenLogs == true,
    coopEnv = opts.coop,
    settings = opts.settings,
    campaigns = opts.campaigns,
    controls = opts.controls,
    screen = "play", tab = "play", cursor = 1, path = "",
    version = Menu.GAMES[1].id,
  }, Menu)
  for _, g in ipairs(Menu.GAMES) do
    if g.id == opts.initial then self.version = g.id end
  end
  self:_cursorTo("cart", self.version)
  return self
end

-- the screen is a tab's own page (the tabs can take the focus)
function Menu:isTop()
  if self.screen == "coop" then return self.coop ~= nil and self.coop.screen == "campaigns" end
  return self.tab == self.screen
end

-- The rows of the current screen: { id, label, detail?, enabled?, game? }.
-- Their order is the order the focus walks without a layout.
function Menu:items()
  local rows = {}
  local function add(row) rows[#rows + 1] = row; return row end
  local s = self.screen
  if s == "play" then
    local ready = self.ready(self.version)
    for _, g in ipairs(Menu.GAMES) do
      add({ id = "cart", game = g.id, label = g.label,
            detail = self.ready(g.id) and L("Ready") or L("Import ROM") })
    end
    add({ id = "solo", label = L("PLAY SOLO"), enabled = ready })
    local coop = self.coopEnv ~= nil
    add({ id = "host", label = L("HOST A CAMPAIGN"), enabled = coop and ready })
    add({ id = "join", label = L("JOIN A FRIEND"), enabled = coop and self:_anyReady() })
    -- two seats on one device come with #4 and #11
    add({ id = "couch", label = L("COUCH CO-OP"), enabled = false, planned = true })
    if not ready then add({ id = "import", label = L("IMPORT ROM") }) end
    local last = self:lastSession()
    if last then
      add({ id = "last", label = last.kind == "host" and L("HOST AGAIN") or L("REJOIN"),
            enabled = self.ready(last.version) or last.kind == "join" })
    end
  elseif s == "solo" then
    if self.saveInfo(self.version) then add({ id = "continue", label = L("CONTINUE") }) end
    add({ id = "new", label = L("NEW GAME") })
    add({ id = "reimport", label = L("IMPORT AGAIN") })
    add({ id = "back", label = L("BACK") })
  elseif s == "controls" then
    if self.controls then
      for _, row in ipairs(self.controls:rows()) do add(row) end
    end
  elseif s == "settings" then
    local settings = self.settings or {}
    add({ id = "language", label = L("LANGUAGE"), detail = Text.NAMES[Text.language] })
    add({ id = "theme", label = L("THEME"),
          detail = settings.theme == "dark" and L("DARK") or L("LIGHT") })
  elseif s == "help" then
    local settings = self.settings or {}
    add({ id = "share", label = L("SHARE LOGS"), detail = settings.shareLogs == false
          and L("OFF") or L("ON") })
    if self.canOpenLogs then add({ id = "open", label = L("OPEN LOGS FOLDER") }) end
  end
  return rows
end

function Menu:_anyReady()
  for _, g in ipairs(Menu.GAMES) do
    if self.ready(g.id) then return true end
  end
  return false
end

-- the last session this device remembers, when it can be resumed:
-- { kind = "host", version, campaign = card } or { kind = "join", version,
-- address, title }
function Menu:lastSession()
  local settings = self.settings
  local last = settings and settings.last
  if not last or not self.coopEnv then return nil end
  if last.kind == "host" then
    local card = self.campaigns and self.campaigns.get(last.campaign)
    if not card then return nil end
    return { kind = "host", version = last.version, campaign = card }
  end
  return { kind = "join", version = last.version, address = last.address, title = last.title }
end

function Menu:_cursorTo(id, game)
  for i, row in ipairs(self:items()) do
    if row.id == id and (game == nil or row.game == game) then
      self.cursor = i
      return true
    end
  end
  return false
end

function Menu:go(screen, version)
  self.screen = screen
  self.version = version or self.version
  self.cursor = 1
  for _, t in ipairs(Menu.TABS) do
    if t == screen then self.tab = t end
  end
end

-- open a tab (the nav bar)
function Menu:openTab(tab)
  if self.coop then self:_leaveCoop() end
  if self.controls then self.controls:cancel() end
  if tab == "campaigns" then
    self.tab = "campaigns"
    if self:openCoop(self.version, nil, "campaigns") then return end
    self:go("play")
    return
  end
  self:go(tab)
  if tab == "play" then self:_cursorTo("cart", self.version) end
end

-- A message box over the current screen; any button closes it.
function Menu:notify(text)
  if self.coop then return self.coop:notify(text) end
  self.notice = text
end

function Menu:currentNotice()
  if self.screen == "coop" and self.coop then return self.coop.notice end
  return self.notice
end

-- The CONTROLS page is waiting for a key or pad press (#4): the prompt, or
-- nil.  While it is, the host sends raw presses to captured().
function Menu:capturing()
  if self.screen ~= "controls" or not self.controls then return nil end
  return self.controls:prompt()
end

-- a raw press while capturing: { kind = "key", key } | { kind = "pad",
-- button, device } | { kind = "cancel" }; true when it was used
function Menu:captured(ev)
  if not self:capturing() then return false end
  return self.controls:captured(ev)
end

-- the co-op screens of `version` (#12) from `start` ("host", "join",
-- "campaigns" or "last"), with a message on top
function Menu:openCoop(version, notice, start)
  local env = self.coopEnv and self.coopEnv(version)
  if not env then return false end
  self.version = version
  self.coop = CoopMenu.new(env, { notice = notice, start = start or "host" })
  self.screen, self.cursor = "coop", 1
  if start == "campaigns" then self.tab = "campaigns" end
  return true
end

function Menu:_leaveCoop()
  local coop = self.coop
  self.coop = nil
  if coop then coop:close() end
end

local function closeCoop(self, command)
  local from = self.coop and self.coop.root
  local notice = self.coop and self.coop.notice
  self:_leaveCoop()
  self:go("play")
  if not self:_cursorTo(from == "join" and "join" or "host") then self:_cursorTo("cart", self.version) end
  if command and command.notice then notice = command.notice end
  self.notice = notice
end

-- One frame; the co-op screens may return a command (a joined session
-- enters the world).
function Menu:update(dt)
  if self.screen ~= "coop" or not self.coop then return nil end
  local command = self.coop:update(dt)
  if command and command.kind == "coop_exit" then return closeCoop(self, command) end
  return command
end

function Menu:importStarted(version, name)
  self.notice = nil
  if self.coop then self:_leaveCoop() end
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
  self:go("play", version)
  self:_cursorTo("solo")
  self:notify(L("%s is ready to play.", gameLabel(version)))
end

function Menu:importFailed(message)
  local version = self.importing and self.importing.version or self.version
  self.importing = nil
  if version and self.ready(version) then
    self:go("play", version)
  else
    self:go("import", version)
  end
  self:notify(message)
end

local function move(self, delta)
  local rows = self:items()
  if #rows == 0 then return end
  for _ = 1, #rows do
    self.cursor = (self.cursor - 1 + delta) % #rows + 1
    if rows[self.cursor].enabled ~= false then break end
  end
end

-- pick a cartridge on PLAY
function Menu:select(version)
  self.version = version
  if self.settings and self.settings.picked then self.settings:picked(version) end
end

local function settingsChanged(self)
  if self.settings and self.settings.save then self.settings:save() end
  return { kind = "settings" }
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
  if screen == "coop" and self.coop then
    local command = self.coop:press(action)
    if command and command.kind == "coop_exit" then return closeCoop(self, command) end
    return command
  end
  if screen == "importing" then return nil end
  if screen == "import" and action == "b" then
    self:go("play")
    self:_cursorTo("cart", self.version)
    return nil
  end
  if screen == "import" and (action == "a" or action == "start") then
    if self.path ~= "" then return { kind = "import", path = self.path } end
    return nil
  end
  if action == "up" or action == "left" then move(self, -1) return nil end
  if action == "down" or action == "right" then move(self, 1) return nil end
  if action == "b" then
    if screen == "solo" then
      self:go("play")
      self:_cursorTo("solo")
    elseif screen ~= "play" then
      self:openTab("play")
    end
    return nil
  end
  if action ~= "a" and action ~= "start" then return nil end
  local row = self:items()[self.cursor]
  if not row or row.enabled == false then return nil end
  local id = row.id

  if screen == "play" then
    if id == "cart" then
      self:select(row.game)
      return nil
    elseif id == "solo" then
      self:go("solo")
    elseif id == "host" then
      self:openCoop(self.version, nil, "host")
    elseif id == "join" then
      self:openCoop(self.version, nil, "join")
    elseif id == "import" then
      self.path = ""
      self:go("import")
    elseif id == "last" then
      local last = self:lastSession()
      local version = last.kind == "host" and last.version
        or (self.ready(last.version) and last.version or self.version)
      if self:openCoop(version, nil, "last") then
        return self.coop:resume()
      end
    end
    return nil
  elseif screen == "solo" then
    if id == "continue" then
      return { kind = "boot", version = self.version, newGame = false }
    elseif id == "new" then
      return { kind = "boot", version = self.version,
        newGame = self.saveInfo(self.version) ~= nil }
    elseif id == "reimport" then
      self.path = ""
      self:go("import")
    elseif id == "back" then
      return self:press("b")
    end
  elseif screen == "controls" then
    if self.controls then self.controls:press(row) end
  elseif screen == "settings" then
    local settings = self.settings
    if id == "language" then
      local nextLanguage = Text.language == "de" and "en" or "de"
      Text.set(nextLanguage)
      if settings then settings.language = nextLanguage end
      return settingsChanged(self)
    elseif id == "theme" and settings then
      settings.theme = settings.theme == "dark" and "light" or "dark"
      return settingsChanged(self)
    end
  elseif screen == "help" then
    local settings = self.settings
    if id == "share" and settings then
      settings.shareLogs = settings.shareLogs == false
      return settingsChanged(self)
    elseif id == "open" then
      return { kind = "open_logs" }
    end
  end
  return nil
end

-- Typing on the import screen or a co-op text field.
function Menu:text(t)
  if self.screen == "coop" and self.coop then return self.coop:text(t) end
  if self.screen ~= "import" or self.notice or not self.canType then return end
  self.path = self.path .. t
end

function Menu:erase()
  if self.screen == "coop" and self.coop then return self.coop:erase() end
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

return Menu
