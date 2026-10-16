-- What a mod sees of the fork's build (#30, design G34).  Two marked hooks
-- in src/mods/Sandbox.lua ask this module:
--
--   Gate.denial(name)     -- a mod's require of upstream's launcher fails
--   Gate.graphics(real)   -- a mod's love.graphics, sized by the game's view
--
-- Upstream's launcher (LICENSE.MD term 2, AGENTS.md) is never loaded in the
-- fork's process, and a mod's require is no exception: the Dramatic Shape
-- Voxel Mod wraps upstream's ROM importer for its Stadium ROM drop, inside
-- a pcall, and falls back to its own drop handler when the require fails.
--
-- A world-pipeline mod renders its scene at the size LOVE gives it, the
-- window's.  In a split-screen half (#11, GameViewport.forced) or under a
-- layout mod's viewport the game is drawn into a view smaller than the
-- window, and a window-sized scene would be cut to its top-left corner.  So
-- a mod's love.graphics answers getDimensions, getPixelDimensions,
-- getWidth and getHeight with the view of the game it runs in (its
-- world's GameViewport); with no view of its own that is the window, as
-- before.

local Gate = {}

-- upstream's launcher modules (the list tests/coop/launcher_boot_test.lua
-- checks the boot path against)
Gate.LAUNCHER = {
  ["src.import.LauncherView"] = true, ["src.import.LauncherSettings"] = true,
  ["src.import.OnlinePanel"] = true, ["src.import.CartLabelArt"] = true,
  ["src.import.CartShape"] = true, ["src.mods.LauncherMods"] = true,
  ["src.import.RomImporter"] = true, ["src.import.LauncherSplash"] = true,
  ["src.import.LauncherThemeVideo"] = true, ["src.import.BoxPanel"] = true,
  ["src.import.BoxUI"] = true,
}

-- the message a mod's require of `name` fails with, or nil
function Gate.denial(name)
  if type(name) ~= "string" then return nil end
  if Gate.LAUNCHER[name] or name:find("^src%.import%.online%.") then
    return ("%s is upstream's launcher, which this build does not include"):format(name)
  end
  return nil
end

-- the game's view (GameViewport) while it has one, else nil.  Everything
-- else, writes included, is the real love.graphics.
local function view()
  local ok, Viewport = pcall(require, "src.render.GameViewport")
  if ok and type(Viewport) == "table" and Viewport.active and Viewport.active() then
    return Viewport
  end
  return nil
end

local proxies = setmetatable({}, { __mode = "k" })

-- a mod's love.graphics: the real table, with the window's size read from
-- the game's view
function Gate.graphics(real)
  if type(real) ~= "table" then return real end
  local proxy = proxies[real]
  if proxy then return proxy end
  proxy = setmetatable({
    getDimensions = function()
      local v = view()
      if v then return v.dimensions() end
      return real.getDimensions()
    end,
    getPixelDimensions = function()
      local v = view()
      if v then return v.pixelDimensions() end
      return real.getPixelDimensions()
    end,
    getWidth = function()
      local v = view()
      if v then return (v.dimensions()) end
      return real.getWidth()
    end,
    getHeight = function()
      local v = view()
      if v then return select(2, v.dimensions()) end
      return real.getHeight()
    end,
  }, {
    __index = real,
    -- a function a mod swaps in is the engine's too (the voxel mod swaps
    -- rectangle around the battle's draw to keep its white field off the
    -- 3D arena)
    __newindex = function(_, key, value) real[key] = value end,
  })
  proxies[real] = proxy
  return proxy
end

return Gate
