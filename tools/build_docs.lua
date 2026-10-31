-- Builds the player reference in docs/ from the mod's own data, so it cannot
-- drift from what the game does:
--   docs/items.md            the added items: price, where to buy, what evolves with them
--   docs/tms.md              the added TMs: move, price, where to buy, how many Pokemon learn it
--   docs/moves.md            the added moves: type, power, accuracy, PP, what they do
--   docs/abilities.md        the added abilities and what they do
--   docs/fairy.md            every Fairy-type Pokemon, original, added and forms
--   docs/pokemon.md          index of the added Pokemon
--   docs/pokemon/genN.md     every added species of one generation: types, its
--                            Gen 3 ability, and its level-up learnset
--
-- Run from the mod root (names come from an imported cart):
--   luajit tools/build_docs.lua [<cart>/data/generated/gba/pokemon]
-- Default cart: ../gen1recomp/firered/data/generated/gba/pokemon

local cart = arg[1] or "../gen1recomp/firered/data/generated/gba/pokemon"

local function load(path)
  local f = assert(loadfile(path), path)
  return f()
end

local abilityNames = load(cart .. "/ability_names.lua")
local moveNames = load(cart .. "/move_names.lua")
local speciesNames = load(cart .. "/names.lua")
local national = load(cart .. "/national.lua")

-- "ROCK HEAD" -> "Rock Head", "DOUBLE-EDGE" -> "Double-Edge", "MR. MIME" -> "Mr. Mime"
local function title(s)
  s = tostring(s):lower():gsub("\226\128\153", "'")   -- a curly apostrophe is a plain one
  s = s:gsub("\195\137", "\195\169")                    -- lower() leaves UTF-8 alone: FLABÉBÉ
  return (s:gsub("(%a)([%w'\128-\255]*)", function(a, b) return a:upper() .. b end))
end

-- ---- data

