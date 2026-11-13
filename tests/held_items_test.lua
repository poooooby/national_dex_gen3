-- Standalone: luajit mods/national_dex_gen3/tests/held_items_test.lua [game] (from the gen1recomp
-- root; needs that cart imported, FireRed by default).
--
-- The newer held items on the Gen 3 games (src/held/gen3.lua, src/held/effects.lua): registered at
-- their fixed numbers where the game lacks them, and what a few do through the battle's seams.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"

local data = H.gen3Data(GAME)
H.useCart(GAME)
local Moves = require("src.core.game3.battle.moves")
data.gen3Moves = Moves
local ItemsData = require("src.core.game3.items_data")
data.gen3Items = ItemsData
-- the hit itself stands in: 40 damage (what comes before and after it is under test)
local Hit = require("src.core.game3.battle.effects.hit")
Hit.run = function(M)
  M.targetDamaged, M.hpDealt = true, 40
  M.adapter:applyHpLoss(M.target, 40)
end

local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
pcall(require("src.mods.Gen3Compat").applyMerged, { mods = run.loader, data = data })
run.loader.events:emit("game.ready", {})
local api = run.loader.exports and run.loader.exports.national_dex_gen3 or (run.mods and run.mods[1] and run.mods[1].exports)
local held = api and api._held
T.check(held ~= nil, "the held items are installed")
local rows = dofile("mods/national_dex_gen3/data/held_items.lua")
local byId = {}
for _, r in ipairs(rows) do byId[r.id] = r end

-- registration
local items = run.loader.content and run.loader.content.items
local state = held and held.state or { byId = {}, byIndex = {} }
T.check(state.byId.LIFE_ORB and state.byId.CHOICE_SCARF and state.byId.FAIRY_GEM, "Gen 4-9 items are registered")
T.check(state.byId.CHOICE_BAND == nil and state.byId.LEFTOVERS == nil, "the game's own (Choice Band) stay its own")
local evoIndex = {}
for _, r in ipairs(dofile("mods/national_dex_gen3/data/items.lua")) do evoIndex[r.id] = r.index end
local function holdOf(id) local i = ItemsData.info(evoIndex[id]); return i and i.holdEffect end
T.eq(holdOf("RAZOR_CLAW"), 41, "Razor Claw (this mod's evolution item) raises critical hits as the Scope Lens does")
T.eq(holdOf("RAZOR_FANG"), 30, "Razor Fang flinches as the King's Rock does")
T.eq(ItemsData.info(byId.LUCK_INCENSE.index).holdEffect, 32, "Luck Incense doubles prize money as the Amulet Coin does")
T.eq(ItemsData.info(byId.PURE_INCENSE.index).holdEffect, 33, "Pure Incense keeps wild Pokemon away as the Cleanse Tag does")
T.eq(ItemsData.info(byId.LIFE_ORB.index) and ItemsData.info(byId.LIFE_ORB.index).name, "LIFE ORB", "Life Orb at its number")
T.eq(ItemsData.info(byId.CHOICE_SCARF.index) and ItemsData.info(byId.CHOICE_SCARF.index).holdEffect, 29,
  "Choice Scarf carries the Choice Band's lock")

local Adapter = require("src.core.game3.battle.adapter")
local State = require("src.core.game3.battle.state")
local Battle = require("src.core.game3.battle")
local Runtime = require("src.mods.Runtime")
Adapter.textSink = function(id) return id end
local function mon(extra)
  local m = { species = 25, level = 50, hp = 150, maxHp = 150, moves = { 33 }, pp = { 35 },
              attack = 100, defense = 100, spAtk = 100, spDef = 100, speed = 100, personality = 0 }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end
local function battle()
  local st = State.new({ wild = true, playerParty = { mon() }, foeMon = mon({ species = 25 }) })
  st.turn = 3
  local ad = Adapter.new(st, function() end)
  ad.roll = function(_, lo) return lo end
  Battle._adapter = ad
  return st, ad
end
local function damage(st, user, target, base, moveNum)
  return Runtime.call("battle.damage", function() return base, { effectiveness = 1, critical = false } end,
    { battle = st, user = user, target = target, move = Moves.get(moveNum or 33), moveNum = moveNum or 33 })
end
local function ctx(n, st, ad, user, target)
  return { mnum = n, moveId = n, slot = 1, adapter = ad, st = st, user = user, target = target,
           move = Moves.get(n), anim = {}, opts = {}, isMoveContext = true,
           attackString = function() end, ppReduce = function() end, tryFaintUser = function() end,
           attackAnimation = function() end, accuracyCheck = function() return true end }
end

local st, ad = battle()
st.player.item = byId.LIFE_ORB.index
T.eq(damage(st, st.player, st.enemy, 100), 130, "Life Orb: 1.3x")
st, ad = battle()
st.player.item = byId.CHOICE_SPECS.index
T.eq(damage(st, st.player, st.enemy, 100, 85), 150, "Choice Specs: 1.5x a special move (Thunderbolt)")
T.eq(damage(st, st.player, st.enemy, 100, 33), 100, "... not a physical one")
st, ad = battle()
st.enemy.item = byId.FOCUS_SASH.index
T.eq(damage(st, st.player, st.enemy, 999), 149, "Focus Sash: a full-HP holder keeps 1 HP")
T.eq(st.enemy.item, 0, "... and the sash is used up")
st, ad = battle()
st.enemy.item = byId.AIR_BALLOON.index
T.eq(damage(st, st.player, st.enemy, 100, 89), 0, "Air Balloon: Earthquake misses")
st, ad = battle()
st.enemy.item = byId.ROCKY_HELMET.index
Hit.run(ctx(33, st, ad, st.player, st.enemy))
T.eq(st.player.mon.hp, 150 - 25, "Rocky Helmet: a Tackle costs the attacker 1/6")
st, ad = battle()
st.enemy.item = byId.WEAKNESS_POLICY.index
st.enemy.type1, st.enemy.type2 = 10, 10                 -- Fire, so Water Gun is super effective
Hit.run(ctx(55, st, ad, st.player, st.enemy))
T.eq(st.enemy.stages.attack, 2, "Weakness Policy: +2 Attack after a super-effective hit")
st, ad = battle()
st.player.item = byId.CHOICE_SCARF.index
st, ad = battle()
st.player.item = byId.BLACK_SLUDGE.index
held.module._core:fire("endTurn", held.module.adapter(ad, held.module._env))
T.eq(st.player.mon.hp, 150 - math.floor(150 / 8), "Black Sludge hurts a holder that is not Poison")

-- Booster Energy: Quark Drive on without Electric Terrain, the item used up
st, ad = battle()
st.player.item = byId.BOOSTER_ENERGY.index
ad.abilityOf = function(_, b) return b == st.player and "QUARK_DRIVE" or nil end
require("src.core.game3.battle.engine").switchInEffects(st, ad, st.player, { spikes = true })
T.check(st.player.__ndxBooster == true and st.player.item == 0, "Booster Energy activates Quark Drive")
-- Grip Claw: a bind lasts 7 turns
st, ad = battle()
st.player.item = byId.GRIP_CLAW.index
st.enemy.expTrapTurns = 3
Hit.run(ctx(328, st, ad, st.player, st.enemy))
T.eq(st.enemy.expTrapTurns, 7, "Grip Claw: the bind lasts 7 turns")

Battle._adapter = nil
run.release()
T.finish("national_dex_gen3 held items (" .. GAME .. ")")
