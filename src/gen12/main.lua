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
  local moveState, resolveMove, directMove
  if Types and Moves and moveRows then
    moveState = Moves.register({ mod = mod, rows = moveRows, generation = generation, types = Types,
      log = mod.log })
    local cartMoves = {}
    for id, rec in mod.content.moves:each() do cartMoves[id] = rec end
    resolveMove, directMove = Moves.resolver(moveState, cartMoves)
    mod.log:info("moves: %d newer moves registered, %d already there", moveState.registered,
      moveState.borrowed)
    if #moveState.highCrit > 0 then
      mod.events:on("game.ready", function(ev)
        local game = ev and ev.game or mod.game
        Moves.installHighCrit(moveState, game and game.data)
      end, 1)
    end
  end

  -- species #152+ (Red) / #252+ (Gold) and the 128 forms, with the placeholder pictures
  local Project = loadSibling(mod, "src/gen12/project.lua")
  local Species = loadSibling(mod, "src/gen12/species.lua")
  local index = loadSibling(mod, "data/gen12/species/index.lua")
  local forms = loadSibling(mod, "data/gen12/forms.lua")
  local speciesState
  if Project and Species and index and forms and resolveMove then
    local records = {}
    for _, shard in ipairs(index.shards) do
      for _, r in ipairs(loadSibling(mod, "data/gen12/species/" .. shard) or {}) do
        records[#records + 1] = r
      end
    end
    local assets = mod.path .. "/assets/gen12/"
    speciesState = Species.register({ mod = mod, generation = generation, project = Project,
      types = Types, resolve = resolveMove, direct = directMove, species = records, forms = forms,
      pictures = { front = assets .. "front.png", back = assets .. "back_gen" .. generation .. ".png" },
      log = mod.log })
    mod.log:info("species: %d registered (%d forms), %d left to another mod",
      speciesState.registered, #speciesState.forms, speciesState.kept)
  end

  -- the evolution items the cart lacks (sold in one shop), then every evolution: this mod's
  -- species and forms, and the newer ones of the cart's own species
  local Items = loadSibling(mod, "src/gen12/items.lua")
  local Evolutions = loadSibling(mod, "src/gen12/evolutions.lua")
  local itemRows = loadSibling(mod, "data/gen12/items.lua")
  local crossgen = loadSibling(mod, "data/gen12/crossgen.lua")
  local Conditional = loadSibling(mod, "src/conditional_evos.lua")
  local Clock = loadSibling(mod, "src/clock.lua")
  local evoState
  if speciesState and Items and Evolutions and itemRows and crossgen and Conditional and Clock then
    local itemState = Items.register({ mod = mod, generation = generation, rows = itemRows,
      log = mod.log, use = function(c)
        if not evoState then return nil end
        if generation == 1 then return evoState.useGen1(c) end
        return evoState.useGen2(c)
      end })
    evoState = Evolutions.install({ mod = mod, generation = generation, require = require,
      conditional = Conditional, clock = Clock, species = speciesState, crossgen = crossgen,
      cartIdOf = speciesState.cartIdOf, itemId = itemState.id, direct = directMove,
      log = mod.log })
    local shop = Items.stock(mod, generation, itemState, mod.log)
    mod.log:info("evolutions: %d rows (%d steps not possible here); %d items, sold at %s",
      evoState.added, evoState.dropped, #itemState.registered, tostring(shop))
  end

  -- party icons and cries (borrowed from each species' proxy; #387+ play their own), sprite
  -- mods' pictures over the placeholder, and the Pokedex
  local Art = loadSibling(mod, "src/gen12/art.lua")
  local Dex = loadSibling(mod, "src/gen12/dex.lua")
  local pictures
  if speciesState and Art then
    local c = Art.register({ mod = mod, generation = generation, species = speciesState, log = mod.log })
    pictures = Art.installPictures(mod, speciesState)
    local cries = Art.installCries({ mod = mod, require = require, species = speciesState,
      index = loadSibling(mod, "data/cries.lua"), log = mod.log })
    mod.log:info("art: %d icons, %d borrowed cries%s", c.icons, c.cries,
      cries and ", own cries for #387+" or "")
  end
  if speciesState and Dex then
    if not Dex.register(mod, generation) then
      mod.log:warn("the Pokedex stays at the cart's size")
    end
    Dex.install(mod, generation, speciesState.forms)
  end

  -- mod.exports: src/api.lua (the Gen 3 path's, as it is) over this path's species
  local Api = loadSibling(mod, "src/api.lua")
  local GenApi = loadSibling(mod, "src/gen12/api.lua")
  if Api and GenApi and speciesState then
    GenApi(mod, { api = Api, species = speciesState, evolutions = evoState, generation = generation,
      art = pictures })
  else
    -- the bare minimum, so a caller can still tell the mod is here
    local exports = mod.exports
    exports.apiVersion = 2
    exports.isActive = function() return true end
    exports.provider = function() return "national_dex_gen3" end
    exports.generation = function() return generation end
  end

  mod.log:info("Gen %d path loaded", generation)
end
