-- The field on Gen 1 / Gen 2: weather, Protect and its kin, entry hazards, side conditions,
-- terrains and rooms. Today's rules; state on the battle's own tables (A:field(), A:side(),
-- A:vol()), never the party Pokemon.
--   weather    Red has none, so rain / sun / sand / hail / snow are all ours there; Gold runs its own
--              rain / sun / sandstorm (A:setWeather hands them over) and gets hail / snow from here
--   Protect    Red has none: a protected battler's foe's move is stopped right after "X used Y!"
--              (core "blocks"); Gold's own protect flag carries ours
--   hazards    on the side they were laid on, met at a switch-in (core "switchedIn")
--   terrains, Trick Room, Gravity, Magic Room, Wonder Room, Tailwind, Aurora Veil, Safeguard,
--   Lucky Chant: counted down at the end of the turn (core "endTurn")

return function(core)
  local function status(t) t.kind = "status"; return t end
  local function hit(t) t.kind = "hit"; return t end
  local function say(A, fmt, ...) A:say(A:text(fmt, ...)) end
  local function sideOf(A, b) return A:side(b) end
  local function foeSide(A, b) return A:side(A:foe(b)) end

  -- on the ground (the terrains, Spikes, Toxic Spikes, Sticky Web)
  local function grounded(A, b)
    if A:field().gravity then return true end
    if A:hasType(b, "FLYING") or A:vol(b).magnetRise then return false end
    return core:ask("ungrounded", A, b) == nil
  end
  core.grounded = grounded

  -- ------------------------------------------------------------------ weather
  local WEATHER = {
    rain = { start = "It started to rain!", go = "Rain continues to fall.", stop = "The rain stopped." },
    sun = { start = "The sunlight turned harsh!", go = "The sunlight is strong.", stop = "The harsh sunlight faded." },
    sand = { start = "A sandstorm kicked up!", go = "The sandstorm is raging.", stop = "The sandstorm subsided.",
      hurt = "%s is buffeted by the sandstorm!", immune = { "ROCK", "GROUND", "STEEL" } },
    hail = { start = "It started to hail!", go = "Hail continues to fall.", stop = "The hail stopped.",
      hurt = "%s is pelted by hail!", immune = { "ICE" } },
    snow = { start = "It started to snow!", go = "Snow continues to fall.", stop = "The snow stopped." },
  }
  local function startWeather(kind)
    return function(A, u)
      if A:weather() == kind then return false end
      A:setWeather(kind, core:fold("weatherTurns", 5, A, u, kind), A:text(WEATHER[kind].start))
      return true
    end
  end
  core:effect("RAIN_DANCE", status({ selfOnly = true, run = startWeather("rain") }))
  core:effect("SUNNY_DAY", status({ selfOnly = true, run = startWeather("sun") }))
  core:effect("SANDSTORM", status({ selfOnly = true, run = startWeather("sand") }))
  core:effect("HAIL", function(row)
    return status({ selfOnly = true, run = startWeather(row.id == "SNOWSCAPE" and "snow" or "hail") })
  end)

  -- the weather's own damage and boosts (Gold already runs rain and sun's)
  core:on("damageMult", function(k, A, u, t, m)
    local w = A:weather()
    local mt = A:moveType(m)
    if (w == "rain" or w == "sun") and (core:ask("ignoresWeather", A, u) or core:ask("ignoresWeather", A, t)) then
      w = nil
    end
    if (w == "rain" or w == "sun") and not A:nativeWeather(w) then
      if mt == "WATER" then k = k * (w == "rain" and 1.5 or 0.5)
      elseif mt == "FIRE" then k = k * (w == "sun" and 1.5 or 0.5) end
    end
    if w == "sand" and A:hasType(t, "ROCK") and A:category(m) == "special" then k = k * 2 / 3 end
    if w == "snow" and A:hasType(t, "ICE") and A:category(m) == "physical" then k = k * 2 / 3 end
    return k
  end)
  core:on("skipCharge", function(A, u, m)
    if A:weather() == "sun" and (m.id == "SOLARBEAM" or m.id == "SOLAR_BEAM" or m.id == "SOLAR_BLADE") then
      return true
    end
  end)
  -- 100 power and the weather's type
  local BALL = { rain = "WATER", sun = "FIRE", sand = "ROCK", hail = "ICE", snow = "ICE" }
  core:effect("WEATHER_BALL", hit({
    power = function(A, u, t, m) return A:weather() and 100 or 50 end,
    type = function(A) return BALL[A:weather() or ""] end,
  }))
  -- 2/3 in the sun, 1/4 in any other weather, else 1/2
  local function sunHeal(A, u)
    if A:hp(u) >= A:maxHp(u) then return false end
    local w = A:weather()
    local f = w == "sun" and 2 / 3 or (w and 1 / 4) or 1 / 2
    A:heal(u, math.max(1, math.floor(A:maxHp(u) * f)), { text = true })
    return true
  end
  for _, name in ipairs({ "MOONLIGHT", "MORNING_SUN", "SYNTHESIS" }) do
    core:effect(name, status({ selfOnly = true, run = sunHeal }))
  end

  -- ------------------------------------------------------------------ Protect and its kin
  -- each use in a row is a third as likely; it stops the foe's moves this turn
  local function protect(kind, text)
    return status({ selfOnly = true, run = function(A, u)
      local v, turn = A:vol(u), A:turn()
      local streak = (v.protectTurn == turn - 1) and (v.protectStreak or 0) or 0
      if streak > 0 and A:rng(3 ^ math.min(streak, 5)) ~= 0 then
        v.protectStreak, v.protectTurn = 0, nil
        return false
      end
      v.protectStreak, v.protectTurn, v.protect, v.protectKind = streak + 1, turn, turn, kind
      if A.gen == 2 then A.battle:volatile(u).protect = true end
      say(A, text or "%s protected itself!", A:name(u))
      return true
    end })
  end
  core:effect("PROTECT", protect(nil))
  for _, kind in ipairs({ "KINGS_SHIELD", "SPIKY_SHIELD", "BANEFUL_BUNKER", "OBSTRUCT", "SILK_TRAP",
      "BURNING_BULWARK" }) do
    core:rule(kind, protect(kind))
  end
  core:effect("ENDURE", status({ selfOnly = true, run = function(A, u)
    local v, turn = A:vol(u), A:turn()
    local streak = (v.protectTurn == turn - 1) and (v.protectStreak or 0) or 0
    if streak > 0 and A:rng(3 ^ math.min(streak, 5)) ~= 0 then
      v.protectStreak, v.protectTurn = 0, nil
      return false
    end
    v.protectStreak, v.protectTurn, v.endure = streak + 1, turn, turn
    if A.gen == 2 then A.battle:volatile(u).endure = true end
    say(A, "%s braced itself!", A:name(u))
    return true
  end }))
  core:on("damageCap", function(A, u, t, m, dmg)
    if A:vol(t).endure == A:turn() and dmg >= A:hp(t) and A:hp(t) > 1 then
      say(A, "%s endured the hit!", A:name(t))
      return A:hp(t) - 1
    end
  end)

  -- what a shield does to an attacker that touched it (the physical moves)
  local function punish(A, u, t, m, kind)
    if not kind or (m.power or 0) == 0 or A:category(m) ~= "physical" or A:hp(u) <= 0 then return end
    if kind == "KINGS_SHIELD" then A:stages(u, { attack = -1 }, { from = t })
    elseif kind == "OBSTRUCT" then A:stages(u, { defense = -2 }, { from = t })
    elseif kind == "SILK_TRAP" then A:stages(u, { speed = -1 }, { from = t })
    elseif kind == "SPIKY_SHIELD" then
      A:damage(u, math.max(1, math.floor(A:maxHp(u) / 8)), { text = A:text("%s was hurt!", A:name(u)) })
    elseif kind == "BANEFUL_BUNKER" then A:ailment(u, "POISON", { from = t })
    elseif kind == "BURNING_BULWARK" then A:ailment(u, "BURN", { from = t }) end
  end
  -- the shields that let status moves through
  local ATTACKS_ONLY = { KINGS_SHIELD = true, OBSTRUCT = true, SILK_TRAP = true }
  -- Red: the move stops here
  core:on("blocks", function(A, u, t, m)
    local v = A:vol(t)
    if v.protect ~= A:turn() or m.id == "FEINT" then return nil end
    if ATTACKS_ONLY[v.protectKind or ""] and (m.power or 0) == 0 then return nil end
    return function()
      say(A, "%s protected itself!", A:name(t))
      punish(A, u, t, m, v.protectKind)
    end
  end)
  -- Gold stopped it with its own flag: the shield's touch
  core:on("afterMove", function(A, u, t, moveId)
    if A.gen ~= 2 then return end
    local v = A:vol(t)
    local ev = A.battle.moveEvent
    if v.protect == A:turn() and v.protectKind and ev and ev.missed and A.battle:volatile(t).protect then
      punish(A, u, t, A:moveDef(moveId) or {}, v.protectKind)
    end
    -- Gold's own Rapid Spin also clears our hazards
    if moveId == "RAPID_SPIN" and not (ev and ev.missed) and A:hp(u) > 0 then
      A:side(u).hazards = nil
    end
  end)
  -- the side's guard this turn (Quick Guard, Wide Guard, Crafty Shield)
  local SPREAD = { EARTHQUAKE = true, MAGNITUDE = true, SURF = true, ROCK_SLIDE = true, EXPLOSION = true,
    SELFDESTRUCT = true, BLIZZARD = true, RAZOR_LEAF = true, ICY_WIND = true, HEAT_WAVE = true,
    HYPER_VOICE = true, BULLDOZE = true, DISCHARGE = true, SLUDGE_WAVE = true, LAVA_PLUME = true }
  local function guarded(A, kind, m)
    if kind == "QUICK_GUARD" then return A:basePriority(m) > 0 end
    if kind == "WIDE_GUARD" then return SPREAD[m.id] or false end
    if kind == "CRAFTY_SHIELD" then return (m.power or 0) == 0 end
    return false
  end
  local function guard(kind, text)
    return status({ selfOnly = true, run = function(A, u)
      A:side(u).guard = { kind = kind, turn = A:turn() }
      if A.gen == 2 then
        -- Gold: its own protect flag, when the foe chose a move this stops
        local id = A:chosen(A:foe(u))
        local m = id and A:moveDef(id)
        if m and guarded(A, kind, m) then A.battle:volatile(u).protect = true end
      end
      say(A, text, A:name(u))
      return true
    end })
  end
  core:rule("QUICK_GUARD", guard("QUICK_GUARD", "Quick Guard protected %s's team!"))
  core:rule("WIDE_GUARD", guard("WIDE_GUARD", "Wide Guard protected %s's team!"))
  core:rule("CRAFTY_SHIELD", guard("CRAFTY_SHIELD", "Crafty Shield protected %s's team!"))
  core:on("blocks", function(A, u, t, m)
    local g = A:side(t).guard
    if g and g.turn == A:turn() and guarded(A, g.kind, m) then
      return function() say(A, "%s protected itself!", A:name(t)) end
    end
  end)
  -- breaks through and lifts a protection
  core:rule("FEINT", hit({ sureHit = true, ignoresProtect = true, fail = function(A, u, t)
    local v = A:vol(t)
    local was = v.protect == A:turn() or (A.gen == 2 and A.battle:volatile(t).protect)
    if was then
      v.protect = nil
      if A.gen == 2 then A.battle:volatile(t).protect = nil end
      say(A, "%s fell for the feint!", A:name(t))
    end
    return false
  end }))

  -- ------------------------------------------------------------------ entry hazards
  local function hazards(A, b)
    local s = sideOf(A, b)
    s.hazards = s.hazards or {}
    return s.hazards
  end
  local function lay(field, max, text)
    return function(A, u)
      local h = hazards(A, A:foe(u))
      if max == 1 then
        if h[field] then return false end
        h[field] = true
      else
        if (h[field] or 0) >= max then return false end
        h[field] = (h[field] or 0) + 1
      end
      say(A, text, A:name(A:foe(u)))
      return true
    end
  end
  core:effect("SPIKES", status({ run = lay("spikes", 3, "Spikes were scattered around %s's feet!") }))
  core:rule("STEALTH_ROCK", status({ run = lay("rocks", 1, "Pointed stones float in the air around %s!") }))
  core:rule("TOXIC_SPIKES", status({ run = lay("toxic", 2, "Poison spikes were scattered around %s's feet!") }))
  core:rule("STICKY_WEB", status({ run = lay("web", 1, "A sticky web spreads out around %s!") }))
  core:rule("CEASELESS_EDGE", hit({ after = function(A, u, t, m, dealt)
    if dealt > 0 then lay("spikes", 3, "Spikes were scattered around %s's feet!")(A, u) end end }))
  core:rule("STONE_AXE", hit({ after = function(A, u, t, m, dealt)
    if dealt > 0 then lay("rocks", 1, "Pointed stones float in the air around %s!")(A, u) end end }))
  core:on("switchedIn", function(A, ev)
    local b = ev.battler
    if not b or A:hp(b) <= 0 then return end
    local h = sideOf(A, b).hazards
    if not h or core:ask("hazardImmune", A, b) then return end
    local max = A:maxHp(b)
    if h.rocks then
      local eff = A:effectiveness("ROCK", b) or 10
      A:damage(b, math.max(1, math.floor(max * eff / 80)),
        { text = A:text("Pointed stones dug into %s!", A:name(b)) })
    end
    if A:hp(b) > 0 and (h.spikes or 0) > 0 and grounded(A, b) then
      local d = ({ 8, 6, 4 })[math.min(3, h.spikes)]
      A:damage(b, math.max(1, math.floor(max / d)), { text = A:text("%s was hurt by the spikes!", A:name(b)) })
    end
    if A:hp(b) > 0 and (h.toxic or 0) > 0 and grounded(A, b) then
      if A:hasType(b, "POISON") then
        h.toxic = nil
        say(A, "The poison spikes disappeared from around %s's feet!", A:name(b))
      elseif not A:hasType(b, "STEEL") then
        A:ailment(b, h.toxic >= 2 and "TOXIC" or "POISON", {})
      end
    end
    if A:hp(b) > 0 and h.web and grounded(A, b) then
      say(A, "%s was caught in a sticky web!", A:name(b))
      A:stages(b, { speed = -1 }, { from = A:foe(b) })
    end
  end)
  local function clearOwn(A, u)
    local s = sideOf(A, u)
    if s.hazards then s.hazards = nil end
    A:vol(u).seeded = nil
  end
  core:effect("RAPID_SPIN", hit({ after = function(A, u, t, m, dealt)
    if dealt > 0 and A:hp(u) > 0 then
      clearOwn(A, u)
      u.leechSeeded = nil
      A:stages(u, { speed = 1 })
    end end }))
  core:rule("MORTAL_SPIN", hit({
    after = function(A, u, t, m, dealt) if dealt > 0 and A:hp(u) > 0 then clearOwn(A, u) end end,
    secondary = function(A, u, t, m) A:ailment(t, "POISON", { from = u, secondary = true, moveType = m.type }) end,
  }))
  core:rule("DEFOG", status({ aimed = true, run = function(A, u, t)
    A:stages(t, { evasion = -1 }, { from = u })
    A:side(u).hazards, A:side(t).hazards = nil, nil
    local s = A:side(t)
    s.auroraVeil, s.safeguard, s.luckyChant = nil, nil, nil
    if A.gen == 1 then t.reflect, t.lightScreen = nil, nil
    else
      local screens = A.battle.screens and A.battle.screens[A:sideName(t)]
      if screens then screens.reflect, screens.lightScreen, screens.safeguard = 0, 0, 0 end
    end
    return true
  end }))
  core:rule("COURT_CHANGE", status({ selfOnly = true, run = function(A, u)
    local mine, theirs = A:side(u), A:side(A:foe(u))
    local keys = { "hazards", "auroraVeil", "tailwind", "safeguard", "luckyChant" }
    for _, k in ipairs(keys) do mine[k], theirs[k] = theirs[k], mine[k] end
    say(A, "%s swapped the battle effects affecting each side of the field!", A:name(u))
    return true
  end }))

  -- ------------------------------------------------------------------ side conditions
  local function sideTurns(field, turns, text, need)
    return status({ selfOnly = true, run = function(A, u)
      if need and not need(A, u) then return false end
      local s = sideOf(A, u)
      if (s[field] or 0) > 0 then return false end
      s[field] = (field == "auroraVeil") and core:fold("screenTurns", turns, A, u) or turns
      say(A, text, A:name(u))
      return true
    end })
  end
  core:rule("AURORA_VEIL", sideTurns("auroraVeil", 5, "Aurora Veil made %s's team stronger against attacks!",
    function(A) local w = A:weather(); return w == "hail" or w == "snow" end))
  core:rule("TAILWIND", sideTurns("tailwind", 4, "The tailwind blew from behind %s's team!"))
  core:rule("LUCKY_CHANT", sideTurns("luckyChant", 5, "Lucky Chant shielded %s's team from critical hits!"))
  core:effect("SAFEGUARD", sideTurns("safeguard", 5, "%s's team cloaked itself in a mystical veil!"))
  core:on("damageMult", function(k, A, u, t, m, info)
    if (A:side(t).auroraVeil or 0) > 0 and not (info and (info.crit or info.critical)) then k = k * 0.5 end
    return k
  end)
  core:on("speed", function(s, A, b)
    if (A:side(b).tailwind or 0) > 0 then return s * 2 end
    return s
  end)
  core:on("noCrit", function(A, attacker, target)
    if target and (A:side(target).luckyChant or 0) > 0 then return true end
  end)
  core:on("blockStatus", function(A, b, s, opts)
    local from = opts and opts.from
    if from and from ~= b and (A:side(b).safeguard or 0) > 0 then
      return A:text("%s is protected by Safeguard!", A:name(b))
    end
  end)

  -- ------------------------------------------------------------------ terrains
  local TERRAIN = {
    ELECTRIC = { start = "An electric current ran across the battlefield!",
      stop = "The electricity disappeared from the battlefield.", boost = "ELECTRIC" },
    GRASSY = { start = "Grass grew to cover the battlefield!",
      stop = "The grass disappeared from the battlefield.", boost = "GRASS" },
    MISTY = { start = "Mist swirled around the battlefield!",
      stop = "The mist disappeared from the battlefield." },
    PSYCHIC = { start = "The battlefield got weird!",
      stop = "The weirdness disappeared from the battlefield!", boost = "PSYCHIC" },
  }
  local function terrain(A) local t = A:field().terrain; return t and t.kind or nil end
  core.terrain = terrain
  for kind, row in pairs(TERRAIN) do
    core:rule(kind .. "_TERRAIN", status({ selfOnly = true, run = function(A, u)
      if terrain(A) == kind then return false end
      A:field().terrain = { kind = kind, turns = core:fold("terrainTurns", 5, A, u) }
      say(A, row.start)
      return true
    end }))
  end
  local HALVED_BY_GRASS = { EARTHQUAKE = true, BULLDOZE = true, MAGNITUDE = true }
  core:on("damageMult", function(k, A, u, t, m)
    local tk = terrain(A)
    if not tk then return k end
    local mt = A:moveType(m)
    local row = TERRAIN[tk]
    if row.boost and mt == row.boost and grounded(A, u) then k = k * 1.3 end
    if tk == "MISTY" and mt == "DRAGON" and grounded(A, t) then k = k * 0.5 end
    if tk == "GRASSY" and HALVED_BY_GRASS[m.id] and grounded(A, t) then k = k * 0.5 end
    return k
  end)
  core:on("blockStatus", function(A, b, s)
    local tk = terrain(A)
    if not tk or not grounded(A, b) then return nil end
    if tk == "MISTY" then return A:text("%s surrounds itself with a protective mist!", A:name(b)) end
    if tk == "ELECTRIC" and s == "SLP" then return A:text("%s is protected by the Electric Terrain!", A:name(b)) end
  end)
  core:on("blocks", function(A, u, t, m)
    if terrain(A) == "PSYCHIC" and A:basePriority(m) > 0 and grounded(A, t) then
      return function() say(A, "%s is protected by the Psychic Terrain!", A:name(t)) end
    end
  end)
  local PULSE = { ELECTRIC = "ELECTRIC", GRASSY = "GRASS", MISTY = "FAIRY", PSYCHIC = "PSYCHIC" }
  core:rule("TERRAIN_PULSE", hit({
    power = function(A, u, t, m) return (terrain(A) and grounded(A, u)) and (m.power or 50) * 2 or m.power end,
    type = function(A, u) return grounded(A, u) and PULSE[terrain(A) or ""] or nil end,
  }))
  core:rule("RISING_VOLTAGE", hit({ power = function(A, u, t, m)
    return (terrain(A) == "ELECTRIC" and grounded(A, t)) and (m.power or 70) * 2 or m.power end }))
  core:rule("EXPANDING_FORCE", hit({ power = function(A, u, t, m)
    return (terrain(A) == "PSYCHIC" and grounded(A, u)) and math.floor((m.power or 80) * 3 / 2) or m.power end }))
  core:rule("STEEL_ROLLER", hit({
    fail = function(A) return terrain(A) == nil end,
    after = function(A) A:field().terrain = nil end,
  }))

  -- ------------------------------------------------------------------ rooms
  local function room(field, startText, stopText)
    return status({ selfOnly = true, run = function(A, u)
      local f = A:field()
      if f[field] then
        f[field] = nil
        say(A, stopText)
      else
        f[field] = 5
        say(A, startText, A:name(u))
      end
      return true
    end })
  end
  core:rule("TRICK_ROOM", room("trickRoom", "%s twisted the dimensions!", "The twisted dimensions returned to normal!"))
  core:rule("GRAVITY", room("gravity", "Gravity intensified!", "Gravity returned to normal!"))
  core:rule("MAGIC_ROOM", room("magicRoom", "It created a bizarre area in which Pokemon's held items lose their effects!",
    "Magic Room wore off, and held items' effects returned to normal!"))
  core:rule("WONDER_ROOM", room("wonderRoom", "It created a bizarre area in which Defense and Sp. Def stats are swapped!",
    "Wonder Room wore off, and Defense and Sp. Def stats returned to normal!"))
  core:on("trickRoom", function(A) if A:field().trickRoom then return true end end)
  core:on("damageMult", function(k, A, u, t, m)
    if not A:field().wonderRoom then return k end
    local def, spd = A:stat(t, "defense"), A:stat(t, "spDef")
    if A:category(m) == "physical" then return k * def / math.max(1, spd) end
    return k * spd / math.max(1, def)
  end)

  -- ------------------------------------------------------------------ the end of the turn
  local SIDE_ENDS = { auroraVeil = "%s's team's Aurora Veil wore off!", tailwind = "%s's team's tailwind petered out!",
    luckyChant = "%s's team's Lucky Chant wore off!", safeguard = "%s's team is no longer protected by Safeguard!" }
  local FIELD_ENDS = { trickRoom = "The twisted dimensions returned to normal!",
    gravity = "Gravity returned to normal!",
    magicRoom = "Magic Room wore off, and held items' effects returned to normal!",
    wonderRoom = "Wonder Room wore off, and Defense and Sp. Def stats returned to normal!" }
  core:on("endTurn", function(A)
    local f = A:field()
    local p, e = A:battlers()
    -- our weather
    local w = f.weather
    if w then
      w.turns = w.turns - 1
      local row = WEATHER[w.kind]
      if w.turns <= 0 then
        f.weather = nil
        say(A, row.stop)
      else
        say(A, row.go)
        if row.hurt then
          for _, b in ipairs({ p, e }) do
            local immune = false
            for _, ty in ipairs(row.immune) do if A:hasType(b, ty) then immune = true end end
            if b and A:hp(b) > 0 and not immune and not core:ask("weatherImmune", A, b) then
              A:damage(b, math.max(1, math.floor(A:maxHp(b) / 16)), { text = A:text(row.hurt, A:name(b)) })
            end
          end
        end
      end
    end
    -- the terrain
    local tr = f.terrain
    if tr then
      if tr.kind == "GRASSY" then
        for _, b in ipairs({ p, e }) do
          if b and A:hp(b) > 0 and A:hp(b) < A:maxHp(b) and grounded(A, b) then
            A:heal(b, math.max(1, math.floor(A:maxHp(b) / 16)),
              { text = A:text("%s's HP was restored.", A:name(b)) })
          end
        end
      end
      tr.turns = tr.turns - 1
      if tr.turns <= 0 then
        f.terrain = nil
        say(A, TERRAIN[tr.kind].stop)
      end
    end
    -- the sides' conditions
    for _, b in ipairs({ p, e }) do
      if b then
        local s = A:side(b)
        for key, text in pairs(SIDE_ENDS) do
          if (s[key] or 0) > 0 then
            s[key] = s[key] - 1
            if s[key] <= 0 then
              s[key] = nil
              say(A, text, A:name(b))
            end
          end
        end
      end
    end
    -- the rooms
    for key, text in pairs(FIELD_ENDS) do
      if f[key] then
        f[key] = f[key] - 1
        if f[key] <= 0 then
          f[key] = nil
          say(A, text)
        end
      end
    end
  end)
end
