-- The Hall of Fame continues the co-op world (#55, design A10.7, G30).
--
-- After THE END the cartridge saves and resets: the boot sequence, the
-- title, CONTINUE.  In a co-op window the reset continues the co-op world
-- instead, and so does every other reset there (START > QUIT, the soft
-- reset chord, the touch skin's reset; Game:returnToTitle, a marked hook):
--
--   * the world freezes: the stack is emptied and a blank screen waits
--     ("Waiting for the host..." after a second);
--   * the window says so to the host (`restart`); after the Hall of Fame it
--     first sends the world it just saved, as one that asks for no save
--     (a save the host refused while a battle ran still reaches it), and
--     the induction (`league`, src/coop/battle/League.lua).  The host
--     handles a link's messages in order, so its answer, this player's
--     world with the story laid over it, comes once it has applied
--     everything sent before.  A link that drops meanwhile is redialled by
--     the session and the restart said again on the new one;
--   * the world reopens from that answer as a Continue: the game's own
--     Game:restoreSave, CONTINUE's facing and music.  A player left in the
--     Hall of Fame flies to Pallet Town: SaveData.applyPostGameHome puts
--     them where the engine's own Continue after the credits does (the
--     cartridge's fly warp to Pallet Town), healed.  A player the campaign
--     has no world for (one still in the opening, which saves nothing)
--     starts the opening again, as NEW GAME;
--   * the window opens again as a late one (Window:reopen) and its battle
--     copies go: finished battles are dropped, a running one this player
--     is in comes back from its record as after a drop (Battles.reopen).
--
-- A reset loses what the window had not sent yet, as a reset on the
-- cartridge loses what was not saved: the world reopens as the host last
-- had it (the last rest point's holdings, the last SAVE).

local Strings = require("src.core.Strings")
local World = require("src.coop.campaign.World")

local Restart = {}

Restart.SHOW_AFTER = 60 -- frames before the waiting line shows

-- the session of a co-op world whose game runs: joined, or redialling
function Restart.session()
  local Session = package.loaded["src.coop.session.Session"]
  local s = Session and Session.current
  if s and s.client and s.inGame and (s.status == "joined" or s.status == "reconnecting") then
    return s
  end
  return nil
end

-- The reset of a co-op window (kind "hall" after the Hall of Fame,
-- "reset" otherwise): returns true when the co-op world takes it over.
function Restart.take(game, kind)
  if not Restart.session() then return false end
  pcall(function() require("src.core.Music").stop() end)
  while game.stack:top() do game.stack:pop() end
  game.stack:push(Restart.waiting(game, kind))
  return true
end

-- the frozen world: what is sent, the answer awaited
function Restart.waiting(game, kind)
  local w = { isOpaque = true, screenId = "CoopRestart", game = game, kind = kind, frames = 0 }
  function w.update(self) Restart.step(self) end
  function w.draw(self)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    if self.frames < Restart.SHOW_AFTER then return end
    local Font = require("src.render.Font")
    Font.drawBox(0, 12, 20, 6)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings("Waiting for the host..."), 8, 14 * 8)
    love.graphics.setColor(1, 1, 1, 1)
  end
  return w
end

-- one frame of the frozen world
function Restart.step(w)
  w.frames = w.frames + 1
  local s = Restart.session()
  -- a session that ended takes the game to the launcher (Session.lua)
  if not s or s.client.status ~= "joined" then return end
  local c = s.client
  if w.client ~= c then
    -- a new link hears it all again
    w.client = c
    if w.kind == "hall" then
      s:sendWorld(w.game.save, false, "hall")
      c:sendLeague("inducted")
    end
    w.seq = c:sendRestart(w.kind)
  end
  local world = c.world
  if w.seq and world and world.restart == w.seq then
    w.done = true
    Restart.reopen(w.game, s, world)
  end
end

-- The world from the host's answer, as a Continue opens it.
function Restart.reopen(game, s, world)
  local save = not world.fresh and world.save and World.decode(world.save) or nil
  if s.window then s.window:reopen() end
  require("src.coop.game.Battles").reopen(s.client)
  require("src.coop.game.Notices").clear()
  if not save then
    game:startNewGame()
    return
  end
  -- the device's options stay the device's (the host keeps none)
  save.options = game.save and game.save.options or save.options
  if type(save.player) == "table" and save.player.map == "HALL_OF_FAME" then
    local SaveData = require("src.core.SaveData")
    local Pokemon = require("src.pokemon.Pokemon")
    SaveData.applyPostGameHome(save, game:bootConfig())
    for _, mon in ipairs(save.party or {}) do Pokemon.heal(mon) end
  end
  game:restoreSave(save, nil, { freshBoot = true, continued = true })
end

return Restart
