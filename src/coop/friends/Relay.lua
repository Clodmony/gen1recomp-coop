-- The link cable of a friend battle (#23, decision G31): a transport for
-- upstream's link session (src/link/Session.lua) that rides the co-op
-- session instead of a socket of its own.  What the window's link battle
-- sends goes to the host as numbered `pair_msg`s, which the host passes on
-- to the partner (src/coop/friends/HostFriends.lua); what the partner sent
-- comes back the same way, in order and once each.
--
--   local relay = Relay.new(pairId, function() return client end)
--   local net = require("src.link.Session").new(relay, { role = "host", kind = "link" })
--   relay:inject({ type = "bye" })  -- a message as if the partner sent it
--
-- A dropped link loses nothing: on a new link (`client` changed after a
-- redial) the relay sends everything again from the first message, and the
-- host keeps only the ones it has not had; the host sends the partner's
-- again from the first, and the relay keeps only the ones it has not had.
-- Meanwhile the link battle simply waits for the partner's turn (A12.4).
--
-- The relay holds a copy of each message as it was sent: the link battle
-- changes a message after sending it (LinkBattle's submit).

local Protocol = require("src.coop.session.Protocol")

local Relay = {}
Relay.__index = Relay

-- clientFn: the session's client now (it changes after a redial), or nil
function Relay.new(pairId, clientFn)
  return setmetatable({
    pair = pairId, clientFn = clientFn,
    -- the fields upstream's link session reads (src/link/Session.lua)
    paired = true, closed = false, error = nil,
    out = {}, sentTo = nil, sentN = 0, -- this window's messages
    readFrom = nil, read = 0, got = 0, inbox = {}, -- the partner's
    forfeited = false,
  }, Relay)
end

local function joined(self)
  local c = self.clientFn and self.clientFn()
  if c and c.status == "joined" then return c end
  return nil
end

function Relay:_flush()
  local c = joined(self)
  if not c then return end
  if self.sentTo ~= c then self.sentTo, self.sentN = c, 0 end -- a new link: all again
  while self.sentN < #self.out do
    local n = self.sentN + 1
    if not c:pairMsg(self.pair, n, self.out[n]) then return end
    self.sentN = n
  end
end

function Relay:send(msg)
  if self.closed then return false end
  local copy = Protocol.plain(msg)
  if type(copy) ~= "table" then return false end
  self.out[#self.out + 1] = copy
  self:_flush()
  return true
end

-- the partner's messages this relay has not had; a forfeit (RUN, A12.3)
-- is taken out and noted, so the battle can say it in the co-op's words
function Relay:update()
  self:_flush()
  local c = joined(self)
  if not c then return end
  if self.readFrom ~= c then self.readFrom, self.read = c, 0 end
  local r = c.relay[self.pair]
  if not r then return end
  while self.read < #r.list do
    self.read = self.read + 1
    if self.read > self.got then
      self.got = self.read
      local msg = r.list[self.read]
      if msg.type == "forfeit" then
        self.forfeited = true
      else
        self.inbox[#self.inbox + 1] = msg
      end
    end
  end
end

function Relay:poll()
  local out = self.inbox
  self.inbox = {}
  return out
end

function Relay:inject(msg)
  self.inbox[#self.inbox + 1] = msg
end

function Relay:close()
  self.closed = true
end

return Relay
