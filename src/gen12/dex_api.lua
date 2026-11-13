-- The read API a battle or stats mod expects on Gen 1 / Gen 2 (apiVersion 9): the calls the
-- g9 battle mods and battle_forms make on a National Dex provider, answered from this mod's own
-- registered records and the reference data in data/gen12/api/ (tools/build_api.py: PokéAPI and
-- Pokémon Showdown). Installed over src/gen12/api.lua's exports, which keep every call they had.
--
--   statsBySpecies(id) / statsByDex(n)   the registered record, deep-copied, plus a normalised
--       view: types, stats { hp, attack, defense, speed, special (Red), spAttack, spDefense },
--       hasSplit, total, baseDex, abilities { { name, slot, hidden } }, evYield, movesFull
--       { { level, move, name, slug } }, movesByMethod { machine, tutor, egg, other }, eggGroups,
--       baseHappiness, genderRate, growthRateName, forms (a base's own form records)
--   listSpecies()            every base species #1-1025 here: { dex, id, slot, name, legendary,
--                            mythical, forms = count, formIds }
--   formsOf(idOrDex)         the base's form records (statsBySpecies shape, plus slot)
--   splitStats(id), hasSplitStats(id)
--   moveById(id)             PokéAPI's facts for a move, by the id this game registers it under,
--                            its separator-free spelling (AQUAJET) or number: id, num, name,
--                            strippedId, slug, type (this game's type id), power, accuracy (0 =
--                            never misses), pp, priority, damageClass, target, category, drain,
--                            healing, ailment, ailmentChance, flinchChance, statChance,
--                            statChanges, critRate, minHits, maxHits, shortEffect, effect, meta
--                            (PokéAPI's shape), engineMove, registered, effectModeled,
--                            gen1EffectModeled, gen2EffectModeled
--   listMoves()              the ids of the moves this game has that moveById knows
--   moveFlags(id)            Showdown's flags as a set ({ contact = true, punch = true, ... })
--   abilityById(id)          name, generation, effect text, effectChanges, behaviour,
--                            expressible, notes; by id (VITALSPIRIT) or display name
--   listAbilities()
--   itemById(id)             name, category, attributes, flingPower, flingEffect, cost, effect
--                            text; an exact miss is retried with HELD on the end
--   listItems()
--   itemFlags(id)            Showdown's facts (fling, naturalGift, isBerry, onPlate, itemUser...)
--   evolutionsOf(idOrDex)    { id, dex, chainId, chain, stage, evolvesFrom = { id, dex, name,
--                            text, methods }, evolvesInto = { ... } }; methods carry PokéAPI's
--                            trigger ("level-up", "use-item", "trade") and conditions, and the
--                            game's own rows add `method` (the engine's name for it)
--   listEvolutions()
--   patch(kind, id, partial) adds to or replaces fields of a reply (maps merge, lists replace);
--                            species / move fields the registered record has go to the registry
--                            too. Kept for this load only.
--
-- Every reply is a copy; an unknown id answers nil, never an error.

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

-- maps merge key by key, lists replace whole
local function isList(t)
  return type(t) == "table" and (t[1] ~= nil or next(t) == nil)
end
local function merge(into, partial)
  for k, v in pairs(partial) do
    if type(v) == "table" and type(into[k]) == "table" and not isList(v) and not isList(into[k]) then
      merge(into[k], v)
    else
      into[k] = copy(v)
    end
  end
  return into
end

local function strip(s)
  if type(s) ~= "string" then return nil end
  local id = s:upper():gsub("[^%w]", "")
  return id ~= "" and id or nil
end

-- the engine's evolution method names -> PokéAPI's triggers
local TRIGGER = {
  LEVEL = "level-up", ITEM = "use-item", TRADE = "trade", FRIENDSHIP = "level-up",
  EVOLVE_LEVEL = "level-up", EVOLVE_ITEM = "use-item", EVOLVE_TRADE = "trade",
  EVOLVE_HAPPINESS = "level-up", EVOLVE_STAT = "level-up",
}

