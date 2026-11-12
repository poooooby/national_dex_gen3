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

  -- Dark / Steel / Fairy, the modern typing of the cart's species and moves, and the two
  -- newer growth curves; first, so every record registered after can name them
  local Types = loadSibling(mod, "src/gen12/types.lua")
  local cart = loadSibling(mod, "data/gen12/cart.lua")
  if Types and cart then
    local c = Types.register({ mod = mod, cart = cart, generation = generation, log = mod.log })
    mod.log:info("types: %d new, %d matchup rows, %d removed; retyped %d species, %d moves; "
      .. "%d growth rates", c.types, c.rows, c.removed, c.species, c.moves, c.growth)
  end

  -- the newer moves that run on an effect this game has, each with a cart move's animation;
  -- `resolveMove(n, taken)` turns any National move number into a move this game has
  local Moves = loadSibling(mod, "src/gen12/moves.lua")
  local moveRows = loadSibling(mod, "data/gen12/moves.lua")
  local moveState, resolveMove
  if Types and Moves and moveRows then
    moveState = Moves.register({ mod = mod, rows = moveRows, generation = generation, types = Types,
      log = mod.log })
    local cartMoves = {}
    for id, rec in mod.content.moves:each() do cartMoves[id] = rec end
    resolveMove = Moves.resolver(moveState, cartMoves)
    mod.log:info("moves: %d newer moves registered, %d already there", moveState.registered,
      moveState.borrowed)
    if #moveState.highCrit > 0 then
      mod.events:on("game.ready", function(ev)
        local game = ev and ev.game or mod.game
        Moves.installHighCrit(moveState, game and game.data)
      end, 1)
    end
  end

  local exports = mod.exports
  exports.apiVersion = 2
  exports.isActive = function() return true end
  exports.provider = function() return "national_dex_gen3" end
  exports.generation = function() return generation end

  mod.log:info("Gen %d path loaded", generation)
end
