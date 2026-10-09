-- The "National Dex" option: the National Pokedex counts as unlocked without earning it.
--
-- Every game asks the same two questions -- Dex.nationalEnabled (the story flag, var and magic
-- number) and PokedexData.isNationalUnlocked (which the FireRed/LeafGreen path answers from its
-- own flags) -- so answering true from both covers the Pokedex screens, the Match Call / TV /
-- Easy Chat checks and trade. The save is not touched, so switching the option off puts it back.
-- Installed once; reads the option live, so toggling it takes effect without a reload.

local NationalUnlock = {}

-- enabled(): the option's current value
function NationalUnlock.install(enabled)
  local ok, Dex = pcall(require, "src.core.game3.dex")
  local okD, PokedexData = pcall(require, "src.core.game3.pokedex_data")
  local rules = { enabled = enabled }
  local function wrap(module, name)
    if not (type(module) == "table" and type(module[name]) == "function") then return end
    module._nationalUnlock = module._nationalUnlock or {}
    module._nationalUnlock.rules = rules          -- a later install replaces what the wrap reads
    if module._nationalUnlock[name] then return end
    module._nationalUnlock[name] = true
    local original = module[name]
    module[name] = function(...)
      local on = module._nationalUnlock.rules.enabled
      if on and on() then return true end
      return original(...)
    end
  end
  if ok then wrap(Dex, "nationalEnabled") end
  if okD then wrap(PokedexData, "isNationalUnlocked") end
end

return NationalUnlock
