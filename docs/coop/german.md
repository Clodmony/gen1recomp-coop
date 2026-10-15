# German Red, Blue and Yellow

The German Rote, Blaue and Gelbe Edition are games of their own in this fork
(#25, #40; design A15.6 and A15.7, decisions G7, G12 and G16 in
[design.md](design.md), the sibling fork's D95 and D102). This page covers
what runs today, how the import works, how the engine's own lines come out
German, and what is still open.

## Game ids

| Id | Cartridge | Dump SHA-1 | Plays as | Cache | Save files |
|---|---|---|---|---|---|
| `red_de` | Pokemon - Rote Edition (Germany) (SGB Enhanced) | `87d523fe1a0c548db7c5477b451ddec1eb083c06` | `red` | `red_de/` | `save_red_de.lua` |
| `blue_de` | Pokemon - Blaue Edition (Germany) (SGB Enhanced) | `20e72dc6f41493eee1fdd0cef54214e6c3389688` | `blue` | `blue_de/` | `save_blue_de.lua` |
| `yellow_de` | Pokemon - Gelbe Edition - Special Pikachu Edition (Germany) (GBC,SGB Enhanced) | `42f3714eec6eca25200d42461ff08d57c98f6d1d` | `yellow` | `yellow_de/` | `save_yellow_de.lua` |

`GameVersion` gives each row a `base`, the US game it plays as, and a
`language`, `"de"`. `GameVersion.isBlue()` and `GameVersion.isYellow()`
answer for the base, so Blaue Edition takes Blue's branches (title Pokémon,
version-gated data) and Gelbe Edition Yellow's (the Pikachu title, the
Yellow intro, the follower, the Pikachu volume) with their own cartridge
data. `GameVersion.isGerman()` and `GameVersion.language()` are the checks
for German layouts.

Separate ids keep caches, saves, mod settings and sessions apart:

- The fork's launcher lists ROT, BLAU and GELB under the US games and
  imports any of the three dumps ([launcher.md](launcher.md)).
- A co-op host refuses a cartridge of another language before anything else,
  with `content_mismatch` ([session.md](session.md)). German Red with German
  Blue is #9's question, inside one language.
- A mod loads only in the games it lists. The German ids are not in
  upstream's `GameVersion.ORDER`, so a mod for `gen1` (or with no `games`
  key) means the US games: their mods carry English words.

## Import

The extractor (`src/import/RomExtractor.lua`) reads a cartridge through a
manifest of symbol addresses. The German manifests,
`tools/rom_manifest_red_de.json`, `tools/rom_manifest_blue_de.json` and
`tools/rom_manifest_yellow_de.json`, are derived from the US ones by
`tools/make_german_manifest.py`, as Blue's is derived from Red's:

