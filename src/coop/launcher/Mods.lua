-- The MODS page (#30, design G34) of one game, as a model with no love.*
-- calls: the mods installed on this device with name, version and what
-- they declare, each ON or OFF for this game; + INSTALL MOD (a mod's folder
-- or .zip, dropped, or a .zip's path typed or pasted); a mod's optional
-- file (IMPORT FILE: the voxel mod's Pokémon Stadium ROM).  The mods and
-- their flags are the game's own (src/coop/mods/Installed.lua on the GPL mod
-- modules); a change takes effect when the game starts.
--
-- Screens: "list", "install" (a path to type or a mod to drop), "import"
-- (a mod's optional file).
-- Actions as Menu's; a press may return { kind = "install_mod", path },
-- { kind = "mod_import", path, mod, import } or { kind = "mods_exit" }.
--
-- env:
--   version                     the game
--   list() -> Installed.list's rows (default: Installed.list(version))
--   setEnabled(id, on)          (default: Installed.setEnabled)
--   canType                     the install screen takes a typed path
--   canPick                     the install and import screens open the
--                               system's file picker (a phone, #7; a press
--                               returns { kind = "pick", what = "mod" or "mod_file" })

local Text = require("src.coop.launcher.Text")
local L = Text.get

local Mods = {}
Mods.__index = Mods

local function Installed() return require("src.coop.mods.Installed") end

function Mods.new(env)
  env = env or {}
  local version = env.version
  local self = setmetatable({
    env = env, version = version, screen = "list", cursor = 1, path = "",
    list = env.list or function() return Installed().list(version) end,
    setEnabled = env.setEnabled or function(id, on) return Installed().setEnabled(version, id, on) end,
    canType = env.canType ~= false,
    canPick = env.canPick == true,
  }, Mods)
  self:refresh()
  return self
end

-- read the installed mods again (after an install or an import)
function Mods:refresh()
  local ok, rows = pcall(self.list)
  self.mods = ok and type(rows) == "table" and rows or {}
end

function Mods:find(id)
  for _, m in ipairs(self.mods) do
    if m.id == id then return m end
  end
  return nil
end

function Mods:items()
  local rows = {}
  local function add(row) rows[#rows + 1] = row end
  local s = self.screen
  if s == "list" then
    for _, m in ipairs(self.mods) do
      add({ id = "toggle", mod = m.id, label = m.enabled and L("ON") or L("OFF"),
            enabled = m.problem == nil })
      for _, imp in ipairs(m.imports or {}) do
        if not imp.present then
          add({ id = "optional", mod = m.id, import = imp.id, label = L("IMPORT FILE") })
        end
      end
    end
    add({ id = "install", label = L("+ INSTALL MOD") })
  elseif (s == "install" or s == "import") and self.canPick then
    add({ id = "pick", label = L("CHOOSE FILE") })
  end
  return rows
end

function Mods:notify(text) self.notice = text end

function Mods:typing()
  return (self.screen == "install" or self.screen == "import") and self.canType and not self.notice
end

function Mods:go(screen)
  self.screen, self.cursor = screen, 1
end

local function move(self, delta)
  local rows = self:items()
  if #rows == 0 then return end
  for _ = 1, #rows do
    self.cursor = (self.cursor - 1 + delta) % #rows + 1
    if rows[self.cursor].enabled ~= false then break end
  end
end

function Mods:press(action)
  if self.notice then
    if action == "a" or action == "b" or action == "start" then self.notice = nil end
    return nil
  end
  local s = self.screen
  if s == "install" or s == "import" then
    if action == "b" then
      self.pending = nil
      self:go("list")
      return nil
    end
    if (action == "a" or action == "start") and self.path ~= "" then
      if s == "install" then return { kind = "install_mod", path = self.path } end
      local p = self.pending or {}
      return { kind = "mod_import", path = self.path, mod = p.mod, import = p.import }
    end
    if (action == "a" or action == "start") and self.canPick then
      return { kind = "pick", what = s == "install" and "mod" or "mod_file" }
    end
    return nil
  end
  if action == "up" or action == "left" then move(self, -1) return nil end
  if action == "down" or action == "right" then move(self, 1) return nil end
  if action == "b" then return { kind = "mods_exit" } end
  if action ~= "a" and action ~= "start" then return nil end
  local row = self:items()[self.cursor]
  if not row or row.enabled == false then return nil end
  if row.id == "toggle" then
    local m = self:find(row.mod)
    if m then
      local ok = pcall(self.setEnabled, m.id, not m.enabled)
      if ok then m.enabled = not m.enabled end
    end
  elseif row.id == "optional" then
    self.pending = { mod = row.mod, import = row.import }
    self.path = ""
    self:go("import")
  elseif row.id == "install" then
    self.path = ""
    self:go("install")
  end
  return nil
end

-- the optional file the import screen asks for: { mod, import } rows
function Mods:pendingImport()
  local p = self.pending
  local m = p and self:find(p.mod)
  if not m then return nil end
  for _, imp in ipairs(m.imports or {}) do
    if imp.id == p.import then return m, imp end
  end
  return nil
end

-- what an install or an import came to; back on the list either way
function Mods:done(ok, text)
  self.pending = nil
  self:go("list")
  self:refresh()
  self:notify(text)
end

function Mods:text(t)
  if not self:typing() then return end
  self.path = self.path .. t
end

function Mods:erase()
  if not (self.screen == "install" or self.screen == "import") or self.notice then return end
  self.path = self.path:sub(1, -2)
  while #self.path > 0 and self.path:byte(-1) >= 0x80 and self.path:byte(-1) < 0xC0 do
    self.path = self.path:sub(1, -2)
  end
  if #self.path > 0 and self.path:byte(-1) >= 0xC0 then self.path = self.path:sub(1, -2) end
end

return Mods
