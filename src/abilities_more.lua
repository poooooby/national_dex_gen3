-- The rest of the newer abilities on Gen 3 (data/abilities.lua ids 130+; src/abilities.lua names
-- them, sets the species' ability pairs and answers `abilityOf`, as for its own 52).
--
-- Every one acts through a wrap of the battle's own functions or a battle hook, the way
-- src/abilities.lua's do. Battle state lives on the battlers and the battle (fields `__ndxAb*`),
-- never on the party Pokemon (it would be saved). The process-wide wraps read the newest install
-- through a hub (`Abilities.__ndxMoreHub`: games switch in-process).
--   hooks (at load)
--     battle.damage      power and damage: Sheer Force, the type and move-kind boosters, the Ruin
--                        four, the auras, Stakeout, Supreme Overlord, Fur Coat, Punk Rock, Water
--                        Bubble, Purifying Salt, Shadow Shield, Disguise, Ice Face, Anger Point
--     battle.crit        Merciless          battle.accuracy   Victory Star, Tangled Feet, Wonder
--                                                              Skin, No Guard
--     battle.turn_order  Quick Draw, Mycelium Might (Triage: RealAbilities.priorityOf)
--     battle.fainted     Soul-Heart
--   engine wraps (on game.ready)
--     Adapter.new        abilityOf (Neutralizing Gas, Mold Breaker & co.), canApplyStatus (the
--                        status guards, Corrosion), applyHpLoss / sayText (Magic Guard, Overcoat)
--     Damage.calc        Unaware, Scrappy / Mind's Eye, Infiltrator's screens, Refrigerate, Aura
--                        Wheel in Hangry Mode
--     Hit.run            Sheer Force, Skill Link, Infiltrator, Unseen Fist, the priority blockers,
--                        Stance Change, Gulp Missile, Disguise's break, Dancer
--     Effects.run        the priority blockers, Good as Gold, Aroma Veil, Overcoat's powder,
--                        Corrosion, Stance Change, Dancer
--     Ctx.accuracyCheck  No Guard, Unaware / Mind's Eye (accuracy and evasion stages)
--     Ab.switchIn        the entry abilities (Download, Forewarn, the surges, Intrepid Sword...)
--     Ab.absorb          Well-Baked Body, Earth Eater, Wind Rider
--     Ab.onDamage        the abilities a hit sets off (on either side)
--     Ab.endTurn         Bad Dreams, Slow Start, Hunger Switch, Cud Chew, the form checks
--     Ab.switchOut       Zero to Hero
--     Ab.runIntimidate   Scrappy, Guard Dog, Full Metal Body, Contrary, Simple
--     Secondary.changeStat / withChance   Contrary, Simple, Full Metal Body, Mind's Eye,
--                        Opportunist; Sheer Force
--     HeldItems.of / has / normal         Klutz, Unnerve, Gluttony, Gorilla Tactics; Ripen,
--                        Cheek Pouch, Cud Chew
--     Engine.resolveMove Steadfast         Engine.selfHit   (Magic Guard lets confusion hurt)
--     RealAbilities.speedModifiers / priorityOf   Unburden, Slow Start, Surge Surfer; Triage
--     the held items' core (src/held/gen3.lua)    Klutz, Unnerve, Gluttony, Ripen, Cheek
--                        Pouch, Magic Guard for the newer items
-- Forms that change in battle (Stance Change, Schooling, Shields Down, Zero to Hero, Ice Face)
-- keep their picture: their stats go on `__ndxStat`, which src/move_rules.lua's damage and
-- RealAbilities' turn order already read. Everything runs protected: an error leaves the game's
-- own result.

local More = {}

local function set(list)
  local t = {}
  for _, k in ipairs(list) do t[k] = true end
  return t
end

local function letters(s) return (tostring(s or ""):upper():gsub("[^%w]", "")) end

-- set aside by Mold Breaker / Neutralizing Gas never
local UNBREAKABLE = set{ "SHADOW_SHIELD", "PRISM_ARMOR", "FULL_METAL_BODY", "COMATOSE", "MULTITYPE",
  "STANCE_CHANGE", "SCHOOLING", "SHIELDS_DOWN", "DISGUISE", "ICE_FACE", "ZERO_TO_HERO", "AS_ONE_GLASTRIER",
  "AS_ONE_SPECTRIER", "NEUTRALIZING_GAS", "GULP_MISSILE" }
-- never copied or replaced (Mummy, Wandering Spirit)
local FIXED = set{ "MULTITYPE", "STANCE_CHANGE", "SCHOOLING", "SHIELDS_DOWN", "DISGUISE", "ICE_FACE",
  "ZERO_TO_HERO", "COMATOSE", "AS_ONE_GLASTRIER", "AS_ONE_SPECTRIER", "GULP_MISSILE", "MUMMY",
  "LINGERING_AROMA", "NEUTRALIZING_GAS", "TRACE", "WONDER_GUARD", "FORECAST", "HUNGER_SWITCH" }
local MOLD = set{ "MOLD_BREAKER", "TURBOBLAZE", "TERAVOLT", "MYCELIUM_MIGHT" }
local PRIORITY_BLOCK = set{ "QUEENLY_MAJESTY", "DAZZLING", "ARMOR_TAIL" }
local MENTAL = set{ "TAUNT", "TORMENT", "ENCORE", "DISABLE", "HEALBLOCK", "ATTRACT" }
local HEALING = set{ "ABSORB", "MEGADRAIN", "GIGADRAIN", "LEECHLIFE", "DRAINPUNCH", "HORNLEECH",
  "PARABOLICCHARGE", "DRAININGKISS", "OBLIVIONWING", "DREAMEATER", "RECOVER", "SOFTBOILED", "MILKDRINK",
  "SLACKOFF", "ROOST", "MOONLIGHT", "MORNINGSUN", "SYNTHESIS", "REST", "WISH", "HEALORDER", "SHOREUP",
  "STRENGTHSAP", "JUNGLEHEALING", "LIFEDEW", "LUNARBLESSING", "HEALPULSE", "FLORALHEALING", "PURIFY",
  "SWALLOW", "HEALINGWISH", "LUNARDANCE", "MATCHAGOTCHA", "BITTERBLADE" }
-- the added-effect kinds Sheer Force takes away (EffectIds.SECONDARY's `eff`)
local SHEER = set{ "POISON", "BURN", "FREEZE", "PARALYSIS", "FLINCH", "TRI_ATTACK", "ATK_MINUS_1",
  "DEF_MINUS_1", "SPD_MINUS_1", "SP_ATK_MINUS_1", "SP_DEF_MINUS_1", "ACC_MINUS_1", "CONFUSION",
  "DEF_PLUS_1", "ATK_PLUS_1", "ALL_STATS_UP", "TOXIC" }
-- the in-battle forms' base stats (attack, defense, spAtk, spDef, speed)
local FORM = {
  BLADE = { atk = 140, def = 50, spa = 140, spd = 50, spe = 60 },      -- Aegislash
  SHIELD = { atk = 50, def = 140, spa = 50, spd = 140, spe = 60 },
  SCHOOL = { atk = 140, def = 130, spa = 140, spd = 135, spe = 30 },   -- Wishiwashi
  CORE = { atk = 100, def = 60, spa = 100, spd = 60, spe = 120 },      -- Minior
  HERO = { atk = 160, def = 97, spa = 106, spd = 87, spe = 100 },      -- Palafin
  NOICE = { atk = 80, def = 70, spa = 65, spd = 50, spe = 130 },       -- Eiscue
}
local INDIRECT_BEFORE = set{ "STRINGID_PKMNBUFFETEDBYSANDSTORM", "STRINGID_PKMNPELTEDBYHAIL",
  "STRINGID_PKMNHURTBYPOISON", "STRINGID_PKMNHURTBYBURN", "STRINGID_PKMNLOCKEDINNIGHTMARE",
  "STRINGID_PKMNAFFLICTEDBYCURSE", "STRINGID_PKMNHURTBY", "STRINGID_PKMNCRASHED" }
local INDIRECT_AFTER = set{ "STRINGID_PKMNHITWITHRECOIL", "STRINGID_PKMNHURTBYSPIKES",
  "STRINGID_PKMNSAPPEDBYLEECHSEED", "STRINGID_ITSUCKEDLIQUIDOOZE", "STRINGID_PKMNHURTSWITH" }
local WEATHER_CHIP = set{ "STRINGID_PKMNBUFFETEDBYSANDSTORM", "STRINGID_PKMNPELTEDBYHAIL" }

local function safe(fn, ...)
  local ok, a, b = pcall(fn, ...)
  if ok then return a, b end
  return nil
end

local function wrapText(s)
  local out, line = {}, ""
  for word in tostring(s):gmatch("%S+") do
    if line == "" then line = word
    elseif #line + 1 + #word <= 26 then line = line .. " " .. word
    else out[#out + 1] = line; line = word end
  end
  if line ~= "" then out[#out + 1] = line end
  return table.concat(out, "\n")
end

local function contact(move) return ((tonumber(move and move.flags) or 0) % 2) == 1 end

-- ------------------------------------------------------------------ the context
-- Built by install(); the hooks and wraps read it through the hub.
local function newContext(opts)
  local require, log = opts.require, opts.log
  local C = { require = require, log = log, names = {}, flags = opts.flags or {}, RA = opts.abilities,
    MoveField = opts.moveField, MoveEffects = opts.moveEffects, MoveRules = opts.moveRules }
  for _, d in ipairs((opts.data or {}).defs or {}) do C.names[d.key] = d.name end
  local function req(name) local ok, m = pcall(require, name); return ok and m or nil end
  C.Types = req("src.core.game3.battle.types")
  C.ID = (C.Types and C.Types.ID) or {}
  C.Secondary = req("src.core.game3.battle.effects.secondary")
  C.State = req("src.core.game3.battle.state")
  C.Moves = req("src.core.game3.battle.moves")
  C.HeldItems = req("src.core.game3.battle.held_items")
  C.ItemsData = req("src.core.game3.items_data")
  C.Pokemon = req("src.core.game3.pokemon")
  C.Engine = req("src.core.game3.battle.engine")
  C.Ab = req("src.core.game3.battle.abilities")
  C.EffectIds = req("src.core.game3.battle.effect_ids")

  function C.ab(ad, b)
    if not (ad and b) then return nil end
    local ok, n = pcall(ad.abilityOf, ad, b)
    return ok and n or nil
  end
  function C.nameOf(key)
    if C.names[key] then return C.names[key] end
    local ok, n = pcall(C.Ab.name, key)
    return ok and n or tostring(key or ""):gsub("_", " ")
  end
  function C.who(ad, b)
    if C.State and C.State.prefixedName then
      local ok, n = pcall(C.State.prefixedName, ad._st, b)
      if ok and n then return n end
    end
    return (ad.displayName and ad:displayName(b)) or "POKeMON"
  end
  function C.say(ad, fmt, ...) ad:say(wrapText(string.format(fmt, ...))) end
  function C.stat(ad, b, stat, delta, flags)
    if not (C.Secondary and b and b.stages) then return nil end
    return safe(C.Secondary.changeStat, ad, b, stat, delta, flags or {})
  end
  function C.hasType(b, t) return b ~= nil and t ~= nil and (b.type1 == t or b.type2 == t) end
  -- a move's number and letters-only name ("WATERPULSE"), from a move record or a number
  function C.moveNum(move, num)
    num = tonumber(num)
    if num then return num end
    if type(move) == "table" then
      num = tonumber(move.numId) or tonumber(move.num) or tonumber(move.index)
      if not num and move.id and C.Moves and C.Moves.numForName then num = safe(C.Moves.numForName, move.id) end
    elseif move ~= nil then
      num = tonumber(move)
      if not num and C.Moves and C.Moves.numForName then num = safe(C.Moves.numForName, move) end
    end
    return num
  end
  function C.moveKey(move, num)
    num = C.moveNum(move, num)
    local name = num and C.Moves and C.Moves.constName and safe(C.Moves.constName, num)
    if not name and type(move) == "table" then name = move.id end
    return letters(name)
  end
  function C.flag(kind, move, num)
    local list = C.flags[kind]
    return list ~= nil and list[C.moveKey(move, num)] == true
  end
  function C.moveRec(num)
    return num and C.Moves and safe(C.Moves.get, num) or nil
  end
  function C.isStatusMove(move) return (tonumber(move and move.power) or 0) == 0 end
  function C.physical(mtype) return C.Types and C.Types.isPhysical and C.Types.isPhysical(tonumber(mtype) or 0) or false end
  function C.weather(ad)
    local st = ad and ad._st
    if not st then return nil end
    local okR, Rules = pcall(require, "src.core.game3.battle.rules")
    if okR and Rules.weather and Rules.weather.effective then
      local ok, w = pcall(Rules.weather.effective, st, ad)
      if ok then return w end
    end
    return st.weather
  end
  function C.terrain(ad)
    local f = ad and ad._st and ad._st.__ndxField
    return f and (f.terrainTurns or 0) > 0 and f.terrain or nil
  end
  function C.foes(ad, b)
    local list = {}
    for _, x in ipairs(ad:activeBattlers() or {}) do
      if x.side ~= b.side and ad:hp(x) > 0 then list[#list + 1] = x end
    end
    return list
  end
  function C.anyActive(ad, key, except)
    for _, x in ipairs(ad:activeBattlers() or {}) do
      if x ~= except and ad:hp(x) > 0 and C.ab(ad, x) == key then return x end
    end
    return nil
  end
  function C.item(b) return tonumber(b and b.item) or 0 end
  function C.isBerry(item)
    return item > 0 and C.ItemsData and C.ItemsData.isBerry and safe(C.ItemsData.isBerry, item) or false
  end
  function C.setItem(b, item)
    b.item = item
    if item == 0 then b.expUsedHeldItem = nil end
    if C.Secondary and C.Secondary.persistItem then pcall(C.Secondary.persistItem, b, item) end
  end
  function C.itemName(item)
    local ok, n = pcall(function() return C.ItemsData.displayName(item) end)
    return ok and n and tostring(n):upper() or "ITEM"
  end
  -- an ability the battle treats as its own (Skill Swap's slot: the engine's traced ability)
  function C.setAbility(b, key)
    b.expTracedAbility = key
    b.expAbilitySuppressed = nil
  end
  -- a form's stats from its base stats and the Pokemon's own IVs, EVs, level and nature
  function C.formStats(b, base)
    local mon = b.mon or {}
    local level = tonumber(mon.level) or 50
    local ivs, evs = mon.ivs or {}, mon.evs or {}
    local nature = (tonumber(mon.personality) or 0) % 25
    local up, down = math.floor(nature / 5), nature % 5
    local order = { "atk", "def", "spe", "spa", "spd" }
    local out = {}
    for i, k in ipairs(order) do
      local n = math.floor(((2 * base[k] + (tonumber(ivs[k]) or 0) + math.floor((tonumber(evs[k]) or 0) / 4)) * level) / 100) + 5
      local mul = 1
      if up ~= down then
        if up == i - 1 then mul = 1.1 elseif down == i - 1 then mul = 0.9 end
      end
      out[k] = math.floor(n * mul)
    end
    return { attack = out.atk, defense = out.def, speed = out.spe, spAtk = out.spa, spDef = out.spd }
  end
  function C.setForm(b, base)
    b.__ndxStat = base and C.formStats(b, base) or nil
  end
  -- switching a Pokemon out (the player picks the next one; the foe takes its best)
  function C.switchOut(ad, b)
    local E, st = C.Engine, ad._st
    if not (E and st) then return nil end
    if st.wild and b.side == "enemy" then
      ad:pushEvent({ kind = "switch_out", side = b.side, reason = "flee" })
      st.over, st.result, st.endReason = true, "run", "fled"
      ad:pushEvent({ kind = "end", result = "run", reason = "fled" })
      C.say(ad, "%s fled from battle!", C.who(ad, b))
      return nil
    end
    local who = st.double and b.id or b.side
    local candidates = E.switchCandidates(st, who)
    if #candidates == 0 then return nil end
    local slot = candidates[1]
    if type(st.batonPassChooser) == "function" then
      local ok, v = pcall(st.batonPassChooser, b.side, candidates)
      for _, c in ipairs(candidates) do if ok and c == tonumber(v) then slot = c end end
    elseif (st.link or b.side == "player") and st.interactiveChoices and coroutine.running() then
      local v = tonumber(coroutine.yield({ kind = "baton_pass", side = b.side, battler = b.id, candidates = candidates }))
      for _, c in ipairs(candidates) do if c == v then slot = c end end
    elseif b.side == "enemy" then
      local pick = E.mostSuitableMon(st, ad, st.double and b.id or "enemy")
      for _, c in ipairs(candidates) do if c == pick then slot = c end end
    end
    local nb = E.performSwitch(st, ad, who, slot, { reason = "switch" })
    if nb then
      local okS, SwitchSeq = pcall(require, "src.core.game3.battle.switch_seq")
      local okT, BattleText = pcall(require, "src.core.game3.battle.battle_text")
      if okS and okT then
        local fill = SwitchSeq.switchInFill(st, nb)
        local text = BattleText.get(BattleText.SWITCHINMON, fill)
        ad:pushEvent({ kind = "msg", text = text, wait = 0, id = (BattleText.key(BattleText.SWITCHINMON, fill)) })
        ad._say(text)
      end
      E.switchInEffects(st, ad, nb, { spikes = true, deferIntimidate = true })
    end
    return nb
  end
  return C
end

-- ------------------------------------------------------------------ hooks (at load)
function More.hooks(mod)
  local function ctx() return More._ctx end
  local Battle
  local function adapter()
    if not Battle then
      local C = ctx()
      local ok, B = pcall(C and C.require or require, "src.core.game3.battle")
      Battle = ok and B or nil
    end
    return Battle and Battle._adapter
  end

  -- damage: the final number
  mod.hooks:wrap("battle.damage", function(nextFn, c)
    local C = ctx()
    local dmg, info = nextFn(c)
    if not (C and type(c) == "table" and type(info) == "table" and type(c.user) == "table"
        and type(c.target) == "table") then return dmg, info end
    local ok, d = pcall(More.damage, C, adapter(), c, tonumber(dmg) or 0, info)
    if ok and d then return d, info end
    return dmg, info
  end)

  mod.hooks:wrap("battle.crit", function(nextFn, c)
    local C = ctx()
    if C and type(c) == "table" and type(c.attacker) == "table" and type(c.target) == "table" then
      local ad = adapter()
      if C.ab(ad, c.attacker) == "MERCILESS" and ad then
        local s = ad:status(c.target)
        if s == "PSN" or s == "TOX" then return true end
      end
    end
    return nextFn(c)
  end)

  mod.hooks:wrap("battle.accuracy", function(nextFn, c)
    local C = ctx()
    if C and type(c) == "table" and tonumber(c.accuracy) and type(c.user) == "table" then
      local ad = adapter()
      local ua, ta = C.ab(ad, c.user), C.ab(ad, c.target)
      if ua == "NO_GUARD" or ta == "NO_GUARD" then
        c.accuracy = 100
      else
        if ua == "VICTORY_STAR" then c.accuracy = math.floor(c.accuracy * 11 / 10) end
        if ta == "TANGLED_FEET" and c.target and (c.target.confusionTurns or 0) > 0 then
          c.accuracy = math.floor(c.accuracy / 2)
        end
        if ta == "WONDER_SKIN" and c.target ~= c.user and C.isStatusMove(c.move) then
          c.accuracy = math.min(c.accuracy, 50)
        end
      end
    end
    return nextFn(c)
  end)

  -- turn order inside a priority bracket: Quick Draw first, Mycelium Might's status moves last
  mod.hooks:wrap("battle.turn_order", function(nextFn, a, aMove, b, bMove, tctx)
    local C = ctx()
    if not (C and a and b and aMove and bMove) then return nextFn(a, aMove, b, bMove, tctx) end
    local ok, decided = pcall(function()
      local ad = adapter()
      local RA = C.RA
      local pa = RA and RA.priorityOf and RA.priorityOf(ad, a, aMove) or tonumber(aMove.priority) or 0
      local pb = RA and RA.priorityOf and RA.priorityOf(ad, b, bMove) or tonumber(bMove.priority) or 0
      if pa ~= pb then return nil end
      local st = ad and ad._st
      local turn = st and st.turn or 0
      local function drew(x, mv)
        if C.ab(ad, x) ~= "QUICK_DRAW" or C.isStatusMove(mv) then return false end
        local q = x.__ndxAbQuickDraw
        if not (q and q.turn == turn) then
          q = { turn = turn, yes = ad:roll(1, 100) <= 30 }
          x.__ndxAbQuickDraw = q
          if q.yes then C.say(ad, "%s's QUICK DRAW let it move first!", C.who(ad, x)) end
        end
        return q.yes
      end
      local qa, qb = drew(a, aMove), drew(b, bMove)
      if qa ~= qb then return qa end
      local ma = C.ab(ad, a) == "MYCELIUM_MIGHT" and C.isStatusMove(aMove)
      local mb = C.ab(ad, b) == "MYCELIUM_MIGHT" and C.isStatusMove(bMove)
      if ma ~= mb then return mb end
      return nil
    end)
    if ok and decided ~= nil then return decided end
    return nextFn(a, aMove, b, bMove, tctx)
  end)

  -- Soul-Heart: any faint
  mod.events:on("battle.fainted", function(ev)
    local C = ctx()
    local ad = adapter()
    if not (C and ad and type(ev) == "table" and type(ev.battler) == "table") then return end
    pcall(function()
      for _, x in ipairs(ad:activeBattlers() or {}) do
        if x ~= ev.battler and ad:hp(x) > 0 and C.ab(ad, x) == "SOUL_HEART" then C.stat(ad, x, "spAtk", 1) end
      end
    end)
  end)
end

-- ------------------------------------------------------------------ the damage hook
-- c: the battle.damage call (user, target, move view, moveNum); info: the engine's result
function More.damage(C, ad, c, dmg, info)
  local u, t = c.user, c.target
  local ua, ta = C.ab(ad, u), C.ab(ad, t)
  local num = tonumber(c.moveNum)
  -- Disguise / Ice Face: the first (physical) hit is taken by the disguise
  if dmg > 0 and t ~= u then
    if ta == "DISGUISE" and not t.__ndxAbBusted and (tonumber(info.effectiveness) or 1) > 0 then
      t.__ndxAbBusted, t.__ndxAbBustNow = true, true
      return 0
    end
    if ta == "ICE_FACE" and not t.__ndxAbNoice and info.physical and (tonumber(info.effectiveness) or 1) > 0 then
      t.__ndxAbNoice, t.__ndxAbIceBreak = true, true
      return 0
    end
  end
  if dmg <= 0 or info.fixed or info.setDamage or (tonumber(info.effectiveness) or 1) <= 0 then return dmg end
  local ID = C.ID
  local mt = tonumber(info.moveType) or tonumber(c.move and c.move.type) or 0
  local phys = info.physical
  if phys == nil then phys = C.physical(mt) end
  local m = 1
  -- the attacker's
  if u.__ndxAbSheer then m = m * 1.3 end
  if ua == "MEGA_LAUNCHER" and C.flag("pulse", c.move, num) then m = m * 1.5 end
  if ua == "SHARPNESS" and C.flag("slicing", c.move, num) then m = m * 1.5 end
  if ua == "PUNK_ROCK" and C.flag("sound", c.move, num) then m = m * 1.3 end
  if ua == "STEELWORKER" and mt == ID.STEEL then m = m * 1.5 end
  if ua == "TRANSISTOR" and mt == ID.ELECTRIC then m = m * 1.3 end
  if ua == "DRAGONS_MAW" and mt == ID.DRAGON then m = m * 1.5 end
  if ua == "WATER_BUBBLE" and mt == ID.WATER then m = m * 2 end
  if ua == "REFRIGERATE" and u.__ndxAbRefrigerated then m = m * 1.2 end
  if ua == "GORILLA_TACTICS" and phys then m = m * 1.5 end
  if ua == "DEFEATIST" and ad:hp(u) * 2 <= ad:maxHp(u) then m = m * 0.5 end
  if ua == "SLOW_START" and phys and (u.__ndxAbSlowStart or 0) > 0 then m = m * 0.5 end
  if ua == "FLOWER_GIFT" and phys and C.weather(ad) == "SUN" then m = m * 1.5 end
  if ua == "ORICHALCUM_PULSE" and phys and C.weather(ad) == "SUN" then m = m * 4 / 3 end
  if ua == "HADRON_ENGINE" and not phys and C.terrain(ad) == "ELECTRIC" then m = m * 4 / 3 end
  if ua == "STAKEOUT" and ad._st and t.__ndxAbEntered == ad._st.turn then m = m * 2 end
  if ua == "SUPREME_OVERLORD" then
    local n = 0
    for _, mon in ipairs(ad:partyMons(u) or {}) do
      if type(mon) == "table" and (tonumber(mon.hp) or 1) <= 0 and mon ~= u.mon then n = n + 1 end
    end
    m = m * (1 + 0.1 * math.min(5, n))
  end
  -- the field's: the Ruin four, the auras
  if phys then
    if C.anyActive(ad, "TABLETS_OF_RUIN", u) then m = m * 0.75 end
    if C.anyActive(ad, "SWORD_OF_RUIN", t) then m = m / 0.75 end
  else
    if C.anyActive(ad, "VESSEL_OF_RUIN", u) then m = m * 0.75 end
    if C.anyActive(ad, "BEADS_OF_RUIN", t) then m = m / 0.75 end
  end
  if (mt == ID.FAIRY and C.anyActive(ad, "FAIRY_AURA")) or (mt == ID.DARK and C.anyActive(ad, "DARK_AURA")) then
    m = m * (C.anyActive(ad, "AURA_BREAK") and 0.75 or 4 / 3)
  end
  -- the target's
  if t ~= u then
    if ta == "FUR_COAT" and phys then m = m * 0.5 end
    if ta == "PUNK_ROCK" and C.flag("sound", c.move, num) then m = m * 0.5 end
    if ta == "WATER_BUBBLE" and mt == ID.FIRE then m = m * 0.5 end
    if ta == "PURIFYING_SALT" and mt == ID.GHOST then m = m * 0.5 end
    if ta == "SHADOW_SHIELD" and ad:hp(t) >= ad:maxHp(t) then m = m * 0.5 end
    if ta == "FLOWER_GIFT" and not phys and C.weather(ad) == "SUN" then m = m / 1.5 end
    if ta == "ANGER_POINT" and info.critical then t.__ndxAbCritTaken = true end
  end
  if m == 1 then return dmg end
  return math.max(1, math.floor(dmg * m))
end

-- ------------------------------------------------------------------ install (game.ready)
-- opts: { data = data/abilities.lua, require, log, flags = data/move_flags.lua, abilities =
-- RealAbilities, moveField, moveEffects, held = src/held/gen3.lua's module }
function More.install(opts)
  local C = newContext(opts)
  local require, log = opts.require, opts.log
  local Ab, Secondary, Engine, HeldItems = C.Ab, C.Secondary, C.Engine, C.HeldItems
  local okA, Adapter = pcall(require, "src.core.game3.battle.adapter")
  local okD, Damage = pcall(require, "src.core.game3.battle.damage")
  local okH, Hit = pcall(require, "src.core.game3.battle.effects.hit")
  local okE, Effects = pcall(require, "src.core.game3.battle.effects")
  if not (okA and okD and okH and okE and Ab and Secondary and Engine) then
    if log then log:warn("the other newer abilities are off: the battle engine's functions were not found") end
    return false
  end
  local hub = Ab.__ndxMoreHub or {}
  Ab.__ndxMoreHub = hub
  hub.C = C
  More._ctx = C
  local ID = C.ID
  local ab, who, say, stat = C.ab, C.who, C.say, C.stat

  -- ---------------------------------------------------------------- the adapter
  if not Adapter.__ndxAbMore then
    Adapter.__ndxAbMore = true
    local new = Adapter.new
    Adapter.new = function(...)
      local a = new(...)
      if type(a) ~= "table" then return a end
      -- whose ability counts: Neutralizing Gas quiets the rest, Mold Breaker's target has none
      local of = a.abilityOf
      local function raw(self, b) return of(self, b) end
      a.__ndxRawAbility = raw
      a.abilityOf = function(self, b)
        local name = of(self, b)
        local X = hub.C
        if not (X and name and b) or UNBREAKABLE[name] then return name end
        local st = self._st
        if st then
          local mb = st.__ndxAbMold
          if mb and mb.user ~= b and mb.user.side ~= b.side then return nil end
          if st.__ndxAbGas and name ~= "NEUTRALIZING_GAS" then
            for _, x in ipairs(self:activeBattlers() or {}) do
              if x ~= b and self:hp(x) > 0 and of(self, x) == "NEUTRALIZING_GAS" then return nil end
            end
          end
        end
        return name
      end
      -- status: the guards, and Corrosion's poison on any type
      local can = a.canApplyStatus
      a.canApplyStatus = function(self, b, status, source, o)
        local X = hub.C
        if X and b then
          local guard = More.statusGuard(X, self, b, status)
          if guard then return false, "ability" end
        end
        local ok, why = can(self, b, status, source, o)
        if not ok and why == "type" and X and (status == "PSN" or status == "TOX") and source ~= b
            and type(source) == "table" and X.ab(self, source) == "CORROSION" then
          local o2 = {}
          for k, v in pairs(o or {}) do o2[k] = v end
          local t1, t2 = b.type1, b.type2
          b.type1, b.type2 = ID.NORMAL or 0, nil
          local ok2, why2 = can(self, b, status, source, o2)
          b.type1, b.type2 = t1, t2
          return ok2, why2
        end
        return ok, why
      end
      -- Magic Guard / Overcoat: no indirect damage, nor its message
      local loss, sayText = a.applyHpLoss, a.sayText
      a.applyHpLoss = function(self, b, amount, o)
        if hub.C and type(b) == "table" and not (o and o.hit) then
          if b.__ndxAbSkipLoss then
            b.__ndxAbSkipLoss = nil
            return 0
          end
          if not b.__ndxAbAllowLoss and not hub.allowLoss and hub.C.ab(self, b) == "MAGIC_GUARD" then
            b.__ndxAbBlocked = true
            return 0
          end
          b.__ndxAbAllowLoss = nil
        end
        return loss(self, b, amount, o)
      end
      a.sayText = function(self, id, fill)
        local X = hub.C
        if X and type(fill) == "table" then
          local b = fill.atk or fill.scrActive
          if type(b) == "table" then
            local k = X.ab(self, b)
            if INDIRECT_BEFORE[id] and (k == "MAGIC_GUARD" or (k == "OVERCOAT" and WEATHER_CHIP[id])) and not hub.allowLoss then
              b.__ndxAbSkipLoss = true
              return nil
            end
            if INDIRECT_AFTER[id] and b.__ndxAbBlocked then
              b.__ndxAbBlocked = nil
              return nil
            end
            if id == "STRINGID_PKMNPERISHCOUNTFELL" then b.__ndxAbAllowLoss = true end
          end
        end
        return sayText(self, id, fill)
      end
      return a
    end
  end
  -- confusion and Destiny Bond still hurt a Magic Guard Pokemon
  if type(Engine.selfHit) == "function" and not Engine.__ndxAbMore then
    Engine.__ndxAbMore = true
    local selfHit = Engine.selfHit
    Engine.selfHit = function(...)
      hub.allowLoss = true
      local r = { pcall(selfHit, ...) }
      hub.allowLoss = nil
      if not r[1] then error(r[2], 0) end
      return (unpack or table.unpack)(r, 2)
    end
    -- Steadfast: a flinch raises SPEED
    -- Mold Breaker & co.: the foes' abilities are set aside for the whole move (Mycelium Might:
    -- for its status moves); Steadfast: a flinch raises SPEED
    local resolve = Engine.resolveMove
    Engine.resolveMove = function(user, target, moveId, slot, ad, st, out, o, ...)
      local X = hub.C
      if not (X and type(ad) == "table" and type(st) == "table") then
        return resolve(user, target, moveId, slot, ad, st, out, o, ...)
      end
      -- the battler the engine will resolve (a game passes a side or slot, as resolveMove takes)
      local who = user
      if type(who) ~= "table" and X.State and X.State.occupant then who = safe(X.State.occupant, st, user) end
      if type(who) ~= "table" then return resolve(user, target, moveId, slot, ad, st, out, o, ...) end
      local flinched = who.flinched
      local prev = st.__ndxAbMold
      local k = X.ab(ad, who)
      if MOLD[k or ""] then
        local rec = X.moveRec(X.moveNum(moveId))
        if k ~= "MYCELIUM_MIGHT" or X.isStatusMove(rec) then st.__ndxAbMold = { user = who } end
      end
      local r = { pcall(resolve, user, target, moveId, slot, ad, st, out, o, ...) }
      st.__ndxAbMold = prev
      if not r[1] then error(r[2], 0) end
      if flinched and not who.flinched and ad:hp(who) > 0 and X.ab(ad, who) == "STEADFAST" then
        pcall(X.stat, ad, who, "speed", 1)
      end
      return (unpack or table.unpack)(r, 2)
    end
  end

  -- ---------------------------------------------------------------- Damage.calc
  if not Damage.__ndxAbMore then
    Damage.__ndxAbMore = true
    local calc = Damage.calc
    Damage.calc = function(attacker, defender, moveId, o, ...)
      local X = hub.C
      local ad = type(o) == "table" and o.adapter
      if not (X and ad and type(attacker) == "table" and type(defender) == "table") then
        return calc(attacker, defender, moveId, o, ...)
      end
      local saved, o2 = {}, nil
      local function put(tbl, key, value)
        saved[#saved + 1] = { tbl, key, tbl[key] }
        tbl[key] = value
      end
      local function opt(key, value)
        if not o2 then
          o2 = {}
          for k, v in pairs(o) do o2[k] = v end
        end
        o2[key] = value
      end
      local okP = pcall(function()
        local ua, da = X.ab(ad, attacker), X.ab(ad, defender)
        local move = type(moveId) == "table" and moveId or X.moveRec(tonumber(moveId))
        local mtype = tonumber(o.moveType) or tonumber(move and move.type) or 0
        attacker.__ndxAbRefrigerated = nil
        -- Unaware: the other side's stages
        if ua == "UNAWARE" and defender.stages then
          put(defender.stages, "defense", 0)
          put(defender.stages, "spDef", 0)
        end
        if da == "UNAWARE" and attacker.stages and attacker ~= defender then
          put(attacker.stages, "attack", 0)
          put(attacker.stages, "spAtk", 0)
        end
        -- Scrappy / Mind's Eye: Normal and Fighting hit Ghost
        if (ua == "SCRAPPY" or ua == "MINDS_EYE") and (mtype == ID.NORMAL or mtype == ID.FIGHTING) then
          opt("foresight", true)
        end
        -- Infiltrator: no screens
        if ua == "INFILTRATOR" then
          opt("reflect", false)
          opt("lightScreen", false)
        end
        -- Refrigerate: Normal moves become Ice
        if ua == "REFRIGERATE" and mtype == ID.NORMAL and (tonumber(move and move.power) or 0) > 0 then
          opt("moveType", ID.ICE)
          attacker.__ndxAbRefrigerated = true
        end
        -- Aura Wheel in Hangry Mode
        if attacker.__ndxAbHangry and X.moveKey(move) == "AURAWHEEL" then opt("moveType", ID.DARK) end
      end)
      if not okP then o2 = nil end
      local r = { pcall(calc, attacker, defender, moveId, o2 or o, ...) }
      for i = #saved, 1, -1 do
        local s = saved[i]
        s[1][s[2]] = s[3]
      end
      if not r[1] then error(r[2], 0) end
      return (unpack or table.unpack)(r, 2)
    end
  end

  -- ---------------------------------------------------------------- around a move
  local function adNow()
    local ok, B = pcall(require, "src.core.game3.battle")
    return ok and B and B._adapter
  end
  -- Light Metal / Heavy Metal: the weight Low Kick and Grass Knot read
  if type(Damage.lowKickPower) == "function" and not Damage.__ndxAbMetal then
    Damage.__ndxAbMetal = true
    local lowKick = Damage.lowKickPower
    Damage.lowKickPower = function(dMon, defender, ...)
      local X, ad = hub.C, adNow()
      local k = X and ad and type(defender) == "table" and X.ab(ad, defender)
      if k == "LIGHT_METAL" or k == "HEAVY_METAL" then
        local w = tonumber(dMon and dMon.weight)
        if not w and X.Pokemon and X.Pokemon.dexEntry then
          local e = safe(X.Pokemon.dexEntry, tonumber(defender.species or (dMon and dMon.species)))
          w = e and tonumber(e.weight)
        end
        if w then
          local copy = {}
          for kk, v in pairs(dMon or {}) do copy[kk] = v end
          copy.weight = math.max(1, math.floor(w * (k == "LIGHT_METAL" and 0.5 or 2)))
          return lowKick(copy, defender, ...)
        end
      end
      return lowKick(dMon, defender, ...)
    end
  end

  -- whether a move's added effect is one Sheer Force takes away
  local function sheerMove(M)
    local eff = tonumber(M.effect) or tonumber(M.move and M.move.effect) or 0
    local spec = C.EffectIds and C.EffectIds.SECONDARY and C.EffectIds.SECONDARY[eff]
    if spec and SHEER[spec.eff] and not spec.certain then return true end
    local extra = C.MoveEffects and C.MoveEffects._specs and C.MoveEffects._specs[tonumber(M.mnum) or -1]
    if extra and extra.kind == "hit" then
      local ch = tonumber(extra.chance) or 100
      if (extra.foe or extra.self) and ch < 100 then return true end
      if extra.ailment and (tonumber(extra.ailmentChance) or 100) < 100 then return true end
      if extra.flinch then return true end
    end
    return false
  end
  -- the target's priority guard: a foe's move with raised priority fails
  local function priorityBlocked(ad, user, target, move)
    if not (target and target ~= user and user.side ~= target.side) then return false end
    local blocker
    for _, x in ipairs(ad:activeBattlers() or {}) do
      if x.side == target.side and ad:hp(x) > 0 and PRIORITY_BLOCK[ab(ad, x) or ""] then blocker = x end
    end
    if not blocker then return false end
    local RA = C.RA
    local p = RA and RA.priorityOf and RA.priorityOf(ad, user, move) or tonumber(move and move.priority) or 0
    if p <= 0 then return false end
    say(ad, "%s's %s makes the move fail!", who(ad, blocker), C.nameOf(ab(ad, blocker)))
    return true
  end
  -- Stance Change: Blade Forme to attack, Shield Forme for King's Shield
  local function stance(ad, user, move, num)
    if ab(ad, user) ~= "STANCE_CHANGE" then return end
    local key = C.moveKey(move, num)
    if key == "KINGSSHIELD" and user.__ndxAbBlade then
      user.__ndxAbBlade = nil
      C.setForm(user, FORM.SHIELD)
      say(ad, "Changed to Shield Forme!")
    elseif not C.isStatusMove(move) and not user.__ndxAbBlade then
      user.__ndxAbBlade = true
      C.setForm(user, FORM.BLADE)
      say(ad, "Changed to Blade Forme!")
    end
  end
  -- Dancer: another Pokemon's dance, danced again
  local function dance(ad, user, num, M)
    if hub.dancing or not (C.flag("dance", nil, num)) then return end
    for _, x in ipairs(ad:activeBattlers() or {}) do
      if x ~= user and ad:hp(x) > 0 and ab(ad, x) == "DANCER" and ad:hp(user) >= 0 then
        hub.dancing = true
        local target = ad:foeOf(x)
        local rec = C.moveRec(num)
        if rec and tonumber(rec.target) == 16 then target = x end
        say(ad, "%s joined in the dance!", who(ad, x))
        pcall(Engine.resolveMove, x, target, num, nil, ad, ad._st, M and M.out or {},
          { called = true, anim = M and M.anim, calledBy = num })
        hub.dancing = nil
      end
    end
  end
  -- the Ctx methods: No Guard, Unaware / Mind's Eye in the accuracy check; Unseen Fist
  local function patchCtx(M)
    local mt = getmetatable(M)
    local Ctx = mt and mt.__index
    if type(Ctx) ~= "table" or Ctx.__ndxAbMore or type(Ctx.accuracyCheck) ~= "function" then return end
    Ctx.__ndxAbMore = true
    local check, isProtected = Ctx.accuracyCheck, Ctx.isProtected
    Ctx.isProtected = function(self, ...)
      local X = hub.C
      if X and self.user and self.target and self.target ~= self.user and X.ab(self.adapter, self.user) == "UNSEEN_FIST"
          and contact(self.move) then return false end
      return isProtected(self, ...)
    end
    Ctx.accuracyCheck = function(self, mode, printFail, ...)
      local X = hub.C
      if not (X and self.user and self.target and mode == "normal") then return check(self, mode, printFail, ...) end
      local ad, u, t = self.adapter, self.user, self.target
      local ua, ta = X.ab(ad, u), X.ab(ad, t)
      if (ua == "NO_GUARD" or ta == "NO_GUARD") and not self:isProtected() then return not self:absorbed() end
      local saved = {}
      if ta == "UNAWARE" and u.stages and (u.stages.accuracy or 0) ~= 0 then
        saved[#saved + 1] = { u.stages, "accuracy", u.stages.accuracy }
        u.stages.accuracy = 0
      end
      if t.stages and ((ua == "UNAWARE" and (t.stages.evasion or 0) ~= 0)
          or (ua == "MINDS_EYE" and (t.stages.evasion or 0) > 0)) then
        saved[#saved + 1] = { t.stages, "evasion", t.stages.evasion }
        t.stages.evasion = 0
      end
      local r = { pcall(check, self, mode, printFail, ...) }
      for i = #saved, 1, -1 do saved[i][1][saved[i][2]] = saved[i][3] end
      if not r[1] then error(r[2], 0) end
      return (unpack or table.unpack)(r, 2)
    end
  end

  if not Hit.__ndxAbMore then
    Hit.__ndxAbMore = true
    local run = Hit.run
    Hit.run = function(M, ...)
      local X = hub.C
      if not (X and type(M) == "table" and M.adapter and M.user) then return run(M, ...) end
      local ad, user, target = M.adapter, M.user, M.target
      pcall(patchCtx, M)
      local num = tonumber(M.mnum)
      local ua = X.ab(ad, user)
      local okB, blocked = pcall(priorityBlocked, ad, user, target, M.move)
      if okB and blocked then
        if M.attackString then M:attackString() end
        if M.ppReduce then M:ppReduce() end
        M.failed, M.noEffect = true, true
        if M.anim then M.anim.missed = true end
        return
      end
      pcall(stance, ad, user, M.move, num)
      local st = ad._st
      local restore = {}
      pcall(function()
        if ua == "SHEER_FORCE" and sheerMove(M) then
          user.__ndxAbSheer = true
          local specs = X.MoveEffects and X.MoveEffects._specs
          local spec = specs and specs[num or -1]
          if spec then
            local copy = {}
            for k, v in pairs(spec) do copy[k] = v end
            if (tonumber(copy.chance) or 100) < 100 then copy.foe, copy.self = nil, nil end
            if (tonumber(copy.ailmentChance) or 100) < 100 then copy.ailment = nil end
            copy.flinch = nil
            specs[num] = copy
            restore[#restore + 1] = function() specs[num] = spec end
          end
        end
        -- Skill Link: 2-5 hits are 5
        local eff = tonumber(M.effect) or 0
        if ua == "SKILL_LINK" and type(M.move) == "table" then
          local multi = X.EffectIds and eff == X.EffectIds.MULTI_HIT
          if multi or type(M.move.hits) == "table" then
            local mv, e0 = M.move, M.effect
            local copy = {}
            for k, v in pairs(mv) do copy[k] = v end
            copy.hits = 5
            M.move = copy
            if multi then M.effect = X.EffectIds.HIT or 0 end
            restore[#restore + 1] = function() M.move, M.effect = mv, e0 end
          end
        end
        -- Infiltrator: through a Substitute
        if ua == "INFILTRATOR" and target and target ~= user and (target.substituteHP or 0) > 0 then
          local sub = target.substituteHP
          target.substituteHP = 0
          restore[#restore + 1] = function() if (target.substituteHP or 0) == 0 then target.substituteHP = sub end end
        end
        -- Innards Out / the half-HP abilities: the HP before the hit
        if target then
          target.__ndxAbHpBefore = ad:hp(target)
          target.__ndxAbStatusBefore = ad:status(target) or false
        end
      end)
      local r = { pcall(run, M, ...) }
      for i = #restore, 1, -1 do pcall(restore[i]) end
      user.__ndxAbSheer = nil
      if not r[1] then error(r[2], 0) end
      -- after the hit: Disguise and Ice Face broke, Gulp Missile's catch, the dance
      pcall(function()
        if target and target.__ndxAbBustNow then
          target.__ndxAbBustNow = nil
          say(ad, "Its disguise served it as a decoy!")
          if ad:hp(target) > 0 then
            hub.allowLoss = true
            ad:applyHpLoss(target, math.max(1, math.floor(ad:maxHp(target) / 8)))
            hub.allowLoss = nil
            say(ad, "%s's disguise was busted!", who(ad, target))
          end
        end
        if target and target.__ndxAbIceBreak then
          target.__ndxAbIceBreak = nil
          C.setForm(target, FORM.NOICE)
          say(ad, "%s's ICE FACE broke!", who(ad, target))
        end
        local key = X.moveKey(M.move, num)
        if ua == "GULP_MISSILE" and (key == "SURF" or key == "DIVE") and ad:hp(user) > 0 then
          user.__ndxAbGulp = ad:hp(user) * 2 > ad:maxHp(user) and "arrokuda" or "pikachu"
        end
        if not M.failed and not M.noEffect then dance(ad, user, num, M) end
      end)
      return (unpack or table.unpack)(r, 2)
    end
  end

  -- Sheer Force: the engine's own added effects (a hit's secondary chance)
  if type(Secondary.withChance) == "function" and not Secondary.__ndxAbMore then
    Secondary.__ndxAbMore = true
    local withChance = Secondary.withChance
    Secondary.withChance = function(M, eff, certainFlag, affectsUser, ...)
      if hub.C and type(M) == "table" and M.user and M.user.__ndxAbSheer and not certainFlag and SHEER[eff or ""] then
        return false
      end
      return withChance(M, eff, certainFlag, affectsUser, ...)
    end
    -- stat changes: Contrary, Simple, Full Metal Body, Mind's Eye, Opportunist
    local changeStat = Secondary.changeStat
    local busy = false
    Secondary.changeStat = function(ad, b, statName, delta, flags, ...)
      local X = hub.C
      flags = flags or {}
      if not (X and ad and type(b) == "table" and tonumber(delta)) or busy then
        return changeStat(ad, b, statName, delta, flags, ...)
      end
      local k = X.ab(ad, b)
      if k == "CONTRARY" then delta = -delta end
      if k == "SIMPLE" then delta = math.max(-6, math.min(6, delta * 2)) end
      if delta < 0 and not flags.certain and not flags.user then
        if k == "FULL_METAL_BODY" or (k == "MINDS_EYE" and statName == "accuracy") then
          if flags.allowPtr then say(ad, "%s's %s prevents stat loss!", X.who(ad, b), X.nameOf(k)) end
          return "blocked"
        end
      end
      local res = changeStat(ad, b, statName, delta, flags, ...)
      if res == "worked" and delta > 0 and not busy then
        for _, x in ipairs(ad:activeBattlers() or {}) do
          if x.side ~= b.side and ad:hp(x) > 0 and X.ab(ad, x) == "OPPORTUNIST" then
            busy = true
            pcall(changeStat, ad, x, statName, delta, { user = true })
            busy = false
          end
        end
      end
      return res
    end
  end

  -- status moves
  if not Effects.__ndxAbMore then
    Effects.__ndxAbMore = true
    local run = Effects.run
    local POWDER_FAIL = function(ad, target, key)
      say(ad, "It doesn't affect %s...", who(ad, target))
      return true
    end
    Effects.run = function(id, ad, user, target, move, moveId, moveCtx, ...)
      local X = hub.C
      local M = type(moveCtx) == "table" and moveCtx or nil
      if not (X and type(ad) == "table" and type(user) == "table") or (M and M.__ndxAbRan) then
        return run(id, ad, user, target, move, moveId, moveCtx, ...)
      end
      if M then M.__ndxAbRan = true end
      local num = tonumber(M and M.mnum) or tonumber(moveId)
      local mv = type(move) == "table" and move or X.moveRec(num)
      local key = X.moveKey(mv, num)
      if type(target) == "table" and target ~= user and target.side ~= user.side then
        local ta = X.ab(ad, target)
        local blocked
        local okB, pb = pcall(priorityBlocked, ad, user, target, mv)
        if okB and pb then blocked = true
        elseif ta == "GOOD_AS_GOLD" and X.isStatusMove(mv) then
          say(ad, "It doesn't affect %s...", who(ad, target)); blocked = true
        elseif ta == "AROMA_VEIL" and MENTAL[key] then
          say(ad, "%s is protected by an aromatic veil!", who(ad, target)); blocked = true
        elseif ta == "OVERCOAT" and X.flag("powder", mv, num) then
          blocked = POWDER_FAIL(ad, target)
        end
        if blocked then
          if M then M.failed = true end
          return true
        end
      end
      pcall(stance, ad, user, mv, num)
      -- self costs (Substitute, Belly Drum, Curse) still hurt a Magic Guard Pokemon
      local allow = hub.allowLoss
      hub.allowLoss = true
      -- Corrosion: a poison move works on Steel and Poison types
      local types
      if (id == "EXP_POISON_EFFECT" or id == "EXP_TOXIC_EFFECT") and type(target) == "table" and target ~= user
          and X.ab(ad, user) == "CORROSION" and (X.hasType(target, ID.POISON) or X.hasType(target, ID.STEEL)) then
        types = { target.type1, target.type2 }
        target.type1, target.type2 = ID.NORMAL or 0, nil
      end
      local r = { pcall(run, id, ad, user, target, move, moveId, moveCtx, ...) }
      if types then target.type1, target.type2 = types[1], types[2] end
      hub.allowLoss = allow
      if not r[1] then error(r[2], 0) end
      pcall(function()
        if M and not M.failed and r[2] ~= false then dance(ad, user, num, M) end
      end)
      return (unpack or table.unpack)(r, 2)
    end
  end
  -- the sleep guards (Status.cantMakeAsleep: Sleep Powder, Spore, Yawn)
  local okSt, Status = pcall(require, "src.core.game3.battle.effects.status")
  if okSt and type(Status.cantMakeAsleep) == "function" and not Status.__ndxAbMore then
    Status.__ndxAbMore = true
    local sleepCheck = Status.cantMakeAsleep
    Status.cantMakeAsleep = function(ctx, target, ...)
      local X = hub.C
      if X and ctx and ctx.adapter and target then
        local k = More.statusGuard(X, ctx.adapter, target, "SLP")
        if k then
          say(ctx.adapter, "%s is protected by %s!", who(ctx.adapter, target), X.nameOf(k))
          return true
        end
      end
      return sleepCheck(ctx, target, ...)
    end
  end
  -- abilities that pass on a status (Static, Synchronize): the guards too
  if type(Ab.applyStatus) == "function" and not Ab.__ndxAbMoreStatus then
    Ab.__ndxAbMoreStatus = true
    local applyStatus = Ab.applyStatus
    Ab.applyStatus = function(ad, holder, victim, status, primary, M, ...)
      local X = hub.C
      if X and ad and type(victim) == "table" and More.statusGuard(X, ad, victim, status) then return false end
      return applyStatus(ad, holder, victim, status, primary, M, ...)
    end
  end

  -- ---------------------------------------------------------------- entering battle
  if type(Engine.switchInEffects) == "function" and not Engine.__ndxAbMoreSwitch then
    Engine.__ndxAbMoreSwitch = true
    local switchIn = Engine.switchInEffects
    Engine.switchInEffects = function(st, ad, b, o, ...)
      if hub.C and type(b) == "table" and st then
        b.__ndxAbEntered = st.turn
        b.__ndxAbItemAtEntry = tonumber(b.item) or 0
      end
      return switchIn(st, ad, b, o, ...)
    end
  end
  if type(Ab.switchIn) == "function" and not Ab.__ndxAbMoreSwitchIn then
    Ab.__ndxAbMoreSwitchIn = true
    local switchIn = Ab.switchIn
    Ab.switchIn = function(ad, b, ...)
      local r = switchIn(ad, b, ...)
      local X = hub.C
      if r or not X or not b or ad:isFainted(b) then return r end
      local ok, acted = pcall(More.onEntry, X, ad, b)
      if ok then return acted or r end
      return r
    end
  end
  -- Intimidate: Scrappy, Guard Dog, Full Metal Body block it; Contrary, Simple, Defiant and
  -- Competitive react to it
  if type(Ab.runIntimidate) == "function" and not Ab.__ndxAbMoreIntimidate then
    Ab.__ndxAbMoreIntimidate = true
    local runIntimidate = Ab.runIntimidate
    Ab.runIntimidate = function(ad, ...)
      local X = hub.C
      if not X then return runIntimidate(ad, ...) end
      local before, guarded = {}, {}
      local pending
      for _, b in ipairs(ad:activeBattlers() or {}) do
        if b.expIntimidatePending and ab(ad, b) == "INTIMIDATE" then pending = pending or b end
      end
      for _, b in ipairs(ad:activeBattlers() or {}) do
        if b.stages then before[b] = b.stages.attack or 0 end
        local k = ab(ad, b)
        if pending and b.side ~= pending.side and (k == "SCRAPPY" or k == "GUARD_DOG" or k == "FULL_METAL_BODY") then
          guarded[b] = k
        end
      end
      local r = runIntimidate(ad, ...)
      pcall(function()
        for b, was in pairs(before) do
          local now = b.stages and b.stages.attack or 0
          if now == was - 1 then
            local k = guarded[b] or ab(ad, b)
            if k == "SCRAPPY" or k == "FULL_METAL_BODY" then
              b.stages.attack = was
              say(ad, "%s's %s kept its ATTACK from dropping!", who(ad, b), X.nameOf(k))
            elseif k == "GUARD_DOG" then
              b.stages.attack = was
              stat(ad, b, "attack", 1, { user = true })
            elseif k == "CONTRARY" then
              b.stages.attack = was
              stat(ad, b, "attack", 1, { user = true })
            elseif k == "SIMPLE" then
              b.stages.attack = math.max(-6, was - 2)
            elseif k == "DEFIANT" then
              stat(ad, b, "attack", 2, { user = true })
            elseif k == "COMPETITIVE" then
              stat(ad, b, "spAtk", 2, { user = true })
            elseif k == "RATTLED" then
              stat(ad, b, "speed", 1, { user = true })
            end
          end
        end
      end)
      return r
    end
  end

  -- ---------------------------------------------------------------- absorbing a move's type
  if type(Ab.absorb) == "function" and not Ab.__ndxAbMoreAbsorb then
    Ab.__ndxAbMoreAbsorb = true
    local absorb = Ab.absorb
    Ab.absorb = function(M, ...)
      local r = absorb(M, ...)
      local X = hub.C
      if r or not X or type(M) ~= "table" then return r end
      local ad, user, target = M.adapter, M.user, M.target
      if not (ad and target and target ~= user) or M.__ndxAbAbsorbChecked then return r end
      M.__ndxAbAbsorbChecked = true
      local ok, acted = pcall(function()
        local k = X.ab(ad, target)
        local mt = tonumber(M.moveType or (M.move and M.move.type)) or 0
        local kind
        if k == "WELL_BAKED_BODY" and mt == ID.FIRE then kind = "def"
        elseif k == "EARTH_EATER" and mt == ID.GROUND then kind = "heal"
        elseif k == "WIND_RIDER" and X.flag("wind", M.move, M.mnum) then kind = "atk"
        end
        if not kind then return false end
        if M.attackString then M:attackString() end
        M.absorbed, M.noEffect = true, true
        if M.anim then M.anim.missed = true end
        if kind == "heal" then
          if ad:hp(target) < ad:maxHp(target) then
            ad:heal(target, math.max(1, math.floor(ad:maxHp(target) / 4)))
            say(ad, "%s restored HP using its %s!", who(ad, target), X.nameOf(k))
          else
            say(ad, "%s's %s made the move useless!", who(ad, target), X.nameOf(k))
          end
        else
          local res = stat(ad, target, kind == "def" and "defense" or "attack", kind == "def" and 2 or 1, {})
          if res ~= "worked" then say(ad, "%s's %s made the move useless!", who(ad, target), X.nameOf(k)) end
        end
        return true
      end)
      if ok then return acted or r end
      return r
    end
  end

  -- ---------------------------------------------------------------- after a hit lands
  if type(Ab.onDamage) == "function" and not Ab.__ndxAbMoreOnDamage then
    Ab.__ndxAbMoreOnDamage = true
    local onDamage = Ab.onDamage
    Ab.onDamage = function(M, ...)
      local X = hub.C
      -- the target's ability reacts to the hit even against a Mold Breaker
      local st = type(M) == "table" and M.adapter and M.adapter._st
      local mold = st and st.__ndxAbMold
      if mold then st.__ndxAbMold = nil end
      local okR, r = pcall(onDamage, M, ...)
      if not X or type(M) ~= "table" then
        if mold then st.__ndxAbMold = mold end
        if not okR then error(r, 0) end
        return r
      end
      if not okR then
        if mold then st.__ndxAbMold = mold end
        error(r, 0)
      end
      local okM, acted = pcall(More.afterHit, X, M)
      if mold then st.__ndxAbMold = mold end
      if okM then return acted or r end
      return r
    end
  end

  -- ---------------------------------------------------------------- the end of the turn
  if type(Ab.endTurn) == "function" and not Ab.__ndxAbMoreEndTurn then
    Ab.__ndxAbMoreEndTurn = true
    local endTurn = Ab.endTurn
    Ab.endTurn = function(ad, b, ...)
      local r = endTurn(ad, b, ...)
      local X = hub.C
      if not X or not b or ad:hp(b) <= 0 then return r end
      local ok, acted = pcall(More.endOfTurn, X, ad, b)
      if ok then return acted or r end
      return r
    end
  end
  if type(Ab.switchOut) == "function" and not Ab.__ndxAbMoreSwitchOut then
    Ab.__ndxAbMoreSwitchOut = true
    local switchOut = Ab.switchOut
    Ab.switchOut = function(ad, b, ...)
      local r = switchOut(ad, b, ...)
      local X = hub.C
      if X and b and b.mon then
        pcall(function()
          if ab(ad, b) == "ZERO_TO_HERO" and ad:hp(b) > 0 then
            local st = ad._st
            st.__ndxAbHero = st.__ndxAbHero or setmetatable({}, { __mode = "k" })
            st.__ndxAbHero[b.mon] = true
          end
        end)
      end
      return r
    end
  end

  -- ---------------------------------------------------------------- held items
  if HeldItems and type(HeldItems.of) == "function" and not HeldItems.__ndxAbMore then
    HeldItems.__ndxAbMore = true
    local of, has = HeldItems.of, HeldItems.has
    local H = HeldItems.HOLD or {}
    local PINCH = {}
    for _, k in ipairs({ "ATTACK_UP", "DEFENSE_UP", "SPEED_UP", "SP_ATTACK_UP", "SP_DEFENSE_UP", "CRITICAL_UP",
      "RANDOM_STAT_UP" }) do if H[k] then PINCH[H[k]] = true end end
    HeldItems.of = function(b, trigger, st, ...)
      local he, param, item, hooked = of(b, trigger, st, ...)
      local X = hub.C
      if not (X and type(b) == "table" and he ~= 0) then return he, param, item, hooked end
      local ad
      do
        local okB, B = pcall(require, "src.core.game3.battle")
        ad = okB and B and B._adapter
      end
      if not (ad and ad._st) then return he, param, item, hooked end
      local k = X.ab(ad, b)
      if k == "KLUTZ" then return 0, 0, item end
      if X.isBerry(tonumber(item) or 0) then
        for _, x in ipairs(X.foes(ad, b)) do
          local fk = X.ab(ad, x)
          if fk == "UNNERVE" or fk == "AS_ONE_GLASTRIER" or fk == "AS_ONE_SPECTRIER" then return 0, 0, item end
        end
        if k == "GLUTTONY" and PINCH[he] and (tonumber(param) or 0) > 2 then param = 2 end
      end
      return he, param, item, hooked
    end
    -- Gorilla Tactics: the Choice Band's lock without the band
    HeldItems.has = function(b, he, trigger, st, ...)
      local X = hub.C
      if X and he == H.CHOICE_BAND and trigger == "check" and type(b) == "table" then
        local okB, B = pcall(require, "src.core.game3.battle")
        local ad = okB and B and B._adapter
        if ad and X.ab(ad, b) == "GORILLA_TACTICS" then return true end
      end
      return has(b, he, trigger, st, ...)
    end
    -- Ripen, Cheek Pouch, Cud Chew: after a berry is eaten
    if type(HeldItems.normal) == "function" then
      local normal = HeldItems.normal
      HeldItems.normal = function(ad, b, ...)
        local X = hub.C
        if not (X and ad and type(b) == "table") then return normal(ad, b, ...) end
        local item = tonumber(b.item) or 0
        local hp0 = ad:hp(b)
        local stages0 = {}
        for k2, v in pairs(b.stages or {}) do stages0[k2] = v end
        local r = normal(ad, b, ...)
        pcall(More.ateBerry, X, ad, b, item, hp0, stages0)
        return r
      end
    end
  end

  -- the newer held items' own core (src/held/gen3.lua): the same abilities answer there
  local Held = opts.held
  local core = Held and Held._core
  if core and core.on then
    local function A_ab(A, b) return A and A.ad and ab(A.ad, b) end
    core:on("itemSuppressed", function(A, b)
      local k = A_ab(A, b)
      if k == "KLUTZ" then return true end
    end)
    core:on("gluttony", function(A, b) return A_ab(A, b) == "GLUTTONY" or nil end)
    core:on("ripen", function(A, b) return A_ab(A, b) == "RIPEN" or nil end)
    core:on("noIndirect", function(A, b) return A_ab(A, b) == "MAGIC_GUARD" or nil end)
    core:on("ateBerry", function(A, b)
      local k = A_ab(A, b)
      if k == "CHEEK_POUCH" and A:hp(b) > 0 and A:hp(b) < A:maxHp(b) then
        A:heal(b, math.floor(A:maxHp(b) / 3))
        say(A.ad, "%s's CHEEK POUCH restored its HP!", who(A.ad, b))
      end
    end)
  end

  -- ---------------------------------------------------------------- speed and priority
  local RA = C.RA
  if type(RA) == "table" and type(RA.speedModifiers) == "table" then
    RA.speedModifiers.moreAbilities = function(ad, b)
      local X = hub.C
      if not (X and ad and b) then return 1 end
      local k = X.ab(ad, b)
      if k == "UNBURDEN" and (b.__ndxAbItemAtEntry or 0) > 0 and (tonumber(b.item) or 0) == 0 then return 2 end
      if k == "SLOW_START" and (b.__ndxAbSlowStart or 0) > 0 then return 0.5 end
      if k == "SURGE_SURFER" and X.terrain(ad) == "ELECTRIC" then return 2 end
      return 1
    end
    if type(RA.priorityOf) == "function" and not RA.__ndxAbMoreTriage then
      RA.__ndxAbMoreTriage = true
      local priorityOf = RA.priorityOf
      RA.priorityOf = function(ad, b, mv)
        local p = priorityOf(ad, b, mv)
        local X = hub.C
        if X and ad and b and X.ab(ad, b) == "TRIAGE" and HEALING[X.moveKey(mv)] then p = p + 3 end
        return p
      end
    end
  end

  -- Light Metal / Heavy Metal for Heavy Slam and Heat Crash (src/move_rules.lua reads this)
  if C.MoveRules then
    C.MoveRules.weightScale = function(b)
      local X, ad = hub.C, adNow()
      local k = X and ad and X.ab(ad, b)
      if k == "LIGHT_METAL" then return 0.5 elseif k == "HEAVY_METAL" then return 2 end
      return 1
    end
  end
  -- Magic Guard: no Stealth Rock damage (src/move_field.lua asks)
  if C.MoveField then
    C.MoveField.noIndirect = function(ad, b)
      local X = hub.C
      return X ~= nil and X.ab(ad, b) == "MAGIC_GUARD"
    end
  end

  hub.on = true
  if log then log:info("the other newer abilities: on") end
  return true
end

-- ------------------------------------------------------------------ the pieces
-- the status a guard keeps off this Pokemon (its ability's key), or nil
function More.statusGuard(C, ad, b, status)
  local k = C.ab(ad, b)
  if not k then return nil end
  status = tostring(status or ""):upper()
  if k == "PURIFYING_SALT" or k == "COMATOSE" then return k end
  if k == "SHIELDS_DOWN" and ad:hp(b) * 2 > ad:maxHp(b) then return k end
  if k == "PASTEL_VEIL" and (status == "PSN" or status == "TOX") then return k end
  if (k == "WATER_BUBBLE" or k == "THERMAL_EXCHANGE") and status == "BRN" then return k end
  return nil
end

-- entering battle
function More.onEntry(C, ad, b)
  local k = C.ab(ad, b)
  local st = ad._st
  local foe = ad:foeOf(b)
  local who, say, stat = C.who, C.say, C.stat
  local function once(tag)
    st.__ndxAbOnce = st.__ndxAbOnce or setmetatable({}, { __mode = "k" })
    local mon = b.mon or b
    st.__ndxAbOnce[mon] = st.__ndxAbOnce[mon] or {}
    if st.__ndxAbOnce[mon][tag] then return false end
    st.__ndxAbOnce[mon][tag] = true
    return true
  end
  -- a form that comes back changed
  if k == "ZERO_TO_HERO" and st.__ndxAbHero and st.__ndxAbHero[b.mon] then
    C.setForm(b, FORM.HERO)
    if once("hero") then say(ad, "%s underwent a heroic transformation!", who(ad, b)) end
  end
  if k == "SCHOOLING" or k == "SHIELDS_DOWN" then More.formCheck(C, ad, b) end
  if k == "MULTITYPE" then More.plateType(C, ad, b) end
  if k == "MIMICRY" then More.mimicry(C, ad, b) end
  if k == "SLOW_START" then
    b.__ndxAbSlowStart = 5
    say(ad, "%s can't get it going!", who(ad, b))
    return true
  end
  if k == "INTREPID_SWORD" and once("sword") then return stat(ad, b, "attack", 1, { user = true }) == "worked" end
  if k == "DAUNTLESS_SHIELD" and once("shield") then return stat(ad, b, "defense", 1, { user = true }) == "worked" end
  if k == "SUPERSWEET_SYRUP" and foe and ad:hp(foe) > 0 and once("syrup") then
    say(ad, "A supersweet aroma is wafting from %s!", who(ad, b))
    stat(ad, foe, "evasion", -1, { allowPtr = true })
    return true
  end
  if k == "DOWNLOAD" and foe and ad:hp(foe) > 0 then
    local d = C.Pokemon and foe.mon and tonumber(foe.mon.defense) or 0
    local s = foe.mon and tonumber(foe.mon.spDef) or 0
    return stat(ad, b, s < d and "spAtk" or "attack", 1, { user = true }) == "worked"
  end
  if k == "FOREWARN" and foe and ad:hp(foe) > 0 then
    local best, power = nil, -1
    for _, mv in ipairs(foe.mon and foe.mon.moves or {}) do
      local n = type(mv) == "table" and tonumber(mv.id or mv.move) or tonumber(mv)
      local rec = n and n > 0 and C.moveRec(n)
      local p = rec and (tonumber(rec.power) or 0) or -1
      if p == 1 then p = 80 end
      if rec and p > power then best, power = n, p end
    end
    if best then
      local okN, nm = pcall(C.Moves.displayName, best)
      say(ad, "%s's FOREWARN alerted it to %s!", who(ad, b), okN and nm or "a move")
      return true
    end
  end
  if k == "SCREEN_CLEANER" then
    local any = false
    for _, side in ipairs({ st.playerSide, st.enemySide }) do
      if side and ((side.expReflectTurns or 0) > 0 or (side.expLightScreenTurns or 0) > 0
          or (side.__ndx and side.__ndx.auroraVeil)) then
        side.expReflectTurns, side.expLightScreenTurns = nil, nil
        if side.__ndx then side.__ndx.auroraVeil = nil end
        any = true
      end
    end
    if any then say(ad, "All screens on the field were cleansed!") end
    return any
  end
  if k == "UNNERVE" or k == "AS_ONE_GLASTRIER" or k == "AS_ONE_SPECTRIER" then
    say(ad, "The opposing team is too nervous to eat Berries!")
    return true
  end
  if k == "NEUTRALIZING_GAS" then
    st.__ndxAbGas = true
    say(ad, "Neutralizing gas filled the area!")
    return true
  end
  if MOLD[k] and k ~= "MYCELIUM_MIGHT" then
    local line = ({ MOLD_BREAKER = "%s breaks the mold!", TURBOBLAZE = "%s is radiating a blazing aura!",
      TERAVOLT = "%s is radiating a bursting aura!" })[k]
    say(ad, line, who(ad, b))
    return true
  end
  if k == "FAIRY_AURA" or k == "DARK_AURA" then
    say(ad, "%s is radiating a %s aura!", who(ad, b), k == "FAIRY_AURA" and "fairy" or "dark")
    return true
  end
  if k == "AURA_BREAK" then
    say(ad, "%s reversed all other Pokemon's auras!", who(ad, b))
    return true
  end
  if k == "COMATOSE" then
    say(ad, "%s is drowsing!", who(ad, b))
    return true
  end
  if k == "TABLETS_OF_RUIN" or k == "SWORD_OF_RUIN" or k == "VESSEL_OF_RUIN" or k == "BEADS_OF_RUIN" then
    local what = ({ TABLETS_OF_RUIN = "ATTACK", SWORD_OF_RUIN = "DEFENSE", VESSEL_OF_RUIN = "SP. ATK",
      BEADS_OF_RUIN = "SP. DEF" })[k]
    say(ad, "%s's %s weakened the %s of all surrounding Pokemon!", who(ad, b), C.nameOf(k), what)
    return true
  end
  local surge = ({ ELECTRIC_SURGE = "ELECTRIC", PSYCHIC_SURGE = "PSYCHIC", GRASSY_SURGE = "GRASSY",
    MISTY_SURGE = "MISTY", HADRON_ENGINE = "ELECTRIC" })[k]
  if surge then return More.startTerrain(C, ad, surge) end
  if k == "ORICHALCUM_PULSE" then
    local okR, Rules = pcall(C.require, "src.core.game3.battle.rules")
    local kind = okR and Rules.weather.kind(st.weather) or st.weather
    if kind ~= "SUN" then
      st.weather, st.weatherTurns = "SUN", 5
      say(ad, "%s turned the sunlight harsh, sending its ancient pulse into a frenzy!", who(ad, b))
      pcall(ad.playAnim, ad, "general", "SUN_CONTINUES", nil, nil)
      return true
    end
  end
  return false
end

-- a terrain on the field for 5 turns (src/move_field.lua keeps and ends it)
function More.startTerrain(C, ad, kind)
  local MF = C.MoveField
  if MF and MF.startTerrain then return MF.startTerrain(ad, kind) and true or false end
  local st = ad._st
  st.__ndxField = st.__ndxField or {}
  local f = st.__ndxField
  if (f.terrainTurns or 0) > 0 and f.terrain == kind then return false end
  f.terrain, f.terrainTurns = kind, 5
  return true
end

-- Multitype: the Plate's type
local PLATE = { FLAME_PLATE = "FIRE", SPLASH_PLATE = "WATER", ZAP_PLATE = "ELECTRIC", MEADOW_PLATE = "GRASS",
  ICICLE_PLATE = "ICE", FIST_PLATE = "FIGHTING", TOXIC_PLATE = "POISON", EARTH_PLATE = "GROUND",
  SKY_PLATE = "FLYING", MIND_PLATE = "PSYCHIC", INSECT_PLATE = "BUG", STONE_PLATE = "ROCK", SPOOKY_PLATE = "GHOST",
  DRACO_PLATE = "DRAGON", DREAD_PLATE = "DARK", IRON_PLATE = "STEEL", PIXIE_PLATE = "FAIRY" }
function More.plateType(C, ad, b)
  local item = tonumber(b.item) or 0
  local t = C.ID.NORMAL or 0
  if item > 0 then
    local name = C.itemName(item):gsub("[^%w]+", "_")
    local tn = PLATE[name]
    if tn and C.ID[tn] then t = C.ID[tn] end
  end
  b.type1, b.type2 = t, nil
end

-- Mimicry: the terrain's type
function More.mimicry(C, ad, b)
  local t = ({ ELECTRIC = C.ID.ELECTRIC, GRASSY = C.ID.GRASS, MISTY = C.ID.FAIRY, PSYCHIC = C.ID.PSYCHIC })[C.terrain(ad) or ""]
  if t then
    if not b.__ndxAbOwnTypes then b.__ndxAbOwnTypes = { b.type1, b.type2 } end
    if b.type1 ~= t or b.type2 then
      b.type1, b.type2 = t, nil
      return true
    end
  elseif b.__ndxAbOwnTypes then
    b.type1, b.type2 = b.__ndxAbOwnTypes[1], b.__ndxAbOwnTypes[2]
    b.__ndxAbOwnTypes = nil
    return true
  end
  return false
end

-- Schooling and Shields Down: the form for the Pokemon's HP
function More.formCheck(C, ad, b)
  local k = C.ab(ad, b)
  if k == "SCHOOLING" then
    local school = (tonumber(b.mon and b.mon.level) or 1) >= 20 and ad:hp(b) * 4 > ad:maxHp(b)
    if school and not b.__ndxAbSchool then
      b.__ndxAbSchool = true
      C.setForm(b, FORM.SCHOOL)
      C.say(ad, "%s formed a school!", C.who(ad, b))
      return true
    elseif not school and b.__ndxAbSchool then
      b.__ndxAbSchool = nil
      C.setForm(b, nil)
      C.say(ad, "%s stopped schooling!", C.who(ad, b))
      return true
    end
  elseif k == "SHIELDS_DOWN" then
    local core = ad:hp(b) * 2 <= ad:maxHp(b)
    if core and not b.__ndxAbCore then
      b.__ndxAbCore = true
      C.setForm(b, FORM.CORE)
      C.say(ad, "Shields Down activated!")
      return true
    elseif not core and b.__ndxAbCore then
      b.__ndxAbCore = nil
      C.setForm(b, nil)
      C.say(ad, "Shields Down deactivated!")
      return true
    end
  end
  return false
end

-- after a hit lands: the target's ability, then the user's (Ab.onDamage)
function More.afterHit(C, M)
  local ad, user, target = M.adapter, M.user, M.target
  if not (ad and user and target) or target == user or M.noEffect or not M.targetDamaged then return false end
  local who, say, stat = C.who, C.say, C.stat
  local ta, ua = C.ab(ad, target), C.ab(ad, user)
  local num = tonumber(M.mnum)
  local mt = tonumber(M.moveType or (M.move and M.move.type)) or 0
  local touched = contact(M.move)
  local tUp, uUp = ad:hp(target) > 0, ad:hp(user) > 0
  local hp0 = tonumber(target.__ndxAbHpBefore) or ad:hp(target)
  local half = ad:maxHp(target) / 2
  local crossed = tUp and hp0 > half and ad:hp(target) <= half
  local did = false
  local ID = C.ID
  -- the target's
  if ta == "INNARDS_OUT" and not tUp and uUp then
    ad:applyHpLoss(user, math.max(1, hp0))
    say(ad, "%s was hurt by %s's INNARDS OUT!", who(ad, user), who(ad, target))
    if M.tryFaintUser then M:tryFaintUser() end
    did = true
  end
  if tUp then
    if ta == "ANGER_POINT" and target.__ndxAbCritTaken then
      target.__ndxAbCritTaken = nil
      if target.stages and (target.stages.attack or 0) < 6 then
        target.stages.attack = 6
        say(ad, "%s maxed its ATTACK!", who(ad, target))
        did = true
      end
    elseif ta == "STEAM_ENGINE" and (mt == ID.FIRE or mt == ID.WATER) then
      did = stat(ad, target, "speed", 6) == "worked"
    elseif ta == "THERMAL_EXCHANGE" and mt == ID.FIRE then
      did = stat(ad, target, "attack", 1) == "worked"
    elseif ta == "WATER_COMPACTION" and mt == ID.WATER then
      did = stat(ad, target, "defense", 2) == "worked"
    elseif ta == "COTTON_DOWN" and uUp then
      say(ad, "%s's COTTON DOWN scattered!", who(ad, target))
      stat(ad, user, "speed", -1, { allowPtr = true })
      did = true
    elseif (ta == "GOOEY" or ta == "TANGLING_HAIR") and touched and uUp then
      stat(ad, user, "speed", -1, { allowPtr = true })
      did = true
    elseif ta == "SAND_SPIT" then
      local st = ad._st
      if st.weather ~= "SAND" then
        st.weather, st.weatherTurns = "SAND", 5
        say(ad, "A sandstorm kicked up!")
        pcall(ad.playAnim, ad, "general", "SANDSTORM_CONTINUES", nil, nil)
        did = true
      end
    elseif ta == "SEED_SOWER" then
      did = More.startTerrain(C, ad, "GRASSY")
    elseif ta == "TOXIC_DEBRIS" and C.physical(mt) then
      local side = ad:ownSide(user)
      if side then
        side.__ndx = side.__ndx or {}
        if (side.__ndx.toxicSpikes or 0) < 2 then
          side.__ndx.toxicSpikes = (side.__ndx.toxicSpikes or 0) + 1
          say(ad, "Poison spikes were scattered around %s's feet!", who(ad, user))
          did = true
        end
      end
    elseif (ta == "WIND_POWER" and C.flag("wind", M.move, num)) or ta == "ELECTROMORPHOSIS" then
      target.expCharged = true
      say(ad, "Being hit by %s charged %s with power!", M.moveName or "the move", who(ad, target))
      did = true
    elseif ta == "CURSED_BODY" and uUp and num and not user.expDisabledMove and ad:roll(1, 100) <= 30 then
      user.expDisabledMove, user.expDisableTurns = num, 4
      say(ad, "%s's %s was disabled by %s's CURSED BODY!", who(ad, user), M.moveName or "move", who(ad, target))
      did = true
    elseif (ta == "MUMMY" or ta == "LINGERING_AROMA") and touched and uUp then
      local k = C.ab(ad, user)
      if k ~= ta and not FIXED[k or ""] then
        C.setAbility(user, ta)
        say(ad, "%s's ability became %s!", who(ad, user), C.nameOf(ta))
        did = true
      end
    elseif ta == "WANDERING_SPIRIT" and touched and uUp then
      local k = C.ab(ad, user)
      if k and not FIXED[k] then
        C.setAbility(user, "WANDERING_SPIRIT")
        C.setAbility(target, k)
        say(ad, "%s swapped abilities with its target!", who(ad, target))
        did = true
      end
    elseif ta == "PICKPOCKET" and touched and uUp and C.item(target) == 0 and C.item(user) > 0 then
      local item = C.item(user)
      C.setItem(user, 0)
      C.setItem(target, item)
      say(ad, "%s stole %s's %s!", who(ad, target), who(ad, user), C.itemName(item))
      did = true
    elseif ta == "GULP_MISSILE" and target.__ndxAbGulp and uUp then
      local prey = target.__ndxAbGulp
      target.__ndxAbGulp = nil
      ad:applyHpLoss(user, math.max(1, math.floor(ad:maxHp(user) / 4)))
      say(ad, "%s spat out its catch!", who(ad, target))
      if prey == "pikachu" then
        if ad:canApplyStatus(user, "PAR", target, {}) then
          ad:applyStatus(user, "PAR", target, { force = true })
          ad:sayText("STRINGID_PKMNWASPARALYZED", { eff = user })
        end
      else
        stat(ad, user, "defense", -1, { allowPtr = true })
      end
      if M.tryFaintUser then M:tryFaintUser() end
      did = true
    end
    if crossed then
      if ta == "BERSERK" then did = stat(ad, target, "spAtk", 1) == "worked" or did
      elseif ta == "ANGER_SHELL" then
        say(ad, "%s's ANGER SHELL activated!", who(ad, target))
        for _, s in ipairs({ "attack", "spAtk", "speed" }) do stat(ad, target, s, 1, { user = true }) end
        for _, s in ipairs({ "defense", "spDef" }) do stat(ad, target, s, -1, { user = true, certain = true }) end
        did = true
      elseif ta == "WIMP_OUT" or ta == "EMERGENCY_EXIT" then
        C.switchOut(ad, target)
        did = true
      end
    end
    if ta == "SCHOOLING" or ta == "SHIELDS_DOWN" then did = More.formCheck(C, ad, target) or did end
  end
  target.__ndxAbHpBefore = nil
  -- the user's
  if not uUp then return did end
  if ua == "MAGICIAN" and C.item(user) == 0 and C.item(target) > 0 and not M.hitSubstitute then
    local item = C.item(target)
    C.setItem(target, 0)
    C.setItem(user, item)
    say(ad, "%s stole %s's %s!", who(ad, user), who(ad, target), C.itemName(item))
    did = true
  end
  if tUp and not M.hitSubstitute and not ad:status(target) then
    if ua == "TOXIC_CHAIN" and ad:roll(1, 100) <= 30 and ad:canApplyStatus(target, "TOX", user, {}) then
      ad:applyStatus(target, "TOX", user, { force = true })
      ad:statusAnim(target, "TOX")
      ad:sayText("STRINGID_PKMNBADLYPOISONED", { eff = target })
      did = true
    end
  end
  if ua == "POISON_PUPPETEER" and tUp then
    local s = ad:status(target)
    if (s == "PSN" or s == "TOX") and target.__ndxAbStatusBefore == false and (target.confusionTurns or 0) <= 0 then
      if ad:applyConfusion(target) then
        ad:sayText("STRINGID_PKMNWASCONFUSED", { eff = target })
        did = true
      end
    end
  end
  target.__ndxAbStatusBefore = nil
  if not tUp then
    local k = ua
    if k == "AS_ONE_GLASTRIER" or k == "CHILLING_NEIGH" then did = stat(ad, user, "attack", 1) == "worked" or did
    elseif k == "AS_ONE_SPECTRIER" or k == "GRIM_NEIGH" then did = stat(ad, user, "spAtk", 1) == "worked" or did end
  end
  return did
end

-- the end of the turn, per battler
function More.endOfTurn(C, ad, b)
  local k = C.ab(ad, b)
  local who, say = C.who, C.say
  if k == "BAD_DREAMS" then
    local any = false
    for _, x in ipairs(C.foes(ad, b)) do
      if ad:status(x) == "SLP" or C.ab(ad, x) == "COMATOSE" then
        ad:applyHpLoss(x, math.max(1, math.floor(ad:maxHp(x) / 8)))
        say(ad, "%s is tormented!", who(ad, x))
        any = true
      end
    end
    return any
  end
  if k == "SLOW_START" and (b.__ndxAbSlowStart or 0) > 0 then
    b.__ndxAbSlowStart = b.__ndxAbSlowStart - 1
    if b.__ndxAbSlowStart == 0 then
      say(ad, "%s finally got its act together!", who(ad, b))
      return true
    end
    return false
  end
  if k == "HUNGER_SWITCH" then
    b.__ndxAbHangry = not b.__ndxAbHangry or nil
    return false
  end
  if k == "SCHOOLING" or k == "SHIELDS_DOWN" then return More.formCheck(C, ad, b) end
  if k == "MIMICRY" then return More.mimicry(C, ad, b) end
  if k == "ICE_FACE" and b.__ndxAbNoice and C.weather(ad) == "HAIL" then
    b.__ndxAbNoice = nil
    C.setForm(b, nil)
    say(ad, "%s's ICE FACE was restored!", who(ad, b))
    return true
  end
  if k == "CUD_CHEW" then
    local c = b.__ndxAbCud
    local st = ad._st
    if c and st and c.turn < (st.turn or 0) and (tonumber(b.item) or 0) == 0 then
      b.__ndxAbCud = nil
      b.item = c.item
      local HeldItems = C.HeldItems
      local ok, ate = pcall(HeldItems.normal, ad, b, false)
      if not (ok and ate) then b.item = 0 end
      return ok and ate or false
    elseif c and st and c.turn < (st.turn or 0) then
      b.__ndxAbCud = nil
    end
  end
  return false
end

-- after the cart's berry code ran (HeldItems.normal): Ripen, Cheek Pouch, Cud Chew
function More.ateBerry(C, ad, b, item, hp0, stages0)
  if item == 0 or (tonumber(b.item) or 0) ~= 0 or not C.isBerry(item) then return end
  local k = C.ab(ad, b)
  if k == "RIPEN" then
    local healed = ad:hp(b) - hp0
    if healed > 0 then ad:heal(b, healed) end
    for s, v in pairs(b.stages or {}) do
      local d = v - (stages0[s] or 0)
      if d > 0 then b.stages[s] = math.min(6, v + d) end
    end
  elseif k == "CHEEK_POUCH" and ad:hp(b) > 0 and ad:hp(b) < ad:maxHp(b) then
    ad:heal(b, math.floor(ad:maxHp(b) / 3))
    C.say(ad, "%s's CHEEK POUCH restored its HP!", C.who(ad, b))
  elseif k == "CUD_CHEW" and not b.__ndxAbCud and ad._st then
    b.__ndxAbCud = { item = item, turn = ad._st.turn or 0 }
  end
end

return More
