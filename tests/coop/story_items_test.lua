-- Story items and the co-op bag (#16, design A6): items gained in the window
-- change that moves the story reach every player, key items the story takes
-- leave every bag, the late-joiner gift list, a full bag's spill to the PC,
-- the gift race's take-back and the 40-row bag.  Item rules over plain save
-- tables with a hand-made item table; host and windows in one process over
-- the loopback transport.  ROM-free.
--   luajit tests/coop/story_items_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local F = require("tests.coop.support.campaign_fixture")
local Transport = require("src.coop.session.Transport")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local Protocol = require("src.coop.session.Protocol")
local World = require("src.coop.campaign.World")
local Campaign = require("src.coop.campaign.Campaign")
local Window = require("src.coop.campaign.Window")
local Items = require("src.coop.campaign.Items")
local CampaignFile = require("src.coop.campaign.CampaignFile")
local Json = require("src.link.Json")

local SHA = ("ab"):rep(20)
local CID = "c0123456789abcdef"

-- the items these tests use, shaped like the cartridge's (keyItem, machine)
local DATA = {
  constants = { bagSize = 20 },
  items = {
    POTION = { id = "POTION", name = "POTION" },
    ANTIDOTE = { id = "ANTIDOTE", name = "ANTIDOTE" },
    BICYCLE = { id = "BICYCLE", name = "BICYCLE", keyItem = true },
    BIKE_VOUCHER = { id = "BIKE_VOUCHER", name = "BIKE VOUCHER", keyItem = true },
    OAKS_PARCEL = { id = "OAKS_PARCEL", name = "OAK's PARCEL", keyItem = true },
    HELIX_FOSSIL = { id = "HELIX_FOSSIL", name = "HELIX FOSSIL", keyItem = true },
    OLD_ROD = { id = "OLD_ROD", name = "OLD ROD", keyItem = true },
    HM_CUT = { id = "HM_CUT", name = "HM01", machine = { kind = "HM", number = 1, move = "CUT" } },
    TM_BIDE = { id = "TM_BIDE", name = "TM34", machine = { kind = "TM", number = 34, move = "BIDE" } },
    TM_MEGA_PUNCH = { id = "TM_MEGA_PUNCH", name = "TM01",
                      machine = { kind = "TM", number = 1, move = "MEGA_PUNCH" } },
    BOULDERBADGE = { id = "BOULDERBADGE", name = "BOULDERBADGE", keyItem = true },
  },
}
Items.data = DATA

local function count(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

-- the item rules (A6.2 to A6.6) ------------------------------------------------
do
  check(Items.isKey("BICYCLE"), "a key item is a key item")
  check(Items.isKey("HM_CUT"), "an HM counts as one (one row, never doubled)")
  check(not Items.isKey("POTION"), "a POTION is not")
  check(not Items.isKey("TM_BIDE"), "nor a TM (they stack)")
  check(Items.isFossil("HELIX_FOSSIL"), "fossils are fossils")
  check(not Items.isFossil("OAKS_PARCEL"), "the parcel is not")

  eq(Items.giftId("BICYCLE", {}), "gift:BICYCLE", "the BICYCLE is on the gift list (A6.5)")
  eq(Items.giftId("HM_CUT", {}), "gift:HM_CUT", "so is HM01")
  eq(Items.giftId("OLD_ROD", {}), "gift:OLD_ROD", "and the rods")
  eq(Items.giftId("OAKS_PARCEL", {}), nil, "the parcel is not: the story takes it")
  eq(Items.giftId("POTION", { ["itemsTaken/ROUTE_1_obj_1"] = true }), nil, "nor a POTION")
  eq(Items.giftId("TM_BIDE", { ["flags/EVENT_GOT_TM34"] = true }), "gift:TM_BIDE",
     "a TM given with its EVENT_GOT_TM flag is a gift TM")
  eq(Items.giftId("TM_BIDE", { ["itemsTaken/ROUTE_1_obj_1"] = true }), nil,
     "a TM from an item ball is not")
  eq(Items.giftId("TM_MEGA_PUNCH", { ["flags/EVENT_GOT_TM34"] = true }), nil,
     "another TM's flag does not count")

  local save = F.save("RED", { inventory = { POTION = 3, BOULDERBADGE = 1, BICYCLE = 1 } })
  local bag = Items.bag(save)
  eq(bag.POTION, 3, "the bag counts items")
  eq(bag.BOULDERBADGE, nil, "but not badges (they are the story's)")
  local gained, lost = Items.delta({ POTION = 1, ANTIDOTE = 2, BICYCLE = 1 },
                                   { POTION = 3, ANTIDOTE = 2 })
  eq(gained.POTION, 2, "a gain")
  eq(lost.BICYCLE, 1, "a loss")
  eq(gained.ANTIDOTE, nil, "nothing for an unchanged item")

  -- giving: the bag, a full bag's PC (A6.6), a key item held once
  eq(Items.give(save, "ANTIDOTE", 2), "bag", "a gift goes to the bag")
  eq(save.inventory.ANTIDOTE, 2, "two of them")
  eq(Items.give(save, "BICYCLE", 1, true), "held", "a key item the player holds is not given twice")
  eq(save.inventory.BICYCLE, 1, "still one BICYCLE")
  local full = F.save("BLUE", { inventory = {} })
  for i = 1, 20 do
    local id = "FILL_" .. i
    DATA.items[id] = { id = id, name = id }
    full.inventory[id] = 1
  end
  eq(Items.give(full, "POTION", 1), "pc", "a full bag sends the gift to the PC (A6.6)")
  eq(full.pcItems.POTION, 1, "the POTION is in the PC")
  eq(full.inventory.POTION, nil, "not in the bag")
  full.pcItems.HM_CUT = 1
  eq(Items.give(full, "HM_CUT", 1, true), "held", "a key item in the PC counts as held")

  -- taking: the bag first, then the PC
  eq(Items.take(save, "POTION", 2), 2, "taken from the bag")
  eq(save.inventory.POTION, 1, "one left")
  eq(Items.take(full, "POTION", 1), 1, "taken from the PC")
  eq(full.pcItems.POTION, nil, "the PC's POTION is gone")
  eq(Items.take(save, "OAKS_PARCEL", 1), 0, "nothing to take")

  -- the 40-row bag (A6.8)
  local cap = DATA.constants.bagSize
  Items.openBag()
  eq(DATA.constants.bagSize, Items.BAG_ROWS, "a co-op world opens a 40-row bag")
  eq(Items.BAG_ROWS, 40, "forty rows")
  Items.openBag()
  Items.closeBag()
  eq(DATA.constants.bagSize, cap, "closing puts the solo bag back")
  Items.closeBag()
  eq(DATA.constants.bagSize, cap, "a second close changes nothing")
  for i = 1, 20 do DATA.items["FILL_" .. i] = nil end
end

-- the campaign's side: sharing, taking, the race, the gift list ------------------
local function campaign()
  local c = Campaign.new({ id = CID, title = "KANTO", game = "red", sha1 = SHA })
  c:addPlayer({ id = "p01", name = "RED", game = "red" })
  c:addPlayer({ id = "p02", name = "BLUE", game = "red" })
  return c
end

local function gifts(c, id)
  return c:player(id).gifts or {}
end

do
  local c = campaign()
  -- RED picks up an item ball: a story entry and a POTION in one change (A6.2)
  c:patch("p01", { ["itemsTaken/ROUTE_1_obj_1"] = true }, {}, { gained = { POTION = 1 }, lost = {} })
  local g = gifts(c, "p02")
  eq(#g, 1, "BLUE is owed RED's story item")
  eq(g[1].item, "POTION", "the POTION")
  eq(g[1].qty, 1, "in the same number")
  eq(g[1].from, "RED", "from RED")
  eq(#gifts(c, "p01"), 0, "RED keeps its own and is owed nothing")

  -- an item gained with no story moved stays with its player (A6.4)
  c:patch("p01", {}, {}, { gained = { ANTIDOTE = 5 }, lost = {}, spent = true })
  eq(#gifts(c, "p02"), 1, "a purchase is not shared")
  c.story["flags/EVENT_VICTORY_ROAD_1_BOULDER_ON_SWITCH"] = true
  c:patch("p01", {}, { "flags/EVENT_VICTORY_ROAD_1_BOULDER_ON_SWITCH" },
          { gained = { ANTIDOTE = 1 }, lost = {} })
  eq(#gifts(c, "p02"), 1, "nor a gain beside a cleared entry only")

  -- a gift on the list is committed once (A6.5)
  c:patch("p01", { ["flags/EVENT_GOT_BICYCLE"] = true }, {},
          { gained = { BICYCLE = 1 }, lost = { BIKE_VOUCHER = 1 } })
  check(c:applied("gift:BICYCLE"), "the BICYCLE is committed to the gift list")
  g = gifts(c, "p02")
  eq(g[2].item, "BICYCLE", "BLUE is owed the BICYCLE")
  eq(g[2].once, true, "once: a held key item is not doubled")
  eq(g[3].item, "BIKE_VOUCHER", "and the voucher the story took leaves BLUE's bag (A6.3)")
  eq(g[3].qty, -1, "as a take")

  -- fossils are each player's (A6.3)
  c:patch("p01", { ["flags/EVENT_GAVE_SOMETHING"] = true }, {},
          { gained = {}, lost = { HELIX_FOSSIL = 1, POTION = 1 } })
  eq(#gifts(c, "p02"), 3, "a fossil or a POTION used up is not taken from BLUE")

  -- a gift TM with its flag
  c:patch("p01", { ["flags/EVENT_GOT_TM34"] = true, ["inventory/BOULDERBADGE"] = 1 }, {},
          { gained = { TM_BIDE = 1 }, lost = {} })
  check(c:applied("gift:TM_BIDE"), "Brock's TM is a gift TM")
  eq(gifts(c, "p02")[4].item, "TM_BIDE", "and BLUE is owed it")

  -- the gift race (A6.7): BLUE took the same ball before hearing of RED's
  c:patch("p02", { ["itemsTaken/ROUTE_1_obj_1"] = true }, {}, { gained = { POTION = 1 }, lost = {} })
  local mine = gifts(c, "p02")
  eq(mine[#mine].item, "POTION", "BLUE lost the race: its POTION is taken back")
  eq(mine[#mine].qty, -1, "one")
  eq(mine[#mine].race, true, "marked as the race's")
  eq(#gifts(c, "p01"), 0, "RED is owed nothing for BLUE's lost race")
  local before = #gifts(c, "p02")
  c:patch("p02", { ["itemsTaken/ROUTE_1_obj_1"] = true }, {},
          { gained = { POTION = 1 }, lost = {}, spent = true })
  eq(#gifts(c, "p02"), before, "a race that spent money is left alone (a purchase may be in it)")
  c:patch("p02", { ["flags/EVENT_GOT_BICYCLE"] = true }, {}, { gained = { BICYCLE = 1 }, lost = {} })
  eq(#gifts(c, "p02"), before, "a key item is never taken back (the share was not doubled)")

  -- a late joiner is handed the gift list (A6.5)
  c:addPlayer({ id = "p03", name = "GREEN", game = "red" })
  local late = gifts(c, "p03")
  local got = {}
  for _, e in ipairs(late) do got[e.item] = e end
  eq(count(got), 2, "GREEN is owed the two gifts on the list")
  check(got.BICYCLE and got.BICYCLE.once, "the BICYCLE, once")
  check(got.TM_BIDE and got.TM_BIDE.once, "Brock's TM, once")
  eq(got.POTION, nil, "not the item ball's POTION")

  -- a world that has taken its gifts lets the host forget them
  local seq = gifts(c, "p02")[2].seq
  local world = F.save("BLUE")
  world.coopGifts = seq
  check(c:setWorld("p02", world), "BLUE's world saved")
  eq(gifts(c, "p02")[1].seq, seq + 1, "the gifts it took are dropped, the rest kept")
  eq(c:player("p02").world.coopGifts, seq, "the world keeps the last gift it took")

  -- the campaign file keeps what is owed
  local copy = assert(Campaign.fromSnapshot(c:snapshot()))
  eq(#copy:player("p03").gifts, 2, "a late joiner's gifts survive the file")
  eq(copy:player("p02").giftSeq, c:player("p02").giftSeq, "and the gift counter")
  eq(copy:player("p02").gifts[1].item, gifts(c, "p02")[1].item, "in order")

  -- a version 2 file (before #16) reads, nobody owed anything
  check(CampaignFile.VERSION >= 3, "campaign files are version 3")
  local data = campaign():snapshot()
  data.format, data.version = CampaignFile.FORMAT, 2
  for _, entry in ipairs(data.players) do entry.gifts, entry.giftSeq = nil, nil end
  local old = CampaignFile.decode(Json.encode(data))
  check(old, "a version 2 file is migrated")
  eq(old and #old:player("p02").gifts, 0, "with no gifts owed")
  eq(old and old:player("p02").giftSeq, 0, "and the counter at 0")
end

-- a window on a hand-made client ------------------------------------------------
local function fakeClient(story)
  local c = { status = "joined", story = story, storyApplied = 0, sent = {}, gifts = {} }
  function c:sendPatch(set, unset, bag)
    self.sent[#self.sent + 1] = { set = set, unset = unset, bag = bag }
    return #self.sent
  end
  function c:sendHoldings() return nil end -- holdings are holdings_test.lua's
  function c:sendOpening() return nil end -- the opening is opening_test.lua's
  return c
end

local function rest(w, save, opts, n)
  opts = opts or {}
  local f
  for _ = 1, n or Window.REST_FRAMES do
    f = { save = save, busy = opts.busy, map = "ROUTE_1", still = true,
          gifted = opts.gifted }
    w:update(f)
  end
  return f
end

do
  local c = fakeClient({ ["flags/EVENT_GOT_POKEDEX"] = true })
  local w = Window.new(c)
  local save = F.save("RED", { inventory = { POTION = 1 }, money = 3000 })
  rest(w, save)
  -- a purchase between two rest points: no story moved, nothing sent
  save.inventory.ANTIDOTE = 2
  save.money = 2800
  rest(w, save, nil, 1)
  eq(#c.sent, 0, "a purchase sends no patch")
  -- an item ball: the story entry and the POTION in one change
  save.itemsTaken = { ROUTE_1_obj_1 = true }
  save.inventory.POTION = 2
  rest(w, save, nil, 1)
  local p = c.sent[1]
  check(p and p.bag, "the patch carries the bag's change")
  eq(p and p.bag.gained.POTION, 1, "the POTION gained since the last rest point")
  eq(p and p.bag.gained.ANTIDOTE, nil, "not the ANTIDOTE bought before")
  eq(p and p.bag.spent, false, "no money spent in this change")
  -- a key item the story takes, and money spent in the same change
  save.flags.EVENT_GOT_BICYCLE = true
  save.inventory.BICYCLE = 1
  save.inventory.POTION = nil
  save.money = 2000
  rest(w, save, nil, 1)
  p = c.sent[2]
  eq(p and p.bag.gained.BICYCLE, 1, "the BICYCLE")
  eq(p and p.bag.lost.POTION, 2, "the POTIONs gone")
  eq(p and p.bag.spent, true, "money spent")
  -- a story change without a bag change sends no bag
  save.flags.EVENT_BEAT_BROCK = true
  rest(w, save, nil, 1)
  eq(c.sent[3] and c.sent[3].bag, nil, "no bag when the bag did not move")

  -- gifts land at a rest point, once each (A6.2, A6.6)
  local shown = {}
  c.gifts = { { seq = 1, item = "OLD_ROD", qty = 1, once = true, from = "BLUE" },
              { seq = 2, item = "POTION", qty = 3, from = "BLUE" } }
  rest(w, save, { busy = "script" }, 4)
  eq(save.inventory.OLD_ROD, nil, "a held window takes no gift")
  rest(w, save, { gifted = function(e, where) shown[#shown + 1] = e.item .. ":" .. where end })
  eq(save.inventory.OLD_ROD, 1, "the OLD ROD arrived")
  eq(save.inventory.POTION, 3, "three POTIONs")
  eq(save.coopGifts, 2, "the world keeps the last gift it took")
  eq(shown[1], "OLD_ROD:bag", "the game is told of each gift")
  c.gifts[#c.gifts + 1] = { seq = 2, item = "POTION", qty = 3, from = "BLUE" }
  c.gifts[#c.gifts + 1] = { seq = 3, item = "OAKS_PARCEL", qty = -1 }
  save.inventory.OAKS_PARCEL = 1
  local sent = #c.sent
  rest(w, save, nil, 1)
  eq(save.inventory.POTION, 3, "a gift heard twice lands once")
  eq(save.inventory.OAKS_PARCEL, nil, "a take leaves the bag")
  eq(#c.sent, sent, "gifts taken are not sent back as the window's own change")
  save.flags.EVENT_GOT_TM34 = true
  rest(w, save, nil, 1)
  eq(c.sent[#c.sent].bag, nil, "nor counted in its next story change")
end

-- host and windows over loopback ----------------------------------------------
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

local function window(hub, name, device, known, save)
  local c = Client.new(hub:dial(), { name = name, game = "red", sha1 = SHA, build = "test",
                                     device = device, known = known, clock = now })
  c:join()
  return { c = c, w = Window.new(c), save = save or F.save(name, { inventory = {} }),
           map = "PALLET_TOWN" }
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
  eq(blue.c.status, "joined", "BLUE joined")

  -- an item ball reaches BLUE (A6.2)
  red.save.itemsTaken = { ROUTE_1_obj_1 = true }
  red.save.inventory.POTION = 1
  pump(host, { red, blue }, 8)
  eq(blue.save.itemsTaken and blue.save.itemsTaken.ROUTE_1_obj_1, true, "BLUE has the ball taken")
  eq(blue.save.inventory.POTION, 1, "and RED's POTION")
  eq(red.save.inventory.POTION, 1, "RED keeps one")

  -- the BICYCLE for the voucher: given, and the voucher taken (A6.3)
  blue.save.inventory.BIKE_VOUCHER = 1
  red.save.inventory.BIKE_VOUCHER = 1
  pump(host, { red, blue }, 4)
  red.save.flags.EVENT_GOT_BICYCLE = true
  red.save.inventory.BIKE_VOUCHER = nil
  red.save.inventory.BICYCLE = 1
  pump(host, { red, blue }, 8)
  eq(blue.save.inventory.BICYCLE, 1, "BLUE has the BICYCLE")
  eq(blue.save.inventory.BIKE_VOUCHER, nil, "and no voucher")

  -- a full bag spills to the PC (A6.6)
  for i = 1, 18 do
    DATA.items["FILL_" .. i] = { id = "FILL_" .. i, name = "FILL" }
    blue.save.inventory["FILL_" .. i] = 1
  end
  pump(host, { red, blue }, 4)
  red.save.flags.EVENT_GOT_OLD_ROD = true
  red.save.inventory.OLD_ROD = 1
  pump(host, { red, blue }, 8)
  eq(blue.save.inventory.OLD_ROD, nil, "BLUE's full bag has no room")
  eq(blue.save.pcItems and blue.save.pcItems.OLD_ROD, 1, "so the OLD ROD went to the PC")

  -- the gift race over the link (A6.7): both take one ball in the same frame
  red.save.itemsTaken.ROUTE_2_obj_1 = true
  red.save.inventory.ANTIDOTE = 1
  blue.save.inventory.FILL_18 = nil
  blue.save.itemsTaken.ROUTE_2_obj_1 = true
  blue.save.inventory.ANTIDOTE = 1
  pump(host, { red, blue }, 10)
  eq(red.save.inventory.ANTIDOTE, 1, "the race's winner has one")
  eq(blue.save.inventory.ANTIDOTE, 1, "and so has the loser: its own taken back, the share standing")
  for i = 1, 17 do blue.save.inventory["FILL_" .. i] = nil end

  -- a player gone when a gift is made gets it on the way back
  blue.c:leave()
  pump(host, { red }, 4)
  red.save.flags.EVENT_GOT_HM01 = true
  red.save.inventory.HM_CUT = 1
  pump(host, { red }, 8)
  check(host.state:applied("gift:HM_CUT"), "HM01 committed while BLUE was away")
  local back = window(hub, "BLUE", "d2", blue.c.known, blue.save)
  pump(host, { red, back }, 10)
  eq(back.save.inventory.HM_CUT, 1, "BLUE got HM01 on rejoining")

  -- a late joiner gets the gift list, and not the item balls (A6.5)
  local green = window(hub, "GREEN", "d3")
  pump(host, { red, back, green }, 10)
  eq(green.save.inventory.BICYCLE, 1, "GREEN got the BICYCLE")
  eq(green.save.inventory.OLD_ROD, 1, "the OLD ROD")
  eq(green.save.inventory.HM_CUT, 1, "and HM01")
  eq(green.save.inventory.POTION, nil, "not the item ball's POTION")

  -- a gift taken but never saved comes again after a rejoin; once saved, never
  local gp = green.c.player
  green.c:leave()
  pump(host, { red, back }, 4)
  local again = window(hub, "GREEN", "d3", green.c.known, F.save("GREEN", { inventory = {} }))
  pump(host, { red, back, again }, 10)
  eq(again.save.inventory.BICYCLE, 1, "an unsaved world gets its gifts again")
  local text = World.encode(again.save)
  again.c:sendWorld(text, true, "menu")
  pump(host, { red, back, again }, 4)
  eq(#host.state:player(gp).gifts, 0, "a saved world that took them clears the host's list")
  for i = 1, 18 do DATA.items["FILL_" .. i] = nil end
end

-- the protocol --------------------------------------------------------------------
do
  check(Protocol.VERSION >= 6, "protocol 6: story items")
  check(Protocol.sanitize({ type = "patch", seq = 1, set = {}, unset = {},
                            bag = { gained = { POTION = 1 }, lost = {}, spent = false } }, "host"),
        "a patch with a bag passes")
  check(not Protocol.sanitize({ type = "patch", seq = 1, set = {}, unset = {},
                                bag = { gained = { POTION = 0 }, lost = {} } }, "host"),
        "a gain of nothing does not")
  check(not Protocol.sanitize({ type = "patch", seq = 1, set = {}, unset = {},
                                bag = { gained = { ["bad id"] = 1 }, lost = {} } }, "host"),
        "nor an odd item id")
  check(Protocol.sanitize({ type = "gifts", list = { { seq = 1, item = "POTION", qty = -1,
                                                       once = false, from = "RED" } } }, "client"),
        "a gift list passes")
  check(not Protocol.sanitize({ type = "gifts", list = { { seq = 1, item = "POTION", qty = 0,
                                                           once = false } } }, "client"),
        "a gift of nothing does not")
end

T.finish()
