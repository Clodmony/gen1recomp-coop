-- The two other ways a new player starts (#57, design A4.1 to A4.3, A4.7,
-- decision G28), besides Oak's opening (#22, Window.lua): in Pallet Town
-- with a chosen starter, or with a trainer brought from one of the device's
-- single-player saves.  The launcher builds the start world here and
-- writes it into the campaign's slot for a player the host has no world
-- for; the game opens it with CONTINUE (its own load path: migrations,
-- `SaveData.validate`, the trainer stamped on every Pokémon), and the
-- window sends it to the host whole (`start`), which keeps it, seeds a
-- campaign with no story yet from it and answers before the window opens.
--
--   Start.offersPallet(version)          -- false for Yellow (G28)
--   Start.story(version, starter)        -- the story a played opening leaves
--   Start.pallet({ version, starter, name, rival, newGame, rng })
--   Start.bringable(save)                -- a solo save that can be brought
--   Start.brought(save)                  -- that save, marked to start with
--   Start.make(SaveData, version, start, session) -- the launcher's choice
--                                        (and split-screen player 2's, #64)
--
-- A start world carries `coopStart` ("pallet" or "save") until its window
-- has sent it; the host never keeps the mark.

local Start = {}

Start.MARK = "coopStart"
Start.HOW = { pallet = true, save = true }
Start.LEVEL = 5

-- the three starters of Red and Blue, the ball each sits in on Oak's table,
-- and the one the rival takes against it (data/scripts/oaks_lab.lua
-- starterBall: the player's ball, then the rival's counter-pick)
Start.STARTERS = { "BULBASAUR", "CHARMANDER", "SQUIRTLE" }
Start.COUNTER = { BULBASAUR = "CHARMANDER", CHARMANDER = "SQUIRTLE", SQUIRTLE = "BULBASAUR" }

-- A starter as the lab's give_pokemon leaves it at level 5 (pokered
-- data/pokemon/base_stats: each knows its two level-1 moves, grows medium
-- slow, so 135 experience points, and has catch rate 45).  The stat block
-- and the moves' PP are the game's: CONTINUE's SaveData.validate derives
-- them (Stats.ensure, the PP fill), as it does for a box Pokémon from a
-- cartridge save; the original trainer is stamped by the same load.
local ROWS = {
  BULBASAUR = { "TACKLE", "GROWL" },
  CHARMANDER = { "SCRATCH", "GROWL" },
  SQUIRTLE = { "TACKLE", "TAIL_WHIP" },
}

local function yellow(version)
  return type(version) == "string" and version:find("^yellow") ~= nil
end

-- Yellow's opening is another one (Oak catches PIKACHU, who follows the
-- player; one ball; the rival takes EEVEE, whose later form #9 decides):
-- its story is not captured, so the start in Pallet Town is Red's and
-- Blue's (and their German editions'); a Yellow trainer is brought
-- instead (G28)
function Start.offersPallet(version)
  return type(version) == "string" and version ~= "" and not yellow(version)
end

local function labScript()
  local ok, lab = pcall(require, "data.scripts.oaks_lab")
  return ok and type(lab) == "table" and lab or nil
end

-- the rows a starter's ball runs (data/scripts/oaks_lab.lua): the balls it
-- hides on Oak's table and the flags it sets
local function ballRows(starter)
  local lab = labScript()
  local rows = lab and lab.talk and lab.talk["TEXT_OAKSLAB_" .. starter .. "_POKE_BALL"]
  if type(rows) ~= "table" then return nil end
  local hidden, flags = {}, {}
  for _, row in ipairs(rows) do
    if row[1] == "hide_object" and row[2] == "OAKS_LAB" then hidden[#hidden + 1] = row[3] end
    if row[1] == "set_flag" then flags[#flags + 1] = row[2] end
  end
  return hidden, flags
end

-- The story a played opening leaves in Red and Blue (A4.7), as #22's run
-- seeded it: Oak walked the player in (data/scripts/story2.lua
-- PALLET_TOWN.onStep: Pallet's Oak hidden, the door's Oak gone, Oak at his
-- desk, the three flags of the walk and his "Choose!"), the player's ball
-- and the rival's counter-pick gone (oaks_lab.lua's ball rows), and the
-- lab's rival fought and gone (OAKS_LAB.onStep).  Returns { flags,
-- objectToggles }, or nil for a version without the start (Yellow) or an
-- unknown starter.
function Start.story(version, starter)
  if not (Start.offersPallet(version) and Start.COUNTER[starter]) then return nil end
  local flags = {
    EVENT_FOLLOWED_OAK_INTO_LAB = true, EVENT_FOLLOWED_OAK_INTO_LAB_2 = true,
    EVENT_OAK_ASKED_TO_CHOOSE_MON = true, EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true,
  }
  local lab = { OAKSLAB_OAK2 = false, OAKSLAB_OAK1 = true, OAKSLAB_RIVAL = false }
  local hidden = ballRows(starter)
  if not hidden or #hidden ~= 2 then
    -- the script's rows were not at hand: the same two balls by name
    hidden = { "OAKSLAB_" .. starter .. "_POKE_BALL",
               "OAKSLAB_" .. Start.COUNTER[starter] .. "_POKE_BALL" }
  end
  for _, obj in ipairs(hidden) do lab[obj] = false end
  return { flags = flags,
           objectToggles = { OAKS_LAB = lab, PALLET_TOWN = { PALLETTOWN_OAK = false } } }
