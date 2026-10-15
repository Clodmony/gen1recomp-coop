-- The German game catalog (#25): the Gen 1 engine's English sources a
-- German game translates (src/coop/game/German.lua), found in the source.
--   luajit tools/game_strings.lua            -- the sources, one per line
--   luajit tools/game_strings.lua --missing  -- sources with no entry
--   luajit tools/game_strings.lua --stale    -- entries no source uses
--   luajit tools/game_strings.lua --markdown -- the tables for
--                                               docs/coop/german-wording.md
-- tests/coop/german_strings_test.lua uses missing(), stale() and markdown().

local M = {}

-- where the Gen 1 game's own lines live (src/import is the launcher and the
-- importers, src/mods the mod screens: not a played German game)
M.DIRS = {
  "src/battle", "src/ui", "src/world", "src/script", "src/inventory",
  "src/pokemon", "src/link", "src/coop/game", "src/coop/battle", "src/coop/friends",
}
M.FILES = { "src/core/Game.lua", "src/online/Connect.lua" }
-- Gen 2 and Gen 3 modules, and screens a cartridge game never reaches
M.SKIP = {
  "gen2", "g3u", "game3", "gen3", "Gen2", "Gen3", "Crystal", "Gold", "Emerald",
  "FireRed", "union", "ShaderFX", "Quarantine", "Bindings", "Palette",
  "Printer", "SurfingMinigame", "LinkBattle2", "Game2", "Protocol2",
}
-- sources a German game keeps as they are: names, codes and settings
-- values that are not words
M.ENGLISH = {
  "GAME FREAK inc.", "GAME FREAK", "Creatures inc.", "Nintendo",
  "GENGAR VS NIDORINO", "T H E  E N D", "POKéMON RED", "POKéMON BLUE",
  "POKéMON YELLOW", "ITEMS", "MODS", "BALL", "NAME", "NORMAL", "STANDARD",
  "VSYNC", "ZOOM", "VIBRATION", "OG", "%dX", "IN%d", "OUT%d", "Level %d",
  "POKéDEX", "POKéMON", "ITEM", "OPTION", "OT/", "STATUS/", "TYPE1/",
  "TYPE2/", "LEVEL/", "HT", "WT", "lb", "GR. %.1fm", "GR. ???m",
  "GEW. %.1fkg", "GEW. ???kg", "BOX%2d", ":L%d", "Printer error!\n%s",
  " [%s %s.%s]", "contribution is not a table", "AUDIO", "VIDEO",
}
-- sources handed to Strings from a table rather than a literal call
-- (src/ui/OptionsMenu.lua SPEEDS)
M.TABLES = { "FAST", "MEDIUM", "SLOW", "AUDIO", "VIDEO", "SPEED", "GRAPHICS" }

local function unescape(s)
  return (s:gsub("\\(%d%d?%d?)", function(d) return string.char(tonumber(d)) end)
           :gsub("\\(.)", { n = "\n", t = "\t", v = "\v", f = "\f", r = "\r",
                            ["\\"] = "\\", ['"'] = '"', ["'"] = "'" }))
end

local function skipped(path)
  for _, pat in ipairs(M.SKIP) do
    if path:find(pat, 1, true) then return true end
  end
  return false
end

