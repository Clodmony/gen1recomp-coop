-- The launcher's words in the player's language (#41): one catalog for
-- every player-facing launcher string, English and German.  The English
-- source is the key, as in upstream's Strings (src/core/Strings.lua), which
-- the launcher cannot use: that catalog fills only once a game boots.
--
--   local L = require("src.coop.launcher.Text").get
--   L("JOIN A FRIEND")
--   L("The host plays %s. This game is %s.", host, mine)
--
-- The launcher's language is a setting of its own (ENGLISH / DEUTSCH, kept
-- in coop/launcher.json), first taken from the system's language.  A
-- game's own text follows its cartridge, not this setting.
--
-- A German entry keeps the English one's `%` directives in the same order.
-- An English string with no German entry is shown in English and listed in
-- Text.missing, which tests/coop/launcher_ui_test.lua checks after drawing
-- every screen in German.

local Text = {}

Text.LANGUAGES = { "en", "de" }
Text.NAMES = { en = "ENGLISH", de = "DEUTSCH" }

Text.language = "en"
Text.missing = {}

local catalogs = { de = require("src.coop.launcher.TextDe") }
Text.catalogs = catalogs

function Text.set(language)
  Text.language = catalogs[language] and language or "en"
end

-- `english` in the launcher's language, filled with the arguments
function Text.get(english, ...)
  local s = english
  local catalog = catalogs[Text.language]
  if catalog then
    local hit = catalog[english]
    if hit then
      s = hit
    else
      Text.missing[english] = true
    end
  end
  if select("#", ...) > 0 then return s:format(...) end
  return s
end

-- "de" when the system speaks German, else "en".  Reads the POSIX locale
-- variables; `getenv` replaces os.getenv in tests.  A system that sets none
-- of them (Windows, an app opened from macOS' Finder) starts in English.
function Text.systemLanguage(getenv)
  getenv = getenv or os.getenv
  for _, name in ipairs({ "LC_ALL", "LC_MESSAGES", "LANGUAGE", "LANG" }) do
    local v = getenv(name)
    if type(v) == "string" and v ~= "" and v ~= "C" and v ~= "POSIX" then
      -- LANGUAGE is a list ("de:en"); the first entry counts
      return v:lower():match("^de[_%.:@%-]") and "de" or (v:lower() == "de" and "de" or "en")
    end
  end
  return "en"
end

return Text
