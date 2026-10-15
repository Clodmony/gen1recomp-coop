# Agent instructions: gen1recomp-coop

This repository ([Clodmony/gen1recomp-coop](https://github.com/Clodmony/gen1recomp-coop))
is a **public fork** of
[bryanthaboi/gen1recomp](https://github.com/bryanthaboi/gen1recomp) that adds a
cooperative two-player campaign: **online co-op** (two players share one
campaign over the network) and **local split-screen co-op** on one machine,
built on the same session code so both modes stay one feature. The co-op
project is built entirely with AI: every change after upstream commit
`f63f485c` is written by an AI coding agent directed by the repository owner.
Keep that disclosure in `README.md` and here.

Read before working:

- **Start here:** [HANDOFF.md](HANDOFF.md), the session handoff note (state,
  open pull requests, next group), and the open issues on GitHub (the only
  task list); work follows the issue loop under *Workflow*.
- Upstream's docs, which still apply: [docs/architecture.md](docs/architecture.md),
  [CONTRIBUTING-mods.md](CONTRIBUTING-mods.md) (mod API compatibility rules),
  and the existing network features the co-op work builds on:
  [docs/union-room.md](docs/union-room.md),
  [docs/guides/online-play.md](docs/guides/online-play.md),
  [docs/link-security.md](docs/link-security.md).
- [docs/coop/design.md](docs/coop/design.md): the co-op design, carried over
  from the sibling fork pokerecomp-online-coop (every rule with its source,
  marked carry, adapt or skip), the issue for each area and this fork's
  decisions (G1, G2, …). A rule that changes is edited there and the change
  recorded as a decision.
- [docs/coop/session.md](docs/coop/session.md): the session core every co-op
  feature builds on (host, client, protocol, transports, logs, the
  `--coop-host`/`--coop-join` development entry).
- [docs/coop/world.md](docs/coop/world.md): what partners share of one
  world and when (ownership, patches, rest points, per-place rules).
- [docs/coop/items.md](docs/coop/items.md): story items reaching every
  player, the gift list, the gift race and the 40-row bag.
- [docs/coop/opening.md](docs/coop/opening.md): a new player's private
  opening, the names, the rival's starter.
- [docs/coop/presence.md](docs/coop/presence.md): what a session shows in
  the game (partners, arrow, CO-OP menu, notices, run) and its hooks in
  upstream files.
- [docs/coop/battles.md](docs/coop/battles.md): co-op battles (lockstep
  copies in every window, the host's record, joining, the rules).
- [docs/coop/friends.md](docs/coop/friends.md): invitations, friend
  battles and direct trades between partners.
- [docs/coop/cable.md](docs/coop/cable.md): the Cable Club over the
  session (trades by pairing, the Colosseum, the continue position).
- [docs/coop/versions.md](docs/coop/versions.md): Red and Blue in one
  campaign, wild Pokémon from both versions, why Yellow stays apart.
- [docs/coop/split.md](docs/coop/split.md): split-screen, two players on one
  device (two worlds in one process, the views, input routing, seat 2).

## Hard rules

- **Two branches.** `main` is an exact copy of upstream's `main` (upstream
  develops on `dev` and merges it into `main`, so `main` holds everything):
  never commit to it; bring it up to date with
  `git fetch upstream && git push origin upstream/main:main`. The co-op line is
  `gen1recomp-coop`, the default branch: issue branches come off it and draft
  pull requests go into it. Upstream fixes come in by merging `main` into it.
- **Licence.** Upstream's `LICENSE.MD` adds terms to the GPL:
  - the README credit line ("Based on the Pokemon Gen 1 Recompilation Project
    by BOIS CLUB GAMES, LLC (https://github.com/bryanthaboi/gen1recomp)")
    stays, and any co-op menu or front end that starts the game shows it;
  - the **launcher is proprietary** and may not be copied, modified,
    redistributed or *used* in any fork; a fork must provide **its own
    launcher**, which shows the credit line. The launcher is
    `src/import/LauncherView.lua`, `LauncherSettings.lua`, `OnlinePanel.lua`,
    `CartLabelArt.lua`, `CartShape.lua`, `src/mods/LauncherMods.lua`, the
    launcher UI in `src/import/RomImporter.lua` (its ROM import, verification
    and cache extraction logic stays GPL and may be reused), `assets/launcher/`
    and `assets/labels/`. Treat the ONLINE tab's screens in
    `src/import/online/*` as launcher UI too.
  - So: never edit, copy from or build on those files; nothing the fork adds
    may call into them; and the fork's game starts through the fork's own
    launcher. The fork's launcher is `src/coop/launcher/`
    ([docs/coop/launcher.md](docs/coop/launcher.md)): `main.lua`'s
    `makeLauncher` builds it, and `tests/coop/launcher_boot_test.lua` fails
    when a boot path loads an upstream launcher module. `LauncherWindow.lua`
    is not on the licence's list and stays; the splash and theme videos play
    `assets/launcher/` files and stay out.
- **The fork is public, its builds are not.** Never publish releases, Pages
  sites, packages, store builds or artifacts. Only `coop-ci.yml` runs here;
  upstream's workflows stay disabled in the fork's Actions settings.
- Never push to `upstream` (its push URL is disabled on purpose) and never
  open pull requests against it. Never force-push over existing work.
- No personal data in commits, docs, issues or pull requests (names, emails,
  hardware, local paths).
- **No session links** (owner, 2026-10-15): commits, pull requests, issues
  and comments carry no `Claude-Session:` line and no claude.ai session
  URL, whatever an attribution default says; they link the public
  repository to the owner's account. `Co-Authored-By: Claude …` and the
  pull request's "Generated with Claude Code" line stay (the AI
  disclosure). Commits are authored as `Claude <noreply@anthropic.com>`
  (the clone's local git config).
- Never commit or upload ROMs, saves, extracted cartridge content
  (`data/generated/`), credentials or local caches. Screenshots of the game
  show cartridge graphics: keep them local, never in commits, issues or pull
  requests. Tests use the committed `tests/fixture_data` dataset; a check that
  needs a real cartridge asks the owner to supply it locally.
- Keep upstream merges cheap: prefer new modules and small hooks over edits
  spread through upstream files, and mark co-op edits in upstream files.
- Do not claim something works on a platform or in a mode that was not run.

## Workflow

- **One group per session** (owner, 2026-10-13). Issues are grouped into
  GitHub milestones `Group N: <topic>`, numbered in the order they unblock
  each other. Work on the open group with the lowest number, unless the owner
  picks another. A session takes one group: branch `coop/group<N>-<topic>`
  from `gen1recomp-coop`, and for each issue in it reproduce the problem (a
  failing test first) and fix it, one commit or more per issue. Then run
  `tools/verify.sh`, update the docs, push and open one draft pull request
  that says `Closes #N` for every issue it finishes. Then rewrite
  `HANDOFF.md` (open pull requests, branch state, next group, cleanup),
  then ask the owner about everything still theirs to do or decide (merges,
  proposed decisions, wording, cleanup) as choices with options, the
  recommended one first (owner, 2026-10-15), record the answers, and
  stop: the owner starts a fresh session for the next group. If a group grows too long, stop
  at an issue boundary, open the pull request for the finished issues, and
  leave the rest of the group for the next session. An issue found on the
  way goes into the milestone where it fits.
- **GitHub issues are the task list.** New work, bugs found on the way and
  follow-ups become issues; there is no task file in the repository.
- **The handoff lives in the repository.** `HANDOFF.md` is rewritten at the end
  of every session and committed on the group's branch. When a session ends
  without a pull request, or the note must be visible before the owner merges,
  commit it alone (`handoff: <date>`) and push it to `gen1recomp-coop`
  directly: it is the one file that may land there without a pull request.
  Per-checkout agent memory is not read from another worktree, so state goes
  into this file, not into memory.
- **Worktrees.** One worktree per group: a Superset workspace, or
  `git worktree add` under scratch. Superset runs `.superset/setup.sh` when it
  creates a workspace; run it by hand in any other worktree (identity, upstream
  remote, tool check). Remove a worktree when its pull request is merged.
- **The owner merges.** A pull request is merged only when the owner says so,
  locally under the Claude identity.
- **Scratch lives on disk, outside the repository**, under
  `~/dev-scratch/gen1recomp-coop/`: captures, logs, verify runs, extra git
  worktrees, pull request bodies. /tmp is a small RAM disk on the owner's
  machine. Delete a group's scratch when its pull request is open.

## Setup

```bash
git config user.name Claude && git config user.email noreply@anthropic.com
git remote add upstream https://github.com/bryanthaboi/gen1recomp.git
git remote set-url --push upstream DISABLED
```

Tests need `luajit`, `python3` with Pillow and a JDK 17 (`javac`, for the
Android importer tier); `luacheck` (via luarocks) is optional locally and
gated in CI. Running the game needs LÖVE 11.x
(`love .`, see [docs/guides/running-from-source.md](docs/guides/running-from-source.md)).

## Verification commands

```bash
# The check of a branch: every test tier, mod lint, fixture PNGs, with a private
# HOME so no test touches the owner's saves or caches; logs and summary.txt in
# ~/dev-scratch/gen1recomp-coop/verify/<stamp>/, exit 0 only if all passed.
tools/verify.sh

# Upstream's entry points, for debugging one part:
scripts/test.sh --group engine   # one ROM-free CI group (--list-groups)
scripts/test.sh --list           # tiers this checkout would run
scripts/lint.sh --gate           # luacheck, only the codes CI blocks on
```

`tools/verify.sh --quick` runs `tests/quick.list`, whose parity suites need
imported ROM data; without it those suites fail, so use the full run for a
ROM-free check.
