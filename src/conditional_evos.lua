-- Evolutions that pick their outcome from the Pokemon itself, which Gen 3's
-- method table cannot express: Rockruff -> Lycanroc (Midday / Midnight / Dusk)
-- and Milcery -> Alcremie (a cream by day or night, or Rainbow Swirl).
--
-- Each outcome is an ordinary EVO_LEVEL row in the live species table (so the
-- Pokedex and everything else that lists evolutions sees them), all at the
-- same level. The engine would take the last row that matches, so this wraps
-- the "evolution.check" hook and lets exactly one of the group through: of
-- the steps whose conditions hold, the one with the highest priority.
--
-- A step's conditions are its `when` table (tools/form_list.py):
--   hold        item slug, or a list of them (any): the Pokemon is holding it
--   time        "night" (20:00-04:00), "dusk" (19:00-20:00) or "day" (every hour
--               but night, so dusk counts); see src/clock.lua for the clock the
--               player chose
--   friendship  at least this much
--   pick        { i, n }: the Pokemon's personality falls in bucket i of n -- a
--               stable "1 in n" that gives the same answer on every check
--   gender      "F" or "M": the Pokemon's gender, from its personality
--   recoil      the recoil damage the Pokemon has taken in battle, in total (src/counters.lua)
--   knows       a list of move ids: the Pokemon knows any one of them
--   party       { species = "REMORAID" } or { type = "DARK" }: another Pokemon in the party
--   weather     "rain": the overworld weather is rain, a thunderstorm or a downpour
--   uses        { move = 99, count = 20 }: it has used that move that many times in battle
--   steps       steps walked while it was first in the party (src/counters.lua)
--   coins       Coin Case coins needed; they are spent when it evolves (src/counters.lua)
--   terrain     "plant", "sandy" or "trash": where the last battle was fought (below)
--   priority    higher wins (default 0)
-- The friendship day/night evolutions (Budew, Riolu, Chingling, Snom, ...) are
-- decided here too, from the same clock, so they work on FireRed and LeafGreen
-- and follow the player's clock option instead of the engine's own noon/midnight
-- split.
-- Held items are resolved live through itemIndex on every check, like the
-- evolution items, so another mod's item of the same name works too.

local ConditionalEvos = {}

-- Burmy's cloak follows the ground of its last battle: the engine keeps the battle
-- background's terrain after the fight (src.core.game3.battle.bg, set at the start of
-- every battle and left alone afterwards), so it is still there when the level-up is
-- checked. Grass and water are Plant, sand / mountain / cave are Sandy, and everything
-- else (buildings, gyms, the League, the Frontier) is Trash. Before the first battle
-- the engine's default is a building. A level-up outside a battle (a Rare Candy) uses
-- the last battle's ground.
local TERRAIN_CLASS = {
  GRASS = "plant", LONG_GRASS = "plant", WATER = "plant", POND = "plant",
  UNDERWATER = "plant", PLAIN = "plant",
  SAND = "sandy", MOUNTAIN = "sandy", CAVE = "sandy",
}

function ConditionalEvos.terrain()
  local ok, Bg = pcall(require, "src.core.game3.battle.bg")
  if not (ok and type(Bg) == "table" and type(Bg.terrainId) == "function") then return "trash" end
  local okId, id = pcall(Bg.terrainId)
  local okT, names = pcall(function() return Bg.TERRAIN end)
  if not (okId and okT and type(names) == "table") then return "trash" end
  for name, value in pairs(names) do
    if value == id and TERRAIN_CLASS[name] then return TERRAIN_CLASS[name] end
  end
  return "trash"
end

-- a mon's held item as an item number (the field is a number or an id)
local function heldNumber(mon)
  local raw = mon and (mon.item or mon.heldItem)
  if raw == nil then return 0 end
  local n = tonumber(raw)
  if n then return n end
  local ok, ItemsData = pcall(require, "src.core.game3.items_data")
  if ok and ItemsData and ItemsData.toNumericId then
    local ok2, id = pcall(ItemsData.toNumericId, raw)
    if ok2 and tonumber(id) then return tonumber(id) end
  end
  return 0
end

local function holds(want, held, itemIndex)
  if held == 0 then return false end
  if type(want) == "string" then return itemIndex(want) == held end
  for _, slug in ipairs(want) do
    if itemIndex(slug) == held then return true end
  end
  return false
end

local TYPE_IDS = {
  NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4, ROCK = 5, BUG = 6, GHOST = 7,
  STEEL = 8, FIRE = 10, WATER = 11, GRASS = 12, ELECTRIC = 13, PSYCHIC = 14, ICE = 15,
  DRAGON = 16, DARK = 17,
}

