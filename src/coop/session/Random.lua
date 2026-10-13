-- Random ids for co-op (#10): device, player and campaign ids.  The plain
-- math.random starts from the same seed in every process (and LÖVE seeds
-- love.math from the second it started), so two games started together
-- drew the same device id in the live check.  This reads the system's
-- random source when there is one and otherwise mixes clocks and an
-- address into a seed of its own.
--
--   Random.hex(16) -- "3f9c0a…"

local Random = {}

local function urandom(n)
  local ok, f = pcall(io.open, "/dev/urandom", "rb")
  if not ok or not f then return nil end
  local bytes = f:read(n)
  f:close()
  if type(bytes) ~= "string" or #bytes < n then return nil end
  return bytes
end

local seeded = false
local function seedOnce()
  if seeded then return end
  seeded = true
  local t = (love and love.timer and love.timer.getTime) and love.timer.getTime() or 0
  local addr = tonumber(tostring({}):match("0x(%x+)") or "0", 16) or 0
  math.randomseed((os.time() + math.floor(t * 1e6) + addr + math.floor(os.clock() * 1e6))
    % 2147483647)
  for _ = 1, 8 do math.random() end
end

function Random.hex(n)
  local bytes = urandom(math.ceil(n / 2))
  if bytes then
    return (bytes:gsub(".", function(c) return ("%02x"):format(c:byte()) end)):sub(1, n)
  end
  seedOnce()
  local out = {}
  for i = 1, n do out[i] = ("%x"):format(math.random(0, 15)) end
  return table.concat(out)
end

return Random
