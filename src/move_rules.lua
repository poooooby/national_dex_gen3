-- Move rules: newer attacks whose power, stats or outcome depend on the battle
-- (data/moves.lua `rule`, set by hand in tools/build_moves.py MANUAL). Every one is a plain
-- hit (effect 0, or a cart effect) to the engine; these wraps make it the real move:
--
--   * Damage.calc (the battle and the AI's damage estimate both call it): the power (Hex,
--     Brine, Stored Power, Heavy Slam, Gyro Ball ...), whose stats are used (Foul Play, Body
--     Press, Psyshock), ignored stat stages (Sacred Sword), always a critical hit (Wicked Blow),
--     damage equal to the user's HP (Final Gambit), and 1.33x when super effective (Collision
--     Course). The battler's own fields are swapped for the call and put back after, so every
--     identity lookup inside the engine still sees the real battler
--   * Hit.run: moves that fail (Sucker Punch, First Impression, Last Resort) and what follows
--     the hit (Clear Smog, Fell Stinger, Final Gambit, Mind Blown, Sparkling Aria, Wake-Up Slap)
--   * battle.move_used / battle.damage_dealt: who moved and who fainted this turn
-- Every step runs protected: an error leaves the move as the plain hit.

local MoveRules = {}

MoveRules._rules = {}                             -- move number -> rule name (install fills it)
MoveRules._hits = {}                              -- move number -> hit count (true: 2-5)
MoveRules._formWeight = {}                        -- form slot -> hectograms
MoveRules._neverMiss = {}                         -- move number -> true: a damaging move that never misses
local ALWAYS_HIT = 17                             -- the cart's EFFECT_ALWAYS_HIT (Swift, Aerial Ace)

-- Fling: power by the cart's item name (Showdown's data for the items Gen 3 has); a berry is 10,
-- anything else 30
local FLING = { ["HARD STONE"] = 100, ["THICK CLUB"] = 90, ["DRAGON FANG"] = 70, ["POISON BARB"] = 70,
  ["SHARP BEAK"] = 50, ["DEEPSEATOOTH"] = 90, ["IRON BALL"] = 130, ["ROCK INCENSE"] = 10,
  ["BLACKGLASSES"] = 30, ["LEFTOVERS"] = 10, ["LIGHT BALL"] = 30, ["KING'S ROCK"] = 30,
  ["METAL COAT"] = 30, ["QUICK CLAW"] = 80, ["MACHO BRACE"] = 60, ["STICK"] = 60,
  ["DRAGON SCALE"] = 30, ["EVERSTONE"] = 30, ["FIRE STONE"] = 30, ["WATER STONE"] = 30,
  ["THUNDERSTONE"] = 30, ["LEAF STONE"] = 30, ["MOON STONE"] = 30, ["SUN STONE"] = 30 }
-- Natural Gift: the 43 Gen 3 berries in order (ItemsData.berryNumber), type and power (Gen 6+)
local GIFT_TYPE = { 10, 11, 13, 12, 15, 1, 3, 4, 2, 14, 6, 5, 7, 16, 17, 8,
                    10, 11, 13, 12, 15, 1, 3, 4, 2, 14, 6, 5, 7, 16, 17, 8,
                    10, 11, 13, 12, 15, 1, 3, 4, 2, 14, 6 }
local GIFT_POWER = { 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80,
                     90, 90, 90, 90, 90, 90, 90, 90, 90, 90, 90, 90, 90, 90, 90, 90,
                     100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100 }

local ALWAYS_CRIT = { FROST_BREATH = true, STORM_THROW = true, WICKED_BLOW = true, FLOWER_TRICK = true,
                      SURGING_STRIKES = true }

local Battle
local function adapter()
  if not Battle then
    local ok, B = pcall(require, "src.core.game3.battle")
    Battle = ok and B or nil
  end
  return Battle and Battle._adapter
end

local function abilityOf(ad, b)
  if not (ad and b) then return nil end
  local ok, name = pcall(ad.abilityOf, ad, b)
  return ok and name or nil
end

local function monOf(b) return b and (b.mon or b) or {} end
local function hpOf(b) return tonumber(monOf(b).hp) or 0 end
local function maxHpOf(b) return math.max(1, tonumber(monOf(b).maxHp) or 1) end
local function stageOf(b, k) return tonumber(b and b.stages and b.stages[k]) or 0 end
local function statusOf(b)
  local s = b and (b.status or (b.mon and b.mon.status))
  if s == 0 then return nil end
  return s
end

local STAGES = { "attack", "defense", "spAtk", "spDef", "speed", "accuracy", "evasion" }

local function boosts(b)
  local n = 0
  for _, k in ipairs(STAGES) do
    local s = stageOf(b, k)
    if s > 0 then n = n + s end
  end
  return n
end

-- hectograms: the Pokedex entry's, or data/species/forms.lua's for a form (which has no entry)
local function weightOf(b)
  local sp = tonumber(b and (b.species or (b.mon and b.mon.species)))
  local w = sp and MoveRules._formWeight[sp]
  if not w then
    local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
    local entry = ok and sp and Pokemon.dexEntry and Pokemon.dexEntry(sp)
    w = entry and tonumber(entry.weight)
  end
  return (w and w > 0) and w or nil
end

local function speedOf(b)
  local ok, Damage = pcall(require, "src.core.game3.battle.damage")
  local s = tonumber(monOf(b).speed) or 1
  if ok and Damage.applyStage then s = Damage.applyStage(s, stageOf(b, "speed")) end
  if statusOf(b) == "PAR" then s = math.floor(s / 4) end
  return math.max(1, s)
end

local function itemOf(b)
  local ok, HeldItems = pcall(require, "src.core.game3.battle.held_items")
  if ok and HeldItems.itemOf then return tonumber(HeldItems.itemOf(b)) or 0 end
  return tonumber(b and b.item) or 0
end

local function isBerry(item)
  local ok, ItemsData = pcall(require, "src.core.game3.items_data")
  return ok and ItemsData.isBerry and ItemsData.isBerry(item) or false
end

local function berryNumber(item)
  local ok, ItemsData = pcall(require, "src.core.game3.items_data")
  return ok and ItemsData.berryNumber and ItemsData.berryNumber(item) or nil
end

local function itemName(item)
  local ok, ItemsData = pcall(require, "src.core.game3.items_data")
  local okN, n = pcall(function() return ok and ItemsData.displayName and ItemsData.displayName(item) end)
  return okN and n and tostring(n):upper() or "ITEM"
