# The fork's launcher

Upstream's launcher is proprietary (`LICENSE.MD` term 2): a fork may not use
it and must ship its own, which shows the credit line of term 1. This fork's
launcher is `src/coop/launcher/` (#3, decision G1 in [design.md](design.md)).
`main.lua` builds it in `makeLauncher`; the fresh start, a restart into the
launcher, the in-process return from a game, a `--game` shortcut to a game
with no ROM and a scripted import (`POKEPORT_IMPORT_ROM`) all land in it.

## What it does

A Game Boy style menu at the game's 160x144 resolution, scaled to the window
in whole steps:

- **Title**: RED, BLUE, YELLOW, ROT (DE) and BLAU (DE) (each marked NO ROM
  until imported; seven rows close up to one line apart), CREDITS, QUIT (not
  on mobile).
- **A game with no ROM**: drop the ROM file on the window, or type or paste
  (Ctrl+V) its path and press Enter. The ROM is checked by SHA-1 (clean US
  dumps and the German Rote and Blaue Edition, `.zip`/`.7z` where the
  platform opens them, [german.md](german.md)); a Gold or FireRed ROM is
  refused, since this launcher plays Gen 1. A dropped ROM is routed to its
  game whatever screen is showing. A scripted import (`POKEPORT_IMPORT_ONLY`)
  that fails prints the error and exits with 1.
- **An imported game**: CONTINUE (when the active save slot holds a save; name,
  badges and play time shown), NEW GAME, CO-OP (see *Co-op screens*), NEW ROM
  (import again), BACK. NEW GAME over a save starts in a new save slot, so the
  old save stays on disk; choosing between slots comes with #6.
- **Credits**: the credit line, the fork, the AI disclosure, the Plain Pixel
  font licence and the trademark notice.

The credit line ("Based on the Pokemon Gen 1 Recompilation Project by BOIS
CLUB GAMES, LLC (https://github.com/bryanthaboi/gen1recomp)") fills the
bottom six rows of every screen.

Text is drawn by the game's own `Font` renderer with the cartridge's font and
text box frames once any of the three games is imported. Before that there is
no cartridge font, so the launcher uses the bundled Plain Pixel face on a
canvas of twice the resolution (its glyphs are taller than a Game Boy row).

Controls: arrows or WASD move, Z / Enter / Space confirm, X / Backspace /
Escape go back; a pad's d-pad or left stick, A, B and Start; a mouse click or
a tap picks a row, a right click goes back.

## Co-op screens

CO-OP on a game's screen opens the co-op screens of that cartridge (#12,
design A2). They are drawn like the rest of the launcher, in Game Boy text
cells with the cartridge's font, boxes and cursor.

- **Co-op**: HOST, JOIN, LAST SESSION (when there is one: hosts the last
  campaign again, or dials the last host and joins at once when it knows this
  device), LOGS, BACK.
- **Host**: one card per campaign of this cartridge, latest hosted first,
  with its player count; NEW CAMPAIGN asks for the campaign's name and the
  player's own. A card shows the game it was started on, its players and when
  it was hosted last, and offers HOST, RENAME and DELETE. DELETE asks again
  and keeps the last state as `coop/campaigns/<id>.json.bak` in the save
  folder; renaming it back to `<id>.json` restores the card.
- **Hosting**: ENTER WORLD (at any time; partners can join later), the
  addresses partners join at (up to two, a VPN address first, then the home
  network, each labelled, the one a partner used last marked LAST USED; A
  copies one), the players in with the cartridge each plays when it differs,
  and STOP. STOP with a partner in asks first; the partner's game goes back to
  its launcher with "The host closed the session." The session keeps running
  while the launcher shows it and on into the game.
- **Join**: the hosts heard on the LAN beacon (one row per campaign, with the
  cartridge this device joins with, or NEEDS <GAME> when none fits), BY
  ADDRESS (an address with an optional `:port`), the recent addresses, BACK. A
  nearby host on another cartridge this device has imported is joined with
  that cartridge.
- **Connecting**: the address, then HOST FOUND, SAME VERSION, CARTRIDGE FITS.
  While nobody answers, the dial is tried again every 3 s for a minute, with
  a countdown, TRY NOW and CANCEL; after the minute "could not reach" and a
  checklist for the kind of address (a VPN address: the VPN on both devices;
  a home address: the same network and the firewall; a public address: port
  forwarding). A device the host knows sees one JOIN AS <name>; a new player
  can type a NEW NAME first. A refusal is named exactly ("The host plays RED.
  This game is BLUE."), with USE <GAME> when another imported cartridge fits.
  Once joined, the game starts.
- **Logs**: SHARE LOGS on or off (sharing of session logs with the session's
  players, #31) and, on desktop, OPEN FOLDER.
- **Text entry**: a grid in the style of the cartridge's naming screen, so a
  pad or a touch screen can type; an address opens on the digits. A keyboard
  types directly (Enter finishes, Escape cancels, Ctrl+V pastes).

Leaving a session in the game (closing its window, or the host stopping)
brings the launcher back on the co-op screen with the reason ("You left the
session.", "The host closed the session.").

The co-op screens remember on this device (`coop/launcher.json`): the
player's name, the last address and up to four recent ones, the cartridge
picked (preselected on the title screen), the last session and the
log-sharing switch.

**Progress until campaign files (#13).** Each device plays a campaign in a
save slot of its own, created and named after the campaign the first time
(decision G10 in [design.md](design.md)). ENTER WORLD and a join make that
slot the game's active one, so the cartridge's title screen offers NEW GAME
the first time and CONTINUE after. The launcher puts the solo slot back when
it opens again (a fresh empty slot when the game had none), so a solo
CONTINUE never opens a campaign's save.

## Files

- `Launcher.lua`: the object `main.lua` drives (update, draw, input callbacks,
  file drop), the font set-up, the import job and the boot.
- `Menu.lua`: the screens and cursor as a model with no `love.*` calls, plus
  the credit text.
- `RomImport.lua`: verify a ROM and fill its private cache. It uses the GPL
  import modules (`RomArchive`, `GameVersion.forSha1`, `CacheFs`,
  `CacheContract`, `ExtractThread`, `RomExtractor`), never `RomImporter.lua`.
- `CoopMenu.lua`: the co-op screens as a model, laid out in text cells; the
  session, campaigns and settings come in through an `env` (Launcher.lua
  passes the real ones, tests their own).
- `Keypad.lua`: the text entry grid.
- `CoopSettings.lua`: what the co-op screens remember on this device, and
  each campaign's save slot.
- `../Campaigns.lua`: the hosting device's campaign cards.

## What it leaves out

Nothing in the fork's boot path loads upstream's launcher: `RomImporter`,
`LauncherView`, `LauncherSettings`, `OnlinePanel`, `CartLabelArt`,
`CartShape`, `LauncherMods`, the Box panels, the ONLINE screens, and the
splash and theme videos that play files from `assets/launcher/`.
`tests/coop/launcher_boot_test.lua` checks `package.loaded` for all of them on
each boot path above. `LauncherWindow.lua` (the launcher's window size and
fullscreen memory) is not on the licence's list and stays.

Upstream features that only its launcher reaches are not offered yet: mod
management and mod updates before a shortcut boot (`main.lua` asks for none),
the save editor, the skin studio, the touch-controls editor, the Box, carts and
the other games. Settings, controls, save slots and mobile are #4 to #7.

## Save folder and upstream services

The fork keeps its saves, options, imported ROM caches and mods in its own
LÖVE save folder, identity `gen1recomp-coop` (`conf.lua`, decision G9 in
[design.md](design.md)); upstream uses `pokemon-love2d`, so an upstream
install on the same machine and the fork never read or write each other's
files. `POKEPORT_IDENTITY` still overrides the name, and the second display
(`--display-companion`) uses `gen1recomp-coop-companion`.

| System  | The fork's folder                                   | Upstream's folder                                 |
| ------- | --------------------------------------------------- | ------------------------------------------------- |
| Linux   | `~/.local/share/love/gen1recomp-coop/`              | `~/.local/share/love/pokemon-love2d/`             |
| macOS   | `~/Library/Application Support/LOVE/gen1recomp-coop/` | `~/Library/Application Support/LOVE/pokemon-love2d/` |
| Windows | `%APPDATA%\LOVE\gen1recomp-coop\`                   | `%APPDATA%\LOVE\pokemon-love2d\`                  |

To play an upstream save in the fork, close both games and copy everything
in upstream's folder into the fork's (create it if the fork has not run yet).
Copy the whole folder rather than single files: `options.lua` holds the save
slot list next to the settings, the saves are `saves/` and `save*.lua`, and
the imported ROM caches come along, so the games need no new import. The fork
has no import screen for this yet; #6 (save management) may add one.

Upstream's self-updater and cloud sync are off on the fork's path
(`src/coop/Upstream.lua`, #26). The updater asks upstream's releases and, in a
packaged build, would download and run upstream's game over the fork; cloud
sync talks to upstream's sync server for a device linked in upstream's
launcher. `main.lua` never runs the updater's boot shell, a launch request's
`--update` and `--sync` are dropped before the pre-launch screen, and
`SyncEngine.shared()` answers nil, so the game's save, focus and resume hooks
send nothing. Upstream's online features (Union Room, trades over its relay)
are not affected.

## Checked

Run on Linux desktop (LÖVE 11.5) with a US Red ROM, driven through
`main.lua`'s input callbacks: the Plain Pixel title, typing the ROM path,
the import, the cartridge font afterwards, NEW GAME into the game's intro,
the credits screen, and closing the game back to the launcher (the restart
path); no upstream launcher module was loaded. Pads, mouse, file drops and
the ROM checks are covered headless only; `.zip`/`.7z` ROMs, Ctrl+V,
Windows, macOS and mobile have not been run.

The co-op screens (#12) were run on the same Linux desktop with US Red, in
two game processes on one machine, each with its own save folder, driven by
frame drivers through the launcher's own press calls (no window, the
offscreen video driver):

- the host made a new campaign and hosted it; the partner's Join screen heard
  it on the LAN beacon (once, after the fix below), probed it (all three
  steps OK), typed a new name on the grid and joined; its game started in a
  new save slot named after the campaign;
- the hosting screen listed the partner, and the address the partner used as
  LAST USED; the host entered the world, both players' maps reached the
  other side, and the card kept both players;
- the host quit its game, which ended the session: the partner's game went
  back to its launcher's co-op screen with "The host closed the session.",
  and its solo save slot came back;
- a second run: LAST SESSION on the host hosted the campaign again, LAST
  SESSION on the partner rejoined in one press as the same player, and STOP
  with the partner in asked first, then sent the partner back to its
  launcher with the reason.

Screenshots of these screens were looked at locally (they show the
cartridge's font and stay out of the repository). The run found three
faults, now fixed and tested: a host on the same machine was listed twice
(heard on 127.0.0.1 and on its LAN address); a device with no save slot kept
the campaign's slot active for solo play afterwards; the cartridge font has
no `_` for the text field's blanks. Two machines on a LAN, pads, touch,
Windows, macOS and phones have not been run.

## Tests

`tests/coop/` runs in the `engine` group of `scripts/test.sh` (and so in
coop-ci): `launcher_menu_test.lua` drives the menu model and ROM checks,
`launcher_boot_test.lua` boots `main.lua` headless on the fixture dataset,
`upstream_services_test.lua` checks that no boot path reaches the updater or
cloud sync and that `conf.lua` uses the fork's identity, and
`driver_launcher_boot_test.lua` runs a frame driver that boots a game from the
launcher (#28). `launcher_coop_test.lua` (#12) runs two devices in one
process over a loopback hub that stands in for the network: hosting a new
campaign, finding it nearby (once per campaign), joining under a typed name,
the players and LAST USED on the hosting screen, STOP with a partner in and
the partner's return note, LAST SESSION on both sides, renaming and deleting
a card to its backup, the refusals and USE <GAME>, the retries every 3 s for
a minute and the checklists, a host that starts after the partner dialled,
the logs switch, the cartridge pick, each campaign's save slot and the solo
slot afterwards, the keypad and address kinds, and that every co-op screen
fits the 20x12 text cells. The ENet suite (`love tests/coop/enet`) has the
late host over real sockets.
