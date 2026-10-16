# Mods in the fork's build

The fork runs upstream's mods, including the ones that patch the engine,
on its own boot path (#30, decision G34 in [design.md](design.md)). The
mod the owner plays co-op with is the **Dramatic Shape Voxel Mod**
(`DRAMATIC_SHAPE` 1.9.0,
[scottcandy34/DramaticShapeVoxelMod-latest](https://github.com/scottcandy34/DramaticShapeVoxelMod-latest)):
it draws the overworld as a voxel diorama, adds first- and third-person
cameras (1ST, 3RD), 3D battles (2D-3D, or STADIUM models from an optional
Pokémon Stadium ROM), water, shadows, anti-aliasing and the time of day,
with its rows on the game's OPTIONS menu.

## Install, never bundle

The voxel mod's README forbids redistributing its code, and its
repository has no licence. So the fork never copies, vendors or ships it,
not even in tests or fixtures: the player installs it. The fork's tests use
a stand-in of its own (`tests/coop/fixtures/mod_standin`) with the same
manifest fields (`api 2`, `engine_internals`, `affects_link: false`, an
optional import).

## Installing and turning mods on

- **The launcher**: SETTINGS > MODS (for the cartridge picked on PLAY)
  lists the mods on this device, each with its name, version, description,
  what it declares (PATCHES ENGINE CODE, CHANGES LINK PLAY) and its
  optional files. A press turns a mod ON or OFF for that game. **+ INSTALL
  MOD** takes a mod's .zip (dropped on the window, or its path typed or
  pasted) or its folder (dropped) and copies it into the save folder's
  `mods/<id>/`; a repository's .zip with the mod in one folder
  (`<Repo>-main/manifest.json`) works as it is. Installing a mod that is
  already there replaces it (an update). **IMPORT FILE** takes a mod's
  optional file (the voxel mod's Stadium ROM), checks its size and MD5
  against the manifest and stores it in the mod's `baseroms/`. A change
  takes effect when the game starts. See [launcher.md](launcher.md).
- **By hand**: a mod folder copied to `<save folder>/mods/<dir>/` loads
  too; the game's mod loader finds every `mods/*/manifest.json`.
- The ON/OFF flag is the one upstream's game reads at boot
  (`options.modsByVersion.<game>` in `options.lua`, GPL `SaveData`); a
  mod with no flag is on, an experimental one off.
- In the game the mod's own OPTIONS rows work as upstream's (DRAMATIC
  SHAPE: VOXEL, T-SHIFT, SHINY ODDS, 3D WORLD, BATTLES, PERFORMANCE and
  its own STADIUM ROM row).

The launcher's page is built on the GPL mod modules only
(`src/coop/mods/Installed.lua`: `Manifest`, `SaveData`'s flags,
`RequiredImports`). Upstream's mod manager (`LauncherMods`) is part of its
proprietary launcher and is never used. Mod updates from GitHub, mod
profiles, mod indexes and carts stay with #27.

## What the fork does for such a mod

A world-pipeline mod owns the overworld's world pass (upstream's
`render_pipelines` registry) and patches engine code. Five things in the
fork needed a change for it:

1. **Upstream's launcher stays out.** The voxel mod wraps upstream's ROM
   importer for its Stadium ROM drop (`require("src.import.RomImporter")`
   in a `pcall`). In the fork's build a mod's require of any upstream
   launcher module fails (`src/coop/mods/Gate.lua`, a marked hook in the
   sandbox's require), so the module is never loaded (LICENSE.MD term 2);
   the mod falls back to its own drop handler.
2. **The partner arrow and the "!" bubble** were drawn in the world pass,
   which a pipeline's world image replaces. With a pipeline they are drawn
   in its field-effect pass (`ctx.drawFx`, a marked hook calling
   `Presence.drawFx`), placed by the pipeline's own camera: an arrow points
   where the partner is on the screen the player sees, and a partner
   behind the camera (1ST, 3RD) gets one along the ground towards them.
3. **The partner's colour.** A pipeline textures a sprite from the map's
   palette unless the sheet is true colour, so a partner's sprite reaches
   it as finished colours in the partner's place colour (`Actor:pose`).
   `SpriteRenderer:resolveImage` wears a player's colour too (a marked
   hook), which a pipeline uses in the GBC colours.
4. **SELECT.** The voxel mod steps its camera with SELECT on the map, in a
   wrap of the overworld's input outside the engine's. In a co-op session
   SELECT stays the CO-OP menu's (design A14 row 9): a frame with SELECT
   pressed goes to the engine's own `handleInput` (captured before the
   mods load), whose hook opens the menu (`CoopMenu.claimSelect`, called
   from `Game:load`). Solo play keeps the mod's SELECT; in a session the
   camera is the "3" key and the mod's OPTIONS row.
5. **Split-screen.** The mod renders its scene at the size LOVE reports
   for the window. In a split-screen half that cut each view to the left
   part of a window-sized scene. A mod's `love.graphics` now answers
   `getDimensions`, `getPixelDimensions`, `getWidth` and `getHeight` with
   its game's view (`GameViewport`; the window when there is none), and
   every write to it reaches the real `love.graphics` (the voxel mod swaps
   `rectangle` around the battle's draw).

## Co-op

- The mod's options are each player's own and graphics only; nothing of
  them is sent (`affects_link: false`). A co-op session does not compare
  mods, so a partner without the mod sees the 2D world and plays the same
  campaign.
- Partners are drawn in the diorama in their colour, solid on this map
  and eased like in 2D; the arrow and the "!" follow the 3D camera.
- Co-op battles (#18, #19) and friend battles (#23) stage in 3D-BTL mode
  like a solo battle: the arena where this player stands, the HUDs and the
  co-op battle's boxes over it. A friend battle is upstream's link battle,
  whose own check compares only mods that change link play.
- In split-screen each seat's world loads its own copy of the mod (the
  worlds' modules are separate, [split.md](split.md)), so each player has
  their own camera and OPTIONS. Both write the one `options.lua`; the
  levels a seat set last are the ones the next start reads.

## Checked

Live, Linux desktop (LÖVE 11.5), US Red, offscreen at 1024 x 768, with the
owner's copy of the mod (1.9.0) installed in each process's private save
folder, 2026-10-16:

- **Solo, the fork's boot path**: the mod loads (no upstream launcher
  module loaded, checked in the process), the voxel overworld draws in
  Cerulean's Pokémon Center and on Route 4 at FULL, 50, 1ST and 3RD; the
  3RD free walk moves the player; OPTIONS > DRAMATIC SHAPE opens its page
  and A on T-SHIFT steps it; a wild battle on Route 4 stages in 3D
  (2D-3D A: the player's back and the foe on the map, the HUDs over it).
- **The launcher**: SETTINGS > MODS listed the bundled example mods; a
  typed path to a .zip of the mod (in a repository folder) installed it
  into `mods/DRAMATIC_SHAPE/`; OFF and ON wrote the flag; CONTINUE booted
  the game with the mod loaded and its pipeline registered.
- **Online co-op**, two processes on one machine (host and guest, both
  with the mod): each sees the other in the diorama in their colour, the
  arrow at the screen's edge when the partner walked away east, the "!"
  over a partner in a battle with its notice ("ASH is in a battle against
  wild RATTATA...") over the diorama, the CO-OP menu on SELECT, a wild co-op
  battle in 3D-BTL in both windows with no `battle_desync` in the host's
  log, and a friend battle (A on the partner, BATTLE, YES) in 3D-BTL.
  Focus lost for 4 s and back, and hidden and shown, kept the link (no
  `left`/`joined` in the log). The guest quit first and the host saw it
  leave.
- **Split-screen** (`--coop-host --coop-split`, two fake pads): each half
  draws its own 3D view centred on its player (one at 50, one at 3RD),
  and a wild battle in seat 2's world stages in its half while seat 1
  sees BLUE under the "!".

Frame time, the mean over 2-3 s of real frames, uncapped, same machine:

| | ms per frame |
|---|---|
| Solo, 2D | 2.0 |
| Solo, voxel at 50 | 5.1 to 5.4 |
| Solo, voxel at 3RD | 6.9 to 7.2 |
| Solo, a 3D battle | 7.3 |
| Split, both 2D | 2.4 to 2.5 |
| Split, one voxel (50), one 2D | 4.0 |
| Split, both voxel (50 and 3RD) | 8.8 to 9.8 |
| Split, a 3D battle in one half | 8.8 |

So drawing the world twice costs about what two half-size scenes cost:
under 10 ms a frame here, within a 60 Hz frame with room to spare. Before
the view-sized fix each half rendered a whole window's scene (10.6 ms).

Again on the merged Group 11 build (#61, with #22, #57, #59, #55, #23,
#60, #9 and #66 in it), the mod installed by hand in each save folder: a
host who started in Pallet Town through the fork's launcher and a guest
joining with START IN PALLET both drew the voxel world and each other,
SELECT opened the CO-OP menu, hiding the guest's window for 4 s kept the
link, and START > SAVE saved; the host announced the guest as "MISTY
joined the session." (not in the opening, #66). A wild co-op battle
joined from the CO-OP menu, a walk-in to a partner's battle and a friend
battle ran in 3D-BTL with no `battle_desync`; split-screen with both
halves in 3D took 8.8 ms a frame.

Not run: Windows, macOS and Android, a real window and real pads, two
machines, the VR companion mod, the STADIUM models (no Stadium ROM here),
the mod's optional file through IMPORT FILE (the test covers it with the
stand-in), installing a dropped folder (LÖVE only mounts a folder dropped
on the window; the test covers the copy).

## Limits

- **This player's own colour.** In the SGB colours the mod paints this
  player's sprite from the map's palette, so in 3D a player is not in
  their place colour on their own screen (partners are). The 2D world and
  the GBC colours keep it.
- **The T-SHIFT blur** is applied to the finished world image, so an
  arrow at the top or bottom edge is blurred with it.
- The mod claims keys 3, 5, 6, 7, 8, 9 and the mouse in the overworld, as
  it does upstream.

## Tests

- `tests/coop/mods_test.lua`: the stand-in through the loader (its
  manifest fields, its pipeline and options; upstream's launcher module
  refused to it); its `love.graphics` sized by a split-screen view, writes
  passing through; in a session, the arrow and the "!" drawn by the
  pipeline's pass under its camera, once; the partner's sprite as finished
  colours; SELECT the mod's in solo and the CO-OP menu's in a session.
- `tests/coop/launcher_mods_test.lua`: SETTINGS > MODS, the cards, ON/OFF
  as the loader reads it, installing from a repository folder or the top
  of a .zip (a copy replaced, `.git` left behind, a missing manifest and a
  bad id refused), the optional file checked by MD5 and stored.
