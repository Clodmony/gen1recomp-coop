# German Red and Blue

The German Rote Edition and Blaue Edition are games of their own in this fork
(#25; design A15.6 and A15.7, decisions G7 and G12 in [design.md](design.md),
the sibling fork's D95 and D102). This page covers what runs today, how the
import works, how the engine's own lines come out German, and what is still
open.

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

## The engine's own lines (D102, decision G15)

Upstream keys every line the engine authors on its English source
(`src/core/Strings.lua`, `S("...")`) and already prints most battle, item
and field lines through the cartridge's own text labels
(`src/core/RomText.lua`), so a German import shows those in German by
itself. The rest, English in a German game before this, is filled at boot by
`src/coop/game/German.lua` into `Data.strings`, in three layers, each only
where the layer above has nothing:

1. **The cartridge's menu words** (`field.words`): the labelled `db "..."`
   strings the engine draws itself, which are not text labels: the START
   menu rows, the battle and Safari menus, YES/NO, the PC rows, the Pokédex
   side panel, the STATUS page's headings and short stat names, the SAVE
   panel, the three options the cartridge has, the naming titles. The
   generator (`tools/make_german_manifest.py`, `GERMAN_WORD_SYMBOLS`) puts
   each label's address into the German manifests and the list into
   `field.words`; `RomExtractor.germanField` reads each at import, rows
   newline-joined. `German.WORDS` maps an English source onto a label's row
   and word ("FIGHT" is the first word of `BattleMenuText`'s first row).
2. **The cartridge's text labels** (`Data.text`): lines upstream prints from
   a literal although the cartridge has the line, composed the way pokered
   prints them (an EXP gain is `_GainedText` + `_ExpPointsText`, a stat
   change `_MonsStatsRoseText` + `_RoseText`). The label's `{RAM:...}`,
   `{USER}`, `{NUM:...}` slots become numbered directives (`%2$s`) so the
   engine's arguments land where the German puts them; a slot the source
   spells the same (`{PLAYER}`, `{RAM:wNameBuffer}`) stays for TextBox; an
   argument the German has no slot for is consumed by a zero-width
   directive so `Strings` keeps the entry.
3. **The fork's own wording** (`German.PROJECT`): co-op lines, the engine's
   extra options, link play, a few prompts no cartridge has. Listed for the
   owner in [german-wording.md](german-wording.md), made by
   `luajit tools/game_strings.lua --markdown`.

A translation mod's entries win; `install()` fills only keys that are not
set. The same English word on a screen where the cartridge uses another
word carries a context (`Strings("QUIT", "pokedex")`, `"shop"`, `"status"`
for the short stat names, `"cableclub"`, `"options"`), small marked edits
in the upstream files. `luajit tools/game_strings.lua --missing` lists the
Gen 1 engine sources with no entry (none today), `--stale` the entries no
source uses; `tests/coop/german_strings_test.lua` fails on either.

The type names the STATUS page, the move box and the Hall of Fame draw come
from the import's `type_chart.names` (upstream keeps English constants and
reads a name only from a mod's type record): a German game gets a type
record per type with the cartridge's name, a mod's renamed type keeps its.

No German cartridge text is in the repository: the words and lines are
decoded from the player's cartridge at import. What is committed is the
list of labels, the English keys, and the fork's own wording.

## Layouts that follow the German cartridge

- **Title**: the 10-tile "ROTE EDITION" / "BLAUE EDITION" ribbon is drawn
  whole at column 6 (US: two pieces at column 7).
- **Copyright**: the intro card and the title line spell ©1995-1999 with the
  nine tile, as Yellow does (US: ©'95.'96.'98).
- **Credits**: E N D E at column 7 (US: T H E  E N D at column 4).
- **Pokédex**: metric sizes.
- **Two-option boxes**: the YES/NO rows are 5 wide, so every two-option box
  is 7 tiles wide and the shared right-hand one sits at column 13 (US 4,
  6 and 14); through `field.theme`, which `src/ui/Theme.lua` merges.
- **Battle menu**: the box from column 6, the words from 8, the right
  column at 13 (US 8, 10, 15); **Safari menu**: the right words at 13
  (US 14). The wide battle layout shifts its right column the same way.
- **SAVE and CONTINUE panels**: a column further left, labels at column 4
  (US 5).
- **Cable Club**: the cancel box 12 columns inside for ABBRECHEN (US 9).
- **Bill's PC**: the STATS/CANCEL box from column 8, a column wider; the
  other PC menus grow to their German rows by themselves (`Menu.new` widens
  to the widest label).

The constants are in `German.layout` (pokered-de at the manifest's pin,
constants only), read behind `GameVersion.isGerman()` with marked edits at
each site; nothing changes for the US games.

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
- Rote Edition again with the word-reading extractor, then a scripted run
  through: the START menu, the SAVE panel and its prompt with the 7-wide
  JA/NEIN box, the party menu and its STATUS/TAUSCH/ZURÜCK rows, both
  STATUS pages (short stat names, TYP1/ with the cartridge's type name,
  EP-PUNKTE, AP), the bag, the options groups, the Pokédex list with its
  side panel, a wild battle (the menu box from column 6, TYP/ in the move
  box, the cartridge's turn messages, an EXP gain composed from two labels),
  and the Safari menu.

`tests/coop/german_test.lua` checks the ids, the manifests (now with the
word labels), the German layouts and the word reading on a synthetic ROM
and the session's language rule without a ROM;
`tests/coop/german_strings_test.lua` the catalog's three layers, the
argument order, what a mod keeps, the German boxes, the type names, full
coverage of the engine's Gen 1 sources and the wording list.

Not run yet: the PC and the Cable Club in a German game, a save and reload,
a co-op session between two German players, Blaue Edition beyond its import.

## Still open

- The owner's review of the fork's wording in
  [german-wording.md](german-wording.md) (the "Better German" column).
- **Gelbe Edition** (#40): in reach the same way.
  [Brianum/pokeyellow-de](https://github.com/Brianum/pokeyellow-de) at
  `567aa893` builds the German Yellow dump
  (`42f3714eec6eca25200d42461ff08d57c98f6d1d`) byte for byte, and 4497 of
  the Yellow manifest's 4502 symbols resolve in it; the other five
  (`MewBaseStats` and four surfing minigame tilemaps) need their German
  names found.
