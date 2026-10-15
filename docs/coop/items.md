# Story items and the co-op bag

Items gained with the shared story reach every player. Key items the story
takes leave every bag. A player who joins later gets the gift list, and the
bag holds forty rows (#16, area A6 in [design.md](design.md), decision G22).
It builds on the shared world ([world.md](world.md)): a window's patch at a
rest point carries its bag change.

## Files

- `src/coop/campaign/Items.lua`: the item rules. It covers the gift list,
  key items and fossils, the bag as a count per item, giving with the spill
  to the PC, taking, and the 40-row bag.
- `src/coop/campaign/Window.lua`: notes the bag and money at every rest
  point and sends the bag change with a patch. It lands the items owed to
  its player, each once.
- `src/coop/campaign/Campaign.lua`: shares, takes and takes back. It keeps
  the gift list as commits and each player's owed items (`gifts`).
- `Host.lua` sends what a player is owed in `gifts`, and `Client.lua`
  keeps it (protocol 6, [session.md](session.md)).
- `src/coop/game/SharedWorld.lua`: a notice for each item landed.
- `src/coop/session/Session.lua`: the 40-row bag while the session's game
  runs.

## A window's change (A6.2 to A6.4)

At every rest point the window notes the bag (items only: badges are the
story's) and the money. A **change** is what happened between two rest
points: a scene with its text boxes, a menu, a walk. A patch that **sets**
story entries also carries the bag's change: items gained, items lost, and
whether money went down.

The host then decides:

- **The change moved the story** (at least one entry the campaign did not
  have yet: an item ball, a person's present, a reward, a badge):
  - every other player is owed each item gained, in the same number (A6.2);
  - a key item lost goes from every other player's bag, then their PC:
    OAK's PARCEL delivered, the BIKE VOUCHER, the GOLD TEETH (A6.3);
  - a fossil lost, or an item used up, is not taken from anyone.
- **The change set only entries the campaign already had** (a gift race,
  A6.7): the player's own gains are taken back, and the first window's
  share stands in.
  - A change that also spent money is left alone, since a purchase may be
    in it.
  - A key item or HM is never taken back. Its share was not doubled.
- **A change that set nothing** (a purchase, a used item, a hidden item, a
  trade) shares nothing (A6.4).

Not caught, as in the source: a race whose change also moves new story, or
one that gives coins.

## What a player is owed

The campaign keeps each player's owed items in order, numbered per player:
`{ seq, item, qty, once, from, race }`, where `qty < 0` takes.

- **Landing** (A6.6). At a rest point, never in a scene:
  - an item goes to the bag, or to the PC's items when the bag is full;
  - `once` (a key item or HM) is skipped when the player holds one, in the
    bag or the PC;
  - a take removes from the bag first, then the PC.
- **Exactly once.** The world keeps the last `seq` it landed (`coopGifts`).
  - The host sends each owed item once per link. A rejoin hears them all
    again, and the window skips any `seq` it has landed.
  - The host forgets an item only when a world the player **saves** shows
    it landed.
  - So an item landed in a world that was never saved comes again after a
    rejoin. A player who was away when an item was shared gets it when they
    come back.
- **Notices.** Each landed item is told over the world:
  - "BLUE shared POTION x2." for a partner's item;
  - "POTION went to the PC." when the bag was full;
  - "RED handed over OAK's PARCEL." for a key item the story took;
  - "Got BICYCLE." for a late joiner's gift;
  - "No room for …!" when neither the bag nor the PC had room.

  A race's take-back and a key item already held say nothing.

## The gift list (A6.5)

An item gained in a change that moved the story is committed as
`gift:<item>`, once, when it is:

- a key item or HM of the list (`Items.LIST`):
  - TOWN MAP, BICYCLE, CARD KEY, SECRET KEY, LIFT KEY, S.S. TICKET;
  - COIN CASE, ITEMFINDER, SILPH SCOPE, POKé FLUTE, EXP.ALL;
  - the three rods;
  - HM01 to HM05;
- or a gift TM: a TM gained with its `EVENT_GOT_TMxx` flag set in the same
  change (a gym leader's, a person's). A TM from an item ball is not one.

A player new to the campaign is owed every committed gift (`once`). Red,
Blue and Yellow name these items alike. Yellow's gift TMs follow the same
flag rule.

Not on the list, as in the source: the Pokédex, OAK's PARCEL, the BIKE
VOUCHER, the GOLD TEETH, fossils. A late joiner's own opening is #22.

## The co-op bag (A6.8)

- While a session's game runs, the bag holds 40 rows
  (`Data.constants.bagSize`, the engine's mod override). Each shared key
  item and HM takes a row in every bag.
- The solo size (20, or a mod's) comes back when the session closes.
- The PC keeps its 50. A full bag's spill uses the same 40, since the
  window lands every gift.
- A campaign's save slot has no EXPORT in the launcher's saves screen, so
  a co-op bag never goes to a cartridge `.sav`.

## Campaign files

Version 3. Each player entry holds `gifts` and `giftSeq`. A version 2 file
gets empty lists.

## Checked

Run on Linux desktop (LÖVE 11.5) with US Red, as three game processes on one
machine. Each process had its own save folder and a frame driver at
`POKEPORT_SPEED=4`: host RED, guest BLUE, then GREEN joining late.

- RED took Viridian Forest's ANTIDOTE ball. BLUE saw "RED shared
  ANTIDOTE." and held one ANTIDOTE, with the ball taken in its world.
- RED took Daisy's TOWN MAP (its `EVENT_GOT_POKEDEX` was set by the
  driver). BLUE saw "RED shared TOWN MAP." and got the map and the flag.
- Both held a BIKE VOUCHER, and RED traded its voucher at the Cerulean
  bike shop. BLUE saw "RED shared BICYCLE." and "RED handed over BIKE
  VOUCHER.": BLUE had the BICYCLE and no voucher.
- The gift race: both took Viridian Forest's POTION in the same moment.
  BLUE was owed RED's share and its own take-back, and each ended with one
  POTION.
- GREEN joined afterwards. It saw "Got BICYCLE." and "Got TOWN MAP.", and
  held neither the ANTIDOTE, the POTION nor a voucher.
- Every process ran with a 40-row bag. Nobody saved, so the host still
  listed every owed item at the end, as intended.

Not run live: a gift TM, a full bag's spill, a rejoin landing an unsaved
gift again (ROM-free only).

## Tests

ROM-free, in `tests/coop/`:

- `story_items_test.lua`:
  - the item rules: key items, fossils, the gift list and gift TMs, the
    bag, giving with the PC spill, taking, the 40-row bag;
  - the campaign: sharing, a key item taken, fossils and used items, gift
    TMs, the race and its exceptions, the late joiner, forgetting what a
    saved world landed, the file round trip and version 2;
  - a window on a hand-made client: what a patch carries, gifts landing
    once and only at rest points, takes, gifts kept out of its own change;
  - host and windows over loopback: an item ball, the BICYCLE for the
    voucher, a full bag's spill, the race, an away player, a late joiner,
    an unsaved world landing again;
  - the protocol's checks.
- `shared_world_game_test.lua`: the fixture overworld hosting a session.
  It covers a partner's item ball reaching the game's bag with its notice,
  the game's own story item reaching the partner, and the bag at 40 rows
  during the session and 20 after.
- `saves_test.lua`: no EXPORT for a campaign's slot.
- `session_fuzz_test.lua`: `gifts` and a patch's `bag` fuzzed.
