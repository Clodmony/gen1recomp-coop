-- The campaign state and its file (#13, design A3.1 to A3.9): the
-- campaign and player sections, uids, exactly-once commits, the versioned
-- file with its .tmp, read-back and .bak, refusals of an unreadable or a
-- newer file, migrations, the journal and the host's save cadence.
-- ROM-free.
--   luajit tests/coop/campaign_file_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local F = require("tests.coop.support.campaign_fixture")
local Json = require("src.link.Json")
local World = require("src.coop.campaign.World")
local Campaign = require("src.coop.campaign.Campaign")
local CampaignFile = require("src.coop.campaign.CampaignFile")
local Store = require("src.coop.campaign.Store")

local CID = "c00000000000000a1"
local P1, P2 = "p00000001", "p00000002"
local SHA = ("ab"):rep(20)

local function newCampaign()
  local c = Campaign.new({ id = CID, title = "KANTO", game = "red", sha1 = SHA, created = 1 })
  c:addPlayer({ id = P1, name = "RED", game = "red" })
  c:addPlayer({ id = P2, name = "BLUE", game = "red" })
  return c
end

-- the world: the game's own save text, checked ------------------------------
do
  local save = F.save("RED")
  local text = World.encode(save)
  check(not text:find("textSpeed"), "a world travels without the device's options")
  local back = World.decode(text)
  eq(back and back.player.name, "RED", "a world reads back")
  eq(back and back.money, 3000, "with its money")
  eq(select(2, World.decode("return { player = 1 }")), "no player", "a world needs a player")
  local big = F.save("RED", { party = { F.mon("A"), F.mon("B"), F.mon("C"), F.mon("D"),
                                        F.mon("E"), F.mon("F"), F.mon("G") } })
  eq(select(2, World.decode(World.encode(big))), "party", "a team of seven is refused")
  local badBox = F.save("RED")
  badBox.boxes[3] = {}
  for i = 1, 21 do badBox.boxes[3][i] = F.mon("RATTATA") end
  eq(select(2, World.decode(World.encode(badBox))), "box", "a box of 21 is refused")
  local negative = F.save("RED", { money = -5 })
  eq(select(2, World.decode(World.encode(negative))), "money", "negative money is refused")
  eq(select(2, World.decode("os.exit()")), "not a save", "code is never run")
  eq(select(2, World.decode(("x"):rep(World.MAX_TEXT + 1))), "too long", "a world has a size cap")
  local rest, boxes = World.split(save)
  local joined = World.join(rest, boxes)
  eq(joined and #joined.boxes, 12, "the PC splits off and joins back")
end

-- sections, uids, commits ---------------------------------------------------
do
  local c = newCampaign()
  local r0 = c.revision
  local save = F.save("RED", { party = { F.mon("BULBASAUR"), F.mon("PIDGEY") } })
  check(c:setWorld(P1, save), "a player's world is taken")
  check(c.revision > r0, "the revision moves")
  local p1 = c:player(P1)
  eq(p1.trainer, 12345, "the in-game trainer id comes from the world")
  eq(p1.world.party[1].coopUid, P1 .. ":1", "each Pokémon gets a uid <player>:<serial>")
  eq(p1.world.party[2].coopUid, P1 .. ":2", "the next serial")
  eq(p1.world.options, nil, "the options are not the campaign's")

  -- the window saves again: its Pokémon carry their uids, a new catch does not
  local again = World.decode(World.encode(p1.world))
  local caught = F.mon("RATTATA")
  again.boxes[1][1] = table.remove(again.party, 2) -- PIDGEY deposited
  again.party[2] = caught
  c:setWorld(P1, again)
  eq(c:player(P1).world.boxes[1][1].coopUid, P1 .. ":2", "a deposit keeps its uid")
  eq(c:player(P1).world.party[2].coopUid, P1 .. ":3", "a catch gets a new uid")

  -- a window that never heard of the uid: matched by its fingerprint
  local stale = World.decode(World.encode(c:player(P1).world))
  stale.party[2].coopUid = nil
  stale.party[2].species = "RATICATE" -- it evolved
  c:setWorld(P1, stale)
  eq(c:player(P1).world.party[2].coopUid, P1 .. ":3", "an evolved Pokémon keeps its uid by fingerprint")

  -- twins: two Pokémon with one fingerprint keep two uids
  local twin = F.mon("MAGIKARP", 5, { dvs = { attack = 1, defense = 1, speed = 1, special = 1 } })
  local twin2 = F.mon("MAGIKARP", 5, { dvs = { attack = 1, defense = 1, speed = 1, special = 1 } })
  local w = World.decode(World.encode(c:player(P1).world))
  w.party[3], w.party[4] = twin, twin2
  c:setWorld(P1, w)
  local u3, u4 = c:player(P1).world.party[3].coopUid, c:player(P1).world.party[4].coopUid
  check(u3 ~= u4, "twins get two uids")
  local w2 = World.decode(World.encode(c:player(P1).world))
  w2.party[3].coopUid, w2.party[4].coopUid = nil, nil
  c:setWorld(P1, w2)
  local v3, v4 = c:player(P1).world.party[3].coopUid, c:player(P1).world.party[4].coopUid
  check(v3 ~= v4 and (v3 == u3 or v3 == u4) and (v4 == u3 or v4 == u4),
        "twins without uids get their two uids back")
  -- a copied uid is kept once
  local dup = World.decode(World.encode(c:player(P1).world))
  dup.party[5] = World.decode(World.encode({ player = {}, party = { dup.party[1] } })).party[1]
  dup.party[5].species = "MEW"
  dup.party[5].otId = 999
  c:setWorld(P1, dup)
  check(c:player(P1).world.party[5].coopUid ~= c:player(P1).world.party[1].coopUid,
        "a uid twice in one world is kept for the first only")
  local serialBefore = c:player(P1).serial
  check(serialBefore >= 4, "serials only grow")

  -- exactly-once commits (design A3.3)
  local given = 0
  check(c:commit("gift:BICYCLE", function() given = given + 1 end), "a commit applies")
  check(not c:commit("gift:BICYCLE", function() given = given + 1 end), "a repeat returns false")
  eq(given, 1, "and changes nothing")
  check(c:applied("gift:BICYCLE"), "the id is remembered")
  check(not pcall(c.commit, c, "party[1]", function() end), "a commit id is a kind and a stable key")
  check(c:commit("victory:BROCK", nil), "a victory commit")
end

-- the file: write, read back, .bak, refusals ---------------------------------
do
  local fs = F.memFs()
  local c = newCampaign()
  c:setWorld(P1, F.save("RED"))
  c:commit("gift:TOWN_MAP")
  local main, bak, tmp, journal = CampaignFile.paths("red", CID)
  eq(main, "coop/campaigns/red/" .. CID .. ".campaign", "one file per campaign under its game")
  check(CampaignFile.write(fs, c), "a checkpoint writes")
  check(fs.files[main] and not fs.files[tmp], "through .tmp into place")
  eq(fs.files[bak], nil, "no backup of nothing")
  local text = fs.files[main]
  local data = Json.decode(text)
  eq(data.format, CampaignFile.FORMAT, "the file names its format")
  eq(data.version, CampaignFile.VERSION, "and its version")
  eq(#data.players, 2, "a section per player, never one merged save")
  check(type(data.players[1].world) == "string" and data.players[1].boxes, "a world and its PC")
  eq(data.players[2].world, nil, "a player who never saved has no world")

  local back = CampaignFile.read(fs, "red", CID)
  check(back ~= nil, "it reads back")
  eq(back.revision, c.revision, "at its revision")
  check(back:applied("gift:TOWN_MAP"), "with its commits")
  eq(back:player(P1).world.party[1].coopUid, P1 .. ":1", "and its uids")
  eq(back:player(P1).serial, c:player(P1).serial, "and the serials")
  eq(back:player(P2).name, "BLUE", "and every player")

  -- the second checkpoint keeps the first as .bak
  c:commit("gift:BICYCLE")
  check(CampaignFile.write(fs, c), "a second checkpoint")
  eq(fs.files[bak], text, "the replaced file is the .bak")

  -- a failed write leaves the old file as it was
  local before = fs.files[main]
  c:commit("gift:SS_TICKET")
  fs.failWrite[tmp] = true
  local ok, why = CampaignFile.write(fs, c)
  check(not ok and why == "write failed", "a failed write says so")
  eq(fs.files[main], before, "and the file is untouched")
  fs.failWrite[tmp] = nil

  -- the .tmp must read back as this campaign
  local realWrite = fs.write
  fs.write = function(p, t) if p == tmp then t = t:sub(1, math.floor(#t / 2)) end return realWrite(p, t) end
  ok, why = CampaignFile.write(fs, c)
  check(not ok and why == "read back failed", "a torn .tmp is caught on read back")
  eq(fs.files[main], before, "and the file is untouched")
  eq(fs.files[tmp], nil, "the torn .tmp is removed")
  fs.write = realWrite

  -- without rename (a system without it): the file written in place
  fs.noRename = true
  check(CampaignFile.write(fs, c), "a checkpoint without rename")
  check(CampaignFile.read(fs, "red", CID):applied("gift:SS_TICKET"), "still reads")
  eq(fs.files[tmp], nil, "and the .tmp is gone")
  fs.noRename = false

  -- cut off between the backup and the rename: the checked .tmp is read
  c:commit("gift:HM01")
  fs.failRenameTo = main
  fs.failWrite[main] = true
  check(not CampaignFile.write(fs, c), "a swap cut off")
  fs.failRenameTo, fs.failWrite[main] = nil, nil
  eq(fs.files[main], nil, "left no file")
  local rec, info = CampaignFile.read(fs, "red", CID)
  check(rec and rec:applied("gift:HM01"), "the .tmp is the newest checkpoint")
  eq(info.recovered, "tmp", "and says so")

  -- an unreadable file is refused and left as it is; the launcher names the backup
  check(CampaignFile.write(fs, c), "a checkpoint again")
  fs.files[main] = "{ not json"
  local none, why2 = CampaignFile.read(fs, "red", CID)
  eq(none, nil, "an unreadable file is refused")
  eq(why2.why, "unreadable", "as unreadable")
  eq(why2.backup, bak, "naming the backup")
  eq(fs.files[main], "{ not json", "and left as it is")

  -- a file of a newer format is refused without touching it
  local newer = Json.decode(fs.files[bak])
  newer.version = CampaignFile.VERSION + 1
  fs.files[main] = Json.encode(newer)
  local keep = fs.files[main]
  local n2, why3 = CampaignFile.read(fs, "red", CID)
  eq(n2, nil, "a newer file is refused")
  eq(why3.why, "newer", "as newer")
  eq(fs.files[main], keep, "and is untouched")

  -- a replaced file that does not read is not kept as .bak
  fs.files[main] = "garbage"
  local oldBak = fs.files[bak]
  check(CampaignFile.write(fs, c), "writing over a broken file")
  eq(fs.files[bak], oldBak, "keeps the last good .bak")

  -- not a campaign file, or another campaign's
  fs.files[main] = Json.encode({ format = "something else", version = 1 })
  eq(select(2, CampaignFile.read(fs, "red", CID)).why, "unreadable", "another format is unreadable")
  eq(select(2, CampaignFile.read(fs, "red", "c0000000000000bb")).why, "missing", "no file: missing")
  eq(select(2, CampaignFile.read(fs, "red", "../x")).why, "missing", "a bad id reads nothing")
end

-- migrations, step by step ---------------------------------------------------
do
  local saved = CampaignFile.VERSION
  local m1, m2 = CampaignFile.MIGRATIONS[1], CampaignFile.MIGRATIONS[2]
  local steps = {}
  CampaignFile.VERSION = 3
  CampaignFile.MIGRATIONS[1] = function(d) steps[#steps + 1] = 1; d.campaign.title = "STEP1"; return d end
  CampaignFile.MIGRATIONS[2] = function(d) steps[#steps + 1] = 2; d.campaign.title = d.campaign.title .. "+2"; return d end
  local c = newCampaign()
  local data = c:snapshot()
  data.format, data.version = CampaignFile.FORMAT, 1
  local m = CampaignFile.decode(Json.encode(data))
  eq(table.concat(steps, ","), "1,2", "an old file is migrated one version at a time")
  eq(m and m.title, "STEP1+2", "each step sees the last one's result")
  CampaignFile.VERSION = saved
  CampaignFile.MIGRATIONS[1], CampaignFile.MIGRATIONS[2] = m1, m2
end

-- the journal ---------------------------------------------------------------
do
  local fs = F.memFs()
  local c = newCampaign()
  local bigBox = F.save("RED")
  for i = 1, 20 do bigBox.boxes[1][i] = F.mon("RATTATA") end
  c:setWorld(P1, bigBox)
  local clock = 0
  local store = Store.new({ campaign = c, fs = fs, clock = function() return clock end })
  check(store:checkpoint("start"), "the first checkpoint")
  local _, _, _, journal = CampaignFile.paths("red", CID)

  store:poll(false)
  eq(fs.files[journal], nil, "no line while nothing changed")

  clock = 1
  c:commit("gift:POKEDEX")
  store:poll(true) -- a battle runs: no autosave, but a line
  local lines = fs.files[journal]
  check(lines and lines:sub(1, 1) == "\n", "a line starts with a newline")
  local line = Json.decode(lines:sub(2))
  eq(line.campaign.revision, c.revision, "a line carries the revision")
  eq(line.players[1].boxes, nil, "an unchanged PC is left out")
  check(line.players[1].world, "the rest of the world is in")
  store:poll(true)
  eq(fs.files[journal], lines, "no second line while nothing moved")

  -- the PC changed: it goes into the next line
  local w = World.decode(World.encode(c:player(P1).world))
  w.boxes[2][1] = table.remove(w.boxes[1], 1)
  c:setWorld(P1, w)
  store:poll(true)
  local second = Json.decode(fs.files[journal]:match("\n([^\n]+)$"))
  check(second.players[1].boxes ~= nil, "a changed PC is in the line")

  -- reading: the checkpoint, then the newest whole line
  local r, info = CampaignFile.read(fs, "red", CID)
  check(info.journal, "the journal is applied")
  eq(r.revision, c.revision, "up to the newest line")
  check(r:applied("gift:POKEDEX"), "with the commit")
  eq(#r:player(P1).world.boxes[1], 19, "and the PC from the line")
  eq(r:player(P1).world.boxes[2][1].coopUid, w.boxes[2][1].coopUid, "a moved Pokémon keeps its uid")

  -- the first line's PC came from the checkpoint
  local firstOnly = F.memFs()
  for k, v in pairs(fs.files) do firstOnly.files[k] = v end
  firstOnly.files[journal] = lines
  local r1 = CampaignFile.read(firstOnly, "red", CID)
  eq(#r1:player(P1).world.boxes[1], 20, "a line without a PC takes the checkpoint's")

  -- a torn last line is skipped
  c:commit("gift:OAKS_PARCEL")
  store:poll(true)
  local full = fs.files[journal]
  fs.files[journal] = full:sub(1, #full - 40)
  local r2 = CampaignFile.read(fs, "red", CID)
  check(not r2:applied("gift:OAKS_PARCEL") and r2:applied("gift:POKEDEX"),
        "a torn last line is skipped, the one before it read")
  -- a line after a torn one still reads (each line starts with a newline)
  fs.files[journal] = full:sub(1, #full - 40)
  c:commit("gift:BIKE_VOUCHER")
  store.journalRevision = nil
  store:poll(true)
  local r3 = CampaignFile.read(fs, "red", CID)
  check(r3:applied("gift:BIKE_VOUCHER"), "a whole line after a torn one reads")

  -- another campaign's or an older line is ignored
  local other = Campaign.new({ id = "c00000000000000b2", title = "X", game = "red" })
  other.revision = 10 ^ 6
  CampaignFile.appendJournal(fs, other, {})
  local r4 = CampaignFile.read(fs, "red", CID)
  eq(r4.id, CID, "another campaign's line is not read")
  eq(r4.revision, c.revision, "the newest own line wins")

  -- a checkpoint deletes the journal
  check(store:checkpoint("menu"), "a checkpoint")
  eq(fs.files[journal], nil, "deletes the journal")
end

-- the host's cadence ------------------------------------------------------------
do
  local fs = F.memFs()
  local c = newCampaign()
  local clock = 100
  local store = Store.new({ campaign = c, fs = fs, clock = function() return clock end })
  local main = CampaignFile.path("red", CID)
  local function revOnDisk()
    local d = fs.files[main] and Json.decode(fs.files[main])
    return d and d.campaign.revision
  end
  store:poll(false)
  eq(revOnDisk(), c.revision, "a changed campaign that was never saved saves")
  c:commit("gift:A")
  clock = 110
  store:poll(false)
  check(revOnDisk() ~= c.revision, "not again within 30 s")
  clock = 130
  store:poll(false)
  eq(revOnDisk(), c.revision, "after 30 s with a change, it saves")
  clock = 200
  store:poll(false)
  eq(store.lastReason, "autosave", "nothing changed: no save")
  local writes = fs.writes
  store:poll(false)
  eq(fs.writes, writes, "an unchanged campaign is not written")
  -- a battle: no autosave while it runs, a save when the last one ends
  c:commit("gift:B")
  clock = 300
  store:poll(true)
  check(revOnDisk() ~= c.revision, "no autosave while a battle runs")
  clock = 301
  store:poll(false)
  eq(revOnDisk(), c.revision, "the save when the last battle ends")
  eq(store.lastReason, "battle_end", "named battle_end")
  eq(math.floor(store:savedAgo()), 0, "saved just now")
  clock = 340
  eq(math.floor(store:savedAgo()), 39, "seconds since the last save")
end

T.finish()
