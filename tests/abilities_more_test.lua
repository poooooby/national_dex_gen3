-- Standalone: luajit mods/national_dex_gen3/tests/abilities_more_test.lua [game] (from the gen1recomp
-- root; needs that cart imported, FireRed by default).
--
-- The rest of the newer abilities on Gen 3 (src/abilities_more.lua), through the battle engine's
-- own functions: whole moves run through Engine.resolveMove (every roll at its low end: moves hit,
-- added effects happen, no critical hits, the damage roll at 100).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"

local data = H.gen3Data(GAME)
H.useCart(GAME)
local Moves = require("src.core.game3.battle.moves")
data.gen3Moves = Moves

local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
pcall(require("src.mods.Gen3Compat").applyMerged, { mods = run.loader, data = data })
run.loader.events:emit("game.ready", {})

local Adapter = require("src.core.game3.battle.adapter")
local Ab = require("src.core.game3.battle.abilities")
local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Battle = require("src.core.game3.battle")
local HeldItems = require("src.core.game3.battle.held_items")
local StatusChip = require("src.core.game3.battle.status")
local Pokemon = require("src.core.game3.pokemon")
local Damage = require("src.core.game3.battle.damage")
Adapter.textSink = function(id) return id end
local RealAbilities = Ab.__ndxMoreHub and Ab.__ndxMoreHub.C and Ab.__ndxMoreHub.C.RA

-- ------- names and numbers
local named = 0
for _, d in ipairs(dofile("mods/national_dex_gen3/data/abilities.lua").defs) do
  if d.id >= 130 and Adapter.ABILITY_BY_ID[d.id] == d.key and Pokemon.abilityName(d.id) == d.name then named = named + 1 end
end
T.eq(named, 126, "the 126 abilities have their numbers and names")
T.eq(Ab.id("MOLD_BREAKER") >= 130, true, "the battle knows them by name")

local function mon(species, extra)
  local m = { species = species or 25, level = 50, hp = 150, maxHp = 150, moves = { 33 }, pp = { 35 },
              attack = 100, defense = 100, spAtk = 100, spDef = 100, speed = 100, personality = 0 }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end
