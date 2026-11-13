-- Exp. Candies on Gen 1 / Gen 2: Sword / Shield's XS, S, M, L and XL, used on a Pokemon from the
-- Bag for 100 / 800 / 3,000 / 10,000 / 30,000 Exp. Points. Same ids as on Gen 3 (and on Gold the
-- same item numbers, 950-954). Sold with the vitamins (src/gen12/shops.lua).
--
-- Each game's Rare Candy already runs everything after a level-up from the Bag, and a mod effect
-- can hand its result to that same flow:
--   Red   an item_effects record (Candies.GEN1_EFFECT, the five items name it) returns the Rare
--         Candy's own result, "consumed" with { leveledTo = level }: the Bag then shows the level
--         text, the stat window, the new level's moves (the forget prompt when four are known)
--         and a level evolution. The moves of the levels in between: Experience.movesLearnedAt is
--         wrapped to answer for every level gained, once, for the candy just used. The Rare
--         Candy's menu rules (the party menu stays up, not in battle) are extended to them.
--   Gold  a record per item with the Rare Candy's action ("candy"): Gold's own Mon.gainExperience
--         gives the Exp. (stats, pokemon.level_up per level), and Gold offers every move of the
--         levels gained and checks evolution after the text, as for a Rare Candy.
-- Like a Rare Candy they do nothing at the level cap, and a candy that gives no new level still
-- adds its Exp.

local Candies = {}

Candies.GEN1_EFFECT = "NATIONAL_DEX_GEN3_EXP_CANDY"
Candies.LIST = {
  { id = "EXP_CANDY_XS", name = "EXP.CANDY XS", index = 950, exp = 100, price = 20, amount = "100" },
  { id = "EXP_CANDY_S", name = "EXP.CANDY S", index = 951, exp = 800, price = 240, amount = "800" },
  { id = "EXP_CANDY_M", name = "EXP.CANDY M", index = 952, exp = 3000, price = 1000, amount = "3,000" },
  { id = "EXP_CANDY_L", name = "EXP.CANDY L", index = 953, exp = 10000, price = 3000, amount = "10,000" },
  { id = "EXP_CANDY_XL", name = "EXP.CANDY XL", index = 954, exp = 30000, price = 10000, amount = "30,000" },
}
Candies.ids = {}
local byId = {}
for _, c in ipairs(Candies.LIST) do Candies.ids[c.id] = c.index; byId[c.id] = c end

-- Red's Celadon Dept. Store 5F vitamin clerk; Gold's Goldenrod Dept. Store 4F (the vitamins)
Candies.GEN1_SHOP = { map = "CeladonMart5F", text = "TEXT_CELADONMART5F_CLERK2" }
Candies.GEN2_SHOP = { "PROTEIN", "IRON", "CARBOS", "CALCIUM", "HP_UP" }

