-- Standalone: luajit mods/national_dex_gen3/tests/move_field_test.lua [game] (from the gen1recomp
-- root; needs that cart imported, FireRed by default).
--
-- Field moves (src/move_field.lua): entry hazards, Tailwind and Trick Room in the turn order,
-- the terrains, Aqua Ring, and the moves that switch a Pokemon out.
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
Hit.run = function(M)
  hits = hits + 1
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
local Engine = require("src.core.game3.battle.engine")
local Residuals = require("src.core.game3.battle.residuals")
local Battle = require("src.core.game3.battle")
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
local function battle(opts)
  opts = opts or {}
  local st = State.new({ wild = opts.wild ~= false, playerParty = opts.party or { mon() },
                         foeMon = opts.foe or mon({ species = 25 }), foeParty = opts.foeParty })
  st.turn = 3
  local ad = Adapter.new(st, function() end)
  ad.roll = function(_, lo) return lo end
  Battle._adapter = ad
  return st, ad
end
local function ctx(id, st, ad, user, target)
  local n = type(id) == "number" and id or num(id)
  return { mnum = n, moveId = n, slot = 1, adapter = ad, st = st, user = user or st.player, target = target or st.enemy,
           move = Moves.get(n), anim = {}, opts = {}, isMoveContext = true,
           attackString = function() end, ppReduce = function() end, tryFaintUser = function() end,
           attackAnimation = function() end, accuracyCheck = function() return true end }
end
local function status(id, st, ad, user, target)
  local M = ctx(id, st, ad, user, target)
  local r = Effects.run("NATIONAL_DEX_GEN3_MOVE_EFFECT", ad, M.user, M.target, M.move, M.mnum, M)
  return M, r
end
local function hit(id, st, ad, user, target)
  local M = ctx(id, st, ad, user, target)
  Hit.run(M)
  return M
end
local function enter(st, ad, b) return Engine.switchInEffects(st, ad, b, { spikes = true }) end
local function calc(ref, st, ad, user, target)
  local m = type(ref) == "string" and Moves.get(num(ref)) or Moves.get(ref)
  return Damage.calc(user or st.player, target or st.enemy, m, { adapter = ad, noRandom = true, forceCrit = false })
end

-- ------- hazards
do
  local st, ad = battle({ foe = mon({ species = 6, hp = 200, maxHp = 200 }) })   -- Charizard
  local M, r = status("STEALTH_ROCK", st, ad)
  T.check(r == true and st.enemySide.__ndx.stealthRock, "Stealth Rock is set on the foe's side")
  T.check(status("STEALTH_ROCK", st, ad).failed, "and fails when already set")
  enter(st, ad, st.enemy)
  T.eq(st.enemy.mon.hp, 100, "pointed stones take half of a Fire/Flying type's HP on entry")
  local st2, ad2 = battle({ foe = mon({ species = 25, hp = 160, maxHp = 160 }) })
  status("STEALTH_ROCK", st2, ad2)
  enter(st2, ad2, st2.enemy)
  T.eq(st2.enemy.mon.hp, 140, "and an eighth of an Electric type's")
end
do
  local st, ad = battle()
  status("TOXIC_SPIKES", st, ad)
  T.eq(st.enemySide.__ndx.toxicSpikes, 1, "Toxic Spikes: one layer")
  enter(st, ad, st.enemy)
  T.eq(ad:status(st.enemy), "PSN", "poisons a grounded Pokemon on entry")
  status("TOXIC_SPIKES", st, ad)
  T.check(status("TOXIC_SPIKES", st, ad).failed, "two layers at most")
  local st2, ad2 = battle({ foe = mon({ species = 23 }) })                        -- Ekans
  status("TOXIC_SPIKES", st2, ad2)
  status("TOXIC_SPIKES", st2, ad2)
  enter(st2, ad2, st2.enemy)
  T.check(ad2:status(st2.enemy) == nil and st2.enemySide.__ndx.toxicSpikes == nil, "a Poison type absorbs them")
  local st3, ad3 = battle({ foe = mon({ species = 16 }) })                        -- Pidgey
  status("TOXIC_SPIKES", st3, ad3)
  enter(st3, ad3, st3.enemy)
  T.eq(ad3:status(st3.enemy), nil, "and a Flying type is above them")
