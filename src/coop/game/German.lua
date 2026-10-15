-- German games: the engine's own lines in the cartridge's words (#25, D102).
--
-- Upstream keys every line the engine authors on its English source
-- (src/core/Strings.lua) and already prints most battle, item and field
-- lines through the cartridge's own text labels (src/core/RomText.lua), so
-- a German import shows those in German by itself.  What stays English in
-- a German game is the rest: the menu words (FIGHT, SAVE, YES/NO, the PC
-- rows), the lines upstream never tied to a label, the options, the link
-- screens and the fork's own co-op lines.
--
-- This module builds a `Data.strings` catalog for those at boot, in three
-- layers, each only where the layer above has nothing:
--
--   1. WORDS: the cartridge's menu words, read at import by label into
--      `field.words` (RomExtractor.germanField, the list in
--      tools/make_german_manifest.py).  "FIGHT" is the first word of the
--      first row of BattleMenuText, whatever the cartridge spells there.
--   2. TEXTS: the cartridge's text labels in `Data.text`, for the lines
--      upstream prints from a literal although the cartridge has the line
--      (pokered prints EXP gains as _GainedText + _ExpPointsText, the engine
--      as one string).  The label's {RAM:...}/{USER}/{NUM:...} slots become
--      numbered directives ("%2$s") so the engine's arguments land in the
--      cartridge's order.
--   3. PROJECT: the fork's own wording for lines no cartridge has (co-op,
--      the engine's extra options, link play, a few prompts), listed for the
--      owner in docs/coop/german-wording.md (tools/game_strings.lua).
--
-- A translation mod's entries win: install() fills only keys that are not
-- in Data.strings yet.  Nothing here runs for an English game: install()
-- is a no-op unless GameVersion.isGerman().
--
-- The German cartridge also draws a few menus wider or elsewhere than the
-- US one; `German.layout` holds those constants (einstein95/pokered-de at
-- the manifest's pin, constants only) and install() puts the two-option
-- boxes into `field.theme` for src/ui/Theme.lua; the other sites read
-- `German.layout` behind GameVersion.isGerman().

local GameVersion = require("src.core.GameVersion")

local German = {}

-- ---------------------------------------------------------------------------
-- 1. the cartridge's menu words (field.words, by pokered label)
--
-- An entry names a label and takes `line` (1-based row of the label's
-- `next`-separated rows, trimmed) and optionally `word` (1-based word of
-- that row, split on spaces), or a `join` list of such parts concatenated;
-- `prefix`/`suffix` wrap the result (a numbered directive there carries the
-- source's argument).  A function receives the data and returns the string.
-- `yellow` holds the entry Gelbe Edition uses instead (#40): its cartridge
-- names a few labels otherwise and puts a PRINT row into two menus
-- (`false`: no such word in Yellow; an entry with only `yellow` is Yellow's
-- alone).  The same key works in the texts below.

local W = {}
German.WORDS = W

-- battle menu (data/text_boxes.asm BattleMenuText, SafariZoneBattleMenuText)
W["FIGHT"] = { "BattleMenuText", line = 1, word = 1 }
W["ITEM"] = { "BattleMenuText", line = 2, word = 1 }
W["RUN"] = { "BattleMenuText", line = 2, word = 2 }
W["BALLx"] = { "SafariZoneBattleMenuText", line = 1, word = 1 }
W["BAIT"] = { "SafariZoneBattleMenuText", line = 1, word = 2 }
W["THROW ROCK"] = { "SafariZoneBattleMenuText", line = 2, word = 1 }
W["WHICH TECHNIQUE?"] = { "WhichTechniqueString", line = 1 }
W["disabled!"] = { "DisabledText", line = 1 }
W["TYPE/"] = { "TypeText", line = 1, suffix = "/" }
W["Enemy %s"] = { "EnemyText", line = 1, suffix = "%1$s", keepSpace = true }
W["POKé BALL"] = function(data)
  local item = data.items and data.items.POKE_BALL
  return item and item.name
end
-- the stat names in battle messages (data/battle/stat_mod_names.asm)
W["ATTACK"] = { "StatModTextStrings", line = 1 }
W["DEFENSE"] = { "StatModTextStrings", line = 2 }
W["SPEED"] = { "StatModTextStrings", line = 3 }
W["SPECIAL"] = { "StatModTextStrings", line = 4 }
W["ACCURACY"] = { "StatModTextStrings", line = 5 }
W["EVADE"] = { "StatModTextStrings", line = 6 }
-- ..and their short forms on the STATUS page (status_screen.asm PrintStatsBox)
W["status|ATTACK"] = { "PrintStatsBox.StatsText", line = 1 }
W["status|DEFENSE"] = { "PrintStatsBox.StatsText", line = 2 }
W["status|SPEED"] = { "PrintStatsBox.StatsText", line = 3 }
W["status|SPECIAL"] = { "PrintStatsBox.StatsText", line = 4 }

-- two-option menus (data/yes_no_menu_strings.asm)
W["YES"] = { "TwoOptionMenuStrings.YesNoMenu", line = 1 }
W["NO"] = { "TwoOptionMenuStrings.YesNoMenu", line = 2 }
W["HEAL"] = { "TwoOptionMenuStrings.HealCancelMenu", line = 1 }
W["TRADE"] = { "TwoOptionMenuStrings.TradeCancelMenu", line = 1 }
W["CANCEL"] = { "ListMenuCancelText", line = 1 }
W["cableclub|CANCEL"] = { "CancelTextString", line = 1 }

-- START menu (engine/menus/draw_start_menu.asm)
W["POKéDEX"] = { "StartMenuPokedexText", line = 1 }
W["POKéMON"] = { "StartMenuPokemonText", line = 1 }
W["SAVE"] = { "StartMenuSaveText", line = 1 }
W["OPTION"] = { "StartMenuOptionText", line = 1 }
-- the SAVE / CONTINUE panel (engine/menus/main_menu.asm SaveScreenInfoText)
W["PLAYER"] = { "SaveScreenInfoText", line = 1 }
W["BADGES"] = { "SaveScreenInfoText", line = 2 }
W["TIME"] = { "SaveScreenInfoText", line = 4 }
W["Now saving..."] = { "NowSavingString", line = 1, yellow = false } -- Yellow: a text, below
W["CONTINUE"] = { "ContinueText", line = 1 }
W["NEW GAME"] = { "NewGameText", line = 1 }

-- the party and its menus (engine/menus/text_box.asm PokemonMenuEntries,
-- data/text_boxes.asm SwitchStatsCancelText)
W["STATS"] = { "PokemonMenuEntries", line = 1 }
W["SWITCH"] = { "PokemonMenuEntries", line = 2 }
W["USE"] = { "UseTossText", line = 1 }
W["TOSS"] = { "UseTossText", line = 2 }
-- field moves on the party menu are the moves' own names
for _, move in ipairs({ "CUT", "FLY", "SURF", "STRENGTH", "FLASH", "DIG",
                        "TELEPORT", "SOFTBOILED" }) do
  W[move] = function(data)
    local def = data.moves and data.moves[move]
    return def and def.name
  end
end

-- shops and money (data/text_boxes.asm BuySellQuitText, MoneyText)
W["BUY"] = { "BuySellQuitText", line = 1 }
W["SELL"] = { "BuySellQuitText", line = 2 }
W["shop|QUIT"] = { "BuySellQuitText", line = 3 }
W["MONEY"] = { "MoneyText", line = 1 }
W["COIN"] = { "PrintPrizePrice.CoinString", line = 1 }

-- the PCs (engine/pokemon/bills_pc.asm, engine/menus/players_pc.asm)
W["WITHDRAW <PK><MN>"] = { "BillsPCMenuText", line = 1 }
W["DEPOSIT <PK><MN>"] = { "BillsPCMenuText", line = 2 }
W["RELEASE <PK><MN>"] = { "BillsPCMenuText", line = 3 }
W["CHANGE BOX"] = { "BillsPCMenuText", line = 4 }
W["SEE YA!"] = { "BillsPCMenuText", line = 5, yellow = { "BillsPCMenuText", line = 6 } }
W["PRINT BOX"] = { yellow = { "BillsPCMenuText", line = 5 } }
W["WITHDRAW"] = { "WithdrawPCText", line = 1 }
W["DEPOSIT"] = { "DepositPCText", line = 1 }
W["WITHDRAW ITEM"] = { "PlayersPCMenuEntries", line = 1 }
W["DEPOSIT ITEM"] = { "PlayersPCMenuEntries", line = 2 }
W["TOSS ITEM"] = { "PlayersPCMenuEntries", line = 3 }
W["LOG OFF"] = { "PlayersPCMenuEntries", line = 4 }
W["BOX No."] = { "BoxNoText", line = 1 }
W["BOX No.%d"] = { "BoxNoText", line = 1, suffix = "%1$d" }
W["SOMEONE'S PC"] = { "SomeonesPCText", line = 1 }
W["BILL'S PC"] = { "BillsPCText", line = 1 }
W["%s's PC"] = { "PlayersPCText", line = 1, suffix = "%1$s", keepSpace = true }
W["PROF.OAK's PC"] = { "OaksPCText", line = 1 }
W["<PK><MN>LEAGUE"] = { "PKMNLeaguePCText", line = 1 }

-- naming (engine/menus/naming_screen.asm)
W["YOUR NAME?"] = { join = { { "YourTextString", line = 1, keepSpace = true },
                             { "NameTextString", line = 1 } } }
W["RIVAL's NAME?"] = { join = { { "RivalsTextString", line = 1, keepSpace = true },
                                { "NameTextString", line = 1 } } }
W["NICKNAME?"] = { "NicknameTextString", line = 1 }
W["NEW NAME"] = function(data)
  local presets = data.field and data.field.presetNames
  return presets and presets.customOption
end

-- the Pokédex (engine/menus/pokedex.asm)
W["SEEN"] = { "PokedexSeenText", line = 1 }
W["OWN"] = { "PokedexOwnText", line = 1 }
W["CONTENTS"] = { "PokedexContentsText", line = 1 }
W["SEEN %3d  OWN %3d"] = { join = { { "PokedexSeenText", line = 1, suffix = " %1$3d  " },
                                    { "PokedexOwnText", line = 1, suffix = " %2$3d" } } }
W["DATA"] = { "PokedexMenuItemsText", line = 1 }
W["CRY"] = { "PokedexMenuItemsText", line = 2 }
W["AREA"] = { "PokedexMenuItemsText", line = 3 }
W["pokedex|QUIT"] = { "PokedexMenuItemsText", line = 4, yellow = { "PokedexMenuItemsText", line = 5 } }
W["PRNT"] = { yellow = { "PokedexMenuItemsText", line = 4 } }
W["%s's NEST"] = { "MonsNestText", line = 1, prefix = "%1$s", keepSpace = true }
W["AREA UNKNOWN"] = { "AreaUnknownText", line = 1 }

-- STATUS page, trainer card, Hall of Fame (status_screen.asm,
-- start_sub_menus.asm, hall_of_fame.asm, league_pc.asm)
W["STATUS/"] = { "StatusText", line = 1 }
W["TYPE1/"] = { "TypesIDNoOTText", line = 1 }
W["TYPE2/"] = { "TypesIDNoOTText", line = 2 }
W["OT/"] = { "TypesIDNoOTText", line = 4 }
W["OT/%s"] = { "TypesIDNoOTText", line = 4, suffix = "%1$s" }
W["EXP POINTS"] = { "StatusScreenExpText", line = 1 }
W["LEVEL UP"] = { "StatusScreenExpText", line = 2 }
W["NAME/%s"] = { "TrainerInfo_NameMoneyTimeText", line = 1, suffix = "%1$s" }
W["MONEY/¥%d"] = { "TrainerInfo_NameMoneyTimeText", line = 2, suffix = "¥%1$d" }
W["TIME/  %d:%02d"] = { "TrainerInfo_NameMoneyTimeText", line = 3, suffix = "  %1$d:%2$02d" }
W["HALL OF FAME"] = { "HallOfFameText", line = 1 }
W["HALL OF FAME No"] = { "HallOfFameNoText", line = 1 }
W["LEVEL/"] = { "HoFMonInfoText", line = 1 }
W["PLAY TIME"] = { "HoFPlayTimeText", line = 1 }
W["Congrats! This"] = { "DiplomaCongrats", line = 1 }
W["diploma certifies"] = { "DiplomaCongrats", line = 2 }
W["that you have"] = { "DiplomaCongrats", line = 3 }
W["completed your"] = { "DiplomaCongrats", line = 4 }
-- the German diploma says it in four rows; the fifth English piece draws
-- a blank
W["POKéDEX."] = function(data)
  local congrats = data.field and data.field.words and data.field.words.DiplomaCongrats
  if type(congrats) ~= "string" then return nil end
  local _, rows = congrats:gsub("\n", "")
  return rows + 1 < 5 and " " or nil
end

-- the options the cartridge has (engine/menus/main_menu.asm)
-- (Yellow's option screen, engine/menus/options.asm, names the options in
-- AllOptionsText and keeps each value bracketed, "[ SCHNELL ]": word 2)
W["TEXT SPEED"] = { "TextSpeedOptionText", line = 1, yellow = { "AllOptionsText", line = 1 } }
W["FAST"] = { "TextSpeedOptionText", line = 2, word = 1, yellow = { "OptionsMenu_TextSpeed.Fast", word = 2 } }
W["MEDIUM"] = { "TextSpeedOptionText", line = 2, word = 2, yellow = { "OptionsMenu_TextSpeed.Mid", word = 2 } }
W["SLOW"] = { "TextSpeedOptionText", line = 2, word = 3, yellow = { "OptionsMenu_TextSpeed.Slow", word = 2 } }
W["BATTLE ANIMATION"] = { "BattleAnimationOptionText", line = 1, yellow = { "AllOptionsText", line = 2 } }
W["ON"] = { "BattleAnimationOptionText", line = 2, word = 1, yellow = { "OptionsMenu_BattleAnimations.On", word = 2 } }
W["OFF"] = { "BattleAnimationOptionText", line = 2, word = 2, yellow = { "OptionsMenu_BattleAnimations.Off", word = 2 } }
W["BATTLE STYLE"] = { "BattleStyleOptionText", line = 1, yellow = { "AllOptionsText", line = 3 } }
W["SHIFT"] = { "BattleStyleOptionText", line = 2, word = 1, yellow = { "OptionsMenu_BattleStyle.Shift", word = 2 } }
W["SET"] = { "BattleStyleOptionText", line = 2, word = 2, yellow = { "OptionsMenu_BattleStyle.Set", word = 2 } }
W["BACK"] = { "OptionMenuCancelText", line = 1 }

-- the Cable Club (engine/link/cable_club.asm, print_waiting_text.asm)
W["Waiting...!"] = { "WaitingText", line = 1 }
W["The trade was\ncancelled."] = { "TradeCanceled" }

-- ---------------------------------------------------------------------------
-- 2. the cartridge's text labels (Data.text)
--
-- An entry lists labels (and literal pieces, anything not starting with
-- "_") concatenated in order with their endings stripped; `page` picks one
-- \f-separated page of the result.  Slots become numbered directives in
-- the order they appear; `args` names, per source argument, the slot that
-- takes it (by the slot's name before any ":" or ","), for lines whose
-- German puts the arguments the other way round or drops one.  A slot that
-- is spelled the same in the source ({PLAYER}, {RAM:wNameBuffer}) stays a
-- slot for TextBox to fill; `fill` gives a slot a fixed value (a string or
-- a function of the data) when the engine's line hard-codes what the
-- cartridge reads from RAM.  An argument the German does not use is
-- consumed by a zero-width directive, so Strings keeps the entry.

local X = {}
German.TEXTS = X

-- the saving line Yellow keeps as a text (engine/menus/save.asm SavingText)
X["Now saving..."] = { yellow = { "_SavingText" } }

-- battle
X["%s gained\n%d EXP. Points!"] = { "_GainedText", "_ExpPointsText" }
X["%s gained\nwith EXP.ALL,\v%d EXP. Points!"] = { "_GainedText", "_WithExpAllText", "_ExpPointsText" }
X["%s grew\nto level %d!"] = { "_GrewLevelText" }
X["%s is out of\nuseable POKéMON!"] = { "_PlayerBlackedOutText", page = 1 }
X["%s blacked\nout!"] = { "_PlayerBlackedOutText", page = 2 }
X["%s is\nabout to use\v%s!"] = { "_TrainerAboutToUseText", page = 1 }
X["Will %s\nchange POKéMON?"] = { "_TrainerAboutToUseText", page = 2 }
X["%s wants\nto fight!"] = { "_TrainerWantsToFightText" }
X["%s has no\nmoves left!"] = { "_NoMovesLeftText" }
X["%s is too\nscared to move!"] = { "_ScaredText" }
-- pokered prints the nickname after these labels itself
X["Go! %s!"] = { "_GoText", "%1$s!" }
X["Do it! %s!"] = { "_DoItText", "%1$s!" }
X["Get'm! %s!"] = { "_GetmText", "%1$s!" }
X["Use next POKéMON?"] = { "_UseNextMonText" }
X["No! There's no\nrunning from a\vtrainer battle!"] = { "_NoRunningText" }
X["You missed the\nPOKéMON!"] = { "_ItemUseBallText01" }
X["Darn! The POKéMON\nbroke free!"] = { "_ItemUseBallText02" }
X["GHOST: Get out...\nGet out..."] = { "_GetOutText" }
X["SILPH SCOPE\nunveiled the\vGHOST's identity!"] = { "_UnveiledGhostText" }
X["{RIVAL}: Yeah! Am\nI great or what?"] = { "_Rival1WinText" }
X["PA: You're out of\nSAFARI BALLs!\nGame over!"] = { "_OutOfSafariBallsText" }
X["PA: You're out of\nSAFARI BALLs!"] = { "_OutOfSafariBallsText", page = 2 }
X["%s\ndug a hole!"] = { "%1$s", "_DugAHoleText" }
X["%s\nflew up high!"] = { "%1$s", "_FlewUpHighText" }
X["%s\nis glowing!"] = { "%1$s", "_SkyAttackGlowingText" }
X["%s\nlowered its head!"] = { "%1$s", "_LoweredItsHeadText" }
X["%s\nmade a whirlwind!"] = { "%1$s", "_MadeWhirlwindText" }
X["%s\ntook in sunlight!"] = { "%1$s", "_TookInSunlightText" }
X["%s's\n%s rose!"] = { "_MonsStatsRoseText", "_RoseText", args = { "USER", "RAM" } }
X["%s's\n%s fell!"] = { "_MonsStatsRoseText", "_FellText", args = { "USER", "RAM" } }
X["%s's\n%s rose."] = { "_VitaminStatRoseText" }
X["%s's\ndream was eaten!"] = { "_DreamWasEatenText" }
X["Sucked health from\n%s!"] = { "_SuckedHealthText" }
X["%s's\nhurt by poison!"] = { "_HurtByPoisonText", args = { "USER" } }
X["%s's\nhurt by the burn!"] = { "_HurtByBurnText", args = { "USER" } }
X["%s is\nalready out!"] = { "_AlreadyOutText" }
X["%s sent\nout %s!"] = { "_TrainerSentOutText" }
X["There's no will\nto fight!"] = { "_NoWillText" }
X["%s learned\n%s!"] = { "_LearnedMove1Text" }

-- field and menus
X["Do you want to\ngive a nickname\nto %s?"] = { "_DoYouWantToNicknameText" }
X["There's no more\nroom for POKéMON!\v%s was\vsent to POKéMON\vBOX %s on PC!"] = { "_SentToBoxText" }
X["Is it OK to toss\n%s?"] = { "_IsItOKToTossItemText" }
X["No cycling\nallowed here."] = { "_NoCyclingAllowedHereText" }
X["Nope! ITEMFINDER\nisn't responding."] = { "_ItemfinderFoundNothingText" }
X["Yes! ITEMFINDER\nindicates there's\nan item nearby."] = { "_ItemfinderFoundItemText" }
X["OAK: %s!\nThis isn't the\ntime to use that!"] = { "_ItemUseNotTimeText" }
X["That's too impor-\ntant to toss!"] = { "_TooImportantToTossText" }
X["Threw away\n%s."] = { "_ThrewAwayItemText" }
X["You can't get off\nhere."] = { "_CannotGetOffHereText" }
-- the engine names the BICYCLE itself; the cartridge's slot takes its name
local function bicycle(data)
  local item = data.items and data.items.BICYCLE
  return item and item.name or "BICYCLE"
end
X["%s got on\nthe BICYCLE!"] = { "_GotOnBicycleText1", "\n", "_GotOnBicycleText2",
                                 args = { "PLAYER" }, fill = { RAM = bicycle } }
X["%s got off\nthe BICYCLE."] = { "_GotOffBicycleText1", "\n", "_GotOffBicycleText2",
                                  args = { "PLAYER" }, fill = { RAM = bicycle } }
X["%s is\ntaken out.\vGot %s."] = { "_MonIsTakenOutText" }
X["%s was\nreleased outside.\fBye %s!"] = { "_MonWasReleasedText" }
X["%s was\nstored in Box %s."] = { "_MonWasStoredText" }
X["Choose a\n<PK><MN> BOX."] = { "_ChooseABoxText" }
X["Once released,\n%s is\ngone forever. OK?"] = { "_OnceReleasedText" }
X["Oops! This Box is\nfull of POKéMON."] = { "_BoxFullText" }
X["What? There are\nno POKéMON here!"] = { "_NoMonText" }
X["What?"] = { "_WhatText" }
X["When you change a\nPOKéMON BOX, data\vwill be saved.\fIs that okay?"] = { "_WhenYouChangeBoxText" }
X["You can't deposit\nthe last POKéMON!"] = { "_CantDepositLastMonText" }
X["You can't take\nany more POKéMON.\fDeposit POKéMON\nfirst."] = { "_CantTakeMonText" }
X["POKéDEX   Seen:{NUM:wDexRatingNumMonsSeen, 1, 3}\n         Owned:{NUM:wDexRatingNumMonsOwned, 1, 3}"] = { "_DexSeenOwnedText" }
X["POKéDEX Rating{COLON}"] = { "_DexRatingText" }
X["Bring out which\nPOKéMON?"] = { "_PartyMenuBattleText" }
X["Choose a POKéMON."] = { "_PartyMenuNormalText" }
X["Move POKéMON\nwhere?"] = { "_PartyMenuSwapMonText" }
X["Use TM on which\nPOKéMON?"] = { "_PartyMenuUseTMText" }
X["Use item on which\nPOKéMON?"] = { "_PartyMenuItemUseText" }
X["No! A new BADGE\nis required."] = { "_NewBadgeRequiredText" }
X["{RAM:wNameBuffer} can't\nFLY here."] = { "_CannotFlyHereText" }
X["{RAM:wNameBuffer} can't\nuse TELEPORT now."] = { "_CannotUseTeleportNowText" }
X["How many?"] = { "_WithdrawHowManyText" }
X["No room left to\nstore items."] = { "_NoRoomToStoreText" }
X["You can't carry\nany more items."] = { "_CantCarryMoreText" }
X["You can't carry\nany more items!"] = { "_CantCarryMoreText" }
X["Here you are!\nThank you!"] = { "_PokemartBoughtItemText" }
X["Hi there!\nMay I help you?"] = { "_PokemartGreetingText" }
X["I can't put a\nprice on that."] = { "_PokemartUnsellableItemText" }
X["Is there anything\nelse I can do?"] = { "_PokemartAnythingElseText" }
X["What would you\nlike to sell?"] = { "_PokemonSellingGreetingText" }
X["You don't have\nanything to sell."] = { "_PokemartItemBagEmptyText" }
X["You don't have\nenough money."] = { "_PokemartNotEnoughMoneyText" }
X["Darn!\nRan out of coins!"] = { "_OutOfCoinsSlotMachineText" }
X["Not enough\ncoins!"] = { "_NotEnoughCoinsSlotMachineText" }
X["%s saved\nthe game!"] = { "_GameSavedText" }
X["Would you like to\nSAVE the game?"] = { "_WouldYouLikeToSaveText" }
X["%s found\n%d coins!"] = { "_FoundHiddenCoinsText" }
X["A blinding FLASH\nlights the area!"] = { "_FlashLightsAreaText" }
X["Accessed PROF.\nOAK's PC.\fAccessed POKéDEX\nRating System."] = { "_AccessedOaksPCText" }
X["An elevator!"] = { "_ElevatorText" }
X["BILL's favorite\nPOKéMON list!"] = { "_BillsHousePokemonListText1" }
X["Bingo!"] = { "_CardKeySuccessText1" }
X["Closed link to\nPROF.OAK's PC."] = { "_ClosedOaksPCText" }
X["Crammed full of\nPOKéMON books!"] = { "_PokemonBooksText" }
X["Gyaoo!"] = { "_VictoryRoad2FMoltresBattleText" }
X["Hey! There's a\nswitch under the\ntrash!\fThe 1st electric\nlock opened!"] = { "_VermilionGymTrashSuccessText1" }
X["Nope! There's\nonly trash here.\fHey! The electric\nlocks were reset!"] = { "_VermilionGymTrashFailText" }
X["The 2nd electric\nlock opened!\fThe motorized door\nopened!"] = { "_VermilionGymTrashSuccessText3" }
X["I like shorts!\nThey're comfy and\neasy to wear!"] = { "_Route3Youngster2BattleText" }
X["OK. We'll need\nyour POKéMON."] = { "_NeedYourPokemonText" }
X["Shall we heal your\nPOKéMON?"] = { "_ShallWeHealYourPokemonText" }
X["Your POKéMON are\nfighting fit!"] = { "_PokemonFightingFitText" }
X["Welcome to our\nPOKéMON CENTER!"] = { "_PokemonCenterWelcomeText", page = 1 }
X["Want to get your\nPOKéDEX rated?"] = { "_GetDexRatedText" }
X["You don't have the\nBOULDERBADGE yet!"] = { "_Route22GateGuardNoBoulderbadgeText", page = 2 }
X["{PLAYER} got on\n{RAM:wNameBuffer}!"] = { "_SurfingGotOnText" }
X["{PLAYER} initiated\nTELEPORTER's Cell\nSeparator!"] = { "_BillsHouseInitiatedText" }
X["{RAM:wNameBuffer} can\nmove boulders."] = { "_CanMoveBouldersText" }
X["{RAM:wNameBuffer} hacked\naway with CUT!"] = { "_UsedCutText" }
X["{RAM:wNameBuffer} used\nSTRENGTH."] = { "_UsedStrengthText" }
X["{PLAYER} got\n%s!"] = { "_GotMonText" }
X["The link was\nbroken."] = { "_LinkCanceledText", yellow = { "_ColosseumCanceledText" } } -- Yellow: the same line under its Colosseum label

-- Oak's speech and the naming screen (engine/movie/oak_speech.asm)
X["Hello there!\nWelcome to the\vworld of POKéMON!\fMy name is OAK!\nPeople call me\vthe POKéMON PROF!"] = { "_OakSpeechText1" }
X["This world is\ninhabited by\vcreatures called\vPOKéMON!"] = { "_OakSpeechText2A" }
X["\fFor some people,\nPOKéMON are\vpets. Others use\vthem for fights.\fMyself...\fI study POKéMON\nas a profession."] = { "_OakSpeechText2B" }
X["First, what is\nyour name?"] = { "_IntroducePlayerText" }
X["This is my grand-\nson. He's been\vyour rival since\vyou were a baby.\f...Erm, what is\nhis name again?"] = { "_IntroduceRivalText" }
X["Right! So your\nname is {PLAYER}!"] = { "_YourNameIsText" }
X["That's right! I\nremember now! His\vname is {RIVAL}!"] = { "_HisNameIsText" }
X["{PLAYER}!\fYour very own\nPOKéMON legend is\vabout to unfold!\fA world of dreams\nand adventures\vwith POKéMON\vawaits! Let's go!"] = { "_OakSpeechText3" }

-- ---------------------------------------------------------------------------
-- 3. the fork's own wording, for lines no cartridge has
--
-- Grouped by the screen that shows them; tools/game_strings.lua --markdown
-- turns the groups ("-- " comment lines) into the tables the owner reviews
-- in docs/coop/german-wording.md.  A box row holds 18 characters, a menu
-- row fewer.

local P = {}
German.PROJECT = P

-- co-op (START > CO-OP, notices)
P["CO-OP"] = "KOOP"
P["NO PARTNERS YET"] = "NOCH KEINE PARTNER"
P["AWAY"] = "WEG"
P["TOWN MAP"] = "KARTE"
P["LEAVE SESSION"] = "SITZUNG VERLASSEN"
P["LEAVE THE CO-OP\nSESSION?"] = "KOOP-SITZUNG\nVERLASSEN?"
P["END THE SESSION\nFOR EVERYONE?"] = "SITZUNG FÜR ALLE\nBEENDEN?"
P["%s joined the session."] = "%s ist der Sitzung beigetreten."
P["%s left the session."] = "%s hat die Sitzung verlassen."
-- co-op saves (#13)
P["Campaign saved."] = "Alles gespeichert."
P["%s saved the campaign."] = "%s hat die Kampagne gespeichert."
P["The campaign was not saved."] = "Die Kampagne wurde nicht gespeichert."
P["A battle is in\nprogress!\fIt can't be saved\nright now."] = "Ein Kampf läuft\nnoch!\fSpeichern geht\ngerade nicht."
P["NOT SAVED YET"] = "NOCH NICHT GESP."
P["SAVED JUST NOW"] = "GERADE GESPEICHERT"
P["SAVED %d MIN AGO"] = "VOR %d MIN GESP."
P["SAVED %d H AGO"] = "VOR %d H GESP."
P["AUTOSAVE: ON"] = "AUTO-SPEICHERN: AN"
-- co-op story items (#16)
P["%s shared %s."] = "%s teilt %s."
P["%s went to the PC."] = "%s liegt jetzt im PC."
P["%s handed over %s."] = "%s hat %s abgegeben."
P["No room for %s!"] = "Kein Platz: %s!"
P["Got %s."] = "%s erhalten."

-- battle
P["FOE"] = "GEGNER"
P["But every BOX\nis full!"] = "Aber jede BOX\nist voll!"
P["%s used\nSAFARI BALL!"] = "%s setzt\nSAFARIBALL ein!"
P["%s\nis charging up!"] = "%s\nlädt sich auf!"
P["%s is\nprotected by MIST!"] = "%s wird\ndurch WEISSNEBEL\ngeschützt!"
P["%s\nwas afflicted\nby %s!"] = "%s\nleidet an\n%s!"
P["HEALTH"] = "KP"
-- the cartridge spells PP as AP but keeps no label for it
P["PP"] = "AP"
P["%s gained\na boosted\v%d EXP. Points!"] = "%s erhält\neinen Bonus:\v%d EP!"
P["%s's\n%s\ngreatly rose!"] = "%ss\n%s\nsteigt stark!"
P["%s's\n%s\ngreatly fell!"] = "%ss\n%s\nsinkt stark!"
P["What will"] = "Was soll"
P[" do?"] = " tun?"
P["%s is out of\nPOKéMON!\f%s wins!"] = "%s hat keine\nPOKéMON mehr!\f%s gewinnt!"
P["%s left the\nbattle."] = "%s hat den\nKampf verlassen."
P["%s ran from\nthe battle!"] = "%s ist aus dem\nKampf geflohen!"
P["%s ran out of\ntime!"] = "%s hat keine\nZeit mehr!"
P["%s vs %s!"] = "%s gegen %s!"
P["%s's %s can't\nbattle on this\ngame."] = "%s: %s kann\nin diesem Spiel\nnicht kämpfen."
P["%s's %s can't\nbattle on this\ngame.\n(%s)"] = "%s: %s kann\nin diesem Spiel\nnicht kämpfen.\n(%s)"
P["Items can't be\nused in a link\nbattle!"] = "Im Link-Kampf\nsind keine Items\nerlaubt!"
P["Link battle needs\nthe same version\nand mods."] = "Link-Kampf nur\nmit gleicher\nVersion und Mods."
P["Link desync!\n%s differs.\fAre both games\nthe same version\nand mods?"] = "Link gestört!\n%s weicht ab.\fHaben beide Spiele\ndieselbe Version\nund Mods?"
P["Their %s isn't\nin this game.\n(%s)"] = "Das %s gibt es\nin diesem Spiel\nnicht. (%s)"
P["Time's up! You\nforfeit the match."] = "Zeit um! Du gibst\nden Kampf auf."
P["Your %s can't\nbattle on the\nother game."] = "Dein %s kann\nim anderen Spiel\nnicht kämpfen."

-- field
P["%s received\n%s!"] = "%s erhält\n%s!"
P["%s received\nthe %s!"] = "%s erhält\n%s!"
P["Go right ahead!"] = "Geh ruhig weiter!"
P["Oh! That is the\n{RAM}!"] = "Oh! Das ist der\n{RAM}!"
P["You don't have the\n{RAM} yet!"] = "Du hast den\n{RAM} noch nicht!"
P["Keep it up!"] = "Weiter so!"
P["PIKACHU looks\ncontent."] = "PIKACHU sieht\nzufrieden aus."
P["POKéMON LEAGUE HQ"] = "POKéMON-LIGA-SITZ"
P["There's a slew of\nPOKéMON stuff!"] = "Hier ist jede\nMenge POKéMON-\nKram!"
P["You need a\nBICYCLE for the\nCycling Road!"] = "Für die Radstraße\nbrauchst Du ein\nFAHRRAD!"
P["POKéDEX comp-\nletion is:\f{NUM:hDexRatingNumMonsSeen} POKéMON seen\n{NUM:hDexRatingNumMonsOwned} POKéMON owned\fPROF.OAK's\nRating:"] =
  "Stand des\nPOKéDEX:\f{NUM:hDexRatingNumMonsSeen} POKéMON\ngesehen,\v{NUM:hDexRatingNumMonsOwned} POKéMON\vgefangen.\fPROF.EICHS\nUrteil:"
P["{RAM}\nPOKéMON GYM\nLEADER: {RAM}"] = "{RAM}\nPOKéMON-ARENA\nLEITER: {RAM}"
P["To %s"] = "Nach %s"
P["FLY TO?"] = "WOHIN?"
P["ABLE"] = "OK"
P["NOT ABLE"] = "NEIN"
P["FNT"] = "BSG"
P["No POKéMON!"] = "Kein POKéMON!"
P["No SURFing here!"] = "Hier kein SURFEN!"
P["Nothing to CUT!"] = "Nichts zu\nZERSCHNEIDEN!"
P["No good! It's not\neven near water."] = "Geht nicht! Kein\nWasser in der\nNähe."
P["The TOWN MAP is\nunreadable here."] = "Die KARTE ist\nhier nicht\nlesbar."
P["There isn't any\nresponse..."] = "Keine\nReaktion..."
P["Empty."] = "Leer."
P["Nothing here."] = "Nichts da."
P["%s looks\nunhappy about it!"] = "%s sieht\nunglücklich aus!"
P["The party is full!"] = "Das Team ist voll!"
P["You need at least\none POKéMON!"] = "Du brauchst\nmindestens ein\nPOKéMON!"
P["BOX %d is full!"] = "BOX %d voll!"
P["PRINT BOX"] = "BOX DRUCKEN"
P["Printed BOX %d!\f"] = "BOX %d\ngedruckt!\f"
P["Printed %s's\ndata!\f"] = "Daten von %s\ngedruckt!\f"
P["Printer error!\n%s"] = "Druckerfehler!\n%s"
P["PRNT"] = "DRCK"
P["Toss %s?"] = "%s\nwegwerfen?"
P["NO THANKS"] = "NEIN DANKE"
P["SLOT MACHINE"] = "SPIELAUTOMAT"
P["COINS %4d"] = "MÜNZEN %4d"
P["RETURN TO MAIN\nMENU?"] = "ZURÜCK ZUM\nHAUPTMENÜ?"
P["QUIT"] = "BEENDEN"
P["EXIT GAME"] = "SPIEL BEENDEN"
P["Diploma"] = "Diplom"
P["Player"] = "Spieler"
P["IDNo.%05d"] = "IDNr.%05d"
P["No.%03d"] = "Nr.%03d"
P["No."] = "Nr."
P[":L%d No.%03d"] = ":L%d Nr.%03d"
P["Trade completed!\f%s received\n%s!"] = "Tausch vollzogen!\f%s erhält\n%s!"
P["The trade stopped:\n%s."] = "Der Tausch wurde\nabgebrochen:\n%s."

-- the engine's own options (START > OPTION)
P["%d OPTIONS"] = "%d OPTIONEN"
-- the option groups ("SPEED" here is the game speed, not the stat)
P["options|SPEED"] = "TEMPO"
P["GRAPHICS"] = "GRAFIK"
P["%d INSTALLED"] = "%d INSTALLIERT"
P["AUDIO MODE"] = "AUDIO-MODUS"
P["AUTO (FILL HUD)"] = "AUTO (HUD FÜLLEN)"
P["BATTLE BG"] = "KAMPF-HINTERGRUND"
P["BATTLE HUD"] = "KAMPF-HUD"
P["BATTLE LAYOUT"] = "KAMPF-LAYOUT"
P["BATTLE SIZE"] = "KAMPF-GRÖSSE"
P["BATTLE SPEED"] = "KAMPF-TEMPO"
P["BLACK"] = "SCHWARZ"
P["BOTH"] = "BEIDE"
P["CENTERED"] = "ZENTRIERT"
P["COLORS"] = "FARBEN"
P["CONTROLS"] = "STEUERUNG"
P["DATE FORMAT"] = "DATUMSFORMAT"
P["DISPLAY"] = "ANZEIGE"
P["DISPLAY (%dHZ)"] = "ANZEIGE (%dHZ)"
P["DYNAMIC"] = "DYNAMISCH"
P["EXTENDED"] = "ERWEITERT"
P["FAITHFUL RATIO"] = "ORIGINALFORMAT"
P["FILL"] = "FÜLLEN"
P["FIT"] = "EINPASSEN"
P["FIXED"] = "FEST"
P["KEY BAR"] = "TASTENLEISTE"
P["LOGIC CLOCK"] = "LOGIKTAKT"
P["MAX FPS"] = "MAX. FPS"
P["MENU SPEED"] = "MENÜ-TEMPO"
P["MUSIC FILTER"] = "MUSIKFILTER"
P["MUSIC VOL"] = "MUSIK-LAUTST."
P["OG"] = "ORIGINAL"
P["ORIENTATION"] = "AUSRICHTUNG"
P["OVERWORLD SPEED"] = "WELT-TEMPO"
P["PERFORMANCE"] = "LEISTUNG"
P["PIKACHU VOL"] = "PIKACHU-LAUTST."
P["RULESET"] = "REGELWERK"
P["SCREEN POS"] = "BILDPOSITION"
P["SFX VOL"] = "EFFEKT-LAUTST."
P["SHADER FX"] = "SHADER-EFFEKTE"
P["SHADER FX 2"] = "SHADER-EFFEKTE 2"
P["TILT"] = "NEIGUNG"
P["TIME FORMAT"] = "ZEITFORMAT"
P["TOUCH PAD"] = "TOUCH-PAD"
P["UI LAYOUT"] = "UI-LAYOUT"
P["UI LETTERBOX"] = "UI-LETTERBOX"
P["UNAVAILABLE"] = "NICHT VERFÜGBAR"
P["VIDEO MODE"] = "VIDEO-MODUS"
P["VOID FILL"] = "RANDFÜLLUNG"
P["WHITE"] = "WEISS"
P["WIDE"] = "BREIT"
P["WORLD"] = "WELT"

-- link play (upstream's Cable Club over the network)
P["HOST A GAME"] = "SPIEL ERÖFFNEN"
P["JOIN A GAME"] = "SPIEL BEITRETEN"
P["BATTLE"] = "KAMPF"
P["Calling..."] = "Rufe an..."
P["Waiting for join..."] = "Warte auf Gast..."
P["Waiting for the"] = "Warte auf das"
P["other game..."] = "andere Spiel..."
P["host to choose..."] = "Wahl des Hosts..."
P["Checking the"] = "Prüfe das"
P["Exchanging data..."] = "Datenaustausch..."
P["Friend joins at:"] = "Freund wählt:"
P["Port: %s"] = "Port: %s"
P["UDP port %s"] = "UDP-Port %s"
P["LEVELS:"] = "LEVEL:"
P["A: connect  B: back"] = "A: start  B: zurück"
P["A: continue  B: back"] = "A: weiter  B: zurück"
P["A: trade anyway"] = "A: trotzdem"
P["Not an IP address."] = "Keine IP-Adresse."
P["Link battle\ncan't start."] = "Link-Kampf kann\nnicht starten."
P["Link error:\n%s"] = "Link-Fehler:\n%s"
P["The other side\nsent bad data."] = "Die Gegenseite\nsendet Unsinn."
P["The relay stopped\nanswering."] = "Das Relay\nantwortet nicht."
P["can't reach relay %s:%d\n(%s)"] = "Relay %s:%d nicht\nerreichbar (%s)"
P["no answer from\n%s"] = "Keine Antwort von\n%s"
P["Something broke\nduring the link."] = "Beim Link ist\netwas kaputt-\ngegangen."
P["Names are 3 to 16 characters."] = "Namen haben 3 bis 16 Zeichen."
P["Sign-in didn't work: %s"] = "Anmeldung fehlgeschlagen: %s"
P["The server kept your old name."] = "Der Server behält Deinen alten Namen."
P["This build is too old for online play. Please update."] = "Dieser Build ist zu alt für Online-Spiel. Bitte aktualisieren."

-- ---------------------------------------------------------------------------
-- the layouts the German cartridge changed (pokered-de, constants only)

German.layout = {
  -- data/text_boxes.asm BATTLE_MENU_TEMPLATE: box (6,12)-(19,17), text
  -- from (8,14); the cursor's right column is one left of the second word
  -- ("KMPF <PK><MN>" puts it at 13; US: box from 8, text 10, cursor 15)
  battleMenu = { boxX = 6, textX = 8, rightCursorX = 12 },
  -- SAFARI_BATTLE_MENU_TEMPLATE keeps its full-width box and text column 2;
  -- the right word starts at 13 ("BALL×      KÖDER"; US: 14, cursor 13)
  safariMenu = { rightX = 13, rightCursorX = 12 },
  -- data/yes_no_menu_strings.asm: YES/NO rows are 5 wide (US 4), so every
  -- two-option box is 7 tiles wide; the shared right-hand one moves to
  -- column 13 (home/yes_no.asm hlcoord 13, 7; US 14, 7)
  twoOption = { width = 7, rightX = 13 },
  -- engine/menus/main_menu.asm: the SAVE and CONTINUE panels start a column
  -- further left (hlcoord 3, 0 / 3, 7; labels at column 4; US 4 and 5)
  savePanel = { boxX = 3, boxW = 17, labelX = 4 },
  -- engine/link/cable_club.asm TradeCenter_DrawCancelBox: 12 columns inside
  -- for ABBRECHEN (US 9), the blank run beside it from column 8 (US 11)
  cableClubCancel = { boxW = 14, fillX = 8, fillW = 12 },
  -- engine/pokemon/bills_pc.asm: the STATS/CANCEL box a column wider, from
  -- column 8 (US 9)
  pcSubmenu = { boxX = 8, boxW = 12 },
}
-- ..and what Gelbe Edition draws otherwise (pokeyellow-de, #40); the rest
-- it draws as Rote and Blaue do
German.layout.yellow = {
  -- engine/link/cable_club.asm TradeCenter_DrawCancelBox: the 12-column box
  -- as in Rote, the blank run beside it where US Yellow has it (hlcoord
  -- 11, 15, 9 wide)
  cableClubCancel = { boxW = 14, fillX = 11, fillW = 9 },
}

-- ---------------------------------------------------------------------------
-- building the catalog

local ENDING = { DONE = true, PROMPT = true }

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function splitLines(s)
  local out = {}
  for line in (s .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
  return out
end

local function splitWords(s)
  local out = {}
  for word in s:gmatch("%S+") do out[#out + 1] = word end
  return out
end

-- one WORDS part -> string or nil
local function wordPart(words, part)
  local raw = words[part[1]]
  if type(raw) ~= "string" then return nil end
  local lines = splitLines(raw)
  local s = lines[part.line or 1]
  if s == nil then return nil end
  if part.word then
    s = splitWords(s)[part.word]
    if s == nil then return nil end
  elseif not part.keepSpace then
    s = trim(s)
  end
  if s == "" then return nil end
  return (part.prefix or "") .. s .. (part.suffix or "")
end

function German.word(data, entry)
  if type(entry) == "function" then
    local ok, s = pcall(entry, data)
    return ok and type(s) == "string" and s ~= "" and s or nil
  end
  local words = data.field and data.field.words
  if type(words) ~= "table" then return nil end
  if entry.join then
    local out = {}
    for i, part in ipairs(entry.join) do
      out[i] = wordPart(words, part)
      if out[i] == nil then return nil end
    end
    return table.concat(out)
  end
  return wordPart(words, entry)
end

-- the name of a slot: "{RAM:wNameBuffer}" -> "RAM", "{NUM:x, 1, 3}" -> "NUM"
local function slotName(token)
  return token:sub(2, -2):match("^[%w_]+") or ""
end

-- The German text of one TEXTS entry, its slots turned into numbered
-- directives; nil when a label is not in the cache.
function German.text(data, source, entry)
  local texts = data.text
  if type(texts) ~= "table" then return nil end
  local pieces = {}
  for i, item in ipairs(entry) do
    if item:sub(1, 1) == "_" then
      local t = texts[item]
      if type(t) ~= "string" then return nil end
      t = t:gsub("{DONE}", ""):gsub("{PROMPT}", ""):gsub("{SCROLL}", "\v")
      pieces[i] = t:gsub("%%", "%%%%")
    else
      pieces[i] = item -- a literal piece, with its own directives
    end
  end
  local text = table.concat(pieces)
  if entry.page then
    local pages = {}
    for page in (text .. "\f"):gmatch("(.-)\f") do pages[#pages + 1] = page end
    text = pages[entry.page]
    if text == nil then return nil end
  end
  -- which slots stay slots: the ones the source spells the same way
  local keep = {}
  for token in source:gmatch("%b{}") do keep[token] = true end
  local named, fill = entry.args, entry.fill
  local used, n = {}, 0
  local out = text:gsub("%b{}", function(token)
    if keep[token] then return token end
    local name = slotName(token)
    if ENDING[name] then return "" end
    local fixed = fill and (fill[token:sub(2, -2):match("^[^,]+")] or fill[name])
    if fixed ~= nil then
      if type(fixed) == "function" then fixed = fixed(data) end
      return tostring(fixed or ""):gsub("%%", "%%%%")
    end
    local index
    if named then
      for i, want in ipairs(named) do
        if name == want or token:sub(2, -2):match("^[^,]+") == want then index = i end
      end
      if not index then return "" end
    else
      n = n + 1
      index = n
    end
    used[index] = true
    return ("%%%d$s"):format(index)
  end)
  -- every argument the source passes must be referenced, or Strings
  -- rejects the entry: the ones the German has no slot for print nothing
  local wants = 0
  for spec in source:gmatch("%%(.)") do if spec ~= "%" then wants = wants + 1 end end
  for index in out:gmatch("%%(%d+)%$") do used[tonumber(index)] = true end
  for index = 1, wants do
    if not used[index] then out = out .. ("%%%d$.0s"):format(index) end
  end
  return out
end

-- The entry a game of this base ("red", "blue", "yellow") reads: `yellow`
-- replaces it in a Yellow game (false: nothing); an entry with no label of
-- its own is Yellow's alone.
function German.variant(entry, base)
  if type(entry) ~= "table" then return entry end
  if base == "yellow" and entry.yellow ~= nil then return entry.yellow or nil end
  if entry[1] == nil and entry.join == nil then return nil end
  return entry
end

-- Every entry this data can fill: source -> German, for a game of `base`
-- (the current game's when nil).
function German.catalog(data, base)
  base = base or GameVersion.base()
  local out = {}
  for source, entry in pairs(German.WORDS) do
    entry = German.variant(entry, base)
    local s = entry and German.word(data, entry)
    if s then out[source] = s end
  end
  for source, entry in pairs(German.TEXTS) do
    entry = German.variant(entry, base)
    if entry and out[source] == nil then
      local s = German.text(data, source, entry)
      if s then out[source] = s end
    end
  end
  for source, s in pairs(German.PROJECT) do
    if out[source] == nil then out[source] = s end
  end
  return out
end

-- The type names the STATUS page, the move box and the Hall of Fame draw:
-- upstream keeps English constants (src/battle/TypeChart.lua DISPLAY_NAMES
-- and the ids) and reads a name only from a mod's type record, while the
-- import already holds the cartridge's names in type_chart.names, in
-- pokered's data/types/names.asm order.  A German game gets a record per
-- type with the cartridge's name, keeping whatever a mod registered.
German.TYPE_ORDER = {
  "NORMAL", "FIGHTING", "FLYING", "POISON", "FIRE", "WATER", "GRASS",
  "ELECTRIC", "PSYCHIC_TYPE", "ICE", "GROUND", "ROCK", "BIRD", "BUG", "GHOST",
  "DRAGON",
}

function German.typeNames(data)
  local chart = data.type_chart
  local names = type(chart) == "table" and chart.names
  if type(names) ~= "table" then return nil end
  local known = data.constants and data.constants.types
  local out = {}
  for i, id in ipairs(German.TYPE_ORDER) do
    local name = names[i]
    if type(known) == "table" and known[id] == nil then
      -- PSYCHIC_TYPE is PSYCHIC in a dataset that names the type by the id
      -- upstream's constants use; take whichever the constants know
      local other = id:match("^(.-)_TYPE$") or (id .. "_TYPE")
      if known[other] ~= nil then id = other end
    end
    if type(name) == "string" and name ~= "" then out[id] = name end
  end
  return out
end

local function installTypeNames(data)
  local names = German.typeNames(data)
  if not names then return end
  local TypeChart = require("src.battle.TypeChart")
  local types = data.type_chart.types
  if type(types) ~= "table" then
    types = {}
    data.type_chart.types = types
  end
  for id, name in pairs(names) do
    -- a record a mod renamed keeps its name; one the merge seeded from the
    -- engine's vanilla record, or made here from it, takes the cartridge's
    local vanilla = TypeChart.TYPES[id] or {}
    local record = types[id]
    if type(record) ~= "table" then
      record = {}
      for key, value in pairs(vanilla) do record[key] = value end
      types[id] = record
    end
    if record.name == nil or record.name == vanilla.name then record.name = name end
  end
end

-- The two-option boxes for src/ui/Theme.lua (field.theme), from the
-- cartridge's 5-wide YES/NO rows.
function German.theme()
  local two = German.layout.twoOption
  return {
    choiceBox = { tx = two.rightX, tw = two.width },
    trainerSwitchBox = { tw = two.width },
    useNextMonBox = { tw = two.width },
    saveBox = { tw = two.width },
  }
end

-- Called from Game:load before the theme and the catalog are read: fills
-- Data.strings and Data.field.theme where a mod left them empty.  A no-op
-- in an English game.
function German.install(data, version)
  if not GameVersion.isGerman(version) then return false end
  local strings = data.strings
  if type(strings) ~= "table" then
    strings = {}
    data.strings = strings
  end
  for source, s in pairs(German.catalog(data, GameVersion.base(version))) do
    if strings[source] == nil then strings[source] = s end
  end
  data.field = data.field or {}
  local theme = data.field.theme
  if type(theme) ~= "table" then
    theme = {}
    data.field.theme = theme
  end
  for box, geometry in pairs(German.theme()) do
    local mine = theme[box]
    if type(mine) ~= "table" then
      mine = {}
      theme[box] = mine
    end
    for key, value in pairs(geometry) do
      if mine[key] == nil then mine[key] = value end
    end
  end
  installTypeNames(data)
  return true
end

-- The layout for a site: German.layout.<name> in a German game (Gelbe
-- Edition's own where it has one), else nil.
function German.layoutFor(name)
  if not GameVersion.isGerman() then return nil end
  local own = GameVersion.base() == "yellow" and German.layout.yellow[name]
  return own or German.layout[name]
end

return German
