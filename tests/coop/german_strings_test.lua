-- The engine's lines in a German game (#25, D102), ROM-free: the catalog
-- src/coop/game/German.lua builds from the cartridge's words and text
-- labels on synthetic data, how the engine's arguments land in the
-- cartridge's slots, what a mod keeps, the German boxes, every engine
-- source covered, and the wording list in docs/coop/german-wording.md.
--   luajit tests/coop/german_strings_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq
local German = require("src.coop.game.German")
local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local Json = require("src.link.Json")

-- the cartridge's words, in English letters: the shapes matter, not the words
local function synthetic()
  return {
    field = {
      words = {
        BattleMenuText = "FGHT <PK><MN>\nITM  RN",
        SafariZoneBattleMenuText = "BLL×      BT\nSTN      RN",
        ["TwoOptionMenuStrings.YesNoMenu"] = "YS\nNO",
        SaveScreenInfoText = "PLYR\nBDGS          \nPOKéDEX        \nTM",
        EnemyText = "Enmy ",
        PlayersPCText = "PC OF ",
        YourTextString = "YR ",
        NameTextString = "NM?",
        PokedexSeenText = "SN",
        PokedexOwnText = "OWN",
        TypesIDNoOTText = "TP1/\nTP2/\n”·/\nOT/\n",
        TrainerInfo_NameMoneyTimeText = "NM/\nMNY/\nTM/",
        StatModTextStrings = "ATK\nDEF\nSPD\nSPC\nACC\nEVD",
        ["PrintStatsBox.StatsText"] = "AT\nDF\nSP\nSC",
        DiplomaCongrats = "one\ntwo\nthree\nfour",
      },
      presetNames = { customOption = "NW NM" },
    },
    text = {
      _GainedText = "{RAM:wNameBuffer} got\n{DONE}",
      _ExpPointsText = "{NUM:wExpAmountGained, 2, 4} XP!{PROMPT}",
      _GrewLevelText = "{RAM:wNameBuffer}\nreaches\vLevel {NUM:wCurEnemyLevel, 1, 3}!{DONE}",
      _PlayerBlackedOutText = "{PLAYER} has no\nmons left!\f{PLAYER} faints!{PROMPT}",
      _TrainerAboutToUseText = "{RAM:wTrainerName} sends\n{RAM:wEnemyMonNick} in!\fSwap your\nmon?{DONE}",
      _MonsStatsRoseText = "{USER}s\n{RAM:wStringBuffer}{DONE}",
      _RoseText = " goes up!{PROMPT}",
      _HurtByPoisonText = "Poison hurts\n{USER}!{PROMPT}",
      _GoText = "Go go! {DONE}",
      _DugAHoleText = "\ndigs in!{PROMPT}",
      _GotOnBicycleText1 = "{PLAYER} mounts{DONE}",
      _GotOnBicycleText2 = "the {RAM:wStringBuffer}!{PROMPT}",
      _CannotFlyHereText = "{RAM:wNameBuffer} cannot\nFLY here.{DONE}",
      _DexSeenOwnedText = "Seen: {NUM:wDexRatingNumMonsSeen, 1, 3}\nOwned: {NUM:wDexRatingNumMonsOwned, 1, 3}{DONE}",
      _WouldYouLikeToSaveText = "Save the\ngame?{DONE}",
      _UseNextMonText = "Next mon?{DONE}",
    },
    items = { POKE_BALL = { name = "PK BALL" }, BICYCLE = { name = "BIKE" } },
    moves = { CUT = { name = "CT" } },
    constants = { types = { NORMAL = 0, FIRE = 20, PSYCHIC_TYPE = 24 } },
    type_chart = {
      names = { "NRML", "FGHT", "FLY", "PSN", "FR", "WTR", "GRS", "ELC", "PSY",
                "ICE", "GRND", "RCK", "BRD", "BUG", "GHST", "DRGN" },
    },
  }
end

