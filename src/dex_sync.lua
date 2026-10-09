-- The "Register Owned" option: opening the Pokedex first marks every Pokemon in the party and
-- the PC boxes as seen and caught.
--
-- A Pokemon put into a save with the save editor (a Galarian Darmanitan, a Latias) never went
-- through a battle or a catch, so the game never registered it. Only the Pokedex screen is
-- hooked (RSE's and FireRed/LeafGreen's `show`), so nothing changes while you play. A form
-- also marks its base species (fixups.installFormDex wraps Dex.setCaught). Eggs are skipped.

local DexSync = {}

local MODULES = { "src.ui.game3.rse.pokedex", "src.ui.game3.pokedex" }

-- Marks everything the session holds. Returns how many Pokemon it looked at.
function DexSync.sync(session)
  if type(session) ~= "table" then return 0 end
  local okD, Dex = pcall(require, "src.core.game3.dex")
  local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
  if not (okD and okP and type(session.dex) == "table") then return 0 end
  local n = 0
  local function mark(mon)
    if type(mon) ~= "table" or Pokemon.isEgg(mon) then return end
    local slot = Pokemon.speciesOf(mon)
    if not slot then return end
    n = n + 1
    Dex.setCaught(session.dex, slot)
  end
  for _, mon in pairs(type(session.party) == "table" and session.party or {}) do mark(mon) end
  local boxes = type(session.storage) == "table" and session.storage.boxes
  for _, box in pairs(type(boxes) == "table" and boxes or {}) do
    for _, mon in pairs(type(box) == "table" and type(box.mons) == "table" and box.mons or {}) do mark(mon) end
  end
  return n
end

-- enabled(): the option's current value
function DexSync.install(enabled, log)
  for _, name in ipairs(MODULES) do
    local ok, module = pcall(require, name)
    if ok and type(module) == "table" and type(module.show) == "function" then
      module._nationalDexSync = module._nationalDexSync or {}
      module._nationalDexSync.enabled = enabled           -- a later install replaces the rule
      if not module._nationalDexSync.wrapped then
        module._nationalDexSync.wrapped = true
        local original = module.show
        module.show = function(dex, opts, ...)
          local on = module._nationalDexSync.enabled
          if on and on() then
            local session = type(opts) == "table" and opts.session or nil
            local okS, err = pcall(DexSync.sync, session)
            if not okS and log and log.warn then log:warn("could not register owned Pokemon (%s)", tostring(err)) end
          end
          return original(dex, opts, ...)
        end
      end
    end
  end
end

return DexSync
