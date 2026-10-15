# The Cable Club

Trades and link battles at a Pokémon Center's Cable Club in a co-op
session (#60, design A12.7 to A12.9 and A14.4, decision G32). The session
is the link cable; a solo game keeps upstream's LAN link menu.

## Files

- `src/coop/game/CableClub.lua`: the window. The receptionist's link
  menu, the transport that carries upstream's link messages over the
  session (`CableClub.Cable`), the uid of a received Pokémon, and the
  continue position.
- `src/coop/session/HostCable.lua`: the host. Who a player's cable
  reaches, passing link messages to the mate, the trade's yes held until
  both said it, and the 30 s and 60 s waits.
- `src/coop/campaign/CableTrade.lua`: the swap on the campaign, once per
  commit id, uids kept. A direct trade (#23) can share it: two
  `{ player, uid }` and a stable commit id.

Upstream files have one marked hook each (`co-op (#60)`):

- `src/world/OverworldController.lua` (`cableClubReceptionist`): after
  her save (now of kind `link`), `CableClub.open` takes the Cable Club in
  a co-op world; otherwise upstream's `LinkState` opens as before.
- `src/link/LinkState.lua`: `newFromSession` takes `opts.onTraded`, called
  with the received Pokémon right after the trade lands and before the
  save that follows.
- `src/core/Game.lua` (`restoreSave`): `CableClub.settle` after
  upstream's `UnionSafety.settle`.

## How it plays

Upstream's Gen 1 Cable Club has no rooms to walk into: the receptionist
saves and opens a LAN link menu (HOST/JOIN by address), and the paired
games run the cartridge's trade screen or link battle
(`src/link/LinkState.lua`, `Protocol.TradeSession`, `LinkBattle`). With
the Union Room setting on, her desk is on the added 2F; off, it is on 1F.
Both reach the same code (G6).

In a co-op world:

1. The receptionist welcomes, asks to apply, saves (a real SAVE that
   reaches the host), then opens the cartridge's own link menu: TRADE
   CENTER, COLOSSEUM, CANCEL, with "Where would you like to go?" (pokered
   `LinkMenu`, its labels read from the cartridge). CANCEL or B ends with
   "Please come again!".
2. A room sends `cable` to the host. Waiting shows "Please wait.", or the
   cartridge's "This area is reserved for 2 friends who are linked by
   cable." when two others already hold that room. B leaves the room.
3. Once the host pairs the player, upstream's `LinkState` runs adopted
   (`newFromSession`) over `CableClub.Cable`: the hellos, the trade
   screen, the link battle, all as upstream draws them. The lower player
   id leads (it deals the battle's seed).
4. When that screen closes (CANCEL, the battle over, the mate gone) the
   player leaves the room and the menu shows again.

## Rules

| Rule | Here |
|---|---|
| A12.7 the partner | An offer either side made (`cable`'s `with`; a player who offered the cable to a partner who is connected and free waits for them), then the room's waiting players in id order, two by two. A pair is kept while both stay; a third player waits without a cable. Rooms never mix, so "the first other free player" has no counterpart (G32). Nothing in the game sends `with` yet: it is the place for #23's invitations. |
| A12.7 swapped once | The host reads the trade's `party` (with each Pokémon's uid; a row without one is found in the stored team by its packed content), `pick` and `confirm`. A yes is held until both said yes after both offers. Then `CableTrade.swap` moves the two rows between the stored teams once (commit `cable:<pair>:<n>`, uids kept, the receiver's Pokédex marked), the host saves, and only then each window hears the other's yes with the uid it receives. A mate who dropped before that trades nothing. |
| A12.7 each window's copy | The window applies the trade as upstream does, stamps the received row with the host's uid (`onTraded`), plays the movie and any trade evolution, and its own save after the trade reaches the host. Its holdings were held meanwhile (anything above the map holds the player). |
| A12.7 partners hidden | A player in a room is named in `state` (`cable`); the others do not draw them (Presence.lua). |
| A12.7 30 s and 60 s | No second offer within 30 s of the first, or no answer within 60 s of both offers: the host moves the trade's round on, both screens start the round over at their lists (`LinkState:beginRound`), and messages of the old round are dropped (`stale`). |
| A12.7 the desk | Either desk (1F with the Union Room off, 2F with it on) opens the same menu (G6). |
| A12.8 the continue position | The rooms' maps are never entered here. A save made in one (a cartridge's save after a link trade) opens before the nurse of the Pokémon Center its last outdoor map leads into, facing up: where upstream already puts a save made in its added rooms (`UnionSafety`). It applies to any save the game opens, solo too, since neither room has a way out. |
| A12.9 the Colosseum | Upstream's link battle (`LinkBattle`), each window against a copy of the mate's team from the lead's seed; the real teams take nothing from it, and nothing reaches the campaign. |

## Protocol (11)

| Client to host | Fields |
|---|---|
| `cable` | `seq`, `room` (`trade`, `colosseum`, `none`), `with` (optional) |
| `cable_link` | `seq`, `round`, `link` (one of upstream's link messages: `hello`, `records`, `party`, `pick`, `confirm`, `action`, `hash`, `replace`, `bye`, `forfeit`, kept as `src/link/Wire.lua` sanitizes it), `uids` (optional) |

| Host to client | Fields |
|---|---|
| `cable` | `room`, `round`, and once paired `mate`, `name`, `lead` |
| `cable_link` | `round`, `link`, `uid` (with the trade's last yes) |

`state` names each player's room (`cable`). A `cable_link` from a player
without a cable is refused `no_cable`, one of another round `stale`.

## Checked

Run on Linux desktop (LÖVE 11.5), US Red, two ENet game processes on one
machine, offscreen, each with its own save folder: RED hosting with the
Union Room setting on (the desk on 2F), GREEN joining with it off (the
desk on 1F of the Viridian Pokémon Center).

- Both talked to their receptionist, answered YES, and the link menu
  opened; both chose TRADE CENTER and the trade screen showed both
  parties.
- RED offered KADABRA, GREEN MACHOKE, both said yes. The host committed
  one `cable:` trade. RED's window got MACHOKE and saw it evolve into
  MACHAMP, GREEN's got KADABRA and saw ALAKAZAM; each received row kept
  its uid from the other player, with the other player as its trainer.
  The host's worlds showed the same, the second Pokémon of each team
  untouched.
- The trade screen started its next round; RED left with B, GREEN's
  screen closed on the bye; both went back to the link menu, then CANCEL
  and "Please come again!" back on the map.
- COLOSSEUM, each with one Pokémon (RED's KADABRA, GREEN's MACHOKE):
  RED led; both windows ran the link battle to its end, RED's lost and
  GREEN's won, with no desync; both teams kept their full HP; both went
  back to the link menu and the map.
- The continue position, in a solo game (the same `restoreSave` a co-op
  window opens its world with): a save written with the player in the
  TRADE_CENTER and Viridian City as the last outdoor map continued in the
  VIRIDIAN_POKECENTER at (3, 3), before the nurse. The same save on the
  branch's base continued in the TRADE_CENTER, which has no way out.

Not run: a partner in a room seen from the same map (the two desks were
on different maps; the ROM-free test covers it), the 30 s and 60 s waits
(ROM-free test), three players, a dropped link during a trade, Blue and
Yellow, German games, other platforms.

## Tests

ROM-free, in `tests/coop/`:

- `cable_host_test.lua`: the partners (alone, mates, kept while both stay,
  a third without a cable, an offer first, rooms apart, a drop); link
  messages to the mate only, `no_cable`, `stale`; a trade swapped once on
  the host with uids kept, the yes held, the save; a repeated commit; the
  30 s and 60 s waits; no trade without both offers or with a mate gone;
  the Colosseum passing every message.
- `cable_game_test.lua`: the fixture overworld hosting a session with a
  partner on the loopback hub playing upstream's trade session: the solo
  receptionist's LAN menu; the co-op link menu; the trade screen over the
  session; the received Pokémon with its uid; the host's worlds swapped
  and committed once; the next round; the partner hidden in the room and
  drawn again after; leaving back to the menu; CANCEL; the continue
  position.
- `session_fuzz_test.lua` covers `cable` and `cable_link` both ways.
