-- The launcher's co-op screens (#12, design A2), ROM-free: two devices in
-- one process, a host and a partner, each with its own CoopMenu, settings
-- and identity, over a loopback hub that stands in for the network.  They
-- host a new campaign, find it nearby, join it, see each other, stop it;
-- campaign cards are renamed and deleted to a backup; the last session
-- comes back in one press; refusals are named exactly; a host nobody
-- reaches is retried every 3 s for a minute and then explained.
--   luajit tests/coop/launcher_coop_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Transport = require("src.coop.session.Transport")
local Protocol = require("src.coop.session.Protocol")
local Identity = require("src.coop.session.Identity")
local Session = require("src.coop.session.Session")
local Addresses = require("src.coop.session.Addresses")
local Campaigns = require("src.coop.Campaigns")
local CoopSettings = require("src.coop.launcher.CoopSettings")
local CoopMenu = require("src.coop.launcher.CoopMenu")
local Keypad = require("src.coop.launcher.Keypad")
local Menu = require("src.coop.launcher.Menu")

local SHA = { red = ("ab"):rep(20), blue = ("cd"):rep(20), yellow = ("ef"):rep(20) }

-- a save folder in memory -------------------------------------------------

local function memoryFs()
  local files = {}
  local fs = { files = files }
  function fs.getInfo(name)
    if files[name] then return { type = "file" } end
    local prefix = name .. "/"
    for k in pairs(files) do
      if k:sub(1, #prefix) == prefix then return { type = "directory" } end
    end
    return nil
  end
  function fs.read(name) return files[name] end
  function fs.write(name, text) files[name] = text return true end
  function fs.remove(name) files[name] = nil return true end
  function fs.createDirectory() return true end
  function fs.getDirectoryItems(dir)
    local out, prefix = {}, dir .. "/"
    for k in pairs(files) do
      local rest = k:sub(1, #prefix) == prefix and k:sub(#prefix + 1)
      if rest and not rest:find("/") then out[#out + 1] = rest end
    end
    table.sort(out)
    return out
  end
  return fs
end

local function memoryStore()
  local text
  return { read = function() return text end, write = function(t) text = t end }
end

-- the "network": one loopback hub per address -----------------------------

local clock = 0
local net = {}        -- address -> hub of the host listening there
local counter = 0
local function hex(n)
  counter = counter + 1
  return ("%0" .. n .. "x"):format(counter)
end

local function netDial(address)
  local hub = net[(address:gsub(":%d+$", ""))]
  if hub and not hub.closed then return hub:dial() end
  local nobody = Transport.loopback()
  nobody:close()
  return nobody:dial()
end

-- a device: its settings, identity, campaigns folder and menu env
local hostFs = memoryFs()
Campaigns.fs = hostFs
Campaigns.now = function() return 1790000000 + math.floor(clock) end

local function device(name, opts)
  opts = opts or {}
  local d = { fs = memoryFs(), ready = opts.ready or { red = true } }
  d.settings = CoopSettings.load(d.fs)
  d.settings.name = name
  d.identity = Identity.load(memoryStore(), hex)
  d.nearbyHosts = {}
  d.listening = false
  d.address = opts.address -- where this device can be reached
  d.env = {
    version = opts.version or "red",
    ready = function(v) return d.ready[v] == true end,
    settings = d.settings,
    campaigns = Campaigns,
    canOpenLogs = true,
    addresses = function() return opts.addresses or {} end,
    nearby = function()
      d.listening = true
      return { update = function() end, hosts = function() return d.nearbyHosts end }
    end,
    closeNearby = function() d.listening = false end,
    host = function(campaign, playerName, version)
      return Session.startHost({
        campaign = campaign, cartridge = { game = version, sha1 = SHA[version] },
        name = playerName, identity = d.identity, log = false, beacon = false,
        clock = function() return clock end, hex = hex,
        listen = function()
          local hub = Transport.loopback()
          net[d.address] = hub
          return hub
        end,
        onRoster = function(roster) Campaigns.record(campaign.id, roster) end,
      })
    end,
    dial = function(address, version, playerName)
      return Session.startDial({
        address = address, cartridge = { game = version, sha1 = SHA[version] },
        name = playerName, identity = d.identity, log = false,
        clock = function() return clock end, dial = netDial,
      })
    end,
  }
  d.menu = CoopMenu.new(d.env)
  return d
end

-- every running session and both menus, a few frames
local sessions = {}
local function frames(devices, n)
  for _ = 1, n or 4 do
    clock = clock + 1 / 60
    for _, d in ipairs(devices) do
      local s = d.menu.session
      if s then s:update(1 / 60, d.inGame and {} or nil) end
      local command = d.menu:update(1 / 60)
      if command then d.command = command end
    end
  end
end

local function ids(menu)
  local out = {}
  for _, r in ipairs(menu:items()) do out[#out + 1] = r.id end
  return table.concat(out, ",")
end

local function cursorTo(menu, id)
  for i, r in ipairs(menu:items()) do
    if r.id == id then menu.cursor = i return r end
  end
  error("no row " .. id .. " on " .. menu.screen .. " (" .. ids(menu) .. ")")
end

local function choose(menu, id)
  cursorTo(menu, id)
  return menu:press("a")
end

-- every text of a view fits the 20x12 cells above the credit line
local function fits(menu, label)
  local v = menu:view()
  local ok = #v.title <= 20
  for _, l in ipairs(v.lines) do
    ok = ok and l.row >= 1 and l.row <= 10 and l.col + #l.text <= 20
  end
  for _, it in ipairs(v.items) do
    local width = 2 + #it.label + (it.detail and (#it.detail + 1) or 0)
    ok = ok and it.row >= 2 and it.row <= 10 and width <= 20
    if it.value then ok = ok and 3 + #it.value <= 20 and it.row + 1 <= 10 end
  end
  check(ok, "the " .. label .. " screen fits the Game Boy screen")
  return v
end

local function findLine(view, pattern)
  for _, l in ipairs(view.lines) do
    if l.text:find(pattern) then return l.text end
  end
  return nil
end

-- the game screen's CO-OP row ---------------------------------------------

do
  local env = device("RED").env
  local m = Menu.new({ ready = function() return true end, coop = function() return env end })
  m:press("a")
  eq(m.screen, "game", "an imported game opens its screen")
  local rows = {}
  for _, r in ipairs(m:items()) do rows[#rows + 1] = r.id end
  eq(table.concat(rows, ","), "new,coop,reimport,back", "the game screen has a CO-OP row")
  m.cursor = 2
  m:press("a")
  eq(m.screen, "coop", "CO-OP opens the co-op screens")
  eq(ids(m.coop), "host,join,logs,back", "the co-op screen: HOST, JOIN, LOGS, BACK")
  m.coop.cursor = 4
  m:press("a")
  eq(m.screen, "game", "BACK returns to the game screen")
  eq(m:items()[m.cursor].id, "coop", "on the CO-OP row")
  local plain = Menu.new({ ready = function() return true end })
  plain:press("a")
  rows = {}
  for _, r in ipairs(plain:items()) do rows[#rows + 1] = r.id end
  eq(table.concat(rows, ","), "new,reimport,back", "no CO-OP row without co-op")
  check(m:openCoop("red", "You left the session."), "the launcher can open the co-op screen")
  eq(m.coop.notice, "You left the session.", "with the reason on top")
end

-- the keypad --------------------------------------------------------------

do
  local k = Keypad.new({ kind = "address", text = "", max = 40 })
  eq(table.concat(k:rows()[1]), "012345678", "an address opens on the digits (number pad)")
  k:press("a")
  k:press("right")
  k:press("a")
  eq(k.text, "01", "A types the character under the cursor")
  k:input("92.168.1.20:24680")
  eq(k.text, "0192.168.1.20:24680", "a keyboard types into it")
  k:press("b")
  eq(k.text, "0192.168.1.20:2468", "B erases")
  local n = Keypad.new({ kind = "name", text = "ash", max = 7 })
  eq(n.text, "ASH", "a name is in the cartridge's capitals")
  n:input("KETCHUM")
  eq(n.text, "ASHKETC", "at most max characters")
  n:input("!/")
  eq(n.text, "ASHKETC", "characters outside the set are left out")
  local rows = n:rows()
  eq(table.concat(rows[#rows], ","), "SPACE,DEL,END", "the last row: SPACE, DEL, END")
  n.row, n.col = #rows, 3
  eq(n:press("a"), "done", "END finishes")
  eq(Keypad.new({}):press("b"), "cancel", "B on an empty field goes back")
  eq(n:press("start"), "done", "START finishes too")
end

-- addresses ---------------------------------------------------------------

do
  eq(Addresses.kind("100.101.2.3"), "vpn", "100.64.0.0/10 is a VPN address")
  eq(Addresses.kind("192.168.1.20:24680"), "home", "192.168/16 is the home network")
  eq(Addresses.kind("10.0.0.7"), "home", "10/8 too")
  eq(Addresses.kind("172.20.1.1"), "home", "and 172.16/12")
  eq(Addresses.kind("203.0.113.9"), "public", "anything else is public")
  eq(Addresses.kind("127.0.0.1"), "here", "127/8 is this device")
  eq(Addresses.kind("mypc.local"), "name", "a host name")
  eq(Addresses.kind("169.254.1.1"), nil, "a link-local address reaches nobody")
  local mine = Addresses.mine({
    route = function(probe) return probe == "192.0.2.1" and "192.168.1.20" or "100.101.2.3" end,
    names = function() return { "127.0.1.1", "192.168.1.20", "10.8.0.2" } end,
  })
  local list = {}
  for _, a in ipairs(mine) do list[#list + 1] = a.ip .. "=" .. a.kind end
  eq(table.concat(list, " "), "100.101.2.3=vpn 10.8.0.2=home 192.168.1.20=home",
    "this device's addresses: VPN first, then home, no loopback, no repeats")
  check(Addresses.checklist("vpn")[1]:find("VPN"), "VPN advice for a VPN address")
  check(Addresses.checklist("home")[1]:find("Wi%-Fi"), "same Wi-Fi for a home address")
  check(Addresses.checklist("home")[2]:find("firewall"), "and the firewall")
  check(Addresses.checklist("public")[1]:find("forward"), "port forwarding for a public one")
end

-- host a new campaign, a partner finds it nearby and joins -------------------

local A = device("RED", { address = "192.168.1.20",
  addresses = { { ip = "192.168.1.20", kind = "home" }, { ip = "100.101.2.3", kind = "vpn" } } })
local B = device("BLUE", { ready = { red = true, blue = true }, version = "blue" })
local campaignId

do
  local m = A.menu
  fits(m, "co-op")
  choose(m, "host")
  eq(m.screen, "host", "HOST lists this cartridge's campaigns")
  eq(ids(m), "new,back", "none yet: NEW CAMPAIGN, BACK")
  choose(m, "new")
  eq(m.screen, "new", "NEW CAMPAIGN asks for the campaign")
  eq(m.form.title, "RED CO-OP", "the name starts as the cartridge's")
  eq(m.form.you, "RED", "the player's name is the remembered one")
  fits(m, "new campaign")
  choose(m, "title")
  eq(m.screen, "entry", "NAME opens the text entry")
  fits(m, "text entry")
  for _ = 1, 30 do m:erase() end
  m:text("KANTO")
  m:press("start")
  eq(m.form.title, "KANTO", "the typed name is the campaign's")
  eq(m.screen, "new", "and the entry closes")
  choose(m, "go")
  eq(m.screen, "hosting", "HOST starts hosting")
  local s = m.session
  check(s and s.kind == "host", "a hosting session runs")
  frames({ A })
  eq(s.status, "joined", "the host's own player is in")
  local c = Campaigns.list("red")[1]
  check(c and c.title == "KANTO" and c.game == "red", "the campaign card is saved")
  campaignId = c.id
  eq(A.settings.last.kind, "host", "the last session is this hosting")
  local v = fits(m, "hosting")
  eq(v.items[2].label, "100.101.2.3", "the VPN address comes first")
  eq(v.items[2].value, "VPN", "labelled VPN")
  eq(v.items[3].label, "192.168.1.20", "then the home network")
  eq(v.items[3].value, "HOME", "labelled HOME")
  eq(findLine(v, "^IN:"), "IN: RED", "the players in: the host")
  cursorTo(m, "address")
  local copy = m:press("a")
  check(copy and copy.kind == "copy" and copy.text == "100.101.2.3", "A copies the address")
  check(m.notice and m.notice:find("Copied"), "and says so")
  m:press("a")
end

do
  local m = B.menu
  choose(m, "join")
  eq(m.screen, "join", "JOIN lists nearby hosts, by address, recent")
  check(B.listening, "the Join screen listens for the LAN beacon")
  eq(ids(m), "searching,address,back", "nobody nearby yet")
  eq(m:items()[m.cursor].id, "address", "the cursor skips the searching line")
  B.nearbyHosts = { { address = "192.168.1.20:24680", lobby = A.menu.session.host:lobby() } }
  frames({ B }, 1)
  eq(ids(m), "nearby,address,back", "the host appears nearby")
  local row = m:items()[1]
  eq(row.label, "KANTO", "by its campaign")
  eq(row.detail, "RED", "with the cartridge this device joins with")
  -- a host on the same machine is heard twice: on 127.0.0.1 and its LAN address
  B.nearbyHosts = { { address = "127.0.0.1:24680", lobby = A.menu.session.host:lobby() },
                    B.nearbyHosts[1] }
  frames({ B }, 1)
  eq(ids(m), "nearby,address,back", "one row per campaign")
  eq(m:items()[1].host.address, "192.168.1.20:24680", "on its LAN address")
  fits(m, "join")
  choose(m, "nearby")
  eq(m.screen, "connecting", "Join opens the Connecting sheet")
  check(not B.listening, "the beacon listener closes")
  frames({ A, B })
  local s = m.session
  eq(s.status, "probed", "the host answered the probe")
  eq(s.cartridge.game, "red", "the partner joins with its RED cartridge, not the BLUE pick")
  local v = fits(m, "connecting")
  eq(findLine(v, "HOST FOUND"), "HOST FOUND     OK", "host found")
  eq(findLine(v, "SAME VERSION"), "SAME VERSION   OK", "same version")
  eq(findLine(v, "CARTRIDGE"), "CARTRIDGE FITS OK", "the cartridges fit")
  eq(ids(m), "join,name,cancel", "a new player: JOIN AS, NEW NAME, CANCEL")
  eq(m:items()[1].label, "JOIN AS BLUE", "under the remembered name")
  choose(m, "name")
  for _ = 1, 30 do m:erase() end
  m:text("ash")
  m:press("start")
  eq(m:items()[1].label, "JOIN AS ASH", "a new player names themself")
  choose(m, "join")
  eq(s.status, "joining", "the hello goes out")
  frames({ A, B })
  eq(s.status, "joined", "the partner is in")
  check(B.command and B.command.kind == "coop_enter", "a joined partner enters the world")
  eq(B.command.campaign.id, campaignId, "the host's campaign")
  eq(B.command.campaign.title, "KANTO", "with its title")
  eq(B.command.version, "red", "on the cartridge that fits")
  eq(B.settings.last.kind, "join", "the partner's last session is this host")
  eq(B.settings.recent[1], "192.168.1.20:24680", "the address is in the recent list")
  eq(B.settings.name, "ASH", "the name is remembered")
  B.inGame = true
  frames({ A, B })
  local hv = A.menu:view()
  eq(findLine(hv, "^IN:"), "IN: RED, ASH", "the host sees the partner")
  local card = Campaigns.get(campaignId)
  eq(#card.players, 2, "the card keeps both players")
  eq(card.via, "192.168.1.20:24680", "and the address the partner used")
  eq(hv.items[3].value, "HOME, LAST USED", "the address the partner used is marked")
end

-- stopping with a partner in asks first and tells the partner ---------------

do
  local m = A.menu
  local guest = B.menu.session
  cursorTo(m, "stop")
  m:press("a")
  eq(m.screen, "stop", "STOP with a partner in asks first")
  eq(m:items()[m.cursor].id, "no", "NO is preselected")
  check(findLine(fits(m, "stop"), "partner is still"), "it says a partner is in")
  m:press("a")
  eq(m.screen, "hosting", "NO keeps hosting")
  cursorTo(m, "stop")
  m:press("a")
  choose(m, "yes")
  eq(m.screen, "coop", "YES stops and goes back to the co-op screen")
  check(m.session == nil and Session.current ~= m.session, "the session is gone")
  local result
  for _ = 1, 4 do result = guest:update(1 / 60, {}) or result end
  eq(guest.status, "ended", "the partner is told")
  eq(result, "launcher", "the partner's game goes back to the launcher")
  local note = Session.takeReturn()
  eq(note and note.notice, "The host closed the session.", "with the host's reason")
  eq(Session.takeReturn(), nil, "the note is read once")
  B.menu = CoopMenu.new(B.env, { notice = note.notice })
  B.inGame = false
end

-- the last session comes back in one press ----------------------------------

do
  local m = A.menu
  eq(m.notice, "The session is closed.", "the host is told the session closed")
  m:press("a")
  eq(ids(m), "host,join,last,logs,back", "the co-op screen offers the last session")
  eq(m:items()[3].value, "HOST KANTO", "hosting KANTO again")
  fits(m, "co-op")
  choose(m, "last")
  eq(m.screen, "hosting", "one press hosts it again")
  frames({ A })
  local bm = B.menu
  bm:press("a") -- the notice from before
  eq(bm:items()[3].value, "JOIN KANTO", "the partner's last session joins KANTO")
  choose(bm, "last")
  frames({ A, B }, 6)
  eq(bm.session.status, "joined", "one press rejoins: the host knows this device")
  eq(A.menu.session.host:roster()[2].name, "ASH", "as the same player")
  eq(#A.menu.session.host:roster(), 2, "nobody new")
  B.menu.session:leave(nil)
  frames({ A, B })
  A.menu:press("b")
  eq(A.menu.screen, "coop", "B on the hosting screen with nobody else in stops at once")
end

-- campaign cards: rename, delete to a backup ---------------------------------

do
  local m = A.menu
  choose(m, "host")
  eq(ids(m), "campaign,new,back", "the campaign has a card")
  eq(m:items()[1].detail, "2P", "with its player count")
  choose(m, "campaign")
  eq(m.screen, "card", "A opens the card")
  local v = fits(m, "card")
  eq(v.title, "KANTO", "the card's title")
  eq(findLine(v, "STARTED"), "STARTED ON RED", "the game it was started on")
  eq(findLine(v, "PLAYERS"), "PLAYERS RED, ASH", "its players")
  check(findLine(v, "^HOSTED "), "when it was hosted last")
  choose(m, "rename")
  for _ = 1, 30 do m:erase() end
  m:text("JOHTO")
  m:press("start")
  eq(Campaigns.get(campaignId).title, "JOHTO", "RENAME renames the campaign")
  eq(m:view().title, "JOHTO", "and the card shows it")
  choose(m, "delete")
  eq(m.screen, "delete", "DELETE asks again")
  eq(m:items()[m.cursor].id, "no", "NO is preselected")
  fits(m, "delete")
  m:press("a")
  eq(m.screen, "card", "NO keeps the campaign")
  choose(m, "delete")
  choose(m, "yes")
  eq(Campaigns.get(campaignId), nil, "YES deletes it")
  check(hostFs.files["coop/campaigns/" .. campaignId .. ".json.bak"],
    "its last state is kept as a .bak")
  check(m.notice and m.notice:find("%.bak"), "the notice names the backup")
  eq(ids(m), "new,back", "the card is gone")
  eq(A.settings.last, nil, "and the last session no longer points at it")
  hostFs.files["coop/campaigns/" .. campaignId .. ".json"] =
    hostFs.files["coop/campaigns/" .. campaignId .. ".json.bak"]
  check(Campaigns.get(campaignId), "renaming the .bak back restores the card")
end

-- refusals are named exactly; another cartridge that fits is offered ---------

do
  local m = A.menu
  m:press("a")
  m:press("b")
  choose(m, "host")
  choose(m, "campaign")
  choose(m, "host")
  frames({ A })
  local bm = CoopMenu.new(B.env)
  B.menu = bm
  -- the partner picked BLUE and types the address
  choose(bm, "join")
  choose(bm, "address")
  eq(bm.screen, "entry", "BY ADDRESS opens the address entry")
  eq(bm.entry.keypad.text, "192.168.1.20:24680", "with the last address")
  for _ = 1, 40 do bm:erase() end
  bm:text("192.168.1.20")
  bm:press("start")
  eq(bm.screen, "connecting", "the address is dialled")
  frames({ A, B })
  eq(bm.session.status, "refused", "BLUE is refused by a RED host")
  local v = fits(bm, "refused")
  eq(findLine(v, "CARTRIDGE"), "CARTRIDGE FITS NO", "the cartridge step fails")
  local said = {}
  for _, l in ipairs(v.lines) do if l.row >= 6 then said[#said + 1] = l.text end end
  eq(table.concat(said, " "), "The host plays RED. This game is BLUE.",
    "the reason names both cartridges")
  eq(ids(bm), "switch,back", "the partner's RED is offered")
  eq(bm:items()[1].label, "USE RED", "USE RED")
  choose(bm, "switch")
  frames({ A, B })
  eq(bm.session.status, "probed", "with RED the host answers")
  eq(bm:items()[1].label, "JOIN AS ASH", "a device the host knows sees one JOIN AS")
  eq(ids(bm), "join,cancel", "and no NEW NAME")
  choose(bm, "cancel")
  eq(bm.screen, "join", "CANCEL goes back to Join")
  eq(CoopMenu.reasonText("protocol_mismatch"):find("another version") ~= nil, true,
    "another protocol is named")
  eq(CoopMenu.reasonText("session_full"), "The session is full.", "a full session too")
  -- a nearby host of another protocol or a game this device lacks
  local old = A.menu.session.host:lobby()
  old.protocol = Protocol.VERSION - 1
  B.nearbyHosts = { { address = "192.168.1.20:24680", lobby = old } }
  frames({ B }, 1)
  eq(bm:items()[1].detail, "NEEDS ", "a host of another version does not fit")
  choose(bm, "nearby")
  check(bm.notice and bm.notice:find("another version"), "and says why")
  bm:press("a")
  local yellow = A.menu.session.host:lobby()
  yellow.game = "yellow"
  B.nearbyHosts = { { address = "10.0.0.9:24680", lobby = yellow } }
  frames({ B }, 1)
  eq(bm:items()[1].detail, "NEEDS ", "a YELLOW host needs YELLOW")
  choose(bm, "nearby")
  check(bm.notice and bm.notice:find("Import YELLOW"), "the notice says what to import")
  bm:press("a")
  A.menu:press("b")
  frames({ A, B })
end

-- nobody answers: retries every 3 s for a minute, then a checklist ------------

do
  local bm = CoopMenu.new(B.env)
  B.menu = bm
  choose(bm, "join")
  choose(bm, "address")
  for _ = 1, 40 do bm:erase() end
  bm:text("192.168.1.77")
  bm:press("start")
  local s = bm.session
  frames({ B }, 2)
  eq(s.status, "waiting", "no answer: waiting for the next attempt")
  local v = fits(bm, "dialling")
  check(findLine(v, "^TRYING IN [123]S$"), "a countdown to the next attempt")
  check(findLine(v, "^GIVES UP IN 0:5%d$"), "and to the end of the minute")
  eq(ids(bm), "retry,cancel", "TRY NOW, CANCEL")
  local attempts = s.attempts
  for _ = 1, 200 do frames({ B }, 1) end
  check(s.attempts > attempts, "a new attempt after 3 s")
  attempts = s.attempts
  choose(bm, "retry")
  eq(s.attempts, attempts + 1, "TRY NOW tries at once")
  for _ = 1, 60 * 61 do frames({ B }, 1) end
  eq(s.status, "unreachable", "after a minute: could not reach")
  check(s.attempts >= 18 and s.attempts <= 22, "about one attempt every 3 s ("
    .. s.attempts .. ")")
  v = fits(bm, "unreachable")
  check(findLine(v, "COULD NOT REACH"), "says so")
  check(findLine(v, "Wi%-Fi"), "with the home-network checklist")
  eq(ids(bm), "retry,back", "TRY AGAIN, BACK")
  -- the partner pressed Join first: the host starts while the dial retries
  choose(bm, "retry")
  eq(s.status, "dialling", "TRY AGAIN starts a new minute")
  local H = device("HOST2", { address = "192.168.1.77", version = "blue",
                               ready = { blue = true } })
  choose(H.menu, "host")
  choose(H.menu, "new")
  choose(H.menu, "go")
  for _ = 1, 4 * 60 do
    frames({ H, B }, 1)
    if s.status == "probed" then break end
  end
  eq(s.status, "probed", "a host that starts later is found by the retries")
  H.menu.session:leave(nil)
  s:leave(nil)
  local vpn = CoopMenu.new(B.env)
  vpn.session = Session.startDial({ address = "100.101.9.9", cartridge = { game = "red", sha1 = SHA.red },
    name = "ASH", identity = B.identity, log = false, clock = function() return clock end,
    dial = netDial })
  vpn.screen = "connecting"
  vpn.session.status, vpn.session.dialStarted = "unreachable", clock
  check(findLine(vpn:view(), "VPN"), "a VPN address gets the VPN checklist")
  vpn.session:leave(nil)
end

-- logs --------------------------------------------------------------------

do
  local m = CoopMenu.new(B.env)
  choose(m, "logs")
  eq(m.screen, "logs", "LOGS opens the troubleshooting screen")
  fits(m, "logs")
  eq(m:items()[1].detail, "ON", "sharing is on by default")
  choose(m, "share")
  eq(m:items()[1].detail, "OFF", "A switches it off")
  eq(CoopSettings.load(B.fs).shareLogs, false, "and it is remembered")
  eq(choose(m, "open").kind, "open_logs", "OPEN FOLDER opens the logs folder")
  choose(m, "back")
  eq(m.screen, "coop", "BACK")
  eq(m:items()[m.cursor].id, "logs", "on the LOGS row")
end

-- the cartridge picked for co-op is remembered --------------------------------

do
  local fs = memoryFs()
  local st = CoopSettings.load(fs)
  st:picked("blue")
  eq(CoopSettings.load(fs).pick, "blue", "the cartridge pick is remembered")
  fs.files[CoopSettings.FILE] = fs.files[CoopSettings.FILE]:gsub('"blue"', '"gold!"')
  eq(CoopSettings.load(fs).pick, nil, "a broken pick is ignored")
end

-- each campaign has its own save slot on each device --------------------------

do
  local slots = { red = { { id = "slot1" } } }
  local active = { red = "slot1" }
  local names = {}
  local saves = {
    listSlots = function(v) return slots[v] or {} end,
    activeSlot = function(v) return active[v] end,
    createSlot = function(v)
      local id = "slot" .. (#(slots[v] or {}) + 1)
      slots[v] = slots[v] or {}
      slots[v][#slots[v] + 1] = { id = id }
      return id
    end,
    renameSlot = function(_, id, name) names[id] = name end,
    setActiveSlot = function(v, id) active[v] = id end,
  }
  local st = CoopSettings.load(memoryFs())
  local slot = st:enterSlot(saves, "red", "c00000000000000aa", "KANTO")
  eq(slot, "slot2", "a campaign gets a new slot")
  eq(names.slot2, "KANTO", "named after the campaign")
  eq(active.red, "slot2", "made active for the game")
  eq(st:enterSlot(saves, "red", "c00000000000000aa", "KANTO"), "slot2",
    "the same campaign plays in the same slot again")
  eq(#slots.red, 2, "no new slot for it")
  local reloaded = CoopSettings.load(st.fs)
  eq(reloaded.slots.c00000000000000aa.slot, "slot2", "the slot is remembered")
  check(reloaded:restoreSlots(saves), "the launcher puts the solo slot back")
  eq(active.red, "slot1", "the slot that was active before")
  eq(CoopSettings.load(st.fs).restore.red, nil, "once")
  -- a device with no save slot before its first campaign
  slots.blue, active.blue = nil, nil
  local fresh = CoopSettings.load(memoryFs())
  eq(fresh:enterSlot(saves, "blue", "c00000000000000bb", "SEAFOAM"), "slot1",
    "the campaign takes the first slot")
  fresh:restoreSlots(saves)
  eq(active.blue, "slot2", "afterwards solo play gets a fresh slot of its own")
  eq(#slots.blue, 2, "next to the campaign's")
end

-- the return note ----------------------------------------------------------

do
  Session.writeReturn("You left the session.", "red")
  local note = Session.takeReturn()
  eq(note and note.notice, "You left the session.", "a fresh note is read")
  eq(note.version, "red", "with the game")
  love.filesystem.write(Session.RETURN_FILE,
    '{"notice":"old","version":"red","t":' .. (os.time() - 3600) .. '}')
  eq(Session.takeReturn(), nil, "a stale note is not shown")
end

T.finish()