local items = load("data/items.lua")
local shops = load("data/shops.lua")
-- the vending machines (data/vending.lua) are stores too: each one's tabs as one list
-- (one per place it stands)
for _, m in ipairs(load("data/vending.lua")) do
  local add = {}
  for _, tab in ipairs(m.tabs) do
    for _, slug in ipairs(tab.add) do add[#add + 1] = slug end
  end
  for _, place in ipairs(m.places) do
    shops[#shops + 1] = { games = place.games, store = place.store, add = add }
  end
end
local crossgen = load("data/species/crossgen.lua")
local forms = load("data/species/forms.lua")
-- the Fairy type (src/types.lua): species by National number and forms by id, modern typing
local fairy = load("data/types.lua")
-- moves newer than Gen 3 that are real moves (src/moves.lua): their names in learnsets
local newMoves = load("data/moves.lua")
for _, m in ipairs(newMoves) do moveNames[m.index] = m.full or m.name end
local index = load("data/species/index.lua")
local species = {}
for _, shard in ipairs(index.shards) do
  for _, r in ipairs(load("data/species/" .. shard)) do species[#species + 1] = r end
end
table.sort(species, function(a, b) return a.dex < b.dex end)

local byDex = {}
for _, r in ipairs(species) do byDex[r.dex] = title(r.name) end
-- cart species by national number
for internal, name in pairs(speciesNames) do
  local dex = national.toNational and national.toNational[internal]
  if dex and dex <= 386 and not byDex[dex] and name ~= "??????????" then byDex[dex] = title(name) end
end

local function out(path, lines)
  local f = assert(io.open(path, "wb"))
  f:write(table.concat(lines, "\n"), "\n")
  f:close()
end

-- ---- items.md

local GROUP = {
  frlg = { "firered", "leafgreen" },
  rse = { "ruby", "sapphire", "emerald" },
}
local function groupOf(rule)
  for _, g in ipairs(rule.games) do
    if g == "firered" then return "frlg" end
    if g == "ruby" then return "rse" end
  end
end

-- slug -> { frlg = { store, ... }, rse = { ... } }
local sold = {}
for _, rule in ipairs(shops) do
  local g = groupOf(rule)
  for _, slug in ipairs(rule.add) do
    sold[slug] = sold[slug] or { frlg = {}, rse = {} }
    table.insert(sold[slug][g], rule.store)
  end
end

-- slug -> list of "Source -> Target (how)"
local uses = {}
local METHOD = { EVO_ITEM = "use it on", EVO_TRADE_ITEM = "trade holding it",
                 EVO_TRADE = "use it on, in place of a trade" }
local function addUse(slug, source, target, method, note)
  uses[slug] = uses[slug] or {}
  table.insert(uses[slug], string.format("%s → %s (%s%s)", source, target, METHOD[method] or method,
    note and (", " .. note) or ""))
end
-- a level-up that needs a held item (src/conditional_evos.lua: Dusk Lycanroc, Alcremie)
local seenHold = {}
local function addHoldUse(slug, r, e)
  -- r: the source species record, or a { name = ... } stand-in for a cart species
  local base = e.target and byDex[e.target]
  local form
  if e.targetForm then
    for _, f in ipairs(forms) do
      if f.id == e.targetForm then base, form = byDex[f.baseDex], f.form break end
    end
  end
  base = base or ("#" .. tostring(e.target))
  -- one outcome of several (the held item alone picks it): name the form; when any of a
  -- list of items will do, the evolution is just Source -> Species
  local label = (form and type(e.when.hold) == "string") and
    (base .. " (" .. title((form:gsub("_", " "))) .. ")") or base
  local when = e.when and e.when.time and (e.when.time == "night" and ", at night" or ", by day") or ""
  local text = string.format("%s → %s (hold it while it levels up%s)", title(r.name), label, when)
  if not seenHold[slug .. text] then
    seenHold[slug .. text] = true
    uses[slug] = uses[slug] or {}
    table.insert(uses[slug], text)
  end
end
for _, r in ipairs(species) do
  for _, e in ipairs(r.evolutions or {}) do
    if e.item then
      local target = e.target and (byDex[e.target] or ("#" .. e.target)) or "?"
      if e.targetForm then
        for _, f in ipairs(forms) do
          if f.id == e.targetForm then
            target = (byDex[f.baseDex] or "?") .. " (" .. title((f.form:gsub("_", " "))) .. ")"
          end
        end
      end
      addUse(e.item, title(r.name), target, e.method)
    end
    local hold = e.when and e.when.hold
    if type(hold) == "string" then addHoldUse(hold, r, e)
    elseif type(hold) == "table" then
      for _, slug in ipairs(hold) do addHoldUse(slug, r, e) end
    end
  end
end
-- a form's own label: "Slowpoke (Galar)"
local formById = {}
for _, f in ipairs(forms) do formById[f.id] = f end
local function formLabel(f)
  return string.format("%s (%s)", title(f.name or f.baseSpecies:gsub("_", " ")), title((tostring(f.form):gsub("_", " "))))
end
local function stepTarget(e)
  if e.targetForm and formById[e.targetForm] then return formLabel(formById[e.targetForm]) end
  return e.target and (byDex[e.target] or ("#" .. e.target)) or "?"
end
for _, f in ipairs(forms) do
  for _, e in ipairs(f.evolutions or {}) do
    if e.item then addUse(e.item, formLabel(f), stepTarget(e), e.method) end
    local hold = e.when and e.when.hold
    if type(hold) == "string" then
      local when = e.when.time and (e.when.time == "night" and ", at night" or ", by day") or ""
      local text = string.format("%s → %s (hold it while it levels up%s)", formLabel(f), stepTarget(e), when)
      if not seenHold[hold .. text] then
        seenHold[hold .. text] = true
        uses[hold] = uses[hold] or {}
        table.insert(uses[hold], text)
      end
    end
  end
end
for _, e in ipairs(crossgen) do
  if e.item then
    addUse(e.item, byDex[e.source] or ("#" .. e.source), byDex[e.target] or ("#" .. e.target), e.method,
      e.gender == "M" and "male only" or e.gender == "F" and "female only" or nil)
  end
  local hold = e.when and e.when.hold
  if type(hold) == "string" then
    addHoldUse(hold, { name = byDex[e.source] or ("#" .. e.source) }, e)
  end
end

-- the Linking Cord (src/conditional_evos.lua): used in place of any trade, so it evolves the cart's
-- trade evolutions and every EVO_TRADE / EVO_TRADE_ITEM row of this mod's species, forms and the
-- cart species' new evolutions; a held-item trade still needs its item held (and uses it up)
local CART_TRADES = {  -- source dex, target dex, held item (nil: a plain trade)
  { 64, 65 }, { 67, 68 }, { 75, 76 }, { 93, 94 },                    -- Kadabra, Machoke, Graveler, Haunter
  { 61, 186, "King's Rock" }, { 79, 199, "King's Rock" }, { 95, 208, "Metal Coat" },
  { 123, 212, "Metal Coat" }, { 117, 230, "Dragon Scale" }, { 137, 233, "Up-Grade" },
  { 366, 367, "Deep Sea Tooth" }, { 366, 368, "Deep Sea Scale" },
}
local itemTitle = {}
for _, it in ipairs(items) do itemTitle[it.slug] = title(it.name) end
local function cordUse(source, target, slug)
  addUse("linking-cord", source, target, "EVO_TRADE",
    slug and ("while it holds " .. (itemTitle[slug] or title((slug:gsub("-", " "))))) or nil)
end
for _, p in ipairs(CART_TRADES) do
  addUse("linking-cord", byDex[p[1]], byDex[p[2]], "EVO_TRADE", p[3] and ("while it holds " .. p[3]) or nil)
end
for _, r in ipairs(species) do
  for _, e in ipairs(r.evolutions or {}) do
    if e.method == "EVO_TRADE" or e.method == "EVO_TRADE_ITEM" then cordUse(title(r.name), stepTarget(e), e.item) end
  end
end
for _, f in ipairs(forms) do
  for _, e in ipairs(f.evolutions or {}) do
    if e.method == "EVO_TRADE" or e.method == "EVO_TRADE_ITEM" then cordUse(formLabel(f), stepTarget(e), e.item) end
  end
end
for _, e in ipairs(crossgen) do
  if e.method == "EVO_TRADE" or e.method == "EVO_TRADE_ITEM" then
    cordUse(byDex[e.source] or ("#" .. e.source), byDex[e.target] or ("#" .. e.target), e.item)
  end
end

-- the items that are not for evolving, from the modules that register them: Exp. Candies
-- (src/exp_candies.lua) and the Dynamax items (src/dynamax.lua); slug as data/shops.lua spells it
local others = {}
local function slugOf(id) return (id:lower():gsub("_", "-")) end
for _, c in ipairs(load("src/exp_candies.lua").LIST) do
  others[#others + 1] = { slug = slugOf(c.id), name = c.name, price = c.price,
    use = "Use it on a Pokémon from the Bag: " .. c.amount .. " Exp. Points, with any level-ups, new moves "
      .. "and evolution a Rare Candy would give. Not sold: Dynamax Raids gives them as rewards." }
end
local DYNAMAX_USE = {
  DYNAMAX_CANDY = "Use it on a Pokémon from the Bag: its Dynamax Level rises by 1, up to 10 (not Zacian, "
    .. "Zamazenta or Eternatus).",
  MAX_MUSHROOMS = "Use it on a Pokémon that has a Gigantamax form, with 3 in the Bag: they make a Max Soup "
    .. "that gives it the Gigantamax Factor, or takes the factor away if it has it (never Melmetal).",
  MAX_HONEY = "Not used on its own: Urshifu's Max Soup takes 1 Max Honey along with the 3 Max Mushrooms.",
  DYNAMAX_CRYSTAL = "No use from the Bag: Dynamax Raids spends one at a den for a legendary or mythical "
    .. "Pokémon's raid.",
}
do
  local okD, Dx = pcall(load("src/dynamax.lua"), { log = { info = function() end, warn = function() end } },
    { data = load("data/dynamax.lua") })
  for _, it in ipairs(okD and Dx.ITEMS or {}) do
    others[#others + 1] = { slug = slugOf(it.id), name = it.name, price = it.price, use = DYNAMAX_USE[it.id] }
  end
end

local function join(list, sep) return table.concat(list, sep) end

local L = {
  "# Added items",
  "",
  "WoobleDex adds " .. #items .. " evolution items that no Gen 3 game has, so the Pokémon that",
  "need them can evolve. They are all sold by the EVO EXPRESS vending machine: Celadon Dept. Store",
  "4F in FireRed / LeafGreen, Lilycove Dept. Store 2F in Ruby / Sapphire / Emerald.",
  "",
  "Further down: [other items](#other-items), the Exp. Candies and the Dynamax items.",
  "",
  "*Generated from `data/items.lua`, `data/shops.lua`, `data/vending.lua`, the Exp. Candy and Dynamax item lists by",
  "`tools/build_docs.lua`.*",
  "",
  "## Summary",
  "",
  "| Item | Price | FireRed / LeafGreen | Ruby / Sapphire / Emerald |",
  "|---|---|---|---|",
}
for _, it in ipairs(items) do
  local s = sold[it.slug] or { frlg = {}, rse = {} }
  L[#L + 1] = string.format("| %s | ₽%d | %s | %s |", it.name, it.price,
    #s.frlg > 0 and join(s.frlg, "; ") or "not sold",
    #s.rse > 0 and join(s.rse, "; ") or "not sold")
end

L[#L + 1] = ""
L[#L + 1] = "Prices are what a store charges; it buys the item back at half. They come from Bulbapedia"
L[#L + 1] = "(twice the sell price listed for the earliest game that has one), or ₽2100, the Gen 3"
L[#L + 1] = "evolution stone price, where there is none. See [CREDITS](../CREDITS.md)."
L[#L + 1] = ""
L[#L + 1] = "## What each item is for"
L[#L + 1] = ""
for _, it in ipairs(items) do
  L[#L + 1] = "### " .. it.name
  L[#L + 1] = ""
  L[#L + 1] = "- Price: ₽" .. it.price
  local s = sold[it.slug] or { frlg = {}, rse = {} }
  L[#L + 1] = "- FireRed / LeafGreen: " .. (#s.frlg > 0 and join(s.frlg, "; ") or "not sold")
  L[#L + 1] = "- Ruby / Sapphire / Emerald: " .. (#s.rse > 0 and join(s.rse, "; ") or "not sold")
  local u = uses[it.slug]
  if u then
    table.sort(u)
    L[#L + 1] = "- Evolves: " .. join(u, "; ")
  end
  L[#L + 1] = ""
end

if #others > 0 then
  L[#L + 1] = "## Other items"
  L[#L + 1] = ""
  L[#L + 1] = "Not for evolving: the Exp. Candies, and the Dynamax items for a Pokémon's Dynamax Level and"
  L[#L + 1] = "Gigantamax Factor (shown on its summary and in the PC)."
  L[#L + 1] = ""
  L[#L + 1] = "| Item | Price | FireRed / LeafGreen | Ruby / Sapphire / Emerald |"
  L[#L + 1] = "|---|---|---|---|"
  for _, it in ipairs(others) do
    local s = sold[it.slug] or { frlg = {}, rse = {} }
    L[#L + 1] = string.format("| %s | ₽%d | %s | %s |", it.name, it.price,
      #s.frlg > 0 and join(s.frlg, "; ") or "not sold", #s.rse > 0 and join(s.rse, "; ") or "not sold")
  end
  L[#L + 1] = ""
  for _, it in ipairs(others) do
    L[#L + 1] = "### " .. it.name
    L[#L + 1] = ""
    L[#L + 1] = "- Price: ₽" .. it.price
    if it.use then L[#L + 1] = "- " .. it.use end
    L[#L + 1] = ""
  end
end

-- stores
local stores = {}
for _, rule in ipairs(shops) do stores[#stores + 1] = rule end
L[#L + 1] = "## By store"
L[#L + 1] = ""
for _, g in ipairs({ "frlg", "rse" }) do
  L[#L + 1] = g == "frlg" and "### FireRed / LeafGreen" or "### Ruby / Sapphire / Emerald"
  L[#L + 1] = ""
  for _, rule in ipairs(stores) do
    if groupOf(rule) == g then
      local names = {}
      for _, slug in ipairs(rule.add) do
        for _, list in ipairs({ items, others }) do
          for _, it in ipairs(list) do
            if it.slug == slug then names[#names + 1] = string.format("%s (₽%d)", it.name, it.price) end
          end
        end
      end
      if #names > 0 then L[#L + 1] = "- **" .. rule.store .. "**: " .. join(names, ", ") end
    end
  end
  L[#L + 1] = ""
end
out("docs/items.md", L)

-- ---- pokemon

local GEN = {
  ["generation-iv"] = 4, ["generation-v"] = 5, ["generation-vi"] = 6,
  ["generation-vii"] = 7, ["generation-viii"] = 8, ["generation-ix"] = 9,
}
local byGen = {}
for _, r in ipairs(species) do
  local g = GEN[r.generation] or 0
  byGen[g] = byGen[g] or {}
  table.insert(byGen[g], r)
end

-- real abilities newer than Gen 3 (src/abilities.lua): a slot whose ability is one of them shows
-- it; every other slot the closest Gen 3 ability, as in the game
local realAbilities = load("data/abilities.lua")
local realBySlug = {}
for _, d in ipairs(realAbilities.defs or {}) do realBySlug[d.slug] = d end

local function abilityText(r)
  local names, seen = {}, {}
  local slots = r.baseSpecies and realAbilities.forms[r.id] or (not r.baseSpecies and realAbilities.species[r.dex])
  local anyReal = false
  for _, s in ipairs(slots or {}) do if realBySlug[s[1]] then anyReal = true end end
  if anyReal then
    for _, s in ipairs(slots) do
      local d = realBySlug[s[1]]
      local n = d and d.name or abilityNames[s[2]]
      if n and not seen[n] then seen[n] = true; names[#names + 1] = title(n) end
    end
    return join(names, " / ")
  end
  for _, id in ipairs(r.abilities or {}) do
    local n = abilityNames[id]
    if n and not seen[n] then seen[n] = true; names[#names + 1] = title(n) end
  end
  return #names > 0 and join(names, " / ") or "none"
end

local function learnsetText(r)
  local parts = {}
  for _, row in ipairs(r.learnset or {}) do
    parts[#parts + 1] = string.format("%d %s", row[1], title(moveNames[row[2]] or ("Move " .. row[2])))
  end
  return join(parts, " · ")
end

local function typesText(r)
  local list = (r.baseSpecies and fairy.forms[r.id]) or (not r.baseSpecies and fairy.species[r.dex]) or r.types or {}
  local t = {}
  for i, ty in ipairs(list) do
    if i == 1 or ty ~= list[1] then t[#t + 1] = title(ty) end
  end
  return join(t, " / ")
end

os.execute("mkdir docs\\pokemon 2> nul")
local I = {
  "# Added Pokémon",
  "",
  "WoobleDex adds " .. #species .. " species, National Dex #387–1025 (Generations 4–9), to",
  "FireRed, LeafGreen, Ruby, Sapphire and Emerald. Each entry lists the typing, the abilities it",
  "has in this game, and its level-up learnset (`level move`).",
  "",
  "*Generated from `data/species/` by `tools/build_docs.lua`.*",
  "",
  "## How to read the entries",
  "",
  "- **Ability.** " .. #(realAbilities.defs or {}) .. " newer abilities work for real ([the list](abilities.md));",
  "  any other is the closest Gen 3 ability (for example Simple becomes Own Tempo), which the",
  "  Pokémon shows and acts like. A second name is its second ability slot.",
  "- **Typing.** The modern typing, Fairy included (Gen 6's type chart).",
  "- **Learnset.** The same moves at the same levels as in the modern games. Newer moves work for",
  "  real ([the list](moves.md)); the few that can't are replaced, at the same level, by the closest",
  "  Gen 3 move.",
  "- TM, HM, tutor and egg moves are not listed here.",
  "",
  "## Generations",
  "",
}
for g = 4, 9 do
  local list = byGen[g] or {}
  if #list > 0 then
    I[#I + 1] = string.format("- [Generation %d](pokemon/gen%d.md): #%d–%d, %d Pokémon", g, g,
      list[1].dex, list[#list].dex, #list)
  end
end
I[#I + 1] = ""
I[#I + 1] = "## Alternate forms"
I[#I + 1] = ""
I[#I + 1] = "- [Forms](pokemon/forms.md): Alolan, Galarian, Hisuian and Paldean forms, Wormadam's cloaks, the Rotom appliances,"
I[#I + 1] = "  the Therian and Origin forms and more, each a Pokémon of its own."
I[#I + 1] = ""
I[#I + 1] = "## By type"
I[#I + 1] = ""
I[#I + 1] = "- [Fairy](fairy.md): every Fairy-type Pokémon, the originals that became part Fairy included."
out("docs/pokemon.md", I)

for g = 4, 9 do
  local list = byGen[g]
  if list and #list > 0 then
    local P = {
      string.format("# Generation %d Pokémon", g),
      "",
      string.format("%d Pokémon, #%d–%d. [Back to the index](../pokemon.md).", #list, list[1].dex, list[#list].dex),
      "",
    }
    for _, r in ipairs(list) do
      P[#P + 1] = string.format("### #%d %s", r.dex, title(r.name))
      P[#P + 1] = ""
      P[#P + 1] = "- Type: " .. typesText(r)
      P[#P + 1] = "- Ability: " .. abilityText(r)
      P[#P + 1] = "- Learnset: " .. learnsetText(r)
      P[#P + 1] = ""
    end
    out(string.format("docs/pokemon/gen%d.md", g), P)
  end
end

-- ---- forms

-- (forms is loaded with the other data above)
-- the item's full name (the in-game one may be abbreviated to fit 14 characters)
local FULL_NAME = { ["leaders-crest"] = "Leader's Crest", ["scroll-of-darkness"] = "Scroll of Darkness",
                    ["scroll-of-waters"] = "Scroll of Waters" }
local function itemText(slug) return FULL_NAME[slug] or title((slug:gsub("-", " "))) end
-- how a form evolves, in words: "into Sandslash (Alola) with an Ice Stone"
local function evolvesText(r)
  local parts = {}
  for _, e in ipairs(r.evolutions or {}) do
    local how
    if e.method == "EVO_ITEM" then how = "use " .. itemText(e.item)
    elseif e.method == "EVO_TRADE" then how = "trade"
    elseif e.method == "EVO_TRADE_ITEM" then how = "trade holding " .. itemText(e.item)
    elseif e.method == "EVO_FRIENDSHIP" then how = "high friendship"
    else
      local w = e.when or {}
      local bits = {}
      if (e.level or 1) > 1 then bits[#bits + 1] = "level " .. e.level end
      if w.hold then bits[#bits + 1] = "holding " .. itemText(type(w.hold) == "string" and w.hold or w.hold[1]) end
      if w.crits then bits[#bits + 1] = "after " .. w.crits .. " critical hits in one battle" end
      if w.hpLost then bits[#bits + 1] = "leveling up " .. w.hpLost .. "+ HP down" end
      if w.recoil then bits[#bits + 1] = "after " .. w.recoil .. " recoil damage" end
      if w.gender then bits[#bits + 1] = (w.gender == "F" and "female" or "male") end
      if w.time == "night" then bits[#bits + 1] = "at night" elseif w.time == "day" then bits[#bits + 1] = "by day" end
      how = #bits > 0 and table.concat(bits, ", ") or "level up"
    end
    parts[#parts + 1] = string.format("into %s (%s)", stepTarget(e), how)
  end
  return #parts > 0 and table.concat(parts, "; ") or nil
end

local function formName(r)
  local label = tostring(r.form):gsub("_", " ")
  return string.format("%s (%s)", title(r.name or r.baseSpecies:gsub("_", " ")), title(label))
end
local F = {
  "# Alternate forms",
  "",
  "WoobleDex adds " .. #forms .. " alternate forms. Each is a Pokémon of its own with its own",
  "stats, typing, ability and moves, and shows its base Pokémon's Pokédex number. Seeing or catching a",
  "form also counts the base Pokémon in your Pokédex.",
  "",
  "*Generated from `data/species/forms.lua` by `tools/build_docs.lua`.*",
  "",
  "## How to read the entries",
  "",
  "- **Where do they come from?** A spawn mod puts the ones that are wild in the real games in the wild",
  "  ([WoobleSpawns](https://github.com/poooooby/g1r_modern_spawns) does), and many evolve from another form:",
  "  see each form's *Evolves* line and the [evolution and forms guide](../evolutions-and-forms.md). Any form",
  "  can also be made with the save editor.",
  "- Ability, typing and moves follow the same rules as the other Pokémon (see the [index](../pokemon.md)).",
  "- Left out: Mega Evolutions, Gigantamax forms, forms that only exist during a battle, cosmetic forms and",
  "  gender differences (those use the same Pokémon with a different picture).",
  "",
}
local group = {}
for _, r in ipairs(forms) do
  local key = r.baseSpecies
  if not group[key] then group[key] = {}; group[#group + 1] = key end
  table.insert(group[key], r)
end
for _, base in ipairs(group) do
  for _, r in ipairs(group[base]) do
    F[#F + 1] = string.format("### %s — #%d", formName(r), r.baseDex)
    F[#F + 1] = ""
    F[#F + 1] = "- Type: " .. typesText(r)
    F[#F + 1] = "- Ability: " .. abilityText(r)
    F[#F + 1] = "- Learnset: " .. learnsetText(r)
    local evo = evolvesText(r)
    if evo then F[#F + 1] = "- Evolves: " .. evo end
    F[#F + 1] = ""
  end
end
out("docs/pokemon/forms.md", F)

-- ---- fairy.md: every Fairy-type Pokemon (data/types.lua is the typing the game uses)

-- GitHub's heading anchor: lower case, punctuation dropped, spaces to hyphens
local function anchor(text)
  local a = text:gsub("\226\128\148", ""):lower()
  return (a:gsub("[^%w%- \128-\255]", ""):gsub(" ", "-"))
end
local function hasFairy(list)
  for _, ty in ipairs(list or {}) do if ty == "FAIRY" then return true end end
  return false
end
local recordByDex = {}
for _, r in ipairs(species) do recordByDex[r.dex] = r end
local FY = {
  "# Fairy-type Pokémon",
  "",
  "Every Pokémon that is part Fairy in this mod, with its typing as the game uses it. Fairy beats",
  "Dragon, Dark and Fighting; Fire, Poison and Steel resist it; Dragon moves can't touch it, and",
  "Poison and Steel moves hit it hard. [Back to the index](pokemon.md).",
  "",
  "*Generated from `data/types.lua` by `tools/build_docs.lua`.*",
  "",
  "## Pokémon",
  "",
  "| # | Pokémon | Type | |",
  "|---|---|---|---|",
}
local dexes, originals = {}, 0
for dex, list in pairs(fairy.species or {}) do if hasFairy(list) then dexes[#dexes + 1] = dex end end
table.sort(dexes)
for _, dex in ipairs(dexes) do
  local r = recordByDex[dex]
  local name = byDex[dex] or ("#" .. dex)
  local typed = typesText(r or { dex = dex })
  local where
  if r then
    local g = GEN[r.generation] or 0
    where = string.format("[Generation %d](pokemon/gen%d.md#%s)", g, g, anchor(string.format("#%d %s", dex, title(r.name))))
  else
    originals = originals + 1
    where = "Gen 1–3 original"
  end
  FY[#FY + 1] = string.format("| %d | %s | %s | %s |", dex, name, typed, where)
end
local fairyForms = {}
for _, f in ipairs(forms) do
  if hasFairy(fairy.forms and fairy.forms[f.id]) then fairyForms[#fairyForms + 1] = f end
end
table.sort(fairyForms, function(a, b)
  if a.baseDex ~= b.baseDex then return a.baseDex < b.baseDex end
  return a.slot < b.slot
end)
if #fairyForms > 0 then
  FY[#FY + 1] = ""
  FY[#FY + 1] = "## Forms"
  FY[#FY + 1] = ""
  FY[#FY + 1] = "| # | Form | Type |"
  FY[#FY + 1] = "|---|---|---|"
  for _, f in ipairs(fairyForms) do
    local heading = string.format("%s — #%d", formName(f), f.baseDex)
    FY[#FY + 1] = string.format("| %d | [%s](pokemon/forms.md#%s) | %s |", f.baseDex, formName(f), anchor(heading), typesText(f))
  end
end
FY[#FY + 1] = ""
FY[#FY + 1] = string.format("%d Pokémon (%d of them originals from #1–386) and %d forms.", #dexes, originals, #fairyForms)
out("docs/fairy.md", FY)

-- ---- moves

local physical = { NORMAL = true, FIGHTING = true, FLYING = true, POISON = true, GROUND = true,
                   ROCK = true, BUG = true, GHOST = true, STEEL = true }
local M = {
  "# Added Moves",
  "",
  "The " .. #newMoves .. " moves from later generations that work in battle here. Pokémon learn them by",
  "level-up or as egg moves. The few left (moves that need a partner to act out of turn, such as",
  "After You and Instruct) are swapped for the closest Gen 3 move. As in Gen 3, a move's type",
  "decides whether it is physical or special.",
  "",
  "| Move | Type | Kind | Power | Accuracy | PP | What it does |",
  "|---|---|---|---|---|---|---|",
}
local sortedMoves = {}
for _, m in ipairs(newMoves) do sortedMoves[#sortedMoves + 1] = m end
table.sort(sortedMoves, function(a, b) return (a.full or a.name) < (b.full or b.name) end)
for _, m in ipairs(sortedMoves) do
  local kind = m.power == 0 and "Status" or (physical[m.type] and "Physical" or "Special")
  local text = (m.rse or m.frlg or ""):gsub("%c", " ")
  M[#M + 1] = string.format("| %s | %s | %s | %s | %s | %d | %s |", m.full or title(m.name), title(m.type), kind,
    m.power > 1 and tostring(m.power) or "—", m.accuracy > 0 and tostring(m.accuracy) or "—", m.pp, text)
end
out("docs/moves.md", M)

-- ---- abilities

local A = {
  "# Added Abilities",
  "",
  "Abilities from later generations that work in battle here. Every other newer ability is the",
  "closest Gen 3 ability (see each Pokémon's page). The summary screen has room for one short line,",
  "so **What it does** below is the full effect, with every number and anything that works",
  "differently from the newer games. Gen 3 decides physical or special by a move's type.",
  "",
  "| Ability | Summary screen | What it does |",
  "|---|---|---|",
}
local sortedAbilities = {}
for _, d in ipairs(realAbilities.defs or {}) do sortedAbilities[#sortedAbilities + 1] = d end
table.sort(sortedAbilities, function(a, b) return a.name < b.name end)
for _, d in ipairs(sortedAbilities) do
  A[#A + 1] = string.format("| %s | %s | %s |", title((d.slug:gsub("-", " "))), d.text, d.detail or d.text)
end
out("docs/abilities.md", A)

-- ---- tms

local tms = load("data/tms.lua")
local moveById = {}
for _, m in ipairs(newMoves) do moveById[m.id] = m end
local TM = {
  "# Added TMs",
  "",
  "TMs for the newer moves, numbered after Gen 3's 50: every move that is a TM in Scarlet / Violet",
  "or Sword / Shield and works in battle here. They go in the TM Case (made bigger to hold them",
  "all), are used up when taught like Gen 3's TMs, and a Pokémon can learn one if it learns that",
  "move by TM in any of the main games.",
  "",
  "*Generated from `data/tms.lua`, `data/shops.lua` and `data/vending.lua` by `tools/build_docs.lua`.*",
  "",
  "| TM | Move | Type | Price | FireRed / LeafGreen | Ruby / Sapphire / Emerald | Pokémon |",
  "|---|---|---|---|---|---|---|",
}
for _, t in ipairs(tms) do
  local m = moveById[t.move] or {}
  local s = sold[t.id:lower()] or { frlg = {}, rse = {} }
  TM[#TM + 1] = string.format("| TM%d | %s | %s | ₽%d | %s | %s | %d |", t.number, m.full or title(t.move:gsub("_", " ")),
    title(m.type or "?"), t.price, #s.frlg > 0 and join(s.frlg, "; ") or "not sold",
    #s.rse > 0 and join(s.rse, "; ") or "not sold", #t.dex + #t.forms)
end
out("docs/tms.md", TM)

print(string.format("docs: %d items, %d TMs, %d moves, %d abilities, %d species, %d forms", #items, #tms, #newMoves,
  #(realAbilities.defs or {}), #species, #forms))
