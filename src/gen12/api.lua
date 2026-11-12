-- mod.exports on Gen 1 / Gen 2: the same src/api.lua the Gen 3 path publishes (loaded as it
-- is), handed this path's species, forms and the cart species' new evolutions in the shape it
-- reads: records { id, dex, slot, name, legendary, mythical, evolutions = { { species, method,
-- level } } }, forms { ..., baseSpecies, form, baseDex }, bridges { sourceId, sourceDex,
-- species, method, level }. The slot is the Gen 3 slot (dex + 64, forms 1090+): the stable key
-- every game shares, and the key of the cries and of a sprite mod's pictures.
--
-- Published here: apiVersion, isActive, provider, listSpecies, slotOf, listForms, formsOf,
-- baseDexOf, idOfSlot, evolutionsOf, setArtProvider, clockSource (and generation). The Gen 3
-- extras src/api.lua also defines (setDexPeek, moveExtra, moveRule; dynamax only with its state)
-- answer nothing here, so they are taken back out: a caller tests for them by presence.
-- Method names are the running game's: Red LEVEL / ITEM / TRADE / FRIENDSHIP, Gold EVOLVE_*.

return function(mod, opts)
  local Api, species, evo, gen = opts.api, opts.species, opts.evolutions, opts.generation

  local function steps(id)
    local out = {}
    for _, row in ipairs(evo and evo.rows[id] or {}) do
      out[#out + 1] = { species = row.species or row.into, method = row.method, level = row.level }
    end
    return out
  end

  local list = {}
  for dex, entry in pairs(species.byDex) do
    local r = entry.data
    list[#list + 1] = { id = entry.id, dex = dex, slot = r.slot, name = r.name,
      legendary = r.legendary, mythical = r.mythical, evolutions = steps(entry.id) }
  end
  table.sort(list, function(a, b) return a.dex < b.dex end)

  local forms = {}
  for i, entry in ipairs(species.forms) do
    local r = entry.data
    forms[i] = { id = entry.id, slot = r.slot, name = r.name, baseSpecies = entry.base,
      form = r.form, baseDex = r.baseDex, evolutions = steps(entry.id) }
  end

  Api(mod, { species = list, forms = forms, bridges = evo and evo.bridges or {}, art = opts.art })

  local exports = mod.exports
  exports.setDexPeek, exports.moveExtra, exports.moveRule, exports.dynamax = nil, nil, nil, nil
  exports.generation = function() return gen end
  -- the clock the time-of-day evolutions read: Red has none of its own (the device's hours),
  -- Gold its own time of day
  exports.clockSource = function() return gen == 1 and "device" or "game" end
end