-- Do a step's conditions hold? facts: { held, night, friendship, personality, gender,
-- terrain, recoil, moves (set of move ids), partySpecies (set of slots), partyTypes (set of
-- type ids), speciesSlot(name), rain, uses, steps, coins }
function ConditionalEvos.qualifies(step, facts, itemIndex)
  local when = step.when
  if not when then return true end
  if when.knows then
    local known = false
    for _, id in ipairs(when.knows) do
      if facts.moves and facts.moves[id] then known = true break end
    end
    if not known then return false end
  end
  if when.party then
    if when.party.species then
      local slot = facts.speciesSlot and facts.speciesSlot(when.party.species)
      if not (slot and facts.partySpecies and facts.partySpecies[slot]) then return false end
    end
    if when.party.type then
      local id = TYPE_IDS[when.party.type]
      if not (id and facts.partyTypes and facts.partyTypes[id]) then return false end
    end
  end
  if when.weather == "rain" and not facts.rain then return false end
  if when.uses and ((facts.uses and facts.uses[when.uses.move]) or 0) < when.uses.count then return false end
  if when.steps and (facts.steps or 0) < when.steps then return false end
  if when.coins and (facts.coins or 0) < when.coins then return false end
  if when.hold and not holds(when.hold, facts.held, itemIndex) then return false end
  if when.time == "night" and not facts.night then return false end
  if when.time == "day" and facts.night then return false end
  if when.time == "dusk" and not facts.dusk then return false end
  if when.friendship and facts.friendship < when.friendship then return false end
  if when.gender and facts.gender ~= when.gender then return false end
  if when.terrain and facts.terrain ~= when.terrain then return false end
  if when.recoil and facts.recoil < when.recoil then return false end
  if when.pick then
    local upper = math.floor(facts.personality / 65536) % 65536
    if upper % when.pick[2] ~= when.pick[1] then return false end
  end
  return true
end

-- The step that applies out of a group, or nil. Ties go to the earlier step.
function ConditionalEvos.winner(group, facts, itemIndex)
  local best, bestPriority
  for _, step in ipairs(group) do
    local priority = step.when and step.when.priority or 0
    if (not best or priority > bestPriority) and ConditionalEvos.qualifies(step, facts, itemIndex) then
      best, bestPriority = step, priority
    end
  end
  return best
end

-- species: every registered species and form (bookkeeping from Species.register);
-- bridges: the evolutions added to the cart's own species (Lickitung, Eevee ...), each
-- { sourceSlot, targetSlot, method, level, when }.
-- A group is the steps of one species that compete: every step with conditions, plus the
-- unconditioned level-ups at a level where one of them has some (like Midday Lycanroc).
function ConditionalEvos.groups(species, bridges)
  local out = {}
  local function add(slot, list)
    local levels = {}
    for _, step in ipairs(list) do
      if step.when and step.method == "EVO_LEVEL" then levels[step.level or 0] = true end
    end
    for _, step in ipairs(list) do
      local gated = step.when ~= nil
      local sibling = step.method == "EVO_LEVEL" and levels[step.level or 0]
      if (gated or sibling) and step.targetSlot then
        out[slot] = out[slot] or {}
        table.insert(out[slot], step)
      end
    end
  end
  for _, r in ipairs(species) do add(r.slot, r.evolutions or {}) end
  local bySource = {}
  for _, b in ipairs(bridges or {}) do
    if b.sourceSlot then
      bySource[b.sourceSlot] = bySource[b.sourceSlot] or {}
      table.insert(bySource[b.sourceSlot], b)
    end
  end
  for slot, list in pairs(bySource) do add(slot, list) end
  return out
end

local RAIN = { [3] = true, [5] = true, [13] = true }   -- Weather.RAIN, RAIN_THUNDERSTORM, DOWNPOUR

local function isRaining()
  local ok, Weather = pcall(require, "src.core.game3.weather")
  if not (ok and type(Weather) == "table") then return false end
  local okG, current = pcall(function()
    if type(Weather.get) == "function" then Weather.get() end
    return Weather.current
  end)
  return okG and RAIN[tonumber(current) or -1] == true
end

