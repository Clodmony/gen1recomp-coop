# Handoff

The session note for this repository. Read it first in a fresh session and
rewrite it at the end of every session (issue loop, last step). It lives in the
repository so it survives any worktree path and any tool; per-checkout agent
memory is not read by a session that starts in another worktree. State goes
here; stable recipes go into `docs/coop/`; personal data and hardware never.

Last updated 2026-10-14 (after merging the workspace pull request #47).

## Repository state

- Default branch `gen1recomp-coop`; `main` = upstream main. The workspace
  pull request #47 (this file, `.superset/`, the AGENTS.md pointers) is merged
  (`5c6a3523`), and `gen1recomp-coop` was merged down the stack #42 -> #46 so
  every branch has it. Nothing of Groups 2a to 4 is merged yet; no owner
  comments on #42-#46.

## Open pull requests (all draft, stacked; the owner reviews and says which to merge)

- **#42** `coop/group2a-german` into `gen1recomp-coop`: launcher redesign (#38)
  and German launcher (#41). G13, G14 (proposed). Owner: the "Better German"
  column in `docs/coop/german-wording.md`, G14, whether #38 may close.
- **#43** `coop/group2a-german-games` on #42's branch: the rest of #25, G15.
- **#44** `coop/group2a-yellow-de` on #43's branch: German Yellow (#40), G16.
- **#45** `coop/group3-launcher-screens` on #44's branch: Group 3, closes #4,
  #5, #6 (G17-G19).
- **#46** `coop/group4-campaign-state` on #45's branch (head 72619cf6): closes
  #13. `src/coop/campaign/` (Campaign, World, CampaignFile, Store), protocol 4
  (`world`, `saved`, state `saved_ago`/`busy`), host saves (gate on
  `host.battles`/`host.joins`, autosave, journal), game hooks
  (`Game:writeSave(kind)` -> `CampaignSave.written`; StartMenu gate and
  `writeSave("menu")`; `love.focus`/`visible` -> `Session.pause`), the
  launcher fills the campaign slot from `Session:takeWorld()` and refuses
  unreadable or newer files. Decision **G20 (proposed)**: player worlds kept
  whole until #14 moves shared keys. Docs: `docs/coop/campaign.md`. Verify
  36/37 (only the javac tier fails locally). Live run (US Red, two processes,
  dev entry, new `--coop-campaign=ID`) passed both phases; not seen live: uids
  (no Pokémon), journal line, battle gate, launcher slot fill.
- Merge order: #42, #43, #44, #45, #46, each locally as Claude
  (`git merge --no-ff`), never `gh pr merge`.

## Owner decision pending (asked in #46)

#16 and #17 mostly need #14 (world patches and rest points, Group 5) and #18
(host-side battles, Group 7). Only A6.8 (the 40-row co-op bag) stands alone;
the uid/fingerprint groundwork for A7.2/A7.3 is in #46. Proposal: move #16
after Group 5, #17 into or after Group 7, or split A6.8 out. Ask before
starting the rest of Group 4.

## Next candidates

- Whatever the owner picks on the regrouping; otherwise Group 5 (#14 shared
  world) builds directly on #46: fill `campaign.story` from world patches,
  classify save keys (A5.1) over the save table (keys listed in
  `docs/coop/campaign.md`; Gen 1 save: flags, objectToggles,
  defeatedTrainers, hiddenTaken, itemsTaken; badges live in `inventory`).
- Group 2 still has #12 and #15 (owner-side checks). #34's campaign part (last
  save in the CO-OP box) is done in #46; its other parts stay.
- For #11 (split-screen): `CoopSettings.slots` is keyed by campaign only; a
  second seat needs its own slot (design A3.14).

## Live-run recipe

Import US Red into a private folder with `POKEPORT_IMPORT_ONLY=1
POKEPORT_IMPORT_ROM=...` under a private `HOME`/`XDG_DATA_HOME`, copy it for a
second process, run both offscreen with `POKEPORT_DRIVER`,
`POKEPORT_COOP_HOST`/`_JOIN` and `stdbuf -oL` (a guest whose host quits goes
back to its launcher, which restarts the process and loses unflushed output).
In a driver, wait for `src.ui.ChoiceBox` on top before pressing YES.

## Worktrees and background processes

- Main checkout on `gen1recomp-coop` (switched 2026-10-15: Superset bases new
  workspaces on the main checkout's branch, and the old local `dev` had no
  `.superset/` or `HANDOFF.md`; keep it on the integration branch). One Superset
  worktree on
  `coop/group4-campaign-state`, pushed, clean. No scratch worktrees, no
  background processes.

## Still open

- After each `main` sync: `gh workflow list -R Clodmony/gen1recomp-coop --all`
  and disable upstream's workflows.
- Optional local tools: JDK 17 (`javac`), luacheck.

## Cleanup the owner may approve

- Scratch under `~/dev-scratch/gen1recomp-coop/`: `ref/`, `probe/` (Group
  2a), `g2a/` (after #42/#43 merge), `shot/`, `launcher-run*.log`, `verify/`
  runs.
- Merged local branches `coop/group1-cleanup`, `coop/group2-first-playable`,
  `coop/25-german` (`coop/workspace-handoff` is already deleted).
