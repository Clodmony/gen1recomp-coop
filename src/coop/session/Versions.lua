-- Which cartridges play one co-op campaign together (#9, design A13, the
-- sibling fork's D101 and D95).  Red and Blue are one game in two
-- cartridges: the same engine, maps, story, Pokémon, moves, items and
-- trainers; they differ in their wild tables (so the version exclusives),
-- Game Corner prizes and the title.  So a host lets in the other game of
-- its pair when both are verified clean dumps; another revision, a hack,
-- Yellow or another language is refused.  Yellow plays with Yellow first
-- (G4); German plays with German only (D95, #25: the German games are ids
-- of their own, so Rot pairs with Blau).
--
--   Versions.pair("red")                       -- "blue"
--   Versions.misfit(hostGame, hostSha1, game, sha1)
--     -- nil when the cartridge fits, else "language", "game" or "dump"
--   Versions.together("red")                   -- { "red", "blue" }
--
-- Pure: no love.*, so the host, the launcher and tests share it.

local GameVersion = require("src.core.GameVersion")

local Versions = {}

-- the other cartridge of each pair, within one language
Versions.PAIRS = { red = "blue", blue = "red", red_de = "blue_de", blue_de = "red_de" }

function Versions.pair(game)
  return Versions.PAIRS[game]
end

-- the games that play a campaign of `game`: itself, then its pair
function Versions.together(game)
  local other = Versions.PAIRS[game]
  if other then return { game, other } end
  return { game }
end

-- a dump the import verifies for that game (the version's own SHA-1, or one
-- of its listed revisions): no hack, no unknown revision
function Versions.clean(game, sha1)
  if type(game) ~= "string" or type(sha1) ~= "string" or not GameVersion.VERSIONS[game] then
    return false
  end
  return GameVersion.acceptsSha1(game, sha1:lower())
end

-- Why cartridge (game, sha1) does not fit a host playing (hostGame,
-- hostSha1), or nil when it fits: "language" (another language, refused
-- before anything else, D95), "dump" (the same game from another dump, or
-- the other game of the pair when either is not a verified dump), "game"
-- (a game that never plays with the host's: Yellow with Red, Red with
-- Gold).
function Versions.misfit(hostGame, hostSha1, game, sha1)
  if GameVersion.language(game) ~= GameVersion.language(hostGame) then return "language" end
  if game == hostGame then
    if sha1 == hostSha1 then return nil end
    return "dump"
  end
  if Versions.PAIRS[hostGame] ~= game then return "game" end
  if not (Versions.clean(hostGame, hostSha1) and Versions.clean(game, sha1)) then return "dump" end
  return nil
end

return Versions