- **Addresses**: every symbol the US manifest names, re-sourced from a build
  of the German disassembly that assembles the cartridge byte for byte:
  [einstein95/pokered-de](https://github.com/einstein95/pokered-de) at its
  master, `f6a2c0cdc557e4c8c1886743629341848ff5bc40`, for Rote and Blaue
  Edition (its `symbols` branch, 2022, uses pret's old label names, so the
  generator needs a fresh build);
  [Brianum/pokeyellow-de](https://github.com/Brianum/pokeyellow-de) at its
  master, `567aa8934ed0c86493982e607e4fffbcdf53d2de`, for Gelbe Edition.
- **Characters**: the German charmap (Ä Ö Ü ä ö ü ß and the accented
  letters) from its `constants/charmap.asm`.
- **Text substitutions**: the order of the RAM, BCD and number fields in each
  text, from its `text_ram`/`text_bcd`/`text_decimal` macros (four texts put
  them in another order than English).
- **Layout constants**: `language: "de"` and the credits' closing column
  (Red and Blue; Yellow draws no closing card, as US Yellow does not).
- **Yellow's renamed symbols**: pokeyellow-de predates two pret renames.
  Mew's stats are placed as the 151st `BaseStats` entry, as the US Yellow
  manifest places them. The surfing minigame's intro screen, which the US
  cartridge keeps as a beach, two lines and a title that the engine
  composes (`SurfingMinigame_BeachIntroTilemap` and three labels inside
  it), the German cartridge keeps as one 20×18 tilemap with its German
  lines in it: the manifest names it `SurfingMinigameIntroScreenTilemap`,
  the extractor reads it whole, and the four US labels are left out.
- **Yellow's copyright line**: Gelbe Edition spells ©1995-2000 from the
  first five tiles of its copyright graphics and a two-tile year ending
  under its own `NineTile` label (US Yellow: six tiles and the one nine
  tile the extractor finds by its distance from the GAME FREAK graphics),
  with GAME FREAK inc. at column 10. The manifest names `NineTile`, the
  extractor reads it by name as wide as `title.nine` says, and the title
  screen and the intro card draw `title.copyPrefix` and put GAME FREAK inc.
  at `title.gameFreakX` (marked edits in `src/ui/TitleState.lua` and
  `src/ui/IntroMovie.lua`).

Neither tree carries a licence, so both are used for addresses and
constants only; none of their asm, text, graphics or symbol files is copied.
All German words come from the player's cartridge at import. The US
manifests carry a few English words from pret's source; for German they are
empty and the extractor reads the cartridge's (`RomExtractor:germanField`):

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

Only needed when the US manifests or a pin change. In a scratch folder
outside the repository:

```bash
git clone https://github.com/gbdev/rgbds -b v1.0.1 && make -C rgbds
git clone https://github.com/einstein95/pokered-de
git -C pokered-de checkout f6a2c0cdc557e4c8c1886743629341848ff5bc40
PATH=$PWD/rgbds:$PATH make -C pokered-de pokered.gbc pokeblue.gbc
git clone https://github.com/Brianum/pokeyellow-de
git -C pokeyellow-de checkout 567aa8934ed0c86493982e607e4fffbcdf53d2de
RGBDS=$PWD/rgbds/ make -C pokeyellow-de pokeyellow.gbc   # SHA-1s as in the table
python3 <repo>/tools/make_german_manifest.py --pokered-de pokered-de --pokeyellow-de pokeyellow-de
```

Each tree flag is optional: the generator writes the manifests whose tree
it was given.

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
   generator (`tools/make_german_manifest.py`, `GERMAN_WORD_SYMBOLS` plus
   `RED_BLUE_WORD_SYMBOLS` or `YELLOW_WORD_SYMBOLS`) puts each label's
   address into the German manifests and the list into `field.words`;
   `RomExtractor.germanField` reads each at import, rows newline-joined.
   `German.WORDS` maps an English source onto a label's row and word
   ("FIGHT" is the first word of `BattleMenuText`'s first row). Where
   Gelbe Edition's cartridge differs, an entry carries a `yellow` variant
   (`German.variant`): its option screen names the options in one list
   (`AllOptionsText`) and keeps each value bracketed ("[ SCHNELL ]"), its
   Bill's PC and Pokédex menus carry a PRINT row (DRUCKEN, DRCK) that moves
   SEE YA! and QUIT a row down, its saving line is a text label
   (`_SavingText`) and its link-broken line sits under its Colosseum label.
   The catalog is built for the game's base (`German.catalog(data, base)`).
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
  Gelbe Edition keeps the blank run beside it where US Yellow has it
  (`German.layout.yellow`).
- **Bill's PC**: the STATS/CANCEL box from column 8, a column wider; the
  other PC menus grow to their German rows by themselves (`Menu.new` widens
  to the widest label).
- **Gelbe Edition** otherwise draws as Rote and Blaue do (pokeyellow-de has
  the same battle menu template, YES/NO rows, SAVE and CONTINUE panels and
  PC sub-menu box), its title has no version ribbon (as US Yellow), and its
  copyright line is the cartridge's ©1995-2000 (above). Yellow's own
  screens (the Pikachu title, the intro, the surfing minigame's title) come
  from its cartridge graphics and tilemaps as the US ones do.

The constants are in `German.layout` (pokered-de and pokeyellow-de at the
manifests' pins, constants only), read behind `GameVersion.isGerman()` with
marked edits at each site; nothing changes for the US games.

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

- Gelbe Edition (#40): the owner's dump imports through the fork's
  launcher's scripted import; a scripted run through the intro's copyright
  card and the title (GELBE EDITION, Pikachu, ©1995-2000 GAME FREAK inc.),
  the START menu, the SAVE panel and prompt, the party menu and both STATUS
  pages, the bag, the options, the Pokédex list with Yellow's five-row side
  panel (DATA, RUF, GEB., DRCK, ZUR.), a wild battle and the Safari menu;
  the German default names (GELB, ASH, JACK; BLAU, GARY, JOHN), the German
  trade nicknames, the credits in German, and the surfing minigame's title
  screen as the extractor reads it (Pikachus Strand, "Surfe mit dem
  Steuerkreuz!"). The US Yellow manifest is untouched; US Yellow was not
  imported again.

`tests/coop/german_test.lua` checks the ids, the manifests (with the word
labels, Yellow's renamed symbols and copyright layout), the German layouts
and the word reading on a synthetic ROM and the session's language rule
without a ROM; `tests/coop/german_strings_test.lua` the catalog's three
layers and Yellow's variants, the argument order, what a mod keeps, the
German boxes, the type names, full coverage of the engine's Gen 1 sources
and the wording list.

Not run yet: the PC and the Cable Club in a German game, a save and reload,
a co-op session between two German players, Blaue Edition beyond its
import, Gelbe Edition's surfing minigame and Pikachu scenes in play.

## Still open

- The owner's review of the fork's wording in
  [german-wording.md](german-wording.md) (the "Better German" column).
- Upstream's union room trade paths (`src/online/Trade.lua`,
  `src/online/union/TradeTxn.lua`) check for the US Yellow id; a traded
  Pikachu's happiness is not touched in Gelbe Edition there. The co-op
  session does not use them.
