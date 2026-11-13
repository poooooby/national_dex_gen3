-- The newer held items (data/held_items.lua) on Red / Blue / Yellow and Gold / Silver / Crystal:
-- each one the game does not already have (by id, or by name: Gold's own EXP SHARE stays its own)
-- is registered as an item of this game. Red: a plain item (any Bag item can be held through the
-- party menu's ITEM, src/gen12/held_red.lua). Gold: a Pack item a Pokemon can hold
-- (HELD_NONE: Gold's own held-item code leaves it alone; src/held/effects.lua gives it its effect),
-- with its number fixed at the row's `index` (saves keep the id, the number must not clash with
-- another mod's) and its two-line description.
--
-- Returns { byId = { id -> row }, registered = { id } }.

local Held = {}

local function norm(s) return (tostring(s or ""):upper():gsub("[^%w]", "")) end

-- opts: { mod, generation, rows, log }
function Held.register(opts)
  local mod, gen, log = opts.mod, opts.generation, opts.log
  local items = mod.content.items
  local state = { byId = {}, registered = {} }
  -- the game's own items by name, so a classic spelling is matched (BLACKGLASSES)
  local names = {}
  pcall(function()
    for id, rec in items:each() do
      names[norm(id)] = true
      if type(rec) == "table" and rec.name then names[norm(rec.name)] = true end
    end
  end)
  local firstError
  for _, row in ipairs(opts.rows or {}) do
    if items:get(row.id) == nil and not names[norm(row.name)] and not names[norm(row.id)] then
      local rec = { id = row.id, name = row.name, price = row.price }
      if gen == 2 then
        rec.pocket, rec.canToss, rec.canSelect = "ITEM", true, false
        rec.battleMenu, rec.fieldMenu = "ITEMMENU_NOUSE", "ITEMMENU_NOUSE"
        rec.heldEffect, rec.heldParameter = "HELD_NONE", 0
        rec.description = row.desc2
        rec.index = row.index
      end
      local ok, err = pcall(items.register, items, row.id, rec)
      if not ok and rec.index then
        rec.index = nil
        ok, err = pcall(items.register, items, row.id, rec)
      end
      if ok then
        state.byId[row.id] = row
        state.registered[#state.registered + 1] = row.id
      else
        firstError = firstError or (row.id .. ": " .. tostring(err))
      end
    end
  end
  if firstError and log then log:warn("held items: some could not be registered (first: %s)", firstError) end
  return state
end

return Held
