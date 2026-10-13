-- Standalone: luajit mods/national_dex_gen3/tests/unown_test.lua (from the gen1recomp root;
-- needs Pokemon FireRed imported under firered/).
--
-- An Unown other than A is drawn from the cart's letter slots (SPECIES_UNOWN_B 413 ..
-- SPECIES_UNOWN_QMARK 439), which have no name in the cart. Once a mod hooks pokemon.sprite
-- (this one does), the engine names the slot for the hook's ctx, and Pokemon.name used to
-- stop the game on "no ROM species name for species 425". The letters answer UNOWN.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")

local data = H.gen3Data()
local Pokemon = require("src.core.game3.pokemon")
local Gen3Compat = require("src.mods.Gen3Compat")

T.check(not pcall(Pokemon.name, 425), "unpatched, the cart has no name for Unown's letter slot 425")

local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.events:emit("game.ready", {})

local bad = {}
for slot = 413, 439 do
  local ok, name = pcall(Gen3Compat.speciesName, slot)
  if not (ok and name == "UNOWN") then bad[#bad + 1] = slot .. "=" .. tostring(name) end
end
T.eq(#bad, 0, "every letter slot is named UNOWN for the sprite hook (" .. table.concat(bad, ", ") .. ")")
T.eq(Pokemon.name(425), "UNOWN", "Pokemon.name(425)")
T.eq(Pokemon.keyName(425), nil, "the letter slots are still not species of their own")
T.eq(Pokemon.speciesFromName("UNOWN"), 201, "UNOWN is still the cart's Unown")
T.eq(Pokemon.name(201), "UNOWN", "and keeps its name")
T.check(not pcall(Pokemon.name, 445), "an unused slot still has no name")
T.eq(Pokemon.name(Pokemon.speciesFromName("TURTWIG")), "TURTWIG", "our species keep theirs")

run.release()
T.finish("national_dex_gen3 Unown letter slots")