-- ------------------------------------------------------------------ Red
-- The process-wide wraps (games switch in-process); each acts only on these item ids, and on the
-- one candy whose moves are waiting.
local function installGen1Wraps(require)
  local okE, ItemEffects = pcall(require, "src.inventory.ItemEffects")
  local okX, Experience = pcall(require, "src.battle.Experience")
  if not (okE and okX and type(ItemEffects) == "table" and type(Experience) == "table") then
    return nil
  end
  local hub = ItemEffects.__ndxGen12Candies
  if hub then return hub end
  hub = { pending = nil }
  ItemEffects.__ndxGen12Candies = hub
  for _, name in ipairs({ "keepsPartyMenuOpen", "usesMedicineMenu", "notTimeInBattle" }) do
    local base = ItemEffects[name]
    if type(base) == "function" then
      ItemEffects[name] = function(id, ...)
        if byId[id] then return true end
        return base(id, ...)
      end
    end
  end
  local baseMoves = Experience.movesLearnedAt
  Experience.movesLearnedAt = function(def, level, ...)
    local p = hub.pending
    if p and p.def == def and p.to == level then
      hub.pending = nil
      local out, seen = {}, {}
      for lv = p.from + 1, p.to do
        for _, move in ipairs(baseMoves(def, lv, ...) or {}) do
          if not seen[move] then seen[move] = true; out[#out + 1] = move end
        end
      end
      return out
    end
    return baseMoves(def, level, ...)
  end
  return hub
end

local function gen1Use(require, hub, onLevels)
  local Growth = require("src.pokemon.Growth")
  local Stats = require("src.pokemon.Stats")
  local Strings = require("src.core.Strings")
  local romText = require("src.core.RomText")
  return function(ctx)
    local data, mon = ctx.data, ctx.target
    local candy = byId[ctx.itemId]
    local noEffect = romText(data, "_ItemUseNoEffectText", "It won't have\nany effect.")
    local def = mon and data.pokemon[mon.species]
    if not (candy and def) then return "failed", { noEffect } end
    local cap = (data.constants and tonumber(data.constants.levelCap)) or 100
    local level = mon.level or 1
    if level >= cap then return "failed", { noEffect } end
    local rate, rates = def.growthRate, data.growth_rates
    local top = Growth.expForLevel(rate, cap, rates)
    local exp = tonumber(mon.exp) or Growth.expForLevel(rate, level, rates)
    mon.exp = math.min(exp + candy.exp, top)
    local reached = Growth.levelForExp(rate, mon.exp, cap, rates)
    local name = mon.nickname or def.name
    if reached <= level then
      return "consumed", { Strings("%s gained\n%s EXP. Points!", name, candy.amount) }
    end
    mon.level = reached
    local old = mon.stats
    mon.stats = Stats.calc(def, reached, mon.dvs, mon.statExp)
    if old and old.hp then
      mon.hp = math.min(mon.stats.hp, (mon.hp or 0) + (mon.stats.hp - old.hp))
    end
    pcall(function()
      require("src.world.PikachuFollower").modifyHappiness(ctx.save, "LEVELUP", mon)
    end)
    if onLevels then pcall(onLevels, mon, reached - level) end
    if hub then hub.pending = { def = def, from = level, to = reached } end
    return "consumed", { romText(data, "_RareCandyText", "%s grew\nto level %d!", name, reached) },
      { leveledTo = reached }
  end
end

-- ------------------------------------------------------------------ Gold
local function gen2Use(require)
  local Mon = require("src.battle.gen2.Mon")
  local Happiness = require("src.core.gen2.Happiness")
  local Strings = require("src.core.Strings")
  local ItemEffects = require("src.core.gen2.ItemEffects")
  return function(ctx)
    local mon, data = ctx.mon, ctx.data
    local candy = byId[ctx.item]
    local noEffect = ItemEffects.TEXT_NO_EFFECT or "It won't have any\neffect."
    if not (mon and candy) or ctx.battle or mon.isEgg then return { used = false, text = noEffect } end
    if (mon.level or 1) >= (Mon.MAX_LEVEL or 100) then return { used = false, text = noEffect } end
    local def = data and data.pokemon and data.pokemon[Mon.partySpecies(mon)]
    local name = mon.nickname or (def and def.name) or tostring(mon.species)
    local r = Mon.gainExperience(mon, candy.exp, data)
    if not r or (r.levels or 0) <= 0 then
      return { used = true, learned = {}, text = Strings("%s gained\n%s EXP. Points!", name, candy.amount) }
    end
    for _ = 1, r.levels do Happiness.change(mon, "GAINLEVEL") end
    return { used = true, level = r.to, learned = r.learned or {}, sfx = "Sfx_DexFanfare5079",
      text = Strings("%s grew to\nlevel %d!", name, r.to) }
  end
end

Candies.GEN2_DESCRIPTION = "Gives a POKéMON<NEXT>%s EXP.POINTS."

-- opts: { mod, generation, require, onLevels = fn(mon, levels) (Red: the friendship counter), log }
-- Returns { registered = { ids } }
function Candies.register(opts)
  local mod, gen, require, log = opts.mod, opts.generation, opts.require, opts.log
  local items, effects = mod.content.items, mod.content.item_effects
  local state = { registered = {} }
  local firstError
  if gen == 1 then
    local hub = installGen1Wraps(require)
    local ok, err = pcall(effects.register, effects, Candies.GEN1_EFFECT,
      { use = gen1Use(require, hub, opts.onLevels), needsTarget = true, battle = false })
    if not ok then
      if log then log:warn("Exp. Candies are off: %s", tostring(err)) end
      return state
    end
  end
  local use = gen == 2 and gen2Use(require) or nil
  for _, c in ipairs(Candies.LIST) do
    local rec = { id = c.id, name = c.name, price = c.price }
    if gen == 1 then
      rec.effect, rec.needsTarget = Candies.GEN1_EFFECT, true
    else
      rec.index, rec.pocket = c.index, "ITEM"
      rec.fieldMenu, rec.battleMenu = "ITEMMENU_PARTY", "ITEMMENU_NOUSE"
      rec.canToss, rec.canSelect = true, false
      rec.heldEffect, rec.heldParameter = "HELD_NONE", 0
      rec.description = Candies.GEN2_DESCRIPTION:format(c.amount)
    end
    local ok, err = true, nil
    if items:get(c.id) == nil then
      ok, err = pcall(items.register, items, c.id, rec)
      if ok and gen == 2 then
        ok, err = pcall(effects.register, effects, c.id,
          { action = "candy", field = true, needsTarget = true, use = use })
      end
    end
    if ok then state.registered[#state.registered + 1] = c.id
    else firstError = firstError or (c.id .. ": " .. tostring(err)) end
  end
  if firstError and log then log:warn("Exp. Candies: %s", firstError) end
  return state
end

return Candies