-- words -------------------------------------------------------------------
do
  local data = synthetic()
  local cat = German.catalog(data)
  eq(cat["FIGHT"], "FGHT", "FIGHT is the first word of the battle menu's first row")
  eq(cat["RUN"], "RN", "RUN the second word of its second row")
  eq(cat["BAIT"], "BT", "BAIT the Safari menu's second word")
  eq(cat["YES"], "YS", "YES from the two-option rows")
  eq(cat["NO"], "NO", "NO likewise")
  eq(cat["BADGES"], "BDGS", "a padded row is trimmed")
  eq(cat["Enemy %s"], "Enmy %1$s", "a prefix word keeps its space and takes the argument")
  eq(cat["%s's PC"], "PC OF %1$s", "the owner's PC puts the name after the cartridge's word")
  eq(cat["YOUR NAME?"], "YR NM?", "the naming title joins two labels")
  eq(cat["SEEN %3d  OWN %3d"], "SN %1$3d  OWN %2$3d", "the Pokédex footer joins words and directives")
  eq(cat["OT/%s"], "OT/%1$s", "OT/ with the trainer's name")
  eq(cat["TIME/  %d:%02d"], "TM/  %1$d:%2$02d", "the trainer card's time keeps its format")
  eq(cat["ATTACK"], "ATK", "the stat names in battle messages")
  eq(cat["status|ATTACK"], "AT", "and their short forms on the STATUS page, by context")
  eq(cat["POKé BALL"], "PK BALL", "the item's own name")
  eq(cat["CUT"], "CT", "a field move is the move's own name")
  eq(cat["NEW NAME"], "NW NM", "the naming screen's custom row is the preset's")
  eq(cat["POKéDEX."], " ", "the diploma's fifth piece draws blank when the cartridge says it in four rows")
  check(cat["TYPE/"] == nil and cat["WHICH TECHNIQUE?"] == nil,
    "a word the data lacks has no entry (the English stands)")
  eq(cat["CO-OP"], German.PROJECT["CO-OP"], "the project's wording fills the rest")
end

-- texts -------------------------------------------------------------------
do
  local data = synthetic()
  local cat = German.catalog(data)
  eq(cat["%s gained\n%d EXP. Points!"], "%1$s got\n%2$s XP!",
    "two labels joined, endings stripped, slots numbered in order")
  eq(cat["%s grew\nto level %d!"], "%1$s\nreaches\vLevel %2$s!", "the cartridge's own line breaks stay")
  eq(cat["%s is out of\nuseable POKéMON!"], "%1$s has no\nmons left!", "page 1 of a two-page label")
  eq(cat["%s blacked\nout!"], "%1$s faints!", "page 2, its {PLAYER} taking the argument")
  eq(cat["Will %s\nchange POKéMON?"], "Swap your\nmon?%1$.0s",
    "an argument the German has no slot for is consumed by a zero-width directive")
  eq(cat["%s's\n%s rose!"], "%1$ss\n%2$s goes up!", "args name the slot for each argument")
  eq(cat["%s's\nhurt by poison!"], "Poison hurts\n%1$s!", "a slot that moved in the German")
  eq(cat["Go! %s!"], "Go go! %1$s!", "a literal piece after the label")
  eq(cat["%s\ndug a hole!"], "%1$s\ndigs in!", "a literal piece before the label")
  eq(cat["%s got on\nthe BICYCLE!"], "%1$s mounts\nthe BIKE!", "fill puts the item's name into the RAM slot")
  eq(cat["{RAM:wNameBuffer} can't\nFLY here."], "{RAM:wNameBuffer} cannot\nFLY here.",
    "a slot the source spells the same stays for TextBox")
  eq(cat["POKéDEX   Seen:{NUM:wDexRatingNumMonsSeen, 1, 3}\n         Owned:{NUM:wDexRatingNumMonsOwned, 1, 3}"],
    "Seen: {NUM:wDexRatingNumMonsSeen, 1, 3}\nOwned: {NUM:wDexRatingNumMonsOwned, 1, 3}",
    "..as do the Hall of Fame's counters")
  check(cat["Use next POKéMON?"] == "Next mon?", "a plain label")
  check(cat["%s has no\nmoves left!"] == nil, "a label the cache lacks has no entry")

  -- and the engine renders them with its arguments
  Strings.load({ strings = cat })
  eq(Strings("%s gained\n%d EXP. Points!", "PIKA", 12), "PIKA got\n12 XP!", "Strings formats a numbered entry")
  eq(Strings("%s's\n%s rose!", "PIKA", Strings("ATTACK")), "PIKAs\nATK goes up!", "the stat name goes through the catalog too")
  eq(Strings("Will %s\nchange POKéMON?", "RED"), "Swap your\nmon?", "the unused argument prints nothing")
  eq(Strings("%s blacked\nout!", "RED"), "RED faints!", "page 2 renders")
  eq(Strings("Enemy %s", "RATTATA"), "Enmy RATTATA", "a word with its argument")
  eq(Strings("ATTACK", "status"), "AT", "the STATUS page's context picks the short form")
  eq(Strings("FIGHT", "battle"), "FGHT", "a context with no entry of its own falls back to the word")
  eq(Strings("TIME/  %d:%02d", 3, 7), "TM/  3:07", "the trainer card's time")
  Strings.load({})
