-- The cartridges the fork's launcher plays (#3, #25, #40), with the name each
-- one carries on its label and the language of its text.

local Games = {}

Games.LIST = {
  { id = "red", label = "RED", language = "en" },
  { id = "blue", label = "BLUE", language = "en" },
  { id = "yellow", label = "YELLOW", language = "en" },
  { id = "red_de", label = "ROT", language = "de" },   -- Rote Edition (#25)
  { id = "blue_de", label = "BLAU", language = "de" }, -- Blaue Edition (#25)
  { id = "yellow_de", label = "GELB", language = "de" }, -- Gelbe Edition (#40)
}

local byId = {}
for _, g in ipairs(Games.LIST) do byId[g.id] = g end

function Games.label(version)
  local g = byId[version]
  return g and g.label or tostring(version or "?"):upper()
end

function Games.language(version)
  local g = byId[version]
  return g and g.language or "en"
end

function Games.known(version) return byId[version] ~= nil end

return Games
