-- Red and Blue in one co-op game (#9, design A13, decision G33), ROM-free:
-- which cartridges fit a host (the other game of the pair when both are
-- verified dumps; another dump, a hack, Yellow or another language is
-- refused, with why in the host's log); the wild tables of "wild Pokémon
-- from both versions" go from each window to the host and on to the other
-- version's players only while the campaign's switch is on, and are never
-- stored; the encounter rule (the upper half of a 0-255 roll, the same map
-- and slot, only the other version's exclusives, the level kept).
--   luajit tests/coop/versions_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local GameVersion = require("src.core.GameVersion")
local Transport = require("src.coop.session.Transport")
local Protocol = require("src.coop.session.Protocol")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local Versions = require("src.coop.session.Versions")
local WildMix = require("src.coop.game.WildMix")

local SHA = {}
for _, id in ipairs({ "red", "blue", "yellow", "red_de", "blue_de" }) do
  SHA[id] = GameVersion.info(id).sha1
end
local HACK = ("ab"):rep(20)
local CAMPAIGN = "c0123456789abcdef"

-- the pair rule --------------------------------------------------------------

eq(Versions.pair("red"), "blue", "Red pairs with Blue")
eq(Versions.pair("blue_de"), "red_de", "Blau pairs with Rot")
eq(Versions.pair("yellow"), nil, "Yellow has no pair (G4)")
eq(Versions.misfit("red", SHA.red, "red", SHA.red), nil, "the same cartridge fits")
eq(Versions.misfit("red", SHA.red, "blue", SHA.blue), nil, "Blue fits a Red host")
eq(Versions.misfit("blue", SHA.blue, "red", SHA.red), nil, "and Red a Blue host")
eq(Versions.misfit("red_de", SHA.red_de, "blue_de", SHA.blue_de), nil, "Blau fits a Rot host")
eq(Versions.misfit("red", SHA.red, "blue", HACK), "dump", "a Blue hack is another dump")
eq(Versions.misfit("red", HACK, "blue", SHA.blue), "dump",
  "a host on an unverified dump lets in no other game")
eq(Versions.misfit("red", SHA.red, "red", HACK), "dump", "another Red dump is refused")
eq(Versions.misfit("red", SHA.red, "yellow", SHA.yellow), "game", "Yellow never plays with Red")
eq(Versions.misfit("yellow", SHA.yellow, "blue", SHA.blue), "game", "nor Blue with Yellow")
eq(Versions.misfit("red", SHA.red, "blue_de", SHA.blue_de), "language",
  "Blau with Red is another language first (D95)")
eq(Versions.misfit("red_de", SHA.red_de, "blue", SHA.blue), "language",
  "and Blue with Rot")

-- the development entry hosts with the switch on ---------------------------------

do
  local Dev = require("src.coop.session.Dev")
  local none = function() return nil end
  eq(Dev.parse({ "--coop-host=25160", "--coop-mix" }, none).mix, true, "--coop-mix turns it on")
  eq(Dev.parse({ "--coop-host=25160" }, none).mix, false, "off by default")
  eq(Dev.parse({}, function(k)
    return ({ POKEPORT_COOP_HOST = "25160", POKEPORT_COOP_MIX = "1" })[k]
  end).mix, true, "POKEPORT_COOP_MIX=1 too")
end

-- a host over loopback --------------------------------------------------------

local clock, counter = 0, 0
local function newHost(game, opts)
  opts = opts or {}
  clock = 0
  local lines = {}
  local host = Host.new({
    campaign = { id = CAMPAIGN, title = "CO-OP" },
    cartridge = { game = game, sha1 = opts.sha1 or SHA[game] },
    hostName = "HOST", build = "test", mix = opts.mix,
    clock = function() return clock end,
    hex = function(n)
      counter = counter + 1
      return ("%0" .. n .. "x"):format(counter)
    end,
    log = { write = function(_, src, kind, data) lines[#lines + 1] = { kind = kind, data = data } end,
            close = function() end },
  })
  host.lines = lines
  return host, host:serve(Transport.loopback())
end

local function seat(hub, name, game, sha1)
  counter = counter + 1
  return Client.new(hub:dial(), {
    name = name, game = game, sha1 = sha1 or SHA[game], device = ("d%x"):format(counter),
    seat = 1, build = "test",
  })
end

local function pump(host, clients, frames)
  for _ = 1, frames or 3 do
    for _, c in ipairs(clients) do c:update() end
    host:update()
    for _, c in ipairs(clients) do c:update() end
  end
end

local function logged(host, kind)
  local out = {}
  for _, l in ipairs(host.lines) do if l.kind == kind then out[#out + 1] = l.data end end
  return out
end

do
  local host, hub = newHost("red")
  local red = seat(hub, "RED", "red")
  red:join()
  local blue = seat(hub, "BLUE", "blue")
  blue:probe()
  pump(host, { red, blue })
  eq(blue.lobby and blue.lobby.refused, "", "a probe from Blue finds the Red host open")
  blue:join()
  pump(host, { red, blue })
  eq(blue.status, "joined", "Blue joins a Red host (D101)")
  eq(host:player(blue.player).game, "blue", "the host knows the partner's cartridge")
  eq(host:lobby().game, "red", "the campaign stays the host's game")
  eq(host.state.game, "red", "and its file the host's")

  local hack = seat(hub, "HACK", "blue", HACK)
  hack:probe()
  pump(host, { red, hack })
  eq(hack.lobby and hack.lobby.refused, "content_mismatch", "a Blue hack's probe is refused")
  hack:join()
  local yellow = seat(hub, "YELLOW", "yellow")
  yellow:join()
  local blau = seat(hub, "BLAU", "blue_de")
  blau:join()
  local reddump = seat(hub, "RED2", "red", HACK)
  reddump:join()
  pump(host, { red, hack, yellow, blau, reddump })
  for _, c in ipairs({ hack, yellow, blau, reddump }) do
    eq(c.reason, "content_mismatch", c.name .. " is refused for its cartridge")
  end
  local whys = {}
  for _, d in ipairs(logged(host, "misfit")) do whys[d.game] = d.why end
  eq(whys.yellow, "game", "the host's log says Yellow is another game")
  eq(whys.blue_de, "language", "Blau another language")
  eq(whys.blue, "dump", "the Blue hack another dump")
  eq(whys.red, "dump", "and the other Red dump too")
  eq(#host.players, 2, "nobody else was created")
end

do
  local host, hub = newHost("red_de")
  local rot = seat(hub, "ROT", "red_de")
  local blau = seat(hub, "BLAU", "blue_de")
  local blue = seat(hub, "BLUE", "blue")
  rot:join(); blau:join(); blue:join()
  pump(host, { rot, blau, blue })
  eq(blau.status, "joined", "Blau joins a Rot host")
  eq(blue.reason, "content_mismatch", "English Blue does not")
end

-- the wild tables of both versions ------------------------------------------

local RED_WILD = {
  ROUTE_4 = { grass = { { species = "RATTATA", level = 10 }, { species = "EKANS", level = 6 } } },
  ROUTE_1 = { grass = { { species = "PIDGEY", level = 3 }, { species = "RATTATA", level = 3 } } },
  SEAFOAM_ISLANDS_B4F = { water = { { species = "HORSEA", level = 30 } } },
}
local BLUE_WILD = {
  ROUTE_4 = { grass = { { species = "RATTATA", level = 10 }, { species = "SANDSHREW", level = 6 } } },
  ROUTE_1 = { grass = { { species = "PIDGEY", level = 3 }, { species = "RATTATA", level = 3 } } },
  SEAFOAM_ISLANDS_B4F = { water = { { species = "KRABBY", level = 30 } } },
}

do
  local host, hub = newHost("red", { mix = true })
  local red = seat(hub, "RED", "red")
  red:join()
  pump(host, { red })
  eq(host:wildWaiting(), "blue", "with the switch on the host waits for a Blue player")
  red:sendWild(RED_WILD)
  pump(host, { red })
  eq(red.wild, nil, "a Red window gets nothing before a Blue one sent its tables")
  local red2 = seat(hub, "RED2", "red")
  red2:join()
  pump(host, { red, red2 })
  eq(red2.wild, nil, "nor does a second Red window")
  local blue = seat(hub, "BLUE", "blue")
  blue:join()
  pump(host, { red, red2, blue })
  eq(host:wildWaiting(), nil, "a player of each version has been in")
  eq(blue.wild and blue.wild.game, "red", "the Blue window gets Red's tables")
  eq(blue.wild and blue.wild.maps.ROUTE_4.grass[2].species, "EKANS", "slot by slot")
  eq(red.wild, nil, "Red waits until Blue's own tables come")
  blue:sendWild(BLUE_WILD)
  pump(host, { red, red2, blue })
  eq(red.wild and red.wild.game, "blue", "then each Red window gets Blue's")
  eq(red2.wild and red2.wild.maps.SEAFOAM_ISLANDS_B4F.water[1].species, "KRABBY",
    "water slots too")
  -- a new link of a player hears them again; a tables message comes once a link
  local sent = 0
  local real = red.conn.send
  for _, l in ipairs(host.links) do
    if l.player and l.player.id == red.player then
      local orig = l.conn.send
      l.conn.send = function(conn, msg)
        if msg.type == "wild" then sent = sent + 1 end
        return orig(conn, msg)
      end
    end
  end
  pump(host, { red, red2, blue }, 5)
  eq(sent, 0, "the tables go out once a link")
  red.conn.send = real
  -- never stored: not in the campaign, and the log names only how much
  local snapshot = require("src.link.Json").encode(host.state:snapshot())
  check(not snapshot:find("SANDSHREW") and not snapshot:find("EKANS"),
    "the campaign keeps no wild table")
  local wl = logged(host, "wild")
  eq(#wl, 2, "the host logs each window's tables")
  check(wl[1] and wl[1].maps == 3 and not require("src.link.Json").encode(wl):find("EKANS"),
    "as a count of maps, not the table")
  -- a malformed table is dropped whole
  local dropped = host.dropped
  red.conn:send({ type = "wild", seq = red.seq + 1,
                  maps = { ROUTE_4 = { grass = { { species = "ekans!", level = 6 } } } } })
  pump(host, { red })
  eq(host.dropped, dropped + 1, "a bad species name drops the message")
  local big = {}
  for i = 1, 11 do big[i] = { species = "RATTATA", level = 3 } end
  check(Protocol.sanitize({ type = "wild", seq = 1, maps = { ROUTE_1 = { grass = big } } },
    "host") == nil, "a table of more than ten slots too")
end

do
  local host, hub = newHost("red", { mix = false })
  local red = seat(hub, "RED", "red")
  local blue = seat(hub, "BLUE", "blue")
  red:join(); blue:join()
  pump(host, { red, blue })
  red:sendWild(RED_WILD); blue:sendWild(BLUE_WILD)
  pump(host, { red, blue })
  eq(host:wildWaiting(), nil, "with the switch off nothing waits")
  check(red.wild == nil and blue.wild == nil, "and no tables are passed on")
end

do
  local host, hub = newHost("yellow", { mix = true })
  local y = seat(hub, "YELLOW", "yellow")
  y:join()
  pump(host, { y })
  eq(host:wildWaiting(), nil, "Yellow has no other version to wait for")
end

-- the encounter rule ---------------------------------------------------------

local data = {
  encounters = {
    ROUTE_4 = { grass = { rate = 20, slots = { { species = "RATTATA", level = 10 },
                                               { species = "EKANS", level = 6 } } } },
    ROUTE_22 = { grass = { rate = 25, slots = { { species = "NIDORAN_M", level = 3 },
                                                { species = "NIDORAN_F", level = 3 } } } },
    SEAFOAM_ISLANDS_B4F = { water = { rate = 5, slots = { { species = "HORSEA", level = 30 } } } },
  },
  pokemon = { RATTATA = {}, EKANS = {}, SANDSHREW = {}, NIDORAN_M = {}, NIDORAN_F = {},
              HORSEA = {}, KRABBY = {} },
}
local other = {
  ROUTE_4 = { grass = { { species = "RATTATA", level = 10 }, { species = "SANDSHREW", level = 8 } } },
  ROUTE_22 = { grass = { { species = "NIDORAN_F", level = 3 }, { species = "NIDORAN_M", level = 3 } } },
  SEAFOAM_ISLANDS_B4F = { water = { { species = "KRABBY", level = 30 } } },
  ROUTE_9 = { grass = { { species = "MEWTWO", level = 70 } } },
}
local function rolls(list)
  local i = 0
  return function(lo, hi)
    i = i + 1
    assert(lo == 0 and hi == 255, "a 0-255 roll")
    return list[i]
  end, function() return i end
end

local rng, drawn = rolls({ 200 })
local enc = WildMix.substitute({ species = "EKANS", level = 6, slot = 2 }, "ROUTE_4", "grass",
  other, data, rng)
eq(enc.species, "SANDSHREW", "the upper half of the roll takes the other version's Pokémon")
eq(enc.level, 6, "at this cartridge's level for the slot")
eq(drawn(), 1, "one roll")
rng, drawn = rolls({ 127 })
enc = WildMix.substitute({ species = "EKANS", level = 6, slot = 2 }, "ROUTE_4", "grass",
  other, data, rng)
eq(enc.species, "EKANS", "the lower half keeps the cartridge's")
rng, drawn = rolls({ 255 })
enc = WildMix.substitute({ species = "NIDORAN_M", level = 3, slot = 1 }, "ROUTE_22", "grass",
  other, data, rng)
eq(enc.species, "NIDORAN_M", "a slot that only shuffles shared Pokémon stays")
eq(drawn(), 0, "and draws no roll")
enc = WildMix.substitute({ species = "RATTATA", level = 10, slot = 1 }, "ROUTE_4", "grass",
  other, data, rng)
eq(enc.species, "RATTATA", "a shared slot stays")
rng = rolls({ 128 })
enc = WildMix.substitute({ species = "HORSEA", level = 30, slot = 1 }, "SEAFOAM_ISLANDS_B4F",
  "water", other, data, rng)
eq(enc.species, "KRABBY", "a water slot takes the other water table's")
rng, drawn = rolls({ 255 })
enc = WildMix.substitute({ species = "HORSEA", level = 30, slot = 1 }, "SEAFOAM_ISLANDS_B4F",
  "grass", other, data, rng)
eq(enc.species, "HORSEA", "a grass roll never reads the water table")
data.encounters.ROUTE_9 = { grass = { rate = 1, slots = { { species = "RATTATA", level = 70 } } } }
enc = WildMix.substitute({ species = "RATTATA", level = 70, slot = 1 }, "ROUTE_9", "grass",
  other, data, rng)
eq(enc.species, "RATTATA", "a species this cartridge does not know is never made up")
enc = WildMix.substitute({ species = "EKANS", level = 6 }, "ROUTE_4", "grass", other, data, rng)
eq(enc.species, "EKANS", "an encounter without its slot (a mod's roll) stays")
enc = WildMix.substitute({ species = "EKANS", level = 6, slot = 2 }, "ROUTE_7", "grass",
  other, data, rng)
eq(enc.species, "EKANS", "a map the other version has no table for keeps its own")
eq(WildMix.substitute(nil, "ROUTE_4", "grass", other, data, rng), nil, "no encounter, none")
-- the window's own tables, as it sends them
local mine = WildMix.tables(data)
eq(mine.ROUTE_4.grass[2].species, "EKANS", "a window sends its grass slots in order")
eq(mine.SEAFOAM_ISLANDS_B4F.water[1].level, 30, "and its water slots")
check(Protocol.sanitize({ type = "wild", seq = 1, maps = mine }, "host") ~= nil,
  "in the protocol's shape")

T.finish()
