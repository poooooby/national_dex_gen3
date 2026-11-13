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

  -- The manifest's options_schema is Gen 3's. This path declares its own list (src/gen12/options.lua:
  -- Modern Moves, Register Owned, and Day & Night on Red / Blue / Yellow), same keys.
  local Options = loadSibling(mod, "src/gen12/options.lua")
  pcall(function() mod.options:define(Options and Options.forGeneration(generation) or {}) end)
  local function option(key)
    local ok, value = pcall(function() return mod.options:get(key) end)
    return not ok or value ~= false
  end

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

  -- Register Owned: opening the Pokedex counts the party and the PC (src/gen12/dex_sync.lua)
  local DexSync = loadSibling(mod, "src/gen12/dex_sync.lua")
  if DexSync and Dex and speciesState then
    DexSync.install({ require = require, generation = generation, forms = speciesState.forms,
      syncForms = Dex.sync, enabled = function() return option("register_owned") end, log = mod.log })
  end

  -- Modern Moves: the cart's own species' newer moves, swapped in while the option is on
  local Modern = loadSibling(mod, "src/gen12/modern_moves.lua")
  local modernRows = loadSibling(mod, "data/gen12/modern.lua")
  if Modern and modernRows and speciesState and directMove then
    local modern = Modern.install({ generation = generation, rows = modernRows, direct = directMove,
      cartIdOf = speciesState.cartIdOf })
    local readyGame                      -- the game game.ready handed over: the live one
    local function applyModern(game)
      local g = game or readyGame or mod.game
      local okA, changed, added = pcall(modern.apply, g and g.data, option("modern_moves"))
      if okA and changed > 0 then
        mod.log:info("modern moves: on (%d species, %d moves)", changed, added)
      end
    end
    mod.events:on("game.ready", function(ev)
      readyGame = ev and ev.game or mod.game
      applyModern(readyGame)
    end, 1)
    mod.events:on("mod.options_changed", function(ev)
      if type(ev) == "table" and ev.mod == mod.id and ev.key == "modern_moves" then applyModern(nil) end
    end)
  end

  -- Day & Night on Red / Blue / Yellow (src/day_night.lua, as on Gen 3): the outdoors (Red's
  -- OVERWORLD, PLATEAU and FOREST tilesets) by the device's clock. Gold has its own day and night.
  local DayNight = generation == 1 and loadSibling(mod, "src/day_night.lua") or nil
  if DayNight and Clock then
    local OUTDOOR = { OVERWORLD = true, PLATEAU = true, FOREST = true }
    local function outdoor(ev)
      local g = mod.game
      local maps = g and g.data and g.data.maps
      local id = ev and ev.mapId
      if not id then
        local ow = g and g.overworld
        id = ow and ow.map and (ow.map.id or ow.map.mapId)
      end
      local def = maps and id and maps[id]
      return type(def) == "table" and OUTDOOR[def.tileset] == true
    end
    local installed = false
    mod.events:on("game.ready", function()
      local okD, errD = pcall(function()
        installed = DayNight.install({ require = require, log = mod.log, generations = { [1] = true },
          enabled = function() return option("day_night") end, outdoor = outdoor,
          phase = function() return Clock.phase(nil, "device") end })
      end)
      if not okD then mod.log:warn("day & night is off: %s", tostring(errD)) end
    end, -100)
    local function refresh(ev) if installed then pcall(DayNight.refresh, ev) end end
    mod.exports._dayNight = { module = DayNight, outdoor = outdoor, refresh = refresh,
      phase = function() return Clock.phase(nil, "device") end }
    mod.events:on("map.entered", refresh)
    mod.events:on("save.loaded", function() refresh(nil) end)
    mod.events:on("mod.options_changed", function(ev)
      if type(ev) == "table" and ev.mod == mod.id and ev.key == "day_night" then refresh(nil) end
    end)
  end

  -- new TMs (Gen 3's TM51+ for the moves that run here) and Exp. Candies, sold at the game's TM
  -- counter and with the vitamins (src/gen12/tms.lua, exp_candies.lua, shops.lua)
  local Shops = loadSibling(mod, "src/gen12/shops.lua")
  local function sell(where, ids, what)
    if not Shops then return nil end
    local ok, n = pcall(Shops.add, mod, generation, where, ids)
    if not ok then mod.log:warn("%s are not sold: %s", what, tostring(n)) end
    return ok and n or nil
  end
  local Tms = loadSibling(mod, "src/gen12/tms.lua")
  local tmRows = loadSibling(mod, "data/tms.lua")
  local tmState
  if Tms and tmRows and moveRows and speciesState and directMove then
    local list = Tms.select(tmRows, moveRows, generation, directMove)
    tmState = Tms.register({ mod = mod, generation = generation, list = list,
      species = speciesState, log = mod.log })
    Tms.install(require, tmState.ids)
    local stores = sell(generation == 1 and Tms.GEN1_SHOP or Tms.GEN2_SHOP, tmState.registered, "new TMs")
    mod.log:info("TMs: %d new (%d species can learn them), in %s store(s)", #tmState.registered,
      tmState.compatible, tostring(stores or 0))
  end
  local Candies = loadSibling(mod, "src/gen12/exp_candies.lua")
  local candyState
  if Candies then
    candyState = Candies.register({ mod = mod, generation = generation, require = require,
      onLevels = evoState and evoState.leveledUp, log = mod.log })
    sell(generation == 1 and Candies.GEN1_SHOP or Candies.GEN2_SHOP, candyState.registered, "Exp. Candies")
    mod.log:info("Exp. Candies: %d", #candyState.registered)
  end

  -- Type Badges (src/gen12/type_badges.lua, the Gen 3 badges' colours and symbols)
  local Badges = loadSibling(mod, "src/gen12/type_badges.lua")
  local Glyphs = Badges and loadSibling(mod, "src/type_badges.lua")
  if Badges and Glyphs then
    local function badgeOpts(data)
      return { require = require, generation = generation, glyphs = Glyphs, data = data,
        enabled = function() return option("type_badges") end, log = mod.log }
    end
    if generation == 1 then
      local badges = Badges.install(badgeOpts(nil))
      if badges then pcall(function() mod.hooks:wrap("battle.overlay", Badges.overlayHook(badges)) end) end
    else
      mod.events:on("game.ready", function(ev)
        local game = ev and ev.game or mod.game
        pcall(Badges.install, badgeOpts(game and game.data))
      end, 1)
    end
  end

  -- Bigger PC: 40 boxes; those past the cart's count are kept in this mod's save data on disk
  local BigPc = loadSibling(mod, "src/gen12/big_pc.lua")
  local pc = BigPc and BigPc.install({ require = require, generation = generation,
    enabled = function() return option("big_pc") end, log = mod.log })
  if pc then
    local pcGame                         -- the game game.ready handed over: the live one
    mod.events:on("game.ready", function(ev) pcGame = ev and ev.game or mod.game end, 1)
    mod.events:on("save.loading", function(ev) pcall(pc.loading, ev and ev.raw) end)
    mod.events:on("mod.options_changed", function(ev)
      if type(ev) == "table" and ev.mod == mod.id and ev.key == "big_pc" then
        local g = pcGame or mod.game
        pcall(pc.toggle, g and g.save)
      end
    end)
  end

  -- mod.exports: src/api.lua (the Gen 3 path's, as it is) over this path's species
  local Api = loadSibling(mod, "src/api.lua")
  local GenApi = loadSibling(mod, "src/gen12/api.lua")
  if Api and GenApi and speciesState then
    GenApi(mod, { api = Api, species = speciesState, evolutions = evoState, generation = generation,
      art = pictures })
    -- the candies' ids, as on Gen 3 (a reward mod can give them)
    if candyState and #candyState.registered > 0 then
      local ids = {}
      for k, v in pairs(Candies.ids) do ids[k] = v end
      mod.exports.expCandies = ids
    end
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
