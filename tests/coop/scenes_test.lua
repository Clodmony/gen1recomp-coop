-- Rival scenes on the host (#59, design A10.5, decision G29), ROM-free:
-- three players over loopback, the windows' claims sent by hand.
-- Covered: the first claim of a map drives and `state` names it; a second
-- claim of that map is refused (`scene_taken`), another map has its own
-- driver; a driver's own claim again changes nothing; a release by the
-- driver ends it, one by anybody else is ignored; the driver changing map,
-- dropping or leaving lets go; a driver's result patch reaches the
-- partners before the release does; a malformed claim is dropped.
--   luajit tests/coop/scenes_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Transport = require("src.coop.session.Transport")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")
local Protocol = require("src.coop.session.Protocol")

local SHA = ("ab"):rep(20)

local clock, idCounter = 0, 0
local logLines = {}
local host = Host.new({
  campaign = { id = "c0123456789abcdef", title = "RED CO-OP" }, cartridge = { game = "red", sha1 = SHA },
  clock = function() return clock end,
  hex = function(n) idCounter = idCounter + 1; return ("%0" .. n .. "x"):format(idCounter) end,
  log = { write = function(_, _, kind, data) logLines[#logLines + 1] = { kind = kind, data = data } end,
          close = function() end },
})
local hub = host:serve(Transport.loopback())

local function seat(name, n)
  local c = Client.new(hub:dial(), { name = name, game = "red", sha1 = SHA, device = "d" .. n,
                                     build = "test" })
  c:join()
  return c
end
local red, green, blue = seat("RED", 1), seat("GREEN", 2), seat("BLUE", 3)
local all = { red, green, blue }
local function pump(frames)
  for _ = 1, frames or 3 do
    clock = clock + 1 / 60
    for _, c in ipairs(all) do if c.status ~= "closed" then c:update() end end
    host:update()
    for _, c in ipairs(all) do if c.status ~= "closed" then c:update() end end
  end
end
pump()
for _, c in ipairs(all) do eq(c.status, "joined", c.name .. " joined") end
red:move("ROUTE_22", 29, 4, "left", true, "walk")
green:move("ROUTE_22", 20, 5, "right", true, "walk")
blue:move("CERULEAN_CITY", 20, 6, "up", true, "walk")
pump()

local function lastRejection(c)
  local r = c.rejections[#c.rejections]
  return r and r.reason
end
local function claims(c)
  local out = {}
  for _, sc in ipairs(c.state and c.state.scenes or {}) do out[sc.map] = sc end
  return out
end

-- the protocol -------------------------------------------------------------------
do
  check(Protocol.VERSION >= 11, "protocol 11 carries the rival scenes")
  check(Protocol.sanitize({ type = "scene", seq = 1, map = "ROUTE_22", key = "route22_1", on = true }, "host"),
        "a claim is a scene message")
  eq(Protocol.sanitize({ type = "scene", seq = 1, map = "ROUTE_22", key = "Route 22!", on = true }, "host"),
     nil, "a malformed scene key is dropped")
  eq(Protocol.sanitize({ type = "scene", seq = 1, map = "ROUTE_22", key = "route22_1" }, "host"),
     nil, "a scene message says claim or release")
  check(Protocol.REASONS.scene_taken, "scene_taken is a refusal")
end

-- the first claim drives (A10.5) ------------------------------------------------------
do
  red:sendScene("ROUTE_22", "route22_1", true)
  pump()
  local c = claims(green).ROUTE_22
  check(c ~= nil, "the claim is in everyone's state")
  eq(c and c.by, red.player, "RED drives Route 22's scene")
  eq(c and c.key, "route22_1", "named by its key")
  local n = #green.rejections
  green:sendScene("ROUTE_22", "route22_1", true)
  pump()
  eq(#green.rejections, n + 1, "a second claim of the map is refused")
  eq(lastRejection(green), "scene_taken", "as scene_taken")
  eq(claims(blue).ROUTE_22.by, red.player, "RED still drives")
  blue:sendScene("CERULEAN_CITY", "cerulean", true)
  pump()
  eq(claims(red).CERULEAN_CITY and claims(red).CERULEAN_CITY.by, blue.player,
     "another map has a driver of its own")
  n = #red.rejections
  red:sendScene("ROUTE_22", "route22_1", true)
  pump()
  eq(#red.rejections, n, "the driver's own claim again is no refusal")
  eq(claims(blue).ROUTE_22.by, red.player, "and changes nothing")
  -- a release by somebody else is ignored
  green:sendScene("ROUTE_22", "route22_1", false)
  pump()
  eq(claims(blue).ROUTE_22 and claims(blue).ROUTE_22.by, red.player, "only the driver releases")
  red:sendScene("ROUTE_22", "route22_1", false)
  blue:sendScene("CERULEAN_CITY", "cerulean", false)
  pump()
  eq(claims(green).ROUTE_22, nil, "the driver's release ends the claim")
  eq(next(claims(green)), nil, "no scene is claimed")
  green:sendScene("ROUTE_22", "route22_1", true)
  pump()
  eq(claims(red).ROUTE_22 and claims(red).ROUTE_22.by, green.player, "then the map is free to claim")
  green:sendScene("ROUTE_22", "route22_1", false)
  pump()
end

-- the result patch first, then the release (A10.5) -------------------------------------
do
  red:sendScene("ROUTE_22", "route22_1", true)
  pump()
  local order = {}
  local handle = green._handle
  green._handle = function(self, msg)
    if msg.type == "story" and msg.set["flags/EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE"] then
      order[#order + 1] = "story"
    elseif msg.type == "state" and not claims({ state = msg }).ROUTE_22 then
      order[#order + 1] = "released"
    end
    return handle(self, msg)
  end
  -- the driver's window sends its scene's result at its rest point, then lets go
  red:sendPatch({ ["flags/EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE"] = true,
                  ["objectToggles/ROUTE_22/ROUTE22_RIVAL1"] = false }, {})
  red:sendScene("ROUTE_22", "route22_1", false)
  pump()
  green._handle = handle
  eq(order[1], "story", "the partner hears the scene's result first")
  eq(order[2], "released", "then the release")
  eq(green.story["flags/EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE"], true, "the rival is beaten in GREEN's story")
end

-- the driver changing map lets go (A10.5) ------------------------------------------------
do
  red:sendScene("ROUTE_22", "route22_2", true)
  pump()
  red:move("ROUTE_22", 29, 5, "left", false, "walk")
  pump()
  eq(claims(green).ROUTE_22 and claims(green).ROUTE_22.by, red.player, "a step on the map keeps it")
  red:move("VIRIDIAN_CITY", 10, 10, "down", true, "walk")
  pump()
  eq(claims(green).ROUTE_22, nil, "a map change lets go")
  red:move("ROUTE_22", 29, 4, "left", true, "walk")
  pump()
end

-- a claim sent before the move onto its map holds once the move comes ---------------------
do
  blue:sendScene("ROUTE_22", "route22_1", true)
  pump()
  eq(claims(red).ROUTE_22 and claims(red).ROUTE_22.by, blue.player,
     "a claim names its map, wherever the host last saw the driver")
  blue:move("ROUTE_22", 29, 5, "left", true, "walk")
  pump()
  eq(claims(red).ROUTE_22 and claims(red).ROUTE_22.by, blue.player, "arriving on it keeps it")
  blue:sendScene("ROUTE_22", "route22_1", false)
  blue:move("CERULEAN_CITY", 20, 6, "up", true, "walk")
  pump()
end

-- the driver dropping or leaving lets go (A10.5) -------------------------------------------
do
  green:sendScene("ROUTE_22", "route22_1", true)
  pump()
  eq(claims(red).ROUTE_22 and claims(red).ROUTE_22.by, green.player, "GREEN drives")
  green.conn:close()
  pump(4)
  eq(claims(red).ROUTE_22, nil, "GREEN's link dropped: the scene is free")
  check((function()
    for _, l in ipairs(logLines) do
      if l.kind == "scene" and l.data.why == "left" then return true end
    end
  end)(), "the host's log says why it let go")
  blue:sendScene("CERULEAN_CITY", "cerulean", true)
  pump()
  eq(claims(red).CERULEAN_CITY and claims(red).CERULEAN_CITY.by, blue.player, "BLUE drives")
  blue:leave()
  pump(4)
  eq(claims(red).CERULEAN_CITY, nil, "BLUE left: the scene is free")
end

T.finish()
