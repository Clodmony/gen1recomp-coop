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
--     says so, writes nothing and asks nothing (A3.10).
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

-- the save box's text when the host would refuse a save now, or nil
function CampaignSave.refusal(game)
  local s = session()
  local why = s and s:saveRefusal()
  if not why then return nil end
  return Strings("A battle is in\nprogress!\fIt can't be saved\nright now.")
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
