-- Standalone: luajit mods/national_dex_gen3/tests/gen12_api_test.lua [red|blue|yellow|gold|silver|crystal ...]
-- (from the gen1recomp root; runs on red, yellow, gold and crystal when none is named; the
-- modern_spawns half needs mods/modern_spawns).
-- src/gen12/api.lua: the exports other mods read on Gen 1/2 (the same src/api.lua as Gen 3):
-- the species and forms, slots, dex numbers, evolutions (the cart's own species' new steps
-- too), the art seam and the clock; none of the Gen 3 extras. Then modern_spawns, loaded beside
-- it, finds the new species, scores them by evolution stage and family, and rolls encounter
-- tables with only species the game has.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")
local Runtime = require("src.mods.Runtime")

local SPAWNS = "mods/modern_spawns"
local function exists(path)
  local f = io.open(path .. "/manifest.json", "rb")
  if f then f:close() return true end
  return false
end

for _, version in ipairs(H.versions()) do
  local gen = H.GENERATION[version]
  local maxDex = gen == 1 and 151 or 251
  local run, api = H.load(version)
  T.eq(#run.errors, 0, version .. ": loads clean")

  local list = api.listSpecies()
  -- every species the game has, the cart's own included (the read API's listSpecies)
  T.eq(#list, 1025, version .. ": listSpecies has every species")
  local ordered = true
  for i, s in ipairs(list) do
    if s.dex ~= i or s.slot ~= s.dex + 64 then ordered = false end
  end
  T.check(ordered, version .. ": in dex order, each at its Gen 3 slot")
  T.eq(api.slotOf("LUCARIO"), 512, version .. ": slotOf by id")
  T.eq(api.slotOf(448), 512, version .. ": slotOf by dex number")
  T.eq(api.idOfSlot(512), "LUCARIO", version .. ": idOfSlot")
  T.eq(#api.listForms(), 128, version .. ": listForms")
  T.eq(api.baseDexOf("VULPIX_ALOLA"), 37, version .. ": a form shows its base's number")
  T.check(#api.formsOf("ROTOM") >= 5, version .. ": formsOf Rotom")

  local grotle = api.evolutionsOf("GROTLE")
  local into = grotle and grotle.evolvesInto[1]
  T.check(grotle and grotle.evolvesFrom and grotle.evolvesFrom.id == "TURTWIG"
    and grotle.evolvesFrom.methods[1].level == 18 and into and into.id == "TORTERRA",
    version .. ": Turtwig -> Grotle (18) -> Torterra")
  local cart, newer = gen == 1 and "GOLBAT" or "TOGETIC", gen == 1 and "CROBAT" or "TOGEKISS"
  local bridge = api.evolutionsOf(cart)
  local found = false
  for _, step in ipairs(bridge and bridge.evolvesInto or {}) do
    if step.id == newer then found = true end
  end
  T.check(found, version .. ": the cart's " .. cart .. " -> " .. newer)
  local back = api.evolutionsOf(newer)
  T.eq(back and back.evolvesFrom and back.evolvesFrom.id, cart, version .. ": and back")

  T.eq(type(api.setArtProvider), "function", version .. ": setArtProvider")
  T.eq(api.clockSource(), gen == 1 and "device" or "game", version .. ": clockSource")
  T.check(api.setDexPeek == nil and api.moveExtra == nil and api.moveRule == nil and api.dynamax == nil,
    version .. ": no Gen 3 extras")
  run.release()

  -- modern_spawns beside it
  if exists(SPAWNS) then
    local data = H.data(version)
    local both = T.sdk.loadMods({ H.modRoot(), SPAWNS }, { data = data, generation = gen })
    T.eq(#both.errors, 0, version .. ": modern_spawns loads beside it (" .. tostring(both.errors[1]) .. ")")
    both.loader.modSave.modern_spawns = { seed = 777 }
    both.loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
    both.loader.game = { mods = both.loader, save = { options = {} }, writeOptions = function() end }
    local spawns = both.loader.exports.modern_spawns
    local ours = {}
    for _, s in ipairs(list) do ours[s.id] = true end
    local n = 0
    for _, c in ipairs(spawns.candidates({ maxGeneration = 9 })) do
      if ours[c.id] then n = n + 1 end
    end
    print(("  %s: %d new species are spawn candidates"):format(version, n))
    T.check(n > 300, version .. ": " .. n .. " new species are spawn candidates")
    local t, g = spawns.profileOf("TURTWIG"), spawns.profileOf("GROTLE")
    T.check(t and g and g.stage == 2 and g.family == t.family and t.evolves and g.evolveLevel == 18,
      version .. ": Grotle is stage 2 of Turtwig's family, reached at 18")
    local c1, c2 = spawns.profileOf(cart), spawns.profileOf(newer)
    T.check(c1 and c2 and c1.family == c2.family, version .. ": " .. newer .. " is in " .. cart .. "'s family")
    if gen == 1 then
      local route = data.encounters.ROUTE_1
      local rolled = Runtime.call("encounter.roll", function(def) return def end, route,
        { mapId = "ROUTE_1", terrain = "grass", rng = function() return 0 end })
      local okSlots = rolled ~= route and #rolled.grass.slots == #route.grass.slots
      for _, slot in ipairs(rolled.grass.slots or {}) do
        if not data.pokemon[slot.species] then okSlots = false end
      end
      T.check(okSlots, version .. ": Route 1 rolls a table of species the game has")
    end
    both.release()
  end
end

T.finish("national_dex_gen3 Gen 1/2 API")
