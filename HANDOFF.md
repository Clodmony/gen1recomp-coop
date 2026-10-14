# Handoff

The session note for this repository. Read it first in a fresh session and
rewrite it at the end of every session (issue loop, last step). It lives in the
repository so it survives any worktree path and any tool; per-checkout agent
memory is not read by a session that starts in another worktree. State goes
here; stable recipes go into `docs/coop/`; personal data and hardware never.

Last updated 2026-10-15 (after Group 5, #14, PR #48).

## Repository state

- Default branch `gen1recomp-coop`; `main` = upstream main. Nothing of
  Groups 2a to 5 is merged yet; no owner comments on #42-#46.
- Regrouping (owner said "do it" to the proposal in #46, 2026-10-15): #16
  moved to the new milestone **Group 5a: Story items and the co-op bag**,
  #17 to the new **Group 7a: Pokémon, party and PC**. Group 4 now holds only
  #13 (closed by #46).

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
- **#48** `coop/group5-shared-world` on #46's branch (head 13707a3b plus
  this note): closes #14. `Ownership.lua` (who owns each save entry),
  `Window.lua` (patches at rest points, unconfirmed patches, the standing
  map), `src/coop/game/SharedWorld.lua` (rest detection from the
  overworld, Vermilion's kept lock), protocol 5 (`patch`, `story`), campaign
  file version 2 with a migration. Decision **G21 (proposed)**: the engine
  saves no per-map script bytes, so A5.6 and A5.9 are adapted. Docs:
  `docs/coop/world.md`. Verify 36/37 (only the javac tier fails locally).
  Live run (US Red, two processes) passed: an object hide, a held flag, both
  Vermilion locks with a reload. Not run live: Victory Road, Cinnabar, the
  League rooms, Vermilion's kept lock, a migrated played file.
- Merge order: #42, #43, #44, #45, #46, #48, each locally as Claude
  (`git merge --no-ff`), never `gh pr merge`.

## Next candidates

- **Group 5a (#16)**, story items and the co-op bag, builds on #48:
  - A6.2: an item gained in the same window change that moves the story
    goes to every player. The window's patch is the place: a patch that
    sets story entries plus that window's bag delta.
  - A6.3: key items the story takes.
  - A6.5: the late-joiner gift list as commits `gift:<item>`
    (`Campaign:commit`).
  - A6.7: the gift race (a patch whose story entries the campaign already
    had).
  - A6.8: the 40-row bag (mod `bagSize` override).
- **Group 6 (#11)**, split-screen: `CoopSettings.slots` is keyed by campaign
  only; a second seat needs its own slot (design A3.14), and its own
  `Window` (one per client already).
- Group 2 still has #12 and #15 (owner-side checks).

## Live-run recipe

Import US Red into a private folder with `POKEPORT_IMPORT_ONLY=1
POKEPORT_IMPORT_ROM=...` under a private `HOME`/`XDG_DATA_HOME`, copy it for a
second process, run both offscreen with `POKEPORT_DRIVER`,
`POKEPORT_COOP_HOST`/`_JOIN` and `stdbuf -oL` (a guest whose host quits goes
back to its launcher, which restarts the process and loses unflushed output).
`tests/drivers/util.lua` has `newGame`, `teleport`, `wait`, `tap`; a driver
reads `Session.current` (`client.state.players`, `window`, `host.state.story`)
to sync with the other process. In a driver, wait for `src.ui.ChoiceBox` on
top before pressing YES. Quit with `love.event.quit()` so the bye goes out.

## Worktrees and background processes

- Main checkout on `gen1recomp-coop` (leave it). One Superset worktree on
  `coop/group5-shared-world`, pushed, clean. No scratch worktrees, no
  background processes. Group 5's scratch is deleted.

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
