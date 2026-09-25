-- Standalone: luajit mods/national_dex_gen3/tests/steps_aside_test.lua (from
-- the gen1recomp root; needs Pokemon FireRed imported under firered/).
-- With 1025Dex installed, national_dex_gen3 registers nothing: 1025Dex owns
-- the same slots and ships the art for them. A separate process from
-- register_test.lua because a mod load writes into the species tables.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")

local data = H.gen3Data()
local run = T.sdk.loadMods({ H.modRoot() .. "/tests/fixtures/1025dex", "mods/national_dex_gen3" },
                           { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean beside 1025Dex (" .. tostring(run.errors[1]) .. ")")
local api = run.loader.exports.national_dex_gen3
T.check(api and not api.isActive(), "inactive beside 1025Dex")
T.eq(api.provider(), "1025dex", "and says who provides the species")
T.eq(#api.listSpecies(), 0, "lists nothing of its own")
T.eq(run.loader.content.pokemon:get("TURTWIG"), nil, "registers nothing")
T.eq(data.gen3Pokemon._names[451], nil, "and writes no species slot")

run.release()
T.finish("national_dex_gen3 steps aside")
