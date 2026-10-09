-- National Dex Gen 3: species #387-1025 for every Gen 3 game -- Pokémon
-- FireRed, LeafGreen, Ruby, Sapphire and Emerald (manifest.json: games =
-- ["gen3"]).
--
-- Data + framework only. The payload (data/species/*.lua, built from PokéAPI
-- by tools/build_species.py) is registered through the engine's own species
-- registry; no artwork, icons or cries ship. A sprite mod supplies pictures
-- through mod.exports.setArtProvider (src/art.lua).
--
-- Module map:
--   src/species.lua  payload -> records, resolved against the running
--                    game's move / item / species registries, and registered
--   src/fixups.lua   Pokemon.onReload repairs the engine cannot do from a
--                    registry write (evolution targets, name + national lookup)
--                    and the move-tutor compatibility the running game keeps
--                    outside the species registry
--   src/items.lua    registers the evolution items no Gen 3 game has (data/items.lua,
--                    built by tools/build_items.py), so this mod's own evolutions
--                    (and anyone else's) stop waiting on a companion item mod
--   src/item_art.lua Bag icons for those items (no hook offers this; wraps the
--                    Bag's own icon draw directly -- see its own header)
--   src/shops.lua    puts those items on sale (data/shops.lua; wraps Marts.itemsFor)
--   src/cry_art.lua  cries for #387-1025 (wraps Audio.playCry; assets/cries/cries.pak)
--   src/conditional_evos.lua  Rockruff's Midday/Midnight/Dusk Lycanroc, Milcery's Alcremie and
--                    the friendship day/night evolutions (evolution.check hook)
--   src/recoil.lua  the recoil damage a Pokemon has taken, for Basculin's evolution
--   src/clock.lua    the hour for those rules: the device clock, or on Ruby/Sapphire/Emerald
--                    the player's choice of device or in-game (options.lua)
--   src/art.lua      pokemon.sprite seam for art providers
--   src/api.lua      mod.exports
--
-- Slot numbering: species dex + 64 (451..1089), above every ROM slot, the
-- dex + 64 numbering, so a save's species numbers never move.

local function loadSibling(mod, name)
  local source = mod:read(name)
  if not source then
    mod.log:error("%s is missing -- reinstall the mod", name)
    return nil
  end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. name)
  if not chunk then
    mod.log:error("%s failed to compile (%s) -- reinstall the mod", name, tostring(err))
    return nil
  end
  local ok, result = pcall(chunk)
  if not ok then
    mod.log:error("%s errored while loading (%s) -- reinstall the mod", name, tostring(result))
    return nil
  end
  return result
end

return function(mod)
  local Species = loadSibling(mod, "src/species.lua")
  local Fixups = loadSibling(mod, "src/fixups.lua")
  local Items = loadSibling(mod, "src/items.lua")
  local ItemArt = loadSibling(mod, "src/item_art.lua")
  local CryArt = loadSibling(mod, "src/cry_art.lua")
  local Shops = loadSibling(mod, "src/shops.lua")
  local Art = loadSibling(mod, "src/art.lua")
  local ConditionalEvos = loadSibling(mod, "src/conditional_evos.lua")
  local Clock = loadSibling(mod, "src/clock.lua")
  local Recoil = loadSibling(mod, "src/recoil.lua")
  local Api = loadSibling(mod, "src/api.lua")
  if not (Species and Fixups and Items and ItemArt and CryArt and Shops and Art and ConditionalEvos and Clock and Recoil and Api) then return end

  local read = function(path) return loadSibling(mod, path) end

  local payload = Species.loadPayload(read)
  if not payload then
    mod.log:error("data/species is missing or empty -- reinstall the mod")
    return
  end

  -- before species registration, so Species.register's own eager item lookup
  -- (species.lua's evolutionRow, a load-time snapshot) sees these too, not
  -- only the live bookkeeping path fixups drives
  local itemPayload = Items.loadPayload(read)
  Items.register(mod, itemPayload)

  local crossgen = Species.loadCrossGeneration(read)
  local forms = Species.loadForms(read)
  local registered, bridges, registeredForms = Species.register(mod, payload, crossgen, forms)
  local fixups = Fixups.new(registered, Species.itemIndex(mod), bridges, mod.log, registeredForms)
  -- after Gen3Compat's own reload hook (registered while the game boots), so
  -- its re-apply of registry data does not undo these repairs
  mod.events:on("game.ready", function(ev)
    fixups.install(ev and ev.game or mod.game)
    ConditionalEvos.installItemGender(bridges)
    ItemArt.install(mod, read)
    CryArt.install(mod, read)
    Shops.install(read("data/shops.lua") or {}, Species.itemIndex(mod), function()
      local okV, GV = pcall(require, "src.core.GameVersion")
      return okV and GV and GV.current or nil
    end, mod.log)
  end, -100)

  -- art providers are asked about forms too, by their own id and slot
  local everySpecies = {}
  for _, r in ipairs(registered) do everySpecies[#everySpecies + 1] = r end
  for _, r in ipairs(registeredForms) do everySpecies[#everySpecies + 1] = r end
  local art = Art.install(mod, everySpecies)
  -- the player's clock choice (options.lua); not defined, "game" is the default
  local okOptions, optionsSource = pcall(function() return mod:read("options.lua") end)
  if okOptions and optionsSource then
    local chunk = load(optionsSource, "@" .. mod.path .. "/options.lua")
    local okSchema, schema = pcall(chunk or function() end)
    if okSchema and type(schema) == "table" then pcall(function() mod.options:define(schema) end) end
  end
  local function clockSource()
    local okGet, value = pcall(function() return mod.options:get("clock_source") end)
    return okGet and value or "game"
  end
  -- species with an evolution that wants recoil damage: slot -> the total it needs
  local needsRecoil = {}
  for _, r in ipairs(everySpecies) do
    for _, step in ipairs(r.evolutions or {}) do
      if step.when and step.when.recoil then needsRecoil[r.slot] = step.when.recoil end
    end
  end
  Recoil.install(mod, needsRecoil)
  ConditionalEvos.install(mod, everySpecies, Species.itemIndex(mod), {
    isNight = function(session) return Clock.isNight(session, clockSource()) end,
    isDusk = function(session) return Clock.isDusk(session, clockSource()) end,
  })
  Api(mod, { species = registered, forms = registeredForms, bridges = bridges, art = art })
end
