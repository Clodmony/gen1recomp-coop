-- The launcher's catalog keys (#41): every English string the fork's
-- launcher puts through Text.get, found in the source, one per line.
--   luajit tools/launcher_strings.lua            -- the keys
--   luajit tools/launcher_strings.lua --missing  -- keys with no German entry
--   luajit tools/launcher_strings.lua --markdown -- the German as tables for
--                                                   docs/coop/german-wording.md
-- tests/coop/launcher_ui_test.lua uses keys() and markdown() for its checks.

local M = {}

M.FILES = {
  "src/coop/launcher/Menu.lua", "src/coop/launcher/CoopMenu.lua",
  "src/coop/launcher/Screens.lua", "src/coop/launcher/Launcher.lua",
  "src/coop/launcher/RomImport.lua", "src/coop/session/Addresses.lua",
  "src/coop/launcher/Controls.lua", "src/coop/launcher/GameOptions.lua",
  "src/coop/launcher/Saves.lua",
}

-- strings handed to Text.get from a table rather than a literal call
M.TABLES = {
  "PLAY", "CAMPAIGNS", "CONTROLS", "SETTINGS", "HELP",
  "ARROWS MOVE · ENTER OR Z CONFIRM · ESC OR X BACK", "D-PAD MOVE · A CONFIRM · B BACK",
  "CLICK TO CHOOSE · RIGHT CLICK GOES BACK", "TAP TO CHOOSE",
  "VPN", "HOME NETWORK", "INTERNET", "THIS DEVICE", "NAME",
  "SPACE", "DEL", "END",
  "You left the session.", "You closed the session.", "The host closed the session.",
  "The connection to the host was lost.", "Preparing", "Ready",
  -- the Game Boy buttons (Controls.BUTTONS)
  "UP", "DOWN", "LEFT", "RIGHT", "A", "B", "START", "SELECT",
  -- the game's options (GameOptions.ROWS, SPEEDS)
  "WINDOW", "INTEGER SCALE", "MUSIC", "SOUND", "TEXT SPEED", "BATTLE ANIMATION", "BATTLE STYLE",
  "FAST", "MEDIUM", "SLOW",
}

local function unescape(s)
  return (s:gsub("\\(.)", { n = "\n", t = "\t", ["\\"] = "\\", ['"'] = '"', ["'"] = "'" }))
end

function M.keys(root)
  root = root or "."
  local seen, out = {}, {}
  local function add(k)
    if not seen[k] then seen[k] = true; out[#out + 1] = k end
  end
  for _, file in ipairs(M.FILES) do
    local f = assert(io.open(root .. "/" .. file, "r"))
    local src = f:read("*a")
    f:close()
    for _, fn in ipairs({ "L", "tr" }) do
      for lit in src:gmatch("%f[%w_]" .. fn .. '%(%s*"(.-[^\\])"') do add(unescape(lit)) end
    end
  end
  for _, k in ipairs(M.TABLES) do add(k) end
  return out
end

-- The German entries of TextDe.lua as one markdown table per section (its
-- "--" comment lines), in the file's order.
function M.markdown(root)
  root = root or "."
  local f = assert(io.open(root .. "/src/coop/launcher/TextDe.lua", "r"))
  local src = f:read("*a")
  f:close()
  local de = assert(load(src, "=TextDe.lua", "t", {}))()
  local out = {}
  local function cell(s) return (s:gsub("|", "\\|"):gsub("\n", " / ")) end
  local open = false
  for line in src:gmatch("[^\n]+") do
    local section = line:match("^  %-%- (.+)$")
    local key = line:match('^  %[(".-[^\\]")%]')
    if section then
      out[#out + 1] = ""
      out[#out + 1] = "### " .. section:sub(1, 1):upper() .. section:sub(2)
      out[#out + 1] = ""
      out[#out + 1] = "| English | German now | Better German |"
      out[#out + 1] = "| --- | --- | --- |"
      open = true
    elseif key and open then
      local english = assert(load("return " .. key))()
      out[#out + 1] = ("| %s | %s | |"):format(cell(english), cell(de[english]))
    end
  end
  return table.concat(out, "\n"):gsub("^\n", "") .. "\n"
end

if arg and arg[0] and arg[0]:find("launcher_strings%.lua$") then
  package.path = "./?.lua;" .. package.path
  if arg[1] == "--markdown" then
    io.write(M.markdown())
  else
    local de = arg[1] == "--missing" and require("src.coop.launcher.TextDe") or nil
    for _, k in ipairs(M.keys()) do
      if not de or not de[k] then print(k) end
    end
  end
end

return M
