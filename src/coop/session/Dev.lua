-- The development entry to a co-op session (#10): start the game with
--
--   love . --coop-host[=PORT] [--coop-name=NAME] [--coop-logs=off]
--   love . --coop-join=ADDRESS[:PORT] [--coop-name=NAME] [--coop-logs=off]
--
-- (or POKEPORT_COOP_HOST=PORT, POKEPORT_COOP_JOIN=ADDRESS,
-- POKEPORT_COOP_NAME=NAME, POKEPORT_COOP_LOGS=off for scripted runs).
-- --coop-campaign=ID (POKEPORT_COOP_CAMPAIGN) hosts that campaign again
-- from its file (#13) instead of a new one.
-- The launcher's co-op screens (#12) are the way in for players; this entry
-- skips them for scripted runs.  Once a game runs, the host side hosts a
-- new campaign on UDP PORT (default 24680) with the LAN beacon, and the
-- join side dials the address and joins as soon as the host answers.  The
-- session itself is Session.lua; the session log is shared with the other
-- players unless logs are off (#31).

local Transport = require("src.coop.session.Transport")
local Protocol = require("src.coop.session.Protocol")
local Session = require("src.coop.session.Session")
local Random = require("src.coop.session.Random")

local Dev = { config = nil, session = nil }

local function say(fmt, ...)
  print("co-op: " .. fmt:format(...))
end

-- reads the --coop-* arguments, then the environment; nil when neither asks
function Dev.parse(args, getenv)
  getenv = getenv or os.getenv
  local cfg = {}
  for _, a in ipairs(args or {}) do
    local key, value = tostring(a):match("^%-%-coop%-(%a+)=?(.*)$")
    if key == "host" then
      cfg.mode, cfg.port = "host", tonumber(value)
    elseif key == "join" and value ~= "" then
      cfg.mode, cfg.address = "join", value
    elseif key == "name" and value ~= "" then
      cfg.name = value
    elseif key == "logs" then
      cfg.logs = value
    elseif key == "campaign" and value ~= "" then
      cfg.campaign = value
    end
  end
  if not cfg.mode then
    local hostPort, joinAddress = getenv("POKEPORT_COOP_HOST"), getenv("POKEPORT_COOP_JOIN")
    if hostPort and hostPort ~= "" then
      cfg.mode, cfg.port = "host", tonumber(hostPort)
    elseif joinAddress and joinAddress ~= "" then
      cfg.mode, cfg.address = "join", joinAddress
    end
  end
  if not cfg.mode then return nil end
  cfg.name = cfg.name or getenv("POKEPORT_COOP_NAME")
  if not Protocol.name(cfg.name) then cfg.name = cfg.mode == "host" and "HOST" or "GUEST" end
  cfg.port = cfg.port or Transport.DEFAULT_PORT
  cfg.campaign = cfg.campaign or getenv("POKEPORT_COOP_CAMPAIGN")
  if not Protocol.campaignId(cfg.campaign) then cfg.campaign = nil end
  -- sharing the session log defaults on (#31, design A1.14)
  local logs = (cfg.logs or getenv("POKEPORT_COOP_LOGS") or ""):lower()
  cfg.logs = nil
  cfg.shareLogs = not (logs == "off" or logs == "0" or logs == "no" or logs == "false")
  return cfg
end

function Dev.configure(args)
  Dev.config = Dev.parse(args)
  if Dev.config then
    say("%s requested (%s)", Dev.config.mode,
        Dev.config.mode == "host" and ("port " .. Dev.config.port) or Dev.config.address)
  end
end

Dev.nextMove = Session.nextMove

function Dev.start()
  local cfg = Dev.config
  local cart = Session.cartridge()
  if cfg.mode == "host" then
    local refused
    Dev.session, refused = Session.startHost({
      campaign = { id = cfg.campaign or ("c" .. Random.hex(16)),
                   title = cart.game:upper() .. " CO-OP" },
      cartridge = cart, name = cfg.name, port = cfg.port, shareLogs = cfg.shareLogs,
    })
    if not Dev.session then
      say("campaign refused: %s", refused and refused.why or "?")
      Dev.config = nil
    end
  else
    Dev.session = Session.startDial({ address = cfg.address, cartridge = cart,
                                 name = cfg.name, shareLogs = cfg.shareLogs })
    say("dialling %s", Dev.session.address)
  end
end

-- One frame of a game: the session the launcher started, or the one this
-- entry starts once the game runs.  Returns "launcher" when the session
-- ended under the game (main.lua then goes back to the launcher).
function Dev.update(dt, game)
  if not game then return nil end
  if not Dev.config then return Session.tick(dt, game) end
  if Session.takeLauncher() then return "launcher" end
  if not Dev.session then Dev.start() end
  local s = Dev.session
  if not s then return nil end
  if s.kind == "join" and s.status == "probed" then s:join() end
  if s.status == "refused" and not s.said then
    s.said = true
    say("refused (%s)", tostring(s.reason))
  end
  if s ~= Session.current then return nil end
  return Session.tick(dt, game)
end

function Dev.shutdown()
  Session.shutdown()
end

return Dev
