-- Damage-formula moves on Gen 1 / Gen 2: variable and conditional power, whose stats the formula
-- reads, critical hits, fixed damage, and the moves that fail before they are used. The numbers
-- are today's (the Gen 3 path's src/move_rules.lua has the same rules); the facts they read come
-- from src/gen12/mech/track.lua (core.track).

return function(core)
  local Track = core.track

  local function hit(t) t.kind = "hit"; return t end
  local STAGES = { "attack", "defense", "spAtk", "spDef", "speed", "accuracy", "evasion" }
  local function boosts(A, b)
    local n, seen = 0, {}
    for _, s in ipairs(STAGES) do
      -- Red's SPECIAL is both Sp. Atk and Sp. Def: count it once
      local v = A:stage(b, s)
      local key = (A.gen == 1 and (s == "spAtk" or s == "spDef")) and "special" or s
      if v > 0 and not seen[key] then n = n + v; seen[key] = true end
    end
    return n
  end
  local function doubled(cond)
    return function(A, u, t, m)
      local base = m.power or 1
      if cond(A, u, t, m) then return base * 2 end
      return base
    end
  end
  local function status(A, b) return A:status(b) end

  -- ------------------------------------------------------------------ conditional power (x2)
  core:rule("HEX", hit({ power = doubled(function(A, u, t) return status(A, t) ~= nil end) }))
  core:rule("VENOSHOCK", hit({ power = doubled(function(A, u, t)
    local s = status(A, t); return s == "PSN" or s == "TOX" end) }))
  core:rule("BRINE", hit({ power = doubled(function(A, u, t) return A:hp(t) * 2 <= A:maxHp(t) end) }))
  core:rule("ACROBATICS", hit({ power = doubled(function(A, u) return not A:item(u) end) }))
  core:rule("ASSURANCE", hit({ power = doubled(function(A, u, t) return (A:vol(t).tookThisTurn or 0) > 0 end) }))
  core:rule("PAYBACK", hit({ power = doubled(function(A, u, t) return Track.movedThisTurn(A, t) end) }))
  local notYet = hit({ power = doubled(function(A, u, t) return not Track.movedThisTurn(A, t) end) })
  core:rule("BOLT_BEAK", notYet)
  core:rule("FISHIOUS_REND", notYet)
  core:rule("RETALIATE", hit({ power = doubled(function(A, u)
    local ft = A:field().faintTurn
    return ft and ft[A:sideName(u)] == A:turn() - 1 or false end) }))
  core:rule("STOMPING_TANTRUM", hit({ power = doubled(function(A, u) return A:vol(u).lastFailed end) }))
  core:rule("FICKLE_BEAM", hit({ power = doubled(function(A) return A:chance(30) end) }))
  local fusion = hit({ power = doubled(function(A, u, t, m)
    local f = A:field().fusionBefore
    return f and f.turn == A:turn() and f.id ~= m.id or false end) })
  core:rule("FUSION_FLARE", fusion)
  core:rule("FUSION_BOLT", fusion)
  -- the damage it took from the target this turn (Revenge, Avalanche)
  core:effect("REVENGE", hit({ power = doubled(function(A, u, t)
    local v = A:vol(u)
    return (v.tookThisTurn or 0) > 0 and v.tookFrom == A:sideName(t) end) }))
  core:effect("FACADE", hit({ power = doubled(function(A, u)
    local s = status(A, u); return s == "BRN" or s == "PSN" or s == "TOX" or s == "PAR" end) }))
  -- x2 against a sleeping / paralysed target, and it wakes / cures it
  local function cures(want, text)
    return function(A, u, t)
      if status(A, t) == want and A:hp(t) > 0 then
        A:cure(t)
        A:say(A:text(text, A:name(t)))
      end
    end
  end
  core:rule("WAKE_UP_SLAP", hit({ power = doubled(function(A, u, t) return status(A, t) == "SLP" end),
    secondary = cures("SLP", "%s woke up!") }))
  core:effect("SMELLINGSALT", hit({ power = doubled(function(A, u, t) return status(A, t) == "PAR" end),
    secondary = cures("PAR", "%s was cured of paralysis!") }))

  -- ------------------------------------------------------------------ computed power
  core:rule("STORED_POWER", hit({ power = function(A, u) return 20 + 20 * boosts(A, u) end }))
  core:rule("POWER_TRIP", hit({ power = function(A, u) return 20 + 20 * boosts(A, u) end }))
  core:rule("PUNISHMENT", hit({ power = function(A, u, t) return math.min(200, 60 + 20 * boosts(A, t)) end }))
  local function weightPower(A, u, t)
    local wa, wd = A:weight(u), A:weight(t)
    local r = (wa and wd) and wa / wd or 1
    return r >= 5 and 120 or r >= 4 and 100 or r >= 3 and 80 or r >= 2 and 60 or 40
  end
  core:rule("HEAVY_SLAM", hit({ power = weightPower }))
  core:rule("HEAT_CRASH", hit({ power = weightPower }))
  -- the target's weight (Low Kick, Grass Knot)
  core:effect("LOW_KICK", hit({ power = function(A, u, t)
    local w = A:weight(t) or 0
    return w < 100 and 20 or w < 250 and 40 or w < 500 and 60 or w < 1000 and 80 or w < 2000 and 100 or 120
  end }))
  core:rule("GYRO_BALL", hit({ power = function(A, u, t)
    return math.min(150, math.floor(25 * A:speed(t) / math.max(1, A:speed(u))) + 1) end }))
  core:rule("ELECTRO_BALL", hit({ power = function(A, u, t)
    local r = A:speed(u) / math.max(1, A:speed(t))
    return r >= 4 and 150 or r >= 3 and 120 or r >= 2 and 80 or r >= 1 and 60 or 40 end }))
  local wring = hit({ power = function(A, u, t) return math.max(1, math.floor(120 * A:hp(t) / A:maxHp(t))) end })
  core:rule("WRING_OUT", wring)
  core:rule("CRUSH_GRIP", wring)
  -- the user's HP (Eruption, Water Spout, Dragon Energy)
  core:effect("ERUPTION", hit({ power = function(A, u)
    return math.max(1, math.floor(150 * A:hp(u) / A:maxHp(u))) end }))
  -- the lower the user's HP the stronger (Flail, Reversal)
  core:effect("FLAIL", hit({ power = function(A, u)
    local p = math.floor(48 * A:hp(u) / A:maxHp(u))
    return p <= 1 and 200 or p <= 4 and 150 or p <= 9 and 100 or p <= 16 and 80 or p <= 32 and 40 or 20 end }))
  core:rule("TRUMP_CARD", hit({ power = function(A, u, t, m)
    local pp
    for _, mv in ipairs(A:moves(u)) do if mv.id == m.id then pp = mv.pp end end
    return pp == 0 and 200 or pp == 1 and 80 or pp == 2 and 60 or pp == 3 and 50 or 40 end }))
  core:rule("ECHOED_VOICE", hit({ power = function(A)
    local e = A:field().echo
    return math.min(200, 40 * ((e and e.count) or 1)) end }))
  core:rule("RAGE_FIST", hit({ power = function(A, u) return math.min(350, 50 + 50 * Track.hits(A, u)) end }))
  core:rule("LAST_RESPECTS", hit({ power = function(A, u) return 50 + 50 * Track.faints(A, A:sideName(u)) end }))
  -- friendship (Return, Frustration)
  core:effect("RETURN", hit({ power = function(A, u)
    return math.max(1, math.floor(A:friendship(u) * 10 / 25)) end }))
  core:effect("FRUSTRATION", hit({ power = function(A, u)
    return math.max(1, math.floor((255 - A:friendship(u)) * 10 / 25)) end }))
  -- 4-10: 5% 10% 20% 30% 20% 10% 5%
  core:effect("MAGNITUDE", hit({ power = function(A)
    local r = A:rng(100)
    local rows = { { 5, 4, 10 }, { 15, 5, 30 }, { 35, 6, 50 }, { 65, 7, 70 }, { 85, 8, 90 }, { 95, 9, 110 }, { 100, 10, 150 } }
    for _, row in ipairs(rows) do
      if r < row[1] then
        A:say(A:text("Magnitude %d!", row[2]))
        return row[3]
      end
    end
    return 70 end }))
  -- Red: the DVs pick the type, as Gold's Hidden Power does; 60 power (Gen 6 on)
  local HIDDEN_TYPES = { "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST", "STEEL",
    "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC", "ICE", "DRAGON", "DARK" }
  core:effect("HIDDEN_POWER", hit({ power = function() return 60 end, type = function(A, u)
    local d = A:dvs(u)
    return HIDDEN_TYPES[((d.attack or 0) % 4) * 4 + ((d.defense or 0) % 4) + 1] end }))
  -- 40% 40, 30% 80, 10% 120, 20% heals the target a quarter instead
  core:effect("PRESENT", hit({
    fail = function(A, u, t)
      local v = A:vol(u)
      v.present = A:rng(100)
      if v.present >= 80 then
        if A:hp(t) >= A:maxHp(t) then return A:text("%s can't receive the gift!", A:name(t)) end
        A:heal(t, math.max(1, math.floor(A:maxHp(t) / 4)), { text = true })
        return ""
      end
      return false
    end,
    power = function(A, u)
      local r = A:vol(u).present or 0
      return r < 40 and 40 or r < 70 and 80 or 120 end }))
  -- one strike per healthy party member (its base Attack / 10 + 5)
  core:effect("BEAT_UP", hit({
    hits = function(A, u)
      local n = 0
      for _, mon in ipairs(A:party(u)) do
        if (mon.hp or 0) > 0 and not mon.status then n = n + 1 end
      end
      return math.max(1, n) end,
    power = function(A, u)
      local r = A:record(u)
      local atk = r and r.baseStats and r.baseStats.attack or 80
      return math.floor(atk / 10) + 5 end }))
  -- 10 / 20 / 30 (Triple Kick), 20 / 40 / 60 (Triple Axel): the middle strike's power each time
  core:effect("TRIPLE_KICK", hit({ hits = 3, power = function(A, u, t, m) return (m.power or 10) * 2 end }))
  -- doubles on each use in a row (Fury Cutter: 40 80 160; Rollout, Ice Ball: up to x16)
  local function ramp(cap)
    return function(A, u, t, m)
      local v = A:vol(u)
      local id = m.id
      if v.ramp and v.ramp.id == id and v.prevMove == id then v.ramp.n = v.ramp.n + 1
      else v.ramp = { id = id, n = 0 } end
      return math.min(cap, (m.power or 1) * 2 ^ v.ramp.n)
    end
  end
  core:effect("FURY_CUTTER", hit({ power = ramp(160) }))
  core:effect("ROLLOUT", hit({ power = ramp(480) }))

  -- ------------------------------------------------------------------ whose stats
  core:rule("FOUL_PLAY", hit({ stats = { attack = "attack", from = "target" } }))
  core:rule("BODY_PRESS", hit({ stats = { attack = "defense" } }))
  core:rule("PSYSHOCK", hit({ stats = { defense = "defense" } }))
  core:rule("SECRET_SWORD", hit({ stats = { defense = "defense" } }))
  core:move("PSYSTRIKE", hit({ stats = { defense = "defense" } }))
  local unaware = hit({ stats = { ignoreDefenseStages = true } })
  core:rule("SACRED_SWORD", unaware)
  core:rule("DARKEST_LARIAT", unaware)
  core:rule("CHIP_AWAY", unaware)

  -- ------------------------------------------------------------------ critical hits
  for _, name in ipairs({ "FROST_BREATH", "STORM_THROW", "WICKED_BLOW", "FLOWER_TRICK" }) do
    core:rule(name, hit({ crit = true, sureHit = name == "FLOWER_TRICK" or nil }))
  end
  core:rule("SURGING_STRIKES", hit({ crit = true, hits = 3 }))

  -- ------------------------------------------------------------------ fixed damage
  core:effect("ENDEAVOR", hit({ fixed = function(A, u, t)
    local d = A:hp(t) - A:hp(u)
    return d > 0 and d or nil end }))
  core:effect("SUPER_FANG", hit({ fixed = function(A, u, t) return math.max(1, math.floor(A:hp(t) / 2)) end }))
  core:rule("FINAL_GAMBIT", hit({
    fixed = function(A, u) return A:hp(u) end,
    after = function(A, u) if A:hp(u) > 0 then A:damage(u, A:hp(u)) end end,
  }))
  -- 1.5x the last damage taken this turn (Metal Burst, Comeuppance); 2x special (Mirror Coat)
  core:rule("METAL_BURST", hit({ fixed = function(A, u)
    local v = A:vol(u)
    if (v.tookThisTurn or 0) <= 0 or not v.lastTaken then return nil end
    return math.floor(v.lastTaken * 3 / 2) end }))
  core:effect("MIRROR_COAT", hit({ fixed = function(A, u)
    local v = A:vol(u)
    if (v.tookThisTurn or 0) <= 0 or v.lastTakenKind ~= "special" or not v.lastTaken then return nil end
    return v.lastTaken * 2 end }))
  -- one-hit KO: the user's level against the target's, 30% + the difference (Sheer Cold 20% unless Ice)
  core:effect("OHKO", hit({
    sureHit = true,
    fail = function(A, u, t, m)
      local diff = A:level(u) - A:level(t)
      if diff < 0 then return A:text("%s is unaffected!", A:name(t)) end
      local base = (m.id == "SHEER_COLD" and not A:hasType(u, "ICE")) and 20 or 30
      if A:rng(100) >= base + diff then return A:text("%s's attack missed!", A:name(u)) end
      return false
    end,
    fixed = function(A, u, t)
      A:say(A:text("It's a one-hit KO!"))
      return A:hp(t)
    end,
  }))
  -- leaves the target 1 HP (False Swipe, Hold Back)
  core:effect("FALSE_SWIPE", hit({ cap = function(A, u, t) return math.max(0, A:hp(t) - 1) end }))

  -- ------------------------------------------------------------------ fails before it is used
  local function firstAction(A, u) return Track.firstAction(A, u) end
  core:effect("FAKE_OUT", hit({
    fail = function(A, u) return not firstAction(A, u) end,
    secondary = function(A, u, t) A:flinch(t) end,
  }))
  core:rule("FIRST_IMPRESSION", hit({ fail = function(A, u) return not firstAction(A, u) end }))
  -- a damaging move the target chose and has not used yet
  core:rule("SUCKER_PUNCH", hit({ fail = function(A, u, t)
    if Track.movedThisTurn(A, t) then return true end
    local id = A:chosen(t)
    local m = id and A:moveDef(id)
    return not (m and (m.power or 0) > 0) end }))
  core:rule("LAST_RESORT", hit({ fail = function(A, u, t, m)
    local used, others = A:vol(u).used or {}, 0
    for _, mv in ipairs(A:moves(u)) do
      if mv.id ~= m.id then
        others = others + 1
        if not used[mv.id] then return true end
      end
    end
    return others == 0 end }))
  core:rule("GIGATON_HAMMER", hit({ fail = function(A, u, t, m) return A:vol(u).prevMove == m.id end }))
  core:rule("SYNCHRONOISE", hit({ fail = function(A, u, t)
    for _, a in ipairs(A:types(u)) do
      if A:hasType(t, a) then return false end
    end
    return true end }))
  -- hit this turn before it moved: it loses its focus (Focus Punch)
  core:effect("FOCUS_PUNCH", hit({ fail = function(A, u)
    if (A:vol(u).tookThisTurn or 0) > 0 then
      return A:text("%s lost its focus and couldn't move!", A:name(u))
    end
    return false end }))
  -- the user's type goes with the move (Burn Up, Double Shock)
  local function spends(typeName, text)
    return hit({
      fail = function(A, u) return not A:hasType(u, typeName) end,
      after = function(A, u, t, m, dealt)
        if dealt <= 0 then return end
        local left = {}
        for _, x in ipairs(A:types(u)) do if x ~= typeName then left[#left + 1] = x end end
        A:setTypes(u, #left > 0 and left or { "NORMAL" })
        A:say(A:text(text, A:name(u)))
      end,
    })
  end
  core:rule("BURN_UP", spends("FIRE", "%s burned itself out!"))
  core:rule("DOUBLE_SHOCK", spends("ELECTRIC", "%s used up all of its electricity!"))

  -- ------------------------------------------------------------------ after the hit
  -- 5461/4096 against a super-effective target (Collision Course, Electro Drift)
  local boostSuper = hit({ mult = function(A, u, t, m, info)
    return (info and (info.typeMult or 10) > 10) and 5461 / 4096 or 1 end })
  core:rule("COLLISION_COURSE", boostSuper)
  core:rule("ELECTRO_DRIFT", boostSuper)
  -- Fighting and Flying at once
  core:rule("FLYING_PRESS", hit({ mult = function(A, u, t)
    return (A:effectiveness("FLYING", t) or 10) / 10 end }))
  core:rule("FELL_STINGER", hit({ after = function(A, u, t, m, dealt)
    if dealt > 0 and A:hp(t) <= 0 and A:hp(u) > 0 then A:stages(u, { attack = 3 }) end end }))
  core:rule("CLEAR_SMOG", hit({ secondary = function(A, u, t)
    local any = false
    for _, s in ipairs(STAGES) do
      if A:stage(t, s) ~= 0 then A:setStage(t, s, 0); any = true end
    end
    if any then A:say(A:text("%s's stat changes were removed!", A:name(t))) end end }))
  core:rule("DIRE_CLAW", hit({ secondary = function(A, u, t, m)
    if A:chance(50) then
      local pick = ({ "POISON", "PARALYSIS", "SLEEP" })[A:rng(3) + 1]
      A:ailment(t, pick, { from = u, secondary = true, moveType = m.type })
    end end }))
  core:rule("SPARKLING_ARIA", hit({ secondary = cures("BRN", "%s's burn was healed!") }))
  -- half the user's HP, hit or miss (Mind Blown, Chloroblast)
  local function halfCost(A, u)
    if A:hp(u) > 0 then
      A:damage(u, math.ceil(A:maxHp(u) / 2), { text = A:text("%s lost half of its HP!", A:name(u)) })
    end
  end
  local costly = hit({ after = function(A, u) halfCost(A, u) end, onMiss = function(A, u) halfCost(A, u) end })
  core:rule("MIND_BLOWN", costly)
  core:rule("CHLOROBLAST", costly)
  core:effect("SECRET_POWER", hit({ secondary = function(A, u, t, m)
    if A:chance(30) then A:ailment(t, "PARALYSIS", { from = u, secondary = true, moveType = m.type }) end end }))

  -- ------------------------------------------------------------------ calls another move
  core:effect("NATURE_POWER", { kind = "status", run = function(A, u, t)
    A:callMove(u, t, "TRI_ATTACK")
    return true end })
end
