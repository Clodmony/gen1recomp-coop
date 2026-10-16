# New players and the opening

A new player plays Oak's opening in the co-op world on a story of their own,
and joins the campaign's story once they leave the lab with a starter (#22,
area A4 in [design.md](design.md), decision G27). Or they start in Pallet
Town with a starter, or bring a trainer from a single-player save (#57,
decision G28; see *Other starts*).

## Files

- `src/coop/campaign/Window.lua`: the window's side. It decides whether its
  world is in the opening, keeps the opening private, ends it and tells the
  host.
- `src/coop/game/Opening.lua`: what the game asks: Oak's speech, whether the
  player is in the opening, the rival's starter.
- `src/coop/campaign/Start.lua` (#57): the start worlds: Pallet Town's (with
  the story a played opening leaves) and a brought save's.
- `src/coop/launcher/CoopMenu.lua`, `Screens.lua` and `Launcher.lua` (#57):
  HOW YOU START, and writing the start world into the campaign's slot.
- `src/coop/session/Host.lua` and `src/coop/campaign/Campaign.lua`: who is in
  the opening, the rival's name and the starter he counters.
- Marked hooks in upstream files: `OakSpeech:buildSteps` (the speech),
  `Game:writeSave` (no save in the opening), `Commands.rival_battle` (the
  rival's team).

## The opening

**Who plays it.** A window whose world has no starter (`EVENT_GOT_STARTER`
unset) is in the opening. A world from the campaign with a starter never is,
wherever it stands. The host marks a player it has no world for as in the
opening when they join, so the others are told "<NAME> joined the session in
the opening." (unless the hello says they start in Pallet Town or bring a
save, `start`, #66); the window's first look then confirms or clears it, and it
says so again on every new link (a done lost to a dropped link is sent
again, with its starter). The first look waits for a world on screen: the
title's save (before CONTINUE or NEW GAME) is not the player's, and taking
it for one put a returning player in the opening until they next stood
outside Oak's lab (found in the integrated live run).

**A private story** (A4.4). While a window plays the opening it sends no
patch, takes nothing of the campaign's story, lands no gifts and sends no
holdings. Each player has their own Oak, rival and three balls, so both may
take the same starter. Nothing of the opening reaches the host, so a player
who drops in it starts it again.

**No save** (A4.9). The game writes no save in the opening: START > SAVE
says "The opening can't be saved. Leave OAK's LAB first!", and
`Game:writeSave` writes nothing for any other caller.

**Its end.** The engine keeps no "left the lab" step, so the opening ends at
a rest point once the player has a starter and stands outside `OAKS_LAB`.
The lab's rival battle (on the way out, win or lose) comes before that, and
walking back into the lab later changes nothing. Then the window:

1. tells the host it is done, with the starter it chose;
2. opens as a late window: the campaign's story over its own entries, or,
   when the campaign has no story yet, its entries seed it (A4.7: the first
   finished opening, as that player's cartridge left it: Oak in the lab, the
   lab's balls, the rival fought);
3. takes the campaign's rival name;
4. sends its world, PC and all, so a rejoin opens it.

The starter's own flags (`EVENT_GOT_STARTER`, `EVENT_CHOSE_*`) are the
player's (`Ownership.PLAYER_FLAGS`), so each keeps theirs.

**Battles.** A battle the world opens in the opening stays in the window: it
is no campaign encounter, nobody is offered to join it, and no JOIN row
shows while the player is in the opening.

## Names

- **The player's** (A4.5) comes from the launcher: Oak's speech drops
  `ask_player_name`, `name_player` and `confirm_player_name`, and the trainer
  is named the session's name in capitals, cut to the cartridge's seven
  characters.
- **The rival's** is the campaign's once somebody named him. The host may
  name him on NEW CAMPAIGN (RIVAL NAME; empty leaves him to the game). Until
  then Oak asks, and a step after `confirm_rival_name` sends the name to the
  host, which keeps the first one given. Once named, Oak's speech drops the
  three rival steps and writes the campaign's name; a window past the opening
  takes it at its rest points.
- **Player 2** on a split-screen device names themself in the launcher (ENTER
  WITH 2 PLAYERS and JOIN WITH 2 PLAYERS ask PLAYER 2 NAME first, offering
  the remembered `name2`), as any new player does ([split.md](split.md)).

## The rival's starter (A4.6)

The first player to finish the opening sets the starter the campaign's rival
counters (`chose`: BULBASAUR, CHARMANDER or SQUIRTLE). Red and Blue's later
rival battles (`Commands.rival_battle`: Route 22, Cerulean, the S.S. Anne,
Pokémon Tower, Silph Co., the Champion) pick his team from it, whatever
starter this player took. The lab's battle is each player's own, from their
own choice. Yellow's rival (EEVEE, `save.rivalStarter`) is #9's.

## Who sees whom (A4.8, A14.4, A14.8)

- A partner in the opening is not drawn, gets no arrow and no TOWN MAP mark.
- A player in the opening sees nobody, gets no arrow and hears of no battle
  to join.
- The CO-OP box shows a partner in the opening as IN THE OPENING.

## Other starts (#57)

**The choice** (A2.3, A2.5). HOW YOU START on NEW CAMPAIGN (the host's
player) and on the connection check (a player the host does not know)
steps through THE OPENING (the default), START IN PALLET (with STARTER:
BULBASAUR, CHARMANDER or SQUIRTLE) and BRING A SAVE. BRING A SAVE opens
*Bring a trainer*: this device's solo saves of the game, as the SAVES page
lists them, without the campaigns' slots; a save still before Oak's lab
(no `EVENT_GOT_STARTER`) shows NO STARTER YET and cannot be picked. A
device the host knows is asked nothing.

**Where the world is made.** On entering, the launcher writes the start
world into the campaign's slot, but only when the host has no world for
the player (`world` `fresh`); a returning player always gets the
campaign's world and is never replaced by a brought save (A4.3). The
world carries `coopStart` (`pallet` or `save`). The title then offers
CONTINUE, and the game's own load opens it: migrations,
`SaveData.validate` and the trainer stamped on every Pokémon (A4.2).

- **Start in Pallet Town** (A4.1): a new game's world named after the
  launcher's name, standing on Pallet Town's blackout cell (5, 6), 3000
  money, the starter at level 5 (its two first moves, 135 experience
  points, random DVs; the validator derives its stats and PP), the
  starter's own flags, its Pokédex entry and the rival's counter-pick seen,
  and the story a played opening leaves (A4.7): Oak's walk
  (`EVENT_FOLLOWED_OAK_INTO_LAB`, `_2`, `EVENT_OAK_ASKED_TO_CHOOSE_MON`,
  Pallet's Oak hidden, the door's Oak gone, Oak at his desk), the lab's
  rival fought and gone (`EVENT_BATTLED_RIVAL_IN_OAKS_LAB`), and the two
  balls `oaks_lab.lua`'s rows for that starter hide (the player's and the
  rival's counter-pick). For SQUIRTLE these are exactly the ten entries
  #22's played run seeded. Red and Blue share it (and the German editions,
  whose scripts are the same).
- **Yellow** offers no START IN PALLET (G28): its opening is another one
  (Oak catches PIKACHU, who follows the player; one ball; the rival's
  EEVEE, whose later form #9 decides), not captured, and no Yellow run
  checked it. A Yellow player plays the opening or brings a save.
- **Bring a trainer** (A4.1, A4.2): the solo save as it stands (team, PC
  and boxes, bag, money, place, its own world keys and its trainer id),
  without the device's options. The solo save itself is never written.

**What the host does.** At its first rest point the window takes the mark
off and sends the world whole (`start`), then waits, sending and taking
nothing. The host:

1. refuses it as `returning` when it has this player's world (A4.3);
2. otherwise keeps it as the player's world (the trainer id with it);
3. when the campaign has no story yet, takes the world's entries as the
   story (walk flags left out): a brought run continues in co-op (A4.3),
   and a Pallet start brings what a played opening leaves (A4.7). The key
   items of that story the world holds join the late joiner's list (A6.5)
   and are owed to every player already in. A campaign that has a story
   keeps it: the brought save's own story stays out;
4. sets the rival's starter from the world's `EVENT_CHOSE_*` if nobody set
   it (A4.6);
5. clears "in the opening", sends the story, then `started`.

The window then opens as a late window: the campaign's story over its own
entries. The host decides the seed, so two skippers into a new campaign
never mix two stories. A start sent again on a new link (its answer lost
with the old one) that the host refuses as `returning` went through on
the old one. Any other refusal leaves the window closed: it sends
nothing, so the host's world for the player stays as it was.

Not covered: a second seat on a split-screen device plays the opening;
a Pallet start into a campaign nobody named the rival in keeps the new
game's rival name until somebody names him in Oak's speech.

## Protocol and file

Protocol 10: a window's `opening` (`done`; optional `rival`, the name given;
`chose`, the starter, with `done`), each player's `opening` in `state`, and
the campaign's `rival` and `chose` in `state`. Protocol 13 (#57): a
window's `start` (`how`, `save`), the host's `started` (`seq`, `seeded`)
and the `returning` refusal. Campaign file version 4 keeps
`rival` and `chose` in the campaign's section; a version 3 file has neither
yet. The campaign card keeps the host's `rival` until the campaign is
created.

## Checks

ROM-free: `tests/coop/opening_test.lua` (host and windows over loopback: the
private story, its end, the seed, a second player's own opening, names, the
starter, the file, the protocol), `tests/coop/starts_test.lua` (#57: the
Pallet start's story against #22's run and the lab's script, the Pallet
world and the validator completing its starter, a host's Pallet start
seeding a new campaign, a brought save into a campaign with a story and
into one without, a returning player refused, a start sent again on a new
link), `tests/coop/opening_game_test.lua` (the
fixture overworld: Oak's steps, the save veto, what a player in the opening
sees, battles, the rival's team), and the launcher's rows in
`tests/coop/launcher_coop_test.lua`.

## Checked

Run on Linux desktop (LÖVE 11.5), US Red, two game processes on one
machine over ENet, each with its own save folder and a frame driver
(`POKEPORT_SPEED=4`): RED hosting a new campaign (`POKEPORT_COOP_NAME=Ash`),
BLUE joining once RED had named the rival. Both played the whole opening
from NEW GAME: Oak's speech, Oak's stop in Pallet Town, the walk to the
lab, a ball, the lab's rival battle and out of the door. Seen in the run
(44 driver checks, none failed; no `battle_desync` or `world_refused` in
the host's log):

- RED's speech asked no player name (the trainer was ASH) and asked the
  rival's; the name given (the driver's mashing typed AAAAAAA) became the
  campaign's. BLUE's speech asked neither and wrote the campaign's rival.
- In the bedroom: RED in the opening, START > SAVE's box refused, and
  `Game:writeSave` wrote nothing. BLUE joined in the opening, on the same
  map, not drawn either way; RED's CO-OP box showed BLUE IN THE OPENING.
- RED took SQUIRTLE; outside the lab the opening ended. The campaign's
  story was seeded with ten entries (Oak's walk flags, the rival fought,
  Oak in the lab, two balls and the rival gone, Pallet's Oak hidden), the
  starter flags stayed RED's, `chose` was SQUIRTLE, the host had RED's
  world and RED could save again. BLUE, still in the opening, saw nobody
  and had none of RED's lab.
- BLUE took BULBASAUR from their own lab of three balls, fought their own
  rival, and outside took the campaign's story (SQUIRTLE's ball gone),
  kept their starter and `EVENT_CHOSE_BULBASAUR`; `chose` stayed
  SQUIRTLE. Both then stood in Pallet Town and each drew the other.
- The campaign file was version 4 with `rival` and `chose`.

**#57** (Linux desktop, LÖVE 11.5, US Red, three ENet processes on one
machine, offscreen, `POKEPORT_SPEED=4`, each driving its own launcher's
co-op screens, 64 driver checks, none failed; no `battle_desync` and no
refused world or start in the host's log):

- A solo run made MISTY's save: SQUIRTLE 14 and PIDGEY 11, a RATTATA in
  the PC, trainer id 4242, BOULDERBADGE and EVENT_BEAT_BROCK, a TOWN MAP,
  4321 money, in Viridian Forest.
- ASH hosted a NEW CAMPAIGN with START IN PALLET and SQUIRTLE. CONTINUE
  opened Pallet Town with SQUIRTLE at level 5 (stats, full HP and TACKLE's
  PP from the validator, ASH its trainer) and 3000 money. The host kept the
  world and seeded the story with the ten entries; the rival counters
  SQUIRTLE; ASH was not in the opening.
- MISTY joined (new to the campaign) with BRING A SAVE, picked the solo
  save and joined. CONTINUE opened it in Viridian Forest with its team,
  trainer id and own Pokémon. The host kept the world (trainer 4242, team,
  PC, money); the campaign's story stayed the Pallet start's (no
  EVENT_BEAT_BROCK, no BOULDERBADGE, no TOWN MAP gift), and MISTY's world
  took it over its own (Oak in the lab) while keeping its starter flags,
  bag and money.
- GREEN joined with THE OPENING, played it alongside (Oak's walk, a
  private lab where SQUIRTLE's ball still stood, CHARMANDER, their own
  rival battle, out of the door), then took the campaign's lab, kept
  EVENT_CHOSE_CHARMANDER, the rival still countered SQUIRTLE, and GREEN
  drew ASH in Pallet Town.

Not run for #57: Blue, the German games, Yellow's refusal on a cartridge
(the launcher's tests only), a dropped link during a start (the loopback
test only), real pads and windows.

**Integrated Group 11 build** (2026-10-16; Linux desktop, LÖVE 11.5, US
Red, offscreen, ENet, every process entering through the fork's launcher
and walking the opening: the house, Oak's stop, the lab, the rival's
battle, the door): ASH hosted NEW CAMPAIGN with RIVAL NAME empty and THE
OPENING; MISTY joined mid-opening with NEW NAME and THE OPENING. Both were
private (not drawn, IN THE OPENING in each CO-OP box, SAVE refused), both
windows lost focus and were hidden for 5 s each, both took SQUIRTLE from
their own labs, saw each other in Pallet Town and saved. MISTY quit and
REJOINed (past the opening, her team); ASH quit and hosted again from
CAMPAIGNS > HOST, MISTY REJOINed, both went on. The run found the first
look on the title (fixed above). #57 in the same build: ASH with START IN
PALLET (CHARMANDER), MISTY with BRING A SAVE (the TRADE save, trainer id,
team and money kept; her solo save file unchanged; the campaign's story
stayed the Pallet start's, so her world lost the brought save's own
story entries such as EVENT_GOT_POKEDEX), GREEN with THE OPENING
(BULBASAUR; the rival still counters CHARMANDER); the campaign file after
the three SAVEs held the three worlds and the ten story entries.

Not run: real pads and windows, a drop during the opening, split-screen
(player 2's name is checked in the launcher's tests), the host's RIVAL
NAME through the launcher by hand (its tests only), a later rival battle
picking the campaign's team on a cartridge (the fixture test only), Blue,
Yellow and the German games.
