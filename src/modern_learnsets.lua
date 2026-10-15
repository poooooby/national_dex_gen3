-- The "Modern Moves" option (off by default): the original 386 Pokemon also learn the newer
-- moves they learn in the modern games (data/species/modern.lua, tools/build_modern_learnsets.py).
--
-- The cart's own learnsets stay as they are; while the option is on, each species' level-up list
-- is swapped for a copy with the newer rows merged in by level, and its egg-move list (only a
-- species that has one: the one an egg hatches as) for a copy with the newer egg moves added.
-- Turning it off puts the cart's own lists back. Pokemon.learnset / eggMoves read these tables
-- live, so level-up learning, the Move Reminder, breeding and the save editor all follow.
-- Nothing is written to the save: a move already learned stays known either way.
local ModernLearnsets = {}

-- opts: { data (data/species/modern.lua), enabled() -> bool, require, log }
function ModernLearnsets.install(opts)
  local require, log, data = opts.require, opts.log, opts.data or {}
  local okP, P = pcall(require, "src.core.game3.pokemon")
  if not (okP and type(P) == "table" and P.speciesFromNational) then
    if log then log:warn("modern moves are off: the species module was not found") end
    return nil
  end

  -- ours[list] = the cart's list it replaced, for the lists this module made (weak: a reload
  -- builds new tables and drops ours)
  local ours = setmetatable({}, { __mode = "k" })

  local function merged(base, extra)
    local out = {}
    for i, row in ipairs(base) do out[i] = row end
    local have = {}
    for _, row in ipairs(base) do have[tostring(row[1]) .. ":" .. tostring(row[2])] = true end
    for _, row in ipairs(extra) do
      if not have[row[1] .. ":" .. row[2]] then out[#out + 1] = { row[1], row[2] } end
    end
    -- by level; the cart's rows keep their order among equal levels, then the newer ones
    local order = {}
    for i, row in ipairs(out) do order[row] = i end
    table.sort(out, function(a, b)
      if a[1] ~= b[1] then return a[1] < b[1] end
      return order[a] < order[b]
    end)
    return out
  end

  local function eggMerged(base, extra)
    local out, have = {}, {}
    for i, m in ipairs(base) do out[i] = m; have[m] = true end
    for _, m in ipairs(extra) do if not have[m] then out[#out + 1] = m end end
    return out
  end

  local function apply()
    if not P._learnsets then pcall(P.learnset, 1) end
    local on = opts.enabled()
    local rows, eggs = 0, 0
    for dex, add in pairs(data) do
      local slot = P.speciesFromNational(dex)
      if slot then
        local sets, eggMoves = P._learnsets, P._eggMoves
        if type(sets) == "table" then
          local cur = sets[slot]
          local cart = ours[cur] or cur
          if on and add.learnset and type(cart) == "table" then
            if not ours[cur] then
              local list = merged(cart, add.learnset)
              ours[list] = cart
              sets[slot] = list
            end
            rows = rows + #add.learnset
          elseif not on and ours[cur] then
            sets[slot] = ours[cur]
          end
        end
        if type(eggMoves) == "table" then
          local cur = eggMoves[slot]
          local cart = ours[cur] or cur
          if on and add.eggMoves and type(cart) == "table" then
            if not ours[cur] then
              local list = eggMerged(cart, add.eggMoves)
              ours[list] = cart
              eggMoves[slot] = list
            end
            eggs = eggs + #add.eggMoves
          elseif not on and ours[cur] then
            eggMoves[slot] = ours[cur]
          end
        end
      end
    end
    return on, rows, eggs
  end

  local on, rows, eggs = apply()
  if P.onReload then P.onReload(function() apply() end, "national_dex_gen3.modern_learnsets") end
  if log then
    if on then log:info("modern moves: on (%d level-up rows, %d egg moves)", rows, eggs)
    else log:info("modern moves: off") end
  end
  return apply
end

-- The Move Reminder lists the level-up moves a Pokemon could know again, but the engine (like
-- the cart, whose lists never passed 20) reads only the first 20 rows of a learnset. Modern
-- learnsets are longer (this mod's species, and the original 386 with Modern Moves on), so this
-- lists every row up to the Pokemon's level, in the same order and with the same rules. The
-- relearner screens scroll, so a longer list fits.
function ModernLearnsets.installRelearner(require)
  local okL, MoveLearn = pcall(require, "src.core.game3.move_learn")
  local okP, P = pcall(require, "src.core.game3.pokemon")
  if not (okL and okP and type(MoveLearn.relearnableMoves) == "function") or MoveLearn.__nationalDexRelearner then
    return false
  end
  MoveLearn.__nationalDexRelearner = true
  local original = MoveLearn.relearnableMoves
  local EGG = tonumber(P.SPECIES_EGG) or 412
  MoveLearn.relearnableMoves = function(mon, ...)
    local species = mon and P.speciesOf and P.speciesOf(mon)
    local set = species and species ~= EGG and P.learnset(species)
    if type(set) ~= "table" or #set <= (tonumber(MoveLearn.MAX_LEVEL_UP_MOVES) or 20) then
      return original(mon, ...)
    end
    local level = tonumber(mon.level) or 0
    local known = {}
    for i = 1, 4 do
      local id = tonumber(P.moveIdAt and P.moveIdAt(mon, i)) or 0
      if id > 0 then known[id] = true end
    end
    local moves, seen = {}, {}
    for _, entry in ipairs(set) do
      local lv = tonumber(entry[1] or entry.level) or 0
      local mv = tonumber(entry[2] or entry.move) or 0
      if mv > 0 and lv <= level and not known[mv] and not seen[mv] then
        seen[mv] = true
        moves[#moves + 1] = mv
      end
    end
    return moves
  end
  return true
end

return ModernLearnsets
