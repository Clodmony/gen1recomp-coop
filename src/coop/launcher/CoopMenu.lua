-- The launcher's co-op screens (#12, design A2) as a model with no drawing
-- and no love.*: Co-op (HOST, JOIN, LAST SESSION, LOGS), the host's
-- campaign cards (new, rename, delete to a backup), the Hosting screen (the
-- addresses partners join at, the players in, ENTER WORLD, STOP), Join
-- (nearby hosts from the LAN beacon, by address, recent addresses) and the
-- Connecting sheet (each step, retries with a countdown, the exact reason
-- for a refusal, a checklist when nobody answered).
--
-- Every screen is laid out in Game Boy text cells (20 columns, rows 0-11
-- above the credit line) by view(); Launcher.lua draws it and turns taps
-- into rows.  The session, campaigns and settings are reached through
-- `env` (Launcher.lua passes the real ones, tests their own):
--
--   env.version            the cartridge picked on the title screen
--   env.ready(v)           the game's ROM is imported here
--   env.settings           a CoopSettings
--   env.campaigns          Campaigns (list, create, rename, delete, get, touch)
--   env.host(campaign, name, version) -> a hosting Session
--   env.dial(address, version, name)  -> a dialling Session
--   env.nearby()           -> a Beacon listener, or nil and why
--   env.closeNearby()
--   env.addresses()        -> { { ip, kind } }, this device's addresses
--   env.canOpenLogs        the logs folder can be opened (desktop)
--
-- Actions: "up", "down", "left", "right", "a", "b", "start".  A press or
-- update() may return a command for the launcher:
--   { kind = "coop_enter", version = v, campaign = { id, title } }
--   { kind = "copy", text = "…" }
--   { kind = "open_logs" }
--   { kind = "coop_exit" }        back to the game's own screen

local Addresses = require("src.coop.session.Addresses")
local Keypad = require("src.coop.launcher.Keypad")
local Protocol = require("src.coop.session.Protocol")

local CoopMenu = {}
CoopMenu.__index = CoopMenu

CoopMenu.COLS = 20
CoopMenu.LIST_ROWS = { 2, 4, 6, 8, 10 } -- a list's rows inside the box
CoopMenu.TITLE_MAX = 16
CoopMenu.DEFAULT_PORT = 24680

local GAMES = { red = "RED", blue = "BLUE", yellow = "YELLOW" }
local function label(v) return GAMES[v] or tostring(v or "?"):upper() end
CoopMenu.gameLabel = label

