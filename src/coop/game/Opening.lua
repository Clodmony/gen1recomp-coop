-- The opening in a co-op world (#22, design A4.4 to A4.9): what the game
-- asks of the window (src/coop/campaign/Window.lua) while a new player
-- plays Oak's opening on their private story.  A solo game is untouched.
--
--   Opening.speech(steps, speech)  -- OakSpeech:buildSteps (marked hook)
--   Opening.active()               -- this player plays the opening now
--   Opening.rivalChoice()          -- Commands.rival_battle (marked hook)
--
-- Names (A4.5): the player's name comes from the launcher, so Oak's speech
-- does not ask it.  The rival's name is asked only until somebody named him
-- (or the host did when creating the campaign); the first name given is
-- the campaign's, and a window takes it at its rest points once past the
-- opening.
--
-- While a player is in the opening (A4.4, A4.8, A4.9) nobody is drawn to
-- them and they see nobody (Presence.lua), a battle their world opens stays
-- in the window, and START > SAVE writes nothing (CampaignSave.lua).
--
-- The rival's starter (A4.6): the first player to finish the opening sets
-- the starter he counters for the campaign, and every later rival battle
-- of Red and Blue picks his team from it, whatever starter this player
-- took.  Yellow's rival (EEVEE, `save.rivalStarter`) is #9's.

local Opening = {}

-- the cartridge's longest trainer name
Opening.NAME_LEN = 7

-- the joined session's window, or nil
local function window()
  local Session = package.loaded["src.coop.session.Session"]
  local s = Session and Session.current
  local c = s and s.client
  if not (c and c.status == "joined") then return nil, nil end
  return s.window, s
end

-- true while this player plays the opening
function Opening.active()
  local w = window()
  return w ~= nil and w:inOpening()
end

local PLAYER_STEPS = { "ask_player_name", "name_player", "confirm_player_name" }
local RIVAL_STEPS = { "ask_rival_name", "name_rival", "confirm_rival_name" }

local function has(steps, id)
  for _, step in ipairs(steps) do
    if step.id == id then return true end
  end
  return false
end

-- Oak's speech in a co-op world: no player name to ask (the launcher's),
-- and the rival's only while nobody named him; a name given here goes to
-- the host
function Opening.speech(steps, speech)
  local w, s = window()
  if not (s and speech and speech.game and type(speech.game.save) == "table") then
    return steps
  end
  local OakSpeech = require("src.ui.OakSpeech")
  local player = speech.game.save.player
  local name = tostring(s.client.name or s.name or ""):upper():sub(1, Opening.NAME_LEN)
  if name:find("%S") then
    player.name = name
    for _, id in ipairs(PLAYER_STEPS) do OakSpeech.removeId(steps, id) end
  end
  local rival = s.client.state and s.client.state.rival
  if rival then
    player.rival = rival
    for _, id in ipairs(RIVAL_STEPS) do OakSpeech.removeId(steps, id) end
  elseif w then
    local anchor = has(steps, "confirm_rival_name") and "confirm_rival_name" or "name_rival"
    if has(steps, anchor) then
      OakSpeech.insertAfter(steps, anchor, {
        id = "coop_rival_named", kind = "fn",
        run = function(sp, done)
          w:named(sp.game.save.player.rival)
          done()
        end,
      })
    end
  end
  return steps
end

-- the starter the campaign's rival counters (Red and Blue), or nil: then
-- the player's own choice picks his team, as the cartridge does
function Opening.rivalChoice()
  local _, s = window()
  local chose = s and s.client.state and s.client.state.chose
  if not chose then return nil end
  local GameVersion = require("src.core.GameVersion")
  if GameVersion.isYellow() then return nil end
  return chose
end

return Opening