end

local function consume(ad, b)
  local ok, HeldItems = pcall(require, "src.core.game3.battle.held_items")
  if ok and HeldItems.consume then HeldItems.consume(ad, b) end
end

local function setAbility(b, name)
  b.expTracedAbility = name
  b.expAbilitySuppressed = nil
  b.ability = name
end

local function battleOf(o)
  local ad = (o and o.adapter) or adapter()
  return ad and ad._st, ad
end

-- PP left in the move's slot (Trump Card), after this use's PP came off
local function ppLeft(b, num)
  local mon = monOf(b)
  for i, m in ipairs(mon.moves or {}) do
    if tonumber(m) == num then return tonumber(mon.pp and mon.pp[i]) end
  end
  return nil
end

-- The power, swaps and options a rule's hit is calculated with.
-- set(tbl, key, value) changes a battler field for the one call.
local function prepare(rule, A, D, move, o, set, num)
  local st, ad = battleOf(o)
  local turn = st and st.turn
  local base = tonumber(o.power) or tonumber(move.power) or 0
  local power
  if rule == "HEX" then
    if statusOf(D) then power = base * 2 end
  elseif rule == "VENOSHOCK" then
    local s = statusOf(D)
    if s == "PSN" or s == "TOX" then power = base * 2 end
  elseif rule == "BRINE" then
    if hpOf(D) * 2 <= maxHpOf(D) then power = base * 2 end
  elseif rule == "ACROBATICS" then
    if (tonumber(A.item) or 0) == 0 then power = base * 2 end
  elseif rule == "ASSURANCE" then
    if (tonumber(D.damageTakenThisTurn) or 0) > 0 then power = base * 2 end
  elseif rule == "PAYBACK" then
    if turn and D.__ndxMovedTurn == turn then power = base * 2 end
  elseif rule == "BOLT_BEAK" or rule == "FISHIOUS_REND" then
    if turn and D.__ndxMovedTurn ~= turn then power = base * 2 end
  elseif rule == "RETALIATE" then
    local f = st and st.__ndxFainted
    if turn and f and f[A.side] == turn - 1 then power = base * 2 end
  elseif rule == "WAKE_UP_SLAP" then
    if statusOf(D) == "SLP" then power = base * 2 end
  elseif rule == "STORED_POWER" or rule == "POWER_TRIP" then
    power = 20 + 20 * boosts(A)
  elseif rule == "PUNISHMENT" then
    power = math.min(200, 60 + 20 * boosts(D))
  elseif rule == "HEAVY_SLAM" or rule == "HEAT_CRASH" then
    local wa, wd = weightOf(A), weightOf(D)
    local r = (wa and wd) and wa / wd or 1
    power = r >= 5 and 120 or r >= 4 and 100 or r >= 3 and 80 or r >= 2 and 60 or 40
  elseif rule == "GYRO_BALL" then
    power = math.min(150, math.floor(25 * speedOf(D) / speedOf(A)) + 1)
  elseif rule == "ELECTRO_BALL" then
    local r = speedOf(A) / speedOf(D)
    power = r >= 4 and 150 or r >= 3 and 120 or r >= 2 and 80 or r >= 1 and 60 or 40
  elseif rule == "WRING_OUT" or rule == "CRUSH_GRIP" then
    power = math.max(1, math.floor(120 * hpOf(D) / maxHpOf(D)))
  elseif rule == "TRUMP_CARD" then
    local pp = ppLeft(A, num)
    power = pp == 0 and 200 or pp == 1 and 80 or pp == 2 and 60 or pp == 3 and 50 or 40
  elseif rule == "ECHOED_VOICE" then
    local e = st and st.__ndxEcho
    power = math.min(200, base * ((e and e.count) or 1))
  elseif rule == "STOMPING_TANTRUM" then
    if A.__ndxLastMoveFailed then power = base * 2 end
  elseif rule == "RAGE_FIST" then
    local hits = st and st.__ndxHits and st.__ndxHits[monOf(A)] or 0
    power = math.min(350, 50 + 50 * hits)
  elseif rule == "LAST_RESPECTS" then
    local n = st and st.__ndxFaintCount and st.__ndxFaintCount[A.side] or 0
    power = 50 + 50 * n
  elseif rule == "FUSION_FLARE" or rule == "FUSION_BOLT" then
    local f = st and st.__ndxFusion
    if f and turn and f.turn == turn and f.rule ~= rule then power = base * 2 end
  elseif rule == "FICKLE_BEAM" then
    if ad and ad:roll(1, 100) <= 30 then power = base * 2 end
  end
  if power then o.power = math.max(1, math.floor(power)) end

  if rule == "REVELATION_DANCE" and tonumber(A.type1) then o.moveType = tonumber(A.type1) end
  if rule == "FLING" then
    local item = itemOf(A)
    o.power = isBerry(item) and 10 or FLING[itemName(item)] or 30
  elseif rule == "NATURAL_GIFT" then
    local n = berryNumber(itemOf(A))
    if n and GIFT_POWER[n] then o.power, o.moveType = GIFT_POWER[n], GIFT_TYPE[n] end
  end
  -- what the field did to the move's type: Electrify, Ion Deluge (Normal moves)
  if A.__ndxElectrified == turn then o.moveType = 13
  elseif st and st.__ndxIonDeluge == turn and (tonumber(o.moveType) or tonumber(move.type) or 0) == 0 then o.moveType = 13 end

  -- whose stats: Gen 3 splits physical and special by type, so the real move's stat goes into
  -- whichever one the move's type reads (Foul Play is Dark, so the foe's ATTACK stands in
  -- for the user's SP. ATK)
  local aMon, dMon = monOf(A), monOf(D)
  -- Power Split, Guard Split, Power Trick: the battler's stats as the moves left them (never
  -- written to the mon, which is the saved party entry)
  for _, pair in ipairs({ { A, aMon }, { D, dMon } }) do
    local over = pair[1].__ndxStat
    if over then
      for _, k in ipairs({ "attack", "defense", "spAtk", "spDef" }) do
        if over[k] then set(pair[2], k, over[k]) end
      end
    end
  end
  -- Miracle Eye: a Dark type takes Psychic hits
  if D.__ndxMiracleEye and (tonumber(o.moveType) or tonumber(move.type)) == 14 then
    if D.type1 == 17 then set(D, "type1", 9) end
    if D.type2 == 17 then set(D, "type2", 9) end
  end
  local okT, Types = pcall(require, "src.core.game3.battle.types")
  local physical = okT and Types.isPhysical and Types.isPhysical(tonumber(o.moveType) or tonumber(move.type) or 0)
  local offense = physical and "attack" or "spAtk"
  local defense = physical and "defense" or "spDef"
  local function use(b, mon, into, value, stage)
    set(mon, into, value)
    if b.expTransform and b.expTransform[into] then set(b.expTransform, into, value) end
    if b.stages then set(b.stages, into, stage) end
  end
  if rule == "FOUL_PLAY" then
    use(A, aMon, offense, tonumber(dMon.attack) or tonumber(aMon[offense]), stageOf(D, "attack"))
  elseif rule == "BODY_PRESS" then
    use(A, aMon, offense, tonumber(aMon.defense) or tonumber(aMon[offense]), stageOf(A, "defense"))
  elseif rule == "SECRET_SWORD" then
    use(A, aMon, offense, tonumber(aMon.spAtk) or tonumber(aMon[offense]), stageOf(A, "spAtk"))
  elseif rule == "PSYSHOCK" then
    use(D, dMon, defense, tonumber(dMon.defense) or tonumber(dMon[defense]), stageOf(D, "defense"))
  elseif rule == "SACRED_SWORD" or rule == "DARKEST_LARIAT" or rule == "CHIP_AWAY" then
    if D.stages then
      set(D.stages, "defense", 0)
      set(D.stages, "spDef", 0)
    end
  end

  -- Laser Focus: the user's next move (the turn after) is a critical hit
  local focused = A.__ndxLaserFocus and turn and A.__ndxLaserFocus + 1 == turn
  if ALWAYS_CRIT[rule] or focused then
    local ab = abilityOf(ad, D)
    if ab ~= "BATTLE_ARMOR" and ab ~= "SHELL_ARMOR" then o.forceCrit = true end
  elseif rule == "FINAL_GAMBIT" then
    o.fixedDamage = math.max(1, hpOf(A))
  elseif rule == "METAL_BURST" then
    local taken = math.max(tonumber(A.lastPhysicalDamageTaken) or 0, tonumber(A.lastSpecialDamageTaken) or 0)
    o.fixedDamage = math.max(1, math.floor(taken * 3 / 2))
  end
  return rule == "ELECTRO_DRIFT" or rule == "COLLISION_COURSE"
