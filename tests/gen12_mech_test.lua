-- Standalone: luajit mods/national_dex_gen3/tests/gen12_mech_test.lua [red|blue|yellow|gold|silver|crystal ...]
-- (from the gen1recomp root; runs on red, yellow, gold and crystal when none is named).
-- The mechanics layer (src/gen12/mech/, src/gen12/battle/): every newer move with no cart effect
-- runs on a mechanic of its own, through each game's adapter, and each family does what it says.
-- Battles come from tests/_gen12.lua's H.sim; "low" rolls land every accuracy and chance roll.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")
local rows = H.module("data/gen12/moves.lua")

-- the moves each game must run on the layer: no cart effect there, not doubles-only
local function expected(gen)
  local maxMove = gen == 1 and 165 or 251
  local out = {}
  for _, r in ipairs(rows) do
    if r.n > maxMove and not r["gen" .. gen] and r.mech and not r.mech.doubles then out[#out + 1] = r.id end
  end
  return out
end

for _, version in ipairs(H.versions()) do
  local sim = H.sim(version)
  local gen, data = sim.gen, sim.data
  T.check(sim.mech ~= nil, version .. ": the mechanics layer is loaded")

  -- coverage: how many of the moves that need a mechanic have one (the rest are still stand-ins)
  local want, have = expected(gen), 0
  for _, id in ipairs(want) do
    if data.moves[id] and tostring(data.moves[id].effect):find("^NDX_M_") then have = have + 1 end
  end
  print(("  %s: %d of %d newer moves run on the mechanics layer"):format(version, have, #want))
  T.eq(have + #sim.mech.missing, #want, version .. ": every such move is either real or reported missing")

  -- the adapter's facts, the same on both games
  local w = sim.fresh({ mine = "ALAKAZAM", foe = "GENGAR" })
  local A = w.A
  local me, foe = w.battler("player"), w.battler("enemy")
  T.eq(A:foe(me), foe, version .. ": A:foe")
  T.eq(A:sideName(foe), "enemy", version .. ": A:sideName")
  T.check(A:hasType(foe, "GHOST") and A:hasType(me, "PSYCHIC"), version .. ": A:types in modern names")
  T.eq(A:hp(me), A:maxHp(me), version .. ": A:hp / A:maxHp")
  A:vol(me).mark = true
  T.check(A:vol(me).mark and not A:vol(foe).mark, version .. ": A:vol is the battler's own")
  A:side(me).mark = 1
  T.check(A:side("player").mark == 1 and not A:side("enemy").mark, version .. ": A:side")
  A:field().mark = 2
  T.eq(A:field().mark, 2, version .. ": A:field")

  -- a stat change both ways, as the cart prints it; Red's SPECIAL takes Sp. Atk's
  T.check(A:stages(me, { spAtk = 2 }), version .. ": A:stages raises")
  T.eq(w.stage("player", "spAtk"), 2, version .. ": Sp. Atk +2")
  T.check(A:stages(foe, { attack = -1 }, { from = me }), version .. ": A:stages lowers the foe")
  T.eq(w.stage("enemy", "attack"), -1, version .. ": Attack -1")
  T.check(A:ailment(foe, "BURN", { from = me }) and w.status("enemy") == "BRN", version .. ": A:ailment")

  -- the `extra` moves through the layer
  w = sim.fresh()
  local hp = w.hp("enemy")
  w.use("CLOSE_COMBAT")
  T.check(w.hp("enemy") < hp and w.stage("player", "defense") == -1, version .. ": Close Combat")

  -- every move on the layer runs both ways without an error (low and high rolls)
  local failed, first = 0, nil
  for _, id in ipairs(want) do
    if data.moves[id] and tostring(data.moves[id].effect):find("^NDX_M_") then
      for _, roll in ipairs({ "low", "high" }) do
        for _, side in ipairs({ "player", "enemy" }) do
          local x = sim.fresh({ roll = roll })
          local ok, err = pcall(x.use, id, side)
          if not ok then failed = failed + 1; first = first or (id .. ": " .. tostring(err)) end
        end
      end
    end
  end
  T.eq(failed, 0, version .. ": every layer move runs" .. (first and (" -- " .. first) or ""))

  -- simple moves from PokeAPI's modern facts (src/gen12/mech/meta.lua)
  local function use(id, o)
    local x = sim.fresh(o)
    x.hp0 = x.hp("enemy")
    x.use(id)
    return x
  end
  w = use("TAIL_GLOW")
  T.eq(w.stage("player", "spAtk"), 3, version .. ": Tail Glow: Sp. Atk +3 (Gen 9)")
  w = use("CHARM")
  if gen == 2 then
    T.eq(w.stage("enemy", "attack"), -2, version .. ": Charm: Attack -2")
  else
    T.eq(w.stage("enemy", "attack"), -2, version .. ": Charm (new on Red): Attack -2")
  end
  w = use("POISON_FANG")
  T.eq(w.status("enemy"), "TOX", version .. ": Poison Fang badly poisons")
  w = use("DUAL_CHOP", { foe = "SNORLAX", level = 20, foeLevel = 70 })
  local said = table.concat(w.texts(), " | ")
  T.check(said:find("2 times") ~= nil, version .. ": Dual Chop hits twice (" .. said .. ")")
  w = use("OVERHEAT")
  T.eq(w.stage("player", "spAtk"), -2, version .. ": Overheat: the user's Sp. Atk -2")
  w = use("TOXIC_THREAD")
  T.check(w.status("enemy") == "PSN" and w.stage("enemy", "speed") == -1, version .. ": Toxic Thread")
  w = use("SWAGGER")
  T.eq(w.stage("enemy", "attack"), 2, version .. ": Swagger: the foe's Attack +2")

  -- damage-formula moves (src/gen12/mech/power.lua)
  local specs = sim.mech.specs
  local function power(id, x)
    local m = data.moves[id]
    return specs[id].power(x.A, x.battler("player"), x.battler("enemy"), m)
  end
  w = sim.fresh({ mine = "PRIMEAPE", foe = "SNORLAX", level = 50, foeLevel = 50 })
  T.eq(power("RAGE_FIST", w), 50, version .. ": Rage Fist starts at 50")
  w.use("TACKLE", "enemy"); w.use("TACKLE", "enemy")
  T.eq(power("RAGE_FIST", w), 150, version .. ": +50 for each hit taken (2)")
  T.eq(power("HEX", w), 65, version .. ": Hex 65 against a healthy target")
  w.A:ailment(w.battler("enemy"), "BURN", {})
  T.eq(power("HEX", w), 130, version .. ": Hex doubles against a status")
  T.eq(power("HEAVY_SLAM", w), 40, version .. ": Heavy Slam: light against heavy (40)")
  w = sim.fresh({ mine = "SNORLAX", foe = "PIDGEY" })
  T.eq(power("HEAVY_SLAM", w), 120, version .. ": Heavy Slam: Snorlax on a Pidgey (120)")
  T.check(power("GYRO_BALL", w) > 25, version .. ": Gyro Ball: slow user, fast target")
  w = sim.fresh({ foe = "SNORLAX", setup = function(x) x.mon("player").hp = 10 end })
  w.use("ENDEAVOR")
  T.eq(w.hp("enemy"), 10, version .. ": Endeavor cuts the target to the user's HP")
  w = sim.fresh({ foe = "SNORLAX" })
  hp = w.hp("enemy")
  w.use("SUCKER_PUNCH")
  T.eq(w.hp("enemy"), hp, version .. ": Sucker Punch fails when the target is not attacking")
  w = sim.fresh({ foe = "SNORLAX", level = 30, foeLevel = 70 })
  hp = w.hp("enemy")
  w.use("FAKE_OUT")
  T.check(w.hp("enemy") < hp, version .. ": Fake Out on the first turn")
  hp = w.hp("enemy")
  w.use("FAKE_OUT")
  T.eq(w.hp("enemy"), hp, version .. ": and only then")
  w = sim.fresh({ level = 50, foeLevel = 30 })
  w.use("SHEER_COLD")
  T.eq(w.hp("enemy"), 0, version .. ": Sheer Cold (one-hit KO)")
  w = sim.fresh({ foe = "SNORLAX", level = 50, foeLevel = 70 })
  local mine = w.hp("player")
  w.use("FINAL_GAMBIT")
  T.check(w.hp("player") == 0, version .. ": Final Gambit: the user faints (" .. mine .. ")")

  -- the field (src/gen12/mech/field.lua)
  local core = sim.mech.core
  w = sim.fresh({ mine = "GOLEM", foe = "RATTATA" })
  w.use("SANDSTORM")
  T.eq(w.A:weather(), "sand", version .. ": Sandstorm (Gold's own on Gold)")
  hp = w.hp("enemy")
  local golem = w.hp("player")
  w.endTurn()
  T.check(w.hp("enemy") < hp and w.hp("player") == golem, version .. ": the sandstorm chips a Rattata, not a Golem")
  w = sim.fresh({ foe = "RATTATA" })
  w.use("HAIL")
  T.eq(w.A:weather(), "hail", version .. ": Hail")
  hp = w.hp("enemy")
  w.endTurn()
  T.check(w.hp("enemy") < hp, version .. ": hail chips the foe")
  w = sim.fresh({ foe = "SNORLAX" })
  w.use("PROTECT", "enemy")
  hp = w.hp("enemy")
  w.use("TACKLE")
  T.eq(w.hp("enemy"), hp, version .. ": Protect stops a Tackle")
  said = table.concat(w.texts(), " | ")
  T.check(said:find("protected itself") ~= nil, version .. ": \"protected itself\"")
  w = sim.fresh({ foe = "SNORLAX" })
  w.use("STEALTH_ROCK")
  T.check(w.A:side("enemy").hazards and w.A:side("enemy").hazards.rocks, version .. ": Stealth Rock on the foe's side")
  hp = w.hp("enemy")
  core:fire("switchedIn", w.A, { battler = w.battler("enemy") })
  T.check(w.hp("enemy") < hp, version .. ": and it hurts the next one in")
  w = sim.fresh()
  local s0 = w.A:speed(w.battler("player"))
  w.use("TAILWIND")
  T.eq(core:fold("speed", s0, w.A, w.battler("player")), s0 * 2, version .. ": Tailwind doubles Speed")
  w.use("TRICK_ROOM")
  T.check(core:ask("trickRoom", w.A), version .. ": Trick Room")
  w = sim.fresh({ mine = "PIKACHU" })
  w.use("ELECTRIC_TERRAIN")
  local thunder = data.moves.THUNDERBOLT
  T.eq(core:fold("damageMult", 1, w.A, w.battler("player"), w.battler("enemy"), thunder, {}), 1.3,
    version .. ": Electric Terrain boosts a grounded Electric move")
  T.check(not w.A:ailment(w.battler("enemy"), "SLEEP", {}), version .. ": and keeps the grounded asleep... awake")
  w = sim.fresh()
  w.use("SAFEGUARD", "enemy")
  T.check(not w.A:ailment(w.battler("enemy"), "BURN", { from = w.battler("player") }), version .. ": Safeguard")
  w = sim.fresh()
  w.use("HAIL")
  w.use("AURORA_VEIL", "enemy")
  T.eq(core:fold("damageMult", 1, w.A, w.battler("player"), w.battler("enemy"), data.moves.TACKLE, {}), 0.5,
    version .. ": Aurora Veil halves a hit")

  -- conditions (src/gen12/mech/volatile.lua)
  w = sim.fresh()
  w.use("TAUNT", "enemy")
  w.use("SWORDS_DANCE")
  T.eq(w.stage("player", "attack"), 0, version .. ": Taunt stops Swords Dance")
  w = sim.fresh()
  w.use("BELLY_DRUM")
  T.check(w.stage("player", "attack") == 6 and w.hp("player") <= math.ceil(w.maxHp("player") / 2) + 1,
    version .. ": Belly Drum")
  w = sim.fresh({ foe = "CHARMANDER" })
  w.use("SOAK")
  T.check(#w.types("enemy") == 1 and w.types("enemy")[1] == "WATER", version .. ": Soak makes it Water")
  w = sim.fresh()
  w.use("MAGNET_RISE", "enemy")
  T.check(core:ask("immune", w.A, w.battler("player"), w.battler("enemy"), data.moves.EARTHQUAKE),
    version .. ": Magnet Rise: Ground moves miss it")
  w = sim.fresh({ foe = "SNORLAX", level = 30, foeLevel = 70 })
  w.use("STOCKPILE"); w.use("STOCKPILE")
  hp = w.hp("enemy")
  w.use("SPIT_UP")
  T.check(w.hp("enemy") < hp and (w.A:vol(w.battler("player")).stockpile or 0) == 0, version .. ": Stockpile, Spit Up")
  w = sim.fresh({ foe = "RATTATA" })
  w.use("WISH")
  w.mon("player").hp = 10
  w.nextTurn()
  w.endTurn()
  T.check(w.hp("player") > 10, version .. ": Wish heals the next turn")
  w = sim.fresh()
  w.use("INGRAIN")
  w.mon("player").hp = 10
  w.endTurn()
  T.check(w.hp("player") > 10, version .. ": Ingrain heals at the end of the turn")
  w = sim.fresh({ level = 50, foeLevel = 50 })
  w.use("PERISH_SONG")
  -- ours on Red counts 3; Gold's own counts 4
  for _ = 1, gen == 1 and 3 or 4 do w.endTurn() end
  T.check(w.hp("enemy") == 0, version .. ": Perish Song")
  w = sim.fresh()
  w.use("GEOMANCY")
  T.eq(w.stage("player", "spAtk"), 0, version .. ": Geomancy charges first")
  w = sim.fresh()
  w.use("HEAL_BLOCK", "enemy")
  w.mon("player").hp = 10
  w.use("RECOVER")
  T.eq(w.hp("player"), 10, version .. ": Heal Block stops Recover")

  -- switching (src/gen12/mech/switching.lua)
  w = sim.fresh({ mine = "SCYTHER", party = { "PIKACHU" }, foe = "SNORLAX", level = 30, foeLevel = 70 })
  w.use("U_TURN")
  w.flush()
  T.eq(w.A:species(w.battler("player")), "PIKACHU", version .. ": U-turn brings in the next Pokemon")
  w = sim.fresh({ party = { "PIKACHU" } })
  w.use("SWORDS_DANCE")
  w.use("BATON_PASS")
  w.flush()
  T.check(w.A:species(w.battler("player")) == "PIKACHU" and w.stage("player", "attack") == 2,
    version .. ": Baton Pass carries the stages")
  w = sim.fresh({ party = { "PIKACHU" } })
  w.use("MEAN_LOOK", "enemy")
  -- Gold's own Mean Look locks Gold's own way; Red's is ours
  T.check(gen == 2 and w.battle:switchLocked() or core:ask("trapped", w.A, w.battler("player")) ~= nil,
    version .. ": Mean Look traps")
  w = sim.fresh({ party = { "PIKACHU" } })
  w.use("NO_RETREAT")
  T.check(gen == 1 and core:ask("trapped", w.A, w.battler("player")) ~= nil or (gen == 2 and w.battle:switchLocked()),
    version .. ": No Retreat keeps the user in")

  -- natures and gender (src/gen12/mech/traits.lua)
  local Traits = core.traits
  local modest = { attack = 0, defense = 0, speed = 0, special = 15 }      -- index 15: MODEST
  T.eq(Traits.nature(modest), "MODEST", version .. ": a nature from the DVs")
  local base = { hp = 100, attack = 100, defense = 100, speed = 100, special = 100,
    specialAttack = 100, specialDefense = 100 }
  local function copyStats() local c = {} for k, v in pairs(base) do c[k] = v end return c end
  local applied = Traits.apply(copyStats(), modest, gen)
  T.eq(applied.attack, 90, version .. ": Modest lowers Attack")
  if gen == 1 then
    T.eq(applied.special, 110, version .. ": and raises Red's SPECIAL")
  else
    T.eq(applied.specialAttack, 110, version .. ": and raises Sp. Atk")
  end
  w = sim.fresh({ mine = "NIDORAN_F", foe = "NIDORAN_M" })
  T.eq(core:ask("gender", w.A, w.battler("player")), "F", version .. ": Nidoran F is female")
  T.eq(core:ask("gender", w.A, w.battler("enemy")), "M", version .. ": Nidoran M is male")
  w.use("ATTRACT")
  T.check(gen == 2 or w.A:vol(w.battler("enemy")).attract ~= nil, version .. ": Attract (Red's ours)")

  -- held items and the moves that use them (src/gen12/mech/held.lua, src/gen12/held_red.lua)
  T.check(data.items.LEFTOVERS ~= nil, version .. ": Leftovers is an item")
  w = sim.fresh()
  w.A:setItem(w.battler("player"), "LEFTOVERS")
  w.mon("player").hp = 10
  w.endTurn()
  T.check(w.hp("player") > 10, version .. ": Leftovers heals at the end of the turn")
  w = sim.fresh({ foe = "SNORLAX", level = 30, foeLevel = 70 })
  w.A:setItem(w.battler("enemy"), "LEFTOVERS")
  w.use("KNOCK_OFF")
  T.eq(w.A:item(w.battler("enemy")), nil, version .. ": Knock Off knocks the item off")
  w = sim.fresh({ foe = "SNORLAX", level = 70, foeLevel = 30 })
  w.A:setItem(w.battler("player"), "LEFTOVERS")
  w.use("KNOCK_OFF", "enemy")
  T.eq(w.A:item(w.battler("player")), nil, version .. ": your item knocked off for the battle")
  core:fire("battleEnded", w.A, {})
  T.eq(w.A:item(w.battler("player")), "LEFTOVERS", version .. ": and given back after it")
  w = sim.fresh()
  w.A:setItem(w.battler("player"), "CHARCOAL")
  w.use("TRICK")
  T.check(w.A:item(w.battler("enemy")) == "CHARCOAL" and w.A:item(w.battler("player")) == nil, version .. ": Trick")
  w = sim.fresh({ foe = "SNORLAX", level = 30, foeLevel = 70 })
  w.A:setItem(w.battler("player"), "CHARCOAL")
  w.use("FLING")
  T.eq(w.A:item(w.battler("player")), nil, version .. ": Fling throws the item")

  -- abilities (src/gen12/mech/abilities.lua): the first of the species' list for an even
  -- Defense DV, the second for an odd one
  local function first(x, side) x.mon(side).dvs.defense = 0; x.A:vol(x.battler(side)).abilityEntered = nil end
  local function second(x, side) x.mon(side).dvs.defense = 1; x.A:vol(x.battler(side)).abilityEntered = nil end
  w = sim.fresh({ mine = "GYARADOS", foe = "RATTATA" })
  first(w, "player")
  T.eq(core.abilityOf(w.A, w.battler("player")), "INTIMIDATE", version .. ": Gyarados has Intimidate")
  w.A:setStage(w.battler("enemy"), "attack", 0)
  core:fire("switchedIn", w.A, { battler = w.battler("player") })
  T.eq(w.stage("enemy", "attack"), -1, version .. ": Intimidate lowers the foe's Attack")
  w = sim.fresh({ mine = "KOFFING" })
  first(w, "player")
  T.check(core:ask("immune", w.A, w.battler("enemy"), w.battler("player"), data.moves.EARTHQUAKE),
    version .. ": Levitate: Ground moves miss")
  w = sim.fresh({ mine = "LAPRAS" })
  first(w, "player")
  w.mon("player").hp = 10
  T.check(core:ask("immune", w.A, w.battler("enemy"), w.battler("player"), data.moves.WATER_GUN)
    and w.hp("player") > 10, version .. ": Water Absorb takes Water moves and heals")
  w = sim.fresh({ mine = "MAGIKARP" })
  first(w, "player")
  local sp = w.A:speed(w.battler("player"))
  w.A:setWeather("rain", 5)
  T.eq(core:fold("speed", sp, w.A, w.battler("player")), sp * 2, version .. ": Swift Swim in the rain")
  w = sim.fresh({ mine = "GEODUDE", foe = "MACHAMP", level = 10, foeLevel = 90 })
  second(w, "player")
  T.eq(core.abilityOf(w.A, w.battler("player")), "STURDY", version .. ": Geodude's second ability, Sturdy")
  w.use("KARATE_CHOP", "enemy")
  T.eq(w.hp("player"), 1, version .. ": Sturdy survives at full HP")
  w = sim.fresh({ mine = "GYARADOS", foe = "PIKACHU" })
  first(w, "player"); first(w, "enemy")
  w.use("SKILL_SWAP")
  T.eq(core.abilityOf(w.A, w.battler("player")), "STATIC", version .. ": Skill Swap")
  -- abilities that only hold in a weather or a terrain
  w = sim.fresh({ mine = "LEAFEON" })
  first(w, "player")
  T.eq(core.abilityOf(w.A, w.battler("player")), "LEAFGUARD", version .. ": Leafeon has Leaf Guard")
  T.eq(core:ask("blockStatus", w.A, w.battler("player"), "PAR"), nil, version .. ": Leaf Guard does nothing out of the sun")
  w.A:setWeather("sun", 5)
  T.check(core:ask("blockStatus", w.A, w.battler("player"), "PAR") ~= nil, version .. ": Leaf Guard in the sun")
  w = sim.fresh({ mine = "RAICHU_ALOLA" })
  first(w, "player")
  T.eq(core.abilityOf(w.A, w.battler("player")), "SURGESURFER", version .. ": Alolan Raichu has Surge Surfer")
  sp = w.A:speed(w.battler("player"))
  T.eq(core:fold("speed", sp, w.A, w.battler("player")), sp, version .. ": Surge Surfer does nothing without a terrain")
  w.A:field().terrain = { kind = "ELECTRIC", turns = 5 }
  T.eq(core:fold("speed", sp, w.A, w.battler("player")), sp * 2, version .. ": Surge Surfer on Electric Terrain")
  -- accuracy multipliers and an ability that acts as its Pokemon leaves
  w = sim.fresh({ mine = "BUTTERFREE" })
  first(w, "player")
  T.eq(core:fold("accuracyScale", 1, w.A, w.battler("player"), w.battler("enemy"), data.moves.SLEEP_POWDER), 1.3,
    version .. ": Compound Eyes")
  w = sim.fresh({ mine = "CORSOLA" })
  first(w, "player")
  T.eq(core.abilityOf(w.A, w.battler("player")), "HUSTLE", version .. ": Corsola has Hustle")
  T.check(math.abs(core:fold("accuracyScale", 1, w.A, w.battler("player"), w.battler("enemy"), data.moves.TACKLE) - 0.8) < 1e-9,
    version .. ": Hustle: physical moves 0.8")
  w = sim.fresh({ mine = "MIENFOO" })
  second(w, "player")
  T.eq(core.abilityOf(w.A, w.battler("player")), "REGENERATOR", version .. ": Mienfoo's Regenerator")
  local max = w.A:maxHp(w.battler("player"))
  w.mon("player").hp = 1
  core:fire("switchedIn", w.A, { battler = w.battler("enemy"), previous = w.battler("player") })
  T.eq(w.mon("player").hp, 1 + math.floor(max * 0.3333), version .. ": Regenerator heals a third as it leaves")

  -- physical / special by the move (option move_split, src/gen12/mech/split.lua)
  local opts = sim.run.loader.modOptions
  opts.national_dex_gen3 = opts.national_dex_gen3 or {}
  w = sim.fresh()
  T.eq(w.A:category(data.moves.FIRE_PUNCH), "special", version .. ": off: Fire Punch is special by its type")
  opts.national_dex_gen3.move_split = true
  T.eq(w.A:category(data.moves.FIRE_PUNCH), "physical", version .. ": on: Fire Punch is physical")
  T.eq(w.A:category(data.moves.SHADOW_BALL or data.moves.NIGHT_SHADE), (data.moves.SHADOW_BALL and "special") or w.A:category(data.moves.NIGHT_SHADE),
    version .. ": on: Shadow Ball is special")
  local x = sim.fresh({ mine = "MACHAMP", foe = "SNORLAX", level = 50, foeLevel = 50 })
  hp = x.hp("enemy")
  x.use("FIRE_PUNCH")
  T.check(x.hp("enemy") < hp, version .. ": a physical Fire Punch still hits")
  opts.national_dex_gen3.move_split = nil

  -- Red's Sp. Def (src/gen12/mech/traits.lua Traits.spDef, src/gen12/battle/red.lua)
  if gen == 1 then
    w = sim.fresh({ mine = "MEWTWO", foe = "ALAKAZAM", level = 50 })
    local Traits = core.traits
    local mew = w.mon("player")
    mew.dvs = { attack = 0, defense = 0, speed = 0, special = 0, hp = 0 }  -- Hardy: no nature change
    T.eq(Traits.nature(mew.dvs), "HARDY", version .. ": a neutral nature for the numbers")
    T.eq(Traits.spDef(mew, data), math.floor(90 * 2 * 50 / 100) + 5, version .. ": Mewtwo's Sp. Def from its base 90")
    local chansey = w.battler("enemy")
    local spd = w.A:stat(chansey, "spDef")
    T.check(spd < w.A:stat(chansey, "spAtk"), version .. ": Alakazam defends with its Sp. Def (base 95), below its SPECIAL (135)")
    local psy = data.moves.PSYCHIC_M or data.moves.PSYCHIC
    local tb = w.battle
    local before = tb:computeDamage(tb.player, chansey, psy, { rng = tb.rng, forceCrit = false })
    w.A:stages(chansey, { spDef = -2 })
    T.eq(w.A:stage(chansey, "spDef"), -2, version .. ": Sp. Def has its own stage")
    T.eq(chansey.stages.special or 0, 0, version .. ": the SPECIAL (Sp. Atk) stage is untouched")
    local after = tb:computeDamage(tb.player, chansey, psy, { rng = tb.rng, forceCrit = false })
    T.check(after > before, version .. ": a lowered Sp. Def lets a special move hit harder")
    T.eq(chansey.curStats.special, chansey.mon.stats.special, version .. ": the SPECIAL is put back after the hit")
    w.A:stages(w.battler("player"), { spAtk = 1 })
    T.eq(w.A:stage(w.battler("player"), "spAtk"), 1, version .. ": Sp. Atk changes are the SPECIAL's")
  end

  -- Modern Rules on Red (src/gen12/modern_rules.lua, option modern_rules, on by default)
  if gen == 1 then
    local MR = sim.api and sim.api._modernRules
    T.check(MR ~= nil, version .. ": Modern Rules installed")
    local ours = MR and data.rulesets and data.rulesets[MR.ID]
    T.check(ours ~= nil and ours.hidden == true and ours.oneIn256Miss == false and ours.focusEnergyBug == false,
      version .. ": its ruleset is registered, hidden from the game's own list")
    w = sim.fresh({ mine = "MACHAMP", foe = "SNORLAX", level = 50 })
    sim.run.loader.events:emit("battle.started", { battle = w.battle })
    T.check(ours ~= nil and w.battle.ruleset == ours, version .. ": a battle takes it when it starts")
    local tb, punch = w.battle, data.moves.STRENGTH
    local base = tb:computeDamage(tb.player, tb.enemy, punch, { rng = tb.rng, forceCrit = false })
    local crit = tb:computeDamage(tb.player, tb.enemy, punch, { rng = tb.rng })
    T.eq(crit, math.floor(base * 3 / 2), version .. ": a critical hit does 1.5x")
    T.eq(tb:computeDamage(tb.player, tb.enemy, punch, { rng = function(a, b) if b == 24 then return 24 end return a end }),
      base, version .. ": 23 rolls in 24 are not critical")
    T.eq(MR.CRIT_ODDS[MR.critStage({ focusEnergy = true }, { highCrit = true }) + 1], 1, version .. ": Focus Energy + a high-critical move always crits")
    opts.national_dex_gen3.modern_rules = false
    local w2 = sim.fresh({ mine = "MACHAMP", foe = "SNORLAX", level = 50 })
    sim.run.loader.events:emit("battle.started", { battle = w2.battle })
    T.check(w2.battle.ruleset ~= ours, version .. ": off: the game's own ruleset")
    opts.national_dex_gen3.modern_rules = nil
  end

  -- breeding on Red (src/gen12/breeding_red.lua)
  if gen == 1 then
    local Breeding = H.module("src/gen12/breeding_red.lua")
    local facts = H.module("data/gen12/battle.lua")
    local pikaF = { dex = 25, groups = facts.eggGroups[25], gender = "F" }
    local pikaM = { dex = 25, groups = facts.eggGroups[25], gender = "M" }
    local ditto = { dex = 132, groups = facts.eggGroups[132] }
    T.eq(Breeding.chance(pikaF, pikaM), 70, version .. ": two Pikachu get along very well")
    T.eq(Breeding.chance(pikaF, pikaF), 0, version .. ": not two of one gender")
    T.eq(Breeding.chance(pikaM, ditto), 20, version .. ": anything with Ditto")
    T.eq(Breeding.babyOf(facts, pikaF, pikaM), 172, version .. ": a Pikachu EGG hatches into Pichu")
    T.eq(Breeding.babyOf(facts, { dex = 143, groups = facts.eggGroups[143], gender = "F" }, ditto), 143,
      version .. ": a Snorlax EGG hatches into Snorlax (no Full Incense here)")
    local Game = require("src.core.Game")
    local st = Breeding.stateOf(Game.save)
    local before = #Game.save.party
    st.egg = { dex = 172, stepsLeft = 1, moves = {} }
    require("src.mods.Runtime").emit("world.stepped", {})
    T.check(#Game.save.party == before + 1 and Game.save.party[#Game.save.party].species == "PICHU",
      version .. ": the carried EGG hatches into the party")
    T.check(st.egg == nil, version .. ": and is gone")
  end
  sim.release()
end

T.finish("national_dex_gen3 Gen 1/2 mechanics layer")
