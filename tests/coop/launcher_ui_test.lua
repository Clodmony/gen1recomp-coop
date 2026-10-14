-- The launcher's pages (#38) and its German (#41), ROM-free: every screen
-- is laid out in English and German at a desktop, a small, a wide and a
-- phone-shaped size.  Each page keeps the credit line word for word, no
-- text runs past the page, every target can be reached by the arrows, and
-- in German no launcher string falls back to English.  The catalog check
-- fails on a launcher string with no German entry.
--   luajit tests/coop/launcher_ui_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Text = require("src.coop.launcher.Text")
local Ui = require("src.coop.launcher.Ui")
local Menu = require("src.coop.launcher.Menu")
local CoopMenu = require("src.coop.launcher.CoopMenu")
local Screens = require("src.coop.launcher.Screens")
local Protocol = require("src.coop.session.Protocol")
local strings = require("tools.launcher_strings")

-- the catalog -------------------------------------------------------------

do
  local de = Text.catalogs.de
  local keys = strings.keys()
  check(#keys > 150, "the launcher's strings are found in its source (" .. #keys .. ")")
  local missing, known = {}, {}
  for _, k in ipairs(keys) do
    known[k] = true
    if not de[k] then missing[#missing + 1] = k end
  end
  eq(table.concat(missing, " | "), "", "every launcher string has a German entry")
  local stale, directives = {}, {}
  for k, v in pairs(de) do
    if not known[k] then stale[#stale + 1] = k end
    local a, b = {}, {}
    for d in k:gmatch("%%[%d%.]*[sdf]") do a[#a + 1] = d end
    for d in v:gmatch("%%[%d%.]*[sdf]") do b[#b + 1] = d end
    if table.concat(a) ~= table.concat(b) then directives[#directives + 1] = k end
  end
  table.sort(stale)
  eq(table.concat(stale, " | "), "", "no German entry for a string the launcher no longer has")
  eq(table.concat(directives, " | "), "", "every German entry keeps the English one's directives")
  -- the check itself: a string with no German entry is caught
  Text.set("de")
  Text.missing = {}
  eq(Text.get("A launcher string nobody translated"), "A launcher string nobody translated",
    "a string with no German entry shows in English")
  check(Text.missing["A launcher string nobody translated"], "and is listed as missing")
  Text.missing = {}
  Text.set("en")
end

-- the wording list for the owner is made from the catalog, and complete
do
  local f = assert(io.open("docs/coop/german-wording.md", "r"))
  local doc = f:read("*a")
  f:close()
  local made = doc:match("<!%-%- made by: luajit tools/launcher_strings%.lua %-%-markdown %-%->\n(.-)<!%-%- end of the made part %-%->")
  eq(made, strings.markdown(), "docs/coop/german-wording.md lists the catalog as it is "
    .. "(luajit tools/launcher_strings.lua --markdown)")
  local missing = {}
  for _, k in ipairs(strings.keys()) do
    if not (made or ""):find("| " .. k:gsub("|", "\\|") .. " |", 1, true) then missing[#missing + 1] = k end
  end
  eq(table.concat(missing, " | "), "", "every launcher string is on the list")
end

-- the system's language ---------------------------------------------------

do
  local function env(t) return function(k) return t[k] end end
  eq(Text.systemLanguage(env({ LANG = "de_DE.UTF-8" })), "de", "a German locale starts in German")
  eq(Text.systemLanguage(env({ LANG = "de_CH.UTF-8" })), "de", "Swiss German too")
  eq(Text.systemLanguage(env({ LANG = "en_US.UTF-8" })), "en", "an English one in English")
  eq(Text.systemLanguage(env({ LANG = "fr_FR.UTF-8" })), "en", "any other in English")
  eq(Text.systemLanguage(env({ LC_ALL = "en_GB.UTF-8", LANG = "de_DE.UTF-8" })), "en",
    "LC_ALL wins over LANG")
  eq(Text.systemLanguage(env({ LANGUAGE = "de:en", LANG = "en_US.UTF-8" })), "de",
    "LANGUAGE's first entry counts")
  eq(Text.systemLanguage(env({ LC_ALL = "C", LANG = "de_DE.UTF-8" })), "de", "C is no language")
  eq(Text.systemLanguage(env({})), "en", "no locale at all: English")
end

-- the pieces --------------------------------------------------------------

do
  eq(Ui.width("ABC"), 18, "a glyph is 6 pixels wide")
  eq(Ui.width("ÄÖÜß"), 24, "an umlaut is one glyph")
  eq(Ui.width("→"), 12, "an arrow is two")
  eq(Ui.width("AB", 2), 24, "twice the size, twice the width")
  eq(table.concat(Ui.wrap("aaaa bbbb cccc", 60), "|"), "aaaa bbbb|cccc", "wrap by pixels")
  eq(table.concat(Ui.wrap("abcdefghijkl", 36), "|"), "abcdef|ghijkl", "a long word is split")
  eq(Ui.fit("ABCDEFGHIJ", 36), "ABCD..", "a cut ends in ..")
  local p = Ui.page(200, 100)
  p:hit(10, 10, 40, 20, "a")
  p:hit(60, 10, 40, 20, "b")
  p:hit(10, 50, 90, 20, "c")
  p:hit(150, 50, 40, 20, "d", nil, false)
  eq(Ui.neighbour(p, "a", "right").key, "b", "right reaches the target beside")
  eq(Ui.neighbour(p, "b", "down").key, "c", "down reaches the one below")
  eq(Ui.neighbour(p, "c", "up").key, "a", "up prefers the one in line")
  eq(Ui.neighbour(p, "c", "right"), nil, "a disabled target is skipped")
  eq(p:at(65, 15).key, "b", "a point finds its target")
end

-- every screen ------------------------------------------------------------

local function memoryFs()
  local files = {}
  local fs = { files = files }
  function fs.getInfo(name)
    if files[name] then return { type = "file" } end
    for k in pairs(files) do
      if k:sub(1, #name + 1) == name .. "/" then return { type = "directory" } end
    end
    return nil
  end
  function fs.read(name) return files[name] end
  function fs.write(name, text) files[name] = text return true end
  function fs.remove(name) files[name] = nil return true end
  function fs.createDirectory() return true end
  function fs.getDirectoryItems(dir)
    local out = {}
    for k in pairs(files) do
      local rest = k:sub(1, #dir + 1) == dir .. "/" and k:sub(#dir + 2)
      if rest and not rest:find("/") then out[#out + 1] = rest end
    end
    table.sort(out)
    return out
  end
  return fs
end

local Campaigns = require("src.coop.Campaigns")
Campaigns.fs = memoryFs()
Campaigns.now = function() return 1790000000 end
local CoopSettings = require("src.coop.launcher.CoopSettings")
local settings = CoopSettings.load(memoryFs())
settings.name = "NOVA"
settings.recent = { "192.168.1.99", "mybox.example:24681" }
local card = Campaigns.create({ title = "SUNDAY RUN", game = "red" })
Campaigns.record(card.id, { { id = "p0000000000000001", name = "NOVA", game = "red" },
                            { id = "p0000000000000002", name = "VALE", game = "red" } })
Campaigns.touch(card.id)
Campaigns.create({ title = "A VERY LONG NAME", game = "blue" })
settings.last = { kind = "host", campaign = card.id, version = "red" }

local ready = { red = true, blue = true, red_de = true }
local nearbyHosts = {
  { address = "192.168.1.42", lobby = { protocol = Protocol.VERSION, game = "red",
    title = "SUNDAY RUN", host = "NOVA", campaign = "c1", players = { { connected = true } } } },
  { address = "192.168.1.43", lobby = { protocol = Protocol.VERSION, game = "yellow",
    title = "PIKA PALS", host = "VALE", campaign = "c2", players = { { connected = true } } } },
}

local function env(version)
  return {
    version = version, settings = settings, campaigns = Campaigns,
    ready = function(v) return ready[v] == true end,
    addresses = function()
      return { { ip = "100.64.12.8", kind = "vpn" }, { ip = "192.168.1.42", kind = "home" } }
    end,
    nearby = function()
      return { hosts = function() return nearbyHosts end, update = function() end,
               close = function() end }
    end,
    closeNearby = function() end,
    host = function(campaign)
      return { kind = "host", status = "joined", port = 24680, cartridge = { game = "red" },
        host = { maxPlayers = 8 }, client = { player = "p0000000000000001" },
        roster = function() return {
          { id = "p0000000000000001", name = "NOVA", game = "red", connected = true },
          { id = "p0000000000000002", name = "VALE", game = "blue", connected = true } } end,
        partners = function() return 1 end, leave = function() end, campaign = campaign }
    end,
    dial = function() return nil end,
  }
end

-- the CONTROLS page's model (#4): a rebind, two pads, one claimed
local Controls = require("src.coop.launcher.Controls")
settings.seats = { false, { kind = "pad", guid = "guid-b", twin = 1, name = "Wireless Controller" } }
local function newControls()
  return Controls.new({
    bindings = function() return { a = { key = "k" } } end,
    saveBindings = function() end,
    settings = settings,
    pads = function()
      return { { kind = "pad", guid = "guid-a", twin = 1, name = "Pad A" },
               { kind = "pad", guid = "guid-b", twin = 1, name = "Wireless Controller" } }
    end,
  })
end

local GameOptions = require("src.coop.launcher.GameOptions")
local optionsFs = memoryFs()

local function newMenu()
  return Menu.new({
    ready = function(v) return ready[v] == true end,
    saveInfo = function(v)
      return v == "red" and { name = "NOVA", badges = 3, time = "12:34" } or nil
    end,
    coop = env, settings = settings, campaigns = Campaigns, canOpenLogs = true,
    controls = newControls(),
    gameOptions = GameOptions.new({ fs = optionsFs }),
  })
end

local function dialSession(status, extra)
  local s = { kind = "join", status = status, address = "192.168.1.42", cartridge = { game = "red" },
    dialTimes = function() return 42, 2 end, leave = function() end, retryNow = function() end }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end

-- each screen: a name and how to get there from a fresh menu
local SCREENS = {
  { "play", function() end },
  { "play, no ROM", function(m) m:select("yellow") end },
  { "solo", function(m) m:go("solo") end },
  { "campaigns", function(m) m:openTab("campaigns") end },
  { "controls", function(m) m:openTab("controls") end },
  { "controls, capturing a key", function(m)
    m:openTab("controls")
    m.controls:press(m:items()[5])
  end },
  { "controls, capturing a seat", function(m)
    m:openTab("controls")
    m.controls:press(m:items()[11])
  end },
  { "settings", function(m) m:openTab("settings") end },
  { "help", function(m) m:openTab("help") end },
  { "import", function(m)
    m:go("import", "yellow")
    m.path = "/home/someone/roms/a very long folder name/Pokemon Yellow.gb"
  end },
  { "importing", function(m)
    m:importStarted("yellow", "yellow.gb")
    m:importProgress(0.4, "Preparing")
  end },
  { "host", function(m) m:openCoop("red", nil, "host") end },
  { "new campaign", function(m)
    m:openCoop("red", nil, "host")
    m.coop.form = { title = "RED CO-OP", you = "NOVA" }
    m.coop:go("new", 3)
  end },
  { "text entry", function(m)
    m:openCoop("red", nil, "host")
    m.coop:_entry("title", Text.get("HOST NAME OR ADDRESS"), "address", "192.168.", 40)
  end },
  { "delete", function(m)
    m:openCoop("red", nil, "host")
    m.coop.campaign = card
    m.coop:go("delete", 1)
  end },
  { "deleted", function(m)
    m:openCoop("red", nil, "host")
    m.coop.deleted = { id = card.id, title = "SUNDAY RUN" }
  end },
  { "hosting", function(m)
    m:openCoop("red", nil, "host")
    m.coop:_startHost(card, "NOVA")
  end },
  { "stop", function(m)
    m:openCoop("red", nil, "host")
    m.coop:_startHost(card, "NOVA")
    m.coop:go("stop", 1)
  end },
  { "join", function(m) m:openCoop("red", nil, "join") end },
  { "join, nobody", function(m)
    m:openCoop("red", nil, "join")
    m.coop.env.nearby = function()
      return { hosts = function() return {} end, update = function() end }
    end
  end },
}
for _, c in ipairs({
  { "waiting" }, { "unreachable" },
  { "probed", { lobby = { title = "SUNDAY RUN", game = "red", you = { player = "p1", name = "NOVA" } } } },
  { "probed", { lobby = { title = "SUNDAY RUN", game = "red" } } },
  { "joining", { lobby = { title = "SUNDAY RUN", game = "red" } } },
  { "refused", { reason = "content_mismatch", lobby = { title = "SUNDAY RUN", game = "blue" } } },
  { "refused", { reason = "content_mismatch", lobby = { title = "KANTO", game = "red_de" } } },
  { "refused", { reason = "protocol_mismatch", lobby = { title = "KANTO", game = "red" } } },
  { "refused", { reason = "session_full" } },
  { "ended" }, { "closed", { reason = "timeout" } },
}) do
  SCREENS[#SCREENS + 1] = { "connecting " .. c[1] .. " " .. tostring(c[2] and (c[2].reason
      or (c[2].lobby.you and "known") or "new")), function(m)
    m:openCoop("red", nil, "join")
    m.coop.session = dialSession(c[1], c[2])
    m.coop:go("connecting")
  end }
end
SCREENS[#SCREENS + 1] = { "a message", function(m)
  m:notify(Text.get("Unknown ROM. This needs a clean US Pokemon Red, Blue or Yellow dump, or a German Rote, Blaue or Gelbe Edition (SHA-1 %s).",
    ("0123456789abcdef"):rep(2) .. "01234567"))
end }

local SIZES = { { 480, 400 }, { 1024, 768 }, { 960, 540 }, { 540, 960 } }
local credit = Menu.CREDIT:gsub("%s", "")

local problems = {}
local function problem(text) problems[#problems + 1] = text end

-- all targets reachable from the focus with the arrows
local function reachable(page, from)
  local seen, queue = { [from] = true }, { from }
  while #queue > 0 do
    local key = table.remove(queue, 1)
    for _, dir in ipairs({ "up", "down", "left", "right" }) do
      local n = Ui.neighbour(page, key, dir)
      if n and not seen[n.key] then
        seen[n.key] = true
        queue[#queue + 1] = n.key
      end
    end
  end
  return seen
end

local screensBuilt = 0
for _, lang in ipairs({ "en", "de" }) do
  Text.set(lang)
  Text.missing = {}
  for _, size in ipairs(SIZES) do
    for _, sc in ipairs(SCREENS) do
      local m = newMenu()
      sc[2](m)
      local ui = { scroll = 0 }
      local page = Screens.build(m, ui, { w = size[1], h = size[2], device = "keys" })
      screensBuilt = screensBuilt + 1
      local where = ("%s %dx%d %s"):format(lang, size[1], size[2], sc[1])
      local joined = table.concat(page:texts(), " "):gsub("%s", "")
      if not joined:find(credit, 1, true) then problem(where .. ": no credit line") end
      for _, n in ipairs(page.nodes) do
        if n.kind == "text" and n.x + Ui.width(n.text, n.scale) > page.w then
          problem(where .. ": past the edge: " .. n.text)
        end
        if n.kind == "text" and n.x < 0 then problem(where .. ": past the left edge: " .. n.text) end
      end
      if not ui.focus or not page:find(ui.focus) then
        if #page:targets() > 0 then problem(where .. ": no focus") end
      else
        local seen = reachable(page, ui.focus)
        for _, n in ipairs(page:targets()) do
          if n.enabled and not seen[n.key] then problem(where .. ": cannot reach " .. n.key) end
        end
      end
    end
  end
  if lang == "de" then
    local missing = {}
    for k in pairs(Text.missing) do missing[#missing + 1] = k end
    table.sort(missing)
    eq(table.concat(missing, " | "), "", "no screen falls back to English in German")
  end
end
Text.set("en")
check(screensBuilt == 2 * #SIZES * #SCREENS, "every screen was laid out (" .. screensBuilt .. ")")
eq(table.concat(problems, "\n"), "", "every page keeps the credit, fits and can be walked")

-- the credit stays English in German
do
  Text.set("de")
  local page = Screens.build(newMenu(), { scroll = 0 }, { w = 480, h = 400 })
  local joined = table.concat(page:texts(), " ")
  check(joined:find("SPIELEN", 1, true), "the German page is German")
  check(joined:gsub("%s", ""):find(credit, 1, true), "and the credit line is word for word")
  Text.set("en")
end

-- a long page scrolls to keep the focus in view
do
  local m = newMenu()
  m:openTab("help")
  local ui = { scroll = 0 }
  local page = Screens.build(m, ui, { w = 480, h = 400 })
  check(page.maxScroll > 0, "HELP is taller than a small launcher")
  ui.focus = "row:2"
  m.cursor = 2
  ui.cursor = 2
  ui.model = m
  page = Screens.build(m, ui, { w = 480, h = 400 })
  local f = page:find("row:2")
  check(f.y >= page.region.y and f.y + f.h <= page.region.y + page.region.h,
    "the focused target is scrolled into view")
end

T.finish()
