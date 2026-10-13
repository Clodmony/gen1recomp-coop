-- The co-op fork's own suites (tests/coop), ROM-free: each runs in its own
-- process against the committed fixture dataset.
--   luajit tests/run_coop.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

require("tests.tier_runner").main({ "tests/coop" }, "coop")
