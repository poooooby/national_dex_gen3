-- Standalone: luajit mods/national_dex_gen3/tests/art_heights_test.lua [game] (from the gen1recomp
-- root; FireRed by default; red / gold / ... load the Gen 1/2 path).
--
-- mod.exports.artHeightOf / artHeights (src/art_heights.lua, data/art_heights.lua): each WoobleSprite
-- front picture's measured height, for other mods' height charts, on every game.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local DIR = (arg[0]:gsub("\\", "/"):match("^(.*)/") or ".")
local GAME = arg[1] or "firered"
local GEN12 = ({ red = 1, blue = 1, yellow = 1, gold = 2, silver = 2, crystal = 2 })[GAME]

local run, api
if GEN12 then
  local H12 = dofile(DIR .. "/_gen12.lua")
  run = H12.load(GAME)
  api = run.loader.exports.national_dex_gen3
else
  local H = dofile(DIR .. "/_gen3.lua")
  local data = H.gen3Data(GAME)
  H.useCart(GAME)
  data.gen3Moves = require("src.core.game3.battle.moves")
  run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
  api = run.loader.exports.national_dex_gen3
end
T.eq(#run.errors, 0, GAME .. ": loads clean (" .. tostring(run.errors[1]) .. ")")
T.check(api and type(api.artHeightOf) == "function" and type(api.artHeights) == "function",
  GAME .. ": the exports are there")

local onix = api.artHeightOf("ONIX")
T.check(onix and onix.id == "ONIX" and onix.dex == 95, "Onix by id")
T.check(onix and onix.long == true and onix.pokedex == 8.8, "its Pokedex number is a length (8.8 m)")
T.check(onix and onix.standing > 1 and onix.standing < onix.pokedex, "so it stands lower than that")
T.eq(api.artHeightOf(95) and api.artHeightOf(95).id, "ONIX", "and by National Dex number")
T.eq(api.artHeightOf("onix") and api.artHeightOf("onix").id, "ONIX", "any case")

local pika = api.artHeightOf(25)
T.check(pika and pika.id == "PIKACHU" and math.abs(pika.standing - 0.4) < 0.15, "Pikachu stands about 0.4 m")
local vulpix = api.artHeightOf("VULPIX_ALOLA")
T.check(vulpix and vulpix.dex == 37 and vulpix.slot and vulpix.slot >= 1090, "a form by its id")
T.eq(api.artHeightOf(37).id, "VULPIX", "the number answers for the base species, not a form")
T.check(api.artHeightOf("MEOWSTIC_FEMALE") ~= nil, "female sheets too")
T.eq(api.artHeightOf("NOT_A_POKEMON"), nil, "an unknown id: nil")
T.eq(api.artHeightOf(9999), nil, "an unknown number: nil")

local all = api.artHeights()
local n = 0
for _, r in pairs(all) do
  n = n + 1
  if not (r.standing > 0 and r.art >= r.standing - 1e-6 and r.width > 0 and r.pokedex > 0) then
    T.check(false, "row " .. tostring(r.id) .. " is sane")
  end
end
T.check(n >= 1182, "every sprite (" .. n .. ")")
all.ONIX.standing = -1
onix.standing = -1
T.check(api.artHeightOf("ONIX").standing > 0, "returns are copies")

run.release()
T.finish("national_dex_gen3 art heights (" .. GAME .. ")")
