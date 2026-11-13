-- The "Modern Moves" option on Gen 1 / Gen 2: the cart's own species (Red #1-151, Gold #1-251)
-- also learn the newer moves they learn in today's games, at the same levels, plus their newer
-- egg moves (Gold). Data: data/gen12/modern.lua (tools/build_gen12.py), National move numbers.
--
-- Only moves the game has outright are added (the cart's own, or a newer move that runs natively
-- there: Moves.resolver's `direct`): a stand-in would only repeat a move the Pokemon has. Moves it
-- already learns keep their own level. Their own rows stay first at a level.
--
-- Records are frozen once mods load, so the live lists are swapped: on game.ready and when the
-- option changes, each cart species' level-up list (Red `learnset`, Gold `levelMoves`) and egg
-- list (Gold) become the merged copies while the option is on, and the originals again when it is
-- off. Moves a Pokemon already knows are never taken away.

local Modern = {}

local function copyRow(r) return { level = r.level, move = r.move } end

-- The merged level-up list and egg list for one cart species, and how many moves were added.
function Modern.merge(def, row, gen, direct)
  local list = gen == 1 and def.learnset or def.levelMoves
  local knows = {}
  for _, m in ipairs(gen == 1 and def.level1Moves or {}) do knows[m] = true end
  for _, r in ipairs(list or {}) do knows[r.move] = true end
  local merged = {}
  for i, r in ipairs(list or {}) do
    local c = copyRow(r)
    c.order = i
    merged[i] = c
  end
  local added = 0
  for _, r in ipairs(row.learnset or {}) do
    local id = direct(r[2])
    if id and not knows[id] then
      knows[id] = true
      added = added + 1
      merged[#merged + 1] = { level = math.max(1, r[1]), move = id, order = 100000 + added }
    end
  end
  table.sort(merged, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return a.order < b.order
  end)
  for _, r in ipairs(merged) do r.order = nil end
  local egg
  if gen == 2 then
    egg, knows = {}, {}
    for i, m in ipairs(def.eggMoves or {}) do egg[i] = m; knows[m] = true end
    for _, n in ipairs(row.eggMoves or {}) do
      local id = direct(n)
      if id and not knows[id] then knows[id] = true; egg[#egg + 1] = id end
    end
  end
  return merged, egg, added
end

-- opts: { generation, rows = data/gen12/modern.lua, direct, cartIdOf = { [dex] = id } }.
-- Returns state with apply(data, on) -> species changed, moves added.
function Modern.install(opts)
  local gen = opts.generation
  local maxDex = gen == 1 and 151 or 251
  local listKey = gen == 1 and "learnset" or "levelMoves"
  local state = { original = {}, merged = {} }

  function state.apply(data, on)
    local pokemon = data and data.pokemon
    if type(pokemon) ~= "table" then return 0, 0 end
    local changed, added = 0, 0
    for _, row in ipairs(opts.rows) do
      local id = row.dex <= maxDex and opts.cartIdOf[row.dex]
      local def = id and pokemon[id]
      if type(def) == "table" then
        local orig = state.original[id]
        if not orig then
          orig = { list = def[listKey], egg = def.eggMoves }
          state.original[id] = orig
        end
        if on then
          local m = state.merged[id]
          if not m then
            local base = { learnset = orig.list, levelMoves = orig.list, eggMoves = orig.egg,
              level1Moves = def.level1Moves }
            local list, egg, n = Modern.merge(base, row, gen, opts.direct)
            m = { list = list, egg = egg, n = n }
            state.merged[id] = m
          end
          def[listKey] = m.list
          if gen == 2 then def.eggMoves = m.egg end
          if m.n > 0 then changed = changed + 1; added = added + m.n end
        else
          def[listKey] = orig.list
          if gen == 2 then def.eggMoves = orig.egg end
        end
      end
    end
    state.on = on
    return changed, added
  end
  return state
end

return Modern
