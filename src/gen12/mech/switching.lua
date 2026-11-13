-- Switching on Gen 1 / Gen 2: the moves that switch the user out (U-turn, Volt Switch, Flip Turn,
-- Parting Shot, Shed Tail, Chilly Reception, Baton Pass on Red) or drag the target out (Dragon Tail,
-- Circle Throw), the ones that act on whoever comes in next (Healing Wish, Lunar Dance) or bring a
-- fainted Pokemon back (Revival Blessing), and what stops a switch (Mean Look and the trapping
-- moves, Ingrain, No Retreat, Fairy Lock).
--
-- The one who comes in is the first healthy Pokemon in the party (the target of Dragon Tail: a
-- random one), as Gold's own Baton Pass picks here; a wild Pokemon has no party to switch to.
-- A Pokemon dragged in before its side moved does not act that turn.

return function(core)
  local Track = core.track
  local function status(t) t.kind = "status"; return t end
  local function hit(t) t.kind = "hit"; return t end
  local function say(A, fmt, ...) A:say(A:text(fmt, ...)) end

  -- a side whose Pokemon was replaced before it moved loses that move
  local function skipIfPending(A, b)
    if not Track.movedThisTurn(A, b) then
      A:side(b).skipTurn = A:turn()
      if A.gen == 2 then
        local bt = A.battle
        bt.moveRulePursuitSpent = bt.moveRulePursuitSpent or {}
        bt.moveRulePursuitSpent[A:sideName(b)] = bt.turn
      end
    end
  end
  core:on("beforeMove", function(A, u, t, m, isCalled)
    local s = A:side(u)
    if s.skipTurn == A:turn() and not isCalled then
      s.skipTurn = nil
      return ""
    end
  end)

  local function pivot(A, u)
    if A:hp(u) <= 0 or not A:replacement(u) then return false end
    return A:switchOut(u)
  end
  for _, name in ipairs({ "U_TURN", "VOLT_SWITCH", "FLIP_TURN" }) do
    core:rule(name, hit({ after = function(A, u, t, m, dealt) if dealt > 0 then pivot(A, u) end end }))
  end
  core:rule("PARTING_SHOT", status({ aimed = true, run = function(A, u, t)
    if not A:stages(t, { attack = -1, spAtk = -1 }, { from = u }) then return nil end
    pivot(A, u)
    return true
  end }))
  core:rule("SHED_TAIL", status({ selfOnly = true, run = function(A, u)
    local cost = math.ceil(A:maxHp(u) / 2)
    if A:hp(u) <= cost or not A:replacement(u) then return false end
    A:damage(u, cost)
    say(A, "%s shed its tail to create a decoy!", A:name(u))
    A:side(u).shedTail = math.floor(A:maxHp(u) / 4)
    return A:switchOut(u)
  end }))
  core:rule("CHILLY_RECEPTION", status({ selfOnly = true, run = function(A, u)
    say(A, "%s is preparing to tell a chillingly bad joke!", A:name(u))
    if A:weather() ~= "snow" then A:setWeather("snow", 5, A:text("It started to snow!")) end
    pivot(A, u)
    return true
  end }))
  -- Red: Baton Pass (Gold runs its own)
  core:effect("BATON_PASS", status({ selfOnly = true, run = function(A, u)
    if not A:replacement(u) then return false end
    say(A, "%s passed the baton!", A:name(u))
    return A:switchOut(u, { carry = true })
  end }))
  local function drag(A, u, t)
    if A:hp(t) <= 0 or not A:replacement(t, true) or A:vol(t).ingrain then return end
    -- Suction Cups, Guard Dog
    if core.hooks.noForceSwitch and core:ask("noForceSwitch", A, t) then return end
    skipIfPending(A, t)
    A:switchOut(t, { random = true })
  end
  for _, name in ipairs({ "DRAGON_TAIL", "CIRCLE_THROW" }) do
    core:rule(name, hit({ secondary = function(A, u, t) drag(A, u, t) end }))
  end
  -- Red: Pursuit hits as an ordinary move (Gold runs its own)
  core:effect("PURSUIT", hit({}))

  -- whoever comes in next
  local function wish(field, text)
    return status({ selfOnly = true, run = function(A, u)
      if not A:replacement(u) then return false end
      A:side(u)[field] = true
      A:damage(u, A:hp(u))
      return true
    end })
  end
  core:rule("HEALING_WISH", wish("healingWish"))
  core:rule("LUNAR_DANCE", wish("lunarDance"))
  core:on("switchedIn", function(A, ev)
    local b = ev.battler
    if not b then return end
    local s = A:side(b)
    if (s.healingWish or s.lunarDance) and A:hp(b) > 0 then
      local lunar = s.lunarDance
      s.healingWish, s.lunarDance = nil, nil
      A:heal(b, A:maxHp(b))
      A:cure(b)
      if lunar then
        for _, mv in ipairs(A:moves(b)) do
          local d = A:moveDef(mv.id)
          mv.pp = mv.maxPp or (d and d.pp) or mv.pp
        end
      end
      say(A, lunar and "%s became cloaked in mystical moonlight!" or "The healing wish came true for %s!", A:name(b))
    end
    if s.shedTail and A:hp(b) > 0 then
      local hp = s.shedTail
      s.shedTail = nil
      if A.gen == 1 then b.substituteHP = hp else A.battle:volatile(b).substitute = hp end
    end
  end)
  core:rule("REVIVAL_BLESSING", status({ selfOnly = true, run = function(A, u)
    for _, mon in ipairs(A:party(u)) do
      if type(mon) == "table" and (mon.hp or 0) <= 0 and not mon.isEgg then
        local max = (mon.maxHp or (mon.stats and mon.stats.hp)) or 1
        mon.hp = math.max(1, math.floor(max / 2))
        mon.status = nil
        say(A, "%s was revived and is ready to fight again!", mon.nickname or mon.name or mon.species)
        return true
      end
    end
    return false
  end }))

  -- what keeps a Pokemon in
  core:rule("FAIRY_LOCK", status({ selfOnly = true, run = function(A)
    A:field().fairyLock = A:turn() + 1
    say(A, "No one will be able to run away during the next turn!")
    return true
  end }))
  core:on("trapped", function(A, b)
    local v = A:vol(b)
    if A:hasType(b, "GHOST") then return nil end
    if v.trapped or v.ingrain then return A:text("%s can't escape!", A:name(b)) end
    local fl = A:field().fairyLock
    if fl and fl >= A:turn() then return A:text("%s can't escape!", A:name(b)) end
  end)
end
