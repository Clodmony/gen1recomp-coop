-- The game's saves in a co-op world (#13, design A3.10 to A3.12): what the
-- game's save code asks of the campaign.  A solo game is untouched.
--
--   * Game:writeSave (a marked hook) hands the world it just wrote to the
--     session: every write there is a real SAVE (START > SAVE, a box
--     change, the Hall of Fame, a link room's), so each asks the host to
--     save the campaign (A3.11).  A heal, a purchase, a gift or a thrown
--     ball never writes there.  The game's own write goes to the campaign's
--     save slot on this device, never to a solo save (A3.14).
--   * START > SAVE (a marked hook in StartMenu) asks `refusal` before its
--     YES/NO: while the host would refuse (a battle running), the save box
--     says so, writes nothing and asks nothing (A3.10).  While the player
--     plays the opening (#22, A4.9) the box says to leave Oak's lab first,
--     and Game:writeSave writes nothing at all (`vetoes`).
--   * The quick keys (#72): F1 (the quick bar's SAVE) is Game:writeSave, so
--     it saves the campaign; where the save box refuses, it writes nothing
--     and a notice says why (`quickSave`).  F2 (the quick bar's LOAD) loads
--     nothing in a session (`quickLoad`): the host's record is the world,
--     and a world loaded back could hold what was handed to a partner.
--   * The notices say who saved (A3.12): "Campaign saved." for the saver,
--     "<NAME> saved the campaign." for the others; the CO-OP box shows how
--     long ago (`ago`).

local Strings = require("src.core.Strings")

local CampaignSave = {}

local function session()
  local Session = require("src.coop.session.Session")
  local s = Session.current
  if s and s.client and s.client.status == "joined" then return s end
  return nil
end

-- the game wrote its save: the scene so far goes out as a patch (#14,
-- design A5.5), then the world goes to the host with a save request
function CampaignSave.written(game, kind)
  local s = session()
  if not s or not game or type(game.save) ~= "table" then return nil end
  if s.window then s.window:flush(game.save) end
  return s:sendWorld(game.save, true, kind)
end

-- true when the game may not write its save now: the player plays the
-- opening, which writes nothing (#22, design A4.9)
function CampaignSave.vetoes(game)
  return session() ~= nil and require("src.coop.game.Opening").active()
end

-- the save box's text when the host would refuse a save now, or nil
function CampaignSave.refusal(game)
  local s = session()
  if s and require("src.coop.game.Opening").active() then
    return Strings("The opening can't\nbe saved.\fLeave OAK's LAB\nfirst!")
  end
  local why = s and s:saveRefusal()
  if not why then return nil end
  return Strings("A battle is in\nprogress!\fIt can't be saved\nright now.")
end

-- F1: true when the game may write its save now; otherwise the save box's
-- refusal goes out as a notice and nothing is written
function CampaignSave.quickSave(game)
  local why = CampaignSave.refusal(game)
  if not why then return true end
  require("src.coop.game.Notices").push((why:gsub("[\n\f]", " ")))
  return false
end

-- F2: true when the game may load its last save now; in a session it may
-- not, even while its link redials, and a notice says so
function CampaignSave.quickLoad(game)
  local s = require("src.coop.session.Session").current
  if not (s and s.client) then return true end
  require("src.coop.game.Notices").push(Strings("No loading in co-op: the host keeps the world."))
  return false
end

-- the notice for one `saved` message, or nil
function CampaignSave.notice(msg)
  if msg.ok then
    if msg.you then return Strings("Campaign saved.") end
    return Strings("%s saved the campaign.", msg.by)
  end
  if msg.you then return Strings("The campaign was not saved.") end
  return nil
end

-- the CO-OP box's line for the last save
function CampaignSave.ago(s)
  local ago = s and s.savedAgo and s:savedAgo()
  if not ago then return Strings("NOT SAVED YET") end
  local minutes = math.floor(ago / 60)
  if minutes < 1 then return Strings("SAVED JUST NOW") end
  if minutes < 60 then return Strings("SAVED %d MIN AGO", minutes) end
  return Strings("SAVED %d H AGO", math.floor(minutes / 60))
end

return CampaignSave
