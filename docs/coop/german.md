# German Red and Blue

The German Rote Edition and Blaue Edition are games of their own in this fork
(#25; design A15.6 and A15.7, decisions G7 and G12 in [design.md](design.md),
the sibling fork's D95 and D102). This page covers what runs today, how the
import works and what is still open.

## Game ids

| Id | Cartridge | Dump SHA-1 | Plays as | Cache | Save files |
|---|---|---|---|---|---|
| `red_de` | Pokemon - Rote Edition (Germany) (SGB Enhanced) | `87d523fe1a0c548db7c5477b451ddec1eb083c06` | `red` | `red_de/` | `save_red_de.lua` |
| `blue_de` | Pokemon - Blaue Edition (Germany) (SGB Enhanced) | `20e72dc6f41493eee1fdd0cef54214e6c3389688` | `blue` | `blue_de/` | `save_blue_de.lua` |

`GameVersion` gives each row a `base`, the US game it plays as, and a
`language`, `"de"`. `GameVersion.isBlue()` answers for the base, so Blaue
Edition takes Blue's branches (title Pokémon, version-gated data) with its
own cartridge data. `GameVersion.isGerman()` and `GameVersion.language()`
are the checks for German layouts.

Separate ids keep caches, saves, mod settings and sessions apart:

- The fork's launcher lists ROT (DE) and BLAU (DE) under the US games and
  imports either dump ([launcher.md](launcher.md)).
- A co-op host refuses a cartridge of another language before anything else,
  with `content_mismatch` ([session.md](session.md)). German Red with German
  Blue is #9's question, inside one language.
- A mod loads only in the games it lists. The German ids are not in
  upstream's `GameVersion.ORDER`, so a mod for `gen1` (or with no `games`
  key) means the US games: their mods carry English words.

## Import

The extractor (`src/import/RomExtractor.lua`) reads a cartridge through a
manifest of symbol addresses. The German manifests,
`tools/rom_manifest_red_de.json` and `tools/rom_manifest_blue_de.json`, are
derived from the US ones by `tools/make_german_manifest.py`, as Blue's is
derived from Red's:

- **Addresses**: every symbol the US manifest names, re-sourced from a build
  of [einstein95/pokered-de](https://github.com/einstein95/pokered-de) at its
  master, `f6a2c0cdc557e4c8c1886743629341848ff5bc40`, which assembles both
  German cartridges byte for byte. Its `symbols` branch (2022) uses pret's
  old label names, so the generator needs a fresh build.
- **Characters**: the German charmap (Ä Ö Ü ä ö ü ß and the accented
  letters) from its `constants/charmap.asm`.
- **Text substitutions**: the order of the RAM, BCD and number fields in each
  text, from its `text_ram`/`text_bcd`/`text_decimal` macros (four texts put
  them in another order than English).
- **Layout constants**: `language: "de"` and the credits' closing column.

pokered-de carries no licence, so it is used for addresses and constants
only; none of its asm, text, graphics or symbol files is copied. All German
words come from the player's cartridge at import. The US manifests carry a
few English words from pret's source; for German they are empty and the
extractor reads the cartridge's (`RomExtractor:germanField`):

- the naming-screen presets, whose first names also become the default
  player and rival names;
- the in-game trade nicknames (`TradeMons`);
- the credits roll, which names the European staff (`CreditsOrder`,
  `CreditsTextPointers`, `CreditsMons`), and its closing E N D E
  (`TheEndTextString`).

Pokédex entries are metric in German: one height byte in decimetres and the
weight in 100 g. The extractor stores them as `heightM` and `weightKg`, which
upstream's `DexEntryMenu` already draws in metres and kilograms, and fills
the imperial fields the mod schema requires with the same sizes converted.

### Regenerating the manifests

Only needed when the US manifests or the pin change. In a scratch folder
outside the repository:

```bash
git clone https://github.com/gbdev/rgbds -b v1.0.1 && make -C rgbds
git clone https://github.com/einstein95/pokered-de
cd pokered-de && git checkout f6a2c0cdc557e4c8c1886743629341848ff5bc40
PATH=../rgbds:$PATH make pokered.gbc pokeblue.gbc   # SHA-1s as in the table
python3 <repo>/tools/make_german_manifest.py --pokered-de .
```

## Layouts that follow the German cartridge

- **Title**: the 10-tile "ROTE EDITION" / "BLAUE EDITION" ribbon is drawn
  whole at column 6 (US: two pieces at column 7).
- **Copyright**: the intro card and the title line spell ©1995-1999 with the
  nine tile, as Yellow does (US: ©'95.'96.'98).
- **Credits**: E N D E at column 7 (US: T H E  E N D at column 4).
- **Pokédex**: metric sizes.

## Checked

Run locally with the owner's dumps (never committed), in a private save
folder that was deleted afterwards:

- both dumps import through the fork's launcher's scripted import;
- Rote Edition: intro copyright card, title, Oak's speech in German, the
  bedroom and Pallet Town, the START menu, a Pokédex entry (German name and
  kind, metric size, umlauts and ß in the entry text), the credits roll in
  German and its E N D E; the German default names;
- Blaue Edition: the title (its ribbon, and Blue's title Pokémon);
- US Red still imports with the changed extractor.

`tests/coop/german_test.lua` checks the ids, the manifests, the German
layouts on a synthetic ROM and the session's language rule without a ROM.

Not run yet: a German game through a battle, the bag, the PC, a save and
reload, a co-op session between two German players.

## Still open in #25

- **Engine wording (D102)**: the engine's own lines are English in a German
  game: menus (POKéMON, ITEM, SAVE, OPTION), battle messages, the bag, the
  PC, co-op lines. Upstream routes them through `Strings` (`S(...)`), a
  catalog keyed by the English source; German needs a catalog that takes
  the cartridge's words where the cartridge has the line and project German
  for the rest, listed for the owner (german-wording.md).
- **Menu layouts** the German cartridge changed: the SAVE box, the wider
  JA/NEIN box, the battle and Safari menu columns, the PC boxes, the Cable
  Club box.
- **Gelbe Edition**: in reach the same way.
  [Brianum/pokeyellow-de](https://github.com/Brianum/pokeyellow-de) at
  `567aa893` builds the German Yellow dump
  (`42f3714eec6eca25200d42461ff08d57c98f6d1d`) byte for byte, and 4497 of
  the Yellow manifest's 4502 symbols resolve in it; the other five
  (`MewBaseStats` and four surfing minigame tilemaps) need their German
  names found.
