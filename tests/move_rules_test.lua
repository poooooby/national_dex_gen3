-- Standalone: luajit mods/national_dex_gen3/tests/move_rules_test.lua [game] (from the gen1recomp
-- root; needs that cart imported, FireRed by default).
--
-- Move rules (src/move_rules.lua): power that depends on the battle, whose stats are used,
-- always-critical hits, moves that fail, and what follows the hit.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"

local data = H.gen3Data(GAME)
H.useCart(GAME)                               -- the engine reads the cart, as in a game
local Pokemon = require("src.core.game3.pokemon")
local Moves = require("src.core.game3.battle.moves")
data.gen3Moves = Moves                         -- the battle's own module, as a game binds it
-- the hit itself stands in: it lands for 40 (what comes before and after it is under test)
local Hit = require("src.core.game3.battle.effects.hit")
local hits = 0
local seenEvasion
Hit.run = function(M)
  hits = hits + 1
  seenEvasion = M.target.stages and M.target.stages.evasion
  M.targetDamaged, M.hpDealt = true, 40
  M.adapter:applyHpLoss(M.target, 40)
end

local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
-- as a game does after loading mods: the registries go into the live tables, and the engine
-- re-applies them after every reload (Gen3Compat)
pcall(require("src.mods.Gen3Compat").applyMerged, { mods = run.loader, data = data })
run.loader.events:emit("game.ready", {})

local Adapter = require("src.core.game3.battle.adapter")
local State = require("src.core.game3.battle.state")
local Damage = require("src.core.game3.battle.damage")
local Effects = require("src.core.game3.battle.effects")
Adapter.textSink = function(id) return id end

local byId = {}
for _, r in ipairs(dofile("mods/national_dex_gen3/data/moves.lua")) do byId[r.id] = r end
local function num(id) return type(id) == "number" and id or byId[id].index end

local function mon(extra)
  local m = { species = 25, level = 50, hp = 150, maxHp = 150, moves = { 33 }, pp = { 35 },
              attack = 100, defense = 100, spAtk = 100, spDef = 100, speed = 100, personality = 0 }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end
