-- Standalone: luajit mods/national_dex_gen3/tests/companion_item_test.lua
-- (from the gen1recomp root; needs Pokemon FireRed imported under firered/).
--
-- An evolution step whose item FireRed does not have is never dropped for
-- good: it waits, and lights up the moment ANY mod registers a matching
-- item -- loaded before national_dex_gen3 or after it, this boot or a later
-- one -- with no code of its own and no re-release of this mod. Proven
-- end-to-end with Rhydon -> Rhyperior, which needs a Protector
-- (data/species/crossgen.lua); tests/fixtures/item_mod adds one. Nosepass ->
-- Probopass (Thunder Stone, which FireRed already has) is the control:
-- always live, with or without the companion mod.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")

-- RHYDON is Gen 1/2 (dex <= 251), where FireRed's internal species slot
-- equals the dex number. NOSEPASS is Hoenn: its dex (299) is NOT its
-- internal slot -- 25 unused placeholder slots (252-276) sit between Gen 2
-- and Hoenn on the cart -- so its slot has to be looked up by name, the same
-- way species.lua's own byDex does it. PROBOPASS is this mod's own species
-- (#476), always at dex + 64 by this mod's own numbering.
local RHYDON, RHYPERIOR_SLOT = 112, 464 + 64
local PROBOPASS_SLOT = 476 + 64

local function liveRow(P, sourceSlot, targetSlot)
  for _, row in ipairs(P._evolutions[sourceSlot] or {}) do
    if row.target == targetSlot then return row end
  end
  return nil
end

-- ------- alone: the step waits, visibly, rather than vanishing

do
  local data = H.gen3Data()
  local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
  T.eq(#run.errors, 0, "loads clean alone (" .. tostring(run.errors[1]) .. ")")
  run.loader.events:emit("game.ready", {})
  T.eq(liveRow(data.gen3Pokemon, RHYDON, RHYPERIOR_SLOT), nil,
       "Rhydon -> Rhyperior is not live: no mod provides a Protector")

  local api = run.loader.exports.national_dex_gen3
  local viaId = api.evolutionsOf("RHYDON")
  local viaDex = api.evolutionsOf(RHYDON)
  local sawRhyperior = false
  for _, row in ipairs((viaId or {}).evolvesInto or {}) do
    if row.id == "RHYPERIOR" then sawRhyperior = true end
  end
  T.check(sawRhyperior, "evolutionsOf('RHYDON') still lists it as a pending step")
  T.check(viaDex ~= nil and #viaDex.evolvesInto == #viaId.evolvesInto,
          "evolutionsOf(112) answers the same, by dex number")
  local back = api.evolutionsOf("RHYPERIOR")
  T.eq(back and back.evolvesFrom and back.evolvesFrom.id, "RHYDON",
       "and RHYPERIOR already knows it evolves from RHYDON")
  run.release()
end

-- ------- item_mod loaded AFTER national_dex_gen3: still resolves

do
  local data = H.gen3Data()
  local run = T.sdk.loadMods({ "mods/national_dex_gen3", H.modRoot() .. "/tests/fixtures/item_mod" },
                             { data = data, generation = 3 })
  T.eq(#run.errors, 0, "loads clean with a companion item mod after it ("
       .. tostring(run.errors[1]) .. ")")
  run.loader.events:emit("game.ready", {})
  -- national_dex_gen3's own item lookup ran, mid-load, before item_mod
  -- registered anything; the live table must still pick it up.
  local row = liveRow(data.gen3Pokemon, RHYDON, RHYPERIOR_SLOT)
  T.check(row ~= nil, "Rhydon -> Rhyperior is live once a companion mod adds a Protector")
  T.eq(row and row.param, 400, "with that Protector's own item number")
  run.release()
end

-- ------- item_mod loaded BEFORE national_dex_gen3: also resolves

do
  local data = H.gen3Data()
  local run = T.sdk.loadMods({ H.modRoot() .. "/tests/fixtures/item_mod", "mods/national_dex_gen3" },
                             { data = data, generation = 3 })
  T.eq(#run.errors, 0, "loads clean with a companion item mod before it ("
       .. tostring(run.errors[1]) .. ")")
  run.loader.events:emit("game.ready", {})
  T.check(liveRow(data.gen3Pokemon, RHYDON, RHYPERIOR_SLOT) ~= nil,
          "resolves the same way regardless of load order")
  run.release()
end

-- ------- Nosepass -> Probopass: unaffected either way (FireRed has a Thunder Stone)

for _, mods in ipairs({ { "mods/national_dex_gen3" },
                        { "mods/national_dex_gen3", H.modRoot() .. "/tests/fixtures/item_mod" } }) do
  local data = H.gen3Data()
  local run = T.sdk.loadMods(mods, { data = data, generation = 3 })
  run.loader.events:emit("game.ready", {})
  local nosepass = data.gen3Pokemon.speciesFromName("NOSEPASS")
  T.check(nosepass ~= nil, "NOSEPASS resolves to a real FireRed slot")
  T.check(liveRow(data.gen3Pokemon, nosepass, PROBOPASS_SLOT) ~= nil,
          "Nosepass -> Probopass is always live (FireRed has its own Thunder Stone)")
  run.release()
end

-- ------- Species.itemIndex itself, directly

do
  local data = H.gen3Data()
  local run = T.sdk.loadMods({ "mods/national_dex_gen3", H.modRoot() .. "/tests/fixtures/item_mod" },
                             { data = data, generation = 3 })
  local Species = H.module("src/species.lua")
  T.eq(Species.itemIndex(run.loader)("protector"), 400,
       "Species.itemIndex resolves a companion mod's item by its PokéAPI slug")
  T.eq(Species.itemIndex(run.loader)("no-such-item"), nil,
       "and answers nil, not an error, for one nothing provides")
  run.release()
end

T.finish("national_dex_gen3 companion item")