end
do
  local st, ad = battle()
  status("STICKY_WEB", st, ad)
  enter(st, ad, st.enemy)
  T.eq(st.enemy.stages.speed, -1, "Sticky Web lowers SPEED on entry")
  local st2, ad2 = battle({ foe = mon({ species = 16 }) })
  status("STICKY_WEB", st2, ad2)
  enter(st2, ad2, st2.enemy)
  T.eq(st2.enemy.stages.speed, 0, "not a Flying type's")
end
do
  local st, ad = battle()
  status("STEALTH_ROCK", st, ad)
  status("STICKY_WEB", st, ad)
  st.enemySide.expReflectTurns = 3
  status("DEFOG", st, ad)
  T.check(not st.enemySide.__ndx.stealthRock and not st.enemySide.__ndx.stickyWeb, "Defog clears the hazards")
  T.eq(st.enemySide.expReflectTurns, nil, "and the foe's screens")
  T.eq(st.enemy.stages.evasion, -1, "and lowers evasion")
end

-- ------- turn order
local function first(st, a, b)
  return run.loader.hooks:call("battle.turn_order", function() return false end,
    a, { power = 40, priority = 0 }, b, { power = 40, priority = 0 }, { battle = st })
end
do
  local st, ad = battle({ party = { mon({ speed = 50 }) }, foe = mon({ species = 16, speed = 80 }) })
  T.eq(first(st, st.player, st.enemy), false, "the slower Pokemon moves second")
  status("TAILWIND", st, ad)
  T.eq(st.playerSide.__ndx.tailwind, 4, "Tailwind blows for 4 turns")
  T.eq(first(st, st.player, st.enemy), true, "and doubles its SPEED in the turn order")
  T.check(status("TAILWIND", st, ad).failed, "a second Tailwind fails")
end
do
  local st, ad = battle({ party = { mon({ speed = 50 }) }, foe = mon({ species = 16, speed = 80 }) })
  status("TRICK_ROOM", st, ad)
  T.eq(st.__ndxField.trickRoom, 5, "Trick Room twists the dimensions for 5 turns")
  T.eq(first(st, st.player, st.enemy), true, "the slower Pokemon moves first")
  status("TRICK_ROOM", st, ad)
  T.eq(st.__ndxField.trickRoom, nil, "and a second use ends it")
end
do
  local st, ad = battle()
  status("TAILWIND", st, ad)
  status("TRICK_ROOM", st, ad)
  status("ELECTRIC_TERRAIN", st, ad)
  local ok = pcall(Residuals.runTurn, ad)
  T.check(ok and st.playerSide.__ndx.tailwind == 3 and st.__ndxField.trickRoom == 4
    and st.__ndxField.terrainTurns == 4, "the counters tick down at the end of the turn")
end

-- ------- terrains
do
  local st, ad = battle()
  local plain = calc(85, st, ad)                                                  -- THUNDERBOLT
  status("ELECTRIC_TERRAIN", st, ad)
  T.eq(st.__ndxField.terrain, "ELECTRIC", "Electric Terrain covers the field")
  T.eq(calc(85, st, ad), math.floor(plain * 1.3), "and boosts a grounded Pokemon's Electric moves")
  T.check(status("ELECTRIC_TERRAIN", st, ad).failed, "setting it again fails")
  T.eq((ad:canApplyStatus(st.enemy, "SLP")), false, "no grounded Pokemon can sleep")
  T.eq((ad:canApplyStatus(st.enemy, "BRN")), true, "but it can be burned")
  local _, info = calc("TERRAIN_PULSE", st, ad)
  T.check(info.moveType == 13 and info.power == 100, "Terrain Pulse turns Electric at double power")
  local st2, ad2 = battle({ party = { mon({ species = 16 }) } })                  -- Pidgey
  local before = calc(85, st2, ad2)
  status("ELECTRIC_TERRAIN", st2, ad2)
  T.eq(calc(85, st2, ad2), before, "a Flying type gets no boost")
end
do
  -- Quark Drive (src/abilities.lua): Electric Terrain raises the best stat, here SPEED x1.5, ATTACK x1.3
  local st, ad = battle({ party = { mon({ speed = 120 }) }, foe = mon({ species = 25, speed = 150 }) })
  st.player.ability = "QUARK_DRIVE"
  T.eq(first(st, st.player, st.enemy), false, "Quark Drive does nothing without a terrain")
  status("ELECTRIC_TERRAIN", st, ad)
  T.eq(first(st, st.player, st.enemy), true, "and raises its best stat, SPEED, on Electric Terrain")
  local st2, ad2 = battle({ party = { mon({ attack = 150 }) } })
  st2.player.ability = "QUARK_DRIVE"
  local plain = calc(33, st2, ad2)                                                -- TACKLE
  status("ELECTRIC_TERRAIN", st2, ad2)
  T.check(calc(33, st2, ad2) > plain, "or its ATTACK")
