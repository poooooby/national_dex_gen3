-- Real abilities newer than Gen 3 (data/abilities.lua, tools/build_abilities.py).
--
-- The Gen 3 battle engine names a battler's ability through the adapter's `abilityOf` (a name
-- string, "TECHNICIAN") and acts on it inside its own functions. A mod cannot add a branch to
-- those, but nearly every place an ability acts is an exported function or a battle hook, so:
--   * names and numbers: each ability gets its id (78+) in the adapter's id table, the species
--     module's ability names and the battle helpers' id lookups; the summary shows its text
--   * which Pokemon have it: a species' ability pair is set on the live table from its real
--     slots (a slot whose ability is not here keeps the closest Gen 3 one), and `abilityOf`
--     answers from the species and the Pokemon's ability slot, so a Pokemon already in a save
--     (it stores the number it was given) gets its real ability too
--   * what it does, through wraps and hooks:
--       Damage.base         power: TECHNICIAN, STRONG_JAW, IRON_FIST, TOUGH_CLAWS, RECKLESS,
--                           SAND_FORCE, RIVALRY, PROTOSYNTHESIS, QUARK_DRIVE; taken: HEATPROOF, DRY_SKIN
--       battle.damage       ADAPTABILITY, SNIPER, TINTED_LENS, MULTISCALE, FLUFFY, FILTER,
--                           SOLID_ROCK, PRISM_ARMOR, PROTOSYNTHESIS, QUARK_DRIVE (defence)
--       battle.crit         SUPER_LUCK          battle.accuracy  SNOW_CLOAK
--       battle.turn_order   PRANKSTER, SAND_RUSH, SLUSH_RUSH, PROTOSYNTHESIS, QUARK_DRIVE (speed)
--       switchIn            SNOW_WARNING, FRISK, ANTICIPATION
--       endTurn             ICE_BODY, HYDRATION, DRY_SKIN
--       switchOut           REGENERATOR
--       absorb              SAP_SIPPER, MOTOR_DRIVE, STORM_DRAIN, DRY_SKIN, BULLETPROOF
--       onDamage            IRON_BARBS, JUSTIFIED, RATTLED, STAMINA, WEAK_ARMOR, AFTERMATH,
--                           POISON_TOUCH, MOXIE, BEAST_BOOST
--       changeStat          BIG_PECKS, FLOWER_VEIL, DEFIANT, COMPETITIVE
--       Status moves        LEAF_GUARD, SWEET_VEIL, FLOWER_VEIL (a status from a move's side
--                           effect is not blocked: that check is local to the engine)
--     HEALER, TELEPATHY and HONEY_GATHER have no effect in a single battle here, as in the
--     games (no partner); QUARK_DRIVE works on Electric Terrain (no Booster Energy in Gen 3)
-- An ability whose wrap target is missing is not installed, and its Pokemon keep the closest
-- Gen 3 ability. Every addition runs protected: an error falls back to the engine's own result.

local RealAbilities = {}

local function set(list)
  local t = {}
  for _, k in ipairs(list) do t[k] = true end
  return t
end

-- moves by the battle's name for them (Moves.constName: the cart's spelling, this mod's ids)
local PUNCH = set{ "COMET_PUNCH", "MEGA_PUNCH", "FIRE_PUNCH", "ICE_PUNCH", "THUNDERPUNCH", "THUNDER_PUNCH",
  "MACH_PUNCH", "DYNAMICPUNCH", "DYNAMIC_PUNCH", "DIZZY_PUNCH", "FOCUS_PUNCH", "METEOR_MASH", "SHADOW_PUNCH",
  "SKY_UPPERCUT", "HAMMER_ARM", "DRAIN_PUNCH", "BULLET_PUNCH", "POWER_UP_PUNCH", "ICE_HAMMER",
  "DOUBLE_IRON_BASH", "PLASMA_FISTS", "JET_PUNCH", "SURGING_STRIKES", "WICKED_BLOW", "HEADLONG_RUSH", "RAGE_FIST" }
local BITE = set{ "BITE", "CRUNCH", "HYPER_FANG", "POISON_FANG", "FIRE_FANG", "ICE_FANG", "THUNDER_FANG",
  "PSYCHIC_FANGS", "JAW_LOCK", "FISHIOUS_REND" }
local RECOIL = set{ "DOUBLE_EDGE", "TAKE_DOWN", "SUBMISSION", "VOLT_TACKLE", "BRAVE_BIRD", "FLARE_BLITZ",
  "WOOD_HAMMER", "HEAD_SMASH", "WILD_CHARGE", "HEAD_CHARGE", "JUMP_KICK", "HI_JUMP_KICK", "HIGH_JUMP_KICK",
  "WAVE_CRASH" }
