-- Standalone: luajit mods/national_dex_gen3/tests/abilities_test.lua [game] (from the gen1recomp
-- root; needs that cart imported, FireRed by default).
--
-- Real abilities newer than Gen 3 (src/abilities.lua, data/abilities.lua): their names, numbers
-- and texts; the species that have them, including a Pokemon saved with its old Gen 3 ability;
-- and what they do, through the battle engine's own functions and hooks.
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

local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.events:emit("game.ready", {})
local api = run.loader.exports.national_dex_gen3

local Adapter = require("src.core.game3.battle.adapter")
local Ab = require("src.core.game3.battle.abilities")
local State = require("src.core.game3.battle.state")
local Damage = require("src.core.game3.battle.damage")
local Secondary = require("src.core.game3.battle.effects.secondary")
local Effects = require("src.core.game3.battle.effects")
local Types = require("src.core.game3.battle.types")
-- the battle hooks, as the game's runtime holds them
local Runtime = { call = function(name, vanilla, ...) return run.loader.hooks:call(name, vanilla, ...) end }
local SummaryData = require("src.core.game3.summary_data")
local ID = Types.ID
-- battle text as message ids (no text cache headlessly)
Adapter.textSink = function(id) return id end

-- ------- names, numbers, texts
T.eq(Adapter.ABILITY_BY_ID[78], "TECHNICIAN", "TECHNICIAN is ability 78")
T.eq(Pokemon.abilityName(78), "TECHNICIAN", "named in the game")
T.eq(Ab.id("TECHNICIAN"), 78, "the battle's id lookup knows it")
T.eq(SummaryData.abilityDescription(78, "TECHNICIAN"), "Powers up weak moves.", "the summary shows its text")

