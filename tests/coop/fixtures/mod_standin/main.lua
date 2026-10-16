-- A stand-in for a world-pipeline graphics mod (#30), used by the fork's
-- tests in place of the Dramatic Shape Voxel Mod, which is never copied
-- into this repository (its licence forbids it; the player installs it).
-- It declares what that mod declares (api 2, engine_internals,
-- affects_link false, an optional import), owns the world pass, and reaches
-- for what such a mod reaches for: an upstream launcher module and the
-- window's size.

local mod = ...

-- a mod may try to wrap upstream's ROM importer (the voxel mod does, for
-- its Stadium ROM drop); the fork's build never loads that launcher module
mod.exports.romImporter = (pcall(require, "src.import.RomImporter"))

-- the size the mod renders its scene at, as it asks LOVE for it
mod.exports.pixelDimensions = function() return love.graphics.getPixelDimensions() end
mod.exports.dimensions = function() return love.graphics.getDimensions() end

-- a mod may swap a love.graphics function for the engine's next call (the
-- voxel mod keeps the battle's white field off its 3D arena that way)
mod.exports.swapGraphics = function(name, fn)
  local old = love.graphics[name]
  love.graphics[name] = fn
  return old
end

-- what each frame of the world pass saw
mod.exports.frames = {}

mod.content.render_pipelines:register("standin", {
  label = "STAND-IN",
  levels = { "OFF", "ON" },
  priority = 5,
  available = function() return true end,
  drawWorld = function(ctx)
    local w, h = love.graphics.getPixelDimensions()
    local canvas = love.graphics.newCanvas(w, h)
    love.graphics.setCanvas(canvas)
    -- a camera turned half a circle: what is up on the map is down on the
    -- screen, and points far from the player lie behind it
    local function project(wx, wy)
      local dx, dy = wx - (ctx.cam.x + ctx.vw / 2), wy - (ctx.cam.y + ctx.vh / 2)
      if math.abs(dx) + math.abs(dy) > 400 then return nil end
      return (ctx.vw / 2 - dx) * ctx.scale, (ctx.vh / 2 - dy) * ctx.scale
    end
    if mod.exports.flat then
      project = function(wx, wy)
        return (wx - ctx.cam.x) * ctx.scale, (wy - ctx.cam.y) * ctx.scale
      end
    end
    mod.exports.inPass = true
    ctx.drawFx(project, ctx.scale)
    mod.exports.inPass = false
    love.graphics.setCanvas()
    mod.exports.frames[#mod.exports.frames + 1] = { width = w, height = h }
    return canvas
  end,
})

mod.options:define({
  { key = "look", type = "choice", label = "LOOK", choices = { { "A", "a" }, { "B", "b" } },
    default = "a", help = "A row of the mod's own." },
})
