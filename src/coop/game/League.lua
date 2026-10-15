-- The team's League run in the window (#55, design A10.6, decision G30).
--
-- The Indigo Plateau lobby erases a run on the cartridge: on entry, once
-- the player has started the Elite Four, its script resets the rooms' and
-- the members' event flags (data/scripts/story6.lua, a marked hook).  In a
-- co-op world the run is the team's: the lobby resets only this player's
-- part of it (the started bit, the walk-ins, Lance's door, the Champion
-- room's run flag; Ownership.PLAYER_FLAGS) and keeps the campaign's (the
-- members' beaten flags and beaten trainers), which the host erases for
-- everybody once nothing holds the run (src/coop/battle/League.lua).  So a
-- player who whited out while a partner is still inside walks back
-- through the rooms the team has beaten.  Every entry asks for the clear:
-- a run left over from a host that forgot its hold ends with the next
-- visit.  The request waits for a link (`League.step`, every frame of a
-- session's game).
--
-- The Hall of Fame's induction goes to the host with the restart that
-- follows it (src/coop/game/Restart.lua).

local Ownership = require("src.coop.campaign.Ownership")

local League = { pending = {} }

-- the session of a co-op world: joined, or redialling a dropped link
function League.session()
  local Session = package.loaded["src.coop.session.Session"]
  local s = Session and Session.current
  if s and s.client and (s.status == "joined" or s.status == "reconnecting") then return s end
  return nil
end

-- an event for the host, sent once a link has it
function League.ask(event)
  local p = League.pending
  if p[#p] ~= event then p[#p + 1] = event end
end

-- every frame of a session's game: the events waiting go out
function League.step(s)
  local c = s and s.client
  if not (c and c.status == "joined") then return end
  while League.pending[1] do
    if not c:sendLeague(League.pending[1]) then return end
    table.remove(League.pending, 1)
  end
end

-- The lobby's entry (INDIGO_PLATEAU_LOBBY.onEnter): `flags` lists the
-- run's flags the cartridge resets, nil when this player started no run.
-- Returns true when the co-op world took the reset.
function League.lobby(game, flags)
  if not League.session() then return false end
  local f = game.save.flags
  if flags then
    f.EVENT_STARTED_ELITE_4 = nil
    for _, flag in ipairs(flags) do
      if not Ownership.owns("flags/" .. flag) then f[flag] = nil end
    end
  end
  League.ask("lobby")
  return true
end

return League
