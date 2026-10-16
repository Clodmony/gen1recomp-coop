-- The opening in the game (#22, design A4.4 to A4.9), ROM-free: the fixture
-- overworld runs headless with this device hosting a session in-process
-- and a partner on its loopback hub.  Oak's speech asks no player name (the
-- launcher's) and the rival's only until somebody named him; a name given
-- reaches the campaign.  While this player plays the opening they see
-- nobody, hear of no battle to join, fight their battles alone and save
-- nothing.  Past the opening the partner shows, and a rival battle picks
-- the team the campaign's starter calls for.
--   luajit tests/coop/opening_game_test.lua

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
local OakSpeech  = require("src.ui.OakSpeech")
local BattleState = require("src.battle.BattleState")
local Commands   = require("src.script.Commands")

local Identity = require("src.coop.session.Identity")
local Session  = require("src.coop.session.Session")
local Client   = require("src.coop.session.Client")
local Presence = require("src.coop.game.Presence")
local Arrow    = require("src.coop.game.Arrow")
local Battles  = require("src.coop.game.Battles")
local CampaignSave = require("src.coop.game.CampaignSave")
local Opening  = require("src.coop.game.Opening")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame() -- a new game: no starter yet
local stack = Game.stack
stack:push(OW, "FIX_TOWN", 5, 6, "down")
local ow = stack:top()
Game.overworld = ow

local SHA = ("ab"):rep(20)
local function memoryStore()
  local text
  return { read = function() return text end, write = function(t) text = t end }
end

local blue
local function step(n)
  for _ = 1, n or 1 do
    local s = Session.current
    if s then s:update(1 / 60, Game) end
    if blue then blue:update() end
    stack:update(1 / 60)
    Presence.step(Game)
  end
end

local function partnerActors()
  local out = {}
  for _, e in ipairs(ow.entities) do
    if e.coopPartner then out[#out + 1] = e end
  end
  return out
end

local function ids(steps)
  local out = {}
  for _, st in ipairs(steps) do out[#out + 1] = st.id end
  return "," .. table.concat(out, ",") .. ","
end

local function speech()
  return setmetatable({ game = Game }, OakSpeech)
end

-- solo: Oak's speech is the cartridge's --------------------------------------------
do
  local list = ids(speech():buildSteps())
  check(list:find(",name_player,"), "solo: Oak asks the player's name")
  check(list:find(",name_rival,"), "solo: and the rival's")
  eq(Opening.active(), false, "solo: no opening of a session")
  eq(CampaignSave.vetoes(Game), false, "solo: saves are written")
end

-- a session: this device hosts a new campaign --------------------------------------
local s = Session.startHost({
  campaign = { id = "c0001", title = "Fix co-op" },
  cartridge = { game = "red", sha1 = SHA }, name = "Ash",
  listen = false, beacon = false, log = false, campaignFs = false,
  identity = Identity.load(memoryStore()),
})
step(4)
eq(s.status, "joined", "the host's own player is in")
eq(Opening.active(), true, "a new game plays the opening")

-- Oak's speech (A4.5) ----------------------------------------------------------------
do
  local sp = speech()
  local steps = sp:buildSteps()
  local list = ids(steps)
  check(not list:find(",name_player,"), "Oak does not ask the player's name")
  check(not list:find(",ask_player_name,") and not list:find(",confirm_player_name,"),
        "nor introduce it")
  eq(Game.save.player.name, "ASH", "the launcher's name is the trainer's, as the cartridge writes it")
  check(list:find(",name_rival,"), "nobody named the rival: Oak asks")
  check(list:find(",confirm_rival_name,coop_rival_named,"), "and the name goes to the host after")
  -- the player names him
  Game.save.player.rival = "GARY"
  for _, st in ipairs(steps) do
    if st.id == "coop_rival_named" then st.run(sp, function() end) end
  end
  step(4)
  eq(s.host.state.rival, "GARY", "the name given in Oak's speech is the campaign's")
  local again = ids(speech():buildSteps())
  check(not again:find(",name_rival,") and not again:find(",ask_rival_name,"),
        "once named, Oak asks nobody else")
end

-- BLUE joins past the opening on this map ------------------------------------------
blue = Client.new(s.hub:dial(), { name = "BLUE", game = "red", sha1 = SHA, device = "b1", seat = 1 })
blue:join()
step(4)
eq(blue.status, "joined", "BLUE joined")
blue:sendOpening(true)
blue:move("FIX_TOWN", 3, 6, "down", true, "walk")
step(4)

-- what the opening keeps away (A4.4, A4.8, A4.9) -------------------------------------
eq(#partnerActors(), 0, "in the opening this player sees nobody")
local hidden = Presence.partners()[1]
check(hidden and hidden.hidden, "the arrow and the TOWN MAP mark skip the partner")
eq(#Arrow.arrows(Game, ow, Presence.partners(), 160, 144), 0, "no arrow")
local refusal = CampaignSave.refusal(Game)
check(refusal and refusal:find("opening"), "START > SAVE says the opening is not saved")
eq(CampaignSave.vetoes(Game), true, "the game writes no save")
eq(Game:writeSave("menu"), false, "Game:writeSave writes nothing")
local wild = BattleState.newWild(Game, "FIXMON_B", 3)
eq(Battles.take(Game, wild), nil, "a battle the opening opens stays in the window")
eq(wild.coopPending, nil, "nothing went to the host")
local items = {}
Battles.joinRows(Game, items)
eq(#items, 0, "nothing to join from the opening")
check(s.client:playerView(s.client.player).opening, "the host says this player is in the opening")

-- the opening ends outside the lab with a starter --------------------------------------
Game.save.party = { Pokemon.new(Data, "FIXMON_A", 5) }
Game.save.flags.EVENT_GOT_STARTER = true
Game.save.flags.EVENT_CHOSE_BULBASAUR = true
step(6)
eq(Opening.active(), false, "the opening is over")
eq(s.host.state.chose, "BULBASAUR", "the rival counters this player's starter now")
eq(#partnerActors(), 1, "BLUE shows")
eq(CampaignSave.refusal(Game), nil, "and the game saves again")
eq(CampaignSave.vetoes(Game), false, "nothing vetoes a save")

-- a rival battle picks the campaign's team (A4.6) --------------------------------------
do
  local real = Commands.start_battle
  local party
  Commands.start_battle = function(_, _, _, p) party = p end
  local save = { flags = { EVENT_CHOSE_SQUIRTLE = true } } -- another starter
  Commands.rival_battle({ game = Game, save = save }, "OPP_RIVAL2", 4)
  eq(party, 4 + 2, "a player who took SQUIRTLE fights the team BULBASAUR calls for")
  Session.current = nil
  Commands.rival_battle({ game = Game, save = save }, "OPP_RIVAL2", 4)
  eq(party, 4 + 1, "solo: the player's own starter picks it")
  Session.current = s
  Commands.start_battle = real
end

T.finish()
