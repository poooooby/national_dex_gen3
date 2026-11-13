-- What the newer held items (data/held_items.lua) do in battle, on every game.
--
-- A mechanics family (function(core, opts)) on the hook vocabulary of src/gen12/mech/core.lua:
-- Red and Gold load it with their mechanics (src/gen12/main.lua), FireRed to Emerald through
-- src/held/gen3.lua, which gives the Gen 3 battle the same adapter calls and fires the same hooks.
-- Only items this mod registered on the running game act here (opts.byId: the game's item id ->
-- its data row); the game's own held items stay the game's.
--
-- The adapter calls used: name hp maxHp heal damage item setItem itemName stages stage setStage
-- status ailment cure confuse types hasType moveType category effectiveness rng field side vol
-- foe battlers say text turn switchOut moves dvs record sideName.
-- Hooks: damageMult damageCap accuracyScale speed priority forceCrit immune dropTypes blockStatus
-- trapped skipCharge hazardImmune weatherImmune weatherTurns screenTurns terrainTurns drainHeal
-- afterMove missed damageDealt switchedIn endTurn beforeMove statusInflicted battleEnded.
--
-- Left to the game or not modelled: Exp. Share / Macho Brace / Power items' growth, Soothe Bell,
-- Luck Incense, Pure Incense and Destiny Knot outside battle, Binding Band, Loaded Dice on a
-- game's own multi-strike moves, Grip Claw on Red (Gen 1's Wrap), Booster Energy on Red and
-- Gold (no Protosynthesis or Quark Drive there).

