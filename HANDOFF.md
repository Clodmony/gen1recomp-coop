# Handoff

The session note for this repository. Read it first in a fresh session and
rewrite it at the end of every session (issue loop, last step). It lives in the
repository so it survives any worktree path and any tool; per-checkout agent
memory is not read by a session that starts in another worktree. State goes
here; stable recipes go into `docs/coop/`; personal data and hardware never.

Last updated 2026-10-15 (after Group 5a, #16, PR #49).

## Repository state

- Default branch `gen1recomp-coop`; `main` = upstream main. Nothing of
  Groups 2a to 5a is merged yet; no owner comments on #42-#46, #48.
- Milestones: Group 5a (#16) is done by #49; Group 7a holds #17.

## Open pull requests (all draft, stacked; the owner reviews and says which to merge)

- **#42** `coop/group2a-german` into `gen1recomp-coop`: launcher redesign (#38)
  and German launcher (#41). G13, G14 (proposed). Owner: the "Better German"
  column in `docs/coop/german-wording.md`, G14, whether #38 may close.
- **#43** `coop/group2a-german-games` on #42's branch: the rest of #25, G15.
- **#44** `coop/group2a-yellow-de` on #43's branch: German Yellow (#40), G16.
- **#45** `coop/group3-launcher-screens` on #44's branch: Group 3, closes #4,
  #5, #6 (G17-G19).
- **#46** `coop/group4-campaign-state` on #45's branch: closes #13 (campaign
  files, G20 proposed).
- **#48** `coop/group5-shared-world` on #46's branch: closes #14 (the
  shared world, G21 proposed, protocol 5, campaign file version 2).
- **#49** `coop/group5a-story-items` on #48's branch (head: the live-run
  docs commit plus this note): closes #16. `src/coop/campaign/Items.lua`.
  - A patch carries its window's bag change, and the host shares, takes
    and takes back.
  - Owed items (`gifts`) wait in the campaign file. They land once at a
    rest point (`save.coopGifts`), and the host drops them once a saved
    world shows them.
  - `gift:<item>` commits build the late joiner's list.
  - The bag holds 40 rows during a session, and a campaign's slot has no
    EXPORT.
  - Protocol 6, campaign file version 3. Decision **G22 (proposed)**.
    Docs: `docs/coop/items.md`.
  - Verify: 36/37 (only the javac tier fails locally).
  - Live run (US Red, three processes) passed: an item ball, Daisy's TOWN
    MAP, the bike shop's BICYCLE for the voucher, the gift race and a late
    joiner. Not run live: a gift TM, a full bag's spill, a rejoin landing
    an unsaved gift.
- Merge order: #42, #43, #44, #45, #46, #48, #49, each locally as Claude
  (`git merge --no-ff`), never `gh pr merge`.

## Next candidates

- **Group 6 (#11)**, split-screen: `CoopSettings.slots` is keyed by campaign
  only; a second seat needs its own slot (design A3.14), and its own
  `Window` (one per client already). Note: `Items.openBag` raises the one
  shared `Data.constants.bagSize`, which suits two seats in one process.
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

- Main checkout on `gen1recomp-coop` (leave it). Superset worktrees on
  `coop/group5-shared-world` (from the last session) and
  `coop/group5a-story-items`, both pushed and clean. No scratch worktrees
  or background processes. Group 5a's scratch is deleted.

## Still open

- After each `main` sync: `gh workflow list -R Clodmony/gen1recomp-coop --all`
  and disable upstream's workflows.
- Optional local tools: JDK 17 (`javac`), luacheck.

## Cleanup the owner may approve

- Scratch under `~/dev-scratch/gen1recomp-coop/`: `ref/`, `probe/` (Group
  2a), `g2a/` (after #42/#43 merge), `shot/`, `launcher-run*.log`, `verify/`
  runs.
- Merged local branches `coop/group1-cleanup`, `coop/group2-first-playable`,
  `coop/25-german`.
