# Handoff

The session note for this repository. Read it first in a fresh session and
rewrite it at the end of every session (issue loop, last step). It lives in the
repository so it survives any worktree path and any tool; per-checkout agent
memory is not read by a session that starts in another worktree. State goes
here; stable recipes go into `docs/coop/`; personal data and hardware never.

Last updated 2026-10-15 (after Group 7a, PR #54).

## Repository state

- Default branch `gen1recomp-coop`; `main` = upstream main. Groups 1 to 6
  are merged (#42-#50, #52).
- Milestones: Group 7 is done by #53 (#18, #19, #20; #34's battle parts),
  open until the owner merges. Group 7a is done by #54 (#17), stacked on
  #53. Group 2 still has #12 and #15 (owner-side checks); Groups 8, 9, 10
  are open.

## Open pull requests (draft)

- **#53** `coop/group7-battles` into `gen1recomp-coop`: closes #18, #19,
  #20; part of #34. Lockstep co-op battles (G24, accepted 2026-10-15).
  `docs/coop/battles.md` has everything. Verify 36/37 (only javac), CI
  passed.
  - **Owner (2026-10-15): merge after their own check** in real windows
    (join, leave, REJOIN, a loss). Once they say so, merge locally as
    Claude (`git merge --no-ff`), push, run `tools/verify.sh`.
- **#54** `coop/group7a-party-pc` into `coop/group7-battles` (stacked):
  closes #17.
  - Holdings at rest points (protocol 8 `holdings`; the host's `uids`
    back). Uid matching (an unchanged row, then the row's place). A catch
    for the named player with each team's `room`, the host's refusal and a
    ball kept when nobody has room. The Pokédex sees every species that
    appeared. `docs/coop/campaign.md` *Holdings*, `battles.md`.
  - Decision **G25** (design.md §6), accepted by the owner 2026-10-15: no
    holdings revision, since the window is the only writer under G24;
    A7.3's hint is the row's place.
  - Verify 36/37 (only javac). Live (US Red, two ENet processes): a catch
    named for the partner, the host's copy following without a SAVE, the
    refused ball's ROM line, the Pokédex. Not run: the name list by hand,
    real pads, a PC deposit by hand, three players, split-screen.
  - **Owner (2026-10-15): merge after their own check, in order.** #53
    first, then retarget #54 to `gen1recomp-coop`
    (`gh pr edit 54 --base gen1recomp-coop`) and merge it the same way.
    "Closes #17" only fires once #54 targets the default branch.

## Next candidates

- **Group 8 is next** (owner, 2026-10-15) (#21, #22, #23, #34's rest): unique encounters and the sight
  gate build on the battle record (`trainer:<class>:<index>` keys are not
  kept yet); #22 the private opening; #23 friend battles and trades (a
  traded Pokémon keeps or gets its uid: `Campaign:_stampUids`).
- Group 2 still has #12 and #15 (owner-side checks).
- A possible follow-up: holdings carry the bag and money as a side effect
  (the world goes whole), so a ball spent on a catch and the catch now
  reach the host together; the gift race (#16) still reads bag changes
  from patches only.

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
- **Cells used for #16:**
  - Viridian Forest ANTIDOTE: stand at (25,12) facing up.
  - Viridian Forest POTION: (11,29) facing right.
  - Daisy: BLUES_HOUSE (2,4) facing up.
  - The bike shop clerk: BIKE_SHOP (6,4) facing up.

## Worktrees and background processes

- Main checkout on `gen1recomp-coop` (leave it; behind origin until pulled).
- This Superset worktree holds `coop/group7a-party-pc` (pushed) and
  `coop/group7-battles` (pushed).
- No background processes. Group 7a's scratch (live import, drivers) is
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
  deleted on GitHub; `coop/group5a-story-items`.
- Done 2026-10-15 (owner approved): the local and remote branches
  `coop/group6-split-screen` and `coop/group6-split-sounds`; the Group 6
  milestone closed.
- Once #53 and #54 are merged: their branches and the Group 7 and 7a
  milestones.
- Kept by the owner's choice: the other merged local branches
  (`coop/group2a-*`, `coop/group3-*`, `coop/group4-*`, `coop/group5-*`,
  `coop/workflow-groups`); the main checkout is not pulled.
