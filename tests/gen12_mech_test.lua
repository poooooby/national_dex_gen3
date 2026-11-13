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
  sim.release()
end

T.finish("national_dex_gen3 Gen 1/2 mechanics layer")
