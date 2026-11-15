-- Standalone: luajit mods/national_dex_gen3/tests/gen12_editor_test.lua [red|blue|yellow|gold|silver|crystal ...]
-- (from the gen1recomp root; needs the carts imported and the stock tools/save-editor).
--
-- The save editor on a Red to Crystal save (src/gen12/editor.lua): while the editor loads mods,
-- every species and form is in its species list with its types, and a form reads
-- "VULPIX (ALOLAN)" with its base's number instead of "VULPIX #20091". Outside the editor (a game,
-- or a game started after the editor closed) the forms keep the name and number the game uses.
-- The editor's session is the one thing faked: the real Gen / App / Catalog modules are used, and
-- the real loader never scans the mods folder or reads options.lua here.
package.path = "./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua;"
  .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local okA, App = pcall(require, "App")
if not okA then print("skipped: the save editor is not in this checkout") os.exit(0) end

local T = require("tests.modkit")
local here = (arg[0]:gsub("\\", "/"):match("^(.*)/") or ".")
local H = dofile(here .. "/_gen12.lua")
local Catalog = require("Catalog")
local TypeChart = require("src.battle.TypeChart")

local function load(version, inEditor)
  local getState = App.getState
  if inEditor then App.getState = function() return {} end end
  local run = H.load(version)
  App.getState = getState
  return run, run.data
end

for _, version in ipairs(H.versions()) do
  -- ------- in the editor
  local run, data = load(version, true)
  T.eq(#run.errors, 0, version .. ": loads in the editor (" .. tostring(run.errors[1]) .. ")")
  local P = data.pokemon
  T.eq(P.VULPIX_ALOLA and P.VULPIX_ALOLA.name, "VULPIX (ALOLAN)", version .. ": Alolan Vulpix is labelled")
  T.eq(P.VULPIX_ALOLA and P.VULPIX_ALOLA.dex, 37, version .. ": with Vulpix's number")
  T.eq(P.VULPIX.name, "VULPIX", version .. ": Vulpix keeps its own name")
  T.eq(P.ROTOM_HEAT and P.ROTOM_HEAT.dex, 479, version .. ": Heat Rotom has Rotom's number")
  T.check(P.ROTOM_HEAT and P.ROTOM_HEAT.name:match("^ROTOM %(.+%)$"), version .. ": Heat Rotom is labelled ("
    .. tostring(P.ROTOM_HEAT and P.ROTOM_HEAT.name) .. ")")

  local forms = run.loader.exports.national_dex_gen3.listForms()
  T.eq(#forms, 128, version .. ": 128 forms")
  local listed = {}
  for _, id in ipairs(Catalog.build(data, nil, version).species) do listed[id] = true end
  local bad
  for _, f in ipairs(forms) do
    local def = P[f.id]
    if not (listed[f.id] and def and def.name:match(" %(.+%)$") and def.dex >= 1 and def.dex <= 1025) then
      bad = bad or (f.id .. " " .. tostring(def and def.name) .. " #" .. tostring(def and def.dex))
    end
  end
  T.eq(bad, nil, version .. ": every form is listed, labelled and numbered as its base")

  -- every National number has its species listed, with types the editor can name
  local byDex, untyped = {}, nil
  for id in pairs(listed) do
    local def = P[id]
    if def.name and def.types then
      if not def.baseSpecies then byDex[tonumber(def.dex) or 0] = true end
      for _, t in ipairs(def.types) do
        if not TypeChart.displayName(t, data) then untyped = untyped or (id .. ":" .. tostring(t)) end
      end
    end
  end
  local missing
  for n = 1, 1025 do if not byDex[n] then missing = missing or n end end
  T.eq(missing, nil, version .. ": every National number 1-1025 is in the species list")
  T.eq(untyped, nil, version .. ": every type has a name")
  T.eq(TypeChart.displayName(P.CLEFAIRY.types[1], data), "FAIRY", version .. ": Clefairy is Fairy")
  T.eq(TypeChart.displayName(P.TINKATON.types[2], data), "STEEL", version .. ": Tinkaton is Fairy/Steel")
  run.release()

  -- ------- a game (or a game after the editor closed: App.getState is nil then)
  local run2, data2 = load(version, false)
  T.eq(#run2.errors, 0, version .. ": loads as a game")
  T.eq(data2.pokemon.VULPIX_ALOLA.name, "VULPIX", version .. ": a game keeps the form's name")
  T.check(data2.pokemon.VULPIX_ALOLA.dex >= 20000, version .. ": and its own number")
  run2.release()
end
T.finish("national_dex_gen3 gen12 save editor")
