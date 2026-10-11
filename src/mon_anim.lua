-- Front (entrance) animations for the species this mod registers.
--
-- The Gen 3 engine animates a Pokemon's front picture (a trainer's lead sent out, the Pokedex,
-- the summary) by looking its slot up in the cart's own animation table
-- (src/core/game3/mon_anim_data.lua, sMonFrontAnimIdsTable). The table ends at the cart's last
-- species, so a slot past it gets no animation and the battle stops on "mon_anim: no port for
-- anim function nil". There is no registry field for it, so this wraps the two lookups
-- (frontAnimId, delay) and answers for our slots with a cart species' own animation:
--   * a form of a cart species (Alolan Meowth) moves like its base (Meowth);
--   * a new species that evolves from a cart species (Rhyperior from Rhydon) moves like it;
--   * any other takes one from a cart species of its own primary type, spread by its
--     National number, so a type's species do not all move the same way;
--   * a form of one of our species moves like its base.
-- Only animations the engine has a port for are used. Every other slot is untouched.

local MonAnim = {}

-- ours: { [slot] = true }, like: { [slot] = slot it should move like }, dexOf: { [slot] = dex }
function MonAnim.install(opts, require)
  local okD, Data = pcall(require, "src.core.game3.mon_anim_data")
  local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
  if not (okD and okP and type(Data) == "table" and type(Data.frontAnimId) == "function") then
    return false
  end
  Data._nationalDexAnim = opts               -- a later install replaces what the wrap reads
  if Data._nationalDexAnimWrapped then return true end
  Data._nationalDexAnimWrapped = true
  local origFront, origDelay = Data.frontAnimId, Data.delay
  local okA, Anim = pcall(require, "src.core.game3.mon_anim")

  local function ported(id)
    if id == nil then return false end
    if not (okA and Anim and Anim.animFunction) then return true end
    return (pcall(Anim.animFunction, id))
  end

  -- cart species by primary type, built once per animation pack (a different cart or reload)
  local byType, pack
  local function cartByType()
    local current = Data.get and Data.get() or nil
    if byType and pack == current then return byType end
    byType, pack = {}, current
    local last = (tonumber(Pokemon.SPECIES_EGG) or 412) - 1
    for slot = 1, last do
      local okT, types = pcall(Pokemon.types, slot)
      local okF, id = pcall(origFront, slot)
      if okT and type(types) == "table" and types[1] and okF and ported(id) then
        local t = types[1]
        byType[t] = byType[t] or {}
        table.insert(byType[t], slot)
      end
    end
    return byType
  end

  -- the cart slot a slot of ours moves like (nil for a slot that is not ours)
  local function cartSlotFor(slot, depth)
    local rules = Data._nationalDexAnim
    if not (rules and rules.ours[slot]) or (depth or 0) > 4 then return nil end
    local like = rules.like[slot]
    if like then
      if rules.ours[like] then return cartSlotFor(like, (depth or 0) + 1) end
      return like
    end
    local okT, types = pcall(Pokemon.types, slot)
    local groups = cartByType()
    local list = okT and type(types) == "table" and groups[types[1]] or nil
    if not (list and #list > 0) then
      list = {}
      for _, l in pairs(groups) do for _, s in ipairs(l) do list[#list + 1] = s end end
      table.sort(list)
    end
    if #list == 0 then return nil end
    local dex = tonumber(rules.dexOf[slot]) or slot
    return list[(dex % #list) + 1]
  end

  Data.frontAnimId = function(species)
    local like = cartSlotFor(tonumber(species))
    if like then
      local id = origFront(like)
      if ported(id) then return id end
    end
    return origFront(species)
  end
  if type(origDelay) == "function" then
    Data.delay = function(species)
      local like = cartSlotFor(tonumber(species))
      if like then return origDelay(like) end
      return origDelay(species)
    end
  end
  MonAnim._cartSlotFor = cartSlotFor           -- tests
  return true
end

return MonAnim
