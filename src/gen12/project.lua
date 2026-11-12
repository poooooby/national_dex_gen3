-- data/gen12 species and form records -> the engine's Gen 1 / Gen 2 species records.
--
-- Pure: no registry, no game. src/gen12/species.lua hands in what the running game supplies.
--   ctx = {
--     generation = 1 | 2,
--     types      = src/gen12/types.lua,
--     resolve, direct = Moves.resolver(...): National move number -> a move this game has
--     machines   = { [moveId] = true }: the moves this game teaches by TM/HM (or tutor)
--     pictures   = { front = path, back = path }: the placeholder pictures
--     dexText    = function(id) -> the Gen 1 text label of that species' entry (Gen 1 only)
--     cartIdOf   = { [dex] = id } for the cart's own species (a form's base keeps that spelling)
--   }
--
-- Gen 1 (Red/Blue/Yellow): one Special (the Special Attack; it matches Red's own 149 most
-- often), level1Moves + learnset, ft/in and tenths of a pound, the entry text as a label.
-- Gen 2 (Gold/Silver/Crystal): split specials, levelMoves, a single type written twice, two egg
-- groups, egg cycles as eggSteps, the entry text inline (<NEXT> between lines), an index of its
-- own (1000 + dex, forms 1000 + slot: past every cart index and never 255).
-- Both: the Gen 3 slot, legendary / mythical, the form fields (baseSpecies, form, baseDex), and
-- top-level spAttack / spDefense (modern_spawns reads them on Gen 1). A form gets the made-up
-- dex number FORM_DEX + its place in data/gen12/forms.lua: Gen 1's Pokedex lists species with
-- pairs, so a form sharing its base's number would randomly stand in for it.
-- Evolutions are left empty here; src/gen12/evolutions.lua fills them.

local Project = {}

Project.FORM_DEX = 20000
Project.GEN2_INDEX = 1000
Project.PIC_SIZE = 7

local M_PER_INCH = 0.0254
local KG_PER_LB = 0.45359237

-- metres -> feet, inches (rounded to the inch)
function Project.feetInches(m)
  local inches = math.floor(m / M_PER_INCH + 0.5)
  return math.floor(inches / 12), inches % 12
end

-- kilograms -> tenths of a pound
function Project.tenthsOfPound(kg)
  return math.floor(kg / KG_PER_LB * 10 + 0.5)
end

