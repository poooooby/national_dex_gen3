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
  return Effects.run("NATIONAL_DEX_GEN3_MOVE_EFFECT", ad, M.user, M.target, M.move, M.mnum, M), M
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

run.release()
T.finish("national_dex_gen3 move rules (" .. GAME .. ")")