local BALL_BOMB = set{ "BARRAGE", "EGG_BOMB", "SHADOW_BALL", "SLUDGE_BOMB", "ZAP_CANNON", "OCTAZOOKA",
  "MIST_BALL", "ICE_BALL", "BULLET_SEED", "WEATHER_BALL", "ENERGY_BALL", "FOCUS_BLAST", "GYRO_BALL",
  "SEED_BOMB", "MUD_BOMB", "MAGNET_BOMB", "ROCK_WRECKER", "AURA_SPHERE", "ACID_SPRAY", "SEARING_SHOT",
  "ELECTRO_BALL", "POLLEN_PUFF", "BEAK_BLAST", "PYRO_BALL" }

-- the abilities that have no effect in a single battle here (installed for their name and text)
local QUIET = set{ "HEALER", "TELEPATHY", "HONEY_GATHER" }

local function safe(fn, ...)
  local ok, a, b = pcall(fn, ...)
  if ok then return true, a, b end
  return false
end

local function contact(move)
  return ((tonumber(move and move.flags) or 0) % 2) == 1
end

-- the battle's current adapter (a mod has no `package`; the module is loaded by then)
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

local function weather(ad)
  local st = ad and ad._st
  return st and st.weather or nil
end

-- Protosynthesis in sun, Quark Drive on Electric Terrain (src/move_field.lua keeps the terrain)
local function boosterOn(ad, ab)
  if ab == "PROTOSYNTHESIS" then return weather(ad) == "SUN" end
  if ab ~= "QUARK_DRIVE" then return false end
  local f = ad and ad._st and ad._st.__ndxField
  return f ~= nil and (f.terrainTurns or 0) > 0 and f.terrain == "ELECTRIC"
end

local function gender(b)
  local mon = b and b.mon
  local g = mon and mon.gender
  if g == "M" or g == "F" then return g end
  return nil
end

local function moveName(require, move)
  if type(move) ~= "table" then return nil end
  if type(move.id) == "string" then return move.id end
  local okM, Moves = pcall(require, "src.core.game3.battle.moves")
  return okM and Moves.constName and Moves.constName(tonumber(move.numId) or tonumber(move.id) or -1) or nil
end

-- the stat Protosynthesis/Beast Boost raise: the highest of the battler's five (ties in order)
local function bestStat(b)
  local mon = b and b.mon or {}
  local best, val = "attack", -1
  for _, k in ipairs({ "attack", "defense", "spAtk", "spDef", "speed" }) do
    local v = tonumber(mon[k]) or 0
    if v > val then best, val = k, v end
  end
  return best
end

