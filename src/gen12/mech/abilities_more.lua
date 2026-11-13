-- The abilities data/gen12/abilities.lua has no behaviour block for, written out (after
-- src/gen12/mech/abilities.lua, whose abilityOf already answers Neutralizing Gas and a Mold
-- Breaker's target). Today's rules, singles only; the state on A:vol / A:side / A:field.
--
-- Before a move (beforeMove): the move's mover (Serene Grace's chances), a Mold Breaker's target,
-- a snapshot of both sides' stages, statuses and HP; Truant, Damp, the priority blockers (Armor
-- Tail, Dazzling, Queenly Majesty), status moves the target shrugs off (Good as Gold, Soundproof,
-- Bulletproof, Overcoat), Cursed Body's disabled move.
-- After it (afterMove): what the snapshot shows changed: stat drops (Clear Body and kin, Mirror
-- Armor, Defiant, Competitive), Contrary, Opportunist, Synchronize, Poison Puppeteer, the HP lines
-- (Anger Shell, Berserk, Emergency Exit, Wimp Out), knock-outs (Beast Boost, the Neighs, As One,
-- Soul-Heart, Innards Out), contact (Mummy, Lingering Aroma, Wandering Spirit, Pickpocket), a hit
-- (Color Change, Cursed Body, Gulp Missile, Sand Spit, Toxic Debris, Magician, Toxic Chain),
-- Pressure's PP, Dancer, Stance Change.
-- Elsewhere: the damage multipliers (the Ruin four, Supreme Overlord, Punk Rock, Sniper, the -ate
-- abilities and Normalize, Protosynthesis / Quark Drive, Aura Break), Disguise and Ice Face,
-- immunities, No Guard, Wonder Skin, Scrappy / Mind's Eye, the trappers, Stall / Quick Draw /
-- Mycelium Might, Unburden, Unaware, Infiltrator, Unseen Fist, Suction Cups / Guard Dog, Sticky
-- Hold, Klutz, the berry ones (Gluttony, Ripen, Cheek Pouch, Cud Chew, Unnerve), Magic Guard, Rock
-- Head, Liquid Ooze, Air Lock / Cloud Nine, Heavy / Light Metal, Serene Grace, Shield Dust, Skill
-- Link, Early Bird, Bad Dreams, the entry ones (Trace, Download, Frisk, Anticipation, Forewarn,
-- Screen Cleaner, Pressure's and Mold Breaker's lines, Zero to Hero), Forecast, Mimicry,
-- Multitype, Hunger Switch, Schooling, Pickup, Run Away.
-- Also the hidden ones a Pokemon can come by through Skill Swap, Trace or Role Play: Protean,
-- Libero, Magic Bounce, Aroma Veil, Moody, Harvest, Long Reach, Perish Body, Zen Mode.
-- The partner abilities and those with nothing to act on here (Battery, Power Spot, Friend Guard,
-- Hospitality, Healer, Plus, Minus, Commander, Receiver, Telepathy, Ball Fetch, Honey Gather,
-- Curious Medicine, Illusion, Power Construct, RKS System, Tera Shift, Corrosion, Imposter,
-- Propeller Tail, Stalwart, Symbiosis, Costar, Power of Alchemy) never reach a battle: abilities.lua
-- (core.ABILITY_SWAP) gives the Pokemon a working one in their place.

