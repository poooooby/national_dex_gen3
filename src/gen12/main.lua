-- WoobleDex on Gen 1 (Red, Blue, Yellow) and Gen 2 (Gold, Silver, Crystal).
--
-- main.lua hands over here (mod.generation 1 or 2) before anything Gen 3 loads, so no module in
-- src/ outside src/gen12/ runs on these games. Everything Gen 1/2 lives in src/gen12/ and
-- data/gen12/; the few Gen 3 modules that are pure (src/conditional_evos.lua's rules,
-- src/clock.lua's hours, src/api.lua) are loaded as they are, never edited for this path.
--
-- The records here are the engine's own Gen 1 / Gen 2 shapes (Schemas.shapeFor, api 2): Gen 1
-- one Special stat, level1Moves + learnset, evolutions -> species; Gen 2 split specials,
-- levelMoves, evolutions -> into.

return function(mod, loadSibling)
  local generation = mod.generation

  -- The manifest's options_schema is Gen 3's: none of those options does anything here.
  -- Declaring this path's own list (none yet) keeps them out of the Mod Manager on these games.
  pcall(function() mod.options:define({}) end)

  local exports = mod.exports
  exports.apiVersion = 2
  exports.isActive = function() return true end
  exports.provider = function() return "national_dex_gen3" end
  exports.generation = function() return generation end

  mod.log:info("Gen %d path loaded", generation)
end
