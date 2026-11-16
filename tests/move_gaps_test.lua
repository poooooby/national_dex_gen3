-- Standalone: luajit mods/national_dex_gen3/tests/move_gaps_test.lua [game] (from the gen1recomp
-- root; needs that cart imported, FireRed by default).
--
-- The newer moves, abilities and held items on FireRed to Emerald, each run as a whole move
-- through the engine (Engine.resolveMove: the real accuracy check, hit, added effects and the
-- battle's own text), where the other suites stand the hit in: the gaps an audit found
-- (2026-11-16) stay fixed.
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
local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Residuals = require("src.core.game3.battle.residuals")
local Battle = require("src.core.game3.battle")
-- the battle's text by key (headless Ruby lacks some of the cart's strings); a missing key stops
-- the battle, as the real lookup does
Adapter.textSink = function(id)
  assert(id ~= nil, "no message for a nil text id")
  return id
end

local byId = {}
for _, r in ipairs(dofile("mods/national_dex_gen3/data/moves.lua")) do byId[r.id] = r end
local function num(id) return type(id) == "number" and id or byId[id].index end

local function mon(extra)
  local m = { species = 25, level = 50, hp = 300, maxHp = 300, moves = { 33 }, pp = { 35 },
              attack = 100, defense = 100, spAtk = 100, spDef = 100, speed = 100, personality = 0 }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end