return function(core, opts)
  local ab = core.abilityOf
  local raw = core.rawAbility
  local nameOf = core.abilityName or function(id) return tostring(id) end
  local function say(A, fmt, ...) A:say(A:text(fmt, ...)) end
  local function flag(k, m) return core.moveFlag ~= nil and core.moveFlag(k, m) or false end
  local STATS = { "attack", "defense", "spAtk", "spDef", "speed", "accuracy", "evasion" }
  local FIVE = { "attack", "defense", "spAtk", "spDef", "speed" }
  local STAT_NAME = { attack = "Attack", defense = "Defense", spAtk = "Sp. Atk", spDef = "Sp. Def",
    speed = "Speed", accuracy = "accuracy", evasion = "evasiveness" }

  -- what each move aims at (PokeAPI's target, from data/gen12/api/moves.lua), by id letters only
  local TARGET, CLASS = {}, {}
  for _, r in ipairs((opts.load and opts.load("data/gen12/api/moves.lua")) or {}) do
    if r.strippedId then TARGET[r.strippedId], CLASS[r.strippedId] = r.target, r.damageClass end
  end
  local SELF_TARGET = { user = true, ["users-field"] = true, ["user-and-allies"] = true, ["entire-field"] = true,
    ["all-allies"] = true, ["opponents-field"] = true, ["user-or-ally"] = true }
  local function letters(id) return (tostring(id or ""):gsub("[^%w]", ""):upper()) end
  local function aimedAtFoe(m)
    local t = TARGET[letters(m.id)]
    return t == nil or not SELF_TARGET[t]
  end
  -- a status move (PokeAPI's damage class: Red and Gold class moves by type)
  local function isStatus(A, m)
    local c = CLASS[letters(m.id)]
    if c then return c == "status" end
    return (m.power or 0) == 0
  end

  local function partyFainted(A, b)
    local n = 0
    for _, mon in ipairs(A:party(b) or {}) do
      if type(mon) == "table" and (mon.hp or 0) <= 0 and not mon.isEgg then n = n + 1 end
    end
    return n
  end

  -- a battle-only stat block from a form's base stats (Stance Change, Zero to Hero, Schooling):
  -- Gen 1/2's formula with the Pokemon's DVs, stat experience and nature
  local function formStats(A, b, base)
    local dvs, mon = A:dvs(b) or {}, A:mon(b) or {}
    local exp, lvl = mon.statExp or {}, A:level(b) or 50
    local DV = { attack = "attack", defense = "defense", spAtk = "special", spDef = "special", speed = "speed" }
    local mods = core.traits and core.traits.mods and core.traits.mods(dvs) or {}
    local out = {}
    for k, dvKey in pairs(DV) do
      local e = math.floor(math.min(255, math.ceil(math.sqrt(exp[dvKey] or 0))) / 4)
      local v = math.floor(((base[k] + (dvs[dvKey] or 0)) * 2 + e) * lvl / 100) + 5
      if mods[k] then v = math.floor(v * mods[k]) end
      out[k] = v
    end
    return out
  end
  local FORM = {
    BLADE = { attack = 140, defense = 50, spAtk = 140, spDef = 50, speed = 60 },        -- Aegislash
    HERO = { attack = 160, defense = 97, spAtk = 106, spDef = 87, speed = 100 },        -- Palafin
    SCHOOL = { attack = 140, defense = 130, spAtk = 140, spDef = 135, speed = 30 },      -- Wishiwashi
    ZEN = { attack = 30, defense = 105, spAtk = 140, spDef = 105, speed = 55 },          -- Darmanitan
  }

  -- ------------------------------------------------------------------ stat drops
  local BLOCK_ALL = { CLEARBODY = true, WHITESMOKE = true, FULLMETALBODY = true }
  local BLOCK_ONE = { HYPERCUTTER = "attack", BIGPECKS = "defense", KEENEYE = "accuracy", ILLUMINATE = "accuracy",
    MINDSEYE = "accuracy" }
  -- drops: { stat = negative change } that a foe (source) just made; undone where the ability
  -- forbids it, then Defiant / Competitive answer what is left
  function core.reactToDrops(A, t, drops, source)
    local id = ab(A, t)
    if not id or A:hp(t) <= 0 then return end
    local all = BLOCK_ALL[id] or id == "MIRRORARMOR" or (id == "FLOWERVEIL" and A:hasType(t, "GRASS"))
    local undone, any = {}, false
    for st, d in pairs(drops) do
      if all or BLOCK_ONE[id] == st then
        A:setStage(t, st, A:stage(t, st) - d)
        undone[st], any = d, true
        drops[st] = nil
      end
    end
    if any then
      say(A, "%s's %s prevents its stats from being lowered!", A:name(t), nameOf(id))
      if id == "MIRRORARMOR" and source and A:hp(source) > 0 then A:stages(source, undone, { from = t }) end
    end
    if next(drops) then
      if id == "DEFIANT" then say(A, "%s's %s!", A:name(t), nameOf(id)); A:stages(t, { attack = 2 })
      elseif id == "COMPETITIVE" then say(A, "%s's %s!", A:name(t), nameOf(id)); A:stages(t, { spAtk = 2 }) end
    end
  end

  -- ------------------------------------------------------------------ before a move
  local MOLD = { MOLDBREAKER = true, TERAVOLT = true, TURBOBLAZE = true }
  local EXPLODE = { SELFDESTRUCT = true, EXPLOSION = true, MINDBLOWN = true, MISTYEXPLOSION = true }
  local PRIORITY_BLOCK = { ARMORTAIL = true, DAZZLING = true, QUEENLYMAJESTY = true }
  local MENTAL = { TAUNT = true, TORMENT = true, ENCORE = true, DISABLE = true, HEALBLOCK = true, ATTRACT = true }
  local function snap(A, b)
    if not b then return nil end
    local s = { hp = A:hp(b), status = A:status(b), stages = {} }
    for _, st in ipairs(STATS) do s.stages[st] = A:stage(b, st) end
    return s
  end
  core:on("beforeMove", function(A, u, t, m, isCalled)
    local f = A:field()
    f.mover = u
    f.abSnap = { user = u, target = t, [u] = snap(A, u), [t or u] = snap(A, t or u) }
    local id = raw(A, u)
    if t and t ~= u and (MOLD[id] or (id == "MYCELIUMMIGHT" and m and isStatus(A, m))) then
      f.moldBreaking = { user = u, target = t, turn = A:turn() }
    else
      f.moldBreaking = nil
    end
    return nil
  end)
  core:on("beforeMove", function(A, u, t, m, isCalled)
    if not m then return nil end
    local v = A:vol(u)
    -- Truant: every other turn
    if ab(A, u) == "TRUANT" and not isCalled then
      if v.truantLoaf then
        v.truantLoaf = false
        return A:text("%s is loafing around!", A:name(u))
      end
      v.truantLoaf = true
    end
    -- Cursed Body's disabled move
    local cb = v.cursedBody
    if cb and cb.id == m.id and A:turn() <= cb.untilTurn and not isCalled then
      return A:text("%s's %s is disabled!", A:name(u), m.name or m.id)
    end
    -- Damp: no explosions while it is out
    if EXPLODE[letters(m.id)] then
      for _, x in ipairs({ A:battlers() }) do
        if x and A:hp(x) > 0 and ab(A, x) == "DAMP" then
          return A:text("%s's %s prevents %s from using %s!", A:name(x), nameOf("DAMP"), A:name(u), m.name or m.id)
        end
      end
    end
    -- Protean / Libero: the user becomes the move's type, once each time it comes in
    local uid = ab(A, u)
    if (uid == "PROTEAN" or uid == "LIBERO") and not v.protean then
      local mt = A:moveType(m)
      if mt ~= "" and not (A:hasType(u, mt) and #A:types(u) == 1) then
        v.protean = true
        A:setTypes(u, { mt })
        say(A, "%s's %s made it the %s type!", A:name(u), nameOf(uid), mt)
      end
    end
    if t and t ~= u and A:hp(t) > 0 then
      local tid = ab(A, t)
      if tid == "AROMAVEIL" and MENTAL[letters(m.id)] then
        return A:text("%s is protected by an aromatic veil!", A:name(t))
      end
      -- Magic Bounce: a status move aimed at it goes back to its user
      if tid == "MAGICBOUNCE" and isStatus(A, m) and aimedAtFoe(m) and not A:field().bouncing then
        local f = A:field()
        f.bouncing = true
        say(A, "%s bounced the %s back!", A:name(t), m.name or m.id)
        pcall(A.callMove, A, t, u, m.id)
        f.bouncing = nil
        return ""
      end
      if PRIORITY_BLOCK[tid] and (A:basePriority(m) or 0) > 0 then
        return A:text("%s cannot use %s!", A:name(u), m.name or m.id)
      end
      if isStatus(A, m) and aimedAtFoe(m) then
        if tid == "GOODASGOLD" or (tid == "SOUNDPROOF" and flag("sound", m))
            or (tid == "OVERCOAT" and flag("powder", m)) or (tid == "BULLETPROOF" and flag("bullet", m)) then
          return A:text("It doesn't affect %s...", A:name(t))
        end
      end
    end
    return nil
  end)

  -- ------------------------------------------------------------------ after a move
  local NEIGH = { CHILLINGNEIGH = "attack", ASONEGLASTRIER = "attack", GRIMNEIGH = "spAtk", ASONESPECTRIER = "spAtk" }
  local CONTACT_SWAP = { MUMMY = true, LINGERINGAROMA = true, WANDERINGSPIRIT = true }
  local NO_COPY = { MULTITYPE = true, STANCECHANGE = true, SCHOOLING = true, DISGUISE = true, ZEROTOHERO = true,
    RKSSYSTEM = true, ICEFACE = true, GULPMISSILE = true, COMMANDER = true, POWERCONSTRUCT = true, TRACE = true,
    ASONEGLASTRIER = true, ASONESPECTRIER = true, TERASHIFT = true, NEUTRALIZINGGAS = true }
  local function bestStat(A, b)
    local best, val = "attack", -1
    for _, st in ipairs(FIVE) do
      local x = A:stat(b, st)
      if x > val then best, val = st, x end
    end
    return best
  end
  core:on("afterMove", function(A, u, t, moveId)
    local f = A:field()
    local s = f.abSnap
    f.abSnap, f.mover = nil, nil
    f.moldBreaking = nil
    if not s or s.user ~= u then return end
    local m = A:moveDef(moveId) or { id = moveId }
    local hitT = t and t ~= u and s[t] and A:hp(t) < s[t].hp
    local contact = hitT and flag("contact", m) and not core:ask("noContact", A, u)
    -- stage changes, both sides
    for _, b in ipairs({ u, t }) do
      local before = b and s[b]
      if before and A:hp(b) > 0 then
        local id = ab(A, b)
        local rose, fell, any = {}, {}, false
        for _, st in ipairs(STATS) do
          local d = A:stage(b, st) - (before.stages[st] or 0)
          if d > 0 then rose[st] = d; any = true elseif d < 0 then fell[st] = d; any = true end
        end
        if any and id == "CONTRARY" then
          for _, st in ipairs(STATS) do
            local d = A:stage(b, st) - (before.stages[st] or 0)
            if d ~= 0 then A:setStage(b, st, (before.stages[st] or 0) - d) end
          end
          say(A, "%s's %s turned its stat changes around!", A:name(b), nameOf(id))
        elseif b ~= u and next(fell) then
          core.reactToDrops(A, b, fell, u)
        end
        -- Opportunist: the foe's boosts, copied
        local o = A:foe(b)
        if next(rose) and o and A:hp(o) > 0 and ab(A, o) == "OPPORTUNIST" and b ~= o then
          say(A, "%s's %s!", A:name(o), nameOf("OPPORTUNIST"))
          A:stages(o, rose)
        end
      end
    end
    -- statuses this move gave
    if t and t ~= u and s[t] and not s[t].status and A:hp(t) > 0 then
      local now = A:status(t)
      if now then
        local tid = ab(A, t)
        if tid == "SYNCHRONIZE" and (now == "PSN" or now == "TOX" or now == "BRN" or now == "PAR") and A:hp(u) > 0 then
          say(A, "%s's %s!", A:name(t), nameOf(tid))
          A:ailment(u, ({ PSN = "POISON", TOX = "TOXIC", BRN = "BURN", PAR = "PARALYSIS" })[now], { from = t })
        end
        if ab(A, u) == "POISONPUPPETEER" and (now == "PSN" or now == "TOX") then A:confuse(t, { from = u }) end
      end
    end
    -- the HP lines a hit crossed, and knock-outs
    if t and t ~= u and s[t] then
      local before, now, max = s[t].hp, A:hp(t), A:maxHp(t)
      local tid = ab(A, t)
      if now <= 0 and before > 0 then
        local uid = ab(A, u)
        if A:hp(u) > 0 then
          if uid == "BEASTBOOST" then say(A, "%s's %s!", A:name(u), nameOf(uid)); A:stages(u, { [bestStat(A, u)] = 1 })
          elseif NEIGH[uid] then say(A, "%s's %s!", A:name(u), nameOf(uid)); A:stages(u, { [NEIGH[uid]] = 1 }) end
        end
        if tid == "INNARDSOUT" and A:hp(u) > 0 and not core:ask("noIndirect", A, u) then
          A:damage(u, before, { text = A:text("%s was hurt by %s's %s!", A:name(u), A:name(t), nameOf(tid)) })
        end
        for _, x in ipairs({ A:battlers() }) do
          if x and x ~= t and A:hp(x) > 0 and ab(A, x) == "SOULHEART" then A:stages(x, { spAtk = 1 }) end
        end
      elseif now > 0 and before * 2 > max and now * 2 <= max then
        if tid == "ANGERSHELL" then
          say(A, "%s's %s!", A:name(t), nameOf(tid))
          A:stages(t, { attack = 1, spAtk = 1, speed = 1, defense = -1, spDef = -1 })
        elseif tid == "BERSERK" then
          A:stages(t, { spAtk = 1 })
        elseif (tid == "EMERGENCYEXIT" or tid == "WIMPOUT") and A:replacement(t) then
          say(A, "%s's %s!", A:name(t), nameOf(tid))
          A:switchOut(t, {})
        end
      end
    end
    -- what a hit or a contact does back
    if hitT and A:hp(u) > 0 then
      local tid = ab(A, t)
      if contact and CONTACT_SWAP[tid] then
        local uid = raw(A, u)
        if uid and not NO_COPY[uid] and uid ~= tid then
          if tid == "WANDERINGSPIRIT" then
            core.setAbility(A, u, tid); core.setAbility(A, t, uid)
            say(A, "%s swapped Abilities with its target!", A:name(t))
          else
            core.setAbility(A, u, tid)
            say(A, "%s's Ability became %s!", A:name(u), nameOf(tid))
          end
        end
      end
      if contact and tid == "PERISHBODY" and A:hp(t) > 0 then
        local vu, vt = A:vol(u), A:vol(t)
        if not vu.perish then
          vu.perish = 3
          if not vt.perish then vt.perish = 3 end
          say(A, "Both Pokemon will faint in three turns!")
        end
      end
      if contact and tid == "PICKPOCKET" and A:hp(t) > 0 and not A:item(t) and A:item(u)
          and not core:ask("itemLocked", A, u) then
        local id = A:item(u)
        A:setItem(u, nil); A:setItem(t, id)
        say(A, "%s stole %s's %s!", A:name(t), A:name(u), A:itemName(id))
      end
      if A:hp(t) > 0 then
        if tid == "COLORCHANGE" then
          local mt = A:moveType(m)
          if mt ~= "" and not A:hasType(t, mt) then
            A:setTypes(t, { mt })
            say(A, "%s's %s made it the %s type!", A:name(t), nameOf(tid), mt)
          end
        elseif tid == "CURSEDBODY" and A:rng(10) < 3 then
          A:vol(u).cursedBody = { id = moveId, untilTurn = A:turn() + 3 }
          say(A, "%s's %s was disabled by %s's %s!", A:name(u), m.name or moveId, A:name(t), nameOf(tid))
        elseif tid == "SANDSPIT" and A:weather() ~= "sand" then
          A:setWeather("sand", core:fold("weatherTurns", 5, A, t, "sand"), A:text("A sandstorm kicked up!"))
        elseif tid == "TOXICDEBRIS" and A:category(m) == "physical" then
          local h = A:side(u)
          h.hazards = h.hazards or {}
          if (h.hazards.toxic or 0) < 2 then
            h.hazards.toxic = (h.hazards.toxic or 0) + 1
            say(A, "Poison spikes were scattered around %s's feet!", A:name(u))
          end
        end
        if tid == "GULPMISSILE" and A:vol(t).gulp then
          local prey = A:vol(t).gulp
          A:vol(t).gulp = nil
          if not core:ask("noIndirect", A, u) then
            A:damage(u, math.max(1, math.floor(A:maxHp(u) / 4)),
              { text = A:text("%s was hit by %s's catch!", A:name(u), A:name(t)) })
          end
          if prey == "PIKACHU" then A:ailment(u, "PARALYSIS", { from = t, secondary = true })
          else A:stages(u, { defense = -1 }, { from = t }) end
        end
      end
      local uid = ab(A, u)
      if uid == "MAGICIAN" and not A:item(u) and A:item(t) and not core:ask("itemLocked", A, t) then
        local id = A:item(t)
        A:setItem(t, nil); A:setItem(u, id)
        say(A, "%s stole %s's %s!", A:name(u), A:name(t), A:itemName(id))
      end
      if uid == "TOXICCHAIN" and A:hp(t) > 0 and not A:status(t) and A:rng(10) < 3 then
        A:ailment(t, "TOXIC", { from = u, secondary = true })
      end
    end
    -- Gulp Missile: Surf or Dive catches prey (an Arrokuda above half HP, else a Pikachu)
    if ab(A, u) == "GULPMISSILE" and (moveId == "SURF" or moveId == "DIVE") and A:hp(u) > 0 then
      A:vol(u).gulp = (A:hp(u) * 2 > A:maxHp(u)) and "ARROKUDA" or "PIKACHU"
    end
    -- Pressure: a foe's move costs one PP more
    if t and t ~= u and ab(A, t) == "PRESSURE" then
      for _, mv in ipairs(A:moves(u)) do
        if mv.id == moveId and (mv.pp or 0) > 0 then mv.pp = mv.pp - 1 break end
      end
    end
    -- Dancer: a dance move used is danced back
    if flag("dance", m) and not f.dancing then
      local d = A:foe(u)
      if d and A:hp(d) > 0 and ab(A, d) == "DANCER" then
        f.dancing = true
        pcall(A.callMove, A, d, u, moveId)
        f.dancing = nil
      end
    end
    -- Stance Change: an attack is the Blade Forme, King's Shield the Shield Forme
    if ab(A, u) == "STANCECHANGE" and A:hp(u) > 0 then
      local v = A:vol(u)
      if moveId == "KINGS_SHIELD" and v.blade then
        v.blade, v.statOver = nil, nil
        say(A, "%s changed to Shield Forme!", A:name(u))
      elseif (m.power or 0) > 0 and not v.blade then
        v.blade = true
        v.statOver = formStats(A, u, FORM.BLADE)
        say(A, "%s changed to Blade Forme!", A:name(u))
      end
    end
  end)

  -- ------------------------------------------------------------------ damage
  local ATE = { REFRIGERATE = "ICE", PIXILATE = "FAIRY", AERILATE = "FLYING", GALVANIZE = "ELECTRIC" }
  local PLATE_TYPE = { FLAME_PLATE = "FIRE", SPLASH_PLATE = "WATER", ZAP_PLATE = "ELECTRIC", MEADOW_PLATE = "GRASS",
    ICICLE_PLATE = "ICE", FIST_PLATE = "FIGHTING", TOXIC_PLATE = "POISON", EARTH_PLATE = "GROUND", SKY_PLATE = "FLYING",
    MIND_PLATE = "PSYCHIC", INSECT_PLATE = "BUG", STONE_PLATE = "ROCK", SPOOKY_PLATE = "GHOST", DRACO_PLATE = "DRAGON",
    DREAD_PLATE = "DARK", IRON_PLATE = "STEEL", PIXIE_PLATE = "FAIRY" }
  core:on("moveType", function(A, u, m)
    local id = ab(A, u)
    if id == "NORMALIZE" then return "NORMAL" end
    if ATE[id] and A:moveType(m) == "NORMAL" then return ATE[id] end
    if id == "LIQUIDVOICE" and flag("sound", m) then return "WATER" end
    if id == "MULTITYPE" and m.id == "JUDGMENT" then return PLATE_TYPE[A:item(u) or ""] end
    if m.id == "AURA_WHEEL" and A:vol(u).hangry then return "DARK" end
  end)
  local function boosted(A, b)
    local id = ab(A, b)
    if id ~= "PROTOSYNTHESIS" and id ~= "QUARKDRIVE" then return nil end
    if A:vol(b).booster then return bestStat(A, b) end
    if id == "PROTOSYNTHESIS" and A:weather() == "sun" then return bestStat(A, b) end
    if id == "QUARKDRIVE" and core.terrain and core.terrain(A) == "ELECTRIC" then return bestStat(A, b) end
    return nil
  end
  core.boosterReady = function(A, b)
    local id = ab(A, b)
    return (id == "PROTOSYNTHESIS" or id == "QUARKDRIVE") and not A:vol(b).booster and boosted(A, b) == nil
  end
  local function onField(A, id)
    for _, x in ipairs({ A:battlers() }) do
      if x and A:hp(x) > 0 and ab(A, x) == id then return true end
    end
    return false
  end
  core:on("damageMult", function(k, A, u, t, m, info)
    local uid, tid = ab(A, u), ab(A, t)
    local cat, mt = A:category(m), A:moveType(m)
    if uid == "SWORDOFRUIN" and cat == "physical" then k = k * 4 / 3 end
    if uid == "BEADSOFRUIN" and cat == "special" then k = k * 4 / 3 end
    if tid == "TABLETSOFRUIN" and cat == "physical" and uid ~= "TABLETSOFRUIN" then k = k * 0.75 end
    if tid == "VESSELOFRUIN" and cat == "special" and uid ~= "VESSELOFRUIN" then k = k * 0.75 end
    if uid == "SUPREMEOVERLORD" then k = k * (1 + 0.1 * math.min(5, partyFainted(A, u))) end
    if uid == "PUNKROCK" and flag("sound", m) then k = k * 1.3 end
    if tid == "PUNKROCK" and flag("sound", m) then k = k * 0.5 end
    if uid == "SNIPER" and info and (info.crit or info.critical) then k = k * 1.5 end
    if (uid == "NORMALIZE" or (ATE[uid] and mt == "NORMAL")) and (m.power or 0) > 0 then k = k * 1.2 end
    local ub, tb = boosted(A, u), boosted(A, t)
    if ub and ((ub == "attack" and cat == "physical") or (ub == "spAtk" and cat == "special")) then k = k * 1.3 end
    if tb and ((tb == "defense" and cat == "physical") or (tb == "spDef" and cat == "special")) then k = k / 1.3 end
    if onField(A, "AURABREAK") and ((mt == "FAIRY" and onField(A, "FAIRYAURA")) or (mt == "DARK" and onField(A, "DARKAURA"))) then
      k = k / (4 / 3) * 0.75
    end
    return k
  end)
  -- Disguise, Ice Face: the first hit (Ice Face: physical) does nothing
  core:on("damageCap", function(A, u, t, m, dmg)
    local id = ab(A, t)
    if u == t or (id ~= "DISGUISE" and id ~= "ICEFACE") then return nil end
    local f = A:field()
    f.busted = f.busted or setmetatable({}, { __mode = "k" })
    local mon = A:mon(t)
    if f.busted[mon] or (id == "ICEFACE" and A:category(m) ~= "physical") then return nil end
    f.busted[mon] = true
    if id == "DISGUISE" then
      say(A, "Its disguise served it as a decoy!")
      if not core:ask("noIndirect", A, t) then A:damage(t, math.max(1, math.floor(A:maxHp(t) / 8))) end
      say(A, "%s's disguise was busted!", A:name(t))
    else
      say(A, "%s's %s!", A:name(t), nameOf(id))
    end
    return 0
  end)

  -- ------------------------------------------------------------------ immunities and guards
  core:on("immune", function(A, u, t, m)
    if u == t then return nil end
    local tid = ab(A, t)
    if (tid == "BULLETPROOF" and flag("bullet", m)) or (tid == "SOUNDPROOF" and flag("sound", m))
        or (tid == "OVERCOAT" and flag("powder", m)) then
      return true
    end
  end)
  core:on("accuracy", function(A, u, t)
    if ab(A, u) == "NOGUARD" or (t and ab(A, t) == "NOGUARD") then return true end
  end)
  core:on("accuracyScale", function(k, A, u, t, m)
    if t and t ~= u and ab(A, t) == "WONDERSKIN" and m and isStatus(A, m) and aimedAtFoe(m) then return k * 0.5 end
    return k
  end)
  core:on("dropTypes", function(A, u, t, m)
    local uid = ab(A, u)
    local mt = A:moveType(m)
    if (uid == "SCRAPPY" or uid == "MINDSEYE") and (mt == "NORMAL" or mt == "FIGHTING") and A:hasType(t, "GHOST") then
      return { GHOST = true }
    end
  end)
  core:on("trapped", function(A, b)
    local o = A:foe(b)
    if not o or A:hp(o) <= 0 or A:hasType(b, "GHOST") then return nil end
    local oid = ab(A, o)
    if (oid == "SHADOWTAG" and ab(A, b) ~= "SHADOWTAG")
        or (oid == "ARENATRAP" and (not core.grounded or core.grounded(A, b)))
        or (oid == "MAGNETPULL" and A:hasType(b, "STEEL")) then
      return A:text("%s can't escape!", A:name(b))
    end
  end)
  core:on("priority", function(p, A, b, m)
    local id = ab(A, b)
    if id == "STALL" or (id == "MYCELIUMMIGHT" and m and isStatus(A, m)) then return p - 0.5 end
    if id == "QUICKDRAW" then
      local v = A:vol(b)
      if v.quickDrawTurn ~= A:turn() then
        v.quickDrawTurn, v.quickDraw = A:turn(), A:rng(10) < 3
        if v.quickDraw then say(A, "%s's %s let it move first!", A:name(b), nameOf(id)) end
      end
      if v.quickDraw then return p + 0.4 end
    end
    return p
  end)
  core:on("speed", function(s, A, b)
    local v = A:vol(b)
    local id = ab(A, b)
    if id == "UNBURDEN" and v.consumed and not A:item(b) then s = s * 2 end
    if boosted(A, b) == "speed" then s = s * 1.5 end
    if v.statOver and v.statOver.speed then s = s * v.statOver.speed / math.max(1, A:stat(b, "speed")) end
    return s
  end)
  core:on("ignoreStages", function(A, holder) if ab(A, holder) == "UNAWARE" then return true end end)
  core:on("infiltrates", function(A, u) if ab(A, u) == "INFILTRATOR" then return true end end)
  core:on("bypassProtect", function(A, u, t, m) if ab(A, u) == "UNSEENFIST" and flag("contact", m) then return true end end)
  core:on("noForceSwitch", function(A, t)
    local id = ab(A, t)
    if id == "SUCTIONCUPS" or id == "GUARDDOG" then
      say(A, "%s anchors itself with %s!", A:name(t), nameOf(id))
      return true
    end
  end)
  core:on("itemLocked", function(A, b)
    if ab(A, b) == "STICKYHOLD" then
      say(A, "%s's item cannot be removed!", A:name(b))
      return true
    end
  end)
  core:on("itemSuppressed", function(A, b) if ab(A, b) == "KLUTZ" then return true end end)
  core:on("gluttony", function(A, b) if ab(A, b) == "GLUTTONY" then return true end end)
  core:on("ripen", function(A, b) if ab(A, b) == "RIPEN" then return true end end)
  core:on("ateBerry", function(A, b, id)
    local aid = ab(A, b)
    if aid == "CHEEKPOUCH" and A:hp(b) > 0 and A:hp(b) < A:maxHp(b) then
      A:heal(b, math.max(1, math.floor(A:maxHp(b) / 3)), { text = A:text("%s's %s restored its HP!", A:name(b), nameOf(aid)) })
    end
    if aid == "CUDCHEW" then A:vol(b).cud = { id = id, turn = A:turn() } end
  end)
  core:on("noIndirect", function(A, b) if ab(A, b) == "MAGICGUARD" then return true end end)
  core:on("noContact", function(A, u) if ab(A, u) == "LONGREACH" then return true end end)
  core:on("noRecoil", function(A, b)
    local id = ab(A, b)
    if id == "ROCKHEAD" or id == "MAGICGUARD" then return true end
  end)
  core:on("weatherImmune", function(A, b)
    local id = ab(A, b)
    if id == "MAGICGUARD" or id == "OVERCOAT" then return true end
  end)
  core:on("hazardImmune", function(A, b) if ab(A, b) == "MAGICGUARD" then return true end end)
  core:on("drainReversed", function(A, u, t) if t and ab(A, t) == "LIQUIDOOZE" then return true end end)
  core:on("noWeather", function(A)
    for _, x in ipairs({ A:battlers() }) do
      if x and A:hp(x) > 0 then
        local id = raw(A, x)
        if id == "AIRLOCK" or id == "CLOUDNINE" then return true end
      end
    end
  end)
  core:on("weight", function(w, A, b)
    local id = ab(A, b)
    if id == "HEAVYMETAL" then return w * 2 end
    if id == "LIGHTMETAL" then return math.max(1, math.floor(w / 2)) end
    return w
  end)
  core:on("chanceScale", function(p, A, u) if ab(A, u) == "SERENEGRACE" then return math.min(100, p * 2) end return p end)
  core:on("noFlinch", function(A, b) if ab(A, b) == "SHIELDDUST" then return true end end)
  core:on("blockStatus", function(A, b, s, o)
    local id = ab(A, b)
    if o and o.secondary and id == "SHIELDDUST" then return "" end
    if id == "FLOWERVEIL" and A:hasType(b, "GRASS") and o and o.from and o.from ~= b then
      return A:text("%s surrounded itself with a veil of petals!", A:name(b))
    end
  end)
  core:on("skillLink", function(A, u) if ab(A, u) == "SKILLLINK" then return true end end)
  core:on("statusInflicted", function(A, ev)
    local b = ev.target
    if not (b and A:status(b) == "SLP" and ab(A, b) == "EARLYBIRD") then return end
    if A.gen == 1 then
      if b.sleepTurns then b.sleepTurns = math.max(1, math.ceil(b.sleepTurns / 2)) end
      local mon = A:mon(b)
      if mon and mon.sleepTurns then mon.sleepTurns = math.max(1, math.ceil(mon.sleepTurns / 2)) end
    else
      local mon = A:mon(b)
      if mon and mon.statusTurns then mon.statusTurns = math.max(1, math.ceil(mon.statusTurns / 2)) end
    end
  end)

  -- ------------------------------------------------------------------ the field's look on a type
  local function retype(A, b)
    local id = ab(A, b)
    if id == "FORECAST" then
      local w = A:weather()
      local t = ({ rain = "WATER", sun = "FIRE", hail = "ICE", snow = "ICE" })[w or ""] or "NORMAL"
      if not A:hasType(b, t) then A:setTypes(b, { t }); say(A, "%s transformed!", A:name(b)) end
    elseif id == "MIMICRY" then
      local t = ({ ELECTRIC = "ELECTRIC", GRASSY = "GRASS", MISTY = "FAIRY", PSYCHIC = "PSYCHIC" })[(core.terrain and core.terrain(A)) or ""]
      local v = A:vol(b)
      if t and not A:hasType(b, t) then
        v.mimicryTypes = v.mimicryTypes or A:types(b)
        A:setTypes(b, { t })
        say(A, "%s's type changed to %s!", A:name(b), t)
      elseif not t and v.mimicryTypes then
        A:setTypes(b, v.mimicryTypes)
        v.mimicryTypes = nil
        say(A, "%s returned to its original type!", A:name(b))
      end
    elseif id == "MULTITYPE" then
      local t = PLATE_TYPE[A:item(b) or ""]
      if t and not A:hasType(b, t) then A:setTypes(b, { t }) end
    elseif id == "ZENMODE" then
      local v = A:vol(b)
      local zen = A:hp(b) * 2 <= A:maxHp(b)
      if zen and not v.zen then
        v.zen, v.zenTypes, v.statOver = true, A:types(b), formStats(A, b, FORM.ZEN)
        A:setTypes(b, { "FIRE", "PSYCHIC" })
        say(A, "%s transformed!", A:name(b))
      elseif not zen and v.zen then
        A:setTypes(b, v.zenTypes or { "FIRE" })
        v.zen, v.zenTypes, v.statOver = nil, nil, nil
        say(A, "%s transformed!", A:name(b))
      end
    elseif id == "SCHOOLING" then
      local v = A:vol(b)
      local school = (A:level(b) or 1) >= 20 and A:hp(b) * 4 > A:maxHp(b)
      if school and not v.school then
        v.school, v.statOver = true, formStats(A, b, FORM.SCHOOL)
        say(A, "%s formed a school!", A:name(b))
      elseif not school and v.school then
        v.school, v.statOver = nil, nil
        say(A, "%s stopped schooling!", A:name(b))
      end
    end
  end

  -- ------------------------------------------------------------------ switching in
  local ENTRY_LINE = { PRESSURE = "%s is exerting its pressure!", MOLDBREAKER = "%s breaks the mold!",
    TERAVOLT = "%s is radiating a bursting aura!", TURBOBLAZE = "%s is radiating a blazing aura!",
    AIRLOCK = "The effects of the weather disappeared.", CLOUDNINE = "The effects of the weather disappeared.",
    NEUTRALIZINGGAS = "Neutralizing gas filled the area!", UNNERVE = "%s's team is too nervous to eat Berries!",
    ASONEGLASTRIER = "%s's team is too nervous to eat Berries!", ASONESPECTRIER = "%s's team is too nervous to eat Berries!" }
  local UNNERVING = { UNNERVE = true, ASONEGLASTRIER = true, ASONESPECTRIER = true }
  core:on("switchedIn", function(A, ev)
    local prev = ev.previous
    local f = A:field()
    if prev then
      local pid = raw(A, prev)
      if pid == "ZEROTOHERO" then
        f.heroes = f.heroes or setmetatable({}, { __mode = "k" })
        f.heroes[A:mon(prev)] = true
      end
      if UNNERVING[pid] then local o = A:foe(prev); if o then A:vol(o).unnerved = nil end end
    end
    local b = ev.battler
    if not b or A:hp(b) <= 0 then return end
    local id = ab(A, b)
    if not id then return end
    local o = A:foe(b)
    if id == "NEUTRALIZINGGAS" then f.gasOn = true end
    if ENTRY_LINE[id] then
      local who = (id == "UNNERVE" or UNNERVING[id]) and (o and A:name(o) or "The foe") or A:name(b)
      say(A, ENTRY_LINE[id], who)
    end
    if UNNERVING[id] and o then A:vol(o).unnerved = true end
    if not (o and A:hp(o) > 0) then retype(A, b) return end
    local oid = ab(A, o)
    if id == "TRACE" and oid and not NO_COPY[oid] then
      core.setAbility(A, b, oid)
      say(A, "%s traced %s's %s!", A:name(b), A:name(o), nameOf(oid))
      if core.abilityEntered then core.abilityEntered(A, b) end
    elseif id == "DOWNLOAD" then
      local def, spd = A:stat(o, "defense"), A:stat(o, "spDef")
      say(A, "%s's %s!", A:name(b), nameOf(id))
      A:stages(b, def < spd and { attack = 1 } or { spAtk = 1 })
    elseif id == "FRISK" and A:item(o) then
      say(A, "%s frisked %s and found its %s!", A:name(b), A:name(o), A:itemName(A:item(o)))
    elseif id == "ANTICIPATION" then
      for _, mv in ipairs(A:moves(o)) do
        local d = A:moveDef(mv.id)
        if d and (d.power or 0) > 0 and (A:effectiveness(A:moveType(d), b) or 10) > 10 then
          say(A, "%s shuddered!", A:name(b))
          break
        end
      end
    elseif id == "FOREWARN" then
      local best, bp = nil, -1
      for _, mv in ipairs(A:moves(o)) do
        local d = A:moveDef(mv.id)
        if d and (d.power or 0) > bp then best, bp = d, d.power or 0 end
      end
      if best then say(A, "%s was alerted to %s!", A:name(b), best.name or best.id) end
    elseif id == "SCREENCLEANER" then
      for _, x in ipairs({ b, o }) do
        A:side(x).auroraVeil = nil
        if A.gen == 1 then x.reflect, x.lightScreen = nil, nil
        else
          local scr = A.battle.screens and A.battle.screens[A:sideName(x)]
          if scr then scr.reflect, scr.lightScreen = 0, 0 end
        end
      end
      say(A, "All screens on the field were cleansed!")
    elseif id == "ZEROTOHERO" and f.heroes and f.heroes[A:mon(b)] then
      A:vol(b).statOver = formStats(A, b, FORM.HERO)
      say(A, "%s underwent a heroic transformation!", A:name(b))
    end
    retype(A, b)
  end)

  -- ------------------------------------------------------------------ the end of the turn
  core:on("endTurn", function(A)
    for _, b in ipairs({ A:battlers() }) do
      if b and A:hp(b) > 0 then
        local id = ab(A, b)
        local o = A:foe(b)
        if id == "BADDREAMS" and o and A:hp(o) > 0 and A:status(o) == "SLP" and not core:ask("noIndirect", A, o) then
          A:damage(o, math.max(1, math.floor(A:maxHp(o) / 8)), { text = A:text("%s is tormented!", A:name(o)) })
        elseif id == "MOODY" then
          local up, down = {}, {}
          for _, st in ipairs(FIVE) do
            if A:stage(b, st) < 6 then up[#up + 1] = st end
            if A:stage(b, st) > -6 then down[#down + 1] = st end
          end
          local change = {}
          if #up > 0 then change[up[A:rng(#up) + 1]] = 2 end
          local others = {}
          for _, st in ipairs(down) do if not change[st] then others[#others + 1] = st end end
          if #others > 0 then change[others[A:rng(#others) + 1]] = -1 end
          if next(change) then say(A, "%s's %s!", A:name(b), nameOf(id)); A:stages(b, change) end
        elseif id == "HARVEST" then
          local v = A:vol(b)
          local id2 = v.consumed
          if id2 and tostring(id2):find("BERRY") and not A:item(b) and (A:weather() == "sun" or A:rng(2) == 0) then
            A:setItem(b, id2)
            v.consumed = nil
            say(A, "%s harvested one %s!", A:name(b), A:itemName(id2))
          end
        elseif id == "HUNGERSWITCH" then
          local v = A:vol(b)
          v.hangry = not v.hangry
        elseif id == "CUDCHEW" then
          local v = A:vol(b)
          if v.cud and v.cud.turn < A:turn() and not A:item(b) and core.heldBerry then
            local berry = v.cud.id
            v.cud = nil
            A:setItem(b, berry)
            say(A, "%s's %s!", A:name(b), nameOf(id))
            pcall(core.heldBerry, A, b)
            if A:item(b) == berry then A:setItem(b, nil) end
          end
        end
        retype(A, b)
      end
    end
  end)

  -- ------------------------------------------------------------------ after the battle, and running
  local PICKUP = { "ORAN_BERRY", "SITRUS_BERRY", "LUM_BERRY", "LEPPA_BERRY", "CHESTO_BERRY", "PERSIM_BERRY" }
  core:on("battleEnded", function(A)
    local p = A.battle and A.battle.player
    if not p then return end
    for _, mon in ipairs(A:party(p) or {}) do
      if type(mon) == "table" and (mon.hp or 0) > 0 and not mon.isEgg then
        local r = A.battle.data and A.battle.data.pokemon and A.battle.data.pokemon[mon.species]
        local id = core.abilityForMon and core.abilityForMon(r, mon.dvs)
        local held = A.gen == 1 and (mon.extra and mon.extra.national_dex_gen3 and mon.extra.national_dex_gen3.item) or mon.item
        if id == "PICKUP" and not held and A:rng(10) == 0 then
          local pick = PICKUP[A:rng(#PICKUP) + 1]
          if A.battle.data.items and A.battle.data.items[pick] then A:setItem(mon, pick) end
        end
      end
    end
  end)
  if opts.mod and opts.mod.hooks then
    pcall(function()
      opts.mod.hooks:wrap("battle.run", function(nextFn, c, ...)
        local A = core.lastAdapter
        local battle = type(c) == "table" and (c.battle or c) or nil
        if A and battle and A.battle == battle and A.battle.player and ab(A, A.battle.player) == "RUNAWAY" then
          return true
        end
        return nextFn(c, ...)
      end)
    end)
  end
end
