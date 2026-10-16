# Partner presence in the world

What a co-op session shows in the game (#15, area A14 in
[design.md](design.md)): the other players on the map, the arrow to a
partner out of sight, their icons on the TOWN MAP, the CO-OP menu, notices,
and hold B to run. It lives in `src/coop/game/` and reads the running
session ([session.md](session.md)); a solo game shows none of it. The parts
that need battles, the opening (done with #22) or friend battles are #34
(friend battles and trades done with #23, [friends.md](friends.md)); the
last save in the CO-OP box came with the campaign files (#13).

## Files

- `Presence.lua`: the partners on the map. `Game:step` calls
  `Presence.step` every logic frame. It reads the session's last state and
  keeps one actor per partner in the overworld's entity list. It also hands
  the overworld its world and UI passes (`drawWorld`, `drawUI`).
- `Colors.lua`: each player's colour, by their place in the session.
- `Arrow.lua`: the partner arrow: the map search, where the arrow goes,
  drawing it.
- `CoopMenu.lua`: START > CO-OP and SELECT, the CO-OP menu.
- `TownMapMarks.lua`: the partners' icons on the TOWN MAP and the fly map.
- `Notices.lua`: the notices over the world.
- `Run.lua`: hold B to run.

Upstream files have one marked hook each (`co-op (#15)`):

- `src/core/Game.lua` (`Game:step`) calls `Presence.step`.
- `src/world/OverworldController.lua`:
  - `OverworldState:interact`: A on a partner opens BATTLE / TRADE /
    CANCEL (#23, [friends.md](friends.md));
  - `OverworldState:draw` draws the arrows in the world pass;
  - `drawUI` draws the notices;
  - `handleInput` opens the CO-OP menu on SELECT, and keeps a SELECT
    pressed mid-step like A and START.
- `src/ui/StartMenu.lua` adds the CO-OP row after OPTION.
- `src/ui/TownMap.lua` draws the partners just before the player's marker.
- `src/world/Player.lua` (`stepLength`) asks `Run.lua` for the step's
  frames.
- `src/render/SpriteRenderer.lua` draws a sprite that has `coopColors` in
  that palette in every COLORS mode, and replays it over the palette zones
  as OG RED's sprites are.

With a world-pipeline mod (#30, [mods.md](mods.md)) four more marked hooks
(`co-op (#30)`): the overworld's `ctx.drawFx` calls `Presence.drawFx`,
which draws the arrows and the "!" under the pipeline's camera (the world
pass skips them then); `SpriteRenderer:resolveImage` wears a player's
colour; `OverworldState.coopBaseHandleInput` keeps the engine's own
`handleInput`, and `Game:load` calls `CoopMenu.claimSelect` once the mods
are in, so SELECT in a session reaches the CO-OP menu past a mod's wrap.

## Rules and what was done

| A14 rule | Here |
|---|---|
| 1. Partners on the map are solid | A partner on this player's map blocks the cell they stand on and, mid-step, the cell they leave. The player's own steps and NPC wandering stop there (`Collision.canMove`). Scripted moves pass through, since they skip collision. A partner's own Pikachu is not drawn. Yellow was not run. |
| 2. Partners on connected maps | A partner on a map the overworld draws as a neighbour (the routes and towns its connections reach) is drawn there, eased, never solid. Out of sight, the arrow takes over. |
| 3. Colours, "!" | Each player wears the colour of their place in the session: red, blue, green, purple, orange, teal, pink, brown, then again (G11). It is an OBJ palette of white, skin, the colour and a dark outline. This player wears theirs too. A partner in a battle their own world opened stands where it started under the cartridge's "!" bubble (#34). |
| 4. Who is not drawn | A partner who left, or who has not reported a position yet, and a partner who joined a battle elsewhere (#34; they show again once it ends). A partner in the opening is not drawn and gets no arrow or TOWN MAP mark, and a player in the opening sees nobody (#22, [opening.md](opening.md)). A partner in a Cable Club room is not drawn (#60, [cable.md](cable.md)): their window shows the link screens, and the trade screen names them. |
| 5. Easing | A step is eased over 16 frames walking or surfing, 8 running or riding. A jump of more than two cells (a warp, a fly) lands at once. A step through a connection keeps easing across the seam. A partner reports the cell their step heads for, so the others ease it while they walk it. |
| 6. Arrow | See *The arrow*. |
| 7. TOWN MAP | The TOWN MAP item, the CO-OP menu's TOWN MAP row and the fly map show each connected partner's icon in their colour, under the player's own. The Pokédex's area view shows none. |
| 8. START > CO-OP | A CO-OP row after OPTION, only in a session. Upstream's START menu ends with MODS and QUIT, where the cartridge has EXIT, so CO-OP comes before those. Red, Blue and Yellow share this menu. See *The CO-OP menu*. JOIN <NAME> joins a partner's battle (#18), REJOIN goes back into one this player left (#20), and a partner in a battle shows IN A BATTLE in the box (#34) ([battles.md](battles.md)). A partner in the opening shows IN THE OPENING, and one who joins in it is announced so (#22). BATTLE <NAME> and TRADE <NAME> invite a free partner, and a partner meeting someone shows IN A BATTLE or TRADING (#23, [friends.md](friends.md)); a JOIN or REJOIN row names the foe on its second line, VS <FOE> (#34). The rows show three at a time and scroll. The last save is in the box since #13. |
| 9. SELECT | SELECT on the map opens the CO-OP menu in a session. The START menu, the bag, a battle and the party are screens of their own, so their own SELECT is untouched. In a co-op battle nothing opens: the battle is the screen on top, and its own SELECT swaps moves as in the cartridge (#34). |
| 10. Notices | "BLUE joined the session." and "BLUE left the session." Light text on a dark band at the top of the screen. Each stays 180 frames (3 s) and fades over the last 30; at most three show at once. A partner's battle this player is free to join is told: "BLUE is in a battle against wild PIDGEY. START > CO-OP to join." (a trainer: "against BUG CATCHER") (#34). A join that cannot go in says why ("The battle is full."), a battle away from the screen says how it ended, and a dropped link says "Lost the host: reconnecting..." and "Back in the session." (#20). |
| 11. Hold B to run | In a session, a walking step with B held takes the bike's 8 frames. The bike (the Cycling Road slope too) and surfing keep their own; a solo game walks as the cartridge does; there is no setting. Upstream Gen 1 has no run option: its `movement.speed` hook is where a mod adds one (`tests/mod_qol_hooks_tests.lua`). A mod there still wraps this. |

## The arrow

A partner off the screen is an 8x8 arrow in their colour, on the view's edge
two pixels in, blinking (on 28 frames of every 40). It is shown only while
the player walks about: no menu, text box, script, battle, warp or animation
up. It is drawn in the world pass, so every box and menu covers it, on the
edges of the map the player sees: a wide window shows more map than the
160x144 UI, and the arrow sits at the map's edge. Like the sprites, it is
replayed after the palette zones, so it keeps its colour in every COLORS
mode.

Where it points comes from a search of the maps, cached per pair of maps and
last map (`Arrow.route`):

- **Connections alone** reach the partner's map: the arrow points at the
  partner (at their drawn position while they are on a neighbour map).
- **Past a door or stairs**: the arrow stands over the door, pointing down,
  when the door is on the screen (a door in the top row keeps the arrow on
  the screen); otherwise it points at the door from the edge. The door is
  the last warp on a map that can be placed, which means this map or one its
  connections reach. Of the doors into the partner's own map, the one that
  lands nearest them wins. Otherwise a door on the player's map they can
  walk to wins, then the nearest. "Can walk to" is a flood over the map's
  walkable cells from the player; it does not treat ledges as one-way. The
  search counts maps between door and partner; doors with the fewest are
  kept.
- **Indoors**, a "last map" exit leads to the player's own last outdoor map,
  only while the search is still inside the building.
- **Nothing joins** the two maps (the partner flew, or is across the sea):
  the arrow takes the TOWN MAP's direction, from the player's place to the
  partner's. Both in one place: no arrow.

## The CO-OP menu

Drawn with the cartridge's font, boxes and cursor. The upper box shows:

- the campaign's name;
- on the host, `IP` and this device's first address (a VPN first, then the
  home network; `Addresses.mine()`);
- when the campaign was last saved (SAVED JUST NOW, SAVED 2 MIN AGO, NOT
  SAVED YET) and AUTOSAVE: ON (#13, [campaign.md](campaign.md));
- each partner with the TOWN MAP name of where they are, or AWAY for one who
  left.

The rows (three at a time, scrolling; a row's second line can name a
battle's foe, VS PIDGEY):

- JOIN <NAME> or REJOIN for a partner's battle ([battles.md](battles.md));
- BATTLE <NAME> and TRADE <NAME> for each free partner (#23,
  [friends.md](friends.md));
- TOWN MAP, only for a player without the TOWN MAP item. B goes back to the
  CO-OP menu.
- LEAVE SESSION, asked YES/NO with NO first. A guest says goodbye; the host
  ends the session for everyone. Either way the game goes back to the
  launcher, as when the host ends it, and the co-op screen says why.
- CANCEL. From START it goes back to the START menu, as B does.

The menu closes by itself if the session ends under it.

## Session changes

- **Protocol 3**: a `move` carries `travel` (`walk`, `run`, `bike`, `surf`)
  and so does each player in `state`. It chooses the sprite (the bike sheet,
  the surfing one; a sheet the cartridge lacks falls back to walking) and
  the easing.
- **Reported cell**: a player's report is the cell their step heads for, not
  the one they leave (`Session.position`).
- **Remembered campaigns**: a device keeps the newest 64 campaigns per host
  and seat (`Protocol.MAX_KNOWN`). More could not go into the hello, and the
  host dropped it, so a player stayed "joining" for good. The live run found
  this: the development entry hosts a new campaign on every boot.

## Checked

Run on Linux desktop (LÖVE 11.5) with US Red, two game processes on one
machine (`--coop-host` and `--coop-join=127.0.0.1`), each with its own save
folder, driven by frame drivers (no window, the offscreen video driver).
Every check below passed in one pass, and the screenshots were looked at
(they stay local):

- the join notice; BLUE next to RED in Pallet Town, each in their colour on
  both screens, facing as reported; RED's step into BLUE refused;
- START with CO-OP after OPTION; SELECT opening the CO-OP menu; its box
  (campaign, IP, BLUE in PALLET TOWN); TOWN MAP from it with BLUE's icon, and
  B back to the CO-OP menu;
- BLUE at the bottom of Route 1 drawn from Pallet Town, and RED from Route 1;
- BLUE far up Route 1: an arrow in BLUE's colour on the top edge, pointing
  up; RED's arrow on BLUE's bottom edge pointing down;
- BLUE in Red's house: RED's arrow standing over the house door; in the
  house, BLUE's arrow standing over the exit mat (a "last map" exit);
- RED holding B: 8-frame steps, and BLUE saw them as a run;
- BLUE leaving through LEAVE SESSION (YES): the leave notice and BLUE gone on
  RED's screen; RED's LEAVE SESSION ending the session and going back to the
  launcher.

The run found three faults, now fixed:

- the remembered-campaigns limit above;
- arrows placed on the UI layer, at the wrong scale on a wide window, and
  darkened by the SGB zones;
- in SGB mode a partner's TOWN MAP icon covered the player's own marker.

The CO-OP menu's box, the notices, the arrows and the TOWN MAP were seen in
SGB colours only. Not run: Blue and Yellow (Pikachu with partners), the fly
map with partners, the other COLORS modes, tilt and render-pipeline modes,
pads and touch, two machines on a LAN, Windows, macOS and phones.

## Tests

`tests/coop/presence_test.lua`, ROM-free, in the `engine` group (and so in
coop-ci). The fixture overworld runs headless, this device hosts a session
in-process, and a partner dials its loopback hub. It covers:

- protocol 3's `travel`;
- nothing of co-op in a solo game;
- the join notice; a partner drawn at their cell, solid, in their place's
  colour, and this player in theirs;
- easing: 16 frames walking, 8 running and riding; the cell left blocking
  mid-step; the bike sheet and the walking fallback;
- the player's step and an NPC's wandering stopped at the partner; a
  scripted move passing through;
- a partner on the connected route: drawn at its offset, passable, no cell;
- the overworld drawing with a partner, an arrow and a notice;
- the arrow on the top edge, none under a menu, none with the partner on the
  screen;
- the route search on maps of its own: exact, doors (nearest landing, a door
  the player can walk to), stairs and "last map" exits, no last map, a
  "last map" exit not followed once the search left the building, the
  cache;
- the arrow's placement: edges, diagonals, over a door, the top row, a TOWN
  MAP direction;
- START > CO-OP after OPTION; SELECT opening the CO-OP menu; its rows with
  and without the TOWN MAP item; its box;
- TOWN MAP marks, and none in the Pokédex's area view;
- hold B: 8 frames in a session, the bike and surfing keeping theirs, a walk
  without B; the reported cell and travel, and the others seeing it;
- the leave notice, a partner who left not drawn, notices fading;
- LEAVE SESSION ending the session and asking for the launcher, the CO-OP
  row and this player's colour gone afterwards.

`tests/coop/session_identity_log_test.lua` has the 64-campaign limit.
