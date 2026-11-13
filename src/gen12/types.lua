-- Types and growth rates on Gen 1 / Gen 2, registered at load.
--
-- The `type_chart` registry owns the whole chart on these games (the engine registers the cart's
-- types and rows first, src/mods/Builtins.lua; the merge rebuilds `types` and `matchups` from
-- every registration), so the new types are plain content:
--   * Red/Blue/Yellow gain DARK, STEEL and FAIRY, Gold/Silver/Crystal FAIRY; each type's
--     physical/special category is what the game splits damage by. Steel physical and Dark
--     special as Gold has them; Fairy special, as on the Gen 3 path. Gen 2 also needs an
--     `index` (Present and Conversion2 read it).
--   * the matchup rows from data/gen12/cart.lua (tools/build_gen12.py): the whole chart as today's
--     has it: the new types' rows, Red's Ghost-vs-Psychic, Bug-vs-Poison and Ice-vs-Fire, Gold's two
--     Gen 2-only rows (Steel resisting Ghost and Dark) removed.
--   * the cart species and moves whose typing is different today are patched to it (Magnemite
--     Electric/Steel, Clefairy Fairy, Bite Dark...).
-- The `growth_rates` registry gets the two curves newer species use, ERRATIC and FLUCTUATING
-- (Gen 2 spells its curves GROWTH_*). data/gen12 uses the modern spellings throughout
-- (PSYCHIC, MEDIUM_FAST); Types.cartId / Types.forCart / Types.growthId turn them into the
-- running game's ids.

local Types = {}

Types.RECORDS = {
  DARK = { name = "DARK", category = "special" },
  STEEL = { name = "STEEL", category = "physical" },
  FAIRY = { name = "FAIRY", category = "special" },
}

-- Gen 2 types carry the cart's type byte; Gold's run 0-9 and 19-27, so Fairy takes the next one
Types.GEN2_INDEX = { FAIRY = 28 }

local CART_ID = { PSYCHIC = "PSYCHIC_TYPE" }

function Types.cartId(name)
  return CART_ID[name] or name
end

-- A modern type list as the game's own: cart ids, and Gen 2 writes a single type twice
function Types.forCart(list, generation)
  local out = {}
  for i, t in ipairs(list) do out[i] = Types.cartId(t) end
  if generation == 2 and #out == 1 then out[2] = out[1] end
  return out
end

function Types.growthId(name, generation)
  if generation == 2 then return "GROWTH_" .. name end
  return name
end

-- The Gen 3+ curves (pret's experience_tables.h), each step floored as the games compute them;
-- like those tables, level 1 is 1 Exp. on both.
Types.GROWTH = {
  ERRATIC = function(n)
    if n <= 1 then return n < 1 and 0 or 1 end
    local c = n * n * n
    if n <= 50 then return math.floor(c * (100 - n) / 50) end
    if n <= 68 then return math.floor(c * (150 - n) / 100) end
    if n <= 98 then return math.floor(c * math.floor((1911 - 10 * n) / 3) / 500) end
    return math.floor(c * (160 - n) / 100)
  end,
  FLUCTUATING = function(n)
    if n <= 1 then return n < 1 and 0 or 1 end
    local c = n * n * n
    if n <= 15 then return math.floor(c * (math.floor((n + 1) / 3) + 24) / 50) end
    if n <= 36 then return math.floor(c * (n + 14) / 50) end
    return math.floor(c * (math.floor(n / 2) + 32) / 50)
  end,
}

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

-- opts: { mod, cart = data/gen12/cart.lua, generation, log }. Returns a count table; any part
-- that fails logs once and leaves the rest registered.
function Types.register(opts)
  local mod, generation, log = opts.mod, opts.generation, opts.log
  local data = opts.cart and opts.cart["gen" .. generation] or {}
  local content = mod.content
  local counts = { types = 0, rows = 0, removed = 0, species = 0, moves = 0, growth = 0 }

  local function try(what, fn)
    local ok, err = pcall(fn)
    if not ok and log then log:warn("%s: %s", what, tostring(err)) end
  end

  try("new types", function()
    local chart = content.type_chart
    for _, name in ipairs(data.types or {}) do
      local record = {}
      for k, v in pairs(Types.RECORDS[name]) do record[k] = v end
      if generation == 2 then record.index = Types.GEN2_INDEX[name] end
      if chart:get(name) == nil then
        chart:register(name, record)
        counts.types = counts.types + 1
      end
    end
    for _, row in ipairs(data.add or {}) do
      local id = Types.cartId(row[1]) .. ">" .. Types.cartId(row[2])
      if chart:get(id) == nil then chart:register(id, { multiplier = row[3] })
      else chart:override(id, { multiplier = row[3] }) end
      counts.rows = counts.rows + 1
    end
    for _, row in ipairs(data.change or {}) do
      chart:override(Types.cartId(row[1]) .. ">" .. Types.cartId(row[2]), { multiplier = row[3] })
      counts.rows = counts.rows + 1
    end
    for _, id in ipairs(data.remove or {}) do
      local a, d = id:match("^([^>]+)>([^>]+)$")
      local cartRow = Types.cartId(a) .. ">" .. Types.cartId(d)
      if chart:get(cartRow) ~= nil then
        chart:remove(cartRow)
        counts.removed = counts.removed + 1
      end
    end
  end)

  try("modern typing of the cart's species", function()
    local pokemon = content.pokemon
    for _, id in ipairs(sortedKeys(data.species)) do
      if pokemon:get(id) ~= nil then
        pokemon:patch(id, { types = Types.forCart(data.species[id], generation) })
        counts.species = counts.species + 1
      end
    end
  end)

  try("modern typing of the cart's moves", function()
    local moves = content.moves
    for _, id in ipairs(sortedKeys(data.moves)) do
      if moves:get(id) ~= nil then
        moves:patch(id, { type = Types.cartId(data.moves[id]) })
        counts.moves = counts.moves + 1
      end
    end
  end)

  try("growth rates", function()
    local rates = content.growth_rates
    for _, name in ipairs(sortedKeys(Types.GROWTH)) do
      local id = Types.growthId(name, generation)
      if rates:get(id) == nil then
        rates:register(id, { expForLevel = Types.GROWTH[name] })
        counts.growth = counts.growth + 1
      end
    end
  end)

  return counts
end

return Types
