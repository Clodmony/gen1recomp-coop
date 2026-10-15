-- The shared world in the running game (#14, design A5.4, A5.11): the
-- frame a window (src/coop/campaign/Window.lua) is handed each frame, built
-- from the Gen 1 overworld, and the co-op rules a map script asks about.
-- A solo game never gets here.
--
--   SharedWorld.step(window, game)     -- Session:update, every joined frame
--   SharedWorld.busy(game)             -- what holds the player, or nil
--   SharedWorld.keepsVermilionLocks(game) -- VERMILION_CITY.onEnter (marked hook)
--
-- A rest point (A5.4, D72) is a frame where the cartridge could save:
-- nothing holds the player.  Held: anything on the state stack above the
-- overworld (a text box, a menu, the CO-OP box, a battle, a fade, a
-- whole-screen overlay), a map load or warp, a running or queued script, a
-- forced or scripted walk (scriptMoves, spinner tiles, a ledge hop), a
-- trainer's approach, a script-held NPC, and the overworld's own animations
-- (fly, teleport, holes, CUT, a boulder's dust, a heal).  Not held: the box
-- a world waits under while a partner faces the rival on its map (#59).  A step the player
-- walks of their own is not held (Window.lua).  A battle the host runs for
-- this player comes with #18.
--
-- Story items (#16): a gift the window lands is told in a notice
-- (`giftText`): a partner's shared item, one that went to the PC, a key
-- item handed over, one with no room anywhere.  A late joiner's list says
-- "Got …"; a race's take-back and a key item already held say nothing.

local Strings = require("src.core.Strings")

local SharedWorld = {}

-- the overworld's animation fields that lock the player while set
local ANIMATIONS = {
  "emote", "teleportOut", "flyAnim", "flyArrive", "spinArrive", "holeFall",
  "holeArrive", "healAnim", "pikaHop", "cutAnim", "shipAnim", "cameraPan",
  "spinnerSliding", "flyFade",
}

function SharedWorld.busy(game)
  local ow = game and game.overworld
  if not (ow and ow.player and ow.map) then return "no_overworld" end
  local stack = game.stack
  local top = stack and stack:top()
  -- a box the world waits under that counts as resting: a partner's rival
  -- scene (#59, Scenes.lua)
  if top and top.coopRest and stack.states and stack.states[#stack.states - 1] == ow then
    top = ow
  end
  if top ~= ow then return "above" end
  if ow.transitioning then return "map_load" end
  if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then return "script" end
  if ow.pendingScripts and #ow.pendingScripts > 0 then return "script" end
  if ow.scriptMoves and #ow.scriptMoves > 0 then return "forced_walk" end
  if ow.engaging then return "trainer" end
  if type(ow.npcMoveLocks) == "table" and next(ow.npcMoveLocks) then return "npc" end
  local p = ow.player
  if p.inputLocked or p.spinning or p.ledgeHop then return "forced_walk" end
  if (ow.hopLand or 0) > 0 then return "forced_walk" end
  for _, k in ipairs(ANIMATIONS) do
    if ow[k] then return k end
  end
  if ow.dustAnim and ow.dustAnim.boulder then return "boulder" end
  return nil
end

-- the frame for the window: the live save, what holds the player, the map
-- and how to reload or refresh it in place
function SharedWorld.frame(game)
  local ow = game and game.overworld
  local map = ow and ow.map and ow.map.id
  return {
    save = game and game.save,
    busy = SharedWorld.busy(game),
    map = map,
    still = not (ow and ow.player and ow.player.moving),
    -- a block swap stamped from a flag: the map is built again (A5.7)
    reload = function(id)
      if ow and ow.reloadMap and ow.map and ow.map.id == id then
        ow:reloadMap(id, "coop")
      end
    end,
    -- an object hidden or shown: the map's people are built again in place,
    -- as WorldAPI:toggleObject does (A5.6)
    refresh = function(id)
      if ow and ow.setMap and ow.map and ow.map.id == id then
        local p = ow.player
        ow:setMap(id, p.cellX, p.cellY, p.facing,
                  { seamless = true, via = "reload", keepMusic = true })
      end
    end,
    -- a gift landed (#16): a notice over the world
    gifted = function(gift, where)
      local text = SharedWorld.giftText(gift, where, game and game.data)
      if text then require("src.coop.game.Notices").push(text) end
    end,
  }
end

-- the notice for a gift the window landed (`where`: Items.give's or
-- "taken"), or nil for one that says nothing
function SharedWorld.giftText(gift, where, data)
  local def = data and data.items and data.items[gift.item]
  local name = def and def.name or gift.item
  if gift.qty > 1 then name = name .. " x" .. gift.qty end
  if gift.race or where == "held" then return nil end
  if gift.qty < 0 then
    if where ~= "taken" or not gift.from then return nil end
    return Strings("%s handed over %s.", gift.from, name)
  end
  if not where then return Strings("No room for %s!", name) end
  if where == "pc" then return Strings("%s went to the PC.", name) end
  if gift.from then return Strings("%s shared %s.", gift.from, name) end
  return Strings("Got %s.", name)
end

function SharedWorld.step(window, game)
  if not (window and game and type(game.save) == "table") then return end
  window:update(SharedWorld.frame(game))
end

-- the joined session's client, or nil
local function client()
  local Session = require("src.coop.session.Session")
  local s = Session.current
  local c = s and s.client
  if c and c.status == "joined" then return c end
  return nil
end

SharedWorld.VERMILION = { VERMILION_CITY = true, VERMILION_GYM = true }

-- Vermilion's first lock (A5.11, D77): while another connected player is
-- in Vermilion City or its gym, a window entering the city keeps the
-- campaign's trash-can locks instead of rolling new ones.  A dropped
-- partner does not count.
function SharedWorld.keepsVermilionLocks(game)
  local c = client()
  if not (c and c.state) then return false end
  for _, p in ipairs(c.state.players or {}) do
    if p.id ~= c.player and p.connected and p.map and SharedWorld.VERMILION[p.map] then
      return true
    end
  end
  return false
end

return SharedWorld
