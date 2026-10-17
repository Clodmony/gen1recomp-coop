-- The game's quick keys in a co-op session (#72), ROM-free: the fixture
-- overworld runs headless with this device hosting a session in-process and
-- a partner on its loopback hub.  F1 (the quick bar's SAVE) saves the
-- campaign as START > SAVE does, and refuses with a notice where the save
-- box refuses (a battle running); F2 (the quick bar's LOAD) loads nothing
-- in a session and says so, so a world handed to a partner cannot be
-- loaded back; a notice stays as long at 4X as at 1X.
--   luajit tests/coop/quick_keys_game_test.lua

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
local CampaignFile = require("src.coop.campaign.CampaignFile")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.save.flags.EVENT_GOT_STARTER = true -- past the opening (#22)
Game.save.player.name = "HOST"
Game.save.party = { Pokemon.new(Data, "FIXMON_A", 20), Pokemon.new(Data, "FIXMON_A", 12) }
local stack = Game.stack
stack:push(OW, "FIX_TOWN", 5, 6, "down")
Game.overworld = stack:top()

local SHA = ("ab"):rep(20)
local CID = "c00000000000000c2"
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
  return CampaignFile.read(campaignFs, "red", CID)
end

-- solo: F1 and F2 are the game's own ------------------------------------------
Game.save.money = 100
Game:keypressed("f1")
Game.save.money = 999
Game:keypressed("f2")
eq(Game.save.money, 100, "solo: F2 loads the last save")
eq(#Notices.texts(), 0, "solo: no notice")
-- the fixture save loads with a report screen over the world
while stack:top() ~= Game.overworld do stack:pop() end

-- a session: this device hosts, BLUE dials in ----------------------------------
local s = Session.startHost({
  campaign = { id = CID, title = "Fix co-op" },
  cartridge = { game = "red", sha1 = SHA }, name = "HOST",
  listen = false, beacon = false, log = false,
  identity = Identity.load(memoryStore()),
})
check(s, "hosting a new campaign")
step(3)
eq(s.status, "joined", "the host's own player is in")
local blue = Client.new(s.hub:dial(), { name = "BLUE", game = "red", sha1 = SHA,
                                        device = "b1", seat = 1 })
Presence.partner = blue
blue:join()
step(3)
eq(blue.status, "joined", "BLUE joined")
Notices.clear()

-- F1 saves the campaign, as START > SAVE does ------------------------------------
Game.save.money = 1234
Game:keypressed("f1")
step(3)
local c = onDisk()
local mine = c and c:player(s.client.player)
eq(mine and mine.world and mine.world.money, 1234, "F1: the campaign file holds this player's world")
eq(Notices.texts()[1], "Campaign saved.", "F1: \"Campaign saved.\"")
check(blue:takeSaves()[1], "F1: BLUE hears of the save")

-- F2 loads nothing back: a Pokémon handed away stays away -------------------------
Notices.clear()
table.remove(Game.save.party, 2) -- handed to a partner since the save
Game.save.money = 50
s:sendWorld(Game.save, false)
step(3)
local party, money = #Game.save.party, Game.save.money
Game:keypressed("f2")
step(2)
eq(#Game.save.party, party, "F2 in a session: the party is not loaded back")
eq(Game.save.money, money, "F2 in a session: nor the money")
check(stack:top() == Game.overworld, "F2 in a session: the world goes on")
local said = table.concat(Notices.texts(), " ")
check(said:find("co-op", 1, true), "F2 in a session: a notice says why (" .. said .. ")")

-- F1 while a battle runs: no save, a notice, as the save box says -----------------
Notices.clear()
s.host.battles.b1 = { open = { by = "p0", kind = "wild" }, players = {}, inputs = {}, suggestions = {} }
step(2)
check(require("src.coop.game.CampaignSave").refusal(Game), "the host would refuse a save")
local before = campaignFs.read(CampaignFile.path("red", CID))
local slotWrites = 0
local realSave = SaveData.save
SaveData.save = function(...) slotWrites = slotWrites + 1 return realSave(...) end
Game:keypressed("f1")
step(3)
SaveData.save = realSave
eq(slotWrites, 0, "F1 in a battle: nothing written to the game's slot")
eq(campaignFs.read(CampaignFile.path("red", CID)), before, "F1 in a battle: nor to the campaign")
said = table.concat(Notices.texts(), " ")
check(said:find("battle", 1, true), "F1 in a battle: the notice says a battle is in progress (" .. said .. ")")
s.host.battles.b1 = nil
step(2)

-- a notice lasts as long at 4X as at 1X ---------------------------------------------
Notices.clear()
Notices.push("A notice.")
Game._frameSpeed = 4
for _ = 1, Notices.SHOW * 2 do Presence.step(Game) end
eq(Notices.texts()[1], "A notice.", "at 4X a notice is still up after half its logic frames")
for _ = 1, Notices.SHOW * 2 + 4 do Presence.step(Game) end
eq(Notices.texts()[1], nil, "and gone after all of them")
Game._frameSpeed = nil

blue:leave()
T.finish()
