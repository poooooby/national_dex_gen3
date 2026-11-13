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
    -- every other newer move: the mechanics layer (src/gen12/mech/core.lua), run by this game's
    -- battle through its adapter (src/gen12/battle/red.lua / gold.lua)
    local Core = loadSibling(mod, "src/gen12/mech/core.lua")
    local Install = Core and loadSibling(mod, "src/gen12/mech/install.lua")
    local Adapter = Install and loadSibling(mod, generation == 1 and "src/gen12/battle/red.lua"
      or "src/gen12/battle/gold.lua")
    local gen3Moves = Adapter and loadSibling(mod, "data/moves.lua")
    if Core and Install and Adapter and gen3Moves then
      local core = Core.new({ generation = generation, gen3 = gen3Moves, log = mod.log,
        facts = loadSibling(mod, "data/gen12/battle.lua") })
      for _, path in ipairs(Core.FAMILIES or {}) do
        local family = loadSibling(mod, path)
        if type(family) == "function" then
          local okF, errF = pcall(family, core, { generation = generation, require = require, mod = mod,
            load = function(p) return loadSibling(mod, p) end,
            option = function(key) return mod.options:get(key) end })
          if not okF then mod.log:warn("move mechanics %s failed to load: %s", path, tostring(errF)) end
        end
      end
      local seams = { require = require, core = core, types = Types }
      local okS, errS = pcall(Adapter.installSeams, mod, seams)
      if not okS then mod.log:warn("move mechanics: a battle seam failed: %s", tostring(errS)) end
      pcall(core.listen, core, mod, Adapter, seams)
      local fx = Install.register({ mod = mod, generation = generation, rows = moveRows, core = core,
        adapter = Adapter, types = Types, state = moveState, require = require, log = mod.log })
      moveState.registered = moveState.registered + fx.registered
      moveState.mechanics = fx.registered
      moveState.looks = fx.looks
      moveState.core, moveState.missingMechanics = core, fx.missing
      mod.exports._mech = { core = core, adapter = Adapter, deps = seams, missing = fx.missing,
        specs = fx.specs }
      -- the summary screens: nature, ability, held item (src/gen12/summary.lua)
      local Summary = loadSibling(mod, "src/gen12/summary.lua")
      if Summary then
        local okY, errY = pcall(Summary.install, { require = require, generation = generation, core = core })
        if not okY then mod.log:warn("summary additions are off: %s", tostring(errY)) end
      end
      mod.log:info("move mechanics: %d moves run on them, %d without one yet (stand-ins)", fx.registered,
        #fx.missing)
    end
    -- the pixelfx move animations (src/gen12/fx_anims.lua), over the borrowed ones
    local FxAnims = loadSibling(mod, "src/gen12/fx_anims.lua")
    local fxData = FxAnims and loadSibling(mod, "data/fx.lua")
    if FxAnims and fxData then
      local looks = {}
      for _, row in ipairs(moveRows) do
        if row.look and row.look["gen" .. generation] then looks[row.id] = row.look["gen" .. generation] end
      end
      for id, look in pairs(moveState.looks or {}) do looks[id] = look end
      local okF, fxState = pcall(FxAnims.register, { mod = mod, generation = generation, data = fxData,
        looks = looks, log = mod.log })
      if okF and fxState.count > 0 then
        local hook = FxAnims.overlay({ generation = generation, data = fxData, lines = fxState.lines,
          root = mod.path, log = mod.log })
        pcall(function() mod.hooks:wrap("battle.overlay", hook) end)
        mod.exports._fx = fxState
        mod.log:info("move animations: %d drawn with pixelfx", fxState.count)
      end
    end
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

  -- Red: today's battle rules and critical hits (src/gen12/modern_rules.lua, option modern_rules)
  if generation == 1 then
    local ModernRules = loadSibling(mod, "src/gen12/modern_rules.lua")
    if ModernRules then
      local okR, errR = pcall(ModernRules.install, { mod = mod, require = require, option = option,
        mech = function() return mod.exports._mech end })
      if okR then mod.exports._modernRules = ModernRules
      else mod.log:warn("modern rules are off: %s", tostring(errR)) end
    end
  end

  -- Red: Gold's held items (src/gen12/held_red.lua): registered, sold, given from the party menu
  if generation == 1 then
    local HeldRed = loadSibling(mod, "src/gen12/held_red.lua")
    local heldRows = HeldRed and loadSibling(mod, "data/gen12/held.lua")
    if HeldRed and heldRows then
      local okH, heldState = pcall(HeldRed.install, { mod = mod, rows = heldRows, require = require, log = mod.log })
      if okH then
        mod.log:info("held items: %d on Red", #heldState.registered)
        mod.exports._held = heldState
      else
        mod.log:warn("held items are off: %s", tostring(heldState))
      end
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

    -- Red: breeding by Gold's rules (src/gen12/breeding_red.lua), a second Day Care slot and eggs
    if generation == 1 and directMove then
      local Breeding = loadSibling(mod, "src/gen12/breeding_red.lua")
      local facts = loadSibling(mod, "data/gen12/battle.lua")
      local modernRows = loadSibling(mod, "data/gen12/modern.lua") or {}
      if Breeding and facts then
        local eggByDex = {}
        for _, r in ipairs(modernRows) do eggByDex[r.dex] = r.eggMoves end
        for _, r in ipairs(records) do if r.dex then eggByDex[r.dex] = r.eggMoves end end
        local function genderOf(record, dvs)
          local dex = record and (record.baseDex or record.dex)
          local rate = dex and facts.genderRates and facts.genderRates[dex]
          local ratio = (rate == nil or rate < 0) and 255 or (rate == 0 and 0) or (rate == 8 and 254)
            or rate * 32 - 1
          if ratio == 255 then return nil end
          if ratio == 0 then return "M" end
          if ratio == 254 then return "F" end
          return ((dvs.attack or 0) * 16 + (dvs.speed or 0)) <= ratio and "F" or "M"
        end
        local okB, errB = pcall(Breeding.install, { mod = mod, require = require, facts = facts,
          gender = genderOf, direct = directMove, eggMoves = function(dex) return eggByDex[dex] end,
          log = mod.log })
        if okB then mod.exports._breeding = Breeding
        else mod.log:warn("breeding is off: %s", tostring(errB)) end
      end
    end
  end

  -- the evolution items the cart lacks (sold in one shop), then every evolution: this mod's
  -- species and forms, and the newer ones of the cart's own species
  local Items = loadSibling(mod, "src/gen12/items.lua")
  local Evolutions = loadSibling(mod, "src/gen12/evolutions.lua")
  local itemRows = loadSibling(mod, "data/gen12/items.lua")
  local crossgen = loadSibling(mod, "data/gen12/crossgen.lua")
  local Conditional = loadSibling(mod, "src/conditional_evos.lua")
  local Clock = loadSibling(mod, "src/clock.lua")
  local evoState, itemState
  -- the vending machines (src/gen12/vending.lua over src/vending_screen.lua and data/vending.lua):
  -- when they are here, they sell the evolution items and the new TMs instead of the Marts
  local Vending = loadSibling(mod, "src/gen12/vending.lua")
  local vendingData = Vending and loadSibling(mod, "data/vending.lua")
  local vendingScreen = vendingData and loadSibling(mod, "src/vending_screen.lua")
  local vendingOn = (Vending and vendingData and vendingScreen and mod.content.sprites) and true or false
  if speciesState and Items and Evolutions and itemRows and crossgen and Conditional and Clock then
    itemState = Items.register({ mod = mod, generation = generation, rows = itemRows,
      log = mod.log, use = function(c)
        if not evoState then return nil end
        if generation == 1 then return evoState.useGen1(c) end
        return evoState.useGen2(c)
      end })
    evoState = Evolutions.install({ mod = mod, generation = generation, require = require,
      conditional = Conditional, clock = Clock, species = speciesState, crossgen = crossgen,
      cartIdOf = speciesState.cartIdOf, itemId = itemState.id, direct = directMove,
      log = mod.log })
    local shop = vendingOn and "the EVO EXPRESS machine" or Items.stock(mod, generation, itemState, mod.log)
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

  -- the Pokedex FORMS page (src/gen12/dex_forms.lua; the form names from src/dex_forms.lua)
  local DexForms = loadSibling(mod, "src/gen12/dex_forms.lua")
  local Labels = DexForms and loadSibling(mod, "src/dex_forms.lua")
  if DexForms and Labels and speciesState and #speciesState.forms > 0 then
    mod.events:on("game.ready", function(ev)
      local game = ev and ev.game or mod.game
      local ok, err = pcall(DexForms.install, { require = require, generation = generation,
        forms = speciesState.forms, label = Labels.label, data = game and game.data })
      if not ok then mod.log:warn("the Pokedex FORMS page is off: %s", tostring(err)) end
    end, 1)
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
    local stores = vendingOn and "the TM EXPRESS machine"
      or ((sell(generation == 1 and Tms.GEN1_SHOP or Tms.GEN2_SHOP, tmState.registered, "new TMs") or 0)
        .. " store(s)")
    mod.log:info("TMs: %d new (%d species can learn them), sold at %s", #tmState.registered,
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

  if vendingOn and itemState then
    local okV, err = pcall(function()
      local BadgeIds = loadSibling(mod, "src/gen12/type_badges.lua")
      local V = Vending.new({ mod = mod, generation = generation, require = require, log = mod.log,
        machines = vendingData, screen = vendingScreen, items = itemRows, itemId = itemState.id,
        tms = tmState and tmRows or {}, moves = loadSibling(mod, "data/moves.lua"),
        gen3Items = loadSibling(mod, "data/items.lua"), icons = loadSibling(mod, "data/item_icons.lua"),
        typeId = BadgeIds and BadgeIds.idOf })
      V.registerSprites()
      V.install()
      mod.exports._vending = V
      mod.log:info("vending machines: %d", #V.machines)
    end)
    if not okV then mod.log:warn("the vending machines are off: %s", tostring(err)) end
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
    -- the read API a battle or stats mod expects of a National Dex (apiVersion 9: moveById,
    -- moveFlags, abilityById, statsBySpecies, ...), over the exports above
    local DexApi = loadSibling(mod, "src/gen12/dex_api.lua")
    if DexApi and Types then
      local ok, err = pcall(DexApi, mod, { generation = generation, types = Types, species = speciesState,
        direct = directMove, evolutions = evoState,
        load = function(path) return loadSibling(mod, path) end })
      if not ok then mod.log:warn("read API: %s", tostring(err)) end
    end
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
