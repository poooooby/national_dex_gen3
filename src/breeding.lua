-- Manaphy lays a Phione egg.
--
-- The engine finds the species an egg hatches as by walking pre-evolutions through the live
-- evolution table (src/core/game3/breeding.lua Breeding.eggSpecies, the Gen 3 GetEggSpecies).
-- Phione never evolves, so it has no row to walk back along, and a Manaphy (or a Manaphy with
-- a Ditto) would hatch a Manaphy. This wraps Breeding.eggSpecies so Manaphy answers Phione;
-- everything else is untouched. Installed once; reads the slots registered at the time.

local Breeding = {}

-- manaphy, phione: the species slots this mod registered
function Breeding.install(manaphy, phione)
  if not (manaphy and phione) then return false end
  local ok, Engine = pcall(require, "src.core.game3.breeding")
  if not (ok and type(Engine) == "table" and type(Engine.eggSpecies) == "function") then return false end
  Engine._nationalDexEggOverrides = { [manaphy] = phione }
  if Engine._nationalDexEggWrapped then return true end
  Engine._nationalDexEggWrapped = true
  local original = Engine.eggSpecies
  Engine.eggSpecies = function(species)
    local egg = original(species)
    local override = Engine._nationalDexEggOverrides[tonumber(egg) or -1]
    return override or egg
  end
  return true
end

return Breeding
