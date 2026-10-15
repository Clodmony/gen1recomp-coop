# Co-op design

The co-op campaign of gen1recomp-coop: two or more players share one Red,
Blue or Yellow campaign, online (direct connections) and in local
split-screen, through one session layer.

The design is carried over from the sibling fork
[Clodmony/pokerecomp-online-coop](https://github.com/Clodmony/pokerecomp-online-coop)
(a Godot fork of Decryptu/pokerecomp, branch `pokerecomp-online-coop` at
`925fafec`), as the owner asked on 2026-10-13: every co-op decision,
improvement, gameplay feature and mechanic, as **behaviour, not code**. Its
`docs/coop/` (brief, design, decisions D1 to D110, playing, progress,
playbook, architecture, test-cases, readiness, german-wording) and its open
issues were catalogued into the areas below. Citations: `Dn` = the sibling's
decision, `design §X` = its design.md section, `#n` in a citation = its issue,
`play` = playing.md, `prog` = progress.md, `tc Xnn` = test-cases.md row,
`arch` = architecture.md. Issue numbers in the *Issues* table are this repo's.

Classes:
- **carry**: a gameplay rule that transfers as it is.
- **adapt**: transfers, but needs re-thinking for LÖVE/gen1recomp, split-screen,
  Yellow, mobile or the fork's own launcher (what to re-think is said).
- **skip**: Godot-, Decryptu/pokerecomp- or source-process-specific (why is said).

Marked **(uncertain)** where the source docs do not settle a detail. When a
rule changes here, the change is recorded under *Decisions* below and the
rule is edited in place.

---

## 1. Brief: the owner's goals and constraints that still apply

- **The game:** a full cooperative Red/Blue campaign (the target adds Yellow),
  initially for two players. Story progression and Gym badges are shared; each
  player owns their Pokémon team, inventory, money and position. Both explore
  independently, also on different maps. It is co-op against the game, not
  just trading or PvP.
- **Battles:** a player may battle while the other explores or fights a separate
  battle; a free player may join a running battle from any map, taking effect
  at a safe turn boundary. One active Pokémon per side; the allied roster holds
  up to twelve (two teams of six). The owner of the Pokémon that is out
  controls the turn; switching to the partner's Pokémon hands control over.
  The other participant's advisory cursor and suggestions never act or use up
  a turn. No player or Pokémon is in two battles at once. Shared story wins and
  badges advance the campaign for both.
- **Defaults:** the joiner's exploration is suspended and their return point
  kept; the initiator stays at the encounter. Each player keeps ownership of
  their Pokémon; items come from the acting player's bag; a catch goes to one
  named player and is never duplicated; experience is tracked per Pokémon and
  paid to its owner. Unique trainers, bosses and story encounters have one
  active instance. Major progression commits exactly once even if messages
  repeat. Losing a battle's required controller pauses only that battle. Host
  shutdown ends the session cleanly; host migration is out of scope.
- **Policies apart from simulation:** open rules (prize split, withdrawal,
  late onboarding) get sensible provisional behaviour, kept in one policy place
  separate from the core simulation, and documented.
- **Architecture:** host-authoritative (clients send intentions, the host
  validates and resolves); clear ownership boundaries (campaign, player, world
  simulation, battle sessions, client presentation, persistence); stable ids
  for players, Pokémon, encounters and battles, never array positions; never a
  merged twelve-member save, each team stays at six; suggestions apart from
  commands; revision ids to refuse stale or repeated actions; no ROM or
  extracted asset ever sent between players, each imports locally.
- **Platforms:** Windows, Linux, Android and iOS with cross-platform play;
  mobile input, suspend/resume and reconnection designed in from the start;
  LAN/direct IP first; no paid relay or external service required for the
  first milestone; nothing published to an app store; iOS acceptance is an
  investigation, not a promise; no executable mod loading in the first iOS
  scope.
- **Testing and honesty:** tests for isolation of simultaneous battles, rosters
  above six, turn authority following ownership, suggestions not mutating
  state, joins only at boundaries, no duplicate participation or rewards,
  shared story with independent locations, save round-trips and disconnects.
  Keep static inspection, passing tests, a successful build and verified
  multiplayer play apart; never report an untested platform or feature as
  working. Never download a ROM; ask the owner for a local one.
- **No longer applying:** the private-repository and Godot-retention parts, the
  source's milestone list, and "local split-screen is a later milestone" (it is
  core in the target). German was a later issue there (D17); see area A15.

---

## 2. Feature areas

Bullets are numbered `A<area>.<n>` so the *Issues* table can assign them.

### A1. Session and connection core

1. **carry** Host-authoritative session: clients send intentions (move, start or join
   a battle, battle command, suggestion, save, world patch, party copy); the host
   validates them and answers each player with only what that player may see
   (design §Sessions, D5, arch).
2. **adapt** One host runs over an in-memory loopback and over the network
   transport alike, independent of engine internals (D11). In the target the
   loopback is the **split-screen transport**, not only a test aid; the network
   side should reuse upstream's ENet LAN link and JSON messages with schema
   checks.
3. **adapt** The hosting device runs the host in-process and its own player
   dials it like any other client (D26). Split-screen: both local players are
   loopback clients of the same in-process host.
4. **carry** Every client field is untrusted: text and numbers type-checked; a world
   patch keeps only entries in their key's own shape and type; a sent Pokémon
   is decoded only when every field has a save's type; a brought save is
   rebuilt from such parts; a team is never replaced by an empty one. A
   seeded fuzz test sends every message type malformed (D35). Messages may
   reach 2 MiB (a full PC is about a quarter of a megabyte) (D35); check the
   target transport's and relay's size limits **(adapt detail)**.
5. **carry** Per-player strictly increasing sequence numbers; a repeated number is
   refused (`duplicate`); the welcome tells a reconnecting client the last
   sequence the host saw (D7, arch §Protocol).
6. **carry** A protocol version in every probe/hello; another version is refused
   (`protocol_mismatch`). A refused hello is told why (`rejected` with a reason)
   before the link is dropped after a short grace (D21, arch).
7. **adapt** Cartridge identity (game id and SHA-1) must match the host's, or be
   the paired version (A13); no ROM or extracted content is ever transmitted
   (design §Sessions, D101). Re-think for Yellow and the target's ROM
   verification.
8. **carry** A `probe` before `hello` on the same link: the host answers whatever the
   protocol, creates no player, and returns the campaign (id, title), build and
   protocol, cartridge fit, its players (name, game, connected, badges, place),
   and which trainer this device or name would get back. Mismatches are found
   before a player exists (D103, arch).
