-- What a co-op device remembers (#10, design A1.9) and its session logs
-- (A1.14): a device id, a player per host, seat and campaign, a host log
-- that records joins, refusals and its end, and log rotation (30 files,
-- 256 MB).  ROM-free, in-memory stores.
--   luajit tests/coop/session_identity_log_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Json = require("src.link.Json")
local Identity = require("src.coop.session.Identity")
local SessionLog = require("src.coop.session.SessionLog")
local Transport = require("src.coop.session.Transport")
local Host = require("src.coop.session.Host")
local Client = require("src.coop.session.Client")

local CAMPAIGN = "c0000000000000001"
local SHA = ("ab"):rep(20)

-- identity --------------------------------------------------------------
local stored
local store = { read = function() return stored end,
                write = function(text) stored = text end }
local id = Identity.load(store, function(n) return ("a"):rep(n) end)
eq(id.device, ("a"):rep(16), "a new device gets a random id")
check(stored ~= nil, "and keeps it")
id:remember("192.168.1.20:24680", 1, CAMPAIGN, "p00000001")
id:remember("192.168.1.20:24680", 2, CAMPAIGN, "p00000002")
id:remember("loopback", 1, CAMPAIGN, "p00000003")
local again = Identity.load(store)
eq(again.device, id.device, "the device id survives a restart")
eq(again:known("192.168.1.20:24680", 1)[CAMPAIGN], "p00000001", "seat 1's player per host")
eq(again:known("192.168.1.20:24680", 2)[CAMPAIGN], "p00000002", "seat 2 has its own player")
eq(again:known("loopback", 1)[CAMPAIGN], "p00000003", "another host is apart")
eq(next(again:known("10.0.0.1:24680", 1)), nil, "an unknown host knows nobody")

stored = '{"device":"ZZ","hosts":{"h":{"1":{"nope":"p1","' .. CAMPAIGN .. '":"x"}}}}'
local broken = Identity.load(store, function(n) return ("b"):rep(n) end)
eq(broken.device, ("b"):rep(16), "a malformed device id is replaced")
eq(next(broken:known("h", 1)), nil, "malformed remembered entries are skipped")
stored = "not json"
eq(#Identity.load(store).device, 16, "an unreadable file starts over")

-- live check #10: two games started together drew the same device id from
-- the unseeded math.random; ids now come from the system's random source
do
  local Random = require("src.coop.session.Random")
  local seen, clash = {}, false
  for _ = 1, 200 do
    local h = Random.hex(16)
    if seen[h] or not h:match("^%x+$") or #h ~= 16 then clash = true end
    seen[h] = true
  end
  check(not clash, "random ids are 16 hex digits and do not repeat")
  local cmd = ((arg and arg[-1]) or "luajit") .. ' -e \'package.path="./?.lua;"..package.path; ' ..
    'io.write(require("src.coop.session.Random").hex(16))\''
  local a = io.popen(cmd):read("*a")
  local b = io.popen(cmd):read("*a")
  check(#a == 16 and a ~= b, "two fresh processes draw two device ids (" .. a .. ", " .. b .. ")")
end

-- session log -----------------------------------------------------------
local files = {}
local function memFs()
  return {
    mkdir = function() end,
    list = function(dir)
      local out = {}
      for path in pairs(files) do
        local name = path:match("^" .. dir:gsub("%p", "%%%0") .. "/(.+)$")
        if name then out[#out + 1] = name end
      end
      return out
    end,
    size = function(path) return files[path] and #files[path] or 0 end,
    remove = function(path) files[path] = nil end,
    open = function(path)
      files[path] = ""
      return { write = function(text) files[path] = files[path] .. text end,
               flush = function() end, close = function() end }
    end,
  }
end

local log = SessionLog.open({ fs = memFs(), device = "abc", name = "HOST", seat = 1,
                              stamp = "20261013-120000", clock = function() return 42 end })
local host = Host.new({ campaign = { id = CAMPAIGN, title = "LOG" },
                        cartridge = { game = "red", sha1 = SHA }, log = log })
local hub = host:serve(Transport.loopback())
local c = Client.new(hub:dial(), { name = "RED", game = "red", sha1 = SHA, device = "d1" })
c:join()
for _ = 1, 3 do host:update(); c:update() end
c:move("PALLET_TOWN", 1, 1, "up", true)
c.conn:send({ type = "move", seq = 1, map = "PALLET_TOWN", x = 1, y = 2,
              facing = "up", warp = false })
c.conn:send({ type = "move", seq = "x" })
for _ = 1, 3 do host:update(); c:update() end
host:shutdown("host_quit")
for _ = 1, 3 do host:update(); c:update() end
eq(host.status, "ended", "the host ended")

local text = files["coop/logs/session-20261013-120000-abc.jsonl"]
check(text ~= nil, "the log file is named by time and device")
local kinds, lines = {}, {}
for line in (text or ""):gmatch("[^\n]+") do
  local entry = Json.decode(line)
  lines[#lines + 1] = entry
  kinds[#kinds + 1] = entry and entry.kind
end
local all = table.concat(kinds, ",")
eq(kinds[1], "start", "the host logs its start state first")
eq(kinds[#kinds], "end", "and its end state last")
for _, k in ipairs({ "joined", "new_player", "message", "rejected", "dropped", "shutdown", "left" }) do
  check(all:find(k, 1, true) ~= nil, "the log has " .. k .. " lines")
end
local first = lines[1]
eq(first.t, 42, "a line has the unix time in ms")
eq(first.device, "abc", "a line has the device")
eq(first.src, "host", "a line has the source")
check(first.data and first.data.campaign and first.data.campaign.id == CAMPAIGN,
  "the start line names the campaign")
for _, entry in ipairs(lines) do
  if entry.kind == "rejected" then
    eq(entry.data.reason, "duplicate", "the refusal is logged with its reason")
  end
end

-- rotation: the newest 30 files, at most the byte cap
files = {}
for i = 1, 35 do files[("coop/logs/session-2026%04d-x.jsonl"):format(i)] = "x" end
files["coop/logs/other.txt"] = "keep"
SessionLog.open({ fs = memFs(), device = "abc", stamp = "20270101-000000" })
local n = 0
for path in pairs(files) do if path:match("session%-") then n = n + 1 end end
eq(n, 30, "30 session files remain with the new one")
check(files["coop/logs/session-20260001-x.jsonl"] == nil, "the oldest go first")
check(files["coop/logs/session-20260035-x.jsonl"] ~= nil, "the newest stay")
eq(files["coop/logs/other.txt"], "keep", "other files are left alone")

files = {}
for i = 1, 5 do files[("coop/logs/session-2026%04d-x.jsonl"):format(i)] = ("y"):rep(100) end
SessionLog.open({ fs = memFs(), device = "abc", stamp = "20270101-000000", maxBytes = 250 })
n = 0
for path in pairs(files) do if path:match("session%-2026") then n = n + 1 end end
eq(n, 2, "old files go until the byte cap holds")

local capped = SessionLog.open({ fs = memFs(), device = "cap", stamp = "s", maxBytes = 200 })
for i = 1, 10 do capped:write("host", "k", { i = i }) end
check(#files["coop/logs/session-s-cap.jsonl"] <= 200, "one file stays under the cap")

T.finish()
