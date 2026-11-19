-- The six EV-lowering berries (Pomeg, Kelpsy, Qualot, Hondew, Grepa, Tamato) on FireRed, LeafGreen,
-- Ruby and Sapphire, as in Emerald and today's games: used from the Bag on a Pokemon, the berry
-- lowers one stat's EVs by 10 and raises its friendship (10 / 5 / 2 by how friendly it already is,
-- the cart's own tiers, Soothe Bell and the Luxury Ball included through Pokemon.itemFriendship).
-- "It won't have any effect" when neither changes.
--
-- Each berry is the cart's own item, patched with an item_effects record (the engine keeps the
-- item's ROM effect bytes beside it, Schemas itemWrite): its Bag use runs ours. Where those bytes
-- already lower the EV (Emerald, the engine's ItemUseCB_ReduceEV), ours hands the use straight
-- back to the game's own code, so Emerald plays exactly as it does without this mod.
local B = {}

B.LIST = {
  { id = "POMEG_BERRY", stat = "hp", name = "HP" },
  { id = "KELPSY_BERRY", stat = "atk", name = "ATTACK" },
  { id = "QUALOT_BERRY", stat = "def", name = "DEFENSE" },
  { id = "HONDEW_BERRY", stat = "spa", name = "SP. ATK" },
  { id = "GREPA_BERRY", stat = "spd", name = "SP. DEF" },
  { id = "TAMATO_BERRY", stat = "spe", name = "SPEED" },
}
B.EV_DROP = 10
B.FRIENDSHIP = { 10, 5, 2 }   -- friendship below 100 / below 200 / above

local NO_EFFECT = "It won't have any effect."

-- the cart's own data lowers this berry's EV (Emerald): its effect bytes name a stat and a fall
local function cartLowers(ItemUse, num, session)
  local okE, e = pcall(ItemUse.effect, num, session)
  if not (okE and type(e) == "table") then return false end
  local change = tonumber(e[7]) or 0
  if change >= 0x80 then change = change - 0x100 end
  return change < 0 and ((tonumber(e[5]) or 0) ~= 0 or (tonumber(e[6]) or 0) ~= 0)
end

local function useOf(berry, require)
  return function(ctx)
    local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
    local mon = ctx and ctx.target
    if not (ok and Pokemon and type(mon) == "table") or mon.isEgg then return "failed", { NO_EFFECT } end
    local okU, ItemUse = pcall(require, "src.core.game3.item_use")
    local okD, ItemsData = pcall(require, "src.core.game3.items_data")
    local num = okD and ItemsData.toNumericId and ItemsData.toNumericId(ctx.itemId or berry.id)
    if okU and num and cartLowers(ItemUse, num, ctx.session) then
      local okV, used, _, text = pcall(ItemUse.useVitamin, ctx.session, mon, num)
      if okV then return used and "consumed" or "failed", { text or NO_EFFECT } end
    end
    local f0 = Pokemon.friendshipOf(mon)
    local e0 = tonumber(Pokemon.evsOf(mon)[berry.stat]) or 0
    Pokemon.lowerEvFromItem(mon, berry.stat, -B.EV_DROP)
    local mapSec = Pokemon.currentMapSec and ctx.session and Pokemon.currentMapSec(ctx.session) or nil
    Pokemon.itemFriendship(mon, B.FRIENDSHIP, { mapSec = mapSec })
    local f1 = Pokemon.friendshipOf(mon)
    local e1 = tonumber(Pokemon.evsOf(mon)[berry.stat]) or 0
    if f0 == f1 and e0 == e1 then return "failed", { NO_EFFECT } end
    local who = (Pokemon.displayMonName and Pokemon.displayMonName(mon)) or "It"
    local text
    if f0 ~= f1 and e0 ~= e1 then
      text = ("%s turned friendly.\nThe base %s fell!"):format(who, berry.name)
    elseif f0 ~= f1 then
      text = ("%s turned friendly.\nThe base %s can't fall!"):format(who, berry.name)
    else
      text = ("%s adores you!\nThe base %s fell!"):format(who, berry.name)
    end
    return "consumed", { text }
  end
end

-- -> how many berries got the effect
function B.register(mod, require)
  local items = mod.content and mod.content.items
  local effects = mod.content and mod.content.item_effects
  if not (items and effects and items.patch) then return 0 end
  local n = 0
  for _, berry in ipairs(B.LIST) do
    local effectId = "EV_" .. berry.id
    local okE = pcall(function()
      effects:register(effectId, { use = useOf(berry, require), needsTarget = true, field = true, battle = false })
    end)
    local okP = okE and pcall(function() items:patch(berry.id, { effect = effectId }) end)
    if okP then n = n + 1 elseif mod.log then mod.log:warn("%s keeps the game's own use", berry.id) end
  end
  return n
end

return B