-- ------- who has it
local ambipom = api.slotOf("AMBIPOM")
T.eq(Pokemon.abilities(ambipom)[1], 78, "Ambipom's first ability is TECHNICIAN")
local function battle(playerMon, foeMon)
  local st = State.new({ wild = true, playerParty = { playerMon }, foeMon = foeMon })
  local said = {}
  local ad = Adapter.new(st, function(text) said[#said + 1] = tostring(text) end)
  return st, ad, said
end
local function mon(species, level, extra)
  local m = { species = species, level = level or 50, hp = 150, maxHp = 150, moves = { 33 }, pp = { 35 },
              attack = 100, defense = 100, spAtk = 100, spDef = 100, speed = 100, personality = 0 }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end
do
  -- a Pokemon saved before this (it stores the Gen 3 ability it was given: PICKUP, 53)
  local st, ad = battle(mon(ambipom, 50, { ability = 53, abilityNum = 0 }), mon(16, 50))
  T.eq(ad:abilityOf(st.player), "TECHNICIAN", "an Ambipom saved with PICKUP battles with TECHNICIAN")
end

-- battlers given an ability by name (a cart species without real abilities of its own)
local function withAbility(m, ab) m.ability = ab return m end

-- ------- Damage.base: power
local function dmg(attackerAb, defenderAb, moveId, weather)
  local st, ad = battle(withAbility(mon(25), attackerAb), withAbility(mon(16), defenderAb))
  st.weather = weather
  local d = Damage.calc(st.player, st.enemy, moveId, { adapter = ad, noRandom = true, forceCrit = false })
  return d
end
local QUICK_ATTACK, MACH_PUNCH, EMBER, TACKLE, BITE = 98, 183, 52, 33, 44
local function ratio(a, b) return math.floor(a / b * 100 + 0.5) / 100 end
T.check(math.abs(ratio(dmg("TECHNICIAN", nil, QUICK_ATTACK), dmg(nil, nil, QUICK_ATTACK)) - 1.5) < 0.12,
  "TECHNICIAN: a 40-power move hits about 1.5x")
T.eq(dmg("TECHNICIAN", nil, 89), dmg(nil, nil, 89), "TECHNICIAN leaves a 100-power move alone")
T.check(dmg("IRON_FIST", nil, MACH_PUNCH) > dmg(nil, nil, MACH_PUNCH), "IRON_FIST powers up Mach Punch")
T.eq(dmg("IRON_FIST", nil, TACKLE), dmg(nil, nil, TACKLE), "but not Tackle")
T.check(dmg("STRONG_JAW", nil, BITE) > dmg(nil, nil, BITE), "STRONG_JAW powers up Bite")
T.check(dmg("TOUGH_CLAWS", nil, TACKLE) > dmg(nil, nil, TACKLE), "TOUGH_CLAWS powers up a contact move")
T.check(dmg(nil, "HEATPROOF", EMBER) < dmg(nil, nil, EMBER), "HEATPROOF halves Fire damage")
T.check(dmg(nil, "DRY_SKIN", EMBER) > dmg(nil, nil, EMBER), "DRY_SKIN takes more from Fire")

-- ------- battle.damage: the final number
local function hooked(userAb, targetAb, info, targetHp, flags)
  local st, ad = battle(withAbility(mon(25), userAb), withAbility(mon(16, 50, { hp = targetHp or 150 }), targetAb))
  local Battle = require("src.core.game3.battle")
  Battle._adapter = ad
  local d = Runtime.call("battle.damage", function() return 100, info end,
    { battle = st, user = st.player, target = st.enemy, move = { flags = flags or 1 } })
  Battle._adapter = nil
  return d
end
local plain = { effectiveness = 1, stab = 1, critical = false, moveType = 0, physical = true }
T.eq(hooked("ADAPTABILITY", nil, { effectiveness = 1, stab = 1.5, moveType = 0 }), 133, "ADAPTABILITY: STAB 2x, not 1.5x")
T.eq(hooked("SNIPER", nil, { effectiveness = 1, stab = 1, critical = true, moveType = 0 }), 150, "SNIPER: critical hits 1.5x more")
T.eq(hooked("TINTED_LENS", nil, { effectiveness = 0.5, stab = 1, moveType = 0 }), 200, "TINTED_LENS doubles resisted hits")
T.eq(hooked(nil, "FILTER", { effectiveness = 2, stab = 1, moveType = 0 }), 75, "FILTER: super-effective hits 3/4")
T.eq(hooked(nil, "MULTISCALE", plain), 50, "MULTISCALE halves damage at full HP")
T.eq(hooked(nil, "MULTISCALE", plain, 100), 100, "but not once hurt")
T.eq(hooked(nil, "FLUFFY", plain), 50, "FLUFFY halves contact damage")
local fire = { effectiveness = 1, stab = 1, critical = false, moveType = 10, physical = false }
T.eq(hooked(nil, "FLUFFY", fire, nil, 0), 200, "FLUFFY doubles Fire damage (Flamethrower, no contact)")
T.eq(hooked(nil, "FLUFFY", fire, nil, 1), 100, "and a Fire contact move (Fire Punch) deals normal damage")
T.eq(hooked(nil, "FLUFFY", plain, nil, 0), 100, "a non-contact, non-Fire move is unchanged")
T.eq(hooked(nil, nil, plain), 100, "no ability, no change")

-- ------- switch-in, end of turn, switch-out
do
  local st, ad = battle(withAbility(mon(25), "SNOW_WARNING"), mon(16))
  Ab.switchIn(ad, st.player)
  T.eq(st.weather, "HAIL", "SNOW_WARNING starts hail")
end
do
  local st, ad = battle(withAbility(mon(25, 50, { hp = 100 }), "ICE_BODY"), mon(16))
  st.weather = "HAIL"
  Ab.endTurn(ad, st.player)
  T.eq(st.player.mon.hp, 109, "ICE_BODY heals 1/16 in hail")
end
do
  local st, ad = battle(withAbility(mon(25, 50, { hp = 60 }), "REGENERATOR"), mon(16))
  Ab.switchOut(ad, st.player)
  T.eq(st.player.mon.hp, 110, "REGENERATOR heals 1/3 on switching out")
end

-- ------- absorbing, contact, stat changes
local function M(st, ad, user, target, move)
  return { adapter = ad, st = st, user = user, target = target, move = move, moveType = move.type, anim = {},
           attackString = function() end, tryFaintUser = function() end, moveName = "MOVE" }
end
do
  local st, ad = battle(mon(25), withAbility(mon(16), "SAP_SIPPER"))
  local m = M(st, ad, st.player, st.enemy, { type = ID.GRASS, power = 40, flags = 0 })
  T.check(Ab.absorb(m) == true and m.noEffect, "SAP_SIPPER absorbs a Grass move")
  T.eq(st.enemy.stages.attack, 1, "and raises ATTACK")
end
do
  local st, ad = battle(mon(25), withAbility(mon(16), "BULLETPROOF"))
  local m = M(st, ad, st.player, st.enemy, { id = "SHADOW_BALL", type = ID.GHOST, power = 80, flags = 0 })
  T.check(Ab.absorb(m) == true and m.noEffect, "BULLETPROOF blocks Shadow Ball")
end
do
  local st, ad = battle(mon(25), withAbility(mon(16), "STAMINA"))
  local m = M(st, ad, st.player, st.enemy, { type = ID.NORMAL, power = 40, flags = 1 })
  m.targetDamaged = true
  Ab.onDamage(m)
  T.eq(st.enemy.stages.defense, 1, "STAMINA raises DEFENSE when hit")
end
do
  local st, ad = battle(mon(25), withAbility(mon(16), "IRON_BARBS"))
  local m = M(st, ad, st.player, st.enemy, { type = ID.NORMAL, power = 40, flags = 1 })
  m.targetDamaged = true
  Ab.onDamage(m)
  T.eq(st.player.mon.hp, 150 - 18, "IRON_BARBS hurts a contact attacker by 1/8")
end
do
  local st, ad = battle(withAbility(mon(25), "MOXIE"), mon(16, 50, { hp = 0 }))
  local m = M(st, ad, st.player, st.enemy, { type = ID.NORMAL, power = 40, flags = 1 })
  m.targetDamaged = true
  Ab.onDamage(m)
  T.eq(st.player.stages.attack, 1, "MOXIE raises ATTACK after a KO")
end
do
  local st, ad = battle(mon(25), withAbility(mon(16), "DEFIANT"))
  Secondary.changeStat(ad, st.enemy, "speed", -1, {})
  T.eq(st.enemy.stages.attack, 2, "DEFIANT: a stat cut sharply raises ATTACK")
end
do
  local st, ad = battle(mon(25), withAbility(mon(16), "BIG_PECKS"))
  T.eq(Secondary.changeStat(ad, st.enemy, "defense", -1, {}), "blocked", "BIG_PECKS stops a DEFENSE cut")
  T.eq(st.enemy.stages.defense, 0, "DEFENSE unchanged")
end

-- ------- turn order, status moves
do
  local st, ad = battle(withAbility(mon(25), "PRANKSTER"), mon(16))
  local Battle = require("src.core.game3.battle")
  Battle._adapter = ad
  local first = Runtime.call("battle.turn_order", function() return false end,
    st.player, { power = 0, priority = 0 }, st.enemy, { power = 40, priority = 0 }, { battle = st })
  T.check(first == true, "PRANKSTER: a status move goes first")
  first = Runtime.call("battle.turn_order", function() return false end,
    st.player, { power = 40, priority = 0 }, st.enemy, { power = 40, priority = 0 }, { battle = st })
  T.check(first == false, "but an attack does not")
  Battle._adapter = nil
end
do
  local st, ad = battle(mon(25), withAbility(mon(16), "LEAF_GUARD"))
  st.weather = "SUN"
  Effects.run("EXP_BURN_EFFECT", ad, st.player, st.enemy, { type = ID.FIRE, power = 0 }, 261)
  T.eq(ad:status(st.enemy), nil, "LEAF_GUARD: no burn in sunshine")
end

run.release()
T.finish("national_dex_gen3 real abilities (" .. GAME .. ")")