-- opts.isNight(session), opts.isDusk(session) -> boolean, from the clock the player chose
-- (src/clock.lua)
function ConditionalEvos.install(mod, species, itemIndex, opts)
  local groups = ConditionalEvos.groups(species, opts and opts.bridges)
  local isNight = opts and opts.isNight or function() return false end
  local isDusk = opts and opts.isDusk or function() return false end
  local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
  local function friendship(mon)
    return okP and Pokemon.friendshipOf and Pokemon.friendshipOf(mon) or 0
  end
  mod.hooks:wrap("evolution.check", function(nextFn, game, mon, view, ctx)
    local matched = nextFn()
    if type(ctx) ~= "table" or ctx.kind ~= "levelup" then return matched end
    -- engine methods 2 / 3: friendship by day / by night
    local methodId = view and tonumber(view.methodId)
    if methodId == ConditionalEvos.FRIENDSHIP_DAY or methodId == ConditionalEvos.FRIENDSHIP_NIGHT then
      if friendship(mon) < ConditionalEvos.FRIENDSHIP_NEEDED then return false end
      return isNight(ctx.session) == (methodId == ConditionalEvos.FRIENDSHIP_NIGHT)
    end
    if not matched then return matched end
    local slot = okP and Pokemon.speciesOf and Pokemon.speciesOf(mon)
      or tonumber(mon and (mon.species or mon.speciesId))
    local group = slot and groups[slot]
    if not group then return matched end
    local target, mine = tonumber(view and view.speciesId), nil
    for _, step in ipairs(group) do
      if step.targetSlot == target then mine = step break end
    end
    if not mine then return matched end
    local personality = tonumber(mon.personality) or 0
    -- what the conditions look at, gathered once per check
    local moves, partySpecies, partyTypes = {}, {}, {}
    if okP and Pokemon.moveIdAt then
      for i = 1, 4 do
        local okM, raw = pcall(Pokemon.moveIdAt, mon, i)
        local id = okM and tonumber(raw) or nil
        if id and id > 0 then moves[id] = true end
      end
    end
    local session = ctx.session
    for _, member in ipairs(type(session) == "table" and session.party or {}) do
      if member ~= mon and okP and Pokemon.speciesOf then
        local memberSlot = Pokemon.speciesOf(member)
        if memberSlot then
          partySpecies[memberSlot] = true
          for _, typeId in ipairs(Pokemon.types(memberSlot)) do partyTypes[typeId] = true end
        end
      end
    end
    local chosen = ConditionalEvos.winner(group, {
      moves = moves, partySpecies = partySpecies, partyTypes = partyTypes,
      speciesSlot = function(name) return okP and Pokemon.speciesFromName(name) or nil end,
      rain = isRaining(),
      uses = type(mon.moveUses) == "table" and mon.moveUses or {},
      steps = tonumber(mon.stepsAsLead) or 0,
      coins = tonumber(type(session) == "table" and session.coins) or 0,
      gender = okP and Pokemon.gender and Pokemon.gender(slot, personality) or nil,
      terrain = ConditionalEvos.terrain(),
      recoil = tonumber(mon.recoilTaken) or 0,
      held = heldNumber(mon),
      night = isNight(ctx.session),
      dusk = isDusk(ctx.session),
      friendship = friendship(mon),
      personality = personality,
    }, itemIndex)
    return chosen == mine
  end)
end

-- Evolution by item has no hook (the engine only hands the "evolution.check" hook the
-- level-up scan), so a gendered item evolution (Dawn Stone: male Kirlia -> Gallade,
-- female Snorunt -> Froslass) is vetoed by wrapping src.core.game3.evolution's
-- targetSpecies: when the item scan finds the row but the Pokemon is the wrong gender,
-- the answer becomes "no evolution".
-- evolutions: the cross-generation bookkeeping (Species.register's `bridges`), whose
-- steps carry `gender`. Safe to call again; the wrapper is installed once and reads the
-- latest rules, which live on the engine module so a reload replaces them.
function ConditionalEvos.installItemGender(evolutions)
  local rules = {}
  for _, step in ipairs(evolutions or {}) do
    if step.gender and step.sourceSlot and step.targetSlot then
      rules[step.sourceSlot] = rules[step.sourceSlot] or {}
      rules[step.sourceSlot][step.targetSlot] = step.gender
    end
  end
  local okE, Evolution = pcall(require, "src.core.game3.evolution")
  local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
  if not (okE and okP and type(Evolution) == "table") then return false end
  Evolution._nationalDexItemGender = rules
  if Evolution._nationalDexItemGenderWrapped then return true end
  Evolution._nationalDexItemGenderWrapped = true
  local original = Evolution.targetSpecies
  Evolution.targetSpecies = function(mon, mode, ...)
    local target, param = original(mon, mode, ...)
    if (target or 0) ~= 0 and (mode == Evolution.EVO_MODE_ITEM_USE or mode == Evolution.EVO_MODE_ITEM_CHECK) then
      local slot = Pokemon.speciesOf(mon)
      local want = slot and Evolution._nationalDexItemGender[slot]
        and Evolution._nationalDexItemGender[slot][target]
      if want and Pokemon.gender(slot, tonumber(mon.personality) or 0) ~= want then return 0, 0 end
    end
    return target, param
  end
  return true
end

ConditionalEvos.FRIENDSHIP_DAY, ConditionalEvos.FRIENDSHIP_NIGHT = 2, 3
ConditionalEvos.FRIENDSHIP_NEEDED = 220   -- the engine's own threshold (evolution.lua)
ConditionalEvos._heldNumber = heldNumber
return ConditionalEvos
