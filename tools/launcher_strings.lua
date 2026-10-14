-- The launcher's catalog keys (#41): every English string the fork's
-- launcher puts through Text.get, found in the source, one per line.
--   luajit tools/launcher_strings.lua            -- the keys
--   luajit tools/launcher_strings.lua --missing  -- keys with no German entry
-- tests/coop/launcher_ui_test.lua uses keys() for its check.

local M = {}

M.FILES = {
  "src/coop/launcher/Menu.lua", "src/coop/launcher/CoopMenu.lua",
  "src/coop/launcher/Screens.lua", "src/coop/launcher/Launcher.lua",
  "src/coop/launcher/RomImport.lua", "src/coop/session/Addresses.lua",
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

if arg and arg[0] and arg[0]:find("launcher_strings%.lua$") then
  package.path = "./?.lua;" .. package.path
  local de = arg[1] == "--missing" and require("src.coop.launcher.TextDe") or nil
  for _, k in ipairs(M.keys()) do
    if not de or not de[k] then print(k) end
  end
end

return M
