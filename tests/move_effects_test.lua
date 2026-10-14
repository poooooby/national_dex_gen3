-- Standalone: luajit mods/national_dex_gen3/tests/move_effects_test.lua [game] (from the gen1recomp
-- root; needs that cart imported, FireRed by default).
--
-- New move mechanics (src/move_effects.lua): status moves on effect byte 250 run their stat
-- changes and healing through the engine's effect dispatcher; attacks apply their extra (stat
-- changes, status, flinch, drain, recoil) after the hit lands.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"

local data = H.gen3Data(GAME)
local Pokemon = require("src.core.game3.pokemon")
local Moves = require("src.core.game3.battle.moves")
do
  local pack = GAME .. "/data/generated/gba/pokemon/battle_moves.lua"
  Moves._rom = dofile(pack).moves
  Moves._romLoaded = true
  Pokemon._battleMoves = dofile(pack).moves
  Pokemon._romMoveNames = Pokemon._romMoveNames or Pokemon._moveNames
  data.gen3Moves = Moves
end
-- the hit itself stands in: it lands for 40 (what follows a landed hit is under test)
local Hit = require("src.core.game3.battle.effects.hit")
Hit.run = function(M) M.targetDamaged, M.hpDealt = true, 40 end

local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.events:emit("game.ready", {})

local Adapter = require("src.core.game3.battle.adapter")
local State = require("src.core.game3.battle.state")
local Effects = require("src.core.game3.battle.effects")
local EffectIds = require("src.core.game3.battle.effect_ids")
Adapter.textSink = function(id) return id end

local byId = {}
for _, r in ipairs(dofile("mods/national_dex_gen3/data/moves.lua")) do byId[r.id] = r end
local function num(id) return byId[id].index end

local function mon(extra)
  local m = { species = 25, level = 50, hp = 150, maxHp = 150, moves = { 33 }, pp = { 35 },
              attack = 100, defense = 100, spAtk = 100, spDef = 100, speed = 100, personality = 0 }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end
local function battle(p, f)
  local st = State.new({ wild = true, playerParty = { p or mon() }, foeMon = f or mon({ species = 16 }) })
  local said = {}
  local ad = Adapter.new(st, function(t) said[#said + 1] = tostring(t) end)
  ad.roll = function(_, lo) return lo end                    -- every chance comes up
  return st, ad, said
end

T.eq(EffectIds.STATUS_SETUP[250], "NATIONAL_DEX_GEN3_MOVE_EFFECT", "effect byte 250 is this mod's handler")
T.check(Moves._rom[num("NASTY_PLOT")] and Moves._rom[num("NASTY_PLOT")].effect == 250, "Nasty Plot runs on it")

local function status(id, st, ad, user, target)
  local M = { mnum = num(id), adapter = ad, attackAnimation = function() end }
  return Effects.run("NATIONAL_DEX_GEN3_MOVE_EFFECT", ad, user or st.player, target or st.enemy,
    Moves._rom[num(id)], num(id), M)
end

-- ------- status moves
do
  local st, ad = battle()
  T.check(status("NASTY_PLOT", st, ad) == true, "Nasty Plot is handled")
  T.eq(st.player.stages.spAtk, 2, "and sharply raises SP. ATK")
end
do
  local st, ad = battle()
  status("SHIFT_GEAR", st, ad)
  T.eq(st.player.stages.attack, 1, "Shift Gear: ATTACK +1")
  T.eq(st.player.stages.speed, 2, "and SPEED +2")
end
do
  local st, ad = battle()
  status("NOBLE_ROAR", st, ad)
  T.eq(st.enemy.stages.attack, -1, "Noble Roar lowers the foe's ATTACK")
  T.eq(st.enemy.stages.spAtk, -1, "and SP. ATK")
  T.eq(st.player.stages.attack, 0, "not the user's")
end
do
  local st, ad = battle(mon({ hp = 50 }))
  status("SHORE_UP", st, ad)
  T.eq(st.player.mon.hp, 125, "Shore Up heals half")
  local st2, ad2 = battle(mon({ hp = 50 }))
  st2.weather = "SAND"
  status("SHORE_UP", st2, ad2)
  T.eq(st2.player.mon.hp, 150, "and more in a sandstorm")
end

-- ------- attacks: after the hit lands
local function hit(id, st, ad)
  local M = { mnum = num(id), adapter = ad, st = st, user = st.player, target = st.enemy,
              move = Moves._rom[num(id)], tryFaintUser = function() end }
  Hit.run(M)
  return M
end
do
  local st, ad = battle()
  hit("CLOSE_COMBAT", st, ad)
  T.eq(st.player.stages.defense, -1, "Close Combat lowers the user's DEFENSE")
  T.eq(st.player.stages.spDef, -1, "and SP. DEF")
  T.eq(st.enemy.stages.defense, 0, "not the foe's")
end
do
  local st, ad = battle()
  hit("FLAME_CHARGE", st, ad)
  T.eq(st.player.stages.speed, 1, "Flame Charge raises the user's SPEED")
end
do
  local st, ad = battle()
  hit("LUNGE", st, ad)
  T.eq(st.enemy.stages.attack, -1, "Lunge lowers the foe's ATTACK")
end
do
  local st, ad = battle(mon({ hp = 100 }))
  hit("DRAINING_KISS", st, ad)
  T.eq(st.player.mon.hp, 130, "Draining Kiss heals 75% of the 40 dealt")
end
do
  local st, ad = battle()
  hit("FLARE_BLITZ", st, ad)
  T.eq(st.player.mon.hp, 150 - 13, "Flare Blitz: recoil of a third of the 40 dealt")
  T.eq(ad:status(st.enemy), "BRN", "and its burn chance can burn")
end
do
  local st, ad = battle()
  hit("FIRE_FANG", st, ad)
  T.eq(ad:status(st.enemy), "BRN", "Fire Fang can burn")
end

run.release()
T.finish("national_dex_gen3 new move mechanics (" .. GAME .. ")")
