-- New move mechanics: moves whose effect Gen 3 lacks but which PokeAPI describes completely
-- (data/moves.lua `extra`, tools/build_moves.py generic_extra): stat changes on the user or the
-- foe, a status or flinch chance, draining and recoil, healing.
--
--   * a status move (Nasty Plot, Noble Roar, Shore Up) has effect byte 250, which the cart
--     never uses: it is mapped to this mod's handler in the engine's effect table
--     (EffectIds.STATUS_SETUP), and a wrap of Effects.run, through which every status move
--     runs, carries it out
--   * an attack (Close Combat, Fire Fang, Draining Kiss, Flare Blitz) is a plain hit
--     (effect 0); a wrap of Hit.run applies its extra once the hit has landed, with the
--     engine's own stat-change, status and message functions (Secondary.changeStat / set)
-- Every step runs protected: an error leaves the move as the plain hit or "nothing happened".

local MoveEffects = {}

MoveEffects.CUSTOM_EFFECT = 250
MoveEffects.EFFECT_ID = "NATIONAL_DEX_GEN3_MOVE_EFFECT"

local ORDER = { "attack", "defense", "spAtk", "spDef", "speed", "accuracy", "evasion" }

-- opts: { moves = src/moves.lua's registered rows, require, log }
function MoveEffects.install(opts)
  local require, log = opts.require, opts.log
  local specs = {}
  -- added effects a row's cart effect drops (Double Iron Bash: the double hit has no secondary,
  -- so its 30% flinch never came)
  local LATE = { DOUBLE_IRON_BASH = { kind = "hit", flinch = 30 } }
  for _, r in ipairs(opts.moves or {}) do
    if type(r.extra) == "table" then specs[r.index] = r.extra
    elseif LATE[r.id] and tonumber(r.index) then specs[tonumber(r.index)] = LATE[r.id] end
  end
  MoveEffects._specs = specs                       -- a later install replaces what the wraps read

  local okI, EffectIds = pcall(require, "src.core.game3.battle.effect_ids")
  local okE, Effects = pcall(require, "src.core.game3.battle.effects")
  local okH, Hit = pcall(require, "src.core.game3.battle.effects.hit")
  local okS, Secondary = pcall(require, "src.core.game3.battle.effects.secondary")
  local okM, Moves = pcall(require, "src.core.game3.battle.moves")
  if not (okI and okE and okH and okS and type(EffectIds.STATUS_SETUP) == "table"
      and type(Effects.run) == "function" and type(Hit.run) == "function"
      and type(Secondary.changeStat) == "function") then
    if log then log:warn("new move mechanics are off: the battle engine's effect functions were not found") end
    return false
  end

  local function specFor(moveId, moveCtx)
    local num = tonumber(moveCtx and moveCtx.mnum) or tonumber(moveId)
    if not num and okM and type(moveId) == "string" then num = Moves.numForName(moveId) end
    return num and MoveEffects._specs[num]
  end

  local function stats(ad, b, changes, flags)
    local any = false
    for _, stat in ipairs(ORDER) do
      local delta = changes[stat]
      if delta and delta ~= 0 then
        local copy = {}
        for k, v in pairs(flags) do copy[k] = v end
        if Secondary.changeStat(ad, b, stat, delta, copy) == "worked" then any = true end
      end
    end
    return any
  end

  -- an added effect's chance (Serene Grace: twice it)
  local function roll(ad, chance, user)
    chance = tonumber(chance) or 100
    if chance >= 100 then return true end
    if user and ad:abilityOf(user) == "SERENE_GRACE" then chance = chance * 2 end
    return ad:roll(1, 100) <= chance
  end
  -- the held item a battler holds, by kind (src/held/gen3.lua's hub)
  local function heldKind(b)
    local ok, HI = pcall(require, "src.core.game3.battle.held_items")
    local h = ok and type(HI) == "table" and HI.__ndxHeldHub
    return h and h.kindOf and h.kindOf(b) or nil
  end

  -- status moves
  EffectIds.STATUS_SETUP[MoveEffects.CUSTOM_EFFECT] = MoveEffects.EFFECT_ID
  if not Effects.__nationalDexMoveEffects then
    Effects.__nationalDexMoveEffects = true
    local run = Effects.run
    Effects.run = function(id, ad, user, target, move, moveId, moveCtx, ...)
      if id ~= MoveEffects.EFFECT_ID then return run(id, ad, user, target, move, moveId, moveCtx, ...) end
      local spec = specFor(moveId, moveCtx)
      if not spec then return false end
      local ok = pcall(function()
        local M = moveCtx
        -- aimed at the foe: the accuracy check first, which is where Protect and a vanished foe
        -- stop a move (Noble Roar, Tearful Look, Confide, Eerie Impulse, Spicy Extract)
        if spec.foe and target and target ~= user and M and M.accuracyCheck and not M:accuracyCheck("normal", true) then
          return
        end
        if spec.self then
          if M and M.attackAnimation then M:attackAnimation() end
          stats(ad, user, spec.self, { user = true })
        end
        if spec.foe and target and target ~= user then
          if (target.substituteHP or 0) > 0 then
            ad:sayText("STRINGID_BUTITFAILED", {})
          else
            if M and M.attackAnimation and not spec.self then M:attackAnimation() end
            stats(ad, target, spec.foe, { allowPtr = true })
          end
        end
        if spec.heal then
          local who = spec.healTarget == "foe" and target or user
          local maxHp, hp = ad:maxHp(who), ad:hp(who)
          if hp >= maxHp then
            ad:sayText("STRINGID_PKMNHPFULL", { def = who })
          else
            local pct = spec.heal
            if spec.sandHeal and ad._st then
              local okR, Rules = pcall(require, "src.core.game3.battle.rules")
              local okW, w = pcall(function() return Rules.weather.effective(ad._st, ad) end)
              if okR and okW and w == "SAND" then pct = spec.sandHeal end
            end
            if M and M.attackAnimation then M:attackAnimation() end
            ad:heal(who, math.max(1, math.floor(maxHp * pct / 100)))
            ad:sayText("STRINGID_PKMNREGAINEDHEALTH", { def = who })
          end
        end
      end)
      if not ok then return false end
      return true
    end
  end

  -- attacks: the extra, once the hit has landed
  if not Hit.__nationalDexMoveEffects then
    Hit.__nationalDexMoveEffects = true
    local hitRun = Hit.run
    Hit.run = function(M, ...)
      local r = hitRun(M, ...)
      local spec = type(M) == "table" and MoveEffects._specs[tonumber(M.mnum) or -1]
      if not (spec and spec.kind == "hit") then return r end
      pcall(function()
        local ad, user, target = M.adapter, M.user, M.target
        if not (ad and user and target) or M.noEffect or not M.targetDamaged then return end
        local dealt = tonumber(M.hpDealt) or 0
        local targetUp = ad:hp(target) > 0
        -- Shield Dust, Covert Cloak: no added effects on the target
        local shielded = ad:abilityOf(target) == "SHIELD_DUST" or heldKind(target) == "covertCloak"
        if spec.self and ad:hp(user) > 0 and roll(ad, spec.chance, user) then
          stats(ad, user, spec.self, { user = true, certain = true })
        end
        if spec.foe and targetUp and not M.hitSubstitute and not shielded and roll(ad, spec.chance, user) then
          stats(ad, target, spec.foe, {})
        end
        if spec.ailment and targetUp and not M.hitSubstitute and not shielded and roll(ad, spec.ailmentChance, user) then
          Secondary.set(M, spec.ailment, false, false, false)
        end
        if spec.flinch and targetUp and not M.hitSubstitute and not shielded and roll(ad, spec.flinch, user) then
          Secondary.set(M, "FLINCH", false, false, false)
        end
        if spec.drain and dealt > 0 then
          local amount = math.max(1, math.floor(dealt * math.abs(spec.drain) / 100))
          if spec.drain > 0 and heldKind(user) == "bigRoot" then amount = math.floor(amount * 1.3) end
          if spec.drain > 0 and ad:hp(user) > 0 and ad:abilityOf(target) == "LIQUID_OOZE" then
            -- Liquid Ooze: the drain hurts instead
            ad:applyHpLoss(user, amount)
            ad:sayText("STRINGID_ITSUCKEDLIQUIDOOZE")
            if M.tryFaintUser then M:tryFaintUser() end
          elseif spec.drain > 0 and ad:hp(user) > 0 and ad:hp(user) < ad:maxHp(user) then
            ad:heal(user, amount)
            ad:sayText("STRINGID_PKMNENERGYDRAINED", { def = target })
          elseif spec.drain < 0 and ad:hp(user) > 0 and ad:abilityOf(user) ~= "ROCK_HEAD" then
            ad:applyHpLoss(user, math.max(1, math.floor(dealt * -spec.drain / 100)))
            ad:sayText("STRINGID_PKMNHITWITHRECOIL", { atk = user })
            if M.tryFaintUser then M:tryFaintUser() end
          end
        end
      end)
      return r
    end
  end

  local n = 0
  for _ in pairs(specs) do n = n + 1 end
  if log then log:info("new move mechanics: %d moves", n) end
  return true
end

return MoveEffects
