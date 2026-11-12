-- Standalone: luajit mods/national_dex_gen3/tests/gen12_types_test.lua [red|blue|yellow|gold|silver|crystal ...]
-- (from the gen1recomp root; runs on red, yellow, gold and crystal when none is named).
-- src/gen12/types.lua: Red/Blue/Yellow gain Dark, Steel and Fairy, Gold/Silver/Crystal Fairy, each
-- with the physical/special split the game's damage reads and today's matchups (Gold's Steel
-- stops resisting Ghost and Dark); the cart's species and moves take their modern typing; the
-- Erratic and Fluctuating curves are registered, equal to the Gen 3 tables at every level.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")

local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

-- the curves against the engine's own port of pret's experience tables (Gen 3: 1 Erratic, 2 Fluctuating)
do
  local Types = H.module("src/gen12/types.lua")
  local SummaryData = require("src.core.game3.summary_data")
  local okE, okF = true, true
  for lv = 1, 100 do
    if Types.GROWTH.ERRATIC(lv) ~= SummaryData.expForLevel(1, lv) then okE = false end
    if Types.GROWTH.FLUCTUATING(lv) ~= SummaryData.expForLevel(2, lv) then okF = false end
  end
  T.check(okE, "Erratic equals the Gen 3 table at every level")
  T.check(okF, "Fluctuating equals the Gen 3 table at every level")
  T.eq(Types.GROWTH.ERRATIC(100), 600000, "Erratic tops out at 600,000")
  T.eq(Types.GROWTH.FLUCTUATING(100), 1640000, "Fluctuating tops out at 1,640,000")
end

