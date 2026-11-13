-- Evolutions on Gen 1 / Gen 2.
--
-- Every registered species and form gets its evolutions, and each cart species gets the newer
-- ones it lacks (data/gen12/crossgen.lua: Golbat -> Crobat on Red, Eevee -> Leafeon everywhere),
-- added after the cart's own rows. Each data step becomes the game's own row:
--   Gold   EVOLVE_LEVEL / _ITEM / _TRADE (+ held item) / _HAPPINESS (+ MORNDAY / NITE) / _STAT
--   Red    LEVEL / ITEM / TRADE, plus FRIENDSHIP, a method this mod registers (Red has no
--          friendship: a hidden counter on the Pokemon stands in, see below)
-- Red has no held items, so a trade item or a held item is used on the Pokemon like a stone.
--
-- Rows are strict records, so a step's other conditions (`when`, the same keys as
-- src/conditional_evos.lua, whose `qualifies` decides them) live in a side table keyed by
-- source > target # method, and a wrap of the evolution.check hook (both games run every row
-- through it, the first row that passes wins) lets a row through only when they hold. A
-- species' rows with conditions come first, highest priority first, so a plain row at the same
-- level (Midday Lycanroc) only fires when none of them does.
-- The facts: time from the clock (Red: the device's hours, src/clock.lua; Gold: its own
-- time of day when the check has one), friendship (Red: the counter; Gold: happiness), the held
-- item (Gold) or the item being used (Red), gender (Gold's own rule from the DVs, on both), a
-- stable 1-in-n pick from the DVs, the moves it knows, the party, coins, and counters kept on
-- the Pokemon (`mon.extra.national_dex_gen3`): steps walked as the lead, uses of a move, critical
-- hits in its last battle.
-- What these games cannot know is left out: rain, the battle's terrain (Burmy's female cloak is
-- Plant), and recoil taken (White-Striped Basculin evolves at level 36 instead). A `knows` move
-- the game does not have makes the step a plain level-up at its level.
-- A held item that a level-up evolution asks for is used up by it (Gold), and Gimmighoul's coins
-- are spent, as in the newer games.

local Evolutions = {}

Evolutions.FRIENDSHIP_TO_EVOLVE = 220
Evolutions.UNTRACKED_LEVEL = 36
Evolutions.BAG = "national_dex_gen3"

local GEN1 = {
  EVO_LEVEL = "LEVEL", EVO_ITEM = "ITEM", EVO_TRADE = "TRADE", EVO_TRADE_ITEM = "ITEM",
  EVO_FRIENDSHIP = "FRIENDSHIP", EVO_FRIENDSHIP_DAY = "FRIENDSHIP",
  EVO_FRIENDSHIP_NIGHT = "FRIENDSHIP", EVO_STAT = "LEVEL",
}
local GEN2 = {
  EVO_LEVEL = "EVOLVE_LEVEL", EVO_ITEM = "EVOLVE_ITEM", EVO_TRADE = "EVOLVE_TRADE",
  EVO_TRADE_ITEM = "EVOLVE_TRADE", EVO_FRIENDSHIP = "EVOLVE_HAPPINESS",
  EVO_FRIENDSHIP_DAY = "EVOLVE_HAPPINESS", EVO_FRIENDSHIP_NIGHT = "EVOLVE_HAPPINESS",
  EVO_STAT = "EVOLVE_STAT",
}

-- the type numbering src/conditional_evos.lua's `party.type` compares against
local TYPE_IDS = {
  NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4, ROCK = 5, BUG = 6, GHOST = 7,
  STEEL = 8, FIRE = 10, WATER = 11, GRASS = 12, ELECTRIC = 13, PSYCHIC = 14, ICE = 15,
  DRAGON = 16, DARK = 17, FAIRY = 18,
}

function Evolutions.key(source, row)
  return tostring(source) .. ">" .. tostring(row.species or row.into) .. "#" .. tostring(row.method)
end

