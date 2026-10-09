-- Standalone: luajit mods/national_dex_gen3/tests/editor_learnset_test.lua (from the
-- gen1recomp root; needs Pokemon FireRed imported under firered/ and tools/save-editor).
--
-- The save editor never boots a game, so it hands the mod loader its own dataset
-- (Gen.bindGame3Data). That must carry the move and item modules the way the game's
-- Game3:_exposeModData does, or the loader's moves registry is empty when this mod
-- registers its species and every species #387+ loses its learnset: a new Pokemon
-- made in the editor then has no moves.
package.path = "./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua;"
  .. package.path
local ok, Gen = pcall(require, "Gen")
if not ok then print("skipped: the save editor is not in this checkout") os.exit(0) end

local T = require("tests.modkit")
love = love or require("tests.love_stub")
local CacheBlob = require("src.import.CacheBlob")
-- the cart's cache read straight off disk (the stock cache check wants a current importer)
local function path(rel) return "firered/" .. rel end
local reader = {
  read = function(_, rel)
    local f = io.open(path(rel), "rb")
    if not f then return nil end
    local data = f:read("*a"); f:close()
    return CacheBlob.decode(rel, data)
  end,
  exists = function(_, rel)
    local f = io.open(path(rel), "rb")
    if f then f:close() return true end
    return false
  end,
}
if not reader:exists("data/generated/gba/pokemon/names.lua") then
  print("skipped: FireRed is not imported")
  os.exit(0)
end

require("src.core.GameVersion").set("firered")
local Dataset = require("src.core.game3.dataset")
Dataset.cache = function() return reader end
local Data = require("src.core.Data")
local MonOps = require("MonOps")
local P = require("src.core.game3.pokemon")

Data:load()
Gen.bindGame3Data(Data)
T.check(Data.gen3Moves ~= nil and Data.gen3Items ~= nil, "the editor's dataset exposes the move and item modules")

local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = Data, generation = 3 })
T.eq(#run.errors, 0, "the mod loads in the editor (" .. tostring(run.errors[1]) .. ")")
Gen.applyGame3Mods(run.loader, Data)
Gen.addGame3RegistrySpecies(Data, run.loader.content.pokemon, P.SPECIES_EGG + 1)

for _, id in ipairs({ "ABOMASNOW", "TURTWIG", "DARUMAKA_GALAR", "PECHARUNT" }) do
  local def = Data.pokemon[id]
  T.check(def ~= nil, id .. " is in the editor's catalog")
  T.check(def and #P.learnset(def.speciesId) > 0, id .. " has a learnset in the editor")
  local mon = MonOps.create(Data, id, 30, 3)
  T.check(#mon.moves > 0, id .. " made in the editor has moves")
end
-- a move the species learns must be a real, named move
local mon = MonOps.create(Data, "ABOMASNOW", 30, 3)
local first = mon.moves[1]
T.check(first and (first.moveId or first.id), "its first move has an id")

run.release()
T.finish("national_dex_gen3 editor learnsets")