-- Hooks have to exist when the mod loads; they act only once install() has run.
function RealAbilities.hooks(mod)
  local on = function() return RealAbilities._on end

  mod.hooks:wrap("battle.damage", function(nextFn, c)
    local dmg, info = nextFn(c)
    if not on() or type(c) ~= "table" or (tonumber(dmg) or 0) <= 0 or type(info) ~= "table" then return dmg, info end
    local ok, out = pcall(function()
      local ad = adapter()
      local ua, ta = abilityOf(ad, c.user), abilityOf(ad, c.target)
      local d = tonumber(dmg)
      local eff = tonumber(info.effectiveness) or 1
      local mtype = tonumber(info.moveType)
      if ua == "ADAPTABILITY" and (tonumber(info.stab) or 1) > 1 then d = d * 2 / 1.5 end
      if ua == "SNIPER" and info.critical then d = d * 1.5 end
      if ua == "TINTED_LENS" and eff > 0 and eff < 1 then d = d * 2 end
      if ta == "MULTISCALE" and ad and ad:hp(c.target) >= ad:maxHp(c.target) then d = d / 2 end
      if ta == "FLUFFY" then
        if contact(c.move) then d = d / 2 end
        if mtype == 10 then d = d * 2 end                     -- FIRE
      end
      if (ta == "FILTER" or ta == "SOLID_ROCK" or ta == "PRISM_ARMOR") and eff > 1 then d = d * 0.75 end
      if boosterOn(ad, ta) then
        local best = bestStat(c.target)
        if (info.physical and best == "defense") or (not info.physical and best == "spDef") then d = d / 1.3 end
      end
      return math.max(1, math.floor(d))
    end)
    if ok then return out, info end
    return dmg, info
  end)

  mod.hooks:wrap("battle.crit", function(nextFn, c)
    if on() and type(c) == "table" then
      local ad = adapter()
      if abilityOf(ad, c.attacker) == "SUPER_LUCK" then c.highCrit = true end
    end
    return nextFn(c)
  end)

  mod.hooks:wrap("battle.accuracy", function(nextFn, c)
    if on() and type(c) == "table" and tonumber(c.accuracy) then
      local ad = adapter()
      if abilityOf(ad, c.target) == "SNOW_CLOAK" and weather(ad) == "HAIL" then
        c.accuracy = math.floor(c.accuracy * 80 / 100)
      end
    end
    return nextFn(c)
  end)

  -- a: first battler, b: second; true when a moves first
  mod.hooks:wrap("battle.turn_order", function(nextFn, a, aMove, b, bMove, ctx)
    if not on() or not (a and b and aMove and bMove) then return nextFn(a, aMove, b, bMove, ctx) end
    local ok, decided = pcall(function()
      local ad = adapter()
      local aa, ba = abilityOf(ad, a), abilityOf(ad, b)
      local pa, pb = RealAbilities.priorityOf(ad, a, aMove), RealAbilities.priorityOf(ad, b, bMove)
      if (aa == "PRANKSTER" or ba == "PRANKSTER") and pa ~= pb then return pa > pb end
      if pa ~= pb then return nil end
      -- only decide when something of ours changes the speeds, so the cart keeps its own
      -- tie-break otherwise
      local reverse = RealAbilities.reverseSpeed and RealAbilities.reverseSpeed(ad and ad._st)
      local sa, ma = RealAbilities.effectiveSpeed(ad, a)
      local sb, mb = RealAbilities.effectiveSpeed(ad, b)
      if not (ma or mb or reverse) or sa == sb then return nil end
      if reverse then return sa < sb end
      return sa > sb
    end)
    if ok and decided ~= nil then return decided end
    return nextFn(a, aMove, b, bMove, ctx)
  end)
end

-- Speed as the turn order sees it: stages, paralysis, the weather-speed abilities, plus any
-- modifier another module registered (src/move_field.lua: Tailwind). Returns the speed and
-- whether anything of ours changed it.
RealAbilities.speedModifiers = {}                -- key -> fn(ad, b) -> multiplier (1 = none)
RealAbilities.reverseSpeed = nil                 -- fn(st) -> true while slower goes first
function RealAbilities.effectiveSpeed(ad, b)
  local over = b.__ndxStat and tonumber(b.__ndxStat.speed)        -- Speed Swap (src/move_rules.lua)
  local s = over or tonumber(b.mon and b.mon.speed) or 0
  local okD, Damage = pcall(require, "src.core.game3.battle.damage")
  if okD and Damage.applyStage then s = Damage.applyStage(s, b.stages and b.stages.speed or 0) end
  local ab, w, modified = abilityOf(ad, b), weather(ad), over ~= nil
  if boosterOn(ad, ab) and bestStat(b) == "speed" then s, modified = s * 1.5, true
  elseif (ab == "SAND_RUSH" and w == "SAND") or (ab == "SLUSH_RUSH" and w == "HAIL") then s, modified = s * 2, true end
  for _, fn in pairs(RealAbilities.speedModifiers) do
    local okM, m = pcall(fn, ad, b)
    if okM and tonumber(m) and m ~= 1 then s, modified = s * m, true end
  end
  if ad and ad:status(b) == "PAR" then s = s / 4 end
  return s, modified
end

function RealAbilities.priorityOf(ad, b, mv)
  local p = tonumber(mv and mv.priority) or 0
  if abilityOf(ad, b) == "PRANKSTER" and (tonumber(mv and mv.power) or 0) == 0 then p = p + 1 end
  return p
end

