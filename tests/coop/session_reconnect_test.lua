-- A dropped link in a running game (#20, design A11.9 to A11.11), ROM-free:
-- a hosting session in-process and a joining session that dials its
-- loopback hub.  Covered: a drop starts reconnecting ("lost"), a new link
-- every 2 s as the same player, the world's window kept, the first position
-- a warp, "back"; a host that stays away for two minutes ends it, shown
-- over the world for 3 s before the launcher; a game back from a long
-- pause dials afresh at once.
--   luajit tests/coop/session_reconnect_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Session = require("src.coop.session.Session")
local Identity = require("src.coop.session.Identity")

local SHA = ("ab"):rep(20)
local t = 0
local function memoryStore()
  local text
  return { read = function() return text end, write = function(x) text = x end }
end

local host = Session.startHost({
  campaign = { id = "c00ff", title = "T" }, cartridge = { game = "red", sha1 = SHA },
  name = "HOST", listen = false, beacon = false, log = false, campaignFs = false,
  identity = Identity.load(memoryStore()), clock = function() return t end,
})
local hostSession = host
Session.current = nil -- this test drives both sessions by hand

local dials = 0
local lastConn
local guest = Session.startDial({
  address = "loop", name = "BLUE", cartridge = { game = "red", sha1 = SHA },
  log = false, identity = Identity.load(memoryStore()), clock = function() return t end,
  dial = function()
    dials = dials + 1
    lastConn = hostSession.hub:dial()
    return lastConn
  end,
})
Session.current = nil

local function frame(n, game)
  for _ = 1, n or 1 do
    t = t + 1 / 60
    hostSession:update(1 / 60, nil)
    local r = guest:update(1 / 60, game)
    if r then return r end
  end
end

frame(3)
eq(guest.status, "probed", "the guest probed the host")
guest:join()
frame(3, {})
eq(guest.status, "joined", "and joined in a running game")
local player = guest.client.player
local window = guest.window
check(window ~= nil, "the world's window is open")

-- the link drops ----------------------------------------------------------------
lastConn:close()
frame(1, {})
eq(guest.status, "reconnecting", "a dropped link in a running game reconnects (A11.9)")
eq(guest.linkNote, "lost", "and says so over the world")
guest.linkNote = nil
local before = dials
frame(30, {})
eq(dials, before, "not before two seconds")
frame(120, {})
check(dials > before, "a new link after two seconds")
frame(5, {})
eq(guest.status, "joined", "back in")
eq(guest.client.player, player, "as the same player")
eq(guest.linkNote, "back", "and says so")
check(guest.window == window, "the world's window is the same, its state kept")
eq(guest.window.client, guest.client, "on the new link")
eq(guest.resync, true, "the first position after a reconnect counts as a warp")
check(hostSession.host:player(player).connected, "the host has the player back")

-- back from a long pause: a fresh link at once (A11.10) -------------------------------
Session.current = guest
Session.pause()
t = t + Session.RESUME_AFTER + 1
before = dials
Session.resume()
Session.current = nil
frame(2, {})
check(dials > before, "a game back from a pause over 3 s dials afresh at once")
frame(5, {})
eq(guest.status, "joined", "and is back in")
Session.current = guest
Session.pause()
t = t + 1
before = dials
Session.resume()
Session.current = nil
frame(2, {})
eq(dials, before, "a short pause keeps its link")

-- a host gone for good: two minutes, then the end over the world, then the launcher
local hostWas = hostSession.hub.dial
hostSession.hub.dial = function()
  local c = hostWas(hostSession.hub)
  c:close()
  return c
end
lastConn:close()
frame(2, {})
eq(guest.status, "reconnecting", "dropped again")
local result = frame(60 * (Session.REDIAL_FOR + 1), {})
eq(result, nil, "not to the launcher at once")
eq(guest.linkNote, "ended", "after two minutes the end shows over the world (A11.11)")
result = frame(60 * Session.END_SHOW + 2, {})
eq(result, "launcher", "then the launcher")
hostSession.hub.dial = hostWas

T.finish()
