-- Move field: newer moves that keep state on the battlefield or change who is on it
-- (data/moves.lua `rule`, set by hand in tools/build_moves.py MANUAL). Gen 3 has no entry
-- hazards but Spikes, no terrains, no Tailwind or Trick Room and no move that switches the user
-- out after hitting; this module keeps that state on the engine's own battle tables
-- (`side.__ndx`, `st.__ndxField`) and drives it through the seams the engine exposes:
--
--   * Effects.run          the status moves (Stealth Rock, Tailwind, Trick Room, the terrains ...)
--   * Hit.run              after a hit: U-turn's switch, Dragon Tail's drag, Steel Roller
--   * Engine.switchInEffects   entry hazards, before the cart's Spikes
--   * Damage.calc          the terrain boosts; Terrain Pulse / Rising Voltage / Expanding Force
--   * Residuals            the turn counters (a field phase of our own, a battler phase of the
--                          cart's) and Aqua Ring / Grassy Terrain healing
--   * RealAbilities.effectiveSpeed / reverseSpeed   Tailwind and Trick Room in the turn order
--   * Adapter canApplyStatus   Misty / Electric Terrain's status guards
--   * Engine.performSwitch + switchCandidates + the "baton_pass" choice (the party prompt)
-- Every step runs protected: an error leaves the move as the plain hit or "nothing happened".

local MoveField = {}

MoveField._rules = {}                             -- move number -> rule name (install fills it)
MoveField._on = false

local ID = { NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4, ROCK = 5, BUG = 6,
             GHOST = 7, STEEL = 8, MYSTERY = 9, FIRE = 10, WATER = 11, GRASS = 12, ELECTRIC = 13,
             PSYCHIC = 14, ICE = 15, DRAGON = 16, DARK = 17, FAIRY = 18 }

local TERRAIN = {
  MISTY_TERRAIN = { kind = "MISTY", type = ID.FAIRY,
    start = "Mist swirled around\nthe battlefield!", stop = "The mist disappeared\nfrom the battlefield." },
  GRASSY_TERRAIN = { kind = "GRASSY", type = ID.GRASS,
    start = "Grass grew to cover\nthe battlefield!", stop = "The grass disappeared\nfrom the battlefield." },
  ELECTRIC_TERRAIN = { kind = "ELECTRIC", type = ID.ELECTRIC,
    start = "An electric current ran\nacross the battlefield!", stop = "The electricity disappeared\nfrom the battlefield." },
  PSYCHIC_TERRAIN = { kind = "PSYCHIC", type = ID.PSYCHIC,
    start = "The battlefield\ngot weird!", stop = "The weirdness disappeared\nfrom the battlefield!" },
}
local TERRAIN_BY_KIND = {}
for _, t in pairs(TERRAIN) do TERRAIN_BY_KIND[t.kind] = t end

local SWITCH_OUT = { U_TURN = true, VOLT_SWITCH = true, FLIP_TURN = true }
local DRAG_OUT = { DRAGON_TAIL = true, CIRCLE_THROW = true }

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

local function prefixed(ad, b)
  local ok, State = pcall(require, "src.core.game3.battle.state")
  if ok and State.prefixedName then
    local okN, n = pcall(State.prefixedName, ad._st, b)
    if okN and n then return n end
  end
  return ad:displayName(b)
end

local function teamName(ad, side)
  -- "your team" / "the foe's team"
  return side == ad._st.playerSide and "your team" or "the foe's team"
end

local function field(st)
  st.__ndxField = st.__ndxField or {}
  return st.__ndxField
end

local function sideData(side)
  side.__ndx = side.__ndx or {}
  return side.__ndx
end

local function terrainOf(st)
  local f = st and st.__ndxField
  return f and (f.terrainTurns or 0) > 0 and f.terrain or nil
end
MoveField.terrainOf = terrainOf

local function hasType(ad, b, t)
  local ok, r = pcall(ad.hasType, ad, b, t)
  return ok and r or false
end

-- on the ground: terrains, Toxic Spikes and Sticky Web only touch grounded Pokemon
local function grounded(ad, b)
  if not (ad and b) then return false end
  if b.__ndxGrounded then return true end
  local st = ad._st
  if st and st.__ndxField and (st.__ndxField.gravity or 0) > 0 then return true end
  if b.semiInvulnerable == "ON_AIR" or b.__ndxMagnetRise then return false end
  if hasType(ad, b, ID.FLYING) or abilityOf(ad, b) == "LEVITATE" then return false end
  return true
end
MoveField.grounded = grounded

local function fail(ad, M)
  if M then M.failed = true end
  ad:sayFail()
end

-- ---------------------------------------------------------------- switching

-- The replacement for a battler that leaves by its own move (U-turn): the cart's Baton Pass
-- choice, which opens the party menu for the player (effects/special.lua batonPass).
local function switchOut(ad, st, b, M, reason)
  local okE, Engine = pcall(require, "src.core.game3.battle.engine")
  if not okE then return nil end
  local who = st.double and b.id or b.side
  local candidates = Engine.switchCandidates(st, who)
  if #candidates == 0 then return nil end
  local pick
  if type(st.batonPassChooser) == "function" then
    local ok, v = pcall(st.batonPassChooser, b.side, candidates)
    if ok then pick = tonumber(v) end
  elseif (st.link or b.side == "player") and st.interactiveChoices and coroutine.running() then
    pick = tonumber(coroutine.yield({ kind = "baton_pass", side = b.side, battler = b.id, candidates = candidates }))
  elseif b.side == "enemy" then
    pick = Engine.mostSuitableMon(st, ad, st.double and b.id or "enemy")
  end
  local slot = candidates[1]
  for _, c in ipairs(candidates) do
    if c == pick then slot = pick end
  end
  local nb = Engine.performSwitch(st, ad, who, slot, { reason = reason })
  if nb then
    if M then M.user = nb end
    local okS, SwitchSeq = pcall(require, "src.core.game3.battle.switch_seq")
    local okT, BattleText = pcall(require, "src.core.game3.battle.battle_text")
    if okS and okT then
      local fill = SwitchSeq.switchInFill(st, nb)
      local text = BattleText.get(BattleText.SWITCHINMON, fill)
      ad:pushEvent({ kind = "msg", text = text, wait = 0, id = (BattleText.key(BattleText.SWITCHINMON, fill)) })
      ad._say(text)
    end
    Engine.switchInEffects(st, ad, nb, { spikes = true, deferIntimidate = true })
  end
  return nb
end

-- Dragon Tail: the target is dragged out (a wild battle ends, as with Roar)
local function dragOut(ad, st, M)
  local target = M.target
  if not (M.targetDamaged and not M.noEffect and not M.failed) then return end
  if ad:hp(target) <= 0 or M.hitSubstitute or ad:hp(M.user) <= 0 then return end
  if abilityOf(ad, target) == "SUCTION_CUPS" or target.expIngrain then return end
  local okE, Engine = pcall(require, "src.core.game3.battle.engine")
  if not okE then return end
  if st.wild then
    ad:pushEvent({ kind = "switch_out", side = target.side, reason = "roar" })
    st.over = true
    st.result = "run"
    st.endReason = "dragon_tail"
    ad:pushEvent({ kind = "end", result = "run", reason = "dragon_tail" })
    return
  end
  local who = st.double and target.id or target.side
  local candidates = Engine.switchCandidates(st, who)
  if #candidates == 0 then return end
  local slot = candidates[ad:roll(1, #candidates)]
  local nb = Engine.performSwitch(st, ad, who, slot, { reason = "roar" })
  if nb then
    M.target = nb
    ad:sayText("STRINGID_PKMNWASDRAGGEDOUT", { def = nb })
    Engine.switchInEffects(st, ad, nb, { spikes = true, deferIntimidate = true })
  end
end

-- ---------------------------------------------------------------- hazards

-- what a Pokemon entering runs into, before the cart's own Spikes; true if it fainted
local function entryHazards(st, ad, b)
  local side = ad:ownSide(b)
  local d = side and side.__ndx
  if not d then return false end
  local okS, Secondary = pcall(require, "src.core.game3.battle.effects.secondary")
  if d.stealthRock then
    local okT, Types = pcall(require, "src.core.game3.battle.types")
    local eff = 1
    if okT and Types.typeCalc then
      local _, _, e = Types.typeCalc(ID.ROCK, b.type1, b.type2, nil, true)
      eff = tonumber(e) or 1
    end
    local dmg = math.max(1, math.floor(ad:maxHp(b) * eff / 8))
    ad:applyHpLoss(b, dmg)
    ad:say("Pointed stones dug into\n" .. prefixed(ad, b) .. "!")
    if ad:isFainted(b) then return true end
  end
  if (d.toxicSpikes or 0) > 0 and grounded(ad, b) then
    if hasType(ad, b, ID.POISON) then
      d.toxicSpikes = nil
      ad:say("The poison spikes disappeared\nfrom around " .. prefixed(ad, b) .. "'s feet!")
    elseif not hasType(ad, b, ID.STEEL) and not ad:status(b) then
      local status = d.toxicSpikes >= 2 and "TOX" or "PSN"
      if ad:applyStatus(b, status, nil, { ignoreSafeguard = true }) then
        ad:sayText(status == "TOX" and "STRINGID_PKMNBADLYPOISONED" or "STRINGID_PKMNWASPOISONED", { def = b })
      end
    end
  end
  if d.stickyWeb and grounded(ad, b) and okS then
    ad:say(prefixed(ad, b) .. " was caught\nin a sticky web!")
    Secondary.changeStat(ad, b, "speed", -1, { allowPtr = true })
  end
  return false
end

-- ---------------------------------------------------------------- status moves

local function statusRule(rule, ad, user, target, M)
  local st = ad._st
  local f = field(st)
  local own, foe = ad:ownSide(user), ad:foeSide(user)
  local okS, Secondary = pcall(require, "src.core.game3.battle.effects.secondary")
  local function anim() if M and M.attackAnimation then M:attackAnimation() end end
  local function accuracy()
    if M and M.accuracyCheck then return M:accuracyCheck("normal", true) end
    return true
  end

  if rule == "STEALTH_ROCK" then
    local d = sideData(foe)
    if d.stealthRock then return fail(ad, M) end
    anim()
    d.stealthRock = true
    ad:say("Pointed stones float in the air\naround " .. teamName(ad, foe) .. "!")
  elseif rule == "TOXIC_SPIKES" then
    local d = sideData(foe)
    if (d.toxicSpikes or 0) >= 2 then return fail(ad, M) end
    anim()
    d.toxicSpikes = (d.toxicSpikes or 0) + 1
    ad:say("Poison spikes were scattered\naround " .. teamName(ad, foe) .. "'s feet!")
  elseif rule == "STICKY_WEB" then
    local d = sideData(foe)
    if d.stickyWeb then return fail(ad, M) end
    anim()
    d.stickyWeb = true
    ad:say("A sticky web spreads out\nunder " .. teamName(ad, foe) .. "'s feet!")
  elseif rule == "DEFOG" then
    if not accuracy() then return end
    anim()
    local okH, Hazards = pcall(require, "src.core.game3.battle.effects.hazards")
    for _, side in ipairs({ own, foe }) do
      if side then
        side.__ndx = side.__ndx and { tailwind = side.__ndx.tailwind } or nil
        if okH then Hazards.clear(side) end
      end
    end
    if foe then
      foe.expReflectTurns, foe.expLightScreenTurns = nil, nil
      foe.expSafeguardTurns, foe.expMistTurns = nil, nil
    end
    if (f.terrainTurns or 0) > 0 then
      ad:say(TERRAIN_BY_KIND[f.terrain].stop)
      f.terrain, f.terrainTurns = nil, nil
    end
    if okS and target and target ~= user then Secondary.changeStat(ad, target, "evasion", -1, { allowPtr = true }) end
  elseif rule == "TAILWIND" then
    local d = sideData(own)
    if (d.tailwind or 0) > 0 then return fail(ad, M) end
    anim()
    d.tailwind = 4
    ad:say("The tailwind blew from\nbehind " .. teamName(ad, own) .. "!")
  elseif rule == "TRICK_ROOM" then
    anim()
    if (f.trickRoom or 0) > 0 then
      f.trickRoom = nil
      ad:say(prefixed(ad, user) .. " returned the\ntwisted dimensions to normal!")
    else
      f.trickRoom = 5
      ad:say(prefixed(ad, user) .. " twisted\nthe dimensions!")
    end
  elseif TERRAIN[rule] then
    local t = TERRAIN[rule]
    if terrainOf(st) == t.kind then return fail(ad, M) end
    anim()
    f.terrain, f.terrainTurns = t.kind, 5
    ad:say(t.start)
  elseif rule == "AQUA_RING" then
    if user.__ndxAquaRing then return fail(ad, M) end
    anim()
    user.__ndxAquaRing = true
    ad:say(prefixed(ad, user) .. " surrounded itself\nwith a veil of water!")
  elseif rule == "PARTING_SHOT" then
    if not target or target == user or not accuracy() then return end
    anim()
    local any = false
    if okS and (target.substituteHP or 0) <= 0 then
      for _, stat in ipairs({ "attack", "spAtk" }) do
        if Secondary.changeStat(ad, target, stat, -1, { allowPtr = true }) == "worked" then any = true end
      end
    end
    if any then switchOut(ad, st, user, M, "parting_shot") else fail(ad, M) end
  else
    return false
  end
  return true
end

-- ---------------------------------------------------------------- residuals

local function tickField(ad)
  local st = ad._st
  for _, side in ipairs({ st.playerSide, st.enemySide }) do
    local d = side and side.__ndx
    if d and (d.tailwind or 0) > 0 then
      d.tailwind = d.tailwind - 1
      if d.tailwind <= 0 then
        d.tailwind = nil
        ad:say(teamName(ad, side):gsub("^%l", string.upper) .. "'s tailwind\npetered out!")
      end
    end
  end
  local f = st.__ndxField
  if not f then return end
  if (f.trickRoom or 0) > 0 then
    f.trickRoom = f.trickRoom - 1
    if f.trickRoom <= 0 then
      f.trickRoom = nil
      ad:say("The twisted dimensions\nreturned to normal!")
    end
  end
  if (f.terrainTurns or 0) > 0 then
    f.terrainTurns = f.terrainTurns - 1
    if f.terrainTurns <= 0 then
      ad:say(TERRAIN_BY_KIND[f.terrain].stop)
      f.terrain, f.terrainTurns = nil, nil
    end
  end
end

local function tickBattler(ad, b)
  if not b or ad:hp(b) <= 0 then return end
  local maxHp, cur = ad:maxHp(b), ad:hp(b)
  if b.__ndxAquaRing and cur < maxHp then
    ad:playAnim("general", "INGRAIN_HEAL", b, b)
    ad:say("A veil of water restored\n" .. prefixed(ad, b) .. "'s HP!")
    ad:heal(b, math.max(1, math.floor(maxHp / 16)))
  end
  if terrainOf(ad._st) == "GRASSY" and grounded(ad, b) and ad:hp(b) < maxHp then
    ad:say(prefixed(ad, b) .. " is healed\nby the grassy terrain!")
    ad:heal(b, math.max(1, math.floor(maxHp / 16)))
  end
end

-- ---------------------------------------------------------------- install

-- Nothing here needs to be subscribed at load: the turn order goes through
-- RealAbilities' hook, and the events are read live.
function MoveField.hooks(mod) end

-- opts: { moves = src/moves.lua's registered rows, require, log, abilities = RealAbilities }
function MoveField.install(opts)
  local require, log = opts.require, opts.log
  local rules = {}
  for _, r in ipairs(opts.moves or {}) do
    if type(r.rule) == "string" and tonumber(r.index) then rules[tonumber(r.index)] = r.rule end
  end
  MoveField._rules = rules

  local okD, Damage = pcall(require, "src.core.game3.battle.damage")
  local okH, Hit = pcall(require, "src.core.game3.battle.effects.hit")
  local okE, Effects = pcall(require, "src.core.game3.battle.effects")
  local okEn, Engine = pcall(require, "src.core.game3.battle.engine")
  local okR, Residuals = pcall(require, "src.core.game3.battle.residuals")
  local okRu, Rules = pcall(require, "src.core.game3.battle.rules")
  local okA, Adapter = pcall(require, "src.core.game3.battle.adapter")
  if not (okD and okH and okE and okEn and type(Damage.calc) == "function" and type(Hit.run) == "function"
      and type(Effects.run) == "function" and type(Engine.switchInEffects) == "function") then
    if log then log:warn("field moves are off: the battle engine's functions were not found") end
    return false
  end

  -- status moves
  if not Effects.__nationalDexMoveField then
    Effects.__nationalDexMoveField = true
    local run = Effects.run
    Effects.run = function(id, ad, user, target, move, moveId, moveCtx, ...)
      local num = tonumber(moveCtx and moveCtx.mnum) or tonumber(moveId)
      local rule = num and MoveField._on and MoveField._rules[num]
      if not (rule and id == "NATIONAL_DEX_GEN3_MOVE_EFFECT") then
        return run(id, ad, user, target, move, moveId, moveCtx, ...)
      end
      local ok, handled = pcall(statusRule, rule, ad, user, target, moveCtx)
      if ok and handled ~= false then return true end
      return run(id, ad, user, target, move, moveId, moveCtx, ...)
    end
  end

  -- attacks: Psychic Terrain's priority block before, switching / dragging / terrain-ending after
  if not Hit.__nationalDexMoveField then
    Hit.__nationalDexMoveField = true
    local hitRun = Hit.run
    Hit.run = function(M, ...)
      if not (MoveField._on and type(M) == "table" and M.adapter and M.user and M.target) then return hitRun(M, ...) end
      local ad, st = M.adapter, M.st
      local rule = MoveField._rules[tonumber(M.mnum) or -1]
      local okP, blocked = pcall(function()
        if terrainOf(st) == "PSYCHIC" and M.target ~= M.user and grounded(ad, M.target)
            and (tonumber(M.move and M.move.priority) or 0) > 0 then
          return "priority"
        end
        if rule == "STEEL_ROLLER" and not terrainOf(st) then return "fail" end
        return nil
      end)
      if okP and blocked then
        M:attackString()
        M:ppReduce()
        M.failed = true
        if M.anim then M.anim.missed = true end
        if blocked == "priority" then
          ad:say(prefixed(ad, M.target) .. " is protected by\nthe psychic terrain!")
        else
          ad:sayFail()
        end
        return
      end
      local r = hitRun(M, ...)
      if rule then
        pcall(function()
          if SWITCH_OUT[rule] then
            if M.targetDamaged and not M.noEffect and not M.failed and ad:hp(M.user) > 0 and not (st and st.over) then
              switchOut(ad, st, M.user, M, "u_turn")
            end
          elseif DRAG_OUT[rule] then
            dragOut(ad, st, M)
          elseif (rule == "STEEL_ROLLER" or rule == "ICE_SPINNER") and M.targetDamaged and not M.noEffect then
            local f = st and st.__ndxField
            if f and (f.terrainTurns or 0) > 0 then
              ad:say(TERRAIN_BY_KIND[f.terrain].stop)
              f.terrain, f.terrainTurns = nil, nil
            end
          end
        end)
      end
      return r
    end
  end

  -- entry hazards, before the cart's Spikes
  if not Engine.__nationalDexMoveField then
    Engine.__nationalDexMoveField = true
    local switchIn = Engine.switchInEffects
    Engine.switchInEffects = function(st, ad, b, o, ...)
      if MoveField._on and o and o.spikes and b and ad and not (st and st.over) then
        local ok, fainted = pcall(entryHazards, st, ad, b)
        if ok and fainted then
          local okP, BattleProfile = pcall(require, "src.core.game3.battle.profile")
          local sequencing = okP and BattleProfile.rule and BattleProfile.rule(st, "sequencingPolicy")
          if sequencing and sequencing.spikesFaint then sequencing.spikesFaint(ad, b) end
          return true
        end
      end
      return switchIn(st, ad, b, o, ...)
    end
  end

  -- Rapid Spin (the cart's) sweeps our hazards away with its Spikes
  local okHz, Hazards = pcall(require, "src.core.game3.battle.effects.hazards")
  if okHz and type(Hazards.clear) == "function" and not Hazards.__nationalDexMoveField then
    Hazards.__nationalDexMoveField = true
    local clear = Hazards.clear
    Hazards.clear = function(side, ...)
      if type(side) == "table" and side.__ndx then
        side.__ndx.stealthRock, side.__ndx.toxicSpikes, side.__ndx.stickyWeb = nil, nil, nil
      end
      return clear(side, ...)
    end
  end

  -- the terrain boosts (and Terrain Pulse / Rising Voltage / Expanding Force)
  if not Damage.__nationalDexMoveField then
    Damage.__nationalDexMoveField = true
    local calc = Damage.calc
    Damage.calc = function(attacker, defender, moveId, o, ...)
      local st = o and o.adapter and o.adapter._st
      local kind = MoveField._on and terrainOf(st)
      if not (kind and type(attacker) == "table" and type(defender) == "table") then
        return calc(attacker, defender, moveId, o, ...)
      end
      local ad = o.adapter
      local num = type(moveId) == "table" and (tonumber(moveId.numId) or tonumber(moveId.id)) or tonumber(moveId)
      local rule = num and MoveField._rules[num]
      local o2 = {}
      for k, v in pairs(o) do o2[k] = v end
      local mult = 1
      local okP = pcall(function()
        local t = TERRAIN_BY_KIND[kind]
        local move = type(moveId) == "table" and moveId or {}
        if rule == "TERRAIN_PULSE" and grounded(ad, attacker) then
          o2.moveType, o2.power = t.type, 100
        end
        local mtype = tonumber(o2.moveType) or tonumber(move.type)
        if grounded(ad, attacker) and mtype == t.type and kind ~= "MISTY" then mult = mult * 1.3 end
        if kind == "MISTY" and mtype == ID.DRAGON and grounded(ad, defender) then mult = mult * 0.5 end
        if rule == "RISING_VOLTAGE" and kind == "ELECTRIC" and grounded(ad, defender) then mult = mult * 2 end
        if rule == "EXPANDING_FORCE" and kind == "PSYCHIC" and grounded(ad, attacker) then mult = mult * 1.5 end
      end)
      if not okP then return calc(attacker, defender, moveId, o, ...) end
      local dmg, info = calc(attacker, defender, moveId, o2, ...)
      if mult ~= 1 and (tonumber(dmg) or 0) > 0 then dmg = math.max(1, math.floor(dmg * mult)) end
      return dmg, info
    end
  end

  -- Misty Terrain: no status on grounded Pokemon; Electric Terrain: no sleep
  if okA and type(Adapter.new) == "function" and not Adapter.__nationalDexMoveField then
    Adapter.__nationalDexMoveField = true
    local new = Adapter.new
    Adapter.new = function(...)
      local a = new(...)
      if type(a) == "table" and type(a.canApplyStatus) == "function" then
        local can = a.canApplyStatus
        a.canApplyStatus = function(self, b, status, ...)
          if MoveField._on and b then
            local kind = terrainOf(self._st)
            if kind and grounded(self, b) then
              local s = tostring(status or ""):upper()
              if kind == "MISTY" then return false, "terrain" end
              if kind == "ELECTRIC" and (s == "SLP" or s == "SLEEP") then return false, "terrain" end
            end
          end
          return can(self, b, status, ...)
        end
      end
      return a
    end
  end

  -- the turn counters and the healing
  if okR and okRu and type(Residuals.register) == "function" and not Rules.__nationalDexMoveField then
    Rules.__nationalDexMoveField = true
    local at = #Rules.FIELD_PHASES_ORDER
    for i, name in ipairs(Rules.FIELD_PHASES_ORDER) do
      if name == "weather_continue" then at = i - 1 end
    end
    table.insert(Rules.FIELD_PHASES_ORDER, at + 1, "ndx_field")
    Residuals.register("ndx_field", function(ctx)
      if MoveField._on and ctx and ctx.adapter then pcall(tickField, ctx.adapter) end
    end)
    Residuals.register("ingrain", function(ctx)
      if MoveField._on and ctx and ctx.adapter then pcall(tickBattler, ctx.adapter, ctx.target) end
    end)
  end

  -- Tailwind and Trick Room in the turn order, through the abilities' hook
  local RA = opts.abilities
  if type(RA) == "table" and type(RA.speedModifiers) == "table" then
    RA.speedModifiers.tailwind = function(ad, b)
      local side = ad and ad:ownSide(b)
      local d = side and side.__ndx
      return (MoveField._on and d and (d.tailwind or 0) > 0) and 2 or 1
    end
    RA.reverseSpeed = function(st)
      local f = MoveField._on and st and st.__ndxField
      return f and (f.trickRoom or 0) > 0 or false
    end
  elseif log then
    log:warn("Tailwind and Trick Room do not change the turn order: the real abilities are off")
  end

  MoveField._on = true
  local n = 0
  for _ in pairs(rules) do n = n + 1 end
  if log then log:info("field moves: %d moves", n) end
  return true
end

return MoveField