-- the engine registries patch() hands whole kinds to
local FORWARD = {
  typeChart = "type_chart", moveEffect = "move_effects", status = "statuses",
  encounter = "encounters", trainer = "trainers", growthRate = "growth_rates", text = "text",
  itemEffect = "item_effects", ball = "balls", evolutionMethod = "evolution_methods",
}

-- opts: { load = fn(path) -> table|nil, generation, types (src/gen12/types.lua), species (state),
--         direct = fn(n) -> move id | nil, evolutions (state) }
return function(mod, opts)
  local exports, gen, Types, load = mod.exports, opts.generation, opts.types, opts.load
  local content = mod.content
  local speciesState = opts.species
  local cartMax = gen == 1 and 165 or 251
  local dexMax = gen == 1 and 151 or 251

  local overlay = { species = {}, move = {}, ability = {}, item = {}, moveFlags = {}, evolution = {},
    itemFlags = {} }
  local function withOverlay(kind, key, rec)
    local o = key and overlay[kind][key]
    if o and rec then merge(rec, o) end
    return rec
  end

  local function getRecord(registry, id)
    if type(id) ~= "string" then return nil end
    local ok, rec = pcall(registry.get, registry, id)
    return ok and type(rec) == "table" and rec or nil
  end

  --------------------------------------------------------------------------- moves
  local moveData
  local function moves()
    if moveData then return moveData end
    moveData = { byN = {}, byStripped = {}, byUnder = {}, idToN = {}, list = {} }
    for _, row in ipairs(load("data/gen12/api/moves.lua") or {}) do
      moveData.byN[row.n] = row
      moveData.byStripped[row.strippedId] = moveData.byStripped[row.strippedId] or row.n
      moveData.byUnder[row.slug:upper():gsub("%-", "_")] = row.n
    end
    for n in pairs(moveData.byN) do
      local id = opts.direct and opts.direct(n)
      if id and not moveData.idToN[id] then
        moveData.idToN[id] = n
        moveData.list[#moveData.list + 1] = id
      end
    end
    table.sort(moveData.list)
    return moveData
  end

  local function moveNumber(id)
    local d = moves()
    if type(id) == "number" then return d.byN[id] and id or nil end
    if type(id) ~= "string" then return nil end
    return d.idToN[id] or d.byUnder[id] or d.byStripped[strip(id) or ""]
  end

  -- whether a move runs as itself on a generation (the cart's own, or a newer move this mod
  -- registers there); the running game answers from what is registered
  local genRows
  local function modeledOn(g, n)
    if g == gen then return opts.direct and opts.direct(n) ~= nil or false end
    if n <= (g == 1 and 165 or 251) then return true end
    if not genRows then
      genRows = {}
      for _, row in ipairs(load("data/gen12/moves.lua") or {}) do genRows[row.n] = row end
    end
    local row = genRows[n]
    return row ~= nil and row["gen" .. g] ~= nil
  end

  local META = { ailment = "ailment", category = "category", drain = "drain", healing = "healing",
    critRate = "crit_rate", ailmentChance = "ailment_chance", flinchChance = "flinch_chance",
    statChance = "stat_chance", minHits = "min_hits", maxHits = "max_hits", minTurns = "min_turns",
    maxTurns = "max_turns" }

  local function moveRecord(n)
    local row = moves().byN[n]
    if not row then return nil end
    local registered = opts.direct and opts.direct(n) or nil
    local live = registered and getRecord(content.moves, registered)
    local rec = {
      id = registered or row.slug:upper():gsub("%-", "_"), num = n, slug = row.slug,
      name = (live and live.name) or row.name:upper(), displayName = row.name,
      strippedId = row.strippedId, type = (live and live.type) or Types.cartId(row.type),
      modernType = row.type, power = row.power, accuracy = row.accuracy or 0, pp = row.pp,
      priority = row.priority or 0, damageClass = row.damageClass, target = row.target,
      generation = row.generation, effectChance = row.effectChance,
      shortEffect = row.shortEffect, effect = row.effect or row.shortEffect,
      statChanges = copy(row.statChanges or {}),
      engineMove = n <= cartMax and registered ~= nil, registered = registered ~= nil,
    }
    -- the other generation is only vouched for when this game runs the move too: a mod on this
    -- game asks about this game, and a reader that falls back from one flag to the other
    -- (`gen2 and a or b`) must not be told a move it cannot use here is modeled
    local here = modeledOn(gen, n)
    rec.effectModeled = here
    rec.gen1EffectModeled = here and modeledOn(1, n)
    rec.gen2EffectModeled = here and modeledOn(2, n)
    local meta = { stat_changes = copy(rec.statChanges) }
    for key, api in pairs(META) do
      if row[key] ~= nil then
        rec[key] = row[key]
        meta[api] = row[key]
      end
    end
    rec.drain, rec.healing, rec.critRate = rec.drain or 0, rec.healing or 0, rec.critRate or 0
    rec.ailmentChance, rec.flinchChance = rec.ailmentChance or 0, rec.flinchChance or 0
    rec.statChance = rec.statChance or 0
    rec.meta = meta
    return withOverlay("move", rec.id, rec)
  end

  exports.moveById = function(id)
    local n = moveNumber(id)
    return n and moveRecord(n) or nil
  end

  exports.listMoves = function()
    return copy(moves().list)
  end

  exports.moveFlags = function(id)
    local n = moveNumber(id)
    local row = n and moves().byN[n]
    if not (row and row.flags) then return nil end
    local out = {}
    for _, f in ipairs(row.flags) do out[f] = true end
    local key = (opts.direct and opts.direct(n)) or row.slug:upper():gsub("%-", "_")
    return withOverlay("moveFlags", key, out)
  end

  --------------------------------------------------------------------------- abilities
  local abilityData
  local function abilities()
    if abilityData then return abilityData end
    abilityData = { byId = {}, list = {} }
    for _, row in ipairs(load("data/gen12/api/abilities.lua") or {}) do
      abilityData.byId[row.id] = row
      abilityData.list[#abilityData.list + 1] = row.id
    end
    table.sort(abilityData.list)
    return abilityData
  end

  exports.abilityById = function(id)
    local key = strip(id)
    local row = key and abilities().byId[key]
    if not row then return nil end
    local rec = copy(row)
    -- a move type in this game's own ids (PSYCHIC_TYPE on Red / Gold), as move records carry
    for _, e in ipairs(rec.behaviour and rec.behaviour.effects or {}) do
      if type(e.moveType) == "string" then e.moveType = Types.cartId(e.moveType) end
    end
    return withOverlay("ability", key, rec)
  end

  exports.listAbilities = function()
    return copy(abilities().list)
  end

  --------------------------------------------------------------------------- items
  local itemData, itemFacts
  local function items()
    if itemData then return itemData end
    itemData = { byId = {}, list = {} }
    for _, row in ipairs(load("data/gen12/api/items.lua") or {}) do
      itemData.byId[row.id] = row
      itemData.list[#itemData.list + 1] = row.id
    end
    table.sort(itemData.list)
    return itemData
  end

  exports.itemById = function(id)
    local key = strip(id)
    if not key then return nil end
    local d = items()
    local row = d.byId[key] or d.byId[key .. "HELD"]
    if not row then return nil end
    return withOverlay("item", row.id, copy(row))
  end

  exports.listItems = function()
    return copy(items().list)
  end

  exports.itemFlags = function(id)
    local key = strip(id)
    if not key then return nil end
    itemFacts = itemFacts or load("data/gen12/api/item_flags.lua") or {}
    local row = itemFacts[key]
    if not row then return nil end
    return withOverlay("itemFlags", key, copy(row))
  end

  --------------------------------------------------------------------------- species
  local shardIndex, shards, formExtra, chains = nil, {}, nil, nil
  local function extraForDex(dex)
    shardIndex = shardIndex or load("data/gen12/api/species/index.lua") or {}
    for _, s in ipairs(shardIndex) do
      if dex >= s.first and dex <= s.last then
        if not shards[s.file] then
          local rows = {}
          for _, r in ipairs(load("data/gen12/api/species/" .. s.file) or {}) do rows[r.dex] = r end
          shards[s.file] = rows
        end
        return shards[s.file][dex]
      end
    end
    return nil
  end
  local function extraForForm(id)
    if not formExtra then
      formExtra = {}
      for _, r in ipairs(load("data/gen12/api/forms.lua") or {}) do formExtra[r.id] = r end
    end
    return formExtra[id]
  end

  -- dex -> the base species' id here (the cart's own or this mod's)
  local function idOfDex(dex)
    if type(dex) ~= "number" then return nil end
    if dex <= dexMax then return speciesState.cartIdOf[dex] end
    local e = speciesState.byDex[dex]
    return e and e.id or nil
  end

  local formsOfBase
  local function formIds(baseId)
    if not formsOfBase then
      formsOfBase = {}
      for _, e in ipairs(speciesState.forms) do
        local rec = getRecord(content.pokemon, e.id)
        local base = (rec and rec.baseSpecies) or e.base
        if base then
          formsOfBase[base] = formsOfBase[base] or {}
          table.insert(formsOfBase[base], e.id)
        end
      end
    end
    return formsOfBase[baseId] or {}
  end

  local function moveEntries(numbers, withLevel)
    local out = {}
    for _, item in ipairs(numbers or {}) do
      local level, n
      if withLevel then level, n = item[1], item[2] else n = item end
      local row = moves().byN[n]
      if row then
        local e = { move = row.strippedId, name = row.name, slug = row.slug, num = n,
          id = opts.direct and opts.direct(n) or nil }
        if withLevel then e.level = level end
        out[#out + 1] = e
      end
    end
    return out
  end

  local EV_KEYS = { "hp", "attack", "defense", "spAttack", "spDefense", "speed" }

  local function speciesRecord(id, nested)
    local live = getRecord(content.pokemon, id)
    if not live then return nil end
    local rec = copy(live)
    rec.id = id
    local isForm = live.baseSpecies ~= nil and live.form ~= nil
    local baseDex = live.baseDex or live.dex
    local extra = isForm and extraForForm(id) or extraForDex(live.dex)
    rec.baseDex = baseDex
    local types, seen = {}, {}
    for _, t in ipairs(live.types or {}) do
      if not seen[t] then types[#types + 1], seen[t] = t, true end
    end
    rec.types = types
    local b = live.baseStats or {}
    local modern = extra and extra.stats or {}
    local stats = { hp = b.hp, attack = b.attack, defense = b.defense, speed = b.speed }
    if gen == 1 then
      stats.special = b.special
      stats.spAttack = live.spAttack or modern.spAttack
      stats.spDefense = live.spDefense or modern.spDefense
    else
      stats.spAttack, stats.spDefense = b.specialAttack, b.specialDefense
    end
    rec.stats, rec.hasSplit = stats, stats.spAttack ~= nil and stats.spDefense ~= nil
    local total = (stats.hp or 0) + (stats.attack or 0) + (stats.defense or 0) + (stats.speed or 0)
    if rec.hasSplit then
      total = total + stats.spAttack + stats.spDefense
    else
      total = total + (stats.special or 0)
    end
    rec.total = total
    if extra then
      rec.abilities = copy(extra.abilities)
      rec.evYield = {}
      for _, k in ipairs(EV_KEYS) do rec.evYield[k] = extra.evYield and extra.evYield[k] or 0 end
      rec.movesFull = moveEntries(extra.movesFull, true)
      rec.movesByMethod = {}
      for _, method in ipairs({ "machine", "tutor", "egg", "other" }) do
        rec.movesByMethod[method] = moveEntries(extra.movesByMethod and extra.movesByMethod[method])
      end
      rec.eggGroupNames = copy(extra.eggGroups)
      rec.baseHappiness = extra.baseHappiness
      rec.genderRate = extra.genderRate
      rec.growthRateName = extra.growthRateName
    else
      rec.abilities, rec.movesFull, rec.movesByMethod = {}, {}, { machine = {}, tutor = {}, egg = {}, other = {} }
      rec.evYield = { hp = 0, attack = 0, defense = 0, spAttack = 0, spDefense = 0, speed = 0 }
    end
    if not isForm and not nested then
      rec.forms = {}
      for _, fid in ipairs(formIds(id)) do
        local f = speciesRecord(fid, true)
        if f then rec.forms[#rec.forms + 1] = f end
      end
    end
    return withOverlay("species", id, rec)
  end

  exports.statsBySpecies = function(id)
    if type(id) ~= "string" then return nil end
    return speciesRecord(id)
  end

  exports.statsByDex = function(dex)
    local id = idOfDex(tonumber(dex))
    return id and speciesRecord(id) or nil
  end

  exports.splitStats = function(id)
    local rec = exports.statsBySpecies(id)
    if not (rec and rec.hasSplit) then return nil end
    return { spAttack = rec.stats.spAttack, spDefense = rec.stats.spDefense }
  end

  exports.hasSplitStats = function(id)
    local rec = exports.statsBySpecies(id)
    return rec ~= nil and rec.hasSplit == true
  end

  exports.listSpecies = function()
    local out = {}
    for dex = 1, 1025 do
      local id = idOfDex(dex)
      local live = id and getRecord(content.pokemon, id)
      if live then
        local fids = formIds(id)
        out[#out + 1] = { dex = dex, id = id, slot = dex + 64, name = live.name,
          legendary = live.legendary or false, mythical = live.mythical or false,
          forms = #fids, formIds = copy(fids) }
      end
    end
    return out
  end

  exports.formsOf = function(idOrDex)
    local id = tonumber(idOrDex) and idOfDex(tonumber(idOrDex)) or idOrDex
    local out = {}
    for _, fid in ipairs(id and formIds(id) or {}) do
      local f = speciesRecord(fid, true)
      if f then out[#out + 1] = f end
    end
    return out
  end

  --------------------------------------------------------------------------- evolutions
  local intoByDex
  local function children(dex)
    if not intoByDex then
      intoByDex = {}
      for d = 1, 1025 do
        local ex = extraForDex(d)
        local from = ex and ex.evolvesFrom
        if from then
          intoByDex[from.dex] = intoByDex[from.dex] or {}
          table.insert(intoByDex[from.dex], { dex = d, methods = from.methods })
        end
      end
    end
    return intoByDex[dex] or {}
  end

  local function nameOf(id)
    local rec = id and getRecord(content.pokemon, id)
    return rec and rec.name or nil
  end

  local function step(id, dex, methods)
    local first = methods[1]
    return { id = id, dex = dex, name = nameOf(id), text = first and first.text or nil,
      methods = copy(methods) }
  end

  -- a game row ({ level, trigger = engine method }) in PokéAPI's words, the method kept
  local function fromGameMethods(methods)
    local out = {}
    for i, m in ipairs(methods or {}) do
      local method = m.trigger
      local t = { method = method, trigger = TRIGGER[method] or "level-up", level = m.level }
      if method == "FRIENDSHIP" or method == "EVOLVE_HAPPINESS" then t.minHappiness = 160 end
      t.text = t.level and ("Level " .. t.level) or (t.trigger == "trade" and "Trade")
        or (t.trigger == "use-item" and "Use an item") or "Level up"
      out[i] = t
    end
    return out
  end

  local legacyEvolutions = exports.evolutionsOf
  local function chainList(chainId)
    chains = chains or load("data/gen12/api/chains.lua") or {}
    return chains[chainId]
  end

  local function evolutionRecord(id)
    local live = getRecord(content.pokemon, id)
    if not live then return nil end
    local isForm = live.baseSpecies ~= nil and live.form ~= nil
    local dex = live.baseDex or live.dex
    local ex = extraForDex(dex)
    local out = { id = id, dex = dex, evolvesInto = {} }
    local seen = {}
    if not isForm and ex then
      out.chainId = ex.chainId
      if ex.evolvesFrom then
        local pid = idOfDex(ex.evolvesFrom.dex)
        if pid then out.evolvesFrom = step(pid, ex.evolvesFrom.dex, ex.evolvesFrom.methods) end
      end
      for _, c in ipairs(children(dex)) do
        local cid = idOfDex(c.dex)
        if cid and not seen[cid] then
          seen[cid] = true
          out.evolvesInto[#out.evolvesInto + 1] = step(cid, c.dex, c.methods)
        end
      end
    elseif ex then
      out.chainId = ex.chainId
    end
    -- the game's own rows: forms, and any step PokéAPI's chain has no species for
    local legacy = legacyEvolutions and legacyEvolutions(id)
    if legacy then
      for _, into in ipairs(legacy.evolvesInto or {}) do
        if into.id and not seen[into.id] then
          seen[into.id] = true
          local rec = getRecord(content.pokemon, into.id)
          out.evolvesInto[#out.evolvesInto + 1] = step(into.id, rec and (rec.baseDex or rec.dex),
            fromGameMethods(into.methods))
        end
      end
      if not out.evolvesFrom and legacy.evolvesFrom and legacy.evolvesFrom.id then
        local rec = getRecord(content.pokemon, legacy.evolvesFrom.id)
        out.evolvesFrom = step(legacy.evolvesFrom.id, rec and (rec.baseDex or rec.dex),
          fromGameMethods(legacy.evolvesFrom.methods))
      end
    end
    if isForm and not out.evolvesFrom and #out.evolvesInto == 0 then return nil end
    -- the family, root first, and how deep this one sits
    local list = out.chainId and chainList(out.chainId)
    out.chain = {}
    for _, d in ipairs(list or {}) do
      local cid = idOfDex(d)
      if cid then out.chain[#out.chain + 1] = cid end
    end
    if #out.chain == 0 then out.chain = { id } end
    local stage, cur = 0, dex
    for _ = 1, 4 do
      local e = extraForDex(cur)
      if not (e and e.evolvesFrom) then break end
      stage, cur = stage + 1, e.evolvesFrom.dex
    end
    if isForm and out.evolvesFrom then stage = math.max(stage, 1) end
    out.stage = stage
    return withOverlay("evolution", id, out)
  end

  exports.evolutionsOf = function(idOrDex)
    local id = idOrDex
    if type(idOrDex) == "number" or tonumber(idOrDex) then id = idOfDex(tonumber(idOrDex)) end
    if type(id) ~= "string" then return nil end
    local ok, rec = pcall(evolutionRecord, id)
    return ok and rec or nil
  end

  exports.listEvolutions = function()
    local out = {}
    for dex = 1, 1025 do
      local id = idOfDex(dex)
      if id then out[#out + 1] = id end
    end
    for _, e in ipairs(speciesState.forms) do
      local legacy = legacyEvolutions and legacyEvolutions(e.id)
      if legacy and (legacy.evolvesFrom or #(legacy.evolvesInto or {}) > 0) then
        out[#out + 1] = e.id
      end
    end
    table.sort(out)
    return out
  end

  --------------------------------------------------------------------------- patch
  -- the fields of `partial` the registered record has go to the registry; all of it is kept
  -- for this mod's replies
  local function forwardKnown(registry, id, partial)
    local live = getRecord(registry, id)
    if not live then return end
    local known = {}
    for k, v in pairs(partial) do
      if live[k] ~= nil then known[k] = v end
    end
    if next(known) then pcall(registry.patch, registry, id, known) end
  end

  exports.patch = function(kind, id, partial)
    if type(kind) ~= "string" or id == nil or type(partial) ~= "table" then
      return false, "patch(kind, id, partial)"
    end
    local registryName = FORWARD[kind]
    if registryName then
      local registry = content[registryName]
      if not registry then return false, "no " .. registryName .. " registry here" end
      local ok, err = pcall(registry.patch, registry, id, partial)
      return ok, not ok and tostring(err) or nil
    end
    local store = overlay[kind]
    if not store then return false, "unknown kind " .. kind end
    local key = id
    if kind == "ability" or kind == "itemFlags" then
      key = strip(id)
    elseif kind == "item" then
      local rec = exports.itemById(id)
      key = rec and rec.id or strip(id)
    elseif kind == "move" or kind == "moveFlags" then
      local n = moveNumber(id)
      key = n and ((opts.direct and opts.direct(n)) or moves().byN[n].slug:upper():gsub("%-", "_")) or id
    end
    store[key] = merge(store[key] or {}, partial)
    if kind == "species" then forwardKnown(content.pokemon, key, partial) end
    if kind == "move" then forwardKnown(content.moves, key, partial) end
    return true
  end

  -- national_dex counts its API from 1; this one answers every call up to 9
  exports.apiVersion = 9
end
