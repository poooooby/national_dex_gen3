-- Standalone: luajit mods/national_dex_gen3/tests/gen12_load_test.lua [red|blue|yellow|gold|silver|crystal ...]
-- (from the gen1recomp root; runs on red, yellow, gold and crystal when none is named).
-- The mod runs on Gen 1 and Gen 2 through its own path (src/gen12/main.lua), forked off main.lua
-- before anything Gen 3 loads; those games' Mod Manager shows this path's own options; and the
-- original national_dex and this mod never run together there.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")

for _, version in ipairs(H.versions()) do
  local gen = H.GENERATION[version]
  local run, api = H.load(version)
  for i = 1, math.min(5, #run.errors) do print("load error: " .. tostring(run.errors[i])) end
  T.eq(#run.errors, 0, version .. ": loads clean")
  local mod = run.mods.national_dex_gen3
  T.check(mod and mod.state == "loaded", version .. ": loaded (" .. tostring(mod and mod.state) .. ")")
  T.check(api and api.isActive(), version .. ": active")
  T.eq(api and api.generation(), gen, version .. ": runs the Gen " .. gen .. " path")
  T.eq(api and api.provider(), "national_dex_gen3", version .. ": provider id")
  -- the Gen 3 path never ran: its exports are absent
  T.check(api and api.setDexPeek == nil and api.dynamax == nil and api.moveRule == nil,
    version .. ": none of the Gen 3 exports")
  -- this path declares its own option list, so the manifest's Gen 3 rows are not offered here
  local schema = run.loader.optionSchemas and run.loader.optionSchemas.national_dex_gen3
  T.check(type(schema) == "table", version .. ": declares its own options")
  local keys = {}
  for _, row in ipairs(schema or {}) do keys[row.key] = true end
  -- Modern Moves, Register Owned, Bigger PC and Type Badges everywhere, Day & Night on Red / Blue /
  -- Yellow only (Gold has its own); none of the Gen 3-only rows
  T.check(keys.modern_moves and keys.register_owned and keys.big_pc and keys.type_badges
    and (keys.day_night == (gen == 1 or nil)), version .. ": its own rows (Day & Night on Gen 1 only)")
  T.check(not (keys.unlock_national or keys.clock_source or keys.modern_learnsets),
    version .. ": none of the Gen 3-only rows")
  run.release()

  -- the original national_dex (same species ids) and this mod never load together: the manifest
  -- names it in conflicts, so this mod is the one that steps aside
  local stub = H.modRoot() .. "/tests/fixtures/national_dex"
  local both = H.load(version, { stub })
  local ours, theirs = both.mods.national_dex_gen3, both.mods.national_dex
  T.check(theirs and theirs.state == "loaded", version .. ": a national_dex alone still loads")
  T.check(ours and ours.state ~= "loaded", version .. ": WoobleDex steps aside beside national_dex ("
    .. tostring(ours and ours.state) .. ")")
  both.release()
end

-- On a Gen 3 cart the same conflict never bites: the loader skips a mod made for other games
-- before it weighs conflicts, so an installed national_dex leaves this mod running there. (Its own
-- process state: the Gen 1/2 loads above never touch the Gen 3 species tables.)
do
  local G3 = dofile(H.modRoot() .. "/tests/_gen3.lua")
  require("src.core.GameVersion").set("firered")
  local data = G3.gen3Data("firered")
  G3.useCart("firered")
  data.gen3Moves = require("src.core.game3.battle.moves")
  local both = T.sdk.loadMods({ H.modRoot(), H.modRoot() .. "/tests/fixtures/national_dex" },
    { data = data, generation = 3 })
  T.check(both.mods.national_dex_gen3 and both.mods.national_dex_gen3.state == "loaded",
    "firered: still loads with the Gen 1/2 national_dex installed ("
      .. tostring(both.mods.national_dex_gen3 and both.mods.national_dex_gen3.state) .. ")")
  T.check(both.mods.national_dex and both.mods.national_dex.state ~= "loaded",
    "firered: national_dex is skipped there")
  local api = both.loader.exports.national_dex_gen3
  T.check(api and api.dynamax ~= nil, "firered: the Gen 3 path ran")
  both.release()
end

T.finish("national_dex_gen3 Gen 1/2 path loads")
