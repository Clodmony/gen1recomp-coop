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
  badges and play time shown), NEW GAME, NEW ROM (import again), BACK.
  NEW GAME over a save starts in a new save slot, so the old save stays on
  disk; choosing between slots comes with #6.
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

## Files

- `Launcher.lua`: the object `main.lua` drives (update, draw, input callbacks,
  file drop), the font set-up, the import job and the boot.
- `Menu.lua`: the screens and cursor as a model with no `love.*` calls, plus
  the credit text.
- `RomImport.lua`: verify a ROM and fill its private cache. It uses the GPL
  import modules (`RomArchive`, `GameVersion.forSha1`, `CacheFs`,
  `CacheContract`, `ExtractThread`, `RomExtractor`), never `RomImporter.lua`.

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
the other games. Settings, controls, save slots, mobile and the co-op screens
are #4 to #7 and #12.

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

## Tests

`tests/coop/` runs in the `engine` group of `scripts/test.sh` (and so in
coop-ci): `launcher_menu_test.lua` drives the menu model and ROM checks,
`launcher_boot_test.lua` boots `main.lua` headless on the fixture dataset,
`upstream_services_test.lua` checks that no boot path reaches the updater or
cloud sync and that `conf.lua` uses the fork's identity, and
`driver_launcher_boot_test.lua` runs a frame driver that boots a game from the
launcher (#28).
