-- mod.exports: what other mods read from national_dex_gen3.
--
--   local dex = mod:find("national_dex_gen3")
--   if dex and (dex.exports.apiVersion or 0) >= 1 then ... end
--
-- Every return is a copy. apiVersion only goes up, and only when an existing
-- field changes meaning; check `>=`.

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

return function(mod, state)
  local exports = mod.exports
  local species = state.species or {}
  local bridges = state.bridges or {}
  -- The alternate forms are species of their own for the engine (a slot above
  -- the base range) but not Pokedex species: they are found by id or slot,
  -- never by dex number (a form's dex is its base's, and the base must keep
  -- answering for it), and listSpecies does not list them.
  local forms = state.forms or {}
  local byId, byDex, bySlot, formsOfBase = {}, {}, {}, {}
  for _, r in ipairs(species) do
    byId[r.id] = r
    byDex[r.dex] = r
    bySlot[r.slot] = r
  end
  for _, r in ipairs(forms) do
    byId[r.id] = r
    bySlot[r.slot] = r
    formsOfBase[r.baseSpecies] = formsOfBase[r.baseSpecies] or {}
    table.insert(formsOfBase[r.baseSpecies], r)
  end
  local everyone = {}
  for _, r in ipairs(species) do everyone[#everyone + 1] = r end
  for _, r in ipairs(forms) do everyone[#everyone + 1] = r end
  local function find(idOrDex)
    return byId[idOrDex] or byDex[tonumber(idOrDex) or -1]
  end

  -- Evolutions from the cart's own species (#1-386) into this mod's own
  -- (Magneton -> Magnezone, ...) never appear in `species`' own bookkeeping
  -- -- the source is not one of this mod's species -- so evolutionsOf reads
  -- them from `bridges` instead, indexed both ways. A bridge whose item
  -- hasn't resolved in this install (src/fixups.lua) is still listed here;
  -- this export does not say whether a step is currently live.
  local bridgeFrom, bridgeInto = {}, {}
  for _, b in ipairs(bridges) do
    bridgeFrom[b.species] = bridgeFrom[b.species]
      or { id = b.sourceId, methods = {} }
    table.insert(bridgeFrom[b.species].methods, { level = b.level, trigger = b.method })
    bridgeInto[b.sourceId] = bridgeInto[b.sourceId] or {}
    bridgeInto[b.sourceDex] = bridgeInto[b.sourceId]
    table.insert(bridgeInto[b.sourceId],
      { id = b.species, methods = { { level = b.level, trigger = b.method } } })
  end

  -- 2: adds listForms, formsOf, baseDexOf, idOfSlot (alternate forms). Nothing
  -- in version 1 changed meaning.
  exports.apiVersion = 2

  -- false when 1025Dex is installed (it provides the species instead)
  exports.isActive = function() return state.active == true end
  -- "national_dex_gen3" or the mod that provides species in its place
  exports.provider = function() return state.provider or "national_dex_gen3" end

  -- { { dex, id, slot, name, legendary, mythical }, ... } ascending by dex
  exports.listSpecies = function()
    local out = {}
    for i, r in ipairs(species) do
      out[i] = { dex = r.dex, id = r.id, slot = r.slot, name = r.name,
                 legendary = r.legendary, mythical = r.mythical }
    end
    return out
  end

  -- The running game's species slot for an id or dex number (this mod's species).
  exports.slotOf = function(idOrDex)
    local r = find(idOrDex)
    return r and r.slot or nil
  end

  -- Alternate forms (Wormadam-Sandy, Rotom-Heat, Galarian Darumaka, ...):
  -- { { id, slot, name, baseSpecies, form, baseDex }, ... } in slot order. Each
  -- is a species of its own in the engine, reporting its base's dex number.
  exports.listForms = function()
    local out = {}
    for i, r in ipairs(forms) do
      out[i] = { id = r.id, slot = r.slot, name = r.name, baseSpecies = r.baseSpecies,
                 form = r.form, baseDex = r.baseDex, dex = r.baseDex }
    end
    return out
  end

  -- The forms of one base species, by id or dex number: { { id, slot, form }, ... }
  exports.formsOf = function(idOrDex)
    local base = byId[idOrDex] or byDex[tonumber(idOrDex) or -1]
    local out = {}
    for _, r in ipairs(base and formsOfBase[base.id] or {}) do
      out[#out + 1] = { id = r.id, slot = r.slot, form = r.form }
    end
    return out
  end

  -- The National Dex number to DISPLAY for a slot, id or dex number: a form's
  -- is its base species'. nil for anything this mod does not register.
  exports.baseDexOf = function(slotOrIdOrDex)
    local r = byId[slotOrIdOrDex] or bySlot[tonumber(slotOrIdOrDex) or -1]
      or byDex[tonumber(slotOrIdOrDex) or -1]
    return r and (r.baseDex or r.dex) or nil
  end

  -- The id of the species (base or form) registered at a slot, or nil.
  exports.idOfSlot = function(slot)
    local r = bySlot[tonumber(slot) or -1]
    return r and r.id or nil
  end

  -- national_dex's evolutionsOf shape:
  --   { id, dex, evolvesFrom = { id, methods = { { level, trigger } } },
  --     evolvesInto = { { id, methods = {...} } } }
  -- Works for this mod's own species (#387-1025) and, evolvesInto only, for
  -- a cart species (#1-386) that gains a step into one of them -- so asking
  -- about vanilla RHYDON finds its new RHYPERIOR evolution even though this
  -- mod never registers RHYDON itself.
  exports.evolutionsOf = function(idOrDex)
    local r = find(idOrDex)
    if not r then
      local into = bridgeInto[idOrDex] or bridgeInto[tonumber(idOrDex) or -1]
      if not into then return nil end
      return copy({ id = idOrDex, evolvesInto = into })
    end
    local out = { id = r.id, dex = r.dex, evolvesInto = {} }
    for _, step in ipairs(r.evolutions or {}) do
      out.evolvesInto[#out.evolvesInto + 1] = {
        id = step.species, methods = { { level = step.level, trigger = step.method } } }
    end
    out.evolvesFrom = bridgeFrom[r.id]
    for _, other in ipairs(everyone) do
      for _, step in ipairs(other.evolutions or {}) do
        if step.species == r.id then
          out.evolvesFrom = { id = other.id,
                              methods = { { level = step.level, trigger = step.method } } }
        end
      end
    end
    return copy(out)
  end

  -- Art seam (src/art.lua): fn(speciesId, side, slot) -> PNG path | nil.
  exports.setArtProvider = function(fn)
    return state.art ~= nil and state.art.add(fn) or false
  end
end
