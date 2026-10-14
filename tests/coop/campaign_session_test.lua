-- The campaign in a running session (#13, design A3.7 to A3.12): the host
-- hands each player their world, takes a window's world and its save
-- requests, refuses a save while a battle runs, saves by itself (a battle's
-- end, every 30 s of changes, a leave, shutdown, a pause), and a host
-- started again from the file gives each player their world back.  Host
-- and clients in one process over the loopback transport.  ROM-free.
--   luajit tests/coop/campaign_session_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local F = require("tests.coop.support.campaign_fixture")
local Json = require("src.link.Json")
local Transport = require("src.coop.session.Transport")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local World = require("src.coop.campaign.World")
local Campaign = require("src.coop.campaign.Campaign")
local CampaignFile = require("src.coop.campaign.CampaignFile")
local Store = require("src.coop.campaign.Store")

local SHA = ("ab"):rep(20)
local CID = "c0123456789abcdef"
local clock = 0
local function now() return clock end
local idCounter = 0
local function hex(n)
  idCounter = idCounter + 1
  return ("%0" .. n .. "x"):format(idCounter)
end

local fs = F.memFs()
local main, bak, _, journal = CampaignFile.paths("red", CID)

local function startHost(state)
  local c = state or Campaign.new({ id = CID, title = "KANTO", game = "red", sha1 = SHA })
  local store = Store.new({ campaign = c, fs = fs, clock = now, saved = state ~= nil })
  local host = Host.new({ campaign = { id = CID, title = "KANTO" },
                          cartridge = { game = "red", sha1 = SHA }, clock = now, hex = hex,
                          state = c, store = store, build = "test" })
  return host, host:serve(Transport.loopback()), store
end

local function client(hub, name, known, device)
  return Client.new(hub:dial(), { name = name, game = "red", sha1 = SHA, build = "test",
                                  device = device or "d1", known = known, clock = now })
end

local function pump(host, clients, frames)
  for _ = 1, frames or 3 do
    for _, c in ipairs(clients) do c:update() end
    host:update()
    for _, c in ipairs(clients) do c:update() end
  end
end

local function onDisk()
  return fs.files[main] and CampaignFile.decode(fs.files[main])
end

local function lastRejection(c)
  local r = c.rejections[#c.rejections]
  return r and r.reason
end

-- a new campaign: each player hears they have no world yet --------------------
local host, hub, store = startHost()
local red = client(hub, "RED", nil, "d1")
local blue = client(hub, "BLUE", nil, "d2")
red:join(); blue:join()
pump(host, { red, blue })
eq(red.status, "joined", "RED joined")
check(red.world and red.world.fresh, "a new player has no world in the campaign")
check(blue.world and blue.world.fresh and blue.world.save == nil, "nor has BLUE")
check(host.state:player(red.player), "the campaign has a section for RED")
check(host.state:player(blue.player), "and one for BLUE")
eq(red.state.busy, "", "no battle: a save would be taken")

-- a world without a save request: kept, journaled, not a checkpoint ----------
local redSave = F.save("RED", { party = { F.mon("CHARMANDER") } })
red:sendWorld(World.encode(redSave), false)
pump(host, { red, blue })
local entry = host.state:player(red.player)
eq(entry.world and entry.world.party[1].species, "CHARMANDER", "the host keeps RED's world")
eq(entry.world.party[1].coopUid, red.player .. ":1", "with uids")
eq(#red:takeSaves(), 0, "a world alone is no save")
check(fs.files[journal] or fs.files[main], "the change reached the disk (journal or autosave)")

-- START > SAVE: a checkpoint, both hear it ---------------------------------------
clock = 5
redSave.money = 4321
red:sendWorld(World.encode(redSave), true, "menu")
pump(host, { red, blue })
local rs, bs = red:takeSaves(), blue:takeSaves()
eq(#rs, 1, "the saver hears one `saved`")
check(rs[1] and rs[1].ok and rs[1].you and rs[1].by == "RED", "\"Campaign saved.\" for the saver")
check(bs[1] and bs[1].ok and not bs[1].you and bs[1].by == "RED", "\"RED saved the campaign.\" for BLUE")
eq(onDisk() and onDisk():player(red.player).world.money, 4321, "the campaign file has RED's world")
eq(fs.files[journal], nil, "a checkpoint deletes the journal")
eq(red.state.saved_ago, 0, "the state says it was saved just now")
eq(red.savedAt, 5, "the window knows when")

-- a save while a battle runs is refused and writes nothing --------------------------
host.battles.b1 = true
pump(host, { red, blue })
eq(blue.state.busy, "battle_in_progress", "the state says a save would be refused")
local diskBefore = fs.files[main]
local rev = host.state.revision
local blueSave = F.save("BLUE", { trainer = 54321, party = { F.mon("SQUIRTLE", 5, { otId = 54321 }) } })
clock = 50
blue:sendWorld(World.encode(blueSave), true, "menu")
pump(host, { red, blue })
local refused = blue:takeSaves()
check(refused[1] and not refused[1].ok and refused[1].reason == "battle_in_progress",
      "the save is refused: battle in progress")
eq(lastRejection(blue), "battle_in_progress", "and the intention rejected")
eq(#red:takeSaves(), 0, "the others hear nothing")
eq(fs.files[main], diskBefore, "nothing written")
eq(host.state.revision, rev, "nothing taken")
eq(host.state:player(blue.player).world, nil, "BLUE's world is not taken either")
-- a join pending is busy too
host.battles.b1 = nil
host.joins.j1 = true
blue:sendWorld(World.encode(blueSave), true, "menu")
pump(host, { red, blue })
eq(blue:takeSaves()[1].reason, "battle_in_progress", "a pending join refuses a save too")
host.joins.j1 = nil
-- no autosave while a battle runs, one when it ends
host.battles.b2 = true
red:sendWorld(World.encode(F.save("RED", { money = 99 })), false)
clock = 200
pump(host, { red, blue })
check(onDisk():player(red.player).world.money ~= 99, "no autosave while a battle runs")
host.battles.b2 = nil
clock = 201
pump(host, { red, blue })
eq(onDisk():player(red.player).world.money, 99, "the battle's end saves")
eq(store.lastReason, "battle_end", "as battle_end")
eq(red.state.saved_ago, 0, "and the players hear the save's age")

-- a world that is not a save is refused --------------------------------------
blue:sendWorld("return { party = 7 }", true, "menu")
pump(host, { red, blue })
eq(lastRejection(blue), "bad_world", "a broken world is refused")
eq(blue:takeSaves()[1].reason, "bad_world", "and the save with it")
blue:sendWorld("return os.exit()", false)
pump(host, { red, blue })
eq(lastRejection(blue), "bad_world", "code is never run")

-- autosave every 30 s of changes -----------------------------------------------
blue:sendWorld(World.encode(blueSave), false)
clock = 215
pump(host, { red, blue })
check(not onDisk():player(blue.player).world, "within 30 s of the last save: the journal only")
local line = fs.files[journal]
check(line and line:find(blue.player, 1, true), "BLUE's world is in the journal")
clock = 232
pump(host, { red, blue })
check(onDisk():player(blue.player).world, "30 s after the last save, it saves")
eq(store.lastReason, "autosave", "as autosave")

-- leaving saves --------------------------------------------------------------
blueSave.money = 777
blue:sendWorld(World.encode(blueSave), false)
pump(host, { red, blue })
clock = 233
local blueId = blue.player
blue:leave()
pump(host, { red })
eq(store.lastReason, "leave", "a player leaving saves the campaign")
eq(onDisk():player(blueId).world.money, 777, "with what they last sent")

-- rejoining: the world comes back -----------------------------------------------
local blue2 = client(hub, "BLUE", { [CID] = blueId }, "d2")
blue2:join()
pump(host, { red, blue2 })
eq(blue2.player, blueId, "BLUE is BLUE again")
check(blue2.world and not blue2.world.fresh, "BLUE gets a world")
local back = World.decode(blue2.world.save)
eq(back and back.money, 777, "their own")
eq(back.party[1].coopUid, blueId .. ":1", "with the uids")
eq(back.player.name, "BLUE", "not RED's")

-- pause and shutdown save ---------------------------------------------------------
red:sendWorld(World.encode(F.save("RED", { money = 1 })), false)
pump(host, { red, blue2 })
check(host:pause(), "a paused hosting app saves")
eq(store.lastReason, "pause", "as pause")
red:sendWorld(World.encode(F.save("RED", { money = 2 })), false)
pump(host, { red, blue2 })
local redId = red.player
host:shutdown("host_quit")
eq(store.lastReason, "shutdown", "shutdown saves")
eq(onDisk():player(redId).world.money, 2, "with the last world")

-- shutdown during a battle: the journal, not a checkpoint
do
  local h2 = startHost(onDisk())
  local s2 = h2.store
  local c1 = client(h2.hubs[1], "RED", { [CID] = redId }, "d1")
  c1:join()
  pump(h2, { c1 })
  h2.battles.x = true
  c1:sendWorld(World.encode(F.save("RED", { money = 3 })), false)
  pump(h2, { c1 })
  h2:shutdown("host_quit")
  check(s2.lastReason == nil, "no checkpoint while a battle runs")
  local r = CampaignFile.read(fs, "red", CID)
  eq(r:player(redId).world.money, 3, "the journal has it")
end

-- a host started from the file -------------------------------------------------
local c3, info = CampaignFile.read(fs, "red", CID)
check(c3 and info, "the campaign reads")
local h3 = startHost(c3)
eq(#h3.players, 2, "its players are known")
check(not h3.players[1].connected, "and away")
local red3 = client(h3.hubs[1], "RED", { [redId] = nil, [CID] = redId }, "d1")
red3:join()
pump(h3, { red3 })
eq(red3.player, redId, "RED gets RED back")
eq(World.decode(red3.world.save).money, 3, "with their world")
-- a new player in an old campaign
local green = client(h3.hubs[1], "GREEN", nil, "d3")
green:join()
pump(h3, { red3, green })
check(green.world.fresh, "a new player starts without a world")

-- the file's shape: one section per player ------------------------------------------
local data = Json.decode(fs.files[main])
eq(#data.players, 3, "a section per player, GREEN included")
check(data.players[1].world ~= data.players[2].world, "each their own world")
check(fs.files[bak], "the replaced file is kept as .bak")

T.finish()
