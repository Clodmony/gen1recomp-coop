# The fork's launcher

Upstream's launcher is proprietary (`LICENSE.MD` term 2): a fork may not use
it and must ship its own, which shows the credit line of term 1. This fork's
launcher is `src/coop/launcher/` (#3, decision G1 in [design.md](design.md)).
`main.lua` builds it in `makeLauncher`; the fresh start, a restart into the
launcher, the in-process return from a game, a `--game` shortcut to a game
with no ROM and a scripted import (`POKEPORT_IMPORT_ROM`) all land in it.

## What it does

The launcher follows #38's design (decision G13 in [design.md](design.md)):
a quiet shell, green LCD panels, one ink and an accent, in a light and a dark
set, drawn in the bundled Plain Pixel face. No cartridge graphics, fonts or
upstream launcher assets appear in it. Its words come from one catalog in
English and German (#41, decision G14): see *Language* below.

Every page has the top bar (GEN1 CO·OP, UNOFFICIAL FORK and the tabs PLAY,
CAMPAIGNS, CONTROLS, SETTINGS, HELP, and QUIT on desktop), the page itself and
the footer: the controls of the device in use and the credit line ("Based on
the Pokemon Gen 1 Recompilation Project by BOIS CLUB GAMES, LLC
(https://github.com/bryanthaboi/gen1recomp)"), word for word in every
language, under every page and every message.

- **PLAY**: the hero ("One story. Two journeys."), the cartridges RED, BLUE,
  YELLOW, ROT, BLAU and GELB (Rote, Blaue and Gelbe Edition,
  [german.md](german.md)), each
  READY or IMPORT ROM; what fits today (the same cartridge on both sides);
  PLAY SOLO; HOST A CAMPAIGN, JOIN A FRIEND, and COUCH CO-OP marked PLANNED
  and not offered until #4 and #11 work; IMPORT ROM for a cartridge with no
  ROM; LAST SESSION with HOST AGAIN or REJOIN.
- **Solo**: CONTINUE (when the active save slot holds a save; name, badges and
  play time shown), NEW GAME, IMPORT AGAIN. NEW GAME over a save starts in a
  new save slot, so the old save stays on disk; choosing between slots comes
  with #6.
- **Import**: drop the ROM file on the window, or type or paste (Ctrl+V) its
  path and press Enter. The ROM is checked by SHA-1 (clean US dumps and the
  German Rote, Blaue and Gelbe Edition, `.zip`/`.7z` where the platform opens
  them);
  a Gold or FireRed ROM is refused, since this launcher plays Gen 1. A dropped
  ROM is routed to its game whatever page is showing. A scripted import
  (`POKEPORT_IMPORT_ONLY`) that fails prints the error and exits with 1.
- **CAMPAIGNS**: every campaign on this device (see *Co-op screens*).
- **CONTROLS**: the launcher's keys, pad buttons, mouse and touch; per-player
  devices are marked PLANNED (#4).
- **SETTINGS**: LANGUAGE (ENGLISH or DEUTSCH) and THEME (LIGHT or DARK).
  Video, sound and game options stay in each game's own OPTIONS menu until #5.
- **HELP**: how partners connect, SHARE LOGS (on by default; session logs go
  to the session's players and hold trainer names and addresses) and OPEN LOGS
  FOLDER on desktop, and the credits: the credit line, the fork, the AI
  disclosure, the Plain Pixel font licence and the trademark notice.

**Size.** The launcher's pixels are whole multiples of the window's: the
largest scale that leaves at least 480 x 400 launcher pixels (a 1024 x 768
window shows it at 1x, 1920 x 1080 at 2x as 960 x 540). Pages are laid out
for the size they get: a centred column up to 640 pixels wide, two columns
side by side from 460, the cartridges three to a row when five do not fit, a
page shorter than the window a third of the way down, a taller one scrolled
(the focus is kept in view; the wheel and Page Up/Down scroll too). The game
keeps its own 160 x 144 renderer.

**Controls.** Arrows or WASD, a pad's d-pad or left stick move the focus to
the nearest target in that direction; Z, Enter or Space and A or START
confirm; X, Escape or Backspace and B go back. A mouse click or a tap picks a
target and a right click goes back; hovering moves the focus. Keys, pads,
mouse and touch walk one order of targets, and the footer names the controls
of the device used last.

## Language

Every player-facing launcher string goes through `Text.lua` (#41), keyed by
its English source like upstream's `Strings`; the German entries are in
`TextDe.lua` and listed for review in [german-wording.md](german-wording.md).
The launcher's language is the SETTINGS choice, kept in `coop/launcher.json`;
before one is made it follows the system's locale (`LC_ALL`, `LC_MESSAGES`,
`LANGUAGE`, `LANG`: German starts the launcher in German, anything else in
English). Windows and an app opened from macOS' Finder set none of these, so
there the launcher starts in English. A game's own text follows its cartridge,
not this setting (D95, D102). Plain Pixel has the umlauts and ß, and the
launcher no longer draws with a cartridge's font, so an English cartridge
needs no fallback. The credit line stays English, as licence term 1 asks.

`luajit tools/launcher_strings.lua` lists the catalog keys found in the
launcher's source (`--missing`: those with no German entry).

## Co-op screens

HOST A CAMPAIGN, JOIN A FRIEND, LAST SESSION and the CAMPAIGNS tab open the
co-op screens of the picked cartridge (#12, design A2). A session started
there keeps running while the launcher shows it and on into the game.

- **Choose your campaign** (HOST A CAMPAIGN) and **Your campaigns** (the
  CAMPAIGNS tab, every cartridge): one card per campaign, latest hosted first,
  with its cartridge, players and when it was hosted last, and HOST, RENAME and
  DELETE. HOST is offered when the card's cartridge is imported here. DELETE
  asks again and keeps the last state as `coop/campaigns/<id>.json.bak` in the
  save folder; RESTORE BACKUP brings the card back. NEW CAMPAIGN asks for the
  campaign's name and the trainer's (16 and 7 characters) and hosts it.
- **Hosting**: the players in (this device's player marked, a partner on
  another cartridge named with it) out of the host's player limit, the
  addresses partners join at (up to two, a VPN address first, then the home
  network, each labelled, the one a partner used last marked LAST USED; COPY
  copies one), a warning when the port is busy or no network was found (then
  only this device can join), STOP HOSTING and ENTER THE WORLD (at any time;
  partners can join later). STOP HOSTING with a partner in asks first; the
  partner's game goes back to its launcher with "The host closed the
  session."
- **Join a friend**: the hosts heard on the LAN beacon (one card per
  campaign, with its cartridge, language and players, and whether this
  device's cartridge fits, which other imported one joins, or which one it
  needs), BY ADDRESS (a host name or address with an optional `:port`), the
  recent addresses. A nearby host on another cartridge this device has
  imported is joined with that cartridge.
- **The connection check**: HOST FOUND, CO-OP PROTOCOL MATCHES and CARTRIDGE
  FITS, each ticked, crossed or waiting. While nobody answers, the dial is
  tried again every 3 s for a minute, with a countdown, TRY NOW and CANCEL;
  after the minute "could not reach" and a checklist for the kind of address
  (a VPN address: the VPN on both devices; a home address: the same network
  and the firewall; a public address: port forwarding). A device the host
  knows sees one JOIN AS <name>; a new player can type a NEW NAME first. A
  refusal is named exactly ("The host plays RED. This game is BLUE.", another
  language, another dump, another protocol, a full or closing session), with
  USE <GAME> when another imported cartridge fits. Once joined, the game
  starts.
- **Text entry**: a grid in the style of the cartridge's naming screen, so a
  pad or a touch screen can type; an address opens on the digits. A keyboard
  types directly (Enter finishes, Escape cancels, Ctrl+V pastes).

Leaving a session in the game (closing its window, or the host stopping)
brings the launcher back on PLAY with the reason ("You left the session.",
"The host closed the session.").

The launcher remembers on this device (`coop/launcher.json`): the player's
name, the last address and up to four recent ones, the cartridge picked, the
last session, the log-sharing switch, the language and the colours.

**Progress until campaign files (#13).** Each device plays a campaign in a
save slot of its own, created and named after the campaign the first time
(decision G10 in [design.md](design.md)). ENTER THE WORLD and a join make that
slot the game's active one, so the cartridge's title screen offers NEW GAME
the first time and CONTINUE after. The launcher puts the solo slot back when
it opens again (a fresh empty slot when the game had none), so a solo
CONTINUE never opens a campaign's save.

## Files

- `Launcher.lua`: the object `main.lua` drives (update, draw, input callbacks,
  file drop, wheel), the import job, the boot, painting a page and the focus.
- `Menu.lua`: tabs, PLAY, solo, import and settings as a model with no
  `love.*` calls, plus the credit text.
- `CoopMenu.lua`: the co-op screens as a model; the session, campaigns and
  settings come in through an `env` (Launcher.lua passes the real ones, tests
  their own).
- `Screens.lua`: every page laid out from the models' rows and details.
- `Ui.lua`: the page's nodes, text widths and wrapping, and the focus moves.
- `Theme.lua`: the light and dark colours. `Games.lua`: the cartridges.
- `Text.lua`, `TextDe.lua`: the launcher's words and their German.
- `RomImport.lua`: verify a ROM and fill its private cache. It uses the GPL
  import modules (`RomArchive`, `GameVersion.forSha1`, `CacheFs`,
  `CacheContract`, `ExtractThread`, `RomExtractor`), never `RomImporter.lua`.
- `Keypad.lua`: the text entry grid.
- `CoopSettings.lua`: what the launcher remembers on this device, and each
  campaign's save slot.
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

The first shell (#3) was run on Linux desktop (LÖVE 11.5) with a US Red ROM,
driven through `main.lua`'s input callbacks: typing the ROM path, the import,
NEW GAME into the game's intro and closing the game back to the launcher (the
restart path); no upstream launcher module was loaded. The co-op screens
(#12) were run in two game processes on one machine (host, nearby join, enter
the world, the host closing the session, LAST SESSION on both sides). Two
machines on a LAN, pads, touch, Windows, macOS and phones have not been run.

The redesign (#38, #41) was run on Linux desktop (LÖVE 11.5, the offscreen
video driver) by a frame driver that opened every page and saved each frame:
English and German at 1024 x 768, German at 480 x 400 and 540 x 960, and the
dark colours in English at 960 x 864; the pages were looked at locally. The cartridges' ready
flags were set by the driver, so no ROM was imported and no game booted in
that run; the session in the hosting page was a real in-process host with
networking off, and the join and connection pages showed sessions the driver
made up. A second run used two game processes on one machine, each with
its own save folder and an imported US Red, driven through the pages'
targets as a click would: the host made a new campaign and hosted it, the
partner found it on Join a friend, its check showed all three steps ticked,
it joined, and both entered the game with both players in the session. Two
machines on a LAN, pads, touch, the system-language default on a German
desktop, Windows, macOS and phones have not been run with the new pages.

## Tests

`tests/coop/` runs in the `engine` group of `scripts/test.sh` (and so in
coop-ci): `launcher_menu_test.lua` drives the menu model (tabs, cartridges,
solo, import, settings) and the ROM checks; `launcher_ui_test.lua` (#38, #41)
lays out every page in English and German at four sizes and checks that each
keeps the credit line, fits the page and can be walked with the arrows, that
no German page falls back to English and that every catalog key has a German
entry with the same directives; `launcher_boot_test.lua` boots `main.lua`
headless on the fixture dataset and drives the launcher with keys, a pad, the
mouse, the wheel and a file drop; `upstream_services_test.lua` checks that no
boot path reaches the updater or cloud sync and that `conf.lua` uses the
fork's identity; and `driver_launcher_boot_test.lua` runs a frame driver that
boots a game from the launcher (#28). `launcher_coop_test.lua` (#12) runs two
devices in one process over a loopback hub that stands in for the network:
hosting a new campaign, finding it nearby (once per campaign), joining under a
typed name, the players and LAST USED on the hosting page, STOP HOSTING with a
partner in and the partner's return note, LAST SESSION on both sides,
renaming, deleting and restoring a card, the refusals and USE <GAME>, the
retries every 3 s for a minute and the checklists, a host that starts after
the partner dialled, each campaign's save slot and the solo slot afterwards,
the keypad and address kinds, and that every co-op page fits a 480 x 400
launcher with the credit line. The ENet suite (`love tests/coop/enet`) has the
late host over real sockets.
