-- The Pokedex on Gen 1 / Gen 2.
--
-- Red/Blue/Yellow: the list runs to constants.dexSize (the cart's 151, derived before mods load)
-- and prints constants.dexDigits; both are raised to 1025 and 4 digits. Forms carry dex numbers
-- of 20000 and up (src/gen12/project.lua), so they stay off the list.
-- Gold/Silver/Crystal: its own code adds every registered species with a dex number to
-- data.gen2Pokedex (src/core/gen2/PokedexText.lua, once, before game.ready), forms included; on
-- game.ready they are taken back out of its entries and of the New and A-Z orders.
-- Both: a form seen or caught counts its base as seen or caught (save.pokedex seen and owned on
-- Red, seen and caught on Gold), synced after anything that can mark one.

local Dex = {}

Dex.SIZE = 1025
Dex.DIGITS = 4

function Dex.register(mod, gen)
  if gen ~= 1 then return true end
  local constants = mod.content.constants
  local ok = pcall(constants.override, constants, "dexSize", Dex.SIZE)
  return ok and pcall(constants.override, constants, "dexDigits", Dex.DIGITS)
end

-- Gold: forms out of the Pokedex. Returns how many were taken out.
function Dex.removeForms(data, forms)
  local dex = data and data.gen2Pokedex
  if not (dex and dex.entries) then return 0 end
  local isForm, n = {}, 0
  for _, entry in ipairs(forms) do
    isForm[entry.id] = true
    if dex.entries[entry.id] then
      dex.entries[entry.id] = nil
      n = n + 1
    end
  end
  for _, key in ipairs({ "newOrder", "alphabeticalOrder" }) do
    local list = dex[key]
    if type(list) == "table" then
      local kept = {}
      for _, id in ipairs(list) do if not isForm[id] then kept[#kept + 1] = id end end
      for i = #list, 1, -1 do list[i] = nil end
      for i, id in ipairs(kept) do list[i] = id end
    end
  end
  return n
end

-- A form seen or caught marks its base too.
function Dex.sync(save, gen, forms)
  local p = save and save.pokedex
  if not p then return end
  local seen, owned = p.seen, gen == 1 and p.owned or p.caught
  for _, entry in ipairs(forms) do
    local base = entry.base
    if base then
      if seen and seen[entry.id] then seen[base] = true end
      if owned and owned[entry.id] then owned[base] = true end
    end
  end
end

function Dex.install(mod, gen, forms)
  local function sync()
    local game = mod.game
    Dex.sync(game and game.save, gen, forms)
  end
  for _, name in ipairs({ "pokemon.caught", "pokemon.evolved", "pokemon.received",
      "battle.ended", "save.loaded" }) do
    mod.events:on(name, sync)
  end
  if gen == 2 then
    mod.events:on("game.ready", function(ev)
      local game = ev and ev.game or mod.game
      Dex.removeForms(game and game.data, forms)
      sync()
    end, 1)
  end
end

return Dex
