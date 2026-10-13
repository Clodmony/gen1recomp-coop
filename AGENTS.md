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

- **Start here:** the open issues on GitHub (the only task list) and the
  session handoff note; work follows the issue loop under *Workflow*.
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
  - the **launcher is proprietary** and may not be modified or reused:
    `src/import/LauncherView.lua`, `LauncherSettings.lua`, `OnlinePanel.lua`,
    `CartLabelArt.lua`, `CartShape.lua`, `src/mods/LauncherMods.lua`, the
    launcher UI in `src/import/RomImporter.lua`, `assets/launcher/`,
    `assets/labels/`. Never edit those files; co-op UI lives in files of its own.
- **The fork is public, its builds are not.** Never publish releases, Pages
  sites, packages, store builds or artifacts. Only `coop-ci.yml` runs here;
  upstream's workflows stay disabled in the fork's Actions settings.
- Never push to `upstream` (its push URL is disabled on purpose) and never
  open pull requests against it. Never force-push over existing work.
- No personal data in commits, docs, issues or pull requests (names, emails,
  hardware, local paths). Commits are authored as `Claude <noreply@anthropic.com>`
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

- **One issue per session.** Pick the issue with the owner, branch
  `coop/<issue>-<topic>` from `gen1recomp-coop`, reproduce the problem (a
  failing test first), fix it, run `tools/verify.sh`, update the docs, push and
  open a draft pull request that says `Closes #N`. Then write the handoff note
  (open pull requests, branch state, next candidates) and stop: the owner
  starts a fresh session for the next issue.
- **GitHub issues are the task list.** New work, bugs found on the way and
  follow-ups become issues; there is no task file in the repository.
- **The owner merges.** A pull request is merged only when the owner says so,
  locally under the Claude identity.
- **Scratch lives on disk, outside the repository**, under
  `~/dev-scratch/gen1recomp-coop/`: captures, logs, verify runs, extra git
  worktrees, pull request bodies. /tmp is a small RAM disk on the owner's
  machine. Delete an issue's scratch when its pull request is open.

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
