-- The team's League run on the host (#55, design A10.6, decision G30).
--
-- The Elite Four is one run for the team (D91): each member's and the
-- Champion's win is the campaign's while a run lasts.  The beaten flags and
-- beaten trainers are story entries (Ownership.lua), so a partner's room
-- reloads with its exit open and a partner arriving later walks through;
-- the League's fights are unique encounters kept done (HostBattles), so a
-- window that walks into one already won hears `beaten` and counts it as
-- won, the Champion included: a late player gets Oak's scene, their own
-- Hall of Fame, the credits and the Continue.  The rooms' script flags
-- (the walk-ins, Lance's door, the started bit, the Champion room's run
-- flag) are each player's, so every window that reaches the Champion's
-- room meets him.
--
-- The run's clear: the cartridge erases a run in the Indigo Plateau lobby
-- (after a whiteout) and after the Hall of Fame.  A window there asks the
-- host (`league`: "lobby" or "inducted"); the host keeps the request and
-- applies it once nothing holds it:
--
--   * a connected player in the League (the four rooms, the Champion's,
--     the Hall of Fame), or a League fight still running;
--   * after the Champion fell, a connected player not yet inducted.
--
-- Applied, it erases the run's story entries and forgets the League's
-- encounters and their victory commits, so the next run fights everyone
-- again; the Champion's beaten flag (EVENT_BEAT_CHAMPION_RIVAL) stays (the
-- Cerulean Cave guard, A10.8).  Costs: the hold lives in host memory
-- (`host.league`), and a disconnected player inside holds nothing.

local League = {}

-- where a connected player holds the run's clear
League.MAPS = { LORELEIS_ROOM = true, BRUNOS_ROOM = true, AGATHAS_ROOM = true,
                LANCES_ROOM = true, CHAMPIONS_ROOM = true, HALL_OF_FAME = true }
-- the rooms whose fights are the run
League.ROOMS = { LORELEIS_ROOM = true, BRUNOS_ROOM = true, AGATHAS_ROOM = true,
                 LANCES_ROOM = true, CHAMPIONS_ROOM = true }
League.CHAMPION = "CHAMPIONS_ROOM"
-- the campaign's flags of a run (data/scripts/story6.lua's E4_RESET_FLAGS
-- the campaign owns); the rest of that list is each player's
League.FLAGS = {
  EVENT_BEAT_LORELEIS_ROOM_TRAINER_0 = true, EVENT_BEAT_BRUNOS_ROOM_TRAINER_0 = true,
  EVENT_BEAT_AGATHAS_ROOM_TRAINER_0 = true, EVENT_BEAT_LANCES_ROOM_TRAINER_0 = true,
  EVENT_BEAT_LANCE = true,
}

-- the room of an encounter (`trainer:<MAP>_obj_<n>`), or nil
function League.roomOf(encounter)
  local map = type(encounter) == "string" and encounter:match("^%l+:(.+)_obj_%d+$")
  return map and League.ROOMS[map] and map or nil
end

-- true for a story entry the run's clear erases
function League.runPath(path)
  if type(path) ~= "string" then return false end
  local flag = path:match("^flags/(.+)$")
  if flag then return League.FLAGS[flag] == true end
  local npc = path:match("^defeatedTrainers/(.+)$")
  local map = npc and npc:match("^(.-)_obj_%d+$")
  return map ~= nil and League.ROOMS[map] == true
end

local function run(host)
  if not host.league then host.league = { want = nil, fell = false, inducted = {} } end
  return host.league
end

-- A battle ended (HostBattles): the Champion's win means he fell.
function League.ended(host, b, result)
  if result == "win" and League.roomOf(b.open.encounter) == League.CHAMPION then
    run(host).fell = true
  end
end

-- Why the run's clear waits now, and for whom; nil when nothing holds it.
function League.held(host)
  local r = run(host)
  for _, p in ipairs(host.players) do
    if p.connected and p.map and League.MAPS[p.map] then return "in_league", p end
  end
  for _, b in pairs(host.battles) do
    if not b.ended and League.roomOf(b.open.encounter) then return "fight" end
  end
  if r.fell then
    for _, p in ipairs(host.players) do
      if p.connected and not r.inducted[p.id] then return "not_inducted", p end
    end
  end
  return nil
end

-- Erase the run: its story entries, the League's encounters and their
-- victory commits; a new run starts afresh.
function League.clear(host)
  local state = host.state
  local paths, forgot = {}, 0
  for path in pairs(state.story) do
    if League.runPath(path) then paths[#paths + 1] = path end
  end
  table.sort(paths)
  for _, path in ipairs(paths) do state.story[path] = nil end
  for enc in pairs(state.encounters) do
    if League.roomOf(enc) then
      state.encounters[enc] = nil
      forgot = forgot + 1
    end
  end
  for id in pairs(state.commits) do
    if League.roomOf(id:match("^victory:(.+)$")) then state.commits[id] = nil end
  end
  if #paths > 0 or forgot > 0 then state:touch() end
  host.league = { want = nil, fell = false, inducted = {} }
  host.dirty = true
  host:_log("league_clear", { entries = #paths, encounters = forgot })
end

-- every frame of the host: a clear asked for goes through once nothing
-- holds it
function League.tick(host)
  local r = host.league
  if r and r.want and not League.held(host) then League.clear(host) end
end

-- A window's `league` (a handler of Host.lua): the lobby asks for the
-- run's clear; an induction asks for it too, after the Champion fell.
function League.message(host, p, msg)
  local r = run(host)
  if msg.event == "inducted" then
    r.fell = true
    r.inducted[p.id] = true
  end
  r.want = r.want or msg.event
  local why, by = League.held(host)
  host:_log("league", { event = msg.event, held = why, by = by and by.id or nil }, p)
  League.tick(host)
  return true
end

return League
