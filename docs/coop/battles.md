# Co-op battles

Two or more players fight the game together: a wild Pokémon or a trainer
one player's world met, with every player's team on the allied side (#18,
area A8 in [design.md](design.md), decision G24, accepted), shown with the
cartridge's own battle screen and menus (#19, area A9); leaving it, coming
back and taking over for a player who dropped (#20, area A11); and what the
world shows of partners in a battle (#34, area A14).

## How a co-op battle runs (G24)

A co-op battle is **lockstep**, the way upstream's link battles are
(`src/link/LinkBattle.lua`): every window in the battle runs the game's own
battle, `src/battle/BattleState.lua`, from the same opening, the same seed
and the same inputs in the same order, so every copy comes to the same
state. The window shows its copy with the cartridge's own screen, sounds and
menus. No copy is the master.

The host runs no battle engine. It keeps each battle's **record**:

- **the opening**: what the opening window's world prepared, which the host
  trusts (design A1.10): wild or trainer, the enemy Pokémon (packed with
  upstream's link codec, so every window rebuilds the same clamped copies),
  the trainer's class, party number and rival name, the map;
- **a seed** it deals, for the battle's own random numbers;
- **the inputs**, numbered: each team that joined and each accepted command.
  A battle's revision is how many inputs it has;
- **the question**: where the battle waits now and for whom. Every window in
  the battle reports where its copy stands (`battle_at`); the host takes the
  first report of a revision and compares the later ones (a different one
  is logged as `battle_desync`);
- the suggestions to whoever decides, apart from the inputs.

A copy takes the next input only when it stands at a question, and the host
makes inputs only at questions, so every copy applies each input at the same
point. The questions are the command menu (FIGHT, PKMN, ITEM, RUN), a forced
replacement after a faint, a move to learn when the Pokémon knows four,
MIMIC's choice, and "Use next POKéMON?" in a wild battle. Each is asked of
the owner of the Pokémon concerned; only that player's window opens the
menu, and its answer goes to the host as a command, not into the battle.
The battle only moves when the command comes back as an input.

## Files

- `src/coop/battle/HostBattles.lua`: the host's side. It opens battles,
  queues and puts in joins, takes commands and suggestions, takes the
  windows' reports and sends each player the battles they are in.
- `src/coop/battle/Replica.lua`: a window's copy. `Replica.make` turns a
  `BattleState` into a co-op battle; `Replica.build` builds one from the
  record; `Replica.catchUp` plays a record's inputs without a screen or
  sound.
- `src/coop/battle/View.lua`: what the battle shows on top of the
  cartridge's screen (who decides, suggestions, the roster menu, the ball
  row, the join line, the self-moving last lines, the catch list).
- `src/coop/game/Battles.lua`: the running game. The world's battles go to
  the host; JOIN and REJOIN in the CO-OP menu; copies away from the screen;
  a fight held while away; battles built again after coming back; the end
  of a battle in the window.
- `src/coop/game/Presence.lua`: partners in a battle in the world (#34).
- `src/coop/session/Protocol.lua`, `Host.lua`, `Client.lua`: protocol 7.

Upstream files, with marked hooks:

- `src/world/OverworldController.lua`: `OverworldState:pushBattle` asks
  `Battles.take` first; every battle the world opens passes there (grass,
  fishing, a trainer's sight, scripts, static Pokémon).
- `src/battle/BattleState.lua`: the send-out after a forced replacement is
  a method of its own (`sendOutReplacement`), so a co-op battle sends out the
  owner's pick; and a battle may award experience its own way (`expAward`,
  `expTrainerId`).
- `src/coop/game/CoopMenu.lua` (the fork's own): the JOIN rows.

## The copy in a window

`Replica.make` changes a `BattleState` this way:

- **Its game is a facade.** The save it sees has the battle's roster as its
  party and money of its own, so nothing the battle writes reaches the
  player's world until the end. The bag and the Pokédex are the player's.
- **Random numbers** come from the record's seed (a Park-Miller generator, as
  in link battles), so the enemy's AI, damage, hits and catches roll the
  same everywhere.
- **The roster** is the allied party: each team that joined, in order, each
  Pokémon with its owner. A team joins behind the roster, so the indices
  already handed out stay valid (A8.5).
- **Locked-in turns** (a recharge, THRASH, RAGE, a charging move, a trapping
  move) are taken by every copy at once, without a command (A8.10).
- **EXP.ALL** in any participant's bag counts for every team; each team gets
  the solo split over its own Pokémon (A8.15). A partner's Pokémon is traded
  or not against its own owner's trainer id (A7.10). Experience goes only to
  the Pokémon that took part, as the cartridge decides (A8.14).
- **The battle style is SET** (A8.18): SHIFT's offer has no natural owner.
- **The bag** works on scratch copies (`Replica.facade`): the acting
  player's bag spends the item, the choice goes to the host, and the item's
  effect comes back as an input that every copy applies with upstream's link
  item code (`src/link/LinkItems.lua`) (A8.13).
- **A catch** goes to the player who threw the ball: their party, else their
  box, and their Pokédex; the other copies only say who caught it. Naming
  another participant comes with #17 (A7.6).
- **RUN** flees for the player whose world opened the battle; the others are
  told only they can (A9.5; leaving a battle is #20).

At the end each window writes its own Pokémon back (by reference, or by uid
for a copy built later), adds what the battle paid to its player's money
(every participant gets the full prize, Pay Day included, A8.16), and runs
evolution for its own Pokémon that grew (A7.8). A loss whites out every
participant in their own world: the opener's through its world's own
`onFinish`, a joiner's through `afterBattle` (A8.17). A side that wins
blacks out nobody.

## What the battle shows (#19)

Every window shows its copy with the cartridge's own battle screen: the
intro (for a player who saw the battle start), the lines, move animations
and sounds, HP bars draining in the turn's order, faints, send-outs, ball
tosses, cries, the battle music by trainer class, the victory fanfare, the
trainer's defeat line and prize with this window's own player name, all as
the cartridge plays them (A9.8, A9.9). A choice waits until the last turn
has played out in the window that makes it. On top of that
(`src/coop/battle/View.lua`):

- **Who decides** (A9.2). The other players' text box names the player the
  battle asks, "<NAME> / decides", left of the menu (and under a
  replacement, a move to learn or a YES/NO of another player).
- **Suggestions** (A8.8, A9.3, A9.4). A player who is not asked walks the
  same menus: FIGHT opens the move list, PKMN the party. The row their
  cursor rests on (20 frames) is suggested to the decider; A suggests it
  again rather than acting. Every window marks a partner's suggestion with
  a hollow ▷ on the main menu's entry (FIGHT, PKMN, ITEM, RUN) and on the
  exact move row or party row, with the partner's initial when three or
  more players are in. When the decider has pressed nothing for two
  seconds, their box alternates every 1.5 s between the menu and
  "<NAME> suggests / <choice>". Marks are in the cartridge's black, not in
  player colours (A9.12).
- **The party list** (A9.1) is the allied roster, six rows at a time: down
  past the sixth row turns the page. The box's top border names the owner
  of the row under the cursor and the page ("GREEN 2/2"). Nicknames show.
- **The party balls** under the HUD are this player's own team, not the
  whole roster (A9.10).
- **Lines of its own** (A9.11): "<NAME> joined the battle!" when a team
  comes in (in every copy, so all stay alike); an item a partner used is
  said with their name; a catch by another player says who caught it.
- **The end** (A9.6). Once the battle is decided, a line waiting for a
  press moves on by itself after 1.5 s, so the battle closes after its last
  line without anybody pressing.
- **A ball** asks whom the catch is for, each player in the battle once
  (A7.6); with one player it asks nothing.
- **The bag** is the cartridge's (A9.1 asks for the battle items only; the
  cartridge lists every item and refuses the others with OAK's line).

Split-screen: each player's game is a world of its own (#11), so each half
shows its player's copy of the battle with its own menus (G2).

## Opening and joining

**Opening** (A8.2): a battle the world opens is sent to the host with this
player's team; the world keeps its trigger, its script branches and its
`onFinish` (trainer flags, story steps, whiteout). The battle waits behind
the battle transition until the host's record comes, then becomes the co-op
copy. If the host refuses, or there is no link, or nothing comes within ten
seconds, the world fights it alone as the cartridge does (A8.22); a record
that comes later is ended at once.

These stay in the window and cannot be joined (A8.19): the Safari Zone, a
GHOST in Pokémon Tower without the SILPH SCOPE, the old man's demo, and the
starter rival in Oak's lab (the opening is #22).

**Joining** (A8.3): JOIN <NAME> in the CO-OP menu sends this player's team.
The world stands still under a "Joining <NAME>..." box until the host puts
the team in, at the battle's next move question (A8.4). The copy is then
built from the record, plays every input so far without a screen or sound
(no intro, A9.8), and comes in on the world's battle transition. The player
never left their map: the return point is where they stood.

**Rules on the host:**

- A player is in one battle at a time, and a queued join counts (A8.1).
- A join waits while the battle asks for a replacement, a move to learn or
  MIMIC's choice (A8.4). Put in, it moves the revision on: a command in
  flight for the old one is refused as `stale`, and the window sends it
  again for the new one.
- The roster holds twelve. A team that does not fit joins with its first
  Pokémon that fit, in party order; the rest sit out untouched. No room is
  `roster_full`. Queued joins share the room in the order they came
  (A8.5, A8.9).
- A command is taken only for the current revision (`stale`), once the
  battle's question is known (`not_ready`), from the player asked
  (`not_yours`), of a kind that answers the question (`bad_cmd`). RUN only
  from the opener (`run_initiator`) (A8.6, A8.7).
- A suggestion is kept apart from the inputs, shown to every participant,
  never applied, and cleared by the next input; the player who decides
  cannot suggest to themself (A8.8). Making and showing suggestions in the
  battle menus is #19 (A9.3, A9.4).
- The first `ended` report ends the battle; every player in it, and a join
  still queued (A11.8), hears the end once, and the host drops the battle,
  so nothing of it can be applied twice (A8.21). A campaign does not save
  while a battle runs or a join waits (A3.7).

## Leaving, coming back, taking over (#20)

A participant is **present** or **absent**: absent because they left on
purpose (LEAVE BATTLE) or because their link dropped. Leaving and dropping
are one rule (A11.1): the absent player's Pokémon stay in the roster and
fight on under whoever is present, and their results, experience and prize
stay theirs. The battle ends for everyone only when it is decided, or when
nobody is left.

- **LEAVE BATTLE** (A9.5, A11.1, A11.2). RUN flees for the player whose
  world opened the battle; for everyone else it asks "Leave the
  battle? / Your team stays." (a partner who is not deciding gets the same
  question from the RUN row they walk to). YES takes them back to their
  world at once: it never moved, so the return point is where they stood.
  The opener cannot leave (`opener_stays`).
- **Out of sight** (A11.3). The copy of a player who left keeps playing the
  record without a screen or sound (`Battles.step`, `Replica.runAway`), so
  their Pokémon get exactly what the battle does to them. When it ends they
  get one line ("The battle against RATTATA was won."), their Pokémon's
  results, their evolutions and, after a loss, their whiteout. Meanwhile
  they start and join nothing: the CO-OP menu has only REJOIN, and a fight
  their world opens waits under "Your battle against X goes on. REJOIN?"
  until that battle ends; then it starts.
- **REJOIN** (A11.4) in the CO-OP menu (or that question) brings the copy
  back on screen behind the battle transition, and the player decides for
  their own Pokémon again. B on the joining box calls off a queued join.
- **Who decides** (A11.5). The host derives it from the owner of the
  Pokémon concerned: the owner when present; for an owner who left, the
  first present participant at once; for an owner who dropped, nobody: the
  battle waits (the others see "<NAME> / is away"), while everything else,
  other battles and the world, goes on. A dropped player who was not asked
  pauses nothing.
- **TAKE OVER** (A11.6). After 30 s waiting for a dropped owner, each
  present participant is asked "<NAME> is away. / TAKE OVER?" (YES/NO; NO
  keeps waiting). The first YES stands in: they decide for that Pokémon,
  the view names both ("FOR GREEN" on the box), and the results stay the
  owner's. The owner decides again the moment they are back.
- **Nobody left** (A11.7). A battle nobody is present in waits two minutes
  (a redial's budget), then ends as fled; at shutdown every battle still
  running ends as fled, and its players hear it before `ended`.
- **The end while away** (A11.8). A join still queued is released; a player
  whose link was down when their battle ended hears the end once back: the
  window builds the battle from the record, plays it out of sight and ends
  it with its line.
- **Back after a drop.** A battle this player is in that the window has no
  copy of (they came back) is built from the record and comes on screen at
  the next quiet moment; a copy the window still has follows the new link
  and asks its question again (a command lost with the old link is sent
  again; the host refuses one it already took).

## In the world (#34)

[presence.md](presence.md) has the rest of area A14. For battles:

- a partner in a battle their own world opened stands where it started,
  under the cartridge's "!" bubble (A14.3); a partner who joined a battle
  elsewhere is not drawn until it ends (A14.4);
- the CO-OP menu offers JOIN <NAME> for each partner's battle with room, or
  REJOIN for one this player left, and the box names a partner in a battle
  IN A BATTLE (A14.8);
- a partner's new battle this player is free to join is told over the
  world: "BLUE is in a battle against wild PIDGEY. START > CO-OP to join."
  (A14.10);
- in a co-op battle SELECT opens nothing: the battle screen is on top and
  its SELECT swaps moves as in the cartridge (A14.9).

## Protocol 7

| Client to host | Fields |
|---|---|
| `battle_open` | `seq`, `kind` (`wild`, `trainer`), `enemy` (packed Pokémon), `map`, `team` (this player's, at most six), optional `trainer` (`class`, `index`, `rival`), `hooked`, `foe`, `otId`, `expAll` |
| `battle_join` | `seq`, `battle`, `team`, optional `otId`, `expAll` |
| `battle_cmd` | `seq`, `battle`, `rev`, `cmd` |
| `battle_suggest` | `seq`, `battle`, `rev`, optional `cmd` (none takes it back) |
| `battle_at` | `seq`, `battle`, `rev`, then `ask` and `by` (the question and the owner of the Pokémon it is about) with `hash`, or `ended` (`win`, `lose`, `run`, `caught`) |
| `battle_leave` | `seq`, `battle`: LEAVE BATTLE, or call off a queued join (#20) |
| `battle_rejoin` | `seq`, `battle`: REJOIN (#20) |
| `battle_takeover` | `seq`, `battle`, `owner`: stand in for a dropped owner (#20) |

| Host to client | Fields |
|---|---|
| `battle` | `id`, `rev`, `seed`, `from`, `inputs` (from `from` on, at most 256 a message), `players` (`id`, `present`, `left`), the `open`ing with the first inputs (and `by`, who opened it), `ask`, `by` (who decides) and `owner` (whose Pokémon it is about), `offer` (a dropped owner the present players may take over for), `standins` (`owner`, `by`), `suggestions` (`by`, `cmd`), `ended` |
| `state` | each player's `battle` (the one they fight in), and `battles`: `id`, `by`, `kind`, `foe`, `players`, `joinable` |

A command is `kind` (`move`, `struggle`, `fight`, `switch`, `item`,
`ball`, `run` answer the menu; `replace`, `learn`, `mimic`, `choice` the
other questions) with `slot`, `index` (a roster row), `item`, `move`,
`yes`, `forget` or `target` as it needs. An input is a `join` (`player`,
`name`, `team`, `otId`, `expAll`) or a `cmd` (`player`, `cmd`). A packed
Pokémon is upstream's link codec's (`species`, `level`, `hp`, `moves`,
`exp`, `status`, `dvs`, `statExp`, `nickname`, `ot`, `otId`) and its
campaign `uid`; the receiving window rebuilds and clamps it.

## Checked

Run on Linux desktop (LÖVE 11.5), US Red, two game processes on one
machine, offscreen, each with its own save folder and a frame driver; RED
hosts, GREEN joins over ENet:

- a wild battle and a trainer battle (BUG CATCHER) RED's world opened,
  GREEN joining each from the CO-OP menu's path (`Battles.join`): both
  won, both copies ended with the same state digest, both players got the
  trainer's prize (¥60 each), GREEN's Pokémon that never fought gained
  nothing;
- a lost battle: RED's lead fell, GREEN's went out on RED's pick and fell
  too; both players whited out in their own world (money halved, back at
  their heal point, party healed);
- RED switched to GREEN's Pokémon at once: GREEN decided every move after
  that, the battle was won and both Pokémon that fought gained experience;
- the host's session log showed no `battle_desync` in any of the five runs
  checked.

Two early runs left GREEN's first battle on its stack after it ended (under
it the return fade, never updated). It did not come back in seven later
runs; a finished co-op battle now leaves at once if it is entered again,
and the joining box removes itself wherever it is on the stack.

- GREEN's box named RED as the decider while RED's Pokémon was out, and
  RED's idle box alternated with "GREEN suggests / FIGHT" after GREEN's
  cursor rested on FIGHT (screenshots, kept local).

- GREEN joined RED's battle and left it at once: back on the map, the copy
  played on out of sight and ended with "The battle against RATTATA was
  won." (#20);
- GREEN's ENet link was closed under the running game: the game showed
  `reconnecting`, redialled and was back as the same player (#20).

Not run yet: real pads in a real window, the menus driven by hand (the
drivers sent the replacement and the switch as commands), a move to learn,
MIMIC, a catch, items and Pay Day with the cartridge (the first four are
covered by the ROM-free tests), three players,
split-screen, and a trainer that uses items.

## Tests

ROM-free, in the `engine` group of `scripts/test.sh` and so in coop-ci:

- `tests/coop/battle_host_test.lua`: the host's rules over loopback, with
  the windows' reports sent by hand: opening and seed, one battle per
  player, joins queued and put in at a move question, trimmed, refused when
  full, stale commands after a join, who may answer, suggestions, desyncs
  logged, the end and the released join, saves refused while a battle runs,
  a dropped player absent and back.
- `tests/coop/battle_replica_test.lua`: two windows' copies of one battle
  over loopback (fixture data): a joiner catches up and stands where the
  opener stands, no desync at any revision, experience and write-back, the
  trainer's prize for both, EXP.ALL per team, a loss for both, a switch
  handing control over, a catch going to the thrower once, a locked-in
  turn taking no command, a POTION from the actor's bag, the bag's facade,
  a move to learn and MIMIC's choice asked of the owner and applied alike
  in both copies.
- `tests/coop/battle_view_test.lua` (#19): who decides, a suggestion from
  a resting cursor and its marks, the idle decider's alternating box, the
  join line in every copy, the roster six rows at a time with its owner,
  the viewer's own ball row, the catch list, the self-moving last lines.
- `tests/coop/battle_leave_test.lua` (#20): LEAVE BATTLE and the copy
  playing on out of sight to the same end, the first present player
  deciding for an absent owner, REJOIN, a dropped owner pausing the battle
  and TAKE OVER after 30 s with both named, a battle nobody is in ending as
  fled with the copy away.
- `tests/coop/session_reconnect_test.lua` (#20): a dropped link redials as
  the same player, keeps its window, warps its first position; two minutes
  without the host end it, shown over the world, then the launcher; a long
  pause dials afresh.
- `tests/coop/battle_game_test.lua`: the running fixture overworld with
  this device hosting: a battle the world opens becomes the host's and
  keeps the world's `onFinish`, a refused opening is fought alone, the
  battles that stay solo, JOIN in the CO-OP menu, a joiner sees no intro,
  RUN by the opener; leaving, REJOIN in the CO-OP menu, a fight held while
  away and started after (#20); a partner's battle told in a notice, the
  "!" over its opener, IN A BATTLE, a joiner from elsewhere not drawn
  (#34).
