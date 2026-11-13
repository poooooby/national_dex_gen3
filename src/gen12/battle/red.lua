-- Red / Blue / Yellow's side of the mechanics layer (src/gen12/mech/core.lua): the adapter a
-- mechanic talks to, and the move_effects record a mechanic becomes.
--
-- Red's battle is src/battle/BattleState.lua: battlers are tables { mon, stages, curTypes,
-- curStats, isPlayer, name, substituteHP, ... } made afresh at every send-out, its text goes into
-- a queue (sayNext), HP bars animate off drainNext, and a move runs through the merged
-- move_effects record (src/battle/EffectRegistry.lua's staged pipeline for a damaging move:
-- gate -> hitCount -> accuracy -> chooseDamage -> afterDamage -> run). Red has one SPECIAL: an Sp.
-- Atk effect is its Special when it attacks, an Sp. Def one when it defends (A:stages maps a
-- change of either to SPECIAL, Sp. Atk's first, as src/gen12/move_fx.lua did).
--
-- Our state lives on the battle's own tables, never the party mon (it would be saved): a
-- battler's in battler.__ndx (gone with the battler at a switch), a side's in
-- battle.__ndxSides[side], the field's in battle.__ndxField.

local Red = {}

local RedA = {}
RedA.__index = RedA

local STAGE = { attack = "attack", defense = "defense", speed = "speed", spAtk = "special",
  spDef = "special", special = "special", accuracy = "accuracy", evasion = "evasion" }
local STATUS_OUT = { BRN = "BRN", PAR = "PAR", SLP = "SLP", FRZ = "FRZ" }
local AILMENT = { BURN = "BRN", PARALYSIS = "PAR", POISON = "PSN", TOXIC = "PSN", SLEEP = "SLP",
  FREEZE = "FRZ" }
local WIDTH = 18

-- an 18-column battle text: each line of `text` broken at spaces (Red does not wrap)
function Red.wrap(text)
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
function Red.adapter(battle, deps)
  local A = rawget(battle, "__ndxA")
  if A and A.core == deps.core then return A end
  A = setmetatable({ battle = battle, gen = 1, core = deps.core, deps = deps,
    Strings = deps.require("src.core.Strings"), romText = deps.require("src.core.RomText"),
    MoveEffects = deps.require("src.battle.MoveEffects"),
    StatusRegistry = deps.require("src.battle.StatusRegistry"),
    TypeChart = deps.require("src.battle.TypeChart") }, RedA)
  battle.__ndxA = A
  return A
end

-- ------------------------------------------------------------------ who and where
function RedA:name(b) return b.isPlayer and b.name or self.Strings("Enemy %s", b.name) end
function RedA:foe(b) local bt = self.battle; return b == bt.player and bt.enemy or bt.player end
function RedA:sideName(b) return b.isPlayer and "player" or "enemy" end
function RedA:side(b)
  local name = type(b) == "string" and b or self:sideName(b)
  local sides = rawget(self.battle, "__ndxSides")
  if not sides then sides = { player = {}, enemy = {} }; self.battle.__ndxSides = sides end
  return sides[name]
end
function RedA:field()
  local f = rawget(self.battle, "__ndxField")
  if not f then f = {}; self.battle.__ndxField = f end
  return f
end
function RedA:vol(b)
  local v = rawget(b, "__ndx")
  if not v then v = {}; b.__ndx = v end
  return v
end
function RedA:battlers() return self.battle.player, self.battle.enemy end
function RedA:isWild() return self.battle.kind == "wild" end

-- ------------------------------------------------------------------ facts
function RedA:hp(b) return b.mon.hp or 0 end
function RedA:maxHp(b) return (b.mon.stats and b.mon.stats.hp) or b.mon.hp or 1 end
function RedA:level(b) return b.mon.level or 1 end
function RedA:species(b) return b.mon.species end
function RedA:mon(b) return b.mon end
-- a battle stat before stages: attack / defense / speed / spAtk / spDef (both are SPECIAL)
function RedA:stat(b, s)
  local cur = b.curStats or b.mon.stats or {}
  return cur[STAGE[s] or s] or 1
end
function RedA:stage(b, s) return (b.stages and b.stages[STAGE[s] or s]) or 0 end
function RedA:setStage(b, s, v)
  b.stages[STAGE[s] or s] = math.max(-6, math.min(6, v))
end
-- the battler's types now, in modern names (PSYCHIC_TYPE -> PSYCHIC, BIRD -> FLYING)
function RedA:types(b)
  local out = {}
  for _, t in ipairs(b.curTypes or {}) do
    local name = tostring(t):gsub("_TYPE$", "")
    if name == "BIRD" then name = "FLYING" end
    local seen = false
    for _, x in ipairs(out) do if x == name then seen = true end end
    if not seen then out[#out + 1] = name end
  end
  return out
end
function RedA:hasType(b, name)
  for _, t in ipairs(self:types(b)) do if t == name then return true end end
  return false
end
function RedA:setTypes(b, list)
  local Types = self.deps.types
  local out = {}
  for i, t in ipairs(list) do out[i] = Types and Types.cartId(t) or t end
  if #out == 1 then out[2] = out[1] end
  b.curTypes = out
end
-- BRN / PAR / PSN / TOX / SLP / FRZ, or nil
function RedA:status(b)
  local s = b.mon.status
  if s == "PSN" then return b.toxicCounter and "TOX" or "PSN" end
  return STATUS_OUT[s]
end
function RedA:hasSub(b) return b.substituteHP ~= nil end
function RedA:turn() return self.battle.turnCount or 0 end
function RedA:speed(b) return self.deps.require("src.battle.TurnOrder").effectiveSpeed(b) end
function RedA:record(b) return self.battle.data.pokemon[b.mon.species] end
function RedA:dex(b) local r = self:record(b); return r and (r.baseDex or r.dex) end
function RedA:weight(b) return self.core:weight(self:record(b), b.mon.species) end
-- Red's hidden friendship (src/gen12/evolutions.lua keeps it on the mon), else 70
function RedA:friendship(b)
  local bag = b.mon.extra and b.mon.extra.national_dex_gen3
  return (bag and bag.friendship) or 70
end
function RedA:item(b)
  local bag = b.mon.extra and b.mon.extra.national_dex_gen3
  return bag and bag.item or nil
end
function RedA:dvs(b) return b.mon.dvs or {} end
-- the battler's moves: { id, pp }
function RedA:moves(b) return b.curMoves or b.mon.moves or {} end
-- the weather (rain / sun / sand / hail / snow): Red has none of its own, so it is all ours
function RedA:weather() local w = self:field().weather; return w and w.kind or nil end
function RedA:setWeather(kind, turns, text)
  self:field().weather = { kind = kind, turns = turns or 5 }
  if text then self:say(text) end
end
function RedA:clearWeather() self:field().weather = nil end
-- does the game run this weather itself (its damage, its turns)?
function RedA:nativeWeather() return false end
-- a move record's priority as Red orders it (src/battle/TurnOrder.lua)
function RedA:basePriority(move)
  if not move then return 0 end
  if move.priority then return move.priority end
  return (move.id == "QUICK_ATTACK" and 1) or (move.id == "COUNTER" and -1) or 0
end
-- a type (modern name) against the battler: x10 (0, 5, 10, 20 ...)
function RedA:effectiveness(typeName, b)
  local Types = self.deps.types
  local t = Types and Types.cartId(typeName) or typeName
  return self.TypeChart.effectiveness(t, b.curTypes)
end
-- "physical" / "special" (Red: by the move's own category, else its type's)
function RedA:category(move)
  local c = move.category or self.TypeChart.category(move.type)
  return c == "special" and "special" or "physical"
end
-- another move, used by this one (Nature Power, Assist)
function RedA:callMove(u, t, id) self.battle:performMove(u, t, { id = id, pp = 1 }, true) end
-- the battler's party (mon tables)
function RedA:party(b)
  if b.isPlayer then return self.battle:playerPartyView() or { b.mon } end
  return self.battle.enemyParty or { b.mon }
end
-- the move this battler chose this turn (battle.turn_started), or nil
function RedA:chosen(b)
  local c = self:field().chosen
  return c and c[self:sideName(b)] or nil
end
function RedA:lastMove(b) return b.lastMove end
function RedA:moveDef(id) return self.battle.data.moves[id] end
function RedA:moveType(m) return (tostring(m.type or ""):gsub("_TYPE$", "")) end

-- ------------------------------------------------------------------ chance
function RedA:rng(n) return self.battle.rng(0, (n or 256) - 1) end
function RedA:chance(pct)
  pct = tonumber(pct) or 100
  if pct >= 100 then return true end
  return self.battle.rng(0, 255) < math.floor(pct * 256 / 100)
end

-- ------------------------------------------------------------------ text
function RedA:text(fmt, ...) return Red.wrap(self.Strings(fmt, ...)) end
-- a line of battle text: into the record's collected messages while one is being built, else
-- straight onto the queue
function RedA:say(text)
  local sink = rawget(self, "sinkList")
  if sink then sink[#sink + 1] = text else self.battle:sayNext(text) end
end
function RedA:sink() self.sinkList = {} end
function RedA:unsink() local s = self.sinkList or {}; self.sinkList = nil; return s end
function RedA:failText() return self.romText(self.battle.data, "_ButItFailedText", "But, it failed!") end

-- ------------------------------------------------------------------ changes
-- stat changes { attack = 1, spAtk = 2, ... } (the Gen 3 `extra` names); opts.from: the foe
-- causing them (Mist and Substitute stop those). Returns whether any landed.
function RedA:stages(b, t, opts)
  opts = opts or {}
  local list = {}
  local special = (t.spAtk and t.spAtk ~= 0) and t.spAtk or t.spDef
  for _, s in ipairs({ "attack", "defense", "speed" }) do
    if t[s] and t[s] ~= 0 then list[#list + 1] = { s, t[s] } end
  end
  if special and special ~= 0 then list[#list + 1] = { "special", special } end
  for _, s in ipairs({ "accuracy", "evasion" }) do
    if t[s] and t[s] ~= 0 then list[#list + 1] = { s, t[s] } end
  end
  local fromFoe = opts.from ~= nil and opts.from ~= b
  local any = false
  for _, c in ipairs(list) do
    local msgs = self.MoveEffects.changeStage(self.battle, b, c[1], c[2], fromFoe) or {}
    if not msgs.failed then any = true end
    if not (opts.secondary and msgs.failed) then
      for _, m in ipairs(msgs) do self:say(m) end
    end
  end
  return any
end

-- a status in the `extra` names (BURN, PARALYSIS, POISON, TOXIC, SLEEP, FREEZE, CONFUSION);
-- opts: from, secondary, moveType. Returns whether it landed.
function RedA:ailment(b, name, opts)
  opts = opts or {}
  if name == "CONFUSION" then return self:confuse(b, opts) end
  local s = AILMENT[name]
  if not s then return false end
  local msgs = self.StatusRegistry.inflict(self.battle, b, s, { secondary = opts.secondary,
    moveType = opts.moveType, source = opts.source, toxic = name == "TOXIC" or nil,
    from = opts.from or false }) or {}
  for _, m in ipairs(msgs) do self:say(m) end
  if name == "TOXIC" and #msgs > 0 and not b.toxicCounter then b.toxicCounter = 0 end
  return #msgs > 0
end
function RedA:confuse(b, opts)
  if b.confusedTurns or (b.substituteHP and opts and opts.from) then return false end
  if self.core.hooks.blockStatus then
    local r = self.core:ask("blockStatus", self, b, "CONFUSION", opts or {})
    if r then
      if type(r) == "string" and r ~= "" and not (opts and opts.secondary) then self:say(r) end
      return false
    end
  end
  b.confusedTurns = self.battle.rng(2, 5)
  self:say(self.romText(self.battle.data, "_BecameConfusedText", "%s\nbecame confused!", self:name(b)))
  return true
end
function RedA:cure(b) b.mon.status = nil; b.toxicCounter = nil end
function RedA:flinch(b) b.flinched = true end

-- HP lost to anything but the move's own hit (recoil, hazards, the weather): past a Substitute
function RedA:damage(b, n, opts)
  local mon = b.mon
  n = math.max(0, math.floor(n))
  local dealt = math.min(n, mon.hp)
  mon.hp = mon.hp - dealt
  if dealt > 0 then self.battle:drainNext(b, mon.hp) end
  if opts and opts.text then self:say(opts.text) end
  if mon.hp <= 0 then self.battle:onFaint(b) end
  return dealt
end
function RedA:heal(b, n, opts)
  local mon = b.mon
  local before = mon.hp
  mon.hp = math.min(self:maxHp(b), mon.hp + math.max(0, math.floor(n)))
  if mon.hp ~= before then self.battle:drainNext(b, mon.hp) end
  if opts and opts.text then
    self:say(type(opts.text) == "string" and opts.text
      or self.romText(self.battle.data, "_RegainedHealthText", "%s\nregained health!", self:name(b)))
  end
  return mon.hp - before
end
function RedA:drain(u, t, n)
  if self:hp(u) >= self:maxHp(u) then return 0 end
  local healed = self:heal(u, n)
  self:say(self.romText(self.battle.data, "_SuckedHealthText", "Sucked health from\n%s!", self:name(t)))
  return healed
end
function RedA:recoil(u, n) self.battle:applyRecoil(u, math.max(1, math.floor(n))) end

-- ------------------------------------------------------------------ the record a mechanic becomes
-- Red runs a status move's record as a "primary" (its messages returned), a damaging one as a
-- "full" record on EffectRegistry.runDamaging's stages.
function Red.record(spec, deps)
  local function adapter(ctx) return Red.adapter(ctx.battle, deps) end
  if spec.kind == "status" then
    return {
      kind = "primary", accuracyChecked = spec.aimed or nil,
      run = function(ctx)
        local A = adapter(ctx)
        A:sink()
        local okRun, result = pcall(spec.run, A, ctx.user, ctx.target, ctx.move)
        local msgs = A:unsink()
        if not okRun then error(result, 0) end
        if result == false or (result == nil and #msgs == 0) then
          if #msgs == 0 then msgs[1] = A:failText() end
          msgs.failed = true
        end
        return msgs
      end,
    }
  end

  local record = { kind = "full" }
  if spec.fail then
    -- true: "But, it failed!"; a string: that text instead ("" for none)
    record.gate = function(ctx)
      local A = adapter(ctx)
      local r = spec.fail(A, ctx.user, ctx.target, ctx.move)
      if not r then return true end
      if type(r) == "string" then return false, r ~= "" and r or nil end
      return false, A:failText()
    end
  end
  if spec.sureHit then record.neverMiss = true end
  if spec.hits then
    record.hitCount = function(ctx)
      if type(spec.hits) == "number" then return spec.hits end
      return spec.hits(adapter(ctx), ctx.user, ctx.target, ctx.move) or 1
    end
  end
  if spec.fixed or spec.power or spec.crit or spec.stats or spec.type or spec.mult or spec.cap then
    record.chooseDamage = function(ctx)
      local A, battle = adapter(ctx), ctx.battle
      local move = ctx.move
      if spec.fixed then
        local mult = A.TypeChart.effectiveness(move.type, ctx.target.curTypes)
        if mult == 0 then return 0, { crit = false, typeMult = 0 } end
        local n = spec.fixed(A, ctx.user, ctx.target, move)
        if not n then return nil, A:failText() end
        return math.max(1, math.floor(n)), { crit = false, typeMult = 10 }
      end
      local m = move
      if spec.power or spec.type then
        m = {}
        for k, v in pairs(move) do m[k] = v end
        if spec.power then
          m.power = math.max(1, math.floor(spec.power(A, ctx.user, ctx.target, move) or move.power))
        end
        if spec.type then
          local t = spec.type(A, ctx.user, ctx.target, move)
          if t then m.type = deps.types and deps.types.cartId(t) or t end
        end
      end
      local crit = spec.crit
      if type(crit) == "function" then crit = crit(A, ctx.user, ctx.target, move) end
      local dmg, info = battle:computeDamage(ctx.user, ctx.target, m, { rng = battle.rng,
        forceCrit = crit and true or nil, ndxStats = spec.stats })
      if spec.mult and dmg and dmg > 0 and info and (info.typeMult or 10) > 0 then
        local k = spec.mult(A, ctx.user, ctx.target, m, info)
        if k and k ~= 1 then dmg = math.max(1, math.floor(dmg * k)) end
      end
      if spec.cap and dmg and dmg > 0 and not ctx.target.substituteHP then
        local most = spec.cap(A, ctx.user, ctx.target, m)
        if most then dmg = math.max(0, math.min(dmg, most)) end
      end
      return dmg, info
    end
  end
  if spec.onMiss then
    record.onMiss = function(ctx, why) spec.onMiss(adapter(ctx), ctx.user, ctx.target, ctx.move, why) end
  end
  if spec.after then
    record.afterDamage = function(ctx, dealt)
      spec.after(adapter(ctx), ctx.user, ctx.target, ctx.move, tonumber(dealt) or 0)
    end
  end
  if spec.secondary then
    record.run = function(ctx)
      local A = adapter(ctx)
      if ctx.target.substituteHP or ctx.brokeSub then return {} end
      A:sink()
      local ok, err = pcall(spec.secondary, A, ctx.user, ctx.target, ctx.move, ctx.totalDealt or 0)
      local msgs = A:unsink()
      if not ok then error(err, 0) end
      return msgs
    end
  end
  return record
end

-- ------------------------------------------------------------------ seams (once per mod load)
-- battle.damage: `ndxStats` (Psyshock, Body Press, Foul Play) puts the stats the move reads into
-- the slots Red's formula reads (the move's category picks SPECIAL or ATTACK / DEFENSE), for the
-- one call.
function Red.installSeams(mod, deps)
  local TypeChart = deps.require("src.battle.TypeChart")
  local core = deps.core

  -- every hit: the multipliers the field, abilities and items put on it (core "damageMult"),
  -- and the most it may take (core "damageCap": Endure)
  mod.hooks:wrap("battle.damage", function(nextFn, c)
    local dmg, info = nextFn(c)
    if not (c and c.battle) or (c.opts and c.opts.typeless) then return dmg, info end
    if dmg and dmg > 0 and info and (info.typeMult or 10) > 0 then
      local A = Red.adapter(c.battle, deps)
      if core.hooks.damageMult then
        local k = core:fold("damageMult", 1, A, c.user, c.target, c.move, info)
        if k ~= 1 then dmg = math.max(1, math.floor(dmg * k)) end
      end
      if core.hooks.damageCap and not c.target.substituteHP then
        local most = core:ask("damageCap", A, c.user, c.target, c.move, dmg)
        if most then dmg = math.max(0, math.min(dmg, most)) end
      end
    end
    return dmg, info
  end)

  -- a critical hit the field forbids (core "noCrit": Lucky Chant); Red's crit ctx names only the
  -- attacker, so the battle is the one whose turn it is
  mod.hooks:wrap("battle.crit", function(nextFn, c)
    local A = core.lastAdapter
    if A and A.gen == 1 and core.hooks.noCrit and c and c.attacker then
      if core:ask("noCrit", A, c.attacker, A:foe(c.attacker)) then return false end
    end
    return nextFn(c)
  end)

  -- a charge turn the field skips (core "skipCharge": Solar Beam in the sun)
  mod.hooks:wrap("battle.charge_required", function(nextFn, c)
    if c and c.battle and core.hooks.skipCharge then
      if core:ask("skipCharge", Red.adapter(c.battle, deps), c.user, c.move) then return false end
    end
    return nextFn(c)
  end)

  -- a status the field or an ability stops (core "blockStatus" -> true or a line to say)
  local StatusRegistry = deps.require("src.battle.StatusRegistry")
  local sHub = StatusRegistry.__ndxMech
  if not sHub then
    sHub = {}
    StatusRegistry.__ndxMech = sHub
    local inflict = StatusRegistry.inflict
    StatusRegistry.inflict = function(battle, target, status, opts)
      if sHub.gate and battle and target and not target.mon.status then
        local ok, r = pcall(sHub.gate, battle, target, status, opts or {})
        if ok and r then return {} end
      end
      return inflict(battle, target, status, opts)
    end
  end
  sHub.gate = function(battle, target, status, opts)
    if not core.hooks.blockStatus then return nil end
    local A = Red.adapter(battle, deps)
    local s = (status == "PSN" and opts.toxic) and "TOX" or status
    if opts.from == nil then
      -- Red's own moves name no source: the battler whose move is landing on this one
      local cur = rawget(battle, "__ndxCur")
      if cur and cur.target == target and cur.user ~= target then
        local o = {}
        for k, v in pairs(opts) do o[k] = v end
        o.from, opts = cur.user, o
      end
    end
    local r = core:ask("blockStatus", A, target, s, opts)
    if type(r) == "string" and r ~= "" and not opts.secondary then A:say(r) end
    return r
  end

  -- who moves first: priority and Speed as the field and abilities change them (Core:order)
  mod.hooks:wrap("battle.turn_order", function(nextFn, a, aMove, b, bMove, c)
    local A = core.lastAdapter
    if A and A.gen == 1 and A.battle.player == a then
      local first = core:order(A, a, aMove, b, bMove)
      if first ~= nil then return first end
    end
    return nextFn(a, aMove, b, bMove, c)
  end)

  -- once per process: the end of the turn (core "endTurn", before the field residuals), and a
  -- move stopped before it lands (core "blocks": Protect) through a record whose `perform`
  -- replaces the move's own resolution right after "X used Y!"
  local BattleState = deps.require("src.battle.BattleState")
  local hub = BattleState.__ndxMech
  if not hub then
    hub = {}
    BattleState.__ndxMech = hub
    local applyFieldResiduals, performMove, effectRecord =
      BattleState.applyFieldResiduals, BattleState.performMove, BattleState.effectRecord
    BattleState.applyFieldResiduals = function(self, ...)
      if hub.endTurn then
        local ok, err = pcall(hub.endTurn, self)
        if not ok and hub.log then hub.log:warn("move mechanics: end of turn failed: %s", tostring(err)) end
      end
      return applyFieldResiduals(self, ...)
    end
    BattleState.performMove = function(self, user, target, moveInst, isCalled)
      local prev = rawget(self, "__ndxCur")
      self.__ndxCur = { user = user, target = target, moveInst = moveInst, isCalled = isCalled }
      local ok, err = pcall(performMove, self, user, target, moveInst, isCalled)
      self.__ndxCur = prev
      if not ok then error(err, 0) end
    end
    BattleState.effectRecord = function(self, effect)
      local rec = effectRecord(self, effect)
      local cur = rawget(self, "__ndxCur")
      if hub.block and cur and rec ~= nil then
        local ok, perform = pcall(hub.block, self, cur, rec)
        if ok and perform then
          return setmetatable({ perform = perform, callsMove = false }, { __index = rec })
        end
      end
      return rec
    end
  end
  hub.log = core.log
  hub.endTurn = function(battle) core:fire("endTurn", Red.adapter(battle, deps)) end
  hub.block = function(battle, cur, rec)
    if not core.hooks.blocks or rec.callsMove then return nil end
    local move = battle.data.moves[cur.moveInst.id]
    if not move or cur.user == cur.target then return nil end
    local aimed = (move.power or 0) > 0 or rec.accuracyChecked or rec.kind == "full"
    if not aimed then return nil end
    local A = Red.adapter(battle, deps)
    local handler = core:ask("blocks", A, cur.user, cur.target, move)
    if not handler then return nil end
    return function(ctx)
      battle:cancelMoveAnim()
      handler(A, cur.user, cur.target, move)
    end
  end
  local function slotOf(move)
    local category = move.category or TypeChart.category(move.type)
    return category == "special" and "special" or "attack", category == "special" and "special" or "defense"
  end
  mod.hooks:wrap("battle.damage", function(nextFn, c)
    local want = c and c.opts and c.opts.ndxStats
    if not want then return nextFn(c) end
    local user, target = c.user, c.target
    local atkSlot, defSlot = slotOf(c.move)
    local saved = {}
    local function put(who, slot, from, stat)
      saved[#saved + 1] = { who, slot, who.curStats[slot], who.stages[slot] }
      who.curStats[slot] = from.curStats[STAGE[stat] or stat]
      who.stages[slot] = from.stages[STAGE[stat] or stat] or 0
    end
    local ok, a, b = pcall(function()
      if want.attack then put(user, atkSlot, want.from == "target" and target or user, want.attack) end
      if want.defense then put(target, defSlot, target, want.defense) end
      if want.ignoreDefenseStages then
        saved[#saved + 1] = { target, defSlot, target.curStats[defSlot], target.stages[defSlot] }
        target.stages[defSlot] = 0
      end
      return nextFn(c)
    end)
    for i = #saved, 1, -1 do
      local s = saved[i]
      s[1].curStats[s[2]], s[1].stages[s[2]] = s[3], s[4]
    end
    if not ok then error(a, 0) end
    return a, b
  end)
end

return Red
