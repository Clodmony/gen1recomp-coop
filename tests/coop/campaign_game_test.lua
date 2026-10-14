-- The campaign in the game (#13, design A3.10 to A3.12, A3.14), ROM-free:
-- the fixture overworld runs headless with this device hosting a session
-- in-process and a partner on its loopback hub.  The game's save sends its
-- world to the host and saves the campaign; START > SAVE while a battle runs
-- fails in the save box with no YES/NO and writes nothing; the notices say
-- who saved; the CO-OP box shows the last save; a paused hosting app saves;
-- the launcher puts the player's world from the campaign into the
-- campaign's slot.
--   luajit tests/coop/campaign_game_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local check, eq = T.check, T.eq

local Data = T.fixtures.fresh()
Data.tilesets.FIX_OUT.tilesPerRow = 16
Data.field.flyWarps = Data.field.flyWarps or {}
Data.field.playerSprites = { walk = "SPRITE_FIX_PLAYER", bike = "SPRITE_FIX_NPC" }
Data.field.waterTilesets = {}
Data.field.forcedMovement = { tiles = {} }

local Game       = require("src.core.Game")
local Input      = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local Renderer   = require("src.render.Renderer")
local SaveData   = require("src.core.SaveData")
local Pokemon    = require("src.pokemon.Pokemon")
local OW         = require("src.world.OverworldController")

local Identity = require("src.coop.session.Identity")
local Session  = require("src.coop.session.Session")
local Client   = require("src.coop.session.Client")
local Presence = require("src.coop.game.Presence")
local Notices  = require("src.coop.game.Notices")
local CoopMenu = require("src.coop.game.CoopMenu")
local CampaignFile = require("src.coop.campaign.CampaignFile")
local World    = require("src.coop.campaign.World")
local StartMenu = require("src.ui.StartMenu")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.save.player.name = "HOST"
Game.save.party = { Pokemon.new(Data, "FIXMON_A", 20) }
local stack = Game.stack
stack:push(OW, "FIX_TOWN", 5, 6, "down")
Game.overworld = stack:top()

local SHA = ("ab"):rep(20)
local CID = "c00000000000000c1"
local function memoryStore()
  local text
  return { read = function() return text end, write = function(t) text = t end }
end

local function step(n)
  for _ = 1, n or 1 do
    local s = Session.current
    if s then s:update(1 / 60, Game) end
    if Presence.partner then Presence.partner:update() end
    stack:update(1 / 60)
    Presence.step(Game)
  end
end

local campaignFs = CampaignFile.loveFs()
local function onDisk()
  local c = CampaignFile.read(campaignFs, "red", CID)
  return c
end

-- solo: a save is only the game's own ----------------------------------------
check(Game:writeSave() ~= false, "a solo save writes")
eq(campaignFs.read(CampaignFile.path("red", CID)), nil, "and no campaign")
eq(require("src.coop.game.CampaignSave").refusal(Game), nil, "solo: nothing refuses a save")

-- a session: this device hosts, BLUE dials in ----------------------------------
local s = Session.startHost({
  campaign = { id = CID, title = "Fix co-op" },
  cartridge = { game = "red", sha1 = SHA }, name = "HOST",
  listen = false, beacon = false, log = false,
  identity = Identity.load(memoryStore()),
})
check(s, "hosting a new campaign")
check(campaignFs.read(CampaignFile.path("red", CID)), "a new campaign has its file at once")
step(3)
eq(s.status, "joined", "the host's own player is in")
check(s:worldReady(), "the host's player heard about their world")
eq(s:takeWorld(), nil, "none yet: a fresh start")
local blue = Client.new(s.hub:dial(), { name = "BLUE", game = "red", sha1 = SHA,
                                        device = "b1", seat = 1 })
Presence.partner = blue
blue:join()
step(3)
eq(blue.status, "joined", "BLUE joined")
Notices.clear()

-- the game's save: the world goes to the host, the campaign is saved -----------
Game.save.money = 1234
check(Game:writeSave("menu") ~= false, "the game saves")
step(3)
local c = onDisk()
local mine = c and c:player(s.client.player)
eq(mine and mine.world and mine.world.money, 1234, "the campaign file holds this player's world")
eq(mine.world.party[1].coopUid, s.client.player .. ":1", "with uids")
eq(mine.world.options, nil, "not the device's options")
eq(Notices.texts()[1], "Campaign saved.", "the saver sees \"Campaign saved.\"")
local heard = blue:takeSaves()
check(heard[1] and heard[1].ok and heard[1].by == "HOST" and not heard[1].you,
      "BLUE hears HOST saved the campaign")
eq(CoopMenu.lines(Game, s, "10.0.0.5")[3], "SAVED JUST NOW", "the CO-OP box: saved just now")
eq(CoopMenu.lines(Game, s, "10.0.0.5")[4], "AUTOSAVE: ON", "and that it saves itself")

-- a partner's save is announced ---------------------------------------------------
Notices.clear()
local blueSave = SaveData.newGame()
blueSave.player.name = "BLUE"
blue:sendWorld(World.encode(blueSave), true, "menu")
step(3)
eq(Notices.texts()[1], "BLUE saved the campaign.", "\"BLUE saved the campaign.\"")

-- START > SAVE while a battle runs: the save box says so, no YES/NO --------------
s.host.battles.b1 = true
step(2)
check(require("src.coop.game.CampaignSave").refusal(Game), "the host would refuse a save")
local before = campaignFs.read(CampaignFile.path("red", CID))
local slotWrites = 0
local realSave = SaveData.save
SaveData.save = function(...) slotWrites = slotWrites + 1 return realSave(...) end
local menu = StartMenu.new(Game)
stack:push(menu)
local saveItem
for _, it in ipairs(menu.items) do if it.label == "SAVE" then saveItem = it end end
saveItem.onSelect()
step(31)
local box = stack:top()
local shown = {}
for _, page in ipairs(box.pages or {}) do
  shown[#shown + 1] = type(page) == "table" and table.concat(page, " ") or tostring(page)
end
check(table.concat(shown, " "):find("battle", 1, true), "the save box says a battle is in progress")
eq(box.choice, nil, "with no YES/NO")
for _ = 1, 400 do
  if stack:top() == box then
    Input:sourcePress("a", "test"); Input:step(); step(1)
    Input:sourceRelease("a", "test"); Input:step(); step(1)
  end
end
check(stack:top() ~= box, "the box closes")
eq(slotWrites, 0, "nothing was written to the game's slot")
eq(campaignFs.read(CampaignFile.path("red", CID)), before, "nor to the campaign")
SaveData.save = realSave
while stack:top() ~= Game.overworld do stack:pop() end

-- a refusal that arrives anyway: the notice says the campaign was not saved ----
Notices.clear()
Game:writeSave("menu")
step(3)
eq(Notices.texts()[1], "The campaign was not saved.", "a refused save says so")
s.host.battles.b1 = nil
step(2)
eq(require("src.coop.game.CampaignSave").refusal(Game), nil, "the battle over: saves are taken")

-- a paused hosting app saves -------------------------------------------------------
Game.save.money = 4321
s:sendWorld(Game.save, false)
step(2)
check(Session.pause(), "a paused hosting app saves the campaign")
eq(onDisk():player(s.client.player).world.money, 4321, "with the newest world")

-- the CO-OP box counts the minutes ---------------------------------------------------
local CampaignSave = require("src.coop.game.CampaignSave")
eq(CampaignSave.ago({ savedAgo = function() return 150 end }), "SAVED 2 MIN AGO", "minutes")
eq(CampaignSave.ago({ savedAgo = function() return 7300 end }), "SAVED 2 H AGO", "hours")
eq(CampaignSave.ago({ savedAgo = function() return nil end }), "NOT SAVED YET", "never")

-- the launcher puts the player's world into the campaign's slot -----------------------
do
  local Launcher = require("src.coop.launcher.Launcher")
  local blue2 = Client.new(s.hub:dial(), { name = "BLUE", game = "red", sha1 = SHA,
                                           device = "b2", seat = 1,
                                           known = { [CID] = blue.player } })
  blue:leave()
  step(2)
  blue2:join()
  for _ = 1, 3 do blue2:update(); step(1); blue2:update() end
  check(blue2.world and not blue2.world.fresh, "BLUE gets their world back")
  -- as the launcher sees it on BLUE's device
  local fakeSession = setmetatable({ client = blue2 }, Session)
  local realCurrent = Session.current
  Session.current = fakeSession
  local written = {}
  local fakeSaves = { writeSlot = function(v, slot, save)
    written = { v = v, slot = slot, save = save }
    return true
  end }
  local notes = {}
  local fakeLauncher = { menu = { notify = function(_, t) notes[#notes + 1] = t end } }
  Launcher._coopWorld(fakeLauncher, fakeSaves, "red", "slot3")
  eq(written.slot, "slot3", "the world goes into the campaign's slot")
  eq(written.save and written.save.player.name, "BLUE", "BLUE's own world")
  eq(#notes, 0, "without a notice")
  -- a fresh player keeps the slot as it is
  blue2.world = { fresh = true }
  written = {}
  Launcher._coopWorld(fakeLauncher, fakeSaves, "red", "slot3")
  eq(written.slot, nil, "a player without a world keeps the slot")
  -- a world that does not read
  blue2.world = { fresh = false, save = "return 1" }
  Launcher._coopWorld(fakeLauncher, fakeSaves, "red", "slot3")
  eq(written.slot, nil, "an unreadable world is not written")
  check(notes[1] and notes[1]:find("could not be read", 1, true), "and the launcher says so")
  Session.current = realCurrent
end

-- a campaign file that cannot be read is not hosted ----------------------------------
do
  s:leave()
  local path = CampaignFile.path("red", CID)
  love.filesystem.write(path, "{ broken")
  local refused, info = Session.startHost({
    campaign = { id = CID, title = "Fix co-op" },
    cartridge = { game = "red", sha1 = SHA }, name = "HOST",
    listen = false, beacon = false, log = false,
    identity = Identity.load(memoryStore()),
  })
  eq(refused, nil, "an unreadable campaign file is not hosted")
  eq(info and info.why, "unreadable", "and why")
  eq(info.backup, path .. ".bak", "naming the backup")
  eq(love.filesystem.read(path), "{ broken", "the file is left as it is")
  eq(Session.current, nil, "no session runs")
end

T.finish()
