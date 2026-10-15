-- German Red, Blue and Yellow (#25, #40), ROM-free: their own game ids,
-- caches and saves; manifests derived from the US ones; the German layouts
-- the extractor reads (names, trade nicknames, credits, metric Pokédex) on
-- a synthetic ROM; and the session refusing to mix languages.
--   luajit tests/coop/german_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq
local GameVersion = require("src.core.GameVersion")

local RED_DE_SHA1 = "87d523fe1a0c548db7c5477b451ddec1eb083c06"
local BLUE_DE_SHA1 = "20e72dc6f41493eee1fdd0cef54214e6c3389688"
local YELLOW_DE_SHA1 = "42f3714eec6eca25200d42461ff08d57c98f6d1d"

-- game ids ------------------------------------------------------------------
eq(GameVersion.forSha1(RED_DE_SHA1), "red_de", "the Rote Edition dump is red_de")
eq(GameVersion.forSha1(BLUE_DE_SHA1), "blue_de", "the Blaue Edition dump is blue_de")
eq(GameVersion.base("red_de"), "red", "red_de plays as Red")
eq(GameVersion.base("blue_de"), "blue", "blue_de plays as Blue")
eq(GameVersion.forSha1(YELLOW_DE_SHA1), "yellow_de", "the Gelbe Edition dump is yellow_de (#40)")
eq(GameVersion.base("yellow_de"), "yellow", "yellow_de plays as Yellow")
eq(GameVersion.language("yellow_de"), "de", "yellow_de is German")
eq(GameVersion.base("red"), "red", "a US game is its own base")
eq(GameVersion.language("red_de"), "de", "red_de is German")
eq(GameVersion.language("blue"), "en", "blue is English")
check(GameVersion.isGerman("blue_de") and not GameVersion.isGerman("red"),
  "isGerman tells them apart")
do
  local prefixes, suffixes = {}, {}
  for _, id in ipairs({ "red", "blue", "yellow", "red_de", "blue_de", "yellow_de" }) do
    local prefix, suffix = GameVersion.cachePrefix(id), GameVersion.saveSuffix(id)
    check(not prefixes[prefix], id .. " has a cache folder of its own")
    check(not suffixes[suffix], id .. " has save files of its own")
    prefixes[prefix], suffixes[suffix] = true, true
  end
end
do
  local previous = GameVersion.get()
  GameVersion.set("blue_de")
  check(GameVersion.isBlue(), "Blaue Edition runs Blue's version branches")
  GameVersion.set("red_de")
  check(not GameVersion.isBlue() and not GameVersion.isYellow(),
    "Rote Edition runs Red's")
  GameVersion.set("yellow_de")
  check(GameVersion.isYellow() and not GameVersion.isBlue(), "Gelbe Edition runs Yellow's")
  GameVersion.set(previous)
end
local inOrder = {}
for _, id in ipairs(GameVersion.ORDER) do inOrder[id] = true end
check(not inOrder.red_de and not inOrder.blue_de and not inOrder.yellow_de,
  "all three stay out of upstream's ORDER, so a Gen 1 mod token means the US games")
local Games = require("src.coop.launcher.Games")
eq(Games.label("yellow_de"), "GELB", "the launcher lists GELB")
eq(Games.language("yellow_de"), "de", "..as a German cartridge")

-- manifests -----------------------------------------------------------------
local Json = require("src.link.Json")
local function manifest(path)
  local f = assert(io.open(path, "rb"))
  local raw = f:read("*a")
  f:close()
  return assert(Json.decode(raw))
end
local CARTRIDGE_WORDS = {
  "DefaultNamesPlayerList", "DefaultNamesRivalList", "TradeMons",
  "CreditsOrder", "CreditsTextPointers", "CreditsMons",
}
for _, pair in ipairs({ { "red_de", "red" }, { "blue_de", "blue" }, { "yellow_de", "yellow" } }) do
  local id, base = pair[1], pair[2]
  local de = manifest(GameVersion.info(id).manifest)
  local us = manifest(GameVersion.info(base).manifest)
  eq(de.romSha1, GameVersion.info(id).sha1, id .. " manifest names its dump")
  eq(de.language, "de", id .. " manifest is marked German")
  -- the US Yellow surfing title's four pieces are one screen in German (below)
  local whole = { SurfingMinigame_BeachIntroTilemap = true, SurfingMinigame_TitleTilemap = true,
                  SurfingMinigame_ToSurfRadTilemap = true, SurfingMinigame_UseControlPadTilemap = true }
  local missing = {}
  for name in pairs(us.symbols) do
    if not de.symbols[name] and not (base == "yellow" and whole[name]) then missing[#missing + 1] = name end
  end
  eq(#missing, 0, id .. " manifest resolves every symbol of " .. base .. "'s")
  for _, name in ipairs(CARTRIDGE_WORDS) do
    check(de.symbols[name] ~= nil, id .. " manifest locates " .. name)
  end
  eq(#de.text.labels, #us.text.labels, id .. " has the same text labels")
  -- the menu words the engine draws itself (German.lua reads field.words)
  local words = de.field.words
  check(type(words) == "table" and #words > 50, id .. " manifest lists the cartridge's menu words")
  local placed = true
  for _, entry in ipairs(words or {}) do
    local name = type(entry) == "table" and entry[1] or entry
    placed = placed and de.symbols[name] ~= nil
  end
  check(placed, id .. " manifest locates every menu word label")
  check(us.field.words == nil, base .. "'s manifest has no such list")
  local listed = {}
  for _, entry in ipairs(words or {}) do listed[type(entry) == "table" and entry[1] or entry] = true end
  if base == "yellow" then
    -- Yellow's options screen and Bill's PC name their strings differently
    check(listed.AllOptionsText and listed["OptionsMenu_TextSpeed.Fast"] and listed.TradeCenterText,
      id .. " lists Yellow's own option and link menu labels")
    check(not listed.TextSpeedOptionText and not listed.NowSavingString,
      id .. " lists none of Red's labels Yellow has not")
    -- pokeyellow-de has no MewBaseStats label: the generator places Mew as
    -- the US manifest does
    local stats = de.symbols.BaseStats
    eq(de.symbols.MewBaseStats[1], stats[1], id .. " puts Mew's stats in BaseStats' bank")
    eq(de.symbols.MewBaseStats[2], stats[2] + 150 * 28, id .. " ..at the 151st entry")
    -- the German cartridge keeps the surfing title screen whole, and its
    -- nine tile under a label of its own
    check(de.symbols.SurfingMinigameIntroScreenTilemap ~= nil, id .. " names the whole surfing title screen")
    local pieces = 0
    for name in pairs(whole) do if de.symbols[name] then pieces = pieces + 1 end end
    eq(pieces, 0, id .. " lists none of the US title's four pieces")
    check(de.symbols.NineTile ~= nil, id .. " names the title's nine tile")
    eq(table.concat(de.field.title.copyPrefix, ","), "0,1,2,3,4", id .. " spells ©1995-2000 from five tiles")
    eq(de.field.title.nine.width, 16, id .. " ..and a two-tile year ending")
    eq(de.field.title.gameFreakX, 80, id .. " ..with GAME FREAK inc. at column 10")
    check(de.field.credits.theEnd == nil, id .. " draws the credits' end as US Yellow does (none)")
    eq(de.field.title.layout, "yellow_pikachu", id .. " keeps Yellow's title layout")
  else
    check(listed.TextSpeedOptionText and listed.NowSavingString, id .. " lists Red's option and save labels")
    eq(de.field.credits.theEnd.column, 7, id .. " ends its credits at column 7")
  end
  eq(de.charmap["192"], "Ä", id .. " charmap has the German letters")
  eq(de.charmap["190"], "ß", id .. " charmap has ß")
  -- no English words from pret's source stand in for the cartridge's
  check(de.field.presetNames == nil, id .. " carries no English name presets")
  check(de.field.credits.screens == nil, id .. " carries no English credits")
  local named = false
  for _, trade in ipairs(de.field.trades) do named = named or trade.nickname ~= nil end
  check(not named, id .. " carries no English trade nicknames")
end

-- the German layouts on a synthetic ROM ---------------------------------------
local RomExtractor = require("src.import.RomExtractor")

local function romWith(writes)
  local bytes = {}
  for i = 1, 0x8000 do bytes[i] = 0 end
  for address, values in pairs(writes) do
    for i, v in ipairs(values) do bytes[address + i] = v end
  end
  local chars = {}
  for i = 1, #bytes do chars[i] = string.char(bytes[i]) end
  return table.concat(chars)
end

local function text(s)
  local out = {}
  for c in s:gmatch(".") do out[#out + 1] = c:byte() - 65 + 0x80 end
  out[#out + 1] = 0x50
  return out
end
local function join(...)
  local out = {}
  for _, list in ipairs({ ... }) do
    for _, v in ipairs(list) do out[#out + 1] = v end
  end
  return out
end

local charmap = {}
for i = 0, 25 do charmap[tostring(0x80 + i)] = string.char(65 + i) end

local rom = romWith({
  [0x4000] = join(text("NAME"), text("ONE"), text("TWO"), text("SIX")),
  [0x4020] = join(text("NAME"), text("TEN"), text("SUN"), text("SKY")),
  -- TradeMons: give 1, get 2, dialogset 1, an 11-byte nickname
  [0x4040] = join({ 1, 2, 1 }, text("BOB"), { 0x50, 0x50, 0x50, 0x50, 0x50, 0x50, 0x50 }),
  -- CreditsOrder: two lines + CRED_TEXT_FADE_MON, copyright + CRED_TEXT, end
  [0x4100] = { 0, 1, 0xFF, 0xFB, 0xFC, 0xFA },
  [0x4200] = { 0x10, 0x42, 0x20, 0x42 },
  [0x4210] = join({ 0xFD }, text("HEADING")),
  [0x4220] = join({ 0xFA }, text("STAFF")),
  [0x4300] = { 2 },
  [0x4320] = { 0x64, 0x7F, 0x66, 0x7F, 0x68, 0x7F, 0x64, 0x50 }, -- E N D E
  -- a metric #DEX entry: kind, 19 dm, 1200 hg, TX_FAR
  [0x4400] = { 0x10, 0x44 },
  [0x4410] = join(text("KIND"), { 19, 0xB0, 0x04, 0x17, 0x00, 0x50, 0x2A }),
  -- menu words: two `next`-joined rows, and three consecutive strings
  [0x4500] = join({ 0x80 + 5, 0x80 + 6, 0x4E, 0x80 + 17, 0x80 + 13 }, { 0x50 }),
  [0x4520] = join(text("AT"), text("DF"), text("SP")),
})
local deManifest = {
  language = "de",
  charmap = charmap,
  constants = { speciesOrder = { "RHYDON", "KANGASKHAN" } },
  dexEntryLabels = { RHYDON = "_RhydonDexEntry" },
  symbols = {
    DefaultNamesPlayerList = { 1, 0x4000 }, DefaultNamesRivalList = { 1, 0x4020 },
    TradeMons = { 1, 0x4040 }, CreditsOrder = { 1, 0x4100 },
    CreditsTextPointers = { 1, 0x4200 }, CreditsMons = { 1, 0x4300 },
    PokedexEntryPointers = { 1, 0x4400 }, TheEndTextString = { 1, 0x4320 },
    BattleMenuText = { 1, 0x4500 }, StatModTextStrings = { 1, 0x4520 },
  },
}
charmap["78"] = "\n"
local x = RomExtractor.new(rom, deManifest)
local field = {
  trades = { { give = "RHYDON", get = "KANGASKHAN", dialogset = 1 } },
  credits = { mons = {}, theEnd = { letters = "THEND", column = 7 } },
  words = { "BattleMenuText", { "StatModTextStrings", 3 }, "NotInThisManifest" },
}
x:germanField(field)
eq(field.words.BattleMenuText, "FG\nRN", "a menu word label is read, its rows newline-joined")
eq(field.words.StatModTextStrings, "AT\nDF\nSP", "a (label, n) pair reads n consecutive strings")
check(field.words.NotInThisManifest == nil, "a label the manifest cannot place is left out")
eq(field.presetNames.customOption, "NAME", "the custom-name row is the cartridge's")
eq(table.concat(field.presetNames.player, ","), "ONE,TWO,SIX", "player presets read")
eq(table.concat(field.presetNames.rival, ","), "TEN,SUN,SKY", "rival presets read")
eq(field.trades[1].nickname, "BOB", "a trade nickname is read from TradeMons")
local screens = field.credits.screens
eq(#screens, 2, "two credits screens")
eq(screens[1].lines[1].text, "HEADING", "a credits line is read")
eq(screens[1].lines[1].column, 6, "at column 9 plus its signed offset")
eq(screens[1].lines[2].column, 3, "the second line's offset")
check(screens[1].fade and screens[1].mon == "KANGASKHAN",
  "CRED_TEXT_FADE_MON fades and takes the next CreditsMons species")
check(screens[2].copyright and not screens[2].fade and screens[2].mon == nil,
  "CRED_COPYRIGHT then CRED_TEXT")

eq(table.concat(field.credits.theEnd.pattern, ","), "2,-1,3,-1,4,-1,2",
  "THE END's letter columns are read from the cartridge")
eq(field.credits.theEnd.display, "E N D E", "and spelled for the text fallback")

local entry = x:dexEntry(1, "RHYDON")
eq(entry.kind, "KIND", "the #DEX kind")
eq(entry.heightM, 1.9, "German height in metres")
eq(entry.weightKg, 120, "German weight in kilograms")
eq(entry.heightFt * 12 + entry.heightIn, 75, "converted to 75 inches for the schema")
eq(entry.weight, 2646, "and to 264.6 lb")
eq(entry.text, "_RhydonDexEntry", "the TX_FAR label")

-- the US layout is unchanged
do
  local usRom = romWith({
    [0x4400] = { 0x10, 0x44 },
    [0x4410] = join(text("DRILL"), { 6, 3, 0x5A, 0x0A, 0x17, 0x00, 0x50, 0x2A }),
  })
  local us = RomExtractor.new(usRom, {
    charmap = charmap, dexEntryLabels = {},
    symbols = { PokedexEntryPointers = { 1, 0x4400 } },
  })
  local e = us:dexEntry(1, "RHYDON")
  eq(e.heightFt * 100 + e.heightIn, 603, "a US entry keeps feet and inches")
  eq(e.weight, 2650, "and tenths of a pound")
  check(e.heightM == nil, "and is not metric")
end

-- the session never mixes languages -----------------------------------------
local Transport = require("src.coop.session.Transport")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local US_RED_SHA1 = GameVersion.info("red").sha1

local function newHost(game, sha1)
  local clock, ids = 0, 0
  local host = Host.new({
    campaign = { id = "c0123456789abcdef", title = "CO-OP" },
    cartridge = { game = game, sha1 = sha1 },
    hostName = "HOST", build = "test",
    clock = function() return clock end,
    hex = function(n) ids = ids + 1 return ("%0" .. n .. "x"):format(ids) end,
  })
  return host, host:serve(Transport.loopback())
end
local devices = 0
local function seat(hub, name, game, sha1)
  devices = devices + 1
  return Client.new(hub:dial(), {
    name = name, game = game, sha1 = sha1, device = ("d%x"):format(devices), seat = 1,
    build = "test",
  })
end
local function pump(host, clients)
  for _ = 1, 3 do
    for _, c in ipairs(clients) do c:update() end
    host:update()
    for _, c in ipairs(clients) do c:update() end
  end
end

do
  local host, hub = newHost("red_de", RED_DE_SHA1)
  local rot = seat(hub, "ROT", "red_de", RED_DE_SHA1)
  rot:join()
  pump(host, { rot })
  eq(rot.status, "joined", "German Red joins a German Red host")
  local red = seat(hub, "RED", "red", US_RED_SHA1)
  red:probe()
  pump(host, { rot, red })
  eq(red.lobby and red.lobby.refused, "content_mismatch",
    "a probe from English Red finds the German host refused")
  red:join()
  pump(host, { rot, red })
  eq(red.reason, "content_mismatch", "English Red is refused by a German host")
  eq(#host.players, 1, "and nobody was created")
end
do
  local host, hub = newHost("red", US_RED_SHA1)
  local rot = seat(hub, "ROT", "red_de", RED_DE_SHA1)
  rot:join()
  pump(host, { rot })
  eq(rot.reason, "content_mismatch", "German Red is refused by an English host")
  check(not host:cartridgeFits("blue_de", BLUE_DE_SHA1),
    "a German cartridge never fits an English session")
end

T.finish()
