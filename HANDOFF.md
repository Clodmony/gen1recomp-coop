# Handoff

The session note for this repository. Read it first in a fresh session and
rewrite it at the end of every session (issue loop, last step). It lives in the
repository so it survives any worktree path and any tool; per-checkout agent
memory is not read by a session that starts in another worktree. State goes
here; stable recipes go into `docs/coop/`; personal data and hardware never.

Last updated 2026-10-15 (after Group 7, PR #53).

## Repository state

- Default branch `gen1recomp-coop`; `main` = upstream main. Groups 1 to 6
  are merged (#42-#50, #52; #50 and #52 merged 2026-10-15 at the owner's
  word, verify 36/37 after).
- Milestones: Group 7 is done by #53 (#18, #19, #20; #34's battle parts),
  open until the owner merges. Group 2 still has #12 and #15 (owner-side
  checks); Groups 7a, 8, 9, 10 are open.

## Open pull requests (draft)

- **#53** `coop/group7-battles` into `gen1recomp-coop`: closes #18, #19,
  #20; part of #34.
  - Co-op battles are lockstep: every window runs the game's own battle
    from the host's record (opening, seed, numbered inputs); the host runs
    no engine. Decision **G24** (proposed, the owner's to accept).
    `docs/coop/battles.md` has everything.
  - New: `src/coop/battle/` (HostBattles, Replica, View),
    `src/coop/game/Battles.lua`, protocol 7, the session's in-game redial.
  - Upstream files touched (marked): `OverworldController.pushBattle`
    (hook), `BattleState` (`sendOutReplacement`, `expAward`,
    `expTrainerId`), `main.lua` `love.focus`/`love.visible` (resume).
  - Verify 36/37 (only javac). CI (coop-ci, luacheck included) passed.
  - Live (US Red, two ENet processes): see the PR and battles.md
    *Checked*. Not run: real pads, menus by hand, three players,
    split-screen battles, a trainer using items.
  - Merge locally as Claude (`git merge --no-ff`), push, run verify, once
    the owner says so.

## Next candidates

- **Group 7a (#17)**: party and PC at rest points (design A7). Battles now
  write each player's Pokémon back by reference or `coopUid`, and a catch
  goes to the player named in the ball's list; #17 adds the uid-matched
  party/PC sync, the Pokédex rule A7.7 for joiners and evolution checks.
- **#34's rest** waits for #22 (the opening) and #23 (friend battles):
  proposed to move #34 to Group 8.
- Group 8 (#21, #22, #23): unique encounters and the sight gate build on
  the battle record (`trainer:<class>:<index>` keys are not kept yet).
- Group 2 still has #12 and #15 (owner-side checks).

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
- **Cells used for #16:**
  - Viridian Forest ANTIDOTE: stand at (25,12) facing up.
  - Viridian Forest POTION: (11,29) facing right.
  - Daisy: BLUES_HOUSE (2,4) facing up.
  - The bike shop clerk: BIKE_SHOP (6,4) facing up.

## Worktrees and background processes

- Main checkout on `gen1recomp-coop` (leave it; behind origin until pulled).
- This Superset worktree holds `coop/group7-battles` (pushed). The merged
  local branches `coop/group6-split-screen` and `coop/group6-split-sounds`
  are still here.
- No background processes. Group 7's scratch (live import, drivers, shots)
  is deleted.

## Still open

- After each `main` sync: `gh workflow list -R Clodmony/gen1recomp-coop --all`
  and disable upstream's workflows.
- Optional local tools: JDK 17 (`javac`), luacheck.

## Cleanup the owner may approve

- Done 2026-10-15 (owner approved): old scratch and `g2a/`; the merged
  local branches `coop/10-session-core`, `coop/25-german`,
  `coop/group1-cleanup`, `coop/group2-first-playable`; the finished
  milestones (Groups 1, 2a, 3, 4, 5, 5a) closed; every merged branch
  deleted on GitHub; `coop/group5a-story-items`.
- Now possible: the local and remote branches `coop/group6-split-screen`
  and `coop/group6-split-sounds` (merged), and the Group 6 milestone.
- Kept by the owner's choice: the other merged local branches
  (`coop/group2a-*`, `coop/group3-*`, `coop/group4-*`, `coop/group5-*`,
  `coop/workflow-groups`); the main checkout is not pulled.
