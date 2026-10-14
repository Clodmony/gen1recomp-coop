#!/usr/bin/env python3
"""Derive the German Red, Blue and Yellow import manifests (co-op, #25, #40).

Rote, Blaue and Gelbe Edition are the US games translated: the same maps,
scripts, trainers and labels, with German text and a German character set.
The shipped US manifests therefore carry everything structural already;
this derives the German ones from them, as make_blue_manifest.py derives
Blue from Red, and overrides only what the language changes:

  * romSha1     -- the German dump's hash.
  * symbols     -- every symbol the US manifest names, re-sourced from a
                   build of einstein95/pokered-de (Red and Blue) or
                   Brianum/pokeyellow-de (Yellow), pinned below, which
                   assemble the German cartridges byte for byte.  The
                   German text is longer, so almost every address moves.
  * charmap, fontCharmap -- the German character codes (Ä Ö Ü ä ö ü ß and
                   the accented letters), from its constants/charmap.asm.
  * text.dynamic -- the order of the RAM, BCD and number substitutions in
                   each text, from its text_ram/text_bcd/text_decimal
                   macros: German sentences put them in a different order.
  * language    -- "de", which makes RomExtractor read the German layouts
                   (metric #DEX entries, the field words below).

Build pokered-de with rgbds 1.0.1 (`make pokered.gbc pokeblue.gbc`) and
pokeyellow-de (`make pokeyellow.gbc`; the hashes match the owner's dumps),
then run this with --pokered-de and --pokeyellow-de pointing at them.
docs/coop/german.md has the steps.

Neither tree carries a licence, so both are used like the pinned
pret/pokered: for addresses and constants only.  Nothing of their asm, text,
graphics or symbol files goes into the project; the German words themselves
are decoded from the player's own cartridge at import.  The US fields that
hold English words from pret's source (preset names, credits, trade
nicknames) are cleared here and read from the cartridge by RomExtractor
instead.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from extract import font  # noqa: E402
from make_rom_manifest import charmap, text_metadata  # noqa: E402
from rom_data import SymbolTable  # noqa: E402

TOOLS = os.path.dirname(os.path.abspath(__file__))

# einstein95/pokered-de master; its `symbols` branch is older (2022) and
# uses pret's old label names, so build this revision (rgbds 1.0.1) and pass
# its pokered.sym / pokeblue.sym.
POKERED_DE_REVISION = "f6a2c0cdc557e4c8c1886743629341848ff5bc40"
# Brianum/pokeyellow-de master (#40): builds the Gelbe Edition dump byte for
# byte with rgbds 1.0.1.  It predates two pret renames, resolved below
# (YELLOW_RENAMED).
POKEYELLOW_DE_REVISION = "567aa8934ed0c86493982e607e4fffbcdf53d2de"

# The German trees: the command line flag naming each checkout and its pin.
TREES = {
    "pokered-de": {"flag": "pokered_de", "revision": POKERED_DE_REVISION},
    "pokeyellow-de": {"flag": "pokeyellow_de", "revision": POKEYELLOW_DE_REVISION},
}

GERMAN = {
    "red_de": {
        "base": os.path.join(TOOLS, "rom_manifest.json"),
        "out": os.path.join(TOOLS, "rom_manifest_red_de.json"),
        "sha1": "87d523fe1a0c548db7c5477b451ddec1eb083c06",
        "tree": "pokered-de",
        "sym": "pokered.sym",
    },
    "blue_de": {
        "base": os.path.join(TOOLS, "rom_manifest_blue.json"),
        "out": os.path.join(TOOLS, "rom_manifest_blue_de.json"),
        "sha1": "20e72dc6f41493eee1fdd0cef54214e6c3389688",
        "tree": "pokered-de",
        "sym": "pokeblue.sym",
    },
    "yellow_de": {
        "base": os.path.join(TOOLS, "rom_manifest_yellow.json"),
        "out": os.path.join(TOOLS, "rom_manifest_yellow_de.json"),
        "sha1": "42f3714eec6eca25200d42461ff08d57c98f6d1d",
        "tree": "pokeyellow-de",
        "sym": "pokeyellow.sym",
    },
}

# pokeyellow-de at its pin names two things differently from pret's
# pokeyellow, which the US Yellow manifest follows (make_yellow_manifest.py):
#   * Mew's base stats are the 151st BaseStats entry (pret pokeyellow has no
#     MewBaseStats label either; the US manifest synthesises it the same way);
#   * the surfing minigame's intro screen is one 360-byte tilemap,
#     Tilemap_3e_5063 (gfx/surfing_pikachu/unknown_3e_5063.tilemap), which
#     pret later split into SurfingMinigame_BeachIntroTilemap and three
#     labels inside it.  The German tilemap has the US layout (checked on the
#     owner's dump: the Pikachu's Beach title the extractor composes), so the
#     US offsets inside the intro tilemap apply.
BASE_STATS_ENTRY_SIZE = 28
MEW_DEX_NUMBER = 151
YELLOW_INTRO_TILEMAP = "Tilemap_3e_5063"
SURFING_TILEMAPS = (
    "SurfingMinigame_BeachIntroTilemap", "SurfingMinigame_TitleTilemap",
    "SurfingMinigame_ToSurfRadTilemap", "SurfingMinigame_UseControlPadTilemap",
)


GERMAN_FIELD_SYMBOLS = (
    "DefaultNamesPlayerList", "DefaultNamesRivalList", "TradeMons",
    "CreditsOrder", "CreditsTextPointers", "CreditsMons", "TheEndTextString",
)

# pokered-de engine/movie/credits.asm: `hlcoord 7, 9` before
# TheEndTextString (US: 4), the four-letter E N D E.
THE_END_COLUMN = 7

# The cartridge's menu words (#25, D102): the labelled `db "..."` strings
# the engine draws itself (menu rows, box headings, the option names), which
# are not text labels and so not in `text.labels`.  RomExtractor.germanField
# reads each as one `@`-terminated string (rows joined by newlines) into
# field.words, keyed by label; src/coop/game/German.lua maps the engine's
# English sources onto them.  A pair (label, n) reads n consecutive
# strings, newline-joined.  These all three cartridges have under one name
# (a row may differ: Yellow's Bill's PC and Pokédex menus carry a PRINT row).
GERMAN_WORD_SYMBOLS = (
    # data/text_boxes.asm, data/yes_no_menu_strings.asm
    "BattleMenuText", "SafariZoneBattleMenuText", "SwitchStatsCancelText",
    "BuySellQuitText", "UseTossText", "MoneyText",
    "TwoOptionMenuStrings.YesNoMenu", "TwoOptionMenuStrings.NoYesMenu",
    "TwoOptionMenuStrings.TradeCancelMenu", "TwoOptionMenuStrings.HealCancelMenu",
    # engine/battle/core.asm, end_of_battle.asm, data/battle/stat_mod_names.asm
    "WhichTechniqueString", "DisabledText", "TypeText",
    "YouWinText", "YouLoseText", "DrawText", ("StatModTextStrings", 6),
    # engine/menus/draw_start_menu.asm, main_menu.asm, save.asm
    "StartMenuPokedexText", "StartMenuPokemonText", "StartMenuItemText",
    "StartMenuSaveText", "StartMenuResetText", "StartMenuExitText",
    "StartMenuOptionText", "ContinueText", "NewGameText",
    "SaveScreenInfoText", "OptionMenuCancelText", "BoxNoText",
    # engine/menus/text_box.asm, players_pc.asm, engine/pokemon/bills_pc.asm
    "PokemonMenuEntries", "PlayersPCMenuEntries", "BillsPCMenuText",
    "DepositPCText", "WithdrawPCText", "StatsCancelPCText",
    "SomeonesPCText", "BillsPCText", "PlayersPCText", "OaksPCText",
    "PKMNLeaguePCText", "LogOffPCText",
    # engine/menus/naming_screen.asm, pokedex.asm, start_sub_menus.asm
    "YourTextString", "RivalsTextString", "NameTextString",
    "NicknameTextString", "PokedexSeenText", "PokedexOwnText",
    "PokedexContentsText", "PokedexMenuItemsText",
    "TrainerInfo_NameMoneyTimeText",
    # engine/pokemon/status_screen.asm, engine/movie/hall_of_fame.asm,
    # engine/menus/league_pc.asm, engine/events/diploma.asm, prize_menu.asm
    "TypesIDNoOTText", "StatusText", "PrintStatsBox.StatsText",
    "StatusScreenExpText", "HallOfFameText", "HoFMonInfoText",
    "HoFPlayTimeText", "HoFMoneyText", "HallOfFameNoText",
    "DiplomaCongrats", "PrintPrizePrice.CoinString",
    # engine/items/town_map.asm, engine/link/cable_club.asm,
    # print_waiting_text.asm, home/list_menu.asm, home/text.asm
    "MonsNestText", "AreaUnknownText", "CancelTextString", "TradeCanceled",
    "WaitingText", "PleaseWaitString", "ListMenuCancelText",
    "TrainerCharText", "EnemyText",
)

# ..the ones Red and Blue have and Yellow names otherwise: the three options
# of the US option screen with their values, the link menu, the saving line
RED_BLUE_WORD_SYMBOLS = (
    "CableClubOptionsText", "TextSpeedOptionText", "BattleAnimationOptionText",
    "BattleStyleOptionText", "NowSavingString",
)
# ..and Yellow's own: its option screen names the options in one list
# (engine/menus/options.asm AllOptionsText) and keeps each value as its own
# bracketed string; its link menu is TradeCenterText (engine/menus/
# link_menu.asm).  Its saving line is a text label (_SavingText), read with
# the other texts.
YELLOW_WORD_SYMBOLS = (
    "AllOptionsText",
    "OptionsMenu_TextSpeed.Fast", "OptionsMenu_TextSpeed.Mid",
    "OptionsMenu_TextSpeed.Slow",
    "OptionsMenu_BattleAnimations.On", "OptionsMenu_BattleAnimations.Off",
    "OptionsMenu_BattleStyle.Shift", "OptionsMenu_BattleStyle.Set",
    "TradeCenterText",
)


def _variable(token):
    """'{NUM:wAmountMoneyWon, $c3}' -> 'wAmountMoneyWon'."""
    return token.strip("{}").split(":", 1)[-1].split(",", 1)[0].strip()


def yellow_renamed(base, symbols):
    """The US Yellow symbols pokeyellow-de has under other names."""
    stats = symbols.by_name.get("BaseStats")
    intro = symbols.by_name.get(YELLOW_INTRO_TILEMAP)
    if stats is None or intro is None:
        raise SystemExit("pokeyellow.sym has no BaseStats or no "
                         + YELLOW_INTRO_TILEMAP)
    out = {"MewBaseStats": [
        stats.bank,
        stats.address + (MEW_DEX_NUMBER - 1) * BASE_STATS_ENTRY_SIZE]}
    us_intro = base["symbols"][SURFING_TILEMAPS[0]]
    for name in SURFING_TILEMAPS:
        us = base["symbols"][name]
        if us[0] != us_intro[0] or not 0 <= us[1] - us_intro[1] < 360:
            raise SystemExit(f"{name} is not inside the US intro tilemap")
        out[name] = [intro.bank, intro.address + us[1] - us_intro[1]]
    return out


def derive(base, tree, symbols_path, sha1, the_end, words, renamed=None):
    """Return a German manifest derived from a US manifest dict.

    `tree` is the German source checkout, `words` the menu word labels this
    cartridge has (GERMAN_WORD_SYMBOLS plus its own), `the_end` Red's
    credits.theEnd entry or None, `renamed` a resolver for the symbols the
    tree names otherwise (yellow_renamed)."""
    out = copy.deepcopy(base)
    out["romSha1"] = sha1
    # RomExtractor reads the German layouts (metric Pokédex, ...) by this.
    out["language"] = "de"

    symbols = SymbolTable(symbols_path)
    other = renamed(base, symbols) if renamed else {}
    resolved, missing = {}, []
    for name in base["symbols"]:
        symbol = symbols.by_name.get(name)
        if symbol is None:
            if name in other:
                resolved[name] = other[name]
            else:
                missing.append(name)
            continue
        resolved[name] = [symbol.bank, symbol.address]
    if missing:
        raise SystemExit(
            f"{os.path.basename(symbols_path)} is missing symbols the "
            "manifest needs: " + ", ".join(sorted(missing)[:10])
            + (" ..." if len(missing) > 10 else ""))
    out["symbols"] = resolved

    out["charmap"] = charmap(tree)
    out["fontCharmap"] = font.parse_charmap(tree)

    # German order; a token keeps the US spelling of the same variable, the
    # one the engine's substitutions are written against.
    dynamic = text_metadata(tree)["dynamic"]
    labels = set(base["text"]["labels"])
    us_dynamic = base["text"]["dynamic"]
    out["text"]["dynamic"] = {}
    for label, tokens in dynamic.items():
        if label not in labels:
            continue
        spelled = {
            (command, _variable(token)): token
            for command, token in us_dynamic.get(label, [])}
        out["text"]["dynamic"][label] = [
            [command, spelled.get((command, _variable(token)), token)]
            for command, token in tokens]

    # The cartridge's words: RomExtractor.germanField reads these tables.
    for name in GERMAN_FIELD_SYMBOLS:
        symbol = symbols.by_name.get(name)
        if symbol is None:
            raise SystemExit(f"{os.path.basename(symbols_path)} has no {name}")
        out["symbols"][name] = [symbol.bank, symbol.address]
    # ..and its menu words, read by label into field.words at import.
    listed = []
    for entry in words:
        name = entry[0] if isinstance(entry, tuple) else entry
        symbol = symbols.by_name.get(name)
        if symbol is None:
            raise SystemExit(f"{os.path.basename(symbols_path)} has no {name}")
        out["symbols"][name] = [symbol.bank, symbol.address]
        listed.append(list(entry) if isinstance(entry, tuple) else entry)
    out["field"]["words"] = listed
    out["field"]["presetNames"] = None
    out["field"]["credits"]["screens"] = None
    # Blue's US manifest has no theEnd entry; both German Red and Blue get
    # Red's (the same TheEndGfx sheet), with the pattern read from the
    # cartridge.  US Yellow draws no closing card in this engine, so neither
    # does Gelbe Edition (the_end is None).
    if the_end is not None:
        the_end = copy.deepcopy(the_end)
        the_end.update({"column": THE_END_COLUMN, "pattern": None, "display": None})
        out["field"]["credits"]["theEnd"] = the_end
    for trade in out["field"]["trades"]:
        trade["nickname"] = None
    return out


def check_revision(tree, revision, allow_mismatch):
    try:
        actual = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=tree, check=True,
            capture_output=True, text=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return
    if actual != revision and not allow_mismatch:
        raise SystemExit(
            f"{tree} is at {actual}, but this generator is pinned to "
            f"{revision}; pass --allow-revision-mismatch to "
            "generate anyway and diff the result.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pokered-de",
                        help="einstein95/pokered-de checkout, built (red_de, blue_de)")
    parser.add_argument("--pokeyellow-de",
                        help="Brianum/pokeyellow-de checkout, built (yellow_de)")
    parser.add_argument("--version", choices=sorted(GERMAN), action="append",
                        help="which manifest to write (default: every one "
                             "whose tree is given)")
    parser.add_argument("--allow-revision-mismatch", action="store_true")
    args = parser.parse_args()

    trees = {}
    for name, tree in TREES.items():
        path = getattr(args, tree["flag"])
        if path is None:
            continue
        path = os.path.abspath(path)
        if not os.path.isfile(os.path.join(path, "main.asm")):
            raise SystemExit(f"{path} is not a {name} checkout")
        check_revision(path, tree["revision"], args.allow_revision_mismatch)
        trees[name] = path
    if not trees:
        parser.error("give --pokered-de and/or --pokeyellow-de")
    versions = args.version or [
        v for v in sorted(GERMAN) if GERMAN[v]["tree"] in trees]
    with open(GERMAN["red_de"]["base"], encoding="utf-8") as f:
        red = json.load(f)
    for version in versions:
        spec = GERMAN[version]
        tree = trees.get(spec["tree"])
        if tree is None:
            raise SystemExit(f"{version} needs --{spec['tree']}")
        yellow = version == "yellow_de"
        with open(spec["base"], encoding="utf-8") as f:
            base = json.load(f)
        data = derive(
            base, tree, os.path.join(tree, spec["sym"]), spec["sha1"],
            None if yellow else red["field"]["credits"]["theEnd"],
            GERMAN_WORD_SYMBOLS + (YELLOW_WORD_SYMBOLS if yellow else RED_BLUE_WORD_SYMBOLS),
            yellow_renamed if yellow else None)
        with open(spec["out"], "w", encoding="utf-8", newline="\n") as f:
            json.dump(data, f, ensure_ascii=True, indent=2, sort_keys=True)
            f.write("\n")
        print(f"wrote {spec['out']}")


if __name__ == "__main__":
    main()