-- The level-up list as move ids: each National number resolved, a stand-in never one the
-- species learns for real anywhere in its list, and each move once (its first level). The first
-- move is always learned at level 1 (Crabrawler's comes at 5): a Pokemon with no move at all
-- cannot battle. Returns { { level, id }, ... } in level order.
function Project.levelMoves(rows, ctx)
  local taken = {}
  for _, row in ipairs(rows) do
    local id = ctx.direct(row[2])
    if id then taken[id] = true end
  end
  local out, seen = {}, {}
  for _, row in ipairs(rows) do
    local id = ctx.direct(row[2]) or ctx.resolve(row[2], taken)
    if id and not seen[id] then
      seen[id] = true
      taken[id] = true
      out[#out + 1] = { row[1], id }
    end
  end
  if out[1] and out[1][1] > 1 then out[1][1] = 1 end
  return out
end

-- National numbers -> ids, only the moves the game has outright (no stand-ins: as on Gen 3,
-- machine and egg moves are never substituted), each once, optionally filtered
local function direct(list, ctx, keep)
  local out, seen = {}, {}
  for _, n in ipairs(list or {}) do
    local id = ctx.direct(n)
    if id and not seen[id] and (keep == nil or keep[id]) then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  return out
end

local function common(r, ctx, dex)
  local rec = {
    id = r.id, name = r.name, dex = dex,
    types = ctx.types.forCart(r.types, ctx.generation),
    catchRate = r.catchRate, baseExp = r.baseExp,
    growthRate = ctx.types.growthId(r.growthRate, ctx.generation),
    evolutions = {},
    spriteFront = ctx.pictures.front, spriteBack = ctx.pictures.back,
    -- extra fields (the top level of a record keeps them): the stable key, and what other
    -- mods read
    slot = r.slot, legendary = r.legendary or nil, mythical = r.mythical or nil,
    spAttack = r.baseStats.specialAttack, spDefense = r.baseStats.specialDefense,
  }
  if r.baseSpecies then
    -- the running game's own id for the base (Gold spells Farfetch'd FARFETCH_D)
    rec.baseSpecies = ctx.cartIdOf and ctx.cartIdOf[r.baseDex] or r.baseSpecies
    rec.form, rec.baseDex = r.form, r.baseDex
  end
  return rec
end

local function gen1(r, ctx, dex)
  local rec = common(r, ctx, dex)
  local s = r.baseStats
  rec.baseStats = { hp = s.hp, attack = s.attack, defense = s.defense, speed = s.speed,
    special = s.specialAttack }
  rec.frontSize = Project.PIC_SIZE
  -- level 1: the last four (what the game would keep), then everything after
  local first, learnset = {}, {}
  for _, row in ipairs(Project.levelMoves(r.learnset, ctx)) do
    if row[1] <= 1 then
      first[#first + 1] = row[2]
      if #first > 4 then table.remove(first, 1) end
    else
      learnset[#learnset + 1] = { level = row[1], move = row[2] }
    end
  end
  rec.level1Moves, rec.learnset = first, learnset
  rec.tmhm = direct(r.teach, ctx, ctx.machines)
  local d = r.dexEntry
  if d then
    local m, kg = d.height / 10, d.weight / 10
    local ft, inch = Project.feetInches(m)
    rec.dexEntry = { kind = d.kind, heightFt = ft, heightIn = inch,
      weight = Project.tenthsOfPound(kg), heightM = m, weightKg = kg,
      text = ctx.dexText(r.id) }
  end
  return rec
end

local function gen2(r, ctx, dex, index)
  local rec = common(r, ctx, dex)
  local s = r.baseStats
  rec.baseStats = { hp = s.hp, attack = s.attack, defense = s.defense, speed = s.speed,
    specialAttack = s.specialAttack, specialDefense = s.specialDefense }
  rec.picSize = Project.PIC_SIZE
  rec.index = index
  local levelMoves = {}
  for _, row in ipairs(Project.levelMoves(r.learnset, ctx)) do
    levelMoves[#levelMoves + 1] = { level = row[1], move = row[2] }
  end
  rec.levelMoves = levelMoves
  rec.tmhm = direct(r.teach, ctx, ctx.machines)
  rec.eggMoves = direct(r.eggMoves, ctx)
  local groups = r.eggGroups or {}
  rec.eggGroups = { groups[1] or "EGG_NONE", groups[2] or groups[1] or "EGG_NONE" }
  rec.eggSteps = r.eggCycles
  rec.genderRatio = r.genderRatio
  local d = r.dexEntry
  if d then
    local m, kg = d.height / 10, d.weight / 10
    local ft, inch = Project.feetInches(m)
    rec.dexEntry = { kind = d.kind, text = (d.text[1] or ""):gsub("\n", "<NEXT>"),
      text2 = d.text[2] and d.text[2]:gsub("\n", "<NEXT>") or nil,
      height = ft * 100 + inch, weight = Project.tenthsOfPound(kg), heightM = m, weightKg = kg }
  end
  return rec
end

-- A species record (#152-1025)
function Project.species(r, ctx)
  if ctx.generation == 1 then return gen1(r, ctx, r.dex) end
  return gen2(r, ctx, r.dex, Project.GEN2_INDEX + r.dex)
end

-- A form record; n is its place in data/gen12/forms.lua
function Project.form(r, n, ctx)
  local dex = Project.FORM_DEX + n
  if ctx.generation == 1 then return gen1(r, ctx, dex) end
  return gen2(r, ctx, dex, Project.GEN2_INDEX + r.slot)
end

-- The Gen 1 entry text: pages of newline-joined lines, \f between pages, and {DONE} so the
-- Pokedex adds no period of its own (the text has its own; src/ui/DexEntryMenu.lua)
function Project.gen1DexText(r)
  local d = r.dexEntry
  if not d then return nil end
  return table.concat(d.text, "\f") .. "{DONE}"
end

return Project
