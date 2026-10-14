-- The launcher's colours (#38): a quiet shell, green LCD panels, one ink
-- and an accent, in a light and a dark set; the edition marks of Red, Blue
-- and Yellow.  Colours are { r, g, b } in 0..1.

local Theme = {}

local function hex(s)
  return { tonumber(s:sub(2, 3), 16) / 255, tonumber(s:sub(4, 5), 16) / 255,
           tonumber(s:sub(6, 7), 16) / 255 }
end

Theme.NAMES = { "light", "dark" }

Theme.light = {
  shell = hex("#F2F1E9"), paper = hex("#FBFAF3"), lcd = hex("#E2E8CD"),
  field = hex("#F0F3E5"), ink = hex("#283B28"), muted = hex("#57664D"),
  line = hex("#BDC8AD"), accent = hex("#344D2D"), onAccent = hex("#F5F8E9"),
  error = hex("#923E30"),
  red = hex("#B45949"), blue = hex("#507799"), yellow = hex("#A78327"),
}

Theme.dark = {
  shell = hex("#171D19"), paper = hex("#202923"), lcd = hex("#253A2B"),
  field = hex("#1B2B20"), ink = hex("#EDF3DD"), muted = hex("#AFBEA4"),
  line = hex("#4E674D"), accent = hex("#D7EE9D"), onAccent = hex("#1C291A"),
  error = hex("#FFC0A6"),
  red = hex("#E8A391"), blue = hex("#9DBFE3"), yellow = hex("#E9D184"),
}

function Theme.get(name) return Theme[name == "dark" and "dark" or "light"] end

-- the edition mark of a game id (a German game wears its US game's colour)
function Theme.edition(colours, game)
  local base = tostring(game or ""):gsub("_de$", "")
  return colours[base] or colours.muted
end

return Theme
