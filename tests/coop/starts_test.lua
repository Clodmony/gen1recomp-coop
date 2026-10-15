-- How a new player starts besides Oak's opening (#57, design A4.1 to A4.3,
-- A4.7, decision G28), ROM-free: the start in Pallet Town (a starter at
-- level 5, 3000 money, the story a played opening leaves, derived from
-- the lab's script; none for Yellow), a trainer brought from a solo save
-- (checked by the game's own validator, its trainer id kept, its story
-- seeding a campaign with none), and a returning player never replaced.
-- Host and windows in one process over loopback; the game's validator on
-- the fixture data.
--   luajit tests/coop/starts_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq
local F = require("tests.coop.support.campaign_fixture")
local Transport = require("src.coop.session.Transport")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local Campaign = require("src.coop.campaign.Campaign")
local Ownership = require("src.coop.campaign.Ownership")
local World = require("src.coop.campaign.World")
local Window = require("src.coop.campaign.Window")
local Start = require("src.coop.campaign.Start")

local SHA = ("ab"):rep(20)
local CID = "c0123456789abcdef"

local clock = 0
local function now() return clock end
local ids = 0
local function hex(n)
  ids = ids + 1
  return ("%0" .. n .. "x"):format(ids)
end

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- the ten entries #22's run seeded for RED, who took SQUIRTLE
local RED_RUN = {
  ["flags/EVENT_BATTLED_RIVAL_IN_OAKS_LAB"] = true,
  ["flags/EVENT_FOLLOWED_OAK_INTO_LAB"] = true,
  ["flags/EVENT_FOLLOWED_OAK_INTO_LAB_2"] = true,
  ["flags/EVENT_OAK_ASKED_TO_CHOOSE_MON"] = true,
  ["objectToggles/OAKS_LAB/OAKSLAB_BULBASAUR_POKE_BALL"] = false,
  ["objectToggles/OAKS_LAB/OAKSLAB_OAK1"] = true,
  ["objectToggles/OAKS_LAB/OAKSLAB_OAK2"] = false,
  ["objectToggles/OAKS_LAB/OAKSLAB_RIVAL"] = false,
  ["objectToggles/OAKS_LAB/OAKSLAB_SQUIRTLE_POKE_BALL"] = false,
  ["objectToggles/PALLET_TOWN/PALLETTOWN_OAK"] = false,
}

local function same(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false, k end end
  for k, v in pairs(b) do if a[k] ~= v then return false, k end end
  return true
end

-- the start in Pallet Town's story (A4.7) ------------------------------------
do
  local story = Start.story("red", "SQUIRTLE")
  local view = Ownership.view({ flags = story.flags, objectToggles = story.objectToggles })
  local ok, diff = same(view, RED_RUN)
  check(ok, "Red's Pallet start leaves the story #22's played run seeded (" .. tostring(diff) .. ")")
  eq(count(view), 10, "ten entries")
  local lab = require("data.scripts.oaks_lab")
  for _, starter in ipairs(Start.STARTERS) do
    local s = Start.story("blue", starter)
    local hidden = {}
    for _, row in ipairs(lab.talk["TEXT_OAKSLAB_" .. starter .. "_POKE_BALL"]) do
      if row[1] == "hide_object" then hidden[#hidden + 1] = row[3] end
    end
    eq(#hidden, 2, starter .. "'s ball hides two balls in the lab's script")
    for _, obj in ipairs(hidden) do
      eq(s.objectToggles.OAKS_LAB[obj], false, starter .. ": " .. obj .. " is gone, as the script hides it")
    end
    eq(s.objectToggles.OAKS_LAB["OAKSLAB_" .. starter .. "_POKE_BALL"], false, starter .. "'s own ball")
    eq(s.objectToggles.OAKS_LAB["OAKSLAB_" .. Start.COUNTER[starter] .. "_POKE_BALL"], false,
       "and the rival's counter-pick")
    eq(count(Ownership.view({ flags = s.flags, objectToggles = s.objectToggles })), 10,
       starter .. ": ten entries in Blue too")
  end
  check(Start.offersPallet("red") and Start.offersPallet("blue")
        and Start.offersPallet("red_de") and Start.offersPallet("blue_de"),
        "Red and Blue (and their German editions) offer the start in Pallet Town")
  check(not Start.offersPallet("yellow") and not Start.offersPallet("yellow_de"),
        "Yellow does not (G28: its opening is PIKACHU's)")
  eq(Start.story("yellow", "BULBASAUR"), nil, "no canned story for Yellow")
  eq(Start.pallet({ version = "yellow", starter = "BULBASAUR" }), nil, "nor a Pallet world")
end

-- the Pallet world (A4.1) -------------------------------------------------------
local function rng() return 7 end
local function pallet(name, starter, version)
  return Start.pallet({ version = version or "red", starter = starter, name = name, rng = rng })
end

do
  local save = pallet("ASH", "CHARMANDER")
  eq(World.check(save), nil, "the Pallet world has a save's shape")
  eq(save.coopStart, "pallet", "marked to start with")
  eq(save.player.name, "ASH", "the launcher's name")
  eq(save.player.map, "PALLET_TOWN", "standing in Pallet Town")
  eq(save.money, 3000, "3000 money")
  eq(#save.party, 1, "one Pokémon")
  eq(save.party[1].species, "CHARMANDER", "the chosen starter")
  eq(save.party[1].level, 5, "at level 5")
  check(save.flags.EVENT_GOT_STARTER and save.flags.EVENT_CHOSE_CHARMANDER, "the starter's own flags")
  check(save.pokedex.owned.CHARMANDER and save.pokedex.seen.SQUIRTLE,
        "the starter owned, the rival's seen in the lab")
  eq(save.objectToggles.OAKS_LAB.OAKSLAB_SQUIRTLE_POKE_BALL, false, "the rival took SQUIRTLE")
  eq(save.options, nil, "no device options in it")
end

-- the game's own validator completes the starter (A4.2), as CONTINUE runs it
do
  local Data = require("tests.modkit").fixtures.fresh()
  Data.pokemon.CHARMANDER = { name = "CHARMANDER", catchRate = 45, growthRate = "MEDIUM_SLOW",
                              baseStats = { hp = 39, attack = 52, defense = 43, speed = 65, special = 50 } }
  Data.moves.SCRATCH = { name = "SCRATCH", pp = 35 }
  Data.moves.GROWL = { name = "GROWL", pp = 40 }
  local SaveData = require("src.core.SaveData")
  local save = pallet("ASH", "CHARMANDER")
  local report = SaveData.validate(save, Data)
  local mon = save.party[1]
  eq(#report.lostMons, 0, "the starter passes the validator")
  check(mon.stats and mon.stats.hp and mon.stats.hp > 0, "the validator derives its stats")
  eq(mon.hp, mon.stats.hp, "at full HP")
  eq(mon.moves[1].pp, 35, "and its moves' PP")
  eq(mon.moves[2].pp, 40, "both")
  require("src.battle.BattleState").stampOT(save, mon)
  eq(mon.otId, save.player.id, "the load stamps the player as its trainer")
end

-- host and windows ----------------------------------------------------------------
local function startHost(players)
  local c = Campaign.new({ id = CID, title = "KANTO", game = "red", sha1 = SHA })
  for _, p in ipairs(players or {}) do
    local cp = c:addPlayer({ id = p.id, name = p.name, game = "red" })
    if p.world then c:setWorld(cp.id, p.world) end
  end
  local host = Host.new({ campaign = { id = CID, title = "KANTO" },
                          cartridge = { game = "red", sha1 = SHA }, clock = now, hex = hex,
                          state = c, build = "test", players = players })
  return host, host:serve(Transport.loopback())
end

local function window(hub, name, device, save, known)
  local c = Client.new(hub:dial(), { name = name, game = "red", sha1 = SHA, build = "test",
                                     device = device, clock = now, known = known })
  c:join()
  local x = { c = c, w = Window.new(c), save = save, map = save.player.map, busy = nil, sent = {} }
  local send = c.send
  c.send = function(self, msg)
    x.sent[#x.sent + 1] = msg.type
    return send(self, msg)
  end
  return x
end

local function sent(x, kind)
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

-- a solo save past several gyms, as a player brings it
local function soloSave(name, trainer)
  local save = F.save(name, { trainer = trainer, map = "CERULEAN_CITY",
    party = { F.mon("SQUIRTLE", 24, { otId = trainer, ot = name }), F.mon("PIDGEY", 18, { otId = trainer, ot = name }) },
    inventory = { POTION = 3, BICYCLE = 1, BOULDERBADGE = 1, CASCADEBADGE = 1 },
    flags = { EVENT_GOT_STARTER = true, EVENT_CHOSE_SQUIRTLE = true,
              EVENT_FOLLOWED_OAK_INTO_LAB = true, EVENT_BEAT_BROCK = true,
              EVENT_BEAT_MISTY = true, EVENT_GOT_BICYCLE = true, EVENT_IN_SAFARI_ZONE = true },
    money = 12345 })
  save.defeatedTrainers = { PEWTER_GYM_obj_1 = true }
  save.boxes[1][1] = F.mon("RATTATA", 7, { otId = trainer, ot = name })
  return save
end

-- the host's player starts in Pallet Town in a new campaign; a guest brings a
-- save; a guest plays the opening alongside --------------------------------------
do
  local host, hub = startHost()
  local red = window(hub, "ASH", "d1", pallet("ASH", "SQUIRTLE"))
  red.busy = "above" -- the title screen, then CONTINUE
  pump(host, { red }, 6)
  eq(red.c.status, "joined", "RED joined")
  local rid = red.c.player
  eq(sent(red, "start"), 0, "nothing goes while the player is held")
  red.busy = nil
  pump(host, { red }, 3)
  eq(sent(red, "start"), 1, "the first rest point sends the start, once")
  eq(sent(red, "patch"), 0, "no patch: the host seeds the story itself")
  pump(host, { red }, 10)
  eq(sent(red, "start"), 1, "and only once")
  local cp = host.state:player(rid)
  check(cp.world ~= nil, "the host keeps the started world")
  eq(cp.world.party[1].species, "SQUIRTLE", "with the starter")
  eq(cp.world.coopStart, nil, "without the start's mark")
  eq(red.save.coopStart, nil, "the window took the mark off")
  local ok, diff = same(host.state.story, RED_RUN)
  check(ok, "an empty campaign takes the Pallet start's story, the played run's (A4.7): " .. tostring(diff))
  eq(host.state.chose, "SQUIRTLE", "the starter is the one the rival counters (A4.6)")
  eq(red.c.seeded, true, "the host says it seeded the story")
  check(not (red.c:playerView(rid) or {}).opening, "a Pallet start is not in the opening")
  check(red.w.sent ~= nil and not red.w:inOpening(), "the window opened as a late one")
  eq(sent(red, "patch"), 0, "and has nothing to patch: the story is its own")
  eq(sent(red, "holdings"), 0, "nor holdings to send: the host has them")
  eq(red.save.flags.EVENT_GOT_STARTER, true, "the starter's flags stay")

  -- a guest brings a solo save into the campaign that has a story
  local brought = Start.brought(soloSave("MISTY", 4242))
  local blue = window(hub, "MISTY", "d2", brought)
  pump(host, { red, blue }, 12)
  local bid = blue.c.player
  eq(sent(blue, "start"), 1, "the brought save goes to the host whole")
  local bp = host.state:player(bid)
  check(bp.world ~= nil, "the host keeps it")
  eq(bp.trainer, 4242, "with its trainer id (A4.2)")
  eq(bp.world.party[1].level, 24, "its team")
  eq(bp.world.boxes[1][1].species, "RATTATA", "its PC")
  eq(bp.world.money, 12345, "its money")
  eq(bp.world.player.map, "CERULEAN_CITY", "its place")
  eq(bp.world.player.id, 4242, "its trainer id in the world")
  eq(host.state.story["flags/EVENT_BEAT_MISTY"], nil,
     "a campaign with a story does not take a brought save's (A4.3)")
  eq(host.state.chose, "SQUIRTLE", "nor its starter for the rival")
  eq(blue.save.flags.EVENT_BEAT_MISTY, nil, "the window takes the campaign's story over its own")
  eq(blue.save.inventory.CASCADEBADGE, nil, "badges are the story's")
  eq(blue.save.objectToggles.OAKS_LAB.OAKSLAB_OAK1, true, "the campaign's lab")
  eq(blue.save.flags.EVENT_CHOSE_SQUIRTLE, true, "its starter flag stays its own")
  eq(blue.save.inventory.BICYCLE, 1, "its bag stays")
  eq(sent(red, "patch") + sent(blue, "patch"), 0, "nobody patched anything")
  eq(sent(blue, "holdings"), 0, "the host had the holdings already")

  -- a guest who plays the opening alongside
  local green = window(hub, "GREEN", "d3", F.save("GREEN", { party = {}, flags = {},
                                                              map = "REDS_HOUSE_2F" }))
  pump(host, { red, blue, green }, 8)
  eq(green.w.opening, true, "a new game still plays the opening")
  eq(sent(green, "start"), 0, "and sends no start")
end

-- the first player of a new campaign who brings a save brings its story (A4.3) ------
do
  local host, hub = startHost()
  local green = window(hub, "GREEN", "d3", F.save("GREEN", { party = {}, flags = {},
                                                              map = "REDS_HOUSE_2F" }))
  pump(host, { green }, 6)
  eq(green.w.opening, true, "GREEN plays the opening on a campaign with no story yet")
  local misty = window(hub, "MISTY", "d2", Start.brought(soloSave("MISTY", 4242)))
  pump(host, { green, misty }, 12)
  eq(host.state.story["flags/EVENT_BEAT_MISTY"], true, "the brought save's story is the campaign's")
  eq(host.state.story["inventory/CASCADEBADGE"], 1, "its badges")
  eq(host.state.story["defeatedTrainers/PEWTER_GYM_obj_1"], true, "its beaten trainers")
  eq(host.state.story["flags/EVENT_IN_SAFARI_ZONE"], nil, "not a walk flag (A5.13)")
  eq(host.state.story["flags/EVENT_GOT_STARTER"], nil, "nor its starter")
  eq(host.state.chose, "SQUIRTLE", "its starter is the rival's counter")
  eq(misty.c.seeded, true, "the host says so")
  check(host.state:applied("gift:BICYCLE"), "its key items join the late joiner's list (A6.5)")
  local gp = host.state:player(green.c.player)
  local owed = false
  for _, g in ipairs(gp.gifts) do if g.item == "BICYCLE" then owed = true end end
  check(owed, "and are owed to the player already in")
  eq(misty.save.flags.EVENT_BEAT_MISTY, true, "the window keeps its own story")
  eq(misty.save.inventory.CASCADEBADGE, 1, "and its badges")
  eq(sent(misty, "patch"), 0, "with no patch")
end

-- a returning player is never replaced by a brought save (A4.3) ----------------------
do
  local mine = F.save("RED", { trainer = 111, money = 777 })
  local host, hub = startHost({ { id = "p00000abc", name = "RED", world = mine } })
  local red = window(hub, "RED", "d1", Start.brought(soloSave("RED", 999)), { [CID] = "p00000abc" })
  pump(host, { red }, 12)
  eq(red.c.player, "p00000abc", "RED came back as themself")
  eq(sent(red, "start"), 1, "a start was sent")
  local cp = host.state:player("p00000abc")
  eq(cp.world.money, 777, "the host keeps RED's world")
  eq(cp.trainer, 111, "and trainer")
  eq(red.w.refused, "returning", "the window hears why")
  pump(host, { red }, 70)
  eq(sent(red, "patch") + sent(red, "holdings"), 0, "and sends nothing more")
  eq(host.state:player("p00000abc").world.money, 777, "so RED's world stays")
end

-- a start whose answer was lost with its link is not refused on the next one ---------
do
  local host, hub = startHost()
  local red = window(hub, "ASH", "d1", pallet("ASH", "BULBASAUR"))
  pump(host, { red }, 3)
  local rid = red.c.player
  -- the start goes out; the link drops before its answer comes back
  red.c:update(); host:update()
  red.w:update({ save = red.save, map = red.map, still = true })
  eq(sent(red, "start"), 1, "the start went out")
  host:update()
  check(host.state:player(rid).world ~= nil, "and the host kept it")
  local c2 = Client.new(hub:dial(), { name = "ASH", game = "red", sha1 = SHA, build = "test",
                                      device = "d1", clock = now, known = { [CID] = rid } })
  c2:join()
  red.c.conn:close()
  red.c, red.w.client = c2, c2
  local send = c2.send
  c2.send = function(self, msg)
    red.sent[#red.sent + 1] = msg.type
    return send(self, msg)
  end
  pump(host, { red }, 12)
  eq(sent(red, "start"), 2, "the window sent it again on the new link")
  eq(red.w.refused, nil, "the host's `returning` there means the first went through")
  check(red.w.sent ~= nil, "the window opened")
  eq(host.state.chose, "BULBASAUR", "with the campaign's rival counter set")
end

T.finish()
