# Handoff

The session note for this repository. Read it first in a fresh session and
rewrite it at the end of every session (issue loop, last step). It lives in the
repository so it survives any worktree path and any tool; per-checkout agent
memory is not read by a session that starts in another worktree. State goes
here; stable recipes go into `docs/coop/`; personal data and hardware never.

Last updated 2026-10-15 (Group 8's first issue, #21, PR #56).

## Repository state

- Default branch `gen1recomp-coop`; `main` = upstream main. Groups 1 to 7a
  are merged: #42-#50, #52, and #53 and #54 (merged 2026-10-15 at the
  owner's word, locally as Claude; verify on the merged branch was 36/37,
  only javac).
- Milestones: Groups 7 and 7a have no open issues (close them at the
  owner's OK). Group 8 is open: #21 is done by #56; #55 (split from #21),
  #22, #23 and #34's rest remain. Group 2 still has #12 and #15
  (owner-side checks); Groups 9 and 10 are open.

## Open pull requests (draft)

- **#56** `coop/group8-story` into `gen1recomp-coop`: closes #21 (A10.1
  to A10.4 and A10.8; the owner split A10.5 to A10.7 into #55).
  - A unique encounter is its map object (`trainer:<MAP>_obj_<n>`,
    `static:<MAP>_obj_<n>`, protocol 9). One running instance; a walk-in
    joins it; a win or a catch is done for the campaign (`victory:`
    commit, campaign `encounters`); a done one answers `beaten` and the
    world counts it as won; a loss, flight, abandon or shutdown releases
    it; the League's rooms are never kept done (until #55). The sight
    gate: a trainer the host names as in a battle spots nobody.
  - Decision **G26** (design.md §6) is proposed: the owner decides.
  - Verify 36/37 (only javac). Live (US Red, two ENet processes): sight,
    the sight gate, a walk-in by talking, a win for both, counts as won.
    `docs/coop/battles.md` *Unique encounters* and *Checked*.

## Next candidates

- **#55** (rival scenes, the team's League run, the Hall of Fame
  continue): A10.5 needs a hook where each rival scene starts (no
  map-script bytes here, G21) and a host lock per map; A10.6 builds on
  `HostBattles.LEAGUE` and `Campaign.encounters`/`commits` (forget the
  League's at the run's clear); A10.7 needs a restart hook.
- **#22** the private opening (first steps: design A4, the comment about
  split-screen's player 2 naming themself).
- **#23** friend battles and trades (a traded Pokémon keeps or gets its
  uid: `Campaign:_stampUids`).
- #34's opening and friend-battle parts go with #22 and #23.
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
- Group 8's worktree: `~/dev-scratch/gen1recomp-coop/wt-group8` on
  `coop/group8-story` (pushed). The Superset worktree `veiled-degree-…`
  still holds the merged `coop/group7a-party-pc`.
- No background processes. Group 8's scratch (live import, drivers) is
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
  deleted on GitHub; `coop/group5a-story-items`; Group 6's branches and
  milestone.
- Merged 2026-10-15: `coop/group7-battles` and `coop/group7a-party-pc`
  (local and remote), the Group 7 and 7a milestones, and the Superset
  worktree that held them.
- Once #56 is merged: `coop/group8-story` and its worktree.
- Kept by the owner's choice: the other merged local branches
  (`coop/group2a-*`, `coop/group3-*`, `coop/group4-*`, `coop/group5-*`,
  `coop/workflow-groups`); the main checkout is not pulled.