end

-- after the engine's number: Flying Press's second type, Glaive Rush's double damage taken
local function adjust(rule, A, D, dmg, info)
  if (tonumber(dmg) or 0) <= 0 or type(info) ~= "table" then return dmg, info end
  if rule == "FLYING_PRESS" then
    local okT, Types = pcall(require, "src.core.game3.battle.types")
    if okT and Types.typeCalc then
      local _, _, eff = Types.typeCalc(2, D.type1, D.type2, nil, D.expIdentified)   -- FLYING
      eff = tonumber(eff) or 1
      info.effectiveness = (tonumber(info.effectiveness) or 1) * eff
      if eff == 0 then
        info.typeFlags = info.typeFlags or {}
        info.typeFlags.immune = true
      end
      dmg = math.floor(dmg * eff)
    end
  end
  if D.__ndxGlaiveRush then dmg = dmg * 2 end
  local mtype = tonumber(info.moveType)
  if D.__ndxType3 and mtype then
    local okT, Types = pcall(require, "src.core.game3.battle.types")
    if okT and Types.typeCalc then
      local _, _, eff = Types.typeCalc(mtype, D.__ndxType3, nil, nil, D.expIdentified)
      eff = tonumber(eff) or 1
      info.effectiveness = (tonumber(info.effectiveness) or 1) * eff
      if eff == 0 then
        info.typeFlags = info.typeFlags or {}
        info.typeFlags.immune = true
      end
      dmg = math.floor(dmg * eff)
    end
  end
  if D.__ndxTarShot and mtype == 10 then dmg = dmg * 2 end
  return dmg, info
end

local function moveNum(moveId)
  if type(moveId) == "table" then
    local n = tonumber(moveId.numId) or tonumber(moveId.id)
    if n then return n end
    moveId = moveId.id
  end
  if tonumber(moveId) then return tonumber(moveId) end
  if type(moveId) == "string" then
    local ok, Moves = pcall(require, "src.core.game3.battle.moves")
    return ok and Moves.numForName and Moves.numForName(moveId) or nil
  end
  return nil
end

-- has the battler chosen an attack it has not used yet this turn (Sucker Punch)
local function aboutToAttack(st, b)
  if not (st and b) or b.__ndxMovedTurn == st.turn then return false end
  local okS, State = pcall(require, "src.core.game3.battle.state")
  local act = okS and st.chosen and st.chosen[State.idOf(b)]
  if not act or (act.kind and act.kind ~= "move") then return false end
  local ref = act.move
  if ref == nil and act.slot then ref = monOf(b).moves and monOf(b).moves[act.slot] end
  local okM, Moves = pcall(require, "src.core.game3.battle.moves")
  local okG, m = pcall(Moves.get, ref)
  return okM and okG and m and (tonumber(m.power) or 0) > 0 or false
end

-- Last Resort: the user knows another move and has used every one since it came in
local function usedAllOthers(b, num)
  local mon, n = monOf(b), 0
  local used = b.__ndxUsed and b.__ndxUsed.mon == mon and b.__ndxUsed.moves or {}
  for _, m in ipairs(mon.moves or {}) do
    m = tonumber(m) or 0
    if m > 0 and m ~= num then
      n = n + 1
      if not used[m] then return false end
    end
  end
  return n > 0
end

