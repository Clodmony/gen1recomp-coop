# Handoff

The session note for this repository. Read it first in a fresh session and
rewrite it at the end of every session (issue loop, last step). It lives in the
repository so it survives any worktree path and any tool; per-checkout agent
memory is not read by a session that starts in another worktree. State goes
here; stable recipes go into `docs/coop/`; personal data and hardware never.

Last updated 2026-10-16 (Group 11 integrated and tested live, with the
3D mod: PR #61, stacked on #58).

## Testing rule (owner, 2026-10-16)

The session tests everything itself, live with the cartridge, on the
**integrated** branch: every scenario of a feature, through the fork's
launcher and the game's menus, including desktop situations (two windows,
focus lost and back, hidden and shown, a frozen or crashed window). It
fixes what breaks (failing test first) before reporting. The owner does
not playtest; they play through with a friend once most of the work is
done. The Dramatic Shape 3D mod (#30) is a hard requirement for that
playthrough, so every live run of a new feature also runs with the mod
on.

## Repository state

- Default branch `gen1recomp-coop`; `main` = upstream main.
- Milestones: Group 8 holds #22 (done by #58). **Group 11** holds #57,
  #59, #55, #23, #60, #9, #34, #30, #65 and #66, all done by #61.
  **Group 12: Group 11 follow-ups** holds #62, #63, #64, #67. Group 2 still has
  #12 and #15 (owner-side checks); Group 10 holds #7 (mobile) and #27
  (launcher entries).

## Open pull requests (draft)

- **#58** `coop/group8-opening` into `gen1recomp-coop`: closes #22.
  G27 accepted. Tested live again inside #61's integrated runs.
- **#61** `coop/group11` into `coop/group8-opening` (stacked): closes
  #57, #59, #55, #23, #60, #9, #34, #30, #65, #66. Protocol 17 (11
  scenes, 12 Red and Blue, 13 starts, 14 Cable Club, 15 friends, 16
  League, 17 the hello's `start`); campaign file version 4. Decisions
  G28 to G35 all accepted by the owner (2026-10-16); G34 is the 3D mod,
  G35 a window that comes back is its own player and a unique encounter
  nobody is in is fought afresh.
  - Verify ALL PASSED at ee8d6289 (37/37 tiers); co-op tier 52/52 at the
    head. luacheck has not run (not installed here; CI does not run on a
    stacked PR): it runs once #61 targets `gen1recomp-coop`.
  - Integrated live runs (round 2): every feature again on the merged
    branch; seven bugs found and fixed (the PR body lists them). The 3D
    mod on the merged build: co-op, battles, walk-in, friend battle,
    split-screen. Not run: real windows and pads, Wayland minimizing,
    two machines, Yellow, German cartridges, the mod's Stadium models.
  - Merge order: #58 first, then `gh pr edit 61 --base gen1recomp-coop`,
    let CI (lint) pass and fix what it finds, then merge #61 locally as
    Claude (`git merge --no-ff`), push, run `tools/verify.sh`.

## Group 11's detail choices (owner, 2026-10-16: every recommendation taken)

Each detail keeps the first, recommended option below; the German wording
stays for the owner's later review in `german-wording.md`. The follow-ups
it calls for are filed in **Group 12: Group 11 follow-ups**: #62 (one
trade core), #63 (a Cable Club trade owed, not lost), #64 (split-screen
player 2 chooses how they start). Yellow mixing stays unsupported for
good (#9's answer); a gift lost on a reset is accepted and documented
(#55).

### #59 rival scenes (G29)
1. Where a scene starts: accept as built (a script fighting the rival on a scene map while his flag is unset; one ScriptRunner hook) [rec] / explicit hooks per scene in data/scripts.
2. A far partner on a large map (Cerulean) also frozen: keep as A10.5 says [rec] / only within a distance.
3. Waiting box: A joins, START/SELECT opens CO-OP [rec] / YES/NO "JOIN?" prompt.
4. German "%s stellt sich hier dem Rivalen. Warte oder hilf im Kampf...": accept [rec] / owner wording.
### #9 Red and Blue (G33)
1. Switch lives on the hosting device's campaign card, changed between hostings [rec] / in the campaign file, changeable while hosting (file v5).
2. Substituted Pokémon level: player's own cartridge's slot level (D104) [rec] / the other version's level.
3. Yellow mixing: keep unsupported for good [rec] / follow-up to investigate same-family battles + flag translation.
4. Extra draw only on slots offering an exclusive [rec] / on every encounter as in the sibling fork.
### #57 starts (G28)
1. Accept G28 as built (launcher writes start world into the slot, window sends `start`, host decides) [rec] / host builds the Pallet world / drop `returning` refusal.
2. Yellow: START IN PALLET hidden until #9 captures its opening [rec] / offer now with guessed state.
3. Pallet starter stands at the blackout cell (5,6) [rec] / outside Oak's lab door.
4. German wording (SO BEGINNST DU, DER SPIELANFANG, START IN ALABASTIA, SPIELSTAND MITBRINGEN, WECHSELN): keep, review later [rec] / replacements.
5. Split-screen seat 2 choosing how to start: follow-up issue [rec] / nothing.
### #60 Cable Club (G32)
1. Rooms as link screens over the session (upstream's LinkState), not walkable maps: accept [rec] / walkable rooms follow-up.
2. Timeouts: 30 s from the first offer, 60 s from both offers, back to lists [rec] / 30 s waiting in the room for any partner.
3. Owed-trade gap (window drops after the host committed the swap before getting the yes -> clone risk): file follow-up [rec] / accept the narrow race.
4. German HANDELSCENTER / KOLOSSEUM: keep until checked on a German cartridge [rec] / read from the cartridge (importer change).
5. The continue fix moves solo saves out of the rooms too: keep for every save [rec] / co-op only.
### #23 friends (G31)
1. Friend battles = upstream's link battle over the session; host commits trades once: accept [rec] / rebuild on G24 record.
2. One trade per pairing, then back to the map [rec] / back to the trade screen until CANCEL.
3. A battle released after 2 min away still pays EXP for what was fought [rec] / pays nothing.
4. German wording of 16 lines (KAMPF %s, TAUSCH %s, "%s sagt NEIN.", "%s hat zu tun."): keep [rec] / owner revises.
### Integration
- Two trade cores now exist: #23's Trade.lua (each window swaps its own rows, host lays the swap over incoming worlds until shown) and #60's CableTrade.swap (host swaps stored worlds, window stamps the received uid). Unify in a follow-up [rec] / leave both.
### #55 League (G30)
1. Accept G30 (every lobby entry asks for the clear; clear held by League presence/fight/uninducted) [rec] / clear only after whiteout or induction.
2. A reset reopens the host's world (last holdings + last SAVE) [rec] / the device's last SAVE.
3. "Every connected player inducted" literal (includes players in the opening/elsewhere) [rec] / only players who entered the League this run.
4. A gift landed after the last holdings is lost on a reset: accept and document [rec] / follow-up: host re-sends owed gifts after a restart.

### Round 2 (integrated tests, #30, the itest agents): owner, 2026-10-16, every recommendation taken

Forfeit EXP became #67 (Group 12). Owner: merge #58 and #61 now; next is Group 12.

- Forfeit EXP farm (A12.5 pays "won or lost"; RUN on turn 1 paid 621 EXP): no EXP to the side that forfeits [rec] / only after a full turn / keep.
- Flood rule also hits the host's own loopback player at inhuman rates: leave [rec] / exempt loopback.
- G34 (the 3D mod) as written: accept [rec] / change.
- SELECT in a co-op session opens the CO-OP menu, the mod's camera on "3" and its OPTIONS row [rec] / the mod keeps SELECT everywhere.
- Own colour in 3D with SGB colours not shown on your own screen: accept and document [rec] / follow-up.
- MODS page in SETTINGS only [rec] / also on each solo sheet.
- T-SHIFT blur also blurs an arrow at the top/bottom edge: accept [rec] / follow-up.
- G35 (same window / same seat takes its player back, 5 s hold): accept [rec] / strict A1.9 with duplicates.
- G35 (a unique encounter nobody is in ends as fled when met again): accept [rec] / keep the 2-minute wait with a waiting box.
- A brought save loses its own story entries when the campaign has a story (MISTY's POKéDEX row): keep per A4.3 [rec] / follow-up to keep key items like the Pokédex.

## Next candidates

- **Group 12** (#62, #63, #64, #67), the owner's pick (2026-10-16).
- Group 10 (#7 mobile, #27 launcher entries) needs owner decisions per
  feature; Group 2's #12 and #15 are owner-side checks.

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
- **Split-screen (#11).** `docs/coop/split.md` § Checks.
  - Claim two fake pads in `coop/launcher.json` (`seats`).
  - Replace `love.joystick.getJoysticks` in the driver and send real
    `love.gamepadpressed`/`released`.
  - `Split.current.game` is seat 2's game; run code inside its world with
    `Worlds.run(Split.current.world, fn)` (never across a yield).
  - To drive the launcher, write `relaunch_to_launcher.txt` first.
  - To check the mix without speakers: `ALSOFT_CONF` pointing at a file
    with `[general] drivers=wave` and `[wave] file=<scratch>/mix.wav`; the
    WAV is 32-bit float (WAVE_FORMAT_EXTENSIBLE), real time, so wait in
    real time (`love.timer.getTime()`), not in frames (offscreen runs
    uncapped).
- **Battles (#18-#20).** RED's driver builds a battle and pushes it the
  way the world does: `BattleState.newWild(Game, "RATTATA", 6)` (or
  `newTrainer(Game, "OPP_BUG_CATCHER", 1)`), `onFinish` calling
  `ow:afterBattle`, then `ow:pushBattle(b)`. GREEN joins with
  `Battles.join(Game, Battles.offers()[1].summary, name)`.
  - The battle on top with `.coop` is the copy. `Replica.question(b)` and
    `Replica.decider(b)` say what it asks and of whom; `Replica.send(b,
    cmd)` answers without the menus (a replacement: `{ kind = "replace",
    index = i }`); `Replica.leave(b)` leaves.
  - Tap A every few frames for the text, but not at your own menu question
    if the scenario must wait for a partner (A8.4 re-sends a command in
    flight).
  - A trainer's transition takes about 300 frames; give waits for the copy
    on top 8000 frames.
  - Check the host's session log (`coop/logs/*.jsonl` in RED's save folder)
    for `battle_desync`; `Replica.hash(b)` is the state digest each window
    reports.
  - A command sent before the host has the copy's question is refused
    `not_ready` and dropped: a driver resends until the copy moves on.
  - `newGame` gives both players the in-game name RED and no Pokémon:
    pick a partner by player id (`b.coop.me`), and give each player a
    Pokémon (`Pokemon.new`, `BattleState.stampOT`).
  - The host's copy of a world (`host.state:player(id).world`) follows the
    window's holdings at rest points; poll for a change, do not wait a
    fixed number of frames.
- **Trainers (#21).** VIRIDIAN_FOREST object 2, a BUG CATCHER at
  (30,33) facing left, sight 4: stand at (27,33) facing right to be
  spotted; (29,33) facing right and A talks to it. The overworld's
  `npcPool["VIRIDIAN_FOREST_obj_2"]` is the trainer.
- **The opening (#22).** `tests/drivers/util.lua`'s `newGame` mashes A
  through Oak's speech (it types the rival's name as AAAAAAA). To play the
  opening: `U.teleport(game, "PALLET_TOWN", 10, 2, "up")`, walk up until
  Oak's script holds the player, mash A until
  `EVENT_OAK_ASKED_TO_CHOOSE_MON` and the lab is idle, teleport to
  `OAKS_LAB` (6, 7 or 8, 4) facing up, mash A for the ball, walk down to
  the rival battle, mash A through it, then to the door at (4/5, 11):
  tap A whenever something holds the player (the rival's walk-out lines).
  A test client with no world in the campaign is in the opening until it
  sends `sendOpening(true)`.
- **Launcher-driven runs and the 3D mod.** The integrated tests drove the
  fork's launcher: write `relaunch_to_launcher.txt` (`return { tab = "red" }`)
  in the save folder, and the driver gets the launcher (`arg.menu`) first,
  then the game. Set the ports in the driver (`Transport.DEFAULT_PORT`,
  `Beacon.PORT`, the launcher's `CoopMenu.DEFAULT_PORT`). Install the mod
  by hand per run: copy the owner's downloaded copy
  (`~/dev-scratch/gen1recomp-coop/mod-dl/dsv`, never committed: its
  licence forbids redistribution) to `<save folder>/mods/dsv`, then
  `require("src.render.Pipelines").setLevel("voxel", 4)` in the driver.
  Drivers and save templates of Group 11 are in
  `~/dev-scratch/gen1recomp-coop/g11/` (`itest1/`, `itest2/`, `fin/`,
  `tpl/a`, `tpl/b` with four solo saves each; `itest1/regress.sh` reruns
  every itest1 scenario). Keep them until #61 is merged, then delete
  `tpl/` (it holds extracted cartridge data).
- **Loopback test clients** need a hex `device` id (`"c1"`, not `"y1"`):
  the protocol drops a hello with another one.
- **Cells used for #16:**
  - Viridian Forest ANTIDOTE: stand at (25,12) facing up.
  - Viridian Forest POTION: (11,29) facing right.
  - Daisy: BLUES_HOUSE (2,4) facing up.
  - The bike shop clerk: BIKE_SHOP (6,4) facing up.

## Worktrees and background processes

- Main checkout on `gen1recomp-coop` (leave it; behind origin until pulled).
- The Superset worktree `veiled-degree-…` holds `coop/group8-opening`.
- `~/dev-scratch/gen1recomp-coop/wt/group11` holds `coop/group11`; remove
  it once #61 is merged. Every agent branch and worktree is removed (all
  merged into `coop/group11`).
- No background processes. `~/dev-scratch/gen1recomp-coop/g11/` keeps
  the drivers, save templates and questions (see the recipe); the
  playtest folder is deleted.

## Still open

- After each `main` sync: `gh workflow list -R Clodmony/gen1recomp-coop --all`
  and disable upstream's workflows.
- Optional local tools: luacheck (JDK 17 is installed since 2026-10-16); with
  six agents' code unlinted, installing it (`luarocks install luacheck`) is
  worth it.

## Cleanup

- Done 2026-10-15 (owner approved): every merged branch, locally and on
  GitHub (the two above excepted); the milestones of Groups 1 to 7a.
- Once #58 is merged: its branch, locally and on GitHub.
