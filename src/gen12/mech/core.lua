-- The mechanics layer of the Gen 1 / Gen 2 path: what a newer move does, written once and run by
-- both games' battles through an adapter (src/gen12/battle/red.lua, src/gen12/battle/gold.lua).
--
-- A move row of data/gen12/moves.lua that the cart has no effect for carries `mech`
-- (tools/build_gen12.py): `rule` (the Gen 3 path's rule of that name), `extra` (the Gen 3
-- `extra` data), `g3` (a Gen 3 effect by its pokefirered name), `api` (PokeAPI only) or `doubles`
-- (a stand-in: no double battles here). Core:specFor(row) finds the mechanic: one written for the
-- move itself first, then its rule, its `extra`, its Gen 3 effect.
--
-- A mechanic ("spec") is a table; every function gets the battle's adapter A, the user u, the
-- target t and the move record m (this game's: id, type, power, accuracy, priority):
--   kind      "hit" (a damaging move) or "status"
--   hits:
--     fail(A,u,t,m) -> true            fails before the accuracy roll ("But it failed!")
--     sureHit = true                   never misses
--     power(A,u,t,m) -> n              its power this time (variable-power moves)
--     fixed(A,u,t,m) -> n | nil        fixed damage instead of the formula (nil: it fails)
--     crit = true                      always a critical hit
--     hits = n | fn(A,u,t,m) -> n      strikes
--     stats = { attack = "defense", defense = "defense", from = "target" }
--                                      which stats the formula reads (Psyshock, Body Press, Foul Play)
--     after(A,u,t,m,dealt)             after the damage, the user's side (also on a KO): recoil,
--                                      drain, its own stat changes, switching out
--     secondary(A,u,t,m,dealt)         after the damage when the target still stands and took some
--     onMiss(A,u,t,m, why)             missed or immune
--   status:
--     aimed = true                     rolls accuracy against the target (else it never misses)
--     selfOnly = true                  only touches the user (Protect does not stop it)
--     run(A,u,t,m) -> ok               false: "But it failed!" (unless it said why itself)
--   both:
--     priority(A,u,t,m) -> n           its priority this turn, when it varies
--
-- Passive behaviour (field state, abilities, items) hangs on hooks: Core:on(name, fn), called by
-- the adapters at the matching engine seam (see each adapter's header for the list).

local Core = {}
Core.__index = Core

-- the Gen 3 `extra` data's names -> ours (the adapters' A:stages / A:ailment use these)
Core.STATS = { "attack", "defense", "spAtk", "spDef", "speed", "accuracy", "evasion" }

-- the mechanic families, each a file returning function(core, opts) that defines its mechanics
-- (loaded by src/gen12/main.lua in this order)
Core.FAMILIES = {}

function Core.new(opts)
  opts = opts or {}
  local self = setmetatable({
    gen = opts.generation, log = opts.log,
    byMove = {}, rules = {}, g3 = {}, hooks = {},
    extra = {},                     -- move id -> the Gen 3 `extra` table (data/moves.lua)
  }, Core)
  for _, r in ipairs(opts.gen3 or {}) do
    if type(r.extra) == "table" then self.extra[r.id] = r.extra end
  end
  return self
end

-- ------------------------------------------------------------------ registering mechanics
function Core:move(id, spec) self.byMove[id] = spec end
function Core:rule(name, spec) self.rules[name] = spec end
function Core:effect(name, spec) self.g3[name] = spec end

-- a spec, or a function(row, core) -> spec (built per move: chances, amounts)
local function resolve(spec, row, core)
  if type(spec) == "function" then return spec(row, core) end
  return spec
end

-- the mechanic a move row runs on, or nil (it keeps its stand-in)
function Core:specFor(row)
  local mech = row.mech
  if not mech or mech.doubles then return nil end
  local spec = self.byMove[row.id]
  if spec then return resolve(spec, row, self) end
  if mech.rule and self.rules[mech.rule] then return resolve(self.rules[mech.rule], row, self) end
  if mech.extra and self.extra[row.id] then return Core.extraSpec(self.extra[row.id]) end
  if mech.g3 and self.g3[mech.g3] then return resolve(self.g3[mech.g3], row, self) end
  return nil
end

-- ------------------------------------------------------------------ hooks
function Core:on(name, fn)
  local list = self.hooks[name]
  if not list then list = {}; self.hooks[name] = list end
  list[#list + 1] = fn
end

-- every handler, in order; returns how many ran
function Core:fire(name, ...)
  local list = self.hooks[name]
  if not list then return 0 end
  for i = 1, #list do list[i](...) end
  return #list
end

-- the first non-nil answer
function Core:ask(name, ...)
  local list = self.hooks[name]
  if not list then return nil end
  for i = 1, #list do
    local v = list[i](...)
    if v ~= nil then return v end
  end
  return nil
end

-- every handler may change `value`; returns it
function Core:fold(name, value, ...)
  local list = self.hooks[name]
  if not list then return value end
  for i = 1, #list do
    local v = list[i](value, ...)
    if v ~= nil then value = v end
  end
  return value
end

-- ------------------------------------------------------------------ the `extra` data
-- data/moves.lua `extra` (the Gen 3 path's src/move_effects.lua data): stat changes on the user or
-- the foe, a status or flinch chance, draining and recoil, healing. The behaviour of the
-- src/gen12/move_fx.lua these replace, on the adapters.
--   { kind = "hit"|"status", self, foe, chance, ailment, ailmentChance, flinch, drain, heal,
--     healTarget }
function Core.extraSpec(e)
  if e.kind == "status" then
    local aimed = (e.foe ~= nil) or (e.ailment ~= nil) or e.healTarget == "foe"
    return {
      kind = "status", aimed = aimed or nil, selfOnly = (not aimed) or nil,
      run = function(A, u, t, m)
        local any = false
        if e.self and A:stages(u, e.self) then any = true end
        if e.foe and A:stages(t, e.foe, { from = u }) then any = true end
        if e.ailment and A:ailment(t, e.ailment, { from = u, moveType = m.type }) then any = true end
        if e.heal then
          local who = e.healTarget == "foe" and t or u
          if A:hp(who) >= A:maxHp(who) then
            if not any then A:say(A:text("%s's HP is full!", A:name(who))); return nil end
          else
            A:heal(who, math.max(1, math.floor(A:maxHp(who) * e.heal / 100)), { text = true })
            any = true
          end
        end
        return any
      end,
    }
  end
  return {
    kind = "hit",
    after = function(A, u, t, m, dealt)
      if (dealt or 0) <= 0 then return end
      if e.self and A:hp(u) > 0 and A:chance(e.chance) then A:stages(u, e.self) end
      if e.drain and A:hp(u) > 0 then
        if e.drain > 0 then
          A:drain(u, t, math.max(1, math.floor(dealt * e.drain / 100)))
        else
          A:recoil(u, math.max(1, math.floor(dealt * -e.drain / 100)))
        end
      end
    end,
    secondary = function(A, u, t, m)
      if e.foe and A:chance(e.chance) then A:stages(t, e.foe, { from = u, secondary = true }) end
      if e.ailment and A:chance(e.ailmentChance) then
        A:ailment(t, e.ailment, { from = u, secondary = true, moveType = m.type })
      end
      if e.flinch and A:chance(e.flinch) then A:flinch(t) end
    end,
  }
end

return Core
