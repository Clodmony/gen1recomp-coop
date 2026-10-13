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
  sent, and shutdown.
- `Client.lua`: one player's link. It sends numbered intentions and keeps
  the last lobby view and state.
- `Identity.lua`: what a device remembers (`coop/identity.json` in the save
  folder): its random id, and per host address and seat, its player in each
  campaign.
- `SessionLog.lua`: one JSON-lines log per session per device.
- `Beacon.lua`: LAN discovery over UDP.
- `Random.lua`: device, player and campaign ids from the system's random
  source.
- `Dev.lua`: the development entry, until the launcher's co-op screens
  (#12).

## Protocol

Version 1. Every message is a JSON object with a `type`. Every field from the
other end is untrusted. A message is kept only when each field has its type,
range and format, and only the schema's fields are kept. Anything else is
dropped whole and counted. This holds in both directions, so a client also
checks what the host sends.

| Client to host | Fields |
|---|---|
| `probe` | `protocol`, `build`, `name`, `game`, `sha1`, `known`: asked before `hello` on the same link. Answered whatever the protocol; creates nobody. |
| `hello` | the probe's fields and `device`, `seat` (1 or 2), `via` (the address dialled) |
| `move` | `seq`, `map`, `x`, `y`, `facing`, `warp` (the map changed or the player jumped) |
| `bye` | `seq`: leaving on purpose. A dropped link leaves the same way. |

| Host to client | Fields |
|---|---|
| `probe` | the lobby view (`kind`, `protocol`, `build`, `campaign`, `title`, `game`, `sha1`, `host`, `players` with `name`, `game`, `connected`), `refused` (empty, `protocol_mismatch` or `content_mismatch`), `you` (the player this device or name would get back) and `port` |
| `welcome` | `protocol`, `player`, `campaign`, `last_seq` |
| `state` | `players` (`id`, `name`, `game`, `connected`, and `map`, `x`, `y`, `facing` once known), `you`, `last_seq`, `nearby` (connected players on your map) |
| `rejected` | `seq` (-1 for a refused hello), `reason` |
| `ended` | `reason` |

Rules (design A1):

- **Versions.** A probe or hello of another protocol version is answered
  with `protocol_mismatch` before anything else in it is read.
- **Cartridge.** The game id and the ROM's SHA-1 must match the host's, or
  the hello is refused with `content_mismatch`. Red with Blue is #9. No ROM
  data is ever sent.
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
  machine, a 2 MiB message arrived whole in about 0.15 s. Per-link limits
  against floods are #32.
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
256 MB. Logs contain names and addresses: they are never posted publicly.
Sharing lines with the other players is #31.

## Development entry

Until the launcher's co-op screens exist (#12), a game joins a session from
the command line:

```bash
love . --coop-host[=PORT] [--coop-name=NAME]     # host on UDP PORT (24680)
love . --coop-join=ADDRESS[:PORT] [--coop-name=NAME]
```

Scripted runs can use `POKEPORT_COOP_HOST=PORT`, `POKEPORT_COOP_JOIN=ADDRESS`
and `POKEPORT_COOP_NAME=NAME` instead. Once a game is running, the host side
opens the port, starts the beacon, and its own player dials it over
loopback. Each player's cell is sent as it changes. A step through a map
connection shows a cell off the map for one frame, which is skipped; the
settled cell on the next map goes out as the map change. The console prints
who joined, left and changed maps. Nothing of the other players is drawn
yet (#15). Each session uses a new campaign id, since campaign files are
#13.

`main.lua` has three marked hooks: `Dev.configure(args)` in `love.load`,
`Dev.update` once a game runs, and `Dev.shutdown` in `love.quit`, which sends
a bye or ends the session.

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
have not been run.

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
  nested, extra; broken JSON). A malformed message is dropped, counted and
  changes nothing; nothing raises; a kept message holds only its schema's
  fields.
- `tests/coop/session_identity_log_test.lua`: the device identity store,
  random ids across processes, the host's log lines and log rotation.
- `tests/coop/session_dev_entry_test.lua`: the entry's arguments, addresses,
  and the moves a game's position becomes.
- `tests/coop/enet/` runs under LÖVE without a window (`love tests/coop/enet`),
  since plain luajit has no lua-enet:
  - a loopback seat and two ENet players on one host;
  - moves and a map change;
  - leaving by bye and by a dropped link, and rejoining;
  - protocol and cartridge refusals;
  - broken JSON and 2 MiB messages;
  - a dial with nobody listening;
  - the beacon on 127.0.0.1.

  It uses its own ports. `scripts/test.sh` runs it when `love` is on PATH,
  and coop-ci has a job that installs LÖVE for it.
