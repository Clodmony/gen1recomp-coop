-- A windowless LÖVE run for the co-op ENet test (#10): no window, graphics
-- or audio, so it runs on a machine without a display (CI).
function love.conf(t)
  t.identity = "gen1recomp-coop-enet-test" -- never the game's save folder
  t.window = nil
  t.console = false
  for _, m in ipairs({ "audio", "data", "event", "font", "graphics", "image",
                       "joystick", "keyboard", "math", "mouse", "physics",
                       "sound", "system", "touch", "video", "window" }) do
    t.modules[m] = false
  end
  t.modules.timer = true
  t.modules.event = true
  t.modules.data = true
end
