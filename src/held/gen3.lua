-- The newer held items (data/held_items.lua) on FireRed / LeafGreen / Ruby / Sapphire / Emerald.
--
-- Registration (at load, Held.register): every row the game lacks (by id or name: Emerald keeps
-- its own CHOICE BAND and berries) becomes an item at the row's fixed `index` (1300+, the number
-- saves keep), in the ITEMS pocket, with its Bag text. Choice Scarf / Specs carry the cart's
-- Choice Band hold effect (29), so the game's own move lock applies; their Attack boost is taken
-- back (HeldItems.of answers 0 for them where the damage reads it) and src/held/effects.lua gives
-- each its own.
--
-- Effects (on game.ready, Held.install): src/held/effects.lua, the same family Red and Gold run,
-- on a core of its own (src/gen12/mech/core.lua's hook bus) and an adapter over the Gen 3 battle
-- adapter (GA below: the calls the family makes). The hooks fire from the battle's seams, each
-- wrapped once a process (`__ndxHeld`):
--   battle.damage   damageMult (both sides' items), damageCap (Focus Sash), the immunities
--                   (Air Balloon, Safety Goggles on powder), Utility Umbrella
--   Hit.run         before: a snapshot of stages; after: damageDealt per hit, afterMove
--   Effects.run     status moves: the same snapshot and afterMove (Clear Amulet against Growl)
--   battle.accuracy accuracyScale (Wide / Zoom Lens, Micle) and "missed" (Blunder Policy)
--   battle.crit     forceCrit (Razor Claw)
--   RealAbilities.speedModifiers   speed (Choice Scarf, Iron Ball, Quick Powder, Lagging Tail
--                   and Full Incense last, Custap first)
--   Engine.switchInEffects         Heavy-Duty Boots (no Spikes or hazards), then switchedIn
--   Engine.canSwitch               Shed Shell
--   battle.charge_required         Power Herb
--   Residuals       a field phase of ours at the end of the turn: endTurn
-- Everything runs protected: an error leaves the game's own result.

local Held = {}

local TYPE_NAME = { [0] = "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST",
  "STEEL", "MYSTERY", "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC", "ICE", "DRAGON", "DARK", "FAIRY" }
local TYPE_ID = {}
for id, n in pairs(TYPE_NAME) do TYPE_ID[n] = id end
local CHOICE_BAND = 29

local function norm(s) return (tostring(s or ""):upper():gsub("[^%w]", "")) end
-- held items this mod registers as evolution items (src/items.lua): they keep their number
Held.ALSO = { RAZOR_CLAW = true, RAZOR_FANG = true }

-- ------------------------------------------------------------------ registration (at load)
-- opts: { mod, rows, log } -> { byId, byIndex, registered }
function Held.register(opts)
  local mod, log = opts.mod, opts.log
  local items = mod.content.items
  local state = { byId = {}, byIndex = {}, registered = {} }
  local names = {}
  pcall(function()
    for id, rec in items:each() do
      names[norm(id)] = true
      if type(rec) == "table" and rec.name then names[norm(rec.name)] = true end
    end
  end)
  local firstError
  for _, row in ipairs(opts.rows or {}) do
    local mine = Held.ALSO[row.id] and items:get(row.id)
    if type(mine) == "table" and tonumber(mine.index) then
      -- this mod's own item already (an evolution item): it gets the held effect too
      state.byId[row.id] = row
      state.byIndex[tonumber(mine.index)] = row
    elseif items:get(row.id) == nil and not names[norm(row.name)] and not names[norm(row.id)] then
      local e = row.effect or {}
      local rec = { id = row.id, name = row.name, index = row.index, price = row.price or 0,
        pocket = "ITEMS", description = row.desc }
      if e.kind == "choice" then rec.holdEffect = CHOICE_BAND end
      local ok, err = pcall(items.register, items, row.id, rec)
      if ok then
        state.byId[row.id] = row
        state.byIndex[row.index] = row
        state.registered[#state.registered + 1] = row
      else
        firstError = firstError or (row.id .. ": " .. tostring(err))
      end
    end
  end
  if log then
    log:info("held items: %d newer ones registered", #state.registered)
    if firstError then log:warn("held items: some could not be registered (first: %s)", firstError) end
  end
  return state
end

-- ------------------------------------------------------------------ the adapter
local GA = {}
GA.__index = GA

local function wrapText(s, width)
  width = width or 28
  local out, line = {}, ""
  for word in tostring(s):gmatch("%S+") do
    if line == "" then line = word
    elseif #line + 1 + #word <= width then line = line .. " " .. word
    else out[#out + 1] = line; line = word end
  end
  if line ~= "" then out[#out + 1] = line end
  return table.concat(out, "\n")
end
Held.wrapText = wrapText

function Held.adapter(ad, env)
  if not ad then return nil end
  local A = rawget(ad, "__ndxHeldA")
  if A and A.env == env then return A end
  A = setmetatable({ ad = ad, battle = ad._st, gen = 3, env = env, core = env.core }, GA)
  ad.__ndxHeldA = A
  return A
end

function GA:name(b)
  local ok, State = pcall(self.env.require, "src.core.game3.battle.state")
  if ok and State.prefixedName then
    local okN, n = pcall(State.prefixedName, self.ad._st, b)
    if okN and n then return n end
  end
  return self.ad:displayName(b)
end
function GA:hp(b) return self.ad:hp(b) end
function GA:maxHp(b) return self.ad:maxHp(b) end
function GA:heal(b, n, opts)
  local got = self.ad:heal(b, math.max(0, math.floor(n)))
  if opts and opts.text and got > 0 then self:say(opts.text) end
  return got
end
function GA:damage(b, n, opts)
  local lost = self.ad:applyHpLoss(b, math.max(0, math.floor(n)))
  if opts and opts.text then self:say(opts.text) end
  return lost
end
-- the battler's item as this mod's id (nil: none; a cart item: "CART:<n>")
function GA:item(b)
  local n = tonumber(b and b.item) or 0
  if n == 0 then return nil end
  local row = self.env.byIndex[n]
  return row and row.id or ("CART:" .. n)
end
function GA:setItem(b, id)
  if not b then return end
  local n = 0
  if id then
    local row = self.env.byId[id]
    n = row and row.index or tonumber(tostring(id):match("^CART:(%d+)$")) or 0
  end
  b.item = n
  if n == 0 then b.expUsedHeldItem = nil end
  local okS, Secondary = pcall(self.env.require, "src.core.game3.battle.effects.secondary")
  if okS and Secondary.persistItem then pcall(Secondary.persistItem, b, n) end
end
function GA:itemName(id)
  local row = id and self.env.byId[id]
  return row and row.name or tostring(id or "")
end
function GA:stage(b, s) return (b and b.stages and b.stages[s]) or 0 end
function GA:setStage(b, s, v) if b and b.stages then b.stages[s] = math.max(-6, math.min(6, v)) end end
function GA:stages(b, t, opts)
  local okS, Secondary = pcall(self.env.require, "src.core.game3.battle.effects.secondary")
  if not okS then return false end
  local any = false
  for _, st in ipairs({ "attack", "defense", "speed", "spAtk", "spDef", "accuracy", "evasion" }) do
    local d = t[st]
    if d and d ~= 0 then
      local r = Secondary.changeStat(self.ad, b, st, d, { allowPtr = true })
      if r ~= "blocked" then any = true end
    end
  end
  return any
end
function GA:status(b) return self.ad:status(b) end
function GA:ailment(b, name, opts)
  local code = ({ BURN = "BRN", TOXIC = "TOX", POISON = "PSN", PARALYSIS = "PAR", SLEEP = "SLP", FREEZE = "FRZ" })[name]
  if not code then return false end
  return self.ad:applyStatus(b, code, nil, opts or {}) and true or false
end
function GA:cure(b) self.ad:clearStatus(b) end
function GA:confuse(b) return self.ad:applyConfusion(b) end
function GA:types(b)
  local out = {}
  if b and b.type1 then out[#out + 1] = TYPE_NAME[b.type1] end
  if b and b.type2 and b.type2 ~= b.type1 then out[#out + 1] = TYPE_NAME[b.type2] end
  return out
end
function GA:hasType(b, name)
  local id = TYPE_ID[name]
  return id ~= nil and b ~= nil and (b.type1 == id or b.type2 == id)
end
function GA:moveType(m) return m and m.type end
function GA:category(m) return m and m.category or "physical" end
function GA:typeEff(at, dt)
  local okT, Types = pcall(self.env.require, "src.core.game3.battle.types")
  if not (okT and TYPE_ID[at] and TYPE_ID[dt]) then return 10 end
  local _, _, p = Types.typeCalc(TYPE_ID[at], TYPE_ID[dt], nil, nil, false)
  return math.floor((tonumber(p) or 1) * 10 + 0.5)
end
function GA:effectiveness(typeName, b)
  local okT, Types = pcall(self.env.require, "src.core.game3.battle.types")
  if not (okT and TYPE_ID[typeName] and b) then return 10 end
  local _, _, p = Types.typeCalc(TYPE_ID[typeName], b.type1, b.type2, nil, false)
  return math.floor((tonumber(p) or 1) * 10 + 0.5)
end
function GA:rng(n) return (self.ad:roll(1, math.max(1, n))) - 1 end
function GA:field()
  local st = self.ad._st
  st.__ndxHeld = st.__ndxHeld or {}
  return st.__ndxHeld
end
function GA:side(b)
  local s = self.ad:ownSide(b)
  if not s then return {} end
  s.__ndxHeld = s.__ndxHeld or {}
  return s.__ndxHeld
end
function GA:vol(b)
  if not b then return {} end
  b.__ndxHeldVol = b.__ndxHeldVol or {}
  return b.__ndxHeldVol
end
function GA:foe(b) return self.ad:foeOf(b) end
function GA:sideName(b) return b and b.side end
function GA:battlers()
  local list = self.ad:activeBattlers() or {}
  return list[1], list[2], list[3], list[4]
end
function GA:turn() return self.ad._st.turn or 0 end
function GA:text(fmt, ...) return wrapText(string.format(fmt, ...)) end
function GA:say(text) if text and text ~= "" then self.ad:say(text) end end
function GA:moves(b) return {} end                       -- (Leppa is the cart's own here)
function GA:dvs(b) return {} end
function GA:record(b)
  local okP, P = pcall(self.env.require, "src.core.game3.pokemon")
  local sp = b and b.mon and b.mon.species
  if not (okP and sp) then return nil end
  local okE, evos = pcall(P.evolutions, sp)
  return { evolutions = okE and evos or {} }
end
function GA:dex(b)
  local okP, P = pcall(self.env.require, "src.core.game3.pokemon")
  local sp = b and b.mon and b.mon.species
  if not (okP and sp) then return nil end
  local ok, n = pcall(P.national, sp)
  return ok and n or nil
end
function GA:weather()
  local w = self.ad._st.weather
  return w and ({ RAIN = "rain", SUN = "sun", SAND = "sand", HAIL = "hail" })[tostring(w):upper()] or nil
end
function GA:switchOut(b, opts)
  local env = self.env
  local okE, Engine = pcall(env.require, "src.core.game3.battle.engine")
  if not okE then return nil end
  local st, ad = self.ad._st, self.ad
  if opts and opts.random and st.wild and b.side == "enemy" then
    ad:pushEvent({ kind = "switch_out", side = b.side, reason = "roar" })
    st.over, st.result, st.endReason = true, "run", "red_card"
    ad:pushEvent({ kind = "end", result = "run", reason = "red_card" })
    return nil
  end
  local who = st.double and b.id or b.side
  local candidates = Engine.switchCandidates(st, who)
  if #candidates == 0 then return nil end
  local slot = candidates[1]
  if opts and opts.random then
    slot = candidates[ad:roll(1, #candidates)]
  elseif type(st.batonPassChooser) == "function" then
    local ok, v = pcall(st.batonPassChooser, b.side, candidates)
    for _, c in ipairs(candidates) do if ok and c == tonumber(v) then slot = c end end
  elseif (st.link or b.side == "player") and st.interactiveChoices and coroutine.running() then
    local v = tonumber(coroutine.yield({ kind = "baton_pass", side = b.side, battler = b.id, candidates = candidates }))
    for _, c in ipairs(candidates) do if c == v then slot = c end end
  elseif b.side == "enemy" then
    local pick = Engine.mostSuitableMon(st, ad, st.double and b.id or "enemy")
    for _, c in ipairs(candidates) do if c == pick then slot = c end end
  end
  local nb = Engine.performSwitch(st, ad, who, slot, { reason = opts and opts.random and "roar" or "switch" })
  if nb then
    local okS, SwitchSeq = pcall(env.require, "src.core.game3.battle.switch_seq")
    local okT, BattleText = pcall(env.require, "src.core.game3.battle.battle_text")
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
-- a Gen 3 move as the family sees it: { id, type (name), power, category, priority }
function GA:moveDef(moveId)
  local env = self.env
  local okM, Moves = pcall(env.require, "src.core.game3.battle.moves")
  local num = tonumber(moveId) or (okM and Moves.numForName and Moves.numForName(moveId))
  return env.moveView(num)
end

-- ------------------------------------------------------------------ the hooks (at load)
-- They act once Held.install has run (Held._env).
function Held.hooks(mod)
  -- damage: both sides' items, Focus Sash, the immunities
  pcall(function()
    mod.hooks:wrap("battle.damage", function(nextFn, c)
      if not Held._env then return nextFn(c) end
      local ad = Held._env.adapterNow()
      if not (Held._env and ad and type(c) == "table" and type(c.user) == "table" and type(c.target) == "table") then
        return nextFn(c)
      end
      local A = Held._env.A_of(ad)
      local m = Held._env.view(c.move, tonumber(c.moveNum))
      -- immunities before the formula
      if Held._core.hooks.immune and Held._core:ask("immune", A, c.user, c.target, m) then
        return 0, { effectiveness = 0, critical = false, typeFlags = { immune = true, super = false, notVery = false } }
      end
      local dmg, info = nextFn(c)
      dmg = tonumber(dmg) or 0
      if dmg > 0 and type(info) == "table" and (tonumber(info.effectiveness) or 1) > 0 then
        local k = Held._core:fold("damageMult", 1, A, c.user, c.target, m,
          { typeMult = math.floor((tonumber(info.effectiveness) or 1) * 10 + 0.5), crit = info.critical })
        -- Utility Umbrella: the rain and sun's boost or cut undone
        local w = A:weather()
        if (w == "rain" or w == "sun") and (Held._core:ask("ignoresWeather", A, c.user) or Held._core:ask("ignoresWeather", A, c.target)) then
          if (w == "rain" and m.type == "WATER") or (w == "sun" and m.type == "FIRE") then k = k / 1.5 end
          if (w == "rain" and m.type == "FIRE") or (w == "sun" and m.type == "WATER") then k = k * 2 end
        end
        if k ~= 1 then dmg = math.max(1, math.floor(dmg * k)) end
        if Held._core.hooks.damageCap then
          local most = Held._core:ask("damageCap", A, c.user, c.target, m, dmg)
          if most then dmg = math.max(0, math.min(dmg, most)) end
        end
      end
      return dmg, info
    end)
  end)

  -- accuracy and misses
  pcall(function()
    mod.hooks:wrap("battle.accuracy", function(nextFn, c)
      if not Held._env then return nextFn(c) end
      local ad = Held._env.adapterNow()
      if not (Held._env and ad and type(c) == "table" and type(c.user) == "table") then return nextFn(c) end
      local A = Held._env.A_of(ad)
      local m = Held._env.view(c.move, tonumber(c.moveNum))
      if tonumber(c.accuracy) and Held._core.hooks.accuracyScale then
        local k = Held._core:fold("accuracyScale", 1, A, c.user, c.target, m)
        if k ~= 1 then c.accuracy = math.floor(c.accuracy * k) end
      end
      local hit = nextFn(c)
      if hit == false and Held._core.hooks.missed then pcall(Held._core.fire, Held._core, "missed", A, c.user, c.target, m) end
      return hit
    end)
    mod.hooks:wrap("battle.crit", function(nextFn, c)
      if not Held._env then return nextFn(c) end
      local ad = Held._env.adapterNow()
      if Held._env and ad and type(c) == "table" and type(c.attacker) == "table" and Held._core.hooks.forceCrit then
        local ok, yes = pcall(Held._core.ask, Held._core, "forceCrit", Held._env.A_of(ad), c.attacker)
        if ok and yes then return true end
      end
      return nextFn(c)
    end)
    mod.hooks:wrap("battle.charge_required", function(nextFn, c)
      if not Held._env then return nextFn(c) end
      local ad = Held._env.adapterNow()
      if Held._env and ad and type(c) == "table" and type(c.user) == "table" and Held._core.hooks.skipCharge then
        local ok, skip = pcall(Held._core.ask, Held._core, "skipCharge", Held._env.A_of(ad), c.user, Held._env.view(c.move))
        if ok and skip then return false end
      end
      return nextFn(c)
    end)
  end)

end

-- ------------------------------------------------------------------ effects (on game.ready)
-- opts: { mod, require, log, state (Held.register's), effects (src/held/effects.lua), Core
-- (src/gen12/mech/core.lua), flags (data/move_flags.lua), abilities (RealAbilities) }
function Held.install(opts)
  local require, log = opts.require, opts.log
  local state = opts.state
  if not (state and next(state.byId)) then return false end
  local core = opts.Core.new({ generation = 3, log = log })
  local env = { require = require, core = core, byId = state.byId, byIndex = state.byIndex }
  local okM, Moves = pcall(require, "src.core.game3.battle.moves")
  local G3ok, G3 = pcall(require, "src.mods.Gen3Compat")
  local physical = { [0] = true, true, true, true, true, true, true, true, true }   -- 0-8 by type
  local views = {}
  function env.moveView(num)
    num = tonumber(num)
    if not num then return nil end
    local v = views[num]
    if v then return v end
    local okG, rec = false, nil
    if okM and Moves.get then okG, rec = pcall(Moves.get, num) end
    if not okG then rec = nil end
    local name = (rec and rec.id) or (okM and Moves.constName and Moves.constName(num))
      or (G3ok and G3.moveName and G3.moveName(num)) or tostring(num)
    local t = tonumber(rec and rec.type) or 0
    v = { id = name, num = num, type = TYPE_NAME[t] or "NORMAL", power = tonumber(rec and rec.power) or 0,
      priority = tonumber(rec and rec.priority) or 0, category = rec and rec.category }
    v.category = v.category or ((v.power == 0) and "status" or (physical[t] and "physical" or "special"))
    views[num] = v
    return v
  end
  local function view(move, num)
    if type(move) == "table" then
      num = num or tonumber(move.numId) or tonumber(move.num)
      if not num and move.id and okM and Moves.numForName then num = Moves.numForName(move.id) end
    end
    local v = env.moveView(num)
    if v then return v end
    local t = type(move) == "table" and tonumber(move.type) or 0
    return { id = type(move) == "table" and move.id or tostring(move), type = TYPE_NAME[t] or "NORMAL",
      power = type(move) == "table" and tonumber(move.power) or 0, category = physical[t] and "physical" or "special" }
  end
  env.view = view

  -- the family's helpers this game answers itself
  local Battle
  local function adapterNow()
    if not Battle then
      local ok, B = pcall(require, "src.core.game3.battle")
      Battle = ok and B or nil
    end
    return Battle and Battle._adapter
  end
  core.STATS = { "attack", "defense", "spAtk", "spDef", "speed", "accuracy", "evasion" }
  core.abilityOf = function(A, b) local ok, n = pcall(A.ad.abilityOf, A.ad, b); return ok and n or nil end
  core.natureDown = function(A, b)
    local p = tonumber(b and b.mon and b.mon.personality)
    if not p then return nil end
    local i = p % 25
    local up, down = math.floor(i / 5) + 1, i % 5 + 1
    if up == down then return nil end
    return ({ "attack", "defense", "speed", "spAtk", "spDef" })[down]
  end
  -- Booster Energy: an ability that would boost, not boosting yet
  core.boosterReady = function(A, b)
    local RA = opts.abilities
    local ab = core.abilityOf(A, b)
    if not (ab == "PROTOSYNTHESIS" or ab == "QUARK_DRIVE") or b.__ndxBooster then return false end
    return not (RA and RA.boosterOn and RA.boosterOn(A.ad, ab, nil))
  end
  core.terrain = function(A)
    local f = A.ad._st and A.ad._st.__ndxField
    return f and (f.terrainTurns or 0) > 0 and f.terrain or nil
  end
  local okFx, err = pcall(opts.effects, core, { generation = 3, byId = state.byId, flags = opts.flags })
  if not okFx then
    if log then log:warn("held items have no effects: %s", tostring(err)) end
    return false
  end
  local function A_of(ad) return Held.adapter(ad, env) end
  env.A_of, env.adapterNow, env.core = A_of, adapterNow, core

  local okD, Damage = pcall(require, "src.core.game3.battle.damage")
  local okH, Hit = pcall(require, "src.core.game3.battle.effects.hit")
  local okE, Effects = pcall(require, "src.core.game3.battle.effects")
  local okEn, Engine = pcall(require, "src.core.game3.battle.engine")
  local okR, Residuals = pcall(require, "src.core.game3.battle.residuals")
  local okRu, Rules = pcall(require, "src.core.game3.battle.rules")
  local okHI, HeldItems = pcall(require, "src.core.game3.battle.held_items")
  local mod = opts.mod

  -- process-wide wraps read the newest install's state through this hub (games switch in-process)
  local hub = (okHI and HeldItems.__ndxHeldHub) or {}
  if okHI then HeldItems.__ndxHeldHub = hub end
  -- the Choice Scarf / Specs: the cart's lock, without the cart's Attack boost
  if okHI and type(HeldItems.of) == "function" and not HeldItems.__ndxHeld then
    HeldItems.__ndxHeld = true
    local of = HeldItems.of
    HeldItems.of = function(b, trigger, st, ...)
      local he, param, item = of(b, trigger, st, ...)
      if he == CHOICE_BAND and trigger == "damage" and hub.env then
        local row = hub.env.byIndex[tonumber(item) or 0]
        if row and row.effect.kind == "choice" and row.effect.stat ~= "attack" then return 0, 0, item end
      end
      return he, param, item
    end
  end

  -- what a move did, from before to after: stages for the snapshot, HP for damageDealt
  function env.before(ad, user, target)
    local A = env.A_of(ad)
    if not A then return nil end
    local snap = {}
    for _, b in ipairs({ user, target }) do
      if type(b) == "table" and b.stages then
        local s = {}
        for _, st in ipairs(core.STATS) do s[st] = b.stages[st] or 0 end
        snap[b] = s
      end
    end
    A:field().heldSnap = snap
    return A, type(target) == "table" and ad:hp(target) or nil
  end
  function env.after(ad, A, user, target, hpBefore, num, move)
    if not A then return end
    local m = view(move, num)
    if hpBefore and type(target) == "table" and target ~= user then
      local dealt = hpBefore - ad:hp(target)
      if dealt > 0 and core.hooks.damageDealt then
        pcall(core.fire, core, "damageDealt", A, { user = user, target = target, damage = dealt, move = m })
      end
    end
    local f = A:field()
    f.moved = f.moved or {}
    if type(user) == "table" then f.moved[user.side] = A:turn() end
    if core.hooks.afterMove then pcall(core.fire, core, "afterMove", A, user, target, m and m.num or num) end
  end

  if okH and type(Hit.run) == "function" and not Hit.__ndxHeld then
    Hit.__ndxHeld = true
    local run = Hit.run
    Hit.run = function(M, ...)
      if not (hub.env and type(M) == "table" and M.adapter and M.user) then return run(M, ...) end
      local ad = M.adapter
      local okB, A, hp0 = pcall(hub.env.before, ad, M.user, M.target)
      M.__ndxHeldAfter = true
      local r = { run(M, ...) }
      if okB then pcall(hub.env.after, ad, A, M.user, M.target, hp0, tonumber(M.mnum), M.move) end
      return (unpack or table.unpack)(r)
    end
  end
  if okE and type(Effects.run) == "function" and not Effects.__ndxHeld then
    Effects.__ndxHeld = true
    local run = Effects.run
    Effects.run = function(id, ad, user, target, move, moveId, moveCtx, ...)
      local M = type(moveCtx) == "table" and moveCtx or nil
      if not (hub.env and type(ad) == "table" and type(user) == "table") or (M and M.__ndxHeldAfter) then
        return run(id, ad, user, target, move, moveId, moveCtx, ...)
      end
      -- Assault Vest: no status moves
      local A = hub.env.A_of(ad)
      local r0 = A and hub.env.byIndex[tonumber(user.item) or 0]
      if r0 and r0.effect.kind == "assaultVest" then
        ad:say(wrapText(A:name(user) .. " can't use status moves while holding its " .. r0.name .. "!"))
        if M then M.failed = true end
        return true
      end
      local num = tonumber(M and M.mnum) or tonumber(moveId)
      -- Safety Goggles: powder moves miss
      if type(target) == "table" and target ~= user then
        local rt = hub.env.byIndex[tonumber(target.item) or 0]
        local mv = hub.env.view(move, num)
        if rt and rt.effect.kind == "safetyGoggles" and hub.env.core.moveFlag and hub.env.core.moveFlag("powder", mv) then
          ad:say(wrapText("It doesn't affect " .. A:name(target) .. "..."))
          if M then M.failed = true end
          return true
        end
      end
      local okB, A2, hp0 = pcall(hub.env.before, ad, user, target)
      if M then M.__ndxHeldAfter = true end
      local r = { run(id, ad, user, target, move, moveId, moveCtx, ...) }
      if okB then pcall(hub.env.after, ad, A2, user, target, nil, num, move) end
      return (unpack or table.unpack)(r)
    end
  end

  -- turn order: Speed multipliers (and the move-last / move-first items, inside their bracket)
  local RA = opts.abilities
  if type(RA) == "table" and type(RA.speedModifiers) == "table" then
    RA.speedModifiers.heldModern = function(ad, b)
      if not (hub.env and ad and b) then return 1 end
      local A = hub.env.A_of(ad)
      local k = hub.env.core:fold("speed", 1, A, b)
      local r = hub.env.byIndex[tonumber(b.item) or 0]
      if r then
        local e = r.effect.kind
        if e == "moveLast" then k = k * 0.0001 end
        if e == "berryCustap" and ad:hp(b) * 4 <= ad:maxHp(b) and ad:hp(b) > 0 then
          A:setItem(b, nil)
          A:say(A:text("%s's %s let it move first!", A:name(b), r.name))
          k = k * 10000
        end
      end
      return k
    end
  elseif log then
    log:warn("held items: Choice Scarf, Iron Ball and the like do not change the turn order (the real abilities are off)")
  end

  -- switching in: Heavy-Duty Boots, then the items that act on entry; Shed Shell
  if okEn and type(Engine.switchInEffects) == "function" and not Engine.__ndxHeld then
    Engine.__ndxHeld = true
    local switchIn = Engine.switchInEffects
    Engine.switchInEffects = function(st, ad, b, o, ...)
      if hub.env and ad and type(b) == "table" and o and o.spikes then
        local r = hub.env.byIndex[tonumber(b.item) or 0]
        if r and r.effect.kind == "heavyDutyBoots" then
          local o2 = {}
          for k, v in pairs(o) do o2[k] = v end
          o2.spikes = false
          o = o2
        end
      end
      local res = { switchIn(st, ad, b, o, ...) }
      if hub.env and ad and type(b) == "table" and hub.env.core.hooks.switchedIn then
        pcall(hub.env.core.fire, hub.env.core, "switchedIn", hub.env.A_of(ad), { battler = b })
      end
      return (unpack or table.unpack)(res)
    end
    if type(Engine.canSwitch) == "function" then
      local canSwitch = Engine.canSwitch
      Engine.canSwitch = function(st, ad, b, ...)
        local who = b or (st and st.player)
        if hub.env and type(who) == "table" then
          local r = hub.env.byIndex[tonumber(who.item) or 0]
          if r and r.effect.kind == "shedShell" then return true end
        end
        return canSwitch(st, ad, b, ...)
      end
    end
  end

  -- the end of the turn: a field phase of ours, before the weather's
  if okR and okRu and type(Residuals.register) == "function" and not Rules.__ndxHeld then
    Rules.__ndxHeld = true
    local at = #Rules.FIELD_PHASES_ORDER
    for i, name in ipairs(Rules.FIELD_PHASES_ORDER) do
      if name == "weather_continue" then at = i - 1 end
    end
    table.insert(Rules.FIELD_PHASES_ORDER, at + 1, "ndx_held")
    Residuals.register("ndx_held", function(ctx)
      if hub.env and ctx and ctx.adapter and hub.env.core.hooks.endTurn then
        pcall(hub.env.core.fire, hub.env.core, "endTurn", hub.env.A_of(ctx.adapter))
      end
    end)
  end
  Held._env, Held._core = env, core
  hub.env = env
  if log then log:info("held items: effects on (%d items)", #state.registered) end
  return true
end

return Held
