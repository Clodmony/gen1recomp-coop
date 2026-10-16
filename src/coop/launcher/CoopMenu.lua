-- The launcher's co-op screens (#12, design A2; laid out anew in #38) as a
-- model with no drawing and no love.*: the campaign cards (choose one to
-- host, new, rename, delete to a backup and restore it), the hosting lobby
-- (the addresses partners join at, the players in, ENTER THE WORLD, STOP
-- HOSTING), Join (nearby hosts from the LAN beacon, by address, recent
-- addresses) and the connection check (each step, retries with a
-- countdown, the exact reason for a refusal, a checklist when nobody
-- answered).
--
-- Screens.lua lays a screen out from items() and details(); the session,
-- campaigns and settings are reached through `env` (Launcher.lua passes the
-- real ones, tests their own):
--
--   env.version            the cartridge picked on PLAY
--   env.ready(v)           the game's ROM is imported here
--   env.settings           a CoopSettings
--   env.campaigns          Campaigns (list, create, rename, delete, restore,
--                          get, touch)
--   env.host(campaign, name, version) -> a hosting Session
--   env.dial(address, version, name)  -> a dialling Session
--   env.nearby()           -> a Beacon listener, or nil and why
--   env.closeNearby()
--   env.addresses()        -> { { ip, kind } }, this device's addresses
--   env.splitReady()       -> true when CONTROLS has a device for each of
--                          two players (split-screen, #11)
--
-- Actions: "up", "down", "left", "right", "a", "b", "start".  A press or
-- update() may return a command for the launcher:
--   { kind = "coop_enter", version = v, campaign = { id, title }, split = true? }
--   (split: a second player on this device joins once the game runs, #11)
--   { kind = "copy", text = "…" }
--   { kind = "coop_exit", notice = text? }   back to PLAY

local Addresses = require("src.coop.session.Addresses")
local Games = require("src.coop.launcher.Games")
local Keypad = require("src.coop.launcher.Keypad")
local Protocol = require("src.coop.session.Protocol")
local L = require("src.coop.launcher.Text").get

local CoopMenu = {}
CoopMenu.__index = CoopMenu

CoopMenu.TITLE_MAX = 16
CoopMenu.NAME_MAX = 7
CoopMenu.DEFAULT_PORT = 24680

local label = Games.label
CoopMenu.gameLabel = label

local function languageName(version)
  return Games.language(version) == "de" and L("German") or L("English")
end
CoopMenu.languageName = languageName

-- the sentence for a refusal (design A2.5: a mismatch is named exactly)
function CoopMenu.reasonText(reason, lobby, version)
  if reason == "content_mismatch" and lobby then
    if Games.language(lobby.game) ~= Games.language(version) then
      return L("The host plays %s in %s, this game is %s in %s. Both need the same language.",
        label(lobby.game), languageName(lobby.game), label(version), languageName(version))
    end
    if lobby.game ~= version then
      return L("The host plays %s. This game is %s.", label(lobby.game), label(version))
    end
    return L("The host's %s ROM is another dump than this one.", label(version))
  elseif reason == "protocol_mismatch" then
    return L("The host runs another version of this co-op game. Both need the same one.")
  elseif reason == "session_full" then
    return L("The session is full.")
  elseif reason == "shutting_down" then
    return L("The host is closing the session.")
  elseif reason == "flood" then
    return L("The host dropped this game: it sent too much at once.")
  end
  return L("The host turned this game away (%s).", tostring(reason))
end

local function hostOnly(address)
  return (tostring(address or ""):gsub(":%d+$", ""))
end

-- opts.start: the screen to open, "host" (the campaigns of this cartridge),
-- "campaigns" (every campaign), "join" or "last" (resume() follows)
function CoopMenu.new(env, opts)
  opts = opts or {}
  local start = opts.start or "host"
  local self = setmetatable({
    env = env, version = env.version, settings = env.settings,
    screen = "host", cursor = 1, clock = 0,
    root = start == "last" and "host" or start,
  }, CoopMenu)
  if opts.notice then self.notice = opts.notice end
  if start == "join" then
    self.joinName = self:_playerName()
    self:go("join")
  elseif start == "campaigns" then
    self:_openList("campaigns")
  elseif start ~= "last" then
    self:_openList("host")
  end
  return self
end

function CoopMenu:notify(text) self.notice = text end

function CoopMenu:go(screen, cursor)
  if self.screen == "join" and screen ~= "join" and screen ~= "entry" then
    self.env.closeNearby()
  end
  self.screen = screen
  self.cursor = cursor or 1
  if screen == "join" then self.env.nearby() end
end

-- leaving the co-op screens: the nearby listener stops (a session that
-- entered the world keeps running)
function CoopMenu:close()
  if self.screen == "join" or self.screen == "connecting" then self.env.closeNearby() end
  if self.session and not self.entered then self:_cancelSession() end
end

function CoopMenu:_playerName()
  local name = self.settings.name
  if Protocol.name(name) then return name end
  return label(self.version):sub(1, CoopMenu.NAME_MAX)
end

-- ------------------------------------------------------------ rows

-- The rows of the current screen: { id, label, detail?, value?, enabled? }.
-- Their order is the order the focus walks without a layout.
function CoopMenu:items()
  local s, rows = self.screen, {}
  local function add(row) rows[#rows + 1] = row; return row end
  if s == "host" or s == "campaigns" then
    -- each card: HOST (its cartridge imported here), RENAME, DELETE
    for _, c in ipairs(self.campaigns or {}) do
      add({ id = "campaign", campaign = c, label = L("HOST"), enabled = self.env.ready(c.game) })
      add({ id = "rename", campaign = c, label = L("RENAME") })
      add({ id = "delete", campaign = c, label = L("DELETE") })
    end
    if self.deleted then add({ id = "restore", label = L("RESTORE BACKUP") }) end
    add({ id = "new", label = L("NEW CAMPAIGN"), enabled = self.env.ready(self.version) })
  elseif s == "delete" then
    add({ id = "no", label = L("CANCEL") })
    add({ id = "yes", label = L("DELETE AND KEEP BACKUP") })
  elseif s == "stop" then
    add({ id = "no", label = L("CANCEL") })
    add({ id = "yes", label = L("CLOSE SESSION") })
  elseif s == "new" then
    add({ id = "title", label = L("CAMPAIGN NAME"), value = self.form.title })
    add({ id = "you", label = L("TRAINER NAME"), value = self.form.you })
    -- the rival's name, or asked in Oak's speech (#22, design A2.3, A4.5)
    add({ id = "rival", label = L("RIVAL NAME"), value = self.form.rival or L("ASK IN THE GAME") })
    add({ id = "go", label = L("CREATE AND HOST") })
  elseif s == "hosting" then
    for _, a in ipairs(self:_hostAddresses()) do
      add({ id = "address", address = a.text, label = L("COPY"), value = a.text, detail = a.note })
    end
    add({ id = "stop", label = L("STOP HOSTING") })
    if self:_splitReady() then add({ id = "enter2", label = L("ENTER WITH 2 PLAYERS") }) end
    add({ id = "enter", label = L("ENTER THE WORLD") })
  elseif s == "join" then
    local listener, why = self.env.nearby()
    self.nearbyError = not listener and why or nil
    for _, h in ipairs(CoopMenu.oneEach(listener and listener:hosts() or {})) do
      add({ id = "nearby", host = h, label = L("CHECK") })
    end
    add({ id = "address", label = L("BY ADDRESS") })
    for _, a in ipairs(self.settings.recent) do
      add({ id = "recent", address = a, label = a })
    end
  elseif s == "connecting" then
    local session = self.session
    local st = session and session.status
    if st == "dialling" or st == "waiting" then
      add({ id = "cancel", label = L("CANCEL") })
      add({ id = "retry", label = L("TRY NOW") })
    elseif st == "probed" then
      local you = session.lobby and session.lobby.you
      add({ id = "cancel", label = L("CANCEL") })
      if not (you and you.player) then add({ id = "name", label = L("NEW NAME") }) end
      if self:_splitReady() then add({ id = "join2", label = L("JOIN WITH 2 PLAYERS") }) end
      add({ id = "join", label = L("JOIN AS %s", (you and you.name) or self.joinName) })
    elseif st == "unreachable" then
      add({ id = "back", label = L("CANCEL") })
      add({ id = "retry", label = L("TRY AGAIN") })
    elseif st == "joining" then
      add({ id = "cancel", label = L("CANCEL") })
    else -- refused, ended, closed
      add({ id = "back", label = L("BACK") })
      local other = self:_otherCartridge()
      if other then add({ id = "switch", label = L("USE %s", label(other)), game = other }) end
    end
  end
  return rows
end

-- after a refusal for the cartridge: another imported one that fits
function CoopMenu:_otherCartridge()
  local session = self.session
  if not session or session.status ~= "refused" or session.reason ~= "content_mismatch" then
    return nil
  end
  local game = session.lobby and session.lobby.game
  if game and game ~= session.cartridge.game and self.env.ready(game) then return game end
  return nil
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

local KIND_LABELS = { vpn = "VPN", home = "HOME NETWORK", public = "INTERNET",
                      here = "THIS DEVICE", name = "NAME" }

-- the addresses partners join at, VPN first (up to two), the one used last
-- marked
function CoopMenu:_hostAddresses()
  if not self.addressList then
    self.addressList = Addresses.sort(self.env.addresses() or {})
  end
  local port = self.session and self.session.port or CoopMenu.DEFAULT_PORT
  local lastVia = self.campaign and self.campaign.via and hostOnly(self.campaign.via)
  local out = {}
  for _, a in ipairs(self.addressList) do
    if #out == 2 then break end
    local text = port == CoopMenu.DEFAULT_PORT and a.ip or (a.ip .. ":" .. port)
    local note = L(KIND_LABELS[a.kind] or "")
    if lastVia == a.ip then note = L("%s · LAST USED", note) end
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
CoopMenu.settle = settle

-- ------------------------------------------------------------ flows

-- the campaign cards: of this cartridge ("host") or all ("campaigns")
function CoopMenu:_openList(screen, focusId)
  screen = screen or self.root
  if screen ~= "campaigns" then screen = "host" end
  self.campaigns = self.env.campaigns.list(screen == "host" and self.version or nil)
  self:go(screen)
  if focusId then
    for i, r in ipairs(self:items()) do
      if r.campaign and r.campaign.id == focusId then
        self.cursor = i
        break
      end
    end
  end
  settle(self)
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
  elseif p == "rival" then
    self.form.rival = text ~= "" and text or nil
  elseif p == "rename" then
    local c = self.env.campaigns.rename(self.campaign.id, text)
    if c then self.campaign = c end
    self:_openList(self.root, self.campaign.id)
  elseif p == "address" then
    self:_dial(text, self.version)
  elseif p == "joinname" then
    self.joinName = text
  elseif p == "name2" then
    -- player 2 names themself, then the two enter or join (#22, #11)
    self.settings.name2 = text
    self.settings:save()
    self.split = true
    if self.screen == "hosting" then return self:_enter() end
    local you = self.session and self.session.lobby and self.session.lobby.you
    if self.session then self.session:join((you and you.player) and you.name or self.joinName) end
  end
end

-- ENTER WITH 2 PLAYERS and JOIN WITH 2 PLAYERS: player 2 names themself
-- first, as any new player does (#22); the remembered name is offered
function CoopMenu:_name2()
  return self:_entry("name2", L("PLAYER 2 NAME"), "name", self.settings.name2 or "",
    CoopMenu.NAME_MAX)
end

function CoopMenu:_startHost(campaign, name)
  local settings = self.settings
  self.version = campaign.game or self.version
  settings.name = name
  settings.last = { kind = "host", campaign = campaign.id, version = self.version }
  settings:save()
  self.env.campaigns.touch(campaign.id)
  self.campaign = self.env.campaigns.get(campaign.id) or campaign
  self.addressList = nil
  self.deleted = nil
  local session, refused = self.env.host(self.campaign, name, self.version)
  if not session then
    -- the campaign's file cannot be read, or is of a newer build: it is
    -- left as it is and its backup named (#13, design A3.5)
    local why = refused and refused.why == "newer"
      and L("This campaign was saved by a newer build. Update to host it.")
      or L("This campaign's file cannot be read. It was left as it is.")
    if refused and refused.backup then why = why .. " " .. L("Its backup: %s", refused.backup) end
    return self:notify(why)
  end
  self.session = session
  self:go("hosting")
  self.cursor = #self:items()
end

function CoopMenu:_dial(address, version, auto)
  address = tostring(address or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if address == "" then return end
  self.joinName = self.joinName or self:_playerName()
  self.dialVersion = version
  self.autoJoin = auto
  self.session = self.env.dial(address, version, self.joinName)
  self:go("connecting")
  self.cursor = #self:items()
end

function CoopMenu:_cancelSession()
  local s = self.session
  self.session = nil
  if s then s:leave(nil) end
end

function CoopMenu:_enter()
  local s = self.session
  if not s then return nil end
  -- the player's world from the campaign comes right after the welcome (#13)
  if s.worldReady and not s:worldReady() then return nil end
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
  return { kind = "coop_enter", version = s.cartridge.game, campaign = campaign,
           split = self.split or nil }
end

-- two players on this device can start: a device claimed for each (#11)
function CoopMenu:_splitReady()
  return self.env.splitReady ~= nil and self.env.splitReady() == true
end

local function exit(notice) return { kind = "coop_exit", notice = notice } end

-- LAST SESSION on PLAY: host that campaign again, or dial the last host and
-- join at once when it knows this device (design A2.1: one press)
function CoopMenu:resume()
  local last = self.settings.last
  if not last then return exit() end
  if last.kind == "host" then
    local c = self:_lastCampaign()
    if c then return self:_startHost(c, self:_playerName()) end
    return exit()
  end
  self.root = "join"
  local version = self.env.ready(last.version) and last.version or self.version
  return self:_dial(last.address, version, true)
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
      -- an empty rival's name leaves him to Oak's speech (#22)
      if text == "" and e.purpose ~= "rival" then return nil end
      if text ~= "" and e.keypad.kind == "name" and not Protocol.name(text) then return nil end
      local command = self:_entryDone(text)
      if e.purpose == "name2" then return command end
    elseif result == "cancel" then
      self.screen, self.cursor = e.back, e.backCursor
      self.entry = nil
    end
    return nil
  end
  if action == "up" or action == "left" then move(self, -1) return nil end
  if action == "down" or action == "right" then move(self, 1) return nil end
  if action ~= "a" and action ~= "start" and action ~= "b" then return nil end
  local s = self.screen
  local rows = self:items()
  local row = rows[self.cursor]
  local back = action == "b"
  if not back and (not row or not selectable(row)) then return nil end
  local id = not back and row.id or "back"

  if s == "host" or s == "campaigns" then
    if id == "back" then return exit() end
    if id == "new" then
      self.form = { title = L("%s CO-OP", label(self.version)), you = self:_playerName() }
      return self:go("new", 4)
    end
    if id == "restore" then
      local restored = self.env.campaigns.restore(self.deleted.id)
      local title = self.deleted.title
      self.deleted = nil
      self:_openList(s, restored and restored.id)
      self:notify(restored and L("Restored %s.", title) or L("The backup could not be restored."))
      return nil
    end
    self.campaign = row.campaign
    if id == "campaign" then return self:_startHost(row.campaign, self:_playerName()) end
    if id == "rename" then
      return self:_entry("rename", L("CAMPAIGN NAME"), "name", row.campaign.title,
        CoopMenu.TITLE_MAX)
    end
    if id == "delete" then return self:go("delete", 1) end
  elseif s == "new" then
    if id == "back" then return self:_openList(self.root) end
    if id == "title" then
      return self:_entry("title", L("CAMPAIGN NAME"), "name", self.form.title, CoopMenu.TITLE_MAX)
    end
    if id == "you" then
      return self:_entry("you", L("TRAINER NAME"), "name", self.form.you, CoopMenu.NAME_MAX)
    end
    if id == "rival" then
      return self:_entry("rival", L("RIVAL NAME"), "name", self.form.rival or "", CoopMenu.NAME_MAX)
    end
    if id == "go" then
      local c = self.env.campaigns.create({ title = self.form.title, game = self.version,
                                            rival = self.form.rival })
      return self:_startHost(c, self.form.you)
    end
  elseif s == "delete" then
    if id == "yes" then
      local c = self.campaign
      local backup = self.env.campaigns.delete(c.id)
      local last = self.settings.last
      if last and last.kind == "host" and last.campaign == c.id then
        self.settings.last = nil
        self.settings:save()
      end
      self.campaign = nil
      self.deleted = backup and { id = c.id, title = c.title } or nil
      self:_openList(self.root)
      if not backup then self:notify(L("The campaign could not be deleted.")) end
      return nil
    end
    return self:_openList(self.root, self.campaign.id)
  elseif s == "hosting" then
    if id == "enter2" then return self:_name2() end
    self.split = nil
    if id == "enter" then return self:_enter() end
    if id == "address" then
      self:notify(L("Copied %s.", row.address))
      return { kind = "copy", text = row.address }
    end
    if id == "stop" or id == "back" then
      if self.session and self.session:partners() > 0 then return self:go("stop", 1) end
      self:_cancelSession()
      return exit()
    end
  elseif s == "stop" then
    if id == "yes" then
      self:_cancelSession()
      return exit(L("The session is closed."))
    end
    self:go("hosting")
    self.cursor = #self:items()
    return nil
  elseif s == "join" then
    if id == "back" then return exit() end
    if id == "address" then
      local start = self.settings.address or ""
      return self:_entry("address", L("HOST NAME OR ADDRESS"), "address", start, 40)
    end
    if id == "recent" then return self:_dial(row.address, self.version) end
    if id == "nearby" then
      local fit = self:_fitFor(row.host.lobby)
      if not fit then
        local lobby = row.host.lobby
        if lobby.protocol ~= Protocol.VERSION then
          return self:notify(CoopMenu.reasonText("protocol_mismatch"))
        end
        return self:notify(L("%s plays %s. Import %s on PLAY to join.",
          lobby.host or L("The host"), label(lobby.game), label(lobby.game)))
      end
      return self:_dial(row.host.address, fit)
    end
  elseif s == "connecting" then
    local st = self.session and self.session.status
    if id == "retry" then
      self.session:retryNow()
    elseif id == "join2" then
      return self:_name2()
    elseif id == "join" then
      self.split = nil
      local you = self.session.lobby and self.session.lobby.you
      self.session:join((you and you.player) and you.name or self.joinName)
    elseif id == "name" then
      return self:_entry("joinname", L("TRAINER NAME"), "name", self.joinName, CoopMenu.NAME_MAX)
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
    return exit(L("The session stopped."))
  end
  if self.screen == "connecting" then
    -- a new step of the check: its main action (the last row) is preselected
    if s.status ~= self.seenStatus then
      self.seenStatus = s.status
      self.cursor = #self:items()
    end
    settle(self)
  end
  return nil
end

-- ------------------------------------------------------------ details

-- What the current screen shows besides its rows, for Screens.lua:
--   host/campaigns: { cards = self.campaigns, deleted = { id, title }? }
--   delete:     { campaign }
--   hosting:    { campaign, players = { { name, game, host } }, max,
--                 warning?, game }
--   join:       { nearby = { { title, game, players, fit, needs } },
--                 searching, nearbyOff }
--   connecting: { address, title?, steps = { found, protocol, fits }
--                 ("ok", "no", "wait" or "skip"), status line?, reason?,
--                 tips?, countdown? }
--   stop:       { partners }
--   entry:      { prompt, keypad = { rows, row, col, text, max } }
function CoopMenu:details()
  local s = self.screen
  local d = {}
  local session = self.session
  if s == "host" or s == "campaigns" then
    d.cards = self.campaigns or {}
    d.deleted = self.deleted
  elseif s == "entry" then
    local e = self.entry
    d.prompt = e.prompt
    d.keypad = { rows = e.keypad:rows(), row = e.keypad.row, col = e.keypad.col,
                 text = e.keypad.text, max = e.keypad.max, kind = e.keypad.kind }
  elseif s == "hosting" then
    d.campaign = self.campaign
    d.game = session and session.cartridge.game or self.version
    d.max = session and session.host and session.host.maxPlayers or 8
    if session and session.listenError then
      d.warning = L("The network port is busy: only this device can join.")
    elseif #self:_hostAddresses() == 0 then
      d.warning = L("No network found: only this device can join.")
    end
    d.players = {}
    local me = session and session.client and session.client.player
    for _, p in ipairs(session and session:roster() or {}) do
      if p.connected then
        d.players[#d.players + 1] = { name = p.name, game = p.game, host = p.id == me }
      end
    end
  elseif s == "stop" then
    d.partners = session and session:partners() or 0
  elseif s == "delete" then
    d.campaign = self.campaign
  elseif s == "join" then
    local listener = self.env.nearby()
    d.nearbyOff = listener == nil
    d.nearby = {}
    for _, h in ipairs(CoopMenu.oneEach(listener and listener:hosts() or {})) do
      local lobby = h.lobby
      local count = 0
      for _, p in ipairs(lobby.players or {}) do
        if p.connected then count = count + 1 end
      end
      d.nearby[#d.nearby + 1] = { title = lobby.title or "?", game = lobby.game,
        host = lobby.host, players = count, fit = self:_fitFor(lobby) }
    end
    d.searching = listener ~= nil and #d.nearby == 0
  elseif s == "connecting" and session then
    self:_connectingDetails(d)
  end
  return d
end

function CoopMenu:_connectingDetails(d)
  local session = self.session
  local st = session.status
  d.address = hostOnly(session.address)
  d.status = st
  d.game = session.cartridge.game
  if st == "dialling" or st == "waiting" then
    local left, nextIn = session:dialTimes()
    d.line = st == "waiting" and L("No answer yet. Trying again in %d s.", math.ceil(nextIn))
      or L("Calling the host...")
    d.countdown = L("Gives up in %d:%02d", math.floor(left / 60), math.floor(left % 60))
    d.steps = { found = "wait", protocol = "wait", fits = "wait" }
  elseif st == "unreachable" then
    d.line = L("No host answered within a minute.")
    d.tips = Addresses.checklist(Addresses.kind(session.address), CoopMenu.DEFAULT_PORT, L)
    d.steps = { found = "no", protocol = "skip", fits = "skip" }
  elseif st == "probed" or st == "joining" or st == "joined" then
    local lobby = session.lobby or {}
    d.title = lobby.title
    d.steps = { found = "ok", protocol = "ok", fits = "ok" }
    if st == "joining" then d.line = L("Joining...") end
    local you = lobby.you
    if you and you.player then d.known = you.name end
  elseif st == "refused" then
    local lobby = session.lobby
    local reason = session.reason
    d.title = lobby and lobby.title or nil
    if lobby then
      d.steps = { found = "ok",
        protocol = reason == "protocol_mismatch" and "no" or "ok",
        fits = reason == "content_mismatch" and "no"
          or (reason == "protocol_mismatch" and "skip" or "ok") }
    else
      d.steps = { found = "ok", protocol = "skip", fits = "skip" }
    end
    d.reason = CoopMenu.reasonText(reason, lobby, session.cartridge.game)
  else -- ended or closed before the world
    d.reason = st == "ended" and L("The host closed the session.")
      or L("The link was lost (%s).", tostring(session.reason or "closed"))
  end
end

return CoopMenu
