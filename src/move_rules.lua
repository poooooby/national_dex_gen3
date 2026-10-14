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

  -- whose stats: Gen 3 splits physical and special by type, so the real move's stat goes into
  -- whichever one the move's type reads (Foul Play is Dark, so the foe's ATTACK stands in
  -- for the user's SP. ATK)
  local aMon, dMon = monOf(A), monOf(D)
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
  end
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
    return false
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
  -- Glaive Rush: the user can't dodge until it moves again
  mod.hooks:wrap("battle.accuracy", function(nextFn, c)
    if type(c) == "table" and c.target and c.target.__ndxGlaiveRush and tonumber(c.accuracy) then c.accuracy = 100 end
    return nextFn(c)
  end)
end

-- opts: { moves = src/moves.lua's registered rows, require, log }
function MoveRules.install(opts)
  local require, log = opts.require, opts.log
  local rules, hits = {}, {}
  for _, r in ipairs(opts.moves or {}) do
    if type(r.rule) == "string" and tonumber(r.index) then rules[tonumber(r.index)] = r.rule end
    if r.hits and tonumber(r.index) then hits[tonumber(r.index)] = r.hits end
  end
  MoveRules._rules = rules                        -- a later install replaces what the wraps read
  MoveRules._hits = hits
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
      local general = type(attacker) == "table" and type(defender) == "table"
        and (attacker.__ndxLaserFocus or defender.__ndxGlaiveRush)
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