-- One data step -> the game's row and its conditions (or nil), or nil when the step cannot
-- exist here (its target or item is missing, or it needs what the game cannot know).
-- ctx: { generation, targetOf(step) -> id, itemId(slug) -> id, direct(n) -> move id }
function Evolutions.convert(step, ctx)
  local target = ctx.targetOf(step)
  if not target then return nil end
  local gen = ctx.generation
  local method = (gen == 1 and GEN1 or GEN2)[step.method]
  if not method then return nil end
  local row, cond = { method = method }, {}
  if gen == 1 then row.species = target else row.into = target end

  if step.method == "EVO_LEVEL" or step.method == "EVO_STAT" then
    row.level = step.level or 1
  end
  if step.method == "EVO_STAT" then
    if gen == 2 then row.comparison = step.comparison else cond.stat = step.comparison end
  end
  if step.method == "EVO_FRIENDSHIP_DAY" then
    if gen == 2 then row.time = "MORNDAY" else cond.time = "day" end
  elseif step.method == "EVO_FRIENDSHIP_NIGHT" then
    if gen == 2 then row.time = "NITE" else cond.time = "night" end
  end
  if step.item then
    local id = ctx.itemId(step.item)
    if not id then return nil end
    row.item = id
  end

  for k, v in pairs(step.when or {}) do
    if k == "knows" then
      local ids = {}
      for _, n in ipairs(v) do
        local id = ctx.direct(n)
        if id then ids[#ids + 1] = id end
      end
      if #ids > 0 then cond.knows = ids end           -- none here: a plain level-up
    elseif k == "hold" then
      local ids = {}
      for _, slug in ipairs(type(v) == "table" and v or { v }) do
        local id = ctx.itemId(slug)
        if id then ids[#ids + 1] = id end
      end
      if #ids == 0 then return nil end
      cond.hold = ids
      if gen == 1 then
        -- no held items: use it instead, at the step's level or later
        if (row.level or 1) > 1 then cond.minLevel = row.level end
        row.method, row.item, row.level = "ITEM", ids[1], nil
      end
    elseif k == "uses" then
      local id = ctx.direct(v.move)
      if id then cond.uses = { move = id, count = v.count } end
    elseif k == "terrain" then
      if v ~= "plant" then return nil end             -- no battle ground here: the Plant cloak
    elseif k == "recoil" then
      row.level = math.max(row.level or 1, Evolutions.UNTRACKED_LEVEL)
    elseif k ~= "weather" then                        -- no rain on these games
      cond[k] = v
    end
  end
  if next(cond) == nil then cond = nil end
  return row, cond
end

-- rows with conditions first (highest priority first, data order kept), then the plain ones
function Evolutions.order(entries)
  for i, e in ipairs(entries) do e.n = i end
  table.sort(entries, function(a, b)
    local ca, cb = a.cond ~= nil, b.cond ~= nil
    if ca ~= cb then return ca end
    local pa, pb = a.cond and a.cond.priority or 0, b.cond and b.cond.priority or 0
    if pa ~= pb then return pa > pb end
    return a.n < b.n
  end)
  return entries
end

-- ---------------------------------------------------------------- the Pokemon's own counters

function Evolutions.bag(mon, create)
  local extra = mon.extra
  if not extra then
    if not create then return nil end
    extra = {}
    mon.extra = extra
  end
  local bag = extra[Evolutions.BAG]
  if not bag and create then
    bag = {}
    extra[Evolutions.BAG] = bag
  end
  return bag
end

-- Red's hidden friendship: the species' base friendship until something changes it
function Evolutions.friendship(mon, base)
  local bag = Evolutions.bag(mon, false)
  return (bag and bag.friendship) or base or 70
end

function Evolutions.addFriendship(mon, base, amount)
  local bag = Evolutions.bag(mon, true)
  local value = (bag.friendship or base or 70) + amount
  bag.friendship = math.max(0, math.min(255, value))
  return bag.friendship
end

-- Gold's gender rule, on both games (pokecrystal engine/pokemon/mon_stats.asm GetGender): the
-- Attack and Speed DVs as one byte against the species' ratio. "F", "M" or nil (genderless).
function Evolutions.gender(ratio, dvs)
  if ratio == nil or ratio == 255 then return nil end
  if ratio == 0 then return "M" end
  if ratio == 254 then return "F" end
  return ((dvs.attack or 0) * 16 + (dvs.speed or 0)) <= ratio and "F" or "M"
end

-- Gold's (and the newer games') level-up gain: +5 below 100, +3 below 200, +2 after
function Evolutions.levelUpGain(value)
  if value < 100 then return 5 end
  if value < 200 then return 3 end
  return 2
end

-- ---------------------------------------------------------------- install

-- opts: { mod, generation, require, conditional (src/conditional_evos.lua), clock
--         (src/clock.lua), species = Species state, crossgen, cartIdOf, itemId(slug),
--         direct(n), log }
function Evolutions.install(opts)
  local mod, gen, req, log = opts.mod, opts.generation, opts.require or require, opts.log
  local Conditional, Clock = opts.conditional, opts.clock
  local pokemon = mod.content.pokemon
  local maxDex = gen == 1 and 151 or 251
  local state = { generation = gen, conds = {}, byPair = {}, rows = {}, bridges = {}, added = 0,
    dropped = 0,
    watch = { steps = {}, uses = {}, crits = {} }, baseFriendship = {}, genderRatio = {} }

  local byDex, byId = opts.species.byDex, opts.species.byId
  local function targetOf(step)
    if step.targetForm then return byId[step.targetForm] and step.targetForm or nil end
    local entry = byDex[step.target]
    if entry then return entry.id end
    if step.target and step.target <= maxDex then return opts.cartIdOf[step.target] end
    return nil
  end
  local ctx = { generation = gen, targetOf = targetOf, itemId = opts.itemId, direct = opts.direct }

  local function build(source, steps)
    local entries = {}
    for _, step in ipairs(steps) do
      local row, cond = Evolutions.convert(step, ctx)
      if row then entries[#entries + 1] = { row = row, cond = cond }
      else state.dropped = state.dropped + 1 end
    end
    Evolutions.order(entries)
    local rows = {}
    for _, e in ipairs(entries) do
      rows[#rows + 1] = e.row
      if e.cond then
        state.conds[Evolutions.key(source, e.row)] = e.cond
        state.byPair[source .. ">" .. (e.row.species or e.row.into)] = e.cond
        if e.cond.steps then state.watch.steps[source] = true end
        if e.cond.uses then state.watch.uses[source] = e.cond.uses.move end
        if e.cond.crits then state.watch.crits[source] = true end
      end
    end
    return rows
  end

  local firstError
  local function patch(id, rows)
    if #rows == 0 then return end
    local ok, err = pcall(pokemon.patch, pokemon, id, { evolutions = rows })
    if ok then
      state.rows[id] = rows
      state.added = state.added + #rows
    else
      firstError = firstError or (id .. ": " .. tostring(err))
    end
  end

  -- this mod's species and forms
  for id, entry in pairs(byId) do
    state.baseFriendship[id] = entry.data.friendship
    state.genderRatio[id] = entry.data.genderRatio      -- Red's records carry none
    patch(id, build(id, entry.data.evolutions or {}))
  end
  -- the cart's species: their own rows first, then the newer evolutions they lack here
  local bySource = {}
  for _, step in ipairs(opts.crossgen) do
    if step.source <= maxDex and (step.targetForm or (step.target and step.target > maxDex)) then
      bySource[step.source] = bySource[step.source] or {}
      table.insert(bySource[step.source], step)
    end
  end
  for dex, steps in pairs(bySource) do
    local id = opts.cartIdOf[dex]
    local current = id and pokemon:get(id)
    if current then
      local rows = {}
      for _, row in ipairs(current.evolutions or {}) do
        local copy = {}
        for k, v in pairs(row) do copy[k] = v end
        rows[#rows + 1] = copy
      end
      for _, row in ipairs(build(id, steps)) do
        rows[#rows + 1] = row
        -- the API's bridges: a cart species' step into a newer one (src/api.lua)
        state.bridges[#state.bridges + 1] = { sourceId = id, sourceDex = dex,
          species = row.species or row.into, level = row.level, method = row.method }
      end
      patch(id, rows)
    end
  end
  if firstError and log then log:warn("some evolutions are missing: %s", firstError) end

  -- ---------------------------------------------------------------- the facts

  local function game() return mod.game end
  local function party()
    local g = game()
    return g and g.save and g.save.party or {}
  end
  local function coins()
    local g = game()
    local save = g and g.save
    if not save then return 0 end
    if gen == 1 then return save.coins or 0 end
    return save.player and save.player.coins or 0
  end
  local function data()
    local g = game()
    return g and g.data
  end

  local function facts(mon, opt)
    local dvs = mon.dvs or {}
    local dvValue = (dvs.attack or 0) * 4096 + (dvs.defense or 0) * 256 + (dvs.speed or 0) * 16
      + (dvs.special or 0)
    local d = opt.data or data()
    local def = d and d.pokemon and d.pokemon[mon.species]
    local gender
    local ratio = def and def.genderRatio or state.genderRatio[mon.species]
    if ratio then gender = Evolutions.gender(ratio, dvs) end
    local moves = {}
    for _, m in ipairs(mon.moves or {}) do moves[m.id or m] = true end
    local partySpecies, partyTypes = {}, {}
    for _, other in ipairs(opt.party or party()) do
      if other ~= mon and other.species then
        partySpecies[other.species] = true
        local odef = d and d.pokemon and d.pokemon[other.species]
        for _, t in ipairs(odef and odef.types or {}) do
          local n = TYPE_IDS[(t:gsub("_TYPE$", ""))]
          if n then partyTypes[n] = true end
        end
      end
    end
    local night
    local tod = opt.timeOfDay
    if not tod and gen == 2 then
      -- Gold's own clock when the check carries none (a stone's use)
      local okP, Palettes = pcall(req, "src.world.gen2.Palettes")
      if okP and type(Palettes) == "table" and Palettes.clockDaytime then
        local okD, now = pcall(Palettes.clockDaytime)
        if okD then tod = now end
      end
    end
    if tod then night = tod == "NITE" or tod == "NITE_F"
    else night = Clock.isNight(nil, "device") end
    local bag = Evolutions.bag(mon, false) or {}
    local stats = mon.stats or {}
    return {
      held = opt.held or (gen == 2 and mon.item) or 0,
      night = night, dusk = Clock.isDusk(nil, "device"),
      friendship = gen == 1 and Evolutions.friendship(mon, state.baseFriendship[mon.species])
        or (mon.happiness or 0),
      personality = dvValue * 65536, gender = gender, moves = moves,
      partySpecies = partySpecies, partyTypes = partyTypes,
      speciesSlot = function(name) return name end,
      uses = bag.moveUses or {}, steps = bag.stepsAsLead or 0, coins = coins(),
      crits = bag.crits or 0, hpLost = (stats.hp or 0) - (mon.hp or 0), recoil = 0,
    }
  end

  local function same(id) return id end
  local function holdsFor(cond, mon, opt)
    if cond.stat then
      local s = mon.stats or {}
      local a, b = s.attack or 0, s.defense or 0
      local cmp = a == b and "ATK_EQ_DEF" or a < b and "ATK_LT_DEF" or "ATK_GT_DEF"
      if cmp ~= cond.stat then return false end
    end
    if cond.minLevel and (mon.level or 1) < cond.minLevel then return false end
    return Conditional.qualifies({ when = cond }, facts(mon, opt), same)
  end
  state.qualifies = holdsFor

  -- every row goes through evolution.check (Red: game, mon, row, trigger; Gold: data, mon,
  -- row, ctx); a row with conditions passes only when they hold
  mod.hooks:wrap("evolution.check", function(nextFn, a, mon, row, trig)
    local ok = nextFn(a, mon, row, trig)
    if not ok or not mon or not row then return ok end
    local cond = state.conds[Evolutions.key(mon.species, row)]
    if not cond then return ok end
    local opt = { timeOfDay = type(trig) == "table" and trig.timeOfDay or nil }
    if gen == 2 then opt.data = a; if type(trig) == "table" and trig.force then opt.held = trig.item end
    else opt.data = a and a.data end
    return holdsFor(cond, mon, opt)
  end)

  -- Red: friendship decides FRIENDSHIP rows, on a level-up
  if gen == 1 then
    local methods = mod.content.evolution_methods
    if methods:get("FRIENDSHIP") == nil then
      pcall(methods.register, methods, "FRIENDSHIP", {
        check = function(_, mon, _, trigger)
          return trigger and trigger.kind == "levelup"
            and Evolutions.friendship(mon, state.baseFriendship[mon.species]) >= Evolutions.FRIENDSHIP_TO_EVOLVE
        end,
        describe = function() return "Friendship" end,
      })
    end
  end

  -- ---------------------------------------------------------------- events
  local events = mod.events
  local stepsTaken = 0
  events:on("world.stepped", function()
    local list = party()
    local lead = list[1]
    if lead and lead.species and state.watch.steps[lead.species] then
      local bag = Evolutions.bag(lead, true)
      bag.stepsAsLead = (bag.stepsAsLead or 0) + 1
    end
    if gen == 1 then
      -- friendship grows as the party walks: +1 every 256 steps (Gold's own rate)
      stepsTaken = stepsTaken + 1
      if stepsTaken >= 256 then
        stepsTaken = 0
        for _, mon in ipairs(list) do
          if mon.species then Evolutions.addFriendship(mon, state.baseFriendship[mon.species], 1) end
        end
      end
    end
  end)
  if gen == 1 then
    events:on("pokemon.level_up", function(ev)
      local mon = ev and ev.mon
      if mon and mon.species then
        local base = state.baseFriendship[mon.species]
        Evolutions.addFriendship(mon, base, Evolutions.levelUpGain(Evolutions.friendship(mon, base)))
      end
    end)
  end
  local function partyMon(battler)
    if type(battler) ~= "table" then return nil end
    return battler.mon or battler
  end
  events:on("battle.started", function()
    for _, mon in ipairs(party()) do
      local bag = Evolutions.bag(mon, false)
      if bag and bag.crits then bag.crits = 0 end
    end
  end)
  events:on("battle.move_used", function(ev)
    local mon = partyMon(ev and ev.user)
    local want = mon and mon.species and state.watch.uses[mon.species]
    local id = ev and (ev.moveId or (ev.move and ev.move.id))
    if want and id == want then
      local bag = Evolutions.bag(mon, true)
      bag.moveUses = bag.moveUses or {}
      bag.moveUses[id] = (bag.moveUses[id] or 0) + 1
    end
  end)
  events:on("battle.damage_dealt", function(ev)
    local mon = partyMon(ev and ev.user)
    if ev and ev.crit and mon and mon.species and state.watch.crits[mon.species] then
      local bag = Evolutions.bag(mon, true)
      bag.crits = (bag.crits or 0) + 1
    end
  end)
  events:on("pokemon.evolved", function(ev)
    local cond = ev and state.byPair[tostring(ev.fromSpecies) .. ">" .. tostring(ev.toSpecies)]
    if not cond then return end
    if gen == 2 and cond.hold and ev.mon then ev.mon.item = nil end
    if cond.coins then
      local g = game()
      local save = g and g.save
      if save and gen == 1 then save.coins = math.max(0, (save.coins or 0) - cond.coins)
      elseif save and save.player then save.player.coins = math.max(0, (save.player.coins or 0) - cond.coins) end
    end
  end)

  -- ---------------------------------------------------------------- using an item
  -- Red: the effect of every item src/gen12/items.lua registers. The first ITEM row that names
  -- the item (or, for a held-item step, lists it) and whose conditions hold.
  function state.useGen1(c)
    local target, d = c.target, c.data
    local function noEffect()
      local ok, RomText = pcall(req, "src.core.RomText")
      local text = ok and RomText and select(2, pcall(RomText, d, "_ItemUseNoEffectText",
        "It won't have\nany effect.")) or "It won't have\nany effect."
      return "failed", { text }
    end
    if not target then return noEffect() end
    local def = d and d.pokemon and d.pokemon[target.species]
    for _, row in ipairs(def and def.evolutions or {}) do
      if row.method == "ITEM" then
        local cond = state.conds[Evolutions.key(target.species, row)]
        local named = row.item == c.itemId
        if not named and cond and cond.hold then
          for _, id in ipairs(cond.hold) do if id == c.itemId then named = true end end
        end
        if named and (not cond or holdsFor(cond, target, { data = d, held = c.itemId,
            party = c.save and c.save.party })) then
          pcall(function() req("src.core.Sound").play(d, "Heal_Ailment") end)
          return "consumed", nil, { evolveTo = row.species }
        end
      end
    end
    return noEffect()
  end

  -- Gold: a stone this mod registered, run as Gold runs its own (EVOLVE_ITEM forced)
  function state.useGen2(c)
    local function noEffect()
      local ok, IE = pcall(req, "src.core.gen2.ItemEffects")
      local okS, Strings = pcall(req, "src.core.Strings")
      local text = ok and IE.TEXT_NO_EFFECT or "It won't have any effect."
      if okS and Strings then text = Strings(text) end
      return { used = false, text = text }
    end
    if not c.mon or c.mon.item == "EVERSTONE" then return noEffect() end
    local Evolution = req("src.core.gen2.Evolution")
    local entry = Evolution.checkMon(c.data, c.mon, { force = true, item = c.item })
    if not entry then return noEffect() end
    return { used = true, evolution = entry }
  end

  return state
end

return Evolutions