for _, version in ipairs(H.versions()) do
  local gen = H.GENERATION[version]
  local run = H.load(version)
  for i = 1, math.min(5, #run.errors) do print("load error: " .. tostring(run.errors[i])) end
  T.eq(#run.errors, 0, version .. ": loads clean")
  local data = run.data
  local chart = data.type_chart
  local pokemon, moves = data.pokemon, data.moves

  if gen == 1 then
    local TypeChart = require("src.battle.TypeChart")
    local Damage = require("src.battle.Damage")
    TypeChart.load(data)
    T.check(chart.types.DARK and chart.types.STEEL and chart.types.FAIRY, version .. ": Dark, Steel and Fairy")
    T.check(Damage.isSpecial("DARK") and not Damage.isSpecial("STEEL") and Damage.isSpecial("FAIRY"),
      version .. ": Dark and Fairy hit with Special, Steel with Attack")
    T.eq(TypeChart.displayName("FAIRY", data), "FAIRY", version .. ": Fairy's name")
    local function eff(a, d) return TypeChart.effectiveness(a, d) end
    T.eq(eff("DARK", { "PSYCHIC_TYPE" }), 20, version .. ": Dark beats Psychic")
    T.eq(eff("PSYCHIC_TYPE", { "DARK" }), 0, version .. ": Psychic can't touch Dark")
    T.eq(eff("FIGHTING", { "STEEL" }), 20, version .. ": Fighting beats Steel")
    T.eq(eff("POISON", { "STEEL" }), 0, version .. ": Poison can't touch Steel")
    T.eq(eff("GHOST", { "STEEL" }), 10, version .. ": Steel takes Ghost neutrally (today's chart)")
    T.eq(eff("FAIRY", { "DRAGON" }), 20, version .. ": Fairy beats Dragon")
    T.eq(eff("DRAGON", { "FAIRY" }), 0, version .. ": Dragon can't touch Fairy")
    T.eq(eff("STEEL", { "FAIRY" }), 20, version .. ": Steel beats Fairy")
    T.eq(eff("GHOST", { "PSYCHIC_TYPE" }), 0, version .. ": the cart's own Ghost-vs-Psychic row is kept")
    T.eq(eff("ELECTRIC", { "ELECTRIC", "STEEL" }), 5, version .. ": Magnemite's typing resists Electric once")
    T.check(same(pokemon.MAGNEMITE.types, { "ELECTRIC", "STEEL" }), version .. ": Magnemite is Electric/Steel")
    T.check(same(pokemon.CLEFAIRY.types, { "FAIRY" }), version .. ": Clefairy is Fairy")
    T.check(same(pokemon.MR_MIME.types, { "PSYCHIC_TYPE", "FAIRY" }), version .. ": Mr. Mime is Psychic/Fairy")
    T.eq(moves.BITE.type, "DARK", version .. ": Bite is Dark")
    T.eq(moves.GUST.type, "FLYING", version .. ": Gust is Flying")
    local Growth = require("src.pokemon.Growth")
    T.eq(Growth.expForLevel("ERRATIC", 100, data.growth_rates), 600000, version .. ": Erratic through the engine")
    T.eq(Growth.expForLevel("FLUCTUATING", 50, data.growth_rates), 142500, version .. ": Fluctuating through the engine")
    T.eq(Growth.levelForExp("ERRATIC", 600000, 100, data.growth_rates), 100, version .. ": levels by the Erratic curve")
  else
    local Damage = require("src.battle.gen2.Damage")
    local Mon = require("src.battle.gen2.Mon")
    T.check(chart.types.FAIRY ~= nil, version .. ": Fairy")
    T.eq(chart.types.FAIRY and chart.types.FAIRY.index, 28, version .. ": Fairy has a type byte of its own")
    T.check(chart.types.DARK and chart.types.STEEL and chart.types.BIRD and chart.types.CURSE_TYPE,
      version .. ": the cart's own types stay")
    T.check(not Damage.isPhysical("FAIRY", chart.types) and Damage.isPhysical("STEEL", chart.types),
      version .. ": Fairy hits with Special Attack, Steel with Attack")
    local function eff(a, d) return Damage.typeMultiplier(a, d, chart.matchups) end
    T.eq(eff("FAIRY", { "DRAGON", "DRAGON" }), 20, version .. ": Fairy beats Dragon")
    T.eq(eff("DRAGON", { "FAIRY", "FAIRY" }), 0, version .. ": Dragon can't touch Fairy")
    T.eq(eff("FAIRY", { "STEEL", "STEEL" }), 5, version .. ": Steel resists Fairy")
    T.eq(eff("POISON", { "FAIRY", "FAIRY" }), 20, version .. ": Poison beats Fairy")
    T.eq(eff("GHOST", { "STEEL", "STEEL" }), 10, version .. ": Steel no longer resists Ghost")
    T.eq(eff("DARK", { "STEEL", "STEEL" }), 10, version .. ": nor Dark")
    T.eq(eff("FIRE", { "STEEL", "STEEL" }), 20, version .. ": the cart's other Steel rows stay")
    T.check(same(pokemon.CLEFAIRY.types, { "FAIRY", "FAIRY" }), version .. ": Clefairy is Fairy (written twice)")
    T.check(same(pokemon.MR__MIME.types, { "PSYCHIC_TYPE", "FAIRY" }), version .. ": Mr. Mime is Psychic/Fairy")
    T.check(same(pokemon.AZUMARILL.types, { "WATER", "FAIRY" }), version .. ": Azumarill is Water/Fairy")
    T.check(same(pokemon.MAGNEMITE.types, { "ELECTRIC", "STEEL" }), version .. ": Magnemite as the cart has it")
    T.eq(moves.CHARM.type, "FAIRY", version .. ": Charm is Fairy")
    T.eq(moves.MOONLIGHT.type, "FAIRY", version .. ": Moonlight is Fairy")
    T.eq(moves.BITE.type, "DARK", version .. ": Bite as the cart has it")
    T.eq(Mon.experienceForLevel(Mon.growthFor(data, "GROWTH_ERRATIC"), 100), 600000,
      version .. ": Erratic through the engine")
    T.eq(Mon.experienceForLevel(Mon.growthFor(data, "GROWTH_FLUCTUATING"), 50), 142500,
      version .. ": Fluctuating through the engine")
    T.eq(Mon.experienceForLevel(Mon.growthFor(data, "GROWTH_SLOW"), 100), 1250000,
      version .. ": the cart's own curves stay")
  end
  run.release()
end

T.finish("national_dex_gen3 Gen 1/2 types")
