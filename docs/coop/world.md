# The shared world

What partners share of one Gen 1 world, and when (#14, area A5 in
[design.md](design.md), decision G21). It builds on the campaign files
([campaign.md](campaign.md)) and the session core ([session.md](session.md)).

## Files

- `src/coop/campaign/Ownership.lua`: who owns each part of a world, the
  campaign or the player. It also turns a world into the campaign's
  entries and writes them back.
- `src/coop/campaign/Window.lua`: a window's side of the exchange. It
  decides what to send and what to take, and when. It knows nothing of the
  game: each frame it gets the save, what holds the player, the map, and
  how to reload or refresh that map.
- `src/coop/game/SharedWorld.lua`: that frame, built from the running Gen 1
  overworld; also the Vermilion rule a map script asks about.
- `src/coop/campaign/Campaign.lua` keeps the story (`story`, `patch`,
  `worldFor`). `Host.lua` and `Client.lua` carry it (protocol 5; 6 adds
  story items, [items.md](items.md)).

## Who owns what (A5.1)

The campaign's entries are the **story**. It is a flat map of paths to
plain values, so two flags set at once in two windows both survive:

| Path | Value | What it is |
|---|---|---|
| `flags/<EVENT>` | `true` | story, gate and progress flags (the team rule, D91) |
| `objectToggles/<MAP>/<OBJ>` | boolean | an object hidden (`false`) or shown |
| `defeatedTrainers/<NPC>` | `true` | a beaten trainer or static Pokémon |
| `itemsTaken/<NPC>` | `true` | an item ball picked up |
| `inventory/<BADGE>` | number | the eight badges (this engine keeps them as items) |
| `trashPuzzle/first`, `/second` | number | Vermilion Gym's trash-can locks |

Everything else is the player's: team, PC, bag, money, Pokédex, position,
hidden items, the FLY list, step counters, the Safari game, the daycare,
the Hall of Fame and Yellow's PIKACHU. A key nobody classified is the
player's, so a new key never reaches a partner unclassified.

Some flags are each player's although they are flags
(`Ownership.PLAYER_FLAGS`):
- the Safari game;
- Pokémon Tower's purified zone;
- the Mansion switch;
- the fossil lab;
- the Elite Four walk-ins and Lance's door lock;
- gift Pokémon (EEVEE, LAPRAS, the Dojo's pair, the MAGIKARP, Yellow's
  three);
- the starter choice.

The balls of gift Pokémon are each player's too (`PLAYER_OBJECTS`).

**No script steps.** This engine keeps no per-map script bytes (pokered's
`wXxxCurScript`). A visit's progress lives on the live overworld and is
never saved, so a bystander never replays a leader's lines from a shared
step (A5.9). Bill's house, the gyms and the other places of A5.9 need no
entry of their own.

## The exchange (A5.2, A5.3)

- **Window to host:** a window sends `patch`: the difference between what it
  last sent and its entries now.
- **Host:** applies a patch entry by entry, skipping entries the campaign
  does not own. It sends each player `story`: the whole story first, then
  what changed since. Each `story` carries the last of that player's
  patches it has applied.
- **Window, taking:** a window applies the difference between the story it
  last took and the newest. It leaves out entries of its own patches the
  host has not yet reported applied, so an older story never rewinds its
  own change.
- **A world saved** (#13) is kept without the story's entries; the patches
  carry those. A world sent to a player has the story laid over it.

## Rest points (A5.4, A5.5)

A window sends and takes only at a **rest point**: three frames in a row
in which nothing holds the player (`SharedWorld.busy`). The player is held
by:

- anything on the state stack above the overworld (a text box, a menu, the
  CO-OP box, a battle, a fade);
- a map load or warp;
- a running or queued script;
- a forced or scripted walk (spinner tiles, a ledge hop);
- a trainer's approach or an NPC a script holds;
- the overworld's own animations (fly, teleport, holes, CUT, a boulder's
  dust, a heal).

A step the player walks of their own does not hold them: the cartridge
opens START at the next cell. A battle the host runs for this player
comes with #18.