local function listLua(dir)
  local out = {}
  local p = io.popen('find "' .. dir .. '" -name "*.lua" 2>/dev/null | sort')
  if p then
    for line in p:lines() do out[#out + 1] = line end
    p:close()
  end
  return out
end

local function read(path)
  local f = assert(io.open(path, "r"))
  local s = f:read("*a")
  f:close()
  return s
end

-- Every literal handed to Strings(...) / Strings.source(...) in the Gen 1
-- game, except the fallbacks of romText(...) calls, which the cartridge's
-- label already prints.  -> { { source = s, file = path }, ... }, unique.
function M.sources(root)
  root = root or "."
  local files = {}
  for _, dir in ipairs(M.DIRS) do
    for _, f in ipairs(listLua(root .. "/" .. dir)) do files[#files + 1] = f end
  end
  for _, f in ipairs(M.FILES) do files[#files + 1] = root .. "/" .. f end
  local seen, out = {}, {}
  for _, s in ipairs(M.TABLES) do
    seen[s] = true
    out[#out + 1] = { source = s, file = "(a table)" }
  end
  for _, path in ipairs(files) do
    if not skipped(path) then
      local src = read(path)
      local fallbacks = {}
      for lit in src:gmatch('romText%(%s*[%w_.]*,?%s*"[^"\n]-",%s*"(.-[^\\])"') do
        fallbacks[unescape(lit)] = true
      end
      for lit in src:gmatch('%f[%w_]Strings%.?s?o?u?r?c?e?%(%s*"(.-[^\\])"') do
        local s = unescape(lit)
        if not fallbacks[s] and not seen[s] then
          seen[s] = true
          out[#out + 1] = { source = s, file = path:gsub("^%./", "") }
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.source < b.source end)
  return out
end

local function catalogKeys()
  local German = require("src.coop.game.German")
  local keys = {}
  for _, layer in ipairs({ German.WORDS, German.TEXTS, German.PROJECT }) do
    for k in pairs(layer) do keys[(k:gsub("^[%w_]+|", ""))] = true end
  end
  return keys
end

-- sources no layer covers and the ENGLISH list does not excuse
function M.missing(root)
  local keys = catalogKeys()
  local english = {}
  for _, s in ipairs(M.ENGLISH) do english[s] = true end
  local out = {}
  for _, row in ipairs(M.sources(root)) do
    if not keys[row.source] and not english[row.source] then out[#out + 1] = row end
  end
  return out
end

-- catalog keys (and ENGLISH entries) that no source spells
function M.stale(root)
  local sources = {}
  for _, row in ipairs(M.sources(root)) do sources[row.source] = true end
  local German = require("src.coop.game.German")
  local out = {}
  for _, layer in ipairs({ German.WORDS, German.TEXTS, German.PROJECT }) do
    for k in pairs(layer) do
      if not sources[(k:gsub("^[%w_]+|", ""))] then out[#out + 1] = k end
    end
  end
  for _, s in ipairs(M.ENGLISH) do
    if not sources[s] then out[#out + 1] = s end
  end
  table.sort(out)
  return out
end

local function cell(s)
  return (s:gsub("|", "\\|"):gsub("[\n\v\f]", " / "))
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function wordWhere(entry)
  if type(entry) == "function" then return "the import's own data (an item, a move, a preset name)" end
  if entry.join then
    local parts = {}
    for i, part in ipairs(entry.join) do parts[i] = wordWhere(part) end
    return table.concat(parts, " + ")
  end
  local where = entry[1] .. (entry.line and (", row " .. entry.line) or "")
  if entry.word then where = where .. ", word " .. entry.word end
  return where
end

local function textWhere(entry)
  local parts = {}
  for _, item in ipairs(entry) do
    if item:sub(1, 1) == "_" then parts[#parts + 1] = item end
  end
  local where = table.concat(parts, " + ")
  if entry.page then where = where .. ", page " .. entry.page end
  return where
end

-- the entry's place, and Yellow's where it reads another (#40)
local function where(entry, describe)
  if type(entry) == "function" then return describe(entry) end
  local own = (entry[1] ~= nil or entry.join ~= nil) and describe(entry) or nil
  if entry.yellow == nil then return own end
  local yellow = "Yellow: " .. (entry.yellow and describe(entry.yellow) or "no such row")
  return own and (own .. "; " .. yellow) or yellow
end

-- The PROJECT groups as the source spells them: "-- name" comment lines
-- head each group of P[...] = "..." entries.
local function projectGroups(root)
  local src = read((root or ".") .. "/src/coop/launcher/../game/German.lua")
  local body = src:match("local P = {}.-\nGerman%.layout = {")
  local groups, current = {}, nil
  local pendingKey, afterBlank = nil, false
  for line in (body .. "\n"):gmatch("(.-)\n") do
    -- a group's name is the comment that follows a blank line; a comment
    -- between entries is a note on the entry below it
    local name = afterBlank and line:match("^%-%- (.+)$")
    afterBlank = line == ""
    local key, value = line:match('^P%["(.-[^\\])"%] = "(.-[^\\])"$')
    if key == nil then
      local k = line:match('^P%["(.-[^\\])"%] =$')
      if k then pendingKey = k end
      local v = pendingKey and line:match('^  "(.-[^\\])"$')
      if v then key, value, pendingKey = pendingKey, v, nil end
    end
    if name and not line:find("^%-%- %-%-") then
      current = { name = name, rows = {} }
      groups[#groups + 1] = current
    elseif key and current then
      current.rows[#current.rows + 1] = { unescape(key), unescape(value) }
    end
  end
  local out = {}
  for _, group in ipairs(groups) do
    if #group.rows > 0 then out[#out + 1] = group end
  end
  return out
end

function M.markdown(root)
  root = root or "."
  local German = require("src.coop.game.German")
  local out = {}
  local function line(s) out[#out + 1] = s end
  line("### From the cartridge")
  line("")
  line("These come from the player's own cartridge at import: nothing to check,")
  line("listed so the owner sees which lines are the cartridge's.")
  line("")
  line("| English | Read from |")
  line("|---|---|")
  for _, k in ipairs(sortedKeys(German.WORDS)) do
    line("| " .. cell(k) .. " | " .. cell(where(German.WORDS[k], wordWhere)) .. " |")
  end
  for _, k in ipairs(sortedKeys(German.TEXTS)) do
    line("| " .. cell(k) .. " | " .. cell(where(German.TEXTS[k], textWhere)) .. " |")
  end
  line("")
  line("### The fork's own wording")
  line("")
  line("Write the better German in the last column; a box row holds 18")
  line("characters, a menu row fewer.")
  for _, group in ipairs(projectGroups(root)) do
    line("")
    line("#### " .. group.name)
    line("")
    line("| English | German | Better German |")
    line("|---|---|---|")
    for _, row in ipairs(group.rows) do
      line("| " .. cell(row[1]) .. " | " .. cell(row[2]) .. " | |")
    end
  end
  line("")
  line("### Kept in English")
  line("")
  line("Names, codes and values that are no words: " .. table.concat((function()
    local quoted = {}
    for i, s in ipairs(M.ENGLISH) do quoted[i] = "`" .. cell(s) .. "`" end
    return quoted
  end)(), ", ") .. ".")
  return table.concat(out, "\n") .. "\n"
end

if arg and arg[0] and arg[0]:find("game_strings%.lua$") then
  package.path = "./?.lua;./?/init.lua;" .. package.path
  local mode = arg[1]
  if mode == "--markdown" then
    io.write(M.markdown())
  elseif mode == "--missing" then
    for _, row in ipairs(M.missing()) do print(("%-50s %s"):format(("%q"):format(row.source), row.file)) end
  elseif mode == "--stale" then
    for _, k in ipairs(M.stale()) do print(("%q"):format(k)) end
  else
    for _, row in ipairs(M.sources()) do print(("%q"):format(row.source)) end
  end
end

return M
