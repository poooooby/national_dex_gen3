-- Conditions on a battler or its side on Gen 1 / Gen 2: what stops a move (Taunt, Torment,
-- Encore, Heal Block, Throat Chop, Imprison, Powder), what counts down at the end of the turn
-- (Ingrain, Aqua Ring, Salt Cure, Wish, Future Sight, Yawn, Perish Song, Nightmare, Curse,
-- Octolock, Uproar), stat swaps and splits, type changes, cures, two-turn moves, the moves that
-- copy or call others, and the ones Red lacks that Gold has (Belly Drum, Destiny Bond, Lock-On,
-- Mean Look, Spite, Sketch, Sleep Talk ...). Today's rules; the state is on A:vol / A:side /
-- A:field, never the party Pokemon.

return function(core)
  local Track = core.track
  local function status(t) t.kind = "status"; return t end
  local function hit(t) t.kind = "hit"; return t end
  local function say(A, fmt, ...) A:say(A:text(fmt, ...)) end
  local STAGES = { "attack", "defense", "spAtk", "spDef", "speed", "accuracy", "evasion" }
  local function active(v, key, A) return v[key] and v[key] > A:turn() end
  local function isStatus(m) return (m.power or 0) == 0 end

  local SOUND = {}
  for _, id in ipairs({ "GROWL", "ROAR", "SING", "SUPERSONIC", "SCREECH", "SNORE", "PERISH_SONG", "HEAL_BELL",
      "UPROAR", "HYPER_VOICE", "METAL_SOUND", "GRASSWHISTLE", "GRASS_WHISTLE", "HOWL", "BUG_BUZZ", "CHATTER",
      "ROUND", "ECHOED_VOICE", "RELIC_SONG", "SNARL", "NOBLE_ROAR", "DISARMING_VOICE", "PARTING_SHOT",
      "BOOMBURST", "CONFIDE", "SPARKLING_ARIA", "CLANGING_SCALES", "CLANGOROUS_SOUL", "OVERDRIVE",
      "EERIE_SPELL", "TORCH_SONG", "ALLURING_VOICE", "PSYCHIC_NOISE" }) do SOUND[id] = true end
  local HEALING = {}
  for _, id in ipairs({ "RECOVER", "SOFTBOILED", "SOFT_BOILED", "MILK_DRINK", "REST", "MOONLIGHT", "MORNING_SUN",
      "SYNTHESIS", "ROOST", "SLACK_OFF", "HEAL_ORDER", "WISH", "SWALLOW", "SHORE_UP", "STRENGTH_SAP",
      "JUNGLE_HEALING", "LUNAR_BLESSING", "LIFE_DEW", "HEAL_PULSE", "FLORAL_HEALING", "PURIFY", "AQUA_RING" }) do
    HEALING[id] = true
  end

  -- ------------------------------------------------------------------ what stops a move
  core:on("beforeMove", function(A, u, t, m, isCalled)
    local v = A:vol(u)
    local turn = A:turn()
    if isStatus(m) and active(v, "taunt", A) then
      return A:text("%s can't use %s after the taunt!", A:name(u), m.name or m.id)
    end
    if v.torment and v.lastMove == m.id and not isCalled then
      return A:text("%s can't use the same move twice in a row due to the torment!", A:name(u))
    end
    if HEALING[m.id] and active(v, "healBlock", A) then
      return A:text("%s can't use %s because of Heal Block!", A:name(u), m.name or m.id)
    end
    if SOUND[m.id] and active(v, "throatChop", A) then
      return A:text("The effects of Throat Chop prevent %s from using certain moves!", A:name(u))
    end
    local foe = A:foe(u)
    local fv = foe and A:vol(foe)
    if fv and fv.imprison and not isCalled then
      for _, mv in ipairs(A:moves(foe)) do
        if mv.id == m.id then return A:text("%s can't use its sealed %s!", A:name(u), m.name or m.id) end
      end
    end
    if v.powder == turn and A:moveType(m) == "FIRE" then
      v.powder = nil
      A:damage(u, math.max(1, math.floor(A:maxHp(u) / 4)),
        { text = A:text("When the flame touched the powder on the Pokemon, it exploded!") })
      return ""
    end
    -- Encore (Gold runs its own): the move it was made to repeat
    if A.gen == 1 and v.encore and active(v.encore, "untilTurn", A) and v.encore.id ~= m.id and not isCalled then
      return { id = v.encore.id }
    end
    -- the foe's coat bounces an aimed status move back (Magic Coat); its Snatch steals one aimed
    -- at the user itself
    if fv and isStatus(m) and not isCalled then
      if fv.magicCoat == turn and m.id ~= "MAGIC_COAT" and core.specAimed(m) then
        fv.magicCoat = nil
        say(A, "%s bounced the %s back!", A:name(foe), m.name or m.id)
        return { user = foe, target = u, id = m.id }
      end
      if fv.snatch == turn and core.specSelf(m) and m.id ~= "SNATCH" then
        fv.snatch = nil
        say(A, "%s snatched %s's move!", A:name(foe), A:name(u))
        return { user = foe, target = u, id = m.id }
      end
    end
    return nil
  end)
  core:on("noHeal", function(A, b) if active(A:vol(b), "healBlock", A) then return true end end)

  -- is a status move aimed at the foe / only at the user (ours: the spec; the cart's: a guess)
  function core.specAimed(m)
    local spec = core.liveSpecs and core.liveSpecs[m.id]
    if spec then return spec.aimed and true or false end
    return (m.accuracy or 100) < 100 or tostring(m.effect or ""):find("DOWN") ~= nil
      or tostring(m.effect or ""):find("SLEEP") ~= nil or tostring(m.effect or ""):find("PARALY") ~= nil
      or tostring(m.effect or ""):find("POISON") ~= nil or tostring(m.effect or ""):find("CONFUS") ~= nil
  end
  function core.specSelf(m)
    local spec = core.liveSpecs and core.liveSpecs[m.id]
    if spec then return spec.selfOnly and true or false end
    return tostring(m.effect or ""):find("UP") ~= nil or tostring(m.effect or ""):find("HEAL") ~= nil
  end

  local function lasting(field, turns, text, opts)
    return status({ aimed = true, run = function(A, u, t)
      local v = A:vol(t)
      if active(v, field, A) then return false end
      v[field] = A:turn() + turns
      say(A, text, A:name(t))
      return true
    end })
  end
  core:effect("TAUNT", lasting("taunt", 3, "%s fell for the taunt!"))
  core:rule("HEAL_BLOCK", lasting("healBlock", 5, "%s was prevented from healing!"))
  core:effect("TORMENT", status({ aimed = true, run = function(A, u, t)
    local v = A:vol(t)
    if v.torment then return false end
    v.torment = true
    say(A, "%s was subjected to torment!", A:name(t))
    return true
  end }))
  core:effect("IMPRISON", status({ selfOnly = true, run = function(A, u)
    local v = A:vol(u)
    if v.imprison then return false end
    v.imprison = true
    say(A, "%s sealed any moves its target shares with it!", A:name(u))
    return true
  end }))
  core:effect("ENCORE", status({ aimed = true, run = function(A, u, t)
    local last = A:vol(t).lastMove
    if not last or last == "ENCORE" then return false end
    A:vol(t).encore = { id = last, untilTurn = A:turn() + 3 }
    say(A, "%s received an encore!", A:name(t))
    return true
  end }))
  core:rule("THROAT_CHOP", hit({ secondary = function(A, u, t) A:vol(t).throatChop = A:turn() + 2 end }))
  core:rule("POWDER", status({ aimed = true, run = function(A, u, t)
    A:vol(t).powder = A:turn()
    say(A, "%s is covered in powder!", A:name(t))
    return true
  end }))
  core:effect("MAGIC_COAT", status({ selfOnly = true, run = function(A, u)
    A:vol(u).magicCoat = A:turn()
    say(A, "%s shrouded itself with Magic Coat!", A:name(u))
    return true
  end }))
  core:effect("SNATCH", status({ selfOnly = true, run = function(A, u)
    A:vol(u).snatch = A:turn()
    say(A, "%s waits for a target to make a move!", A:name(u))
    return true
  end }))

  -- ------------------------------------------------------------------ stat moves
  core:effect("BELLY_DRUM", status({ selfOnly = true, run = function(A, u)
    local cost = math.floor(A:maxHp(u) / 2)
    if A:hp(u) <= cost or A:stage(u, "attack") >= 6 then return false end
    A:damage(u, cost)
    A:setStage(u, "attack", 6)
    say(A, "%s cut its own HP and maximized its Attack!", A:name(u))
    return true
  end }))
  core:effect("PSYCH_UP", status({ selfOnly = true, run = function(A, u, t)
    for _, s in ipairs(STAGES) do A:setStage(u, s, A:stage(t, s)) end
    say(A, "%s copied %s's stat changes!", A:name(u), A:name(t))
    return true
  end }))
  core:rule("ACUPRESSURE", status({ selfOnly = true, run = function(A, u)
    local open = {}
    for _, s in ipairs(STAGES) do if A:stage(u, s) < 6 then open[#open + 1] = s end end
    if #open == 0 then return false end
    return A:stages(u, { [open[A:rng(#open) + 1]] = 2 })
  end }))
  local function payFor(fraction, changes)
    return status({ selfOnly = true, run = function(A, u)
      local cost = math.floor(A:maxHp(u) * fraction)
      if A:hp(u) <= cost then return false end
      A:damage(u, cost)
      return A:stages(u, changes)
    end })
  end
  core:rule("CLANGOROUS_SOUL", payFor(1 / 3, { attack = 1, defense = 1, spAtk = 1, spDef = 1, speed = 1 }))
  core:rule("FILLET_AWAY", payFor(1 / 2, { attack = 2, spAtk = 2, speed = 2 }))
  core:rule("NO_RETREAT", status({ selfOnly = true, run = function(A, u)
    if A:vol(u).noRetreat then return false end
    A:vol(u).noRetreat, A:vol(u).trapped = true, true
    return A:stages(u, { attack = 1, defense = 1, spAtk = 1, spDef = 1, speed = 1 })
  end }))
  -- the Plus / Minus moves: nothing for a Pokemon without either ability
  local function plusMinus(changes)
    return status({ selfOnly = true, run = function(A, u)
      local ab = core:ask("ability", A, u)
      if ab ~= "PLUS" and ab ~= "MINUS" then return false end
      return A:stages(u, changes)
    end })
  end
  core:rule("GEAR_UP", plusMinus({ attack = 1, spAtk = 1 }))
  core:rule("MAGNETIC_FLUX", plusMinus({ defense = 1, spDef = 1 }))
  local function grassBoost(changes, needGround)
    return status({ selfOnly = true, run = function(A)
      local any = false
      for _, b in ipairs({ A:battlers() }) do
        if b and A:hasType(b, "GRASS") and (not needGround or core.grounded(A, b)) then
          if A:stages(b, changes) then any = true end
        end
      end
      return any
    end })
  end
  core:rule("ROTOTILLER", grassBoost({ attack = 1, spAtk = 1 }, true))
  core:rule("FLOWER_SHIELD", grassBoost({ defense = 1 }))
  core:rule("TOPSY_TURVY", status({ aimed = true, run = function(A, u, t)
    local any = false
    for _, s in ipairs(STAGES) do
      local v = A:stage(t, s)
      if v ~= 0 then A:setStage(t, s, -v); any = true end
    end
    if any then say(A, "All stat changes on %s were inverted!", A:name(t)) end
    return any
  end }))
  core:rule("STRENGTH_SAP", status({ aimed = true, run = function(A, u, t)
    if A:stage(t, "attack") <= -6 then return false end
    local atk = A:stat(t, "attack")
    A:stages(t, { attack = -1 }, { from = u })
    if A:hp(u) < A:maxHp(u) then A:heal(u, atk, { text = true }) end
    return true
  end }))
  core:rule("VENOM_DRENCH", status({ aimed = true, run = function(A, u, t)
    local s = A:status(t)
    if s ~= "PSN" and s ~= "TOX" then return false end
    return A:stages(t, { attack = -1, spAtk = -1, speed = -1 }, { from = u })
  end }))
  core:rule("CAPTIVATE", status({ aimed = true, run = function(A, u, t)
    local gu, gt = core:ask("gender", A, u), core:ask("gender", A, t)
    if not gu or not gt or gu == gt then return false end
    return A:stages(t, { spAtk = -2 }, { from = u })
  end }))
  core:effect("MEMENTO", status({ aimed = true, run = function(A, u, t)
    A:stages(t, { attack = -2, spAtk = -2 }, { from = u })
    A:damage(u, A:hp(u))
    return true
  end }))
  -- the target's raised stats become the user's, then it hits
  core:rule("SPECTRAL_THIEF", hit({ sureHit = false, fail = function(A, u, t)
    local stole = false
    for _, s in ipairs(STAGES) do
      local v = A:stage(t, s)
      if v > 0 then
        A:setStage(u, s, A:stage(u, s) + v)
        A:setStage(t, s, 0)
        stole = true
      end
    end
    if stole then say(A, "%s stole the target's boosted stats!", A:name(u)) end
    return false
  end }))
  -- stats swapped or shared, kept on the battlers for the rest of their time out
  local function statOf(A, b, s)
    local o = A:vol(b).statOver
    return (o and o[s]) or A:stat(b, s)
  end
  local function setOver(A, b, s, v)
    local vol = A:vol(b)
    vol.statOver = vol.statOver or {}
    vol.statOver[s] = v
  end
  local function split(keys, text)
    return status({ aimed = true, run = function(A, u, t)
      for _, s in ipairs(keys) do
        local avg = math.floor((statOf(A, u, s) + statOf(A, t, s)) / 2)
        setOver(A, u, s, avg)
        setOver(A, t, s, avg)
      end
      say(A, text, A:name(u))
      return true
    end })
  end
  core:rule("POWER_SPLIT", split({ "attack", "spAtk" }, "%s shared its power with the target!"))
  core:rule("GUARD_SPLIT", split({ "defense", "spDef" }, "%s shared its guard with the target!"))
  local function swap(keys, text)
    return status({ aimed = true, run = function(A, u, t)
      for _, s in ipairs(keys) do
        local a, b = A:stage(u, s), A:stage(t, s)
        A:setStage(u, s, b)
        A:setStage(t, s, a)
      end
      say(A, text, A:name(u))
      return true
    end })
  end
  core:rule("POWER_SWAP", swap({ "attack", "spAtk" }, "%s switched all changes to its Attack and Sp. Atk with the target!"))
  core:rule("GUARD_SWAP", swap({ "defense", "spDef" }, "%s switched all changes to its Defense and Sp. Def with the target!"))
  core:rule("HEART_SWAP", swap(STAGES, "%s switched stat changes with the target!"))
  core:rule("SPEED_SWAP", status({ aimed = true, run = function(A, u, t)
    local a, b = statOf(A, u, "speed"), statOf(A, t, "speed")
    setOver(A, u, "speed", b)
    setOver(A, t, "speed", a)
    say(A, "%s switched Speed with its target!", A:name(u))
    return true
  end }))
  core:rule("POWER_TRICK", status({ selfOnly = true, run = function(A, u)
    local a, d = statOf(A, u, "attack"), statOf(A, u, "defense")
    setOver(A, u, "attack", d)
    setOver(A, u, "defense", a)
    say(A, "%s switched its Attack and Defense!", A:name(u))
    return true
  end }))
  core:on("speed", function(s, A, b)
    local o = A:vol(b).statOver
    if o and o.speed then return math.floor(s * o.speed / math.max(1, A:stat(b, "speed"))) end
    return s
  end)
  -- Red: the HP of both, averaged (Gold runs its own)
  core:effect("PAIN_SPLIT", status({ aimed = true, run = function(A, u, t)
    local avg = math.floor((A:hp(u) + A:hp(t)) / 2)
    for _, b in ipairs({ u, t }) do
      local d = avg - A:hp(b)
      if d > 0 then A:heal(b, d) elseif d < 0 then A:damage(b, -d) end
    end
    say(A, "The battlers shared their pain!")
    return true
  end }))

  -- ------------------------------------------------------------------ types
  local function retype(typeName, text)
    return status({ aimed = true, run = function(A, u, t)
      local ts = A:types(t)
      if #ts == 1 and ts[1] == typeName then return false end
      A:setTypes(t, { typeName })
      say(A, text, A:name(t))
      return true
    end })
  end
  core:rule("SOAK", retype("WATER", "%s transformed into the Water type!"))
  core:rule("MAGIC_POWDER", retype("PSYCHIC", "%s transformed into the Psychic type!"))
  local function addType(typeName, text)
    return status({ aimed = true, run = function(A, u, t)
      if A:hasType(t, typeName) then return false end
      local ts = A:types(t)
      ts[#ts + 1] = typeName
      A:setTypes(t, ts)
      say(A, text, A:name(t), typeName)
      return true
    end })
  end
  core:rule("TRICK_OR_TREAT", addType("GHOST", "%s's type changed!"))
  core:rule("FORESTS_CURSE", addType("GRASS", "%s's type changed!"))
  core:rule("REFLECT_TYPE", status({ aimed = true, run = function(A, u, t)
    A:setTypes(u, A:types(t))
    say(A, "%s's type became the same as %s's type!", A:name(u), A:name(t))
    return true
  end }))
  -- a type that resists the foe's last move (Conversion 2), the ground's (Camouflage)
  local RESISTS_ORDER = { "STEEL", "FIRE", "WATER", "GRASS", "ROCK", "GHOST", "DARK", "FAIRY", "FIGHTING",
    "POISON", "FLYING", "PSYCHIC", "BUG", "GROUND", "ELECTRIC", "ICE", "DRAGON", "NORMAL" }
  core:effect("CONVERSION_2", status({ selfOnly = true, run = function(A, u, t)
    local last = A:vol(t).lastMove
    local m = last and A:moveDef(last)
    if not m then return false end
    local mt = A:moveType(m)
    for _, ty in ipairs(RESISTS_ORDER) do
      local okE, eff = pcall(A.typeEff, A, mt, ty)
      eff = okE and eff or nil
      if eff and eff < 10 and not A:hasType(u, ty) then
        A:setTypes(u, { ty })
        say(A, "%s transformed into the %s type!", A:name(u), ty)
        return true
      end
    end
    return false
  end }))
  core:effect("CAMOUFLAGE", status({ selfOnly = true, run = function(A, u)
    local tr = core.terrain and core.terrain(A)
    local ty = ({ ELECTRIC = "ELECTRIC", GRASSY = "GRASS", MISTY = "FAIRY", PSYCHIC = "PSYCHIC" })[tr or ""] or "NORMAL"
    if A:hasType(u, ty) and #A:types(u) == 1 then return false end
    A:setTypes(u, { ty })
    say(A, "%s transformed into the %s type!", A:name(u), ty)
    return true
  end }))
  core:rule("REVELATION_DANCE", hit({ type = function(A, u) return A:types(u)[1] end }))
  core:rule("TAR_SHOT", status({ aimed = true, run = function(A, u, t)
    local v = A:vol(t)
    local any = A:stages(t, { speed = -1 }, { from = u })
    if not v.tarShot then
      v.tarShot = true
      say(A, "%s became weaker to fire!", A:name(t))
      any = true
    end
    return any
  end }))
  core:on("damageMult", function(k, A, u, t, m)
    if A:vol(t).tarShot and A:moveType(m) == "FIRE" then k = k * 2 end
    return k
  end)
  core:rule("ELECTRIFY", status({ aimed = true, run = function(A, u, t)
    A:vol(t).electrify = A:turn()
    say(A, "%s's moves have been electrified!", A:name(t))
    return true
  end }))
  core:rule("ION_DELUGE", status({ selfOnly = true, run = function(A)
    A:field().ionDeluge = A:turn()
    say(A, "A deluge of ions showers the battlefield!")
    return true
  end }))
  core:rule("PLASMA_FISTS", hit({ after = function(A)
    if A:field().ionDeluge ~= A:turn() then
      A:field().ionDeluge = A:turn()
      say(A, "A deluge of ions showers the battlefield!")
    end end }))
  core:on("moveType", function(A, u, m)
    if A:vol(u).electrify == A:turn() then return "ELECTRIC" end
    if A:field().ionDeluge == A:turn() and A:moveType(m) == "NORMAL" then return "ELECTRIC" end
  end)
  -- what a hit ignores: Ghost against Normal / Fighting (Foresight), Dark against Psychic
  -- (Miracle Eye), Flying against Ground (Smack Down, Thousand Arrows, Gravity, Ingrain)
  core:on("dropTypes", function(A, u, t, m)
    local v = A:vol(t)
    local mt = A:moveType(m)
    local drop
    if v.foresight and (mt == "NORMAL" or mt == "FIGHTING") then drop = { GHOST = true } end
    if v.miracleEye and mt == "PSYCHIC" then drop = { DARK = true } end
    if mt == "GROUND" and (v.smackedDown or v.ingrain or A:field().gravity or m.id == "THOUSAND_ARROWS") then
      drop = { FLYING = true }
    end
    return drop
  end)
  core:on("ungrounded", function(A, b)
    if A:vol(b).smackedDown or A:vol(b).ingrain then return nil end
  end)
  core:on("immune", function(A, u, t, m)
    local v = A:vol(t)
    if A:moveType(m) == "GROUND" and active(v, "magnetRise", A) and not A:field().gravity then return true end
  end)
  local function sight(field, text)
    return status({ aimed = true, run = function(A, u, t)
      A:vol(t)[field] = true
      say(A, text, A:name(u), A:name(t))
      return true
    end })
  end
  core:effect("FORESIGHT", sight("foresight", "%s identified %s!"))
  core:rule("MIRACLE_EYE", sight("miracleEye", "%s identified %s!"))
  core:rule("SMACK_DOWN", hit({ secondary = function(A, u, t)
    local v = A:vol(t)
    if not v.smackedDown and (A:hasType(t, "FLYING") or active(v, "magnetRise", A)) then
      v.smackedDown, v.magnetRise = true, nil
      say(A, "%s fell straight down!", A:name(t))
    end end }))
  core:rule("THOUSAND_ARROWS", hit({ secondary = function(A, u, t)
    local v = A:vol(t)
    if not v.smackedDown and A:hasType(t, "FLYING") then
      v.smackedDown = true
      say(A, "%s fell straight down!", A:name(t))
    end end }))
  core:rule("MAGNET_RISE", status({ selfOnly = true, run = function(A, u)
    local v = A:vol(u)
    if active(v, "magnetRise", A) or v.smackedDown or v.ingrain then return false end
    v.magnetRise = A:turn() + 5
    say(A, "%s levitated with electromagnetism!", A:name(u))
    return true
  end }))
  core:on("ungrounded", function(A, b) if active(A:vol(b), "magnetRise", A) then return true end end)

  -- ------------------------------------------------------------------ next move
  core:rule("LASER_FOCUS", status({ selfOnly = true, run = function(A, u)
    A:vol(u).laserFocus = A:turn() + 1
    say(A, "%s concentrated intensely!", A:name(u))
    return true
  end }))
  core:on("forceCrit", function(A, b)
    local v = A:vol(b)
    if v.laserFocus and v.laserFocus >= A:turn() then return true end
  end)
  core:effect("CHARGE", status({ selfOnly = true, run = function(A, u)
    A:vol(u).charged = A:turn() + 1
    say(A, "%s began charging power!", A:name(u))
    A:stages(u, { spDef = 1 })
    return true
  end }))
  core:on("damageMult", function(k, A, u, t, m)
    local v = A:vol(u)
    if v.charged and v.charged >= A:turn() and A:moveType(m) == "ELECTRIC" then
      v.charged = nil
      k = k * 2
    end
    return k
  end)
  core:effect("LOCK_ON", status({ aimed = true, run = function(A, u, t)
    A:vol(u).lockOn = { target = t, turn = A:turn() + 1 }
    say(A, "%s took aim at %s!", A:name(u), A:name(t))
    return true
  end }))
  core:on("accuracy", function(A, u, t)
    local l = A:vol(u).lockOn
    if l and l.target == t and l.turn >= A:turn() then return true end
  end)
  core:effect("STOCKPILE", status({ selfOnly = true, run = function(A, u)
    local v = A:vol(u)
    if (v.stockpile or 0) >= 3 then return false end
    v.stockpile = (v.stockpile or 0) + 1
    say(A, "%s stockpiled %d!", A:name(u), v.stockpile)
    A:stages(u, { defense = 1, spDef = 1 })
    return true
  end }))
  local function release(A, u)
    local v = A:vol(u)
    local n = v.stockpile or 0
    v.stockpile = nil
    A:stages(u, { defense = -n, spDef = -n })
    return n
  end
  core:effect("SPIT_UP", hit({
    fail = function(A, u) return (A:vol(u).stockpile or 0) == 0 end,
    power = function(A, u) return 100 * (A:vol(u).stockpile or 1) end,
    after = function(A, u) release(A, u) end,
  }))
  core:effect("SWALLOW", status({ selfOnly = true, run = function(A, u)
    local n = A:vol(u).stockpile or 0
    if n == 0 then return false end
    local frac = n == 1 and 1 / 4 or n == 2 and 1 / 2 or 1
    if A:hp(u) < A:maxHp(u) then A:heal(u, math.max(1, math.floor(A:maxHp(u) * frac)), { text = true }) end
    release(A, u)
    return true
  end }))
  core:effect("MUD_SPORT", status({ selfOnly = true, run = function(A)
    if A:field().mudSport then return false end
    A:field().mudSport = 5
    say(A, "Electricity's power was weakened!")
    return true
  end }))
  core:effect("WATER_SPORT", status({ selfOnly = true, run = function(A)
    if A:field().waterSport then return false end
    A:field().waterSport = 5
    say(A, "Fire's power was weakened!")
    return true
  end }))
  core:on("damageMult", function(k, A, u, t, m)
    local f, mt = A:field(), A:moveType(m)
    if f.mudSport and mt == "ELECTRIC" then k = k / 3 end
    if f.waterSport and mt == "FIRE" then k = k / 3 end
    if A:vol(t).glaiveRush and A:vol(t).glaiveRush >= A:turn() then k = k * 2 end
    return k
  end)
  core:rule("GLAIVE_RUSH", hit({ after = function(A, u, t, m, dealt)
    if dealt > 0 then A:vol(u).glaiveRush = A:turn() + 1 end end }))
  core:rule("ICE_SPINNER", hit({ after = function(A, u, t, m, dealt)
    if dealt > 0 and A:field().terrain then A:field().terrain = nil end end }))
  core:rule("EERIE_SPELL", hit({ secondary = function(A, u, t)
    local last = A:vol(t).lastMove
    for _, mv in ipairs(A:moves(t)) do
      if mv.id == last and (mv.pp or 0) > 0 then
        local before = mv.pp
        mv.pp = math.max(0, mv.pp - 3)
        say(A, "It reduced the PP of %s's move by %d!", A:name(t), before - mv.pp)
        break
      end
    end end }))
  core:effect("SPITE", status({ aimed = true, run = function(A, u, t)
    local last = A:vol(t).lastMove or (A.gen == 1 and t.lastMove)
    for _, mv in ipairs(A:moves(t)) do
      if mv.id == last and (mv.pp or 0) > 0 then
        local before = mv.pp
        mv.pp = math.max(0, mv.pp - 4)
        say(A, "It reduced the PP of %s's move by %d!", A:name(t), before - mv.pp)
        return true
      end
    end
    return false
  end }))
  core:rule("SHELL_TRAP", hit({ fail = function(A, u)
    local v = A:vol(u)
    if (v.tookThisTurn or 0) > 0 and v.lastTakenKind == "physical" then return false end
    return A:text("%s's shell trap didn't work!", A:name(u))
  end }))
  core:rule("POLLEN_PUFF", hit({}))
  -- ------------------------------------------------------------------ cures and healing
  local function cureSide(A, u, text)
    for _, mon in ipairs(A:party(u)) do
      if type(mon) == "table" then mon.status = nil end
    end
    A:cure(u)
    say(A, text)
    return true
  end
  core:effect("HEAL_BELL", function(row)
    return status({ selfOnly = true, run = function(A, u)
      return cureSide(A, u, row.id == "AROMATHERAPY" and "A soothing aroma wafted through the area!"
        or "A bell chimed!")
    end })
  end)
  core:effect("REFRESH", status({ selfOnly = true, run = function(A, u)
    local s = A:status(u)
    if s ~= "BRN" and s ~= "PSN" and s ~= "TOX" and s ~= "PAR" then return false end
    A:cure(u)
    say(A, "%s's status returned to normal!", A:name(u))
    return true
  end }))
  core:rule("PURIFY", status({ aimed = true, run = function(A, u, t)
    if not A:status(t) then return false end
    A:cure(t)
    say(A, "%s's status returned to normal!", A:name(t))
    if A:hp(u) < A:maxHp(u) then A:heal(u, math.max(1, math.floor(A:maxHp(u) / 2)), { text = true }) end
    return true
  end }))
  core:rule("JUNGLE_HEALING", status({ selfOnly = true, run = function(A, u)
    local any = false
    if A:hp(u) < A:maxHp(u) then A:heal(u, math.max(1, math.floor(A:maxHp(u) / 4)), { text = true }); any = true end
    if A:status(u) then A:cure(u); any = true end
    return any
  end }))
  core:rule("PSYCHO_SHIFT", status({ aimed = true, run = function(A, u, t)
    local s = A:status(u)
    local names = { BRN = "BURN", PAR = "PARALYSIS", PSN = "POISON", TOX = "TOXIC", SLP = "SLEEP", FRZ = "FREEZE" }
    if not s or A:status(t) then return false end
    if not A:ailment(t, names[s], { from = u }) then return false end
    A:cure(u)
    return true
  end }))
  core:effect("WISH", status({ selfOnly = true, run = function(A, u)
    local s = A:side(u)
    if s.wish then return false end
    s.wish = { turn = A:turn() + 1, amount = math.max(1, math.floor(A:maxHp(u) / 2)), name = A:name(u) }
    return true
  end }))
  core:effect("INGRAIN", status({ selfOnly = true, run = function(A, u)
    local v = A:vol(u)
    if v.ingrain then return false end
    v.ingrain, v.trapped, v.magnetRise = true, true, nil
    say(A, "%s planted its roots!", A:name(u))
    return true
  end }))
  core:rule("AQUA_RING", status({ selfOnly = true, run = function(A, u)
    local v = A:vol(u)
    if v.aquaRing then return false end
    v.aquaRing = true
    say(A, "%s surrounded itself with a veil of water!", A:name(u))
    return true
  end }))
  core:rule("SALT_CURE", hit({ secondary = function(A, u, t)
    local v = A:vol(t)
    if not v.saltCure then
      v.saltCure = true
      say(A, "%s is being salt cured!", A:name(t))
    end end }))

  -- ------------------------------------------------------------------ trapping
  local function trap(target, text)
    return function(A, u, t)
      local v = A:vol(t)
      if v.trapped then return false end
      v.trapped, v.trappedBy = true, u
      if text then say(A, text, A:name(t)) end
      return true
    end
  end
  core:effect("MEAN_LOOK", status({ aimed = true, run = trap(nil, "%s can no longer escape!") }))
  for _, name in ipairs({ "SPIRIT_SHACKLE", "ANCHOR_SHOT", "THOUSAND_WAVES" }) do
    core:rule(name, hit({ secondary = function(A, u, t) trap(nil, "%s can no longer escape!")(A, u, t) end }))
  end
  core:rule("JAW_LOCK", hit({ secondary = function(A, u, t)
    if not A:vol(t).trapped then
      A:vol(t).trapped, A:vol(u).trapped = true, true
      say(A, "Neither Pokemon can run away!")
    end end }))
  core:rule("OCTOLOCK", status({ aimed = true, run = function(A, u, t)
    if A:vol(t).octolock then return false end
    A:vol(t).octolock, A:vol(t).trapped = true, true
    say(A, "%s can no longer escape because of Octolock!", A:name(t))
    return true
  end }))

  -- ------------------------------------------------------------------ later, or at a faint
  core:effect("FUTURE_SIGHT", function(row)
    return status({ selfOnly = true, run = function(A, u, t)
      local s = A:side(t)
      if s.future then return false end
      local m = A:moveDef(row.id) or { power = 120 }
      s.future = { turn = A:turn() + 2, user = u, move = row.id, power = row.id == "DOOM_DESIRE" and 140 or 120,
        level = A:level(u), atk = A:stat(u, "spAtk") }
      say(A, row.id == "DOOM_DESIRE" and "%s chose Doom Desire as its destiny!" or "%s foresaw an attack!", A:name(u))
      return true
    end })
  end)
  core:effect("YAWN", status({ aimed = true, run = function(A, u, t)
    local v = A:vol(t)
    if v.yawn or A:status(t) then return false end
    v.yawn = A:turn() + 1
    say(A, "%s made %s drowsy!", A:name(u), A:name(t))
    return true
  end }))
  core:effect("PERISH_SONG", status({ selfOnly = true, run = function(A, u, t)
    local any = false
    for _, b in ipairs({ u, t }) do
      local v = A:vol(b)
      if not v.perish then v.perish = 3; any = true end
    end
    if any then say(A, "All Pokemon that heard the song will faint in three turns!") end
    return any
  end }))
  core:effect("NIGHTMARE", status({ aimed = true, run = function(A, u, t)
    if A:status(t) ~= "SLP" or A:vol(t).nightmare then return false end
    A:vol(t).nightmare = true
    say(A, "%s began having a nightmare!", A:name(t))
    return true
  end }))
  core:effect("CURSE", status({ run = function(A, u, t)
    if A:hasType(u, "GHOST") then
      if A:vol(t).cursed then return false end
      A:damage(u, math.max(1, math.floor(A:maxHp(u) / 2)))
      A:vol(t).cursed = true
      say(A, "%s cut its own HP and put a curse on %s!", A:name(u), A:name(t))
      return true
    end
    return A:stages(u, { speed = -1, attack = 1, defense = 1 })
  end }))
  core:effect("DESTINY_BOND", status({ selfOnly = true, run = function(A, u)
    A:vol(u).destinyBond = A:turn()
    say(A, "%s is hoping to take its attacker down with it!", A:name(u))
    return true
  end }))
  core:effect("GRUDGE", status({ selfOnly = true, run = function(A, u)
    A:vol(u).grudge = A:turn()
    say(A, "%s wants its target to bear a grudge!", A:name(u))
    return true
  end }))
  core:on("fainted", function(A, ev)
    local b = ev.battler
    if not b then return end
    local v = A:vol(b)
    local foe = A:foe(b)
    if v.tookFrom ~= A:sideName(foe) or not foe or A:hp(foe) <= 0 then return end
    if v.destinyBond and v.destinyBond >= A:turn() - 1 then
      say(A, "%s took its attacker down with it!", A:name(b))
      A:damage(foe, A:hp(foe))
    end
    if v.grudge and v.grudge >= A:turn() - 1 then
      local last = A:vol(foe).lastMove
      for _, mv in ipairs(A:moves(foe)) do
        if mv.id == last then
          mv.pp = 0
          say(A, "%s's %s lost all its PP due to the grudge!", A:name(foe), last)
        end
      end
    end
  end)
  core:effect("UPROAR", hit({ after = function(A, u)
    if not A:field().uproar then
      A:field().uproar = 3
      say(A, "%s caused an uproar!", A:name(u))
    end end }))
  core:on("blockStatus", function(A, b, s)
    if s == "SLP" and A:field().uproar then return A:text("But the uproar kept %s awake!", A:name(b)) end
  end)

  -- ------------------------------------------------------------------ calls, copies, sleep moves
  core:effect("ASSIST", status({ selfOnly = true, run = function(A, u, t)
    local pool = {}
    local me = A:mon(u)
    for _, mon in ipairs(A:party(u)) do
      if mon ~= me then
        for _, mv in ipairs(mon.moves or {}) do
          if mv.id and mv.id ~= "ASSIST" then pool[#pool + 1] = mv.id end
        end
      end
    end
    if #pool == 0 then return false end
    A:callMove(u, t, pool[A:rng(#pool) + 1])
    return true
  end }))
  core:move("ME_FIRST", status({ selfOnly = true, run = function(A, u, t)
    if Track.movedThisTurn(A, t) then return false end
    local id = A:chosen(t)
    local m = id and A:moveDef(id)
    if not m or (m.power or 0) == 0 or id == "ME_FIRST" then return false end
    A:vol(u).meFirst = A:turn()
    A:callMove(u, t, id)
    return true
  end }))
  core:on("damageMult", function(k, A, u)
    if A:vol(u).meFirst == A:turn() then k = k * 1.5 end
    return k
  end)
  core:effect("SKETCH", status({ aimed = true, run = function(A, u, t)
    local last = A:vol(t).lastMove or (A.gen == 1 and t.lastMove)
    if not last or last == "SKETCH" or last == "STRUGGLE" then return false end
    for _, list in ipairs({ A:moves(u), A:mon(u).moves or {} }) do
      for _, mv in ipairs(list) do
        if mv.id == "SKETCH" then
          local m = A:moveDef(last)
          mv.id, mv.pp, mv.maxPp = last, m and m.pp or 10, m and m.pp or 10
          break
        end
      end
    end
    say(A, "%s sketched %s!", A:name(u), last)
    return true
  end }))
  -- Red: Sleep Talk and Snore while asleep (Gold runs its own)
  core:on("sleepMove", function(A, u, id) if id == "SLEEP_TALK" or id == "SNORE" then return true end end)
  core:effect("SLEEP_TALK", status({ selfOnly = true, run = function(A, u, t)
    if A:status(u) ~= "SLP" then return false end
    local pool = {}
    for _, mv in ipairs(A:moves(u)) do
      if mv.id ~= "SLEEP_TALK" and mv.id ~= "ASSIST" then pool[#pool + 1] = mv.id end
    end
    if #pool == 0 then return false end
    A:callMove(u, t, pool[A:rng(#pool) + 1])
    return true
  end }))
  core:effect("SNORE", hit({
    fail = function(A, u) return A:status(u) ~= "SLP" end,
    secondary = function(A, u, t) if A:chance(30) then A:flinch(t) end end,
  }))

  -- ------------------------------------------------------------------ geomancy and the vanishing moves
  core:rule("GEOMANCY", status({ selfOnly = true, charge = { text = "%s is absorbing power!" },
    run = function(A, u) return A:stages(u, { spAtk = 2, spDef = 2, speed = 2 }) end }))
  for _, name in ipairs({ "PHANTOM_FORCE", "SHADOW_FORCE" }) do
    core:rule(name, hit({ sureHit = false, ignoresProtect = true,
      charge = { text = "%s vanished instantly!", vanish = true },
      fail = function(A, u, t)
        local v = A:vol(t)
        if v.protect == A:turn() or (A.gen == 2 and A.battle:volatile(t).protect) then
          v.protect = nil
          if A.gen == 2 then A.battle:volatile(t).protect = nil end
        end
        return false
      end }))
  end
  core:rule("HYPERSPACE_HOLE", hit({ sureHit = true, ignoresProtect = true, fail = function(A, u, t)
    A:vol(t).protect = nil
    if A.gen == 2 then A.battle:volatile(t).protect = nil end
    return false
  end }))

  -- ------------------------------------------------------------------ breaking the screens
  core:effect("BRICK_BREAK", function(row)
    return hit({ fail = function(A, u, t)
      local broke = false
      if A.gen == 1 then
        if t.reflect or t.lightScreen then t.reflect, t.lightScreen = nil, nil; broke = true end
      else
        local sc = A.battle.screens and A.battle.screens[A:sideName(t)]
        if sc and ((sc.reflect or 0) > 0 or (sc.lightScreen or 0) > 0) then
          sc.reflect, sc.lightScreen = 0, 0
          broke = true
        end
      end
      if (A:side(t).auroraVeil or 0) > 0 then A:side(t).auroraVeil = nil; broke = true end
      if broke then say(A, "It shattered the barrier!") end
      return false
    end, type = row.id == "RAGING_BULL" and function(A, u)
      local ts = A:types(u)
      return (ts[1] == "FIGHTING" or ts[1] == "FIRE" or ts[1] == "WATER") and ts[1] or nil
    end or nil })
  end)

  -- ------------------------------------------------------------------ the end of the turn
  core:on("endTurn", function(A)
    local turn = A:turn()
    for _, b in ipairs({ A:battlers() }) do
      if b and A:hp(b) > 0 then
        local v, s = A:vol(b), A:side(b)
        local max = A:maxHp(b)
        -- a Future Sight aimed at this side
        local f = s.future
        if f and f.turn <= turn then
          s.future = nil
          say(A, "%s took the %s attack!", A:name(b), f.move == "DOOM_DESIRE" and "Doom Desire" or "Future Sight")
          local def = math.max(1, A:stat(b, "spDef"))
          local d = math.floor(math.floor(math.floor(2 * f.level / 5 + 2) * f.power * f.atk / def) / 50) + 2
          A:damage(b, math.max(1, d))
        end
        -- a Wish
        local w = s.wish
        if w and w.turn <= turn and A:hp(b) > 0 then
          s.wish = nil
          if A:hp(b) < max then A:heal(b, w.amount, { text = A:text("%s's wish came true!", w.name) }) end
        end
        if A:hp(b) > 0 then
          if v.ingrain and A:hp(b) < max then
            A:heal(b, math.max(1, math.floor(max / 16)), { text = A:text("%s absorbed nutrients with its roots!", A:name(b)) })
          end
          if v.aquaRing and A:hp(b) < max then
            A:heal(b, math.max(1, math.floor(max / 16)), { text = A:text("A veil of water restored %s's HP!", A:name(b)) })
          end
          if v.saltCure then
            local d = (A:hasType(b, "WATER") or A:hasType(b, "STEEL")) and 4 or 8
            A:damage(b, math.max(1, math.floor(max / d)), { text = A:text("%s is hurt by Salt Cure!", A:name(b)) })
          end
          if v.nightmare and A:status(b) == "SLP" and A:hp(b) > 0 then
            A:damage(b, math.max(1, math.floor(max / 4)), { text = A:text("%s is locked in a nightmare!", A:name(b)) })
          end
          if v.cursed and A:hp(b) > 0 then
            A:damage(b, math.max(1, math.floor(max / 4)), { text = A:text("%s is afflicted by the curse!", A:name(b)) })
          end
          if v.octolock and A:hp(b) > 0 then A:stages(b, { defense = -1, spDef = -1 }, { from = A:foe(b) }) end
          if v.yawn and v.yawn <= turn then
            v.yawn = nil
            if not A:status(b) then A:ailment(b, "SLEEP", {}) end
          end
          if v.perish then
            v.perish = v.perish - 1
            say(A, "%s's perish count fell to %d!", A:name(b), v.perish)
            if v.perish <= 0 then A:damage(b, A:hp(b)) end
          end
        end
      end
    end
    local f = A:field()
    for _, key in ipairs({ "mudSport", "waterSport", "uproar" }) do
      if f[key] then
        f[key] = f[key] - 1
        if f[key] <= 0 then f[key] = nil end
      end
    end
  end)
end
