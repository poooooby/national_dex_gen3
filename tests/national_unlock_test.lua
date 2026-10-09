-- Standalone: luajit mods/national_dex_gen3/tests/national_unlock_test.lua (from the gen1recomp
-- root; needs Pokemon FireRed imported). The "National Dex" option answers true from the two
-- engine questions without touching the save, and only while it is on.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local Dex = require("src.core.game3.dex")
local PokedexData = require("src.core.game3.pokedex_data")

local data = H.gen3Data()
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local on = false
local Unlock = assert(loadfile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/../src/national_unlock.lua"))()
Unlock.install(function() return on end)
local save = { version = "firered", dex = {}, flags = {}, vars = {} }
T.eq(Dex.nationalEnabled(save), false, "locked by default")
T.eq(PokedexData.isNationalUnlocked({ version = "firered", dex = {} }, {}), false, "FireRed's check too")
on = true
T.eq(Dex.nationalEnabled(save), true, "the option unlocks it")
T.eq(PokedexData.isNationalUnlocked({ version = "firered", dex = {} }, {}), true, "and FireRed's own check")
T.eq(next(save.dex), nil, "without writing to the save")
on = false
T.eq(Dex.nationalEnabled(save), false, "turning it off puts it back")
Unlock.install(function() return true end)
T.eq(Dex.nationalEnabled(save), true, "a second install replaces the rule instead of stacking")
run.release()
T.finish("national_dex_gen3 national unlock")
