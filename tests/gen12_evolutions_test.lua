-- Standalone: luajit mods/national_dex_gen3/tests/gen12_evolutions_test.lua [red|blue|yellow|gold|silver|crystal ...]
-- (from the gen1recomp root; runs on red, yellow, gold and crystal when none is named).
-- src/gen12/evolutions.lua + items.lua through each game's own evolution code (Red:
-- Evolution.pendingFor and the Bag's item use; Gold: Evolution.checkMon and its stone records):
-- every row points at real species, items and methods; level, friendship, stat, 1-in-n,
-- gender, known-move, party, steps, move-use and coins conditions; the new items evolve (Red: used, also
-- trade and held items; Gold: stones used, trade and held items held); a held item is used up
-- and coins are spent; the items are on sale.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")
local Clock = H.module("src/clock.lua")
local itemRows = H.module("data/gen12/items.lua")
local Runtime = require("src.mods.Runtime")

local function lowDvs(attack, speed)
  return { attack = attack or 0, defense = 8, speed = speed or 0, special = 8 }
end

local machineStock

local function gen1(version)
  local run = H.load(version)
  for i = 1, math.min(5, #run.errors) do print("load error: " .. tostring(run.errors[i])) end
  T.eq(#run.errors, 0, version .. ": loads clean")
  local data = run.data
  local Pokemon = require("src.pokemon.Pokemon")
  local Evolution = require("src.pokemon.Evolution")
  local ItemEffects = require("src.inventory.ItemEffects")
  local Game = require("src.core.Game")
  Game.data = data
  Game.save = require("src.core.SaveData").newGame()
  Game.save.party = {}
  local game = Game

  -- every row is whole
  local bad
  for id, def in pairs(data.pokemon) do
    if type(def) == "table" then
      for _, row in ipairs(def.evolutions or {}) do
        if not (data.pokemon[row.species] and data.evolution_methods[row.method]
            and (row.item == nil or data.items[row.item])) then bad = bad or (id .. " -> " .. tostring(row.species)) end
      end
    end
  end
  T.check(bad == nil, version .. ": every row names a species, method and item the game has (" .. tostring(bad) .. ")")
  T.check(data.evolution_methods.FRIENDSHIP ~= nil, version .. ": a FRIENDSHIP method")

  local function mon(species, level, dvs)
    local m = Pokemon.new(data, species, level)
    if dvs then m.dvs = dvs end
    return m
  end
  local function levelUp(m) return (Evolution.pendingFor(game, m, { kind = "levelup" })) end
  local function use(itemId, m)
    local result, _, extra = ItemEffects.use(data, game.save, itemId, m)
    return result == "consumed" and extra and extra.evolveTo or nil
  end

  T.eq(levelUp(mon("CHIKORITA", 16)), "BAYLEEF", version .. ": Chikorita at 16")
  T.eq(levelUp(mon("CHIKORITA", 15)), nil, version .. ": not at 15")

  -- friendship: a hidden counter, raised by level-ups
  local golbat = mon("GOLBAT", 30)
  T.eq(levelUp(golbat), nil, version .. ": Golbat at base friendship")
  Runtime.emit("pokemon.level_up", { mon = golbat, level = 31, prevLevel = 30 })
  T.eq(golbat.extra.national_dex_gen3.friendship, 75, version .. ": a level-up adds 5")
  golbat.extra.national_dex_gen3.friendship = 220
  T.eq(levelUp(golbat), "CROBAT", version .. ": Golbat -> Crobat at 220")

  -- items: the cart's stone and a new one, a trade item and a held item, used
  local eevee = mon("EEVEE", 20)
  T.eq(use("LEAF_STONE", eevee), "LEAFEON", version .. ": Leaf Stone (the cart's) -> Leafeon")
  T.eq(use("ICE_STONE", eevee), "GLACEON", version .. ": Ice Stone (new) -> Glaceon")
  T.eq(use("METAL_COAT", mon("ONIX", 20)), "STEELIX", version .. ": Metal Coat, used -> Steelix")
  T.eq(use("METAL_COAT", mon("PIDGEY", 20)), nil, version .. ": no effect on Pidgey")
  local night = Clock.isNight(nil, "device")
  T.eq(use("RAZOR_CLAW", mon("SNEASEL", 20)), night and "WEAVILE" or nil,
    version .. ": Razor Claw, used " .. (night and "at night -> Weavile" or "by day: nothing"))
  local milcery = mon("MILCERY", 24)
  T.eq(use("STAR_SWEET", milcery), nil, version .. ": a sweet before Lv 25: nothing")
  milcery.level = 25
  T.check(use("STAR_SWEET", milcery) ~= nil, version .. ": a sweet at Lv 25 -> an Alcremie")

  -- stats, 1-in-2, gender, a known move, the party
  local tyrogue = mon("TYROGUE", 20)
  tyrogue.stats.attack, tyrogue.stats.defense = 40, 30
  T.eq(levelUp(tyrogue), "HITMONLEE", version .. ": Tyrogue, Attack > Defense -> Hitmonlee")
  tyrogue.stats.attack = 30
  T.eq(levelUp(tyrogue), "HITMONTOP", version .. ": equal -> Hitmontop")
  local a, b = levelUp(mon("WURMPLE", 7, { attack = 0, defense = 0, speed = 0, special = 0 })),
    levelUp(mon("WURMPLE", 7, { attack = 0, defense = 0, speed = 0, special = 1 }))
  T.check(a ~= b and (a == "SILCOON" or a == "CASCOON") and (b == "SILCOON" or b == "CASCOON"),
    version .. ": Wurmple's two cocoons (" .. tostring(a) .. ", " .. tostring(b) .. ")")
  T.eq(levelUp(mon("COMBEE", 21, lowDvs(0, 0))), "VESPIQUEN", version .. ": a female Combee")
  T.eq(levelUp(mon("COMBEE", 21, lowDvs(15, 15))), nil, version .. ": a male one never")
  local bonsly = mon("BONSLY", 10)
  bonsly.moves = { { id = "TACKLE", pp = 35 } }
  T.eq(levelUp(bonsly), nil, version .. ": Bonsly without Mimic")
  bonsly.moves[2] = { id = "MIMIC", pp = 10 }
  T.eq(levelUp(bonsly), "SUDOWOODO", version .. ": Bonsly knowing Mimic")
  local mantyke = mon("MANTYKE", 10)
  game.save.party = { mantyke }
  T.eq(levelUp(mantyke), nil, version .. ": Mantyke alone")
  game.save.party = { mantyke, mon("REMORAID", 10) }
  T.eq(levelUp(mantyke), "MANTINE", version .. ": Mantyke with a Remoraid")

  -- counters: steps as the lead, coins (spent on evolving)
  local pawmo = mon("PAWMO", 20)
  game.save.party = { pawmo }
  for _ = 1, 999 do Runtime.emit("world.stepped", {}) end
  T.eq(levelUp(pawmo), nil, version .. ": Pawmo after 999 steps")
  Runtime.emit("world.stepped", {})
  T.eq(levelUp(pawmo), "PAWMOT", version .. ": after 1000")
  local gimmighoul = mon("GIMMIGHOUL", 10)
  game.save.coins = 998
  T.eq(levelUp(gimmighoul), nil, version .. ": Gimmighoul with 998 coins")
  game.save.coins = 1200
  T.eq(levelUp(gimmighoul), "GHOLDENGO", version .. ": with 999")
  Evolution.apply(game, gimmighoul, "GHOLDENGO", "LEVEL")
  T.eq(game.save.coins, 201, version .. ": the 999 coins are spent")
  -- Primeape: Rage Fist or Rage 20 times, from level 35
  local primeape = mon("PRIMEAPE", 35)
  for _ = 1, 19 do Runtime.emit("battle.move_used", { user = { mon = primeape }, moveId = "RAGE" }) end
  Runtime.emit("battle.move_used", { user = { mon = primeape }, moveId = "KARATE_CHOP" })
  T.eq(levelUp(primeape), nil, version .. ": Primeape after Rage x 19 (and another move)")
  Runtime.emit("battle.move_used", { user = { mon = primeape }, moveId = "RAGE" })
  T.eq(levelUp(primeape), "ANNIHILAPE", version .. ": after Rage x 20")
  -- Rage Fist is real here too, and counts together with Rage
  local primeape2 = mon("PRIMEAPE", 35)
  for i = 1, 20 do
    Runtime.emit("battle.move_used", { user = { mon = primeape2 }, moveId = i % 2 == 0 and "RAGE_FIST" or "RAGE" })
  end
  T.eq(levelUp(primeape2), "ANNIHILAPE", version .. ": after Rage Fist x 10 and Rage x 10")

  -- on sale: the EVO EXPRESS machine (Celadon 4F)
  local sells = machineStock(run, data)
  local missing
  for _, r in ipairs(itemRows) do
    if not r.carts.gen1 and not sells[r.id] then missing = missing or r.id end
  end
  T.check(missing == nil, version .. ": every new item in the EVO EXPRESS machine (" .. tostring(missing) .. ")")
  run.release()
end

-- what the EVO EXPRESS machine sells here (src/gen12/vending.lua): id -> true
machineStock = function(run, data)
  local V = run.loader.exports.national_dex_gen3._vending
  local out = {}
  for _, e in ipairs(V and V.machines or {}) do
    if e.m.id == "evo" then
      for _, tab in ipairs(V.stock(e.m, data)) do
        for _, x in ipairs(tab.entries) do out[x.id] = true end
      end
    end
  end
  return out
end

local function gen2(version)
  local run = H.load(version)
  for i = 1, math.min(5, #run.errors) do print("load error: " .. tostring(run.errors[i])) end
  T.eq(#run.errors, 0, version .. ": loads clean")
  local data = run.data
  local Mon = require("src.battle.gen2.Mon")
  local Evolution = require("src.core.gen2.Evolution")
  local GenItems = require("src.core.gen2.ItemEffects")

  local bad
  for id, def in pairs(data.pokemon) do
    if type(def) == "table" and def.evolutions then
      for _, row in ipairs(def.evolutions) do
        if not (data.pokemon[row.into] and (row.item == nil or data.items[row.item])) then
          bad = bad or (id .. " -> " .. tostring(row.into))
        end
      end
    end
  end
  T.check(bad == nil, version .. ": every row names a species and item the game has (" .. tostring(bad) .. ")")

  local function mon(species, level, dvs)
    local m = Mon.new(data, species, level)
    if dvs then m.dvs = dvs end
    return m
  end
  local function check(m, ctx)
    local entry = Evolution.checkMon(data, m, ctx or { timeOfDay = "DAY" })
    return entry and entry.into or nil
  end
  local function use(itemId, m)
    local rec = GenItems.recordFor(itemId, data)
    local out = rec and rec.use and rec.use({ mon = m, item = itemId, data = data })
    return out and out.used and out.evolution and out.evolution.into or nil
  end

  T.eq(check(mon("TURTWIG", 18)), "GROTLE", version .. ": Turtwig at 18")
  T.eq(use("SHINY_STONE", mon("TOGETIC", 20)), "TOGEKISS", version .. ": Shiny Stone (new) -> Togekiss")
  T.eq(use("SHINY_STONE", mon("PIDGEY", 20)), nil, version .. ": no effect on Pidgey")
  local zap = mon("ELECTABUZZ", 30)
  zap.item = "ELECTIRIZER"
  T.eq(check(zap, { link = true }), "ELECTIVIRE", version .. ": Electabuzz traded holding an Electirizer")
  local sneasel = mon("SNEASEL", 20)
  sneasel.item = "RAZOR_CLAW"
  T.eq(check(sneasel, { timeOfDay = "NITE" }), "WEAVILE", version .. ": Sneasel holding a Razor Claw at night")
  T.eq(check(sneasel, { timeOfDay = "DAY" }), nil, version .. ": not by day")
  local evolved = Evolution.apply(data, sneasel, { method = "EVOLVE_LEVEL", into = "WEAVILE", level = 1 })
  T.eq(evolved and evolved.item, nil, version .. ": the Razor Claw is used up")
  local budew = mon("BUDEW", 10)
  budew.happiness = 220
  T.eq(check(budew, { timeOfDay = "DAY" }), "ROSELIA", version .. ": a happy Budew by day")
  T.eq(check(budew, { timeOfDay = "NITE" }), nil, version .. ": not at night")
  local rockruff = mon("ROCKRUFF", 25)
  -- the dusk hour (19:00-20:00, the device's, as Gold's own time of day is) outranks night
  T.eq(check(rockruff, { timeOfDay = "NITE" }), Clock.isDusk(nil, "device") and "LYCANROC_DUSK"
    or "LYCANROC_MIDNIGHT", version .. ": Rockruff at night -> Midnight")
  T.eq(check(rockruff, { timeOfDay = "DAY" }), Clock.isDusk(nil, "device") and "LYCANROC_DUSK" or "LYCANROC",
    version .. ": by day -> Midday")
  T.eq(check(mon("COMBEE", 21, lowDvs(0, 0))), "VESPIQUEN", version .. ": a female Combee")
  T.eq(check(mon("COMBEE", 21, lowDvs(15, 15))), nil, version .. ": a male one never")
  local tyrogue = mon("TYROGUE", 20)
  tyrogue.stats.attack, tyrogue.stats.defense = 30, 40
  T.eq(check(tyrogue), "HITMONCHAN", version .. ": Gold's own Tyrogue")
  local primeape = mon("PRIMEAPE", 35)
  for _ = 1, 19 do Runtime.emit("battle.move_used", { user = { mon = primeape }, moveId = "RAGE" }) end
  T.eq(check(primeape), nil, version .. ": Primeape after Rage x 19")
  Runtime.emit("battle.move_used", { user = { mon = primeape }, moveId = "RAGE" })
  T.eq(check(primeape), "ANNIHILAPE", version .. ": after Rage x 20")

  -- the items are held (hold / trade) or used (stone), and sold by the EVO EXPRESS machine
  local sells = machineStock(run, data)
  local missing
  for _, r in ipairs(itemRows) do
    if not r.carts.gen2 and not sells[r.id] then missing = missing or r.id end
  end
  T.check(missing == nil, version .. ": every new item in the EVO EXPRESS machine (" .. tostring(missing) .. ")")
  T.eq(data.items.RAZOR_CLAW and data.items.RAZOR_CLAW.pocket, "ITEM", version .. ": a Razor Claw is an item to hold")
  run.release()
end

for _, version in ipairs(H.versions()) do
  if H.GENERATION[version] == 1 then gen1(version) else gen2(version) end
end

T.finish("national_dex_gen3 Gen 1/2 evolutions")
