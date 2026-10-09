-- Builds the player reference in docs/ from the mod's own data, so it cannot
-- drift from what the game does:
--   docs/items.md            the added items: price, where to buy, what evolves with them
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
  s = tostring(s):lower()
  return (s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

-- ---- data

local items = load("data/items.lua")
local shops = load("data/shops.lua")
local crossgen = load("data/species/crossgen.lua")
local forms = load("data/species/forms.lua")
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
local METHOD = { EVO_ITEM = "use it on", EVO_TRADE_ITEM = "trade holding it" }
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

local function join(list, sep) return table.concat(list, sep) end

local L = {
  "# Added items",
  "",
  "National Dex Gen 3 adds " .. #items .. " evolution items that no Gen 3 game has, so the Pokémon that",
  "need them can evolve. The real games sell almost none of these, so where each one is sold is a",
  "design choice: by item type, and by how far into the game the store is.",
  "",
  "*Generated from `data/items.lua` and `data/shops.lua` by `tools/build_docs.lua`.*",
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
        for _, it in ipairs(items) do
          if it.slug == slug then names[#names + 1] = string.format("%s (₽%d)", it.name, it.price) end
        end
      end
      L[#L + 1] = "- **" .. rule.store .. "**: " .. join(names, ", ")
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

local function abilityText(r)
  local names, seen = {}, {}
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
  local t = {}
  for _, ty in ipairs(r.types or {}) do t[#t + 1] = title(ty) end
  return join(t, " / ")
end

os.execute("mkdir docs\\pokemon 2> nul")
local I = {
  "# Added Pokémon",
  "",
  "National Dex Gen 3 adds " .. #species .. " species, National Dex #387–1025 (Generations 4–9), to",
  "FireRed, LeafGreen, Ruby, Sapphire and Emerald. Each entry lists the Gen 3 typing, the ability it",
  "has in this game, and its level-up learnset (`level move`).",
  "",
  "*Generated from `data/species/` by `tools/build_docs.lua`.*",
  "",
  "## How to read the entries",
  "",
  "- **Ability.** Gen 3 can't take new abilities, so each newer ability is mapped to the closest one",
  "  Gen 3 has (for example Simple becomes Own Tempo, Moxie becomes Guts). A Pokémon shows and acts",
  "  like the Gen 3 ability listed here, not its real one. A second name is its second ability slot.",
  "- **Typing.** Gen 3 has no Fairy type: a Fairy half is dropped, and a pure Fairy is Normal. Togekiss",
  "  and its relatives keep their Gen 5 typing (Normal / Flying).",
  "- **Learnset.** The list keeps the same length as in the modern games. Gen 3 has only its own 354",
  "  moves, so a newer move is replaced, at the same level, by the closest Gen 3 move (same type where",
  "  possible, then similar power and effect). Some moves therefore differ from the real games.",
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
I[#I + 1] = "- [Forms](pokemon/forms.md): Galarian and Hisuian forms, Wormadam's cloaks, the Rotom appliances,"
I[#I + 1] = "  the Therian and Origin forms and more, each a Pokémon of its own."
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
local function formName(r)
  local label = tostring(r.form):gsub("_", " ")
  return string.format("%s (%s)", title(r.baseSpecies:gsub("_", " ")), title(label))
end
local F = {
  "# Alternate forms",
  "",
  "National Dex Gen 3 adds " .. #forms .. " alternate forms. Each is a Pokémon of its own with its own",
  "stats, typing, ability and moves, and shows its base Pokémon's Pokédex number. Seeing or catching a",
  "form also counts the base Pokémon in your Pokédex.",
  "",
  "*Generated from `data/species/forms.lua` by `tools/build_docs.lua`.*",
  "",
  "## How to read the entries",
  "",
  "- **Where do they come from?** Nothing places them in the wild yet, and Gen 3 can't change a Pokémon's",
  "  form (no Gracidea, Reveal Glass, Griseous Orb or Rotom Catalog). They can be added with a save editor,",
  "  and a few evolve into each other (Galarian Darumaka → Galarian Darmanitan with an Ice Stone,",
  "  Hisuian Zorua → Hisuian Zoroark at level 30, Pumpkaboo → Gourgeist of the same size by trade).",
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
    F[#F + 1] = ""
  end
end
out("docs/pokemon/forms.md", F)

print(string.format("docs: %d items, %d species, %d forms", #items, #species, #forms))
