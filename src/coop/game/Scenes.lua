-- Rival scenes in the running game (#59, design A10.5, decision G29).  A
-- solo game never gets past the first line of each function.
--
--   Scenes.started(runner, script)  -- ScriptRunner:run (marked hook)
--   Scenes.step(game)               -- Session:update, every joined frame
--   Scenes.of(map, script, save)    -- the scene a script starts, or nil
--   Scenes.waiting()                -- the box this world waits under, or nil
--
-- The engine keeps no map-script bytes (G21), so a scene is a script the
-- runner starts on one of the maps below whose rows fight the rival
-- (`rival_battle` with his class), while the rival is not beaten yet (the
-- scene's flag).  That covers each way a scene starts: a map script's
-- ambush when the player steps on its cells (Route 22, Cerulean's Nugget
-- Bridge, the S.S. Anne 2F, Pokémon Tower 2F, Silph Co. 7F) and talking
-- to the rival where he waits (Cerulean, the tower).  The scene ends when
-- that script ends.  The Champion's room is not listed (no lock), nor Oak's
-- lab (the opening is the window's own, #22).  Scenes.LIST is the Red and
-- Blue list; Yellow's Jessie and James scenes and its rival maps are #9's
-- (an entry may name another battle verb).
--
-- The driver (A10.5): the window whose world started a scene claims its
-- map on the host (HostScenes.lua); a refused claim plays on, and its
-- battle joins the driver's as one unique encounter (the rival is his map
-- object, #21).  The claim is released at the first rest point after the
-- scene (the window's result patch goes out first, in the same frame), at
-- once when the player leaves the map, and by the host when the driver
-- drops or leaves.  A link that came back claims a scene still running
-- again.
--
-- A partner (A10.5): a window standing on a map another player drives
-- waits from its next rest point, frozen under "<NAME> is facing the rival
-- here. Wait, or join the battle..." (A joins the driver's battle, START or
-- SELECT opens the CO-OP menu).  The frozen world counts as resting, so the
-- scene's result lands at once; the box goes when the claim does.  A
-- player in the opening is never held.

local Strings = require("src.core.Strings")

local Scenes = { LIST = {}, driving = nil, box = nil }

-- the scenes after the opening, Red and Blue (G4: Yellow re-lists, #9)
Scenes.LIST = {
  { key = "route22_1", map = "ROUTE_22", opp = "OPP_RIVAL1",
    flag = "EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE" },
  { key = "route22_2", map = "ROUTE_22", opp = "OPP_RIVAL2",
    flag = "EVENT_BEAT_ROUTE22_RIVAL_2ND_BATTLE" },
  { key = "cerulean", map = "CERULEAN_CITY", opp = "OPP_RIVAL1",
    flag = "EVENT_BEAT_CERULEAN_RIVAL" },
  { key = "ss_anne", map = "SS_ANNE_2F", opp = "OPP_RIVAL2", flag = "EVENT_BEAT_SS_ANNE_RIVAL" },
  { key = "tower", map = "POKEMON_TOWER_2F", opp = "OPP_RIVAL2",
    flag = "EVENT_BEAT_POKEMON_TOWER_RIVAL" },
  { key = "silph", map = "SILPH_CO_7F", opp = "OPP_RIVAL2", flag = "EVENT_BEAT_SILPH_CO_RIVAL" },
}

-- the joined session, or nil
local function session()
  local Session = package.loaded["src.coop.session.Session"]
  local s = Session and Session.current
  if s and s.client and s.client.status == "joined" then return s end
  return nil
end

local function mapOf(game)
  local ow = game and game.overworld
  return ow and ow.map and ow.map.id
end

-- the scene `script` starts on `map` for a world with `save`, or nil
function Scenes.of(map, script, save)
  if type(map) ~= "string" or type(script) ~= "table" then return nil end
  local flags = save and type(save.flags) == "table" and save.flags or {}
  for _, e in ipairs(Scenes.LIST) do
    if e.map == map and not flags[e.flag] then
      local verb = e.verb or "rival_battle"
      for _, row in ipairs(script) do
        if type(row) == "table" and row[1] == verb and (not e.opp or row[2] == e.opp) then
          return e
        end
      end
    end
  end
  return nil
end

-- ScriptRunner:run's hook: the runner has just made its coroutine for
-- `script`; a rival scene is this window's to drive
function Scenes.started(runner, script)
  if not session() then return end
  if require("src.coop.game.Opening").active() then return end
  local game = runner.game
  local map = runner.overworld and runner.overworld.map and runner.overworld.map.id
  local e = Scenes.of(map, script, game and game.save)
  if not e then return end
  Scenes.driving = { entry = e, map = map, runner = runner, co = runner.co }
end

-- the claim on `map` of another player than this one, or nil
function Scenes.claimOn(client, map)
  if not (client and map) then return nil end
  for _, c in ipairs(client.state and client.state.scenes or {}) do
    if c.map == map and c.by ~= client.player then return c end
  end
  return nil
end

local function nameOf(client, id)
  for _, p in ipairs(client.state and client.state.players or {}) do
    if p.id == id then return p.name end
  end
  return "?"
end

-- the box this world waits under --------------------------------------------------

local Wait = {}
Wait.__index = Wait

function Wait.new(game, claim, name)
  -- coopRest: the world under it counts as resting (SharedWorld.busy)
  return setmetatable({ game = game, claim = claim, name = name, map = claim.map,
                        isOpaque = false, coopRest = true }, Wait)
end

function Wait:lines()
  local text = Strings("%s is facing the rival here. Wait, or join the battle...", self.name)
  return require("src.coop.game.Notices").wrap(text, 18)
end

function Wait:close()
  if Scenes.box == self then Scenes.box = nil end
  local stack = self.game.stack
  if stack:top() == self then
    stack:pop()
    return
  end
  for i, st in ipairs(stack.states or {}) do
    if st == self then table.remove(stack.states, i) break end
  end
end

-- the driver's battle this player may join, or nil
function Wait:offer()
  for _, o in ipairs(require("src.coop.game.Battles").offers()) do
    if o.summary.by == self.claim.by then return o end
  end
  return nil
end

function Wait:update()
  local game = self.game
  local s = session()
  if not s or mapOf(game) ~= self.map then return self:close() end
  if not Scenes.claimOn(s.client, self.map) then
    -- the claim's gone: the box goes on a rest frame, so the window has
    -- taken the story the release came behind (the scene's result)
    if s.window and s.window:resting() then self:close() end
    return
  end
  local input = game.input
  if not input then return end
  if input:wasPressed("a") then
    local o = self:offer()
    if o then require("src.coop.game.Battles").join(game, o.summary, o.name) end
  elseif input:wasPressed("start") or input:wasPressed("select") then
    require("src.coop.game.CoopMenu").select(game)
  end
end

function Wait:draw()
  local Font = require("src.render.Font")
  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(0, 0, 0, 1)
  for i, line in ipairs(self:lines()) do
    if i > 4 then break end
    Font.draw(line, 8, (12 + i) * 8)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Scenes.waiting()
  return Scenes.box
end

-- every joined frame ----------------------------------------------------------

-- the driver's side: claim on each link, let go at the first rest point
-- after the scene (the window sent its patch earlier this frame)
local function drive(s, game, d)
  local c = s.client
  local key = d.entry.key
  if not d.ended and (d.runner.co ~= d.co or not d.runner:isRunning()) then d.ended = true end
  if mapOf(game) ~= d.map then
    if d.sentTo then c:sendScene(d.map, key, false) end
    Scenes.driving = nil
    return
  end
  if d.ended then
    if not d.sentTo then
      Scenes.driving = nil
    elseif s.window and s.window:resting() then
      c:sendScene(d.map, key, false)
      Scenes.driving = nil
    end
    return
  end
  if d.sentTo ~= c and c:sendScene(d.map, key, true) then d.sentTo = c end
end

function Scenes.step(game)
  local s = session()
  if not s then return end
  local d = Scenes.driving
  if d then return drive(s, game, d) end
  if not game then return end
  local box = Scenes.box
  if box then
    -- a box something else took off the stack (a reload, the launcher)
    local on = false
    for _, st in ipairs(game.stack and game.stack.states or {}) do
      if st == box then on = true end
    end
    if on then return end
    Scenes.box = nil
  end
  local ow = game.overworld
  if not (ow and game.stack and game.stack:top() == ow) then return end
  if not (s.window and s.window:resting()) then return end
  if ow.player and ow.player.moving then return end -- between two cells
  if require("src.coop.game.Opening").active() then return end
  local claim = Scenes.claimOn(s.client, mapOf(game))
  if not claim then return end
  Scenes.box = Wait.new(game, claim, nameOf(s.client, claim.by))
  game.stack:push(Scenes.box)
end

return Scenes
