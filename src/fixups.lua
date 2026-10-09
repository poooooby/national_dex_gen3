-- Repairs the running Gen 3 game's species tables need after a registry write, re-applied on
-- every species reload (Pokemon.onReload), because the engine rebuilds its
-- tables from the ROM pack each time.
--
--   * evolution targets: the registry resolves a step's target while it is
--     still assigning slots, so a step into another new species can land on
--     slot 0 and never fire. Each registered species' rows are rewritten with
--     the real target slots.
--   * name lookup: Pokemon.speciesFromName reads an index built from the ROM
--     names at install time; new species are added to it.
--   * national numbers: Pokemon.national / speciesFromNational read the ROM's
--     national table; new species are added both ways.
--
-- Reaches into src.core.game3.pokemon (engine_internals): none of this has a
-- registry or hook.

local Fixups = {}

-- G3.EVOLUTIONS order (src/mods/Schemas.lua): the method's number is its
-- position; level methods take the level as their parameter.
local METHOD = {
  EVO_FRIENDSHIP = 1, EVO_FRIENDSHIP_DAY = 2, EVO_FRIENDSHIP_NIGHT = 3,
  EVO_LEVEL = 4, EVO_TRADE = 5, EVO_TRADE_ITEM = 6, EVO_ITEM = 7,
}