local function battle(p, f)
  local st = State.new({ wild = true, playerParty = { p or mon() }, foeMon = f or mon({ species = 16 }) })
  st.turn = 3
  local said = {}
  local ad = Adapter.new(st, function(t) said[#said + 1] = tostring(t) end)
  ad.roll = function(_, lo) return lo end
  return st, ad, said
end
local function calc(id, st, ad, user, target)
  return Damage.calc(user or st.player, target or st.enemy, Moves.get(num(id)),
    { adapter = ad, noRandom = true, forceCrit = false })
end
local function power(id, st, ad, user, target)
  local _, info = calc(id, st, ad, user, target)
  return info and info.power
end

-- ------- power
do
  local st, ad = battle(nil, mon({ species = 1 }))
  T.eq(power("HEX", st, ad), 65, "Hex: 65 on a healthy foe")
  st.enemy.status = "PAR"; st.enemy.mon.status = "PAR"
  T.eq(power("HEX", st, ad), 130, "and 130 on one with a status problem")
  T.eq(power("VENOSHOCK", st, ad), 65, "Venoshock: no boost for paralysis")
  st.enemy.status = "PSN"; st.enemy.mon.status = "PSN"
  T.eq(power("VENOSHOCK", st, ad), 130, "but double on a poisoned foe")
end
do
  local st, ad = battle(nil, mon({ species = 16, hp = 70 }))
  T.eq(power("BRINE", st, ad), 130, "Brine doubles under half HP")
end
do
  local st, ad = battle()
  st.player.item = 0
  T.eq(power("ACROBATICS", st, ad), 110, "Acrobatics doubles with no held item")
  st.player.item = 1
  T.eq(power("ACROBATICS", st, ad), 55, "and not with one")
end
do
  local st, ad = battle()
  st.player.stages.attack, st.player.stages.speed = 2, 1
  T.eq(power("STORED_POWER", st, ad), 80, "Stored Power: 20 + 20 per boost")
  st.enemy.stages.defense = 3
  T.eq(power("PUNISHMENT", st, ad), 120, "Punishment: 60 + 20 per foe boost")
end
do
  local st, ad = battle(nil, mon({ species = 16, speed = 400 }))
  T.eq(power("GYRO_BALL", st, ad), 101, "Gyro Ball: 25 x foe speed / own speed + 1")
  T.eq(power("ELECTRO_BALL", st, ad), 40, "Electro Ball: 40 against a much faster foe")
  st.enemy.mon.speed = 20
  T.eq(power("ELECTRO_BALL", st, ad), 150, "and 150 against a much slower one")
end
do
  local st, ad = battle(nil, mon({ species = 16, hp = 75 }))
  T.eq(power("CRUSH_GRIP", st, ad), 60, "Crush Grip scales with the foe's HP")
end
do
  -- Snorlax (460 kg) on Pidgey (1.8 kg)
  local st, ad = battle(mon({ species = 143 }))
  T.eq(power("HEAVY_SLAM", st, ad), 120, "Heavy Slam: 120 on a far lighter foe")
  local st2, ad2 = battle(mon({ species = 16 }), mon({ species = 143 }))
  T.eq(power("HEAVY_SLAM", st2, ad2), 40, "and 40 on a heavier one")
end
do
  local st, ad = battle(mon({ moves = { num("TRUMP_CARD") }, pp = { 1 } }))
  T.eq(power("TRUMP_CARD", st, ad), 80, "Trump Card: 80 with 1 PP left")
end
do
  local st, ad = battle()
  T.eq(power("PAYBACK", st, ad), 50, "Payback: 50 if the foe has not moved")
  st.enemy.__ndxMovedTurn = st.turn
  T.eq(power("PAYBACK", st, ad), 100, "and 100 once it has")
  T.eq(power("BOLT_BEAK", st, ad), 85, "Bolt Beak: no boost after the foe moved")
  st.enemy.__ndxMovedTurn = nil
  T.eq(power("BOLT_BEAK", st, ad), 170, "but double before it")
end
do
  local st, ad = battle()
  T.eq(power("ASSURANCE", st, ad), 60, "Assurance: 60 on an unhurt foe")
  st.enemy.damageTakenThisTurn = 10
  T.eq(power("ASSURANCE", st, ad), 120, "and 120 if it was hurt this turn")
end
do
  local st, ad = battle()
  st.turn = 2
  run.loader.events:emit("battle.fainted", { battle = st, battler = st.player })
  st.turn = 3
  T.eq(power("RETALIATE", st, ad), 140, "Retaliate doubles after an ally fainted last turn")
end

local function use(id, st, ad, user, target)
  local M = { mnum = num(id), adapter = ad, st = st, user = user or st.player, target = target or st.enemy,
              move = Moves.get(num(id)), anim = {}, opts = {}, isMoveContext = true }
  function M:attackString() self.printedUsed = true end
  function M:ppReduce() end
  function M:tryFaintUser() end
  Hit.run(M)
  return M
end

local function status(id, st, ad, user, target)
  local M = { mnum = num(id), adapter = ad, st = st, user = user or st.player, target = target or st.enemy,
              move = Moves.get(num(id)), isMoveContext = true, attackAnimation = function() end }
  local r = Effects.run("NATIONAL_DEX_GEN3_MOVE_EFFECT", ad, M.user, M.target, M.move, M.mnum, M)
  return M, r
end

-- ------- whose stats
do
  local st, ad = battle(mon({ attack = 50 }), mon({ species = 16, attack = 300 }))
  local plain = calc("FOUL_PLAY", st, ad)
  local st2, ad2 = battle(mon({ attack = 50 }), mon({ species = 16, attack = 50 }))
  T.check(plain > calc("FOUL_PLAY", st2, ad2), "Foul Play hits harder against a strong foe")
  T.eq(st.player.mon.spAtk, 100, "and the user's own stat is put back")
end
do
  local st, ad = battle(mon({ attack = 50, defense = 300 }))
  local st2, ad2 = battle(mon({ attack = 50, defense = 50 }))
  T.check(calc("BODY_PRESS", st, ad) > calc("BODY_PRESS", st2, ad2), "Body Press uses the user's DEFENSE")
  T.eq(st.player.mon.attack, 50, "and leaves ATTACK as it was")
end
do
  local st, ad = battle(nil, mon({ species = 16, defense = 30, spDef = 300 }))
  local st2, ad2 = battle(nil, mon({ species = 16, defense = 300, spDef = 300 }))
  T.check(calc("PSYSHOCK", st, ad) > calc("PSYSHOCK", st2, ad2), "Psyshock hits the foe's DEFENSE")
end
do
  local st, ad = battle()
  st.enemy.stages.defense = 6
  local st2, ad2 = battle()
  T.eq(calc("SACRED_SWORD", st, ad), calc("SACRED_SWORD", st2, ad2), "Sacred Sword ignores DEFENSE boosts")
  T.eq(st.enemy.stages.defense, 6, "which stay where they were")
  st.enemy.stages.evasion = 4
  use("SACRED_SWORD", st, ad)
  T.check(seenEvasion == 0 and st.enemy.stages.evasion == 4, "and evasion, for the accuracy check only")
end

-- ------- crits and fixed damage
do
  local st, ad = battle()
  local _, info = calc("WICKED_BLOW", st, ad)
  T.check(info.critical, "Wicked Blow is always a critical hit")
end
do
  local st, ad = battle(mon({ hp = 77 }))
  T.eq(calc("FINAL_GAMBIT", st, ad), 77, "Final Gambit deals the user's HP")
end

-- ------- moves that fail, and what follows the hit
do
  local st, ad = battle()
  local before = hits
  local M = use("SUCKER_PUNCH", st, ad)
  T.check(M.failed and hits == before, "Sucker Punch fails if the foe isn't attacking")
  st.chosen = { [State.idOf(st.enemy)] = { kind = "move", move = 33 } }   -- TACKLE
  M = use("SUCKER_PUNCH", st, ad)
  T.check(not M.failed and hits == before + 1, "and hits if it is")
  st.chosen[State.idOf(st.enemy)].move = 45                                -- GROWL
  T.check(use("SUCKER_PUNCH", st, ad).failed, "but not against a status move")
end
do
  local st, ad = battle()
  st.player.isFirstTurn = 0
  T.check(use("FIRST_IMPRESSION", st, ad).failed, "First Impression fails after the first turn")
  st.player.isFirstTurn = 1
  T.check(not use("FIRST_IMPRESSION", st, ad).failed, "and works on it")
end
do
  local st, ad = battle(mon({ moves = { num("LAST_RESORT"), 33 }, pp = { 5, 35 } }))
  T.check(use("LAST_RESORT", st, ad).failed, "Last Resort fails before the other moves are used")
  run.loader.events:emit("battle.move_used", { battle = st, user = st.player, moveNum = 33 })
  T.check(not use("LAST_RESORT", st, ad).failed, "and works after")
end
do
  local st, ad = battle()
  st.enemy.stages.attack, st.enemy.stages.evasion = 2, -1
  use("CLEAR_SMOG", st, ad)
  T.eq(st.enemy.stages.attack, 0, "Clear Smog resets the foe's stat changes")
  T.eq(st.enemy.stages.evasion, 0, "all of them")
end
do
  local st, ad = battle(nil, mon({ species = 16, hp = 30 }))
  use("FELL_STINGER", st, ad)
  T.eq(st.player.stages.attack, 3, "Fell Stinger: ATTACK +3 on a knockout")
end
do
  local st, ad = battle()
  use("FINAL_GAMBIT", st, ad)
  T.eq(st.player.mon.hp, 0, "Final Gambit: the user faints")
end
do
  local st, ad = battle()
  use("MIND_BLOWN", st, ad)
  T.eq(st.player.mon.hp, 75, "Mind Blown costs half the user's HP")
end
do
  local st, ad = battle()
  st.enemy.status = "BRN"; st.enemy.mon.status = "BRN"
  use("SPARKLING_ARIA", st, ad)
  T.eq(ad:status(st.enemy), nil, "Sparkling Aria heals the foe's burn")
end
do
  local st, ad = battle()
  st.enemy.status = "SLP"; st.enemy.mon.status = "SLP"
  use("WAKE_UP_SLAP", st, ad)
  T.eq(ad:status(st.enemy), nil, "Wake-Up Slap wakes the foe")
end
do
  local st = battle()
  for t = 1, 3 do
    st.turn = t
    run.loader.events:emit("battle.move_used", { battle = st, user = st.player, moveNum = num("ECHOED_VOICE") })
  end
  local ad = Adapter.new(st, function() end)
  T.eq(power("ECHOED_VOICE", st, ad), 120, "Echoed Voice builds up turn after turn")
end

-- ------- phase 3: the rest
do
  local st, ad = battle()
  T.eq(use("TRIPLE_DIVE", st, ad).move.hits, 3, "Triple Dive hits 3 times")
  T.eq(type(use("WATER_SHURIKEN", st, ad).move.hits), "table", "Water Shuriken 2 to 5")
  local _, info = calc("SURGING_STRIKES", st, ad)
  T.check(info.critical, "Surging Strikes always crits")
end
do
  local st, ad = battle(nil, mon({ species = 25 }))
  T.eq(power("STOMPING_TANTRUM", st, ad), 75, "Stomping Tantrum: 75 after a move that worked")
  st.player.__ndxLastMoveFailed = true
  T.eq(power("STOMPING_TANTRUM", st, ad), 150, "and double after one that failed")
  use("GIGATON_HAMMER", st, ad)
  T.eq(st.player.__ndxLastMoveFailed, false, "a landed hit is stamped as worked")
end
do
  local st, ad = battle(nil, mon({ species = 25 }))
  for _ = 1, 2 do run.loader.events:emit("battle.damage_dealt", { battle = st, target = st.player, damage = 10 }) end
  T.eq(power("RAGE_FIST", st, ad), 150, "Rage Fist: 50 more per hit taken")
  for _ = 1, 2 do run.loader.events:emit("battle.fainted", { battle = st, battler = { side = "player" } }) end
  T.eq(power("LAST_RESPECTS", st, ad), 150, "Last Respects: 50 more per fallen ally")
end
do
  local st, ad = battle()
  T.check(use("METAL_BURST", st, ad).failed, "Metal Burst fails when the user wasn't hit")
  st.player.lastPhysicalDamageTaken, st.player.lastPhysicalById = 40, State.idOf(st.enemy)
  T.eq(calc("METAL_BURST", st, ad), 60, "and deals 1.5x the damage taken")
  T.check(not use("COMEUPPANCE", st, ad).failed, "Comeuppance too")
end
do
  local st, ad = battle(mon({ species = 4 }))                                      -- Charmander
  use("BURN_UP", st, ad)
  T.eq(st.player.type1, 9, "Burn Up leaves the user typeless")
  local st2, ad2 = battle()
  T.check(use("BURN_UP", st2, ad2).failed, "and fails without the Fire type")
  local _, info = calc("REVELATION_DANCE", st2, ad2)
  T.eq(info.moveType, 13, "Revelation Dance takes the user's type")
end
do
  local st, ad = battle(nil, mon({ species = 66 }))                                -- Machop
  local _, info = calc("FLYING_PRESS", st, ad)
  T.eq(info.effectiveness, 2, "Flying Press is Fighting and Flying at once (Flying hits Fighting)")
  local _, plain = calc(2, st, ad)                                                 -- KARATE CHOP
  T.eq(plain.effectiveness, 1, "where Fighting alone is neutral")
  T.check(use("SYNCHRONOISE", st, ad).failed, "Synchronoise fails without a shared type")
  local st2, ad2 = battle(nil, mon({ species = 25 }))
  T.check(not use("SYNCHRONOISE", st2, ad2).failed, "and works with one")
end
do
  local st, ad = battle()
  T.eq(power("FUSION_FLARE", st, ad), 100, "Fusion Flare alone")
  run.loader.events:emit("battle.move_used", { battle = st, user = st.enemy, moveNum = num("FUSION_BOLT") })
  T.eq(power("FUSION_FLARE", st, ad), 200, "doubles after Fusion Bolt this turn")
end
do
  local st, ad = battle()
  local before = calc(33, st, ad, st.enemy, st.player)
  use("GLAIVE_RUSH", st, ad)
  T.eq(calc(33, st, ad, st.enemy, st.player), before * 2, "Glaive Rush: the user takes double damage")
  run.loader.events:emit("battle.move_used", { battle = st, user = st.player, moveNum = 33 })
  T.eq(calc(33, st, ad, st.enemy, st.player), before, "until it moves again")
end
do
  local st, ad = battle()
  run.loader.events:emit("battle.move_used", { battle = st, user = st.player, moveNum = num("GIGATON_HAMMER") })
  T.check(use("GIGATON_HAMMER", st, ad).failed, "Gigaton Hammer can't be used twice in a row")
  run.loader.events:emit("battle.move_used", { battle = st, user = st.player, moveNum = 33 })
  T.check(not use("GIGATON_HAMMER", st, ad).failed, "but after another move it can")
end
do
  local st, ad = battle()
  status("LASER_FOCUS", st, ad)
  st.turn = st.turn + 1
  local _, info = calc(33, st, ad)
  T.check(info.critical, "Laser Focus: the next move is a critical hit")
end
do
  local st, ad = battle()
  use("DIRE_CLAW", st, ad)
  T.eq(ad:status(st.enemy), "PSN", "Dire Claw can poison (or paralyze, or put to sleep)")
  st.player.status = "BRN"; st.player.mon.status = "BRN"
  status("TAKE_HEART", st, ad)
  T.eq(ad:status(st.player), nil, "Take Heart cures the user's status")
end
do
  local st, ad = battle(mon({ species = 1090 }))                                   -- Galarian Darumaka, 40 kg
  T.eq(power("HEAVY_SLAM", st, ad), 120, "Heavy Slam reads a form's weight")
  local st2, ad2 = battle(mon({ species = 16 }), mon({ species = 1090 }))
  T.eq(power("HEAVY_SLAM", st2, ad2), 40, "both ways")
  local _, info = calc(67, st2, ad2)                                               -- LOW KICK
  T.eq(info.power, 60, "and so does Low Kick")
end
do
  local st, ad = battle()
  st.enemy.ability = "DAMP"
  local M = use("MIND_BLOWN", st, ad)
  T.check(M.failed and st.player.mon.hp == 150, "Damp stops Mind Blown")
end

-- ------- batch B: abilities and types
do
  local st, ad = battle()
  status("WORRY_SEED", st, ad)
  T.eq(ad:abilityOf(st.enemy), "INSOMNIA", "Worry Seed makes the foe's ability INSOMNIA")
  status("GASTRO_ACID", st, ad)
  T.eq(ad:abilityOf(st.enemy), nil, "Gastro Acid suppresses it")
  local st2, ad2 = battle()
  st2.player.ability = "DRIZZLE"
  status("ENTRAINMENT", st2, ad2)
  T.eq(ad2:abilityOf(st2.enemy), "DRIZZLE", "Entrainment copies the user's ability over")
  status("DOODLE", st2, ad2, st2.enemy, st2.player)
  T.eq(ad2:abilityOf(st2.enemy), "DRIZZLE", "Doodle copies the foe's onto the user")
end
do
  local st, ad = battle(nil, mon({ species = 16 }))
  status("SOAK", st, ad)
  T.check(st.enemy.type1 == 11 and st.enemy.type2 == nil, "Soak makes the foe pure Water")
  status("TRICK_OR_TREAT", st, ad)
  T.eq(st.enemy.__ndxType3, 7, "Trick-or-Treat adds Ghost")
  T.eq(calc(33, st, ad), 0, "so a Normal move can't touch it")
  status("REFLECT_TYPE", st, ad)
  T.check(st.player.type1 == 11 and st.player.__ndxType3 == 7, "Reflect Type copies all of it")
end
do
  local st, ad = battle()
  local plain = calc(52, st, ad)                                                   -- EMBER
  status("TAR_SHOT", st, ad)
  T.check(st.enemy.stages.speed == -1 and calc(52, st, ad) == plain * 2, "Tar Shot: SPEED down, Fire moves doubled")
  local _, info = calc(33, st, ad, st.enemy, st.player)
  T.eq(info.moveType, 0, "Tackle is Normal")
  status("ELECTRIFY", st, ad)
  _, info = calc(33, st, ad, st.enemy, st.player)
  T.eq(info.moveType, 13, "until Electrify makes the foe's next move Electric")
  local st2, ad2 = battle()
  status("ION_DELUGE", st2, ad2)
  _, info = calc(33, st2, ad2)
  T.eq(info.moveType, 13, "Ion Deluge turns Normal moves Electric this turn")
end
do
  local st, ad = battle(nil, mon({ species = 198 }))                               -- Murkrow (Dark/Flying)
  T.eq(calc(94, st, ad), 0, "Psychic can't touch a Dark type")                   -- PSYCHIC
  status("MIRACLE_EYE", st, ad)
  T.check(calc(94, st, ad) > 0, "until Miracle Eye")
end

-- ------- stats
do
  local st, ad = battle(mon({ attack = 50 }), mon({ species = 25, attack = 150 }))
  status("POWER_SPLIT", st, ad)
  T.check(st.player.__ndxStat.attack == 100 and st.enemy.__ndxStat.attack == 100, "Power Split averages ATTACK")
  T.check(st.player.mon.attack == 50 and st.enemy.mon.attack == 150, "without writing the Pokemon's stats")
  local st2, ad2 = battle(mon({ attack = 50 }), mon({ species = 25, attack = 50 }))
  T.check(calc(33, st, ad) > calc(33, st2, ad2), "and the damage uses the shared value")
end
do
  local st, ad = battle(mon({ attack = 50, defense = 200 }))
  status("POWER_TRICK", st, ad)
  T.check(st.player.__ndxStat.attack == 200 and st.player.__ndxStat.defense == 50, "Power Trick swaps ATTACK and DEFENSE")
  local st2, ad2 = battle(mon({ speed = 50 }), mon({ species = 25, speed = 200 }))
  status("SPEED_SWAP", st2, ad2)
  local RA = require("src.core.game3.battle") and nil
  T.check(st2.player.__ndxStat.speed == 200 and st2.enemy.__ndxStat.speed == 50, "Speed Swap swaps SPEED")
end
do
  local st, ad = battle()
  st.player.stages.attack, st.enemy.stages.spAtk = 3, -2
  status("HEART_SWAP", st, ad)
  T.check(st.player.stages.attack == 0 and st.player.stages.spAtk == -2 and st.enemy.stages.attack == 3, "Heart Swap swaps every stat change")
  status("TOPSY_TURVY", st, ad)
  T.eq(st.enemy.stages.attack, -3, "Topsy-Turvy flips the foe's")
end
do
  local st, ad = battle(mon({ hp = 50 }), mon({ species = 25, attack = 80 }))
  status("STRENGTH_SAP", st, ad)
  T.check(st.player.mon.hp == 130 and st.enemy.stages.attack == -1, "Strength Sap heals by the foe's ATTACK and lowers it")
  T.check(status("VENOM_DRENCH", st, ad).failed, "Venom Drench fails on an unpoisoned foe")
  st.enemy.status = "PSN"; st.enemy.mon.status = "PSN"
  status("VENOM_DRENCH", st, ad)
  T.check(st.enemy.stages.attack == -2 and st.enemy.stages.speed == -1, "and lowers three stats on a poisoned one")
end
do
  local st, ad = battle(mon({ gender = "M" }), mon({ species = 25, gender = "F" }))
  status("CAPTIVATE", st, ad)
  T.eq(st.enemy.stages.spAtk, -2, "Captivate works on the opposite gender")
  local st2, ad2 = battle(mon({ gender = "M" }), mon({ species = 25, gender = "M" }))
  T.check(status("CAPTIVATE", st2, ad2).failed, "and fails on the same")
end
do
  local st, ad = battle()
  status("CLANGOROUS_SOUL", st, ad)
  T.check(st.player.mon.hp == 100 and st.player.stages.attack == 1 and st.player.stages.speed == 1, "Clangorous Soul: a third of HP for +1 everything")
  status("NO_RETREAT", st, ad)
  T.check(st.player.stages.attack == 2 and st.player.expTrapped, "No Retreat: +1 everything, no escape")
  local st2, ad2 = battle()
  status("FILLET_AWAY", st2, ad2)
  T.check(st2.player.mon.hp == 75 and st2.player.stages.attack == 2, "Fillet Away: half the HP for +2")
  status("ACUPRESSURE", st2, ad2)
  T.eq(st2.player.stages.attack, 4, "Acupressure: +2 to a stat (the first open one here)")
end
do
  local st, ad = battle()
  T.check(status("GEAR_UP", st, ad).failed, "Gear Up needs PLUS or MINUS")
  st.player.ability = "PLUS"
  status("GEAR_UP", st, ad)
  T.eq(st.player.stages.attack, 1, "and works with it")
  local st2, ad2 = battle(mon({ species = 1 }))                                    -- Bulbasaur
  status("ROTOTILLER", st2, ad2)
  T.eq(st2.player.stages.attack, 1, "Rototiller raises Grass types on the ground")
end

-- ------- items and berries
do
  local st, ad = battle()
  T.check(use("FLING", st, ad).failed, "Fling fails with no item")
  st.player.item = 133                                                             -- CHERI BERRY
  T.eq(power("FLING", st, ad), 10, "a berry flings for 10")
  use("FLING", st, ad)
  T.eq(st.player.item, 0, "and is gone after")
  local st2, ad2 = battle()
  st2.player.item = 133
  local _, info = calc("NATURAL_GIFT", st2, ad2)
  T.check(info.power == 80 and info.moveType == 10, "Natural Gift: a Cheri Berry is an 80-power Fire move")
  T.check(use("BELCH", st2, ad2).failed, "Belch fails before a berry was eaten")
  st2.player.expUsedHeldItem = 133
  T.check(not use("BELCH", st2, ad2).failed, "and works after")
end
do
  local st, ad = battle()
  st.player.item = 133
  status("STUFF_CHEEKS", st, ad)
  T.check(st.player.item == 0 and st.player.stages.defense == 2, "Stuff Cheeks eats the berry for +2 DEFENSE")
  st.enemy.item = 133
  use("BUG_BITE", st, ad)
  T.eq(st.enemy.item, 0, "Bug Bite eats the foe's berry")
end
do
  local st, ad = battle()
  status("POWDER", st, ad)
  local before = hits
  local M = use(52, st, ad, st.enemy, st.player)                                   -- EMBER
  T.check(M.failed and hits == before and st.enemy.mon.hp == 150 - 37, "Powder blows up a Fire move in the foe's face")
end
do
  local st, ad = battle(nil, mon({ species = 25, moves = { 33 }, pp = { 10 } }))
  st.enemy.lastMoveId = 33
  use("EERIE_SPELL", st, ad)
  T.eq(st.enemy.mon.pp[1], 7, "Eerie Spell takes 3 PP from the foe's last move")
  st.player.status = "BRN"; st.player.mon.status = "BRN"
  status("PSYCHO_SHIFT", st, ad)
  T.check(ad:status(st.player) == nil and ad:status(st.enemy) == "BRN", "Psycho Shift passes the burn on")
end
do
  local st, ad = battle()
  run.loader.events:emit("battle.move_used", { battle = st, user = st.enemy, moveNum = 33 })
  use("CORE_ENFORCER", st, ad)
  T.eq(ad:abilityOf(st.enemy), nil, "Core Enforcer suppresses a foe that already moved")
end

run.release()
-- moves that never miss (PokeAPI accuracy none, stored as 0): the engine reads 0 as a 0% chance
-- unless the effect is ALWAYS_HIT, so the accuracy hook makes them hit
do
  local function acc(id, a)
    return run.loader.hooks:call("battle.accuracy", function(c) return c.accuracy end,
      { moveNum = num(id), accuracy = a })
  end
  for _, id in ipairs({ "FLOWER_TRICK", "CLEAR_SMOG", "HYPERSPACE_HOLE", "HYPERSPACE_FURY", "TACHYON_CUTTER", "TRUMP_CARD" }) do
    T.eq(acc(id, 0), 100, id .. " never misses")
  end
  T.eq(acc(33, 95), 95, "Tackle keeps its own accuracy")
  T.eq(acc("MOONBLAST", 100), 100, "a 100% move stays 100%")
end

T.finish("national_dex_gen3 move rules (" .. GAME .. ")")
