-- The game's options on the launcher's SETTINGS page (#5), with no love.*
-- calls: window mode, integer scale, music and sound volume, text speed,
-- battle animation and battle style.  They live where the game reads
-- them, options.lua (GPL SaveData, the keys the game's own OPTIONS menu
-- writes: videoMode, faithfulRes, musicVol, sfxVol, textSpeed, animations,
-- battleStyle), so the launcher and the game always show the same value;
-- the launcher's own settings (language, colours) stay in its own file.
-- Each change is one partial write, folded over the file (#932).
--
-- env:
--   fs            -> the filesystem SaveData writes to (nil: the save folder)
--   fixedDisplay  -> no WINDOW row (phone, console)

local SaveData = require("src.core.SaveData")
local VideoMode = require("src.core.VideoMode")
local FaithfulRes = require("src.core.FaithfulRes")
local Text = require("src.coop.launcher.Text")
local L = Text.get

local GameOptions = {}
GameOptions.__index = GameOptions

-- TextSpeedOptionData's frame delays with the cartridge's labels
local SPEEDS = { { 1, "FAST" }, { 3, "MEDIUM" }, { 5, "SLOW" } }

local function speedIndex(v)
  for i, s in ipairs(SPEEDS) do
    if s[1] == v then return i end
  end
  return 2
end

local function volume(v)
  v = tonumber(v)
  if not v or v ~= math.floor(v) or v < 0 or v > 7 then return 7 end
  return v
end

local function volumeLabel(v)
  return v == 0 and L("OFF") or tostring(v)
end

-- the rows: id, label, group, the value's label, and how it steps
GameOptions.ROWS = {
  { id = "window", group = "video", label = "WINDOW", key = "videoMode",
    read = function(o) return VideoMode.normalize(o.videoMode) end,
    show = function(v) return v == "borderless" and L("BORDERLESS") or L("WINDOWED") end,
    step = function(v) return VideoMode.cycle(v) end },
  { id = "scale", group = "video", label = "INTEGER SCALE", key = "faithfulRes",
    read = function(o) return FaithfulRes.normalize(o.faithfulRes) end,
    show = function(v) return v == 0 and L("OFF") or FaithfulRes.label(v) end,
    step = function(v, dir) return FaithfulRes.cycle(v, dir) end },
  { id = "music", group = "audio", label = "MUSIC", key = "musicVol",
    read = function(o) return volume(o.musicVol) end,
    show = volumeLabel,
    -- the volumes stop at the ends, as the game's menu does
    step = function(v, dir) return math.max(0, math.min(7, v + dir)) end },
  { id = "sound", group = "audio", label = "SOUND", key = "sfxVol",
    read = function(o) return volume(o.sfxVol) end,
    show = volumeLabel,
    step = function(v, dir) return math.max(0, math.min(7, v + dir)) end },
  { id = "textSpeed", group = "game", label = "TEXT SPEED", key = "textSpeed",
    read = function(o) return SPEEDS[speedIndex(o.textSpeed)][1] end,
    show = function(v) return L(SPEEDS[speedIndex(v)][2]) end,
    step = function(v, dir) return SPEEDS[(speedIndex(v) - 1 + dir) % #SPEEDS + 1][1] end },
  { id = "animations", group = "game", label = "BATTLE ANIMATION", key = "animations",
    read = function(o) return o.animations ~= false end,
    show = function(v) return v and L("ON") or L("OFF") end,
    step = function(v) return not v end },
  { id = "battleStyle", group = "game", label = "BATTLE STYLE", key = "battleStyle",
    read = function(o) return o.battleStyle == "set" and "set" or "shift" end,
    show = function(v) return v == "set" and L("SET") or L("SHIFT") end,
    step = function(v) return v == "set" and "shift" or "set" end },
}

function GameOptions.new(env)
  return setmetatable({ env = env or {} }, GameOptions)
end

function GameOptions:_options()
  local ok, options = pcall(SaveData.loadOptions, self.env.fs)
  return ok and type(options) == "table" and options or SaveData.defaultOptions()
end

-- the rows as the menu lists them: { id, label, detail, group, option = true }
function GameOptions:rows()
  local options = self:_options()
  local rows = {}
  for _, r in ipairs(GameOptions.ROWS) do
    if not (r.id == "window" and self.env.fixedDisplay) then
      rows[#rows + 1] = { id = r.id, label = L(r.label), group = r.group, option = true,
                          detail = r.show(r.read(options)) }
    end
  end
  return rows
end

-- step a row's value by `dir` (1: on, as A does; -1: back) and write it
function GameOptions:step(row, dir)
  for _, r in ipairs(GameOptions.ROWS) do
    if r.id == row.id then
      local value = r.step(r.read(self:_options()), dir or 1)
      local ok = pcall(SaveData.saveOptions, { [r.key] = value }, self.env.fs)
      return ok and value or nil
    end
  end
  return nil
end

return GameOptions