end

-- install -----------------------------------------------------------------
do
  local previous = GameVersion.get()
  local data = synthetic()
  check(German.install(data, "red") == false and data.strings == nil,
    "an English game gets no catalog")
  check(data.field.theme == nil, "..and no theme")
  data = synthetic()
  data.strings = { FIGHT = "MOD" }
  data.field.theme = { choiceBox = { tx = 12 } }
  check(German.install(data, "red_de"), "a German game installs")
  eq(data.strings.FIGHT, "MOD", "a mod's entry wins")
  eq(data.strings.YES, "YS", "the rest is filled")
  eq(data.strings["CO-OP"], German.PROJECT["CO-OP"], "project wording included")
  eq(data.field.theme.choiceBox.tx, 12, "a mod's box geometry wins")
  eq(data.field.theme.choiceBox.tw, 7, "the German YES/NO box is 7 wide")
  eq(data.field.theme.useNextMonBox.tw, 7, "so is the battle's")
  eq(data.field.theme.saveBox.tw, 7, "and the SAVE prompt's")
  check(data.field.theme.healCancelBox == nil, "HEAL/CANCEL keeps its US width")
  local TypeChart = require("src.battle.TypeChart")
  eq(data.type_chart.types.FIRE.name, "FR", "the cartridge's type names become type records")
  eq(data.type_chart.types.PSYCHIC_TYPE.name, "PSY", "PSYCHIC under the id the constants use")
  eq(data.type_chart.types.FIRE.category, TypeChart.TYPES.FIRE.category,
    "a made record keeps the type's category")
  eq(TypeChart.displayName("FIRE", data), "FR", "TypeChart.displayName reads them")
  data = synthetic()
  data.type_chart.types = { FIRE = { name = "MODFIRE", category = "special" },
                            WATER = { name = "WATER", category = "special" } }
  German.install(data, "red_de")
  eq(data.type_chart.types.FIRE.name, "MODFIRE", "a mod's type name wins")
  eq(data.type_chart.types.WATER.name, "WTR", "a record still carrying the vanilla English name takes the cartridge's")
  eq(data.type_chart.types.GRASS.name, "GRS", "the others are filled")
  GameVersion.set("red_de")
  eq(German.layoutFor("battleMenu").boxX, 6, "the German battle menu box starts at column 6")
  eq(German.layoutFor("savePanel").labelX, 4, "the SAVE panel's labels at column 4")
  GameVersion.set("red")
  check(German.layoutFor("battleMenu") == nil, "no German layout in an English game")
  GameVersion.set(previous)
end