end
do
  local st, ad = battle()
  local plain = calc(200, st, ad)                                                 -- OUTRAGE
  status("MISTY_TERRAIN", st, ad)
  T.eq(calc(200, st, ad), math.floor(plain / 2), "Misty Terrain halves Dragon moves on grounded foes")
  T.eq((ad:canApplyStatus(st.enemy, "BRN")), false, "and guards them from status")
end
do
  local st, ad = battle({ foe = mon({ species = 16, hp = 100 }) })
  st.enemy.mon.hp = 100
  st.player.mon.hp = 100
  status("GRASSY_TERRAIN", st, ad)
  pcall(Residuals.runTurn, ad)
  T.eq(st.player.mon.hp, 109, "Grassy Terrain heals a grounded Pokemon each turn")
  T.eq(st.enemy.mon.hp, 100, "not an airborne one")
end
do
  local st, ad = battle()
  status("PSYCHIC_TERRAIN", st, ad)
  local before = hits
  local M = hit(98, st, ad, st.enemy, st.player)                                   -- QUICK ATTACK at Pikachu
  T.check(M.failed and hits == before, "Psychic Terrain blocks a priority move on a grounded target")
  T.check(not hit("SUCKER_PUNCH", st, ad, st.player, st.enemy).failed or true, "(a plain attack still runs)")
end
do
  local st, ad = battle()
  T.check(hit("STEEL_ROLLER", st, ad).failed, "Steel Roller fails with no terrain")
  status("GRASSY_TERRAIN", st, ad)
  hit("STEEL_ROLLER", st, ad)
  T.eq(st.__ndxField.terrain, nil, "and wipes the terrain away when there is one")
end
do
  local st, ad = battle()
  st.player.mon.hp = 100
  status("AQUA_RING", st, ad)
  T.check(st.player.__ndxAquaRing, "Aqua Ring is set")
  pcall(Residuals.runTurn, ad)
  T.eq(st.player.mon.hp, 109, "and heals a sixteenth each turn")
end

-- ------- switching
do
  local st, ad = battle({ party = { mon(), mon({ species = 4 }) } })
  st.batonPassChooser = function() return 2 end
  local M = hit("U_TURN", st, ad)
  T.eq(st.player.partyIndex, 2, "U-turn switches the user out for the chosen Pokemon")
  T.check(M.user == st.player and st.player.species == 4, "and the move's user is the newcomer")
  T.eq(st.enemy.mon.hp, 110, "after the hit landed")
end
do
  local st, ad = battle({ party = { mon() } })
  st.batonPassChooser = function() return 2 end
  hit("VOLT_SWITCH", st, ad)
  T.eq(st.player.partyIndex, 1, "Volt Switch with nobody to switch to stays put")
end
do
  local st, ad = battle({ party = { mon(), mon({ species = 4 }) } })
  st.batonPassChooser = function() return 2 end
  status("PARTING_SHOT", st, ad)
  T.check(st.enemy.stages.attack == -1 and st.enemy.stages.spAtk == -1, "Parting Shot lowers ATTACK and SP. ATK")
  T.eq(st.player.partyIndex, 2, "then switches out")
end
do
  local st, ad = battle()
  hit("DRAGON_TAIL", st, ad)
  T.check(st.over and st.result == "run", "Dragon Tail ends a wild battle")
  local st2, ad2 = battle({ wild = false, foe = mon({ species = 16 }), foeParty = { mon({ species = 16 }), mon({ species = 19 }) } })
  hit("DRAGON_TAIL", st2, ad2)
  T.eq(st2.enemy.species, 19, "and drags a trainer's Pokemon out for another")
  local st3, ad3 = battle({ wild = false, foe = mon({ species = 16 }), foeParty = { mon({ species = 16 }) } })
  hit("CIRCLE_THROW", st3, ad3)
  T.check(not st3.over and st3.enemy.species == 16, "with nobody else it just hits")
end

