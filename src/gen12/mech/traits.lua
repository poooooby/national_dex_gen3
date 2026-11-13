-- Natures and gender on Gen 1 / Gen 2.
--
-- Natures (both games): each Pokemon's nature comes from its DVs (a stable pick of the 25, so a
-- Pokemon keeps it for good and nothing new is saved), and raises one stat 10% and lowers another
-- 10% where the game works its stats out (Red Stats.calc, Gold Mon.stats). Red has one SPECIAL:
-- it takes Sp. Atk's factor times Sp. Def's, so Modest raises it and Rash / Gentle leave it
-- about even. The party's stats are worked out again when a save loads, so Pokemon from before
-- this get theirs at once.
--
-- Gender: Gold's rule on both games (its Attack and Speed DVs against the species' ratio), Red
-- reading the ratios from data/gen12/battle.lua. core "gender" answers it (Attract, Captivate).

return function(core, opts)
  local gen, require, mod = opts.generation, opts.require, opts.mod
  local Traits = {}
  core.traits = Traits

  Traits.NATURES = { "HARDY", "LONELY", "BRAVE", "ADAMANT", "NAUGHTY", "BOLD", "DOCILE", "RELAXED",
    "IMPISH", "LAX", "TIMID", "HASTY", "SERIOUS", "JOLLY", "NAIVE", "MODEST", "MILD", "QUIET",
    "BASHFUL", "RASH", "CALM", "GENTLE", "SASSY", "CAREFUL", "QUIRKY" }
  local KEYS = { "attack", "defense", "speed", "spAtk", "spDef" }

  function Traits.natureIndex(dvs)
    if type(dvs) ~= "table" then return 0 end
    local s = dvs.special or dvs.specialAttack or 0
    return ((dvs.attack or 0) * 4096 + (dvs.defense or 0) * 256 + (dvs.speed or 0) * 16 + s) % 25
  end
  function Traits.nature(dvs) return Traits.NATURES[Traits.natureIndex(dvs) + 1] end
  -- { stat = 1.1 / 0.9 } (empty for the five neutral natures)
  function Traits.mods(dvs)
    local i = Traits.natureIndex(dvs)
    local up, down = math.floor(i / 5) + 1, i % 5 + 1
    if up == down then return {} end
    return { [KEYS[up]] = 1.1, [KEYS[down]] = 0.9 }
  end
  function Traits.apply(stats, dvs, generation)
    local m = Traits.mods(dvs)
    if not next(m) or type(stats) ~= "table" then return stats end
    local function scale(key, k) if k and stats[key] then stats[key] = math.floor(stats[key] * k) end end
    scale("attack", m.attack)
    scale("defense", m.defense)
    scale("speed", m.speed)
    if generation == 1 then
      local k = (m.spAtk or 1) * (m.spDef or 1)
      if k ~= 1 then scale("special", k) end
    else
      scale("specialAttack", m.spAtk)
      scale("specialDefense", m.spDef)
    end
    return stats
  end

  -- once per process (games switch in-process); applies only on the version this install is for
  local GameVersion = require("src.core.GameVersion")
  local version = GameVersion.get()
  local function on(hub) return hub.version == GameVersion.get() end
  if gen == 1 then
    local Stats = require("src.pokemon.Stats")
    local hub = Stats.__ndxNature
    if not hub then
      hub = {}
      Stats.__ndxNature = hub
      local calc = Stats.calc
      Stats.calc = function(speciesDef, level, dvs, statExp, ...)
        local out = calc(speciesDef, level, dvs, statExp, ...)
        if on(hub) then Traits.apply(out, dvs or {}, 1) end
        return out
      end
    end
    hub.version = version
  else
    local Mon = require("src.battle.gen2.Mon")
    local hub = Mon.__ndxNature
    if not hub then
      hub = {}
      Mon.__ndxNature = hub
      local stats = Mon.stats
      Mon.stats = function(baseStats, dvs, level, statExp, ...)
        local out = stats(baseStats, dvs, level, statExp, ...)
        if on(hub) then Traits.apply(out, dvs or {}, 2) end
        return out
      end
    end
    hub.version = version
  end

  -- the party's stats again on load (a full Pokemon stays full)
  local function refresh(game)
    local data = game and game.data
    local party = game and game.save and game.save.party
    if not (data and type(party) == "table") then return end
    for _, mon in ipairs(party) do
      if type(mon) == "table" and mon.species and mon.dvs then
        local def = data.pokemon[mon.species]
        local oldMax = mon.stats and mon.stats.hp
        if gen == 1 and def and def.baseStats then
          mon.stats = require("src.pokemon.Stats").calc(def, mon.level or 1, mon.dvs, mon.statExp)
        elseif gen == 2 and def then
          require("src.battle.gen2.Mon").refreshStats(mon, data)
        end
        local max = mon.stats and mon.stats.hp
        if max and oldMax and mon.hp == oldMax then mon.hp = max end
        if max and mon.hp and mon.hp > max then mon.hp = max end
      end
    end
  end
  if mod then
    mod.events:on("save.loaded", function(ev)
      local game = (ev and ev.game) or mod.game
      pcall(refresh, game)
    end)
  end

  -- ------------------------------------------------------------------ gender
  local function ratioOf(A, b)
    local r = A:record(b)
    if r and r.genderRatio then return r.genderRatio end
    local facts = core.facts
    local dex = A:dex(b)
    local rate = facts and facts.genderRates and dex and facts.genderRates[dex]
    if rate == nil or rate < 0 then return 255 end
    if rate == 0 then return 0 end
    if rate == 8 then return 254 end
    return rate * 32 - 1
  end
  -- "M" / "F" / nil (genderless)
  function Traits.gender(ratio, dvs)
    if ratio == nil or ratio == 255 then return nil end
    if ratio == 0 then return "M" end
    if ratio == 254 then return "F" end
    return ((dvs.attack or 0) * 16 + (dvs.speed or 0)) <= ratio and "F" or "M"
  end
  core:on("gender", function(A, b) return Traits.gender(ratioOf(A, b), A:dvs(b)) end)
  core:on("nature", function(A, b) return Traits.nature(A:dvs(b)) end)

  -- Red: Attract (Gold runs its own): half the time an infatuated Pokemon can't move
  core:effect("ATTRACT", { kind = "status", aimed = true, run = function(A, u, t)
    local gu, gt = core:ask("gender", A, u), core:ask("gender", A, t)
    if not gu or not gt or gu == gt or A:vol(t).attract then return false end
    A:vol(t).attract = u
    A:say(A:text("%s fell in love!", A:name(t)))
    return true
  end })
  core:on("beforeMove", function(A, u, t, m, isCalled)
    local v = A:vol(u)
    if v.attract and v.attract == A:foe(u) and not isCalled then
      A:say(A:text("%s is in love with %s!", A:name(u), A:name(v.attract)))
      if A:chance(50) then return A:text("%s is immobilized by love!", A:name(u)) end
    end
  end)
end