-- true (and a message id + fill) when the move fails before it is used
local function preFails(rule, M)
  if rule == "SUCKER_PUNCH" then return not aboutToAttack(M.st, M.target) end
  if rule == "FIRST_IMPRESSION" then return (tonumber(M.user.isFirstTurn) or 0) <= 0 end
  if rule == "LAST_RESORT" then return not usedAllOthers(M.user, tonumber(M.mnum)) end
  if rule == "MIND_BLOWN" or rule == "CHLOROBLAST" then
    local ad = M.adapter
    for _, b in ipairs(ad:activeBattlers()) do
      if abilityOf(ad, b) == "DAMP" then
        local okH, H = pcall(require, "src.core.game3.battle.effects._helpers")
        return true, "STRINGID_PKMNPREVENTSUSAGE", { def = b, atk = M.user, currentMove = M.mnum,
          defAbility = okH and H.abilityId and H.abilityId("DAMP") or nil }
      end
    end
  elseif rule == "METAL_BURST" then
    -- strikes back at whoever hit the user hardest this turn
    local user = M.user
    local phys, spec = tonumber(user.lastPhysicalDamageTaken) or 0, tonumber(user.lastSpecialDamageTaken) or 0
    if phys <= 0 and spec <= 0 then return true end
    local id = phys >= spec and user.lastPhysicalById or user.lastSpecialById
    local okS, State = pcall(require, "src.core.game3.battle.state")
    local src = okS and id ~= nil and State.battler(M.st, id) or nil
    if src and src ~= user and M.adapter:hp(src) > 0 then
      M.target, M.tname = src, M.adapter:displayName(src)
    end
    if M.adapter:hp(M.target) <= 0 then return true end
  elseif rule == "BURN_UP" then
    return not M.adapter:hasType(M.user, 10)                                     -- FIRE
  elseif rule == "DOUBLE_SHOCK" then
    return not M.adapter:hasType(M.user, 13)                                     -- ELECTRIC
  elseif rule == "SYNCHRONOISE" then
    local u, t = M.user, M.target
    local shared = false
    for _, ty in ipairs({ u.type1, u.type2 }) do
      if ty and (ty == t.type1 or ty == t.type2) then shared = true end
    end
    return not shared
  elseif rule == "GIGATON_HAMMER" then
    return M.user.__ndxLastMove == tonumber(M.mnum)
  elseif rule == "FLING" then
    return itemOf(M.user) == 0
  elseif rule == "NATURAL_GIFT" then
    return not isBerry(itemOf(M.user))
  elseif rule == "BELCH" then
    return not isBerry(tonumber(M.user.expUsedHeldItem) or 0)
  end
  return false
end

local function prefixed(ad, b)
  local ok, State = pcall(require, "src.core.game3.battle.state")
  if ok and State.prefixedName then
    local okN, n = pcall(State.prefixedName, ad._st, b)
    if okN and n then return n end
  end
  return ad:displayName(b)
end

local function after(rule, M)
  local ad, user, target = M.adapter, M.user, M.target
  if not (ad and user and target) or M.failed then return end
  local landed = M.targetDamaged and not M.noEffect
  local targetUp = ad:hp(target) > 0
  if rule == "CLEAR_SMOG" and landed and targetUp and not M.hitSubstitute and target.stages then
    local any = false
    for _, k in ipairs(STAGES) do
      if stageOf(target, k) ~= 0 then target.stages[k] = 0; any = true end
    end
    if any then ad:say(prefixed(ad, target) .. "'s stat changes\nwere removed!") end
  elseif rule == "FELL_STINGER" and landed and not targetUp and ad:hp(user) > 0 then
    local okS, Secondary = pcall(require, "src.core.game3.battle.effects.secondary")
    if okS then Secondary.changeStat(ad, user, "attack", 3, { user = true, certain = true }) end
  elseif rule == "FINAL_GAMBIT" and landed and ad:hp(user) > 0 then
    ad:applyHpLoss(user, ad:hp(user))
    if M.tryFaintUser then M:tryFaintUser() end
  elseif (rule == "CHLOROBLAST" or rule == "MIND_BLOWN") and ad:hp(user) > 0
      and abilityOf(ad, user) ~= "MAGIC_GUARD" then
    ad:applyHpLoss(user, math.ceil(ad:maxHp(user) / 2))
    ad:say(prefixed(ad, user) .. " lost half\nof its HP!")
    if M.tryFaintUser then M:tryFaintUser() end
  elseif rule == "SPARKLING_ARIA" and landed and targetUp and ad:status(target) == "BRN" then
    ad:clearStatus(target)
    ad:say(prefixed(ad, target) .. "'s burn\nwas healed!")
  elseif rule == "WAKE_UP_SLAP" and landed and targetUp and not M.hitSubstitute
      and ad:status(target) == "SLP" then
    ad:clearStatus(target)
    ad:sayText("STRINGID_PKMNWOKEUP", { atk = target })
  elseif (rule == "BURN_UP" or rule == "DOUBLE_SHOCK") and landed then
    -- the user loses the type; a single-typed one is left typeless (MYSTERY)
    local t = rule == "BURN_UP" and 10 or 13
    if user.type2 == t then user.type2 = nil
    elseif user.type1 == t then user.type1, user.type2 = user.type2 or 9, nil end
    if user.expTransform then
      if user.expTransform.type2 == t then user.expTransform.type2 = nil
      elseif user.expTransform.type1 == t then user.expTransform.type1, user.expTransform.type2 = user.expTransform.type2 or 9, nil end
    end
    ad:say(prefixed(ad, user) .. (rule == "BURN_UP" and " burned itself out!" or " used up all\nof its electricity!"))
  elseif rule == "GLAIVE_RUSH" and landed then
    user.__ndxGlaiveRush = true
  elseif rule == "DIRE_CLAW" and landed and targetUp and not M.hitSubstitute and ad:roll(1, 100) <= 50 then
    local okS, Secondary = pcall(require, "src.core.game3.battle.effects.secondary")
    if okS then Secondary.set(M, ({ "POISON", "PARALYSIS", "SLEEP" })[ad:roll(1, 3)], false, false, false) end
  elseif rule == "FLING" or rule == "NATURAL_GIFT" then
    if not M.failed then
      if rule == "FLING" then ad:say(prefixed(ad, user) .. " flung its\n" .. itemName(itemOf(user)) .. "!") end
      consume(ad, user)
    end
  elseif (rule == "BUG_BITE" or rule == "PLUCK" or rule == "INCINERATE") and landed and targetUp and not M.hitSubstitute then
    local item = itemOf(target)
    if isBerry(item) then
      local name = itemName(item)
      consume(ad, target)
      if rule == "INCINERATE" then
        ad:say(prefixed(ad, target) .. "'s " .. name .. "\nwas burned up!")
      else
        ad:say(prefixed(ad, user) .. " stole and ate\n" .. prefixed(ad, target) .. "'s " .. name .. "!")
      end
    end
  elseif rule == "CORE_ENFORCER" and landed and targetUp and not M.hitSubstitute
      and M.st and target.__ndxMovedTurn == M.st.turn and abilityOf(ad, target) then
    target.expTracedAbility, target.expAbilitySuppressed = nil, true
    ad:say(prefixed(ad, target) .. "'s ability\nwas suppressed!")
  elseif rule == "PLASMA_FISTS" and landed and M.st then
    M.st.__ndxIonDeluge = M.st.turn
    ad:say("A deluge of ions showers\nthe battlefield!")
  elseif rule == "EERIE_SPELL" and landed and targetUp and not M.hitSubstitute then
    local mon = monOf(target)
    local last = tonumber(target.lastMoveId or target.lastMove) or target.__ndxLastMove
    for i, m in ipairs(mon.moves or {}) do
      if tonumber(m) == last and mon.pp and (tonumber(mon.pp[i]) or 0) > 0 then
        local before = mon.pp[i]
        mon.pp[i] = math.max(0, mon.pp[i] - 3)
        local okMo, Moves = pcall(require, "src.core.game3.battle.moves")
        local name = okMo and Moves.displayName and Moves.displayName(last) or "its move"
        ad:say(prefixed(ad, target) .. "'s " .. tostring(name) .. "\nlost " .. (before - mon.pp[i]) .. " PP!")
        break
      end
    end
  end
