-- New move mechanics on Gen 1 / Gen 2: the newer moves that neither game has an effect for but
-- that data/moves.lua describes completely (`extra`, the Gen 3 path's src/move_effects.lua data:
-- stat changes on the user or the foe, a status or flinch chance, draining and recoil, healing)
-- become real moves here instead of stand-ins: Close Combat, Fire Fang, Nasty Plot, Shell Smash,
-- Draining Kiss, Flare Blitz... They are registered before the species, so the learnsets name them.
--
--   Red   one move_effects record per move ("NDX_FX_<move>"), run by Red's own effect pipeline:
--         a status move is a "primary" record (its accuracy checked when it aims at the foe); an
--         attack is a "full" record whose afterDamage does what happens even on a KO (the user's
--         stat changes, drain or recoil) and whose run does what needs the foe standing (the
--         foe's stat changes, the status, the flinch). Red's own helpers and texts: changeStage
--         ("X's ATTACK greatly rose!", Mist and Substitute), StatusRegistry.inflict (its
--         immunities), applyRecoil, drainNext. Red has one SPECIAL: Sp. Atk's change goes there,
--         else Sp. Def's.
--   Gold  an attack is a plain hit (EFFECT_NORMAL_HIT); Battle.useMove is wrapped (once per
--         process, our move ids only) to add the extra after the hit's own messages, when the
--         hit landed (the foe's HP or its Substitute went down). A status move has a
--         move_effects record of its own with Gold's helpers: changeStage /
--         changeStageAgainstMist, applyStatus, flinch, heal, and the cart's texts; one that only
--         touches the user is added to Effects.NO_CHECKHIT, as Gold's own stat-up moves are.
-- Chances roll on the battle's own generator (0-255 against the percentage of 256).
-- Each move borrows the animation of its first stand-in that is a cart move.

local MoveFx = {}

MoveFx.PREFIX = "NDX_FX_"

local GEN1_STATUS = { BURN = "BRN", PARALYSIS = "PAR", POISON = "PSN", TOXIC = "PSN", SLEEP = "SLP",
  FREEZE = "FRZ" }
local GEN2_STATUS = { BURN = "burn", PARALYSIS = "paralyze", POISON = "poison", TOXIC = "toxic",
  SLEEP = "sleep", FREEZE = "freeze", CONFUSION = "confuse" }
local ORDER = { "attack", "defense", "spAtk", "spDef", "speed", "accuracy", "evasion" }

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

-- the stat changes in this game's names, in order: { { stat, delta } }
function MoveFx.changes(gen, t)
  local out = {}
  if type(t) ~= "table" then return out end
  if gen == 1 then
    local special = (t.spAtk and t.spAtk ~= 0) and t.spAtk or t.spDef
    for _, s in ipairs({ "attack", "defense", "speed" }) do
      if t[s] and t[s] ~= 0 then out[#out + 1] = { s, t[s] } end
    end
    if special and special ~= 0 then out[#out + 1] = { "special", special } end
    for _, s in ipairs({ "accuracy", "evasion" }) do
      if t[s] and t[s] ~= 0 then out[#out + 1] = { s, t[s] } end
    end
    return out
  end
  local names = { spAtk = "specialAttack", spDef = "specialDefense" }
  for _, s in ipairs(ORDER) do
    if t[s] and t[s] ~= 0 then out[#out + 1] = { names[s] or s, t[s] } end
  end
  return out
end

-- a percentage against a 0-255 roll
local function hits(r, pct)
  pct = tonumber(pct) or 100
  if pct >= 100 then return true end
  return r < math.floor(pct * 256 / 100)
end

-- ------------------------------------------------------------------ Red
local function gen1Record(spec, require)
  local MoveEffects = require("src.battle.MoveEffects")
  local romText = require("src.core.RomText")
  local Strings = require("src.core.Strings")
  local function name(b) return b.isPlayer and b.name or Strings("Enemy %s", b.name) end
  local function failed(battle) return { romText(battle.data, "_ButItFailedText", "But, it failed!"), failed = true } end
  local function roll(battle, pct) return hits(battle.rng(0, 255), pct) end
  local function stages(battle, who, list, fromEnemy, out)
    local any = false
    for _, c in ipairs(list) do
      local msgs = MoveEffects.changeStage(battle, who, c[1], c[2], fromEnemy) or {}
      if not msgs.failed then any = true end
      for _, m in ipairs(msgs) do out[#out + 1] = m end
    end
    return any
  end
  local function confuse(battle, target, out)
    if target.confusedTurns or target.substituteHP then return false end
    target.confusedTurns = battle.rng(2, 5)
    out[#out + 1] = romText(battle.data, "_BecameConfusedText", "%s\nbecame confused!", name(target))
    return true
  end
  local function ailment(ctx, out)
    local target = ctx.target
    if spec.ailment == "CONFUSION" then return confuse(ctx.battle, target, out) end
    local s = GEN1_STATUS[spec.ailment]
    if not s then return false end
    local msgs = ctx.inflict(target, s, { secondary = spec.kind == "hit", moveType = ctx.move and ctx.move.type,
      source = ctx.move and ctx.move.id }) or {}
    for _, m in ipairs(msgs) do out[#out + 1] = m end
    return #msgs > 0
  end
  local selfList, foeList = MoveFx.changes(1, spec.self), MoveFx.changes(1, spec.foe)

  if spec.kind == "status" then
    local aimed = #foeList > 0 or (spec.ailment ~= nil)
    return {
      kind = "primary", accuracyChecked = aimed or nil,
      run = function(ctx)
        local battle, user, target = ctx.battle, ctx.user, ctx.target
        local out, any = {}, false
        if #selfList > 0 and stages(battle, user, selfList, false, out) then any = true end
        if #foeList > 0 and stages(battle, target, foeList, true, out) then any = true end
        if spec.ailment and ailment(ctx, out) then any = true end
        if spec.heal then
          local who = spec.healTarget == "foe" and target or user
          local mon = who.mon
          if mon.hp >= mon.stats.hp then
            if not any then return failed(battle) end
          else
            mon.hp = math.min(mon.stats.hp, mon.hp + math.max(1, math.floor(mon.stats.hp * spec.heal / 100)))
            out[#out + 1] = romText(battle.data, "_RegainedHealthText", "%s\nregained health!", name(who))
            out.hpBarFirst = true
            any = true
          end
        end
        if not any then
          if #out == 0 then return failed(battle) end
          out.failed = true
        end
        return out
      end,
    }
  end

  return {
    kind = "full",
    afterDamage = function(ctx, dealt)
      local battle, user = ctx.battle, ctx.user
      dealt = tonumber(dealt) or 0
      if dealt <= 0 then return end
      if #selfList > 0 and user.mon.hp > 0 and roll(battle, spec.chance) then
        local out = {}
        stages(battle, user, selfList, false, out)
        for _, m in ipairs(out) do ctx.say(m) end
      end
      if spec.drain and not ctx.brokeSub and user.mon.hp > 0 then
        local mon = user.mon
        if spec.drain > 0 and mon.hp < mon.stats.hp then
          mon.hp = math.min(mon.stats.hp, mon.hp + math.max(1, math.floor(dealt * spec.drain / 100)))
          battle:drainNext(user, mon.hp)
          ctx.say(romText(battle.data, "_SuckedHealthText", "Sucked health from\n%s!", name(ctx.target)))
        elseif spec.drain < 0 then
          battle:applyRecoil(user, math.max(1, math.floor(dealt * -spec.drain / 100)))
        end
      end
    end,
    run = function(ctx)
      local battle, target = ctx.battle, ctx.target
      local out = {}
      if target.substituteHP then return out end
      if #foeList > 0 and roll(battle, spec.chance) then stages(battle, target, foeList, false, out) end
      if spec.ailment and roll(battle, spec.ailmentChance) then ailment(ctx, out) end
      if spec.flinch and roll(battle, spec.flinch) then target.flinched = true end
      return out
    end,
  }
end

-- ------------------------------------------------------------------ Gold
local function gen2Status(spec, require)
  local Strings = require("src.core.Strings")
  local selfList, foeList = MoveFx.changes(2, spec.self), MoveFx.changes(2, spec.foe)
  return {
    kind = "primary",
    run = function(self, attacker, defender, def, moveId, sureHit)
      local aimed = #foeList > 0 or spec.ailment ~= nil or spec.healTarget == "foe"
      if aimed and not sureHit and not self:accuracyRoll(def, attacker, defender) then
        self:markMissed()
        self:emit({ kind = "message", text = Strings("%s's attack missed!", self:battlerName(attacker)) })
        return
      end
      local any = false
      for _, c in ipairs(selfList) do
        if self:changeStage(attacker, c[1], c[2]) then any = true end
      end
      for _, c in ipairs(foeList) do
        if self:changeStageAgainstMist(attacker, defender, c[1], c[2]) then any = true end
      end
      if spec.ailment and GEN2_STATUS[spec.ailment] then
        if self:applyStatus(defender, GEN2_STATUS[spec.ailment], attacker,
            { primary = true, moveType = def.type }) then any = true end
      end
      if spec.heal then
        local who = spec.healTarget == "foe" and defender or attacker
        local maxHp = who.maxHp or (who.stats and who.stats.hp) or 1
        if (who.hp or 0) >= maxHp then
          self:emit({ kind = "message", text = Strings("%s's HP is full!", self:battlerName(who)) })
        else
          self:heal(who, math.max(1, math.floor(maxHp * spec.heal / 100)))
          self:emit({ kind = "message", text = Strings("%s regained health!", self:battlerName(who)) })
          any = true
        end
      end
      if not any then self:markMissed() end
    end,
  }
end

-- after Gold's own hit: what the move adds once it landed
local function gen2After(self, spec, attacker, defender, def, before, require)
  local Strings = require("src.core.Strings")
  local hp, sub = defender.hp or 0, (self:volatile(defender).substitute or 0)
  local dealt = math.max(0, before.hp - hp)
  local intoSub = math.max(0, before.sub - sub)
  if dealt + intoSub <= 0 or (self.moveEvent and self.moveEvent.missed) then return end
  local function roll(pct)
    local r = self.random and self.random(256) or math.random(256) - 1
    return hits(r, pct)
  end
  local name = self:battlerName(attacker)
  if (attacker.hp or 0) > 0 and spec.self and roll(spec.chance) then
    for _, c in ipairs(MoveFx.changes(2, spec.self)) do self:changeStage(attacker, c[1], c[2]) end
  end
  if spec.drain and (attacker.hp or 0) > 0 then
    local total = dealt + intoSub
    if spec.drain > 0 and dealt > 0 then
      local maxHp = attacker.maxHp or (attacker.stats and attacker.stats.hp) or 1
      if (attacker.hp or 0) < maxHp then
        self:heal(attacker, math.max(1, math.floor(dealt * spec.drain / 100)))
        self:emit({ kind = "message", text = Strings("%s's energy was drained!", self:battlerName(defender)) })
      end
    elseif spec.drain < 0 then
      local recoil = math.max(1, math.floor(total * -spec.drain / 100))
      attacker.hp = math.max(0, (attacker.hp or 0) - recoil)
      self:emit({ kind = "damage", side = self:sideOf(attacker), amount = recoil, hp = attacker.hp, anim = false })
      self:emit({ kind = "message", text = Strings("%s is hit with recoil!", name) })
    end
  end
  if hp <= 0 or dealt <= 0 then return end              -- the foe's part needs it standing, hit
  if spec.foe and roll(spec.chance) then
    for _, c in ipairs(MoveFx.changes(2, spec.foe)) do
      self:changeStageAgainstMist(attacker, defender, c[1], c[2])
    end
  end
  if spec.ailment and GEN2_STATUS[spec.ailment] and roll(spec.ailmentChance) then
    self:applyStatus(defender, GEN2_STATUS[spec.ailment], attacker, { secondary = true, moveType = def.type })
  end
  if spec.flinch and roll(spec.flinch) and self.flinch then self:flinch(defender) end
end

local function installGen2Hits(require, specs)
  local okB, Battle = pcall(require, "src.battle.gen2.Battle")
  if not (okB and type(Battle) == "table" and type(Battle.useMove) == "function") then return false end
  local hub = Battle.__ndxMoveFx
  if not hub then
    hub = {}
    Battle.__ndxMoveFx = hub
    local useMove = Battle.useMove
    Battle.useMove = function(self, attacker, defender, moveId, ...)
      local spec = hub.specs and hub.specs[moveId]
      if not (spec and spec.kind == "hit" and defender) then
        return useMove(self, attacker, defender, moveId, ...)
      end
      local before = { hp = defender.hp or 0, sub = self:volatile(defender).substitute or 0 }
      local a, b, c = useMove(self, attacker, defender, moveId, ...)
      local def = self:moveDef(moveId)
      local ok, err = pcall(gen2After, self, spec, attacker, defender, def or {}, before, require)
      if not ok and hub.log and not hub.warned then
        hub.warned = true
        hub.log:warn("a new move's extra failed: %s", tostring(err))
      end
      return a, b, c
    end
  end
  hub.specs, hub.log = specs, hub.log
  return true
end

-- ------------------------------------------------------------------ registration
-- opts: { mod, generation, rows (data/gen12/moves.lua), gen3 (data/moves.lua), types
-- (src/gen12/types.lua), state (src/gen12/moves.lua's: byNumber gets these moves), require, log }
function MoveFx.register(opts)
  local mod, gen, Types, require, log = opts.mod, opts.generation, opts.types, opts.require, opts.log
  local key = "gen" .. gen
  local maxMove = gen == 1 and 165 or 251
  local content = mod.content
  local moves, effects, anims = content.moves, content.move_effects, content.battle_anims
  local extra = {}
  for _, r in ipairs(opts.gen3 or {}) do
    if type(r.extra) == "table" then extra[r.id] = r.extra end
  end
  local cartByIndex = {}
  for id, rec in moves:each() do
    if type(rec) == "table" and type(rec.index) == "number" and rec.index <= maxMove then
      cartByIndex[rec.index] = id
    end
  end
  local goldScripts, goldAdded = nil, {}
  if gen == 2 and anims then
    local ok, base = pcall(anims.get, anims, "moves")
    goldScripts = ok and type(base) == "table" and base or nil
  end
  local okE, Effects = false, nil
  if gen == 2 then okE, Effects = pcall(require, "src.battle.gen2.Effects") end

  local result = { registered = 0, specs = {}, failed = 0, looks = {} }
  local firstError
  for _, row in ipairs(opts.rows or {}) do
    local spec = extra[row.id]
    if spec and row.n > maxMove and not row[key] and not opts.state.byNumber[row.n]
        and moves:get(row.id) == nil then
      local look
      for _, s in ipairs(row.subs and row.subs[key] or {}) do
        if s <= maxMove and cartByIndex[s] then look = cartByIndex[s]; break end
      end
      local ok, err = pcall(function()
        local rec = { id = row.id, name = row.name, type = Types.cartId(row.type), power = row.power,
          accuracy = row.accuracy > 0 and row.accuracy or 100, pp = row.pp }
        local effectId = MoveFx.PREFIX .. row.id
        if gen == 1 then
          effects:register(effectId, gen1Record(spec, require))
          rec.effect = effectId
          if row.highCrit then rec.highCrit = true end
          local like = look and moves:get(look)
          if like and like.anim then rec.anim = copy(like.anim) end
        else
          rec.index, rec.effectChance = row.n, 0
          if spec.kind == "status" then
            effects:register(effectId, gen2Status(spec, require))
            rec.effect = effectId
            if not spec.foe and not spec.ailment and spec.healTarget ~= "foe" and okE
                and type(Effects.NO_CHECKHIT) == "table" then
              Effects.NO_CHECKHIT[effectId] = true
            end
          else
            rec.effect = "EFFECT_NORMAL_HIT"
          end
        end
        local okR, errR = pcall(moves.register, moves, row.id, rec)
        if not okR and gen == 2 then
          rec.index = nil
          okR, errR = pcall(moves.register, moves, row.id, rec)
        end
        if not okR then error(errR, 0) end
        if look then
          if gen == 1 and anims then
            local okA, seq = pcall(anims.get, anims, look)
            if okA and seq then pcall(anims.register, anims, row.id, copy(seq)) end
          elseif goldScripts and goldScripts[look] then
            goldAdded[row.id] = goldScripts[look]
          end
        end
      end)
      if ok then
        opts.state.byNumber[row.n] = row.id
        result.registered = result.registered + 1
        result.specs[row.id] = spec
        result.looks[row.id] = look
      else
        result.failed = result.failed + 1
        firstError = firstError or (row.id .. ": " .. tostring(err))
      end
    end
  end
  if next(goldAdded) then pcall(anims.patch, anims, "moves", goldAdded) end
  if gen == 2 then
    local okI = pcall(installGen2Hits, require, result.specs)
    if not okI and log then log:warn("the new moves' extras are off on this game") end
    local okB, Battle = pcall(require, "src.battle.gen2.Battle")
    if okB and Battle.__ndxMoveFx then Battle.__ndxMoveFx.log = log end
  end
  if firstError and log then
    log:warn("%d new move mechanics failed (first: %s); those moves use stand-ins", result.failed, firstError)
  end
  return result
end

return MoveFx
