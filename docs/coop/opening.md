# New players and the opening

A new player plays Oak's opening in the co-op world on a story of their own,
and joins the campaign's story once they leave the lab with a starter (#22,
area A4 in [design.md](design.md), decision G27). The start in Pallet Town
and bringing a single-player save are #57.

## Files

- `src/coop/campaign/Window.lua`: the window's side. It decides whether its
  world is in the opening, keeps the opening private, ends it and tells the
  host.
- `src/coop/game/Opening.lua`: what the game asks: Oak's speech, whether the
  player is in the opening, the rival's starter.
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
the opening."; the window's first look then confirms or clears it, and it
says so again on every new link (a done lost to a dropped link is sent
again, with its starter).

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

## Protocol and file

Protocol 10: a window's `opening` (`done`; optional `rival`, the name given;
`chose`, the starter, with `done`), each player's `opening` in `state`, and
the campaign's `rival` and `chose` in `state`. Campaign file version 4 keeps
`rival` and `chose` in the campaign's section; a version 3 file has neither
yet. The campaign card keeps the host's `rival` until the campaign is
created.

## Checks

ROM-free: `tests/coop/opening_test.lua` (host and windows over loopback: the
private story, its end, the seed, a second player's own opening, names, the
starter, the file, the protocol), `tests/coop/opening_game_test.lua` (the
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

Not run: real pads and windows, a drop during the opening, split-screen
(player 2's name is checked in the launcher's tests), the host's RIVAL
NAME through the launcher by hand (its tests only), a later rival battle
picking the campaign's team on a cartridge (the fixture test only), Blue,
Yellow and the German games.
