-- Held items in battle on Gen 1 / Gen 2, and the moves that use them.
--
-- Red: the held items of data/gen12/held.lua (src/gen12/held_red.lua gives them) do what they do on
-- Gold: berries, Leftovers, King's Rock, Quick Claw, BrightPowder, Scope Lens, Focus Band, the
-- type boosters, the species items, the Berserk Gene, Everstone, the Smoke Ball, the Amulet Coin
-- and the Lucky Egg. Gold runs its own.
--
-- Both: Knock Off, Thief and Covet (Red), Trick, Switcheroo, Bestow, Recycle, Belch, Bug Bite,
-- Pluck, Incinerate, Fling, Natural Gift, Stuff Cheeks, Teatime. A Pokemon's item knocked off is
-- given back to the player's Pokemon after the battle; one stolen or swapped stays where it went.

return function(core, opts)
  local gen = opts.generation
  local function hit(t) t.kind = "hit"; return t end
  local function status(t) t.kind = "status"; return t end
  local function say(A, fmt, ...) A:say(A:text(fmt, ...)) end

  local held = {}
  core.heldItems = held
  for _, row in ipairs(opts.load and opts.load("data/gen12/held.lua") or {}) do held[row.id] = row end
  local function isBerry(id) return id ~= nil and tostring(id):find("BERRY") ~= nil end
  core.isBerry = isBerry

  -- the item, unless Magic Room or Embargo keeps it quiet
  local function itemOf(A, b)
    if A:field().magicRoom then return nil end
    return A:item(b)
  end
  local function eat(A, b)
    local id = A:item(b)
    if not id then return nil end
    A:setItem(b, nil)
    local v = A:vol(b)
    v.consumed = id
    if isBerry(id) then v.ateBerry = true end
    return id
  end

  -- ------------------------------------------------------------------ Red's held items
  if gen == 1 then
    local function row(A, b) local id = itemOf(A, b); return id and held[id], id end
    local CURES = { PAR = "PAR", SLP = "SLP", BRN = "BRN", FRZ = "FRZ", PSN = "PSN" }
    local function tryBerry(A, b)
      local r, id = row(A, b)
      if not r or A:hp(b) <= 0 then return end
      if r.effect == "heal" and A:hp(b) * 2 <= A:maxHp(b) then
        eat(A, b)
        A:heal(b, r.param, { text = A:text("%s restored its HP using its %s!", A:name(b), A:itemName(id)) })
      elseif r.effect == "cure" then
        local s = A:status(b)
        local want = r.param
        local hit = (want == "ALL" and (s or b.confusedTurns)) or (want == "CONFUSION" and b.confusedTurns)
          or (CURES[want] and (s == want or (want == "PSN" and s == "TOX")))
        if hit then
          eat(A, b)
          if want == "CONFUSION" or want == "ALL" then b.confusedTurns = nil end
          if want ~= "CONFUSION" then A:cure(b) end
          say(A, "%s used its %s!", A:name(b), A:itemName(id))
        end
      end
    end
    core:on("damageDealt", function(A, ev) if ev.target then tryBerry(A, ev.target) end end)
    core:on("statusInflicted", function(A, ev) if ev.target then tryBerry(A, ev.target) end end)
    core:on("endTurn", function(A)
      for _, b in ipairs({ A:battlers() }) do
        if b and A:hp(b) > 0 then
          local r, id = row(A, b)
          if r and r.effect == "leftovers" and A:hp(b) < A:maxHp(b) then
            A:heal(b, math.max(1, math.floor(A:maxHp(b) / 16)),
              { text = A:text("%s restored a little HP using its %s!", A:name(b), A:itemName(id)) })
          end
          tryBerry(A, b)
        end
      end
    end)
    -- a move run out of PP: the Mystery Berry
    core:on("moveUsed", function(A, ev)
      local u = ev.user
      local r = u and row(A, u)
      if not (r and r.effect == "pp") then return end
      for _, mv in ipairs(A:moves(u)) do
        if (mv.pp or 1) == 0 then
          local id = eat(A, u)
          mv.pp = r.param
          say(A, "%s restored PP using its %s!", A:name(u), A:itemName(id))
          return
        end
      end
    end)
    core:on("damageMult", function(k, A, u, t, m)
      local r = row(A, u)
      if r and r.effect == "boost" and A:moveType(m) == r.type then k = k * (100 + r.param) / 100 end
      if r and r.effect == "species" then
        local sp = A:species(u)
        for _, s in ipairs(r.species) do
          if s == sp and (r.stat == "attack" and A:category(m) == "physical"
              or r.stat == "spAtk" and A:category(m) == "special") then k = k * 2 end
        end
      end
      local rt = row(A, t)
      if rt and rt.effect == "species" and rt.stat == "defense" then
        for _, s in ipairs(rt.species) do if s == A:species(t) then k = k * 2 / 3 end end
      end
      return k
    end)
    core:on("forceCrit", function(A, b)
      local r = row(A, b)
      if not r then return nil end
      if r.effect == "crit" and A:rng(8) == 0 then return true end
      if r.effect == "species" and r.stat == "crit" then
        for _, s in ipairs(r.species) do if s == A:species(b) and A:rng(4) == 0 then return true end end
      end
    end)
    core:on("accuracy", function(A, u, t)
      local r = t and row(A, t)
      if r and r.effect == "evasion" and A:rng(256) < r.param then return false end
    end)
    core:on("damageCap", function(A, u, t, m, dmg)
      local r = row(A, t)
      if r and r.effect == "focusBand" and dmg >= A:hp(t) and A:hp(t) > 1 and A:rng(256) < r.param then
        say(A, "%s hung on using its %s!", A:name(t), A:itemName(A:item(t)))
        return A:hp(t) - 1
      end
    end)
    core:on("damageDealt", function(A, ev)
      local u, t = ev.user, ev.target
      local r = u and row(A, u)
      if r and r.effect == "flinch" and t and A:hp(t) > 0 and A:rng(256) < r.param then A:flinch(t) end
    end)
    core:on("speed", function(s, A, b)
      local r = row(A, b)
      if r and r.effect == "quickClaw" and A:rng(256) < r.param then return s * 1000 end
      return s
    end)
    core:on("switchedIn", function(A, ev)
      local b = ev.battler
      local r = b and row(A, b)
      if r and r.effect == "berserk" then
        eat(A, b)
        A:stages(b, { attack = 2 })
        A:confuse(b, {})
      end
    end)
  end

  -- ------------------------------------------------------------------ the moves that use items
  -- Knock Off: 1.5x against an item, which goes (given back to the player's Pokemon after)
  core:effect("KNOCK_OFF", function(row)
    return hit({
      power = function(A, u, t, m) return A:item(t) and math.floor((m.power or 65) * 3 / 2) or m.power end,
      secondary = function(A, u, t)
        local id = A:item(t)
        if not id then return end
        A:setItem(t, nil)
        if A:sideName(t) == "player" then
          local f = A:field()
          f.knocked = f.knocked or {}
          f.knocked[#f.knocked + 1] = { mon = A:mon(t), item = id }
        end
        say(A, "%s knocked off %s's %s!", A:name(u), A:name(t), A:itemName(id))
      end,
    })
  end)
  core:on("battleEnded", function(A)
    for _, k in ipairs(A:field().knocked or {}) do
      if k.mon then
        if A.gen == 1 then
          k.mon.extra = k.mon.extra or {}
          k.mon.extra.national_dex_gen3 = k.mon.extra.national_dex_gen3 or {}
          k.mon.extra.national_dex_gen3.item = k.mon.extra.national_dex_gen3.item or k.item
        else
          k.mon.item = k.mon.item or k.item
        end
      end
    end
    A:field().knocked = nil
  end)
  -- Red: Thief and Covet steal (Gold runs its own Thief)
  core:effect("THIEF", hit({ secondary = function(A, u, t)
    local id = A:item(t)
    if id and not A:item(u) then
      A:setItem(t, nil)
      A:setItem(u, id)
      say(A, "%s stole %s's %s!", A:name(u), A:name(t), A:itemName(id))
    end end }))
  -- swap items (Trick, Switcheroo)
  core:effect("TRICK", status({ aimed = true, run = function(A, u, t)
    local a, b = A:item(u), A:item(t)
    if not a and not b then return false end
    A:setItem(u, b)
    A:setItem(t, a)
    say(A, "%s switched items with its target!", A:name(u))
    return true
  end }))
  core:move("BESTOW", status({ aimed = true, run = function(A, u, t)
    local id = A:item(u)
    if not id or A:item(t) then return false end
    A:setItem(u, nil)
    A:setItem(t, id)
    say(A, "%s received %s from %s!", A:name(t), A:itemName(id), A:name(u))
    return true
  end }))
  core:effect("RECYCLE", status({ selfOnly = true, run = function(A, u)
    local v = A:vol(u)
    if not v.consumed or A:item(u) then return false end
    A:setItem(u, v.consumed)
    say(A, "%s found one %s!", A:name(u), A:itemName(v.consumed))
    v.consumed = nil
    return true
  end }))
  core:rule("BELCH", hit({ fail = function(A, u) return not A:vol(u).ateBerry end }))
  -- eat the target's berry (Bug Bite, Pluck), burn it (Incinerate)
  local function stealBerry(burn)
    return hit({ secondary = function(A, u, t)
      local id = A:item(t)
      if not isBerry(id) then return end
      A:setItem(t, nil)
      if burn then
        say(A, "%s's %s was burned up!", A:name(t), A:itemName(id))
      else
        say(A, "%s stole and ate its target's %s!", A:name(u), A:itemName(id))
        local r = held[id]
        if r and r.effect == "heal" then A:heal(u, r.param) end
        A:vol(u).ateBerry = true
      end
    end })
  end
  core:rule("BUG_BITE", stealBerry(false))
  core:rule("PLUCK", stealBerry(false))
  core:rule("INCINERATE", stealBerry(true))
  -- throws the item: berries 10, the rest 30 (Gen 9's common power), and it is gone
  core:rule("FLING", hit({
    fail = function(A, u) return A:item(u) == nil end,
    power = function(A, u) return isBerry(A:item(u)) and 10 or 30 end,
    after = function(A, u)
      local id = eat(A, u)
      if id then say(A, "%s flung its %s!", A:name(u), A:itemName(id)) end
    end,
  }))
  core:rule("NATURAL_GIFT", hit({
    fail = function(A, u) return not isBerry(A:item(u)) end,
    power = function() return 80 end,
    after = function(A, u) eat(A, u) end,
  }))
  local function eatOwn(A, b, extra)
    local id = A:item(b)
    if not isBerry(id) then return false end
    eat(A, b)
    say(A, "%s ate its %s!", A:name(b), A:itemName(id))
    local r = held[id]
    if r and r.effect == "heal" then A:heal(b, r.param) end
    if extra then extra() end
    return true
  end
  core:rule("STUFF_CHEEKS", status({ selfOnly = true, run = function(A, u)
    return eatOwn(A, u, function() A:stages(u, { defense = 2 }) end)
  end }))
  core:move("TEATIME", status({ selfOnly = true, run = function(A)
    local any = false
    for _, b in ipairs({ A:battlers() }) do
      if b and eatOwn(A, b) then any = true end
    end
    return any
  end }))
end
