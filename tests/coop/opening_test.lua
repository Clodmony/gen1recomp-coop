-- New players and the opening (#22, design A4.4 to A4.8), ROM-free: a
-- window whose player has no starter yet plays the opening on a private
-- story (it sends and takes nothing of the campaign's); the opening ends at
-- a rest point once the player has a starter and stands outside Oak's lab,
-- and the window then takes the campaign's story, or seeds a campaign that
-- has none (A4.7); the first rival name and the first finished starter
-- choice become the campaign's (A4.5, A4.6); the host says who is in the
-- opening.  Host and clients in one process over loopback.
--   luajit tests/coop/opening_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq
local F = require("tests.coop.support.campaign_fixture")
local Transport = require("src.coop.session.Transport")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local Protocol = require("src.coop.session.Protocol")
local Campaign = require("src.coop.campaign.Campaign")
local CampaignFile = require("src.coop.campaign.CampaignFile")
local Window = require("src.coop.campaign.Window")

local SHA = ("ab"):rep(20)
local CID = "c0123456789abcdef"

local clock = 0
local function now() return clock end
local ids = 0
local function hex(n)
  ids = ids + 1
  return ("%0" .. n .. "x"):format(ids)
end

local function startHost(opts)
  local c = Campaign.new({ id = CID, title = "KANTO", game = "red", sha1 = SHA,
                           rival = opts and opts.rival })
  local host = Host.new({ campaign = { id = CID, title = "KANTO" },
                          cartridge = { game = "red", sha1 = SHA }, clock = now, hex = hex,
                          state = c, build = "test" })
  return host, host:serve(Transport.loopback())
end

-- a window on a new game: no starter, in the bedroom
local function newcomer(hub, name, device)
  local c = Client.new(hub:dial(), { name = name, game = "red", sha1 = SHA, build = "test",
                                     device = device, clock = now })
  c:join()
  local save = F.save(name, { party = {}, flags = {}, map = "REDS_HOUSE_2F" })
  local x = { c = c, w = Window.new(c), save = save, map = "REDS_HOUSE_2F", busy = nil,
              sent = {} }
  local send = c.send
  c.send = function(self, msg)
    x.sent[#x.sent + 1] = msg.type
    return send(self, msg)
  end
  return x
end

local function count(x, kind)
  local n = 0
  for _, t in ipairs(x.sent) do if t == kind then n = n + 1 end end
  return n
end

local function pump(host, wins, frames)
  for _ = 1, frames or 4 do
    clock = clock + 1 / 60
    for _, x in ipairs(wins) do x.c:update() end
    host:update()
    for _, x in ipairs(wins) do
      x.c:update()
      x.w:update({ save = x.save, busy = x.busy, map = x.map, still = true })
    end
  end
end

local function view(x, id)
  return x.c:playerView(id or x.c.player) or {}
end

-- the opening a played run leaves in the lab (Red's, as story2.lua and
-- oaks_lab.lua set it), with this player's starter
local function playOpening(x, starter)
  local s = x.save
  s.flags.EVENT_FOLLOWED_OAK_INTO_LAB = true
  s.flags.EVENT_FOLLOWED_OAK_INTO_LAB_2 = true
  s.flags.EVENT_OAK_ASKED_TO_CHOOSE_MON = true
  s.objectToggles = { PALLET_TOWN = { PALLETTOWN_OAK = false },
                      OAKS_LAB = { OAKSLAB_OAK2 = false, OAKSLAB_OAK1 = true,
                                   OAKSLAB_RIVAL = false } }
  s.objectToggles.OAKS_LAB["OAKSLAB_" .. starter .. "_POKE_BALL"] = false
  s.party = { F.mon(starter, 5) }
  s.flags.EVENT_GOT_STARTER = true
  s.flags["EVENT_CHOSE_" .. starter] = true
  s.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  x.map = "OAKS_LAB"
  s.player.map = "OAKS_LAB"
end

local function leaveLab(x)
  x.map = "PALLET_TOWN"
  x.save.player.map = "PALLET_TOWN"
end

-- a private opening (A4.4) and the seed of a new campaign (A4.7) ------------------
do
  local host, hub = startHost()
  local red = newcomer(hub, "RED", "d1")
  pump(host, { red }, 8)
  eq(red.c.status, "joined", "RED joined")
  local pid = red.c.player
  eq(red.w.opening, true, "a player with no starter is in the opening")
  check(view(red).opening, "the host says RED is in the opening (A4.8)")
  eq(host.state:player(pid).opening, nil, "the opening is the session's, not the file's")

  playOpening(red, "SQUIRTLE")
  pump(host, { red }, 8)
  eq(count(red, "patch"), 0, "the opening's story stays in the window (A4.4)")
  eq(count(red, "holdings"), 0, "and so does the team")
  eq(next(host.state.story), nil, "the campaign has no story yet")
  eq(host.state:player(pid).world, nil, "nor a world for RED (A4.9)")
  eq(red.w.opening, true, "a starter in the lab is still the opening")

  red.busy = "map_load"
  leaveLab(red)
  pump(host, { red }, 4)
  eq(red.w.opening, true, "the opening ends at a rest point, not while held")
  red.busy = nil
  pump(host, { red }, 12)
  eq(red.w.opening, false, "outside the lab with a starter, the opening is over")
  check(not view(red).opening, "the host knows")
  eq(host.state.story["flags/EVENT_BATTLED_RIVAL_IN_OAKS_LAB"], true,
     "the first finished opening seeds the campaign's story (A4.7)")
  eq(host.state.story["objectToggles/OAKS_LAB/OAKSLAB_OAK1"], true, "Oak waits in the lab")
  eq(host.state.story["flags/EVENT_GOT_STARTER"], nil, "the starter stays RED's own")
  check(host.state:player(pid).world ~= nil, "the host has RED's world once the opening ends")
  eq(host.state.chose, "SQUIRTLE", "the first finisher's starter is the campaign's (A4.6)")
  eq(red.c.state and red.c.state.chose, "SQUIRTLE", "and every window hears it")

  -- a second player: their own Oak, rival and balls (A4.4)
  local blue = newcomer(hub, "BLUE", "d2")
  pump(host, { red, blue }, 10)
  local bid = blue.c.player
  eq(blue.w.opening, true, "BLUE starts in the opening")
  check(view(red, bid).opening, "RED's window sees BLUE in the opening")
  eq(blue.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB, nil,
     "the campaign's story does not reach the opening")
  eq(blue.save.objectToggles, nil, "nor the campaign's lab")

  -- a partner's change meanwhile reaches the campaign, not BLUE
  red.save.flags.EVENT_GOT_POKEDEX = true
  pump(host, { red, blue }, 8)
  eq(host.state.story["flags/EVENT_GOT_POKEDEX"], true, "RED's change reached the campaign")
  eq(blue.save.flags.EVENT_GOT_POKEDEX, nil, "BLUE's opening does not take it")

  playOpening(blue, "SQUIRTLE")
  blue.save.flags.EVENT_SOMETHING_PRIVATE = true
  pump(host, { red, blue }, 8)
  eq(count(blue, "patch"), 0, "BLUE's opening sends nothing")
  leaveLab(blue)
  pump(host, { red, blue }, 12)
  eq(blue.w.opening, false, "BLUE's opening is over")
  eq(blue.save.flags.EVENT_GOT_POKEDEX, true, "BLUE takes the campaign's story")
  eq(blue.save.flags.EVENT_SOMETHING_PRIVATE, nil, "the opening's own entries are dropped")
  eq(blue.save.flags.EVENT_CHOSE_SQUIRTLE, true, "BLUE keeps their own starter's flags")
  eq(blue.save.party[1] and blue.save.party[1].species, "SQUIRTLE", "and their starter")
  eq(host.state.story["flags/EVENT_SOMETHING_PRIVATE"], nil, "nothing of it reached the campaign")
  eq(host.state.chose, "SQUIRTLE", "the second finisher does not change the rival's starter")
end

-- a new player who starts in Pallet or brings a save is not "in the opening"
-- when they join (found in the integrated build's live run: the join notice
-- said "joined the session in the opening") ----------------------------------
do
  local host, hub = startHost()
  local c = Client.new(hub:dial(), { name = "MISTY", game = "red", sha1 = SHA, build = "test",
                                     device = "d7", clock = now, start = "pallet" })
  c:join()
  local watcher = Client.new(hub:dial(), { name = "BROCK", game = "red", sha1 = SHA,
                                           build = "test", device = "d8", clock = now })
  watcher:join()
  for _ = 1, 6 do
    clock = clock + 1 / 60
    c:update(); watcher:update(); host:update(); c:update(); watcher:update()
  end
  eq(c.status, "joined", "MISTY joined")
  check(not (watcher:playerView(c.player) or {}).opening,
        "a player who chose START IN PALLET is not announced in the opening")
  check((c:playerView(watcher.player) or {}).opening,
        "one who chose nothing (the opening) still is")
  local bad = Protocol.sanitize({ type = "hello", protocol = Protocol.VERSION, build = "t",
                                  name = "X", game = "red", sha1 = SHA, device = "d9", seat = 1,
                                  start = "nowhere" }, "host")
  eq(bad, nil, "an unknown start is dropped whole")
end

-- a returning player is never in the opening ------------------------------------
do
  local host, hub = startHost()
  local c = Client.new(hub:dial(), { name = "RED", game = "red", sha1 = SHA, build = "test",
                                     device = "d1", clock = now })
  c:join()
  local x = { c = c, w = Window.new(c), save = F.save("RED", { map = "OAKS_LAB" }),
              map = "OAKS_LAB", sent = {} }
  pump(host, { x }, 8)
  eq(x.w.opening, false, "a world with a starter is past the opening, even in the lab")
  check(not view(x).opening, "the host agrees")

  -- a new link tells the host again: a host without this player's world
  -- marks them in the opening when they come back
  host.state:player(x.c.player).world = nil
  x.c.conn:close()
  local c2 = Client.new(hub:dial(), { name = "RED", game = "red", sha1 = SHA, build = "test",
                                      device = "d1", clock = now, known = x.c.known })
  c2:join()
  x.c, x.w.client = c2, c2
  pump(host, { x }, 8)
  eq(c2.status, "joined", "back in")
  check(not view(x).opening, "the window says again it is past the opening")
end

-- the rival's name (A4.5) --------------------------------------------------------
do
  local host, hub = startHost()
  local red = newcomer(hub, "RED", "d1")
  local blue = newcomer(hub, "BLUE", "d2")
  pump(host, { red, blue }, 8)
  eq(red.c.state and red.c.state.rival, nil, "nobody named the rival yet")
  red.w:named("GARY")
  pump(host, { red, blue }, 4)
  eq(host.state.rival, "GARY", "the first to name him names him")
  eq(blue.c.state and blue.c.state.rival, "GARY", "for everyone")
  blue.w:named("JOHN")
  pump(host, { red, blue }, 4)
  eq(host.state.rival, "GARY", "a later name does not replace him")

  -- after the opening the window's rival is the campaign's
  blue.save.player.rival = "JOHN"
  playOpening(blue, "BULBASAUR")
  leaveLab(blue)
  pump(host, { red, blue }, 12)
  eq(blue.w.opening, false, "BLUE's opening is over")
  eq(blue.save.player.rival, "GARY", "BLUE's rival takes the campaign's name")
end

-- the host names the rival when it creates the campaign ---------------------------
do
  local host, hub = startHost({ rival = "BLUE" })
  local red = newcomer(hub, "RED", "d1")
  pump(host, { red }, 8)
  eq(red.c.state and red.c.state.rival, "BLUE", "the host's name is the campaign's from the start")
  red.w:named("GARY")
  pump(host, { red }, 4)
  eq(host.state.rival, "BLUE", "and stays")
end

-- the campaign file keeps the rival (A4.5, A4.6) ---------------------------------
do
  local c = Campaign.new({ id = CID, title = "T", game = "red", rival = "GARY" })
  c.chose = "CHARMANDER"
  local back = Campaign.fromSnapshot(c:snapshot())
  eq(back and back.rival, "GARY", "the rival's name survives the file")
  eq(back and back.chose, "CHARMANDER", "and the starter he counters")
  local odd = c:snapshot()
  odd.campaign.rival = "<script>alert(1)</script>"
  odd.campaign.chose = "MEWTWO"
  local bad = Campaign.fromSnapshot(odd)
  eq(bad and bad.rival, nil, "a name the protocol would refuse is dropped")
  eq(bad and bad.chose, nil, "so is a starter that is none")
  check(CampaignFile.VERSION >= 4, "the file's version moved with the rival")
end

-- the protocol checks what the opening carries ------------------------------------
do
  local ok = Protocol.sanitize({ type = "opening", seq = 1, done = true, chose = "SQUIRTLE" }, "host")
  check(ok ~= nil, "an opening message passes")
  local bad = Protocol.sanitize({ type = "opening", seq = 1, done = true, chose = "MEW" }, "host")
  eq(bad, nil, "a starter that is none is dropped whole")
  local named = Protocol.sanitize({ type = "opening", seq = 2, done = false, rival = "GARY" }, "host")
  eq(named and named.rival, "GARY", "a rival's name passes")
end

T.finish()
