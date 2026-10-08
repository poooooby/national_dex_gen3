-- Standalone: luajit mods/national_dex_gen3/tests/dex_entries_test.lua (from
-- the gen1recomp root; needs Emerald imported under emerald/).
--
-- Emerald's Pokedex entries (Mapsec.readLua("pokemon/pokedex/entries.lua"))
-- end at slot 411. A mod that walks every National number and asserts an
-- entry for each (Kanto Gear's species cache, once Dex.NATIONAL_MAX covers
-- #387+) errors on the first species past it, so this mod answers for every
-- species it registers. Mapsec reads the engine's virtual file cache, which
-- is not set up headlessly, so the reader is stubbed with one shaped like
-- the real file BEFORE the mod loads (the wrap is installed once per process).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")

local Mapsec = require("src.ui.game3.rse.mapsec")
local reads = 0
Mapsec.readLua = function(rel)
  reads = reads + 1
  if rel == "pokemon/pokedex/entries.lua" then
    return { [1] = { category = "SEED", height = 7, weight = 69, description = "cart text" } }
  end
  return { other = true }
end

local data = H.gen3Data("emerald")
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.events:emit("game.ready", {})

local entries = Mapsec.readLua("pokemon/pokedex/entries.lua")
T.eq(entries[1].description, "cart text", "the cart's own entries pass through untouched")
local lacking = 0
for slot = 451, 1089 do
  if entries[slot] == nil then lacking = lacking + 1 end
end
T.eq(lacking, 0, "every registered species (slots 451-1089) has an entry")
local turtwig = entries[451]
T.eq(turtwig.category, "TINY LEAF", "its category is PokeAPI's genus")
T.eq(turtwig.height, 4, "height in decimetres, as Gen 3 stores it")
T.eq(turtwig.weight, 102, "weight in hectograms")
T.eq(type(turtwig.description), "string", "text is a string (blank), not nil, for readers that index it")
T.eq(Mapsec.readLua("something/else.lua").other, true, "other files are passed through")
run.release()
T.finish("national_dex_gen3 Pokedex entries")
