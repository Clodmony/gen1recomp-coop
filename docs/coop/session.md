# The co-op session core

One session layer for online and split-screen co-op (#10, area A1 in
[design.md](design.md)). It lives in `src/coop/session/`. A hosting device
runs the host in-process, and its own players dial it like any other client.
A split-screen seat dials over an in-memory loopback hub, a network player
over ENet. One host serves both kinds at once (G3).

## Files

- `Protocol.lua`: the protocol version, the message types and one
  sanitizer per type, for each direction.
- `Transport.lua`: the transports, `loopback()` (many clients in one
  process) and `listen(port)` / `dial(address)` (ENet). Both have the same
  API and carry JSON text. Upstream's `src/link/Net.lua` pairs exactly two
  ends and caps a message at 256 KB, so co-op has its own transport and
  reuses upstream's `Json.lua`.
- `Host.lua`: the host. It handles probe and hello, identity, sequence
  numbers, the step check, leaving, rejoining, the state each player is
  sent, and shutdown. It can start with a campaign's known players
  (`players`, disconnected until they come back), and `roster()` lists every
  player with the address they dialled, for the campaign card.
- `Client.lua`: one player's link. It sends numbered intentions and keeps
  the last lobby view and state.
- `Identity.lua`: what a device remembers (`coop/identity.json` in the save
  folder): its random id, and per host address and seat, its player in each
  campaign, the newest 64 (`Protocol.MAX_KNOWN`, the most a hello carries;
  #15).
- `SessionLog.lua`: one JSON-lines log per session per device.
- `Beacon.lua`: LAN discovery over UDP.
- `Random.lua`: device, player and campaign ids from the system's random
  source.
- `Session.lua`: the session this process takes part in (see *The running
  session*).
- `Addresses.lua`: this device's addresses by kind (VPN, home, public) and
  the checklist for an address nobody answered on.
- `Dev.lua`: the development entry for scripted runs.
- The campaign the host keeps and saves is `src/coop/campaign/`
  ([campaign.md](campaign.md)).

## Protocol

Version 11 (1 was #10; 2 added shared logs, #31, and the `flood` refusal,
#32; 3 added how a player travels, #15; 4 added campaign files, #13:
[campaign.md](campaign.md); 5 added the shared world, #14:
[world.md](world.md); 6 added story items, #16: [items.md](items.md); 7
added co-op battles, #18: [battles.md](battles.md); 8 added holdings and
uids, #17: [campaign.md](campaign.md); 9 added unique encounters, #21:
[battles.md](battles.md); 10 added the opening, #22: [opening.md](opening.md);
11 added rival scenes, #59: [battles.md](battles.md)). Every message is a JSON object with a `type`. Every field from the
other end is untrusted. A message is kept only when each field has its type,
range and format, and only the schema's fields are kept. Anything else is
dropped whole and counted. This holds in both directions, so a client also
checks what the host sends.

| Client to host | Fields |
|---|---|
| `probe` | `protocol`, `build`, `name`, `game`, `sha1`, `known`: asked before `hello` on the same link. Answered whatever the protocol; creates nobody. |
| `hello` | the probe's fields and `device`, `seat` (1 or 2), `via` (the address dialled), `logs` (`share`: this link carries the device's shared log) |
| `move` | `seq`, `map`, `x`, `y`, `facing`, `warp` (the map changed or the player jumped), `travel` (`walk`, `run`, `bike`, `surf`) |
| `bye` | `seq`: leaving on purpose. A dropped link leaves the same way. |
| `log` | `lines`: the device's own session log lines since its last batch (see *Session logs*) |
| `world` | `seq`, `save` (the game's save text, at most 1.5 MiB), `checkpoint` (a real SAVE asking the host to save the campaign), `kind` (`menu`, `box`, `hall`, `link`, `quick`; optional) |
| `patch` | `seq`, `set` (story path to value: a boolean or a whole number 0 to 255), `unset` (paths): this window's change to the shared story since its last patch, at most 8192 entries each, `bag` (optional, #16: `gained` and `lost`, item id to a count 1 to 999, and `spent`, the money went down; the window's bag change in the same rest-to-rest change) |
| `battle_open`, `battle_join`, `battle_cmd`, `battle_suggest`, `battle_at` | co-op battles (#18): [battles.md](battles.md) |
| `opening` | `seq`, `done` (the window plays the opening, or finished it), `rival` (optional: the rival's name given in Oak's speech), `chose` (optional, with `done`: the starter it took) (#22): [opening.md](opening.md) |
| `scene` | `seq`, `map`, `key`, `on`: a claim of a rival scene on that map (on), refused `scene_taken` while another player drives it, or its release (#59): [battles.md](battles.md) |

| Host to client | Fields |
|---|---|
| `probe` | the lobby view (`kind`, `protocol`, `build`, `campaign`, `title`, `game`, `sha1`, `host`, `players` with `name`, `game`, `connected`), `refused` (empty, `protocol_mismatch` or `content_mismatch`), `you` (the player this device or name would get back) and `port` |
| `welcome` | `protocol`, `player`, `campaign`, `last_seq` |
| `state` | `players` (`id`, `name`, `game`, `connected`, and `map`, `x`, `y`, `facing`, `travel` once known), `you`, `last_seq`, `nearby` (connected players on your map), `saved_ago` (seconds since the campaign was saved, -1 never), `busy` (why a save would be refused now, or empty); since #22 each player's `opening`, and the campaign's `rival` and `chose` ([opening.md](opening.md)); since #59 `scenes`, the rival scenes being played (`map`, `key`, `by`) ([battles.md](battles.md)) |
| `world` | once after `welcome`: `fresh` (the campaign has no world for this player), `save` (their world) |
| `saved` | `ok`, `by` (who saved), `you` (this player asked), `reason` (a refusal: `battle_in_progress`, `bad_world`, `save_failed`), `kind` |
| `story` | `rev`, `base` (the whole story, replacing the window's), `set`, `unset` (what changed since the last `story` to this player), `applied` (the last of this player's patches the host applied) |
| `gifts` | `list` (#16): items the campaign owes this player, oldest first, each `seq`, `item`, `qty` (below 0 takes), `once` (not given to a player who holds one), `from` (the partner's name), `race` (a take-back); at most 256 a message |
| `battle` | a battle this player is in or joining (#18): [battles.md](battles.md); `state` then also names each player's `battle` and lists the running `battles` |
| `rejected` | `seq` (-1 for a refused hello), `reason` |
| `ended` | `reason` |
| `log` | `lines`: other devices' log lines, passed on once |

Rules (design A1):

- **Versions.** A probe or hello of another protocol version is answered
  with `protocol_mismatch` before anything else in it is read.
- **Cartridge.** The game id and the ROM's SHA-1 must match the host's, or
  the hello is refused with `content_mismatch`. Red with Blue is #9. A
  cartridge of another language (German `red_de`/`blue_de` against English,
  [german.md](german.md)) is refused first, whatever #9 lets pair (D95). No
  ROM data is ever sent.
- **Refused hellos.** The host sends `rejected` with seq -1 and drops the
  link after `Host.GRACE` (1 s), so the reason arrives first.
- **Sequence numbers.** Per player and strictly increasing. A number seen
  before is refused as `duplicate` and changes nothing. The welcome tells a
  rejoining player the last number the host saw. An intention before hello
  is refused as `hello_first`.
- **Identity.** The hello carries the seat's `{ campaign = player }` map
  for this host. A remembered player who is not connected gets their player
  back. If that player is connected already (a second window), the device
  joins as someone new. A device that lost its id is recognised by the same
  name. Split-screen has two seats, so a device remembers two players per
  campaign.
- **Worlds** (#13). A `world` is kept only when it parses with the game's
  own save parser and has a save's shape (a team of at most six, twelve
  boxes of twenty, a current box among them, money a number); otherwise it
  is refused as `bad_world` and changes nothing. A `checkpoint` while a
  battle runs or a join is pending is refused as `battle_in_progress` and
  takes nothing.
- **Story** (#14). A `patch` entry is applied only when the campaign owns
  its path and the value fits (`Ownership.lua`); others are skipped, and
  the patch still counts as applied. The world a player gets has the story
  laid over it. See [world.md](world.md).
- **Story items** (#16). A `patch` that sets story entries carries its
  window's bag change; the host shares it or takes it back as
  [items.md](items.md) says. Each link hears each owed gift once; a new
  link hears them all again, and the window applies each `seq` once.
- **Trusted windows** (D72). The host checks only the step length, up to
  two cells on one map (a ledge hop). A map change or a jump has to come
  with `warp`, which is taken as it is. A refused step is `bad_step`.
- **Leaving.** A player who leaves keeps their position. The others see
  `connected` false.
- **Shutdown.** Clients get `ended`, and further messages are ignored. The
  host closes once all links are gone or after the grace.

## Transport and limits

- **Size.** One message may be 2 MiB (`Protocol.MAX_MESSAGE`). A bigger
  one is not sent, and a bigger wire text is dropped. Over ENet on one
  machine, a 2 MiB message arrived whole in 0.15 to 0.26 s.
- **Per-link limits** (#32). Arriving text waits on its link undecoded.
  Each frame the host decodes at most 256 KB or 64 messages of one link
  (`Host.FRAME_BUDGET`; always at least one message) and the rest waits for
  the next frame, so one link cannot take the frame from the others. Each
  link has an allowance of 4 MiB and 512 messages (`Host.BURST`, two full
  messages), refilled at 1 MiB and 120 messages a second (`Host.RATE`). A
  link that goes over it is refused with `rejected` `flood` (seq -1): its
  player leaves at once, nothing more it sends is read, and the link closes
  after the grace. A client that gets `flood` while joined goes to
  `refused`. Clients do not limit the host.
- **Decoding cost.** Upstream's `Json.lua` decodes, in LuaJIT on one
  desktop machine, a 2 MiB string in about 22 ms and structured data (a
  PC-like list of records) at about 46 ms per MB. Scanning a string's plain
  run at once instead of one character at a time halved the string case
  but saved only about 15% on structured data, so the decoder stays
  upstream's; the frame budget is what bounds a frame. One 2 MiB message
  still costs one frame up to about 0.1 s.
- **ENet.** Up to 32 peers, one reliable channel, no bandwidth cap. A dial
  that gets no answer closes after 5 s with "no answer from …".
- **Ports** (G8). The game port is UDP 24680 and the LAN beacon UDP 24681,
  apart from upstream's link port 7777.
- **Internet play** is direct (G5): a forwarded port or a VPN, no relay.

## LAN beacon

A hosting session sends its lobby view and game port as one JSON datagram
once a second. It goes to port 24681 on 255.255.255.255, on the LAN's
`.255` and on 127.0.0.1. A joining device lists the hosts heard in the last
4 s. Only one listener binds per device. The beacon is optional: joining by
address works without it.

LÖVE's luasocket leaves a plain `socket.udp()` without an address family,
and `sendto` on it is refused, so the beacon uses `socket.udp4()`. iOS
needs the multicast entitlement for broadcasts (#7).

## Session logs

Each device writes `coop/logs/session-<time>-<device>.jsonl` in the save
folder. A line holds `t` (unix ms), `frame`, `device`, `name`, `seat`, `src`
(host or client), `player`, `kind` and `data`. The host logs its start
state, every message it reads, joins, new players, refusals, drops, leaves,
the shutdown and its end state. The newest 30 files are kept, at most
256 MB. Logs contain names and addresses: they go to the other players of
the session and are never posted publicly.

**Sharing** (#31, design A1.14) is on by default; SHARE LOGS OFF on the
launcher's co-op LOGS screen (#12), or `--coop-logs=off` (or
`POKEPORT_COOP_LOGS=off`) for the development entry, keeps a device's lines
on that device. Each line a device writes carries `n`, its number on that
device.

- A joined client that shares sends its own new lines every 2 s
  (`SessionLog.SHARE_INTERVAL`) in a `log` batch, and a last batch before
  its bye. A batch is at most 64 KB and 1024 lines; a line over 8 KB goes
  without its data (`data` becomes `omitted_bytes`); lines that do not fit
  are counted in a `stream_dropped` line.
- The host takes only lines of the sending link's device (the hello's
  `device`), up to a batch, keeps them in its own log when it shares too,
  and passes the batch on once to every other sharing device, one link per
  device. It shares its own lines the same way, and a last batch before
  `ended`.
- A device stores lines from others with `relay` (`via`: the host, or on
  the host the sending player, and `t`) and never puts them in its own
  batches, so a line is passed on once. A device's own lines never come
  back to it.
- The host keeps the last 256 KB of batches (`Host.LOG_BACKLOG`); a device
  that joins later gets the lines it missed from that backlog.
- A device that does not share sends nothing and gets nothing; a batch it
  sends anyway is ignored. The hosting device's own player and a second
  seat on one device carry no log on their link. A second seat (split-screen,
  [split.md](split.md)) writes its own file, `session-<stamp>-<device>-seat2.jsonl`.
- A log's last line (`close`) counts the lines sent, received and not
  sent.

## The running session

`Session.lua` holds the one session of a process (`Session.current`). The
launcher's co-op screens start it ([launcher.md](launcher.md)), and it keeps
running from the launcher into the game:

- `Session.startHost` runs the host in-process on a loopback hub, opens UDP
  24680 and the beacon, and its own player dials the hub. A busy port leaves
  a host only this device can join.
- `Session.startDial` probes the address first. While nobody answers it
  tries again every `Session.RETRY` (3 s) for `Session.DIAL_FOR` (60 s), then
  stays `unreachable` until tried again; partners often press Join first. An
  ENet dial that gets no answer gives up after 5 s, so an attempt that hangs
  is followed at once by the next. A probe answer with a refusal ends the
  dial as `refused`; otherwise `join(name)` sends the hello on the same link.
- Each frame, main.lua's hook and the launcher call `Session.tick`. Once a
  game runs, the player's cell goes to the host as it changes: the cell a
  step heads for, so the other screens ease it while it is walked, with how
  the player travels (`Session.position`). The console prints who joined,
  left and changed maps. The game draws the other players
  ([presence.md](presence.md), #15).
- Leaving from the game (the CO-OP menu's LEAVE SESSION) ends the session
  the same way and takes the game back to the launcher
  (`Session.takeLauncher`).
- A joining game whose link drops under it reconnects (#20, design
  A11.9): it redials as the same player every 2 s (`Session.REDIAL`) for
  two minutes (`REDIAL_FOR`), saying "Lost the host: reconnecting..." over
  the world and "Back in the session." when the host has it back. The world
  keeps running and sends nothing meanwhile; the shared world's window and
  the battle copies follow the new link; the first position after counts
  as a warp. A game back from a pause (focus or visibility lost) longer than
  3 s closes its link and dials at once (A11.10); a hosting game put away
  saves its campaign (#13).
- A session that ends under the game (the host stopped it, the link stayed
  lost for two minutes) shows why over the world for 3 s (A11.11), then
  main.lua goes back to the launcher; leaving on purpose (the game window
  closed, `love.quit`) sends a bye or ends the session for everyone, and on
  shutdown the host waits for the clients to leave for up to 2 s
  (`Host.END_GRACE`). Either way `coop/return.json` in the save folder
  carries the reason, and the launcher shows it on the co-op screen if it
  opens within two minutes.

## Development entry

For scripted runs, a game can host or join a session from the command line,
past the launcher's screens:

```bash
love . --coop-host[=PORT] [--coop-name=NAME] [--coop-logs=off]  # host on UDP PORT (24680)
love . --coop-join=ADDRESS[:PORT] [--coop-name=NAME] [--coop-logs=off]
love . --coop-host --coop-campaign=ID  # host that campaign again from its file (#13)
love . --coop-host --coop-split[=NAME]   # and a second player in split-screen (#11)
```

Scripted runs can use `POKEPORT_COOP_HOST=PORT`, `POKEPORT_COOP_JOIN=ADDRESS`,
`POKEPORT_COOP_NAME=NAME`, `POKEPORT_COOP_LOGS=off`,
`POKEPORT_COOP_CAMPAIGN=ID` and `POKEPORT_COOP_SPLIT=NAME` (or `1`) instead. Once a game
is running, the host side hosts a new campaign (a new id each time) and the
join side dials the address and joins as soon as the host answers. A step
through a map connection shows a cell off the map for one frame, which is
skipped; the settled cell on the next map goes out as the map change.

`main.lua` has three marked hooks: `Dev.configure(args)` in `love.load`,
`Dev.update` once a game runs (it ticks the session the launcher started,
and goes back to the launcher when it ends), and `Session.shutdown` in
`love.quit`, which sends a bye or ends the session.

## Checked

Run on Linux desktop (LÖVE 11.5), US Red, two game processes on one
machine, each with its own save folder and a frame driver:

- a host with `--coop-host` and a guest with `--coop-join=127.0.0.1:PORT`;
- the guest joined, moved, crossed from Route 1 into Pallet Town by the map
  connection, and quit, which sent a bye;
- a second guest run rejoined as the same player, its numbers going on after
  the bye;
- each side saw the other's maps.

The run found three faults, now fixed and tested:
- the connection step's off-map cell was sent, then refused;
- both processes drew the same device id;
- the log's `frame` was always 0.

Two machines on a LAN, the beacon across machines, Windows, macOS and mobile
have not been run. The launcher's co-op screens were run the same way
(#12); [launcher.md](launcher.md) says what was run.

## Tests

ROM-free, in the `engine` group of `scripts/test.sh` and so in coop-ci:

- `tests/coop/session_loopback_test.lua`:
  - two seats and more players join over loopback, move and change maps;
  - steps, warps and bad steps;
  - duplicates and `hello_first`;
  - leave, rejoin, rejoin by name, a second window;
  - the probe;
  - protocol and cartridge refusals with the grace;
  - shutdown and 2 MiB.
- `tests/coop/session_fuzz_test.lua [seed]`: a seeded fuzz of every message
  type in both directions (fields removed, retyped, out of range, oversized,
  nested, extra; broken JSON), `log` included. A malformed message is
  dropped, counted and changes nothing; nothing raises; a kept message holds
  only its schema's fields; the fuzz's pace is no flood.
- `tests/coop/session_identity_log_test.lua`: the device identity store and
  its 64 campaigns per seat, random ids across processes, the host's log
  lines and log rotation.
- `tests/coop/session_logs_test.lua` (#31): three sharing devices and the
  host; lines reach the others through the host, the backlog for late
  joiners and its 256 KB cap, the 8 KB line and 64 KB batch caps, no line
  passed on twice, forged lines of another device, a device that does not
  share, the last lines before a bye and before `ended`.
- `tests/coop/session_flood_test.lua` (#32): a move every frame for 20 s, a
  2 MiB message and a backlog of small messages are no flood; a 3 MB burst
  is decoded a budget at a time; a flood of large or of many small messages
  is dropped with `flood` within a second while another player's move goes
  through in every frame.
- `tests/coop/session_dev_entry_test.lua`: the entry's arguments, addresses,
  and the moves a game's position becomes.
- `tests/coop/session_reconnect_test.lua` (#20): a dropped link
  reconnects, gives up after two minutes, and a long pause dials afresh.
- `tests/coop/launcher_coop_test.lua` (#12): the running session as the
  launcher's co-op screens use it, over loopback; see
  [launcher.md](launcher.md).
- `tests/coop/presence_test.lua` (#15): the partners in a running game;
  see [presence.md](presence.md).
- `tests/coop/campaign_file_test.lua`, `campaign_session_test.lua` and
  `campaign_game_test.lua` (#13): the campaign, its file and its saves;
  see [campaign.md](campaign.md).
- `tests/coop/enet/` runs under LÖVE without a window (`love tests/coop/enet`),
  since plain luajit has no lua-enet:
  - a loopback seat and two ENet players on one host;
  - moves and a map change;
  - leaving by bye and by a dropped link, and rejoining;
  - protocol and cartridge refusals;
  - broken JSON and 2 MiB messages;
  - a log line from one ENet player to another, and a flooding ENet
    player dropped while another one moves;
  - a dial with nobody listening;
  - a partner who dials before the host listens, found by the retries
    (#12), and the host's STOP reaching them;
  - the beacon on 127.0.0.1.

  It uses its own ports. `scripts/test.sh` runs it when `love` is on PATH,
  and coop-ci has a job that installs LÖVE for it.
