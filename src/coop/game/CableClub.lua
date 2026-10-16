-- The Cable Club in a co-op world (#60, design A12.7 to A12.9, decision
-- G32): the session is the link cable.  A solo game is untouched.
--
--   CableClub.open(game)          -- the receptionist, after her save (marked hook
--                                 -- in OverworldState:cableClubReceptionist)
--   CableClub.settle(save, data)  -- a world continued in a Cable Club room
--                                 -- (marked hook in Game:restoreSave)
--   CableClub.Cable               -- the link transport over the session
--
-- Upstream's Gen 1 Cable Club has no rooms: the receptionist saves and
-- opens its LAN link menu (src/link/LinkState.lua), which pairs two games
-- over a cable of its own and then runs the cartridge's trade screen or
-- link battle.  In a co-op world the receptionist opens the cartridge's
-- own link menu instead (TRADE CENTER / COLOSSEUM / CANCEL, pokered
-- LinkMenu) and the room chosen goes to the host, which finds the player's
-- mate (src/coop/session/HostCable.lua, A12.7).  Once paired, the same
-- LinkState runs adopted (LinkState.newFromSession) over a `Cable`: each
-- link message travels to the mate through the host.  Upstream's Union
-- Room setting only moves the desk (1F or 2F, G6): both reach this.
--
--   * While waiting: "Please wait." (or, when two others already hold the
--     room's cable, "This area is reserved for 2 friends who are linked by
--     cable."); B leaves the room and goes back to the menu.
--   * The trade (A12.7): the screen's party message carries each Pokémon's
--     uid; the host swaps once and hands this window the mate's yes with
--     the uid of the Pokémon received, which the received row then carries
--     (LinkState's marked `onTraded` hook).  This window plays the movie
--     and any trade evolution on its own copy, and its save after the
--     trade (LinkState's own) reaches the host as a real SAVE.  A round the
--     host turns back (no offer within 30 s, no answer within 60 s) starts
--     over at the lists (LinkState:beginRound).
--   * The Colosseum (A12.9): the cartridge's link battle (LinkBattle), the
--     lead's seed, a copy of the mate's team; nothing of it reaches the
--     campaign.
--   * When the screen closes (cancelled, the battle over, the mate gone)
--     this player leaves the room and the menu shows again.
--
-- Partners in a Cable Club room are not drawn (A14.4, Presence.lua): the
-- trade screen names the mate.
--
-- The continue position (A12.8): a world saved in the TRADE CENTER or the
-- COLOSSEUM (a cartridge's save after a link trade; neither room has a way
-- out but a reset) opens at the counter of the Pokémon Center the room was
-- reached from, the town of its last outdoor map, where upstream already
-- puts a save made in its added rooms (UnionSafety: before the nurse,
-- facing up).

local Font = require("src.render.Font")
local RomText = require("src.core.RomText")
local Strings = require("src.core.Strings")
local LinkProtocol = require("src.link.Protocol")

local CableClub = {}

CableClub.ROOMS = { TRADE_CENTER = true, COLOSSEUM = true }
-- pokered LinkMenu: a box at (5, 5), 13 x 6 inside, the rows from (7, 7)
CableClub.BOX = { tx = 5, ty = 5, tw = 15, th = 8 }
CableClub.MODES = { "trade", "colosseum" }

local function session()
  local Session = package.loaded["src.coop.session.Session"]
  local s = Session and Session.current
  if s and s.client and s.client.status == "joined" then return s end
  return nil
end

local function client()
  local s = session()
  return s and s.client or nil
end

-- the label's line for drawing: no {DONE} markers, every break a new line
local function plain(text)
  return (tostring(text):gsub("%b{}", ""):gsub("[\v\f]", "\n"))
end

-- the link transport --------------------------------------------------------------

-- what tells a party row from its packed copy
local key = require("src.coop.campaign.CableTrade").key

-- the uid of each packed Pokémon of a party message, "" for none
function CableClub.uidsFor(party, mons)
  local rows, used, out = {}, {}, {}
  for i, mon in ipairs(party or {}) do rows[i] = key(LinkProtocol.packMon(mon)) end
  for n, packed in ipairs(mons or {}) do
    local k, uid = key(packed), ""
    for i, rk in ipairs(rows) do
      if not used[i] and rk == k then
        used[i] = true
        uid = type(party[i].coopUid) == "string" and party[i].coopUid or ""
        break
      end
    end
    out[n] = uid
  end
  return out
end

local Cable = {}
Cable.__index = Cable
CableClub.Cable = Cable

-- a cable to `mate` in the trade's round `round`; game: whose party the
-- uids are read from
function Cable.new(game, mate, round)
  return setmetatable({ game = game, mate = mate, round = round, inbox = {},
                        paired = true, closed = false, error = nil, uid = nil,
                        onRound = nil }, Cable)
end

function Cable:send(msg)
  local c = client()
  if self.closed or not c then return nil end
  local uids
  if msg.type == "party" then
    uids = CableClub.uidsFor(self.game.save and self.game.save.party, msg.mons)
  end
  return c:cableLink(self.round, msg, uids)
end

function Cable:update()
  if self.closed then return end
  local c = client()
  local cable = c and c.cable
  if not cable or cable.room == "none" or cable.mate ~= self.mate then
    self.closed = true -- the mate left the room or dropped, or the session went
    return
  end
  if cable.round > self.round then
    self.round = cable.round
    self.inbox = {}
    if self.onRound then self.onRound() end
  end
  for _, m in ipairs(c:takeCableLinks()) do
    if m.round == self.round then
      self.inbox[#self.inbox + 1] = m.link
      if m.uid then self.uid = m.uid end
    end
  end
end

function Cable:poll()
  local out = self.inbox
  self.inbox = {}
  return out
end

function Cable:close()
  self.closed = true
  if self.left then return end
  self.left = true
  local c = client()
  if c then c:cableEnter("none") end
end

-- the menu ------------------------------------------------------------------------

local Club = {}
Club.__index = Club
CableClub.State = Club

function Club.new(game)
  return setmetatable({ game = game, stage = "menu", index = 1 }, Club)
end

-- the receptionist's link menu, after her save: true when a co-op session
-- took the Cable Club
function CableClub.open(game)
  if not session() then return false end
  game.stack:push(Club.new(game))
  return true
end

function Club:close(withText)
  local game = self.game
  if game.stack:top() == self then game.stack:pop() end
  if withText then
    local TextBox = require("src.render.TextBox")
    game.stack:push(TextBox.new(game, RomText(game.data, "_CableClubNPCPleaseComeAgainText",
                                              "Please come\nagain!")))
  end
end

function Club:leaveRoom()
  local c = client()
  if c then c:cableEnter("none") end
  self.stage = "menu"
end

-- the room's cable is ours: the cartridge's trade screen or link battle
function Club:link(cable)
  local LinkState = require("src.link.LinkState")
  local wire = Cable.new(self.game, cable.mate, cable.round)
  local mode = self.room == "trade" and "trade" or "battle"
  local ls = LinkState.newFromSession(self.game, wire, mode, cable.lead == true, {
    onTraded = function(received)
      if received and type(wire.uid) == "string" and wire.uid ~= "" then
        received.coopUid = wire.uid
      end
    end,
  })
  -- a round the host turned back starts over at the lists (A12.7)
  wire.onRound = function()
    if ls.stage == "trade" and not ls.roundBusy then ls:beginRound() end
  end
  self.wire, self.linkState = wire, ls
  self.stage = "linked"
  self.game.stack:push(ls)
end

function Club:update()
  local input = self.game.input
  local c = client()
  if not c then return self:close(false) end
  if self.stage == "linked" then
    -- the screen above closed: out of the room, back to the menu
    if self.wire then self.wire:close() end
    self.wire, self.linkState = nil, nil
    self.stage = "menu"
    return
  end
  if self.stage == "waiting" then
    local cable = c.cable
    if cable and cable.room == self.room and cable.mate then return self:link(cable) end
    if input:wasPressed("b") then self:leaveRoom() end
    return
  end
  if input:wasPressed("up") then
    self.index = (self.index - 2) % 3 + 1
  elseif input:wasPressed("down") then
    self.index = self.index % 3 + 1
  elseif input:wasPressed("b") or (input:wasPressed("a") and self.index == 3) then
    self:close(true)
  elseif input:wasPressed("a") then
    self.room = CableClub.MODES[self.index]
    self.stage = "waiting"
    c.cable = nil -- what the host says from now on
    c:cableEnter(self.room)
  end
end

-- the players besides this one in this player's room, as `state` says
local function others(room)
  local c = client()
  local n = 0
  for _, p in ipairs(c and c.state and c.state.players or {}) do
    if p.id ~= c.player and p.cable == room then n = n + 1 end
  end
  return n
end

local function drawText(text)
  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(0, 0, 0, 1)
  local y = 14
  for line in (plain(text) .. "\n"):gmatch("(.-)\n") do
    if y > 16 then break end
    Font.draw(line, 8, y * 8)
    y = y + 2
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Club:draw()
  if self.stage == "linked" then return end
  local data = self.game.data
  -- the line below first: the menu's bottom edge lies on its top edge
  if self.stage == "waiting" then
    if others(self.room) >= 2 then
      drawText(RomText(data, "_CableClubNPCAreaReservedFor2FriendsLinkedByCableText",
                       "This area is\nreserved for 2\nfriends who are\nlinked by cable."))
    else
      drawText(RomText(data, "_CableClubNPCPleaseWaitText", "Please wait."))
    end
  else
    drawText(RomText(data, "_WhereWouldYouLikeText", "Where would you\nlike to go?"))
  end
  local b = CableClub.BOX
  Font.drawBox(b.tx, b.ty, b.tw, b.th)
  love.graphics.setColor(0, 0, 0, 1)
  local rows = { Strings("TRADE CENTER"), Strings("COLOSSEUM"), Strings("CANCEL") }
  for i, row in ipairs(rows) do
    local y = (b.ty + 2 * i) * 8
    Font.draw(row, (b.tx + 2) * 8, y)
    if i == self.index then
      Font.drawCode(self.stage == "waiting" and 0xEC or 0xED, (b.tx + 1) * 8, y)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- the continue position (A12.8) ---------------------------------------------------

-- a save in a Cable Club room moves to its center's counter; returns the
-- spot, or nil when the save is not in such a room
function CableClub.settle(save, data)
  local p = type(save) == "table" and save.player
  if not (type(p) == "table" and CableClub.ROOMS[p.map] and type(data) == "table") then
    return nil
  end
  local UnionSafety = require("src.world.gen1.UnionSafety")
  -- the center the town of the last outdoor map leads into (wLastMap)
  local last = type(save.lastOutdoor) == "table" and save.lastOutdoor.id
  local town = type(last) == "string" and data.maps and data.maps[last]
  local spot
  for _, w in ipairs(type(town) == "table" and town.warps or {}) do
    spot = UnionSafety.nurseFront(data, w.destMap)
    if spot then break end
  end
  spot = spot or UnionSafety.target(save, data)
  local moved = {}
  for k, v in pairs(p) do moved[k] = v end
  moved.map, moved.x, moved.y, moved.facing = spot.map, spot.x, spot.y, spot.facing or "up"
  save.player = moved
  return spot
end

return CableClub
