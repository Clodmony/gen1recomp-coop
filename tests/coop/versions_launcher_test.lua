-- Red and Blue in the launcher (#9, design A13.1 to A13.3), ROM-free: which
-- games play together on PLAY, a refusal named exactly (Yellow, another
-- language, an unverified dump of the pair), the cartridge of this device
-- that fits a nearby host (its own, or the other of the pair), the
-- "wild Pokémon from both versions" switch on NEW CAMPAIGN and on the
-- campaign's card, the Hosting screen saying which version it waits for,
-- and a Blue cartridge hosting a Red campaign, whose file stays in Red's
-- folder.  Every screen is laid out at 480 x 400 with the credit line.
--   luajit tests/coop/versions_launcher_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq
local GameVersion = require("src.core.GameVersion")
local Protocol = require("src.coop.session.Protocol")
local Identity = require("src.coop.session.Identity")
local Session = require("src.coop.session.Session")
local Campaigns = require("src.coop.Campaigns")
local CampaignFile = require("src.coop.campaign.CampaignFile")
local CoopSettings = require("src.coop.launcher.CoopSettings")
local CoopMenu = require("src.coop.launcher.CoopMenu")
local Menu = require("src.coop.launcher.Menu")
local Screens = require("src.coop.launcher.Screens")
local Ui = require("src.coop.launcher.Ui")
require("src.coop.launcher.Text").set("en")

local SHA = {}
for _, id in ipairs({ "red", "blue", "yellow", "red_de" }) do SHA[id] = GameVersion.info(id).sha1 end

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

Campaigns.fs = memoryFs()
Campaigns.now = function() return 1790000000 end
-- the campaign files' calls (CampaignFile.loveFs's shape), in memory
local files = {}
local campaignFs = {
  read = function(path) return files[path] end,
  write = function(path, text) files[path] = text return true end,
  exists = function(path) return files[path] ~= nil end,
  remove = function(path) files[path] = nil return true end,
  rename = function(from, to) files[to], files[from] = files[from], nil return true end,
  append = function(path, text) files[path] = (files[path] or "") .. text return true end,
  mkdir = function() return true end,
}

local counter = 0
local function hex(n)
  counter = counter + 1
  return ("%0" .. n .. "x"):format(counter)
end

local function device(version, ready)
  local d = { fs = memoryFs(), ready = ready }
  d.settings = CoopSettings.load(d.fs)
  d.settings.name = "ASH"
  d.env = {
    version = version,
    ready = function(v) return d.ready[v] == true end,
    settings = d.settings, campaigns = Campaigns,
    addresses = function() return {} end,
    nearby = function()
      return { update = function() end, hosts = function() return d.nearbyHosts or {} end }
    end,
    closeNearby = function() end,
    splitReady = function() return false end,
    host = function(campaign, name, v)
      return Session.startHost({
        campaign = campaign, cartridge = { game = v, sha1 = SHA[v] }, name = name,
        identity = Identity.load(memoryStore(), hex), log = false, beacon = false,
        listen = false, hex = hex, campaignFs = campaignFs,
      })
    end,
    dial = function() error("no dialling here") end,
  }
  return d
end