local function low(_, lo) return lo end
-- a battle with every roll low, the damage roll (the battle's rng) at its top
local function battle(p, f)
  local st = State.new({ wild = true, playerParty = { p or mon() }, foeMon = f or mon(16) })
  st.turn = 2
  -- the damage roll (85-100) at its top, no critical hits (0-n), every other roll at its low end
  st.rng = function(lo, hi) if lo == 85 or lo == 0 then return hi end return lo end
  local ad = Adapter.new(st, function() end)
  ad.roll = low
  Battle._adapter = ad
  return st, ad
end
local function use(st, ad, user, target, id)
  return Engine.resolveMove(user, target, id, 1, ad, st, {})
end
-- the HP the foe lost to one move of the player's
local function dealt(pAb, fAb, move, pExtra, fExtra, prep)
  local p, f = mon(pExtra and pExtra.species or 25, pExtra), mon(fExtra and fExtra.species or 16, fExtra)
  p.ability, f.ability = pAb or p.ability, fAb or f.ability
  local st, ad = battle(p, f)
  if prep then prep(st, ad) end
  local hp = ad:hp(st.enemy)
  use(st, ad, st.player, st.enemy, move)
  return hp - ad:hp(st.enemy), st, ad
end
local TACKLE, EMBER, GROWL, EARTHQUAKE, FLAMETHROWER, FURY_ATTACK, IRON_TAIL = 33, 52, 45, 89, 53, 31, 231
local QUICK_ATTACK, TOXIC, SWORDS_DANCE, GIGA_DRAIN = 98, 92, 14, 202
local GASTLY, DRAGONITE, MAGNEMITE = 92, 149, 81

-- ------- abilities set aside
T.eq(dealt(nil, "LEVITATE", EARTHQUAKE, nil, { species = GASTLY }), 0, "Levitate: Earthquake misses (control)")
T.check(dealt("MOLD_BREAKER", "LEVITATE", EARTHQUAKE, nil, { species = GASTLY }) > 0, "MOLD_BREAKER: Earthquake hits a Levitate Pokemon")
T.check(dealt("TERAVOLT", "LEVITATE", EARTHQUAKE, nil, { species = GASTLY }) > 0, "TERAVOLT too")
do
  local st, ad = battle(mon(25, { ability = "NEUTRALIZING_GAS" }), mon(16, { ability = "INTIMIDATE" }))
  Ab.switchIn(ad, st.player)
  T.eq(ad:abilityOf(st.enemy), nil, "NEUTRALIZING_GAS: the foe's ability is gone")
  T.eq(ad:abilityOf(st.player), "NEUTRALIZING_GAS", "but not its own")
end

-- ------- damage
local plainTackle = dealt(nil, nil, TACKLE)
T.check(plainTackle > 0, "Tackle lands (" .. plainTackle .. ")")
T.check(dealt("STEELWORKER", nil, IRON_TAIL) > dealt(nil, nil, IRON_TAIL), "STEELWORKER: Steel moves hit harder")
T.check(dealt(nil, "FUR_COAT", TACKLE) < plainTackle, "FUR_COAT: physical hits deal less")
T.check(dealt("SWORD_OF_RUIN", nil, TACKLE) > plainTackle, "SWORD_OF_RUIN: the foe's DEFENSE is down")
T.check(dealt(nil, "TABLETS_OF_RUIN", TACKLE) < plainTackle, "TABLETS_OF_RUIN: the attacker's ATTACK is down")
T.check(dealt(nil, "SHADOW_SHIELD", TACKLE) < plainTackle, "SHADOW_SHIELD: less damage at full HP")
T.check(dealt("REFRIGERATE", nil, TACKLE, nil, { species = DRAGONITE }) > 2 * dealt(nil, nil, TACKLE, nil, { species = DRAGONITE }),
  "REFRIGERATE: Tackle is an Ice move against Dragonite")
T.eq(dealt(nil, nil, TACKLE, nil, { species = GASTLY }), 0, "Tackle doesn't touch a Ghost (control)")
T.check(dealt("SCRAPPY", nil, TACKLE, nil, { species = GASTLY }) > 0, "SCRAPPY: it does")
T.check(dealt("SKILL_LINK", nil, FURY_ATTACK) > 2 * dealt(nil, nil, FURY_ATTACK), "SKILL_LINK: Fury Attack strikes 5 times")
do
  local screened = function(st) st.enemySide.expReflectTurns = 5 end
  T.check(dealt(nil, nil, TACKLE, nil, nil, screened) < plainTackle, "Reflect halves Tackle (control)")
  T.eq(dealt("INFILTRATOR", nil, TACKLE, nil, nil, screened), plainTackle, "INFILTRATOR: Reflect doesn't count")
end
do
  local boosted = function(st) st.player.stages.attack = 6 end
  T.eq(dealt(nil, "UNAWARE", TACKLE, nil, nil, boosted), dealt(nil, "UNAWARE", TACKLE), "UNAWARE: the attacker's +6 doesn't count")
end
do
  local d, st, ad = dealt("SHEER_FORCE", nil, FLAMETHROWER)
  local d0, st0, ad0 = dealt(nil, nil, FLAMETHROWER)
  T.check(d > d0, "SHEER_FORCE: Flamethrower hits harder")
  T.eq(ad:status(st.enemy), nil, "and burns nothing")
  T.eq(ad0:status(st0.enemy), "BRN", "(it burns without: every roll is low)")
end
do
  local d, st, ad = dealt(nil, "DISGUISE", TACKLE)
  T.eq(d, math.floor(150 / 8), "DISGUISE: the first hit only costs 1/8 HP")
  local hp = ad:hp(st.enemy)
  use(st, ad, st.player, st.enemy, TACKLE)
  T.eq(hp - ad:hp(st.enemy), plainTackle, "and the next hit lands in full")
end
do
  local _, st, ad = dealt(nil, "INNARDS_OUT", TACKLE, { attack = 400 }, { hp = 30 })
  T.eq(ad:hp(st.player), 150 - 30, "INNARDS_OUT: the attacker loses the HP it had left")
end

-- ------- absorbing
do
  local d, st = dealt(nil, "WELL_BAKED_BODY", EMBER)
  T.eq(d, 0, "WELL_BAKED_BODY: Fire does nothing")
  T.eq(st.enemy.stages.defense, 2, "and raises DEFENSE two stages")
  local _, st2, ad2 = dealt(nil, "EARTH_EATER", EARTHQUAKE, nil, { species = 25, hp = 100 })
  T.eq(ad2:hp(st2.enemy), 137, "EARTH_EATER: Ground restores 1/4 HP")
end

-- ------- after a hit
do
  local _, st = dealt(nil, "GOOEY", TACKLE)
  T.eq(st.player.stages.speed, -1, "GOOEY: contact lowers the attacker's SPEED")
  local _, st2, ad2 = dealt(nil, "MUMMY", TACKLE)
  T.eq(ad2:abilityOf(st2.player), "MUMMY", "MUMMY: contact passes it on")
  local _, st3 = dealt(nil, "PICKPOCKET", TACKLE, { item = 1 })
  T.check(st3.enemy.item == 1 and (st3.player.item or 0) == 0, "PICKPOCKET: takes the attacker's item")
  local _, st4 = dealt(nil, "COTTON_DOWN", EMBER)
  T.eq(st4.player.stages.speed, -1, "COTTON_DOWN: any hit lowers the attacker's SPEED")
  local _, st5 = dealt(nil, "TOXIC_DEBRIS", TACKLE)
  T.eq(st5.playerSide.__ndx and st5.playerSide.__ndx.toxicSpikes, 1, "TOXIC_DEBRIS: poison spikes on the attacker's side")
  local _, st6 = dealt(nil, "BERSERK", TACKLE, { attack = 200 }, { hp = 90 })
  T.eq(st6.enemy.stages.spAtk, 1, "BERSERK: dropping to half HP raises SP. ATK")
  local _, st7 = dealt(nil, "STEAM_ENGINE", EMBER)
  T.eq(st7.enemy.stages.speed, 6, "STEAM_ENGINE: Fire maxes SPEED")
  local _, st8, ad8 = dealt(nil, "WANDERING_SPIRIT", TACKLE, { ability = "STATIC" })
  T.check(ad8:abilityOf(st8.player) == "WANDERING_SPIRIT" and ad8:abilityOf(st8.enemy) == "STATIC",
    "WANDERING_SPIRIT: swaps on contact")
  local _, st9 = dealt("MAGICIAN", nil, EMBER, nil, { item = 1 })
  T.check(st9.player.item == 1 and (st9.enemy.item or 0) == 0, "MAGICIAN: takes the target's item")
  local _, st10, ad10 = dealt("TOXIC_CHAIN", nil, TACKLE)
  T.eq(ad10:status(st10.enemy), "TOX", "TOXIC_CHAIN: badly poisons")
end

-- ------- stat changes
do
  local _, st = dealt(nil, "CONTRARY", GROWL)
  T.eq(st.enemy.stages.attack, 1, "CONTRARY: Growl raises ATTACK")
  local _, st2 = dealt(nil, "SIMPLE", GROWL)
  T.eq(st2.enemy.stages.attack, -2, "SIMPLE: Growl lowers it two stages")
  local _, st3 = dealt(nil, "FULL_METAL_BODY", GROWL)
  T.eq(st3.enemy.stages.attack, 0, "FULL_METAL_BODY: no stat loss")
  local _, st4 = dealt(nil, "OPPORTUNIST", SWORDS_DANCE)
  T.eq(st4.enemy.stages.attack, 2, "OPPORTUNIST: copies the foe's Swords Dance")
end
do
  local st, ad = battle(mon(25, { ability = "INTIMIDATE" }), mon(16, { ability = "GUARD_DOG" }))
  st.player.expIntimidatePending = true
  Ab.runIntimidate(ad)
  T.eq(st.enemy.stages.attack, 1, "GUARD_DOG: Intimidate raises ATTACK")
  local st2, ad2 = battle(mon(25, { ability = "INTIMIDATE" }), mon(16, { ability = "SCRAPPY" }))
  st2.player.expIntimidatePending = true
  Ab.runIntimidate(ad2)
  T.eq(st2.enemy.stages.attack, 0, "SCRAPPY: Intimidate does nothing")
end

-- ------- status
do
  local _, st, ad = dealt(nil, nil, TOXIC, nil, { species = MAGNEMITE })
  T.eq(ad:status(st.enemy), nil, "Toxic doesn't poison a Steel type (control)")
  local _, st2, ad2 = dealt("CORROSION", nil, TOXIC, nil, { species = MAGNEMITE })
  T.eq(ad2:status(st2.enemy), "TOX", "CORROSION: it does")
  local st3, ad3 = battle(mon(25), mon(16, { ability = "PURIFYING_SALT" }))
  T.eq((ad3:canApplyStatus(st3.enemy, "PAR", st3.player)), false, "PURIFYING_SALT: no status")
  local st4, ad4 = battle(mon(25), mon(16, { ability = "PASTEL_VEIL" }))
  T.check(not ad4:canApplyStatus(st4.enemy, "PSN", st4.player) and ad4:canApplyStatus(st4.enemy, "PAR", st4.player),
    "PASTEL_VEIL: no poison, other problems as usual")
  local _, st5 = dealt(nil, "GOOD_AS_GOLD", GROWL)
  T.eq(st5.enemy.stages.attack, 0, "GOOD_AS_GOLD: Growl does nothing")
  T.eq(dealt(nil, "QUEENLY_MAJESTY", QUICK_ATTACK), 0, "QUEENLY_MAJESTY: Quick Attack fails")
  T.check(dealt(nil, "QUEENLY_MAJESTY", TACKLE) > 0, "but Tackle lands")
end

-- ------- indirect damage
do
  local st, ad = battle(mon(25, { ability = "MAGIC_GUARD" }), mon(16))
  st.player.status = "PSN"
  StatusChip.tickChip(st.player, ad)
  T.eq(ad:hp(st.player), 150, "MAGIC_GUARD: no poison damage")
  local st2, ad2 = battle(mon(25), mon(16))
  st2.player.status = "PSN"
  StatusChip.tickChip(st2.player, ad2)
  T.eq(ad2:hp(st2.player), 150 - 18, "(control: 1/8)")
  local st3, ad3 = battle(mon(25, { ability = "OVERCOAT" }), mon(16))
  ad3:sayText("STRINGID_PKMNBUFFETEDBYSANDSTORM", { atk = st3.player })
  ad3:applyHpLoss(st3.player, 9)
  T.eq(ad3:hp(st3.player), 150, "OVERCOAT: no sandstorm damage")
end

-- ------- entering battle
do
  local st, ad = battle(mon(25, { ability = "INTREPID_SWORD" }), mon(16))
  Ab.switchIn(ad, st.player)
  T.eq(st.player.stages.attack, 1, "INTREPID_SWORD: ATTACK +1 on entry")
  st.player.stages.attack = 0
  Ab.switchIn(ad, st.player)
  T.eq(st.player.stages.attack, 0, "once per battle")
  local st2, ad2 = battle(mon(25, { ability = "DOWNLOAD" }), mon(16, { defense = 200, spDef = 50 }))
  Ab.switchIn(ad2, st2.player)
  T.eq(st2.player.stages.spAtk, 1, "DOWNLOAD: the lower SP. DEF raises SP. ATK")
  local st3, ad3 = battle(mon(25, { ability = "ELECTRIC_SURGE" }), mon(16))
  Ab.switchIn(ad3, st3.player)
  T.eq(st3.__ndxField and st3.__ndxField.terrain, "ELECTRIC", "ELECTRIC_SURGE: Electric Terrain")
  local st4, ad4 = battle(mon(25, { ability = "SCREEN_CLEANER" }), mon(16))
  st4.enemySide.expReflectTurns = 3
  Ab.switchIn(ad4, st4.player)
  T.eq(st4.enemySide.expReflectTurns, nil, "SCREEN_CLEANER: Reflect is gone")
  local st5, ad5 = battle(mon(25, { ability = "SLOW_START" }), mon(16))
  Ab.switchIn(ad5, st5.player)
  T.eq(RealAbilities.effectiveSpeed(ad5, st5.player), 50, "SLOW_START: SPEED halved")
end

-- ------- speed, priority, turn order
do
  local st, ad = battle(mon(25, { ability = "UNBURDEN", item = 1 }), mon(16))
  Engine.switchInEffects(st, ad, st.player, {})
  st.player.item = 0
  T.eq(RealAbilities.effectiveSpeed(ad, st.player), 200, "UNBURDEN: SPEED doubles once the item is gone")
  T.eq(RealAbilities.priorityOf(ad, st.player, Moves.get(GIGA_DRAIN)), 0, "Giga Drain: priority 0")
  st.player.ability = "TRIAGE"
  T.eq(RealAbilities.priorityOf(ad, st.player, Moves.get(GIGA_DRAIN)), 3, "TRIAGE: +3")
  local st2 = battle(mon(25, { ability = "QUICK_DRAW", speed = 10 }), mon(16, { speed = 200 }))
  T.eq(run.loader.hooks:call("battle.turn_order", function() return false end, st2.player, { power = 40, priority = 0 },
    st2.enemy, { power = 40, priority = 0 }, { battle = st2 }), true, "QUICK_DRAW: the slower one moves first")
end

-- ------- held items
do
  local st = battle(mon(25, { ability = "KLUTZ", item = 200 }), mon(16))
  st.player.item = 200
  T.eq((HeldItems.of(st.player, "damage", st)), 0, "KLUTZ: the held item does nothing")
end

-- ------- the end of the turn
do
  local st, ad = battle(mon(25, { ability = "BAD_DREAMS" }), mon(16))
  ad:applyStatus(st.enemy, "SLP", nil, { force = true, turns = 3 })
  Ab.endTurn(ad, st.player)
  T.eq(ad:hp(st.enemy), 150 - 18, "BAD_DREAMS: a sleeping foe loses 1/8")
end

-- ------- forms
do
  local st, ad = battle(mon(25, { ability = "STANCE_CHANGE" }), mon(16))
  use(st, ad, st.player, st.enemy, TACKLE)
  T.check(st.player.__ndxStat ~= nil and st.player.__ndxStat.attack > 100, "STANCE_CHANGE: Blade Forme to attack")
end

-- ------- more damage
local WATER_GUN, WATER_PULSE, HYPER_VOICE, BITE, THUNDERBOLT, DRAGON_CLAW, SLASH, LICK = 55, 352, 304, 44, 85, 337, 163, 122
local function more(ab, move, control)
  return dealt(ab, nil, move, nil, { species = 25 }) > dealt(nil, nil, move, nil, { species = 25 })
end
T.check(more("MEGA_LAUNCHER", WATER_PULSE), "MEGA_LAUNCHER: Water Pulse hits harder")
T.check(more("PUNK_ROCK", HYPER_VOICE), "PUNK_ROCK: Hyper Voice hits harder")
T.check(dealt(nil, "PUNK_ROCK", HYPER_VOICE) < dealt(nil, nil, HYPER_VOICE), "and takes less from it")
T.check(more("WATER_BUBBLE", WATER_GUN), "WATER_BUBBLE: Water moves hit harder")
T.check(dealt(nil, "WATER_BUBBLE", EMBER) < dealt(nil, nil, EMBER), "and Fire moves hit it softer")
T.check(more("TRANSISTOR", WATER_GUN) == false and more("TRANSISTOR", THUNDERBOLT), "TRANSISTOR: Electric moves only")
T.check(more("DRAGONS_MAW", DRAGON_CLAW), "DRAGONS_MAW: Dragon moves")
T.check(more("SHARPNESS", SLASH) and not more("SHARPNESS", TACKLE), "SHARPNESS: slicing moves only")
T.check(more("DARK_AURA", BITE), "DARK_AURA: Dark moves")
T.check(more("GORILLA_TACTICS", TACKLE), "GORILLA_TACTICS: ATTACK 1.5x")
T.check(dealt(nil, "PURIFYING_SALT", LICK, nil, { species = 25 }) < dealt(nil, nil, LICK, nil, { species = 25 }),
  "PURIFYING_SALT: Ghost moves hit softer")
T.check(dealt("STAKEOUT", nil, TACKLE, nil, nil, function(st) st.enemy.__ndxAbEntered = st.turn end) > plainTackle,
  "STAKEOUT: a foe that just came in takes double")
T.check(dealt("DEFEATIST", nil, TACKLE, { hp = 60 }) < dealt(nil, nil, TACKLE, { hp = 60 }), "DEFEATIST: weaker at half HP")
T.check(dealt("FLOWER_GIFT", nil, TACKLE, nil, nil, function(st) st.weather = "SUN" end) > plainTackle,
  "FLOWER_GIFT: stronger in sunshine")
T.check(dealt("MERCILESS", nil, TACKLE, nil, nil, function(st) st.enemy.status = "PSN"; st.enemy.mon.status = "PSN" end)
  > plainTackle, "MERCILESS: a critical hit against a poisoned foe")
do
  local p = mon(25, { ability = "SUPREME_OVERLORD" })
  local st = State.new({ wild = true, playerParty = { p, mon(25, { hp = 0 }), mon(25, { hp = 0 }) }, foeMon = mon(16) })
  st.turn = 2
  st.rng = function(lo, hi) if lo == 85 or lo == 0 then return hi end return lo end
  local ad = Adapter.new(st, function() end)
  ad.roll = low
  Battle._adapter = ad
  use(st, ad, st.player, st.enemy, TACKLE)
  T.check(150 - ad:hp(st.enemy) > plainTackle, "SUPREME_OVERLORD: fainted party members add power")
end
T.check(dealt(nil, nil, TACKLE, nil, nil, function(st) st.enemy.semiInvulnerable = "ON_AIR" end) == 0
  and dealt("NO_GUARD", nil, TACKLE, nil, nil, function(st) st.enemy.semiInvulnerable = "ON_AIR" end) > 0,
  "NO_GUARD: hits a Pokemon in the air")
do
  local d, st, ad = dealt(nil, "ICE_FACE", TACKLE)
  T.eq(d, 0, "ICE_FACE: the first physical hit does nothing")
  T.check(st.enemy.__ndxStat ~= nil and st.enemy.__ndxStat.speed > 100, "and the face breaks (SPEED 130)")
  T.check(dealt(nil, "ICE_FACE", EMBER) > 0, "a special hit lands")
end

-- ------- more after a hit
do
  local _, st = dealt(nil, "WATER_COMPACTION", WATER_GUN)
  T.eq(st.enemy.stages.defense, 2, "WATER_COMPACTION: Water raises DEFENSE two stages")
  local _, st2, ad2 = dealt(nil, "THERMAL_EXCHANGE", EMBER)
  T.check(st2.enemy.stages.attack == 1 and ad2:status(st2.enemy) == nil, "THERMAL_EXCHANGE: Fire raises ATTACK, no burn")
  local d3, st3 = dealt(nil, "WIND_RIDER", 16)
  T.check(d3 == 0 and st3.enemy.stages.attack == 1, "WIND_RIDER: Gust raises ATTACK instead")
  local _, st4 = dealt(nil, "ELECTROMORPHOSIS", TACKLE)
  T.eq(st4.enemy.expCharged, true, "ELECTROMORPHOSIS: a hit charges it")
  local _, st5 = dealt(nil, "CURSED_BODY", TACKLE)
  T.eq(st5.player.expDisabledMove, TACKLE, "CURSED_BODY: disables the move")
  local _, st6 = dealt(nil, "SAND_SPIT", TACKLE)
  T.eq(st6.weather, "SAND", "SAND_SPIT: a sandstorm")
  local _, st7 = dealt(nil, "SEED_SOWER", TACKLE)
  T.eq(st7.__ndxField and st7.__ndxField.terrain, "GRASSY", "SEED_SOWER: Grassy Terrain")
  local _, st8 = dealt(nil, "ANGER_SHELL", TACKLE, { attack = 200 }, { hp = 90 })
  T.check(st8.enemy.stages.attack == 1 and st8.enemy.stages.defense == -1, "ANGER_SHELL: riled up at half HP")
  local _, st9 = dealt(nil, "ANGER_POINT", TACKLE, nil, nil, function(st)
    st.rng = function(lo, hi) if lo == 85 then return hi end return lo end end)
  T.eq(st9.enemy.stages.attack, 6, "ANGER_POINT: a critical hit maxes ATTACK")
  local _, st10 = dealt(nil, "EMERGENCY_EXIT", TACKLE, { attack = 200 }, { hp = 90 })
  T.eq(st10.over, true, "EMERGENCY_EXIT: a wild one runs at half HP")
  local _, st11 = dealt("CHILLING_NEIGH", nil, TACKLE, { attack = 400 }, { hp = 10 })
  T.eq(st11.player.stages.attack, 1, "CHILLING_NEIGH: a KO raises ATTACK")
  local _, st12 = dealt("SOUL_HEART", nil, TACKLE, { attack = 400 }, { hp = 10 })
  T.eq(st12.player.stages.spAtk, 1, "SOUL_HEART: a faint raises SP. ATK")
  local _, st13, ad13 = dealt("POISON_PUPPETEER", nil, 40)          -- Poison Sting
  T.check(ad13:status(st13.enemy) == "PSN" and (st13.enemy.confusionTurns or 0) > 0, "POISON_PUPPETEER: poisoned and confused")
end
do
  local _, st = dealt(nil, "DANCER", SWORDS_DANCE)
  T.eq(st.enemy.stages.attack, 2, "DANCER: dances the Swords Dance too")
  T.eq(st.player.stages.attack, 2, "(the user's own +2)")
end

-- ------- more status
do
  local _, st, ad = dealt(nil, "AROMA_VEIL", 269)                   -- Taunt
  T.eq(st.enemy.expTauntedTurns, nil, "AROMA_VEIL: Taunt does nothing")
  local _, st2, ad2 = dealt(nil, nil, 79)                          -- Sleep Powder
  local _, st3, ad3 = dealt(nil, "OVERCOAT", 79)
  T.check(ad2:status(st2.enemy) == "SLP" and ad3:status(st3.enemy) == nil, "OVERCOAT: Sleep Powder does nothing")
  local st4, ad4 = battle(mon(25), mon(16, { ability = "COMATOSE" }))
  T.eq((ad4:canApplyStatus(st4.enemy, "BRN", st4.player)), false, "COMATOSE: no status")
end

-- ------- turn order and speed
do
  local st, ad = battle(mon(25, { ability = "MYCELIUM_MIGHT", speed = 200 }), mon(16, { speed = 10 }))
  T.eq(run.loader.hooks:call("battle.turn_order", function() return true end, st.player, { power = 0, priority = 0 },
    st.enemy, { power = 40, priority = 0 }, { battle = st }), false, "MYCELIUM_MIGHT: its status move goes last")
  local st2, ad2 = battle(mon(25, { ability = "SURGE_SURFER" }), mon(16))
  st2.__ndxField = { terrain = "ELECTRIC", terrainTurns = 3 }
  T.eq(RealAbilities.effectiveSpeed(ad2, st2.player), 200, "SURGE_SURFER: SPEED doubles on Electric Terrain")
  local st3, ad3 = battle(mon(25, { ability = "STEADFAST" }), mon(16))
  st3.player.flinched = true
  use(st3, ad3, st3.player, st3.enemy, TACKLE)
  T.eq(st3.player.stages.speed, 1, "STEADFAST: a flinch raises SPEED")
  local function acc(ab, extra)
    local st4 = battle(mon(25, { ability = ab }), mon(16, extra))
    return run.loader.hooks:call("battle.accuracy", function(c) return c.accuracy end,
      { battle = st4, user = st4.player, target = st4.enemy, accuracy = 100, move = { power = 40 } })
  end
  T.eq(acc("VICTORY_STAR"), 110, "VICTORY_STAR: 1.1x accuracy")
end

-- ------- entering battle and forms
do
  local st, ad = battle(mon(25, { ability = "ORICHALCUM_PULSE" }), mon(16))
  Ab.switchIn(ad, st.player)
  T.eq(st.weather, "SUN", "ORICHALCUM_PULSE: harsh sunlight")
  local st2, ad2 = battle(mon(25, { ability = "SUPERSWEET_SYRUP" }), mon(16))
  Ab.switchIn(ad2, st2.player)
  T.eq(st2.enemy.stages.evasion, -1, "SUPERSWEET_SYRUP: the foe's evasion falls")
  local st3, ad3 = battle(mon(25, { ability = "MIMICRY" }), mon(16))
  st3.__ndxField = { terrain = "PSYCHIC", terrainTurns = 3 }
  Ab.switchIn(ad3, st3.player)
  T.eq(st3.player.type1, 14, "MIMICRY: Psychic Terrain makes it Psychic")
  local st4, ad4 = battle(mon(25, { ability = "MULTITYPE" }), mon(16))
  Ab.switchIn(ad4, st4.player)
  T.eq(st4.player.type1, 0, "MULTITYPE: Normal without a Plate")
  local st5, ad5 = battle(mon(25, { ability = "SCHOOLING" }), mon(16))
  Ab.switchIn(ad5, st5.player)
  T.check(st5.player.__ndxStat ~= nil and st5.player.__ndxStat.attack > 100, "SCHOOLING: a school at full HP")
  local st6, ad6 = battle(mon(25, { ability = "HUNGER_SWITCH" }), mon(16))
  Ab.endTurn(ad6, st6.player)
  T.eq(st6.player.__ndxAbHangry, true, "HUNGER_SWITCH: Hangry Mode after a turn")
  local st7, ad7 = battle(mon(25, { ability = "ZERO_TO_HERO" }), mon(16))
  Ab.switchOut(ad7, st7.player)
  Ab.switchIn(ad7, st7.player)
  T.check(st7.player.__ndxStat ~= nil and st7.player.__ndxStat.attack > 100, "ZERO_TO_HERO: Hero Form after switching out")
end

-- ------- berries
do
  local ORAN = 139
  local function eat(ab, foeAb)
    local st, ad = battle(mon(25, { ability = ab, hp = 60, item = ORAN }), mon(16, { ability = foeAb }))
    st.player.item = ORAN
    HeldItems.normal(ad, st.player, false)
    return ad:hp(st.player), st
  end
  T.eq((eat(nil)), 70, "an Oran Berry restores 10 HP (control)")
  T.eq((eat("RIPEN")), 80, "RIPEN: 20")
  T.eq((eat("CHEEK_POUCH")), 120, "CHEEK_POUCH: and 1/3 more")
  T.eq((eat(nil, "UNNERVE")), 60, "UNNERVE: the foe can't eat it")
  local _, st = eat("CUD_CHEW")
  T.check(st.player.__ndxAbCud ~= nil, "CUD_CHEW: remembers the berry")
end
do
  local stM = battle(mon(25, { ability = "HEAVY_METAL" }), mon(16))
  local w = Damage.lowKickPower(stM.player.mon, stM.player)
  local stN = battle(mon(25), mon(16))
  T.check(w > Damage.lowKickPower(stN.player.mon, stN.player), "HEAVY_METAL: Low Kick hits it harder")
end

run.release()
T.finish("national_dex_gen3 more abilities (" .. GAME .. ")")
