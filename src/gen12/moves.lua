-- Moves on Gen 1 / Gen 2: the newer moves that run on an effect the game already has, and the
-- National-number resolver every learnset goes through.
--
-- data/gen12/moves.lua (tools/build_gen12.py) has a row per move past #165 that some species
-- learns. A row with `gen1` / `gen2` runs natively on that generation: it is registered here as a
-- real move on the cart's effect (Red's effect names, Gold's EFFECT_* plus its chance), and it
-- borrows the battle animation of its `look`, a cart move (Red also takes that move's sound,
-- which Red keeps on the move record). Every other row has `subs`: the ranked stand-ins the
-- resolver picks from.
--
-- Numbers: Red's moves #1-165 and Gold's #1-251 are the National numbers (the carts' own
-- indices); Gold's registered moves keep their National number as their index too, so a save or
-- another mod that reads indices sees the same number on every game.
--
-- Gold keeps its high-critical moves in the type chart's battle rules, outside any registry, so
-- those are added to the live table on game.ready (Moves.installHighCrit).

local Moves = {}

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

-- opts: { mod, rows = data/gen12/moves.lua, generation, types = src/gen12/types.lua, log }.
-- Returns state: { byNumber = { [n] = id } for the moves that run here, rows, generation,
-- registered, borrowed (another mod already had the id), highCrit = { ids } (Gold), failed }.
function Moves.register(opts)
  local mod, gen, Types, log = opts.mod, opts.generation, opts.types, opts.log
  local key = "gen" .. gen
  local content = mod.content
  local moves, anims = content.moves, content.battle_anims
  local state = { generation = gen, rows = opts.rows, byNumber = {}, registered = 0, borrowed = 0,
    failed = 0, highCrit = {} }

  -- Gold maps move id -> animation script pointer in one table
  local goldScripts, goldAdded = nil, {}
  if gen == 2 and anims then
    local ok, base = pcall(anims.get, anims, "moves")
    goldScripts = ok and type(base) == "table" and base or nil
  end

  local firstError
  for _, row in ipairs(opts.rows) do
    local real = row[key]
    if real then
      local id = row.id
      if moves:get(id) ~= nil then
        -- another mod (or a later engine) already has this move: use theirs
        state.byNumber[row.n] = id
        state.borrowed = state.borrowed + 1
      else
        local rec = {
          id = id, name = row.name, type = Types.cartId(row.type), power = row.power,
          accuracy = row.accuracy > 0 and row.accuracy or 100, pp = row.pp, effect = real.effect,
        }
        local look = row.look and row.look[key]
        if gen == 1 then
          if row.priority ~= 0 then rec.priority = row.priority end
          if row.highCrit then rec.highCrit = true end
          local like = look and moves:get(look)
          if like and like.anim then rec.anim = copy(like.anim) end
        else
          rec.effectChance = real.chance or 0
          rec.index = row.n
        end
        local ok, err = pcall(moves.register, moves, id, rec)
        if not ok and gen == 2 then
          -- the number is taken (or reserved): let the engine pick one
          rec.index = nil
          ok, err = pcall(moves.register, moves, id, rec)
        end
        if ok then
          state.byNumber[row.n] = id
          state.registered = state.registered + 1
          if gen == 2 and row.highCrit then state.highCrit[#state.highCrit + 1] = id end
          if look then
            if gen == 1 and anims then
              local okA, seq = pcall(anims.get, anims, look)
              if okA and seq then pcall(anims.register, anims, id, copy(seq)) end
            elseif goldScripts and goldScripts[look] then
              goldAdded[id] = goldScripts[look]
            end
          end
        else
          state.failed = state.failed + 1
          firstError = firstError or (id .. ": " .. tostring(err))
        end
      end
    end
  end
  if next(goldAdded) then
    local ok, err = pcall(anims.patch, anims, "moves", goldAdded)
    if not ok and log then log:warn("new moves keep no animation: %s", tostring(err)) end
  end
  if firstError and log then
    log:warn("%d newer moves could not be registered (first: %s); they use stand-ins", state.failed,
      firstError)
  end
  return state
end

-- Gold: the registered high-critical moves join the battle rules' list (idempotent).
function Moves.installHighCrit(state, data)
  local rules = data and data.type_chart and data.type_chart.battleRules
  local list = rules and rules.highCriticalMoves
  if type(list) ~= "table" then return 0 end
  for _, id in ipairs(state.highCrit) do list[id] = true end
  return #state.highCrit
end

-- A function (n, taken) -> move id: the cart's move for #1-165 (Red) / #1-251 (Gold), the
-- registered move where one runs here, else the first stand-in (`subs`) the Pokemon does not
-- already know (`taken`: id -> true; the stand-in is not marked, the caller does that). nil only
-- when nothing fits (every stand-in taken), in which case the move is left out.
function Moves.resolver(state, cartMoves)
  local key = "gen" .. state.generation
  local maxMove = state.generation == 1 and 165 or 251
  local byIndex = {}
  for id, rec in pairs(cartMoves) do
    if type(rec) == "table" and type(rec.index) == "number" and rec.index >= 1
        and rec.index <= maxMove then
      byIndex[rec.index] = id
    end
  end
  local rows = {}
  for _, row in ipairs(state.rows) do rows[row.n] = row end

  local function direct(n)
    if n <= maxMove then return byIndex[n] end
    return state.byNumber[n]
  end
  return function(n, taken)
    local id = direct(n)
    if id then return id end
    local row = rows[n]
    for _, s in ipairs(row and row.subs and row.subs[key] or {}) do
      local sub = direct(s)
      if sub and not (taken and taken[sub]) then return sub end
    end
    return nil
  end
end

return Moves
