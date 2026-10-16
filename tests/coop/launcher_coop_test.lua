-- The launcher's co-op screens (#12, design A2; laid out anew in #38),
-- ROM-free: two devices in one process, a host and a partner, each with its
-- own CoopMenu, settings and identity, over a loopback hub that stands in
-- for the network.  They host a new campaign, find it nearby, join it, see
-- each other, stop it; campaign cards are renamed, deleted to a backup and
-- restored; the last session comes back in one press; refusals are named
-- exactly; a host nobody reaches is retried every 3 s for a minute and then
-- explained.  Every screen is laid out (Screens.lua) and keeps the credit.
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
local Screens = require("src.coop.launcher.Screens")
local Ui = require("src.coop.launcher.Ui")
require("src.coop.launcher.Text").set("en")

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
    addresses = function() return opts.addresses or {} end,
    nearby = function()
      d.listening = true
      return { update = function() end, hosts = function() return d.nearbyHosts end }
    end,
    closeNearby = function() d.listening = false end,
    splitReady = function() return opts.split == true end,
    soloSaves = opts.saves and function(v) d.savesAsked = v; return opts.saves end or nil,
    host = function(campaign, playerName, version, start)
      return Session.startHost({
        campaign = campaign, cartridge = { game = version, sha1 = SHA[version] },
        name = playerName, identity = d.identity, log = false, beacon = false, start = start,
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
  d.menu = CoopMenu.new(d.env, { start = opts.start })
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

-- every screen is laid out in a 480 x 400 launcher: nothing past the
-- page's right edge, the credit line in the footer
local function fits(menu, label)
  local m = Menu.new({ ready = function() return true end })
  m.coop, m.screen = menu, "coop"
  local page = Screens.build(m, { scroll = 0 }, { w = 480, h = 400 })
  local ok = true
  for _, n in ipairs(page.nodes) do
    if n.kind == "text" and n.x + Ui.width(n.text, n.scale) > page.w then
      ok = false
      print("  past the edge: " .. n.text)
    end
  end
  check(ok, "the " .. label .. " screen fits the launcher")
  local joined = table.concat(page:texts(), " "):gsub("%s", "")
  check(joined:find(Menu.CREDIT:gsub("%s", ""), 1, true) ~= nil,
    "the " .. label .. " screen shows the credit line")
  return menu:details(), page
end

-- PLAY's co-op rows -----------------------------------------------------------

do
  local env = device("RED").env
  local m = Menu.new({ ready = function() return true end, coop = function() return env end })
  local function pick(id)
    for i, r in ipairs(m:items()) do if r.id == id then m.cursor = i end end
    return m:press("a")
  end
  pick("host")
  eq(m.screen, "coop", "HOST A CAMPAIGN opens the co-op screens")
  eq(m.coop.screen, "host", "on this cartridge's campaigns")
  m:press("b")
  eq(m.screen, "play", "B returns to PLAY")
  eq(m:items()[m.cursor].id, "host", "on HOST A CAMPAIGN")
  pick("join")
  eq(m.coop.screen, "join", "JOIN A FRIEND opens Join")
  m:press("b")
  eq(m:items()[m.cursor].id, "join", "and B comes back to it")
  m:openTab("campaigns")
  eq(m.coop.screen, "campaigns", "the CAMPAIGNS tab lists the campaigns")
  check(m:isTop(), "as a tab's page")
  local plain = Menu.new({ ready = function() return true end })
  local rows = {}
  for _, r in ipairs(plain:items()) do
    if r.id == "host" or r.id == "join" then rows[#rows + 1] = tostring(r.enabled) end
  end
  eq(table.concat(rows, ","), "false,false", "no hosting or joining without co-op")
  check(m:openCoop("red", "You left the session."), "the launcher can open the co-op screens")
  eq(m:currentNotice(), "You left the session.", "with the reason on top")
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
  local Text = require("src.coop.launcher.Text")
  Text.set("de")
  check(Addresses.checklist("home", 24680, Text.get)[2]:find("Firewall des Hosts UDP 24680"),
    "the checklist in the launcher's language (#41)")
  Text.set("en")
end

-- host a new campaign, a partner finds it nearby and joins -------------------

local A = device("RED", { address = "192.168.1.20",
  addresses = { { ip = "192.168.1.20", kind = "home" }, { ip = "100.101.2.3", kind = "vpn" } } })
local B = device("BLUE", { ready = { red = true, blue = true }, version = "blue", start = "join" })
local campaignId

do
  local m = A.menu
  eq(m.screen, "host", "the co-op screens open on this cartridge's campaigns")
  eq(ids(m), "new", "none yet: NEW CAMPAIGN")
  fits(m, "campaigns")
  choose(m, "new")
  eq(m.screen, "new", "NEW CAMPAIGN asks for the campaign")
  eq(m:items()[m.cursor].id, "go", "CREATE AND HOST is preselected")
  eq(m.form.title, "RED CO-OP", "the name starts as the cartridge's")
  eq(m.form.you, "RED", "the player's name is the remembered one")
  fits(m, "new campaign")
  choose(m, "title")
  eq(m.screen, "entry", "CAMPAIGN NAME opens the text entry")
  fits(m, "text entry")
  for _ = 1, 30 do m:erase() end
  m:text("KANTO")
  m:press("start")
  eq(m.form.title, "KANTO", "the typed name is the campaign's")
  eq(m.screen, "new", "and the entry closes")
  -- the rival's name (#22, design A2.3, A4.5): asked in the game unless typed
  local rivalRow = cursorTo(m, "rival")
  eq(rivalRow and rivalRow.value, "ASK IN THE GAME", "the rival is asked in Oak's speech by default")
  choose(m, "rival")
  eq(m.screen, "entry", "RIVAL NAME opens the text entry")
  m:text("GARY")
  m:press("start")
  eq(m.form.rival, "GARY", "the typed name is the rival's")
  choose(m, "rival")
  for _ = 1, 10 do m:erase() end
  m:press("start")
  eq(m.screen, "new", "an empty rival's name closes the entry")
  eq(m.form.rival, nil, "and leaves him to Oak's speech")
  choose(m, "rival")
  m:text("GARY")
  m:press("start")
  fits(m, "new campaign with a rival")
  choose(m, "go")
  eq(m.screen, "hosting", "CREATE AND HOST starts hosting")
  eq(m:items()[m.cursor].id, "enter", "ENTER THE WORLD is preselected")
  local s = m.session
  check(s and s.kind == "host", "a hosting session runs")
  frames({ A })
  eq(s.status, "joined", "the host's own player is in")
  local c = Campaigns.list("red")[1]
  check(c and c.title == "KANTO" and c.game == "red", "the campaign card is saved")
  eq(c and c.rival, "GARY", "with the rival's name")
  eq(s.host and s.host.state.rival, "GARY", "the new campaign's rival is named (A4.5)")
  campaignId = c.id
  eq(A.settings.last.kind, "host", "the last session is this hosting")
  local d = fits(m, "hosting")
  local rows = m:items()
  eq(rows[1].value, "100.101.2.3", "the VPN address comes first")
  eq(rows[1].detail, "VPN", "labelled VPN")
  eq(rows[2].value, "192.168.1.20", "then the home network")
  eq(rows[2].detail, "HOME NETWORK", "labelled HOME NETWORK")
  eq(#d.players, 1, "one player in")
  eq(d.players[1].name, "RED", "the host")
  check(d.players[1].host, "marked as this device")
  eq(d.max, 8, "of the host's player limit")
  cursorTo(m, "address")
  local copy = m:press("a")
  check(copy and copy.kind == "copy" and copy.text == "100.101.2.3", "A copies the address")
  check(m.notice and m.notice:find("Copied"), "and says so")
  m:press("a")
end

do
  local m = B.menu
  eq(m.screen, "join", "JOIN lists nearby hosts, by address, recent")
  check(B.listening, "the Join screen listens for the LAN beacon")
  eq(ids(m), "address", "nobody nearby yet: BY ADDRESS")
  check(m:details().searching, "and it says it is searching")
  B.nearbyHosts = { { address = "192.168.1.20:24680", lobby = A.menu.session.host:lobby() } }
  frames({ B }, 1)
  eq(ids(m), "nearby,address", "the host appears nearby")
  local n = m:details().nearby[1]
  eq(n.title, "KANTO", "by its campaign")
  eq(n.fit, "red", "with the cartridge this device joins with")
  -- a host on the same machine is heard twice: on 127.0.0.1 and its LAN address
  B.nearbyHosts = { { address = "127.0.0.1:24680", lobby = A.menu.session.host:lobby() },
                    B.nearbyHosts[1] }
  frames({ B }, 1)
  eq(ids(m), "nearby,address", "one row per campaign")
  eq(m:items()[1].host.address, "192.168.1.20:24680", "on its LAN address")
  fits(m, "join")
  choose(m, "nearby")
  eq(m.screen, "connecting", "CHECK opens the connection check")
  check(not B.listening, "the beacon listener closes")
  frames({ A, B })
  local s = m.session
  eq(s.status, "probed", "the host answered the probe")
  eq(s.cartridge.game, "red", "the partner joins with its RED cartridge, not the BLUE pick")
  local d = fits(m, "connecting")
  eq(d.steps.found .. d.steps.protocol .. d.steps.fits, "okokok",
    "host found, same protocol, the cartridges fit")
  eq(ids(m), "cancel,name,how,join", "a new player: CANCEL, NEW NAME, HOW YOU START (#57), JOIN AS")
  eq(m:items()[m.cursor].id, "join", "JOIN AS is preselected")
  eq(m:items()[4].label, "JOIN AS BLUE", "under the remembered name")
  choose(m, "name")
  for _ = 1, 30 do m:erase() end
  m:text("ash")
  m:press("start")
  eq(m:items()[4].label, "JOIN AS ASH", "a new player names themself")
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
  local hd = A.menu:details()
  eq(#hd.players, 2, "the host sees the partner")
  eq(hd.players[2].name, "ASH", "by name")
  local card = Campaigns.get(campaignId)
  eq(#card.players, 2, "the card keeps both players")
  eq(card.via, "192.168.1.20:24680", "and the address the partner used")
  eq(A.menu:items()[2].detail, "HOME NETWORK · LAST USED", "the address the partner used is marked")
end

-- stopping with a partner in asks first and tells the partner ---------------

do
  local m = A.menu
  local guest = B.menu.session
  choose(m, "stop")
  eq(m.screen, "stop", "STOP HOSTING with a partner in asks first")
  eq(m:items()[m.cursor].id, "no", "CANCEL is preselected")
  eq(fits(m, "stop").partners, 1, "it says a partner is in")
  m:press("a")
  eq(m.screen, "hosting", "CANCEL keeps hosting")
  choose(m, "stop")
  local out = choose(m, "yes")
  eq(out and out.kind, "coop_exit", "CLOSE SESSION stops and leaves the co-op screens")
  eq(out and out.notice, "The session is closed.", "saying the session closed")
  check(m.session == nil and Session.current ~= m.session, "the session is gone")
  local result
  local t = 0
  guest.clock = function() return t end
  for _ = 1, 4 do result = guest:update(1 / 60, {}) or result end
  eq(guest.status, "ended", "the partner is told")
  eq(result, nil, "the partner's game first shows why over the world (#20, A11.11)")
  t = t + Session.END_SHOW
  result = guest:update(1 / 60, {})
  eq(result, "launcher", "then goes back to the launcher")
  local note = Session.takeReturn()
  eq(note and note.notice, "The host closed the session.", "with the host's reason")
  eq(Session.takeReturn(), nil, "the note is read once")
  B.inGame = false
end

-- the last session comes back in one press ----------------------------------

do
  local m = CoopMenu.new(A.env, { start = "last" })
  A.menu = m
  m:resume()
  eq(m.screen, "hosting", "LAST SESSION hosts the campaign again in one press")
  frames({ A })
  local bm = CoopMenu.new(B.env, { start = "last" })
  B.menu = bm
  bm:resume()
  frames({ A, B }, 6)
  eq(bm.session.status, "joined", "one press rejoins: the host knows this device")
  eq(A.menu.session.host:roster()[2].name, "ASH", "as the same player")
  eq(#A.menu.session.host:roster(), 2, "nobody new")
  B.menu.session:leave(nil)
  frames({ A, B })
  local out = A.menu:press("b")
  eq(out and out.kind, "coop_exit", "B on the hosting screen with nobody else in stops at once")
  eq(A.menu.session, nil, "and ends the session")
end

-- campaign cards: rename, delete to a backup, restore -------------------------

do
  local m = CoopMenu.new(A.env)
  A.menu = m
  eq(ids(m), "campaign,rename,delete,mix,new",
    "the campaign has a card: HOST, RENAME, DELETE, and Red's switch of both versions (#9)")
  local d = fits(m, "campaign cards")
  eq(#d.cards[1].players, 2, "with its players")
  -- a campaign's name has its 16 characters, not a player name's 10 (the
  -- integrated build's live run: Enter did nothing on an 11-character name)
  choose(m, "rename")
  for _ = 1, 30 do m:erase() end
  m:text("KANTO WITH BLUE")
  m:press("start")
  eq(m.screen, "host", "a 15-character campaign name finishes the entry")
  eq(Campaigns.get(campaignId).title, "KANTO WITH BLUE", "and renames the campaign")
  choose(m, "new")
  choose(m, "title")
  for _ = 1, 30 do m:erase() end
  m:text("SIXTEEN CHARS OK")
  m:press("start")
  eq(m.screen, "new", "NEW CAMPAIGN takes a 16-character name")
  eq(m.form.title, "SIXTEEN CHARS OK", "as the campaign's name")
  choose(m, "you")
  for _ = 1, 30 do m:erase() end
  m:text("TOOLONG")
  m:press("start")
  eq(m.form.you, "TOOLONG", "a trainer name of 7")
  m:press("b")
  eq(m.screen, "host", "B leaves NEW CAMPAIGN")
  choose(m, "rename")
  for _ = 1, 30 do m:erase() end
  m:text("JOHTO")
  m:press("start")
  eq(Campaigns.get(campaignId).title, "JOHTO", "RENAME renames the campaign")
  eq(m:details().cards[1].title, "JOHTO", "and the card shows it")
  eq(m:items()[m.cursor].id, "campaign", "the cursor is back on the card")
  choose(m, "delete")
  eq(m.screen, "delete", "DELETE asks again")
  eq(m:items()[m.cursor].id, "no", "CANCEL is preselected")
  fits(m, "delete")
  m:press("a")
  eq(m.screen, "host", "CANCEL keeps the campaign")
  choose(m, "delete")
  choose(m, "yes")
  eq(Campaigns.get(campaignId), nil, "DELETE AND KEEP BACKUP deletes it")
  check(hostFs.files["coop/campaigns/" .. campaignId .. ".json.bak"],
    "its last state is kept as a .bak")
  eq(ids(m), "restore,new", "the card is gone, RESTORE BACKUP is offered")
  eq(m:details().deleted.title, "JOHTO", "naming the deleted campaign")
  eq(A.settings.last, nil, "and the last session no longer points at it")
  fits(m, "deleted")
  choose(m, "restore")
  check(Campaigns.get(campaignId), "RESTORE BACKUP brings the card back")
  eq(hostFs.files["coop/campaigns/" .. campaignId .. ".json.bak"], nil, "and drops the backup")
  check(m.notice and m.notice:find("JOHTO"), "saying which one")
  m:press("a")
  eq(ids(m), "campaign,rename,delete,mix,new", "the card is listed again")
  -- every campaign on the CAMPAIGNS tab, this cartridge's on HOST (and its
  -- pair's, #9: tests/coop/versions_launcher_test.lua)
  local yellow = Campaigns.create({ title = "SEAFOAM", game = "yellow" })
  eq(#CoopMenu.new(A.env):details().cards, 1, "HOST lists this cartridge's campaigns")
  local all = CoopMenu.new(A.env, { start = "campaigns" })
  eq(#all:details().cards, 2, "CAMPAIGNS lists every campaign")
  for _, r in ipairs(all:items()) do
    if r.id == "campaign" and r.campaign.game == "yellow" then
      eq(r.enabled, false, "one whose cartridge is not imported cannot be hosted")
    end
  end
  Campaigns.delete(yellow.id)
end

-- refusals are named exactly; another cartridge that fits is offered ---------

do
  local m = A.menu
  choose(m, "campaign")
  eq(m.screen, "hosting", "HOST on a card hosts it")
  frames({ A })
  local bm = CoopMenu.new(B.env, { start = "join" })
  B.menu = bm
  -- the partner picked BLUE and types the address
  choose(bm, "address")
  eq(bm.screen, "entry", "BY ADDRESS opens the address entry")
  eq(bm.entry.keypad.text, "192.168.1.20:24680", "with the last address")
  for _ = 1, 40 do bm:erase() end
  bm:text("192.168.1.20")
  bm:press("start")
  eq(bm.screen, "connecting", "the address is dialled")
  frames({ A, B })
  eq(bm.session.status, "refused", "BLUE is refused by a RED host")
  local d = fits(bm, "refused")
  eq(d.steps.fits, "no", "the cartridge step fails")
  -- this test's dumps are not the verified ones: Red and Blue do not pair (#9)
  eq(d.reason, "RED and BLUE play together only from verified dumps. One of the two ROMs is another dump.",
    "the reason names both cartridges")
  eq(ids(bm), "back,switch", "the partner's RED is offered")
  eq(bm:items()[2].label, "USE RED", "USE RED")
  eq(bm:items()[bm.cursor].id, "switch", "and preselected")
  choose(bm, "switch")
  frames({ A, B })
  eq(bm.session.status, "probed", "with RED the host answers")
  eq(bm:items()[2].label, "JOIN AS ASH", "a device the host knows sees one JOIN AS")
  eq(ids(bm), "cancel,join", "and no NEW NAME")
  eq(bm:details().known, "ASH", "it says who this device is there")
  choose(bm, "cancel")
  eq(bm.screen, "join", "CANCEL goes back to Join")
  eq(CoopMenu.reasonText("protocol_mismatch"):find("another version") ~= nil, true,
    "another protocol is named")
  eq(CoopMenu.reasonText("session_full"), "The session is full.", "a full session too")
  eq(CoopMenu.reasonText("content_mismatch", { game = "red_de" }, "red"),
    "The host plays ROT in German, this game is RED in English. Both need the same language.",
    "another language is named as such (#25)")
  -- a nearby host of another protocol or a game this device lacks
  local old = A.menu.session.host:lobby()
  old.protocol = Protocol.VERSION - 1
  B.nearbyHosts = { { address = "192.168.1.20:24680", lobby = old } }
  frames({ B }, 1)
  eq(bm:details().nearby[1].fit, nil, "a host of another version does not fit")
  choose(bm, "nearby")
  check(bm.notice and bm.notice:find("another version"), "and says why")
  bm:press("a")
  local yellow = A.menu.session.host:lobby()
  yellow.game = "yellow"
  B.nearbyHosts = { { address = "10.0.0.9:24680", lobby = yellow } }
  frames({ B }, 1)
  eq(bm:details().nearby[1].fit, nil, "a YELLOW host needs YELLOW")
  fits(bm, "join with a host that needs another game")
  choose(bm, "nearby")
  check(bm.notice and bm.notice:find("Import YELLOW"), "the notice says what to import")
  bm:press("a")
  A.menu:press("b")
  frames({ A, B })
end

-- nobody answers: retries every 3 s for a minute, then a checklist ------------

do
  local bm = CoopMenu.new(B.env, { start = "join" })
  B.menu = bm
  choose(bm, "address")
  for _ = 1, 40 do bm:erase() end
  bm:text("192.168.1.77")
  bm:press("start")
  local s = bm.session
  frames({ B }, 2)
  eq(s.status, "waiting", "no answer: waiting for the next attempt")
  local d = fits(bm, "dialling")
  check(d.line:find("Trying again in [123] s"), "a countdown to the next attempt")
  check(d.countdown:find("^Gives up in 0:5%d$"), "and to the end of the minute")
  eq(ids(bm), "cancel,retry", "CANCEL, TRY NOW")
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
  d = fits(bm, "unreachable")
  check(d.line:find("within a minute"), "says so")
  check(table.concat(d.tips, " "):find("Wi%-Fi"), "with the home-network checklist")
  eq(ids(bm), "back,retry", "CANCEL, TRY AGAIN")
  -- the partner pressed Join first: the host starts while the dial retries
  choose(bm, "retry")
  eq(s.status, "dialling", "TRY AGAIN starts a new minute")
  local H = device("HOST2", { address = "192.168.1.77", version = "blue",
                               ready = { blue = true } })
  choose(H.menu, "new")
  choose(H.menu, "go")
  for _ = 1, 4 * 60 do
    frames({ H, B }, 1)
    if s.status == "probed" then break end
  end
  eq(s.status, "probed", "a host that starts later is found by the retries")
  H.menu.session:leave(nil)
  s:leave(nil)
  local vpn = CoopMenu.new(B.env, { start = "join" })
  vpn.session = Session.startDial({ address = "100.101.9.9", cartridge = { game = "red", sha1 = SHA.red },
    name = "ASH", identity = B.identity, log = false, clock = function() return clock end,
    dial = netDial })
  vpn.screen = "connecting"
  vpn.session.status, vpn.session.dialStarted = "unreachable", clock
  check(table.concat(vpn:details().tips, " "):find("VPN"), "a VPN address gets the VPN checklist")
  vpn.session:leave(nil)
end

-- the launcher's language and colours are remembered (#41, #38) ---------------

do
  local fs = memoryFs()
  local st = CoopSettings.load(fs)
  eq(st.language, nil, "no language yet: the system's")
  st.language, st.theme = "de", "dark"
  st:save()
  local back = CoopSettings.load(fs)
  eq(back.language, "de", "the language is remembered")
  eq(back.theme, "dark", "and the colours")
  fs.files[CoopSettings.FILE] = fs.files[CoopSettings.FILE]:gsub('"de"', '"fr"')
  eq(CoopSettings.load(fs).language, nil, "a language the launcher lacks is ignored")
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

-- split-screen (#11): two players on one device ------------------------------

do
  -- a device whose CONTROLS has a device for each of two players
  local H = device("RED", { split = true, address = "192.168.1.30" })
  local m = H.menu
  choose(m, "new")
  choose(m, "go")
  frames({ H })
  eq(m.screen, "hosting", "the two-player device hosts")
  eq(ids(m):match("stop.*$"), "stop,enter2,enter", "ENTER WITH 2 PLAYERS beside ENTER THE WORLD")
  eq(m:items()[m.cursor].id, "enter", "ENTER THE WORLD stays preselected")
  fits(m, "hosting with two players")
  -- player 2 names themself first (#22)
  local out = choose(m, "enter2")
  eq(out, nil, "ENTER WITH 2 PLAYERS asks player 2's name first")
  eq(m.screen, "entry", "in the text entry")
  eq(m.entry and m.entry.prompt, "PLAYER 2 NAME", "for PLAYER 2 NAME")
  fits(m, "player 2's name")
  m:text("LEAF")
  out = m:press("start")
  check(out and out.kind == "coop_enter" and out.split == true,
        "then the two enter, a second player on this device")
  eq(H.settings.name2, "LEAF", "player 2's name is remembered")
  local again = require("src.coop.launcher.CoopSettings").load(H.settings.fs)
  eq(again.name2, "LEAF", "on the device")
  local J = device("BLUE", { split = true, start = "join" })
  J.nearbyHosts = { { address = H.address .. ":24680", lobby = H.menu.session.host:lobby() } }
  frames({ J }, 1)
  choose(J.menu, "nearby")
  frames({ H, J })
  eq(J.menu.session.status, "probed", "a two-player device found the host")
  eq(ids(J.menu), "cancel,name,how,join2,join", "JOIN WITH 2 PLAYERS beside JOIN AS")
  fits(J.menu, "connecting with two players")
  choose(J.menu, "join2")
  eq(J.menu.screen, "entry", "JOIN WITH 2 PLAYERS asks player 2's name first")
  J.menu:text("KRIS")
  J.menu:press("start")
  frames({ H, J })
  check(J.command and J.command.kind == "coop_enter" and J.command.split == true,
        "JOIN WITH 2 PLAYERS enters with a second player on this device")
  -- a plain join on the same screen enters alone
  local K = device("GREEN", { split = true, start = "join" })
  K.nearbyHosts = J.nearbyHosts
  frames({ K }, 1)
  choose(K.menu, "nearby")
  frames({ H, K })
  choose(K.menu, "join")
  frames({ H, K })
  check(K.command and K.command.kind == "coop_enter" and K.command.split == nil,
        "JOIN AS enters alone")
end

-- how a new player starts (#57, design A2.3, A2.5, A4.1) -----------------------

do
  local SAVES = {
    { id = "slot1", name = "RED", badges = 3, dex = 20, time = "12:34", bringable = true },
    { id = "slot2", name = "NEW", badges = 0, dex = 0, time = "0:05", bringable = false },
  }
  local H = device("OAK", { address = "192.168.1.40", saves = SAVES })
  local m = H.menu
  choose(m, "new")
  local how = cursorTo(m, "how")
  eq(how.value, "THE OPENING", "a new campaign's player plays the opening by default")
  eq(ids(m), "title,you,rival,mix,how,go", "HOW YOU START sits under the names")
  choose(m, "how")
  eq(cursorTo(m, "how").value, "START IN PALLET", "A steps to START IN PALLET")
  eq(cursorTo(m, "starter").value, "BULBASAUR", "with a STARTER to pick")
  fits(m, "new campaign starting in Pallet Town")
  choose(m, "starter")
  eq(cursorTo(m, "starter").value, "CHARMANDER", "A steps through the three")
  choose(m, "starter")
  eq(cursorTo(m, "starter").value, "SQUIRTLE", "SQUIRTLE")
  choose(m, "how")
  eq(m.screen, "bring", "BRING A SAVE opens the device's solo saves")
  eq(H.savesAsked, "red", "of this game")
  eq(ids(m), "slot,slot", "one row a save")
  eq(m:items()[2].enabled, false, "a save still in the opening cannot be brought")
  fits(m, "bring a trainer")
  m:press("b")
  eq(m.screen, "new", "B goes back to the form")
  eq(cursorTo(m, "how").value, "THE OPENING", "and with no save picked, the opening stays")
  choose(m, "how")
  choose(m, "how")
  choose(m, "slot")
  eq(m.screen, "new", "a save picked goes back to the form")
  eq(cursorTo(m, "save").value, "RED", "naming it")
  fits(m, "new campaign bringing a save")
  choose(m, "go")
  frames({ H })
  local out = choose(m, "enter")
  check(out and out.kind == "coop_enter", "the host enters")
  eq(out.start and out.start.how, "save", "bringing the save")
  eq(out.start.slot, "slot1", "slot1")
  -- a host who starts in Pallet Town, on a card hosted later: no choice
  local again = device("OAK", { address = "192.168.1.41", saves = SAVES })
  choose(again.menu, "new")
  choose(again.menu, "how")
  choose(again.menu, "go")
  frames({ again })
  local hs = again.menu.session
  eq(hs.client.start, "pallet", "the host's hello says it starts in Pallet (#66)")
  check(not (hs.client:playerView(hs.client.player) or {}).opening,
        "so the host's own player is not in the opening (#66)")
  out = choose(again.menu, "enter")
  eq(out.start and out.start.how, "pallet", "START IN PALLET goes to the game")
  eq(out.start.starter, "BULBASAUR", "with the starter")
  -- a partner new to the campaign chooses on the connection check
  local P = device("ASH", { start = "join", saves = SAVES })
  P.nearbyHosts = { { address = H.address .. ":24680", lobby = H.menu.session.host:lobby() } }
  frames({ P }, 1)
  choose(P.menu, "nearby")
  frames({ H, P })
  eq(P.menu.session.status, "probed", "the partner found the host")
  eq(cursorTo(P.menu, "how").value, "THE OPENING", "a new player chooses how they start")
  choose(P.menu, "how")
  eq(cursorTo(P.menu, "starter").value, "BULBASAUR", "START IN PALLET with a starter")
  fits(P.menu, "connecting, starting in Pallet Town")
  choose(P.menu, "join")
  frames({ H, P })
  check(P.command and P.command.kind == "coop_enter", "the partner enters")
  eq(P.command.start and P.command.start.how, "pallet", "starting in Pallet Town")
  local pid = P.menu.session.client.player
  check(not (H.menu.session.client:playerView(pid) or {}).opening,
        "the host does not announce the partner in the opening (#66)")
  -- a returning player is asked nothing (A4.3)
  local R = device("ASH", { start = "join", saves = SAVES })
  R.identity = P.identity
  R.menu.env.dial = P.menu.env.dial
  R.nearbyHosts = P.nearbyHosts
  P.menu.session:leave()
  frames({ H, P })
  frames({ R }, 1)
  choose(R.menu, "nearby")
  frames({ H, R })
  eq(R.menu.session.status, "probed", "the returning partner found the host")
  eq(ids(R.menu), "cancel,join", "a player the host knows is asked nothing: they start from the campaign's world")
  -- Yellow has no start in Pallet Town (G28)
  local Y = device("OAK", { ready = { yellow = true }, version = "yellow", saves = SAVES })
  choose(Y.menu, "new")
  choose(Y.menu, "how")
  eq(Y.menu.screen, "bring", "in Yellow the opening is followed by BRING A SAVE")
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
