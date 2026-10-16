-- A window's side of the shared world (#14, design A5.2 to A5.7, A5.17):
-- what this player's game sends of the campaign's story and what it takes
-- from it.  The window is game-agnostic: each frame it is handed the save
-- table, whether the player is held, the map it stands on and how to reload
-- or refresh that map (src/coop/game/SharedWorld.lua builds that frame from
-- the running game; the tests build it by hand).
--
--   local w = Window.new(client)
--   every frame: w:update({ save = save, busy = why or nil, map = "PALLET_TOWN",
--                           still = true,  -- not between two cells
--                           reload = function(map) … end,
--                           refresh = function(map) … end,
--                           gifted = function(gift, where) … end,   -- optional
--                           traded = function(row, gave) … end })  -- optional
--   w:flush(save)   -- START > SAVE: the scene so far goes out now
--
-- Rules:
--   * Rest points (A5.4, D72): a frame where nothing holds the player.  It
--     counts after REST_FRAMES such frames in a row.  Away from a rest
--     point the window sends and takes nothing (A5.5); a closed window or a
--     lost link sends nothing, so the host keeps the last resting state.
--     A step the player walks of their own does not hold them (the
--     cartridge opens START at the next cell), but a reload or refresh
--     waits for a frame between two cells.
--   * Opening (A5.2, A5.19): the first rest point takes the campaign's
--     story instead of pushing the window's own; only a campaign with no
--     story yet takes the window's entries (its first window starts it).
--   * Patches, not copies (A5.2): the window sends the difference between
--     what it last sent and its current entries, and applies the difference
--     between the host's story it last took and the newest.
--   * Unconfirmed patches (A5.3, D51): an entry this window sent in a patch
--     the host has not reported applied is left out of what it takes, so an
--     older story never rewinds its own change.
--   * The map it stands on (A5.6, A5.7, A5.17): this engine keeps no
--     per-map script steps (Ownership.lua), so a partner's entry lands at
--     once; a pulled object hide or show on the standing map refreshes that
--     map, a pulled flag the map is stamped from owes it a reload, and a
--     Victory Road switch cleared by a partner waits while this window
--     still stands on that floor.
--   * Story items (#16, design A6, Items.lua): the bag and money are noted
--     at every rest point; a patch that sets story entries carries the
--     bag's change since the last rest point (and whether money went down),
--     so the host can share it.  The items the host owes this player
--     (client.gifts) land at a rest point, each once: the save keeps the
--     last one taken (`coopGifts`), so a gift heard again after a rejoin
--     is skipped unless the world it landed in was never saved.  A gift
--     taken is not this window's own change.
--   * Trades (#63, Trade.lua): a trade the host committed that this
--     window's save does not show yet (its link dropped before the yes,
--     or it came back without its trade screen) lands at a rest point:
--     the row it gave leaves, the row it gets takes its place with its
--     uid, the Pokédex marks it, and `traded(row, gave)` lets the game
--     say so and run a trade evolution.  One the save shows already
--     changes nothing.
--   * Holdings (#17, design A7.2, A7.4, A7.5, G25): the party, current box,
--     Pokédex, bag and money are looked at on the first rest frame after
--     the player was held and every HOLDINGS_EVERY rest frames after (a
--     poisoned team loses HP while walking), the PC only on that first
--     frame (it changes only while the player is held: a PC, a catch).
--     When they changed, the world goes to the host without the PC, the PC
--     with it when it changed or with the first copy on a link.  The window is the only
--     writer of its player's holdings (G24 writes battle results here), so
--     the host takes each copy as it comes.  The first rest point only
--     notes them: the window opened what the host has.  START > SAVE sends
--     the world whole (flush), so nothing is sent again.  The uids the host
--     gives rows (client.uids) are stamped at a rest point on the row that
--     still stands there with the same fingerprint.
--   * The opening (#22, design A4.4 to A4.6, A4.9): a window whose world
--     has no starter yet plays the opening on a private story: it sends
--     and takes nothing of the campaign's, lands no gifts and sends no
--     holdings, so nothing of it reaches the host.  The host hears that it
--     plays the opening, and the rival's name it gave in Oak's speech
--     (`named`).  The opening ends at a rest point once the player has a
--     starter and stands outside Oak's lab; the window then opens as a
--     late one (the campaign's story over its entries, or its entries
--     seeding a campaign with no story yet, A4.7), tells the host the
--     starter it chose, sends its world, and takes the campaign's rival
--     name from then on.
--   * A start (#57, design A4.1 to A4.3, G28): a world the launcher
--     started (in Pallet Town, or brought from a solo save) carries
--     `coopStart`.  At its first rest point the window takes the mark off
--     and sends the world whole (`start`); it waits, sending and taking
--     nothing, until the host keeps it, then opens as a late window (the
--     campaign's story over its entries: its own when it seeded the
--     campaign).  A start sent again on a new link that the host refuses
--     as `returning` went through on the old one.  Any other refusal
--     leaves the window closed: it sends nothing, so the host's world for
--     this player stays as it was (A4.3).

local SaveSerializer = require("src.core.SaveSerializer")
local Ownership = require("src.coop.campaign.Ownership")
local Items = require("src.coop.campaign.Items")
local World = require("src.coop.campaign.World")
local Campaign = require("src.coop.campaign.Campaign")
local Protocol = require("src.coop.session.Protocol")
local Trade = require("src.coop.campaign.Trade")

local Window = {}
Window.__index = Window

Window.REST_FRAMES = 3
Window.HOLDINGS_EVERY = 60 -- rest frames between two looks at the holdings
Window.LAB = "OAKS_LAB" -- the opening ends outside it (#22)

function Window.new(client)
  return setmetatable({
    client = client,
    rest = 0,        -- frames in a row with nothing holding the player
    sent = nil,      -- the entries as last sent (nil: not opened yet)
    seen = {},       -- the host's story as last taken
    unconfirmed = {}, -- seq -> { path = true } for patches not yet applied
    patches = 0, taken = 0, reloads = 0, -- counters for the log and the tests
    owed = nil,      -- { map, reload } a reload or refresh owed to that map
    bag = nil,       -- the bag at the last rest point (Items.bag)
    money = nil,     -- the money then
    gifts = 0,       -- gifts landed (a counter for the log and the tests)
    trades = 0,      -- owed trades landed (#63)
    held = nil,      -- the holdings as last sent or noted (#17), as text
    heldBoxes = nil, -- the PC then, as text
    boxesTo = nil,   -- the client the PC last went to
    holdings = 0,    -- holdings sent (a counter for the tests)
    opening = nil,   -- #22: true while the player plays the opening, false
                     -- once past it (nil: not looked at yet)
    naming = nil,    -- a rival's name given in Oak's speech, not sent yet
    told = nil,      -- the client the opening's state last went to
    finished = nil,  -- this window finished the opening
    starting = nil,  -- #57: how this world started ("pallet", "save") until the host kept it
    startTo = nil,   -- the client the start last went to, and its seq
    startSeq = nil,
    resent = nil,    -- the start went out again on a new link
    refused = nil,   -- why the host refused the start: the window stays closed
  }, Window)
end

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

-- true when an unconfirmed patch of this window touched `path`
function Window:_mine(path)
  for _, paths in pairs(self.unconfirmed) do
    if paths[path] then return true end
  end
  return false
end

function Window:_ready()
  local c = self.client
  return c ~= nil and c.status == "joined" and c.story ~= nil
end

-- the patches the host has applied are confirmed (A5.3)
function Window:_confirm()
  local applied = self.client.storyApplied or 0
  for seq in pairs(self.unconfirmed) do
    if seq <= applied then self.unconfirmed[seq] = nil end
  end
end

-- the bag and money as they stand: the next change is measured from here
function Window:_note(save)
  self.bag = Items.bag(save)
  self.money = save.money
end

-- the bag's change since the last rest point, or nil (#16)
function Window:_bagChange(save)
  if not self.bag then return nil end
  local gained, lost = Items.delta(self.bag, Items.bag(save))
  if next(gained) == nil and next(lost) == nil then return nil end
  local spent = type(save.money) == "number" and type(self.money) == "number"
    and save.money < self.money
  return { gained = gained, lost = lost, spent = spent }
end

-- this window's change since the last patch goes out; returns its seq
function Window:_send(save)
  local cur = Ownership.view(save)
  local set, unset, n = Ownership.diff(self.sent, cur)
  if n == 0 then return nil end
  local bag = next(set) ~= nil and self:_bagChange(save) or nil
  local seq = self.client:sendPatch(set, unset, bag)
  if not seq then return nil end
  local paths = {}
  for path in pairs(set) do paths[path] = true end
  for _, path in ipairs(unset) do paths[path] = true end
  self.unconfirmed[seq] = paths
  self.sent = cur
  self.patches = self.patches + 1
  return seq
end

-- The first rest point: the campaign's story over the window's entries
-- (A5.2: a window opened late takes the campaign).  A campaign without a
-- story yet keeps the window's entries, which its first patch sends.
function Window:_open(f)
  local story = self.client.story
  if next(story) == nil then
    self.sent = {}
    self.seen = {}
    return
  end
  local before = Ownership.view(f.save)
  Ownership.overlay(f.save, story)
  self.sent = Ownership.view(f.save)
  self.seen = copy(story)
  local _, _, n = Ownership.diff(before, self.sent)
  self.taken = self.taken + n
  if n > 0 then self:_owe(f.map, true) end
end

-- a reload (or a lighter refresh) owed to the map the window stands on
function Window:_owe(map, reload)
  if not map then return end
  if self.owed and self.owed.map == map then
    self.owed.reload = self.owed.reload or reload
  else
    self.owed = { map = map, reload = reload }
  end
end

-- what is owed, once the player stands between two cells on that map; a
-- map left since loaded fresh and owes nothing
function Window:_settle(f)
  local owed = self.owed
  if not owed then return end
  if f.map ~= owed.map then self.owed = nil; return end
  if f.still == false then return end
  self.owed = nil
  self.reloads = self.reloads + 1
  if owed.reload and f.reload then
    f.reload(owed.map)
  elseif f.refresh then
    f.refresh(owed.map)
  elseif f.reload then
    f.reload(owed.map)
  end
end

-- the host's changes since the last one taken, by the rules above
function Window:_take(f)
  local story = self.client.story
  local changed = {}
  for path, v in pairs(story) do
    if self.seen[path] ~= v then changed[path] = true end
  end
  for path in pairs(self.seen) do
    if story[path] == nil then changed[path] = true end
  end
  for path in pairs(changed) do
    local value = story[path]
    local wait = self:_mine(path)
      or (value == nil and f.map ~= nil and Ownership.keepOnFloor(path) == f.map)
    if not wait then
      Ownership.write(f.save, path, value)
      self.seen[path] = value
      self.sent[path] = value
      self.taken = self.taken + 1
      if f.map ~= nil and Ownership.reloadFor(path) == f.map then
        self:_owe(f.map, true)
      elseif f.map ~= nil and Ownership.isObject(path) and Ownership.mapOf(path) == f.map then
        self:_owe(f.map, false)
      end
    end
  end
end

-- the items the host owes this player, each once (#16, design A6.2, A6.6)
function Window:_gifts(f)
  local list = self.client.gifts
  if type(list) ~= "table" or #list == 0 then return end
  local save = f.save
  for _, g in ipairs(list) do
    if g.seq > (save.coopGifts or 0) then
      local where
      if g.qty > 0 then
        where = Items.give(save, g.item, g.qty, g.once)
      else
        where = Items.take(save, g.item, -g.qty) > 0 and "taken" or nil
      end
      save.coopGifts = g.seq
      self.gifts = self.gifts + 1
      if f.gifted then f.gifted(g, where) end
    end
  end
  self.client.gifts = {}
end

-- the holdings a rest point looks at, as text (#17)
local function holdingsKey(save)
  return SaveSerializer.encode({ party = save.party or {}, currentBox = save.currentBox,
                                 pokedex = save.pokedex, inventory = save.inventory,
                                 money = save.money })
end

local function boxesText(save)
  return SaveSerializer.encode(save.boxes or {})
end

-- the holdings as they stand were sent (or are the host's already)
function Window:_noteHoldings(save)
  self.held, self.heldBoxes = holdingsKey(save), boxesText(save)
  self.boxesTo = self.client
end

-- The holdings go out when they changed (#17, design A7.2); `pc` looks at
-- the PC too.  Returns the seq, or nil when nothing went.
function Window:_holdings(save, pc)
  if not self.held then
    -- noted, not sent: the PC still goes with the first copy on this link
    self.held, self.heldBoxes = holdingsKey(save), boxesText(save)
    return nil
  end
  local key = holdingsKey(save)
  local boxes = pc and boxesText(save) or self.heldBoxes
  if key == self.held and boxes == self.heldBoxes then return nil end
  local rest, pcText = World.split(save)
  local withBoxes = boxes ~= self.heldBoxes or self.boxesTo ~= self.client
  local seq = self.client:sendHoldings(rest, withBoxes and pcText or nil)
  if not seq then return nil end
  self.held, self.heldBoxes = key, boxes
  if withBoxes then self.boxesTo = self.client end
  self.holdings = self.holdings + 1
  return seq
end

-- the trades the host owes this player (#63): each lands once
function Window:_trades(f)
  local list = self.client.trades
  if type(list) ~= "table" or #list == 0 then return end
  self.client.trades = {}
  -- what the window had before is the host's already (a first rest point
  -- only notes it); the trade landed goes out at once
  if not self.held then self.held, self.heldBoxes = holdingsKey(f.save), boxesText(f.save) end
  local landed = false
  for _, t in ipairs(list) do
    local give, get = Trade.decodeTeam(t.give), Trade.decodeTeam(t.get)
    give, get = give and give[1], get and get[1]
    local how, _, _, row
    if give and get then how, _, _, row = Trade.swap(f.save, give, get) end
    if how == "swapped" then
      Trade.mark(f.save, row.species)
      self.trades = self.trades + 1
      landed = true
      if f.traded then f.traded(row, give) end
    end
  end
  if landed then self:_holdings(f.save, true) end
end

-- the uids the host gave this window's rows (#17, design A7.3); the
-- holdings stay noted as sent when only the uids moved
function Window:_uids(save)
  local list = self.client.uids
  if type(list) ~= "table" or #list == 0 then return end
  self.client.uids = {}
  local same = self.held ~= nil and holdingsKey(save) == self.held
  local sameBoxes = self.heldBoxes ~= nil and boxesText(save) == self.heldBoxes
  local inBox = false
  for _, u in ipairs(list) do
    local row = World.at(save, u.box, u.slot)
    if type(row) == "table" and Campaign.fingerprint(row) == u.fp then
      row[Campaign.UID_FIELD] = u.uid
      inBox = inBox or u.box > 0
    end
  end
  if same then self.held = holdingsKey(save) end
  if sameBoxes and inBox then self.heldBoxes = boxesText(save) end
end

-- a battle the world opens: the holdings so far go out first (#17)
function Window:flushHoldings(save)
  if not self:_ready() or not self.sent or type(save) ~= "table" then return nil end
  if self.opening then return nil end
  return self:_holdings(save, true)
end

function Window:update(f)
  if not self:_ready() or type(f.save) ~= "table" then return end
  if self.refused then return end
  self:_confirm()
  if self:_start(f) then
    self.rest = f.busy and 0 or self.rest + 1
    return
  end
  if self:_opening(f) then
    self.rest = f.busy and 0 or self.rest + 1
    return
  end
  if f.busy then
    self.rest = 0
    return
  end
  self.rest = self.rest + 1
  if self.rest < Window.REST_FRAMES then return end
  if not self.sent then
    self:_open(f)
  else
    self:_send(f.save)
    self:_take(f)
  end
  self:_rival(f.save)
  self:_gifts(f)
  self:_trades(f)
  self:_note(f.save)
  self:_uids(f.save)
  local since = self.rest - Window.REST_FRAMES
  if since % Window.HOLDINGS_EVERY == 0 then self:_holdings(f.save, since == 0) end
  self:_settle(f)
end

-- the starter a save chose (Red and Blue's three), or nil
local function chosen(save)
  local flags = type(save.flags) == "table" and save.flags or {}
  for starter in pairs(Protocol.STARTERS) do
    if flags["EVENT_CHOSE_" .. starter] then return starter end
  end
  return nil
end

local function hasStarter(save)
  return type(save.flags) == "table" and save.flags.EVENT_GOT_STARTER == true
end

-- The rival's name given in Oak's speech (#22, design A4.5): it goes to
-- the host, which keeps the first one given in the campaign
function Window:named(name)
  self.naming = name
  if self:_ready() and self.client:sendOpening(false, name) then self.naming = nil end
end

-- the campaign's rival's name over the player's own (A4.5)
function Window:_rival(save)
  local state = self.client.state
  local name = state and state.rival
  if name and type(save.player) == "table" and save.player.rival ~= name then
    save.player.rival = name
  end
end

-- One frame of the opening (#22): its first look says whether the world
-- is in it; a rest point outside the lab with a starter ends it.  Returns
-- true while the window plays the opening.
function Window:_opening(f)
  if self.naming and self.client:sendOpening(false, self.naming) then self.naming = nil end
  if self.opening == nil then
    -- the first look waits for a world on screen: the title's (and Oak's
    -- speech's) save is not yet the one CONTINUE or NEW GAME plays
    if f.map == nil then return true end
    self.opening = not hasStarter(f.save)
  end
  -- each link tells the host once: a host that lost this player's world
  -- marks them in the opening when they come back
  -- (with the starter, when this window finished the opening: a done lost
  -- to a dropped link)
  if self.told ~= self.client
     and self.client:sendOpening(not self.opening, nil, self.finished and chosen(f.save) or nil) then
    self.told = self.client
  end
  if not self.opening then return false end
  if f.busy or self.rest + 1 < Window.REST_FRAMES then return true end
  if not (hasStarter(f.save) and f.map ~= nil and f.map ~= Window.LAB) then return true end
  self.opening, self.finished = false, true
  self.client:sendOpening(true, nil, chosen(f.save))
  self.told = self.client
  -- the campaign's story over the private one, as a late window opens
  self.sent = nil
  self:_open(f)
  self:_rival(f.save)
  -- the world goes to the host now, PC and all
  self.held, self.heldBoxes = "", ""
  self:_holdings(f.save, true)
  return false
end

-- the host's answer to this window's start: "ok", a refusal, or nil
function Window:_startAnswer()
  local c = self.client
  if not self.startSeq or self.startTo ~= c then return nil end
  if c.started == self.startSeq then return "ok" end
  for _, r in ipairs(c.rejections) do
    if r.seq == self.startSeq then
      -- the host had the world from the start sent on the old link
      if r.reason == "returning" and self.resent then return "ok" end
      return r.reason
    end
  end
  return nil
end

-- One frame of a start (#57): its first rest point sends the world the
-- launcher started, whole; the window waits for the host's answer.
-- Returns true while it waits.
function Window:_start(f)
  local save = f.save
  if not self.starting then
    if self.sent or type(save.coopStart) ~= "string" then return false end
    self.starting = save.coopStart
    save.coopStart = nil
  end
  local answer = self:_startAnswer()
  if answer == "ok" then
    self.starting = nil
    -- a world with a starter plays no opening; the host knows
    self.opening, self.told = false, self.client
    return false
  elseif answer then
    self.starting, self.refused = nil, answer
    return true
  end
  if f.busy or self.rest + 1 < Window.REST_FRAMES then return true end
  local c = self.client
  if self.startTo ~= c then
    local seq = c:sendStart(self.starting, World.encode(save))
    if seq then
      if self.startTo then self.resent = true end
      self.startTo, self.startSeq = c, seq
    end
  end
  return true
end

-- The game reopened its world from the host (#55, design A10.7: the Hall
-- of Fame's continue, a reset): the window opens again as a late one at
-- its next rest point, and the holdings it opened are the host's.
function Window:reopen()
  self.rest, self.sent, self.seen, self.unconfirmed = 0, nil, {}, {}
  self.owed, self.bag, self.money = nil, nil, nil
  self.held, self.heldBoxes = nil, nil
  self.opening = nil
end

-- true while the player plays the opening (#22)
function Window:inOpening()
  return self.opening == true
end

-- true once this window has a rest point behind it
function Window:resting()
  return self.rest >= Window.REST_FRAMES
end

-- START > SAVE sends the scene so far (A5.5), wherever the player stands
function Window:flush(save)
  if not self:_ready() or not self.sent or type(save) ~= "table" then return nil end
  if self.opening then return nil end
  self:_confirm()
  local seq = self:_send(save)
  self:_note(save)
  self:_noteHoldings(save)
  return seq
end

return Window
