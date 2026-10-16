# Friend battles and trades

Two players of a campaign battle each other or trade Pokémon where they
stand (#23, area A12.1 to A12.6 in [design.md](design.md), decision G31,
proposed), from the CO-OP menu's BATTLE and TRADE rows or by talking to
the partner (#34, A14.8). The Cable Club's trades and the Colosseum
(A12.7 to A12.9) are #60.

## How it runs (G31)

A friend battle is **upstream's lockstep link battle**
(`src/link/LinkBattle.lua`), not a co-op battle record (G24). Each window
runs the whole battle from its own side, as two Game Boys on a cable do:
the same seed, both parties packed and rebuilt the same way, each side's
move sent to the other, a state digest compared every turn. What changes
is the cable: the link battle's messages ride the co-op session
(`src/coop/friends/Relay.lua`), and the host passes them from one window
to the other. The host deals the seed and runs nothing.

Why not the co-op battle record: G24's record runs the game's battle with
every player on the allied side against an enemy the opener's world
prepared; the enemy's moves are its AI's. A friend battle needs a second
human side, a mirrored view, a replacement and a RUN for each side, and no
reward. Upstream's link battle already has all of it, uses the
cartridge's own battle screen, and keeps the real teams untouched (the
battle fights copies). Its LAN screens (`src/link/LinkState.lua`'s menus)
are not used, and nothing here calls the launcher's ONLINE screens.

A direct trade uses **upstream's link trade screen** for what it shows
(`LinkState.lua`'s "trade" stage: the two lists, STATS / TRADE, CANCEL,
"Waiting...!"), with the host in the middle instead of a cable: each window
sends its team, its offer and its TRADE to the host, which commits the
swap once. The swap core is `src/coop/campaign/Trade.lua`.

## Files

- `src/coop/friends/HostFriends.lua`: the host's side: invitations,
  pairings, the link battle's messages, a trade's offers and its commit.
- `src/coop/friends/Relay.lua`: a window's link cable over the session.
- `src/coop/friends/FriendBattle.lua`: a window's friend battle: the
  waiting box, the co-op rules on the link battle, the heal and the EXP
  after.
- `src/coop/friends/TradeScreen.lua`: a window's trade screen, the swap on
  its own team, the movie and the trade evolution.
- `src/coop/campaign/Trade.lua`: the swap core (below).
- `src/coop/game/Friends.lua`: the running game: talking to a partner, the
  CO-OP menu's rows, the invited player's question, opening a pairing.

Upstream files, with marked hooks (`co-op (#23)`):

- `src/world/OverworldController.lua` (`OverworldState:interact`): A on a
  partner asks `Friends.talk` first.

The fork's own files: `Host.lua` (handlers, `meeting` in `state`, the swap
laid over a world or holdings), `Client.lua`, `Protocol.lua`,
`Session.lua` (`Friends.step` every joined frame), `CoopMenu.lua`,
`Presence.lua` and `Battles.lua` (VS <foe>, #34), `German.lua`, and
`tools/game_strings.lua` (it reads `src/coop/friends`).

## Inviting (A12.1, A12.2)

- **Talking to a partner** (A on the partner standing in front) opens
  BATTLE / TRADE / CANCEL. A partner who is not free gets "BLUE is busy."
  instead.
- **START > CO-OP** lists BATTLE <NAME> and TRADE <NAME> for each free
  partner. The menu shows three rows and scrolls (a "more" arrow on its
  border); the session box above it got one line shorter for that.
- Either sends the invitation, and "Invitation sent." says so.
- **Free** means connected, past the opening, in no co-op battle (nor
  joining one) and in no other meeting. A player who is not free invites
  nobody; one in the opening, away from a co-op battle or meeting someone
  gets no rows. The host refuses an invitation to a partner who is away
  (`partner_away`), busy (`partner_busy`), or when either player is
  already in an invitation (`invite_pending`); the sender's notice says
  "BLUE is away." or "BLUE is busy.". A player whose own invitation still
  waits sends no second one: the notice says "Waiting for BLUE...".
- **The question** ("RED / wants to battle!", "RED / wants to trade!", then
  the cartridge's YES / NO) shows only at a rest point (the shared world's,
  [world.md](world.md)) with the overworld on top: no menu, text box,
  script, battle or warp. NO, B on the YES / NO, or 30 seconds after the
  question showed decline. An invitation the host settled meanwhile
  (expired, the sender left) closes the question.
- **The host** expires an invitation after 60 seconds (`timeout`), settles
  it `left` when either player leaves, and checks both players again on a
  YES (`busy` when either is no longer free). Both players hear how it
  ended; the sender's notice says "BLUE declined.", "BLUE did not
  answer.", "BLUE is busy." or "BLUE left.".
- **The pairing**: a YES pairs the two. Each window opens the battle or the
  trade screen at its next rest point, where the player stands. `state`
  names each player's `meeting` (`battle`, `trade`), and the CO-OP box shows
  a partner meeting someone as IN A BATTLE or TRADING.

## Friend battle (A12.3 to A12.5)

- The waiting box ("Waiting for BLUE...") stands over the map while the two
  windows exchange the link session's hello (both games and their mods are
  checked as upstream's link does; a mismatch says "Link battle needs the
  same version and mods.") and each party. B on it calls the battle off
  for both. Then the battle comes in behind the battle transition.
- **Mirrored**: each window's own team is its side; each player picks
  their own moves, switches and replacements. Locked-in turns, a forced
  replacement after a faint and a double faint are the link battle's own.
- **Private**: no co-op battle is opened, nobody else can join or see it,
  and no notice tells the others.
- **RUN forfeits**: the player who runs loses ("RED forfeited the
  match!"), the partner wins.
- **No items** ("Items can't be used in a link battle!"), no money (Pay
  Day pays nothing), no prize, no story, no whiteout: a loss goes back to
  the map behind the fade like any other end.
- **A dropped partner** (A12.4): the battle waits for their turn, and the
  other player cannot answer for them. Their window keeps its battle and,
  back on a new link, sends what it sent again from the first message (the
  host keeps the ones it has not had) and hears the partner's again (it
  keeps the ones it has not had), so the battle goes on. After two minutes
  away the host releases the pairing and the other window's battle ends
  ("BLUE left the battle.") as a draw. A player who leaves the session on
  purpose ends it at once.
- **Afterwards** (A12.5): the team is healed where it stands (HP, PP,
  status); the battle never touched it. Each Pokémon then gets the full
  trainer-battle EXP and stat EXP of every distinct opposing Pokémon it
  stood against (both out with HP left at the same time), won or lost,
  not split among the team, with a traded Pokémon's boost: the
  cartridge's "gained ... EXP. Points!" and "grew to level" lines over the
  map, a move learned at each level (the forget list when it knows four),
  and the evolutions of the Pokémon that grew. A released battle pays the
  same. **The side that forfeits gets no EXP** (G36, #67): the player who
  ran is healed and nothing more, so starting and forfeiting friend
  battles farms nothing; the partner who did not run is paid as above.

## Direct trade (A12.6)

- Both windows show the trade screen where they stand: this player's team
  on top, the partner's below. A on a row offers STATS / TRADE; STATS
  shows its pages (the partner's too); TRADE offers it. Once both offered,
  "TRADE KADABRA / for GRAVELER?" asks; A says TRADE, B cancels.
- **Once**: two TRADEs make the host commit the trade
  (`trade:<pair>`, an exactly-once commit, [campaign.md](campaign.md)).
  It swaps the two rows in both players' worlds in the campaign; each
  window then swaps its own team (the rows keep their uids and original
  trainers), sets the Pokédex, writes its save (a `link` save, as the
  Cable Club saves before its movie), plays the trade movie, "Trade
  completed!", and a trade evolution (KADABRA, MACHOKE, GRAVELER, HAUNTER;
  it cannot be cancelled), then saves again. One trade per pairing; both
  are back on the map.
- **The window stays the writer** of its holdings (G25): the commit owes
  each player their side of the trade (kept in the campaign file, G37).
  Until a player's window sends a world or holdings that shows the swap,
  the host lays the swap over every one it sends, so a copy sent before
  the window applied it cannot undo it or clone a row. The window's later
  copy wins (its evolution, for example).
- **A done that never reached a window** (#63, G37): a window whose link
  dropped after the commit, before it heard the trade was done, gets the
  trade it is owed from the host on its new link (`trades`) and applies
  it at its next rest point: the row it gave leaves, the row it gets
  takes its place with its uid, the Pokédex marks it, "Trade completed!
  RED received KADABRA!" over the map, a trade evolution, and a `link`
  save. No movie: the trade is over. A window that applied the trade on
  its screen changes nothing.
- **CANCEL** (below the party), B before TRADE, or the partner's cancel:
  both screens close ("The trade was cancelled."), nothing traded. A
  disconnect before the commit ends it the same way ("The link was
  broken."). A window that comes back to a committed trade it never
  showed lands it as above.

## The trade core (`src/coop/campaign/Trade.lua`)

The one core for direct trades and the Cable Club's ([cable.md](cable.md);
#62, G37):

| Call | Does |
|---|---|
| `Trade.encodeTeam(party)` | the team's rows (at most six) as the game's save text |
| `Trade.decodeTeam(text)` | the rows back, checked for a team's shape; nil and why otherwise |
| `Trade.find(list, row)` | where `row` stands in a team or box: by its uid, else by fingerprint, species and level |
| `Trade.swap(save, give, get)` | one side of a trade on a save table (a window's live save or the host's copy of a world): `give` leaves the team and a copy of `get` takes its slot, marked `traded`. Returns `"swapped"` (and the slot), `"already"` (the save holds `get`, not `give`), or nil and `"gone"`. Idempotent. |
| `Trade.evolution(data, mon)` | the species a trade evolves `mon` into, or nil |
| `Trade.copy(v)` | a deep copy |
| `Trade.commit(campaign, id, a, b)` | the host: the trade once under a commit id (`trade:<pair>`, `cable:<pair>:<n>`); `a`, `b` are `{ player, give }` with the row each gives. Both stored worlds swap (a world that does not hold the row yet gets it laid over when it comes), the receivers' Pokédexes mark it, and each player is owed their side. Returns true; false, `"done"` on a repeat; false, `"unswapped"` when a row is unknown (nothing moved or owed). |
| `Trade.layOver(campaign, id, save)` | the host, on every world or holdings a window sends: each owed trade is laid over it; one the save shows already ends. Returns the ended ones (`trade_shown` in the log). |
| `Trade.owed(campaign, id)` | the trades a player is owed: `{ id, give, get }` |
| `Trade.key(packed)`, `Trade.rowOf(campaign, id, uid)`, `Trade.uidOf(campaign, id, packed)` | the Cable Club's packed rows: what tells one from another on the cable, a stored row by its uid, the uid of the stored row a packed one was made from |

Who writes what, for both kinds (G25, G37): the host commits once and
owes each side; each window applies its own side on its own save (on its
trade screen when it hears the yes, else at its next rest point from what
it is owed); the host lays an owed trade over every world or holdings
until one shows it. `Trade.swap` finds the row given in the team, else
in the PC (a row deposited before an owed trade landed).

Rows are whole save rows, so a received Pokémon arrives exactly as its
owner held it: uid, original trainer and id, DVs, stat EXP, moves, PP Ups,
nickname.

## Protocol 15

| Client to host | Fields |
|---|---|
| `invite` | `seq`, `to` (a player), `kind` (`battle`, `trade`) |
| `invite_answer` | `seq`, `invite`, `yes` |
| `pair_msg` | `seq`, `pair`, `n` (this window's message number in the pairing), `msg` (one link battle message: plain data with a `type`) |
| `pair_end` | `seq`, `pair`, `result` (`win`, `lose`, `draw`, `forfeit`, `cancel`, `done`): this window's side is over |
| `trade_team` | `seq`, `pair`, `team` (the rows as save text, at most 64 KB) |
| `trade_pick` | `seq`, `pair`, `slot` (1 to 6) |
| `trade_confirm` | `seq`, `pair`, `yes` (TRADE, or CANCEL) |

| Host to client | Fields |
|---|---|
| `invite` | `id`, `from`, `to`, `kind`, and once settled `answer` (`accepted`, `declined`, `timeout`, `busy`, `left`) |
| `pair` | `id`, `kind`, `partner`, `role` (`host` for the inviter, `guest`), `seed`, and `name` (the partner's), `away` (the partner's link is down), `ended` (`released`, `left`, `cancel`); a trade's `mine`, `theirs` (teams), `myPick`, `theirPick`, `confirmed`, `theirConfirmed`, `done` (committed) |
| `pair_msg` | `pair`, `n`, `msg`: the partner's link battle messages, in order, again from the first on a new link |
| `state` | each player's `meeting` (`battle`, `trade`) |
| `trades` (protocol 18, #63) | `list` of `{ id, give, get }` (the commit id, the row given and the row received, each as save text): the trades this player is owed, once per link |

Refusals (`rejected`): `no_partner`, `partner_away`, `partner_busy`,
`invite_pending`, `in_battle` (the sender is not free), `no_invite`,
`no_pair`, `bad_team`, `bad_pick`. The host's session log has `invite`,
`invite_answer`, `pair`, `pair_side`, `pair_end`, `trade` and
`trade_shown` lines.

## Checked

Run on Linux desktop (LÖVE 11.5), US Red, two game processes on one
machine, offscreen, each with its own save folder and a frame driver; RED
hosts, GREEN joins over ENet. RED had PIDGEY L50 and KADABRA L30, GREEN
RATTATA L20 and GRAVELER L25; the drivers pressed the buttons:

- RED pressed A facing GREEN: BATTLE / TRADE / CANCEL. BATTLE: "Invitation
  sent."; GREEN's question came up on the map, B on its YES / NO declined,
  and RED's notice read "GREEN declined.".
- RED's CO-OP menu (SELECT) listed BATTLE GREEN, TRADE GREEN, TOWN MAP and
  scrolled; BATTLE GREEN, and GREEN's YES: both windows showed the waiting
  box, then the link battle, RED's PIDGEY against GREEN's RATTATA in RED's
  window and the other way round in GREEN's, "GREEN wants to fight!". The
  battle ran to its end (RED lost and GREEN won in both of two runs, after
  23 and 25 turns: PIDGEY's first move is WHIRLWIND). Afterwards RED's
  team was at full HP; PIDGEY and KADABRA each got 243 EXP (RATTATA L20's
  full trainer award each), GREEN's RATTATA got 1519 (PIDGEY's and
  KADABRA's), grew to level 21 and evolved into RATICATE; GRAVELER, which
  never came out, got none.
- RED talked to GREEN, TRADE; GREEN said YES; both trade screens listed
  both teams; each offered its second Pokémon, "TRADE KADABRA / for
  GRAVELER?", both said TRADE. The host committed `trade:<pair>` once;
  GREEN's window played the trade movie (GRAVELER, OT/GREEN). RED ended
  with GOLEM (GREEN's uid, OT GREEN), GREEN with ALAKAZAM (RED's uid, OT
  RED): both evolved by trade. The host's copies of both worlds held the
  same, and its log showed each window's world showing the swap.
- The host's session log showed no `battle_desync`. The first run also
  showed each window's TRADE sent twice (the driver kept pressing A) and
  refused as `no_pair` after the commit, harmless; the screen now sends
  its offer and its TRADE once, and the second run had no refusal.

**The integrated build** (Group 11, 2026-10-16; Linux desktop, LÖVE 11.5,
US Red, two ENet processes offscreen at `POKEPORT_SPEED=4`, each driving
its own launcher: ASH hosted NEW CAMPAIGN and MISTY joined BY ADDRESS, both
with BRING A SAVE of a solo save in the Viridian Pokémon Center with
KADABRA, GRAVELER, MACHOKE, HAUNTER, WARTORTLE and PIDGEOTTO at level 20;
58 driver checks, none failed; no `battle_desync`):

- A on MISTY: BATTLE / TRADE / CANCEL, CANCEL back on the map. TRADE:
  MISTY's NO, then the CO-OP menu's BATTLE MISTY and MISTY's B, each "MISTY
  declined."; a third invitation left unanswered closed itself after 30 s
  ("MISTY declined.") while MISTY's window had lost focus for 8 s, and her
  link stayed up.
- A friend battle to the end (61 command menus), each window losing focus
  for 5 or 6 s in it: both teams healed, EXP to every Pokémon that stood
  out (all six of ASH's, four of MISTY's, some to level 21), money
  unchanged.
  MISTY's RUN in the next battle: "MISTY forfeited the match!", ASH won.
- TRADE: KADABRA for GRAVELER, MISTY's window losing focus for 6 s on the
  lists and its visibility for 6 s at the question, ASH's visibility for
  5 s at the question: "Trade completed!", ALAKAZAM and GOLEM, each with
  the other player's uid. After both SAVEd the host's worlds held the same.
  CANCEL on MISTY's lists: "The trade was cancelled." on both, nothing
  moved. MISTY quit and came back with REJOIN on PLAY: her world from the
  host had ALAKAZAM with ASH's uid and no GRAVELER.

Not run with the cartridge: a dropped link during a friend battle and the
two-minute release, the 30-second answer, a busy partner, a move learned
or a forget list after a friend battle, CANCEL on the trade screen, a
disconnect before the swap (the ROM-free tests cover them),
three players, split-screen, Blue and Yellow, German games, real pads.

## Tests

ROM-free, in the co-op tier (`luajit tests/run_coop.lua`):

- `tests/coop/friends_host_test.lua`: the host's rules over loopback:
  invitations (oneself, the opening, pending, NO, a settled one, the 60 s
  expiry, the recheck on YES, a player who leaves), `meeting` in `state`,
  privacy (no co-op battle), the relay in order and once, again from the
  first on a new link, a partner away and back, the release after two
  minutes heard on return, both sides finishing, a window with no battle
  ending it, a trade's teams, offers and TRADEs, the commit once with uids,
  laid over both worlds and a stale copy until the window shows it,
  CANCEL and a drop before the commit.
- `tests/coop/friends_battle_test.lua`: two windows' link battles over the
  session: mirrored, one outcome, no desync, the real teams untouched, no
  money, the heal, the full EXP and stat EXP per foe won or lost, RUN
  forfeiting, a partner's drop waited for and the battle going on, the
  release as a draw, B on the waiting box.
- `tests/coop/friends_trade_test.lua`: the swap core (text and back, find
  by uid and fingerprint, the swap once, the evolution), and two windows'
  trade screens: both offer and say TRADE, the commit, uids and original
  trainers kept, the Pokédex, a trade evolution keeping its uid; CANCEL,
  B, and a drop.
- `tests/coop/friends_game_test.lua`: the fixture overworld: nothing solo,
  A on the partner, the CO-OP rows, the question only at a rest point, B
  and 30 s declining, the waiting box after YES and B calling it off, a
  busy partner.
- `tests/coop/presence_test.lua` and `battle_game_test.lua`: the new rows
  and VS <foe>.
