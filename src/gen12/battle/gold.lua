-- Gold / Silver / Crystal's side of the mechanics layer (src/gen12/mech/core.lua): the adapter a
-- mechanic talks to, and the move_effects record a mechanic becomes.
--
-- Gold's battle is src/battle/gen2/Battle.lua: the battlers ARE the mon tables (hp, maxHp, stats
-- with split specials, status "burn" / "paralyze" / "poison" / "toxic" / "sleep" / "freeze"),
-- their volatile state hangs off Battle:volatile(mon) (dropped at a switch and at the end), stat
-- stages are per SIDE (battle.stages[side]), and everything the screen shows is an emitted event
-- (message, damage, heal, stage ...). A move whose effect has a move_effects record with `run` is
-- handed to that run after Protect and the Fly / Dig check (Battle:useMove), so every mechanic is
-- a "primary" record here: it rolls its own accuracy and lands its hits through Battle:hitOnce
-- (the cart's formula, held items, weather, screens; `power` overridable).
--
-- Our state: a battler's in volatile(mon).__ndx (gone with the volatile), a side's in
-- battle.__ndxSides[side], the field's in battle.__ndxField.

local Gold = {}

local GoldA = {}
GoldA.__index = GoldA

local STAGE = { attack = "attack", defense = "defense", speed = "speed", spAtk = "specialAttack",
  spDef = "specialDefense", accuracy = "accuracy", evasion = "evasion" }
local STAT = { attack = "attack", defense = "defense", speed = "speed", spAtk = "specialAttack",
  spDef = "specialDefense" }
local STATUS_OUT = { burn = "BRN", paralyze = "PAR", poison = "PSN", toxic = "TOX", sleep = "SLP",
  freeze = "FRZ" }
local AILMENT = { BURN = "burn", PARALYSIS = "paralyze", POISON = "poison", TOXIC = "toxic",
  SLEEP = "sleep", FREEZE = "freeze", CONFUSION = "confuse" }
local ORDER = { "attack", "defense", "spAtk", "spDef", "speed", "accuracy", "evasion" }
local WIDTH = 18

local function rand(random, n)
  if random then return random(n) end
  return math.random(n) - 1
end

-- 18 columns, the battle text box's width (the cart breaks every line itself)
function Gold.wrap(text)
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    while #line > WIDTH do
      local cut = line:sub(1, WIDTH + 1):match("^.*() ")
      if not cut or cut <= 1 then cut = WIDTH + 1 end
      out[#out + 1] = line:sub(1, cut - 1)
      line = line:sub(cut):gsub("^ +", "")
    end
    out[#out + 1] = line
  end
  return table.concat(out, "\n")
end

-- the adapter for one battle (kept on it); deps: { require, core, types }
function Gold.adapter(battle, deps)
  local A = rawget(battle, "__ndxA")
  if A and A.core == deps.core then return A end
  A = setmetatable({ battle = battle, gen = 2, core = deps.core, deps = deps,
    Strings = deps.require("src.core.Strings"), Damage = deps.require("src.battle.gen2.Damage") }, GoldA)
  battle.__ndxA = A
  return A
end

-- ------------------------------------------------------------------ who and where
function GoldA:name(b) return self.battle:battlerName(b) end
function GoldA:foe(b) local bt = self.battle; return b == bt.player and bt.enemy or bt.player end
function GoldA:sideName(b) return self.battle:sideOf(b) end
function GoldA:side(b)
  local name = type(b) == "string" and b or self:sideName(b)
  local sides = rawget(self.battle, "__ndxSides")
  if not sides then sides = { player = {}, enemy = {} }; self.battle.__ndxSides = sides end
  return sides[name]
end
function GoldA:field()
  local f = rawget(self.battle, "__ndxField")
  if not f then f = {}; self.battle.__ndxField = f end
  return f
end
function GoldA:vol(b)
  local state = self.battle:volatile(b)
  local v = state.__ndx
  if not v then v = {}; state.__ndx = v end
  return v
end
function GoldA:battlers() return self.battle.player, self.battle.enemy end
function GoldA:isWild() return not self.battle.trainer end

-- ------------------------------------------------------------------ facts
function GoldA:hp(b) return b.hp or 0 end
function GoldA:maxHp(b) return b.maxHp or (b.stats and b.stats.hp) or 1 end
function GoldA:level(b) return b.level or 1 end
function GoldA:species(b) return b.species end
function GoldA:mon(b) return b end
function GoldA:stat(b, s) return (b.stats and b.stats[STAT[s] or s]) or 1 end
function GoldA:stage(b, s)
  local st = self.battle.stages[self:sideName(b)]
  return (st and st[STAGE[s] or s]) or 0
end
function GoldA:setStage(b, s, v)
  self.battle.stages[self:sideName(b)][STAGE[s] or s] = math.max(-6, math.min(6, v))
end
function GoldA:types(b)
  local out = {}
  for _, t in ipairs(self.battle:battlerTypes(b) or {}) do
    local name = tostring(t):gsub("_TYPE$", "")
    local seen = false
    for _, x in ipairs(out) do if x == name then seen = true end end
    if not seen then out[#out + 1] = name end
  end
  return out
end
function GoldA:hasType(b, name)
  for _, t in ipairs(self:types(b)) do if t == name then return true end end
  return false
end
function GoldA:setTypes(b, list)
  local Types = self.deps.types
  local out = {}
  for i, t in ipairs(list) do out[i] = Types and Types.cartId(t) or t end
  if #out == 1 then out[2] = out[1] end
  self:vol(b).types = out
end
function GoldA:status(b) return STATUS_OUT[b.status] end
function GoldA:hasSub(b) return (self.battle:volatile(b).substitute or 0) > 0 end
function GoldA:turn() return self.battle.turn or 0 end
function GoldA:speed(b) return self.battle:effectiveSpeed(b) end
function GoldA:record(b) return self.battle.data.pokemon[b.species] end
function GoldA:dex(b) local r = self:record(b); return r and (r.baseDex or r.dex) end
function GoldA:weight(b) return self.core:weight(self:record(b), b.species) end
function GoldA:friendship(b) return b.happiness or 70 end
function GoldA:item(b) return b.item end
function GoldA:setItem(b, id) b.item = id end
function GoldA:itemName(id)
  local d = id and self.battle:itemDef(id)
  return (d and d.name) or (id and tostring(id):gsub("_", " ")) or ""
end
function GoldA:dvs(b) return b.dvs or {} end
function GoldA:moves(b) return b.moves or {} end
-- the weather: Gold's own rain / sun / sandstorm (battle.weather: its damage, its turns, its
-- screen), and our hail / snow beside it (one weather at a time)
local NATIVE_WEATHER = { rain = "rain", sun = "sun", sand = "sandstorm" }
local FROM_NATIVE = { rain = "rain", sun = "sun", sandstorm = "sand" }
function GoldA:weather()
  local w = FROM_NATIVE[self.battle.weather or ""]
  if w then return w end
  local f = self:field().weather
  return f and f.kind or nil
end
function GoldA:setWeather(kind, turns, text)
  local native = NATIVE_WEATHER[kind]
  if native then
    self:field().weather = nil
    self.battle.weather, self.battle.weatherTurns = native, turns or 5
    self.battle:emit({ kind = "weather", weather = native, text = text })
  else
    self.battle.weather, self.battle.weatherTurns = nil, 0
    self:field().weather = { kind = kind, turns = turns or 5 }
    if text then self:say(text) end
  end
end
function GoldA:clearWeather()
  self.battle.weather, self.battle.weatherTurns = nil, 0
  self:field().weather = nil
end
function GoldA:nativeWeather(kind) return NATIVE_WEATHER[kind] ~= nil end
-- a move record's priority as Gold orders it (by its effect; ours by their own)
function GoldA:basePriority(move)
  if not move then return 0 end
  return self.battle:movePriority(move.id) or 0
end
function GoldA:typeEff(attackType, defendType)
  local Types = self.deps.types
  local a = Types and Types.cartId(attackType) or attackType
  local d = Types and Types.cartId(defendType) or defendType
  return self.Damage.typeMultiplier(a, { d }, nil)
end
function GoldA:effectiveness(typeName, b)
  local Types = self.deps.types
  local t = Types and Types.cartId(typeName) or typeName
  return self.Damage.typeMultiplier(t, self.battle:battlerTypes(b), self.battle:matchupsAgainst(b))
end
function GoldA:category(move)
  local by = self.core.moveCategory and self.core.moveCategory(move)
  if by then return by end
  local chart = self.battle.data.type_chart
  return self.Damage.isPhysical(move.type, chart and chart.types) and "physical" or "special"
end
function GoldA:callMove(u, t, id)
  local bt = self.battle
  bt.copyDepth = (bt.copyDepth or 0) + 1
  local ok, err = pcall(bt.useMove, bt, u, t, id)
  bt.copyDepth = bt.copyDepth - 1
  if not ok then error(err, 0) end
end
function GoldA:party(b)
  local bt = self.battle
  if bt:sideOf(b) == "player" then return bt.party or { b } end
  return bt.enemyParty or { b }
end
-- the party Pokemon that could come in for this battler (index, mon), or nil
function GoldA:replacement(b, random)
  local bt = self.battle
  local player = bt:sideOf(b) == "player"
  if not player and not bt.trainer then return nil end
  local party = player and bt.party or bt.enemyParty or {}
  local pool = {}
  for i, mon in ipairs(party) do
    if mon ~= b and (mon.hp or 0) > 0 and not mon.isEgg then pool[#pool + 1] = i end
  end
  if #pool == 0 then return nil end
  local i = random and pool[self:rng(#pool) + 1] or pool[1]
  return i, party[i]
end

-- switch this battler out mid-turn, through Gold's own switch (its events, Spikes, the new
-- side's empty stages); opts: random, carry (Baton Pass: stages and the volatile go with it)
function GoldA:switchOut(b, opts)
  opts = opts or {}
  local bt = self.battle
  local i, mon = self:replacement(b, opts.random)
  if not mon then return false end
  local side = bt:sideOf(b)
  local stages = opts.carry and bt.stages[side] or nil
  local vol = opts.carry and bt:volatile(b) or nil
  local ok
  if side == "player" then ok = bt:switch(i) else ok = bt:switchEnemy(i) end
  if ok and opts.carry then
    local now = side == "player" and bt.player or bt.enemy
    bt.stages[side] = stages
    now.volatile = vol
  end
  return ok and true or false
end
function GoldA:chosen(b)
  local c = self:field().chosen
  return c and c[self:sideName(b)] or nil
end
function GoldA:lastMove(b) return self.battle:volatile(b).lastMove end
function GoldA:moveDef(id) return self.battle:moveDef(id) end
function GoldA:moveType(m) return (tostring(m.type or ""):gsub("_TYPE$", "")) end

-- ------------------------------------------------------------------ chance
function GoldA:rng(n) return rand(self.battle.random, n or 256) end
function GoldA:chance(pct)
  pct = tonumber(pct) or 100
  if pct >= 100 then return true end
  return rand(self.battle.random, 256) < math.floor(pct * 256 / 100)
end

-- ------------------------------------------------------------------ text
function GoldA:text(fmt, ...) return Gold.wrap(self.Strings(fmt, ...)) end
function GoldA:say(text) self.battle:emit({ kind = "message", text = text }) end
function GoldA:failText() return self.Strings("But it failed!") end

-- ------------------------------------------------------------------ changes
function GoldA:stages(b, t, opts)
  opts = opts or {}
  local fromFoe = opts.from ~= nil and opts.from ~= b
  local any = false
  for _, s in ipairs(ORDER) do
    local d = t[s]
    if d and d ~= 0 then
      local ok
      if fromFoe then
        ok = self.battle:changeStageAgainstMist(opts.from, b, STAGE[s], d)
      else
        ok = self.battle:changeStage(b, STAGE[s], d)
      end
      if ok then any = true end
    end
  end
  return any
end
function GoldA:ailment(b, name, opts)
  opts = opts or {}
  local s = AILMENT[name]
  if not s then return false end
  if s == "confuse" then return self.battle:applyConfusion(b, nil, opts.from) and true or false end
  return self.battle:applyStatus(b, s, opts.from, { secondary = opts.secondary, primary = not opts.secondary,
    moveType = opts.moveType }) and true or false
end
function GoldA:confuse(b, opts) return self:ailment(b, "CONFUSION", opts) end
function GoldA:cure(b) b.status, b.statusTurns, b.toxicCounter = nil, nil, nil end
function GoldA:flinch(b)
  if self.battle.flinch then return self.battle:flinch(b) end
  self.battle:volatile(b).flinched = true
end
function GoldA:damage(b, n, opts)
  n = math.max(0, math.floor(n))
  local dealt = math.min(n, b.hp or 0)
  b.hp = (b.hp or 0) - dealt
  if dealt > 0 then
    self.battle:emit({ kind = "damage", side = self:sideName(b), amount = dealt, hp = b.hp, anim = false })
  end
  if opts and opts.text then self:say(opts.text) end
  return dealt
end
function GoldA:heal(b, n, opts)
  if self.core.hooks.noHeal and self.core:ask("noHeal", self, b) then return 0 end
  local healed = self.battle:heal(b, math.max(0, math.floor(n)))
  if opts and opts.text then
    self:say(type(opts.text) == "string" and opts.text or self:text("%s regained health!", self:name(b)))
  end
  return healed
end
function GoldA:drain(u, t, n)
  if self:hp(u) >= self:maxHp(u) then return 0 end
  if self.core.hooks.noHeal and self.core:ask("noHeal", self, u) then return 0 end
  if self.core.hooks.drainHeal then n = self.core:fold("drainHeal", n, self, u) end
  local healed = self.battle:heal(u, n)
  self:say(self:text("%s's energy was drained!", self:name(t)))
  return healed
end
function GoldA:recoil(u, n)
  self:damage(u, math.max(1, math.floor(n)))
  self:say(self:text("%s is hit with recoil!", self:name(u)))
end

-- ------------------------------------------------------------------ the record a mechanic becomes
function Gold.record(spec, deps)
  local Strings = deps.require("src.core.Strings")
  return {
    kind = "primary",
    run = function(self, attacker, defender, def, moveId, sureHit)
      local A = Gold.adapter(self, deps)
      local name = self:battlerName(attacker)
      if spec.kind == "status" then
        if spec.aimed and not sureHit and not self:accuracyRoll(def, attacker, defender) then
          self:markMissed()
          A:say(Strings("%s's attack missed!", name))
          return
        end
        local result = spec.run(A, attacker, defender, def)
        if result == false then
          self:markMissed()
          A:say(A:failText())
        elseif result == nil then
          self:markMissed()
        end
        return
      end

      if spec.fail then
        local r = spec.fail(A, attacker, defender, def)
        if r then
          self:markMissed()
          if type(r) ~= "string" then A:say(A:failText()) elseif r ~= "" then A:say(r) end
          return
        end
      end
      if not (sureHit or spec.sureHit) and not self:accuracyRoll(def, attacker, defender) then
        self:markMissed()
        A:say(Strings("%s's attack missed!", name))
        if spec.onMiss then spec.onMiss(A, attacker, defender, def, "accuracy") end
        return
      end
      local count = 1
      if spec.hits then
        count = type(spec.hits) == "number" and spec.hits or (spec.hits(A, attacker, defender, def) or 1)
      end
      local total, landed, hadSub = 0, 0, A:hasSub(defender)
      for _ = 1, count do
        if (defender.hp or 0) <= 0 or (attacker.hp or 0) <= 0 then break end
        local dealt, info
        if spec.fixed then
          local mult = A.Damage.typeMultiplier(def.type, self:battlerTypes(defender),
            self:matchupsAgainst(defender))
          if mult == 0 then
            self:markMissed()
            A:say(Strings("It doesn't affect\n%s!", self:battlerName(defender)))
            if spec.onMiss then spec.onMiss(A, attacker, defender, def, "immune") end
            return
          end
          local n = spec.fixed(A, attacker, defender, def)
          if not n then
            self:markMissed()
            A:say(A:failText())
            return
          end
          dealt = self:dealDamage(attacker, defender, math.max(1, math.floor(n)), { move = def, moveId = moveId })
        else
          local power
          if spec.power then
            power = math.max(1, math.floor(spec.power(A, attacker, defender, def) or def.power))
          end
          local hitDef = def
          if spec.type then
            local t = spec.type(A, attacker, defender, def)
            if t then
              hitDef = {}
              for k, v in pairs(def) do hitDef[k] = v end
              hitDef.type = deps.types and deps.types.cartId(t) or t
            end
          end
          local crit = spec.crit
          if type(crit) == "function" then crit = crit(A, attacker, defender, def) end
          self.__ndxCalc = { stats = spec.stats, crit = crit, mult = spec.mult, A = A, user = attacker,
            target = defender, def = hitDef,
            cap = spec.cap and not A:hasSub(defender) and spec.cap(A, attacker, defender, def) or nil }
          local ok, a, b = pcall(self.hitOnce, self, attacker, defender, hitDef, { power = power, moveId = moveId })
          self.__ndxCalc = nil
          if not ok then error(a, 0) end
          dealt, info = a, b
          if info and info.effectiveness == 0 then
            if spec.onMiss then spec.onMiss(A, attacker, defender, def, "immune") end
            return
          end
        end
        total = total + (dealt or 0)
        landed = landed + 1
        if hadSub and not A:hasSub(defender) then break end
      end
      if count > 1 and landed > 0 then A:say(Strings("Hit %d times!", landed)) end
      if spec.after then spec.after(A, attacker, defender, def, total) end
      if spec.secondary and (defender.hp or 0) > 0 and total > 0 and not hadSub then
        spec.secondary(A, attacker, defender, def, total)
      end
      self:heldFlinch(attacker, defender, def, total)
    end,
  }
end

-- ------------------------------------------------------------------ seams (once per mod load)
-- battle.crit: a move that always crits (its __ndxCalc.crit). battle.damage: `stats` (Psyshock,
-- Body Press, Foul Play, Sacred Sword) writes the stats the move reads into the slots Gold's
-- formula reads (the move's type picks physical or special), and `mult` scales the finished
-- number (Collision Course).
function Gold.installSeams(mod, deps)
  local Damage = deps.require("src.battle.gen2.Damage")

  -- the formula's inputs with the stats a move reads put in place (copies: the stage tables
  -- are the battle's own)
  local function placeStats(c, want)
    local battle, o = c.battle, c.opts
    local physical = Damage.isPhysical(c.move.type, battle.data.type_chart and battle.data.type_chart.types)
    local atkSlot = physical and "attack" or "specialAttack"
    local defSlot = physical and "defense" or "specialDefense"
    local function stagesOf(mon)
      local copy = {}
      for k, v in pairs(battle.stages[battle:sideOf(mon)] or {}) do copy[k] = v end
      return copy
    end
    if want.attack then
      local from = want.from == "target" and c.target or c.user
      local st = stagesOf(c.user)
      st[atkSlot] = (battle.stages[battle:sideOf(from)] or {})[STAGE[want.attack]] or 0
      o.attacker.stages = st
      o.attacker[atkSlot] = (from.stats or {})[STAT[want.attack]] or o.attacker[atkSlot]
    end
    if want.defense or want.ignoreDefenseStages then
      local st = stagesOf(c.target)
      if want.defense then
        st[defSlot] = (battle.stages[battle:sideOf(c.target)] or {})[STAGE[want.defense]] or 0
        o.defender[defSlot] = (c.target.stats or {})[STAT[want.defense]] or o.defender[defSlot]
      end
      if want.ignoreDefenseStages then st[defSlot] = 0 end
      o.defender.stages = st
    end
  end

  mod.hooks:wrap("battle.crit", function(nextFn, c)
    local calc = c and c.battle and rawget(c.battle, "__ndxCalc")
    if calc and calc.crit then return true end
    -- a critical hit the field forbids (core "noCrit": Lucky Chant)
    if c and c.battle and c.attacker then
      local A = Gold.adapter(c.battle, deps)
      if deps.core.hooks.noCrit and deps.core:ask("noCrit", A, c.attacker, A:foe(c.attacker)) then return false end
      if deps.core.hooks.forceCrit and deps.core:ask("forceCrit", A, c.attacker) then return true end
    end
    return nextFn(c)
  end)
  local core = deps.core
  -- before the formula: an immunity the field gives (core "immune"), types a hit ignores (core
  -- "dropTypes"), the move's type this time (core "moveType"), a battler's stats as moves left
  -- them (A:vol(b).statOver)
  mod.hooks:wrap("battle.damage", function(nextFn, c)
    if not (c and c.battle and c.opts) then return nextFn(c) end
    local A = Gold.adapter(c.battle, deps)
    local o = c.opts
    if core.hooks.immune and core:ask("immune", A, c.user, c.target, c.move) then
      return 0, { effectiveness = 0, typeMult = 0 }
    end
    if core.hooks.moveType then
      local t = core:ask("moveType", A, c.user, c.move)
      if t then o.moveType = deps.types and deps.types.cartId(t) or t end
    end
    if core.hooks.dropTypes then
      local drop = core:ask("dropTypes", A, c.user, c.target, c.move)
      if drop and o.defender and o.defender.types then
        local keep = {}
        for _, t in ipairs(o.defender.types) do
          if not drop[(tostring(t):gsub("_TYPE$", ""))] then keep[#keep + 1] = t end
        end
        if #keep == 0 then keep[1] = deps.types and deps.types.cartId("NORMAL") or "NORMAL" end
        o.defender.types = keep
      end
    end
    local function over(mon, side, keys)
      local v = mon and mon.volatile and mon.volatile.__ndx
      local s = v and v.statOver
      if s and side then
        for stat, slot in pairs(keys) do if s[stat] then side[slot] = s[stat] end end
      end
    end
    over(c.user, o.attacker, { attack = "attack", spAtk = "specialAttack" })
    over(c.target, o.defender, { defense = "defense", spDef = "specialDefense" })
    -- physical / special by the move (option move_split): Gold picks by type, so the class's
    -- stats go where the type's formula looks
    local by = core.moveCategory and core.moveCategory(c.move)
    if by and o.attacker and o.defender then
      local typePhysical = A.Damage.isPhysical(o.moveType or c.move.type, o.types)
      if (by == "physical") ~= typePhysical then
        local function swapped(stages, a, b)
          local copy = {}
          for k, v in pairs(stages or {}) do copy[k] = v end
          copy[a], copy[b] = (stages or {})[b] or 0, (stages or {})[a] or 0
          return copy
        end
        o.attacker.attack, o.attacker.specialAttack = o.attacker.specialAttack, o.attacker.attack
        o.attacker.stages = swapped(o.attacker.stages, "attack", "specialAttack")
        o.defender.defense, o.defender.specialDefense = o.defender.specialDefense, o.defender.defense
        o.defender.stages = swapped(o.defender.stages, "defense", "specialDefense")
      end
    end
    return nextFn(c)
  end)
  mod.hooks:wrap("battle.damage", function(nextFn, c)
    local calc = c and c.battle and rawget(c.battle, "__ndxCalc")
    if not calc then
      local dmg, info = nextFn(c)
      -- every hit: the multipliers the field, abilities and items put on it
      if c and c.battle and core.hooks.damageMult and dmg and dmg > 0 then
        local eff = type(info) == "table" and (info.effectiveness or info.typeMult) or 10
        if eff > 0 then
          local A = Gold.adapter(c.battle, deps)
          local k = core:fold("damageMult", 1, A, c.user, c.target, c.move, { typeMult = eff })
          if k ~= 1 then dmg = math.max(1, math.floor(dmg * k)) end
        end
      end
      if c and c.battle and core.hooks.damageCap and dmg and dmg > 0 then
        local A = Gold.adapter(c.battle, deps)
        if not A:hasSub(c.target) then
          local most = core:ask("damageCap", A, c.user, c.target, c.move, dmg)
          if most then dmg = math.max(0, math.min(dmg, most)) end
        end
      end
      return dmg, info
    end
    if calc.stats then placeStats(c, calc.stats) end
    local dmg, info = nextFn(c)
    if core.hooks.damageMult and dmg and dmg > 0 then
      local eff = type(info) == "table" and (info.effectiveness or info.typeMult) or 10
      if eff > 0 then
        local k = core:fold("damageMult", 1, calc.A, calc.user, calc.target, calc.def, { typeMult = eff })
        if k ~= 1 then dmg = math.max(1, math.floor(dmg * k)) end
      end
    end
    if calc.mult and dmg and dmg > 0 then
      local eff = type(info) == "table" and (info.effectiveness or info.typeMult) or 10
      if eff > 0 then
        local k = calc.mult(calc.A, calc.user, calc.target, calc.def, { typeMult = eff })
        if k and k ~= 1 then dmg = math.max(1, math.floor(dmg * k)) end
      end
    end
    if calc.cap and dmg then dmg = math.max(0, math.min(dmg, calc.cap)) end
    if core.hooks.damageCap and dmg and dmg > 0 and calc.A and not calc.A:hasSub(calc.target) then
      local most = core:ask("damageCap", calc.A, calc.user, calc.target, calc.def, dmg)
      if most then dmg = math.max(0, math.min(dmg, most)) end
    end
    return dmg, info
  end)

  -- once per process (games switch in-process): Gold orders moves by their EFFECT's priority, so
  -- a move on our records answers its own; a type change made by a move (Soak, Burn Up) is the
  -- battler's types until it switches out (volatile(mon).__ndx.types)
  -- a move that never misses this time (core "accuracy": Lock-On)
  local function roll(nextFn, c)
    if c and c.battle and core.hooks.accuracy then
      local r = core:ask("accuracy", Gold.adapter(c.battle, deps), c.user, c.target, c.move)
      if r ~= nil then return r end
    end
    -- core "accuracyScale" (Compound Eyes, Hustle) scales the move's accuracy for this roll
    if c and c.battle and core.hooks.accuracyScale and (c.accuracy or c.accuracyRaw) then
      local k = core:fold("accuracyScale", 1, Gold.adapter(c.battle, deps), c.user, c.target, c.move)
      if k ~= 1 then
        if c.accuracyRaw then c.accuracyRaw = math.max(0, math.min(255, math.floor(c.accuracyRaw * k))) end
        if c.accuracy then c.accuracy = math.max(0, math.min(100, math.floor(c.accuracy * k))) end
      end
    end
    return nextFn(c)
  end
  -- core "missed" (Blunder Policy) when the roll fails
  mod.hooks:wrap("battle.accuracy", function(nextFn, c)
    local hit = roll(nextFn, c)
    if hit == false and c and c.battle and core.hooks.missed then
      pcall(core.fire, core, "missed", Gold.adapter(c.battle, deps), c.user, c.target, c.move)
    end
    return hit
  end)

  -- who moves first: priority and Speed as the field and abilities change them (Core:order)
  mod.hooks:wrap("battle.turn_order", function(nextFn, a, aMove, b, bMove, c)
    local battle = c and c.battle
    if battle and battle.player == a then
      local first = core:order(Gold.adapter(battle, deps), a, aMove, b, bMove)
      if first ~= nil then return first end
    end
    return nextFn(a, aMove, b, bMove, c)
  end)

  local Battle = deps.require("src.battle.gen2.Battle")
  local hub = Battle.__ndxMech
  if not hub then
    hub = {}
    Battle.__ndxMech = hub
    local movePriority, battlerTypes = Battle.movePriority, Battle.battlerTypes
    local betweenTurnEffects, useMove = Battle.betweenTurnEffects, Battle.useMove
    Battle.movePriority = function(self, moveId, ...)
      local def = moveId and self:moveDef(moveId)
      if def and tostring(def.effect or ""):find("^NDX_M_") then return def.priority or 0 end
      return movePriority(self, moveId, ...)
    end
    Battle.battlerTypes = function(self, mon, ...)
      local v = mon and mon.volatile and mon.volatile.__ndx
      if v and v.types then return v.types end
      return battlerTypes(self, mon, ...)
    end
    -- the end of the turn (core "endTurn"), after Gold's own; then any faint it caused
    Battle.betweenTurnEffects = function(self, ...)
      local a, b = betweenTurnEffects(self, ...)
      if hub.endTurn and not self.over then
        local ok, err = pcall(hub.endTurn, self)
        if not ok and hub.log then hub.log:warn("move mechanics: end of turn failed: %s", tostring(err)) end
        if ((self.player and self.player.hp or 1) <= 0 or (self.enemy and self.enemy.hp or 1) <= 0) then
          self:resolveFaints(true)
        end
      end
      return a, b
    end
    -- the player's switch, refused while a move or the field holds it (core "trapped")
    local switchLocked = Battle.switchLocked
    Battle.switchLocked = function(self, ...)
      if switchLocked(self, ...) then return true end
      if hub.trapped and self.player then
        local ok, r = pcall(hub.trapped, self, self.player)
        if ok and r then return true end
      end
      return false
    end
    -- a status the field or an ability stops (core "blockStatus")
    local applyStatus, applyConfusion = Battle.applyStatus, Battle.applyConfusion
    Battle.applyStatus = function(self, mon, status, source, ...)
      if hub.gate and mon and not mon.status and status ~= "confuse" then
        local ok, r = pcall(hub.gate, self, mon, status, source)
        if ok and r then return false end
      end
      return applyStatus(self, mon, status, source, ...)
    end
    Battle.applyConfusion = function(self, mon, turns, source, ...)
      if hub.gate and mon then
        local ok, r = pcall(hub.gate, self, mon, "confuse", source)
        if ok and r then return false end
      end
      return applyConfusion(self, mon, turns, source, ...)
    end
    -- after a move (core "afterMove"): what a Protect variant does to the attacker
    Battle.useMove = function(self, attacker, defender, moveId, ...)
      -- before the move (core "beforeMove"): stopped with a line, or another move / user
      if hub.before and attacker and moveId then
        local okB, r = pcall(hub.before, self, attacker, defender, moveId)
        if okB and r ~= nil then
          if type(r) == "string" then
            if r ~= "" then self:emit({ kind = "message", text = r }) end
            return
          end
          if type(r) == "table" then
            if r.id then moveId = r.id end
            if r.user then attacker, defender = r.user, r.target end
          end
        end
      end
      local a, b, c = useMove(self, attacker, defender, moveId, ...)
      if hub.afterMove then
        local ok, err = pcall(hub.afterMove, self, attacker, defender, moveId)
        if not ok and hub.log then hub.log:warn("move mechanics: after a move failed: %s", tostring(err)) end
      end
      return a, b, c
    end
  end
  hub.log = core.log
  local GATE_STATUS = { burn = "BRN", paralyze = "PAR", poison = "PSN", toxic = "TOX", sleep = "SLP",
    freeze = "FRZ", confuse = "CONFUSION" }
  hub.gate = function(battle, mon, status, source)
    if not core.hooks.blockStatus then return nil end
    local A = Gold.adapter(battle, deps)
    local r = core:ask("blockStatus", A, mon, GATE_STATUS[status] or status, { from = source })
    if type(r) == "string" and r ~= "" then A:say(r) end
    return r
  end
  hub.trapped = function(battle, mon)
    if not core.hooks.trapped then return nil end
    return core:ask("trapped", Gold.adapter(battle, deps), mon)
  end
  hub.before = function(battle, attacker, defender, moveId)
    if not core.hooks.beforeMove then return nil end
    local def = battle:moveDef(moveId)
    if not def then return nil end
    return core:ask("beforeMove", Gold.adapter(battle, deps), attacker, defender, def,
      (battle.copyDepth or 0) > 0)
  end
  hub.endTurn = function(battle) core:fire("endTurn", Gold.adapter(battle, deps)) end
  hub.afterMove = function(battle, attacker, defender, moveId)
    if core.hooks.afterMove then
      core:fire("afterMove", Gold.adapter(battle, deps), attacker, defender, moveId)
    end
  end
end

return Gold