end

local STATS5 = { "attack", "defense", "spAtk", "spDef", "speed" }

local function changeStats(ad, b, list, delta, flags)
  local okS, Secondary = pcall(require, "src.core.game3.battle.effects.secondary")
  if not okS then return false end
  local any = false
  for _, stat in ipairs(list) do
    if Secondary.changeStat(ad, b, stat, delta, flags) == "worked" then any = true end
  end
  return any
end

local function statOf(b, k)
  local over = b.__ndxStat
  return tonumber(over and over[k]) or tonumber(monOf(b)[k]) or 0
end

local function partnerOf(ad, b)
  local ok, p = pcall(ad.partnerOf, ad, b)
  if ok and p and p ~= b and ad:hp(p) > 0 then return p end
  return nil
end

local function genderOf(b)
  local g = monOf(b).gender
  if g == "M" or g == "F" then return g end
  return nil
end

-- the status moves with a rule of their own (effect byte 250)
local function statusRule(rule, ad, user, target, M)
  local st = ad._st
  if rule == "LASER_FOCUS" then
    if M and M.attackAnimation then M:attackAnimation() end
    user.__ndxLaserFocus = st and st.turn or 0
    ad:say(prefixed(ad, user) .. " concentrated\nintensely!")
  elseif rule == "TAKE_HEART" then
    if ad:status(user) then
      ad:clearStatus(user)
      ad:say(prefixed(ad, user) .. "'s status\nreturned to normal!")
    end
  else
    local okS, Secondary = pcall(require, "src.core.game3.battle.effects.secondary")
    local function anim() if M and M.attackAnimation then M:attackAnimation() end end
    local function fail() if M then M.failed = true end ad:sayFail() end
    local function accuracy(mode)
      if M and M.accuracyCheck then return M:accuracyCheck(mode or "normal", true) end
      return true
    end
    local foe = target and target ~= user and target or nil
    local turn = st and st.turn
    if rule == "WORRY_SEED" or rule == "ENTRAINMENT" or rule == "SIMPLE_BEAM" or rule == "GASTRO_ACID" then
      if not foe or not accuracy("lockon") then return true end
      local cur = abilityOf(ad, foe)
      if cur == "WONDER_GUARD" or (rule == "GASTRO_ACID" and foe.expAbilitySuppressed) then return fail() end
      anim()
      if rule == "GASTRO_ACID" then
        foe.expTracedAbility, foe.expAbilitySuppressed = nil, true
        ad:say(prefixed(ad, foe) .. "'s ability\nwas suppressed!")
      else
        local name = rule == "WORRY_SEED" and "INSOMNIA" or rule == "SIMPLE_BEAM" and "SIMPLE" or abilityOf(ad, user)
        if not name or name == cur then return fail() end
        setAbility(foe, name)
        ad:say(prefixed(ad, foe) .. " acquired\n" .. tostring(name):gsub("_", " ") .. "!")
      end
    elseif rule == "DOODLE" then
      if not foe or not accuracy("lockon") then return true end
      local name = abilityOf(ad, foe)
      if not name or name == "WONDER_GUARD" then return fail() end
      anim()
      for _, b in ipairs({ user, partnerOf(ad, user) }) do if b then setAbility(b, name) end end
      ad:say(prefixed(ad, user) .. " acquired\n" .. tostring(name):gsub("_", " ") .. "!")
    elseif rule == "SOAK" or rule == "MAGIC_POWDER" then
      if not foe or not accuracy() then return true end
      local t = rule == "SOAK" and 11 or 14
      if foe.type1 == t and (foe.type2 == nil or foe.type2 == t) then return fail() end
      anim()
      foe.type1, foe.type2, foe.__ndxType3 = t, nil, nil
      if foe.expTransform then foe.expTransform.type1, foe.expTransform.type2 = t, nil end
      ad:say(prefixed(ad, foe) .. " transformed into\nthe " .. (t == 11 and "WATER" or "PSYCHIC") .. " type!")
    elseif rule == "REFLECT_TYPE" then
      if not foe or (foe.type1 == 9 and foe.type2 == nil) then return fail() end
      anim()
      user.type1, user.type2, user.__ndxType3 = foe.type1, foe.type2, foe.__ndxType3
      if user.expTransform then user.expTransform.type1, user.expTransform.type2 = foe.type1, foe.type2 end
      ad:say(prefixed(ad, user) .. "'s type became\nthe same as " .. prefixed(ad, foe) .. "'s!")
    elseif rule == "TRICK_OR_TREAT" or rule == "FORESTS_CURSE" then
      if not foe or not accuracy() then return true end
      local t = rule == "TRICK_OR_TREAT" and 7 or 12
      if foe.type1 == t or foe.type2 == t or foe.__ndxType3 == t then return fail() end
      anim()
      foe.__ndxType3 = t
      ad:say((t == 7 and "GHOST" or "GRASS") .. " type was added\nto " .. prefixed(ad, foe) .. "!")
    elseif rule == "TAR_SHOT" then
      if not foe or not accuracy() then return true end
      if foe.__ndxTarShot then return fail() end
      anim()
      foe.__ndxTarShot = true
      changeStats(ad, foe, { "speed" }, -1, { allowPtr = true })
      ad:say(prefixed(ad, foe) .. " became weaker\nto fire!")
    elseif rule == "ELECTRIFY" then
      if not foe or foe.__ndxMovedTurn == turn then return fail() end
      anim()
      foe.__ndxElectrified = turn
      ad:say(prefixed(ad, foe) .. "'s moves have been\nelectrified!")
    elseif rule == "ION_DELUGE" then
      anim()
      st.__ndxIonDeluge = turn
      ad:say("A deluge of ions showers\nthe battlefield!")
    elseif rule == "POWER_SPLIT" or rule == "GUARD_SPLIT" then
      if not foe then return fail() end
      anim()
      local keys = rule == "POWER_SPLIT" and { "attack", "spAtk" } or { "defense", "spDef" }
      for _, b in ipairs({ user, foe }) do b.__ndxStat = b.__ndxStat or {} end
      local avg = {}
      for _, k in ipairs(keys) do avg[k] = math.floor((statOf(user, k) + statOf(foe, k)) / 2) end
      for _, k in ipairs(keys) do user.__ndxStat[k], foe.__ndxStat[k] = avg[k], avg[k] end
      ad:say(prefixed(ad, user) .. " shared its\n" .. (rule == "POWER_SPLIT" and "power" or "guard") .. " with the target!")
    elseif rule == "POWER_SWAP" or rule == "GUARD_SWAP" or rule == "HEART_SWAP" then
      if not foe then return fail() end
      anim()
      local keys = rule == "POWER_SWAP" and { "attack", "spAtk" } or rule == "GUARD_SWAP" and { "defense", "spDef" }
        or { "attack", "defense", "spAtk", "spDef", "speed", "accuracy", "evasion" }
      for _, k in ipairs(keys) do
        user.stages[k], foe.stages[k] = foe.stages[k] or 0, user.stages[k] or 0
      end
      ad:say(prefixed(ad, user) .. " switched stat changes\nwith the target!")
    elseif rule == "SPEED_SWAP" then
      if not foe then return fail() end
      anim()
      local a, b = statOf(user, "speed"), statOf(foe, "speed")
      user.__ndxStat, foe.__ndxStat = user.__ndxStat or {}, foe.__ndxStat or {}
      user.__ndxStat.speed, foe.__ndxStat.speed = b, a
      ad:say(prefixed(ad, user) .. " switched SPEED\nwith the target!")
    elseif rule == "POWER_TRICK" then
      anim()
      local a, d = statOf(user, "attack"), statOf(user, "defense")
      user.__ndxStat = user.__ndxStat or {}
      user.__ndxStat.attack, user.__ndxStat.defense = d, a
      ad:say(prefixed(ad, user) .. " switched its\nATTACK and DEFENSE!")
    elseif rule == "TOPSY_TURVY" then
      if not foe or not accuracy() then return true end
      local any = false
      for k, v in pairs(foe.stages) do if (tonumber(v) or 0) ~= 0 then foe.stages[k] = -v any = true end end
      if not any then return fail() end
      anim()
      ad:say(prefixed(ad, foe) .. "'s stat changes\nwere all reversed!")
    elseif rule == "STRENGTH_SAP" then
      if not foe or not accuracy() then return true end
      if (foe.stages.attack or 0) <= -6 then return fail() end
      anim()
      local okD, Damage = pcall(require, "src.core.game3.battle.damage")
      local amount = statOf(foe, "attack")
      if okD and Damage.applyStage then amount = Damage.applyStage(amount, foe.stages.attack or 0) end
      changeStats(ad, foe, { "attack" }, -1, { allowPtr = true })
      if ad:hp(user) < ad:maxHp(user) and (user.__ndxHealBlock or 0) <= 0 then
        ad:heal(user, math.max(1, math.floor(amount)))
        ad:sayText("STRINGID_PKMNREGAINEDHEALTH", { def = user })
      end
    elseif rule == "VENOM_DRENCH" then
      local status = foe and ad:status(foe)
      if not (status == "PSN" or status == "TOX") or not accuracy() then
        if foe and accuracy() then return fail() end
        return true
      end
      anim()
      changeStats(ad, foe, { "attack", "spAtk", "speed" }, -1, { allowPtr = true })
    elseif rule == "CAPTIVATE" then
      if not foe or not accuracy() then return true end
      local g1, g2 = genderOf(user), genderOf(foe)
      if not (g1 and g2 and g1 ~= g2) or abilityOf(ad, foe) == "OBLIVIOUS" then return fail() end
      anim()
      changeStats(ad, foe, { "spAtk" }, -2, { allowPtr = true })
    elseif rule == "ACUPRESSURE" then
      local who = (foe and foe.side == user.side) and foe or user
      local open = {}
      for _, k in ipairs({ "attack", "defense", "spAtk", "spDef", "speed", "accuracy", "evasion" }) do
        if (who.stages[k] or 0) < 6 then open[#open + 1] = k end
      end
      if #open == 0 then return fail() end
      anim()
      changeStats(ad, who, { open[ad:roll(1, #open)] }, 2, { user = who == user, certain = true })
    elseif rule == "CLANGOROUS_SOUL" or rule == "FILLET_AWAY" then
      local cost = rule == "CLANGOROUS_SOUL" and math.floor(ad:maxHp(user) / 3) or math.floor(ad:maxHp(user) / 2)
      local list = rule == "CLANGOROUS_SOUL" and STATS5 or { "attack", "spAtk", "speed" }
      local room = false
      for _, k in ipairs(list) do if (user.stages[k] or 0) < 6 then room = true end end
      if ad:hp(user) <= cost or not room then return fail() end
      anim()
      ad:applyHpLoss(user, cost)
      changeStats(ad, user, list, rule == "CLANGOROUS_SOUL" and 1 or 2, { user = true, certain = true })
    elseif rule == "NO_RETREAT" then
      local room = false
      for _, k in ipairs(STATS5) do if (user.stages[k] or 0) < 6 then room = true end end
      if not room or user.__ndxNoRetreat then return fail() end
      anim()
      changeStats(ad, user, STATS5, 1, { user = true, certain = true })
      if not (user.expTrapped or user.escapePrevention) then
        user.expTrapped, user.escapePrevention, user.__ndxNoRetreat = true, true, true
        ad:say(prefixed(ad, user) .. " can no longer escape\nbecause it used NO RETREAT!")
      end
    elseif rule == "GEAR_UP" or rule == "MAGNETIC_FLUX" then
      local list = rule == "GEAR_UP" and { "attack", "spAtk" } or { "defense", "spDef" }
      local any = false
      for _, b in ipairs({ user, partnerOf(ad, user) }) do
        local ab = b and abilityOf(ad, b)
        if ab == "PLUS" or ab == "MINUS" then
          if not any then anim() end
          if changeStats(ad, b, list, 1, { user = b == user, certain = true }) then any = true end
        end
      end
      if not any then return fail() end
    elseif rule == "ROTOTILLER" or rule == "FLOWER_SHIELD" then
      local any = false
      for _, b in ipairs(ad:activeBattlers()) do
        if ad:hasType(b, 12) and (rule == "FLOWER_SHIELD" or (b.semiInvulnerable == nil and ad:hasType(b, 12))) then
          if not any then anim() end
          local list = rule == "ROTOTILLER" and { "attack", "spAtk" } or { "defense" }
          if changeStats(ad, b, list, 1, { user = b == user, certain = b == user, allowPtr = b ~= user }) then any = true end
        end
      end
      if not any then return fail() end
    elseif rule == "DECORATE" or rule == "AROMATIC_MIST" then
      local ally = partnerOf(ad, user)
      if not ally then return fail() end
      anim()
      if rule == "DECORATE" then changeStats(ad, ally, { "attack", "spAtk" }, 2, { certain = true })
      else changeStats(ad, ally, { "spDef" }, 1, { certain = true }) end
    elseif rule == "STUFF_CHEEKS" then
      local item = itemOf(user)
      if not isBerry(item) or (user.stages.defense or 0) >= 6 then return fail() end
      anim()
      ad:say(prefixed(ad, user) .. " ate its\n" .. itemName(item) .. "!")
      consume(ad, user)
      changeStats(ad, user, { "defense" }, 2, { user = true, certain = true })
    elseif rule == "POWDER" then
      if not foe or not accuracy() then return true end
      anim()
      foe.__ndxPowder = turn
      ad:say(prefixed(ad, foe) .. " is covered\nin powder!")
    elseif rule == "PSYCHO_SHIFT" then
      local status = ad:status(user)
      if not foe or not status or ad:status(foe) or not accuracy() then
        if foe and not (status and not ad:status(foe)) then return fail() end
        return true
      end
      if not ad:applyStatus(foe, status, user) then return fail() end
      anim()
      ad:clearStatus(user)
      ad:say(prefixed(ad, user) .. " transferred its\nstatus to " .. prefixed(ad, foe) .. "!")
    elseif rule == "MIRACLE_EYE" then
      if not foe or foe.__ndxMiracleEye or not accuracy() then
        if foe and foe.__ndxMiracleEye then return fail() end
        return true
      end
      anim()
      foe.expIdentified, foe.__ndxMiracleEye = true, true
      ad:sayText("STRINGID_PKMNIDENTIFIED", { atk = user, def = foe })
    else
      return false
    end
  end
  return true
end

-- Events have to be subscribed when the mod loads; they act once install() has filled _rules.
function MoveRules.hooks(mod)
  mod.events:on("battle.move_used", function(ev)
    local st, user = ev and ev.battle, ev and ev.user
    if type(st) ~= "table" or type(user) ~= "table" then return end
    user.__ndxMovedTurn = st.turn
    user.__ndxGlaiveRush = nil                     -- Glaive Rush lasts until the user moves again
    local num = tonumber(ev.moveNum)
    if not num then return end
    user.__ndxLastMove = num
    local rule = MoveRules._rules[num]
    if rule == "FUSION_FLARE" or rule == "FUSION_BOLT" then st.__ndxFusion = { turn = st.turn, rule = rule } end
    local mon = monOf(user)
    if not (user.__ndxUsed and user.__ndxUsed.mon == mon) then user.__ndxUsed = { mon = mon, moves = {} } end
    user.__ndxUsed.moves[num] = true
    if MoveRules._rules[num] == "ECHOED_VOICE" and not ev.isCalled then
      local e = st.__ndxEcho
      if e and e.turn == st.turn then
        -- a second use the same turn keeps the count
      elseif e and st.turn and e.turn == st.turn - 1 then
        e.turn, e.count = st.turn, math.min(5, e.count + 1)
      else
        st.__ndxEcho = { turn = st.turn, count = 1 }
      end
    end
  end)
  mod.events:on("battle.fainted", function(ev)
    local st, b = ev and ev.battle, ev and ev.battler
    if type(st) ~= "table" or type(b) ~= "table" or not b.side then return end
    st.__ndxFainted = st.__ndxFainted or {}
    st.__ndxFainted[b.side] = st.turn                                -- Retaliate
    st.__ndxFaintCount = st.__ndxFaintCount or {}
    st.__ndxFaintCount[b.side] = (st.__ndxFaintCount[b.side] or 0) + 1   -- Last Respects
  end)
  -- Rage Fist: how often the Pokemon was hit this battle (kept across switches, never saved)
  mod.events:on("battle.damage_dealt", function(ev)
    local st, target = ev and ev.battle, ev and ev.target
    if type(st) ~= "table" or type(target) ~= "table" or ev.substitute or (tonumber(ev.damage) or 0) <= 0 then return end
    st.__ndxHits = st.__ndxHits or setmetatable({}, { __mode = "k" })
    local mon = monOf(target)
    st.__ndxHits[mon] = (st.__ndxHits[mon] or 0) + 1
  end)
  -- Glaive Rush: the user can't dodge until it moves again. A newer damaging move that never
  -- misses (PokeAPI accuracy none -> 0 here: Flower Trick, Clear Smog, Hyperspace Hole...) and
  -- whose effect isn't the cart's ALWAYS_HIT: the engine reads its accuracy 0 as a 0% chance,
  -- so it hits here instead (still not a Pokemon mid-Fly or Dig, as Swift: checked before this)
  mod.hooks:wrap("battle.accuracy", function(nextFn, c)
    if type(c) == "table" and tonumber(c.accuracy) then
      if (c.target and c.target.__ndxGlaiveRush) or MoveRules._neverMiss[tonumber(c.moveNum) or -1] then
        c.accuracy = 100
      end
    end
    return nextFn(c)
  end)
end

-- opts: { moves = src/moves.lua's registered rows, require, log }
function MoveRules.install(opts)
  local require, log = opts.require, opts.log
  local rules, hits, neverMiss = {}, {}, {}
  for _, r in ipairs(opts.moves or {}) do
    if type(r.rule) == "string" and tonumber(r.index) then rules[tonumber(r.index)] = r.rule end
    if r.hits and tonumber(r.index) then hits[tonumber(r.index)] = r.hits end
    if tonumber(r.index) and (tonumber(r.accuracy) or 0) == 0 and (tonumber(r.power) or 0) > 0
        and tonumber(r.effect) ~= ALWAYS_HIT then
      neverMiss[tonumber(r.index)] = true
    end
  end
  MoveRules._rules = rules                        -- a later install replaces what the wraps read
  MoveRules._hits = hits
  MoveRules._neverMiss = neverMiss
  MoveRules._formWeight = opts.formWeight or {}

  local okD, Damage = pcall(require, "src.core.game3.battle.damage")
  local okH, Hit = pcall(require, "src.core.game3.battle.effects.hit")
  local okE, Effects = pcall(require, "src.core.game3.battle.effects")
  if not (okD and okH and type(Damage.calc) == "function" and type(Hit.run) == "function") then
    if log then log:warn("move rules are off: the battle engine's damage functions were not found") end
    return false
  end

  if not Damage.__nationalDexMoveRules then
    Damage.__nationalDexMoveRules = true
    local calc = Damage.calc
    Damage.calc = function(attacker, defender, moveId, o, ...)
      local num = moveNum(moveId)
      local rule = num and MoveRules._rules[num]
      local st = o and o.adapter and o.adapter._st
      local general = type(attacker) == "table" and type(defender) == "table"
        and (attacker.__ndxLaserFocus or defender.__ndxGlaiveRush or attacker.__ndxStat or defender.__ndxStat
             or defender.__ndxType3 or defender.__ndxTarShot or defender.__ndxMiracleEye
             or (attacker.__ndxElectrified and st and attacker.__ndxElectrified == st.turn)
             or (st and st.__ndxIonDeluge == st.turn))
      if not ((rule or general) and type(attacker) == "table" and type(defender) == "table") then
        return calc(attacker, defender, moveId, o, ...)
      end
      local o2 = {}
      for k, v in pairs(o or {}) do o2[k] = v end
      local saved = {}
      local function set(tbl, key, value)
        saved[#saved + 1] = { tbl, key, tbl[key] }
        tbl[key] = value
      end
      local move = type(moveId) == "table" and moveId or {}
      if move.power == nil then
        local okM, Moves = pcall(require, "src.core.game3.battle.moves")
        local okG, m = pcall(Moves.get, num)
        if okM and okG and m then move = m end
      end
      local okP, boost = pcall(prepare, rule, attacker, defender, move, o2, set, num)
      local function restore()
        for i = #saved, 1, -1 do
          local s = saved[i]
          s[1][s[2]] = s[3]
        end
      end
      if not okP then
        restore()
        return calc(attacker, defender, moveId, o, ...)
      end
      local res = { pcall(calc, attacker, defender, moveId, o2, ...) }
      restore()
      if not res[1] then error(res[2], 0) end
      local dmg, info = res[2], res[3]
      if boost and (tonumber(dmg) or 0) > 0 and type(info) == "table"
          and (tonumber(info.effectiveness) or 1) > 1 then
        dmg = math.floor(dmg * 5461 / 4096)
      end
      local okA, d2, i2 = pcall(adjust, rule, attacker, defender, dmg, info)
      if okA then dmg, info = d2, i2 end
      return dmg, info
    end
  end

  -- the status moves with a rule (Laser Focus, Take Heart); every status move's outcome is
  -- stamped for Stomping Tantrum
  if okE and type(Effects.run) == "function" and not Effects.__nationalDexMoveRules then
    Effects.__nationalDexMoveRules = true
    local run = Effects.run
    Effects.run = function(id, ad, user, target, move, moveId, moveCtx, ...)
      local r = run(id, ad, user, target, move, moveId, moveCtx, ...)
      local M = type(moveCtx) == "table" and moveCtx.isMoveContext and moveCtx or nil
      if id == "NATIONAL_DEX_GEN3_MOVE_EFFECT" then
        local num = tonumber(M and M.mnum) or tonumber(moveId)
        local rule = num and MoveRules._rules[num]
        if rule and type(user) == "table" then
          local ok, handled = pcall(statusRule, rule, ad, user, target, M)
          if ok and handled then r = true end
        end
      end
      if M and type(user) == "table" then user.__ndxLastMoveFailed = (M.failed or not r) and true or false end
      return r
    end
  end

  -- Low Kick / Grass Knot against a form: its weight is in forms.lua, not a Pokedex entry
  if type(Damage.lowKickPower) == "function" and not Damage.__nationalDexLowKick then
    Damage.__nationalDexLowKick = true
    local lowKick = Damage.lowKickPower
    Damage.lowKickPower = function(dMon, defender, ...)
      local sp = tonumber(defender and defender.species or (dMon and dMon.species))
      local w = sp and MoveRules._formWeight[sp]
      if w and not (dMon and dMon.weight) then return lowKick({ weight = w }, defender, ...) end
      return lowKick(dMon, defender, ...)
    end
  end

  if not Hit.__nationalDexMoveRules then
    Hit.__nationalDexMoveRules = true
    local hitRun = Hit.run
    Hit.run = function(M, ...)
      if type(M) ~= "table" or not M.user then return hitRun(M, ...) end
      local num = tonumber(M.mnum) or -1
      local rule, nHits = MoveRules._rules[num], MoveRules._hits[num]
      if nHits and type(M.move) == "table" then M.move.hits = (nHits == true) and {} or tonumber(nHits) end
      if not rule then
        local r = hitRun(M, ...)
        M.user.__ndxLastMoveFailed = (M.failed or M.missReason ~= nil) and true or false
        return r
      end
      local okF, fails, msgId, fill = pcall(preFails, rule, M)
      if okF and fails then
        M.user.__ndxLastMoveFailed = true
        M:attackString()
        M:ppReduce()
        M.failed = true
        if M.anim then M.anim.missed = true end
        if msgId then M.adapter:sayText(msgId, fill) else M.adapter:sayFail() end
        return
      end
      -- Sacred Sword & co. ignore evasion too: the stage is hidden for the accuracy check
      local evasion
      if (rule == "SACRED_SWORD" or rule == "DARKEST_LARIAT" or rule == "CHIP_AWAY")
          and M.target and M.target.stages then
        evasion = M.target.stages.evasion
        M.target.stages.evasion = 0
      end
      local res = { pcall(hitRun, M, ...) }
      if evasion and M.target and M.target.stages then M.target.stages.evasion = evasion end
      if not res[1] then error(res[2], 0) end
      pcall(after, rule, M)
      M.user.__ndxLastMoveFailed = (M.failed or M.missReason ~= nil) and true or false
      return res[2]
    end
  end

  local n = 0
  for _ in pairs(rules) do n = n + 1 end
  if log then log:info("move rules: %d moves", n) end
  return true
end

return MoveRules
