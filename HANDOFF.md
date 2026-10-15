# Handoff

The session note for this repository. Read it first in a fresh session and
rewrite it at the end of every session (issue loop, last step). It lives in the
repository so it survives any worktree path and any tool; per-checkout agent
memory is not read by a session that starts in another worktree. State goes
here; stable recipes go into `docs/coop/`; personal data and hardware never.

Last updated 2026-10-15 (after merging #42-#49).

## Repository state

- Default branch `gen1recomp-coop`; `main` = upstream main. Groups 1 to 5a
  are merged: #42, #43, #44, #45, #46, #48, #49 went in on 2026-10-15
  (locally as Claude, `--no-ff`), closing #38, #41, #25, #40, #4, #5, #6,
  #13, #14, #16. `tools/verify.sh` on the merge: 36/37 (only the javac
  tier fails locally); `coop-ci` passed on it.
- The owner accepted G14, G20, G21 and G22 as built, and the German
  wording as written (the "Better German" column stays empty).
- No open pull requests.

## Next candidates

- **Group 6 (#11)**, split-screen: `CoopSettings.slots` is keyed by campaign
  only; a second seat needs its own slot (design A3.14), and its own
  `Window` (one per client already). `Items.openBag` raises the one shared
  `Data.constants.bagSize`, which suits two seats in one process.
- **Group 7 (#18 and the rest)**, battles, then **Group 7a (#17)** party
  and PC at rest points (design A7; a window's party sync would ride on the
  same rest points as the story and gifts).
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
- **Cells used for #16:**
  - Viridian Forest ANTIDOTE: stand at (25,12) facing up.
  - Viridian Forest POTION: (11,29) facing right.
  - Daisy: BLUES_HOUSE (2,4) facing up.
  - The bike shop clerk: BIKE_SHOP (6,4) facing up.

## Worktrees and background processes

- Main checkout on `gen1recomp-coop` (leave it; it is behind origin until
  pulled). One Superset worktree on `coop/group5a-story-items` (merged; its
  branch is deleted on GitHub; remove it, see Cleanup).
  No background processes.

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
- Approved, for the next session (or Superset): remove the merged worktree
  on `coop/group5a-story-items` (it ran this session, so it could not
  remove itself) and its local branch.
- Kept by the owner's choice: the other merged local branches
  (`coop/group2a-*`, `coop/group3-*`, `coop/group4-*`, `coop/group5-*`,
  `coop/workflow-groups`); the main checkout is not pulled.
