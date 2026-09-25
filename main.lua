-- National Dex Gen 3: species #387-1025 for Pokémon FireRed / LeafGreen.
--
-- Data + framework only. The payload (data/species/*.lua, built from PokéAPI
-- by tools/build_species.py) is registered through the engine's own species
-- registry; no artwork, icons or cries ship. A sprite mod supplies pictures
-- through mod.exports.setArtProvider (src/art.lua).
--
-- Module map:
--   src/species.lua  payload -> FireRed records, resolved against the running
--                    game's move / item / species registries, and registered
--   src/fixups.lua   Pokemon.onReload repairs the engine cannot do from a
--                    registry write (evolution targets, name + national lookup)
--                    and the move-tutor compatibility FireRed keeps outside
--                    the species registry
--   src/art.lua      pokemon.sprite seam for art providers
--   src/api.lua      mod.exports
--
-- FireRed slot numbering: species dex + 64 (451..1089), above every ROM slot,
-- the same numbering 1025Dex uses, so a save moves between the two intact.

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
  local Art = loadSibling(mod, "src/art.lua")
  local Api = loadSibling(mod, "src/api.lua")
  if not (Species and Fixups and Art and Api) then return end

  -- 1025Dex registers the same species into the same slots with its own art;
  -- two registrations of one slot would fight. It wins; this mod steps aside.
  local ok, other = pcall(function() return mod:find("1025dex") end)
  if ok and other then
    mod.log:info("1025Dex is installed and provides species #387-1025 -- "
      .. "national_dex_gen3 registers nothing")
    Api(mod, { active = false, provider = "1025dex" })
    return
  end

  local payload = Species.loadPayload(function(path) return loadSibling(mod, path) end)
  if not payload then
    mod.log:error("data/species is missing or empty -- reinstall the mod")
    return
  end

  local crossgen = Species.loadCrossGeneration(function(path) return loadSibling(mod, path) end)
  local registered, bridges = Species.register(mod, payload, crossgen)
  local fixups = Fixups.new(registered, Species.itemIndex(mod), bridges, mod.log)
  -- after Gen3Compat's own reload hook (registered while the game boots), so
  -- its re-apply of registry data does not undo these repairs
  mod.events:on("game.ready", function(ev)
    fixups.install(ev and ev.game or mod.game)
  end, -100)

  local art = Art.install(mod, registered)
  Api(mod, { active = true, species = registered, bridges = bridges, art = art })
end