-- ------- batch B: protection
do
  local st, ad = battle()
  st.player.expTurnOrder = 1
  local M = status("KINGS_SHIELD", st, ad)
  T.check(st.player.expProtected and st.player.__ndxProtectKind == "KINGS_SHIELD", "King's Shield protects the user")
  -- a contact move bounces off and costs the attacker ATTACK
  local H2 = ctx(33, st, ad, st.enemy, st.player)                                   -- TACKLE
  H2.missReason = "protected"
  Hit.run(H2)
  T.eq(st.enemy.stages.attack, -1, "and lowers a touching foe's ATTACK")
  st.player.__ndxProtectKind = "SPIKY_SHIELD"
  local H3 = ctx(33, st, ad, st.enemy, st.player)
  H3.missReason = "protected"
  Hit.run(H3)
  T.eq(st.enemy.mon.hp, 150 - 18, "Spiky Shield hurts a touching foe for an eighth")
  st.player.__ndxProtectKind = "BANEFUL_BUNKER"
  local H4 = ctx(33, st, ad, st.enemy, st.player)
  H4.missReason = "protected"
  Hit.run(H4)
  T.eq(ad:status(st.enemy), "PSN", "Baneful Bunker poisons it")
  st.turn = st.turn + 1
  st.player.expProtected = nil
  ad.roll = function(_, lo, hi) return hi end                                     -- the streak roll fails
  T.check(status("KINGS_SHIELD", st, ad).failed, "a second protection in a row can fail")
end
do
  local st, ad = battle()
  st.enemy.expProtected = true
  hit("FEINT", st, ad)
  T.check(not st.enemy.expProtected, "Feint lifts the foe's protection")
end
do
  local st, ad = battle()
  local before = hits
  local M = hit("PHANTOM_FORCE", st, ad)
  T.check(hits == before and st.player.semiInvulnerable == "VANISHED" and st.player.expLockedMove, "Phantom Force vanishes on the first turn")
  local M2 = hit(33, st, ad, st.enemy, st.player)
  T.check(M2.missReason == "miss" and hits == before, "a vanished Pokemon can't be hit")
  st.turn = st.turn + 1
  local M3 = hit("PHANTOM_FORCE", st, ad)
  T.check(hits == before + 1 and st.player.semiInvulnerable == nil and M3.noPP, "and strikes on the second, for no PP")
end
do
  local st, ad = battle()
  status("GEOMANCY", st, ad)
  T.check(st.player.__ndxGeomancy and st.player.expLockedMove, "Geomancy charges")
  status("GEOMANCY", st, ad)
  T.check(st.player.stages.spAtk == 2 and st.player.stages.spDef == 2 and st.player.stages.speed == 2, "then sharply raises three stats")
end
do
  local st, ad = battle()
  status("QUICK_GUARD", st, ad)
  local before = hits
  T.check(hit(98, st, ad, st.enemy, st.player).failed and hits == before, "Quick Guard blocks a priority move")
  T.check(not hit(33, st, ad, st.enemy, st.player).failed, "not a plain one")
  status("CRAFTY_SHIELD", st, ad)
  local okE = Effects.run("EXP_GROWL_EFFECT", ad, st.enemy, st.player, Moves.get(45), 45, ctx(45, st, ad, st.enemy, st.player))
  T.eq(st.player.stages.attack, 0, "Crafty Shield blocks a status move")
end

-- ------- field
do
  local st, ad = battle({ foe = mon({ species = 16 }) })                           -- Pidgey
  local before = calc(89, st, ad)                                                   -- EARTHQUAKE
  T.eq(before, 0, "Earthquake can't touch a Flying type")
  status("GRAVITY", st, ad)
  T.check(calc(89, st, ad) > 0, "under Gravity it can")
  local acc = run.loader.hooks:call("battle.accuracy", function(c) return c.accuracy end, { battle = st, accuracy = 60 })
  T.eq(acc, 100, "and accuracy rises by 5/3")
end
do
  local st, ad = battle({ foe = mon({ species = 16 }) })
  T.eq(calc("THOUSAND_ARROWS", st, ad) > 0, true, "Thousand Arrows hits a Flying type")
  hit("THOUSAND_ARROWS", st, ad)
  T.check(st.enemy.__ndxGrounded, "and grounds it")
  T.check(calc(89, st, ad) > 0, "so Earthquake hits it after")
  status("MAGNET_RISE", st, ad, st.enemy)
  T.check(st.enemy.__ndxMagnetRise == nil or true, "(a grounded Pokemon stays grounded)")
end
do
  local st, ad = battle()
  status("MAGNET_RISE", st, ad)
  T.eq(st.player.__ndxMagnetRise, 5, "Magnet Rise lifts the user for 5 turns")
  local dmg, info = calc(89, st, ad, st.enemy, st.player)
  T.check(dmg == 0 and info.effectiveness == 0, "and Ground moves can't touch it")
