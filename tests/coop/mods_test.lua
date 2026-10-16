-- A world-pipeline graphics mod in the fork's build (#30, design G34),
-- ROM-free, with the stand-in fixture mod (tests/coop/fixtures/mod_standin)
-- in place of the Dramatic Shape Voxel Mod, which is never committed:
--   * the loader path: discovered under mods/, its manifest fields (api 2,
--     engine_internals, affects_link false, an optional import) read, its
--     pipeline and options registered, and upstream's launcher module
--     refused to it;
--   * the size a mod renders at is its game's view (a split-screen half);
--   * in a co-op session the partner arrow and the "!" bubble are drawn by
--     the pipeline's field-effect pass, under its camera, and a partner
--     keeps their colour in the 3D world.
--   luajit tests/coop/mods_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local check, eq = T.check, T.eq

local FIXTURE = "tests/coop/fixtures/mod_standin/"
local function readFile(path)
  local f = assert(io.open(path, "rb"))
  local text = f:read("*a")
  f:close()
  return text
end

-- the fs surface the loader needs, backed by a flat path->content table
local function memfs(files)
  return {
    read = function(path) return files[path] end,
    write = function(path, content) files[path] = content return true end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
    load = function(path)
      if not files[path] then return nil, "no file: " .. path end
      return load(files[path], "@" .. path)
    end,
    getDirectoryItems = function(path)
      local seen, items = {}, {}
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then
          local child = key:sub(#prefix + 1):match("^[^/]+")
          if child and not seen[child] then
            seen[child] = true
            items[#items + 1] = child
          end
        end
      end
      table.sort(items)
      return items
    end,
  }
end

-- the loader path ---------------------------------------------------------

local Data = T.fixtures.fresh()
Data.tilesets.FIX_OUT.tilesPerRow = 16
Data.field.flyWarps = Data.field.flyWarps or {}
Data.field.playerSprites = { walk = "SPRITE_FIX_PLAYER", bike = "SPRITE_FIX_NPC" }
Data.field.waterTilesets = {}
Data.field.forcedMovement = { tiles = {} }

local Loader = require("src.mods.Loader")
local files = {
  ["mods/COOP_STANDIN/manifest.json"] = readFile(FIXTURE .. "manifest.json"),
  ["mods/COOP_STANDIN/main.lua"] = readFile(FIXTURE .. "main.lua"),
}
local loader = Loader.new({ fs = memfs(files), generation = 1 })
check(loader:load(Data) == true, "the loader runs with the stand-in installed")
local entry = loader.mods.COOP_STANDIN
check(entry ~= nil, "the stand-in is discovered under mods/")
eq(entry and entry.state, "loaded", "and loads: " .. table.concat(loader.errors, "; "))
local manifest = entry and entry.manifest or {}
eq(manifest.api, 2, "its manifest is api 2")
check(manifest.permissionSet and manifest.permissionSet.engine_internals,
      "it asks for engine_internals")
eq(manifest.affects_link, false, "and says it does not affect a link")
eq(manifest.optional_imports and manifest.optional_imports[1]
   and manifest.optional_imports[1].id, "standin_rom", "with its optional import")
check(Data.render_pipelines and Data.render_pipelines.standin, "its world pipeline is registered")
local exports = loader.exports.COOP_STANDIN or {}

-- upstream's launcher (LICENSE.MD term 2) stays out of the fork's process
-- even when a mod asks for it (the voxel mod wraps its ROM importer)
eq(exports.romImporter, false, "a mod's require of upstream's launcher module fails")
eq(package.loaded["src.import.RomImporter"], nil, "and the launcher module was never loaded")

-- the size a mod renders at -----------------------------------------------

local GameViewport = require("src.render.GameViewport")
local winW, winH = love.graphics.getDimensions()
local w, h = exports.pixelDimensions()
eq(w, winW, "with no view of its own, a mod renders at the window's width")
GameViewport.forced = { x = 0, y = 0, width = math.floor(winW / 2), height = winH }
GameViewport.begin(1)
w, h = exports.pixelDimensions()
eq(w, math.floor(winW / 2), "in a split-screen half, at the half's width")
eq(h, winH, "and its height")
w = exports.dimensions()
eq(w, math.floor(winW / 2), "love.graphics.getDimensions answers the same view")
GameViewport.forced = nil
GameViewport.finish()
GameViewport.reset()
eq((exports.pixelDimensions()), winW, "after the view, the window again")
local function noFill() end
local realRectangle = exports.swapGraphics("rectangle", noFill)
check(love.graphics.rectangle == noFill, "a function a mod swaps in love.graphics is the engine's too")
exports.swapGraphics("rectangle", realRectangle)
check(love.graphics.rectangle == realRectangle, "and so is the one it puts back")

-- the world pass in a co-op session --------------------------------------

local Game       = require("src.core.Game")
local Input      = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local Renderer   = require("src.render.Renderer")
local SaveData   = require("src.core.SaveData")
local Pokemon    = require("src.pokemon.Pokemon")
local OW         = require("src.world.OverworldController")
local Pipelines  = require("src.render.Pipelines")
local Identity = require("src.coop.session.Identity")
local Session  = require("src.coop.session.Session")
local Client   = require("src.coop.session.Client")
local Presence = require("src.coop.game.Presence")
local Arrow    = require("src.coop.game.Arrow")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.save.flags.EVENT_GOT_STARTER = true
Game.save.party = { Pokemon.new(Data, "FIXMON_A", 20) }
Pipelines.install(Data)
local stack = Game.stack
stack:push(OW, "FIX_TOWN", 5, 6, "down")
local ow = stack:top()
Game.overworld = ow

local function step(n)
  for _ = 1, n or 1 do
    if Session.current then Session.current:update(1 / 60, Game) end
    if Presence.partner then Presence.partner:update() end
    stack:update(1 / 60)
    Presence.step(Game)
  end
end

local function memoryStore()
  local text
  return { read = function() return text end, write = function(t) text = t end }
end
local SHA = ("ab"):rep(20)
local s = Session.startHost({
  campaign = { id = "c0001", title = "Fix co-op" },
  cartridge = { game = "red", sha1 = SHA }, name = "HOST",
  listen = false, beacon = false, log = false,
  identity = Identity.load(memoryStore()),
})
step(3)
local blue = Client.new(s.hub:dial(), { name = "BLUE", game = "red", sha1 = SHA,
                                        device = "b1", seat = 1 })
Presence.partner = blue
blue:join()
step(3)
blue:sendOpening(true)
blue:move("FIX_ROUTE", 4, 2, "up", true, "walk")
step(3)

-- the arrows and bubbles a frame draws, and where
local drawn
local realDrawOne, realBubble = Arrow.drawOne, Presence.drawBubble
Arrow.drawOne = function(a, scale)
  drawn.arrows[#drawn.arrows + 1] = { dir = a.dir, x = a.x, y = a.y, scale = scale,
                                      pass = exports.inPass }
end
Presence.drawBubble = function(game, w, a)
  drawn.bubbles[#drawn.bubbles + 1] = { id = a.id, pass = exports.inPass }
end
local function frame()
  drawn = { arrows = {}, bubbles = {} }
  Presence.frame = 0 -- the arrow's blink is on
  local ok, err = pcall(function()
    Renderer:beginFrame()
    ow:draw()
    Renderer:endFrame()
  end)
  check(ok, "the overworld draws: " .. tostring(err))
  return drawn
end

eq(Arrow.arrows(Game, ow, Presence.partners(), 160, 144)[1].dir, "up",
   "flat: BLUE far up the route, the arrow points up")
local d = frame()
eq(#d.arrows, 1, "the flat world pass draws the arrow")
eq(d.arrows[1].dir, "up", "pointing up")

Pipelines.setLevel("standin", 1)
eq(Pipelines.worldPipeline(), "standin", "the stand-in owns the world pass")
d = frame()
check(#exports.frames > 0, "the pipeline drew the world")
eq(#d.arrows, 1, "the arrow is drawn once")
check(d.arrows[1] and d.arrows[1].pass, "by the pipeline's field-effect pass")
eq(d.arrows[1] and d.arrows[1].dir, "down",
   "under the pipeline's camera (turned half a circle) BLUE is down the screen")
check(d.arrows[1] and d.arrows[1].scale ~= nil, "at the pipeline's scale")
exports.flat = true
d = frame()
eq(d.arrows[1] and d.arrows[1].dir, "up", "a camera that looks down on the map: up again")
exports.flat = nil

-- BLUE in a battle on the connected route: the "!" over them
blue:move("FIX_ROUTE", 4, 30, "down", true, "walk")
step(3)
local a = Presence.actors[blue.player]
check(a and a.visible, "BLUE on the route below the town's edge is drawn")
a.inBattle = true
d = frame()
eq(#d.bubbles, 1, "BLUE's \"!\" is drawn once")
check(d.bubbles[1] and d.bubbles[1].pass, "by the pipeline's field-effect pass too")
a.inBattle = false

-- BLUE's colour in the 3D world: their sprite as the pipeline sees it
local sprite = a:pose()
check(sprite.def.trueColor == true, "a pipeline takes BLUE's sprite as finished colours")
eq(sprite.def.id, "SPRITE_FIX_PLAYER", "of BLUE's own sheet")
check(not a:sprite(Data).def.trueColor, "the 2D sprite is untouched")
local SpriteRenderer = require("src.render.SpriteRenderer")
local plain = SpriteRenderer.new(a:sprite(Data).def, "plain")
check(sprite:resolveImage() ~= plain:resolveImage(), "in BLUE's colour, not the map's")
check(ow.player.sprite:resolveImage() ~= plain:resolveImage(),
      "and this player's own sprite in theirs")

Arrow.drawOne, Presence.drawBubble = realDrawOne, realBubble
Pipelines.setLevel("standin", 0)
blue:leave()
step(2)
s:leave()

T.finish("mods")
