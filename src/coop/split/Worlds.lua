-- Two games in one process (#11): each split-screen seat plays its own
-- world, a module graph of its own.  Upstream's Gen 1 game is built of
-- module singletons (Game, Input, Renderer, StateStack, SaveData, ...), so a
-- second game cannot be a second instance; it is a second set of modules.
-- `package.loaded` is swapped per world, as tests/link3_harness.lua does
-- for two link partners: while a world runs, every `require` (at load or
-- lazily inside a function) finds that world's modules.
--
--   local home = Worlds.home()             -- the modules loaded now: seat 1
--   local w = Worlds.new("seat2", { silent = true })  -- a fresh graph
--   Worlds.run(w, function() ... require("src.core.Game") ... end)
--
-- A few modules stay one per process (SHARED below): the version and
-- cartridge cache mounts, the logger, the split-screen modules themselves.
-- A silent world runs without love.audio, love.sound and love.thread: the
-- process has one mix (seat 1's), and the background workers' channels are
-- process-global, so a second world's workers would take the first one's
-- results.  Upstream's modules all have a path without them (the headless
-- tests run there).

local Worlds = { current = nil, known = {} }

-- name prefixes and names that stay one per process
Worlds.SHARED_PREFIX = { "src.import.", "src.coop.split.", "tests." }
Worlds.SHARED = {
  ["src.core.GameVersion"] = true,
  ["src.core.Logger"] = true,
  ["src.link.Json"] = true,
}

-- the love modules a silent world runs without
Worlds.HIDDEN = { "audio", "sound", "thread" }

local function swappable(name)
  if type(name) ~= "string" or name:sub(1, 4) ~= "src." then return false end
  if Worlds.SHARED[name] then return false end
  for _, prefix in ipairs(Worlds.SHARED_PREFIX) do
    if name:sub(1, #prefix) == prefix then return false end
  end
  return true
end
Worlds.swappable = swappable

local function capture(w)
  for name, mod in pairs(package.loaded) do
    if swappable(name) then
      Worlds.known[name] = true
      w.mods[name] = mod
    end
  end
  -- a module unloaded while the world ran (Game's EXIT GAME rebuild)
  for name in pairs(w.mods) do
    if package.loaded[name] == nil then w.mods[name] = nil end
  end
end

local function hide(w)
  if not w.silent or not love then return end
  w.saved = {}
  for _, k in ipairs(Worlds.HIDDEN) do
    w.saved[k] = love[k]
    love[k] = nil
  end
end

local function unhide(w)
  if not w.saved or not love then return end
  for _, k in ipairs(Worlds.HIDDEN) do love[k] = w.saved[k] end
  w.saved = nil
end

local function leave()
  local w = Worlds.current
  if not w then return end
  capture(w)
  unhide(w)
end

local function newWorld(name, opts)
  return { name = name, mods = {}, silent = opts and opts.silent == true }
end

-- The world whose modules are loaded now (main.lua's game, seat 1).
function Worlds.home()
  if Worlds.homeWorld then return Worlds.homeWorld end
  local w = newWorld("home")
  capture(w)
  Worlds.homeWorld, Worlds.current = w, w
  return w
end

function Worlds.enter(w)
  if Worlds.current == w then return end
  leave()
  for name in pairs(Worlds.known) do package.loaded[name] = w.mods[name] end
  for name in pairs(w.mods) do package.loaded[name] = w.mods[name] end
  Worlds.current = w
  hide(w)
end

-- A world with none of the swappable modules loaded: the first `require`
-- inside it builds its own.
function Worlds.new(name, opts)
  Worlds.home()
  local w = newWorld(name, opts)
  local before = Worlds.current
  Worlds.enter(w)
  if before then Worlds.enter(before) end
  return w
end

-- fn(...) inside world `w`, then back in the world that was current; an
-- error comes out after the way back
function Worlds.run(w, fn, ...)
  local before = Worlds.current
  Worlds.enter(w)
  local out = { pcall(fn, ...) }
  if before then Worlds.enter(before) else leave() end
  if not out[1] then error(out[2], 0) end
  return unpack(out, 2, table.maxn(out))
end

-- Back to one world: the home world's modules stay loaded, the others are
-- dropped.
function Worlds.reset()
  local home = Worlds.homeWorld
  if home then Worlds.enter(home) end
  Worlds.homeWorld, Worlds.current, Worlds.known = nil, nil, {}
end

return Worlds
