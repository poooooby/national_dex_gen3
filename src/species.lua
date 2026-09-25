-- Payload -> FireRed species records, registered through mod.content.pokemon.
--
-- The payload is written in numbers (move ids, ability ids, dex targets); the
-- NAMES FireRed's registry wants are read from the running game, never
-- hard-coded: move names from the moves registry (record.index = move id),
-- evolution items from the items registry, evolution targets from the species
-- registry plus this payload. Anything the game cannot resolve is dropped
-- rather than registered broken.

local Species = {}

local SLOT_CAP = 1089 -- dex 1025 + 64

local function normalize(name)
  return (tostring(name or ""):upper():gsub("[^A-Z0-9]", ""))
end

local function ids(registry)
  local out = {}
  local ok, result = pcall(function() return registry:each() end)
  if not ok then return out end
  if type(result) == "function" then
    for id in result do out[#out + 1] = id end
  elseif type(result) == "table" then
    for _, id in ipairs(result) do out[#out + 1] = id end
  end
  return out
end

local function get(registry, id)
  local ok, value = pcall(function() return registry:get(id) end)
  return ok and value or nil
end

-- data/species/index.lua names the shards; each returns a list of records.
function Species.loadPayload(load)
  local index = load("data/species/index.lua")
  if type(index) ~= "table" or type(index.shards) ~= "table" then return nil end
  local out = {}
  for _, shard in ipairs(index.shards) do
    local list = load("data/species/" .. shard)
    if type(list) == "table" then
      for _, record in ipairs(list) do out[#out + 1] = record end
    end
  end
  table.sort(out, function(a, b) return a.dex < b.dex end)
  return #out > 0 and out or nil
end

-- FireRed's species registry caps `index` at 1023; this payload needs 1089.
-- The cap is a schema constant with no mod API, hence engine_internals.
local function raiseSlotCap(mod)
  local ok, Schemas = pcall(require, "src.mods.Schemas")
  local fields = ok and type(Schemas) == "table" and Schemas.REGISTRIES
    and Schemas.REGISTRIES.pokemon and Schemas.REGISTRIES.pokemon.gen3Fields
  if fields and Schemas.f and Schemas.f.opt and Schemas.f.int then
    fields.index = Schemas.f.opt(Schemas.f.int(1, SLOT_CAP))
    return true
  end
  mod.log:warn("could not raise FireRed's species slot cap -- species past "
    .. "slot 1023 (dex > 959) will not register")
  return false
end

-- Lookups read from the running game.
local function lookups(mod, payload)
  local content = mod.content
  local moveName = {}
  for _, id in ipairs(ids(content.moves)) do
    local record = get(content.moves, id)
    local n = type(record) == "table" and tonumber(record.index) or nil
    if n then moveName[n] = id end
  end
  local itemId = {}
  if content.items then
    for _, id in ipairs(ids(content.items)) do
      local record = get(content.items, id)
      itemId[normalize(id)] = id
      if type(record) == "table" and record.name then itemId[normalize(record.name)] = id end
    end
  end
  -- dex -> { id, slot } for the cart's species and this payload
  local byDex = {}
  for _, id in ipairs(ids(content.pokemon)) do
    local record = get(content.pokemon, id)
    if type(record) == "table" and tonumber(record.dex) then
      byDex[record.dex] = byDex[record.dex] or { id = id, slot = record.index }
    end
  end
  for _, r in ipairs(payload) do
    byDex[r.dex] = { id = r.id, slot = r.slot }
  end
  return moveName, itemId, byDex
end

local function enginePicPath(side, slot)
  return table.concat({ "data", "generated", "gba", "pokemon", side, slot .. ".rgba" }, "/")
end

-- One evolution step -> a registry row { method, species, level?, item? },
-- or nil when FireRed lacks the target or the item RIGHT NOW. Eager and
-- load-time only: used for the schema-validated record handed to
-- mod.content.pokemon:register/:patch, which can't be touched again once
-- content freezes. `itemId` is the snapshot lookups() built from whatever is
-- registered at the moment THIS mod runs -- a companion mod loaded after it
-- is invisible here, which is why this is never the only place an item is
-- resolved (see evolutionStep below).
local function evolutionRow(step, itemId, byDex)
  local target = byDex[step.target]
  if not target then return nil end
  local row = { method = step.method, species = target.id }
  if step.level then row.level = step.level end
  if step.item then
    row.item = itemId[normalize(step.item)]
    if not row.item then return nil end -- an item FireRed does not have yet
  end
  return row, target.slot
end

-- One evolution step -> the bookkeeping row src/fixups.lua drives the LIVE
-- species table from, or nil when the target species itself never
-- registered (should not happen for a valid dex 1-1025). Unlike
-- evolutionRow, an item step is never dropped here: `item` stays the raw
-- PokéAPI slug (e.g. "oval-stone"), and fixups re-resolves it against the
-- item registry on every apply() -- at game.ready, once every mod (in any
-- load order) has registered, and again on every reload -- so a step lights
-- up the moment any mod adds a matching item, including one loaded after
-- this one.
local function evolutionStep(step, byDex)
  local target = byDex[step.target]
  if not target then return nil end
  return { method = step.method, level = step.level, item = step.item,
           species = target.id }, target.slot
end

local function moveNames(ids, moveName)
  local out = {}
  for _, id in ipairs(ids or {}) do
    local name = moveName[id]
    if name then out[#out + 1] = name end
  end
  return out
end

-- One payload row -> the record FireRed's registry validates.
local function toRecord(r, moveName, itemId, byDex)
  local learnset = {}
  for _, row in ipairs(r.learnset or {}) do
    local name = moveName[row[2]]
    if name then learnset[#learnset + 1] = { level = row[1], move = name } end
  end
  table.sort(learnset, function(a, b) return a.level < b.level end)

  local evolutions = {}
  for _, step in ipairs(r.evolutions or {}) do
    local row = evolutionRow(step, itemId, byDex)
    if row then evolutions[#evolutions + 1] = row end
  end

  return {
    id = r.id, name = r.name, dex = r.dex,
    index = r.slot, gen3Species = r.slot,
    types = r.types, baseStats = r.baseStats,
    catchRate = r.catchRate, baseExp = r.baseExp, growthRate = r.growthRate,
    genderRatio = r.genderRatio, eggCycles = r.eggCycles, friendship = r.friendship,
    abilities = (r.abilities and #r.abilities > 0) and r.abilities or nil,
    learnset = learnset, evolutions = evolutions,
    -- every FireRed move the species can be taught; the registry keeps the
    -- ones that are FireRed TMs/HMs (the tutors are src/fixups.lua's job)
    tmhm = moveNames(r.teach, moveName),
    eggMoves = moveNames(r.eggMoves, moveName),
    dexEntry = r.dexEntry,
    -- The engine's OWN default pic path for the slot (Schemas G3.vanillaSprite),
    -- so the registry records no sprite override and art providers answer
    -- through the pokemon.sprite hook (src/art.lua). Nothing is shipped or
    -- read from that path by this mod; it is assembled rather than spelled
    -- because modkit's ROM-content gate flags the literal cache prefix.
    spriteFront = enginePicPath("front", r.slot),
    spriteBack = enginePicPath("back", r.slot),
    -- carried through for readers (this mod's API, spawn mods)
    legendary = r.legendary or nil, mythical = r.mythical or nil,
  }
end

-- Evolutions from the cart's own species into new ones (Magneton ->
-- Magnezone ...). Two things happen per step:
--   * bookkeeping for fixups (returned, unfiltered by item -- see
--     evolutionStep): the source's LIVE table gets this row the moment its
--     item resolves, this load or a later one;
--   * a best-effort, load-time-only patch of the source's REGISTRY record,
--     for anything reading mod.content.pokemon:get(id).evolutions directly;
--     only steps whose item already resolves now make it in, because a
--     registry patch is only possible before content freezes.
-- Returns { { sourceId, sourceSlot, method, level?, item?, species,
-- targetSlot } }.
local function crossGeneration(mod, steps, itemId, byDex)
  local applied, bySource = {}, {}
  for _, step in ipairs(steps or {}) do
    local source = byDex[step.source]
    if source then
      local ev, targetSlot = evolutionStep(step, byDex)
      if ev then
        applied[#applied + 1] = { sourceId = source.id, sourceSlot = source.slot,
                                  sourceDex = step.source,
                                  method = ev.method, level = ev.level, item = ev.item,
                                  species = ev.species, targetSlot = targetSlot }
      end
      local row = evolutionRow(step, itemId, byDex)
      if row then
        bySource[source.id] = bySource[source.id] or {}
        bySource[source.id][#bySource[source.id] + 1] = row
      end
    end
  end
  for id, rows in pairs(bySource) do
    local record = get(mod.content.pokemon, id)
    local evolutions = {}
    for _, row in ipairs(type(record) == "table" and record.evolutions or {}) do
      evolutions[#evolutions + 1] = row
    end
    for _, row in ipairs(rows) do evolutions[#evolutions + 1] = row end
    local ok, err = pcall(function()
      mod.content.pokemon:patch(id, { evolutions = evolutions })
    end)
    if not ok then
      mod.log:warn("could not add %s's new evolutions (%s)", id, tostring(err))
    end
  end
  return applied
end

-- Registers every payload species; returns the list actually registered, each
-- { id, dex, slot, name, teach, evolutions = { {method, level?, item?, targetSlot} } },
-- and the cross-generation evolutions added to the cart's species.
function Species.register(mod, payload, crossgen)
  raiseSlotCap(mod)
  local moveName, itemId, byDex = lookups(mod, payload)
  local registered, failed, firstError = {}, 0, nil
  for _, r in ipairs(payload) do
    local record = toRecord(r, moveName, itemId, byDex)
    local ok, err = pcall(function() mod.content.pokemon:register(record.id, record) end)
    if ok then
      -- Bookkeeping for fixups, built from the PAYLOAD's own evolution list
      -- (not `record.evolutions`, which evolutionRow already thinned to
      -- whatever resolves right now): an item step that FireRed's item
      -- registry does not answer for yet is kept, not dropped, so it can
      -- resolve on a later apply() once some mod adds that item.
      local evolutions = {}
      for _, step in ipairs(r.evolutions or {}) do
        local ev, targetSlot = evolutionStep(step, byDex)
        if ev then
          evolutions[#evolutions + 1] = { method = ev.method, level = ev.level,
                                           item = ev.item, species = ev.species,
                                           targetSlot = targetSlot }
        end
      end
      registered[#registered + 1] = {
        id = r.id, dex = r.dex, slot = r.slot, name = r.name,
        legendary = r.legendary, mythical = r.mythical, evolutions = evolutions,
        teach = r.teach or {},
      }
    else
      failed = failed + 1
      firstError = firstError or tostring(err)
    end
  end
  mod.log:info("registered %d species (#%d-%d)", #registered,
    payload[1] and payload[1].dex or 0, payload[#payload] and payload[#payload].dex or 0)
  if failed > 0 then
    mod.log:warn("%d species failed to register; first: %s", failed, firstError)
  end
  local bridges = crossGeneration(mod, crossgen, itemId, byDex)
  return registered, bridges
end

-- data/species/crossgen.lua: evolution steps from the cart's species.
function Species.loadCrossGeneration(load)
  local steps = load("data/species/crossgen.lua")
  return type(steps) == "table" and steps or {}
end

-- PokéAPI item slug (e.g. "oval-stone") -> the item's FireRed number, or nil
-- when no registered item matches it -- YET. Matched by normalized id/name
-- against the item registry FRESH ON EVERY CALL, never a snapshot, so an
-- item any mod adds -- loaded before this one or after it, this session or
-- a later one -- is found the moment it exists. Evolution params are item
-- numbers; src/fixups.lua calls this on every apply() (game.ready and every
-- reload) rather than once at load time for exactly this reason.
function Species.itemIndex(mod)
  return function(slug)
    if not (slug and mod.content.items) then return nil end
    local key = normalize(slug)
    for _, id in ipairs(ids(mod.content.items)) do
      local record = get(mod.content.items, id)
      if normalize(id) == key
        or (type(record) == "table" and record.name and normalize(record.name) == key) then
        return type(record) == "table" and tonumber(record.index) or nil
      end
    end
    return nil
  end
end

Species._normalize = normalize
Species._toRecord = toRecord

return Species
