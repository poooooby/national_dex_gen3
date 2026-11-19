-- The Move Split option on FireRed to Emerald (option move_split, off by default; the same key
-- as Red to Crystal's src/gen12/mech/split.lua): a move is physical or special by the move
-- itself, as in today's games, instead of by its type.
--
-- The Gen 3 battle engine asks one function everywhere: Types.isPhysical(moveType), in the
-- damage formula (which attack and defence stats, stages, burn, Reflect / Light Screen, type
-- boosting items), the hit's bookkeeping (what Counter and Mirror Coat return), Hustle's accuracy,
-- and this mod's own move rules and abilities. So while a move is being resolved, the question
-- is answered by that move: data/move_split.lua gives every damaging move's class in today's
-- games by Gen 3 index (tools/build_move_split.py).
--
-- "While a move is being resolved" is a stack of moves per coroutine (the engine runs a move in a
-- coroutine that can pause for a prompt: Baton Pass, U-turn), pushed by wraps of:
--   Damage.calc       the battle's and the AI's damage estimate: its move
--   Hit.run           the move's hit, from accuracy to after the damage: M.mnum
--   Hit.dealDamage    a hit dealt outside Hit.run (the engine's own fixed-damage calls): M.mnum
--   Effects.run       a move's effect script (Future Sight and Doom Desire work out their damage
--                     there, with Damage.base); an effect with no move keeps the move around it
-- A called move (Metronome, Sleep Talk, Mirror Move, Assist) is a move of its own to the engine
-- (Engine.resolveMove), so it pushes its own class.
-- Link battles and recorded link battles keep the game's split: both players' games must work out
-- the same damage, and the link fingerprint checks the type table, not this option.
-- hub.categoryOf(num, st) answers "physical" / "special" (or nil: the game's way) for code that
-- classifies a move itself rather than asking Types.isPhysical (src/held/gen3.lua).
-- Outside a move, or with the option off, or for a move with no class (status moves, Struggle's
-- stand-ins), the engine's own answer by type stands. The stacks are weak-keyed by coroutine, so
-- a battle left in the middle of a move leaves nothing behind.
--
-- The wraps must be the outermost on Damage.calc and Hit.run, so every other wrap of this mod
-- (move rules, field moves, abilities) asks inside the move: install after them. They are
-- process-wide (Types.__ndxSplit), installed once; a later install only refreshes the data and
-- the option reader.
local Split = {}

local MAIN = {}     -- the stack key outside any coroutine
local NATIVE = {}   -- on a stack: a move with no class, answered by type

-- opts: { require, log, classes = data/move_split.lua, enabled() -> bool }
function Split.install(opts)
  local require, log = opts.require, opts.log
  local okT, Types = pcall(require, "src.core.game3.battle.types")
  local okD, Damage = pcall(require, "src.core.game3.battle.damage")
  local okH, Hit = pcall(require, "src.core.game3.battle.effects.hit")
  if not (okT and okD and okH and type(Types.isPhysical) == "function" and type(Damage.calc) == "function"
      and type(Hit.run) == "function") then
    if log then log:warn("move split is off: the battle engine's functions were not found") end
    return nil
  end
  local hub = Types.__ndxSplit
  if not hub then
    hub = { stacks = setmetatable({}, { __mode = "k" }) }
    Types.__ndxSplit = hub

    local function stack()
      local co = coroutine.running() or MAIN
      local s = hub.stacks[co]
      if not s then
        s = {}
        hub.stacks[co] = s
      end
      return s
    end

    -- the class of a move by its number, or nil (no class: the game's own answer)
    local function classOf(num)
      local c = num and hub.classes and hub.classes[num]
      if c == "p" then return true elseif c == "s" then return false end
      return nil
    end

    local function finish(s, depth, ok, ...)
      for i = #s, depth, -1 do s[i] = nil end
      if not ok then error((...), 0) end
      return ...
    end

    -- a link battle, live or recorded: both sides must work out the same damage
    local function linked(st)
      return type(st) == "table" and (st.link or (type(st.kinds) == "table" and st.kinds.recordedLink)) and true or false
    end
    local function active(st) return hub.enabled and hub.enabled() and not linked(st) end
    hub.categoryOf = function(num, st)
      if not active(st) then return nil end
      local c = classOf(tonumber(num))
      if c == true then return "physical" elseif c == false then return "special" end
      return nil
    end

    -- run f(...) with the move num on this coroutine's stack: its class, or NATIVE for a move
    -- with none (so a status move or a typeless hit inside another move gets the game's answer);
    -- inherit: with no move to go by, leave the stack as it is (an effect run inside a hit)
    local function within(num, st, inherit, f, ...)
      if not active(st) then return f(...) end
      local physical = classOf(num)
      local s = stack()
      if physical == nil and (#s == 0 or (inherit and num == nil)) then return f(...) end
      local depth = #s + 1
      if physical == nil then s[depth] = NATIVE else s[depth] = physical end
      return finish(s, depth, pcall(f, ...))
    end
    hub.within = within

    local function moveNum(moveId)
      if type(moveId) == "table" then
        local n = tonumber(moveId.numId) or tonumber(moveId.id) or tonumber(moveId.index)
        if n then return n end
        moveId = moveId.id
      end
      if tonumber(moveId) then return tonumber(moveId) end
      if type(moveId) == "string" then
        local okM, Moves = pcall(require, "src.core.game3.battle.moves")
        return okM and Moves.numForName and Moves.numForName(moveId) or nil
      end
      return nil
    end
    hub.moveNum = moveNum

    local isPhysical = Types.isPhysical
    Types.isPhysical = function(typeId, ...)
      local s = hub.stacks[coroutine.running() or MAIN]
      local top = s and s[#s]
      if top == true or top == false then return top end
      return isPhysical(typeId, ...)
    end

    local calc = Damage.calc
    Damage.calc = function(attacker, defender, moveId, o, ...)
      local st = type(o) == "table" and type(o.adapter) == "table" and o.adapter._st or nil
      return within(moveNum(moveId), st, false, calc, attacker, defender, moveId, o, ...)
    end

    local run = Hit.run
    Hit.run = function(M, ...)
      local num = type(M) == "table" and (tonumber(M.mnum) or moveNum(M.move)) or nil
      return within(num, type(M) == "table" and M.st or nil, false, run, M, ...)
    end

    if type(Hit.dealDamage) == "function" then
      local deal = Hit.dealDamage
      Hit.dealDamage = function(M, dmg, info, ...)
        local num = type(M) == "table" and (tonumber(M.mnum) or moveNum(M.move)) or nil
        local st = type(M) == "table" and M.st or nil
        if type(info) == "table" and info.physical ~= nil and num and active(st) then
          local c = classOf(num)
          if c ~= nil and c ~= info.physical then
            local copy = {}
            for k, v in pairs(info) do copy[k] = v end
            copy.physical = c
            info = copy
          end
        end
        return within(num, st, false, deal, M, dmg, info, ...)
      end
    end

    local okE, Effects = pcall(require, "src.core.game3.battle.effects")
    if okE and type(Effects) == "table" and type(Effects.run) == "function" then
      local effRun = Effects.run
      Effects.run = function(id, adapter, user, target, move, moveId, moveCtx, ...)
        local num = moveNum(moveId)
        if num == nil or not (hub.classes and hub.classes[num]) then num = moveNum(move) or num end
        local st = type(adapter) == "table" and adapter._st or nil
        return within(num, st, true, effRun, id, adapter, user, target, move, moveId, moveCtx, ...)
      end
    end
  end
  hub.classes = opts.classes or hub.classes or {}
  hub.enabled = opts.enabled or hub.enabled or function() return false end
  return hub
end

return Split
