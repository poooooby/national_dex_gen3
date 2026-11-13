-- Abilities on Gen 1 / Gen 2, neither of which has any.
--
-- Each Pokemon has one of its species' abilities (data/gen12/battle.lua `abilities`, by dex
-- number and form): the first or, when there is one, the second, picked from its DVs, so it keeps
-- it for good and nothing new is saved (the hidden ability is not picked). A move can change it for
-- the battle (Skill Swap, Worry Seed, Gastro Acid: A:vol(b).ability).
--
-- What an ability does is data/gen12/abilities.lua's `b` (tools/ability_behaviour.py's
-- vocabulary), run here on the core hooks: stat and damage multipliers, crits, priority, status and
-- type immunities, healing and stat changes on a trigger, weather and terrain on entry, a contact
-- punished. CONDITION adds what the data leaves to the battle code (Swift Swim's rain, Guts'
-- status, Technician's 60 power ...); a few are written out in full (Sturdy, Wonder Guard, Battle
-- Armor, Multiscale, Shed Skin, Natural Cure).

return function(core, opts)
  local load = opts.load
  local ABILITIES = (load and load("data/gen12/abilities.lua")) or {}
  local facts = core.facts or {}
  local function say(A, fmt, ...) A:say(A:text(fmt, ...)) end
  local STAT = { attack = "attack", defense = "defense", ["special-attack"] = "spAtk",
    ["special-defense"] = "spDef", speed = "speed", accuracy = "accuracy", evasion = "evasion" }
  local STATUS = { paralysis = "PAR", freeze = "FRZ", burn = "BRN", sleep = "SLP", poison = "PSN",
    confusion = "CONFUSION" }
  local AILMENT = { paralysis = "PARALYSIS", freeze = "FREEZE", burn = "BURN", sleep = "SLEEP", poison = "POISON",
    confusion = "CONFUSION" }

  -- ------------------------------------------------------------------ whose ability
  local function speciesList(A, b)
    local r = A:record(b)
    if r and r.form and facts.formAbilities then
      local list = facts.formAbilities[r.id]
      if list then return list end
    end
    local dex = A:dex(b)
    return dex and facts.abilities and facts.abilities[dex] or nil
  end
  -- the Pokemon's ability id, or nil (suppressed, or none known)
  local function abilityOf(A, b)
    if not b then return nil end
    local v = A:vol(b)
    if v.abilitySuppressed then return nil end
    if v.ability then return v.ability end
    local list = speciesList(A, b)
    if not list then return nil end
    local first, second = list[1], list[2]
    if second and second ~= false then
      local d = A:dvs(b)
      if (d.defense or 0) % 2 == 1 then return second end
    end
    return first ~= false and first or nil
  end
  core.abilityOf = abilityOf
  core:on("ability", function(A, b) return abilityOf(A, b) end)
  local function nameOf(id) local a = ABILITIES[id]; return a and a.name or (id and tostring(id)) or "" end
  core.abilityName = nameOf

  -- ------------------------------------------------------------------ conditions
  local function weather(A) return A:weather() end
  local function statused(A, b) return A:status(b) ~= nil end
  local CONDITION = {
    SWIFTSWIM = function(A) return weather(A) == "rain" end,
    CHLOROPHYLL = function(A) return weather(A) == "sun" end,
    SANDRUSH = function(A) return weather(A) == "sand" end,
    SLUSHRUSH = function(A) local w = weather(A); return w == "hail" or w == "snow" end,
    SOLARPOWER = function(A) return weather(A) == "sun" end,
    SANDVEIL = function(A) return weather(A) == "sand" end,
    SNOWCLOAK = function(A) local w = weather(A); return w == "hail" or w == "snow" end,
    GUTS = statused, MARVELSCALE = statused, QUICKFEET = statused,
    TOXICBOOST = function(A, b) local s = A:status(b); return s == "PSN" or s == "TOX" end,
    FLAREBOOST = function(A, b) return A:status(b) == "BRN" end,
    TECHNICIAN = function(A, b, m) return m and (m.power or 0) > 0 and (m.power or 0) <= 60 end,
    PRANKSTER = function(A, b, m) return m and (m.power or 0) == 0 end,
    GALEWINGS = function(A, b, m) return m and A:moveType(m) == "FLYING" and A:hp(b) >= A:maxHp(b) end,
    MULTISCALE = function(A, b) return A:hp(b) >= A:maxHp(b) end,
    SHADOWSHIELD = function(A, b) return A:hp(b) >= A:maxHp(b) end,
    FLOWERGIFT = function(A) return weather(A) == "sun" end,
    SANDFORCE = function(A) return weather(A) == "sand" end,
    HUSTLE = function(A, b, m) return m and A:category(m) == "physical" end,
  }
  -- the data's own "when" phrases
  local function whenHolds(A, b, m, when, ability)
    if when == nil then return true end
    when = tostring(when):lower()
    if when:find("1/3") then return A:hp(b) * 3 <= A:maxHp(b) end
    if when:find("stab") then
      return m and A:hasType(b, A:moveType(m)) or false
    end
    for _, w in ipairs({ "rain", "sun", "sand", "hail", "snow" }) do
      if when:find(w) then
        local now = weather(A)
        return now == w or (w == "sand" and now == "sand") or (w == "hail" and now == "snow")
      end
    end
    if when:find("full hp") then return A:hp(b) >= A:maxHp(b) end
    if when:find("status") then return statused(A, b) end
    return true
  end
  local function behaviourOf(id)
    local a = ABILITIES[id]
    return a and a.b
  end
  local function holds(A, b, m, id)
    local c = CONDITION[id]
    return c == nil or c(A, b, m) and true or false
  end

  -- each effect of a battler's ability of `kind`: fn(effect, behaviour, id)
  local function each(A, b, kind, fn, m)
    local id = abilityOf(A, b)
    local beh = id and behaviourOf(id)
    if not beh or not holds(A, b, m, id) then return end
    for _, e in ipairs(beh.effects or {}) do
      if e.kind == kind then fn(e, beh, id) end
    end
  end

  -- ------------------------------------------------------------------ passive: damage, speed, crits
  core:on("damageMult", function(k, A, u, t, m)
    local mt, cat = A:moveType(m), A:category(m)
    each(A, u, "damage_dealt_multiplier", function(e, beh, id)
      if (not e.moveType or e.moveType == mt) and whenHolds(A, u, m, e.when, id) then
        -- Adaptability's 2x STAB replaces the game's own 1.5x
        k = k * (id == "ADAPTABILITY" and 4 / 3 or e.factor)
      end
    end, m)
    each(A, u, "stat_multiplier", function(e)
      if (e.stat == "attack" and cat == "physical") or (e.stat == "special-attack" and cat == "special") then
        k = k * e.factor
      end
    end, m)
    each(A, t, "damage_taken_multiplier", function(e, beh, id)
      if (not e.moveType or e.moveType == mt) and whenHolds(A, t, m, e.when, id) then k = k * e.factor end
    end, m)
    each(A, t, "stat_multiplier", function(e)
      if (e.stat == "defense" and cat == "physical") or (e.stat == "special-defense" and cat == "special") then
        k = k / e.factor
      end
    end, m)
    -- Multiscale, Shadow Shield: half at full HP
    local ta = abilityOf(A, t)
    if (ta == "MULTISCALE" or ta == "SHADOWSHIELD") and A:hp(t) >= A:maxHp(t) then k = k * 0.5 end
    return k
  end)
  core:on("speed", function(s, A, b)
    each(A, b, "stat_multiplier", function(e) if e.stat == "speed" then s = s * e.factor end end)
    return s
  end)
  core:on("priority", function(p, A, b, m)
    each(A, b, "priority_change", function(e) p = p + (e.amount or 0) end, m)
    return p
  end)
  core:on("forceCrit", function(A, b)
    local hit = false
    each(A, b, "crit_change", function(e) if e.always then hit = true end end)
    if hit then return true end
  end)
  core:on("noCrit", function(A, attacker, target)
    local id = target and abilityOf(A, target)
    if id == "BATTLEARMOR" or id == "SHELLARMOR" then return true end
  end)
  core:on("accuracy", function(A, u, t, m)
    -- an evasion boost on the target (Sand Veil, Snow Cloak): a fifth of moves miss
    local miss = false
    each(A, t, "stat_multiplier", function(e) if e.stat == "evasion" and A:rng(5) == 0 then miss = true end end, m)
    if miss then return false end
  end)

  -- ------------------------------------------------------------------ immunities
  core:on("blockStatus", function(A, b, s)
    local id = abilityOf(A, b)
    local beh = id and behaviourOf(id)
    if not beh or not holds(A, b, nil, id) then return nil end
    for _, e in ipairs(beh.effects or {}) do
      if e.kind == "status_immunity" then
        local want = e.status
        if want == "any" or (want == "major" and s ~= "CONFUSION") or STATUS[want] == s
            or (want == "poison" and s == "TOX") then
          return A:text("%s's %s prevents it!", A:name(b), nameOf(id))
        end
      end
    end
  end)
  -- a type it is immune to; the absorbing ones heal or rise instead
  core:on("immune", function(A, u, t, m)
    local id = abilityOf(A, t)
    local beh = id and behaviourOf(id)
    if not beh or u == t then return nil end
    local mt = A:moveType(m)
    local immune = false
    for _, e in ipairs(beh.effects or {}) do
      if e.kind == "type_immunity" and e.moveType == mt then immune = true end
    end
    if not immune then return nil end
    -- what it does with the hit (Water Absorb heals, Motor Drive and Lightning Rod raise a stat)
    for _, e in ipairs(beh.effects or {}) do
      if e.kind == "heal" and A:hp(t) < A:maxHp(t) then
        A:heal(t, math.max(1, math.floor(A:maxHp(t) * (e.fraction or 0.25))))
        say(A, "%s's %s restored its HP!", A:name(t), nameOf(id))
      elseif e.kind == "stat_change" and STAT[e.stat] then
        A:stages(t, { [STAT[e.stat]] = e.stages or 1 })
      end
    end
    return true
  end)
  -- Wonder Guard: only a super-effective hit lands
  core:on("immune", function(A, u, t, m)
    if abilityOf(A, t) == "WONDERGUARD" and (m.power or 0) > 0 and u ~= t then
      local eff = A:effectiveness(A:moveType(m), t) or 10
      if eff <= 10 then return true end
    end
  end)
  core:on("ungrounded", function(A, b) if abilityOf(A, b) == "LEVITATE" then return true end end)
  -- Sturdy: a full-HP Pokemon survives with 1 HP
  core:on("damageCap", function(A, u, t, m, dmg)
    if abilityOf(A, t) == "STURDY" and A:hp(t) >= A:maxHp(t) and dmg >= A:hp(t) and A:hp(t) > 1 then
      say(A, "%s endured the hit!", A:name(t))
      return A:hp(t) - 1
    end
  end)

  -- ------------------------------------------------------------------ triggers
  local function apply(A, b, beh, id, foe)
    for _, e in ipairs(beh.effects or {}) do
      local who = (beh.scope == "foes") and foe or b
      if e.kind == "stat_change" and STAT[e.stat] and who and A:hp(who) > 0 then
        say(A, "%s's %s!", A:name(b), nameOf(id))
        A:stages(who, { [STAT[e.stat]] = e.stages or 1 }, who ~= b and { from = b } or nil)
      elseif e.kind == "set_weather" then
        local w = ({ rain = "rain", sun = "sun", sandstorm = "sand", hail = (id == "SNOWWARNING") and "snow" or "hail" })[e.weather]
        if w and A:weather() ~= w then
          say(A, "%s's %s!", A:name(b), nameOf(id))
          local text = ({ rain = "It started to rain!", sun = "The sunlight turned harsh!",
            sand = "A sandstorm kicked up!", hail = "It started to hail!", snow = "It started to snow!" })[w]
          A:setWeather(w, 5, A:text(text))
        end
      elseif e.kind == "set_terrain" then
        local kind = tostring(e.terrain or ""):upper()
        local f = A:field()
        if kind ~= "" and not (f.terrain and f.terrain.kind == kind) then
          say(A, "%s's %s!", A:name(b), nameOf(id))
          f.terrain = { kind = kind, turns = 5 }
        end
      elseif e.kind == "heal" and A:hp(b) > 0 and A:hp(b) < A:maxHp(b) and whenHolds(A, b, nil, e.when, id) then
        A:heal(b, math.max(1, math.floor(A:maxHp(b) * (e.fraction or 0.0625))),
          { text = A:text("%s's %s restored its HP!", A:name(b), nameOf(id)) })
      elseif e.kind == "damage_self" and A:hp(b) > 0 and whenHolds(A, b, nil, e.when, id) then
        A:damage(b, math.max(1, math.floor(A:maxHp(b) * (e.fraction or 0.125))))
      end
    end
  end
  local function entered(A, b)
    if not b or A:hp(b) <= 0 then return end
    local v = A:vol(b)
    if v.abilityEntered then return end
    v.abilityEntered = true
    local id = abilityOf(A, b)
    local beh = id and behaviourOf(id)
    if beh and beh.trigger == "switch_in" and holds(A, b, nil, id) then apply(A, b, beh, id, A:foe(b)) end
  end
  core:on("switchedIn", function(A, ev) entered(A, ev.battler) end)
  core:on("battleStarted", function(A)
    local p, e = A:battlers()
    entered(A, p); entered(A, e)
  end)
  -- the first turn of a battle that began without the event (and any battler not yet seen)
  core:on("turnStarted", function(A)
    local p, e = A:battlers()
    entered(A, p); entered(A, e)
  end)
  core:on("endTurn", function(A)
    for _, b in ipairs({ A:battlers() }) do
      if b and A:hp(b) > 0 then
        local id = abilityOf(A, b)
        local beh = id and behaviourOf(id)
        if beh and beh.trigger == "turn_end" and holds(A, b, nil, id) then apply(A, b, beh, id, A:foe(b)) end
        -- Shed Skin: a third of the time, its status is cured
        if id == "SHEDSKIN" and A:status(b) and A:rng(3) == 0 then
          A:cure(b)
          say(A, "%s's %s cured its status!", A:name(b), nameOf(id))
        end
      end
    end
  end)
  -- hit: what the hit Pokemon's ability does back (contact: the physical moves)
  core:on("damageDealt", function(A, ev)
    local u, t, m = ev.user, ev.target, ev.move
    if not (u and t and m) or u == t or A:hp(u) <= 0 then return end
    local id = abilityOf(A, t)
    local beh = id and behaviourOf(id)
    if not beh then return end
    if beh.trigger == "on_contact_taken" and A:category(m) == "physical" then
      if beh.chance and A:rng(100) >= beh.chance then return end
      local effects = beh.effects or {}
      local list = {}
      for _, e in ipairs(effects) do list[#list + 1] = e end
      -- Effect Spore: one of its statuses
      local e = (#list > 1 and list[1].kind == "inflict_status") and list[A:rng(#list) + 1] or nil
      for _, x in ipairs(e and { e } or list) do
        if x.kind == "inflict_status" and AILMENT[x.status] then
          A:ailment(u, AILMENT[x.status], { from = t, secondary = true })
        elseif x.kind == "damage" then
          A:damage(u, math.max(1, math.floor(A:maxHp(u) * (x.fraction or 0.125))),
            { text = A:text("%s was hurt by %s's %s!", A:name(u), A:name(t), nameOf(id)) })
        elseif x.kind == "stat_change" and STAT[x.stat] then
          A:stages(u, { [STAT[x.stat]] = x.stages or -1 }, { from = t })
        end
      end
    elseif beh.trigger == "on_hit_by" and A:hp(t) > 0 then
      for _, x in ipairs(beh.effects or {}) do
        if x.kind == "stat_change" and STAT[x.stat] then
          local when = tostring(x.when or "")
          local mt = A:moveType(m)
          if when == "" or when:upper():find(mt, 1, true) then
            A:stages(t, { [STAT[x.stat]] = x.stages or 1 })
          end
        end
      end
    end
  end)
  -- Natural Cure: its status is cured as it leaves
  core:on("switchedIn", function(A, ev)
    local prev = ev.previous
    if prev and abilityOf(A, prev) == "NATURALCURE" then
      local mon = A:mon(prev)
      if mon then mon.status = nil end
    end
  end)

  -- ------------------------------------------------------------------ the moves that change abilities
  local function setAbility(A, b, id)
    local v = A:vol(b)
    v.ability, v.abilitySuppressed, v.abilityEntered = id, nil, nil
  end
  local function status(t) t.kind = "status"; return t end
  core:effect("ROLE_PLAY", status({ aimed = true, run = function(A, u, t)
    local id = abilityOf(A, t)
    if not id or id == abilityOf(A, u) then return false end
    setAbility(A, u, id)
    say(A, "%s copied %s's %s!", A:name(u), A:name(t), nameOf(id))
    return true
  end }))
  core:effect("SKILL_SWAP", status({ aimed = true, run = function(A, u, t)
    local a, b = abilityOf(A, u), abilityOf(A, t)
    if not a and not b or a == "WONDERGUARD" or b == "WONDERGUARD" then return false end
    setAbility(A, u, b)
    setAbility(A, t, a)
    say(A, "%s swapped Abilities with its target!", A:name(u))
    return true
  end }))
  core:rule("DOODLE", status({ aimed = true, run = function(A, u, t)
    local id = abilityOf(A, t)
    if not id then return false end
    setAbility(A, u, id)
    say(A, "%s copied %s's %s!", A:name(u), A:name(t), nameOf(id))
    return true
  end }))
  core:rule("ENTRAINMENT", status({ aimed = true, run = function(A, u, t)
    local id = abilityOf(A, u)
    if not id or id == abilityOf(A, t) then return false end
    setAbility(A, t, id)
    say(A, "%s acquired %s!", A:name(t), nameOf(id))
    return true
  end }))
  local function giveTo(id)
    return status({ aimed = true, run = function(A, u, t)
      if abilityOf(A, t) == id then return false end
      setAbility(A, t, id)
      say(A, "%s acquired %s!", A:name(t), nameOf(id))
      return true
    end })
  end
  core:rule("SIMPLE_BEAM", giveTo("SIMPLE"))
  core:rule("WORRY_SEED", giveTo("INSOMNIA"))
  core:rule("GASTRO_ACID", status({ aimed = true, run = function(A, u, t)
    local v = A:vol(t)
    if v.abilitySuppressed then return false end
    v.abilitySuppressed = true
    say(A, "%s's Ability was suppressed!", A:name(t))
    return true
  end }))
  core:rule("CORE_ENFORCER", { kind = "hit", secondary = function(A, u, t)
    if core.track.movedThisTurn(A, t) and not A:vol(t).abilitySuppressed then
      A:vol(t).abilitySuppressed = true
      say(A, "%s's Ability was suppressed!", A:name(t))
    end
  end })
end
