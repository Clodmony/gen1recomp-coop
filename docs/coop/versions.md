# Red and Blue in one campaign

Red and Blue players share one co-op campaign, each on their own cartridge,
and a campaign can let the other version's wild Pokémon into every world
(#9, area A13 in [design.md](design.md), decision G33, the sibling fork's
D101 and D104). Yellow plays with Yellow only (G4); what mixing it would take
is in design A13.

## Files

- `src/coop/session/Versions.lua`: which cartridges play together (the pair
  rule), shared by the host and the launcher.
- `src/coop/session/Host.lua`: the join check (`cartridgeFits`), the wild
  tables in memory, the version it waits for (`wildWaiting`).
- `src/coop/game/WildMix.lua`: the window's side of "wild Pokémon from both
  versions": its own tables to send, the encounter rule.
- Marked hooks in upstream files: `Encounter.roll` names the slot it picked,
  `OverworldState:rollEncounter` hands its encounter to `WildMix.encounter`.
- The launcher (`src/coop/launcher/CoopMenu.lua`, `Screens.lua`) and the
  campaign card (`src/coop/Campaigns.lua`, `mix`).

## Which cartridges play together

Red and Blue are one game in two cartridges. Compared by the fork's own
extraction of the US dumps, their species, moves, items, type chart,
trainers, trainer headers and texts are the same; the maps and tilesets
differ only in the ROM addresses their headers were read from. What
differs: the wild tables (the version exclusives), the palettes of the
title logo and the slot machines, the credits' title and the name presets. The Game Corner's prizes are the engine's
by version.

So a host lets in (`Versions.misfit`):

| The joining cartridge | Result | The host's log (`misfit`) |
|---|---|---|
| the host's game and dump | joins | |
| the other game of the pair (Red with Blue, Rot with Blau), both verified dumps | joins | |
| another language (Blau with Red) | `content_mismatch` | `language` |
| another dump of the same game, or of the pair when either dump is not a verified one (a hack, an unknown revision) | `content_mismatch` | `dump` |
| a game that never plays with the host's (Yellow with Red) | `content_mismatch` | `game` |

A verified dump is one the import accepts for that game
(`GameVersion.acceptsSha1`). The launcher names the refusal from the probe's
lobby: "The host plays YELLOW. This game is RED. YELLOW plays with YELLOW
only.", "RED and BLUE play together only from verified dumps. One of the two
ROMs is another dump.", or the language sentence of #25.

**The campaign stays the host's game.** Its file is
`coop/campaigns/<game>/<id>.campaign` of the game it was started on, and each
player keeps their own `game` in it. Each window runs its own cartridge: its
world, its wild tables, Game Corner and in-game trades, its title.

**Battles use only what both share.** A co-op battle's record (G24) carries
the opening (the enemies as packed Pokémon: species, level, moves, DVs), the
seed, the teams and the commands. Each window plays it with its own
cartridge's species, moves, items and type chart, which are the same in Red
and Blue, so a Red and a Blue window play the same battle. A wild battle
against a Blue exclusive opened by a Blue window is played by a Red window
from the record's species, like any other.

**Version exclusives cross by trading**, as between the real cartridges:
friend trades and the Cable Club are #23 and #60.

**A Blue cartridge hosts a Red campaign.** Choose your campaign lists the
campaigns of both games of the pair; HOST takes the campaign's own game when
it is imported here, else the other of the pair. The file stays in the
campaign's game's folder.

**Split-screen** plays one cartridge on one device: seat 2's game shares the
process's version and cartridge cache (`GameVersion` and `src.import.*` are
one per process, [split.md](split.md)), so both seats play the cartridge
player 1 picked. A Red and a Blue player cannot share one device; a
split-screen pair on Blue joins a Red host like any Blue player. No screen
offers a second cartridge for seat 2, so there is nothing to refuse.

## Wild Pokémon from both versions

A per-campaign switch, off by default: NEW CAMPAIGN's WILD POKéMON row
(THIS VERSION ONLY or BOTH VERSIONS) and the campaign's card (BOTH VERSIONS:
ON or OFF), so it can be changed later; it takes effect the next time the
campaign is hosted. The card keeps it (`mix`). Only games with a pair have
it.

