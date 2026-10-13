-- Hold B to run (#15, design A14.11, D105): in a co-op session, walking
-- with B held moves at the bike's pace; the bike and surfing keep their
-- own, and a solo game walks as the cartridge does.  No setting.
-- Player:stepLength asks here for every step (a marked hook); the player's
-- `running` tells the session to report the step as a run.
--
-- Upstream has no run option of its own in Gen 1: its movement.speed mod
-- hook is where a mod would add one, and a mod there still wraps this.

local Run = {}

function Run.active()
  local Session = package.loaded["src.coop.session.Session"]
  local s = Session and Session.current
  return s ~= nil and s.client ~= nil and s.client.status == "joined"
end

-- the frames of the step `player` starts; `frames` is the cartridge's
function Run.stepFrames(player, frames, onBike, input)
  player.running = false
  if onBike or player.surfing or player.spinning then return frames end
  if not (input and input.isDown and input:isDown("b")) or not Run.active() then
    return frames
  end
  player.running = true
  return player.bikeStepFrames or 8
end

return Run
