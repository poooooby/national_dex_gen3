-- Standalone: luajit mods/national_dex_gen3/tests/rse_test.lua (from the
-- gen1recomp root; needs Emerald, Ruby and Sapphire imported under
-- emerald/, ruby/ and sapphire/).
--
-- Ruby, Sapphire and Emerald run the same game3 engine and schema as
-- FireRed/LeafGreen (Schemas.GEN3, G3.EVOLUTIONS and gen3Fields.index are
-- one shared table, not per-ROM), so this mod needs no game-specific code
-- for them -- see register_test.lua for the FireRed-specific checks this
-- file does not repeat. One real difference: Ruby and Sapphire shipped no
-- move tutors at all (Emerald and FireRed/LeafGreen added them); their
-- carts have no tutor.lua, and that is confirmed to produce no bits rather
-- than an error, not skipped outright.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")

local HAS_TUTORS = { emerald = true, ruby = false, sapphire = false }

for _, game in ipairs({ "emerald", "ruby", "sapphire" }) do
  local data = H.gen3Data(game)
  local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
  T.eq(#run.errors, 0, game .. ": loads clean (" .. tostring(run.errors[1]) .. ")")
  local api = run.loader.exports.national_dex_gen3
  T.check(api.isActive(), game .. ": active")

  local list = api.listSpecies()
  T.eq(#list, 639, game .. ": species #387-1025 are registered")

  local turtwig = run.loader.content.pokemon:get("TURTWIG")
  T.eq(turtwig.index, 451, game .. ": TURTWIG is slot 451")
  T.eq(turtwig.dex, 387, game .. ": national dex 387")

  run.loader.events:emit("game.ready", {})
  local evo = data.gen3Pokemon._evolutions[451] and data.gen3Pokemon._evolutions[451][1]
  T.check(evo ~= nil, game .. ": TURTWIG has a live evolution row")
  T.eq(evo and evo.target, 452, game .. ": into GROTLE's slot, not slot 0")

  -- TM/HM and egg moves: present, but not pinned to FireRed's exact counts
  -- -- this game's own item/move set differs slightly.
  local tw = run.loader.content.pokemon:get("TURTWIG")
  T.check(#(tw.tmhm or {}) > 0, game .. ": TURTWIG has TM/HM compatibility")
  T.check(#(tw.eggMoves or {}) > 0, game .. ": and egg moves")

  -- Move tutors: Emerald has them live; Ruby/Sapphire correctly have none,
  -- with no error either way (src.core.game3.move_learn already answers nil
  -- for a cart with no tutor.lua -- see tests/_gen3.lua).
  local ML = require("src.core.game3.move_learn")
  local sets = ML.tutorLearnsets()
  if HAS_TUTORS[game] then
    T.check(type(sets) == "table" and sets[451] ~= nil, game .. ": TURTWIG has tutor bits")
  else
    T.eq(sets, nil, game .. ": no tutor pack at all, and no error getting here")
  end

  -- Evolutions from the cart's own species into new ones (Magneton ->
  -- Magnezone, FireRed's own Thunder Stone check in register_test.lua):
  -- resolves the same way here, since it is the same shared item schema.
  local magneton = run.loader.content.pokemon:get("MAGNETON")
  local toMagnezone = false
  for _, e in ipairs(magneton.evolutions or {}) do
    if e.species == "MAGNEZONE" then toMagnezone = true end
  end
  T.check(toMagnezone, game .. ": MAGNETON gains an evolution into MAGNEZONE")

  run.release()
end

T.finish("national_dex_gen3 Ruby/Sapphire/Emerald")
