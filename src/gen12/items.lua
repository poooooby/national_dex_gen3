-- Evolution items on Gen 1 / Gen 2: the stones, trade items and held items evolutions call for
-- that the running cart lacks (data/gen12/items.lua), registered at load and sold in one shop.
--
-- Red/Blue/Yellow have no held items, so every one of them is used on the Pokemon, like a
-- stone: one `item_effects` record (Items.GEN1_EFFECT) that src/gen12/evolutions.lua answers
-- (Evolutions.useItem). The cart's own stones keep the cart's code, which already evolves any
-- species whose ITEM row names them.
-- Gold/Silver/Crystal hold items: a trade or hold item is just an item to give a Pokemon; a
-- stone gets an `item_effects` record of its own with `action = "stone"`, whose use runs Gold's
-- own Evolution.checkMon with the stone forced, exactly as Gold's stones do (so the
-- evolution.check conditions apply there too).
-- The Linking Cord (kind "cord") is used the same way on both games: it runs the game's own trade
-- evolution on the spot (Red: a TRADE row; Gold: EVOLVE_TRADE as if linked, so a row that wants
-- a held item takes it, and Gold's own Evolution.apply uses that item up).
--
-- Shops: Red's Celadon Dept. Store 4F clerk (its `mart` list, where the cart sells its stones),
-- Gold's Goldenrod Dept. Store 4F (found by its own stock, the vitamins, so the Crystal list
-- order does not matter).
--
-- Items.id(slug) -> the running game's id for an item: the cart's, ours, or another mod's of
-- the same id.

local Items = {}

Items.GEN1_EFFECT = "NATIONAL_DEX_GEN3_EVOLUTION_ITEM"

Items.GEN2_DESCRIPTION = {
  stone = "Evolves certain<NEXT>kinds of POKéMON.",
  cord = "Evolves POKéMON<NEXT>that evolve by trade.",
  trade = "Some POKéMON<NEXT>evolve holding it.",
  hold = "Some POKéMON<NEXT>evolve holding it.",
}

-- Gold's Goldenrod Dept. Store 4F stock (pokegold data/items/marts.asm MartGoldenrod4F)
Items.GEN2_SHOP = { "PROTEIN", "IRON", "CARBOS", "CALCIUM", "HP_UP" }
Items.GEN1_SHOP = { map = "CeladonMart4F", text = "TEXT_CELADONMART4F_CLERK" }

local function sameList(a, b)
  if type(a) ~= "table" or #a ~= #b then return false end
  for i = 1, #b do if a[i] ~= b[i] then return false end end
  return true
end

-- opts: { mod, generation, rows = data/gen12/items.lua, use = function(ctx) (Gen 1 effect)
--         or function(ctx) (Gen 2 stone), log }
function Items.register(opts)
  local mod, gen, log = opts.mod, opts.generation, opts.log
  local key = "gen" .. gen
  local items, effects = mod.content.items, mod.content.item_effects
  local state = { idOf = {}, registered = {}, failed = 0 }

  if gen == 1 then
    local ok, err = pcall(effects.register, effects, Items.GEN1_EFFECT,
      { use = opts.use, needsTarget = true, battle = false })
    if not ok and log then log:warn("evolution items cannot be used: %s", tostring(err)) end
  end

  local firstError
  for _, row in ipairs(opts.rows) do
    local cart = row.carts and row.carts[key]
    if cart then
      state.idOf[row.slug] = cart
    elseif items:get(row.id) ~= nil then
      state.idOf[row.slug] = row.id              -- another mod's item of this id
    else
      local rec = { id = row.id, name = row.name, price = row.price }
      if gen == 1 then
        rec.effect, rec.needsTarget = Items.GEN1_EFFECT, true
      else
        rec.pocket, rec.canToss, rec.canSelect = "ITEM", true, false
        rec.battleMenu = "ITEMMENU_NOUSE"
        local usable = row.kind == "stone" or row.kind == "cord"
        rec.fieldMenu = usable and "ITEMMENU_PARTY" or "ITEMMENU_NOUSE"
        rec.heldEffect, rec.heldParameter = "HELD_NONE", 0
        rec.description = Items.GEN2_DESCRIPTION[row.kind]
      end
      local ok, err = pcall(items.register, items, row.id, rec)
      if ok and gen == 2 and (row.kind == "stone" or row.kind == "cord") then
        ok, err = pcall(effects.register, effects, row.id, { action = "stone", use = opts.use })
      end
      if ok then
        state.idOf[row.slug] = row.id
        state.registered[#state.registered + 1] = row.id
      else
        state.failed = state.failed + 1
        firstError = firstError or (row.id .. ": " .. tostring(err))
      end
    end
  end
  if firstError and log then
    log:warn("%d evolution items could not be registered (first: %s)", state.failed, firstError)
  end
  state.id = function(slug) return state.idOf[slug] end
  return state
end

-- Put every registered item on sale. Returns the shop's name, or nil.
function Items.stock(mod, gen, state, log)
  if #state.registered == 0 then return nil end
  local ok, err = pcall(function()
    if gen == 1 then
      local pointers = mod.content.text_pointers
      local map = pointers:get(Items.GEN1_SHOP.map)
      local clerk = map and map[Items.GEN1_SHOP.text]
      if not (clerk and clerk.mart) then error("no Celadon Dept. Store 4F clerk") end
      -- a deep registry: the patch's list is added to the clerk's
      local extra = {}
      for _, id in ipairs(state.registered) do extra[#extra + 1] = id end
      pointers:patch(Items.GEN1_SHOP.map, { [Items.GEN1_SHOP.text] = { mart = extra } })
    else
      local marts = mod.content.marts
      for n = 0, 33 do
        local list = marts:get(tostring(n))
        if sameList(list, Items.GEN2_SHOP) then
          local stock = {}
          for _, id in ipairs(list) do stock[#stock + 1] = id end
          for _, id in ipairs(state.registered) do stock[#stock + 1] = id end
          marts:patch(tostring(n), stock)
          state.martIndex = n
          return
        end
      end
      error("no Goldenrod Dept. Store 4F")
    end
  end)
  if not ok then
    if log then log:warn("the evolution items are not sold: %s", tostring(err)) end
    return nil
  end
  return gen == 1 and "Celadon Dept. Store 4F" or "Goldenrod Dept. Store 4F"
end

return Items