**The rule** (A13.3). On every wild encounter the world draws (grass, a
cave's floor, water while surfing), the window looks up the other version's
Pokémon in the same map and slot. When that Pokémon is one the window's own
version never has in its grass or water tables, a third number is drawn from
the world's own generator (`love.math.random(0, 255)`); 128 or more takes the
other version's Pokémon, at this cartridge's level for the slot. So the
other version's wild exclusives come in, each taking half of its slot:

| A Red world gets | A Blue world gets |
|---|---|
| SANDSHREW, SANDSLASH, BELLSPROUT, WEEPINBELL, MEOWTH, VULPIX, MAGMAR, PINSIR, KRABBY, KINGLER | EKANS, ARBOK, ODDISH, GLOOM, MANKEY, GROWLITHE, ELECTABUZZ, SCYTHER, HORSEA, SEADRA |

A shared slot, a slot that only shuffles shared Pokémon (Route 22's
NIDORAN), and a map the other version has no table for keep the cartridge's
encounter and draw nothing more. The level is the cartridge's: one slot
differs in level between the two (the Mansion's B1F slot 9, WEEZING at 42 in
Red, MAGMAR at 38 in Blue), so a Red world meets that MAGMAR at 42. The rule
looks up by map and slot, never by species and level (two slots can share
both). Fishing, the Game Corner's prizes and in-game trades stay each
player's own version.

**No cartridge data is shipped or stored** (A13.4). Each window of a paired
game sends its own wild slots once a link (`wild`, about 20 KB of JSON for
57 maps). The host keeps each version's in memory only (not in the campaign
file; the log names only the version and the number of maps) and, while the
switch is on, passes the other version's to each window once a link. A
window holds them only for its session (`Client.wild`). Until a player of
each version has been in, every world keeps its own tables, and the Hosting
screen says "Wild Pokémon from both versions: waiting for a BLUE player."
(the host's own cartridge counts as in). The extra number is drawn only
while the window holds the other version's tables and the slot has a
Pokémon to offer, so a campaign without the switch keeps the cartridge's
encounter stream.

## The launcher

- PLAY says which games play together: "RED plays with RED or BLUE",
  "YELLOW plays with YELLOW".
- Join a friend: a nearby host's card says "Your cartridge fits" (this
  cartridge, or the other of the pair), "Joins with BLUE" (another imported
  one fits), or "Needs RED or BLUE". After a refusal, USE <GAME> offers an
  imported cartridge that fits.
- Choose your campaign: the campaigns of both games of the pair, each with
  its switch row; HOST needs either game imported.
- NEW CAMPAIGN: the WILD POKéMON row (games with a pair).
- Hosting: "Wild Pokémon from both versions: on." or which version it
  waits for.

## Checks

ROM-free, in the co-op tier: `tests/coop/versions_test.lua` (the pair rule,
the refusals and why, the tables passed only with the switch, once a link,
never stored, the encounter rule), `tests/coop/versions_game_test.lua` (the
fixture overworld's own grass roll through the hook, with and without the
switch), `tests/coop/versions_launcher_test.lua` (PLAY, the reasons, the
fitting cartridge, the switch on NEW CAMPAIGN and the card, a Blue cartridge
hosting a Red campaign, each screen at 480 x 400).

Live, 2026-10-16: a US Red host (switch on) and a US Blue guest over ENet on
one machine, offscreen, with the owner's dumps imported into private
folders. Blue joined Red's campaign; each window sent its tables (57 maps),
each got the other's. A driver rolled 20000 encounter steps through
`rollEncounter` on eight maps in each window. Red's world met SANDSHREW on
Route 4 (168 of 1540, at the slots' levels 6 to 12), BELLSPROUT on Route 24,
BELLSPROUT and MEOWTH on Route 5, KRABBY on Seafoam B4F, VULPIX and MAGMAR
(at 42) in the Mansion's B1F; Blue's world met EKANS, ODDISH, MANKEY,
HORSEA, ELECTABUZZ in the Power Plant and GROWLITHE. Route 1 and Route 22
gave nothing of the other version, and Red's Power Plant nothing (Blue's
RAICHU there is wild in Red too). With the switch off, neither window got
tables and no encounter changed. Probes over ENet from the Blue process as
Yellow, as Blue with another dump and as Blaue Edition were refused
`content_mismatch`, the host's log saying `game`, `dump` and `language`; a
Blue probe with the verified dump was not refused. Not run: the launcher's
screens with a real cartridge, split-screen with the switch, a real step
into the grass ending in a battle against a mixed Pokémon.
