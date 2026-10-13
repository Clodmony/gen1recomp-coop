-- Frame driver for driver_launcher_boot_test.lua (#28).  main.lua resumes it
-- with the launcher while no game runs and restarts it with the game once one
-- boots; on the launcher it boots Red, in the game it runs a few frames.
return function(first)
  if first and first._boot then
    first:_boot("red")
    coroutine.yield()
    error("the launcher was resumed again after booting a game")
  end
  for _ = 1, 3 do coroutine.yield() end
end
