# Handoff

The session note for this repository. Read it first in a fresh session and
rewrite it at the end of every session (issue loop, last step). It lives in the
repository so it survives any worktree path and any tool; per-checkout agent
memory is not read by a session that starts in another worktree. State goes
here; stable recipes go into `docs/coop/`; personal data and hardware never.

Last updated 2026-10-15 (after Group 8's first issue, #21: PR #56 merged).

## Repository state

- Default branch `gen1recomp-coop`; `main` = upstream main. Merged at the
  owner's word on 2026-10-15, locally as Claude: #53, #54 and #56. Verify
  on the merged branch: 36/37 tiers (only the Android importer tier: no
  `javac` here).
- Every merged branch is deleted, locally and on GitHub. Two stay
  locally: `coop/group7a-party-pc` (checked out in the Superset worktree
  `veiled-degree-…`) and that worktree's own branch `veiled-degree-…`.
- Milestones: Groups 7 and 7a closed. Group 8 is open: #21 is closed;
  #55 (split from #21 by the owner), #22, #23 and #34's rest remain.
  Group 2 still has #12 and #15 (owner-side checks); Groups 9 and 10 are
  open.

## Open pull requests

None.

## For the next session

- **Decision G26 was accepted by the owner (2026-10-15)** after #56
  merged: mark it accepted in `docs/coop/design.md` §6 (it still says
  "proposed") on the next group branch.
- **Next: #22, the private opening** (owner, 2026-10-15): branch
  `coop/group8-opening` from `gen1recomp-coop`. First steps: design A4,
  the issue's comment (split-screen's player 2 names themself the same
  way), and #34's opening part ("in the opening" in the CO-OP box, nobody
  drawn during the opening).

## Next candidates after that

- **#55** (rival scenes, the team's League run, the Hall of Fame
  continue): A10.5 needs a hook where each rival scene starts (no
  map-script bytes here, G21) and a host lock per map; A10.6 builds on
  `HostBattles.LEAGUE` and `Campaign.encounters`/`commits` (forget the
  League's at the run's clear); A10.7 needs a restart hook.
- **#23** friend battles and trades (a traded Pokémon keeps or gets its
  uid: `Campaign:_stampUids`); #34's friend-battle part with it.
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
- **Loopback test clients** need a hex `device` id (`"c1"`, not `"y1"`):
  the protocol drops a hello with another one.
- **Cells used for #16:**
  - Viridian Forest ANTIDOTE: stand at (25,12) facing up.
  - Viridian Forest POTION: (11,29) facing right.
  - Daisy: BLUES_HOUSE (2,4) facing up.
  - The bike shop clerk: BIKE_SHOP (6,4) facing up.

## Worktrees and background processes

- Main checkout on `gen1recomp-coop` (leave it; behind origin until pulled).
- The Superset worktree `veiled-degree-…` holds the merged
  `coop/group7a-party-pc`; this session ran in it, so it was not removed.
  The owner removes it in Superset when they like; then
  `git branch -D coop/group7a-party-pc veiled-degree-…` in the main
  checkout.
- No background processes, no scratch worktrees. Group 8's scratch (live
  import with the extracted cartridge data, drivers) is deleted.

## Still open

- After each `main` sync: `gh workflow list -R Clodmony/gen1recomp-coop --all`
  and disable upstream's workflows.
- Optional local tools: JDK 17 (`javac`), luacheck.

## Cleanup

- Done 2026-10-15 (owner approved): every merged branch, locally and on
  GitHub (the two above excepted); the milestones of Groups 1 to 7a.