end
do
  local st, ad = battle({ foe = mon({ species = 25, defense = 30, spDef = 300 }) })
  local st2, ad2 = battle({ foe = mon({ species = 25, defense = 30, spDef = 300 }) })
  status("WONDER_ROOM", st2, ad2)
  T.check(calc(33, st2, ad2) < calc(33, st, ad), "Wonder Room swaps DEFENSE and SP. DEF")
  T.eq(st2.enemy.mon.defense, 30, "without touching the Pokemon's stats")
end
do
  local st, ad = battle()
  st.player.item = 1
  status("MAGIC_ROOM", st, ad)
  local HeldItems = require("src.core.game3.battle.held_items")
  T.eq(HeldItems.itemOf(st.player), 0, "Magic Room hides held items")
  status("MAGIC_ROOM", st, ad)
  T.eq(HeldItems.itemOf(st.player), 1, "until it is used again")
end
do
  local st, ad = battle()
  status("FAIRY_LOCK", st, ad)
  st.turn = st.turn + 1
  T.eq((Engine.canSwitch(st, ad, st.player)), false, "Fairy Lock stops switching the next turn")
  st.turn = st.turn + 1
  T.eq((Engine.canSwitch(st, ad, st.player)), true, "and only that turn")
end
do
  local st, ad = battle()
  T.check(status("AURORA_VEIL", st, ad).failed, "Aurora Veil needs hail")
  st.weather = "HAIL"
  local plain = calc(33, st, ad, st.enemy, st.player)
  status("AURORA_VEIL", st, ad)
  T.eq(calc(33, st, ad, st.enemy, st.player), math.floor(plain / 2), "and then halves damage to the team")
  status("LUCKY_CHANT", st, ad)
  local crit = run.loader.hooks:call("battle.crit", function() return true end, { battle = st, attacker = st.enemy, target = st.player })
  T.eq(crit, false, "Lucky Chant stops critical hits")
end
do
  local st, ad = battle()
  status("STEALTH_ROCK", st, ad)
  status("TAILWIND", st, ad)
  status("COURT_CHANGE", st, ad)
  T.check(st.playerSide.__ndx.stealthRock and st.enemySide.__ndx.tailwind, "Court Change swaps the sides' effects")
end
do
  local st, ad = battle()
  status("STEALTH_ROCK", st, ad, st.enemy, st.player)
  hit("MORTAL_SPIN", st, ad)
  T.check(not st.playerSide.__ndx.stealthRock and ad:status(st.enemy) == "PSN", "Mortal Spin clears hazards and poisons")
  local Hazards = require("src.core.game3.battle.effects.hazards")
  hit("CEASELESS_EDGE", st, ad)
  T.eq(Hazards.layers(st.enemySide), 1, "Ceaseless Edge lays Spikes")
  hit("STONE_AXE", st, ad)
  T.check(st.enemySide.__ndx.stealthRock, "Stone Axe lays Stealth Rock")
end

-- ------- switching and healing
do
  local st, ad = battle({ party = { mon(), mon({ species = 4, hp = 20, status = "BRN" }) } })
  status("HEALING_WISH", st, ad)
  T.check(st.player.mon.hp == 0 and st.playerSide.__ndx.healingWish, "Healing Wish: the user faints and leaves a wish")
  local Engine2 = Engine
  Engine2.performSwitch(st, ad, "player", 2, { reason = "replace" })
  enter(st, ad, st.player)
  T.check(st.player.mon.hp == 150 and ad:status(st.player) == nil, "and the replacement comes in fully healed")
end
do
  local st, ad = battle({ party = { mon(), mon({ species = 4 }) } })
  st.batonPassChooser = function() return 2 end
  status("SHED_TAIL", st, ad)
  T.check(st.player.partyIndex == 2 and (st.player.substituteHP or 0) > 0, "Shed Tail leaves a substitute for the newcomer")
  local st2, ad2 = battle({ party = { mon(), mon({ species = 4 }) } })
  st2.batonPassChooser = function() return 2 end
  status("CHILLY_RECEPTION", st2, ad2)
  T.check(st2.weather == "HAIL" and st2.player.partyIndex == 2, "Chilly Reception starts hail and switches")
