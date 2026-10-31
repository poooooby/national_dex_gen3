-- Standalone: luajit mods/national_dex_gen3/tests/shops_test.lua
-- (from the gen1recomp root; reads each imported cart's scripts/marts.lua).
--
-- data/shops.lua finds a store by its original stock. This proves every entry
-- is real: for each game it lists that has been imported, the `match` list is
-- one store, not none (a typo) and not several (it would sell in a town it
-- was not meant for); and that src/shops.lua adds the right items to it,
-- leaves every other store alone, adds nothing twice, and skips an item no
-- mod provides.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local root = (arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/.."
local rules = dofile(root .. "/data/shops.lua")
local itemRows = dofile(root .. "/data/items.lua")
local Shops = dofile(root .. "/src/shops.lua")

local index = {}
for _, r in ipairs(itemRows) do index[r.slug] = r.index end
-- and the new TMs (data/tms.lua), sold by slug "tm51" ...
for _, t in ipairs(dofile(root .. "/data/tms.lua")) do index[t.id:lower()] = t.index end
-- and the Dynamax items (src/dynamax.lua), "dynamax-candy" ...
for _, it in ipairs(dofile(root .. "/src/dynamax.lua")({}, { data = {} }).ITEMS) do
  index[it.id:lower():gsub("_", "-")] = it.index
end

-- the distinct stores of a cart: ptr -> items (the same list is stored under
-- three keys)
local function stores(game)
  local f = io.open(game .. "/data/generated/gba/scripts/marts.lua")
  if not f then return nil end
  f:close()
  local pack = dofile(game .. "/data/generated/gba/scripts/marts.lua")
  local out, seen = {}, {}
  for _, e in pairs(pack.marts or pack) do
    if type(e) == "table" and e.items and e.ptr and not seen[e.ptr] and e.kind ~= "decorations" then
      seen[e.ptr] = true
      out[#out + 1] = e
    end
  end
  return out
end

local function matches(list, want)
  if #list ~= #want then return false end
  for i = 1, #list do if tonumber(list[i]) ~= want[i] then return false end end
  return true
end

-- every added slug is an item this mod registers
for _, rule in ipairs(rules) do
  for _, slug in ipairs(rule.add) do
    T.check(index[slug] ~= nil, rule.store .. ": " .. slug .. " is one of this mod's items")
  end
end

-- each match is exactly one store, in every imported game it names
local carts = {}
for _, rule in ipairs(rules) do
  for _, game in ipairs(rule.games) do
    carts[game] = carts[game] == nil and (stores(game) or false) or carts[game]
    local list = carts[game]
    if list then
      local hits = 0
      for _, e in ipairs(list) do if matches(e.items, rule.match) then hits = hits + 1 end end
      T.eq(hits, 1, rule.store .. " is exactly one store in " .. game)
    end
  end
end

-- behavior, on FireRed's real stores through a stand-in Marts module
local fr = carts.firered
if fr then
  local byKey = {}
  for _, e in ipairs(fr) do byKey[e.key] = e end
  local fake = { itemsFor = function(key) local e = byKey[key]; return e and e.items, e end }
  package.loaded["src.core.game3.marts"] = fake
  local provided = function(slug) return index[slug] end
  T.check(Shops.install(rules, provided, function() return "firered" end), "installs over Marts.itemsFor")
  T.check(not Shops.install(rules, provided, function() return "firered" end), "and never twice")

  local function keyOf(match)
    for _, e in ipairs(fr) do if matches(e.items, match) then return e.key end end
  end
  -- (the evolution items and the new TMs are sold by the vending machines: the Marts keep the
  -- Dynamax items, at Celadon 5F beside the vitamins)
  local celadon5 = keyOf({ 63, 64, 65, 67, 70, 66 })
  local items = fake.itemsFor(celadon5)
  local function has(list, id) for _, v in ipairs(list) do if tonumber(v) == id then return true end end end
  T.check(has(items, index["dynamax-candy"]) and has(items, index["max-honey"]),
          "Celadon 5F sells the Dynamax items")
  T.check(has(items, 63), "and still sells its own")
  local n = #items
  fake.itemsFor(celadon5)
  T.eq(#items, n, "asking again adds nothing twice")

  local viridian = keyOf({ 4, 13, 14, 18 })
  T.eq(#fake.itemsFor(viridian), 4, "an unrelated store is untouched")
  local celadon4 = keyOf({ 80, 132, 95, 96, 97, 98 })
  T.eq(#fake.itemsFor(celadon4), 6, "Celadon 4F keeps its own stock (the machine sells the new stones)")
  local sixKey = keyOf({ 2, 19, 20, 24, 23, 85, 84, 130 })
  T.eq(#fake.itemsFor(sixKey), 8, "and so does Six Island")

  -- a rule only applies in the games it lists
  local wrongGame = { itemsFor = function() return { 63, 64, 65, 67, 70, 66 } end }
  package.loaded["src.core.game3.marts"] = wrongGame
  Shops.install(rules, provided, function() return "emerald" end)
  T.eq(#wrongGame.itemsFor("x"), 6, "a rule only applies in the games it lists")

  -- an item nothing provides is skipped, not sold as a broken id
  local lone = { itemsFor = function() return { 63, 64, 65, 67, 70, 66 } end }
  package.loaded["src.core.game3.marts"] = lone
  Shops.install(rules, function(slug) return slug ~= "dynamax-candy" and index[slug] or nil end,
                function() return "firered" end)
  local got = lone.itemsFor("x")
  T.check(not has(got, index["dynamax-candy"]) and has(got, index["max-honey"]),
          "an item no mod provides is skipped; the others still sell")
else
  print("firered not imported: behavior checks skipped")
end

T.finish("national_dex_gen3 shops")
