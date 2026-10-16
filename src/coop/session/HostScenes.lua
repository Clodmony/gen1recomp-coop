-- Rival scenes on the host (#59, design A10.5, decision G29): one driver a
-- map.  A window whose world starts one of the rival's scenes after the
-- opening claims it (`scene`, on); the first claim of a map drives and
-- every player's `state` names it (`scenes`), and a second claim of that
-- map is refused `scene_taken` (that window plays on: its battle joins the
-- driver's as one unique encounter, #21).  The claim ends with the
-- driver's release (its window sends it at its first rest point after the
-- scene, behind the scene's result patch), or when the driver changes map,
-- drops or leaves; the scene then replays from its start for whoever meets
-- the rival next.  Partners on that map wait in their own windows
-- (src/coop/game/Scenes.lua).  The claims live in host memory only.
--
--   HostScenes.claim(host, p, msg)  -- the `scene` handler (Host.lua)
--   HostScenes.moved(host, p)       -- after a move (Host:_move)
--   HostScenes.left(host, p)        -- a player dropped or left
--   HostScenes.summaries(host)      -- `state.scenes`

local HostScenes = {}

local function claims(host)
  host.scenes = host.scenes or {}
  return host.scenes
end

local function release(host, map, why)
  local c = host.scenes and host.scenes[map]
  if not c then return end
  host.scenes[map] = nil
  host.dirty = true
  host:_log("scene", { map = map, key = c.key, on = false, why = why }, host.byId[c.by])
end

-- a claim (msg.on) or a release; returns true, or false and the refusal
function HostScenes.claim(host, p, msg)
  local all = claims(host)
  local c = all[msg.map]
  if not msg.on then
    if c and c.by == p.id then release(host, msg.map, "done") end
    return true
  end
  if c and c.by ~= p.id then
    host:_log("scene", { map = msg.map, key = msg.key, on = true, refused = "scene_taken" }, p)
    return false, "scene_taken"
  end
  if c then return true end
  -- a player drives one scene at a time
  for map, other in pairs(all) do
    if other.by == p.id then release(host, map, "another") end
  end
  all[msg.map] = { map = msg.map, key = msg.key, by = p.id }
  host.dirty = true
  host:_log("scene", { map = msg.map, key = msg.key, on = true }, p)
  return true
end

-- a driver whose move names another map lets go
function HostScenes.moved(host, p)
  for map, c in pairs(claims(host)) do
    if c.by == p.id and p.map ~= map then release(host, map, "map") end
  end
end

-- a driver who dropped or left lets go
function HostScenes.left(host, p)
  for map, c in pairs(claims(host)) do
    if c.by == p.id then release(host, map, "left") end
  end
end

-- the claims as `state` names them, by map
function HostScenes.summaries(host)
  local out = {}
  for _, c in pairs(claims(host)) do out[#out + 1] = { map = c.map, key = c.key, by = c.by } end
  table.sort(out, function(a, b) return a.map < b.map end)
  return out
end

return HostScenes