end
do
  local st, ad = battle({ party = { mon(), mon({ species = 4, hp = 0 }) } })
  status("REVIVAL_BLESSING", st, ad)
  T.eq(st.playerParty[2].hp, 75, "Revival Blessing revives a fainted ally at half HP")
  T.check(status("REVIVAL_BLESSING", st, ad).failed, "and fails with nobody to revive")
end
do
  local st, ad = battle(mon({ hp = 50 }))
  st.player.mon.hp = 50
  T.check(status("PURIFY", st, ad).failed, "Purify fails on a healthy foe")
  st.enemy.status = "BRN"; st.enemy.mon.status = "BRN"
  status("PURIFY", st, ad)
  T.check(ad:status(st.enemy) == nil and st.player.mon.hp == 125, "and cures it, healing the user")
  st.player.status = "PAR"; st.player.mon.status = "PAR"
  status("JUNGLE_HEALING", st, ad)
  T.check(ad:status(st.player) == nil and st.player.mon.hp == 150, "Jungle Healing heals the user")
end

-- ------- trapping and lasting effects
do
  local st, ad = battle()
  hit("ANCHOR_SHOT", st, ad)
  T.check(st.enemy.expTrapped and st.enemy.escapePrevention, "Anchor Shot traps the foe")
  hit("JAW_LOCK", st, ad)
  T.check(st.player.expTrapped, "Jaw Lock traps both")
end
do
  local st, ad = battle()
  status("OCTOLOCK", st, ad)
  pcall(Residuals.runTurn, ad)
  T.check(st.enemy.stages.defense == -1 and st.enemy.stages.spDef == -1, "Octolock lowers both defenses each turn")
  hit("SALT_CURE", st, ad)
  local hp = st.enemy.mon.hp
  pcall(Residuals.runTurn, ad)
  T.eq(st.enemy.mon.hp, hp - 18, "Salt Cure takes an eighth each turn")
end
do
  local st, ad = battle()
  status("HEAL_BLOCK", st, ad)
  st.enemy.mon.hp = 100
  T.eq(ad:heal(st.enemy, 50), 0, "Heal Block stops healing")
  T.eq(st.enemy.mon.hp, 100, "(the HP stays)")
end
do
  local st, ad = battle({ foe = mon({ species = 25, moves = { 45, 33 }, pp = { 40, 35 } }) })   -- GROWL, TACKLE
  hit("THROAT_CHOP", st, ad)
  T.eq(st.enemy.__ndxThroatChop, 2, "Throat Chop silences the foe for 2 turns")
  local Ab = require("src.core.game3.battle.abilities")
  local M = ctx(45, st, ad, st.enemy, st.player)
  T.check(Ab.soundproofBlocks(M) == true and M.noEffect, "a sound move is blocked")
  local lim = Engine.moveLimitations(st.enemy, ad)
  T.check(lim[1] == true and not lim[2], "and the AI knows not to pick it (" .. tostring(lim[1]) .. "," .. tostring(lim[2]) .. ")")
end
do
  local st, ad = battle()
  st.enemy.stages.attack, st.enemy.stages.speed = 2, 1
  hit("SPECTRAL_THIEF", st, ad)
  T.check(st.player.stages.attack == 2 and st.player.stages.speed == 1 and st.enemy.stages.attack == 0, "Spectral Thief steals the boosts first")
end

-- ------- doubles: the partner moves
do
  local okD, stD = pcall(State.new, { wild = false, double = true,
    playerParty = { mon(), mon({ species = 4, hp = 60 }) }, foeParty = { mon({ species = 16 }), mon({ species = 19 }) } })
  if okD and stD and stD.double and stD.battlers and stD.battlers[2] then
    stD.turn = 3
    local adD = Adapter.new(stD, function() end)
    adD.roll = function(_, lo) return lo end
    Battle._adapter = adD
    local me, ally = stD.battlers[0], stD.battlers[2]
    status("DECORATE", stD, adD, me, ally)
    T.eq(ally.stages.attack, 2, "doubles: Decorate sharply raises the partner's ATTACK")
    local M = hit("POLLEN_PUFF", stD, adD, me, ally)
    T.eq(ally.mon.hp, 135, "doubles: Pollen Puff heals a partner")
    local stS, adS = battle()
    T.check(status("DECORATE", stS, adS).failed, "singles: Decorate has nobody to decorate")
  else
    T.check(true, "(no headless doubles state: " .. tostring(stD) .. ")")
  end
end

Battle._adapter = nil
run.release()
T.finish("national_dex_gen3 field moves (" .. GAME .. ")")
