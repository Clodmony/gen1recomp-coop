-- The CO-OP menu in a co-op session (#15, design A14.7-A14.9): a CO-OP row
-- in the cartridge's START menu (after OPTION, only in a co-op session;
-- a marked hook in src/ui/StartMenu.lua), and SELECT on the map opens it
-- too (a marked hook in OverworldState:handleInput).  Drawn with the
-- cartridge's font, boxes and cursor:
--
--   * above, a box with the campaign's name, on the host its address
--     (IP …), and each partner with where they are (the TOWN MAP's area
--     name; AWAY for one who left);
--   * the rows TOWN MAP (only for a player without the TOWN MAP item; it
--     shows the partners' icons too), LEAVE SESSION (asked YES/NO) and
--     CANCEL.
--
-- The box also shows when the campaign was last saved and that it saves
-- itself (#13).  Fight offers, JOIN/REJOIN, BATTLE and TRADE rows, "in a
-- battle" and "in the opening" come with #34 (battles, friend battles, new
-- players).

local Font = require("src.render.Font")
local Menu = require("src.ui.Menu")
local Screens = require("src.ui.Screens")
local Strings = require("src.core.Strings")
local Presence = require("src.coop.game.Presence")
local CampaignSave = require("src.coop.game.CampaignSave")

local CoopMenu = { isMenu = true }

CoopMenu.BOX = { tx = 0, ty = 0, tw = 20, th = 11 }    -- the session box
CoopMenu.ROWS = { tx = 0, ty = 11, tw = 20, th = 7 }   -- the rows

local function hasTownMap(game)
  local inv = game.save and game.save.inventory
  return inv ~= nil and (inv.TOWN_MAP or 0) > 0
end

-- the TOWN MAP's name for a map, or its id
function CoopMenu.areaName(data, mapId)
  local towns = data and data.field and data.field.townMap and data.field.townMap.locations
  local loc = towns and towns[mapId]
  if loc and loc.name then return Strings(loc.name) end
  return tostring(mapId or "?"):gsub("_", " ")
end

-- this device's address for partners, once per menu (host only)
local function hostAddress()
  local ok, list = pcall(function() return require("src.coop.session.Addresses").mine() end)
  local first = ok and type(list) == "table" and list[1]
  return first and first.ip or nil
end

-- the session box's lines
function CoopMenu.lines(game, s, address)
  local title = s.kind == "host" and s.opts.campaign and s.opts.campaign.title
    or s.lobby and s.lobby.title or "CO-OP"
  local lines = { tostring(title):upper():sub(1, 18) }
  if s.kind == "host" then lines[#lines + 1] = "IP " .. (address or "?") end
  -- the last save, and that the campaign saves itself too (#13, A3.12)
  lines[#lines + 1] = CampaignSave.ago(s)
  lines[#lines + 1] = Strings("AUTOSAVE: ON")
  lines[#lines + 1] = ""
  local partners = Presence.partners()
  if #partners == 0 then lines[#lines + 1] = Strings("NO PARTNERS YET") end
  local room = 9 - #lines
  for i, p in ipairs(partners) do
    if room < 2 then
      lines[#lines + 1] = ("+%d MORE"):format(#partners - i + 1)
      break
    end
    lines[#lines + 1] = p.name
    lines[#lines + 1] = " " .. (p.connected and p.map and CoopMenu.areaName(game.data, p.map)
                                or Strings("AWAY"))
    room = room - 2
  end
  return lines
end

-- leave the session from the game: a guest says goodbye, the host ends it
-- for everyone; either way this game goes back to the launcher
function CoopMenu.leave(s)
  s:leave(s.kind == "host" and "You closed the session." or "You left the session.")
end

function CoopMenu.new(game, opts)
  opts = opts or {}
  local s = Presence.session()
  local items = {}
  local function again() game.stack:push(CoopMenu.new(game, opts)) end

  if not hasTownMap(game) then
    items[#items + 1] = { label = Strings("TOWN MAP"), onSelect = function()
      again()
      Screens.push(game, "TownMap")
    end }
  end
  items[#items + 1] = { label = Strings("LEAVE SESSION"), onSelect = function()
    local TextBox = require("src.render.TextBox")
    local ask = s and s.kind == "host" and Strings("END THE SESSION\nFOR EVERYONE?")
      or Strings("LEAVE THE CO-OP\nSESSION?")
    game.stack:push(TextBox.new(game, ask, nil, {
      defaultNo = true,
      choice = function(yes)
        local live = Presence.session()
        if yes and live then CoopMenu.leave(live) end
      end,
    }))
  end }
  items[#items + 1] = { label = Strings("CANCEL"), onSelect = function()
    if opts.onCancel then opts.onCancel() end
  end }

  local r = CoopMenu.ROWS
  local menu = Menu.new(game, items, { tx = r.tx, ty = r.ty, tw = r.tw, th = r.th,
                                       onCancel = opts.onCancel })
  menu.isMenu = true
  menu.coopMenu = true
  local address = s and s.kind == "host" and hostAddress() or nil
  local baseDraw = menu.draw
  menu.draw = function(self)
    local live = Presence.session()
    local b = CoopMenu.BOX
    Font.drawBox(b.tx, b.ty, b.tw, b.th)
    if live then
      love.graphics.setColor(0, 0, 0, 1)
      for i, line in ipairs(CoopMenu.lines(game, live, address)) do
        Font.draw(line, (b.tx + 1) * 8, (b.ty + i) * 8)
      end
      love.graphics.setColor(1, 1, 1, 1)
    end
    baseDraw(self)
  end
  -- the session ended under the menu: close it
  local baseUpdate = menu.update
  menu.update = function(self, dt)
    if not Presence.session() then
      if game.stack:top() == self then game.stack:pop() end
      return
    end
    baseUpdate(self, dt)
  end
  return menu
end

function CoopMenu.push(game, opts)
  local m = CoopMenu.new(game, opts)
  game.stack:push(m)
  return m
end

-- the START menu's CO-OP row (StartMenu's marked hook, after OPTION)
function CoopMenu.startRow(game, items, reopen)
  if not Presence.session() then return end
  items[#items + 1] = { label = Strings("CO-OP"), onSelect = function()
    CoopMenu.push(game, { onCancel = reopen })
  end }
end

-- SELECT on the map (OverworldState:handleInput's marked hook): true when
-- the CO-OP menu opened
function CoopMenu.select(game)
  if not Presence.session() then return false end
  require("src.core.Sound").play(game.data, "Start_Menu")
  CoopMenu.push(game)
  return true
end

return CoopMenu