local function nameKeys(record)
  local keys = {}
  for _, s in ipairs({ record.id, record.name }) do
    if type(s) == "string" then
      local k = s:upper():gsub("[%.']", ""):gsub("[%s%-]+", "_")
      keys[#keys + 1] = k
      keys[#keys + 1] = (k:gsub("_", ""))
    end
  end
  return keys
end

-- The step's engine PARAM (a level, or an item's number in the running game), and
-- whether it resolved. An item step that does not resolve is not "param 0"
-- -- that would be a real, wrong item id -- it is "not yet": the caller
-- must skip writing the row rather than write a bad one.
local function resolveParam(step, itemIndex)
  if not step.item then return step.level or 0, true end
  local index = itemIndex and itemIndex(step.item)
  return index, index ~= nil
end

-- registered: Species.register's list; itemIndex(slug) -> the item's number,
-- re-resolved live (Species.itemIndex) -- never a snapshot, so a step gated
-- on an item that does not exist YET simply waits; bridges: evolutions
-- added to the cart's own species (Species.register); log: mod.log, for a
-- one-line summary of what is waiting and on what.
function Fixups.new(registered, itemIndex, bridges, log, forms)
  local self = {}
  bridges = bridges or {}
  forms = forms or {}
  -- Every species this mod registered, base species first, then the alternate
  -- forms (src/species.lua). A form is a species of its own for the engine's
  -- tables, but it is not a Pokedex species: it reports its base's National
  -- number and never takes over the base's slot in the number -> slot map.
  local all = {}
  for _, r in ipairs(registered) do all[#all + 1] = r end
  for _, r in ipairs(forms) do all[#all + 1] = r end
  local baseSlotOf = {}
  for _, f in ipairs(forms) do
    for _, b in ipairs(registered) do
      if b.id == f.baseSpecies then baseSlotOf[f.slot] = b.slot end
    end
    -- a form of the cart's own species (Hisuian Qwilfish): the base is the cart's slot
    if not baseSlotOf[f.slot] then
      local okP, PokemonG3 = pcall(require, "src.core.game3.pokemon")
      local base = okP and PokemonG3.speciesFromName and PokemonG3.speciesFromName(f.baseSpecies)
      if base then baseSlotOf[f.slot] = base end
    end
  end
  local loggedWaiting = false

  -- The cart's species keep their own rows; each added step whose item (if
  -- any) resolves is found by its target (or the slot-0 row the registry
  -- wrote for it) and repaired, or appended when the reload dropped it. A
  -- step whose item does not resolve yet is left untouched -- not written,
  -- not removed -- so it costs nothing and simply appears once it does.
  local waiting = {}
  local function applyBridges(P)
    for _, b in ipairs(bridges) do
      local method = METHOD[b.method]
      if method and b.targetSlot and b.sourceSlot then
        local p, ok = resolveParam(b, itemIndex)
        if ok then
          local rows = P._evolutions[b.sourceSlot] or {}
          P._evolutions[b.sourceSlot] = rows
          local found
          for _, row in ipairs(rows) do
            if row.target == b.targetSlot
              or ((row.target or 0) == 0 and row.method == method) then
              found = row
              break
            end
          end
          found = found or {}
          found.method, found.param, found.target = method, p, b.targetSlot
          local present = false
          for _, row in ipairs(rows) do if row == found then present = true end end
          if not present then rows[#rows + 1] = found end
        elseif b.item then
          waiting[b.item] = (waiting[b.item] or 0) + 1
        end
      end
    end
  end

  -- The running game's move tutors (FireRed/LeafGreen: 15; Ruby/Sapphire: none;
  -- Emerald: its own larger set): a species' tutor bits come from the moves it
  -- can be taught in any game. MoveLearn loads its tutor pack lazily and can
  -- drop it (resetTutorPack), so the bits are added to whichever pack its
  -- tutorLearnsets() hands back, once per pack.
  local function installTutors()
    local ok, ML = pcall(require, "src.core.game3.move_learn")
    if not (ok and type(ML) == "table" and type(ML.tutorLearnsets) == "function")
      or ML.__nationalDexGen3 then
      return
    end
    ML.__nationalDexGen3 = true
    local original = ML.tutorLearnsets
    local done = setmetatable({}, { __mode = "k" })
    ML.tutorLearnsets = function(...)
      local sets = original(...)
      if type(sets) == "table" and not done[sets] then
        done[sets] = true
        local tutorOf = {}
        for tutor, move in pairs(type(ML.tutorMoves) == "function" and ML.tutorMoves() or {}) do
          tutorOf[move] = tutor
        end
        for _, r in ipairs(all) do
          local bits = 0
          for _, move in ipairs(r.teach or {}) do
            local tutor = tutorOf[move]
            if tutor then bits = bits + 2 ^ tutor end
          end
          if bits > 0 then sets[r.slot] = bits end
        end
      end
      return sets
    end
  end

  function self.apply(P)
    if type(P) ~= "table" then return end
    P._evolutions = P._evolutions or {}
    for slug in pairs(waiting) do waiting[slug] = nil end -- recount fresh each pass
    for _, r in ipairs(all) do
      -- every step is decided fresh against the current item registry, so a
      -- mod that stops providing an item between reloads (disabled, removed)
      -- takes its evolution step with it rather than leaving a stale row
      local rows = {}
      for _, step in ipairs(r.evolutions) do
        local method = METHOD[step.method]
        if method and step.targetSlot then
          local p, ok = resolveParam(step, itemIndex)
          if ok then
            rows[#rows + 1] = { method = method, param = p, target = step.targetSlot }
          elseif step.item then
            waiting[step.item] = (waiting[step.item] or 0) + 1
          end
        end
      end
      P._evolutions[r.slot] = rows
      if type(P._byName) == "table" then
        for _, key in ipairs(nameKeys(r)) do
          if P._byName[key] == nil then P._byName[key] = r.slot end
        end
      end
      if type(P._national) == "table" then
        P._national.toNational = P._national.toNational or {}
        P._national.toSpecies = P._national.toSpecies or {}
        P._national.toNational[r.slot] = r.dex -- a form's dex is its base's
        if not r.form then P._national.toSpecies[r.dex] = r.slot end
      end
    end
    applyBridges(P)
  end

  -- One line, once per boot: which items -- if any mod ever registers them
  -- -- would light up an evolution this install currently skips. Logged
  -- after the first apply() so the counts reflect every mod that has
  -- registered by then, not just this one.
  local function logWaiting()
    if loggedWaiting or not log or next(waiting) == nil then return end
    loggedWaiting = true
    local parts, total = {}, 0
    for slug, count in pairs(waiting) do
      parts[#parts + 1] = slug .. " x" .. count
      total = total + count
    end
    table.sort(parts)
    log:info("%d evolution step(s) wait on an item no installed mod provides "
      .. "-- they activate on their own if one ever does: %s",
      total, table.concat(parts, ", "))
  end

  -- Called on game.ready: apply now and after every reload. The key replaces
  -- an earlier registration of the same hook (F5 reloads).
  -- The engine's "how many National Dex entries exist" constant. It is a
  -- loop bound only (seen/caught are plain tables keyed by slot), and a mod
  -- that reads it to enumerate species -- Kanto Gear's wild-encounter guide
  -- builds its species cache over 1..NATIONAL_MAX -- never sees species past
  -- it, so a spawn mod's #387+ rows silently vanish from that guide. Raised,
  -- never lowered. SIDE EFFECT, deliberate:
  -- the native Pokedex list in National mode also uses this bound, so it now
  -- lists #387-1025, without art unless a sprite mod provides it.
  local DEX_TOP = 1025
  local function raiseNationalMax()
    local ok, Dex = pcall(require, "src.core.game3.dex")
    if ok and type(Dex) == "table" and (tonumber(Dex.NATIONAL_MAX) or 0) < DEX_TOP then
      Dex.NATIONAL_MAX = DEX_TOP
    end
  end

  -- Emerald's Pokedex entries (category / size / text per internal slot) are
  -- read, fresh each call, through Mapsec.readLua; its table ends at slot 411.
  -- A mod that walks every National number and asserts an entry exists for
  -- each (Kanto Gear's species cache, once Dex.NATIONAL_MAX covers #387+)
  -- errors on the first species past it, so every species this mod registers
  -- gets an entry, keyed by slot like the cart's own. Category, height and
  -- weight come from PokeAPI; there is no flavor text, so it is blank. The
  -- other games' lookups fall back to a blank entry on their own and need no
  -- help (and are keyed by National number where it matters, so injecting
  -- slot-keyed rows there would label the wrong species).
  local function installDexEntries()
    local ok, Mapsec = pcall(require, "src.ui.game3.rse.mapsec")
    if not (ok and type(Mapsec) == "table" and type(Mapsec.readLua) == "function")
      or Mapsec.__nationalDexGen3 then
      return
    end
    Mapsec.__nationalDexGen3 = true
    local original = Mapsec.readLua
    Mapsec.readLua = function(rel, ...)
      local out = original(rel, ...)
      if rel == "pokemon/pokedex/entries.lua" and type(out) == "table" then
        local entryOf = {}
        for _, b in ipairs(registered) do entryOf[b.id] = b.dexEntry end
        for _, r in ipairs(all) do
          if out[r.slot] == nil then
            local d = r.dexEntry or entryOf[r.baseSpecies] or {}
            out[r.slot] = { category = d.kind or "", height = d.height or 0,
              weight = d.weight or 0, description = d.text or "", description2 = "" }
          end
        end
      end
      return out
    end
  end

  -- The Pokedex knows species by slot (seen/caught are tables keyed by it),
  -- so a form slot would count as a species of its own and never light up its
  -- base. Marking a form seen/caught also marks its base, and the counts are
  -- taken over a view of the Dex without form slots. Installed once.
  local function installFormDex()
    local ok, Dex = pcall(require, "src.core.game3.dex")
    if not (ok and type(Dex) == "table") or Dex.__nationalDexGenForms or next(baseSlotOf) == nil then
      return
    end
    Dex.__nationalDexGenForms = true

    local function withBase(name)
      local original = Dex[name]
      if type(original) ~= "function" then return end
      Dex[name] = function(dex, species, ...)
        local result = original(dex, species, ...)
        local base = baseSlotOf[tonumber(species) or -1]
        if base then original(dex, base) end
        return result
      end
    end
    withBase("setSeen")
    withBase("setCaught")

    local function withoutForms(dex)
      if type(dex) ~= "table" then return dex end
      local view = {}
      for k, v in pairs(dex) do view[k] = v end
      for _, key in ipairs({ "seen", "caught", "owned" }) do
        if type(dex[key]) == "table" then
          local kept = {}
          for slot, on in pairs(dex[key]) do
            if not baseSlotOf[tonumber(slot) or -1] then kept[slot] = on end
          end
          view[key] = kept
        end
      end
      return view
    end
    for _, name in ipairs({ "countSeen", "countCaught", "countOwned" }) do
      local original = Dex[name]
      if type(original) == "function" then
        Dex[name] = function(dex, ...) return original(withoutForms(dex), ...) end
      end
    end
    local summary = Dex.summaryCount
    if type(summary) == "function" then
      Dex.summaryCount = function(save)
        if type(save) ~= "table" then return summary(save) end
        local view = {}
        for k, v in pairs(save) do view[k] = v end
        if type(save.dex) == "table" then view.dex = withoutForms(save.dex)
        elseif type(save.pokedex) == "table" then view.pokedex = withoutForms(save.pokedex) end
        return summary(view)
      end
    end
  end

  -- Ruby/Sapphire/Emerald's Pokedex lists species from orders packs extracted from the cart
  -- (numerical_national, atoz, lightest, smallest: arrays of National numbers) and sizes its
  -- National list by `#numerical_national`, so it stops at #386. Extend the orders with the
  -- species this mod registered: numerical by number, A-Z by name, weight / height by their
  -- own value (Gfx.orders caches, so the extended copy is built once). Bases only.
  local function installRseDexOrders()
    local okG, Gfx = pcall(require, "src.ui.game3.rse.pokedex_gfx")
    if not (okG and type(Gfx) == "table" and type(Gfx.orders) == "function") or Gfx.__nationalDexGen3 then
      return
    end
    Gfx.__nationalDexGen3 = true
    local original = Gfx.orders
    local extended
    Gfx.orders = function(...)
      local base = original(...)
      if extended and extended.__source == base then return extended end
      local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
      local okM, Mapsec = pcall(require, "src.ui.game3.rse.mapsec")
      if not (okP and okM and type(base) == "table" and type(base.numerical_national) == "table") then
        return base
      end
      local entries = Mapsec.readLua("pokemon/pokedex/entries.lua") or {}
      local out = {}
      for k, v in pairs(base) do out[k] = v end
      local top = #base.numerical_national
      local added = {}
      for _, b in ipairs(registered) do
        if b.dex > top and b.dex <= 1025 then added[#added + 1] = b end
      end
      table.sort(added, function(a, b) return a.dex < b.dex end)
      local function copy(list) local c = {} for i, v in ipairs(list or {}) do c[i] = v end return c end
      local function slotOfNat(nat) return Pokemon.speciesFromNational and Pokemon.speciesFromNational(nat) end
      -- insert every added species into a sorted list by key (stable, after equals)
      local function merge(list, key)
        local c = copy(list)
        for _, b in ipairs(added) do
          local k = key(b.slot)
          local at = #c + 1
          for i = 1, #c do
            local ck = key(slotOfNat(c[i]))
            if ck ~= nil and k < ck then at = i break end
          end
          table.insert(c, at, b.dex)
        end
        return c
      end
      out.numerical_national = copy(base.numerical_national)
      for _, b in ipairs(added) do out.numerical_national[#out.numerical_national + 1] = b.dex end
      local function nameKey(slot) local n = slot and Pokemon.name(slot); return n and tostring(n):upper() or nil end
      local function field(name) return function(slot)
        local e = slot and entries[slot]; return e and tonumber(e[name]) or nil end end
      if base.atoz then out.atoz = merge(base.atoz, nameKey) end
      if base.lightest then out.lightest = merge(base.lightest, field("weight")) end
      if base.smallest then out.smallest = merge(base.smallest, field("height")) end
      out.__source = base
      extended = out
      return out
    end
  end

  -- FireRed/LeafGreen's Pokedex reads PokedexData._entries (keyed by slot, built once by
  -- PokedexData.init) and answers a placeholder ("newly discovered POKéMON", UNKNOWN) for a
  -- slot it has no row for, and its A-Z / weight / height orders (PokedexData._orders, arrays
  -- of National numbers) stop at #386. Add a row for every species and form this mod registered
  -- and merge them into those orders. Installed once, repeated safely.
  local function installFrlgDexData()
    local okD, PokedexData = pcall(require, "src.core.game3.pokedex_data")
    if not (okD and type(PokedexData) == "table" and type(PokedexData.init) == "function")
      or PokedexData.__nationalDexGen3 then
      return
    end
    PokedexData.__nationalDexGen3 = true
    local original = PokedexData.init
    local done
    PokedexData.init = function(...)
      local out = original(...)
      local entries, orders = PokedexData._entries, PokedexData._orders
      if type(entries) ~= "table" or done == entries then return out end
      done = entries
      local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
      if not okP then return out end
      local entryOf, added = {}, {}
      for _, b in ipairs(registered) do entryOf[b.id] = b.dexEntry end
      for _, r in ipairs(all) do
        if entries[r.slot] == nil then
          local d = r.dexEntry or entryOf[r.baseSpecies] or {}
          entries[r.slot] = { category = d.kind or "", height = d.height or 0, weight = d.weight or 0,
            description = d.text or "", description2 = "", pokemonScale = 256, pokemonOffset = 0,
            trainerScale = 256, trainerOffset = 0 }
        end
        if not r.form and r.dex > 386 then added[#added + 1] = r end
      end
      if type(orders) ~= "table" then return out end
      table.sort(added, function(a, b) return a.dex < b.dex end)
      local function merge(list, key)
        local c = {}
        for i, v in ipairs(list or {}) do c[i] = v end
        for _, r in ipairs(added) do
          local k = key(r.slot)
          local at = #c + 1
          for i = 1, #c do
            local slot = Pokemon.speciesFromNational and Pokemon.speciesFromNational(c[i])
            local ck = slot and key(slot)
            if ck ~= nil and k < ck then at = i break end
          end
          table.insert(c, at, r.dex)
        end
        return c
      end
      local function nameKey(slot) local n = Pokemon.name(slot); return n and tostring(n):upper() or nil end
      local function field(name) return function(slot)
        local e = entries[slot]; return e and tonumber(e[name]) or nil end end
      if orders.atoz then orders.atoz = merge(orders.atoz, nameKey) end
      if orders.lightest then orders.lightest = merge(orders.lightest, field("weight")) end
      if orders.smallest then orders.smallest = merge(orders.smallest, field("height")) end
      return out
    end
  end

  function self.install(_)
    installTutors()
    raiseNationalMax()
    installFormDex()
    installDexEntries()
    installRseDexOrders()
    installFrlgDexData()
    local ok, P = pcall(require, "src.core.game3.pokemon")
    if not (ok and type(P) == "table") then return false end
    self.apply(P)
    logWaiting()
    if type(P.onReload) == "function" then
      P.onReload(function(mod) self.apply(mod or P) end, "national_dex_gen3")
    end
    return true
  end

  return self
end

Fixups._nameKeys = nameKeys
Fixups._METHOD = METHOD

return Fixups
