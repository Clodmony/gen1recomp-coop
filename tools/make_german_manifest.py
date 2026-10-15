#!/usr/bin/env python3
"""Derive the German Red and Blue import manifests (co-op, #25).

Rote Edition and Blaue Edition are the US games translated: the same maps,
scripts, trainers and labels, with German text and a German character set.
The shipped US manifest therefore carries everything structural already;
this derives the German ones from it, as make_blue_manifest.py derives Blue
from Red, and overrides only what the language changes:

  * romSha1     -- the German dump's hash.
  * symbols     -- every symbol the US manifest names, re-sourced from a
                   build of einstein95/pokered-de (pinned below), which
                   assembles both German cartridges byte for byte.  The
                   German text is longer, so almost every address moves.
  * charmap, fontCharmap -- the German character codes (Ä Ö Ü ä ö ü ß and
                   the accented letters), from its constants/charmap.asm.
  * text.dynamic -- the order of the RAM, BCD and number substitutions in
                   each text, from its text_ram/text_bcd/text_decimal
                   macros: German sentences put them in a different order.
  * language    -- "de", which makes RomExtractor read the German layouts
                   (metric #DEX entries, the field words below).

Build pokered-de with rgbds 1.0.1 (`make pokered.gbc pokeblue.gbc`; the
hashes match the owner's dumps), then run this with --pokered-de pointing at
it.  docs/coop/german.md has the steps.

pokered-de carries no licence, so it is used like the pinned pret/pokered:
for addresses and constants only.  Nothing of its asm, text, graphics or
symbol files goes into the project; the German words themselves are decoded
from the player's own cartridge at import.  The US fields that hold English
words from pret's source (preset names, credits, trade nicknames) are
cleared here and read from the cartridge by RomExtractor instead.
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

GERMAN = {
    "red_de": {
        "base": os.path.join(TOOLS, "rom_manifest.json"),
        "out": os.path.join(TOOLS, "rom_manifest_red_de.json"),
        "sha1": "87d523fe1a0c548db7c5477b451ddec1eb083c06",
        "sym": "pokered.sym",
    },
    "blue_de": {
        "base": os.path.join(TOOLS, "rom_manifest_blue.json"),
        "out": os.path.join(TOOLS, "rom_manifest_blue_de.json"),
        "sha1": "20e72dc6f41493eee1fdd0cef54214e6c3389688",
        "sym": "pokeblue.sym",
    },
}


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
# strings, newline-joined.
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
    "CableClubOptionsText", "SaveScreenInfoText", "TextSpeedOptionText",
    "BattleAnimationOptionText", "BattleStyleOptionText",
    "OptionMenuCancelText", "NowSavingString", "BoxNoText",
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


def _variable(token):
    """'{NUM:wAmountMoneyWon, $c3}' -> 'wAmountMoneyWon'."""
    return token.strip("{}").split(":", 1)[-1].split(",", 1)[0].strip()


def derive(base, pokered_de, symbols_path, sha1, the_end):
    """Return a German manifest derived from a US manifest dict."""
    out = copy.deepcopy(base)
    out["romSha1"] = sha1
    # RomExtractor reads the German layouts (metric Pokédex, ...) by this.
    out["language"] = "de"

    symbols = SymbolTable(symbols_path)
    resolved, missing = {}, []
    for name in base["symbols"]:
        symbol = symbols.by_name.get(name)
        if symbol is None:
            missing.append(name)
            continue
        resolved[name] = [symbol.bank, symbol.address]
    if missing:
        raise SystemExit(
            f"{os.path.basename(symbols_path)} is missing symbols the "
            "manifest needs: " + ", ".join(sorted(missing)[:10])
            + (" ..." if len(missing) > 10 else ""))
    out["symbols"] = resolved

    out["charmap"] = charmap(pokered_de)
    out["fontCharmap"] = font.parse_charmap(pokered_de)

    # German order; a token keeps the US spelling of the same variable, the
    # one the engine's substitutions are written against.
    dynamic = text_metadata(pokered_de)["dynamic"]
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
    words = []
    for entry in GERMAN_WORD_SYMBOLS:
        name = entry[0] if isinstance(entry, tuple) else entry
        symbol = symbols.by_name.get(name)
        if symbol is None:
            raise SystemExit(f"{os.path.basename(symbols_path)} has no {name}")
        out["symbols"][name] = [symbol.bank, symbol.address]
        words.append(list(entry) if isinstance(entry, tuple) else entry)
    out["field"]["words"] = words
    out["field"]["presetNames"] = None
    out["field"]["credits"]["screens"] = None
    # Blue's US manifest has no theEnd entry; both German carts get Red's
    # (the same TheEndGfx sheet), with the pattern read from the cartridge.
    the_end = copy.deepcopy(the_end)
    the_end.update({"column": THE_END_COLUMN, "pattern": None, "display": None})
    out["field"]["credits"]["theEnd"] = the_end
    for trade in out["field"]["trades"]:
        trade["nickname"] = None
    return out


def check_revision(pokered_de, allow_mismatch):
    try:
        actual = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=pokered_de, check=True,
            capture_output=True, text=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return
    if actual != POKERED_DE_REVISION and not allow_mismatch:
        raise SystemExit(
            f"{pokered_de} is at {actual}, but this generator is pinned to "
            f"{POKERED_DE_REVISION}; pass --allow-revision-mismatch to "
            "generate anyway and diff the result.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pokered-de", required=True,
                        help="einstein95/pokered-de checkout, built")
    parser.add_argument("--version", choices=sorted(GERMAN), action="append",
                        help="which manifest to write (default: both)")
    parser.add_argument("--allow-revision-mismatch", action="store_true")
    args = parser.parse_args()

    pokered_de = os.path.abspath(args.pokered_de)
    if not os.path.isfile(os.path.join(pokered_de, "main.asm")):
        raise SystemExit(f"{pokered_de} is not a pokered-de checkout")
    check_revision(pokered_de, args.allow_revision_mismatch)
    with open(GERMAN["red_de"]["base"], encoding="utf-8") as f:
        red = json.load(f)
    for version in args.version or sorted(GERMAN):
        spec = GERMAN[version]
        with open(spec["base"], encoding="utf-8") as f:
            base = json.load(f)
        data = derive(base, pokered_de,
                      os.path.join(pokered_de, spec["sym"]), spec["sha1"],
                      red["field"]["credits"]["theEnd"])
        with open(spec["out"], "w", encoding="utf-8", newline="\n") as f:
            json.dump(data, f, ensure_ascii=True, indent=2, sort_keys=True)
            f.write("\n")
        print(f"wrote {spec['out']}")


if __name__ == "__main__":
    main()
