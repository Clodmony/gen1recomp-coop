# Phones: the Android build, the launcher on touch, iOS

Issue #7. The fork's launcher and the game on a phone, from a local build
that is never published (AGENTS.md). Android is built and was run on an
emulator; iOS is blocked (below). Split-screen on a phone is left out for
now (owner, 2026-10-17).

## Building an APK

`tools/build_android.sh [--abi x86_64|arm64-v8a|armeabi-v7a|all]` writes a
debug APK to `~/dev-scratch/gen1recomp-coop/android-build/gen1recomp-coop-debug.apk`
(`COOP_ANDROID_OUT` moves it). It:

- copies the working tree (uncommitted edits included) to `<out>/tree` and
  runs upstream's `scripts/build_android.sh --package-only` there, because
  that script writes into `mobile/android` (branding in `gradle.properties`,
  `game.love`); the checkout stays clean;
- builds under the fork's own app id `gen1recomp.coop.dev` and name
  "gen1recomp co-op (dev)", so it installs next to upstream's app;
- takes upstream's launcher out of `game.love` (LICENSE.MD term 2): the
  modules `tests/coop/launcher_boot_test.lua` forbids, `src/import/online/`,
  `assets/labels/` and `assets/launcher/` except `assets/launcher/lucide/`
  (the icon sheets the save editor's kit draws, as on desktop). The build
  fails if one of them is still in the archive or the fork's launcher is
  missing;
- runs gradle (`assembleEmbedNoRecordDebug`) on the vendored love-android
  11.5a tree. `--abi x86_64` builds only what an emulator needs and is
  much faster; the default builds arm64-v8a, armeabi-v7a and x86_64 (39 MB).

It needs JDK 17, `zip`, `unzip` and `rsync`, and an Android SDK with
platform 36, build-tools 36 and NDK 25.2.9519653 in `ANDROID_SDK_ROOT`
(default `~/dev-scratch/gen1recomp-coop/android-sdk`). The SDK can be set up
without root from Google's command-line tools:
`sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
"ndk;25.2.9519653" "emulator" "system-images;android-34;google_apis;x86_64"`.
Upstream's optional ShaderFX bridge (Rust, cargo-ndk) is not built.

## The launcher on a touch screen

The launcher knows a phone by `love.system.getOS()` (Android or iOS). There:

- **A tap presses when the finger lifts**; a finger that moves more than
  6 launcher pixels drags the page instead and presses nothing. On a phone
  in portrait every page fits; on its side SETTINGS and CONTROLS scroll.
- **Files come through the system's file picker.** A phone can neither drop
  a file nor type a path, so the import screens of PLAY (the ROM), SAVES
  (IMPORT .SAV) and MODS (+ INSTALL MOD, a mod's IMPORT FILE) have CHOOSE
  FILE. It calls `love.system.pickFile` (a native bridge of the vendored
  love-android, not part of LÖVE), which copies the picked file into the
  save folder as `picked_rom.gb`, `picked_save.sav`, `picked_mod.zip` or
  `picked_required_import.bin`; a cancel or a failed copy leaves
  `pick_error.flag`. The launcher takes the copy up when it appears (each
  frame while a pick is open, else once a second, so also after Android
  closed the app while its picker was open) and removes it. A cancel says
  nothing; a failed copy says so.
- **EXPORT asks where the .sav goes.** The exported file is staged as
  `pending_export.sav` and `love.system.createFile` opens the system's
  save-as screen; `export_done.flag` says the copy was written. An app
  without the bridge names the file in the app's folder, as on desktop.
- **SETTINGS > ON-SCREEN CONTROLS**: LAYOUT opens upstream's
  touch-controls editor (`src/ui/TouchControlsEditor.lua`) and SKIN its
  skin studio (`src/ui/SkinStudio.lua`), both GPL, through `main.lua`'s
  `openTouchControlsEditor` and `openSkinStudio`, over the parked
  launcher; their Done or Close comes back to SETTINGS. They are not
  offered on desktop. This is #27's deferred decision (G38), decided in
  G39.
- No QUIT on PLAY (the system closes the app), no OPEN LOGS FOLDER.

The game itself is upstream's on a phone: its on-screen pad
(`src/core/TouchControls.lua`), the "•••" quick bar (SAVE, LOAD, SPEED,
COLOR, TILT, ZOOM), the START menu's QUIT to the title and the title's
EXIT GAME back to the fork's launcher. Android's back gesture opens the
title menu. The quick bar's SAVE, LOAD and SPEED in a co-op session are
#72.

## Co-op on a phone

Online co-op uses the same session as desktop. JOIN A FRIEND types the
host's address on the launcher's keypad. Nearby discovery (the LAN beacon)
was not run: an emulator sits behind its own network address translation.

Design A15 in a phone run: the on-screen pad stays usable under the CO-OP
menu (SELECT opens it) and a co-op battle in portrait (A15.1); the swipe and
tap gestures over the CO-OP menu and a battle (A15.2) are not built (#73).
iOS discovery (A15.5) is untested with iOS.

## iOS

Blocked: `scripts/build_ios.sh` needs macOS and Xcode (`xcodebuild`), and
this project's machine runs Linux. The fork's code has nothing
Android-only: the launcher treats iOS as a phone, and the picker and
save-as bridges are used when `love.system.pickFile` / `createFile` exist,
which on iOS needs upstream's patched LÖVE (`mobile/ios/patch_love_src.py`).
A build would need the same launcher strip as `tools/build_android.sh`
does.

## Checks

`tests/coop/launcher_mobile_test.lua` boots `main.lua` as Android at
1080 x 2400 with a stand-in picker: IMPORT ROM's CHOOSE FILE, the picked
copy checked and removed, a cancel and a failed copy, a copy waiting from
before a restart, a save and a mod through the picker, EXPORT through the
save-as screen and without it, a drag that scrolls without pressing and a
tap that wobbles, and SETTINGS' LAYOUT and SKIN opening the editor and
studio and coming back. `tests/coop/launcher_ui_test.lua` lays out the
phone's import, SAVES and SETTINGS screens at every size in English and
German.

### Run on an emulator (2026-10-17)

An Android 14 x86_64 emulator (Pixel 6 size, 1080 x 2400, headless,
software GL) on Linux, the debug APK built by `tools/build_android.sh
--abi x86_64`, driven with `adb` (taps, key events, `uiautomator` for the
system's screens). Before the fix, the import screen said importing a ROM
comes later. After it:

- the fork's launcher started in portrait with the credit line; IMPORT
  ROM > CHOOSE FILE opened the system's picker, a US Red ROM picked from
  Downloads was imported ("RED is ready to play"), and NEW GAME played the
  intro on the on-screen pad;
- IMPORT .SAV through the picker made a new slot; EXPORT opened the
  save-as screen and wrote a 32 KB .sav to Downloads; a drag scrolled
  SETTINGS to its end; LAYOUT moved the A button and Done came back to
  SETTINGS; SKIN selected the GBA skin, which the game then used;
- + INSTALL MOD through the picker installed the Dramatic Shape Voxel Mod
  (#30) from a .zip; the touch SELECT turned its 3D view on in a solo game,
  after the mod built its voxel cache once (about five minutes on the
  emulator);
- a desktop host on the same machine (LÖVE 11.5, offscreen) and the phone
  joining by address (10.0.2.2, the emulator's way to the machine): the
  phone played the private opening, its moves and map changes reached the
  host; with START IN PALLET and the 3D mod on both sides each saw the
  other on the map; SELECT opened the CO-OP menu; JOIN DESK joined the
  host's wild battle, the phone's copy ran in portrait with the pad below,
  its touch menu sent a suggestion, the battle ended in a win with no
  desync in the host's log;
- the app in the background for 20 s and for 75 s kept its session (the
  host saw the next step); the host closing the session sent the phone
  back to its launcher with the reason; REJOIN dialled again.

Not run: a real phone (arm64; the APK for it builds), pads on Android, the
LAN beacon, two phones, German cartridges on a phone, the voxel mod's speed
on real hardware (the emulator renders in software), and iOS.
