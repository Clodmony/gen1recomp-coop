-- The shared world (#14, design A5): who owns each part of a world, the
-- campaign's story built from the windows' patches, the rest-point rule,
-- unconfirmed patches, the map a window stands on, opening a world like a
-- Continue, the walk flags a host drops, and a file from before #14 whose
-- worlds still carry the story.  Windows over plain save tables; host and
-- clients in one process over the loopback transport.  ROM-free.
--   luajit tests/coop/shared_world_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local F = require("tests.coop.support.campaign_fixture")
local Json = require("src.link.Json")
local Transport = require("src.coop.session.Transport")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local Protocol = require("src.coop.session.Protocol")
local World = require("src.coop.campaign.World")
local Campaign = require("src.coop.campaign.Campaign")
local CampaignFile = require("src.coop.campaign.CampaignFile")
local Ownership = require("src.coop.campaign.Ownership")
local Window = require("src.coop.campaign.Window")

local SHA = ("ab"):rep(20)
local CID = "c0123456789abcdef"

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- ownership (A5.1) ------------------------------------------------------------
do
  check(Ownership.owns("flags/EVENT_GOT_POKEDEX"), "a story flag is the campaign's")
  check(Ownership.owns("flags/EVENT_GAVE_GUARDS_DRINK"), "the gate drink is the campaign's (A5.14)")
  check(Ownership.owns("flags/EVENT_CINNABAR_GYM_GATE2_UNLOCKED"), "Cinnabar's quiz gates (A5.16)")
  check(Ownership.owns("flags/EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH1"), "Victory Road's switches (A5.17)")
  check(not Ownership.owns("flags/EVENT_SAFARI_GAME_OVER"), "the Safari game is the player's (A5.12)")
  check(not Ownership.owns("flags/EVENT_IN_PURIFIED_ZONE"), "the purified zone is the player's")
  check(not Ownership.owns("flags/EVENT_MANSION_SWITCH_ON"), "the Mansion switch is the player's")
  check(not Ownership.owns("flags/EVENT_GAVE_FOSSIL_TO_LAB"), "the fossil lab is the player's")
  check(not Ownership.owns("flags/EVENT_LANCES_ROOM_LOCK_DOOR"), "Lance's door lock is the player's")
  check(not Ownership.owns("flags/EVENT_AUTOWALKED_INTO_BRUNOS_ROOM"), "an Elite Four walk-in too")
  check(not Ownership.owns("flags/EVENT_GOT_LAPRAS"), "LAPRAS received is the player's (A5.15)")
  check(not Ownership.owns("flags/EVENT_GOT_EEVEE"), "a gift Pokémon's flag is the player's (A7.9)")
  check(Ownership.owns("objectToggles/ROUTE_1/ROUTE1_BALL"), "an object toggle is the campaign's")
  check(not Ownership.owns("objectToggles/FIGHTING_DOJO/FIGHTINGDOJO_HITMONLEE_POKE_BALL"),
        "a gift Pokémon's ball is the player's")
  check(Ownership.owns("defeatedTrainers/ROUTE_3_obj_4"), "a beaten trainer is the campaign's")
  check(Ownership.owns("itemsTaken/ROUTE_1_obj_2"), "an item ball picked up is the campaign's")
  check(not Ownership.owns("hiddenTaken/ROUTE_1_3_4"), "hidden items are the player's (A6.4)")
  check(Ownership.owns("inventory/BOULDERBADGE"), "a badge is the campaign's (A5.15)")
  check(not Ownership.owns("inventory/POTION"), "an item is the player's")
  check(Ownership.owns("trashPuzzle/first"), "Vermilion's trash-can locks are the campaign's (A5.10)")
  check(not Ownership.owns("money/x"), "money is the player's")
  check(not Ownership.owns("mystery/NEW_KEY"), "a key nobody classified is the player's")
  check(not Ownership.owns("flags/A/B"), "a path of the wrong depth is nobody's")
  check(not Ownership.owns("flags/../x"), "nor a path with dots in odd places")
  check(not Ownership.valid("flags/EVENT_X", false), "a flag holds only true")
  check(not Ownership.valid("inventory/BOULDERBADGE", 999), "a badge count stays small")
  check(Ownership.valid("objectToggles/MAP/OBJ", false), "an object toggle holds false (hidden)")

  local save = F.save("RED", { flags = { EVENT_GOT_STARTER = true, EVENT_GOT_POKEDEX = true,
                                         EVENT_SAFARI_GAME_OVER = true },
                               inventory = { POTION = 3, BOULDERBADGE = 1 } })
  save.objectToggles = { ROUTE_1 = { BALL = false },
                         FIGHTING_DOJO = { FIGHTINGDOJO_HITMONLEE_POKE_BALL = false } }
  save.defeatedTrainers = { ROUTE_3_obj_4 = true }
  save.hiddenTaken = { ROUTE_1_3_4 = true }
  save.trashPuzzle = { first = 4 }
  save.safari = { balls = 30, steps = 500 }
  local view = Ownership.view(save)
  eq(count(view), 5, "the campaign's entries of a world")
  eq(view["flags/EVENT_GOT_POKEDEX"], true, "the story flag")
  eq(view["objectToggles/ROUTE_1/BALL"], false, "the hidden ball")
  eq(view["inventory/BOULDERBADGE"], 1, "the badge")
  eq(view["trashPuzzle/first"], 4, "the trash can")
  eq(view["flags/EVENT_GOT_STARTER"], nil, "not the starter (the player's)")

  local stripped = Ownership.strip(World.decode(World.encode(save)))
  eq(count(Ownership.view(stripped)), 0, "a stripped world holds none of them")
  eq(stripped.inventory.POTION, 3, "but keeps the player's items")
  eq(stripped.inventory.BOULDERBADGE, nil, "without the badge")
  eq(stripped.objectToggles.FIGHTING_DOJO.FIGHTINGDOJO_HITMONLEE_POKE_BALL, false,
     "the player's own gift ball stays")
  eq(stripped.objectToggles.ROUTE_1, nil, "an emptied map's toggles go")
  eq(stripped.flags.EVENT_SAFARI_GAME_OVER, true, "the player's flags stay")
  eq(stripped.hiddenTaken.ROUTE_1_3_4, true, "and hidden items")

  Ownership.overlay(stripped, { ["flags/EVENT_BEAT_BROCK"] = true, ["inventory/BOULDERBADGE"] = 1 })
  eq(stripped.flags.EVENT_BEAT_BROCK, true, "the overlay writes the campaign's flags")
  eq(stripped.inventory.BOULDERBADGE, 1, "and badges")
  eq(stripped.flags.EVENT_GOT_POKEDEX, nil, "a world's own story entry gives way to the campaign's")

  Ownership.dropWalk(save)
  eq(save.flags.EVENT_SAFARI_GAME_OVER, nil, "walk flags dropped (A5.13)")
  eq(save.safari, nil, "and the Safari game")
  eq(save.flags.EVENT_GOT_POKEDEX, true, "not the story")

  local set, unset, n = Ownership.diff({ a = true, b = 1 }, { b = 2, c = true })
  eq(n, 3, "a diff counts each changed entry")
  eq(set.b, 2, "a changed value")
  eq(set.c, true, "a new entry")
  eq(unset[1], "a", "a cleared entry")

  eq(Ownership.mapOf("objectToggles/ROUTE_1/BALL"), "ROUTE_1", "an object's map")
  eq(Ownership.mapOf("defeatedTrainers/ROUTE_3_obj_4"), "ROUTE_3", "a trainer's map")
  eq(Ownership.mapOf("flags/EVENT_GOT_POKEDEX"), nil, "a flag of no one map")
  eq(Ownership.reloadFor("flags/EVENT_2ND_LOCK_OPENED"), "VERMILION_GYM", "Surge's door owes a reload (A5.7)")
  eq(Ownership.reloadFor("flags/EVENT_CINNABAR_GYM_GATE0_UNLOCKED"), "CINNABAR_GYM", "a quiz gate")
  eq(Ownership.reloadFor("defeatedTrainers/CINNABAR_GYM_obj_3"), "CINNABAR_GYM", "a beaten gate guard")
  eq(Ownership.reloadFor("flags/EVENT_BEAT_LORELEIS_ROOM_TRAINER_0"), "LORELEIS_ROOM", "a League room's exit")
  eq(Ownership.keepOnFloor("flags/EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH2"), "VICTORY_ROAD_3F",
     "a Victory Road switch waits on its floor")
  eq(Ownership.keepOnFloor("flags/EVENT_2ND_LOCK_OPENED"), nil, "a gym lock does not")
end

-- the campaign's story (A5.2) and a file from before #14 ------------------------
do
  local c = Campaign.new({ id = CID, title = "KANTO", game = "red", sha1 = SHA })
  local red = c:addPlayer({ id = "p01", name = "RED", game = "red" })
  local blue = c:addPlayer({ id = "p02", name = "BLUE", game = "red" })
  eq(c:patch(red.id, { ["flags/EVENT_A"] = true }, {}), 1, "a patch sets an entry")
  eq(c:patch(blue.id, { ["flags/EVENT_B"] = true }, {}), 1, "another window's patch")
  eq(c.story["flags/EVENT_A"], true, "both stand: patches merge entry by entry")
  eq(c.story["flags/EVENT_B"], true, "both stand")
  eq(c:patch(red.id, { ["flags/EVENT_SAFARI_GAME_OVER"] = true, ["inventory/POTION"] = 5,
                       ["flags/EVENT_C"] = "yes" }, {}), 0,
     "entries the campaign does not own, or bad values, are skipped")
  local rev = c.revision
  eq(c:patch(red.id, { ["flags/EVENT_A"] = true }, {}), 0, "an unchanged entry changes nothing")
  eq(c.revision, rev, "and the revision stays")
  eq(c:patch(blue.id, {}, { "flags/EVENT_A" }), 1, "a patch clears an entry")
  eq(c.story["flags/EVENT_A"], nil, "cleared")

  local save = F.save("RED", { flags = { EVENT_B = true, EVENT_GOT_STARTER = true } })
  save.player.map, save.player.x, save.player.y = "ROUTE_2", 7, 9
  check(c:setWorld(red.id, save), "a world is kept")
  eq(red.world.flags.EVENT_B, nil, "without the story's entries")
  eq(red.world.flags.EVENT_GOT_STARTER, true, "with the player's own")
  local opened = c:worldFor(red.id)
  eq(opened.flags.EVENT_B, true, "a world opens with the story over it (A5.19)")
  eq(opened.player.map, "ROUTE_2", "on the player's own map")
  eq(opened.player.x, 7, "and cell")
  eq(red.world.flags.EVENT_B, nil, "and the kept world is not touched")
  eq(c:worldFor(blue.id), nil, "a player without a world opens none")

  local back = CampaignFile.decode(CampaignFile.encode(c))
  eq(back and back.story["flags/EVENT_B"], true, "the story is in the file")
  eq(back.story["flags/EVENT_A"], nil, "as it stands")

  -- a version 1 file: the worlds hold the story
  local old = Campaign.new({ id = CID, title = "OLD", game = "red", sha1 = SHA })
  old:addPlayer({ id = "p01", name = "RED", game = "red" })
  old:addPlayer({ id = "p02", name = "BLUE", game = "red" })
  local w1 = F.save("RED", { flags = { EVENT_GOT_STARTER = true, EVENT_GOT_POKEDEX = true },
                             inventory = { BOULDERBADGE = 1, POTION = 2 } })
  w1.trashPuzzle = { first = 2 }
  local w2 = F.save("BLUE", { flags = { EVENT_BEAT_BROCK = true, EVENT_SAFARI_GAME_OVER = true } })
  w2.trashPuzzle = { first = 8 }
  w2.objectToggles = { ROUTE_1 = { BALL = false } }
  old.byId.p01.world, old.byId.p02.world = w1, w2
  local data = old:snapshot()
  data.format, data.version = CampaignFile.FORMAT, 1
  data.campaign.story = { flags = {}, badges = {} }
  local m = CampaignFile.decode(Json.encode(data))
  check(m, "a version 1 file reads")
  eq(m.story["flags/EVENT_GOT_POKEDEX"], true, "its story comes from the worlds")
  eq(m.story["flags/EVENT_BEAT_BROCK"], true, "every player's: the team rule")
  eq(m.story["inventory/BOULDERBADGE"], 1, "badges too")
  eq(m.story["objectToggles/ROUTE_1/BALL"], false, "and hidden objects")
  eq(m.story["trashPuzzle/first"], 2, "an entry held two ways takes the first player's")
  eq(m.story["flags/EVENT_SAFARI_GAME_OVER"], nil, "a player's flag stays out")
  eq(m:player("p02").world.flags.EVENT_BEAT_BROCK, nil, "the worlds lose the story")
  eq(m:player("p02").world.flags.EVENT_SAFARI_GAME_OVER, true, "but keep their own")
  eq(m:player("p01").world.inventory.POTION, 2, "and their items")
end

-- a window on a hand-made client: rest points, unconfirmed patches, the map ----
local function fakeClient(story)
  local c = { status = "joined", story = story, storyApplied = 0, sent = {} }
  function c:sendPatch(set, unset)
    self.sent[#self.sent + 1] = { set = set, unset = unset }
    return #self.sent
  end
  function c:sendHoldings() return nil end -- holdings are holdings_test.lua's
  function c:sendOpening() return nil end -- the opening is opening_test.lua's
  return c
end

local function frame(save, opts)
  opts = opts or {}
  local f = { save = save, busy = opts.busy, map = opts.map or "ROUTE_1",
              still = opts.still ~= false, reloads = {}, refreshes = {} }
  f.reload = function(m) f.reloads[#f.reloads + 1] = m end
  f.refresh = function(m) f.refreshes[#f.refreshes + 1] = m end
  return f
end

local function rest(w, save, opts, n)
  local f
  for _ = 1, n or Window.REST_FRAMES do
    f = frame(save, opts)
    w:update(f)
  end
  return f
end

do
  local c = fakeClient(nil)
  local w = Window.new(c)
  local save = F.save("RED", { flags = { EVENT_GOT_STARTER = true } })
  rest(w, save)
  eq(#c.sent, 0, "nothing before the host's story arrives")
  c.story = {}
  rest(w, save, nil, Window.REST_FRAMES - 1)
  eq(w:resting(), false, "a rest point counts only after three frames in a row")
  rest(w, save, nil, 1)
  check(w:resting(), "three quiet frames: a rest point (A5.4)")

  save.flags.EVENT_GOT_POKEDEX = true
  rest(w, save, { busy = "script" })
  eq(#c.sent, 0, "a held window sends nothing (A5.5)")
  rest(w, save, nil, Window.REST_FRAMES - 1)
  eq(#c.sent, 0, "nor before three quiet frames")
  rest(w, save, nil, 1)
  eq(#c.sent, 1, "at the rest point the change goes out")
  eq(c.sent[1].set["flags/EVENT_GOT_POKEDEX"], true, "as a patch of what changed")
  eq(count(c.sent[1].set), 1, "only what changed (not the player's starter flag)")

  save.money = 1
  save.flags.EVENT_SAFARI_GAME_OVER = true
  save.hiddenTaken = { ROUTE_1_3_4 = true }
  rest(w, save)
  eq(#c.sent, 1, "the player's own keys never go out")

  -- unconfirmed patches (A5.3)
  save.trashPuzzle = { first = 2 }
  rest(w, save)
  eq(#c.sent, 2, "a second patch")
  c.story = { ["flags/EVENT_GOT_POKEDEX"] = true, ["trashPuzzle/first"] = 4 }
  c.storyApplied = 1
  rest(w, save)
  eq(save.trashPuzzle.first, 2, "an older story never rewinds the window's unconfirmed change")
  c.storyApplied = 2
  c.story["trashPuzzle/first"] = 2
  rest(w, save)
  eq(save.trashPuzzle.first, 2, "confirmed")
  c.story["trashPuzzle/first"] = 6
  rest(w, save)
  eq(save.trashPuzzle.first, 6, "a partner's later change then lands")
  eq(#c.sent, 2, "and is not sent back")

  -- a held window takes nothing
  c.story["flags/EVENT_BEAT_BROCK"] = true
  rest(w, save, { busy = "above" })
  eq(save.flags.EVENT_BEAT_BROCK, nil, "a held window takes nothing (A5.5)")
  rest(w, save)
  eq(save.flags.EVENT_BEAT_BROCK, true, "it lands at the rest point")

  -- an object on the map the window stands on lands at once and refreshes it
  c.story["objectToggles/ROUTE_1/BALL"] = false
  local f = rest(w, save, { map = "ROUTE_1", still = false })
  eq(save.objectToggles.ROUTE_1.BALL, false, "a pulled hide lands at once (A5.6)")
  eq(#f.refreshes, 0, "mid-step the refresh waits")
  f = rest(w, save, { map = "ROUTE_1" }, 1)
  eq(f.refreshes[1], "ROUTE_1", "between two cells the map is refreshed")
  f = rest(w, save, { map = "ROUTE_1" }, 1)
  eq(#f.refreshes, 0, "once")
  c.story["objectToggles/ROUTE_2/BALL"] = false
  f = rest(w, save, { map = "ROUTE_1" })
  eq(save.objectToggles.ROUTE_2.BALL, false, "another map's object lands too")
  eq(#f.refreshes + #f.reloads, 0, "with nothing to rebuild")

  -- owed reloads (A5.7)
  c.story["flags/EVENT_2ND_LOCK_OPENED"] = true
  f = frame(save, { map = "VERMILION_GYM" })
  w:update(f)
  eq(save.flags.EVENT_2ND_LOCK_OPENED, true, "Surge's door flag lands")
  eq(f.reloads[1], "VERMILION_GYM", "and owes the gym a reload")
  c.story["flags/EVENT_1ST_LOCK_OPENED"] = true
  local g = frame(save, { map = "VERMILION_GYM" })
  w:update(g)
  eq(g.reloads[1], "VERMILION_GYM", "a pulled lock owes the gym a reload")
  c.story["flags/EVENT_CINNABAR_GYM_GATE1_UNLOCKED"] = true
  g = frame(save, { map = "VERMILION_GYM" })
  w:update(g)
  eq(#g.reloads, 0, "another map's gate owes this one nothing")
  eq(save.flags.EVENT_CINNABAR_GYM_GATE1_UNLOCKED, true, "but lands")

  -- Victory Road's switches (A5.17)
  c.story["flags/EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH1"] = true
  g = frame(save, { map = "VICTORY_ROAD_2F" })
  w:update(g)
  eq(g.reloads[1], "VICTORY_ROAD_2F", "a partner's switch opens the wall on this floor")
  c.story["flags/EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH1"] = nil
  rest(w, save, { map = "VICTORY_ROAD_2F" })
  eq(save.flags.EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH1, true,
     "a cleared switch waits while this window stands on the floor")
  rest(w, save, { map = "VICTORY_ROAD_1F" })
  eq(save.flags.EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH1, nil, "and lands once it left")
  eq(#c.sent, 2, "none of it went back to the host")

  -- START > SAVE sends the scene so far (A5.5)
  save.flags.EVENT_GOT_HM01 = true
  eq(w:flush(save), 3, "a save sends the scene so far, held or not")
end

-- opening (A5.2, A5.19) ----------------------------------------------------------
do
  local c = fakeClient({ ["flags/EVENT_BEAT_BROCK"] = true, ["inventory/BOULDERBADGE"] = 1 })
  local w = Window.new(c)
  local save = F.save("GREEN", { flags = { EVENT_GOT_STARTER = true, EVENT_STALE = true } })
  rest(w, save, { map = "PEWTER_CITY" })
  eq(save.flags.EVENT_BEAT_BROCK, true, "a window opened late takes the campaign")
  eq(save.inventory.BOULDERBADGE, 1, "badges and all")
  eq(save.flags.EVENT_STALE, nil, "its own story entries give way to the campaign's")
  eq(save.flags.EVENT_GOT_STARTER, true, "its player's keys stay")
  eq(#c.sent, 0, "and it pushes nothing")
  rest(w, save, { map = "PEWTER_CITY" }, 1)
  eq(w.reloads, 1, "the map it stands on is built again with the campaign's story")

  local c2 = fakeClient({})
  local w2 = Window.new(c2)
  -- (past the opening: a starter; the opening's seed is opening_test.lua's)
  local first = F.save("RED", { flags = { EVENT_GOT_STARTER = true, EVENT_GOT_POKEDEX = true } })
  rest(w2, first)
  eq(#c2.sent, 0, "a new campaign's first window opens")
  rest(w2, first, nil, 1)
  eq(c2.sent[1] and c2.sent[1].set["flags/EVENT_GOT_POKEDEX"], true,
     "and starts the story with its own entries")
end

-- host and windows over loopback ---------------------------------------------------
local clock = 0
local function now() return clock end
local ids = 0
local function hex(n)
  ids = ids + 1
  return ("%0" .. n .. "x"):format(ids)
end

local function startHost(state)
  local c = state or Campaign.new({ id = CID, title = "KANTO", game = "red", sha1 = SHA })
  local host = Host.new({ campaign = { id = CID, title = "KANTO" },
                          cartridge = { game = "red", sha1 = SHA }, clock = now, hex = hex,
                          state = c, build = "test" })
  return host, host:serve(Transport.loopback())
end

local function client(hub, name, device, known)
  return Client.new(hub:dial(), { name = name, game = "red", sha1 = SHA, build = "test",
                                  device = device, known = known, clock = now })
end

-- a window: a client, its save and its map
local function window(hub, name, device, known)
  local c = client(hub, name, device, known)
  c:join()
  return { c = c, w = Window.new(c), save = F.save(name), map = "PALLET_TOWN", busy = nil }
end

local function pump(host, wins, frames)
  for _ = 1, frames or 4 do
    for _, x in ipairs(wins) do x.c:update() end
    host:update()
    for _, x in ipairs(wins) do
      x.c:update()
      x.w:update({ save = x.save, busy = x.busy, map = x.map, still = true })
    end
  end
end

do
  local host, hub = startHost()
  local red = window(hub, "RED", "d1")
  local blue = window(hub, "BLUE", "d2")
  pump(host, { red, blue }, 6)
  eq(red.c.status, "joined", "RED joined")
  check(red.c.story and blue.c.story, "each window heard the story")

  -- two flags at once both survive (A5.2)
  red.save.flags.EVENT_GOT_POKEDEX = true
  blue.save.objectToggles = { ROUTE_1 = { BALL = false } }
  pump(host, { red, blue }, 6)
  eq(host.state.story["flags/EVENT_GOT_POKEDEX"], true, "RED's flag reached the campaign")
  eq(host.state.story["objectToggles/ROUTE_1/BALL"], false, "BLUE's taken ball too")
  eq(blue.save.flags.EVENT_GOT_POKEDEX, true, "BLUE has RED's flag")
  eq(red.save.objectToggles.ROUTE_1.BALL, false, "RED has BLUE's ball")
  eq(host.state:player(red.c.player).world, nil, "no world was sent: patches are not saves")

  -- a held window sends and takes nothing (A5.5)
  red.busy = "script"
  red.save.flags.EVENT_BEAT_BROCK = true
  red.save.inventory.BOULDERBADGE = 1
  blue.save.flags.EVENT_GOT_HM01 = true
  pump(host, { red, blue }, 6)
  eq(host.state.story["flags/EVENT_BEAT_BROCK"], nil, "a scene's change stays until it ends")
  eq(red.save.flags.EVENT_GOT_HM01, nil, "a held window takes nothing")
  red.busy = nil
  pump(host, { red, blue }, 6)
  eq(blue.save.flags.EVENT_BEAT_BROCK, true, "the scene's result arrives when it ends")
  eq(blue.save.inventory.BOULDERBADGE, 1, "a badge is everyone's (A5.15)")
  eq(red.save.flags.EVENT_GOT_HM01, true, "and the window took what it missed")

  -- the player's own keys stay with them
  local blueMoney = blue.save.money
  red.save.money = 9
  red.save.flags.EVENT_SAFARI_GAME_OVER = true
  red.save.hiddenTaken = { ROUTE_1_3_4 = true }
  red.save.inventory.POTION = 7
  pump(host, { red, blue }, 6)
  eq(blue.save.money, blueMoney, "money is each player's")
  eq(blue.save.flags.EVENT_SAFARI_GAME_OVER, nil, "so is the Safari game (A5.12)")
  eq(blue.save.hiddenTaken, nil, "and hidden items (A6.4)")
  eq(blue.save.inventory.POTION, 1, "and the bag")

  -- a patch with entries the campaign does not own: they are skipped
  local seq = red.c:sendPatch({ ["flags/EVENT_GOT_LAPRAS"] = true, ["inventory/POTION"] = 99 }, {})
  pump(host, { red, blue }, 4)
  check(seq, "a patch went out")
  eq(host.state.story["flags/EVENT_GOT_LAPRAS"], nil, "a player's flag never enters the story")
  eq(host.state.story["inventory/POTION"], nil, "nor an item")
  eq(red.c.storyApplied, seq, "the host still reports the patch applied")

  -- a world saved by a window keeps only the player's keys
  red.c:sendWorld(World.encode(red.save), true, "menu")
  pump(host, { red, blue }, 4)
  local kept = host.state:player(red.c.player).world
  eq(kept.flags.EVENT_GOT_POKEDEX, nil, "the kept world holds no story")
  eq(kept.flags.EVENT_SAFARI_GAME_OVER, true, "but the player's flags")
  eq(kept.money, 9, "and money")

  -- a window opened late takes the campaign (A5.2, A5.19)
  local green = window(hub, "GREEN", "d3")
  green.save.flags.EVENT_STALE = true
  pump(host, { red, blue, green }, 8)
  eq(green.save.flags.EVENT_BEAT_BROCK, true, "the late window took the campaign")
  eq(green.save.flags.EVENT_STALE, nil, "instead of pushing its own")
  eq(host.state.story["flags/EVENT_STALE"], nil, "which never reached the campaign")

  -- a lost link sends nothing: the host keeps the last resting state (A5.5)
  green.busy = "script"
  green.save.flags.EVENT_GOT_HM02 = true
  pump(host, { red, blue, green }, 2)
  green.c.conn:close()
  pump(host, { red, blue }, 4)
  eq(host.state.story["flags/EVENT_GOT_HM02"], nil, "a scene cut off by a lost link is not kept")

  -- a rejoining player's world opens like a Continue (A5.19)
  local known = { [CID] = red.c.player }
  red.c:leave()
  pump(host, { blue }, 4)
  local back = client(hub, "RED", "d1", known)
  back:join()
  pump(host, { blue }, 2)
  for _ = 1, 3 do back:update(); host:update(); back:update() end
  local opened = back.world and World.decode(back.world.save)
  check(opened, "the rejoining player gets a world")
  eq(opened and opened.flags.EVENT_GOT_HM01, true, "with the campaign's story laid over it")
  eq(opened and opened.flags.EVENT_SAFARI_GAME_OVER, true, "and their own flags")
  eq(opened and opened.money, 9, "and their own money")
  eq(opened and opened.player.map, "PALLET_TOWN", "on their own map")
  host:shutdown("test")
end

-- the walk flags a host drops when it opens a campaign (A5.13) ----------------------
do
  local c = Campaign.new({ id = CID, title = "KANTO", game = "red", sha1 = SHA })
  local p = c:addPlayer({ id = "p01", name = "RED", game = "red" })
  local save = F.save("RED", { flags = { EVENT_SAFARI_GAME_OVER = true, EVENT_GOT_STARTER = true } })
  save.safari = { balls = 3, steps = 10 }
  c:setWorld(p.id, save)
  local host = startHost(c)
  eq(c:player("p01").world.flags.EVENT_SAFARI_GAME_OVER, nil, "the Safari game is over for nobody")
  eq(c:player("p01").world.safari, nil, "nobody is in the Safari Zone")
  eq(c:player("p01").world.flags.EVENT_GOT_STARTER, true, "the rest of the world stays")
  host:shutdown("test")
end

-- protocol: patch and story are checked like every message --------------------------
do
  check(Protocol.sanitize({ type = "patch", seq = 1, set = { ["flags/X"] = true }, unset = {} }, "host"),
        "a patch passes")
  check(not Protocol.sanitize({ type = "patch", seq = 1, set = { ["flags/X"] = "code()" },
                                unset = {} }, "host"), "a text value is dropped")
  check(not Protocol.sanitize({ type = "patch", seq = 1, set = { ["../etc"] = true },
                                unset = {} }, "host"), "a bad path is dropped")
  check(not Protocol.sanitize({ type = "patch", seq = 1, set = {}, unset = { "flags/" } }, "host"),
        "a path with an empty key is dropped")
  check(Protocol.sanitize({ type = "story", rev = 1, base = true, set = {}, unset = {},
                            applied = 0 }, "client"), "a story passes")
end

T.finish()
