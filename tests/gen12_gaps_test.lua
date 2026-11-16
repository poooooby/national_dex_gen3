-- Standalone: luajit mods/national_dex_gen3/tests/gen12_gaps_test.lua [red|yellow|gold|crystal ...]
-- (from the gen1recomp root; needs those carts imported; red, yellow, gold, crystal by default).
--
-- The gaps an audit of the Red to Crystal mechanics found (2026-11-16), each in a simulated battle
-- (tests/_gen12.lua H.sim): abilities whose data could not say when they act, and the game's own
-- paths that went past the mechanics' hooks. They stay fixed.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")

for _, version in ipairs(H.versions()) do
  local sim = H.sim(version)
  local core = sim.mech.core
  local function as(w, side, id) w.A:vol(w.battler(side)).ability = id end
  local function damage(w, move, side)
    local other = side == "enemy" and "player" or "enemy"
    local hp = w.hp(other)
    w.use(move, side)
    return hp - w.hp(other)
  end
  local function v(s) return version .. ": " .. s end

  -- ------- abilities that act only after something happens: the damage multiplier the mechanics
  -- give a move (the game's own rolls left out)
  local function mult(w, move)
    return core:fold("damageMult", 1, w.A, w.battler("player"), w.battler("enemy"), sim.data.moves[move], {})
  end
  do
    local w = sim.fresh({ mine = "CHARMANDER", foe = "SLOWPOKE", level = 50 })
    local plain = mult(w, "EMBER")
    as(w, "player", "FLASHFIRE")
    T.eq(mult(w, "EMBER"), plain, v("Flash Fire does nothing before it takes a Fire move"))
    w.use("EMBER", "enemy")
    T.check(w.A:vol(w.battler("player")).flashFire, v("then a Fire move powers it up"))
    T.eq(mult(w, "EMBER"), plain * 1.5, v("and its Fire moves hit 1.5x harder"))

    w = sim.fresh({ mine = "PIKACHU", foe = "SLOWPOKE", level = 50 })
    local base = mult(w, "THUNDERSHOCK")
    as(w, "player", "ELECTROMORPHOSIS")
    T.eq(mult(w, "THUNDERSHOCK"), base, v("Electromorphosis does nothing before it is hit"))
    w.use("TACKLE", "enemy")
    T.check(w.A:vol(w.battler("player")).charged, v("then a hit charges it"))

    w = sim.fresh({ mine = "MACHOP", foe = "SLOWPOKE", level = 50 })
    local str = mult(w, "STRENGTH")
    as(w, "player", "SLOWSTART")
    T.eq(mult(w, "STRENGTH"), str * 0.5, v("Slow Start halves Attack at first"))
    for _ = 1, 5 do w.nextTurn() end
    T.eq(mult(w, "STRENGTH"), str, v("and not after five turns"))

    -- conditions the data spells out: Rivalry by gender (one factor, or none), Fluffy by contact
    w = sim.fresh({ mine = "NIDORAN_M", foe = "SLOWPOKE", level = 50 })
    local t0 = mult(w, "TACKLE")
    as(w, "player", "RIVALRY")
    local r = mult(w, "TACKLE") / t0
    T.check(r == 1 or math.abs(r - 1.25) < 1e-9 or math.abs(r - 0.75) < 1e-9, v("Rivalry: one factor (" .. r .. ")"))
    w = sim.fresh({ mine = "CHARMANDER", foe = "SLOWPOKE", level = 50 })
    local tackle, ember = mult(w, "TACKLE"), mult(w, "EMBER")
    as(w, "enemy", "FLUFFY")
    T.eq(mult(w, "TACKLE"), tackle * 0.5, v("Fluffy halves a contact move"))
    T.eq(mult(w, "EMBER"), ember * 2, v("and doubles Fire, which makes no contact"))
  end

  -- ------- what a hit does back
  do
    local w = sim.fresh({ foe = "SLOWPOKE" })
    as(w, "player", "COTTONDOWN")
    w.use("TACKLE", "enemy")
    T.eq(w.stage("enemy", "speed"), -1, v("Cotton Down lowers the attacker's Speed"))
    T.eq(w.stage("player", "speed"), 0, v("not its own"))
    w = sim.fresh({ foe = "SLOWPOKE", roll = "high" })
    as(w, "player", "ANGERPOINT")
    w.use("TACKLE", "enemy")
    T.eq(w.stage("player", "attack"), 0, v("Anger Point ignores a hit that is not critical"))
    w = sim.fresh({ foe = "SLOWPOKE" })
    as(w, "player", "STAMINA")
    w.use("TACKLE", "enemy")
    T.eq(w.stage("player", "defense"), 1, v("Stamina raises Defense when hit"))
    w = sim.fresh({ foe = "SLOWPOKE" })
    as(w, "player", "WEAKARMOR")
    w.use("EMBER", "enemy")
    T.eq(w.stage("player", "speed"), 0, v("Weak Armor ignores a special hit"))
    w.use("TACKLE", "enemy")
    T.eq(w.stage("player", "speed"), 2, v("but not a physical one"))
    w = sim.fresh({ foe = "SLOWPOKE" })
    as(w, "player", "SEEDSOWER")
    w.use("TACKLE", "enemy")
    T.eq(w.A:field().terrain and w.A:field().terrain.kind, "GRASSY", v("Seed Sower turns the field grassy"))
    w = sim.fresh({ foe = "SLOWPOKE" })
    as(w, "player", "THERMALEXCHANGE")
    w.use("EMBER", "enemy")
    T.eq(w.stage("player", "attack"), 1, v("Thermal Exchange: a Fire hit raises Attack"))
  end

  -- ------- the attacker's own
  do
    local w = sim.fresh({ foe = "SLOWPOKE" })
    as(w, "player", "POISONTOUCH")
    -- every roll low (Gold's simulator lifts every fourth, which lands on this one)
    if type(w.battle.random) == "function" then w.battle.random = function() return 0 end end
    w.use("TACKLE")
    T.eq(w.status("enemy"), "PSN", v("Poison Touch poisons on contact"))
    w = sim.fresh({ foe = "SLOWPOKE" })
    as(w, "player", "MOXIE")
    w.A:damage(w.battler("enemy"), w.hp("enemy") - 1)
    w.use("TACKLE")
    T.eq(w.stage("player", "attack"), 1, v("Moxie: a knock-out raises Attack"))
    w = sim.fresh()
    as(w, "player", "SIMPLE")
    w.use("SWORDS_DANCE")
    T.eq(w.stage("player", "attack"), 4, v("Simple doubles Swords Dance"))
  end

  -- ------- at the end of the turn
  do
    local w = sim.fresh()
    as(w, "player", "HYDRATION")
    w.A:ailment(w.battler("player"), "PARALYSIS", {})
    w.A:setWeather("rain", 5, "")
    w.endTurn()
    T.eq(w.status("player"), nil, v("Hydration cures in the rain"))
    w = sim.fresh()
    as(w, "player", "DRYSKIN")
    w.A:setWeather("sun", 5, "")
    local hp = w.hp("player")
    w.endTurn()
    T.check(w.hp("player") < hp, v("Dry Skin hurts in the sun"))
  end
  -- ------- the game's own end-of-turn damage: Magic Guard, Poison Heal, Heatproof, Liquid Ooze
  -- (the game's ticks, run as its turn runs them: Red after each mover, Gold between turns)
  local function tick(w, side)
    local other = side == "enemy" and "player" or "enemy"
    if sim.gen == 1 then
      w.battle:residualFor(w.battler(side), w.battler(other))
      w.flush()
    else
      w.battle:tickStatus(w.battler(side))
      w.battle:tickSeedAndCurse(w.battler(side))
    end
    w.endTurn()
  end
  do
    local function poisoned(ability)
      local w = sim.fresh({ foe = "SLOWPOKE" })
      if ability then as(w, "player", ability) end
      w.A:ailment(w.battler("player"), "POISON", {})
      w.A:damage(w.battler("player"), 10)
      local hp = w.hp("player")
      tick(w, "player")
      return w.hp("player") - hp
    end
    local plain = poisoned(nil)
    T.check(plain < 0, v("(poison hurts at the end of the turn: " .. plain .. ")"))
    T.eq(poisoned("MAGICGUARD"), 0, v("Magic Guard takes no poison damage"))
    T.check(poisoned("POISONHEAL") > 0, v("Poison Heal heals while poisoned"))
    local w = sim.fresh({ foe = "SLOWPOKE" })
    as(w, "player", "POISONHEAL")
    w.A:damage(w.battler("player"), 10)
    local hp = w.hp("player")
    tick(w, "player")
    T.eq(w.hp("player"), hp, v("and not otherwise"))
    -- both burns on one Pokemon (a fresh battle rolls new stats, and so new max HP)
    local x = sim.fresh({ foe = "SLOWPOKE" })
    x.A:ailment(x.battler("player"), "BURN", {})
    local h0 = x.hp("player")
    tick(x, "player")
    local full = h0 - x.hp("player")
    as(x, "player", "HEATPROOF")
    local h1 = x.hp("player")
    tick(x, "player")
    local half = h1 - x.hp("player")
    T.check(full > 0 and math.abs(half * 2 - full) <= 1, v("Heatproof halves the burn (" .. half .. " / " .. full .. ")"))
    w = sim.fresh({ foe = "SLOWPOKE" })
    as(w, "enemy", "LIQUIDOOZE")
    w.use("LEECH_SEED")
    w.A:damage(w.battler("player"), 20)
    hp = w.hp("player")
    tick(w, "enemy")
    T.check(w.hp("player") < hp, v("Leech Seed into Liquid Ooze hurts the seeder"))
  end
  sim.release()
end
T.finish("national_dex_gen3 Gen 1/2 gaps")
