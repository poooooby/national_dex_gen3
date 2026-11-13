-- Standalone: luajit mods/national_dex_gen3/tests/gen12_data_test.lua [red|blue|yellow|gold|silver|crystal ...]
-- (from the gen1recomp root; checks against red, yellow, gold and crystal when none is named).
-- data/gen12/ (tools/build_gen12.py) is whole and fits the Gen 1/2 games: every species #152-1025
-- once, names / kinds / Pokédex lines within the cart's boxes, learnsets sorted, every move a
-- list names has a row, and on each cart every newer move either runs on an effect that cart has
-- or has stand-ins it has; evolutions point at real species and forms; the borrowed icons and
-- cries name the cart's own species; the keys (ids, slots) are the Gen 3 path's, so a species
-- is the same species on every game.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")

local function data(name) return H.module("data/gen12/" .. name) end

local function chars(s)          -- characters, not bytes (é is two)
  local n = 0
  for i = 1, #s do
    if bit.band(s:byte(i), 0xC0) ~= 0x80 then n = n + 1 end
  end
  return n
end
bit = require("bit")

local index = data("species/index.lua")
local species = {}
for _, shard in ipairs(index.shards) do
  for _, r in ipairs(data("species/" .. shard)) do species[#species + 1] = r end
end
local forms = data("forms.lua")
local crossgen = data("crossgen.lua")
local moves = data("moves.lua")
local cart = data("cart.lua")

-- ---------------------------------------------------------------- the species list
T.eq(index.first, 152, "species start at #152")
T.eq(#species, index.count, "index count matches the shards")
T.eq(#species, 1025 - 151, "every species #152-1025")
local byDex, byId = {}, {}
local okOrder = true
for i, r in ipairs(species) do
  if r.dex ~= 151 + i or r.slot ~= r.dex + 64 then okOrder = false end
  byDex[r.dex], byId[r.id] = r, r
end
T.check(okOrder, "in dex order, each at its Gen 3 slot (dex + 64)")
T.eq(#forms, 128, "the 128 forms")
local formById = {}
for i, f in ipairs(forms) do formById[f.id] = f end

-- the same ids and slots the Gen 3 path registers (data/species), so saves and other mods agree
local g3 = {}
for _, shard in ipairs(H.module("data/species/index.lua").shards) do
  for _, r in ipairs(H.module("data/species/" .. shard)) do g3[r.dex] = r end
end
local sameKeys = true
for dex, r in pairs(g3) do
  if not byDex[dex] or byDex[dex].id ~= r.id or byDex[dex].slot ~= r.slot then sameKeys = false end
end
T.check(sameKeys, "#387-1025 keep the Gen 3 path's ids and slots")
local g3forms, sameForms = H.module("data/species/forms.lua"), true
for i, f in ipairs(g3forms) do
  if not forms[i] or forms[i].id ~= f.id or forms[i].slot ~= f.slot then sameForms = false end
end
T.check(sameForms, "forms keep the Gen 3 path's ids and slots, in order")

-- ---------------------------------------------------------------- each record
local TYPES = {}
for _, t in ipairs({ "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST",
  "STEEL", "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC", "ICE", "DRAGON", "DARK", "FAIRY" }) do
  TYPES[t] = true
end
local GROWTH = { SLOW = true, MEDIUM_FAST = true, FAST = true, MEDIUM_SLOW = true, ERRATIC = true,
  FLUCTUATING = true }
local EGG = {}
for _, g in ipairs({ "EGG_MONSTER", "EGG_WATER_1", "EGG_BUG", "EGG_FLYING", "EGG_GROUND",
  "EGG_FAIRY", "EGG_PLANT", "EGG_HUMANSHAPE", "EGG_WATER_3", "EGG_MINERAL", "EGG_INDETERMINATE",
  "EGG_WATER_2", "EGG_DITTO", "EGG_DRAGON", "EGG_NONE" }) do EGG[g] = true end
local METHODS = { EVO_LEVEL = true, EVO_ITEM = true, EVO_TRADE = true, EVO_TRADE_ITEM = true,
  EVO_FRIENDSHIP = true, EVO_FRIENDSHIP_DAY = true, EVO_FRIENDSHIP_NIGHT = true, EVO_STAT = true }

local moveRow = {}
for _, m in ipairs(moves) do moveRow[m.n] = m end

local bad = {}
local function fail(what, r) bad[what] = bad[what] or (r.id or tostring(r.dex)) end

local function checkRecord(r, isForm)
  if chars(r.name) > 10 then fail("name over 10", r) end
  if #r.types < 1 or #r.types > 2 then fail("one or two types", r) end
  for _, t in ipairs(r.types) do if not TYPES[t] then fail("known type", r) end end
  for _, k in ipairs({ "hp", "attack", "defense", "speed", "specialAttack", "specialDefense" }) do
    local v = r.baseStats[k]
    if type(v) ~= "number" or v < 1 or v > 255 then fail("stats 1-255", r) end
  end
  if not GROWTH[r.growthRate] then fail("growth rate", r) end
  for _, g in ipairs(r.eggGroups) do if not EGG[g] then fail("egg group", r) end end
  if r.baseExp < 0 or r.baseExp > 255 or r.catchRate > 255 then fail("bytes", r) end
  local last = 0
  for _, row in ipairs(r.learnset) do
    if row[1] < last then fail("learnset sorted by level", r) end
    last = row[1]
    if row[2] > 165 and not moveRow[row[2]] then fail("every learnset move has a row", r) end
  end
  for _, n in ipairs(r.teach) do if n > 251 then fail("teach is #1-251", r) end end
  for _, n in ipairs(r.eggMoves) do
    if n > 165 and not moveRow[n] then fail("every egg move has a row", r) end
  end
  for _, e in ipairs(r.evolutions) do
    if not METHODS[e.method] then fail("evolution method", r) end
    if e.target and not (e.target >= 1 and e.target <= 1025) then fail("evolution target", r) end
    if e.targetForm and not formById[e.targetForm] then fail("evolution form", r) end
    if not e.target and not e.targetForm then fail("evolution has a target", r) end
    if (e.method == "EVO_ITEM" or e.method == "EVO_TRADE_ITEM") and type(e.item) ~= "string" then
      fail("item steps name an item", r)
    end
    for _, n in ipairs((e.when or {}).knows or {}) do
      if n > 165 and not moveRow[n] then fail("`knows` moves have a row", r) end
    end
  end
  if not isForm then
    local d = r.dexEntry
    if chars(d.kind) > 10 then fail("kind over 10", r) end
    if #d.text > 2 then fail("two pages at most", r) end
    for _, page in ipairs(d.text) do
      local lines = 0
      for line in (page .. "\n"):gmatch("(.-)\n") do
        lines = lines + 1
        if chars(line) > 18 then fail("Pokédex lines of 18", r) end
      end
      if lines > 3 then fail("three lines a page", r) end
    end
    if d.height <= 0 or d.weight <= 0 then fail("height and weight", r) end
  end
end

for _, r in ipairs(species) do checkRecord(r, false) end
for _, f in ipairs(forms) do
  checkRecord(f, true)
  if not (f.baseDex >= 1 and f.baseDex <= 1025) then fail("form base dex", f) end
  if f.baseDex >= 152 and byDex[f.baseDex].id ~= f.baseSpecies then fail("form base id", f) end
end
for _, step in ipairs(crossgen) do
  if not (step.source >= 1 and step.source <= 251) then fail("crossgen from #1-251", step) end
  if not (step.target and step.target >= 152) then fail("crossgen into a newer species", step) end
end
local none = next(bad) == nil
for what, who in pairs(bad) do print("FAIL " .. what .. " (" .. tostring(who) .. ")") end
T.check(none, "every species, form and cross-generation step is well formed")

-- the evolution items: one row per item any step names or wants held, names within 12 columns
local itemRows, itemBySlug, itemsOk = data("items.lua"), {}, true
for _, it in ipairs(itemRows) do
  if chars(it.name) > 12 or itemBySlug[it.slug] or not (it.kind == "stone" or it.kind == "trade"
      or it.kind == "hold" or it.kind == "cord") then itemsOk = false end
  itemBySlug[it.slug] = it
end
local function wantItems(step)
  if step.item and not itemBySlug[step.item] then itemsOk = false end
  local hold = step.when and step.when.hold
  for _, slug in ipairs(type(hold) == "table" and hold or { hold }) do
    if not itemBySlug[slug] then itemsOk = false end
  end
end
for _, r in ipairs(species) do for _, e in ipairs(r.evolutions) do wantItems(e) end end
for _, f in ipairs(forms) do for _, e in ipairs(f.evolutions) do wantItems(e) end end
for _, step in ipairs(crossgen) do wantItems(step) end
T.check(itemsOk, "every evolution item has a row, its name within 12 columns")

-- Sneasel is a Gold species: on Red it is a new one, and its night evolution is its own there
local weavile = false
for _, e in ipairs(byDex[215].evolutions) do if e.target == 461 then weavile = true end end
T.check(weavile, "Sneasel evolves into Weavile from its own record")
T.eq(#byDex[236].evolutions, 3, "Tyrogue's three outcomes")

-- ---------------------------------------------------------------- against each cart
for _, version in ipairs(H.versions()) do
  local gen = H.GENERATION[version]
  local d = H.data(version)
  local key = "gen" .. gen
  local maxDex, maxMove = gen == 1 and 151 or 251, gen == 1 and 165 or 251
  local cartMoves, effects, cartSpecies = {}, {}, {}
  for id, m in pairs(d.moves) do
    if type(m) == "table" and m.index then cartMoves[m.index] = m; effects[m.effect] = true end
  end
  for id, s in pairs(d.pokemon) do if type(s) == "table" and s.dex then cartSpecies[id] = s end end

  local missing = {}
  local function miss(what, who) missing[what] = missing[what] or tostring(who) end
  for _, m in ipairs(moves) do
    if m.n > maxMove then
      local real, subs = m[key], m.subs and m.subs[key]
      if real then
        if not effects[real.effect] then miss("a real move's effect is one the cart's moves use", m.n) end
        local look = m.look and m.look[key]
        if not (look and d.moves[look] and d.moves[look].index) then
          miss("a real move borrows a cart move's animation", m.n)
        end
      elseif not (subs and #subs > 0) then
        miss("every other newer move has stand-ins", m.n)
      else
        for _, s in ipairs(subs) do
          local ok = (s <= maxMove and cartMoves[s]) or (moveRow[s] and moveRow[s][key])
          if not ok then miss("stand-ins are moves the game has", m.n .. "->" .. s) end
        end
      end
    end
  end
  for _, r in ipairs(species) do
    if r.dex > maxDex and not cartSpecies[r.proxy[key]] then miss("proxy is a cart species", r.id) end
  end
  for _, f in ipairs(forms) do
    if not cartSpecies[f.proxy[key]] then miss("form proxy is a cart species", f.id) end
  end
  for id in pairs(cart[key].species) do
    if not cartSpecies[id] then miss("retyped species are the cart's", id) end
  end
  for id in pairs(cart[key].moves) do
    if not (d.moves[id] and d.moves[id].index) then miss("retyped moves are the cart's", id) end
  end
  for what, who in pairs(missing) do print("FAIL " .. version .. ": " .. what .. " (" .. who .. ")") end
  T.check(next(missing) == nil, version .. ": every newer move runs or has stand-ins there; proxies and retypes are the cart's")
end

T.finish("national_dex_gen3 Gen 1/2 data")
