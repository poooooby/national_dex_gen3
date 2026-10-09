-- Standalone: luajit mods/national_dex_gen3/tests/dex_sync_test.lua (from the gen1recomp root;
-- needs Pokemon FireRed imported). Opening the Pokedex registers the party and the PC.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local data = H.gen3Data()
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.events:emit("game.ready", {})
local api = run.loader.exports.national_dex_gen3
local Dex = require("src.core.game3.dex")
local Pokemon = require("src.core.game3.pokemon")
local DexSync = assert(loadfile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/../src/dex_sync.lua"))()

local latias, darmanitan = Pokemon.speciesFromName("PIKACHU"), api.slotOf("DARMANITAN_GALAR_STANDARD")
T.check(darmanitan ~= nil, "the Galarian Darmanitan form exists")
local session = { dex = Dex.new(), party = { { species = latias } },
  storage = { boxes = { { mons = { [3] = { species = darmanitan }, [4] = { species = darmanitan, isEgg = true } } } } } }
T.eq(DexSync.sync(session), 2, "two Pokemon looked at (eggs skipped)")
T.check(Dex.isCaught(session.dex, latias), "a party Pokemon is registered")
T.check(Dex.isCaught(session.dex, darmanitan), "a boxed form is registered")
T.check(Dex.isCaught(session.dex, api.slotOf("DARMANITAN")), "and marks its base species")
T.eq(DexSync.sync(nil), 0, "no session is fine")
run.release()
T.finish("national_dex_gen3 dex sync")
