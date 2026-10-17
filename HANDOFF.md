# Handoff

The session note for this repository. Read it first in a fresh session and
rewrite it at the end of every session (issue loop, last step). It lives in the
repository so it survives any worktree path and any tool; per-checkout agent
memory is not read by a session that starts in another worktree. State goes
here; stable recipes go into `docs/coop/`; personal data and hardware never.

Last updated 2026-10-17 (#74 merged locally, its push waits for the owner; #72 in PR #76; #75 filed in Group 10).

## Testing rule (owner, 2026-10-16)

The session tests everything itself, live with the cartridge, on the
**integrated** branch: every scenario of a feature, through the fork's
launcher and the game's menus, including desktop situations (two windows,
focus lost and back, hidden and shown, a frozen or crashed window). It
fixes what breaks (failing test first) before reporting. The owner does
not playtest; they play through with a friend once most of the work is
done. The Dramatic Shape 3D mod (#30) is a hard requirement for that
playthrough, so every live run of a new feature also runs with the mod
on.

## Repository state

- Default branch `gen1recomp-coop`; `main` = upstream main.
- **Merged 2026-10-16** (owner): #58 (the private opening, #22) and #61
  (Group 11: #57, #59, #55, #23, #60, #9, #34, #30, #65, #66), both
  locally as Claude. CI passed every check on #61 (its first luacheck run
  found one W113 from #9, fixed). `tools/verify.sh` on `gen1recomp-coop`
  at 9741ed7d: ALL PASSED (37/37 tiers).
- **Merged 2026-10-16** (owner): #68 (Group 12: #62, #63, #64, #67),
  locally as Claude. CI passed every check on it, luacheck included.
- Protocol 18; campaign file version 5. Decisions G1 to G37 all accepted
  (G36 the owner's own call on #67; G37 accepted as built, 2026-10-16).
- **Merged 2026-10-17** (owner): #69 (#27), locally as Claude; the owner
  pushed the merge (the push-guard cannot review a merge commit with no
  patch of its own, so it needs the owner's `--no-verify` push).
- **Merged 2026-10-17** (owner said merge once coop-ci is green): #71
  (#70). Pushed as a **fast-forward** of `gen1recomp-coop` to the PR's
  head (the owner chose it over a merge commit: the push-guard cannot
  review a merge commit and the owner was away); no merge commit, #70
  closed.
- Protocol and campaign file unchanged by #27, #70 and #7. Decision G38
  (#27's entries) recorded from the owner's answers; G39 (#7) accepted
  as built (owner, 2026-10-17).
- **#74 merged locally** (2026-10-17, owner): merge commit `af169152`
  (as Claude) on top of `origin/gen1recomp-coop` (`3d3714d7`). The push
  was blocked by the auto-mode guard (a merge with no review), and the
  owner said they would push it themselves (`af169152:gen1recomp-coop`,
  with the push-guard bypass only the owner may use). Until then GitHub
  shows #74 open.
- Decision G40 (#72) proposed.
- Milestones: Groups 8, 11 and 12 closed. Group 2 has #12 and #15
  (owner-side checks). Group 9 has no issues. Group 10 now: #72 (in PR
  #76), #73 (A15.2 swipe and tap gestures on a phone) and #75 (the
  partner-battle notice's `>` has no glyph in the cartridge font).

## Open pull requests

- **#74** `coop/group10-mobile`: merged locally as `af169152` (see
  above). It closes once that commit is pushed.
- **#76** `coop/group10-quick-keys` → `gen1recomp-coop`, draft: #72
  (Closes). F1/SAVE saves the campaign and is refused with a notice
  wherever START > SAVE refuses. F2/LOAD loads nothing in a session.
  Notices age in real frames, so they last as long at 4X. G40 proposed;
  `docs/coop/campaign.md` § The quick keys. The branch starts at
  `af169152`, so its diff shows #74's commits until that merge is
  pushed. Verify: ALL PASSED at a184b2be (38/38 tiers). Live: two
  processes with US Red, once with the 3D mod (see the PR).

## #7's answers (owner, 2026-10-17: every recommendation taken)

- #74: the next session merges it locally as Claude once coop-ci is
  green (a merge commit, if `gen1recomp-coop` moved, is pushed by the
  owner with `--no-verify`).
- G39 accepted as built.
- Scratch `android-sdk/` and `android-build/` kept for #73; the
  emulator's app data was wiped (done; the AVD boots clean).
- `coop/group10-editor-close` deleted locally and on GitHub (done).

## #70's answers (owner, 2026-10-17: every recommendation taken)

- B after a refused window close asks once more: kept as built.
- #71: the next session merges it locally as Claude once coop-ci is
  green; the owner pushes the merge commit with `--no-verify`.
- `coop/group10-launcher-entries` deleted on GitHub and locally (done).
- #7: test on an Android emulator on this machine; split-screen on a
  phone left out for now.

## #27's answers (owner, 2026-10-16: every recommendation taken)

- This session: #27 (not #7).
- Save editor: EDIT on a solo save row; campaign worlds not editable.
- Skin studio and touch-controls editor: deferred to #7.
- Carts: left out for now; revisit after the playthrough.
- At the handoff: merge #69 locally as Claude once coop-ci passes on it
  (the next session does it, then removes this worktree); the editor's
  one early close is filed as #70 (Group 10), to be looked at again in a
  live run with a real mouse; BEARBEITEN and the refusal line are kept
  for the owner's later review in `german-wording.md`; the merged local
  branch `coop/group12-followups` is deleted.

## Group 12's answers (owner, 2026-10-16: every recommendation taken)

- #68 merged; G37 accepted as built.
- German "SO BEGINNT SPIELER 2", "So beginnt Spieler 2" and the subtitle:
  kept, for the owner's later review of `german-wording.md`.
- Cleanup: `g11/` scratch and the old local branches deleted. luacheck:
  the owner wants it locally, but it needs sudo (`sudo pacman -S
  luacheck`, Arch's `extra` repo; no luarocks on the machine), so the
  owner installs it. This worktree stays (the owner did not pick its
  removal); it is on the merged `coop/group12-followups`.
- What Group 12 did not run live: real pads, two real windows, Yellow,
  and player 2 playing the opening through.

## Group 11's detail choices (owner, 2026-10-16: every recommendation taken)

Each detail keeps the first, recommended option below; the German wording
stays for the owner's later review in `german-wording.md`. The follow-ups
it calls for are filed in **Group 12: Group 11 follow-ups**: #62 (one
trade core), #63 (a Cable Club trade owed, not lost), #64 (split-screen
player 2 chooses how they start). Yellow mixing stays unsupported for
good (#9's answer); a gift lost on a reset is accepted and documented
(#55).

### #59 rival scenes (G29)
1. Where a scene starts: accept as built (a script fighting the rival on a scene map while his flag is unset; one ScriptRunner hook) [rec] / explicit hooks per scene in data/scripts.
2. A far partner on a large map (Cerulean) also frozen: keep as A10.5 says [rec] / only within a distance.
3. Waiting box: A joins, START/SELECT opens CO-OP [rec] / YES/NO "JOIN?" prompt.
4. German "%s stellt sich hier dem Rivalen. Warte oder hilf im Kampf...": accept [rec] / owner wording.
### #9 Red and Blue (G33)
1. Switch lives on the hosting device's campaign card, changed between hostings [rec] / in the campaign file, changeable while hosting (file v5).
2. Substituted Pokémon level: player's own cartridge's slot level (D104) [rec] / the other version's level.
3. Yellow mixing: keep unsupported for good [rec] / follow-up to investigate same-family battles + flag translation.
4. Extra draw only on slots offering an exclusive [rec] / on every encounter as in the sibling fork.
### #57 starts (G28)
1. Accept G28 as built (launcher writes start world into the slot, window sends `start`, host decides) [rec] / host builds the Pallet world / drop `returning` refusal.
2. Yellow: START IN PALLET hidden until #9 captures its opening [rec] / offer now with guessed state.
3. Pallet starter stands at the blackout cell (5,6) [rec] / outside Oak's lab door.
4. German wording (SO BEGINNST DU, DER SPIELANFANG, START IN ALABASTIA, SPIELSTAND MITBRINGEN, WECHSELN): keep, review later [rec] / replacements.
5. Split-screen seat 2 choosing how to start: follow-up issue [rec] / nothing.
### #60 Cable Club (G32)
1. Rooms as link screens over the session (upstream's LinkState), not walkable maps: accept [rec] / walkable rooms follow-up.
2. Timeouts: 30 s from the first offer, 60 s from both offers, back to lists [rec] / 30 s waiting in the room for any partner.
3. Owed-trade gap (window drops after the host committed the swap before getting the yes -> clone risk): file follow-up [rec] / accept the narrow race.
4. German HANDELSCENTER / KOLOSSEUM: keep until checked on a German cartridge [rec] / read from the cartridge (importer change).
5. The continue fix moves solo saves out of the rooms too: keep for every save [rec] / co-op only.
### #23 friends (G31)
1. Friend battles = upstream's link battle over the session; host commits trades once: accept [rec] / rebuild on G24 record.
2. One trade per pairing, then back to the map [rec] / back to the trade screen until CANCEL.
3. A battle released after 2 min away still pays EXP for what was fought [rec] / pays nothing.
4. German wording of 16 lines (KAMPF %s, TAUSCH %s, "%s sagt NEIN.", "%s hat zu tun."): keep [rec] / owner revises.
### Integration
- Two trade cores now exist: #23's Trade.lua (each window swaps its own rows, host lays the swap over incoming worlds until shown) and #60's CableTrade.swap (host swaps stored worlds, window stamps the received uid). Unify in a follow-up [rec] / leave both.
### #55 League (G30)
1. Accept G30 (every lobby entry asks for the clear; clear held by League presence/fight/uninducted) [rec] / clear only after whiteout or induction.
2. A reset reopens the host's world (last holdings + last SAVE) [rec] / the device's last SAVE.
3. "Every connected player inducted" literal (includes players in the opening/elsewhere) [rec] / only players who entered the League this run.
4. A gift landed after the last holdings is lost on a reset: accept and document [rec] / follow-up: host re-sends owed gifts after a restart.

### Round 2 (integrated tests, #30, the itest agents): owner, 2026-10-16, every recommendation taken

Forfeit EXP became #67 (Group 12).

- Forfeit EXP farm (A12.5 pays "won or lost"; RUN on turn 1 paid 621 EXP): no EXP to the side that forfeits [rec] / only after a full turn / keep.
- Flood rule also hits the host's own loopback player at inhuman rates: leave [rec] / exempt loopback.
- G34 (the 3D mod) as written: accept [rec] / change.
- SELECT in a co-op session opens the CO-OP menu, the mod's camera on "3" and its OPTIONS row [rec] / the mod keeps SELECT everywhere.
- Own colour in 3D with SGB colours not shown on your own screen: accept and document [rec] / follow-up.
- MODS page in SETTINGS only [rec] / also on each solo sheet.
- T-SHIFT blur also blurs an arrow at the top/bottom edge: accept [rec] / follow-up.
- G35 (same window / same seat takes its player back, 5 s hold): accept [rec] / strict A1.9 with duplicates.
- G35 (a unique encounter nobody is in ends as fled when met again): accept [rec] / keep the 2-minute wait with a waiting box.
- A brought save loses its own story entries when the campaign has a story (MISTY's POKéDEX row): keep per A4.3 [rec] / follow-up to keep key items like the Pokédex.

## Next candidates

- **First:** check that `af169152` reached `origin/gen1recomp-coop` (#74
  closed). Then merge #76 if the owner says so.
- **#75** (Group 10, small): the partner-battle notice's `>`. First
  step: a test that draws every co-op notice and menu string with
  `Font` and fails on a missing glyph.
- **#73** (Group 10): A15.2 swipe/tap over the CO-OP menu and co-op
  battles on a phone. First step: a test feeding `love.touchmoved` over an
  open CO-OP menu; then the emulator (recipe below).
- Group 2's #12 and #15 are owner-side checks.

## Live-run recipe

- **Import.** Import US Red into a private folder with
  `POKEPORT_IMPORT_ONLY=1 POKEPORT_IMPORT_ROM=...` under a private
  `HOME`/`XDG_DATA_HOME`. Copy that data folder for each process.
- **Run.** Start each process offscreen (`SDL_VIDEODRIVER=offscreen
  SDL_AUDIODRIVER=dummy`) with `POKEPORT_DRIVER`, `POKEPORT_COOP_HOST`/`_JOIN`,
  `POKEPORT_COOP_NAME`, `stdbuf -oL` and **`POKEPORT_SPEED=4`**. The driver
  then runs four logic frames per rendered frame. Rest points count logic
  frames, so the checks hold, but waits on the network stay in real time.
- **Drivers.** `tests/drivers/util.lua` has `newGame`, `teleport`, `wait`
  and `tap`.
  - `dofile` it by an absolute path when the process starts outside the
    repository.
  - A driver reads `Session.current` (`client.state.players`, `window`,
    `host.state.story`, `host.state.players[i].gifts`) to sync with the
    other processes. Flag files in the run's scratch folder also work.
  - A guest's `newGame` and join take several thousand frames. Let the
    host wait for a "guest idle" flag, not a short timeout.
  - `U.teleport` moves the player off a cell that is not walkable (it logs
    `[warn] saved position ... not walkable`). Check the player's cell
    after a teleport.
- **Waits.** Wait for `src.ui.ChoiceBox` on top before pressing YES.
- **Quit.** Quit with `love.event.quit()` so the bye goes out. A guest
  whose host quits first goes back to its launcher and reruns its driver;
  let guests quit first.
- **Split-screen (#11).** `docs/coop/split.md` § Checks.
  - Claim two fake pads in `coop/launcher.json` (`seats`).
  - Replace `love.joystick.getJoysticks` in the driver and send real
    `love.gamepadpressed`/`released`.
  - `Split.current.game` is seat 2's game; run code inside its world with
    `Worlds.run(Split.current.world, fn)` (never across a yield).
  - To drive the launcher, write `relaunch_to_launcher.txt` first.
  - To check the mix without speakers: `ALSOFT_CONF` pointing at a file
    with `[general] drivers=wave` and `[wave] file=<scratch>/mix.wav`; the
    WAV is 32-bit float (WAVE_FORMAT_EXTENSIBLE), real time, so wait in
    real time (`love.timer.getTime()`), not in frames (offscreen runs
    uncapped).
- **Battles (#18-#20).** RED's driver builds a battle and pushes it the
  way the world does: `BattleState.newWild(Game, "RATTATA", 6)` (or
  `newTrainer(Game, "OPP_BUG_CATCHER", 1)`), `onFinish` calling
  `ow:afterBattle`, then `ow:pushBattle(b)`. GREEN joins with
  `Battles.join(Game, Battles.offers()[1].summary, name)`.
  - The battle on top with `.coop` is the copy. `Replica.question(b)` and
    `Replica.decider(b)` say what it asks and of whom; `Replica.send(b,
    cmd)` answers without the menus (a replacement: `{ kind = "replace",
    index = i }`); `Replica.leave(b)` leaves.
  - Tap A every few frames for the text, but not at your own menu question
    if the scenario must wait for a partner (A8.4 re-sends a command in
    flight).
  - A trainer's transition takes about 300 frames; give waits for the copy
    on top 8000 frames.
  - Check the host's session log (`coop/logs/*.jsonl` in RED's save folder)
    for `battle_desync`; `Replica.hash(b)` is the state digest each window
    reports.
  - A command sent before the host has the copy's question is refused
    `not_ready` and dropped: a driver resends until the copy moves on.
  - `newGame` gives both players the in-game name RED and no Pokémon:
    pick a partner by player id (`b.coop.me`), and give each player a
    Pokémon (`Pokemon.new`, `BattleState.stampOT`).
  - The host's copy of a world (`host.state:player(id).world`) follows the
    window's holdings at rest points; poll for a change, do not wait a
    fixed number of frames.
- **Trainers (#21).** VIRIDIAN_FOREST object 2, a BUG CATCHER at
  (30,33) facing left, sight 4: stand at (27,33) facing right to be
  spotted; (29,33) facing right and A talks to it. The overworld's
  `npcPool["VIRIDIAN_FOREST_obj_2"]` is the trainer.
- **The opening (#22).** `tests/drivers/util.lua`'s `newGame` mashes A
  through Oak's speech (it types the rival's name as AAAAAAA). To play the
  opening: `U.teleport(game, "PALLET_TOWN", 10, 2, "up")`, walk up until
  Oak's script holds the player, mash A until
  `EVENT_OAK_ASKED_TO_CHOOSE_MON` and the lab is idle, teleport to
  `OAKS_LAB` (6, 7 or 8, 4) facing up, mash A for the ball, walk down to
  the rival battle, mash A through it, then to the door at (4/5, 11):
  tap A whenever something holds the player (the rival's walk-out lines).
  A test client with no world in the campaign is in the opening until it
  sends `sendOpening(true)`.
- **Launcher-driven runs and the 3D mod.** The integrated tests drove the
  fork's launcher: write `relaunch_to_launcher.txt` (`return { tab = "red" }`)
  in the save folder, and the driver gets the launcher (`arg.menu`) first,
  then the game. Set the ports in the driver (`Transport.DEFAULT_PORT`,
  `Beacon.PORT`, the launcher's `CoopMenu.DEFAULT_PORT`). Install the mod
  by hand per run: copy the owner's downloaded copy
  (`~/dev-scratch/gen1recomp-coop/mod-dl/dsv`, never committed: its
  licence forbids redistribution) to `<save folder>/mods/dsv`, then
  `require("src.render.Pipelines").setLevel("voxel", 4)` in the driver.
  Drivers and save templates of Group 11 are in
  `~/dev-scratch/gen1recomp-coop/g11/` (`itest1/`, `itest2/`, `fin/`,
  `tpl/a`, `tpl/b` with four solo saves each; `itest1/regress.sh` reruns
  every itest1 scenario; their worktree paths point at the removed
  `wt/itest1`, so edit `WT` in `run.sh` to the new worktree). `tpl/`
  holds extracted cartridge data: never commit it.
- **Trades and other owed things (Group 12).**
  - An owed trade lands only at a rest point: the driver must stand still
    on the map (no text box, no menu) for it to apply.
  - After a rejoin, the owed trade's "Trade completed!" can be on screen
    before the driver's first on-map check. Wait for the map, and watch
    the text from the moment of REJOIN.
  - After "The link was broken." a Cable Club guest is back at the Cable
    Club's menu, not on the map.
  - Set the voxel level after CONTINUE, not at the title.
  - Group 11's and 12's drivers and save templates are deleted. A new
    live run imports the cartridge again (*Import* above) and makes new
    solo saves with `newGame`.
- **Real pads (2026-10-16).** This machine's connected controllers are
  visible to an offscreen LÖVE run. A driver that uses no pads should
  replace `love.gamepadpressed` and the other joystick callbacks with
  no-ops and `love.joystick.getJoysticks` with an empty list.
- **Real input (#70).** `gamescope --backend headless -W 1280 -H 900 -w
  1280 -h 900 -- run.sh` with `env -u WAYLAND_DISPLAY -u DISPLAY` and a
  private `XDG_RUNTIME_DIR` (mode 700) runs the game with
  `SDL_VIDEODRIVER=x11` on gamescope's own Xwayland, off the owner's
  screen. python-xlib's XTEST sends real pointer moves, clicks and keys;
  gamescope puts the one window at the root origin, so window coordinates
  are root coordinates. A window close is a `WM_PROTOCOLS` /
  `WM_DELETE_WINDOW` client message; a focus loss is a second mapped X
  window taking `set_input_focus`. The editor's buttons: set
  `Kit.audit = {}` before each draw and read the `control` entries by
  label. Real pads still reach the process: mute them (*Real pads*) unless
  the run is about pads. Drivers were in `g10b/` (deleted).
- **The save editor (#27).** main.lua does not resume the driver while
  the editor runs. Wrap `love.update` in the driver to act on
  `package.loaded.App.getState()` and call `App.save()` and `App.close()`,
  the calls its buttons make.
- **Android emulator (#7).** Everything under
  `~/dev-scratch/gen1recomp-coop/` (not in the repo): `android-sdk/setup.sh`
  installs the SDK without root, `android-sdk/emu.sh` starts the headless
  AVD `coop34` (port 5580; `-wipe-data` resets it), `bin/` has `adbe`
  (adb to that emulator), `taptext "Text"` (tap a system view via
  uiautomator), `pad a|b|start|select|up|down|left|right [n] [gap]` (the
  built-in on-screen pad in portrait) and a Python stand-in `zip` (this
  machine has no `zip`; put `bin/` first on PATH for
  `tools/build_android.sh`). Build with `--abi x86_64`, `adbe install -r`.
  `adbe shell input keyevent KEYCODE_DPAD_DOWN` / `KEYCODE_Z` reach the
  game as keys. The emulator reaches this machine as 10.0.2.2: host on the
  desktop (offscreen LÖVE, `POKEPORT_COOP_HOST`), JOIN by address on the
  phone. A desktop host from `newGame` is in its own opening (sees nobody):
  give it `EVENT_GOT_STARTER` and a party Pokémon first. Taps are window
  pixels of the 1080 x 2400 screen. The voxel mod builds its cache once
  (about 5 min on the emulator).
- **Quick keys and speed (#72).**
  - A scripted run pins `Game.speedOverride = 1` (main.lua), so the
    speed key does nothing. To test GAME SPEED, set
    `game.speedOverride = nil` in the driver, then send
    `love.keypressed("1")`.
  - A driver run steps `Game:update(1/60)` once per yield, uncapped, so
    real seconds mean nothing. Count driver frames (`U.frame()`) and
    logic frames (`Presence.frame`) instead.
  - Send keys with `love.keypressed(key)`: that is the path the touch
    quick bar takes.
  - The player's cell is `ow.player.cellX`/`cellY`.
  - A joiner enters a co-op battle at a turn boundary. The battle's
    owner must keep fighting; a driver that waits for the joiner's
    copy before acting deadlocks.
  - A party menu can open over the copy for a replacement, so look for
    the copy (`state.coop`) anywhere in the stack, not only on top.
- **Loopback test clients** need a hex `device` id (`"c1"`, not `"y1"`):
  the protocol drops a hello with another one.
- **Cells used for #16:**
  - Viridian Forest ANTIDOTE: stand at (25,12) facing up.
  - Viridian Forest POTION: (11,29) facing right.
  - Daisy: BLUES_HOUSE (2,4) facing up.
  - The bike shop clerk: BIKE_SHOP (6,4) facing up.

## Worktrees and background processes

- Main checkout on `gen1recomp-coop` (behind origin until pulled; leave
  it to the owner).
- The Superset worktree `veiled-degree-…` is on `coop/group10-quick-keys`
  (PR #76). The local branch `coop/group10-mobile` (#74) can be deleted,
  locally and on GitHub, once `af169152` is pushed.
- No background processes.
- Scratch: `g72/` (#72's import, drivers, runs, the pre-fix worktree) is
  deleted.
  `android-sdk/` (9.7 GB: SDK, NDK, emulator, the AVD `coop34`,
  app data wiped) and `android-build/` (1.2 GB, incremental gradle tree)
  are kept for #73 (owner); `bin/` holds the helpers above; `mod-dl/dsv` is the owner's
  copy of the 3D mod (never committed); `verify/` holds verify logs.

## Still open

- After each `main` sync: `gh workflow list -R Clodmony/gen1recomp-coop --all`
  and disable upstream's workflows.
- Local tools: luacheck is not installed yet; the owner runs `sudo pacman
  -S luacheck` (then `tools/verify.sh` runs the lint gate too). CI gates
  it on every pull request. JDK 17 is installed. `zip` is not installed
  (`sudo pacman -S zip`); until then `tools/build_android.sh` runs with the
  stand-in in scratch `bin/`.

## Cleanup

- Done 2026-10-15 (owner approved): every merged branch, locally and on
  GitHub (the two above excepted); the milestones of Groups 1 to 7a.
- Done 2026-10-16: #58's and #61's branches on GitHub, Group 8's and
  Group 11's milestones; after #68: its branch on GitHub, Group 12's
  milestone, `g11/` and `g12/` scratch, the old local branches.
