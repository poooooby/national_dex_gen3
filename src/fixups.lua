-- Repairs FireRed's species tables need after a registry write, re-applied on
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

-- The step's engine PARAM (a level, or an item's FireRed number), and
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
function Fixups.new(registered, itemIndex, bridges, log)
  local self = {}
  bridges = bridges or {}
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

  -- FireRed's 15 move tutors: a species' tutor bits come from the moves it
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
        for _, r in ipairs(registered) do
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
    for _, r in ipairs(registered) do
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
        P._national.toNational[r.slot] = r.dex
        P._national.toSpecies[r.dex] = r.slot
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
  function self.install(_)
    installTutors()
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
