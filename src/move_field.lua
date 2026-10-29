-- Move field: newer moves that keep state on the battlefield or change who is on it
-- (data/moves.lua `rule`, set by hand in tools/build_moves.py MANUAL). Gen 3 has no entry
-- hazards but Spikes, no terrains, no Tailwind or Trick Room, no protection that punishes, no
-- move that switches the user out after hitting; this module keeps that state on the engine's
-- own battle tables (`side.__ndx`, `st.__ndxField`, `battler.__ndx*`; never on the party mon,
-- which is saved) and drives it through the seams the engine exposes:
--
--   * Effects.run          the status moves (Stealth Rock, Tailwind, King's Shield, Gravity ...)
--   * Hit.run              before a hit: Psychic Terrain's priority block, Wide / Quick Guard, a
--                          vanished target, Powder, Pollen Puff on an ally, Feint; after it:
--                          U-turn's switch, Dragon Tail's drag, trapping, Smack Down, the
--                          punishment a protection variant deals, Mortal Spin ...
--   * Engine.switchInEffects   entry hazards and Healing Wish, before the cart's Spikes
--   * Damage.calc          the terrain boosts, Aurora Veil, Wonder Room, Magnet Rise, Thousand Arrows
--   * Residuals            the turn counters (a field phase of our own, a battler phase of the
--                          cart's), Aqua Ring / Grassy Terrain healing, Salt Cure, Octolock
--   * RealAbilities.effectiveSpeed / reverseSpeed   Tailwind and Trick Room in the turn order
--   * Adapter              canApplyStatus (Misty / Electric Terrain), heal (Heal Block),
--                          abilityOf (Levitate while grounded)
--   * Engine.canSwitch / canRun (Fairy Lock), HeldItems.of (Magic Room), Hazards.clear
--     (Rapid Spin), Abilities.soundproofBlocks + Commands.selectionError + Engine.moveLimitations
--     (Throat Chop), the battle.accuracy (Gravity) and battle.crit (Lucky Chant) hooks
--   * Engine.performSwitch + switchCandidates + the "baton_pass" choice (the party prompt)
-- Every step runs protected: an error leaves the move as the plain hit or "nothing happened".

local MoveField = {}

MoveField._rules = {}                             -- move number -> rule name (install fills it)
MoveField._on = false
MoveField._sound = {}                             -- move number -> true (Throat Chop)

-- sound moves (Pokemon Showdown's flag), the cart's and ours, by engine id
local SOUND_NAMES = { "ALLURING_VOICE", "BOOMBURST", "BUG_BUZZ", "CHATTER", "CLANGING_SCALES",
  "CLANGOROUS_SOUL", "CONFIDE", "DISARMING_VOICE", "ECHOED_VOICE", "EERIE_SPELL", "GRASSWHISTLE",
  "GROWL", "HEAL_BELL", "HOWL", "HYPER_VOICE", "METAL_SOUND", "NOBLE_ROAR", "OVERDRIVE",
  "PARTING_SHOT", "PERISH_SONG", "PSYCHIC_NOISE", "RELIC_SONG", "ROAR", "ROUND", "SCREECH", "SING",
  "SNARL", "SNORE", "SPARKLING_ARIA", "SUPERSONIC", "TORCH_SONG", "UPROAR" }

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
local PROTECT = { SPIKY_SHIELD = true, KINGS_SHIELD = true, BANEFUL_BUNKER = true, OBSTRUCT = true,
                  SILK_TRAP = true, BURNING_BULWARK = true }
local VANISH = { PHANTOM_FORCE = true, SHADOW_FORCE = true }
local TRAP = { JAW_LOCK = true, THOUSAND_WAVES = true, SPIRIT_SHACKLE = true, ANCHOR_SHOT = true }
local HEALING_WISH = { HEALING_WISH = true, LUNAR_DANCE = true }
-- the cart's field counters a "room"/field move ticks in our phase: key -> ended message
local FIELD_TIMERS = {
  trickRoom = "The twisted dimensions\nreturned to normal!",
  gravity = "Gravity returned\nto normal!",
  wonderRoom = "Wonder Room wore off, and\nDEFENSE and SP. DEF stats\nreturned to normal!",
  magicRoom = "Magic Room wore off, and\nheld items' effects returned\nto normal!",
}
local SIDE_TIMERS = {
  tailwind = "'s tailwind\npetered out!",
  auroraVeil = "'s AURORA VEIL\nwore off!",
  luckyChant = "'s LUCKY CHANT\nwore off!",
}

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

local function fieldOn(st, key)
  local f = st and st.__ndxField
  return f and (f[key] or 0) > 0
end

local function hasType(ad, b, t)
  local ok, r = pcall(ad.hasType, ad, b, t)
  return ok and r or false
end

local function contact(move)
  return (tonumber(move and move.flags) or 0) % 2 == 1
end

-- on the ground: terrains, Toxic Spikes and Sticky Web only touch grounded Pokemon
local function grounded(ad, b)
  if not (ad and b) then return false end
  if b.__ndxGrounded then return true end
  if fieldOn(ad._st, "gravity") then return true end
  if b.semiInvulnerable == "ON_AIR" or (b.__ndxMagnetRise or 0) > 0 then return false end
  if hasType(ad, b, ID.FLYING) or abilityOf(ad, b) == "LEVITATE" then return false end
  return true
end
MoveField.grounded = grounded

local function fail(ad, M)
  if M then M.failed = true end
  ad:sayFail()
end

local function secondary()
  local ok, S = pcall(require, "src.core.game3.battle.effects.secondary")
  return ok and S or nil
end

local function changeStat(ad, b, stat, delta, flags)
  local S = secondary()
  return S and S.changeStat(ad, b, stat, delta, flags or {}) or "blocked"
end

local function trap(b, by)
  b.expTrapped, b.escapePrevention, b.expTrappedBy = true, true, by
end

local function partnerOf(ad, b)
  local ok, p = pcall(ad.partnerOf, ad, b)
  if ok and p and p ~= b and ad:hp(p) > 0 then return p end
  return nil
end

-- ---------------------------------------------------------------- switching

-- The replacement for a battler that leaves by its own move (U-turn): the cart's Baton Pass
-- choice, which opens the party menu for the player (effects/special.lua batonPass).
local function switchOut(ad, st, b, M, reason, keep)
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
  local sub = b.substituteHP
  local nb = Engine.performSwitch(st, ad, who, slot, { reason = reason })
  if nb then
    if keep == "substitute" and (sub or 0) > 0 then nb.substituteHP = sub end
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

-- ---------------------------------------------------------------- hazards and entry

-- what a Pokemon entering runs into, before the cart's own Spikes; true if it fainted
local function entryHazards(st, ad, b)
  local side = ad:ownSide(b)
  local d = side and side.__ndx
  if not d then return false end
  if d.healingWish then
    d.healingWish = nil
    if ad:hp(b) < ad:maxHp(b) or ad:status(b) then
      ad:heal(b, ad:maxHp(b))
      ad:clearStatus(b)
      ad:say("The healing wish came true\nfor " .. prefixed(ad, b) .. "!")
    end
  end
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
  if d.stickyWeb and grounded(ad, b) then
    ad:say(prefixed(ad, b) .. " was caught\nin a sticky web!")
    changeStat(ad, b, "speed", -1, { allowPtr = true })
  end
  return false
end

local function clearHazards(side)
  if side and side.__ndx then
    side.__ndx.stealthRock, side.__ndx.toxicSpikes, side.__ndx.stickyWeb = nil, nil, nil
  end
end

local function endTerrain(ad, f)
  if f and (f.terrainTurns or 0) > 0 then
    ad:say(TERRAIN_BY_KIND[f.terrain].stop)
    f.terrain, f.terrainTurns = nil, nil
  end
end

-- ---------------------------------------------------------------- protection

-- Protect's chance of working again (effects/volatiles.lua protect_like), on a stamp of our
-- own since the engine resets its streak for any move number it doesn't know
local function protectWorks(ad, st, user)
  local streak = (user.__ndxProtectTurn == (st.turn or 0) - 1) and (user.__ndxProtectStreak or 0) or 0
  local ok = user.expTurnOrder ~= (st.double and 4 or 2)
  if ok and streak > 0 then ok = ad:roll(0, 2 ^ math.min(streak, 3) - 1) == 0 end
  if not ok then
    user.__ndxProtectStreak = 0
    return false
  end
  user.__ndxProtectTurn, user.__ndxProtectStreak = st.turn, streak + 1
  return true
end

-- the protection variants' answer to a blocked contact move
local function punish(ad, st, M)
  local target, user = M.target, M.user
  if not (target and target.__ndxProtectTurn == st.turn and target.__ndxProtectKind) then return end
  local kind = target.__ndxProtectKind
  if ad:hp(user) <= 0 then return end
  if kind == "SPIKY_SHIELD" and contact(M.move) then
    ad:applyHpLoss(user, math.max(1, math.floor(ad:maxHp(user) / 8)))
    ad:say(prefixed(ad, user) .. " was hurt\nby the spiky shield!")
    if M.tryFaintUser then M:tryFaintUser() end
  elseif kind == "KINGS_SHIELD" and contact(M.move) then
    changeStat(ad, user, "attack", -1, { allowPtr = true })
  elseif kind == "OBSTRUCT" and contact(M.move) then
    changeStat(ad, user, "defense", -2, { allowPtr = true })
  elseif kind == "SILK_TRAP" and contact(M.move) then
    changeStat(ad, user, "speed", -1, { allowPtr = true })
  elseif kind == "BANEFUL_BUNKER" and contact(M.move) then
    if ad:applyStatus(user, "PSN", target) then ad:sayText("STRINGID_PKMNWASPOISONED", { def = user }) end
  elseif kind == "BURNING_BULWARK" and contact(M.move) then
    if ad:applyStatus(user, "BRN", target) then ad:sayText("STRINGID_PKMNWASBURNED", { def = user }) end
  end
end

-- ---------------------------------------------------------------- status moves

local function statusRule(rule, ad, user, target, M)
  local st = ad._st
  local f = field(st)
  local own, foe = ad:ownSide(user), ad:foeSide(user)
  local function anim() if M and M.attackAnimation then M:attackAnimation() end end
  local function accuracy(mode)
    if M and M.accuracyCheck then return M:accuracyCheck(mode or "normal", true) end
    return true
  end
  local function sideTimer(side, key, turns, startMsg)
    local d = sideData(side)
    if (d[key] or 0) > 0 then return fail(ad, M) end
    anim()
    d[key] = turns
    ad:say(startMsg)
  end
  local function fieldTimer(key, turns, startMsg)
    anim()
    if (f[key] or 0) > 0 then
      f[key] = nil
      ad:say(FIELD_TIMERS[key])
    else
      f[key] = turns
      ad:say(startMsg)
    end
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
      clearHazards(side)
      if okH and side then Hazards.clear(side) end
    end
    if foe then
      foe.expReflectTurns, foe.expLightScreenTurns = nil, nil
      foe.expSafeguardTurns, foe.expMistTurns = nil, nil
      if foe.__ndx then foe.__ndx.auroraVeil = nil end
    end
    endTerrain(ad, f)
    if target and target ~= user then changeStat(ad, target, "evasion", -1, { allowPtr = true }) end
  elseif rule == "TAILWIND" then
    sideTimer(own, "tailwind", 4, "The tailwind blew from\nbehind " .. teamName(ad, own) .. "!")
  elseif rule == "AURORA_VEIL" then
    local okR, Rules = pcall(require, "src.core.game3.battle.rules")
    local okW, w = pcall(function() return Rules.weather.effective(st, ad) end)
    if not (okR and okW and w == "HAIL") then return fail(ad, M) end
    sideTimer(own, "auroraVeil", 5, "AURORA VEIL made " .. teamName(ad, own) .. "\nstronger against attacks!")
  elseif rule == "LUCKY_CHANT" then
    sideTimer(own, "luckyChant", 5, "The LUCKY CHANT shielded " .. teamName(ad, own) .. "\nfrom critical hits!")
  elseif rule == "WIDE_GUARD" or rule == "QUICK_GUARD" or rule == "CRAFTY_SHIELD" then
    local d = sideData(own)
    local key = rule == "WIDE_GUARD" and "wideGuard" or rule == "QUICK_GUARD" and "quickGuard" or "craftyShield"
    if d[key] == st.turn then return fail(ad, M) end
    anim()
    d[key] = st.turn
    ad:say((rule == "CRAFTY_SHIELD" and "CRAFTY SHIELD" or rule == "WIDE_GUARD" and "WIDE GUARD" or "QUICK GUARD")
      .. " protected\n" .. teamName(ad, own) .. "!")
  elseif rule == "TRICK_ROOM" then
    fieldTimer("trickRoom", 5, prefixed(ad, user) .. " twisted\nthe dimensions!")
  elseif rule == "GRAVITY" then
    if (f.gravity or 0) > 0 then return fail(ad, M) end
    anim()
    f.gravity = 5
    ad:say("Gravity intensified!")
    for _, b in ipairs(ad:activeBattlers()) do
      if b.semiInvulnerable == "ON_AIR" then
        local okE, Engine = pcall(require, "src.core.game3.battle.engine")
        if okE and Engine.cancelMultiTurnMoves then Engine.cancelMultiTurnMoves(b) end
        ad:say(prefixed(ad, b) .. " fell from the sky\ndue to the gravity!")
      end
    end
  elseif rule == "WONDER_ROOM" then
    fieldTimer("wonderRoom", 5, "It created a bizarre area in which\nDEFENSE and SP. DEF stats are swapped!")
  elseif rule == "MAGIC_ROOM" then
    fieldTimer("magicRoom", 5, "It created a bizarre area in which\nPOKeMON's held items lose their effects!")
  elseif rule == "FAIRY_LOCK" then
    anim()
    f.fairyLock = (st.turn or 0) + 1
    ad:say("No one will be able to run away\nduring the next turn!")
  elseif rule == "COURT_CHANGE" then
    anim()
    local okH, Hazards = pcall(require, "src.core.game3.battle.effects.hazards")
    local a, b = st.playerSide, st.enemySide
    a.__ndx, b.__ndx = b.__ndx, a.__ndx
    if okH then
      local la, lb = Hazards.layers(a), Hazards.layers(b)
      Hazards.set(a, lb)
      Hazards.set(b, la)
    end
    for _, k in ipairs({ "expReflectTurns", "expLightScreenTurns", "expSafeguardTurns", "expMistTurns" }) do
      a[k], b[k] = b[k], a[k]
    end
    ad:say(prefixed(ad, user) .. " swapped the battle\neffects affecting each side!")
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
  elseif rule == "MAGNET_RISE" then
    if (user.__ndxMagnetRise or 0) > 0 or user.expIngrain or fieldOn(st, "gravity") then return fail(ad, M) end
    anim()
    user.__ndxMagnetRise = 5
    ad:say(prefixed(ad, user) .. " levitated\nwith electromagnetism!")
  elseif PROTECT[rule] then
    if not protectWorks(ad, st, user) then return fail(ad, M) end
    anim()
    user.expProtected = true
    user.__ndxProtectKind = rule
    ad:sayText("STRINGID_PKMNPROTECTEDITSELF2", { atk = user })
  elseif rule == "GEOMANCY" then
    if user.__ndxGeomancy then
      user.__ndxGeomancy = nil
      if M and M.slot and user.mon and user.mon.pp and user.mon.pp[M.slot] then
        user.mon.pp[M.slot] = user.mon.pp[M.slot] + 1          -- the charge turn paid the PP
      end
      anim()
      local S = secondary()
      if S then
        S.multiStatAnim(ad, user, { "spAtk", "spDef", "speed" }, 2)
        for _, stat in ipairs({ "spAtk", "spDef", "speed" }) do
          S.changeStat(ad, user, stat, 2, { user = true, certain = true, noAnim = true })
        end
      end
    else
      user.__ndxGeomancy = true
      user.twoTurnMove, user.twoTurnTarget = M and M.moveId, target
      user.expLockedMove, user.expLockedSlot = M and M.moveId, M and M.slot
      ad:say(prefixed(ad, user) .. " is absorbing power!")
    end
  elseif rule == "PARTING_SHOT" then
    if not target or target == user or not accuracy() then return end
    anim()
    local any = false
    if (target.substituteHP or 0) <= 0 then
      for _, stat in ipairs({ "attack", "spAtk" }) do
        if changeStat(ad, target, stat, -1, { allowPtr = true }) == "worked" then any = true end
      end
    end
    if any then switchOut(ad, st, user, M, "parting_shot") else fail(ad, M) end
  elseif HEALING_WISH[rule] then
    local okE, Engine = pcall(require, "src.core.game3.battle.engine")
    if not (okE and #Engine.switchCandidates(st, st.double and user.id or user.side) > 0) then return fail(ad, M) end
    anim()
    sideData(own).healingWish = true
    ad:setHp(user, 0)
    if M then M.checkUserFaint = true; if M.tryFaintUser then M:tryFaintUser() end end
  elseif rule == "SHED_TAIL" then
    local okE, Engine = pcall(require, "src.core.game3.battle.engine")
    if not (okE and #Engine.switchCandidates(st, st.double and user.id or user.side) > 0) then return fail(ad, M) end
    local okF, Effects = pcall(require, "src.core.game3.battle.effects")
    if okF then Effects.run("EXP_SUBSTITUTE_EFFECT", ad, user, target, M and M.move, M and M.moveId, M) end
    if (user.substituteHP or 0) > 0 and not (M and M.failed) then switchOut(ad, st, user, M, "shed_tail", "substitute") end
  elseif rule == "CHILLY_RECEPTION" then
    local okE, Engine = pcall(require, "src.core.game3.battle.engine")
    if not (okE and #Engine.switchCandidates(st, st.double and user.id or user.side) > 0) then return fail(ad, M) end
    anim()
    ad:say(prefixed(ad, user) .. " is preparing\nto tell a chillingly bad joke!")
    ad:setWeather("HAIL", 5)
    ad:sayText("STRINGID_STARTEDHAIL")
    switchOut(ad, st, user, M, "chilly_reception")
  elseif rule == "REVIVAL_BLESSING" then
    local party = user.side == "player" and st.playerParty or st.foeParty
    local mon
    for _, m in ipairs(party or {}) do
      if m and not m.isEgg and (tonumber(m.hp) or 0) <= 0 and (tonumber(m.maxHp) or 0) > 0 then mon = m break end
    end
    if not mon then return fail(ad, M) end
    anim()
    mon.hp = math.max(1, math.floor(mon.maxHp / 2))
    mon.status = nil
    local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
    local name = okP and Pokemon.nickname and Pokemon.nickname(mon) or mon.nickname or "The POKeMON"
    ad:say(tostring(name) .. " was revived\nand is ready to fight again!")
  elseif rule == "PURIFY" then
    if not target or target == user or not ad:status(target) then return fail(ad, M) end
    if not accuracy() then return end
    anim()
    ad:clearStatus(target)
    ad:say(prefixed(ad, target) .. "'s status\nreturned to normal!")
    if ad:hp(user) < ad:maxHp(user) then
      ad:heal(user, math.max(1, math.floor(ad:maxHp(user) / 2)))
      ad:sayText("STRINGID_PKMNREGAINEDHEALTH", { def = user })
    end
  elseif rule == "JUNGLE_HEALING" then
    local did = false
    for _, b in ipairs({ user, partnerOf(ad, user) }) do
      if b and (ad:hp(b) < ad:maxHp(b) or ad:status(b)) then
        if not did then anim() end
        did = true
        ad:heal(b, math.max(1, math.floor(ad:maxHp(b) / 4)))
        ad:clearStatus(b)
        ad:sayText("STRINGID_PKMNREGAINEDHEALTH", { def = b })
      end
    end
    if not did then fail(ad, M) end
  elseif rule == "OCTOLOCK" then
    if not target or target == user or not accuracy() then return end
    if target.expTrapped or target.escapePrevention or (target.substituteHP or 0) > 0 then return fail(ad, M) end
    anim()
    trap(target, user)
    target.__ndxOctolock = user
    ad:sayText("STRINGID_TARGETCANTESCAPENOW", { def = target })
  elseif rule == "HEAL_BLOCK" then
    if not target or target == user or not accuracy() then return end
    if (target.__ndxHealBlock or 0) > 0 then return fail(ad, M) end
    anim()
    target.__ndxHealBlock = 5
    ad:say(prefixed(ad, target) .. " was prevented\nfrom healing!")
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
    if d then
      for key, msg in pairs(SIDE_TIMERS) do
        if (d[key] or 0) > 0 then
          d[key] = d[key] - 1
          if d[key] <= 0 then
            d[key] = nil
            ad:say(teamName(ad, side):gsub("^%l", string.upper) .. msg)
          end
        end
      end
    end
  end
  local f = st.__ndxField
  if not f then return end
  for key, msg in pairs(FIELD_TIMERS) do
    if (f[key] or 0) > 0 then
      f[key] = f[key] - 1
      if f[key] <= 0 then
        f[key] = nil
        ad:say(msg)
      end
    end
  end
  if (f.terrainTurns or 0) > 0 then
    f.terrainTurns = f.terrainTurns - 1
    if f.terrainTurns <= 0 then endTerrain(ad, f) end
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
  if b.__ndxSaltCure and abilityOf(ad, b) ~= "MAGIC_GUARD" then
    local div = (hasType(ad, b, ID.WATER) or hasType(ad, b, ID.STEEL)) and 4 or 8
    ad:applyHpLoss(b, math.max(1, math.floor(maxHp / div)))
    ad:say(prefixed(ad, b) .. " is being\nhurt by SALT CURE!")
  end
  local octo = b.__ndxOctolock
  if octo then
    if ad:hp(octo) <= 0 or octo.zeroed then
      b.__ndxOctolock = nil
    else
      changeStat(ad, b, "defense", -1, { allowPtr = true })
      changeStat(ad, b, "spDef", -1, { allowPtr = true })
    end
  end
  for _, key in ipairs({ "__ndxMagnetRise", "__ndxHealBlock", "__ndxThroatChop" }) do
    if (b[key] or 0) > 0 then
      b[key] = b[key] - 1
      if b[key] <= 0 then
        b[key] = nil
        if key == "__ndxMagnetRise" then ad:say(prefixed(ad, b) .. "'s electromagnetism\nwore off!")
        elseif key == "__ndxHealBlock" then ad:say(prefixed(ad, b) .. "'s HEAL BLOCK\nwore off!") end
      end
    end
  end
end

-- ---------------------------------------------------------------- hits

-- before the hit: the move is stopped (returns a reason) or changed
local function beforeHit(rule, ad, st, M)
  local user, target = M.user, M.target
  local f = st and st.__ndxField
  local turn = st and st.turn
  local prio = tonumber(M.move and M.move.priority) or 0
  -- the user's own state
  if user.__ndxPowder == turn and (tonumber(M.move and M.move.type) or -1) == ID.FIRE then
    ad:say("When the flame touched the powder\non " .. prefixed(ad, user) .. ", it exploded!")
    ad:applyHpLoss(user, math.max(1, math.floor(ad:maxHp(user) / 4)))
    if M.tryFaintUser then M:tryFaintUser() end
    return "fail"
  end
  if VANISH[rule] then
    if user.__ndxVanished then
      user.__ndxVanished, user.semiInvulnerable = nil, nil
      user.twoTurnMove, user.twoTurnTarget, user.expLockedMove, user.expLockedSlot = nil, nil, nil, nil
      M.noPP = true
      M.isProtected = function() return false end
    else
      user.__ndxVanished = true
      user.semiInvulnerable = "VANISHED"
      user.twoTurnMove, user.twoTurnTarget = M.moveId, target
      user.expLockedMove, user.expLockedSlot = M.moveId, M.slot
      M:attackString()
      M:ppReduce()
      ad:say(prefixed(ad, user) .. " vanished\ninstantly!")
      return "charge"
    end
  end
  if rule == "HYPERSPACE_HOLE" then M.isProtected = function() return false end end
  if rule == "SHELL_TRAP" and (tonumber(user.lastPhysicalDamageTaken) or 0) <= 0 then return "fail" end
  if not target or target == user then return nil end
  -- the target's
  if target.semiInvulnerable == "VANISHED" then return "miss" end
  if rule == "FEINT" and target.expProtected then
    target.expProtected = nil
    ad:say(prefixed(ad, target) .. " fell for\nthe feint!")
  end
  if rule == "POLLEN_PUFF" and target.side == user.side then
    M:attackString()
    M:ppReduce()
    if ad:hp(target) >= ad:maxHp(target) or (target.__ndxHealBlock or 0) > 0 then
      ad:sayText("STRINGID_PKMNHPFULL", { def = target })
    else
      M:attackAnimation()
      ad:heal(target, math.max(1, math.floor(ad:maxHp(target) / 2)))
      ad:sayText("STRINGID_PKMNREGAINEDHEALTH", { def = target })
    end
    return "done"
  end
  if terrainOf(st) == "PSYCHIC" and prio > 0 and grounded(ad, target) then return "priority" end
  local tside = ad:ownSide(target)
  local d = tside and tside.__ndx
  if d and turn then
    local tgt = tonumber(M.move and M.move.target) or 0
    if d.wideGuard == turn and (tgt == 8 or tgt == 32) then return "guard" end
    if d.quickGuard == turn and prio > 0 then return "guard" end
  end
  if rule == "STEEL_ROLLER" and not terrainOf(st) then return "fail" end
  if rule == "SPECTRAL_THIEF" and (target.substituteHP or 0) <= 0 then
    local any = false
    for _, stat in ipairs({ "attack", "defense", "spAtk", "spDef", "speed", "accuracy", "evasion" }) do
      local s = tonumber(target.stages and target.stages[stat]) or 0
      if s > 0 then
        target.stages[stat] = 0
        user.stages[stat] = math.min(6, (user.stages[stat] or 0) + s)
        any = true
      end
    end
    if any then ad:say(prefixed(ad, user) .. " stole the target's\nboosted stats!") end
  end
  return nil
end

-- after the hit landed
local function afterHit(rule, ad, st, M)
  local user, target = M.user, M.target
  local landed = M.targetDamaged and not M.noEffect and not M.failed
  local targetUp = target and ad:hp(target) > 0
  if SWITCH_OUT[rule] then
    if landed and ad:hp(user) > 0 and not (st and st.over) then switchOut(ad, st, user, M, "u_turn") end
  elseif DRAG_OUT[rule] then
    dragOut(ad, st, M)
  elseif (rule == "STEEL_ROLLER" or rule == "ICE_SPINNER") and landed then
    endTerrain(ad, st and st.__ndxField)
  elseif TRAP[rule] and landed and targetUp and not M.hitSubstitute then
    if not (target.expTrapped or target.escapePrevention) then
      trap(target, user)
      ad:sayText("STRINGID_TARGETCANTESCAPENOW", { def = target })
    end
    if rule == "JAW_LOCK" and not (user.expTrapped or user.escapePrevention) then trap(user, target) end
  elseif rule == "SALT_CURE" and landed and targetUp and not M.hitSubstitute and not target.__ndxSaltCure then
    target.__ndxSaltCure = true
    ad:say(prefixed(ad, target) .. " is being\nsalt cured!")
  elseif rule == "THROAT_CHOP" and landed and targetUp and not M.hitSubstitute then
    target.__ndxThroatChop = 2
    if not target.__ndxThroatChopSaid then
      target.__ndxThroatChopSaid = true
      ad:say("The effects of THROAT CHOP prevent\n" .. prefixed(ad, target) .. " from using sound moves!")
    end
  elseif (rule == "SMACK_DOWN" or rule == "THOUSAND_ARROWS") and landed and targetUp and not target.__ndxGrounded then
    if not grounded(ad, target) then
      target.__ndxGrounded = true
      if target.semiInvulnerable == "ON_AIR" then
        local okE, Engine = pcall(require, "src.core.game3.battle.engine")
        if okE and Engine.cancelMultiTurnMoves then Engine.cancelMultiTurnMoves(target) end
      end
      ad:say(prefixed(ad, target) .. " fell\nstraight down!")
    end
  elseif rule == "MORTAL_SPIN" and landed then
    local own = ad:ownSide(user)
    local okH, Hazards = pcall(require, "src.core.game3.battle.effects.hazards")
    clearHazards(own)
    if okH and own then Hazards.clear(own) end
    user.expTrapped, user.escapePrevention, user.expTrapTurns, user.wrapped = nil, nil, nil, nil
    user.expSeeded, user.expSeedSource = nil, nil
    if targetUp and not M.hitSubstitute and ad:applyStatus(target, "PSN", user) then
      ad:sayText("STRINGID_PKMNWASPOISONED", { def = target })
    end
  elseif rule == "CEASELESS_EDGE" and landed then
    local okH, Hazards = pcall(require, "src.core.game3.battle.effects.hazards")
    local foe = ad:foeSide(user)
    if okH and foe and Hazards.layers(foe) < 3 then
      Hazards.set(foe, Hazards.layers(foe) + 1)
      ad:sayText("STRINGID_SPIKESSCATTERED", { def = target })
    end
  elseif rule == "STONE_AXE" and landed then
    local foe = ad:foeSide(user)
    if foe and not sideData(foe).stealthRock then
      sideData(foe).stealthRock = true
      ad:say("Pointed stones float in the air\naround " .. teamName(ad, foe) .. "!")
    end
  end
end

-- ---------------------------------------------------------------- install

-- Hooks have to exist when the mod loads; they act once install() has run.
function MoveField.hooks(mod)
  local on = function() return MoveField._on end
  -- Gravity: accuracy x5/3
  mod.hooks:wrap("battle.accuracy", function(nextFn, c)
    if on() and type(c) == "table" and tonumber(c.accuracy) and fieldOn(c.battle, "gravity") then
      c.accuracy = math.floor(c.accuracy * 5 / 3)
    end
    return nextFn(c)
  end)
  -- Lucky Chant: no critical hits on that side
  mod.hooks:wrap("battle.crit", function(nextFn, c)
    if on() and type(c) == "table" and c.target then
      local ad = adapter()
      local side = ad and ad:ownSide(c.target)
      if side and side.__ndx and (side.__ndx.luckyChant or 0) > 0 then return false end
    end
    return nextFn(c)
  end)
end

-- opts: { moves = src/moves.lua's registered rows, require, log, abilities = RealAbilities }
function MoveField.install(opts)
  local require, log = opts.require, opts.log
  local rules = {}
  for _, r in ipairs(opts.moves or {}) do
    if type(r.rule) == "string" and tonumber(r.index) then rules[tonumber(r.index)] = r.rule end
  end
  MoveField._rules = rules
  MoveField._sound = {}
  do
    local okM, Moves = pcall(require, "src.core.game3.battle.moves")
    for _, name in ipairs(SOUND_NAMES) do
      local n = okM and Moves.numForName and Moves.numForName(name)
      if tonumber(n) then MoveField._sound[tonumber(n)] = true end
    end
  end

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
      if not (MoveField._on and type(user) == "table" and type(ad) == "table") then
        return run(id, ad, user, target, move, moveId, moveCtx, ...)
      end
      local st = ad._st
      local M = type(moveCtx) == "table" and moveCtx.isMoveContext and moveCtx or nil
      -- a vanished target, Crafty Shield, King's Shield (status moves pass it)
      if type(target) == "table" and target ~= user and st then
        if target.semiInvulnerable == "VANISHED" then
          if M then M.failed = true end
          ad:sayText("STRINGID_ATTACKMISSED", { atk = user })
          return true
        end
        local tside = ad:ownSide(target)
        if tside and tside.__ndx and tside.__ndx.craftyShield == st.turn and target.side ~= user.side then
          if M then M.failed = true end
          ad:sayText("STRINGID_PKMNPROTECTEDITSELF", { def = target })
          return true
        end
        if target.expProtected and target.__ndxProtectKind == "KINGS_SHIELD" and target.__ndxProtectTurn == st.turn then
          target.expProtected = nil
          local r = run(id, ad, user, target, move, moveId, moveCtx, ...)
          target.expProtected = true
          return r
        end
      end
      local num = tonumber(moveCtx and moveCtx.mnum) or tonumber(moveId)
      local rule = num and MoveField._rules[num]
      if not (rule and id == "NATIONAL_DEX_GEN3_MOVE_EFFECT") then
        return run(id, ad, user, target, move, moveId, moveCtx, ...)
      end
      local ok, handled = pcall(statusRule, rule, ad, user, target, M or moveCtx)
      if ok and handled ~= false then return true end
      return run(id, ad, user, target, move, moveId, moveCtx, ...)
    end
  end

  -- attacks
  if not Hit.__nationalDexMoveField then
    Hit.__nationalDexMoveField = true
    local hitRun = Hit.run
    Hit.run = function(M, ...)
      if not (MoveField._on and type(M) == "table" and M.adapter and M.user) then return hitRun(M, ...) end
      local ad, st = M.adapter, M.st
      local rule = MoveField._rules[tonumber(M.mnum) or -1]
      local okB, stop = pcall(beforeHit, rule, ad, st, M)
      if okB and stop then
        if stop == "charge" or stop == "done" then return end
        M:attackString()
        M:ppReduce()
        M.failed = true
        if M.anim then M.anim.missed = true end
        if stop == "priority" then
          ad:say(prefixed(ad, M.target) .. " is protected by\nthe psychic terrain!")
        elseif stop == "guard" then
          ad:sayText("STRINGID_PKMNPROTECTEDITSELF", { def = M.target })
        elseif stop == "miss" then
          M.failed = nil
          M.missReason = "miss"
          ad:sayText("STRINGID_ATTACKMISSED", { atk = M.user })
        else
          ad:sayFail()
        end
        return
      end
      local r = hitRun(M, ...)
      pcall(function()
        if M.missReason == "protected" then punish(ad, st, M) end
        if rule then afterHit(rule, ad, st, M) end
      end)
      return r
    end
  end

  -- entry hazards and Healing Wish, before the cart's Spikes
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
    -- Fairy Lock: nobody switches or runs the turn after
    local function locked(st)
      local f = MoveField._on and st and st.__ndxField
      return f and f.fairyLock and f.fairyLock == st.turn
    end
    if type(Engine.canSwitch) == "function" then
      local canSwitch = Engine.canSwitch
      Engine.canSwitch = function(st, ad, b, ...)
        if locked(st) then return false, "Can't escape!" end
        return canSwitch(st, ad, b, ...)
      end
    end
    if type(Engine.canRun) == "function" then
      local canRun = Engine.canRun
      Engine.canRun = function(st, ad, b, ...)
        if locked(st) then return false, "Can't escape!" end
        return canRun(st, ad, b, ...)
      end
    end
    -- Throat Chop: the AI's move list
    if type(Engine.moveLimitations) == "function" then
      local lim = Engine.moveLimitations
      Engine.moveLimitations = function(b, ad, ...)
        local bad = lim(b, ad, ...)
        if MoveField._on and type(b) == "table" and (b.__ndxThroatChop or 0) > 0 and type(bad) == "table" then
          local okM, Moves = pcall(require, "src.core.game3.battle.moves")
          for i = 1, 4 do
            local mv = b.mon and b.mon.moves and b.mon.moves[i]
            local n = okM and mv and Moves.numForName(mv) or tonumber(mv)
            if n and MoveField._sound[n] then bad[i] = true end
          end
        end
        return bad
      end
    end
  end

  -- Throat Chop: the move itself, and the player's menu
  local okAb, Ab = pcall(require, "src.core.game3.battle.abilities")
  if okAb and type(Ab.soundproofBlocks) == "function" and not Ab.__nationalDexMoveField then
    Ab.__nationalDexMoveField = true
    local blocks = Ab.soundproofBlocks
    Ab.soundproofBlocks = function(M, ...)
      if MoveField._on and type(M) == "table" and M.user and (M.user.__ndxThroatChop or 0) > 0
          and MoveField._sound[tonumber(M.mnum) or -1] then
        if M.user.expLockedMove then M.noPP = true end
        M:attackString()
        M:ppReduce()
        M.adapter:say("The effects of THROAT CHOP prevent\n" .. prefixed(M.adapter, M.user) .. " from using certain moves!")
        if M.anim then M.anim.statusOnly, M.anim.missed = true, true end
        M.noEffect = true
        return true
      end
      return blocks(M, ...)
    end
  end
  local okC, Commands = pcall(require, "src.core.game3.battle.commands")
  if okC and type(Commands.selectionError) == "function" and not Commands.__nationalDexMoveField then
    Commands.__nationalDexMoveField = true
    local selErr = Commands.selectionError
    Commands.selectionError = function(st, slot, battlerId, ...)
      local err = selErr(st, slot, battlerId, ...)
      if err or not MoveField._on then return err end
      local okS, State = pcall(require, "src.core.game3.battle.state")
      local b = okS and State.battler(st, battlerId)
      if b and (b.__ndxThroatChop or 0) > 0 and slot and b.mon and b.mon.moves then
        local okM, Moves = pcall(require, "src.core.game3.battle.moves")
        local mv = b.mon.moves[slot]
        local n = okM and mv and Moves.numForName(mv) or tonumber(mv)
        if n and MoveField._sound[n] then return "The effects of THROAT CHOP prevent\n" .. prefixed(adapter() or { _st = st, displayName = function() return "It" end }, b) .. " from using certain moves!" end
      end
      return err
    end
  end

  -- Rapid Spin (the cart's) sweeps our hazards away with its Spikes
  local okHz, Hazards = pcall(require, "src.core.game3.battle.effects.hazards")
  if okHz and type(Hazards.clear) == "function" and not Hazards.__nationalDexMoveField then
    Hazards.__nationalDexMoveField = true
    local clear = Hazards.clear
    Hazards.clear = function(side, ...)
      if type(side) == "table" then clearHazards(side) end
      return clear(side, ...)
    end
  end

  -- Magic Room: held items stay held but do nothing. Every held-item EFFECT the battle reads goes
  -- through HeldItems.of (-> hold effect, parameter, item); the item itself (HeldItems.itemOf,
  -- b.item) is untouched, so Knock Off, Trick, Thief and Fling still see and move it, as in the
  -- real games. (The engine's held_item.trigger hook could do the same, but registering it makes
  -- every held-item check in every battle copy the item's info table; this wrap allocates nothing.)
  local okHI, HeldItems = pcall(require, "src.core.game3.battle.held_items")
  if okHI and type(HeldItems.of) == "function" and not HeldItems.__nationalDexMoveField then
    HeldItems.__nationalDexMoveField = true
    local heldOf = HeldItems.of
    HeldItems.of = function(b, trigger, st, ...)
      if MoveField._on then
        local field = st or (adapter() and adapter()._st)
        if fieldOn(field, "magicRoom") then
          local _, _, item = heldOf(b, trigger, st, ...)
          return 0, 0, item
        end
      end
      return heldOf(b, trigger, st, ...)
    end
  end

  -- the terrain boosts, Aurora Veil, Wonder Room, Magnet Rise, Thousand Arrows
  if not Damage.__nationalDexMoveField then
    Damage.__nationalDexMoveField = true
    local calc = Damage.calc
    Damage.calc = function(attacker, defender, moveId, o, ...)
      local ad = o and o.adapter
      local st = ad and ad._st
      if not (MoveField._on and st and type(attacker) == "table" and type(defender) == "table") then
        return calc(attacker, defender, moveId, o, ...)
      end
      local kind = terrainOf(st)
      local f = st.__ndxField or {}
      local dside = ad:ownSide(defender)
      local veil = dside and dside.__ndx and (dside.__ndx.auroraVeil or 0) > 0
      local num = type(moveId) == "table" and (tonumber(moveId.numId) or tonumber(moveId.id)) or tonumber(moveId)
      local rule = num and MoveField._rules[num]
      local move = type(moveId) == "table" and moveId or {}
      local mtype = tonumber(o.moveType) or tonumber(move.type)
      local magnet = (defender.__ndxMagnetRise or 0) > 0 and mtype == ID.GROUND and not defender.__ndxGrounded
      -- a Flying type brought down (Smack Down, Gravity) takes Ground moves; so does one under Thousand Arrows
      local flying = defender.type1 == ID.FLYING or defender.type2 == ID.FLYING
      local brought = flying and mtype == ID.GROUND and (defender.__ndxGrounded or (f.gravity or 0) > 0)
      if not (kind or (f.wonderRoom or 0) > 0 or veil or magnet or brought or rule == "THOUSAND_ARROWS") then
        return calc(attacker, defender, moveId, o, ...)
      end
      local o2 = {}
      for k, v in pairs(o) do o2[k] = v end
      local saved = {}
      local function set(tbl, key, value)
        saved[#saved + 1] = { tbl, key, tbl[key] }
        tbl[key] = value
      end
      local mult = 1
      local okP = pcall(function()
        if kind then
          local t = TERRAIN_BY_KIND[kind]
          if rule == "TERRAIN_PULSE" and grounded(ad, attacker) then
            o2.moveType, o2.power = t.type, 100
            mtype = t.type
          end
          if grounded(ad, attacker) and mtype == t.type and kind ~= "MISTY" then mult = mult * 1.3 end
          if kind == "MISTY" and mtype == ID.DRAGON and grounded(ad, defender) then mult = mult * 0.5 end
          if rule == "RISING_VOLTAGE" and kind == "ELECTRIC" and grounded(ad, defender) then mult = mult * 2 end
          if rule == "EXPANDING_FORCE" and kind == "PSYCHIC" and grounded(ad, attacker) then mult = mult * 1.5 end
        end
        if (f.wonderRoom or 0) > 0 then
          local dMon = defender.mon or defender
          local d, s = tonumber(dMon.defense), tonumber(dMon.spDef)
          set(dMon, "defense", s)
          set(dMon, "spDef", d)
          if defender.stages then
            local ds, ss = defender.stages.defense, defender.stages.spDef
            set(defender.stages, "defense", ss)
            set(defender.stages, "spDef", ds)
          end
        end
        if brought or (rule == "THOUSAND_ARROWS" and not grounded(ad, defender)) then
          -- a Flying type is hit for neutral damage
          if defender.type1 == ID.FLYING then set(defender, "type1", ID.MYSTERY) end
          if defender.type2 == ID.FLYING then set(defender, "type2", ID.MYSTERY) end
          if defender.expTransform then
            if defender.expTransform.type1 == ID.FLYING then set(defender.expTransform, "type1", ID.MYSTERY) end
            if defender.expTransform.type2 == ID.FLYING then set(defender.expTransform, "type2", ID.MYSTERY) end
          end
        end
      end)
      local function restore()
        for i = #saved, 1, -1 do saved[i][1][saved[i][2]] = saved[i][3] end
      end
      if not okP then
        restore()
        return calc(attacker, defender, moveId, o, ...)
      end
      local res = { pcall(calc, attacker, defender, moveId, o2, ...) }
      restore()
      if not res[1] then error(res[2], 0) end
      local dmg, info = res[2], res[3]
      if magnet and type(info) == "table" then
        info.effectiveness = 0
        info.typeFlags = info.typeFlags or {}
        info.typeFlags.immune = true
        return 0, info
      end
      if veil and type(info) == "table" and not info.critical and (tonumber(dmg) or 0) > 0 then
        mult = mult * (o.doubleScreens and 2 / 3 or 0.5)
      end
      if mult ~= 1 and (tonumber(dmg) or 0) > 0 then dmg = math.max(1, math.floor(dmg * mult)) end
      return dmg, info
    end
  end

  -- Misty / Electric Terrain's status guards, Heal Block, Levitate while grounded
  if okA and type(Adapter.new) == "function" and not Adapter.__nationalDexMoveField then
    Adapter.__nationalDexMoveField = true
    local new = Adapter.new
    Adapter.new = function(...)
      local a = new(...)
      if type(a) ~= "table" then return a end
      if type(a.canApplyStatus) == "function" then
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
      if type(a.heal) == "function" then
        local heal = a.heal
        a.heal = function(self, b, amount, ...)
          if MoveField._on and b and (b.__ndxHealBlock or 0) > 0 then return 0 end
          return heal(self, b, amount, ...)
        end
      end
      if type(a.abilityOf) == "function" then
        local of = a.abilityOf
        a.abilityOf = function(self, b)
          local name = of(self, b)
          if name == "LEVITATE" and MoveField._on and b and (b.__ndxGrounded or fieldOn(self._st, "gravity")) then
            return nil
          end
          return name
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
