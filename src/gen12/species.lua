-- Species and forms on Gen 1 / Gen 2, registered at load.
--
-- Every data/gen12 species past the cart's own (Red #152+, Gold #252+) and all 128 forms are
-- registered as the engine's own records (src/gen12/project.lua shapes them). On Red each entry's
-- text is a `text` record of its own (Red's Pokedex reads the entry by label). A species id the
-- registry already has (another mod's) is left to that mod. Gold's records ask for their own
-- index; if another mod holds it, the engine picks one.
--
-- Returns the state the later stages and the API read: byId / byDex / bySlot (data record +
-- the id as registered), forms in order, and counts.

local Species = {}

Species.TEXT_PREFIX = "_national_dex_gen3_"

-- the union of the cart species' own TM/HM lists: Gold keeps its machine list outside any
-- registry, and on Crystal this takes in the three tutor moves too
local function machineMoves(pokemon)
  local out = {}
  for _, rec in pokemon:each() do
    if type(rec) == "table" and type(rec.tmhm) == "table" then
      for _, move in ipairs(rec.tmhm) do out[move] = true end
    end
  end
  return out
end

-- opts: { mod, generation, project, types, resolve, direct, species = { records }, forms,
--         pictures = { front, back }, log }
function Species.register(opts)
  local mod, gen, Project, log = opts.mod, opts.generation, opts.project, opts.log
  local pokemon, text = mod.content.pokemon, mod.content.text
  local maxDex = gen == 1 and 151 or 251
  local state = { generation = gen, byId = {}, byDex = {}, bySlot = {}, forms = {},
    registered = 0, kept = 0, failed = 0 }
  local cartIdOf = {}
  for id, rec in pokemon:each() do
    if type(rec) == "table" and type(rec.dex) == "number" and rec.dex <= maxDex then
      cartIdOf[rec.dex] = id
    end
  end
  state.cartIdOf = cartIdOf
  local ctx = {
    generation = gen, types = opts.types, resolve = opts.resolve, direct = opts.direct,
    machines = machineMoves(pokemon), pictures = opts.pictures, cartIdOf = cartIdOf,
    dexText = function(id) return Species.TEXT_PREFIX .. id end,
  }

  local firstError
  local function add(r, rec)
    if pokemon:get(r.id) ~= nil then
      state.kept = state.kept + 1          -- another mod's species of this id
      return false
    end
    if gen == 1 and rec.dexEntry then
      local okT = pcall(text.register, text, rec.dexEntry.text, Project.gen1DexText(r))
      if not okT then rec.dexEntry.text = nil end
    end
    local ok, err = pcall(pokemon.register, pokemon, r.id, rec)
    if not ok and gen == 2 and rec.index then
      rec.index = nil                      -- the index is taken: let the engine pick one
      ok, err = pcall(pokemon.register, pokemon, r.id, rec)
    end
    if not ok then
      state.failed = state.failed + 1
      firstError = firstError or (r.id .. ": " .. tostring(err))
      return false
    end
    state.registered = state.registered + 1
    local entry = { data = r, id = r.id, dex = rec.dex, base = rec.baseSpecies }
    state.byId[r.id], state.bySlot[r.slot] = entry, entry
    return entry
  end

  for _, r in ipairs(opts.species) do
    if r.dex > maxDex then
      local entry = add(r, Project.species(r, ctx))
      if entry then state.byDex[r.dex] = entry end
    end
  end
  for n, r in ipairs(opts.forms) do
    local entry = add(r, Project.form(r, n, ctx))
    if entry then state.forms[#state.forms + 1] = entry end
  end
  if firstError and log then
    log:warn("%d species could not be registered (first: %s)", state.failed, firstError)
  end
  return state
end

return Species
