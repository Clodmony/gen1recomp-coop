-- The launcher's SAVES page (#6), ROM-free with fixture saves: the slots of
-- a game listed with name, badges, Pokédex and time, the active one and a
-- campaign's marked; PLAY makes a slot active; NEW SAVE adds one; DELETE
-- asks first; a .sav in the cartridge's format imports into a new slot
-- (an oversized one after a question) and any slot exports to one, and
-- the two round trip.  The Gen 1 codec reads the fixture dataset.
--   luajit tests/coop/saves_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq
local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
local SaveConvert = require("src.save_convert.SaveConvert")
local GenSave = require("src.save_convert.GenSave")
local GameVersion = require("src.core.GameVersion")
local G1 = require("tests.fixtures.save.gen1_build")
local Text = require("src.coop.launcher.Text")
Text.set("en")
local Saves = require("src.coop.launcher.Saves")
local Menu = require("src.coop.launcher.Menu")

-- the codec's crosswalk from the fixture dataset (no ROM cache here)
do
  local stub = {}
  for _, name in ipairs({ "pokemon", "moves", "items", "maps", "encounters", "field",
                          "text_pointers", "trainer_headers", "tilesets" }) do
    local chunk = loadfile("tests/fixture_data/" .. name .. ".lua")
    if chunk then stub[name] = chunk() end
  end
  SaveConvert.setGen1DataStub(stub, "red")
end

local function memfs(files)
  return {
    files = files,
    write = function(path, content) files[path] = content return true end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil return true end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
    createDirectory = function() return true end,
    getSaveDirectory = function() return "/fake/save" end,
  }
end

local function fresh()
  local files = {}
  love.filesystem = memfs(files)
  SaveData.resetSlotState()
  SaveData.invalidateOptionsCache()
  GameVersion.set("red")
  return files
end

-- a minimal decodable Red save (as tests/engine/save_slots.lua makes them)
local function luaSave(name, badges, playTime)
  local inv = {}
  for _, id in ipairs(badges or {}) do inv[id] = true end
  return { version = "red", player = { name = name, map = "PALLET_TOWN", x = 1, y = 1 },
           pokedex = { seen = {}, owned = { PIKACHU = true } }, inventory = inv, playTime = playTime or 0 }
end

local campaigns = {}
local function newSaves(version)
  return Saves.new({
    version = version or "red",
    campaignOf = function(slotId) return campaigns[slotId] end,
  })
end

