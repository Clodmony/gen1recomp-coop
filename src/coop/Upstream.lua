-- Upstream's services the fork keeps off (#26).  The self-updater asks
-- upstream's GitHub releases and, in a packaged build, would download and
-- chainload upstream's payload over the fork (src/update); cloud sync talks
-- to upstream's sync server for a device linked in upstream's launcher, which
-- the fork has no screen for (src/sync).  main.lua calls Upstream.install at
-- boot and filters a launch request's tasks through Upstream.launchTasks.
-- See docs/coop/launcher.md.

local Upstream = {}

-- what the fork lets through; both stay off until the fork decides it wants
-- its own updater or sync service
Upstream.UPDATER = false
Upstream.CLOUD_SYNC = false

-- Before the self-updater's boot shell would run.  Every sync user asks
-- SyncEngine.shared(), which answers nil once _shared is false (its own "no
-- engine" value): the game's save, focus and resume hooks, the pre-launch
-- sync and the Box journal all skip sync then.
function Upstream.install()
  if not Upstream.CLOUD_SYNC then
    require("src.sync.SyncEngine")._shared = false
  end
end

-- whether main.lua may run the updater's boot shell (src/update/Boot.lua)
function Upstream.updaterAllowed()
  return Upstream.UPDATER
end

-- A launch request (shortcut, --update, --sync, a URI) with the update check
-- and the pre-launch sync taken out, so src/core/Prelaunch has nothing to do.
function Upstream.launchTasks(tasks)
  local out = {}
  for k, v in pairs(type(tasks) == "table" and tasks or {}) do out[k] = v end
  if not Upstream.UPDATER then out.update = false end
  if not Upstream.CLOUD_SYNC then out.sync = false end
  return out
end

return Upstream
