# Campaign files

A co-op campaign's state on the hosting device and how it is saved (#13,
area A3 in [design.md](design.md), decision G20). It lives in
`src/coop/campaign/`. The host keeps it, and the windows send what their
game saved. The session that carries it is in [session.md](session.md).

## Files

- `Campaign.lua`: the state. It has a campaign section and one section per
  player, never one merged save. It also holds uids and exactly-once
  commits.
- `World.lua`: a player's world as it travels and as it is stored. That is
  the game's own save text (`SaveSerializer`), read back by its safe parser
  and checked for a save's shape.
- `CampaignFile.lua`: the versioned file, its `.tmp`, `.bak` and journal,
  and reading a file back.
- `Store.lua`: when the host writes the file (checkpoints, the journal and
  the save cadence).
- `src/coop/game/CampaignSave.lua`: what the game's save code asks of the
  campaign (the save request, the gate, the notices, the CO-OP box line).

## The state

**Campaign section:**
- id, title, cartridge (game and SHA-1), created;
- a revision that moves with every change;
- the shared story (`story`): the campaign's entries of every world (flags,
  hidden objects, beaten trainers, item balls, badges, Vermilion's locks)
  as a flat map of paths, filled by the windows' patches (#14,
  [world.md](world.md), G21);
- the unique-encounter registry (`encounters`, id to `{ state, battle }`,
  for #21);
- the set of applied commit ids.

**Player section:**
- id, name, game, the in-game trainer id;
- the serial of the last uid handed out;
- their **world**: the save table their game wrote, without the device's
  options and without the story's entries. It holds the team, the PC
  (twelve boxes of twenty) and current box, bag, money, map, cell, facing
  and the rest. A world sent to the player has the story laid over it.
- the items the campaign owes them (`gifts`, numbered by `giftSeq`, #16,
  [items.md](items.md)): kept until a world they save shows each taken
  (its `coopGifts`).

The battle a player is in and their return point come with #18. Whether a
player is connected is the session's business and is not stored.

**Uids** (design A3.2):
- Every Pokémon in a world carries `coopUid = "<player id>:<serial>"`. A
  serial is never used twice, and the uid is kept through deposits, trades
  and evolutions.
- A Pokémon arrives without a uid when the window caught it but has not yet
  played from a world the host stamped. The host matches it to the player's
  last world by its fingerprint (original trainer, DVs, catch rate). If
  nothing matches, it gets the next serial.
- Twins with one fingerprint keep two uids. A uid that appears twice in one
  world stays with the first Pokémon only.
- Matching (#17, A7.3): a row without a uid takes a uid of the player's last
  world with its fingerprint that no row carries. It takes the one whose row
  is unchanged first, then the one that stood on its place, then any.
- The host sends back the uids it gave (`uids`: box, slot, uid, fingerprint).
  The window stamps each one on the row that still stands there with that
  fingerprint, so its rows carry them from then on.

**Holdings** (#17, design A7.2, A7.4, A7.5, decision G25):
- A window sends its player's holdings at its rest points
  (`src/coop/campaign/Window.lua`, `holdings`). That is its world without
  the PC, and the PC when it changed or with the first copy on a link. The
  host keeps it as it keeps a saved world, without saving the campaign; its
  own cadence saves it (A3.9). So a heal, a gift, a catch, a deposit or a
  withdrawal reaches the host without a SAVE, and a rejoin opens it.
- It goes out when the team, current box, Pokédex, bag or money changed.
  The window looks on the first rest frame after the player was held, and
  every `HOLDINGS_EVERY` (60) rest frames after that: a poisoned team loses
  HP while walking. It looks at the PC only on that first frame, since the
  PC changes only while the player is held (a PC, a catch).
- The first rest point only notes the holdings: the window opened what the
  host has. START > SAVE sends the world whole, so nothing goes again.
- A battle the world opens sends the holdings first.
- The window is the only writer of its player's holdings: battle results
  and catches are written in the windows (G24). So the host takes every
  copy in the link's order and keeps no revision (A7.2's refusal has
  nothing to guard here).
- Not covered: a player who never saved and whose holdings never changed
  has no world on the host, as before.
- Checked live (#17: US Red, two ENet processes, offscreen). A driver
  lowered RED's lead's HP while RED stood on the map. Without a SAVE, the
  host's copy of RED's world then had that HP, and RED's row carried the
  uid the host gave it. After a battle, the RATTATA GREEN caught for RED
  was in the host's copy of RED's team, with a uid RED's row carried. One
  run whose driver waited a fixed 200 frames missed the HP change; polling
  found it arrive.

**Commits** (design A3.3): `campaign:commit(id, apply)` with a stable id
such as `gift:BICYCLE` or `victory:<encounter>`. A repeated id returns false
and changes nothing. Gifts (#16) and victories (#18, #21) use it.

## The file

`coop/campaigns/<game>/<id>.campaign` in the save folder, beside the
campaign's card (`coop/campaigns/<id>.json`, #12). It is JSON:

- `format` (`"gen1recomp-coop campaign"`) and `version` (4; version 1,
  from before the shared world, is migrated: [world.md](world.md); version
  2, from before story items, gets empty gift lists: [items.md](items.md);
  version 3, from before the opening, has no rival yet:
  [opening.md](opening.md));
- `saved` (unix time);
- `campaign`, the campaign section (since version 4 with the rival's name
  `rival` and the starter he counters `chose`, once set, #22);
- `players`, a list with one entry per player: their `world` (the game's
  save text without the PC) and `boxes` (the PC as text).

**Writing** (a checkpoint):
1. The text goes to `<file>.tmp` and is read back. It must decode as this
   campaign at this revision, or the `.tmp` is removed and the old file
   stays as it was.
2. The old file becomes `<file>.bak`, but only if it still reads as a
   campaign; otherwise the last good `.bak` stays.
3. The `.tmp` is renamed into place. `love.filesystem` has no rename, so it
   renames in the real save folder (`os.rename`). Where that fails, the
   file is written in place with the checked `.tmp` as the witness, as
   upstream's own saves do.
4. The journal is deleted.

**Reading:**
- A missing file whose `.tmp` reads is taken from the `.tmp`: the swap was
  cut off between the backup and the rename.
- A file that does not read is refused and left as it is. So is a file of a
  newer `version`: an older build never touches it. The launcher names the
  backup instead of hosting it (design A3.5).
- An older version is brought up one step at a time
  (`CampaignFile.MIGRATIONS[n]` takes n to n + 1).

**Journal** (design A3.8):
- `<id>.journal` beside the file. At the end of every host poll in which the
  revision moved past the last checkpoint or line, the whole state is
  appended as one line. A PC unchanged since the checkpoint is left out.
- Every line starts with a newline, so a line written after a torn one still
  reads.
- Reading takes the checkpoint, then the newest whole line of the same
  campaign with a higher revision. A line without a PC takes the
  checkpoint's.
- In the tests, a line with a box of twenty Pokémon is a few kilobytes.

## When the host saves

Checkpoints happen only at a safe point: no battle running and no battle
join pending (`host.battles`, `host.joins`, filled by #18).

Every write of the game's save is a real SAVE (design A3.11): START > SAVE,
a box change, the Hall of Fame, a link room's save. Each one sends the
player's world to the host with a save request:
- If the host is not busy, it writes the file. Everyone gets `saved`: the
  saver's notice is "Campaign saved.", the others' is "<NAME> saved the
  campaign.".
- While a battle runs, START > SAVE does not reach the YES/NO. The save box
  says "A battle is in progress! It can't be saved right now." and closes,
  and nothing is written in the game's slot or the campaign (design A3.10).
  A request that arrives anyway is refused, takes nothing, and the saver
  sees "The campaign was not saved."

A heal, a purchase, a gift or a thrown ball never writes the game's save,
so it asks for nothing.

The host also saves by itself (design A3.9):
- when its last running battle ends;
- at most every 30 s while something changed and no battle runs;
- when a player leaves;
- on shutdown;
- when the hosting app is paused (LÖVE's `focus` or `visible` going false).

A shutdown during a battle writes the journal instead. A crash loses at most
the battle in progress.

The CO-OP box shows when the campaign was last saved (SAVED JUST NOW, SAVED
2 MIN AGO, NOT SAVED YET) and AUTOSAVE: ON (design A3.12). Nobody has to
save before leaving.

## On the player's device

The game plays from, and writes to, the campaign's save slot on the device:
the scratch area of design A3.14 (G10's slot). It never touches a solo save.

Entering a campaign from the launcher writes the player's world from the
host into that slot before the game boots. A player the campaign has no
world for keeps what the slot holds: a new game, or the device's progress
from before campaign files. That progress reaches the host with the first
save. Such a player who chose START IN PALLET or BRING A SAVE (#57) gets
that start world in the slot instead; its window sends it to the host
whole (`start`), and the host keeps it unless it has the player's world
already ([opening.md](opening.md) § Other starts).

Split-screen (#11) needs one such slot per seat. `CoopSettings.slots` is
keyed by campaign today.

## Several campaigns

- Each campaign is its own file under its game's folder, with the campaign
  ids of #12 (`c` and 16 hex digits) and the card's title.
- A device remembers its player per host and campaign (`Identity.lua`).
- Deleting a card (#12) leaves the campaign's file. RESTORE BACKUP brings
  the card back to it.

## Tests

ROM-free, in `tests/coop/`:

- `campaign_file_test.lua`:
  - a world's checks;
  - sections, uids (deposits, evolution by fingerprint, twins, a copied
    uid), commits;
  - the file: `.tmp`, read back, `.bak`, a failed or torn write, no rename,
    a swap cut off, an unreadable, newer or foreign file;
  - migrations step by step;
  - the journal: lines, PCs left out, torn lines, other campaigns;
  - the cadence: first save, 30 s, a battle's end.
- `holdings_test.lua` (#17): uid matching (twins, an unchanged row, the
  row's place); holdings at rest points (held windows, the PC only when
  changed, a redial sending the PC again, a SAVE not sent twice, a rejoin
  opening the kept world); the uids reaching the window; a catch for the
  named player; room and a refused ball; the Pokédex; a gift with six in
  the party.
- `campaign_session_test.lua`: host and clients over loopback.
  - a new player's fresh start;
  - a world kept and journaled;
  - a checkpoint everyone hears;
  - a save refused during a battle or a pending join, taking nothing;
  - autosaves after a battle and every 30 s;
  - leaving, pause and shutdown, and shutdown during a battle;
  - a rejoin and a host started again from the file, each giving the world
    back;
  - a broken or code-carrying world refused.
- `campaign_game_test.lua`: the fixture overworld hosting a session.
  - the game's save reaching the campaign file with uids and without the
    options;
  - the notices, both ways;
  - START > SAVE during a battle: the save box with no YES/NO and nothing
    written;
  - a refused save's notice;
  - a paused host saving;
  - the CO-OP box's line;
  - the launcher writing the world into the campaign's slot (and not
    writing a fresh or unreadable one);
  - an unreadable file not hosted and left as it is.
- `session_fuzz_test.lua` covers the protocol 4 messages.