local function ids(s)
  local out = {}
  for _, r in ipairs(s:items()) do out[#out + 1] = r.id .. (r.slot and (":" .. r.slot) or "") end
  return table.concat(out, ",")
end

local function pick(s, id, slot)
  for i, r in ipairs(s:items()) do
    if r.id == id and (slot == nil or r.slot == slot) then
      s.cursor = i
      return s:press("a")
    end
  end
  error("no row " .. id .. " " .. tostring(slot))
end

-- 1. no saves yet -------------------------------------------------------------
do
  fresh()
  local s = newSaves()
  eq(#s:details().slots, 0, "a fresh game lists no slot")
  eq(ids(s), "new,import", "only NEW SAVE and IMPORT .SAV")
end

-- 2. two saves, the active one and a campaign's marked --------------------
do
  local files = fresh()
  local a = SaveData.createSlot("red")
  SaveData.writeSlot("red", a, luaSave("ASH", { "BOULDERBADGE", "CASCADEBADGE" }, 3661))
  local b = SaveData.createSlot("red")
  SaveData.writeSlot("red", b, luaSave("MISTY", {}, 125))
  SaveData.setActiveSlot("red", b)
  campaigns[b] = "SUNDAY RUN"
  local s = newSaves()
  local d = s:details()
  eq(#d.slots, 2, "two slots")
  eq(d.slots[1].name .. "/" .. d.slots[1].badges .. "/" .. d.slots[1].dex .. "/" .. d.slots[1].time,
    "ASH/2/1/1:01", "name, badges, Pokédex and time as the continue screen shows them")
  eq(d.slots[2].name, "MISTY", "the second slot")
  eq(d.slots[1].active, false, "slot 1 is not the active one")
  eq(d.slots[2].active, true, "slot 2 is")
  eq(d.slots[2].campaign, "SUNDAY RUN", "and belongs to a campaign")
  eq(d.slots[1].campaign, nil, "slot 1 is a solo save")
  eq(ids(s), "play:" .. a .. ",export:" .. a .. ",delete:" .. a .. ",export:" .. b .. ",delete:" .. b .. ",new,import",
    "PLAY, EXPORT and DELETE per solo slot; a campaign's slot plays from its campaign")
  -- a campaign's world (a 40-row bag) never goes to a cartridge save (#16, A6.8)
  for _, r in ipairs(s:items()) do
    if r.id == "export" then
      eq(r.enabled, r.slot == a, "EXPORT is offered for the solo slot only: " .. r.slot)
    end
  end
  eq(pick(s, "export", b), nil, "EXPORT on a campaign's slot does nothing")
  eq(s.notice, nil, "and writes nothing")
  -- PLAY makes the slot active and boots the game on it
  local cmd = pick(s, "play", a)
  eq(cmd and cmd.kind .. "/" .. cmd.version .. "/" .. tostring(cmd.newGame), "boot/red/false",
    "PLAY boots the game to continue")
  eq(SaveData.activeSlot("red"), a, "on that slot")
  -- NEW SAVE adds an empty slot and boots on it
  cmd = pick(s, "new")
  eq(cmd and cmd.kind, "boot", "NEW SAVE boots")
  local active = SaveData.activeSlot("red")
  check(active ~= a and active ~= b, "on a new slot")
  eq(#s:details().slots, 3, "three slots now")
  eq(s:details().slots[3].exists, false, "the new one is empty")
  eq(s:details().slots[3].name, nil, "and has no name")
  -- DELETE asks first
  campaigns[b] = nil
  pick(s, "delete", a)
  eq(s.screen, "delete", "DELETE opens the question")
  check(s:prompt():find("ASH", 1, true), "naming the save")
  eq(ids(s), "confirm,cancel", "with DELETE and CANCEL")
  pick(s, "cancel")
  eq(s.screen, "list", "CANCEL goes back")
  eq(#s:details().slots, 3, "and keeps the save")
  pick(s, "delete", a)
  pick(s, "confirm")
  eq(s.screen, "list", "DELETE goes back to the list")
  eq(#s:details().slots, 2, "one slot fewer")
  eq(files["saves/red/" .. a .. ".lua"], nil, "the file is gone")
  check(s.notice and s.notice:find("ASH", 1, true), "and the page says so")
  s.notice = nil
  -- deleting the active slot moves the active pointer, never to a ghost
  pick(s, "delete", active)
  pick(s, "confirm")
  eq(SaveData.activeSlot("red"), b, "deleting the active slot makes another active")
end

-- 3. a .sav imports into a new slot; an oversized one after a question;
-- garbage is refused ---------------------------------------------------------
do
  fresh()
  local s = newSaves()
  pick(s, "import")
  eq(s.screen, "import", "IMPORT .SAV opens the import screen")
  local bytes = G1.build({ player = "BRIO", badges = 0x07, money = 12345, playTime = { 2, 0, 30, 0, 0 } })
  eq(#bytes, 32768, "the fixture save is a cartridge image")
  check(s:importData(bytes, "brio.sav"), "the bytes are taken")
  eq(s.screen, "list", "back on the list")
  local d = s:details()
  eq(#d.slots, 1, "one slot now")
  eq(d.slots[1].name .. "/" .. d.slots[1].badges .. "/" .. d.slots[1].time, "BRIO/3/2:30",
    "with the save's trainer, badges and time")
  eq(d.slots[1].active, true, "and it is the active slot")
  check(s.notice and s.notice:find("BRIO", 1, true), "the page says what came in")
  s.notice = nil
  -- oversized: a question first
  pick(s, "import")
  check(not s:importData(bytes .. ("\0"):rep(18), "big.sav") or s.screen == "confirm",
    "an oversized file asks first")
  eq(s.screen, "confirm", "on the question screen")
  check(s:prompt():find("32786", 1, true), "naming the size")
  pick(s, "cancel")
  eq(#s:details().slots, 1, "CANCEL imports nothing")
  pick(s, "import")
  s:importData(bytes .. ("\0"):rep(18), "big.sav")
  pick(s, "confirm")
  eq(#s:details().slots, 2, "IMPORT takes the first 32 KB")
  eq(s:details().slots[2].name, "BRIO", "and the save is whole")
  s.notice = nil
  -- garbage
  pick(s, "import")
  check(s:importData(("x"):rep(100), "notes.txt"), "a wrong file is answered")
  eq(#s:details().slots, 2, "and imports nothing")
  check(s.notice ~= nil, "with a reason")
  eq(s.screen, "import", "staying on the import screen")
  s:press("b")
  eq(s.notice, nil, "B closes the reason")
  s:press("b")
  eq(s.screen, "list", "and B again leaves the import screen")
end

-- 4. export: any slot, the active one untouched; and the round trip ----------
do
  local files = fresh()
  local s = newSaves()
  pick(s, "import")
  s:importData(G1.build({ player = "BRIO", badges = 0x07, money = 12345 }), "brio.sav")
  local first = SaveData.activeSlot("red")
  pick(s, "import")
  s:importData(G1.build({ player = "VALE", badges = 0x01, money = 500 }), "vale.sav")
  local second = SaveData.activeSlot("red")
  s.notice = nil
  pick(s, "export", first)
  local path = "exports/red/gen1recomp-red-" .. first .. ".sav"
  check(files[path] ~= nil, "EXPORT writes the slot's .sav")
  eq(#(files[path] or ""), 32768, "a cartridge image")
  eq(SaveConvert.mainChecksumValid(files[path], "red"), true, "with a valid checksum")
  eq(SaveData.activeSlot("red"), second, "the active slot is unchanged")
  check(s.notice and s.notice:find(first, 1, true), "the page names the file")
  -- the round trip: the export imports as the same save
  s.notice = nil
  pick(s, "import")
  s:importData(files[path], "again.sav")
  local d = s:details()
  eq(#d.slots, 3, "the export came back in")
  eq(d.slots[3].name .. "/" .. d.slots[3].badges, "BRIO/3", "as the same trainer with the same badges")
  local save = SaveSerializer.decode(files["saves/red/" .. SaveData.activeSlot("red") .. ".lua"])
  eq(save and save.money, 12345, "and the same money")
end

-- 5. in the menu: from the solo sheet, back with B ---------------------------
do
  fresh()
  local m = Menu.new({
    ready = function() return true end,
    saveInfo = function() return nil end,
    saves = function(version) return newSaves(version) end,
  })
  m:go("solo")
  local found
  for i, r in ipairs(m:items()) do if r.id == "saves" then found = i end end
  check(found ~= nil, "the solo sheet offers SAVES")
  m.cursor = found
  m:press("a")
  eq(m.screen, "saves", "which opens the saves page")
  local rows = {}
  for _, r in ipairs(m:items()) do rows[#rows + 1] = r.id end
  eq(table.concat(rows, ","), "new,import", "with the saves model's rows")
  m:press("b")
  eq(m.screen, "solo", "B goes back to the solo sheet")
end

T.finish()
