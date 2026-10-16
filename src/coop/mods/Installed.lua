-- The mods on this device (#30, design G34), for the fork's launcher: what
-- is installed under mods/, whether each runs in a game, installing one
-- from a folder or a .zip, and a mod's optional import (a file it asks the
-- player for, such as the voxel mod's Pokémon Stadium ROM).  Built on the
-- GPL mod modules only (Manifest, SaveData's enable flags, RequiredImports),
-- never on upstream's launcher (LauncherMods, LICENSE.MD term 2).  The game's
-- mod loader (src/mods/Loader.lua) reads the same folder and the same flags
-- at boot, so a change here takes effect when the game starts.
--
--   Installed.list(version, fs)             -- { row } sorted by name
--   Installed.find(id, fs)                  -- one mod's manifest, or nil
--   Installed.setEnabled(version, id, on, fs)
--   Installed.install(tree, fs)             -- manifest, or nil and why
--   Installed.importOptional(id, importId, bytes, fs, hash)
--   Installed.mountedTree(mountpoint)       -- a tree over love.filesystem
--
-- A tree is the files of a mod to install, wherever they come from (a
-- mounted .zip, a dropped folder, a test):
--   tree.items(rel) -> names in the directory rel ("" for the top)
--   tree.kind(rel)  -> "file" | "directory" | nil
--   tree.read(rel)  -> the bytes of a file
-- The mod's manifest.json is at the top or in the one folder there (a
-- repository's .zip holds "<Repo>-main/manifest.json").  Each `fs` is
-- love.filesystem's calls (the save folder); tests pass their own.

local Json = require("src.link.Json")
local Manifest = require("src.mods.Manifest")
local SaveData = require("src.core.SaveData")

local Installed = {}

Installed.ROOT = "mods"
Installed.MAX_FILES = 5000
Installed.MAX_BYTES = 256 * 1024 * 1024

local function defaultFs() return love and love.filesystem end

-- a mod id that is a plain folder name
local function safeId(id)
  return type(id) == "string" and id:match("^[%w_%-][%w_%-%.]*$") ~= nil and #id <= 64
end

local function readManifest(fs, root)
  local raw = fs.read(root .. "/manifest.json")
  if type(raw) ~= "string" then return nil, "no manifest.json" end
  local okJ, data = pcall(Json.decode, raw)
  if not okJ or type(data) ~= "table" then return nil, "manifest.json is not JSON" end
  local ok, manifest = pcall(Manifest.validate, data, root)
  if not ok then return nil, tostring(manifest) end
  return manifest
end

function Installed.find(id, fs)
  fs = fs or defaultFs()
  if not safeId(id) then return nil end
  return (readManifest(fs, Installed.ROOT .. "/" .. id))
end

-- whether `manifest` runs in a game of `version`: the player's flag, else on
-- (experimental mods: off), as the loader decides
local function enabled(options, manifest, version)
  local on = SaveData.modEnabled(options, manifest.id, SaveData.modScope(version))
  if on == nil then return not manifest.experimental end
  return on
end

-- The installed mods: { id, name, version, description, enabled, engine
-- (patches engine code), link (affects a link), imports = { { id, name,
-- present } } (optional ones), problem (a manifest that does not read) }
function Installed.list(version, fs)
  fs = fs or defaultFs()
  local out = {}
  if not (fs and fs.getInfo and fs.getInfo(Installed.ROOT)) then return out end
  local okO, options = pcall(SaveData.loadOptions, fs)
  if not okO then options = {} end
  local RequiredImports = require("src.mods.RequiredImports")
  for _, name in ipairs(fs.getDirectoryItems(Installed.ROOT) or {}) do
    local root = Installed.ROOT .. "/" .. name
    local info = fs.getInfo(root)
    if info and (info.type == "directory" or info.type == "symlink")
        and fs.getInfo(root .. "/manifest.json") then
      local manifest, err = readManifest(fs, root)
      if manifest then
        local imports = {}
        for _, spec in ipairs(manifest.optional_imports or {}) do
          local present = fs.getInfo(RequiredImports.path(manifest, spec), "file") ~= nil
          imports[#imports + 1] = { id = spec.id, name = spec.name, present = present }
        end
        out[#out + 1] = {
          id = manifest.id, name = manifest.name or manifest.id, version = manifest.version,
          description = manifest.description or "", enabled = enabled(options, manifest, version),
          engine = manifest.permissionSet and manifest.permissionSet.engine_internals == true,
          link = manifest.affects_link == true, imports = imports, manifest = manifest,
        }
      else
        out[#out + 1] = { id = name, name = name, problem = err, enabled = false, imports = {} }
      end
    end
  end
  table.sort(out, function(a, b)
    local an, bn = tostring(a.name):lower(), tostring(b.name):lower()
    if an ~= bn then return an < bn end
    return a.id < b.id
  end)
  return out
end

-- the flag the loader reads at boot (SaveData's per-game mod flags)
function Installed.setEnabled(version, id, on, fs)
  fs = fs or defaultFs()
  local options = SaveData.loadOptions(fs)
  SaveData.setModEnabled(options, id, on and true or false, SaveData.modScope(version))
  return SaveData.saveOptions(options, fs)
end

-- the folder of the tree that holds manifest.json: "" or "<dir>/"
local function baseOf(tree)
  if tree.kind("manifest.json") == "file" then return "" end
  local dirs = {}
  for _, name in ipairs(tree.items("") or {}) do
    if tree.kind(name) == "directory" and name ~= "__MACOSX" then dirs[#dirs + 1] = name end
  end
  if #dirs == 1 and tree.kind(dirs[1] .. "/manifest.json") == "file" then
    return dirs[1] .. "/"
  end
  return nil
end

-- every file under `base` (relative to it), .git left out
local function filesOf(tree, base)
  local out = {}
  local function walk(rel)
    local dir = rel == "" and base:gsub("/$", "") or (base .. rel)
    for _, name in ipairs(tree.items(dir) or {}) do
      local sub = rel == "" and name or (rel .. "/" .. name)
      local kind = tree.kind(base .. sub)
      if kind == "directory" then
        if name ~= ".git" and name ~= "__MACOSX" then
          local ok, err = walk(sub)
          if not ok then return nil, err end
        end
      elseif kind == "file" then
        out[#out + 1] = sub
        if #out > Installed.MAX_FILES then return nil, "too many files" end
      end
    end
    return true
  end
  local ok, err = walk("")
  if not ok then return nil, err end
  return out
end

-- remove a folder of the save folder and everything in it
local function removeTree(fs, path)
  local info = fs.getInfo(path)
  if not info then return end
  if info.type == "directory" then
    for _, name in ipairs(fs.getDirectoryItems(path) or {}) do removeTree(fs, path .. "/" .. name) end
  end
  fs.remove(path)
end

local function ensureDir(fs, path, made)
  if made[path] then return end
  local parent = path:match("^(.*)/[^/]+$")
  if parent then ensureDir(fs, parent, made) end
  if fs.createDirectory then fs.createDirectory(path) end
  made[path] = true
end

-- Install the mod in `tree` into the save folder's mods/<id>/, replacing an
-- installed copy of the same mod (an update).  Returns its manifest, or nil
-- and the reason.
function Installed.install(tree, fs)
  fs = fs or defaultFs()
  local base = baseOf(tree)
  if not base then return nil, "no manifest.json at its top or in its one folder" end
  local raw = tree.read(base .. "manifest.json")
  local okJ, data = pcall(Json.decode, raw or "")
  if not okJ or type(data) ~= "table" then return nil, "manifest.json is not JSON" end
  if not safeId(data.id) then return nil, "the manifest's id is not a folder name" end
  local root = Installed.ROOT .. "/" .. data.id
  local okM, manifest = pcall(Manifest.validate, data, root)
  if not okM then return nil, tostring(manifest) end
  local files, err = filesOf(tree, base)
  if not files then return nil, err end
  -- read everything first: a file that does not read leaves the old copy
  local contents, total = {}, 0
  for i, rel in ipairs(files) do
    local bytes = tree.read(base .. rel)
    if type(bytes) ~= "string" then return nil, ("%s could not be read"):format(rel) end
    total = total + #bytes
    if total > Installed.MAX_BYTES then return nil, "the mod is too large" end
    contents[i] = bytes
  end
  removeTree(fs, root)
  local made = {}
  ensureDir(fs, root, made)
  for i, rel in ipairs(files) do
    local dir = rel:match("^(.*)/[^/]+$")
    if dir then ensureDir(fs, root .. "/" .. dir, made) end
    local ok, werr = fs.write(root .. "/" .. rel, contents[i])
    if not ok then return nil, ("%s could not be written: %s"):format(rel, tostring(werr)) end
  end
  return manifest
end

-- A file a mod asks for (its manifest's optional_imports), checked by size
-- and MD5 and stored in the mod's baseroms/ (GPL RequiredImports).
function Installed.importOptional(id, importId, bytes, fs, hash)
  fs = fs or defaultFs()
  local manifest = Installed.find(id, fs)
  if not manifest then return nil, "the mod is not installed" end
  return require("src.mods.RequiredImports").importData(manifest, importId, bytes, { hash = hash })
end

-- a tree over a mount point of love.filesystem (a .zip or a dropped folder)
function Installed.mountedTree(mountpoint)
  local fs = love.filesystem
  local function at(rel) return rel == "" and mountpoint or (mountpoint .. "/" .. rel) end
  return {
    items = function(rel) return fs.getDirectoryItems(at(rel)) end,
    kind = function(rel)
      local info = fs.getInfo(at(rel))
      return info and info.type or nil
    end,
    read = function(rel) return (fs.read(at(rel))) end,
  }
end

return Installed