local function ids(menu)
  local out = {}
  for _, r in ipairs(menu:items()) do out[#out + 1] = r.id end
  return table.concat(out, ",")
end
local function row(menu, id, campaign)
  for i, r in ipairs(menu:items()) do
    if r.id == id and (not campaign or (r.campaign and r.campaign.id == campaign)) then
      return r, i
    end
  end
  error("no row " .. id .. " (" .. ids(menu) .. ")")
end
local function choose(menu, id, campaign)
  local _, i = row(menu, id, campaign)
  menu.cursor = i
  return menu:press("a")
end

local function page(menu)
  local m = Menu.new({ ready = function() return true end })
  m.coop, m.screen = menu, "coop"
  return Screens.build(m, { scroll = 0 }, { w = 480, h = 400 })
end
local function fits(menu, label)
  local p = page(menu)
  local ok = true
  for _, n in ipairs(p.nodes) do
    if n.kind == "text" and n.x + Ui.width(n.text, n.scale) > p.w then
      ok = false
      print("  past the edge: " .. n.text)
    end
  end
  check(ok, "the " .. label .. " screen fits the launcher")
  local joined = table.concat(p:texts(), " "):gsub("%s", "")
  check(joined:find(Menu.CREDIT:gsub("%s", ""), 1, true) ~= nil,
    "the " .. label .. " screen shows the credit line")
  return table.concat(p:texts(), " ")
end

-- which games play together ---------------------------------------------------

eq(CoopMenu.togetherText("red"), "RED or BLUE", "Red plays with Red or Blue")
eq(CoopMenu.togetherText("blue_de"), "BLAU or ROT", "Blau with Blau or Rot")
eq(CoopMenu.togetherText("yellow"), "YELLOW", "Yellow with Yellow (G4)")
do
  local m = Menu.new({ ready = function() return true end })
  local text = table.concat(Screens.build(m, { scroll = 0 }, { w = 480, h = 400 }):texts(), " ")
  check(text:find("RED plays with RED or BLUE", 1, true) ~= nil,
    "PLAY says which games play together")
end

-- refusals named exactly ------------------------------------------------------

eq(CoopMenu.reasonText("content_mismatch", { game = "yellow" }, "red"),
  "The host plays YELLOW. This game is RED. YELLOW plays with YELLOW only.",
  "Yellow refuses Red, saying what it plays with")
eq(CoopMenu.reasonText("content_mismatch", { game = "red" }, "yellow"),
  "The host plays RED. This game is YELLOW. RED plays with RED or BLUE only.",
  "and Red refuses Yellow")
eq(CoopMenu.reasonText("content_mismatch", { game = "red" }, "blue"),
  "RED and BLUE play together only from verified dumps. One of the two ROMs is another dump.",
  "a refused pair is a dump that is not the verified one")
eq(CoopMenu.reasonText("content_mismatch", { game = "red_de" }, "blue"),
  "The host plays ROT in German, this game is BLUE in English. Both need the same language.",
  "another language first")

-- the cartridge that fits a nearby host ------------------------------------------

do
  local lobby = { protocol = Protocol.VERSION, game = "red", sha1 = SHA.red }
  local blue = CoopMenu.new(device("blue", { blue = true }).env, { start = "join" })
  eq(blue:_fitFor(lobby), "blue", "Blue fits a Red host as it is")
  local yellow = CoopMenu.new(device("yellow", { yellow = true, blue = true }).env,
    { start = "join" })
  eq(yellow:_fitFor(lobby), "blue", "a device on Yellow joins a Red host with its Blue")
  eq(yellow:_fitFor({ protocol = Protocol.VERSION, game = "red", sha1 = ("ab"):rep(20) }), nil,
    "a host on an unverified dump takes no other game")
  local d = device("yellow", { yellow = true })
  d.nearbyHosts = { { address = "10.0.0.9:24680", lobby = lobby } }
  local m = CoopMenu.new(d.env, { start = "join" })
  local text = fits(m, "join with a host this device has no cartridge for")
  check(text:find("Needs RED or BLUE", 1, true) ~= nil, "the card says which cartridges fit")
end

-- the switch on NEW CAMPAIGN ------------------------------------------------------

local redId
do
  local d = device("red", { red = true })
  local m = CoopMenu.new(d.env)
  choose(m, "new")
  eq(ids(m), "title,you,rival,mix,go", "Red's NEW CAMPAIGN has the switch")
  eq(m:items()[m.cursor].id, "go", "CREATE AND HOST is still preselected")
  eq(row(m, "mix").value, "THIS VERSION ONLY", "off by default")
  fits(m, "new campaign")
  choose(m, "mix")
  eq(row(m, "mix").value, "BOTH VERSIONS", "A turns it on")
  eq(m.screen, "new", "on the same form")
  choose(m, "go")
  eq(m.screen, "hosting", "the campaign is hosted")
  redId = m.campaign.id
  eq(Campaigns.get(redId).mix, true, "the card keeps the switch")
  check(m.session.host.mix, "the host plays with it")
  local d2 = m:details()
  eq(d2.mix and d2.mix.waiting, "blue", "the Hosting screen waits for a Blue player")
  local text = fits(m, "hosting with both versions")
  check(text:find("waiting for a BLUE player", 1, true) ~= nil, "and says so")
  m:press("b")
  local y = CoopMenu.new(device("yellow", { yellow = true }).env)
  choose(y, "new")
  eq(ids(y), "title,you,rival,go", "Yellow's has none")
end

-- the switch on the card, changeable later ---------------------------------------

do
  local m = CoopMenu.new(device("red", { red = true }).env)
  eq(row(m, "mix", redId).label, "BOTH VERSIONS: ON", "the card shows the switch")
  fits(m, "campaigns with the switch")
  choose(m, "mix", redId)
  eq(Campaigns.get(redId).mix, nil, "A turns it off on the card")
  eq(row(m, "mix", redId).label, "BOTH VERSIONS: OFF", "and the row says so")
  eq(m:items()[m.cursor].id, "mix", "the focus stays on it")
  choose(m, "mix", redId)
  eq(Campaigns.get(redId).mix, true, "and on again")
end

-- a Blue cartridge hosts a Red campaign (A13.2) ------------------------------------

do
  local m = CoopMenu.new(device("blue", { blue = true }).env)
  local r = row(m, "campaign", redId)
  eq(r.enabled, true, "HOST on Blue lists the Red campaign and can host it")
  choose(m, "campaign", redId)
  eq(m.screen, "hosting", "hosted")
  local s = m.session
  eq(s.cartridge.game, "blue", "with this device's Blue")
  eq(s.host.state.game, "red", "the campaign stays Red's")
  check(files[CampaignFile.path("red", redId)] ~= nil, "its file stays in Red's folder")
  check(files[CampaignFile.path("blue", redId)] == nil, "none in Blue's")
  eq(m:details().mix.waiting, "red", "and it waits for a Red player")
  fits(m, "hosting a Red campaign on Blue")
  m:press("b")
  local all = CoopMenu.new(device("yellow", { yellow = true }).env, { start = "campaigns" })
  eq(row(all, "campaign", redId).enabled, false, "a Yellow-only device cannot host it")
end

T.finish()
