#!/usr/bin/env bash
# One unattended check of the checked-out branch (the co-op fork's verify
# script): upstream's test entry point, then the ROM-free gates CI adds on
# top of it, with a summary of a few lines at the end.
#
#   tools/verify.sh [--quick]
#
#   --quick     scripts/test.sh --quick (tests/quick.list, under a minute)
#               instead of every tier
#
# Stages: tests (scripts/test.sh; runs luacheck itself when it is installed),
# mod lint (tools/modkit.py lint over mods/*), fixture PNGs. Full logs go to
# $VERIFY_OUT/<stamp>/ (default ~/dev-scratch/gen1recomp-coop/verify), the
# summary to <stamp>/summary.txt and stdout. Exits 0 only if every stage passed.
#
# Every stage runs with a private HOME and TMPDIR inside the run folder, so no
# test reads or writes the owner's LOVE saves, imported caches or settings.
# The ROM content tiers then skip; to run them, point POKEPORT_TEST_CACHES at
# a cache folder made for tests (see scripts/test.sh).
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
quick=0
for a in "$@"; do
	case "$a" in
		--quick) quick=1 ;;
		-h|--help) sed -n '2,19p' "$0"; exit 0 ;;
		*) echo "unknown option: $a" >&2; exit 2 ;;
	esac
done

out="${VERIFY_OUT:-$HOME/dev-scratch/gen1recomp-coop/verify}/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out/home" "$out/tmp"
summary="$out/summary.txt"
failed=0

note() { echo "$*" >> "$summary"; }
note "verify $(git -C "$root" rev-parse --abbrev-ref HEAD) @ $(git -C "$root" rev-parse --short HEAD) ($(date '+%F %T'))"

# stage <name> <command...>: run from the repository root in the private
# HOME/TMPDIR, output in <name>.log.
stage() {
	local name="$1"; shift
	if (cd "$root" && HOME="$out/home" TMPDIR="$out/tmp" XDG_DATA_HOME="$out/home/.local/share" \
		"$@") > "$out/$name.log" 2>&1; then
		note "$name: ok"
	else
		note "$name: FAILED"
		failed=$((failed + 1))
	fi
}

tests=(scripts/test.sh)
(( quick )) && tests+=(--quick)
stage tests "${tests[@]}"
# scripts/test.sh prints "-- <tier>: PASS|FAIL|skipped" per tier, FAIL/SYNTAX
# lines in --quick
pass="$(grep -c -- '^-- .*: PASS$' "$out/tests.log")"
fail="$(grep -c -- '^-- .*: FAIL$' "$out/tests.log")"
(( quick )) || note "  tiers: $pass passed, $fail failed"
grep -E -- '^-- .*(: FAIL$|: skipped)|^   (FAIL|SYNTAX) |^-- quick: ' "$out/tests.log" \
	| sed 's/^/  /' | head -20 >> "$summary"

modlint() {
	local mod
	for mod in mods/*/; do
		[ -f "$mod/manifest.json" ] || continue
		echo "== $mod"
		python3 tools/modkit.py lint "${mod%/}" || return 1
	done
}
stage modlint modlint

fixture_pngs() {
	python3 - <<'PY'
import glob, sys
from PIL import Image
paths = sorted(glob.glob("tests/fixture_data/assets/*.png"))
if not paths:
    sys.exit("no fixture assets found")
for path in paths:
    with Image.open(path) as image:
        image.load()
print(f"{len(paths)} fixture assets valid")
PY
}
stage fixtures fixture_pngs

stages="$(grep -cE '^[a-z]+: (ok|FAILED)$' "$summary")"
note "$((stages - failed))/$stages stages passed; logs in $out"
if (( failed )); then note "RESULT: FAILURES"; else note "RESULT: ALL PASSED"; fi
cat "$summary"
exit $(( failed > 0 ))
