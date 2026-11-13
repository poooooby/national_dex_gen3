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
  sim.release()
end

T.finish("national_dex_gen3 Gen 1/2 mechanics layer")