return function(core, opts)
  local byId = opts.byId or {}
  local FLAGS = opts.flags or {}
  core.heldModern = byId

  local function flag(kind, m)
    local set = FLAGS[kind]
    if not (set and m and m.id) then return false end
    return set[(tostring(m.id):gsub("[^%w]", ""):upper())] == true
  end
  core.moveFlag = core.moveFlag or flag
  local function say(A, fmt, ...) A:say(A:text(fmt, ...)) end
  local function eff(info) return (info and (info.typeMult or info.effectiveness)) or 10 end

  -- the holder's item row (and id), unless Magic Room keeps items quiet
  local function row(A, b)
    if not b then return nil end
    local f = A:field()
    if f.magicRoom then return nil end
    local id = A:item(b)
    local r = id and byId[id]
    if r and A:vol(b).embargo then return nil end
    return r, id
  end
  local function kind(A, b, k)
    local r, id = row(A, b)
    if r and r.effect.kind == k then return r.effect, id end
    return nil
  end
  local function use(A, b, id)
    A:setItem(b, nil)
    local v = A:vol(b)
    v.consumed = id
    if tostring(id):find("BERRY") then v.ateBerry = true end
  end
  local function named(A, id) return A:itemName(id) end

  -- ------------------------------------------------------------------ damage
  local PHYS, SPEC = "physical", "special"
  local function canEvolve(A, b)
    local r = A:record(b)
    local evos = r and (r.evolutions or r.evos)
    return type(evos) == "table" and next(evos) ~= nil
  end
  local function speciesIn(A, b, list)
    local dex = A:dex(b)
    for _, d in ipairs(list or {}) do if d == dex then return true end end
    return false
  end

  core:on("damageMult", function(k, A, u, t, m, info)
    local mt, cat = A:moveType(m), A:category(m)
    local r, id = row(A, u)
    if r then
      local e = r.effect
      if e.kind == "boostType" and mt == e.type then k = k * e.mult
      elseif e.kind == "boostCategory" and cat == e.category then k = k * e.mult
      elseif e.kind == "choice" and ((e.stat == "attack" and cat == PHYS) or (e.stat == "spAtk" and cat == SPEC)) then
        k = k * 1.5
      elseif e.kind == "lifeOrb" then
        k = k * 1.3
        A:vol(u).lifeOrbHit = true
      elseif e.kind == "expertBelt" and eff(info) > 10 then k = k * 1.2
      elseif e.kind == "metronome" then
        local n = A:vol(u).metronomeRun or 0
        k = k * math.min(2, 1 + 0.2 * n)
      elseif e.kind == "punchingGlove" and flag("punch", m) then k = k * 1.1
      elseif e.kind == "speciesType" and speciesIn(A, u, e.species) then
        for _, ty in ipairs(e.types) do if ty == mt then k = k * e.mult break end end
      elseif e.kind == "speciesStat" and speciesIn(A, u, e.species)
          and ((e.stat == "attack" and cat == PHYS) or (e.stat == "spAtk" and cat == SPEC)) then
        k = k * e.mult
      elseif e.kind == "gem" and mt == e.type and (m.power or 0) > 1 then
        use(A, u, id)
        say(A, "The %s strengthened %s's power!", named(A, id), m.name or m.id)
        k = k * 1.3
      end
    end
    local d, did = row(A, t)
    if d then
      local e = d.effect
      if e.kind == "eviolite" and canEvolve(A, t) then k = k / 1.5
      elseif e.kind == "assaultVest" and cat == SPEC then k = k / 1.5
      elseif e.kind == "speciesStat" and speciesIn(A, t, e.species)
          and ((e.stat == "defense" and cat == PHYS) or (e.stat == "spDef" and cat == SPEC)) then
        k = k / e.mult
      elseif e.kind == "berryResist" and mt == e.type and (eff(info) > 10 or e.type == "NORMAL")
          and not A:vol(t).unnerved then
        use(A, t, did)
        say(A, "The %s weakened the damage to %s!", named(A, did), A:name(t))
        k = k * 0.5
      end
    end
    return k
  end)

  -- Focus Sash: a full-HP holder lives through a hit with 1 HP
  core:on("damageCap", function(A, u, t, m, dmg)
    local e, id = kind(A, t, "focusSash")
    if e and A:hp(t) >= A:maxHp(t) and A:hp(t) > 1 and dmg >= A:hp(t) then
      use(A, t, id)
      say(A, "%s hung on using its %s!", A:name(t), named(A, id))
      return A:hp(t) - 1
    end
  end)

  -- ------------------------------------------------------------------ accuracy, speed, order
  core:on("accuracyScale", function(k, A, u, t, m)
    local r = row(A, u)
    if r then
      local e = r.effect
      if e.kind == "accuracy" then k = k * e.mult
      elseif e.kind == "zoomLens" and t then
        local moved = A:field().moved
        if moved and moved[A:sideName(t)] == A:turn() then k = k * 1.2 end
      end
    end
    if A:vol(u).micle then
      A:vol(u).micle = nil
      k = k * 1.2
    end
    local d = t and row(A, t)
    if d and d.effect.kind == "evasion" then k = k * d.effect.mult end
    return k
  end)

  core:on("speed", function(s, A, b)
    local r = row(A, b)
    if not r then return s end
    local e = r.effect
    if e.kind == "choice" and e.stat == "speed" then return s * 1.5 end
    if e.kind == "ironBall" or e.kind == "halfSpeed" or e.kind == "powerItem" then return s * 0.5 end
    if e.kind == "speciesStat" and e.stat == "speed" and speciesIn(A, b, e.species) then return s * e.mult end
    return s
  end)

  core:on("priority", function(p, A, b, m)
    local r, id = row(A, b)
    if not r then return p end
    local e = r.effect
    if e.kind == "moveLast" then return p - 0.5 end
    if e.kind == "berryCustap" and A:hp(b) * 4 <= A:maxHp(b) and A:hp(b) > 0 then
      use(A, b, id)
      say(A, "%s's %s let it move first!", A:name(b), named(A, id))
      return p + 0.5
    end
    return p
  end)

  core:on("forceCrit", function(A, b)
    local r = row(A, b)
    if r and r.effect.kind == "critUp" and A:rng(8) == 0 then return true end
    if A:vol(b).lansat and A:rng(4) == 0 then return true end
  end)

  -- ------------------------------------------------------------------ immunities and guards
  core:on("immune", function(A, u, t, m)
    if u == t then return nil end
    local e = kind(A, t, "airBalloon")
    if e and A:moveType(m) == "GROUND" and not A:field().gravity and (m.power or 0) > 0 then return true end
    if kind(A, t, "safetyGoggles") and flag("powder", m) then return true end
  end)
  core:on("ungrounded", function(A, b)
    if kind(A, b, "airBalloon") then return true end
  end)
  -- Ring Target: the holder's immunities go; Iron Ball: a flying holder meets Ground moves
  core:on("dropTypes", function(A, u, t, m)
    if kind(A, t, "ringTarget") then
      local drop, any = {}, false
      for _, ty in ipairs(A:types(t)) do
        if A:typeEff(A:moveType(m), ty) == 0 then drop[ty], any = true, true end
      end
      if any then return drop end
    end
    if kind(A, t, "ironBall") and A:moveType(m) == "GROUND" and A:hasType(t, "FLYING") then
      return { FLYING = true }
    end
  end)
  -- Covert Cloak: no added effects of a foe's moves (a status that came as one)
  core:on("blockStatus", function(A, b, s, o)
    if o and o.secondary and kind(A, b, "covertCloak") then return "" end
  end)
  core:on("hazardImmune", function(A, b) if kind(A, b, "heavyDutyBoots") then return true end end)
  core:on("weatherImmune", function(A, b) if kind(A, b, "safetyGoggles") then return true end end)
  core:on("ignoresWeather", function(A, b) if kind(A, b, "utilityUmbrella") then return true end end)
  core:on("noContact", function(A, u) if kind(A, u, "protectivePads") then return true end end)
  core:on("abilityLocked", function(A, b) if kind(A, b, "abilityShield") then return true end end)
  core:on("loadedDice", function(A, u) if kind(A, u, "loadedDice") then return true end end)
  -- Shed Shell: free to switch, whatever holds it (asked before the trapping moves)
  local trappedList = core.hooks.trapped or {}
  core.hooks.trapped = trappedList
  table.insert(trappedList, 1, function(A, b) if kind(A, b, "shedShell") then return false end end)
  -- Power Herb: a two-turn move in one
  core:on("skipCharge", function(A, u, m)
    local e, id = kind(A, u, "powerHerb")
    if e then
      use(A, u, id)
      say(A, "%s became fully charged due to its %s!", A:name(u), named(A, id))
      return true
    end
  end)
  -- Assault Vest: no status moves
  core:on("beforeMove", function(A, u, t, m, isCalled)
    if m and (m.power or 0) == 0 and A:category(m) == "status" and kind(A, u, "assaultVest") and not isCalled then
      return A:text("%s can't use status moves while holding its %s!", A:name(u), named(A, A:item(u)))
    end
    -- the user's stats and the target's before the move (White Herb, Clear Amulet, Eject Pack,
    -- Mirror Herb compare after it)
    local snap = {}
    for _, b in ipairs({ u, t }) do
      if b then
        local s = {}
        for _, st in ipairs(core.STATS) do s[st] = A:stage(b, st) end
        snap[b] = s
      end
    end
    A:field().heldSnap = snap
    return nil
  end)
  -- the Choice items: one move until the holder leaves (Encore's way: another choice becomes it)
  core:on("beforeMove", function(A, u, t, m, isCalled)
    if isCalled or not m then return nil end
    local e = kind(A, u, "choice")
    local v = A:vol(u)
    if not e then v.choiceLock = nil return nil end
    if v.choiceLock and v.choiceLock ~= m.id then
      for _, mv in ipairs(A:moves(u)) do
        if mv.id == v.choiceLock and (mv.pp or 1) > 0 then return { id = v.choiceLock } end
      end
    end
    v.choiceLock = v.choiceLock or m.id
    return nil
  end)

  -- ------------------------------------------------------------------ during and after a move
  -- what happened to whom this move (damageDealt per hit)
  core:on("damageDealt", function(A, ev)
    local t, u, n = ev.target, ev.user, tonumber(ev.damage) or 0
    if not t or not u or u == t or n <= 0 then return end
    local f = A:field()
    f.heldHits = f.heldHits or {}
    local h = f.heldHits
    h[#h + 1] = { user = u, target = t, damage = n, move = ev.move }
    local vu = A:vol(u)
    vu.dealtThisMove = (vu.dealtThisMove or 0) + n
    -- Air Balloon pops at the first hit
    local e, id = kind(A, t, "airBalloon")
    if e then
      A:setItem(t, nil)
      say(A, "%s's %s popped!", A:name(t), named(A, id))
    end
  end)

  local function hitOnce(A, b, list)
    for _, h in ipairs(list) do if h.target == b then return h end end
    return nil
  end

  core:on("afterMove", function(A, u, t, moveId)
    local f = A:field()
    local hits, snap = f.heldHits or {}, f.heldSnap or {}
    f.heldHits, f.heldSnap = nil, nil
    local m = A:moveDef(moveId) or { id = moveId }
    local vu = A:vol(u)
    local dealt = vu.dealtThisMove or 0
    vu.dealtThisMove = nil

    -- the user's item
    local r, id = row(A, u)
    if r and A:hp(u) > 0 then
      local e = r.effect
      if e.kind == "lifeOrb" and vu.lifeOrbHit and dealt > 0 then
        A:damage(u, math.max(1, math.floor(A:maxHp(u) / 10)), { text = A:text("%s lost some of its HP!", A:name(u)) })
      elseif e.kind == "shellBell" and dealt > 0 and A:hp(u) < A:maxHp(u) then
        A:heal(u, math.max(1, math.floor(dealt / 8)), { text = A:text("%s restored a little HP using its %s!", A:name(u), named(A, id)) })
      elseif e.kind == "throatSpray" and flag("sound", m) then
        use(A, u, id)
        A:stages(u, { spAtk = 1 })
      elseif e.kind == "weatherRock" and A.gen == 2 and A.battle.weatherTurns == 5 then
        local w = A:weather()
        if w == e.weather then A.battle.weatherTurns = 8 end
      elseif e.kind == "lightClay" and A.gen == 2 then
        local s = A.battle.screens and A.battle.screens[A:sideName(u)]
        if s then
          if moveId == "REFLECT" and s.reflect == 5 then s.reflect = 8 end
          if moveId == "LIGHT_SCREEN" and s.lightScreen == 5 then s.lightScreen = 8 end
        end
      end
    end
    vu.lifeOrbHit = nil
    -- Grip Claw: a bind lasts 7 turns (Gold's wrap count, Gen 3's trap turns)
    if t and t ~= u and A:hp(t) > 0 and kind(A, u, "gripClaw") then
      if A.gen == 2 and A.battle.volatile then
        local tv = A.battle:volatile(t)
        if (tv.wrapCount or 0) > 0 and not tv.__ndxGrip then tv.wrapCount, tv.__ndxGrip = 7, true end
      elseif A.gen == 3 and (t.expTrapTurns or 0) > 0 and not t.__ndxGrip then
        t.expTrapTurns, t.__ndxGrip = 7, true
      end
    end
    -- Metronome: the same move again and again
    if moveId == vu.lastHeldMove then vu.metronomeRun = (vu.metronomeRun or 0) + 1
    else vu.metronomeRun = 0 end
    vu.lastHeldMove = moveId

    -- the target's item, if this move hit it
    local h = t and hitOnce(A, t, hits)
    if h and t ~= u then
      local d, did = row(A, t)
      local cat, mt = A:category(m), A:moveType(m)
      if d then
        local e = d.effect
        local contact = flag("contact", m) and not core:ask("noContact", A, u)
        if e.kind == "rockyHelmet" and contact and A:hp(u) > 0 then
          A:damage(u, math.max(1, math.floor(A:maxHp(u) / 6)), { text = A:text("%s was hurt by the %s!", A:name(u), named(A, did)) })
        elseif e.kind == "stickyBarb" and contact and not A:item(u) then
          A:setItem(t, nil)
          A:setItem(u, did)
        elseif e.kind == "statOnHit" and A:hp(t) > 0 then
          local yes = (e.superEffective and (A:effectiveness(mt, t) or 10) > 10)
            or (e.type and e.type == mt) or (e.category and e.category == cat)
          if yes then
            use(A, t, did)
            say(A, "%s used its %s!", A:name(t), named(A, did))
            A:stages(t, e.stats)
          end
        elseif e.kind == "berryRetaliate" and e.category == cat and A:hp(u) > 0 then
          use(A, t, did)
          A:damage(u, math.max(1, math.floor(A:maxHp(u) / 8)), { text = A:text("%s was hurt by %s's %s!", A:name(u), A:name(t), named(A, did)) })
        elseif e.kind == "berryEnigma" and (A:effectiveness(mt, t) or 10) > 10 and A:hp(t) > 0 then
          use(A, t, did)
          A:heal(t, math.max(1, math.floor(A:maxHp(t) / 4)), { text = A:text("%s restored its health using its %s!", A:name(t), named(A, did)) })
        elseif e.kind == "ejectButton" and A:hp(t) > 0 then
          use(A, t, did)
          say(A, "%s is switched out with the %s!", A:name(t), named(A, did))
          A:switchOut(t, {})
        elseif e.kind == "redCard" and A:hp(u) > 0 then
          use(A, t, did)
          say(A, "%s held up its %s against %s!", A:name(t), named(A, did), A:name(u))
          A:switchOut(u, { random = true })
        end
      end
    end

    -- stat changes this move made
    for b, before in pairs(snap) do
      local r2, id2 = row(A, b)
      if r2 and A:hp(b) > 0 then
        local e = r2.effect
        local fell, rose = {}, {}
        local anyFell = false
        for _, st in ipairs(core.STATS) do
          local now = A:stage(b, st)
          if now < (before[st] or 0) then fell[st] = now - before[st]; anyFell = true end
          if now > (before[st] or 0) then rose[st] = now - before[st] end
        end
        if e.kind == "clearAmulet" and anyFell and b ~= u then
          for st, dlt in pairs(fell) do A:setStage(b, st, A:stage(b, st) - dlt) end
          say(A, "%s's %s prevents its stats from being lowered!", A:name(b), named(A, id2))
        elseif e.kind == "ejectPack" and anyFell then
          use(A, b, id2)
          say(A, "%s is switched out by the %s!", A:name(b), named(A, id2))
          A:switchOut(b, {})
        end
      end
      -- Mirror Herb: the holder copies the boosts its foe just gave itself
      local foe = A:foe(b)
      local r3, id3 = row(A, foe)
      if b == u and r3 and r3.effect.kind == "mirrorHerb" and A:hp(foe) > 0 then
        local got = {}
        local any = false
        for _, st in ipairs(core.STATS) do
          local d = A:stage(b, st) - (before[st] or 0)
          if d > 0 then got[st] = d; any = true end
        end
        if any then
          use(A, foe, id3)
          say(A, "%s used its %s to mirror its opponent's stat changes!", A:name(foe), named(A, id3))
          A:stages(foe, got)
        end
      end
    end
    -- White Herb: lowered stats come back (either side, after any move)
    for _, b in ipairs({ u, t }) do
      local e, wid = b and kind(A, b, "whiteHerb")
      if e and A:hp(b) > 0 then
        local any = false
        for _, st in ipairs(core.STATS) do
          if A:stage(b, st) < 0 then A:setStage(b, st, 0); any = true end
        end
        if any then
          use(A, b, wid)
          say(A, "%s returned its stats to normal using its %s!", A:name(b), named(A, wid))
        end
      end
    end
    -- Mental Herb: free of Taunt, Encore, Torment, Heal Block, Disable and infatuation
    for _, b in ipairs({ u, t }) do
      local e, mid = b and kind(A, b, "mentalHerb")
      if e and A:hp(b) > 0 then
        local v = A:vol(b)
        if v.taunt or v.encore or v.torment or v.healBlock or v.disabled or v.attract then
          v.taunt, v.encore, v.torment, v.healBlock, v.disabled, v.attract = nil, nil, nil, nil, nil, nil
          use(A, b, mid)
          say(A, "%s used its %s to come back to its senses!", A:name(b), named(A, mid))
        end
      end
    end
    -- Room Service when Trick Room comes up; the terrain items when a terrain does
    for _, b in ipairs({ A:battlers() }) do
      if b and A:hp(b) > 0 then
        local e, rid = kind(A, b, "roomService")
        if e and A:field().trickRoom then
          use(A, b, rid)
          A:stages(b, { speed = -1 })
        end
      end
    end
  end)

  -- Blunder Policy: a miss sharply raises Speed
  core:on("missed", function(A, u, t, m)
    local e, id = kind(A, u, "blunderPolicy")
    if e and A:hp(u) > 0 then
      use(A, u, id)
      A:stages(u, { speed = 2 })
    end
  end)

  -- turn counts a held item lengthens
  core:on("weatherTurns", function(n, A, u, w)
    local e = u and kind(A, u, "weatherRock")
    if e and e.weather == w or (e and e.weather == "hail" and w == "snow") then return 8 end
    return n
  end)
  core:on("screenTurns", function(n, A, u) if u and kind(A, u, "lightClay") then return 8 end return n end)
  core:on("terrainTurns", function(n, A, u) if u and kind(A, u, "terrainExtender") then return 8 end return n end)
  core:on("drainHeal", function(n, A, b) if kind(A, b, "bigRoot") then return math.floor(n * 1.3) end return n end)

  -- ------------------------------------------------------------------ berries in a pinch
  local CURE = { PAR = "PAR", SLP = "SLP", BRN = "BRN", FRZ = "FRZ", PSN = "PSN" }
  local STATS5 = { "attack", "defense", "spAtk", "spDef", "speed" }
  local function berry(A, b)
    local r, id = row(A, b)
    if not r or A:hp(b) <= 0 then return end
    local e = r.effect
    local hp, max = A:hp(b), A:maxHp(b)
    local quarter = hp * 4 <= max
    if e.kind == "berryCure" then
      local s = A:status(b)
      local want = e.status
      local conf = A:vol(b).confused or b.confusedTurns or (A.gen == 2 and A.battle.volatile and A.battle:volatile(b).confused)
      local hitS = (want == "ALL" and s) or (CURE[want] and (s == want or (want == "PSN" and s == "TOX")))
      local hitC = (want == "ALL" or want == "CONFUSION") and conf
      if hitS or hitC then
        use(A, b, id)
        if hitS then A:cure(b) end
        if hitC then
          b.confusedTurns = nil
          A:vol(b).confused = nil
          if A.gen == 2 and A.battle.volatile then A.battle:volatile(b).confused = nil end
        end
        say(A, "%s's %s cured it!", A:name(b), named(A, id))
      end
    elseif e.kind == "berryHeal" and hp * 2 <= max then
      use(A, b, id)
      local n = e.amount or math.floor(max * (e.fraction or 0.25))
      A:heal(b, math.max(1, n), { text = A:text("%s restored its health using its %s!", A:name(b), named(A, id)) })
    elseif e.kind == "berryPinch" and quarter then
      use(A, b, id)
      A:heal(b, math.max(1, math.floor(max * (e.fraction or 1 / 3))), { text = A:text("%s restored its health using its %s!", A:name(b), named(A, id)) })
      local down = core.natureDown and core.natureDown(A, b)
      if down and down == e.dislike then A:confuse(b, {}) end
    elseif e.kind == "berryStat" and quarter then
      use(A, b, id)
      say(A, "%s used its %s!", A:name(b), named(A, id))
      A:stages(b, { [e.stat] = 1 })
    elseif e.kind == "berryStarf" and quarter then
      use(A, b, id)
      say(A, "%s used its %s!", A:name(b), named(A, id))
      A:stages(b, { [STATS5[A:rng(5) + 1]] = 2 })
    elseif e.kind == "berryCrit" and quarter then
      use(A, b, id)
      A:vol(b).lansat = true
      say(A, "%s used its %s to get pumped!", A:name(b), named(A, id))
    elseif e.kind == "berryMicle" and quarter then
      use(A, b, id)
      A:vol(b).micle = true
      say(A, "%s boosted the accuracy of its next move using its %s!", A:name(b), named(A, id))
    elseif e.kind == "berryPP" then
      for _, mv in ipairs(A:moves(b)) do
        if mv.pp == 0 then
          use(A, b, id)
          mv.pp = math.min(mv.maxPp or 10, e.amount or 10)
          say(A, "%s restored PP to its move using its %s!", A:name(b), named(A, id))
          break
        end
      end
    end
  end
  core.heldBerry = berry
  core:on("damageDealt", function(A, ev) if ev.target then berry(A, ev.target) end end)
  core:on("statusInflicted", function(A, ev) if ev.target then berry(A, ev.target) end end)

  -- ------------------------------------------------------------------ switching in
  core:on("switchedIn", function(A, ev)
    local b = ev.battler
    if not b or A:hp(b) <= 0 then return end
    local e, id = kind(A, b, "airBalloon")
    if e then say(A, "%s floats in the air with its %s!", A:name(b), named(A, id)) end
    -- Adrenaline Orb: the foe that came in has Intimidate
    local foe = A:foe(b)
    local ab = core.abilityOf and core.abilityOf(A, b)
    local oe, oid = foe and kind(A, foe, "adrenalineOrb")
    if oe and ab == "INTIMIDATE" and A:hp(foe) > 0 then
      use(A, foe, oid)
      A:stages(foe, { speed = 1 })
    end
    A:vol(b).choiceLock = nil
    -- Booster Energy: Protosynthesis / Quark Drive without the sun or Electric Terrain
    local be, beid = kind(A, b, "boosterEnergy")
    if be and core.boosterReady and core.boosterReady(A, b) then
      use(A, b, beid)
      b.__ndxBooster = true
      say(A, "%s used its %s to activate its %s!", A:name(b), named(A, beid),
        (core.abilityOf(A, b) == "QUARK_DRIVE") and "Quark Drive" or "Protosynthesis")
    end
  end)

  -- ------------------------------------------------------------------ the end of the turn
  local function seedCheck(A)
    local terrain = core.terrain and core.terrain(A)
    if not terrain then return end
    for _, b in ipairs({ A:battlers() }) do
      local e, id = b and kind(A, b, "seed")
      if e and e.terrain == terrain and A:hp(b) > 0 then
        use(A, b, id)
        say(A, "%s used its %s!", A:name(b), named(A, id))
        A:stages(b, { [e.stat] = 1 })
      end
    end
  end
  core.heldSeeds = seedCheck
  core:on("endTurn", function(A)
    seedCheck(A)
    for _, b in ipairs({ A:battlers() }) do
      local r, id = b and row(A, b)
      if r and A:hp(b) > 0 then
        local e = r.effect
        local max = A:maxHp(b)
        if e.kind == "blackSludge" then
          if A:hasType(b, "POISON") then
            if A:hp(b) < max then
              A:heal(b, math.max(1, math.floor(max / 16)), { text = A:text("%s restored a little HP using its %s!", A:name(b), named(A, id)) })
            end
          else
            A:damage(b, math.max(1, math.floor(max / 8)), { text = A:text("%s was hurt by its %s!", A:name(b), named(A, id)) })
          end
        elseif e.kind == "stickyBarb" then
          A:damage(b, math.max(1, math.floor(max / 8)), { text = A:text("%s was hurt by its %s!", A:name(b), named(A, id)) })
        elseif e.kind == "inflictSelf" and not A:status(b) then
          local landed = A:ailment(b, e.status == "TOX" and "TOXIC" or "BURN", {})
          if landed then
            say(A, e.status == "TOX" and "%s was badly poisoned by the %s!" or "%s was burned by the %s!",
              A:name(b), named(A, id))
          end
        end
        berry(A, b)
      end
    end
  end)
end