-- the Theme merge takes the German boxes ------------------------------------
do
  local Theme = require("src.ui.Theme")
  local before = { tx = Theme.choiceBox.tx, tw = Theme.choiceBox.tw }
  local data = synthetic()
  German.install(data, "blue_de")
  Theme.load(data)
  eq(Theme.choiceBox.tx, 13, "Theme.choiceBox moves to column 13")
  eq(Theme.choiceBox.tw, 7, "and is 7 wide")
  eq(Theme.choiceBox.ty, 7, "its row is untouched")
  Theme.choiceBox.tx, Theme.choiceBox.tw = before.tx, before.tw
  Theme.trainerSwitchBox.tw, Theme.useNextMonBox.tw, Theme.saveBox.tw = 6, 6, 6
end

-- the project wording is well formed ----------------------------------------
do
  local function directives(s)
    local n = 0
    for spec in s:gmatch("%%(.)") do if spec ~= "%" then n = n + 1 end end
    return n
  end
  local function widest(s)
    local w = 0
    for line in (s .. "\n"):gmatch("(.-)[\n\v\f]") do
      local plain = line:gsub("%b{}", "123"):gsub("%%[-0-9.]*[sd]", "12345")
      local _, glyphs = plain:gsub("[^\128-\191]", "")
      if glyphs > w then w = glyphs end
    end
    return w
  end
  local bad = {}
  for source, german in pairs(German.PROJECT) do
    if directives(source) ~= directives(german) then bad[#bad + 1] = source end
    if widest(source) <= 18 and widest(german) > 18 then bad[#bad + 1] = source .. " (too wide)" end
  end
  table.sort(bad)
  eq(table.concat(bad, "; "), "", "every project line keeps its directives and fits the box its English fits")
end

-- every engine source is covered, nothing stale -----------------------------
local tool = require("tools.game_strings")
do
  local missing = {}
  for _, row in ipairs(tool.missing()) do missing[#missing + 1] = ("%q"):format(row.source) end
  eq(table.concat(missing, ", "), "", "every Gen 1 engine source has a German entry (tools/game_strings.lua --missing)")
  eq(table.concat(tool.stale(), ", "), "", "no catalog entry is stale (tools/game_strings.lua --stale)")
end

-- the labels exist in the German manifests -----------------------------------
do
  local function manifest(path)
    local f = assert(io.open(path, "rb"))
    local raw = f:read("*a")
    f:close()
    return assert(Json.decode(raw))
  end
  for _, id in ipairs({ "red_de", "blue_de" }) do
    local m = manifest(GameVersion.info(id).manifest)
    local words = {}
    for _, entry in ipairs(m.field.words or {}) do
      words[type(entry) == "table" and entry[1] or entry] = true
    end
    local labels = {}
    for _, label in ipairs(m.text.labels) do labels[label] = true end
    local missing = {}
    local function wordLabels(entry)
      if type(entry) == "function" then return end
      if entry.join then
        for _, part in ipairs(entry.join) do wordLabels(part) end
        return
      end
      if not words[entry[1]] then missing[#missing + 1] = entry[1] end
      if not m.symbols[entry[1]] then missing[#missing + 1] = entry[1] .. " (symbol)" end
    end
    for _, entry in pairs(German.WORDS) do wordLabels(entry) end
    for _, entry in pairs(German.TEXTS) do
      for _, item in ipairs(entry) do
        if item:sub(1, 1) == "_" and not labels[item] then missing[#missing + 1] = item end
      end
    end
    table.sort(missing)
    eq(table.concat(missing, ", "), "", id .. " manifest places every label the catalog reads")
  end
end

-- the wording list the owner reviews --------------------------------------------
do
  local f = assert(io.open("docs/coop/german-wording.md", "r"))
  local doc = f:read("*a")
  f:close()
  local made = doc:match("<!%-%- made by: luajit tools/game_strings%.lua %-%-markdown %-%->\n(.-)<!%-%- end of the games part %-%->")
  eq(made, tool.markdown(), "docs/coop/german-wording.md lists the games' catalog as it is "
    .. "(luajit tools/game_strings.lua --markdown)")
end

T.finish()