9. **adapt** Identity: a device remembers its player per host per campaign id; the
   hello carries that map and the host looks up its own campaign; a device whose
   remembered player is already connected joins as someone new (two windows on
   one machine are two players); a player whose device lost its id is
   recognised by typing the same name (D26, D48, D49). Split-screen needs two
   remembered identities per device (one per local seat). Here (#11) both
   seats remember theirs in one identity, under the host's key and the seat
   ([split.md](split.md)).
10. **carry** Windows stay trusted (owner, D72): the host checks only step length (up
    to two cells on the same map, a ledge hop), trusts the warps a window
    reports and the enemies its world prepared; collision is the window's own;
    no host-side re-simulation (design §Exploration, D20, D72).
11. **adapt** LAN discovery: a hosting session sends its lobby view and port as a
    UDP beacon on port 24681 once a second (broadcast, each network's `.255` and
    127.0.0.1); Join lists hosts heard in the last four seconds; one listener
    per device; optional (the address path is complete without it); mDNS was
    rejected (D103, arch). Check against upstream's own LAN link discovery and
    iOS's multicast entitlement.
12. **adapt** Default game port UDP 24680, `:port` may be typed (play). The
    co-op ports stay apart from upstream's link port 7777 (G8).
13. **adapt** Internet play in the source is a VPN or a forwarded port only, no
    relay (play §Playing over the internet; #51 open). Upstream has an external
    TCP relay; co-op does not use it (G5).
14. **adapt** Session logs on every device: one JSON-lines file per session (unix
    ms, frame, random device id, player name, per-device number, source, player
    id, kind, plain data), last 30 files and at most 256 MB kept. The host logs
    its start state, every message with its result, battles with seeds and each
    revision's view, commits, saves and its end state, enough for a replay tool
    to re-run a fresh host to the same end. Optional sharing (default on):
    clients send their own lines every 2 s in batches of at most 64 KB (a line
    over 8 KB without its data), the host relays them to every other sharing
    device with a 256 KB backlog for late joiners; relayed lines are never sent
    on. Logs contain names and addresses: never posted publicly (D59, play
    §Logs). Re-think for LÖVE's save directory; in split-screen one process
    holds both players' lines (here each seat writes its own file, and the
    first seat's link shares, #11). The local logs are #10, sharing them #31
    ([session.md](session.md)): the hello's `logs` carries only `share`, the
    hello's `device` already names the device.
15. **skip** Godot `var_to_bytes` encoding and `ENetMultiplayerPeer` raw packets
    (D11): engine-specific; the target already has JSON over ENet.

### A2. Launcher co-op flow (hosting, joining, campaign management)

All of this lives in the fork's **own** launcher (upstream's is proprietary).
The screens are in place (#12, [launcher.md](launcher.md)), laid out after
#38's design (G13): the start screen is the PLAY tab and the troubleshooting
entry (log sharing, the logs folder) is on the HELP tab. Left for other
issues: the line saying which games play together and the both-versions
switch (#9); a card's badges, place and last save (campaign files, #13); the
rival's name and how a new player starts (#22); the split-screen entry
(#11); a phone layout run on a phone (#7).

1. **adapt** Start screen: cartridge tiles (Ready / needs re-import / not imported),
   the pick remembered, a line saying which games play together; HOST and JOIN;
   a **Last session** row that hosts the last campaign again or rejoins the
   last host in one press; a Troubleshooting entry (log-sharing switch, open the
   logs folder) (D103, play §Starting). Re-think as Game Boy-style screens.
2. **carry** Host screen: one card per campaign of this cartridge and of its paired
   version, showing the game it was started on, players, the cartridge each
   plays, badges, place and last save, latest saved first; edit renames the
   campaign or the rival (the rival's new name applies at the next hosting);
   delete asks again and keeps the last state as a `.bak` that can be renamed
   back (D49, D103, tc K05, K15).
3. **carry** New campaign: name; the rival's name from the cartridge's presets,
   typed, or "ask in Oak's speech"; the player's name; how they start (A4); the
   "wild Pokémon from both versions" switch (A13) (D103, D104, play).
4. **adapt** Hosting screen: the addresses partners join at, each labelled by network
   (a VPN first, then the home network) with Copy, the one a partner used last
   time marked; live players with the cartridge they play; "Enter the world" at
   any time (partners can join later); the session keeps running while the
   launcher shows it; stopping with a partner in asks first and tells the
   partner (D103, tc K03, K04). Clipboard and network naming differ on mobile.
5. **carry** Join screen: **Nearby** (from the beacon, one Join button per fitting
   cartridge, a non-fitting host says why), **By address**, **Recent**. The
   Connecting sheet shows each step (host found, same version, cartridges fit);
   a device the host knows sees one "Join as <name>"; a new player names
   themself and chooses how to start; a version or cartridge mismatch is named
   exactly, with the player's cartridge that would fit (D103, play, tc S02,
   K06, K07, K10).
6. **carry** Dialling retries every 3 s for a minute (partners often press Join
   first) with a countdown, Try now and Cancel; then "could not reach" with a
   checklist that fits the address kind: VPN address → VPN advice, home address
   → same Wi-Fi and firewall, public address → port forwarding (D103, tc K08,
   K09).
7. **carry** Leaving lands back on the Co-op screen with the reason ("You left the
   session." or that the host closed it) (D69, tc S11).
8. **carry** The co-op screens remember the player's name, the last address and the
   cartridge pick (D69).
9. **adapt** Phone layout: one column, cartridges scroll sideways, the main button
   pinned at the bottom, sheets rise from the bottom, the address field opens a
   number keypad (D103, tc K11).
10. **adapt** A split-screen entry (both seats on one device) has no source
    equivalent; it needs its own start path in this flow (G2, G3; #11).
    Here: ENTER WITH 2 PLAYERS on the hosting screen and JOIN WITH 2
    PLAYERS on the connection check, shown when CONTROLS has a device for
    each player ([split.md](split.md)).
11. **skip** Launcher themes surviving a theme switch (tc K12), the scripted
    launcher checks (D69's runner): Godot launcher and source tooling.

### A3. Campaign state, saves and persistence

1. **carry** Campaign state: campaign id and title, cartridge identity, shared event
   flags, badges, the unique-encounter registry (free / active with its battle
   id / done) and the set of applied commit ids. Player state: player id,
   in-game trainer id, team of at most six, PC in twelve boxes of twenty,
   current box, bag, money, map, cell, facing, return point, battle id,
   connection state (design table, arch §Ownership).
2. **carry** Stable ids: each Pokémon has a uid `<player id>:<serial>`, never reused
   and kept through deposits, trades and evolutions (brief, D23, D29, arch).
3. **carry** Exactly-once commits: every progression change goes through
   `commit(id, changes)` with stable ids (`victory:<encounter id>`,
   `gift:<item>`); a repeat returns false and changes nothing (D10, D30).
4. **carry** One versioned file per campaign with a campaign section and one section
   per player, never a merged single-player save; written to a temporary file,
   read back to verify, then renamed over the old one; the replaced file is kept
   beside it as `.bak`, but only if it still reads as a campaign; a failed write
   leaves the old file untouched (D12, D40, D44).
5. **carry** A campaign file that cannot be read, or is of a newer format, is refused
   for hosting and left as it is; the launcher names the backup (D37, D40, D66).
6. **carry** Format version in the file, migrations step by step (`if version < N`);
   an older build refuses a newer file without touching it (D66).
7. **carry** Checkpoints only at a safe point: no battle running and no join
   pending; a save request during a battle is refused with a reason (design
   §Saving, D12).
8. **carry** Journal between checkpoints: at the end of every host poll in which the
   campaign revision moved past the last checkpoint or line, append the whole
   state (campaign and every player, each PC left out while unchanged since the
   checkpoint) as one line to `<campaign>.journal`; each checkpoint deletes it.
   Reading takes the checkpoint, then the newest whole journal line of the same
   campaign with a higher revision; a torn last line is skipped; each line
   starts with a newline. A state, not a change list, because a story flag
   recovered without its item (a parcel, an HM, a prize, a catch) would strand
   the story. Measured: about 37 KB and 1.5 ms a line late-game (D66).
9. **carry** Host autosave: when its last running battle ends, at most every 30 s
   while something changed and no battle runs, on leaving or shutdown, and when
   a hosting app is paused (D28, D46, prog §Incomplete). A crash loses at most
   the battle in progress and player changes since the last story change.
10. **adapt** START > SAVE in a co-op world saves the whole campaign: it asks the
    host for a checkpoint. A save the host would refuse (any battle running)
    fails in the game's own save box ("battle in progress") and writes nothing,
    with no YES/NO left behind (D56, D70). Needs a gate hook in the target's
    save menu.
11. **carry** Only a real SAVE asks for a checkpoint (START > SAVE, a link room's,
    a box change's, the Hall of Fame's); a heal, purchase, gift or thrown ball
    does not (D80, D81).
12. **carry** Save feedback: the saver sees "Campaign saved.", the others
    "<NAME> saved the campaign."; the CO-OP menu shows how long ago it saved and
    that it also saves itself after battles and every thirty seconds of changes
    (D48, play §In the world). Nobody has to save before leaving.
13. **carry** Several campaigns per host device, each its own file under
    `coop_campaigns/<game>/`, id `<game>-<unix time>-<tag>`, with a title; a
    device is remembered per campaign (D49). Here: `coop/campaigns/<game>/<id>.campaign`
    beside the campaign's card, with #12's ids (`c` and 16 hex digits) (G20).
14. **adapt** A co-op world never writes the player's single-player saves: it plays
    on a scratch save area, restored on leaving; nothing is written back to a
    single-player save a player brought in (D29, D34). Split-screen needs one
    scratch area per seat. Here the scratch area is the campaign's save slot
    on the device (G10), filled from the host's file on entering (G20). The
    second seat plays in the campaign's second slot on the device (#11,
    [split.md](split.md)).
15. **skip** Moving the earlier build's single campaign file in as FIRST CAMPAIGN
    (D49) and settling format-1 files with the intro state (D58, D66): source
    migrations with no target history.
16. **skip** Run snapshots every 10 s and resume tooling (D96), campaign seeds from
    upstream's story walk (D78): source test tooling.

### A4. New players and the opening

In place (#22, [opening.md](opening.md), G27): the opening on a private
story, the names, the rival's starter, a new campaign's story, "in the
opening" and no save in it (A4.4 to A4.9). Split into #57 (owner,
2026-10-15): the start in Pallet Town and bringing a save (A4.1 to A4.3).

1. **adapt** Three ways to start: **play Oak's opening** (default); **start in Pallet
   Town** with a chosen starter at level 5 and 3000 money; **bring a trainer**
   from one of the device's single-player saves (team, PC with its boxes, bag,
   money, place and own world keys) (D34, D50, D61, play). Yellow: the "chosen
   starter" option and the opening differ (G4; #9).
2. **carry** A brought save is checked with the game's own validator (the world left
   out, since the campaign places the player) and keeps its trainer id, so the
   player's own Pokémon do not count as traded (D34, D37).
3. **carry** The first player of a new campaign who brings a save brings its story
   too (flags, badges, shared world keys), so an existing run can continue in
   co-op; a returning player is never replaced by a brought save (D34).
4. **adapt** A played opening runs on a **private story**: the campaign half of that
   window's world patches goes to the player's own copy, the state sent to the
   window carries it instead of the campaign's, and a battle it opens is neither
   a campaign encounter nor joinable. Nobody is drawn to that player and they
   see nobody for the whole opening (each has their own Oak, rival and balls,
   so both may take the same starter). It ends when the player **has a starter
   and has left the lab** (not at the rival fight, which can be walked past);
   then the copy is dropped and the window takes the campaign's story (D50,
   play §The opening). Yellow's opening differs (Pikachu, Oak's catch scene).
5. **carry** The player's name comes from the launcher, so Oak only asks for the
   rival's name, and only until somebody has named him (or the host named him
   when creating the campaign); the first to name him names him for everyone
   (D50, D61, D103).
6. **adapt** The first player to finish the opening sets the rival's starter for the
   campaign, if nobody set it before (D50). Yellow's rival always takes EEVEE
   and its later form depends on battle outcomes (G4; #9).
7. **adapt** A new campaign's shared story starts in the state a played opening
   leaves (for Red: the intro flags plus "Oak appeared in Pallet", the lab,
   Pallet Town and house script steps, and the town map, lab rival and two
   starter balls toggled), so skippers and opening players share one campaign
   and Oak is in the lab to take the parcel (D58, replaces D25). Re-capture for
   the target engine and per version, Yellow especially.
8. **carry** A player in the opening shows in the CO-OP menu as "in the opening",
   not at a place, and is announced when they join (D69).
9. **adapt** The opening plays in a co-op window without writing a save (arch:
   upstream intro screen hooks). Needs a target hook.

### A5. Shared world: ownership, rest points and per-place rules

In place (#14, [world.md](world.md), G21).

1. **adapt** Ownership table: every world, snapshot, save and runtime field has an
   owner. The campaign's: story/event flags, badges, map-script steps, toggled
   (hidden/shown) objects and other shared keys. The player's: bag, wallet,
   step counters, Pokédex, position and the rest. A key nobody classified goes
   to the player, so a new key never reaches a partner unclassified (D23, D63,
   design §Exploration). Must be redone over the target's world/save fields.
2. **carry** Windows and host exchange **patches, not copies**: a window sends the
   difference between what it last sent and its current state, and applies the
   difference between the last host state it saw and the new one; tables merge
   entry by entry, so two flags set at once both survive; a window opened late
   takes the campaign instead of pushing its blank state (D23).
3. **carry** A window keeps each patch it sent until the host reports that sequence
   applied, and leaves those entries out of what it applies, so an older host
   state never rewinds its own change (D51).
4. **adapt** **Rest-point rule** (owner, D72): share what the cartridge would save,
   never what it is doing. A rest point is a frame where the cartridge could
   save: nothing holds the player (no co-op menu, script, map load, forced walk
   or scripted NPC, battle of its own or on the host, whole-screen overlay, or
   locked screen such as a fade or a trainer's approach); it counts after three
   such frames in a row. A scene is the stretch between two rest points
   (D72, D79). The target needs equivalents for each "busy" signal; in
   split-screen each view rests on its own (here each seat's game has its
   own session and window, #11). Here (G21) a step the player
   walks of their own does not hold them, since START opens at the next
   cell; a reload or refresh waits for a frame between two cells.
5. **carry** Away from a rest point a window sends and takes nothing, world or
   party. Exceptions: a battle the world asks for sends the party first, and
   START > SAVE sends the scene so far. A scene's world patch and the party
   leave in the same frame. LEAVE, a closed window or a lost link send nothing:
   the host keeps the last resting state and the scene replays from its start
   (D72, D79; the 15 s cap of D67 is gone). Accepted costs: the partner sees a
   scene's result, not the scene; a long scene arrives when it ends (D72).
6. **adapt** A partner's step for the map a window stands on waits until that window
   loads another map, unless its own unconfirmed patch touched it; a pulled
   object hide or show lands at once (else, e.g., a taken fossil or item ball
   bars the partner's way) (D79). Here (G21) the engine saves no script
   steps, so a partner's entry lands at once; an object on the standing map
   rebuilds its people in place, and a flag the map is stamped from owes a
   reload (A5.7).
7. **carry** A pulled flag can owe the window a map reload: Vermilion Gym's second
   lock (Surge's door), Cinnabar Gym's quiz gates, Victory Road's switches, the
   League rooms' exits (D75, D86, D89, D93).
8. **carry** Not shared: NPC wandering and object positions a script moves (until the
   map loads again); a scene's animation, boxes, menus, music and sounds in the
   partner's window; wild encounters, trainer sight and map-load rolls (each
   window rolls its own); party and PC changes mid-scene (design §Exploration).
9. **adapt** Map-script bytes are the campaign's except where the resting value
   follows one player's walk, which are that player's: Cerulean City,
   Vermilion City, all eight gyms (so a bystander never replays a leader's
   lines or gift), Mt. Moon B2F, Museum 1F, the Safari Zone gate, the
   Champion's room, Seafoam B3F and B4F, the four Elite Four rooms and the Hall
   of Fame. Bill's house stays the campaign's (the partner sees Bill come out)
   (D74, D79, D87, D93). Yellow's script bytes and offsets differ (pokeyellow).
   Here (G21) the engine keeps no script bytes: a visit's state lives on the
   live overworld and is never saved, so these places share only their
   flags, and the flags that follow one player's walk are each player's.
10. **carry** Other Gen 1 script bytes: Vermilion Gym's trash-can lock bytes are the
    campaign's (both search the same cans); the slot machine's luck, the SURF
    high score and other scratch bytes are each player's; unknown names go to
    the player (D63). (Yellow's surfing-Pikachu score: per player, by the same
    rule; **uncertain**, not in source.)
11. **carry** Vermilion's first lock stays while any other connected player is in
    Vermilion City or its gym: an entering window takes the synced locks
    instead of rolling; with nobody there the next entry rolls as on the
    cartridge; a wrong second can still re-hides for everyone. Costs accepted:
    a player stepping out keeps the lock; two arriving at once may both roll; a
    dropped partner does not count (D77).
12. **carry** Per-player event flags: Safari Game over and in-Safari-Zone (each
    player's own 30 balls and 500 steps; leaving ends only the leaver's game)
    (D81); Pokémon Tower's purified zone (D82); the Pokémon Mansion switch
    (D86); the fossil lab's gave-fossil flag and the two after it (D86); in the
    Seafoam Islands (D94); the Elite Four walk-ins and Lance's door lock (D93);
    gift-Pokémon flags (A7.9) (D62).
13. **carry** Walk flags the cartridge clears itself (the two Safari flags, Seafoam)
    are dropped when the host opens a campaign (D94).
14. **carry** **Team rule** (owner, D91): a story gate, unlock or progress flag one
    player clears is cleared for both; Pokémon and items stay each player's.
    So Saffron's gate drink is the campaign's (one FRESH WATER lets both
    through all gates; a partner standing in a gate walks on at once) (D91,
    D92).
15. **carry** Engine/status flags: badges and the gate drink are the campaign's;
    the rest (STRENGTH active, the surf check, LAPRAS received) are each
    player's (D85, D92).
16. **carry** Cinnabar Gym's quiz gates are the campaign's: either player's right
    answer opens the gate in both windows (D86).
17. **carry** Victory Road's switches are the campaign's (the wall opens in a
    partner's window on that floor); boulder positions are each window's; the
    cartridge's switch resets stay the campaign's, but a window still on a
    Victory Road floor keeps its switches open until it leaves (D89).
18. **carry** Seafoam's boulder hides/shows are the campaign's; a player leaving by
    Route 20 with the puzzle unfinished resets it for a partner inside, as the
    cartridge does for one player (accepted, D94).
19. **adapt** A window opens its world as a Continue would: the player's map, cell
    and facing, the host's world with the player's keys over it, and the last
    outside map and last blackout map, which each step reports and the host
    keeps with the player (D73). A window reopened on water starts surfing
    (D86). Map these to the target's save/continue fields.
20. **carry** Known accepted gaps: a card-key door a partner opened stays drawn shut
    on the floor a window stands on until it reloads (D85); a partner's Game
    Corner poster switch opens the stairs only when the window reads it or
    enters again (D83); the partner is drawn in full colour in Rock Tunnel's
    dark (tc W36).
21. **skip** Generation 1 engine fixes found on the way (a wild battle's reload
    runs the map's load callback, D90; scripted walks hold the player, D54; a
    press faces its direction, D57; no-press boxes close at a row's end, D76;
    link rooms close their wait box, D71): upstream Godot bugs; the target
    should be checked for the same cartridge behaviour on its own, not as
    co-op work.

### A6. Items, bag, money and story gifts

In place (#16, [items.md](items.md), G22).

1. **carry** Bag and money are each player's; Pokémon Centers, Marts and Bill's PC
   work on that player's own team, bag, money and PC in their own world (design
   table, tc W07).
2. **carry** **Story items reach every player in the same number:** an item a
   player gains in the same world change that moves the shared story (a flag
   set, an object taken: item balls, a person's present, a reward) is given to
   every other player too (owner, D52).
3. **carry** A key item the story takes (OAK's PARCEL delivered, the BIKE VOUCHER,
   the GOLD TEETH) is taken from every player; fossils excepted, each player
   revives their own (D30, D52).
4. **carry** Bought, traded-for, used and hidden items stay with whoever got them;
   hidden items are each player's own flags (D52).
5. **adapt** A late joiner is handed every gift committed before from the shared
   list: key items and HMs (TOWN MAP, BICYCLE, keys, S.S. TICKET, COIN CASE,
   ITEMFINDER, SILPH SCOPE, POKé FLUTE, EXP.ALL, rods, HM01 to HM05) and gift
   TMs (an `EVENT_GOT_TMxx` flag); each is a commit `gift:<item>` (D30, design
   §Policies). Check the list against Yellow. Here (G22) a gift TM is one
   gained with its `EVENT_GOT_TMxx` flag in the same change; Yellow names
   the list's items alike.
6. **carry** A full bag sends a shared gift to the PC's items (D30).
7. **carry** Gift race: a window change that sets story flags or objects the campaign
   already has (it lost the race) has its item gains taken back, the first
   window's share standing in; a change that also spent money is left alone
   (a purchase may be in it). Not caught: a race that also moves new story, or
   one that gives coins (D62, prog §Incomplete). Rejected: a host lock, since
   every NPC script would wait for a round trip.
8. **adapt** A co-op bag holds 40 rows (each shared key item and HM takes a row in
   every bag); a solo game keeps 20; raised when the session's world opens and
   put back when it closes; the host's spill to the PC uses the same 40; the PC
   keeps its 50; a co-op bag is never exported to a cartridge save (owner,
   D109). The target already has a mod `bagSize` override for Gen 1's single
   bag; reuse it. Here (G22) the bag is raised while the session's game
   runs; every gift lands in a window, so the spill uses the window's 40;
   a campaign's slot has no EXPORT.

### A7. Pokémon, party, PC, Pokédex and captures

In place (#17, [campaign.md](campaign.md), [battles.md](battles.md), G25),
with these adaptations: A7.2 keeps no holdings revision, since the window
is the only writer of its player's holdings; A7.3's hint is the row's
place; A7.6's room follows this engine's box overflow. A7.8 and A7.10 came
with #18.

1. **carry** Team of at most six and a PC of twelve boxes of twenty per player,
   stored as `{uid, mon, box}`; a combined roster exists only inside a battle
   (brief, D6, D29).
2. **carry** Party and PC sync against a revision: the host sends a player's PC to
   its owner only when it changed; a window sends its party, and its PC when
   changed, with the `holdings_rev` it last took; the host refuses a copy from
   before its own latest change (a catch, battle results) and the window takes
   the host's; a current copy is believed whole, so a Pokémon missing from it
   was released or traded (D29).
3. **carry** Rows are matched to uids by fingerprint (original trainer, DVs, catch
   data), preferring an unchanged row, then the window's hint, so two Pokémon
   sharing a fingerprint keep their uids; a Pokémon missing from a window's
   party is kept in the host's box, never lost (D23, D29, design §Exploration).
4. **carry** The party a window shows follows the host: battle results replace it;
   a heal, gift, deposit or withdrawal made in the window goes to the host
   (design §Exploration).
5. **carry** The box the player switched to at a PC is the one the host stores
   catches into (prog, tc W72).
6. **carry** Captures: the ball is rolled on the host with the cartridge's catch
   formula; the thrower names whom the catch is for (any participant; the list
   offers each ball once per participant); a held ball ends the battle and the
   Pokémon goes once to that player as its trainer: team if room, else box,
   and their Pokédex; a trainer's Pokémon cannot be caught; with no room
   anywhere the throw is refused and the ball kept, as the cartridge refuses it
   (design §Battles, D27, D37).
7. **carry** Pokédex is each player's; at a shared battle's end every species that
   appeared is marked seen for every participant (a late joiner is credited
   with the whole battle) (D47).
8. **carry** After a shared battle each player's own world runs evolution for their
   own Pokémon that grew (design §Battles, D27).
9. **adapt** Gift Pokémon are one per player: EEVEE, LAPRAS, the Dojo's HITMONLEE
   or HITMONCHAN, the MAGIKARP for sale and each revived fossil; their flags
   and balls are each player's (owner, D61, D62, D85). A gift with six in the
   party goes to that player's box (tc W68). Yellow's gift list differs
   (G4; #9).
10. **carry** A partner's own Pokémon is not a traded Pokémon (no boosted EXP); one
    with a foreign original trainer still is: the engine reads each Pokémon's
    owner trainer id, single-player unchanged (D9, design §Battles).

### A8. Co-op battles against the game: rules

In place (#18, [battles.md](battles.md), G24): every rule below but their
menu side, which is #19's presentation (making and showing suggestions,
A9.3 and A9.4; A8.11's marks in the move list). The catch's name list
(A7.6) came with #17.

1. **carry** A player starts a battle alone; the other may explore or start a
   separate battle; no player or Pokémon is in two battles at once (brief,
   design §Battles).
2. **adapt** Every wild or trainer battle a window's own world opens (tall grass,
   trainer sight, scripted fights, statics) is fought on the host as a joinable
   co-op battle: the world keeps its trigger, script branches, party commit and
   whiteout; the world's own prize is zeroed (the host pays) and the host
   charges no blackout (the world whites out its player) (D24, design
   §Exploration). Needs a battle-takeover hook in the target's world and a
   scene-free battle engine instance per session (the target's battle code is
   single-player); upstream's lockstep link battle is an alternative engine
   path to weigh.
3. **carry** Join from any map through the CO-OP menu: the joiner's exploration is
   suspended and the return point kept; the initiator stays at the encounter
   (brief, design §Battles).
4. **carry** Joins apply at a safe boundary, when the battle waits for an action; a
   request during a forced replacement, a move-learn question or a MIMIC choice
   waits; one made at a boundary applies at once and advances the revision, so
   a command in flight for the old revision is refused and re-sent (D8).
5. **carry** Allied roster: the joiner's Pokémon are appended behind the existing
   roster (indices handed out stay valid), up to twelve; a team that does not
   fit joins with its first Pokémon that fit, in party order, the rest sit out
   untouched; no room → refused (`roster_full`) (D6, D55).
6. **carry** The controller is derived, never stored: the owner of the Pokémon that is
   out; switching to the partner's Pokémon hands them control; a question about
   a Pokémon (replacement after a faint, a move to learn, MIMIC) goes to its
   owner; a replacement may be any standing allied Pokémon (D7, design).
7. **carry** Every accepted decision advances a per-battle revision; commands carry
   it; a stale or repeated one is refused and changes nothing (D7).
8. **carry** Suggestions: a separate message type, stored outside the engine; the
   non-controller may suggest a move, switch, item, run or send-out; shown to
   all participants, never executed, never uses up a turn, cleared when the
   revision advances; the controller cannot suggest to themselves (D7, design).
9. **carry** Three or more players: every partner's suggestion is marked, queued joins
   share the roster's room (D55).
10. **carry** Locked-in turns (DIG, FLY, SOLARBEAM, HYPER BEAM's recharge, THRASH,
    RAGE) are taken by the host with the last chosen move, no second command
    (prog #118-#120).
11. **carry** A DISABLEd move or one with no PP is marked in the move list and refused
    with a worded reason (D83).
12. **carry** While a co-op battle or the CO-OP menu is open, the player's own world
    stands still (design §Battles); its sound keeps playing (D38).
13. **carry** Items come from the acting player's bag; key items are not consumed;
    the bag offers its battle-usable items, used on the Pokémon that is out
    (design, D98).
14. **carry** Experience goes only to Pokémon that took part, as the cartridge
    decides, written to the owner's record by uid (design §Battles).
15. **carry** EXP.ALL (owner, D61): one in any participant's bag counts for every
    team; each team gets the solo split over its own party (the fighters' block
    halved, the other half shared over that player's own team, never over the
    joint roster) (D61, D62).
16. **carry** Prize (owner, D61): every participant receives the full prize, Pay Day
    included.
17. **carry** Loss (owner, D61): every participant, a trimmed joiner included, whites
    out in their own world (party healed, half their own money, back to the
    last spawn). A side that wins blacks out nobody, even an initiator whose own
    team fell (D27, D55, D61, D88).
18. **carry** SET battle style in shared battles: the SHIFT "switch?" offer has no
    natural owner, so it is never asked (D14, #28).
19. **carry** Battles that stay in the window and cannot be joined: the Safari Zone,
    and a GHOST in Pokémon Tower without the SILPH SCOPE (only run works);
    MAROWAK unveiled with the scope is a normal joinable host battle (D68).
20. **adapt** Enemy moves use the cartridge's Gen 1 trainer AI; each battle has its
    own seeded random generator (arch, design §Policies). Re-think against
    upstream's shared-seed lockstep link battles and Yellow's AI.
21. **carry** A finished battle is removed from the host, so results and prizes
    cannot be applied twice (D10).
22. **carry** While the link is down, a battle the world starts is fought in the
    world itself, as solo (D46).
23. **skip** Encounters registered by a host tool for the session menu (D15, design
    §Exploration "the session menu still offers the host's own encounters"):
    synthetic test content of the source.

### A9. Co-op battles: presentation and menus

In place (#19, [battles.md](battles.md)): every rule below but A9.5's
question to leave the battle (#20) and the bag's battle-only list (the
cartridge's bag stays, refusing the rest; accepted by the owner,
2026-10-15).

1. **adapt** A co-op battle uses the cartridge's own battle screen and menus: FIGHT /
   PKMN / ITEM / RUN, the move list with TYPE/PP, a party list six rows at a
   time over every player's Pokémon (the text box names the owner of the row
   under the cursor), the Gen 1 bag list (battle items only), YES/NO boxes, and
   a name list for whom a ball catches for (owner, D98, replaces D22/D32/D45's
   panels). In the target, feed the existing battle UI from host events; in
   split-screen each view draws its own player's menus (each seat's game is
   a world of its own, #11, so a battle of one seat shows only in its half).
2. **carry** The menu says who decides ("<NAME> decides") (D98, play §Battles).
3. **carry** A partner's suggestion is a hollow ▷ at every menu level (on the main
   menu entry and on the exact row), a partner's initial with three or more
   players, and the idle controller's text box alternates with the menu as
   "<NAME> suggests / <choice>" (D98).
4. **carry** The non-controller walks the same menus: resting the cursor on a row
   suggests it; A sends it again rather than acting (D98).
5. **carry** RUN flees for the player whose world started the fight and asks everyone
   else whether to leave the battle (their team stays); TAKE OVER and REJOIN are
   YES/NO questions (D98).
6. **carry** A finished battle closes by itself after its last line; no press needed
   (#98, D98).
7. **carry** An open list is re-asked only on a turn that carries events or when the
   phase, controller, pause or the session's own rows change, so a partner's
   lock-in does not reset the other's open menu (prog #120).
8. **adapt** The battle is drawn from the host's views by replaying each turn's
   events in order, as the cartridge would: lines, move animations and sounds,
   HP bars draining in the turn's order, faints, recalls and send-outs, the
   ball toss and wobbles, cries and battle music by trainer class; a battle
   seen from its start opens with the sliding intro (a mid-battle joiner sees
   none); a choice waits until the last turn has played out; a trainer win
   closes with the defeat line, the trainer sliding back, their own line and
   each window's own player name and prize (D32, D39, D41, D42, D43, D44).
   The target has its own renderer; only the "replay host events through it"
   approach carries (source #26 is the unfinished version of this).
9. **carry** Music: a wild win's fanfare starts when the Pokémon falls, a trainer's
   after the experience; the map's music returns only after the battle closes
   (prog D105 entry).
10. **carry** Party balls: under the trainer's intro both rows (only the player's for a
    wild battle); the trainer's row comes back after a faint until the next
    Pokémon comes out; the player's row shows the viewer's own Pokémon, not the
    whole twelve-member roster (D108).
11. **carry** Co-op events have their own lines: a join ("<NAME> joined the
    battle!"), an item used, a throw with the catch or near-miss line (D32).
12. **adapt** Source trade-offs to revisit: suggestion marks are monochrome rather than
    in player colours, and nicknames are not shown (the view carried species
    only) (D98).
13. **skip** Godot-specific fixes: the audio player's process mode under a held world
    (D38), the Generation 1 tilemap kept for animations (D39), the back-picture
    head layout (D42/L8), borrowing the battle screen's private `_describe`
    (D43), the menu-white cover under a battle (prog D106), DIG's slide-up
    picture (prog #119).

### A10. Unique encounters, trainers, rival scenes and the League

A10.1 to A10.4 and A10.8 are in place (#21, [battles.md](battles.md), G26),
with these adaptations: an encounter is named by its map object, and the
League's rooms are never kept done until A10.6. A10.5 to A10.7 are #55
(owner, 2026-10-15).

1. **carry** A unique encounter (or any carrying victory flags) has at most one active
   instance; beating it marks it done for everybody; losing or fleeing releases
   it (D10, design §Story).
2. **carry** A trainer is the encounter `trainer:<class>:<index>`: a second window
   walking into it joins the running fight; once beaten it answers as beaten
   without a fight ("counts as won") (D24).
3. **adapt** One-off wild Pokémon (Red/Blue: SNORLAX, the three birds, MEWTWO; none
   met in grass) are `static:<species>:<map>`: a second window joins the
   running fight; beaten or caught, done for the campaign; lost or fled, it
   stays; a catch is reported to the world as a win so the world removes it
   (D36). List per version, Yellow included.
4. **carry** Trainer sight gate: a trainer the host names as in a battle or beaten
   for the campaign spots nobody else; a lost or fled fight releases it;
   talking to it, or JOIN, still joins. Left open: a partner spotted during the
   first player's walk-up, before the host knows of the fight, still joins
   (D107, replaces the earlier "spotted partner joins", L1/#60).
5. **adapt** Rival scenes after the opening (Route 22 both fights, Cerulean/Nugget
   Bridge, S.S. Anne 2F, Pokémon Tower 2F, Silph Co. 7F): the first window whose
   map-script byte enters the scene's states claims it on the host; one driver
   per map, a second claim is refused; released at the driver's first rest point
   after the byte left those states (its result patch first), or when the driver
   drops, leaves or changes map. A partner on that map waits from its next rest
   point, frozen under "<name> is facing the rival here. Wait, or join the
   battle…"; JOIN fights the rival together; the frozen world counts as
   resting, so the result is pulled; at the end the scene's step lands at once.
   Two windows starting at once both play it; the first claim drives and the
   loser's battle joins as one unique encounter. A dropped driver lets the
   partner go and meets the rival again from the start. The Champion's room has
   no lock (D72, D84). Yellow adds Jessie and James scenes and changes rival
   maps: re-list (G4; #9).
6. **carry** The Elite Four is one run for the team (owner, D91): each member's and
   the Champion's beaten flag is the campaign's; a window in that room reloads
   so the exit opens; a partner arriving later walks through. The walk-ins,
   Lance's door lock and the rooms' and Hall of Fame's script bytes are each
   player's. AGATHA's win readies each reached window's Champion room; a late
   player meets the Champion and the host ends the fight at once as won, then
   gets Oak's scene, their own Hall of Fame, credits and Continue. The run's
   clear (lobby after a whiteout, Hall of Fame) is held while any connected
   player is in the League and, after the Champion fell, until every connected
   player is inducted; applied, it erases the run and forgets the League's
   encounters and victory commits, so the next run fights everyone again (D93,
   replaces D87). Costs: the hold lives in host memory; a disconnected player
   inside holds nothing.
7. **adapt** The Hall of Fame's save-and-reset continues the co-op world: the session
   freezes the world, waits until the host applied what was sent, and reopens it
   as a Continue; a player left in the Hall of Fame flies to Pallet Town (the
   cartridge's own rule); finished battles are dropped; a reset in a co-op
   window always continues this way (D88). Needs a target restart hook.
8. **carry** The Hall of Fame's hiding of the Cerulean Cave guard stays the campaign's
   (D87, D93).

### A11. Leaving, reconnecting, taking over and shutting down

In place (#20, [battles.md](battles.md), [session.md](session.md)): every
rule below but the per-player reconnection secrets of A11.10 (a player is
recognised by their remembered id and name, as since #10). A11.13 is met by
the transport's own flush on close (ENet delivers the bye or `ended` for up
to 0.5 s before the socket goes), not by deferring `love.quit`. The owner
accepted both as built (2026-10-15).

1. **carry** Leaving and dropping are one rule (owner, D61): a participant who uses
   LEAVE BATTLE or loses the link is absent: back at their return point; their
   Pokémon stay in the roster and fight on under whoever is present; results,
   experience and prize stay theirs; they may rejoin. A battle ends for
   everyone only when nobody is left (D61, D62).
2. **carry** Only a participant whose own world did not open the fight may leave: the
   initiator, and a second window that walked into the same trainer, stay
   (their world waits on the outcome) (D62).
3. **carry** A player who left keeps the battle's id: they may walk but start or join
   nothing; a fight their world opens waits until that battle ends, showing the
   old battle with REJOIN; when it ends they get one line saying how it went,
   and their evolutions and whiteout still follow (D62).
4. **carry** REJOIN (CO-OP menu, also SELECT) takes them back in at once; a queued
   join can be called off the same way (D62, design §Battles).
5. **carry** If the deciding owner has left, the first present participant decides at
   once; if they dropped, the battle pauses; everything else (exploration,
   other battles) continues; a dropped non-controller does not pause it
   (design §Sessions, D62).
6. **carry** After 30 s without a dropped controller, the present participants are
   asked TAKE OVER or KEEP WAITING (YES/NO); nobody decides for another player's
   Pokémon without choosing to; a stand-in's results stay the owner's; the view
   names both; the owner takes back control on returning; the host announces
   the change itself (D33, D61, D62).
7. **carry** A battle nobody is left in waits as long as a window redials (about two
   minutes), then ends as fled; battles still running at shutdown end as fled
   (D37, D61).
8. **carry** A join still queued when its battle ends is released; a participant away
   when their battle ended gets the final view when back (D37).
9. **carry** Reconnect: a dropped client redials as the same player every 2 s for
   about two minutes, showing "Lost the host: reconnecting..." and then "Back in
   the session."; the budget resets on each welcome; the world link and the
   remote actor send nothing until the host has the player back; the first
   position after a reconnect counts as a warp (D28, D37, D46).
10. **adapt** Mobile: a joining app back from a pause longer than 3 s closes its link
    and dials at once; a hosting app sent to the background saves the campaign
    first (D46). Map to LÖVE's focus/visibility callbacks on Android and iOS;
    per-player reconnection secrets are still open (#20).
11. **carry** Shutdown: the host sends `ended` with a reason, ignores further messages,
    and closes when every client has left or after a 2 s grace; a client closes
    on `ended`; a joiner shows why over the world for 3 s, then returns to the
    launcher (D18, D28).
12. **carry** One way out: LEAVE SESSION (asked YES/NO), the end notice and closing the
    window all take the same leave path; a hosting device writes the campaign
    and tells every client (D28, D99).
13. **adapt** Closing the app during a session first says goodbye (the host's `ended`
    and last log lines, a joiner's last log batch), then quits at most 2.5 s
    (host) or 0.6 s (joiner) later (D60). In LÖVE: defer `love.quit`.
    Split-screen: closing ends both seats, the second seat's goodbye first
    (#11).
14. **carry** Host migration stays out of scope (brief, design §Sessions).

### A12. Friend battles and trades

1. **carry** Talking to the partner opens BATTLE / TRADE / CANCEL; the CO-OP menu also
   lists BATTLE and TRADE with each free partner's name (D100).
2. **carry** An invitation needs the recipient's YES, shown only at a rest point, back
   on the map and out of every menu, Mart, PC and TOWN MAP; NO, B or 30 s
   unanswered declines; the host expires a pending invitation after 60 s and
   rechecks both players on acceptance; a busy or offline partner cannot be
   invited (D100, prog D106 entry, tc B24, B30).
3. **adapt** Friend battle: both players choose their own moves, switches and
   replacements; each sees their own team as allies in a mirrored view; both
   choices may carry the same round revision; learning answers have their own
   minimum revision per side; forced turns continue on the host; RUN forfeits;
   items are unavailable; the battle is private to its two players (D100,
   arch). Upstream's lockstep link battle (shared seed) may be the better
   engine here; decide in the issue.
4. **carry** A dropped opponent pauses human choices for the two-minute reconnection
   grace; the other player cannot stand in; when it expires the fight is
   released and both are healed (D100, tc B26).
5. **carry** Afterwards both teams recover HP, PP and status where they stood; no
   money, story reward or whiteout; each Pokémon gets the full trainer EXP and
   stat EXP for every distinct opposing Pokémon it faced, won or lost, not
   split among teammates; traded boosts, levels, learning and evolution as the
   engine does (D100, design).
6. **adapt** Direct trade: after acceptance both see the normal trade screen where they
   stand; the host swaps the two Pokémon exactly once, keeping uids and
   applying trade evolutions; CANCEL (below the party) returns both in place;
   a disconnect ends the pairing (D100, D31). Upstream has its own link trade
   screen; reuse it with a host-side swap.
7. **adapt** Cable Club trades: the partner is an offer either side made; else the
   player's mate in the Trade Center or Colosseum (paired in id order, kept
   while both stay); else someone waiting alone in a room; else the first other
   free player; a third player in a room of two gets no cable. The host swaps
   once and saves; each window plays the movie and evolution on its own copy
   while its party sync is held, then takes the host's swap. Partners are
   hidden in the Cable Club rooms (the game's own friend sprite is the
   partner). No offer within 30 s or no answer within 60 s returns the screen
   to its lists (D31, D55). Upstream's Union Room option moves the Gen 1 Cable
   Club desk (G6).
8. **adapt** A world continued inside a Cable Club room (whose only exit on the
   cartridge is a reset) opens at the receptionist: the host keeps the cell the
   room was entered from and the map the center's door leads to (prog §0.1.75
   "Stuck in the Trade Center", tc T05, T06). Upstream already relocates saves
   made in added rooms; align with it.
9. **adapt** Colosseum: not a co-op battle; the window runs the cartridge's own link
   battle against a copy of the partner's team (design §Policies). Never tried
   in the source **(uncertain)**.
10. **skip** The trade movie built before the evolution (D64): a fix to upstream
    Godot code; check the target's trade movie on its own.

### A13. Red + Blue mixing (and where Yellow fits)

In place (#9, [versions.md](versions.md), G33): Red and Blue (and Rot and
Blau) in one campaign, the refusals named, a Blue cartridge hosting a Red
campaign, and "wild Pokémon from both versions" (A13.1 to A13.4). A save
brought from the partner's game comes with bringing a save (#57). Yellow
stays with Yellow (G4); the answer on mixing it is at the end of this
section.

1. **adapt** Red and Blue play one campaign (owner, D101): the host also lets in the
   other game of the same pair when both are verified dumps; another revision,
   a hack, Yellow or another language is refused ("Red or Blue of the same
   language"); the campaign stays the host's game; a save brought from the
   partner game is kept; each world draws its wild tables, Game Corner prizes
   and title from its own cartridge; exclusives cross by trade (D101, tc G06).
   Yellow plays with Yellow first (G4).
2. **carry** The host screen lists the campaigns of both games of the pair, labelled
   by game; a Blue cartridge hosts a Red campaign, whose file stays in Red's
   folder (prog D103 follow-up, tc K15).
3. **carry** **Wild Pokémon from both versions** (owner, D104): a per-campaign switch,
   off by default, also in Edit campaign. On: each grass or water wild, on the
   upper half of a 0 to 255 roll from the world's own encounter generator,
   becomes the other version's Pokémon from the same map and slot (its level
   and rarity stay), but only where that Pokémon is one the player's own
   version never has in the wild; shared slots, slots that only shuffle shared
   Pokémon, and maps the other version has no table for keep the cartridge's
   odds. So only the other version's ten wild exclusives appear, each taking
   half its slot. Fishing, Game Corner prizes and in-game trades stay each
   player's own version. Rejected: lookup by species and level (two slots can
   share both).
4. **carry** No cartridge data is shipped or cached: each window of a paired game
   sends its own wild slots after every welcome (about 10 KB in the source,
   about 20 KB of JSON here; session only),
   the host passes the other version's to the other game's players; until a
   device of each version has been in, the Hosting screen says which version it
   waits for and every world keeps its own; the roll is drawn only while a
   window holds the other tables, so a campaign without the switch keeps the
   cartridge's encounter stream (D104). Here the extra number is drawn only
   where the slot offers the other version's exclusive (G33).

**Yellow with Red or Blue (#9, G4).** Compared by the fork's own extraction
of the US dumps and the engine's Yellow branches (`GameVersion.isYellow()`),
Yellow is not a third cartridge of the same game:

- **Species.** 38 species differ in their data: learnsets (225 entries),
  level-1 moves, TM and HM sets, two catch rates, front sprite sizes. Moves,
  items and the type chart are the same. A co-op battle is one record every
  window plays with its own cartridge's data (G24), so a Red and a Yellow
  window would part at the first level-up move, evolution move or catch:
  a desync on every battle that reaches one.
- **Wild Pokémon and fishing.** Every wild table differs (59 maps), and so do
  the Super Rod's.
- **Trainers.** Twenty trainer classes have other teams: the rival's three
  (EEVEE, its evolution chosen by his first battles, `Commands.rival_battle`
  and `save.rivalStarter`), the gym leaders, Giovanni and the Rockets, with
  Jessie and James as `OPP_ROCKET` with their own picture; eight maps have
  other trainer headers.
- **The story.** Pallet's opening (Oak catches PIKACHU, the rival takes
  EEVEE), the gift starters (BULBASAUR in Cerulean, CHARMANDER on Route 24,
  SQUIRTLE in Vermilion), Jessie and James' scenes: map objects differ on 42
  maps and 516 texts differ. The campaign's story is a set of the
  cartridge's flags and toggles (G21); the same flag stands for another
  scene in the other cartridge, or for none.
- **The Pikachu.** The follower, its mood and happiness on every step
  (`PikachuFollower.onStep`), its scenes (Bill's house), its send-out
  without a ball and its refusal of the THUNDERSTONE are Yellow's alone;
  the surfing PIKACHU, the cries, the GBC colours and Yellow's intro,
  title, Pokédex, box and option screens are too.
- **Trades.** Yellow's in-game trades differ (27 entries).

Proposal: keep mixing Yellow with Red or Blue unsupported, as now. A Yellow
host lets in Yellow only and a Red or Blue host refuses Yellow, naming it
("YELLOW plays with YELLOW only."). Yellow with Yellow plays co-op with every
rule here. Mixing would need, before any story rule: battles between a
Yellow and a Red or Blue window refused (or run on one cartridge's species
data, which the no-shipping rule forbids), and a translation of the story
between the two cartridges' flags, map by map. Only then would the owner's
analogies (2026-10-13) apply: each player their own Pikachu follower, one
gift starter each, Jessie and James under the rival-scene lock (D84), and
the first player to finish the opening setting the rival's EEVEE line (D50).

### A14. Presence, finding the partner, the CO-OP menu and the run button

In place (#15, [presence.md](presence.md)), with what a session without
battles supports; the battle parts since #34 ([battles.md](battles.md)):
the "!" where a battle started, a joiner from elsewhere not drawn, JOIN and
REJOIN, IN A BATTLE, the battle notice, SELECT in a co-op battle. Left: who
is not drawn in the opening or the Cable Club, the BATTLE and TRADE rows
and "in the opening" (#22, #23); the last save is in since #13.

1. **adapt** Partners on the same map are drawn as solid actors: the player's own
   steps and NPC wandering stop at them; scripted and forced movement passes
   through (D19, D53). The target's Collision has passable entities (Yellow's
   Pikachu); check the interplay with a partner's Pikachu.
2. **carry** A partner on a map that connections reach (the next route or town) is
   drawn there too, eased and never solid; the arrow takes over once out of
   sight (prog D106 entry, tc W81; this outdates design.md's "same map only").
3. **adapt** Each player is drawn in one colour in every window, by their place in
   the session; a player in a battle wears the "!" emote where it started
   (design §Exploration). Colours must suit the target's Gen 1 palettes.
4. **carry** Not drawn: a player who left the map to join a battle elsewhere, a
   disconnected one, anyone in the opening (both ways), and partners in the
   Cable Club rooms (design, D50, D31).
5. **carry** A partner's steps are eased over the time between their reports: 8
   frames when they run or ride, 16 when they walk (D105).
6. **carry** **Partner arrow** (owner, D106): a partner off the screen is an 8x8 arrow
   in their colour, blinking, on the screen's edge (two pixels in), drawn over
   the map and under every box and menu, and only while the player walks about
   (no menu, script, battle or own screen up). It points through a
   breadth-first search of the maps from the player's: where connections alone
   reach the partner's map it points at them exactly; past a door or stairs it
   stands over (or points at) the last warp on a map that can be placed: on the
   player's map a door they can walk to, into the partner's map the door that
   lands nearest them; indoors, "last map" exits resolve to the player's own
   last map, only until the search has left the building; where nothing joins
   the two (flown, across the sea) it takes the TOWN MAP's direction. Cached per
   map pair and last map; an arrow over a door in the top row stays on screen.
   Rejected: a minimap, arrows through menus (D106, prog).
7. **carry** The TOWN MAP item, and a TOWN MAP row in the CO-OP menu for players
   without it, show each partner's icon in their colour, under the player's own,
   on the map and the fly map, not the Pokédex's area view (D106).
8. **adapt** **START > CO-OP**: a CO-OP row in the cartridge's START menu (between
   OPTION and EXIT, only in a co-op world), drawn with the cartridge's font,
   boxes and cursor: fight offers, JOIN <partner> / VS <foe>, REJOIN, BATTLE and
   TRADE <partner>, TOWN MAP, LEAVE SESSION (asked YES/NO), CANCEL; above them a
   box with the campaign's name, each partner and where they are (the town
   map's area name, "in a battle", "in the opening"), the last save, and on the
   host its address (`IP …`) (owner, D99, D45, D100, D103, D106, tc S20-S22,
   K14). Needs a START-menu hook in the target; Yellow's START menu too.
9. **carry** SELECT on the map also opens the CO-OP menu, except where the world reads
   SELECT itself (the START menu, the bag's swap, a world battle, the party); in a
   co-op battle nothing opens (D99, tc S23).
10. **carry** Notices over the world on a dark backdrop: a partner joins or leaves the
    session, or starts a battle this player is free to join ("<NAME> is in a
    battle against wild X. START > CO-OP to join."); refusals as plain sentences
    that fade after a few seconds (D45, D99, play).
11. **adapt** **Hold B to run** (owner, D105): walking with B held moves at the bike's
    pace; the bike and surfing keep their own; only in a co-op session, so a
    solo game walks as the cartridge does; no setting. Check whether upstream
    gen1recomp already has a run option to reuse.

### A15. Mobile, touch, input and language

1. **adapt** On a phone the on-screen pad stays usable below a co-op battle and the
   CO-OP menu (a held world keeps its touch controls); a portrait window puts
   the battle at the top with the pad visible below (prog #98, tc P03, P06).
   Map to the target's TouchControls.
2. **carry** While the CO-OP menu or a co-op battle is open, a swipe over the game
   screen is one d-pad press per 16 hardware pixels of travel and a tap is A,
   fed as ordinary presses; pad touches and two-finger touches are left alone;
   walking on the map is untouched (D99, tc P02, P07).
3. **adapt** Menus are drawn at the game screen's scale with no extra size setting
   (D99). Re-think for split-screen halves on a phone.
4. **adapt** Controller pick: one chosen pad plays (kept by GUID, name, serial and
   order among twins, found again after a replug, the others ignored);
   keyboard and mouse always work (prog "Controller pick", tc P08).
   Split-screen needs per-seat pad assignment instead (G3; #4, G17: a seat
   per local player with the device claimed on CONTROLS).
5. **adapt** iOS discovery may need the multicast entitlement; the address path works
   without it (D103).
6. **adapt** Languages are separate games: German plays only with German, English
   only with English; mixed sessions are refused; each language has its own game
   ids, so caches and saves stay apart (owner, D95). German Red and Blue import
   and play ([german.md](german.md), #25, G7, G12); the German wording of the
   engine's own lines is still open in #25.
7. **adapt** In a German world every engine and co-op line uses the cartridge's own
   words where the cartridge has the line; co-op-only lines are project wording
   kept in a list for the owner to check; layouts follow the German cartridge
   (wider YES/NO, battle and PC columns); each window speaks its own language
   (D102, german-wording.md, tc G10).

### A16. Source-specific items (all skip)

1. **skip** Staying on Godot pokerecomp; a private repository carrying upstream
   history; release automation off; upstream merges by tag; Godot pins (D1, D2,
   D3, D97, D110): the target is a public LÖVE fork with its own rules.
2. **skip** AI-authorship notice (D4): the target already has its own.
3. **skip** Co-op layer beside the engine with small upstream hooks (D5): already a
   target hard rule ("new modules and small hooks").
4. **skip** Comment ceiling (D13): a pokerecomp source-budget test.
5. **skip** German as a later issue (D17), Android deferred (D61, D72): source
   scheduling.
6. **skip** Godot mod actor seam, `coop_play.gd` tool windows, overlay/side panels
   (D19, D20, D22, D32's panel, D45's panel): engine or superseded UI.
7. **skip** Two-window scenario runner, autoplay, seeds, snapshots, resume (D65, D69,
   D78, D96), tests' own folders (prog D105 entry; already a target rule):
   source test tooling.
8. **skip** Upstream engine bug fixes (D54, D57, D64, D70, D71, D76, D90, L8, the DIG
   slide): pokerecomp bugs; re-check the target independently.

---

## 3. Superseded decisions (not carried as written)

- D11 (64 KiB packet cap) → D35 (2 MiB).
- D12 (crash loses everything since the checkpoint) → D66 (journal).
- D15 (encounters only from the host's menu) → D24 (the world's own battles go to the host).
- D16 (balls refused in shared battles) → D27 (rolled on the host for a named player).
- D20 (local wild encounters and trainer sight off; party copied at launch) → D24, D23, D29.
- D22 (text overlay panel) → D32 (field plus side panel) → D98 (cartridge menus on the game screen).
- D24 and D41 (host pays each participant a split/share of the prize) → D61 (full prize each).
- D25 (demo host marks five intro flags) → D50, D58 (played opening; the state it leaves).
- D26 (identity per host address) → D49 (per campaign), with D48 (found by name).
- D28 (ten redials, two seconds apart) → D46 (about two minutes).
- D30 (only a fixed list of key items, HMs and gift TMs shared) → D52 (every story item; the list stays for late joiners).
- D33 (stand-in imposed after 30 s) → D61, D62 (asked: TAKE OVER or KEEP WAITING).
- D36 ("gift Pokémon stay with whoever is given them first") → D61, D62 (one per player).
- D37 (a battle everyone left ends after the 30 s stand-in time) → D61 (about two minutes).
- D37 (a SAVE detected as a fresh world snapshot) → D80 (explicit "save written" signal).
- D45 (panel rows and taps; session menu on SELECT) → D98 (battle menus), D99 (START > CO-OP).
- D63's cost (a partner entering Vermilion re-rolls the first lock) → D77.
- D67 (hold a script's patches, 15 s cap) → D72, D79 (rest points, no cap).
- D79's note (per-walk flags such as the Safari ones stay the campaign's) → D81, D94.
- D85 (gate drink per player) → D91, D92 (the campaign's).
- D87 (each player's Elite Four run their own) → D91, D93 (one run for the team).
- L1 / #60 (a partner a trainer spots joins that trainer's fight) → D107 (sight gate).
- design.md "partners shown on the same map only" → the D106 follow-up in progress.md (also drawn on connected maps).

---

## 4. Open or planned in the source (gameplay features not done)

- #53 Local split-screen: two local players on one device sharing the host (core in the target).
- #52 Dedicated server mode: the host headless, without a local player.
- #51 Internet relay option for players who cannot reach each other directly.
- #20 Reconnection tokens: a per-player secret on first join, grace window for mobile suspend, resync after resume (partly done: redial by player id, D46).
- #45 Android client: pause/resume, network changes and reconnect (no build yet).
- #46 iOS client without executable mods.
- #43 Touch and pad input for every co-op menu (done in tests, not on a device).
- #28 Give the SHIFT switch offer (and, in Gen 2, Baton Pass) an owner; until then SET style is forced.
- #26 Drive the real battle screen from host events instead of the field's replay.
- #50 German Red/Blue (largely done; still open: about 400 English engine literals, some fixed-column menus).
- #27 Gen 2 enemy AI in sessions (Gen 2 only: out of the target's scope).
- Left open inside decisions: a partner spotted during the walk-up before the host knows of the fight (D107); Pokémon Tower 2F and Silph Co. 7F lock one box late (D84); gift races that also move new story or give coins (D62); the Colosseum never tried (T04); Elite Four hold lost on a host restart (D93).

---

## 5. Issues

Every carry and adapt rule belongs to one issue of this repository.

| Area | Issue |
|---|---|
| A1 Session and connection core | #10 (done: [session.md](session.md)); log sharing #31, flood limits #32 |
| A2 Launcher co-op flow | #12 ([launcher.md](launcher.md)); the rival's name #22, how to start #57, both versions #9, split-screen entry #11 |
| A3 Campaign state, saves and persistence | #13 ([campaign.md](campaign.md)) |
| A4 New players and the opening | #22 ([opening.md](opening.md)); the Pallet start and bringing a save #57 |
| A5 Shared world | #14 ([world.md](world.md)); story items and the gift race #16 ([items.md](items.md)), party at rest points #17 |
| A6 Items, bag, money and story gifts | #16 ([items.md](items.md)) |
| A7 Pokémon, party, PC, Pokédex and captures | #17 |
| A8 Co-op battles: rules | #18 ([battles.md](battles.md)) |
| A9 Co-op battles: presentation and menus | #19 |
| A10 Unique encounters, trainers, rival scenes, the League | #21 ([battles.md](battles.md)); rival scenes, the League run and the Hall of Fame #55 |
| A11 Leaving, reconnecting, taking over, shutting down | #20 |
| A12 Friend battles and trades | #23 |
| A13 Red + Blue mixing, Yellow | #9 ([versions.md](versions.md)) |
| A14 Presence, finding the partner, CO-OP menu, run button | #15 ([presence.md](presence.md)); the battle, opening, friend battle and campaign file parts #34 |
| A15 Mobile, touch, input and language | #7 (and #4 for pads); German: #25 |
| Local split-screen (the sibling's open #53) | #11 |

## 6. Decisions

Decisions of this fork, numbered G1, G2, … so they never clash with the
sibling's D-numbers.

- **G1. The fork has its own launcher** (licence term 2; owner, 2026-10-13).
  Gen 1 only (Red, Blue, Yellow) at first; Game Boy style; desktop and mobile;
  controls and pad assignment, settings and save management (#3 to #7).
  The shell is in place: [launcher.md](launcher.md).
- **G2. Split-screen battles: each half, own menus** (owner, 2026-10-13). When
  both local players are in one battle, each player's half shows it with their
  own cartridge menus, as each window does in the sibling fork.
- **G3. Split-screen and online players mix** (owner, 2026-10-13). Local players
  are loopback clients of the in-process host like any network player, so a
  split-screen pair can share a campaign with online partners.
- **G4. Yellow plays with Yellow first** (owner, 2026-10-13). Mixing Yellow
  with Red or Blue is investigated in #9, with the proposals in A13.
- **G5. Internet play is direct** (owner, 2026-10-13), as in the sibling fork:
  ENet by address (LAN, port forwarding or a VPN). Upstream's relay is an
  external service that only passes its own message types; no relay for co-op.
- **G6. Cable Club trades stay** next to direct friend trades (default
  proposed 2026-10-13, owner may change it). Upstream's Union Room setting
  moves the Gen 1 Cable Club desk; #23 handles both.
- **G7. German Red and Blue are in scope** (owner, 2026-10-13), as in the
  sibling fork (D95, D102): own game ids, German only with German, the
  cartridge's own words and layouts. Upstream accepts only the English dumps
  today, so import support comes first (#25).
- **G8. Co-op has its own ports** (#10, 2026-10-13): the game port is UDP
  24680 and the LAN beacon UDP 24681, as in the sibling fork, instead of
  upstream's link port 7777. A co-op host and upstream's own link (a Cable
  Club cable, for example) could otherwise not run in one process. The
  session core is in [session.md](session.md).
- **G9. The fork has its own save folder; upstream's updater and sync are
  off** (#26, owner, 2026-10-13). The LÖVE identity is `gen1recomp-coop`, not
  upstream's `pokemon-love2d`, so the two never share saves, options or ROM
  caches. Upstream saves come over by copying the folder by hand, as
  [launcher.md](launcher.md) describes; an import in the launcher may come
  with #6. The self-updater and cloud sync stay off until the fork wants its
  own (`src/coop/Upstream.lua`).
- **G10. Until campaign files, a campaign's progress is a save slot per
  device** (#12, owner, 2026-10-13). Each device plays a campaign in a save
  slot of its own, created and named after the campaign; entering the
  campaign makes it the active slot, and the launcher puts the solo slot
  back afterwards. The host's campaign card holds the title, the game it was
  started on, the players seen and the address a partner used last. Since
  #13 the slot is the scratch area the game plays in: the player's progress
  lives in the host's campaign file, and entering fills the slot from it
  (G20).
- **G11. Colours by place** (#15, owner, 2026-10-14). Each player wears the colour of their place in the
  session, the host's player first: red, blue, green, purple, orange, teal,
  pink, brown, then again. A colour is an OBJ palette (white, skin, the
  colour, a dark outline) that reads on every Gen 1 COLORS mode. This
  player wears theirs too, so a player has one colour in every window.
- **G12. German games are the US games with a language** (#25, owner,
  2026-10-14). `red_de` and `blue_de` carry `base` (the US game they play
  as) and `language` ("de") in `GameVersion`; their import manifests are
  derived from the US ones with every address re-sourced from a build of
  einstein95/pokered-de at its master (its `symbols` branch is from 2022 and
  uses old label names). Words the US manifests carry from pret's source
  (name presets, trade nicknames, credits) are read from the cartridge
  instead, so no German text is committed. Details: [german.md](german.md).
- **G13. The launcher's own look** (#38, 2026-10-14). The launcher leaves
  the 160 x 144 text grid for #38's design: tabs (PLAY, CAMPAIGNS, CONTROLS,
  SETTINGS, HELP), green LCD panels in a light and a dark set, the bundled
  Plain Pixel face and no cartridge graphics or fonts, the credit line under
  every page. It is drawn at whole multiples of the window's pixels with at
  least 480 x 400 launcher pixels and laid out for the size it gets (two
  columns from 460 wide, a scrolled page when it is taller); the game's
  renderer keeps 160 x 144. Couch co-op and per-player controls show as
  PLANNED and are not offered until #4 and #11 work. Details:
  [launcher.md](launcher.md).
- **G14. The launcher speaks English or German** (#41, 2026-10-14,
  accepted by the owner 2026-10-15: the system's locale first). Every launcher string goes through
  one catalog keyed by its English source; LANGUAGE in SETTINGS picks
  ENGLISH or DEUTSCH, and before a choice the system's locale does (German:
  Deutsch, else English). The setting is the launcher's alone: a game's text
  follows its cartridge (D95, D102). The German wording is listed in
  [german-wording.md](german-wording.md); the credit line stays English.
- **G15. A German game's engine lines come from its cartridge** (#25,
  D102, 2026-10-14). The lines the engine authors itself are keyed on their
  English source (upstream's `Strings`); a German game fills that catalog at
  boot from three layers, each only where the one above has nothing: the
  cartridge's menu words, read at import by pokered label (`field.words`);
  the cartridge's text labels, composed the way pokered prints them (an EXP
  gain is `_GainedText` + `_ExpPointsText`); and the fork's own wording for
  lines no cartridge has (co-op, the engine's extra options, link play),
  listed for the owner in [german-wording.md](german-wording.md). A
  translation mod's entries win. The menus the German cartridge draws wider
  or elsewhere (the two-option boxes, the battle and Safari menus, the SAVE
  panels, the Cable Club's cancel box, the PC sub-menu) follow it from
  constants in `src/coop/game/German.lua`; nothing changes for the US games.
  No German cartridge text is in the repository: it is decoded from the
  player's cartridge at import. Details in [german.md](german.md).
- **G16. Gelbe Edition is a game of its own, the way Rote and Blaue are**
  (#40, 2026-10-14). `yellow_de` plays as Yellow (`GameVersion.isYellow()`
  answers for the base, as `isBlue()` does) with the German cartridge's
  data, through a manifest derived from the US Yellow one with the
  addresses of Brianum/pokeyellow-de (constants only, pinned). Where the
  German Yellow cartridge differs from German Red, the difference lives
  in data, not branches: a catalog entry's `yellow` variant for the menu
  words Yellow names otherwise or puts a PRINT row into, `German.layout.yellow`
  for the one box it draws otherwise, and the manifest's title layout for
  its ©1995-2000 line and its one-piece surfing title screen. Nothing
  changes for US Yellow.
- **G17. One Input per seat, the device claimed on CONTROLS** (#4,
  2026-10-14). Upstream's `Input` merges every pad and the keyboard into one
  player; the fork keeps that for solo and online play (player 1 is that
  very table) and adds a seat per local player (`src/coop/game/Seats.lua`):
  an instance of `Input` that, in couch mode, takes only the device claimed
  for it on the launcher's CONTROLS page, the keyboard or one pad by GUID
  and order among twins, remembered in `coop/launcher.json`. The hook in
  `Input.lua` is one filter at each device entry, marked. Rebinds are not
  per seat: the launcher writes `options.bindings` where the game reads it,
  so every seat and the game's own CONTROLS menu agree. Couch co-op (#11)
  starts couch mode; until then the seats are only remembered.
- **G18. The game's options live in the game's file** (#5, 2026-10-14).
  The launcher's SETTINGS page edits video, audio and game options in
  `options.lua` through GPL `SaveData`, the keys the game's own OPTIONS menu
  writes, one key per change; the launcher's own settings (language,
  colours, devices, sessions) stay in `coop/launcher.json`. A second copy of
  the game's options in the launcher's file would drift from the game's
  menu, and `options.lua` is the engine's file, not the proprietary
  launcher's: upstream's launcher only called the same GPL reader and
  writer, which the fork keeps calling and never routes through
  `LauncherSettings.lua`. Per-cart overlays (`CART_OPTION_KEYS`) keep
  working, since the writes go through the same path as the game's.
- **G19. Save slots are upstream's; a campaign's slot is entered from its
  campaign** (#6, 2026-10-14). The SAVES page lists, plays, adds, deletes,
  imports and exports the game's own slots through GPL `SaveData`,
  `SaveFileIO` and `SaveConvert`, so a .sav comes and goes exactly as in
  the game's own importer. A slot that a campaign plays in (G10) shows its
  campaign and has no PLAY here: entering it goes through CAMPAIGNS, which
  keeps the session and the slot together; it can still be exported and
  deleted. Since #13 the slot's content comes from the host's campaign file
  on entering (G20).
- **G20. A campaign file holds each player's world whole until the shared
  world** (#13, 2026-10-14, accepted by the owner 2026-10-15). The host's file (`coop/campaigns/<game>/<id>.campaign`,
  JSON) has the campaign's section (id, title, cartridge, revision, the
  shared story, the unique-encounter registry, the applied commits) and a
  section per player whose world is the game's own save text
  (`SaveSerializer`, read back by its safe parser), the PC apart for the
  journal. Until the world patches of #14 move the shared keys (flags,
  badges, toggled objects) into the campaign's story, each player's world
  keeps its own. Every write of the game's save in a co-op world sends that
  world to the host as a real SAVE; the device still plays from the
  campaign's save slot (G10), which the launcher fills from the host's file
  on entering. Each Pokémon carries its uid in `coopUid`. `love.filesystem`
  has no rename, so the swap renames in the real save folder and falls back
  to writing in place with the checked `.tmp` as the witness. Details:
  [campaign.md](campaign.md).
- **G21. The shared world is a story of save entries** (#14, 2026-10-15,
  accepted by the owner the same day).
  The engine has no RAM bytes to share: a Gen 1 world here is a save table.
  The campaign owns six families of its entries (`Ownership.lua`): event
  flags (less a list of each player's: Safari, purified zone, Mansion
  switch, fossil lab, Elite Four walk-ins and Lance's lock, gift Pokémon,
  the starter choice), object toggles (less the gift Pokémon's balls),
  beaten trainers, item balls taken, the eight badges (inventory items
  here) and Vermilion's trash-can locks. Anything else is the player's.
  They travel as a flat map of paths, so patches merge entry by entry. The
  engine saves no per-map script steps, so A5.6 and A5.9 adapt: a
  partner's entry lands at the next rest point even on the map a window
  stands on, with the map rebuilt for objects and reloaded for the flags it
  is stamped from. A step the player walks of their own does not hold a
  rest point (A5.4). A window opened late takes the campaign, and only a
  campaign with no story yet takes a window's entries. The host keeps each
  player's world without the story and lays the story over it when it
  sends it. Campaign files move to version 2, the story built from a
  version 1 file's worlds by the team rule. Details: [world.md](world.md).
- **G22. Story items ride on the window's patch** (#16, 2026-10-15,
  accepted by the owner the same day: the race's take-back, the late
  joiner's list, the 40-row bag and the German notices as built). A window notes its bag and money at every rest point. A patch
  that sets story entries carries the bag's change since the last rest
  point. The host shares a change that moved the story: every other player
  is owed its gains and loses its key items, fossils excepted. A change
  that moved nothing new had its gains taken back, unless money went down
  or the item is a key item or HM. What a player is owed waits in the
  campaign file, numbered. It lands at a window's rest point (bag, else
  PC; a held key item or HM is skipped), and the save keeps the last
  number landed. The host forgets an item once a saved world shows it, so
  nothing is lost to a dropped link or given twice by a rejoin. The gift
  list is the `gift:<item>` commits: the key items and HMs of A6.5, and a
  TM gained with its `EVENT_GOT_TMxx` flag. A new player is owed all of
  them. The bag holds 40 rows while a session's game runs, and a
  campaign's slot is not exported to a `.sav`. Protocol 6, campaign file
  version 3. Details: [items.md](items.md).
- **G23. Split-screen: two worlds, one mix** (#11, 2026-10-15, accepted by
  the owner the same day, with player 2's sound effects to follow in #51
  and player 2's naming in #22).
  The second seat's game is a second set of the game's modules in the same
  process (`package.loaded` swapped per world). It is a client of the
  session like any other player: it dials the in-process host's loopback
  hub, or the host the first seat joined. The window has one mix: the
  first seat's music and both seats' sound effects (#51). The second
  seat's game runs without `love.thread` (the workers' channels are
  process-global) and with a guarded `love.audio` that cannot stop, pause
  or set anything for the whole device; its music stays off, so the first
  seat's song plays on. Its sound waits take the real lengths of its
  sounds; its music waits keep their silent timings. Its trainer is named
  `PLAYER2` until a host knows it. The launcher shows the two-player rows
  only when CONTROLS has a device for each player. Details:
  [split.md](split.md).
- **G24. Co-op battles are lockstep; the host keeps the record** (#18,
  2026-10-15, accepted by the owner the same day). A8.2 asked for a scene-free battle
  engine on the host, with upstream's lockstep link battles as the
  alternative to weigh. The engine's battle is one `BattleState` with its
  presentation woven through its logic, and the host runs in the hosting
  game's process, so a second, headless copy there would share that game's
  sounds, mods and singletons. Every window in a battle instead runs the
  game's own battle from the host's record: the opening the opener's world
  prepared, a seed the host deals, and the numbered inputs (teams that
  joined, accepted commands), applied at the battle's questions; each window
  reports where its copy stands, and the host takes the first report of a
  revision and logs a different one as a desync. So every window shows the
  cartridge's own battle (#19 builds on it), a joiner catches up by playing
  the record without a screen, and the host stays free of the engine. Costs:
  a desync is detected, not repaired; a window has to run its copy for its
  player's Pokémon to get their results (a player away from the battle is
  #20). Details: [battles.md](battles.md).
- **G25. A window's holdings travel at its rest points; the window is their
  only writer** (#17, 2026-10-15, accepted by the owner the same day). A7.2 has the host refuse a
  copy older than its own latest change (a catch, battle results). Under
  G24 neither happens on the host: every copy plays the catch and the
  battle's results, and the copy of the player the catch is for stores it
  in that player's world (a copy out of sight plays on, A11.3, so a named
  player who left still gets it). So the window sends its holdings (its
  world without the PC, the PC when it changed or first on a link) at rest
  points, and the host takes each copy in the link's order with no
  revision. The host stamps uids and sends back the ones it gave, so a
  window's rows carry them; matching prefers an unchanged row, then the
  row's place, which the host already knows (A7.3's hint). A catch's room
  is said with each team (`room`): a party under six, or any box with
  space, since this engine fills the next box (`Boxes.deposit`). Costs: a
  window encodes its PC after each held scene (about 2 ms for a full PC on
  a desktop); a world reaches the host each time the holdings change, not
  only on SAVE. Details: [campaign.md](campaign.md).
- **G26. A unique encounter is its map object; a beaten one counts as won
  in the world** (#21, 2026-10-15, accepted by the owner the same day). A10.2 and A10.3 name a
  trainer `trainer:<class>:<index>` and a one-off wild Pokémon
  `static:<species>:<map>`. This engine already keys a beaten trainer or
  static Pokémon by its map object (`defeatedTrainers/<MAP>_obj_<n>`, the
  campaign's since #14), so the encounter is `trainer:<MAP>_obj_<n>` or
  `static:<MAP>_obj_<n>`: one key per object, and a scripted fight with a
  map object (a gym leader, SNORLAX) gets one too. A battle with no map
  object (grass, water, a scene's sprite) is no encounter. A window
  walking into a done one is refused `beaten`; its world's own `onFinish`
  hears a win after the battle transition, with no fight and no prize, and
  a notice says "<FOE> was already beaten.". The sight gate reads the
  running encounters from `state`; a beaten trainer is the story's, which
  already stops it seeing anyone. The League's rooms are never kept done,
  so every run fights everyone again, until #55's team run (A10.6).
- **G27. The opening's private story stays in the window** (#22,
  2026-10-15, accepted by the owner on 2026-10-16; the split into #57 and
  the seed from the first finished opening chosen by the owner on
  2026-10-15). A4.4 has the host
  keep a private copy of the story for a player in the opening and send it
  to their window. Here the window keeps it: a window whose world has no
  starter (`EVENT_GOT_STARTER`) sends and takes nothing of the campaign's
  story, lands no gifts, sends no holdings, and the game writes no save
  (A4.9), so nothing of the opening reaches the host and a player who
  drops in it plays it again. The engine keeps no "left the lab" byte, so
  the opening ends at a rest point once the player has a starter and
  stands outside `OAKS_LAB`; the lab's rival battle stands between the
  two. A4.7 asks for a canned post-opening story per version; instead a
  new campaign has no story until its first player finishes the opening,
  whose entries seed it as their cartridge left them (the Pallet start of
  #57 will need the canned state). The host marks a player it has no
  world for as in the opening when they join, so they are announced so,
  until their window says otherwise. The campaign keeps the rival's name
  (the first given in Oak's speech, or the host's at NEW CAMPAIGN) and
  the starter he counters (the first finisher's); Red and Blue's later
  rival battles pick his team from it. Protocol 10, campaign file 4.
  Details: [opening.md](opening.md).
- **G33. Red and Blue are one game in two cartridges; the switch of both
  versions is the campaign card's** (#9, 2026-10-16, proposed). A host lets
  in its own game and dump, and the other game of its pair (Red with Blue,
  Rot with Blau) when both are verified dumps (`GameVersion.acceptsSha1`);
  everything else is refused `content_mismatch`, the host's log saying
  `language`, `dump` or `game`, and the launcher naming it from the lobby.
  The fork's extraction shows the two share species, moves, items,
  trainers and texts, so a co-op battle's record plays the same in both
  windows. Choose your campaign lists both games' campaigns, and a Blue
  cartridge hosts a Red campaign whose file stays in Red's folder (A13.2).
  "Wild Pokémon from both versions" (A13.3, A13.4) differs from the source
  in three details: the switch lives on the hosting device's campaign card
  (`mix`, NEW CAMPAIGN's row and the card's), not in the campaign file, so
  it is changed between hostings and needs no file version; the window
  draws the extra number only where the slot offers an exclusive, so a
  slot without one keeps the cartridge's stream even with the tables held;
  the tables are about 20 KB of JSON. A split-screen device plays one
  cartridge for both seats (the version and the cartridge cache are one per
  process), so a Red and a Blue player never share a device. Yellow stays
  with Yellow (G4); the answer is in A13. Protocol 11. Details:
  [versions.md](versions.md).
