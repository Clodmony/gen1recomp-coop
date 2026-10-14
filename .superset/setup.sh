#!/usr/bin/env bash
# Makes a fresh worktree of this fork ready for an agent session. Superset runs
# it on workspace creation (.superset/config.json); run it by hand in any other
# worktree. Idempotent, a few seconds, touches only this checkout's git config
# and the scratch folder. Never installs anything and never changes the owner's
# global git identity.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

git config user.name Claude
git config user.email noreply@anthropic.com
if ! git remote get-url upstream >/dev/null 2>&1; then
	git remote add upstream https://github.com/bryanthaboi/gen1recomp.git
fi
git remote set-url --push upstream DISABLED

mkdir -p "$HOME/dev-scratch/gen1recomp-coop"

for t in love luajit lua5.4 python3; do
	command -v "$t" >/dev/null || echo "setup: $t missing (tests or the game need it)" >&2
done
python3 -c 'import PIL' 2>/dev/null || echo "setup: python3 Pillow missing (fixture PNG stage)" >&2
command -v javac >/dev/null || echo "setup: no javac; the Android importer tier fails locally (CI has Java)" >&2
command -v luacheck >/dev/null || echo "setup: no luacheck; that tier skips locally" >&2

echo "setup: $(git config user.name) <$(git config user.email)>, branch $(git branch --show-current)"
echo "setup: read HANDOFF.md first, then AGENTS.md; new files under .github/ and .superset/ need git add -f"