end

local function rng(opts)
  if opts.rng then return opts.rng end
  if love and love.math and love.math.random then return love.math.random end
  return math.random
end

-- the starter at level 5, as the lab hands it over (the game derives the rest)
function Start.starterRow(starter, random)
  local moves = {}
  for i, id in ipairs(ROWS[starter]) do moves[i] = { id = id } end
  local dvs = { attack = random(0, 15), defense = random(0, 15), speed = random(0, 15),
                special = random(0, 15) }
  dvs.hp = (dvs.attack % 2) * 8 + (dvs.defense % 2) * 4 + (dvs.speed % 2) * 2 + dvs.special % 2
  return {
    species = starter, level = Start.LEVEL, exp = 135, dvs = dvs,
    statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 },
    catchRate = 45, moves = moves,
  }
end

-- The start in Pallet Town (A4.1): a new game's world with the starter at
-- level 5 and the new game's 3000 money, standing in Pallet Town where a
-- blackout lands, the starter's own flags (EVENT_GOT_STARTER,
-- EVENT_CHOSE_<starter>, the player's), its Pokédex entry and the rival's
-- seen in the lab, and the story a played opening leaves.  opts: version,
-- starter, name (the trainer's), rival (the campaign's, when named),
-- newGame (SaveData.newGame), rng.  Returns the save, or nil and why.
function Start.pallet(opts)
  opts = opts or {}
  local story = Start.story(opts.version, opts.starter)
  if not story then return nil, "no start in Pallet Town for this game" end
  local SaveData = require("src.core.SaveData")
  local save = (opts.newGame or SaveData.newGame)()
  local heal = SaveData.defaultHeal()
  save.version = opts.version
  save.options = nil
  local p = save.player
  if type(opts.name) == "string" and opts.name:find("%S") then p.name = opts.name end
  if type(opts.rival) == "string" and opts.rival:find("%S") then p.rival = opts.rival end
  p.map, p.x, p.y, p.facing = heal.map, heal.x, heal.y, "down"
  save.lastHeal = { map = heal.map, x = heal.x, y = heal.y }
  save.lastOutdoor = { id = heal.map, x = heal.x, y = heal.y }
  save.money = 3000
  save.party = { Start.starterRow(opts.starter, rng(opts)) }
  save.pokedex = { seen = { [opts.starter] = true, [Start.COUNTER[opts.starter]] = true },
                   owned = { [opts.starter] = true } }
  save.flags = save.flags or {}
  for flag in pairs(story.flags) do save.flags[flag] = true end
  local _, ballFlags = ballRows(opts.starter)
  for _, flag in ipairs(ballFlags or {}) do save.flags[flag] = true end
  save.flags.EVENT_GOT_STARTER = true
  save.flags["EVENT_CHOSE_" .. opts.starter] = true
  save.objectToggles = story.objectToggles
  save[Start.MARK] = "pallet"
  return save
end

-- a solo save a player can bring (A4.1): a Gen 1 trainer past Oak's lab;
-- one still in the opening plays it again here
function Start.bringable(save)
  return type(save) == "table" and type(save.player) == "table"
    and type(save.flags) == "table" and save.flags.EVENT_GOT_STARTER == true
end

-- A brought trainer (A4.1, A4.2): the save as it stands (team, PC and
-- boxes, bag, money, place and own world keys, its trainer id kept),
-- without the device's options, marked to start with.  The game's own load
-- checks it (SaveData.validate) before its window sends it.  Returns the
-- save, or nil and why.
function Start.brought(save)
  if not Start.bringable(save) then return nil, "no starter yet" end
  save.options = nil
  save.importedOptions = nil
  save[Start.MARK] = "save"
  return save
end

-- The world a new player starts with, as the launcher's choice says
-- (`start`: { how = "pallet", starter } or { how = "save", slot }): in
-- Pallet Town with their starter under the session's name and the
-- campaign's rival, or a solo save of this device; nil and why.  The
-- launcher calls it for player 1, Split for player 2 (#64).
function Start.make(SaveData, version, start, s)
  if start.how == "pallet" then
    local state = s and s.client and s.client.state
    local name = tostring(s and s.name or ""):upper():sub(1, 7)
    return Start.pallet({ version = version, starter = start.starter, name = name,
                          rival = state and state.rival or nil })
  end
  local text = SaveData.readSlotSource(version, start.slot)
  local ok, save = pcall(SaveData.decode, text or "")
  if not ok or type(save) ~= "table" then return nil, "the save does not read" end
  return Start.brought(save)
end

return Start
