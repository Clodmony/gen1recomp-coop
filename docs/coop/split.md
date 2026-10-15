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
- **No workers.** Player 2's world runs without `love.thread`. The
  background workers' channels are process-global, so a second world's
  workers would take the first one's results. Every upstream module has a
  path without them, the one the headless tests run: player 2's chip sound
  effects render on the main thread when they first play (12 of them took
  53 ms together in the live run, 17 ms at most), and its sources are
  cached from then on.
- **One mix** (decision G23, #51). The window plays player 1's music and
  both players' sound effects. Player 2's world makes sources of its own
  through a guarded `love.audio` (`Worlds.guardAudio`, world option
  `sounds`): `stop`, `pause` and `play` act only on the sources they are
  given, and every `set*` (the master volume, the listener, the mix with
  the system's audio) is dropped, so player 2 cannot silence or retune
  player 1. Player 2's sound waits take the real lengths of its sounds.
- **Music off for player 2.** `Split.musicOff` makes player 2's `Music`
  (its own world's module) start no song, as without `love.audio`. Player
  1's song plays on, and a jingle player 2 waits for (`Music.playOnce`)
  takes its silent timing. A fanfare of player 2 ducks the `Music` of its
  own world only, so player 1's song does not pause under it.

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
  `tests/coop/launcher_coop_test.lua` covers the two rows. Sounds (#51):
  a world with sounds makes its sources in the process's mix and cannot
  stop, pause or set the whole device; in the whole path, player 2's sound
  effect plays in the window's mix with its real wait, player 2's music
  makes no source, and player 1's song plays on.
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
- Live sounds (US Red, offscreen, 2026-10-15, #51), the development entry
  (`--coop-host --coop-split=BLUE`) with OpenAL Soft writing the mix to a
  WAV file instead of a device (`ALSOFT_CONF` with `drivers=wave` and
  `[wave] file=...`): both players to the overworld, player 1's Pallet
  Town song playing; with player 1's music at level 0 the file is silent
  except player 2 opening and closing their START menu; at level 7 player
  2's sound sits on top of the song, which plays on. Player 2's music
  stayed off.
- Not run: real pads, a real window (its resize), listening on speakers,
  and a pair that joined a remote host.

## Player 2's name

ENTER WITH 2 PLAYERS and JOIN WITH 2 PLAYERS ask PLAYER 2 NAME first,
offering the name remembered on this device (`name2` in
`coop/launcher.json`), so player 2 names themself as any new player does
(#22, [opening.md](opening.md)). Oak's speech then uses that name. The
development entry takes `--coop-split=NAME`; without a name the second
seat is `PLAYER2` until a host knows them.

## Not yet

- Player 2's world does not get the device events of mobile platforms
  (`love.handlers.audiosuspend`/`audioreset` reach player 1's modules
  only); split-screen is not run on a phone.
- Co-op battles (#18, #19) will feed each half's own menus (G2).
- Phone halves (design A15.3) are #7.