So a scene's result reaches the partners when the scene ends, not during
it. Exceptions:
- START > SAVE (any write of the game's save) sends the scene so far at
  once.
- A closed window or a lost link sends nothing, and the host keeps the
  last resting state.

## The map a window stands on (A5.6, A5.7, A5.17)

A partner's entry lands at the next rest point:

- **An object hidden or shown on this map** (a toggle, an item ball) lands
  at once. The map's people are rebuilt in place, as
  `WorldAPI:toggleObject` does, on a frame between two cells.
- **A flag the map is stamped from** owes the window a reload. That covers
  Vermilion Gym's locks, Cinnabar Gym's quiz gates (and a beaten gate
  guard), Victory Road's switches and the League rooms' exits
  (`Ownership.RELOADS`). Block swaps are stamped when a map loads.
- **Victory Road:** a switch a partner's cartridge reset clears waits while
  this window still stands on that floor.
- Anything else lands at once. A beaten trainer is read live, so a
  partner's win stops that trainer seeing this player.

## Opening a world (A5.2, A5.19)

A window's first rest point takes the campaign's story. The world's own
story entries give way, and nothing is pushed: a window opened late never
spreads its blank or stale state. Only a campaign with no story yet takes
the first window's entries.

The world a player gets on joining is their own keys with the story laid
over it (`Campaign:worldFor`): their map, cell, facing, last outside map
and last heal point, as a Continue opens them. The engine's boot path
restores surfing on water.

## Per-place rules

- **Vermilion's first lock (A5.11):** `VERMILION_CITY.onEnter` re-rolls the
  first lock's can on every entry. While another connected player is in
  Vermilion City or its gym, an entering window keeps the campaign's locks
  instead (a marked hook in `data/scripts/story.lua`). A dropped partner
  does not count.
- **Walk flags (A5.13):** the Safari game (`safari`, `safariGameOver`,
  `EVENT_SAFARI_GAME_OVER`) is dropped from every player's world when the
  host opens a campaign. Seafoam's walk state is
  not saved by this engine; its boulder holes are the campaign's toggles
  and flags (A5.18).
- **Team rule (A5.14 to A5.16):** the gate drink, badges, Cinnabar's quiz
  gates and Victory Road's switches are flags or badges the campaign owns.
- **Not shared (A5.8):** NPC wandering, boulder positions, a scene's boxes
  and sounds, wild encounters, trainer sight rolls.

## Campaign files

Version 2 (3 since #16, [items.md](items.md)). The campaign's section
holds `story` as the flat map. A
version 1 file is migrated on reading. Its story is built from the
players' worlds: a flag any player set stands, and an entry held with two
values takes the first player's. The worlds then lose those entries.

## Not covered yet

- Party and PC changes at rest points, and the party sent before a battle
  the world asks for: #17.
- A battle the host runs for a player holding them: #18.
- Story items reaching every player, and the gift race: done in #16,
  [items.md](items.md).
- A new player's private opening: #22. Today a new player's window takes
  the campaign's story at its first rest point.

## Checked

Run on Linux desktop (LÖVE 11.5), US Red, two game processes on one
machine, each with its own save folder and a frame driver (host with
`POKEPORT_COOP_HOST`, guest with `POKEPORT_COOP_JOIN`):

- The host hid PALLETTOWN_FISHER from Route 1 while the guest stood in
  Pallet Town. The fisher left the guest's live map within 241 frames, and
  the guest stayed on its cell.
- The host set a flag with a text box open. After 300 held frames the
  campaign's story still lacked it; it went out once the box closed and
  reached the guest.
- The host opened both Vermilion Gym locks while the guest stood in the
  gym. Both flags reached the guest, the gym was reloaded once, and the
  guest stayed on its cell.

Not run live: Victory Road, Cinnabar's gates, the League rooms, Vermilion's
kept lock with a partner there (ROM-free only), a version 1 file from a
played campaign.

## Tests

ROM-free, in `tests/coop/`:

- `shared_world_test.lua`:
  - the ownership table;
  - patches merging entry by entry;
  - a world stripped and laid over;
  - the version 1 migration;
  - a window on a hand-made client: rest points, unconfirmed patches,
    objects and owed reloads on the standing map, Victory Road's switches,
    opening late, a new campaign's first window, START > SAVE;
  - host and three windows over loopback: two flags at once, a held
    window, player keys staying home, foreign entries skipped, a late
    window, a lost link, a rejoin opening like a Continue;
  - the walk flags dropped on opening;
  - the protocol's checks.
- `shared_world_game_test.lua`: the fixture overworld hosting a session.
  - what holds the player;
  - the game's flag reaching a partner;
  - a partner's hidden object leaving the live map at a rest point and not
    before;
  - START > SAVE sending a held scene;
  - Vermilion's lock with a partner in the gym, in the city, and dropped.
