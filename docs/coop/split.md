# Split-screen co-op

Two players on one device (#11): two views in one window, each player on
the device claimed for their seat on CONTROLS (#4). Both players are
clients of the session like any network player (design A1.3, G3): when
this device hosts, both dial the in-process host; when it joined a host,
both dial that host. So a split-screen pair can share a campaign with
online partners. The code is `src/coop/split/`.

## Starting

- **Launcher.** CONTROLS has a device for each of two players
  (`Seats.complete(2)`): the hosting screen shows **ENTER WITH 2 PLAYERS**
  beside ENTER THE WORLD, and the connection check shows **JOIN WITH 2
  PLAYERS** beside JOIN AS. Without two claimed devices the rows are not
  there. Either row enters with `coop_enter { split = true }`. The launcher
  then asks `Split.request` before the game boots.
- **Development entry.** `--coop-split[=NAME]` (`POKEPORT_COOP_SPLIT=NAME`,
  or `1`) with `--coop-host` or `--coop-join` adds player 2, named NAME
  when the host does not know them yet ([session.md](session.md)).

Player 1's game boots as in solo co-op. Once its session is in
(`Dev.update`), `Split.frame` starts player 2. Player 2 dials, joins, enters
a save slot of its own and boots its own game at the title, and its view
says `JOINING...` until then. CONTINUE on player 2's title enters their
world; a player new to the campaign starts a NEW GAME.

## Two worlds in one process

Upstream's Gen 1 game is built of module singletons (`Game`, `Input`,
`Renderer`, `StateStack`, `SaveData`, ...), so player 2 cannot be a second
instance. Player 2 is a second set of the game's modules: `Worlds.lua`
swaps `package.loaded` per world, as `tests/link3_harness.lua` does for two
link partners. While a world runs, every `require`, at load or inside a
function, finds that world's modules.

- **Home** is the world that was loaded when split-screen started:
  main.lua's game, player 1, the launcher's modules.
- **Shared** (one per process): `src.import.*` (the cartridge cache
  mounts), `src.core.GameVersion`, `src.core.Logger`, `src.link.Json`,
  `src.coop.split.*`, `tests.*`.
- **Silent.** Player 2's world runs without `love.audio`, `love.sound` and
  `love.thread`. The window has one mix, player 1's (decision G23). The
  background workers' channels are process-global, so a second world's
  workers would take the first one's results. Every upstream module has a
  path without them, the one the headless tests run. A sound wait in player
  2's game takes its silent timing.

## Stepping, drawing and input

`Split.start` wraps player 1's `Game.update` and `Game.draw` (its module
table) and the window's input handlers on `love`. `Split.stop` puts them
back.

- **Update.** Each `Game:update` of player 1 is followed by one of player
  2: its session (`Session.tick`), then its game. A scripted run steps
  both once per logic frame.
- **Draw.** `Layout.views` splits the window into two rects: side by side
  or stacked, whichever draws each 160x144 view at the larger whole scale.
  A tie goes to side by side in a window wider than tall. Each world draws
  with its rect in `GameViewport.forced` (a marked hook in
  `src/render/GameViewport.lua`). Its renderer fits the game into the rect
  as it fits the window in solo play, and clears only its own rect. At the
  start, a window that is not fullscreen or maximised grows to show both
  views at the scale it had (`Layout.grow`, within the desktop).
- **Input.** `Split.route` sends each event to the seat whose device sent
  it. The keyboard and the pads go to the seat that claimed them. A device
  no seat claimed goes nowhere. A pad plugged in or out, focus and
  visibility reach both games. The mouse and touch stay player 1's.
  Inside each game, upstream's `Input` filter (`Input.seatFilter`, #4) also
  keeps polled pads apart. Player 2's world sets `Input.seat = 2` on its
  own `Input`.

## Seat 2 in the session

- **Dial.** Player 2 dials the hosting session's loopback hub, or the
  address player 1 dialled (`Session.startDial` with `seat = 2`).
- **Identity.** Both seats remember their players in one `Identity`, under
  the host's key and their seat. Player 2 gets their trainer back in the
  next session (design A1.9).
- **Save slot.** Player 2 plays in the campaign's second slot on this
  device (`CoopSettings:enterSlot(..., 2)`, `slots[id].slot2`, named
  "<campaign> P2"), filled from the host's file on joining (design A3.14).
  The SAVES page counts it as the campaign's.
- **Log.** Player 2 writes a session log of its own,
  `session-<stamp>-<device>-seat2.jsonl`. One link per device carries the
  log, player 1's (#31).
- **Leaving.** Closing the app, or the session ending, ends both seats.
  Player 2 says goodbye first (`Session.shutdown` calls `Split.stop`,
  design A11.13). Opening the launcher stops split-screen.

## Checks

- ROM-free: `tests/coop/split_screen_test.lua` covers the layout, the
  routing and the worlds. It also runs the whole path with two fixture
  overworlds: this device hosts, player 2 joins as seat 2 in its own world,
  pad A walks player 1 and pad B player 2, and stopping says goodbye.
  `tests/coop/launcher_coop_test.lua` covers the two rows.
- Live (US Red, offscreen, 2026-10-15), with two fake pads of one model
  claimed in `coop/launcher.json` and `love.joystick.getJoysticks`
  replaced by the driver:
  - from the launcher: NEW CAMPAIGN, ENTER WITH 2 PLAYERS, both titles to
    the overworld, pad 1 walks only player 1, pad 2 only player 2;
  - player 2 saves, and the next run (HOST on the card, ENTER WITH 2
    PLAYERS) gives player 2 the same trainer on the cell they saved on;
  - a wild battle in player 2's world shows in their half, played with
    pad 2, while player 1 stays on the map.
  - A driver reaches the launcher only after a restart into it: write
    `relaunch_to_launcher.txt` (`return { tab = "red" }`) into the save
    folder first. The driver then runs on the launcher, and again in the
    game once it boots.
- Not run: real pads, a real window (its resize), audio, and a pair that
  joined a remote host.

## Not yet

- Player 2's trainer name is `PLAYER2` until a host knows them (the
  development entry takes a name); naming new players is #22.
- Player 2's game is silent (G23).
- Co-op battles (#18, #19) will feed each half's own menus (G2).
- Phone halves (design A15.3) are #7.