-- opts: { data = data/abilities.lua, require, log, formSlots = { [formId] = slot } }
function RealAbilities.install(opts)
  local require, log, data = opts.require, opts.log, opts.data or {}
  local okA, Adapter = pcall(require, "src.core.game3.battle.adapter")
  local okAb, Ab = pcall(require, "src.core.game3.battle.abilities")
  local okP, P = pcall(require, "src.core.game3.pokemon")
  if not (okA and okAb and okP and type(Adapter.ABILITY_BY_ID) == "table" and type(Adapter.new) == "function") then
    if log then log:warn("real abilities are off: the battle engine's ability table was not found") end
    return false
  end
  local okS, Secondary = pcall(require, "src.core.game3.battle.effects.secondary")
  local okD, Damage = pcall(require, "src.core.game3.battle.damage")
  local okSt, Status = pcall(require, "src.core.game3.battle.effects.status")
  local okT, Types = pcall(require, "src.core.game3.battle.types")
  local okState, State = pcall(require, "src.core.game3.battle.state")
  local okI, ItemsData = pcall(require, "src.core.game3.items_data")

  -- which abilities can work: their wrap targets exist
  local need = {
    damage = okD and type(Damage.base) == "function",
    switchIn = type(Ab.switchIn) == "function", endTurn = type(Ab.endTurn) == "function",
    switchOut = type(Ab.switchOut) == "function", absorb = type(Ab.absorb) == "function",
    onDamage = type(Ab.onDamage) == "function",
    stat = okS and type(Secondary.changeStat) == "function",
    status = okSt and type(Status.cantMakeAsleep) == "function",
  }
  local REQUIRES = {
    TECHNICIAN = "damage", STRONG_JAW = "damage", IRON_FIST = "damage", TOUGH_CLAWS = "damage",
    RECKLESS = "damage", SAND_FORCE = "damage", HEATPROOF = "damage", DRY_SKIN = "damage", RIVALRY = "damage",
    PROTOSYNTHESIS = "damage", QUARK_DRIVE = "damage", SNOW_WARNING = "switchIn", FRISK = "switchIn", ANTICIPATION = "switchIn",
    ICE_BODY = "endTurn", HYDRATION = "endTurn", REGENERATOR = "switchOut", SAP_SIPPER = "absorb",
    MOTOR_DRIVE = "absorb", STORM_DRAIN = "absorb", BULLETPROOF = "absorb", IRON_BARBS = "onDamage",
    JUSTIFIED = "onDamage", RATTLED = "onDamage", STAMINA = "onDamage", WEAK_ARMOR = "onDamage",
    AFTERMATH = "onDamage", POISON_TOUCH = "onDamage", MOXIE = "onDamage", BEAST_BOOST = "onDamage",
    BIG_PECKS = "stat", DEFIANT = "stat", COMPETITIVE = "stat", FLOWER_VEIL = "stat",
    LEAF_GUARD = "status", SWEET_VEIL = "status",
  }
  local byKey, bySlug, idOf, textOf = {}, {}, {}, {}
  for _, d in ipairs(data.defs or {}) do
    local req = REQUIRES[d.key]
    if req == nil or need[req] then
      byKey[d.key], bySlug[d.slug], idOf[d.key], textOf[d.id] = d, d, d.id, d.text
    end
  end

  -- names and numbers
  local function names()
    for key, d in pairs(byKey) do
      Adapter.ABILITY_BY_ID[d.id] = key
      if type(P._abilityNames) == "table" then P._abilityNames[d.id] = d.name end
    end
  end
  if not P._abilityNames then pcall(P.abilityName, 1) end
  names()
  if not Ab.__nationalDexAbilities then
    Ab.__nationalDexAbilities = true
    local id = Ab.id
    Ab.id = function(ab) return idOf[ab] or id(ab) end
    local okH, H = pcall(require, "src.core.game3.battle.effects._helpers")
    if okH and type(H) == "table" and type(H.abilityId) == "function" then
      local hid = H.abilityId
      H.abilityId = function(name) return idOf[name] or hid(name) end
    end
    local okSD, SummaryData = pcall(require, "src.core.game3.summary_data")
    if okSD and type(SummaryData.abilityDescription) == "function" then
      local desc = SummaryData.abilityDescription
      SummaryData.abilityDescription = function(abilityId, name, ...)
        local t = textOf[tonumber(abilityId) or -1]
        if t then return t end
        return desc(abilityId, name, ...)
      end
    end
  end

  -- which Pokemon have it: live ability pairs, and the real name by species and slot
  local real = {}                                  -- slot -> { [1] = KEY?, [2] = KEY? }
  local function pairOf(slots)
    local ids, keys = {}, {}
    for _, s in ipairs(slots or {}) do
      local d = bySlug[s[1]]
      local id = d and d.id or tonumber(s[2]) or 0
      if id > 0 then
        local dup = false
        for _, v in ipairs(ids) do if v == id then dup = true end end
        if not dup then ids[#ids + 1] = id; keys[#ids] = d and d.key or false end
      end
    end
    return ids, keys
  end
  local function applyPairs()
    if type(P._abilities) ~= "table" then return 0 end
    local n = 0
    local function put(slot, slots)
      if not slot then return end
      local ids, keys = pairOf(slots)
      if #ids == 0 then return end
      local any = keys[1] or keys[2]
      if not any then return end                       -- nothing real: keep the record's pair
      P._abilities[slot] = { ids[1], ids[2] or 0 }
      real[slot] = { keys[1] or nil, keys[2] or nil }
      n = n + 1
    end
    for dex, slots in pairs(data.species or {}) do
      put(P.speciesFromNational and P.speciesFromNational(dex), slots)
    end
    for fid, slots in pairs(data.forms or {}) do
      put(opts.formSlots and opts.formSlots[fid], slots)
    end
    return n
  end
  local count = applyPairs()
  if P.onReload then P.onReload(function() names() applyPairs() end, "national_dex_gen3.abilities") end

  local function realFor(b)
    local mon = b.mon or {}
    local species = tonumber(b.species) or tonumber(mon.species)
    local r = species and real[species]
    if not r then return nil end
    local pair = P._abilities and P._abilities[species] or {}
    local slot = tonumber(mon.abilityNum or mon.altAbility)
    if not slot then slot = (pair[2] and pair[2] ~= 0) and ((tonumber(mon.personality) or 0) % 2) or 0 end
    if not (pair[2] and pair[2] ~= 0) then slot = 0 end
    return r[(slot % 2) + 1]
  end

  if not Adapter.__nationalDexAbilities then
    Adapter.__nationalDexAbilities = true
    local new = Adapter.new
    Adapter.new = function(...)
      local a = new(...)
      if type(a) == "table" and type(a.abilityOf) == "function" then
        local of = a.abilityOf
        a.abilityOf = function(self, b)
          local name = of(self, b)
          if not b or b.expTracedAbility or b.expAbilitySuppressed then return name end
          local ok, r = pcall(realFor, b)
          if ok and r then return r end
          return name
        end
      end
      return a
    end
  end

  local function prefixed(ad, b)
    if okState and State.prefixedName then
      local ok, n = pcall(State.prefixedName, ad._st, b)
      if ok and n then return n end
    end
    return (ad.displayName and ad:displayName(b)) or "POKeMON"
  end
  local function raise(ad, b, stat, delta, flags)
    if okS then return Secondary.changeStat(ad, b, stat, delta, flags or {}) end
  end
  local function hasType(b, t) return b and (b.type1 == t or b.type2 == t) end
  local ID = okT and Types.ID or {}

  -- Damage.base: power, and the defending side's Heatproof / Dry Skin
  if need.damage and not Damage.__nationalDexAbilities then
    Damage.__nationalDexAbilities = true
    local base = Damage.base
    Damage.base = function(attacker, defender, move, o, ...)
      if not (RealAbilities._on and type(o) == "table" and o.adapter and type(move) == "table") then
        return base(attacker, defender, move, o, ...)
      end
      local ok, mult = pcall(function()
        local ad = o.adapter
        local aa, da = abilityOf(ad, attacker), abilityOf(ad, defender)
        local power = tonumber(o.power) or tonumber(move.power) or 0
        local mtype = tonumber(o.moveType) or tonumber(move.type) or 0
        local name = moveName(require, move)
        local m = 1
        if power <= 0 then return 1 end
        if aa == "TECHNICIAN" and power <= 60 then m = m * 1.5 end
        if aa == "STRONG_JAW" and name and BITE[name] then m = m * 1.5 end
        if aa == "IRON_FIST" and name and PUNCH[name] then m = m * 1.2 end
        if aa == "TOUGH_CLAWS" and contact(move) then m = m * 1.3 end
        if aa == "RECKLESS" and name and RECOIL[name] then m = m * 1.2 end
        if aa == "SAND_FORCE" and weather(ad) == "SAND"
            and (mtype == ID.ROCK or mtype == ID.GROUND or mtype == ID.STEEL) then m = m * 1.3 end
        if aa == "RIVALRY" then
          local ga, gd = gender(attacker), gender(defender)
          if ga and gd then m = m * (ga == gd and 1.25 or 0.75) end
        end
        if boosterOn(ad, aa) then
          local best = bestStat(attacker)
          local phys = okT and Types.isPhysical(mtype)
          if (phys and best == "attack") or (not phys and best == "spAtk") then m = m * 1.3 end
        end
        if da == "HEATPROOF" and mtype == ID.FIRE then m = m * 0.5 end
        if da == "DRY_SKIN" and mtype == ID.FIRE then m = m * 1.25 end
        return m
      end)
      if ok and mult and mult ~= 1 then
        local copy = {}
        for k, v in pairs(o) do copy[k] = v end
        copy.power = math.max(1, math.floor((tonumber(o.power) or tonumber(move.power) or 0) * mult))
        return base(attacker, defender, move, copy, ...)
      end
      return base(attacker, defender, move, o, ...)
    end
  end

  -- switch-in
  if need.switchIn and not Ab.__nationalDexSwitchIn then
    Ab.__nationalDexSwitchIn = true
    local switchIn = Ab.switchIn
    Ab.switchIn = function(ad, b, ...)
      local r = switchIn(ad, b, ...)
      if r or not RealAbilities._on or not b or ad:isFainted(b) then return r end
      local ok, acted = safe(function()
        local ab = abilityOf(ad, b)
        local st = ad._st
        if ab == "SNOW_WARNING" and st and st.weather ~= "HAIL" then
          st.weather, st.weatherTurns = "HAIL", 0
          ad:sayText("STRINGID_STARTEDHAIL", {})
          pcall(ad.playAnim, ad, "general", "HAIL_CONTINUES", nil, nil)
          return true
        elseif ab == "FRISK" and not b.expFrisked then
          b.expFrisked = true
          local foe = ad:foeOf(b)
          local item = foe and foe.mon and tonumber(foe.mon.item or foe.mon.heldItem) or 0
          if item > 0 and okI and ItemsData.displayName then
            ad:say(prefixed(ad, b) .. " frisked the foe and\nfound its " .. tostring(ItemsData.displayName(item)) .. "!")
            return true
          end
        elseif ab == "ANTICIPATION" and not b.expAnticipated then
          b.expAnticipated = true
          local foe = ad:foeOf(b)
          local okM, Moves = pcall(require, "src.core.game3.battle.moves")
          for _, mv in ipairs(foe and foe.mon and foe.mon.moves or {}) do
            local num = type(mv) == "table" and tonumber(mv.id or mv.move) or tonumber(mv)
            local okG, def = okM and pcall(Moves.get, num)
            if okG and type(def) == "table" and (tonumber(def.power) or 0) > 0 and okT
                and Types.effectiveness(def.type, b.type1, b.type2) > 1 then
              ad:say(prefixed(ad, b) .. " shuddered!")
              return true
            end
          end
        end
        return false
      end)
      if ok then return acted or r end
      return r
    end
  end

  -- end of turn
  if need.endTurn and not Ab.__nationalDexEndTurn then
    Ab.__nationalDexEndTurn = true
    local endTurn = Ab.endTurn
    Ab.endTurn = function(ad, b, ...)
      local r = endTurn(ad, b, ...)
      if r or not RealAbilities._on or not b or ad:hp(b) <= 0 then return r end
      local ok, acted = safe(function()
        local ab, w = abilityOf(ad, b), weather(ad)
        local maxHp, hp = ad:maxHp(b), ad:hp(b)
        if ab == "ICE_BODY" and w == "HAIL" and hp < maxHp then
          ad:heal(b, math.max(1, math.floor(maxHp / 16)))
          ad:sayText("STRINGID_PKMNSXRESTOREDHPALITTLE2", { atk = b, atkAbility = idOf.ICE_BODY })
          return true
        elseif ab == "DRY_SKIN" and w == "RAIN" and hp < maxHp then
          ad:heal(b, math.max(1, math.floor(maxHp / 8)))
          ad:sayText("STRINGID_PKMNSXRESTOREDHPALITTLE2", { atk = b, atkAbility = idOf.DRY_SKIN })
          return true
        elseif ab == "DRY_SKIN" and w == "SUN" then
          ad:applyHpLoss(b, math.max(1, math.floor(maxHp / 8)))
          ad:say(prefixed(ad, b) .. " was hurt by its\nDRY SKIN!")
          return true
        elseif ab == "HYDRATION" and w == "RAIN" and ad:status(b) then
          ad:clearStatus(b)
          if okState and State.partyMon then
            local pm = State.partyMon(b)
            if pm then pm.status = nil end
          end
          ad:say(prefixed(ad, b) .. "'s HYDRATION\ncured its status problem!")
          return true
        end
        return false
      end)
      if ok then return acted or r end
      return r
    end
  end

  -- switch-out
  if need.switchOut and not Ab.__nationalDexSwitchOut then
    Ab.__nationalDexSwitchOut = true
    local switchOut = Ab.switchOut
    Ab.switchOut = function(ad, b, ...)
      local r = switchOut(ad, b, ...)
      if RealAbilities._on and b then
        safe(function()
          if abilityOf(ad, b) == "REGENERATOR" and ad:hp(b) > 0 and ad:hp(b) < ad:maxHp(b) then
            local mon = b.mon
            local amt = math.floor(ad:maxHp(b) / 3)
            mon.hp = math.min(ad:maxHp(b), ad:hp(b) + amt)
            if okState and State.partyMon then
              local pm = State.partyMon(b)
              if pm and pm ~= mon then pm.hp = mon.hp end
            end
          end
        end)
      end
      return r
    end
  end

  -- absorbing a move's type
  if need.absorb and not Ab.__nationalDexAbsorb then
    Ab.__nationalDexAbsorb = true
    local absorb = Ab.absorb
    Ab.absorb = function(M, ...)
      local r = absorb(M, ...)
      if r or not RealAbilities._on or type(M) ~= "table" then return r end
      local ad, user, target = M.adapter, M.user, M.target
      if not (ad and target and target ~= user) or M.nationalDexAbsorbChecked then return r end
      M.nationalDexAbsorbChecked = true
      local ok, acted = safe(function()
        local ab = abilityOf(ad, target)
        local mt = tonumber(M.moveType or (M.move and M.move.type)) or 0
        local name = moveName(require, M.move)
        local stat
        if ab == "SAP_SIPPER" and mt == ID.GRASS then stat = "attack"
        elseif ab == "MOTOR_DRIVE" and mt == ID.ELECTRIC then stat = "speed"
        elseif ab == "STORM_DRAIN" and mt == ID.WATER then stat = "spAtk"
        elseif ab == "DRY_SKIN" and mt == ID.WATER then stat = "heal"
        elseif ab == "BULLETPROOF" and name and BALL_BOMB[name] then stat = "block"
        end
        if not stat then return false end
        if M.attackString then M:attackString() end
        M.absorbed, M.noEffect = true, true
        if M.anim then M.anim.missed = true end
        if stat == "heal" then
          if ad:hp(target) < ad:maxHp(target) then
            ad:heal(target, math.max(1, math.floor(ad:maxHp(target) / 4)))
            ad:sayText("STRINGID_PKMNRESTOREDHPUSING", { def = target, defAbility = idOf.DRY_SKIN })
          else
            ad:sayText("STRINGID_PKMNSXMADEYUSELESS", { def = target, defAbility = idOf.DRY_SKIN, currentMove = M.moveName })
          end
        elseif stat == "block" then
          ad:say("It doesn't affect\n" .. prefixed(ad, target) .. "...")
        else
          local res = raise(ad, target, stat, 1, {})
          if res ~= "worked" then
            ad:sayText("STRINGID_PKMNSXMADEYUSELESS", { def = target, defAbility = idOf[ab], currentMove = M.moveName })
          end
        end
        return true
      end)
      if ok then return acted or r end
      return r
    end
  end

  -- after a hit lands
  if need.onDamage and not Ab.__nationalDexOnDamage then
    Ab.__nationalDexOnDamage = true
    local onDamage = Ab.onDamage
    Ab.onDamage = function(M, ...)
      local r = onDamage(M, ...)
      if not RealAbilities._on or type(M) ~= "table" then return r end
      local ad, user, target = M.adapter, M.user, M.target
      if not (ad and user and target) or target == user or M.noEffect or not M.targetDamaged then return r end
      local ok, acted = safe(function()
        local ta, ua = abilityOf(ad, target), abilityOf(ad, user)
        local mt = tonumber(M.moveType or (M.move and M.move.type)) or 0
        local touched = contact(M.move)
        local targetDown = ad:hp(target) <= 0
        local did = false
        -- the target's ability
        if ta == "IRON_BARBS" and touched and ad:hp(user) > 0 then
          ad:applyHpLoss(user, math.max(1, math.floor(ad:maxHp(user) / 8)))
          ad:sayText("STRINGID_PKMNHURTSWITH", { def = target, defAbility = idOf.IRON_BARBS, atk = user })
          if M.tryFaintUser then M:tryFaintUser() end
          did = true
        elseif ta == "AFTERMATH" and touched and targetDown and ad:hp(user) > 0 then
          ad:applyHpLoss(user, math.max(1, math.floor(ad:maxHp(user) / 4)))
          ad:say(prefixed(ad, user) .. " was hurt by\nthe AFTERMATH!")
          if M.tryFaintUser then M:tryFaintUser() end
          did = true
        elseif not targetDown then
          if ta == "JUSTIFIED" and mt == ID.DARK then did = raise(ad, target, "attack", 1) == "worked"
          elseif ta == "RATTLED" and (mt == ID.BUG or mt == ID.GHOST or mt == ID.DARK) then
            did = raise(ad, target, "speed", 1) == "worked"
          elseif ta == "STAMINA" then did = raise(ad, target, "defense", 1) == "worked"
          elseif ta == "WEAK_ARMOR" and okT and Types.isPhysical(mt) then
            raise(ad, target, "defense", -1, { user = true, certain = true })
            did = raise(ad, target, "speed", 2) == "worked"
          end
        end
        -- the user's ability
        if ua == "POISON_TOUCH" and touched and not targetDown and not ad:status(target)
            and ad:roll(1, 100) <= 30 then
          did = Ab.applyStatus(ad, user, target, "PSN", false, M) or did
        elseif (ua == "MOXIE" or ua == "BEAST_BOOST") and targetDown and ad:hp(user) > 0 then
          local stat = ua == "MOXIE" and "attack" or bestStat(user)
          did = raise(ad, user, stat, 1) == "worked" or did
        end
        return did
      end)
      if ok then return acted or r end
      return r
    end
  end

  -- stat changes
  if need.stat and not Secondary.__nationalDexAbilities then
    Secondary.__nationalDexAbilities = true
    local changeStat = Secondary.changeStat
    local busy = false
    Secondary.changeStat = function(ad, battler, stat, delta, flags, ...)
      flags = flags or {}
      if not RealAbilities._on or busy or not battler then return changeStat(ad, battler, stat, delta, flags, ...) end
      local ab = abilityOf(ad, battler)
      if delta < 0 and not flags.certain and not flags.user then
        local blocks = (ab == "BIG_PECKS" and stat == "defense")
          or (ab == "FLOWER_VEIL" and hasType(battler, ID.GRASS))
        if blocks then
          if flags.allowPtr then
            ad:sayText("STRINGID_PKMNSXPREVENTSYLOSS", {
              scrActive = battler, scrActiveAbility = idOf[ab], buff1 = Secondary.statName(stat),
            })
          end
          return "blocked"
        end
      end
      local res = changeStat(ad, battler, stat, delta, flags, ...)
      if res == "worked" and delta < 0 and not flags.user and (ab == "DEFIANT" or ab == "COMPETITIVE") then
        busy = true
        safe(changeStat, ad, battler, ab == "DEFIANT" and "attack" or "spAtk", 2, {})
        busy = false
      end
      return res
    end
  end

  -- status moves
  if need.status and not Status.__nationalDexAbilities then
    Status.__nationalDexAbilities = true
    local function guarded(ad, target, status)
      local ab = abilityOf(ad, target)
      if ab == "LEAF_GUARD" and weather(ad) == "SUN" then return ab end
      if ab == "SWEET_VEIL" and status == "SLP" then return ab end
      if ab == "FLOWER_VEIL" and hasType(target, ID.GRASS) then return ab end
      return nil
    end
    local function say(ad, target, ab)
      ad:say(prefixed(ad, target) .. " is protected\nby " .. tostring(byKey[ab] and byKey[ab].name or ab) .. "!")
    end
    local sleepCheck = Status.cantMakeAsleep
    Status.cantMakeAsleep = function(ctx, target, ...)
      if RealAbilities._on and ctx and ctx.adapter and target then
        local ab = guarded(ctx.adapter, target, "SLP")
        if ab then say(ctx.adapter, target, ab) return true end
      end
      return sleepCheck(ctx, target, ...)
    end
    -- burn / poison / toxic / paralysis moves: the effect registry holds the Status functions
    -- themselves (captured at load), so the guard sits on Effects.run, which every status move
    -- goes through
    local okE, Effects = pcall(require, "src.core.game3.battle.effects")
    local BY_EFFECT = { EXP_BURN_EFFECT = "BRN", EXP_POISON_EFFECT = "PSN", EXP_TOXIC_EFFECT = "TOX",
                        EXP_PARALYZE_EFFECT = "PAR" }
    if okE and type(Effects) == "table" and type(Effects.run) == "function" and not Effects.__nationalDexAbilities then
      Effects.__nationalDexAbilities = true
      local run = Effects.run
      Effects.run = function(id, ad, user, target, ...)
        local status = BY_EFFECT[id]
        if status and RealAbilities._on and ad and target and target ~= user then
          local okG, ab = pcall(guarded, ad, target, status)
          if okG and ab then
            if ad:status(target) == nil then say(ad, target, ab) return true end
          end
        end
        return run(id, ad, user, target, ...)
      end
    end
  end

  RealAbilities._on = true
  local n = 0
  for _ in pairs(byKey) do n = n + 1 end
  if log then log:info("real abilities: %d installed, on %d species and forms", n, count) end
  return true
end

RealAbilities.QUIET = QUIET
return RealAbilities
