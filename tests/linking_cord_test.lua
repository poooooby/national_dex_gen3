-- Standalone: luajit mods/national_dex_gen3/tests/linking_cord_test.lua
-- (from the gen1recomp root; needs Pokemon FireRed imported under firered/).
--
-- The Linking Cord (data/items.lua, src/conditional_evos.lua's EVO_TRADE override): used from
-- the Bag it evolves a Pokemon that evolves by a plain trade, the cart's own (Kadabra) and this
-- mod's (Boldore), and nothing else; a real trade still evolves it. This mod's evolution items
-- that are used rather than held tell the Bag so (fieldUse "evo"): without it the Bag offered no
-- USE on the party for any of them.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")

H.useCart("firered")
local data = H.gen3Data()
local ItemsData = require("src.core.game3.items_data")
if ItemsData.ensureLoaded then ItemsData.ensureLoaded() end
data.gen3Items = ItemsData
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local okA, errA = pcall(require("src.mods.Gen3Compat").applyMerged, { mods = run.loader, data = data })
T.check(okA, "registry items reach the item tables (" .. tostring(errA) .. ")")
run.loader.events:emit("game.ready", {})

local P = require("src.core.game3.pokemon")
local Evolution = require("src.core.game3.evolution")
local ItemUse = require("src.core.game3.item_use")

local cord = run.loader.content.items:get("LINKING_CORD")
T.eq(cord and cord.index, 938, "the Linking Cord is item 938")
local CORD = cord and cord.index or 938

local function mon(id, level)
  return { species = P.speciesFromName(id), level = level or 40, personality = 0, moves = { 33, 0, 0, 0 } }
end
local function cordTarget(id) return Evolution.itemTarget(mon(id), CORD) end

T.eq(cordTarget("KADABRA"), P.speciesFromName("ALAKAZAM"), "Kadabra + Linking Cord -> Alakazam (the cart's trade)")
T.eq(cordTarget("HAUNTER"), P.speciesFromName("GENGAR"), "Haunter + Linking Cord -> Gengar")
T.eq(cordTarget("BOLDORE"), P.speciesFromName("GIGALITH"), "Boldore + Linking Cord -> Gigalith (this mod's trade)")
T.eq(cordTarget("PIKACHU"), nil, "Pikachu: the cord does nothing")
-- a trade holding an item: the cord stands in for that trade too, with the item held
local function holding(id, item)
  local m = mon(id)
  m.item, m.heldItem = item, item
  return m
end
local DISC = run.loader.content.items:get("DUBIOUS_DISC").index
T.eq(cordTarget("ONIX"), nil, "Onix holding nothing: the cord does nothing")
T.eq(Evolution.itemTarget(holding("ONIX", 199), CORD), P.speciesFromName("STEELIX"), "Onix holding a Metal Coat -> Steelix")
T.eq(Evolution.itemTarget(holding("SEADRA", 201), CORD), P.speciesFromName("KINGDRA"), "Seadra holding a Dragon Scale -> Kingdra")
T.eq(Evolution.itemTarget(holding("PORYGON2", DISC), CORD), P.speciesFromName("PORYGON_Z"),
     "Porygon2 holding a Dubious Disc -> Porygon-Z (this mod's item)")
T.eq(Evolution.itemTarget(holding("PORYGON2", 199), CORD), nil, "Porygon2 holding the wrong item: nothing")
T.eq(Evolution.tradeTarget(holding("ONIX", 199)), P.speciesFromName("STEELIX"), "a real trade holding the item still works")

-- the evolution uses the held item up, as the trade would; a stone evolution keeps its held item
do
  local p2 = holding("PORYGON2", DISC)
  local target = Evolution.itemTarget(p2, CORD)
  Evolution.apply(p2, target, nil, nil, "item")
  T.eq(P.speciesOf(p2), P.speciesFromName("PORYGON_Z"), "Porygon2 became Porygon-Z")
  T.eq(tonumber(p2.item) or 0, 0, "and its Dubious Disc is used up")
  local clefairy = holding("CLEFAIRY", 199)
  Evolution.apply(clefairy, Evolution.itemTarget(clefairy, 94), nil, nil, "item")
  T.eq(clefairy.item, 199, "a Moon Stone evolution keeps the Pokemon's held item")
end
T.eq(Evolution.itemCheck(mon("MACHOKE"), CORD), P.speciesFromName("MACHAMP"),
     "the party menu's can-it-evolve check agrees (Machoke)")
T.eq(Evolution.itemTarget(mon("KADABRA"), 94), nil, "a Moon Stone still does nothing to Kadabra")
T.eq(Evolution.tradeTarget(mon("KADABRA")), P.speciesFromName("ALAKAZAM"), "a real trade still evolves Kadabra")
T.eq(Evolution.itemTarget(mon("CLEFAIRY"), 94), P.speciesFromName("CLEFABLE"), "the cart's stones are untouched")

-- the Bag: every item used on a Pokemon offers USE on the party; held ones do not
for _, n in ipairs({ 900, 902, 904, 909, 910, 911, 913, 914, 916, 917, 919, 934, 936, 938 }) do
  T.eq(ItemUse.fieldUseKind(n), "evo", (ItemsData.info(n) or {}).name .. " is used from the Bag")
  T.check(ItemUse.needsPartyTarget(n), (ItemsData.info(n) or {}).name .. " asks for a Pokemon")
end
for _, n in ipairs({ 906, 923, 930, 932 }) do
  T.check(ItemUse.fieldUseKind(n) ~= "evo", (ItemsData.info(n) or {}).name .. " is held, not used")
end

run.release()
T.finish("national_dex_gen3 linking cord")
