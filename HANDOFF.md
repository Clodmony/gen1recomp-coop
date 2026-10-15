# Handoff

The session note for this repository. Read it first in a fresh session and
rewrite it at the end of every session (issue loop, last step). It lives in the
repository so it survives any worktree path and any tool; per-checkout agent
memory is not read by a session that starts in another worktree. State goes
here; stable recipes go into `docs/coop/`; personal data and hardware never.

Last updated 2026-10-15 (after Group 6, #51, PR #52 stacked on #50).

## Repository state

- Default branch `gen1recomp-coop`; `main` = upstream main. Groups 1 to 5a
  are merged (#42-#49, 2026-10-15).
- Milestones: Group 6 is done by #50 (#11) and #52 (#51), open until the
  owner merges. Group 2 still has #12 and #15 (owner-side checks); Groups
  7, 7a, 8, 9, 10 are open.

## Open pull requests (draft)

- **#50** `coop/group6-split-screen` into `gen1recomp-coop`: closes #11,
  local split-screen. `src/coop/split/` (Worlds, Layout, Split), docs
  `docs/coop/split.md`, decision **G23** (accepted 2026-10-15).
  - The second seat's game is a second set of the game's modules
    (`package.loaded` swapped per world), silent, a loopback (or remote)
    client as seat 2, in the campaign's `slot2`, with a `-seat2` log.
  - Launcher: ENTER / JOIN WITH 2 PLAYERS when CONTROLS has a device for
    each player; dev entry `--coop-split[=NAME]`.
  - The one upstream file touched: `src/render/GameViewport.lua`
    (`Viewport.forced`, marked).
  - Verify: 36/37 (only the javac tier fails locally; no luacheck locally).
  - Live (US Red, offscreen, two fake pads): launcher host + ENTER WITH 2
    PLAYERS, pads routed per seat, seat 2 saved and continued its world in
    a second run, a wild battle in seat 2's half. Not run: real pads, a
    real window (resize), audio, a split pair joining a remote host.
  - CI (coop-ci, luacheck included) passed.
  - **Owner (2026-10-15): merge after their own check with two real pads**
    from the launcher in a real window. Once they say so, merge locally as
    Claude (`git merge --no-ff`), push, run `tools/verify.sh`.
- **#52** `coop/group6-split-sounds` into `gen1recomp-coop`, **stacked on
  #50** (branched from it; merge #50 first, then #52 shows only its own
  commit): closes #51, player 2's sound effects in the window's one mix.
  - Player 2's world runs with `love.sound` and a guarded `love.audio`
    (`Worlds.guardAudio`: no stop/pause of every source, no `set*`), still
    without `love.thread`; `Split.musicOff` keeps player 2's music off.
  - No upstream file touched. Docs: split.md, G23 in design.md.
  - Live (US Red, offscreen, mix written to a WAV by OpenAL Soft's wave
    driver): player 2's START sounds alone in the mix with player 1's
    music at 0, on top of the song at 7; player 1's song played on.
  - **Owner (2026-10-15): merge #50 first, then #52**, both after their
    check with two real pads (now also listening for player 2's sounds).
    Merge each locally as Claude (`git merge --no-ff`), push, run
    `tools/verify.sh` after each.
  - Verify: 36/37 (only the javac tier fails locally; no luacheck locally).

## Next candidates

- **Owner (2026-10-15): the next session takes Group 7** (battles).

- **Group 7 (#18, #19, #20, #34)**, battles: co-op battles against the game
  (rules), then their presentation with the cartridge's menus. Split-screen
  already gives each seat its own battle screen (G2); #19 feeds both.
- **Group 7a (#17)** party and PC at rest points (design A7).
- Group 2 still has #12 and #15 (owner-side checks).
- Player 2 names themself with #22 (owner, 2026-10-15; comment on #22).

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
- **Cells used for #16:**
  - Viridian Forest ANTIDOTE: stand at (25,12) facing up.
  - Viridian Forest POTION: (11,29) facing right.
  - Daisy: BLUES_HOUSE (2,4) facing up.
  - The bike shop clerk: BIKE_SHOP (6,4) facing up.

## Worktrees and background processes

- Main checkout on `gen1recomp-coop` (leave it; it is behind origin until
  pulled). The Superset worktree that held `coop/group6-split-screen` now
  holds `coop/group6-split-sounds` (pushed, clean); `coop/group6-split-screen`
  stays as a local branch too. No background processes. #51's scratch is
  deleted.

## Still open

- After each `main` sync: `gh workflow list -R Clodmony/gen1recomp-coop --all`
  and disable upstream's workflows.
- Optional local tools: JDK 17 (`javac`), luacheck.

## Cleanup the owner may approve

- Done 2026-10-15 (owner approved): old scratch and `g2a/`; the merged
  local branches `coop/10-session-core`, `coop/25-german`,
  `coop/group1-cleanup`, `coop/group2-first-playable`; the finished
  milestones (Groups 1, 2a, 3, 4, 5, 5a) closed; every merged branch
  deleted on GitHub.
- Done 2026-10-15: the local branch `coop/group5a-story-items`; its
  worktree carried on as Group 6's.
- Once #50 and #52 are merged: this worktree and the branches
  `coop/group6-split-screen` and `coop/group6-split-sounds`.
- Kept by the owner's choice: the other merged local branches
  (`coop/group2a-*`, `coop/group3-*`, `coop/group4-*`, `coop/group5-*`,
  `coop/workflow-groups`); the main checkout is not pulled.
