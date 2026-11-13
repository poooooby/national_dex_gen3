-- Simple newer moves from PokeAPI's modern facts (data/gen12/moves.lua `meta`, tools/build_gen12.py
-- move_meta): stat moves, status moves, Swagger-style moves, and hits that change stats, inflict a
-- status, flinch, drain or recoil, strike several times or crit more often. Their Gen 9 numbers,
-- which is what makes Tail Glow +3 and Sweet Scent -2 evasion here.
--
-- These Gen 3 effects (tools/build_gen12.py `mech.g3`) and the moves known only from PokeAPI run
-- on it; anything with a category PokeAPI calls "unique", a field effect or a variable power
-- has a mechanic of its own elsewhere.

return function(core)
  local Core = getmetatable(core)

  local SELF_TARGETS = { user = true, ["users-field"] = true, ["user-and-allies"] = true,
    ["user-or-ally"] = true, ["all-allies"] = true }
  local AILMENT = { paralysis = "PARALYSIS", sleep = "SLEEP", freeze = "FREEZE", burn = "BURN",
    poison = "POISON", confusion = "CONFUSION" }
  local HITS = { "damage", "damage-ailment", "damage-raise", "damage-lower", "damage-heal" }
  local isHit = {}
  for _, c in ipairs(HITS) do isHit[c] = true end

  -- 2-5 strikes: 35% / 35% / 15% / 15% (Gen 5 on)
  local function twoToFive(A, u)
    if u and core:ask("loadedDice", A, u) then return 4 + A:rng(2) end   -- Loaded Dice: 4 or 5
    local r = A:rng(100)
    if r < 35 then return 2 elseif r < 70 then return 3 elseif r < 85 then return 4 end
    return 5
  end

  -- the mechanic for a row's meta, or nil when it is not a simple one. `over` changes the
  -- `extra`-shaped description before it is built (a move PokeAPI under-describes).
  function Core.metaSpec(row, over)
    local m = row.meta
    if not m then return nil end
    local cat = m.cat
    if m.ailment and not AILMENT[m.ailment] then return nil end
    local selfTarget = SELF_TARGETS[m.target]
    local e = {}
    if cat == "net-good-stats" then
      if not m.stats then return nil end
      e.kind = "status"
      if selfTarget then e.self = m.stats else e.foe = m.stats end
    elseif cat == "ailment" then
      e.kind, e.ailment = "status", AILMENT[m.ailment]
      if not e.ailment then return nil end
    elseif cat == "heal" then
      if not m.healing then return nil end
      e.kind, e.heal = "status", m.healing
      if not selfTarget then e.healTarget = "foe" end
    elseif cat == "swagger" then
      e.kind, e.foe, e.ailment = "status", m.stats, AILMENT[m.ailment]
    elseif isHit[cat] then
      if (row.power or 0) == 0 then return nil end      -- variable power: a mechanic of its own
      e.kind = "hit"
      local chance = (m.statChance and m.statChance > 0) and m.statChance or 100
      if cat == "damage-ailment" then
        e.ailment = AILMENT[m.ailment]
        e.ailmentChance = (m.ailmentChance and m.ailmentChance > 0) and m.ailmentChance or 100
      elseif cat == "damage-raise" then
        e.self, e.chance = m.stats, chance
      elseif cat == "damage-lower" then
        e.foe, e.chance = m.stats, chance
      end
      if m.drain then e.drain = m.drain end
      if m.flinch then e.flinch = m.flinch end
    else
      return nil
    end
    if over then over(e) end
    local spec = Core.extraSpec(e)
    if e.kind == "hit" then
      if m.minHits then
        if m.minHits == m.maxHits then spec.hits = m.minHits
        elseif m.minHits == 2 and m.maxHits == 5 then spec.hits = twoToFive end
      end
      if (m.crit or 0) >= 1 then spec.highCrit = true end
      if m.sure then spec.sureHit = true end
    end
    return spec
  end

  local function metaOf(row) return Core.metaSpec(row) end

  -- the Gen 3 effects these cover
  for _, name in ipairs({ "HIT", "ACCURACY_DOWN_HIT", "ALL_STATS_UP_HIT", "ATTACK_DOWN", "ATTACK_DOWN_2",
      "ATTACK_UP_HIT", "BLAZE_KICK", "BULK_UP", "CALM_MIND", "COSMIC_POWER", "DEFENSE_UP_HIT",
      "DRAGON_DANCE", "EVASION_DOWN", "FLATTER", "OVERHEAT", "POISON_TAIL", "SPECIAL_ATTACK_DOWN_HIT",
      "SPECIAL_ATTACK_UP_2", "SPECIAL_DEFENSE_DOWN_2", "SPEED_DOWN_2", "SUPERPOWER", "SWAGGER", "TICKLE",
      "WILL_O_WISP", "TEETER_DANCE", "SKY_UPPERCUT", "TWISTER", "THAW_HIT", "VITAL_THROW",
      "MOONLIGHT", "MORNING_SUN", "SYNTHESIS" }) do
    core:effect(name, metaOf)
  end
  core:api(metaOf)

  -- PokeAPI calls bad poison plain "poison"
  local function toxic(e) if e.ailment == "POISON" then e.ailment = "TOXIC" end end
  core:effect("POISON_FANG", function(row) return Core.metaSpec(row, toxic) end)
end
