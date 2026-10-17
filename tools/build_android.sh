#!/usr/bin/env bash
# A local Android debug build of the co-op fork (#7): an APK for a device or
# emulator on this machine, never published (AGENTS.md).
#
#   tools/build_android.sh [--abi x86_64|arm64-v8a|armeabi-v7a|all]
#
# Upstream's scripts/build_android.sh does the packing (game.love, branding,
# manifests); it writes into mobile/android, so this script runs it on a copy
# of the working tree under $COOP_ANDROID_OUT (default
# ~/dev-scratch/gen1recomp-coop/android-build) and the checkout stays clean.
# The copy is built under the fork's own app id and name, so it installs next
# to upstream's app instead of over it.
#
# game.love then loses upstream's proprietary launcher (LICENSE.MD term 2):
# the modules tests/coop/launcher_boot_test.lua forbids, src/import/online/,
# assets/labels/ and assets/launcher/ except the lucide icon sheets the save
# editor's kit draws (src/ui/kit/Icons.lua), as on desktop.  The build fails
# if one of them is still in the archive.
#
# Needs JDK 17 and an Android SDK with platform 36, NDK 25.2.9519653 and
# build-tools 36 in ANDROID_SDK_ROOT (default
# ~/dev-scratch/gen1recomp-coop/android-sdk).  Output: <out>/gen1recomp-coop-debug.apk.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$HOME/dev-scratch/gen1recomp-coop"
out="${COOP_ANDROID_OUT:-$scratch/android-build}"
sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$scratch/android-sdk}}"
abi=all
while [ $# -gt 0 ]; do
	case "$1" in
		--abi) abi="$2"; shift ;;
		-h|--help) sed -n '2,23p' "$0"; exit 0 ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done

for tool in zip unzip rsync java; do
	command -v "$tool" >/dev/null || { echo "$tool not found" >&2; exit 1; }
done
[ -d "$sdk/platforms/android-36" ] || { echo "no Android SDK with platform 36 at $sdk" >&2; exit 1; }
export ANDROID_SDK_ROOT="$sdk" ANDROID_HOME="$sdk"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$sdk/gradle-home}"

# The copy: the working tree as it is (uncommitted edits included), without
# git data, ROM caches or build outputs.  Gradle's own outputs stay between
# runs so a rebuild is incremental.
tree="$out/tree"
mkdir -p "$tree"
rsync -a --delete \
	--exclude=/.git --exclude=/dist --exclude=/data/generated --exclude=/assets/generated \
	--exclude=/mobile/android/.gradle --exclude=/mobile/android/app/build \
	--exclude=/mobile/android/love/build --exclude=/mobile/android/love/.cxx \
	--exclude=/mobile/android/app/.cxx --exclude=/mobile/android/local.properties \
	--exclude=/mobile/ios \
	"$root/" "$tree/"

GEN1RECOMP_ANDROID_APPLICATION_ID="gen1recomp.coop.dev" \
GEN1RECOMP_ANDROID_APP_NAME="gen1recomp co-op (dev)" \
	"$tree/scripts/build_android.sh" --package-only

love="$tree/mobile/android/app/src/embed/assets/game.love"
proprietary='^(src/import/(LauncherView|LauncherSettings|OnlinePanel|CartLabelArt|CartShape|RomImporter|LauncherSplash|LauncherThemeVideo|BoxPanel|BoxUI)\.lua|src/mods/LauncherMods\.lua|src/import/online/.*|assets/labels/.*|assets/launcher/.*)$'
# (list once, then grep the text: unzip piped into grep -q dies of SIGPIPE
# under pipefail, see scripts/build_android.sh)
entries="$(unzip -Z1 "$love")"
mapfile -t drop < <(grep -E "$proprietary" <<< "$entries" | grep -Ev '^assets/launcher/lucide/' || true)
if [ "${#drop[@]}" -gt 0 ]; then zip -q -d "$love" "${drop[@]}"; fi
entries="$(unzip -Z1 "$love")"
left="$(grep -E "$proprietary" <<< "$entries" | grep -Ev '^assets/launcher/lucide/' || true)"
[ -z "$left" ] || { echo "game.love still holds upstream's launcher:" >&2; echo "$left" >&2; exit 1; }
grep -qx 'src/coop/launcher/Launcher.lua' <<< "$entries" || { echo "game.love is missing the fork's launcher" >&2; exit 1; }
echo "==> game.love without upstream's launcher (${#drop[@]} entries removed)"

# One ABI builds much faster (the emulator needs x86_64 only).
if [ "$abi" != all ]; then
	sed -i -E "s/abiFilters 'armeabi-v7a', 'arm64-v8a'/abiFilters '$abi'/; /abiFilters \+= 'x86_64'/d" \
		"$tree/mobile/android/love/build.gradle"
fi

printf 'sdk.dir=%s\n' "$sdk" > "$tree/mobile/android/local.properties"
(cd "$tree/mobile/android" && ./gradlew --no-daemon -q assembleEmbedNoRecordDebug)
apk="$(find "$tree/mobile/android/app/build/outputs/apk/embedNoRecord/debug" -name '*.apk' | head -1)"
[ -n "$apk" ] || { echo "gradle wrote no APK" >&2; exit 1; }
cp "$apk" "$out/gen1recomp-coop-debug.apk"
echo "==> $out/gen1recomp-coop-debug.apk ($(du -h "$out/gen1recomp-coop-debug.apk" | cut -f1))"