-- a wild battle; rolls in the middle of their range (hits land, 100% effects happen, chances
-- under 50% do not)
local function battle(opts)
  opts = opts or {}
  local st = State.new({ wild = true, playerParty = opts.party or { mon() }, foeMon = opts.foe or mon() })
  st.turn = 3
  local ad = Adapter.new(st, function() end)
  ad.roll = opts.roll or function(_, lo, hi) return math.floor((lo + (hi or lo)) / 2) end
  Battle._adapter = ad
  local said = {}
  local say = ad.say
  ad.say = function(self, s, ...) said[#said + 1] = tostring(s); return say(self, s, ...) end
  return st, ad, said
end
-- the player's Pokemon uses `id` on the foe (or `user` on `target`); nil, or the error
local function use(st, ad, id, user, target)
  local ok, err = pcall(Engine.resolveMove, user or st.player, target or st.enemy, num(id), 1, ad, st, {}, {})
  return not ok and tostring(err) or nil
end

-- ------- the newer binding moves: trapped, with their own message (the cart had no text for them)
for _, id in ipairs({ "INFESTATION", "SNAP_TRAP", "THUNDER_CAGE", "MAGMA_STORM" }) do
  local st, ad = battle()
  T.eq(use(st, ad, id), nil, id .. " runs to the end")
  T.check((st.enemy.expTrapTurns or 0) > 0, id .. " traps the foe")
end

-- ------- moves that can't miss (accuracy 0): the engine read it as a 0% chance
do
  local st, ad = battle()
  use(st, ad, "PLAY_NICE")
  T.eq(st.enemy.stages.attack, -1, "Play Nice lands")
  local st2, ad2 = battle()
  use(st2, ad2, "DEFOG")
  T.eq(st2.enemy.stages.evasion, -1, "Defog lands")
end

-- ------- abilities that guard their holder only against moves aimed at it
local function withAbility(ad, b, name)
  local of = ad.abilityOf
  ad.abilityOf = function(self, x) if x == b then return name end return of(self, x) end
end
do
  local st, ad = battle()
  withAbility(ad, st.player, "GOOD_AS_GOLD")
  use(st, ad, 14, st.enemy, st.player)                                   -- the foe's SWORDS DANCE
  T.eq(st.enemy.stages.attack, 2, "Good as Gold lets the foe's Swords Dance work")
  use(st, ad, 45, st.enemy, st.player)                                   -- GROWL at it
  T.eq(st.player.stages.attack, 0, "but blocks Growl")
  local st2, ad2 = battle()
  withAbility(ad2, st2.player, "QUEENLY_MAJESTY")
  use(st2, ad2, 182, st2.enemy, st2.player)                              -- the foe's PROTECT
  T.check(st2.enemy.expProtected, "Queenly Majesty lets the foe's Protect work")
  local hp = st2.player.mon.hp
  use(st2, ad2, 98, st2.enemy, st2.player)                               -- QUICK ATTACK at it
  T.eq(st2.player.mon.hp, hp, "but blocks Quick Attack")
end

-- ------- Electromorphosis: charged by a hit, as after Charge, and it wears off
do
  local st, ad = battle()
  withAbility(ad, st.player, "ELECTROMORPHOSIS")
  use(st, ad, 33, st.enemy, st.player)                                   -- TACKLE at it
  T.eq(st.player.expCharged, 2, "Electromorphosis: a hit charges it")
  for _ = 1, 2 do Residuals.runTurn(ad) end
  T.eq(st.player.expCharged, nil, "and the charge runs out")
end

-- ------- held items whose effect the Gen 3 path never asked for (src/held/gen3.lua)
local ITEM = {}
for _, r in ipairs(dofile("mods/national_dex_gen3/data/held_items.lua")) do ITEM[r.id] = r.index end
-- what `fn(st, ad)` measures without the item and with it on `who` ("player" / "enemy")
local function withItem(id, who, opts, fn)
  local function once(item)
    local st, ad = battle(opts and opts())
    if item then (who == "enemy" and st.enemy or st.player).item = ITEM[id] end
    return fn(st, ad)
  end
  return once(false), once(true)
end
do
  local a, b = withItem("LIGHT_CLAY", "player", nil, function(st, ad)
    use(st, ad, 115, st.player, st.player); return st.playerSide.expReflectTurns end)
  T.check(a == 5 and b == 8, "Light Clay: Reflect lasts 8 turns (" .. tostring(a) .. " / " .. tostring(b) .. ")")
  a, b = withItem("DAMP_ROCK", "player", nil, function(st, ad)
    use(st, ad, 240, st.player, st.player); return st.weatherTurns end)
  T.check(a == 5 and b == 8, "Damp Rock: Rain Dance lasts 8 turns (" .. tostring(a) .. " / " .. tostring(b) .. ")")
  a, b = withItem("SAFETY_GOGGLES", "enemy", nil, function(st, ad)
    st.weather, st.weatherTurns = "SAND", 5
    local hp = st.enemy.mon.hp
    Residuals.runTurn(ad)
    return hp - st.enemy.mon.hp end)
  T.check(a > 0 and b == 0, "Safety Goggles: no sandstorm damage (" .. a .. " / " .. b .. ")")
  a, b = withItem("RING_TARGET", "enemy", function() return { foe = mon({ species = 92 }) } end, function(st, ad)
    local hp = st.enemy.mon.hp; use(st, ad, 33); return hp - st.enemy.mon.hp end)
  T.check(a == 0 and b > 0, "Ring Target: Tackle hits a Ghost holder (" .. a .. " / " .. b .. ")")
  a, b = withItem("IRON_BALL", "enemy", function() return { foe = mon({ species = 16 }) } end, function(st, ad)
    local hp = st.enemy.mon.hp; use(st, ad, 89); return hp - st.enemy.mon.hp end)
  T.check(a == 0 and b > 0, "Iron Ball: Earthquake hits a Flying holder (" .. a .. " / " .. b .. ")")
  a, b = withItem("COVERT_CLOAK", "enemy", function() return { foe = mon({ species = 1 }) } end, function(st, ad)
    use(st, ad, 85); return ad:status(st.enemy) end)                     -- THUNDERBOLT, a middling roll
  T.check(b == nil, "Covert Cloak: no added paralysis (" .. tostring(a) .. " / " .. tostring(b) .. ")")
  a, b = withItem("PROTECTIVE_PADS", "player", nil, function(st, ad)
    withAbility(ad, st.enemy, "ROUGH_SKIN")
    local hp = st.player.mon.hp; use(st, ad, 33); return hp - st.player.mon.hp end)
  T.check(a > 0 and b == 0, "Protective Pads: no Rough Skin damage (" .. a .. " / " .. b .. ")")
  a, b = withItem("BIG_ROOT", "player", function() return { party = { mon({ hp = 20 }) } } end, function(st, ad)
    use(st, ad, 202); return st.player.mon.hp - 20 end)                  -- GIGA DRAIN
  T.check(b > a, "Big Root: Giga Drain heals more (" .. a .. " / " .. b .. ")")
  a, b = withItem("FLOAT_STONE", "enemy", function() return { foe = mon({ species = 68 }) } end, function(st, ad)
    local hp = st.enemy.mon.hp; use(st, ad, 67); return hp - st.enemy.mon.hp end)   -- LOW KICK, Machamp
  T.check(b < a, "Float Stone: a lighter holder takes a weaker Low Kick (" .. a .. " / " .. b .. ")")
  a, b = withItem("LOADED_DICE", "player", nil, function(st, ad)
    local hp = st.enemy.mon.hp; use(st, ad, 331); return hp - st.enemy.mon.hp end)  -- BULLET SEED
  T.check(b > a, "Loaded Dice: more hits (" .. a .. " / " .. b .. ")")
  a, b = withItem("UTILITY_UMBRELLA", "player", nil, function(st, ad)
    st.weather, st.weatherTurns = "RAINY", 5
    local hp = st.enemy.mon.hp; use(st, ad, 55); return hp - st.enemy.mon.hp end)   -- WATER GUN in rain
  T.check(b < a, "Utility Umbrella: no rain boost (" .. a .. " / " .. b .. ")")
end

-- ------- the abilities' status guards where the cart forces or passes on a status
do
  local Ab = require("src.core.game3.battle.abilities")
  for _, k in ipairs({ "COMATOSE", "PURIFYING_SALT", "SWEET_VEIL" }) do
    local st, ad = battle()
    withAbility(ad, st.enemy, k)
    use(st, ad, 281)                                                     -- YAWN
    T.eq(st.enemy.expYawnTurns, nil, k .. ": Yawn fails")
  end
  local st, ad = battle()
  withAbility(ad, st.player, "LEAF_GUARD")
  st.weather, st.weatherTurns = "SUN", 5
  Ab.applyStatus(ad, st.enemy, st.player, "PAR", false, nil)            -- Static's way
  T.eq(ad:status(st.player), nil, "Leaf Guard in the sun: no paralysis from an ability")
  local st2, ad2 = battle({ party = { mon({ species = 1 }) } })          -- Bulbasaur, Grass
  withAbility(ad2, st2.player, "FLOWER_VEIL")
  T.eq((ad2:canApplyStatus(st2.player, "BRN")), false, "Flower Veil: a Grass type can't be burned")
  local st3, ad3 = battle()
  withAbility(ad3, st3.player, "OVERCOAT")
  withAbility(ad3, st3.enemy, "EFFECT_SPORE")
  Ab.applyStatus(ad3, st3.enemy, st3.player, "SLP", false, nil)
  T.eq(ad3:status(st3.player), nil, "Overcoat keeps Effect Spore off")
end

-- ------- stat-drop guards against a 100% added drop (Icy Wind)
do
  local st, ad = battle()
  withAbility(ad, st.enemy, "FULL_METAL_BODY")
  use(st, ad, 196)                                                       -- ICY WIND
  T.eq(st.enemy.stages.speed, 0, "Full Metal Body stops Icy Wind's Speed drop")
  local st2, ad2 = battle()
  use(st2, ad2, 196)
  T.eq(st2.enemy.stages.speed, -1, "(which lowers it otherwise)")
end

-- ------- what an ability remembers: a lead's item for Unburden; a busted Disguise past a switch
do
  local Ab = require("src.core.game3.battle.abilities")
  local st, ad = battle()
  st.player.item = 139                                                   -- a held berry
  Ab.switchIn(ad, st.player)                                             -- the battle's start
  T.eq(st.player.__ndxAbItemAtEntry, 139, "Unburden: a lead's item is noted at the start")
  local st2, ad2 = battle()
  withAbility(ad2, st2.enemy, "DISGUISE")
  local hp = st2.enemy.mon.hp
  use(st2, ad2, 33)
  T.eq(st2.enemy.mon.hp, hp - math.floor(300 / 8), "Disguise takes the first hit (an eighth of its HP, Gen 8 on)")
  hp = st2.enemy.mon.hp
  -- the same Pokemon back in: a new battler (the cart builds one on every switch)
  local again = {}
  for k, v in pairs(st2.enemy) do
    if not (type(k) == "string" and k:find("^__ndx")) then again[k] = v end    -- none of ours carried
  end
  st2.enemy = again
  withAbility(ad2, again, "DISGUISE")
  use(st2, ad2, 33, st2.player, again)
  local st3, ad3 = battle()
  local plain = st3.enemy.mon.hp
  use(st3, ad3, 33)
  plain = plain - st3.enemy.mon.hp                                       -- Tackle, no Disguise
  T.check(plain ~= math.floor(300 / 8) and hp - again.mon.hp == plain,
    "and stays busted after a switch: a plain hit (" .. (hp - again.mon.hp) .. " / " .. plain .. ")")
end

-- ------- the turn order: a priority of ours decides (Triage); our Speed starts from the cart's
local function first(st, a, aMove, b, bMove)
  return run.loader.hooks:call("battle.turn_order", function() return false end, a, aMove, b, bMove, { battle = st })
end
do
  local st, ad = battle({ party = { mon({ speed = 50 }) }, foe = mon({ speed = 200 }) })
  withAbility(ad, st.player, "TRIAGE")
  local Moves3 = require("src.core.game3.battle.moves")
  T.eq(first(st, st.player, Moves3.get(202), st.enemy, Moves3.get(98)), true,
    "Triage: Giga Drain goes before a faster Quick Attack")
  local st2, ad2 = battle({ party = { mon({ speed = 50 }) }, foe = mon({ speed = 150 }) })
  withAbility(ad2, st2.player, "SWIFT_SWIM")
  st2.weather, st2.weatherTurns = "RAINY", 5
  st2.playerSide.__ndx = { tailwind = 3 }
  T.eq(first(st2, st2.player, Moves3.get(33), st2.enemy, Moves3.get(33)), true,
    "Swift Swim in the rain counts with Tailwind (50 x2 x2 beats 150)")
end

-- ------- Sheer Force, Infiltrator, Guard Dog, Wind Rider, Bulletproof
do
  local st, ad = battle()
  withAbility(ad, st.player, "SHEER_FORCE")
  st.player.item = ITEM.LIFE_ORB
  local hp = st.player.mon.hp
  use(st, ad, "FLAME_CHARGE")
  T.eq(st.player.mon.hp, hp, "Sheer Force: no Life Orb recoil on a move it powered")
  T.eq(st.player.stages.speed, 0, "and Flame Charge's sure Speed boost is gone")
  use(st, ad, 33)                                                        -- TACKLE
  T.check(st.player.mon.hp < hp, "but Life Orb still hurts after a plain move")
  local function veiled(infiltrator)
    local s2, a2 = battle()
    if infiltrator then withAbility(a2, s2.player, "INFILTRATOR") end
    s2.enemySide.__ndx = { auroraVeil = 5 }
    local h = s2.enemy.mon.hp; use(s2, a2, 33); return h - s2.enemy.mon.hp
  end
  local s3, a3 = battle()
  local h3 = s3.enemy.mon.hp; use(s3, a3, 33)
  local plain, through, halved = h3 - s3.enemy.mon.hp, veiled(true), veiled(false)
  T.check(math.abs(through - plain) <= 1 and halved < through,
    "Infiltrator hits through Aurora Veil (" .. through .. " / " .. plain .. " / veiled " .. halved .. ")")
  local s4, a4, said4 = battle()
  withAbility(a4, s4.enemy, "GUARD_DOG")
  use(s4, a4, 46)                                                        -- ROAR
  local anchored = false
  for _, line in ipairs(said4) do if line:find("anchors") then anchored = true end end
  T.check(anchored, "Guard Dog anchors against Roar")
  local s5, a5 = battle()
  withAbility(a5, s5.player, "WIND_RIDER")
  use(s5, a5, "TAILWIND", s5.player, s5.player)
  T.eq(s5.player.stages.attack, 1, "Wind Rider: Tailwind raises its Attack")
  local s6, a6 = battle()
  withAbility(a6, s6.enemy, "BULLETPROOF")
  local h6 = s6.enemy.mon.hp
  use(s6, a6, 350)                                                       -- ROCK BLAST
  T.eq(s6.enemy.mon.hp, h6, "Bulletproof stops Rock Blast")
end

-- ------- abilities that can't be suppressed, overwritten or copied; Ability Shield; Mold Breaker
do
  local function holding(b, name) b.expTracedAbility = name end           -- the cart's own way
  local st, ad = battle()
  holding(st.enemy, "DISGUISE")
  use(st, ad, "GASTRO_ACID")
  T.eq(st.enemy.expAbilitySuppressed, nil, "Gastro Acid fails on Disguise")
  local st2, ad2, said2 = battle()
  holding(st2.enemy, "COMATOSE")
  use(st2, ad2, "WORRY_SEED")
  T.eq(st2.enemy.expTracedAbility, "COMATOSE", "Worry Seed can't overwrite Comatose")
  local st3, ad3 = battle()
  holding(st3.enemy, "DISGUISE")
  use(st3, ad3, 285)                                                      -- SKILL SWAP
  T.eq(st3.enemy.expTracedAbility, "DISGUISE", "Skill Swap can't take Disguise")
  local st4, ad4 = battle()
  holding(st4.enemy, "MULTITYPE")
  use(st4, ad4, 272)                                                      -- ROLE PLAY
  T.check(st4.player.expTracedAbility ~= "MULTITYPE", "Role Play can't copy Multitype")
  local st5, ad5 = battle()
  st5.enemy.item = ITEM.ABILITY_SHIELD
  use(st5, ad5, "GASTRO_ACID")
  T.eq(st5.enemy.expAbilitySuppressed, nil, "Ability Shield keeps Gastro Acid off")
  local st6, ad6 = battle()
  use(st6, ad6, "GASTRO_ACID")
  T.eq(st6.enemy.expAbilitySuppressed, true, "(which works otherwise)")
  -- Mold Breaker gets through Disguise: a full hit, not the eighth
  local st7, ad7 = battle()
  holding(st7.player, "MOLD_BREAKER")
  holding(st7.enemy, "DISGUISE")
  local hp = st7.enemy.mon.hp
  use(st7, ad7, 33)
  local st8, ad8 = battle()
  local hp8 = st8.enemy.mon.hp
  use(st8, ad8, 33)
  local through, plain = hp - st7.enemy.mon.hp, hp8 - st8.enemy.mon.hp
  T.check(math.abs(through - plain) <= 1 and through ~= math.floor(300 / 8),
    "Mold Breaker hits through Disguise (" .. through .. " / " .. plain .. ")")
end

-- ------- move details: Freeze-Dry
do
  local st, ad = battle({ foe = mon({ species = 7 }) })                  -- Squirtle, Water
  local hp = st.enemy.mon.hp
  use(st, ad, "FREEZE_DRY")
  local onWater = hp - st.enemy.mon.hp
  local st2, ad2 = battle({ foe = mon({ species = 19 }) })               -- Rattata, Normal
  local hp2 = st2.enemy.mon.hp
  use(st2, ad2, "FREEZE_DRY")
  local onNormal = hp2 - st2.enemy.mon.hp
  T.check(onWater > onNormal * 1.5, "Freeze-Dry is super effective on Water (" .. onWater .. " / " .. onNormal .. ")")
end

-- ------- foe-aimed status moves stop at Protect
do
  for _, id in ipairs({ "NOBLE_ROAR", "POWER_SWAP" }) do
    local st, ad = battle()
    use(st, ad, 182, st.enemy, st.enemy)                                  -- the foe's PROTECT
    st.player.stages.attack = 2
    use(st, ad, id)
    T.check((st.enemy.stages.attack or 0) == 0 and (st.enemy.stages.spAtk or 0) == 0,
      id .. " stops at Protect")
  end
  local st, ad = battle()
  use(st, ad, "NOBLE_ROAR")
  T.eq(st.enemy.stages.attack, -1, "(Noble Roar lowers Attack otherwise)")
end

T.finish("national_dex_gen3 move gaps (" .. GAME .. ")")