-- Word wrap to `width` columns (Menu.wrap's rule).
local function wrap(text, width)
  local lines, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    local candidate = line == "" and word or (line .. " " .. word)
    if #candidate <= width then
      line = candidate
    elseif line ~= "" and #word <= width then
      lines[#lines + 1] = line
      line = word
    else
      local rest = candidate
      while #rest > width do
        lines[#lines + 1] = rest:sub(1, width)
        rest = rest:sub(width + 1)
      end
      line = rest
    end
  end
  if line ~= "" or #lines == 0 then lines[#lines + 1] = line end
  return lines
end
CoopMenu.wrap = wrap

-- the sentence for a refusal (design A2.5: a mismatch is named exactly)
function CoopMenu.reasonText(reason, lobby, version)
  if reason == "content_mismatch" and lobby then
    if lobby.game ~= version then
      return ("The host plays %s. This game is %s."):format(label(lobby.game), label(version))
    end
    return ("The host's %s ROM is another dump than this one."):format(label(version))
  elseif reason == "protocol_mismatch" then
    return "The host runs another version of this co-op game. Both need the same one."
  elseif reason == "session_full" then
    return "The session is full."
  elseif reason == "shutting_down" then
    return "The host is closing the session."
  elseif reason == "flood" then
    return "The host dropped this game: it sent too much at once."
  end
  return ("The host turned this game away (%s)."):format(tostring(reason))
end

local function hostOnly(address)
  return (tostring(address or ""):gsub(":%d+$", ""))
end

function CoopMenu.new(env, opts)
  opts = opts or {}
  local self = setmetatable({
    env = env, version = env.version, settings = env.settings,
    screen = "coop", cursor = 1, scroll = 0, clock = 0,
  }, CoopMenu)
  if opts.notice then self.notice = opts.notice end
  return self
end

function CoopMenu:notify(text) self.notice = text end

function CoopMenu:go(screen, cursor)
  if self.screen == "join" and screen ~= "join" and screen ~= "entry" then
    self.env.closeNearby()
  end
  self.screen = screen
  self.cursor, self.scroll = cursor or 1, 0
end

local function playerName(self)
  local name = self.settings.name
  if Protocol.name(name) then return name end
  return label(self.version):sub(1, 7)
end

-- ------------------------------------------------------------ rows

-- The rows of the current screen: { id, label, detail?, value?, row?,
-- enabled? }.  Rows without `row` are a list laid out on LIST_ROWS with
-- scrolling; `value` is a second line under the label.
function CoopMenu:items()
  local s, rows = self.screen, {}
  local function add(row) rows[#rows + 1] = row; return row end
  if s == "coop" then
    add({ id = "host", label = "HOST", row = 2 })
    add({ id = "join", label = "JOIN", row = 4 })
    local last = self.settings.last
    local r = 6
    if last then
      local what = last.kind == "host" and self:_lastCampaign() or nil
      if last.kind == "join" or what then
        add({ id = "last", label = "LAST SESSION", row = 6,
          value = last.kind == "host" and ("HOST " .. what.title)
            or ("JOIN " .. (last.title or hostOnly(last.address))) })
        r = 8
      end
    end
    add({ id = "logs", label = "LOGS", row = r })
    add({ id = "back", label = "BACK", row = r + 2 })
  elseif s == "logs" then
    add({ id = "share", label = "SHARE LOGS", detail = self.settings.shareLogs and "ON" or "OFF",
          row = 8 })
    if self.env.canOpenLogs then add({ id = "open", label = "OPEN FOLDER", row = 9 }) end
    add({ id = "back", label = "BACK", row = 10 })
  elseif s == "host" then
    for _, c in ipairs(self.campaigns or {}) do
      add({ id = "campaign", campaign = c, label = c.title:sub(1, 12),
            detail = #c.players > 0 and (#c.players .. "P") or nil })
    end
    add({ id = "new", label = "NEW CAMPAIGN" })
    add({ id = "back", label = "BACK" })
  elseif s == "card" then
    add({ id = "host", label = "HOST", row = 7 })
    add({ id = "rename", label = "RENAME", row = 8 })
    add({ id = "delete", label = "DELETE", row = 9 })
    add({ id = "back", label = "BACK", row = 10 })
  elseif s == "delete" or s == "stop" then
    add({ id = "yes", label = "YES", row = 8 })
    add({ id = "no", label = "NO", row = 10 })
  elseif s == "new" then
    add({ id = "title", label = "NAME", value = self.form.title, row = 2 })
    add({ id = "you", label = "YOUR NAME", value = self.form.you, row = 5 })
    add({ id = "go", label = "HOST", row = 8 })
    add({ id = "back", label = "BACK", row = 10 })
  elseif s == "hosting" then
    add({ id = "enter", label = "ENTER WORLD", row = 2 })
    local r = 4
    for i, a in ipairs(self:_hostAddresses()) do
      if i > 2 then break end
      add({ id = "address", address = a.text, label = a.text, row = r, value = a.note })
      r = r + 2
    end
    add({ id = "stop", label = "STOP", row = 10 })
  elseif s == "join" then
    local listener, why = self.env.nearby()
    self.nearbyError = not listener and why or nil
    local hosts = CoopMenu.oneEach(listener and listener:hosts() or {})
    for _, h in ipairs(hosts) do
      local fit = self:_fitFor(h.lobby)
      add({ id = "nearby", host = h, label = (h.lobby.title or "?"):sub(1, 12),
            detail = fit and label(fit) or ("NEEDS " .. label(h.lobby.game)):sub(1, 6) })
    end
    if #hosts == 0 then
      add({ id = "searching", label = listener and "SEARCHING..." or "NEARBY OFF",
            enabled = false })
    end
    add({ id = "address", label = "BY ADDRESS" })
    for _, a in ipairs(self.settings.recent) do
      add({ id = "recent", address = a, label = a:sub(1, 17) })
    end
    add({ id = "back", label = "BACK" })
  elseif s == "connecting" then
    local session = self.session
    local st = session and session.status
    if st == "dialling" or st == "waiting" then
      add({ id = "retry", label = "TRY NOW", row = 8 })
      add({ id = "cancel", label = "CANCEL", row = 10 })
    elseif st == "probed" then
      local you = session.lobby and session.lobby.you
      add({ id = "join", label = "JOIN AS " .. ((you and you.name) or self.joinName), row = 8 })
      if not (you and you.player) then add({ id = "name", label = "NEW NAME", row = 9 }) end
      add({ id = "cancel", label = "CANCEL", row = 10 })
    elseif st == "unreachable" then
      add({ id = "retry", label = "TRY AGAIN", row = 9 })
      add({ id = "back", label = "BACK", row = 10 })
    elseif st == "joining" then
      add({ id = "cancel", label = "CANCEL", row = 10 })
    else -- refused, ended, closed
      local other = st == "refused" and session.reason == "content_mismatch"
        and session.lobby and session.lobby.game ~= session.cartridge.game
        and self.env.ready(session.lobby.game) and session.lobby.game
      if other then add({ id = "switch", label = "USE " .. label(other), game = other, row = 9 }) end
      add({ id = "back", label = "BACK", row = 10 })
    end
  end
  return rows
end

function CoopMenu:_lastCampaign()
  local last = self.settings.last
  if not last or last.kind ~= "host" then return nil end
  return self.env.campaigns.get(last.campaign)
end

-- One row per hosted campaign: a host on this machine is heard on
-- 127.0.0.1 and on its LAN address; the LAN one is kept (it is the one
-- the host's own screen lists).
function CoopMenu.oneEach(hosts)
  local out, at = {}, {}
  for _, h in ipairs(hosts) do
    local key = tostring(h.lobby.campaign) .. "/" .. tostring(h.lobby.host)
    local i = at[key]
    if not i then
      out[#out + 1] = h
      at[key] = #out
    elseif Addresses.kind(out[i].address) == "here" then
      out[i] = h
    end
  end
  return out
end

-- the cartridge of this device that fits a host's lobby: the picked one, or
-- another imported game (Red with Blue is #9)
function CoopMenu:_fitFor(lobby)
  if not lobby or lobby.protocol ~= Protocol.VERSION then return nil end
  if lobby.game == self.version then return self.version end
  if self.env.ready(lobby.game) then return lobby.game end
  return nil
end

-- the addresses partners join at, VPN first, the one used last marked
function CoopMenu:_hostAddresses()
  if not self.addressList then
    self.addressList = Addresses.sort(self.env.addresses() or {})
  end
  local port = self.session and self.session.port or CoopMenu.DEFAULT_PORT
  local lastVia = self.campaign and self.campaign.via and hostOnly(self.campaign.via)
  local out = {}
  for _, a in ipairs(self.addressList) do
    local text = port == CoopMenu.DEFAULT_PORT and a.ip or (a.ip .. ":" .. port)
    local note = Addresses.LABELS[a.kind] or ""
    if lastVia == a.ip then note = note .. ", LAST USED" end
    out[#out + 1] = { text = text, note = note }
  end
  return out
end

local function selectable(row) return row.enabled ~= false end

local function move(self, delta)
  local rows = self:items()
  if #rows == 0 then return end
  for _ = 1, #rows do
    self.cursor = (self.cursor - 1 + delta) % #rows + 1
    if selectable(rows[self.cursor]) then break end
  end
end

-- the first selectable row at or after the cursor
local function settle(self)
  local rows = self:items()
  if #rows == 0 then return end
  self.cursor = math.max(1, math.min(self.cursor, #rows))
  for _ = 1, #rows do
    if selectable(rows[self.cursor]) then return end
    self.cursor = self.cursor % #rows + 1
  end
end

-- ------------------------------------------------------------ flows

function CoopMenu:_openHost()
  self.campaigns = self.env.campaigns.list(self.version)
  self:go("host")
end

function CoopMenu:_entry(purpose, prompt, kind, text, max)
  self.entry = {
    purpose = purpose, prompt = prompt, back = self.screen, backCursor = self.cursor,
    keypad = Keypad.new({ kind = kind, text = text, max = max }),
  }
  self.screen = "entry"
end

function CoopMenu:_entryDone(text)
  local e = self.entry
  self.entry = nil
  self.screen, self.cursor = e.back, e.backCursor
  local p = e.purpose
  if p == "title" then
    self.form.title = text
  elseif p == "you" then
    self.form.you = text
  elseif p == "rename" then
    local c = self.env.campaigns.rename(self.campaign.id, text)
    if c then self.campaign = c end
  elseif p == "address" then
    self:_dial(text, self.version)
  elseif p == "joinname" then
    self.joinName = text
  end
end

function CoopMenu:_startHost(campaign, name)
  local settings = self.settings
  settings.name = name
  settings.last = { kind = "host", campaign = campaign.id, version = self.version }
  settings:save()
  self.env.campaigns.touch(campaign.id)
  self.campaign = self.env.campaigns.get(campaign.id) or campaign
  self.addressList = nil
  self.session = self.env.host(self.campaign, name, self.version)
  self:go("hosting")
end

function CoopMenu:_dial(address, version, auto)
  address = tostring(address or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if address == "" then return end
  self.joinName = self.joinName or playerName(self)
  self.dialVersion = version
  self.autoJoin = auto
  self.session = self.env.dial(address, version, self.joinName)
  self:go("connecting")
end

function CoopMenu:_cancelSession()
  local s = self.session
  self.session = nil
  if s then s:leave(nil) end
end

function CoopMenu:_enter()
  local s = self.session
  if not s then return nil end
  local campaign
  if s.kind == "host" then
    campaign = { id = self.campaign.id, title = self.campaign.title }
  else
    local settings = self.settings
    settings.name = s.name
    settings:dialled(s.address)
    settings.last = { kind = "join", address = s.address, version = self.dialVersion,
                      title = s.lobby and s.lobby.title or nil }
    settings:save()
    campaign = { id = s.client.campaign, title = s.lobby and s.lobby.title or "CO-OP" }
  end
  self.entered = true
  return { kind = "coop_enter", version = s.cartridge.game, campaign = campaign }
end

-- ------------------------------------------------------------ input

function CoopMenu:press(action)
  if self.notice then
    if action == "a" or action == "b" or action == "start" then self.notice = nil end
    return nil
  end
  if self.screen == "entry" then
    local e = self.entry
    local result = e.keypad:press(action)
    if result == "done" then
      local text = e.keypad.text:gsub("^%s+", ""):gsub("%s+$", "")
      if text == "" then return nil end
      if e.keypad.kind == "name" and not Protocol.name(text) then return nil end
      self:_entryDone(text)
    elseif result == "cancel" then
      self.screen, self.cursor = e.back, e.backCursor
      self.entry = nil
    end
    return nil
  end
  if action == "up" then move(self, -1) return nil end
  if action == "down" then move(self, 1) return nil end
  if action ~= "a" and action ~= "start" and action ~= "b" then return nil end
  local s = self.screen
  local rows = self:items()
  local row = rows[self.cursor]
  local back = action == "b"
  if row and not selectable(row) and not back then return nil end
  local id = not back and row and row.id or "back"

  if s == "coop" then
    if id == "back" then return { kind = "coop_exit" } end
    if id == "host" then return self:_openHost() end
    if id == "join" then
      self.joinName = playerName(self)
      self:go("join")
      settle(self)
      return nil
    end
    if id == "logs" then return self:go("logs") end
    if id == "last" then return self:_last() end
  elseif s == "logs" then
    if id == "back" then return self:go("coop", self:_cursorOf("coop", "logs")) end
    if id == "share" then
      self.settings.shareLogs = not self.settings.shareLogs
      self.settings:save()
    elseif id == "open" then
      return { kind = "open_logs" }
    end
  elseif s == "host" then
    if id == "back" then return self:go("coop", 1) end
    if id == "new" then
      self.form = { title = label(self.version) .. " CO-OP", you = playerName(self) }
      return self:go("new")
    end
    if id == "campaign" then
      self.campaign = row.campaign
      return self:go("card")
    end
  elseif s == "new" then
    if id == "back" then return self:_openHost() end
    if id == "title" then
      return self:_entry("title", "CAMPAIGN NAME?", "name", self.form.title, CoopMenu.TITLE_MAX)
    end
    if id == "you" then
      return self:_entry("you", "YOUR NAME?", "name", self.form.you, 7)
    end
    if id == "go" then
      local c = self.env.campaigns.create({ title = self.form.title, game = self.version })
      return self:_startHost(c, self.form.you)
    end
  elseif s == "card" then
    if id == "back" then
      self:_openHost()
      for i, r in ipairs(self:items()) do
        if r.campaign and r.campaign.id == self.campaign.id then self.cursor = i end
      end
      return nil
    end
    if id == "host" then return self:_startHost(self.campaign, playerName(self)) end
    if id == "rename" then
      return self:_entry("rename", "CAMPAIGN NAME?", "name", self.campaign.title,
        CoopMenu.TITLE_MAX)
    end
    if id == "delete" then return self:go("delete", 2) end
  elseif s == "delete" then
    if id == "yes" then
      local backup = self.env.campaigns.delete(self.campaign.id)
      local last = self.settings.last
      if last and last.kind == "host" and last.campaign == self.campaign.id then
        self.settings.last = nil
        self.settings:save()
      end
      self.campaign = nil
      self:_openHost()
      self:notify(backup and ("Deleted. A backup is kept as " .. backup .. ".")
        or "The campaign could not be deleted.")
      return nil
    end
    return self:go("card", 3)
  elseif s == "hosting" then
    if id == "enter" then return self:_enter() end
    if id == "address" then
      self:notify("Copied " .. row.address .. ".")
      return { kind = "copy", text = row.address }
    end
    if id == "stop" or id == "back" then
      if self.session and self.session:partners() > 0 then return self:go("stop", 2) end
      self:_cancelSession()
      return self:go("coop", 1)
    end
  elseif s == "stop" then
    if id == "yes" then
      self:_cancelSession()
      self:go("coop", 1)
      self:notify("The session is closed.")
      return nil
    end
    return self:go("hosting", 3)
  elseif s == "join" then
    if id == "back" then return self:go("coop", 2) end
    if id == "address" then
      local start = self.settings.address or ""
      return self:_entry("address", "HOST ADDRESS?", "address", start, 40)
    end
    if id == "recent" then return self:_dial(row.address, self.version) end
    if id == "nearby" then
      local fit = self:_fitFor(row.host.lobby)
      if not fit then
        local lobby = row.host.lobby
        if lobby.protocol ~= Protocol.VERSION then
          return self:notify(CoopMenu.reasonText("protocol_mismatch"))
        end
        return self:notify(("%s plays %s. Import %s on the title screen to join."):format(
          lobby.host or "The host", label(lobby.game), label(lobby.game)))
      end
      return self:_dial(row.host.address, fit)
    end
  elseif s == "connecting" then
    local st = self.session and self.session.status
    if id == "retry" then
      self.session:retryNow()
    elseif id == "join" then
      local you = self.session.lobby and self.session.lobby.you
      self.session:join((you and you.player) and you.name or self.joinName)
    elseif id == "name" then
      return self:_entry("joinname", "YOUR NAME?", "name", self.joinName, 7)
    elseif id == "switch" then
      local address = self.session.address
      self:_cancelSession()
      return self:_dial(address, row.game)
    elseif id == "cancel" or id == "back" then
      if st ~= "unreachable" and st ~= "refused" then self:_cancelSession() end
      self.session = nil
      self:go("join")
      settle(self)
    end
  end
  return nil
end

function CoopMenu:_cursorOf(screen, id)
  local saved = self.screen
  self.screen = screen
  local index = 1
  for i, r in ipairs(self:items()) do if r.id == id then index = i end end
  self.screen = saved
  return index
end

-- LAST SESSION: host that campaign again, or dial the last host and join at
-- once when it knows this device (design A2.1: one press)
function CoopMenu:_last()
  local last = self.settings.last
  if last.kind == "host" then
    local c = self:_lastCampaign()
    if c then return self:_startHost(c, playerName(self)) end
    return nil
  end
  local version = self.env.ready(last.version) and last.version or self.version
  return self:_dial(last.address, version, true)
end

-- Typing on a text entry screen (a keyboard).
function CoopMenu:text(t)
  if self.screen == "entry" and not self.notice then self.entry.keypad:input(t) end
end

function CoopMenu:erase()
  if self.screen == "entry" and not self.notice then self.entry.keypad:erase() end
end

function CoopMenu:typing() return self.screen == "entry" and not self.notice end

-- leave a text entry without taking its text (a keyboard's Escape)
function CoopMenu:cancelEntry()
  local e = self.entry
  if self.screen ~= "entry" or not e then return end
  self.screen, self.cursor = e.back, e.backCursor
  self.entry = nil
end

-- One frame: the nearby list, the session's progress.  Returns a command.
function CoopMenu:update(dt)
  self.clock = self.clock + (dt or 0)
  if self.screen == "join" then
    local listener = self.env.nearby()
    if listener then listener:update() end
    settle(self)
  end
  local s = self.session
  if not s or self.entered then return nil end
  -- a partner joined: the card now knows the address they used
  if s.kind == "host" and s.rosterKey ~= self.seenRoster then
    self.seenRoster = s.rosterKey
    self.campaign = self.env.campaigns.get(self.campaign.id) or self.campaign
  end
  if s.kind == "join" and s.status == "probed" and self.autoJoin then
    self.autoJoin = false
    local you = s.lobby and s.lobby.you
    if you and you.player then s:join(you.name) end
  end
  if s.kind == "join" and s.status == "joined" then return self:_enter() end
  if s.kind == "host" and (s.status == "ended" or s.status == "closed") then
    self.session = nil
    self:go("coop", 1)
    self:notify("The session stopped.")
  end
  return nil
end

-- ------------------------------------------------------------ view

local function lines(view, text, col, row, maxRows, width)
  for i, line in ipairs(wrap(text, width or (CoopMenu.COLS - col - 1))) do
    if maxRows and i > maxRows then break end
    view.lines[#view.lines + 1] = { col = col, row = row + i - 1, text = line }
  end
end

-- The current screen in text cells: { title, lines = { {col,row,text} },
-- items = { {label,detail,value,row,index} }, cursor (an item index),
-- more (rows below the list), keypad = { rows, row, col, text } }.
function CoopMenu:view()
  local s = self.screen
  local v = { title = "", lines = {}, items = {}, cursor = self.cursor }
  if s == "entry" then
    local e = self.entry
    v.title = e.prompt
    v.keypad = { rows = e.keypad:rows(), row = e.keypad.row, col = e.keypad.col,
                 text = e.keypad.text, max = e.keypad.max }
    return v
  end
  local rows = self:items()
  local session = self.session
  if s == "coop" then
    v.title = "CO-OP " .. label(self.version)
  elseif s == "logs" then
    v.title = "SESSION LOGS"
    lines(v, "Shared logs go to the players of a session. They hold names and "
      .. "addresses: never post them.", 1, 2, 5)
  elseif s == "host" then
    v.title = "HOST " .. label(self.version)
  elseif s == "card" then
    local c = self.campaign
    v.title = c.title:sub(1, CoopMenu.COLS)
    v.lines[#v.lines + 1] = { col = 1, row = 2, text = "STARTED ON " .. label(c.game) }
    local names = {}
    for _, p in ipairs(c.players) do names[#names + 1] = p.name end
    lines(v, #names > 0 and ("PLAYERS " .. table.concat(names, ", ")) or "NO PLAYERS YET",
      1, 3, 2)
    v.lines[#v.lines + 1] = { col = 1, row = 5,
      text = c.hosted and ("HOSTED " .. os.date("!%Y-%m-%d", c.hosted)) or "NEVER HOSTED" }
  elseif s == "delete" then
    v.title = "DELETE"
    lines(v, ("Delete %s? Its last state is kept as a backup."):format(self.campaign.title),
      1, 2, 5)
  elseif s == "new" then
    v.title = "NEW CAMPAIGN"
  elseif s == "hosting" then
    v.title = "HOSTING " .. (self.campaign and self.campaign.title or ""):sub(1, 12)
    if session and session.listenError then
      lines(v, "Network port busy: only this device can join.", 1, 4, 2)
    elseif #self:_hostAddresses() == 0 then
      lines(v, "No network found: only this device can join.", 1, 4, 2)
    end
    local names = {}
    local mine = session and session.cartridge.game
    for _, p in ipairs(session and session:roster() or {}) do
      if p.connected then
        names[#names + 1] = p.name .. ((p.game and p.game ~= mine) and (" " .. label(p.game)) or "")
      end
    end
    lines(v, "IN: " .. table.concat(names, ", "), 1, 8, 2)
  elseif s == "stop" then
    v.title = "STOP"
    local n = session and session:partners() or 0
    lines(v, ("%d partner%s still in. Stop the session for everyone?"):format(
      n, n == 1 and " is" or "s are"), 1, 2, 5)
  elseif s == "join" then
    v.title = "JOIN " .. label(self.version)
  elseif s == "connecting" then
    v.title = "JOIN"
    self:_connectingLines(v)
  end
  -- rows: fixed ones where they say, a list on LIST_ROWS with scrolling
  local list = {}
  for i, r in ipairs(rows) do
    if r.row then
      v.items[#v.items + 1] = { label = r.label, detail = r.detail, value = r.value,
                                row = r.row, index = i, enabled = r.enabled }
    else
      list[#list + 1] = i
    end
  end
  if #list > 0 then
    local visible = #CoopMenu.LIST_ROWS
    local pos
    for k, i in ipairs(list) do if i == self.cursor then pos = k end end
    if pos then
      if pos <= self.scroll then self.scroll = pos - 1 end
      if pos > self.scroll + visible then self.scroll = pos - visible end
    end
    self.scroll = math.max(0, math.min(self.scroll, math.max(0, #list - visible)))
    for k = 1, visible do
      local i = list[self.scroll + k]
      if i then
        local r = rows[i]
        v.items[#v.items + 1] = { label = r.label, detail = r.detail, value = r.value,
                                  row = CoopMenu.LIST_ROWS[k], index = i, enabled = r.enabled }
      end
    end
    v.more = self.scroll + visible < #list
  end
  return v
end

function CoopMenu:_connectingLines(v)
  local session = self.session
  if not session then return end
  local st = session.status
  local add = function(row, text) v.lines[#v.lines + 1] = { col = 1, row = row, text = text } end
  local function steps(found, version, fits)
    add(4, "HOST FOUND     " .. found)
    add(5, "SAME VERSION   " .. version)
    add(6, "CARTRIDGE FITS " .. fits)
  end
  if st ~= "refused" or not session.lobby then add(2, hostOnly(session.address):sub(1, 18)) end
  if st == "dialling" or st == "waiting" then
    local left, nextIn = session:dialTimes()
    add(3, st == "waiting" and ("TRYING IN %dS"):format(math.ceil(nextIn)) or "CALLING...")
    steps("..", "..", "..")
    add(7, ("GIVES UP IN %d:%02d"):format(math.floor(left / 60), math.floor(left % 60)))
  elseif st == "unreachable" then
    add(3, "COULD NOT REACH IT")
    local tips = Addresses.checklist(Addresses.kind(session.address), CoopMenu.DEFAULT_PORT)
    local row = 4
    for _, tip in ipairs(tips) do
      for _, line in ipairs(wrap(tip, CoopMenu.COLS - 2)) do
        if row <= 8 then add(row, line) end
        row = row + 1
      end
    end
  elseif st == "probed" or st == "joining" then
    local lobby = session.lobby or {}
    add(3, (lobby.title or ""):sub(1, 18))
    steps("OK", "OK", "OK")
    if st == "joining" then add(8, "JOINING...") end
  elseif st == "refused" then
    local lobby = session.lobby
    local reason = session.reason
    if lobby then
      -- the steps one row up, so the reason has three rows
      add(2, "HOST FOUND     OK")
      add(3, "SAME VERSION   " .. (reason == "protocol_mismatch" and "NO" or "OK"))
      add(4, "CARTRIDGE FITS " .. (reason == "content_mismatch" and "NO"
        or (reason == "protocol_mismatch" and "--" or "OK")))
    end
    lines(v, CoopMenu.reasonText(reason, lobby, session.cartridge.game), 1, lobby and 6 or 4,
      lobby and 3 or 4)
  else -- ended or closed before the world
    lines(v, session.status == "ended" and "The host closed the session."
      or ("The link was lost (" .. tostring(session.reason or "closed") .. ")."), 1, 4, 4)
  end
end

return CoopMenu
