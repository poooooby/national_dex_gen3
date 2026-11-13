-- Breeding on Red / Blue / Yellow, by Gold's rules. Red's own Day Care keeps one Pokemon (the
-- gentleman, save.daycare); the Day Care Lady here, a runtime NPC beside him on Route 5
-- (DAYCARE), keeps a second. Every 256 steps two compatible Pokemon (a shared egg group and
-- opposite genders, or one of them Ditto; never the Undiscovered group) may leave an EGG with her:
-- 70% the same species, 50% two species, 20% with Ditto. An accepted EGG is carried until it
-- hatches (the species' egg cycles x 256 steps; one at a time), then the Pokemon joins the
-- party, or the PC when the party is full: level 1, its level-1 moves, and the egg moves it gets
-- from a parent that knows them. Red has no egg in its party menus, so the EGG is carried rather
-- than shown. The lady's Pokemon gains a point of Exp. per step, as the gentleman's does.
--
-- State: save.modData.national_dex_gen3.breeding = { lady = mon, steps, eggReady, egg = { dex,
-- stepsLeft, moves } } (the save keeps it; the cartridge .sav does not).

local Breeding = {}

Breeding.MAP = "DAYCARE"
Breeding.SPOT = { x = 5, y = 3 }
Breeding.NAME = "NATIONAL_DEX_GEN3_DAYCARE_LADY"
Breeding.SPRITES = { "SPRITE_MIDDLE_AGED_WOMAN", "SPRITE_GRANNY", "SPRITE_GIRL" }

local function stateOf(save)
  save.modData = save.modData or {}
  local bag = save.modData.national_dex_gen3
  if not bag then bag = {}; save.modData.national_dex_gen3 = bag end
  bag.breeding = bag.breeding or {}
  return bag.breeding
end
Breeding.stateOf = stateOf

-- the chance (of 100) per 256 steps that two Pokemon leave an EGG, 0 if they cannot
-- a / b: { dex, groups = { "monster", ... }, gender = "M" / "F" / nil }
function Breeding.chance(a, b)
  local function undiscovered(x)
    for _, g in ipairs(x.groups or {}) do if g == "no-eggs" then return true end end
    return #(x.groups or {}) == 0
  end
  if undiscovered(a) or undiscovered(b) then return 0 end
  local dittoA, dittoB = a.dex == 132, b.dex == 132
  if dittoA and dittoB then return 0 end
  if dittoA or dittoB then return 20 end
  if not a.gender or not b.gender or a.gender == b.gender then return 0 end
  local shared = false
  for _, x in ipairs(a.groups) do
    for _, y in ipairs(b.groups) do if x == y then shared = true end end
  end
  if not shared then return 0 end
  return a.dex == b.dex and 70 or 50
end

-- the dex the EGG hatches into: the mother's family (the one that is not Ditto)
function Breeding.babyOf(facts, a, b)
  local mother = a
  if a.dex == 132 then mother = b
  elseif b.dex ~= 132 and a.gender ~= "F" and b.gender == "F" then mother = b end
  local baby = facts.baby and facts.baby[mother.dex]
  return baby or mother.dex
end

-- opts: { mod, require, facts (data/gen12/battle.lua), gender = fn(species record, dvs) ->
--   M/F/nil, direct = fn(national move) -> this game's id, eggMoves = fn(dex) -> { national },
--   log }
function Breeding.install(opts)
  local mod, require, facts, log = opts.mod, opts.require, opts.facts or {}, opts.log
  local Strings = require("src.core.Strings")

  local function parent(game, mon)
    local r = game.data.pokemon[mon.species]
    local dex = r and (r.baseDex or r.dex) or 0
    return { dex = dex, groups = facts.eggGroups and facts.eggGroups[dex] or {},
      gender = opts.gender(r, mon.dvs or {}), mon = mon }
  end
  local function speciesForDex(game, dex)
    for id, r in pairs(game.data.pokemon) do
      if type(r) == "table" and r.dex == dex and not r.form then return id end
    end
    return nil
  end
  local function say(game, lines, onDone, choice)
    local TextBox = require("src.render.TextBox")
    local box = TextBox.new(game, lines, onDone, choice and { choice = choice } or nil)
    game.stack:push(box)
  end
  local function monName(m) return m.nickname or m.name or m.species end

  -- the lady's Pokemon back, with the Exp. of its steps
  local function giveBack(game, st)
    local mon = st.lady
    local Growth = require("src.pokemon.Growth")
    local Stats = require("src.pokemon.Stats")
    local def = game.data.pokemon[mon.species]
    mon.exp = (mon.exp or 0) + (st.steps or 0)
    if def then
      local ok, lvl = pcall(Growth.levelForExp, def.growthRate, mon.exp, 100)
      if ok and lvl and lvl > (mon.level or 1) then
        mon.level = lvl
        mon.stats = Stats.calc(def, lvl, mon.dvs or {}, mon.statExp)
        mon.hp = mon.stats.hp
      end
    end
    require("src.pokemon.Party").add(game.save.party, mon)
    st.lady, st.steps = nil, nil
    return mon
  end

  local function talk(game)
    local st = stateOf(game.save)
    if st.eggReady then
      say(game, Strings("Ah, it's you! Your POKéMON\nhad an EGG!\fDo you want it?"), nil, function(yes)
        if not yes then return end
        if st.egg then
          say(game, Strings("You're already\ncarrying an EGG!"))
          return
        end
        local gentleman = game.save.daycare and game.save.daycare.mon
        if not (gentleman and st.lady) then st.eggReady = nil return end
        local a, b = parent(game, gentleman), parent(game, st.lady)
        local dex = Breeding.babyOf(facts, a, b)
        local moves = {}
        local eggMoves = opts.eggMoves(dex) or {}
        local want = {}
        for _, n in ipairs(eggMoves) do
          local id = opts.direct(n)
          if id then want[id] = true end
        end
        for _, p in ipairs({ a, b }) do
          for _, mv in ipairs(p.mon.moves or {}) do
            if want[mv.id] and #moves < 4 then moves[#moves + 1] = mv.id; want[mv.id] = nil end
          end
        end
        -- a Destiny Knot on either parent: three of the four DVs come from the parents
        local dvs
        local function knot(m) local bag = m.extra and m.extra.national_dex_gen3; return bag and bag.item == "DESTINY_KNOT" end
        if knot(a.mon) or knot(b.mon) then
          local keys = { "attack", "defense", "speed", "special" }
          local skip = love.math.random(4)
          dvs = {}
          for i, k in ipairs(keys) do
            if i ~= skip then
              local from = love.math.random(2) == 1 and a.mon or b.mon
              dvs[k] = (from.dvs or {})[k]
            end
          end
        end
        st.egg = { dex = dex, stepsLeft = (facts.eggCycles and facts.eggCycles[dex] or 20) * 256, moves = moves,
          dvs = dvs }
        st.eggReady = nil
        say(game, Strings("You received\nthe EGG!\fTake good care\nof it."))
      end)
      return
    end
    if st.lady then
      say(game, Strings("Your %s is\ndoing fine.\fShall I give it\nback to you?", monName(st.lady)), nil, function(yes)
        if not yes then return end
        if #game.save.party >= 6 then
          say(game, Strings("You have no room\nfor it."))
          return
        end
        local mon = giveBack(game, st)
        say(game, Strings("%s came back\nto you!", monName(mon)))
      end)
      return
    end
    say(game, Strings("I raise a POKéMON\nalongside the one\fmy husband keeps.\nShall I raise one\fof yours?"), nil, function(yes)
      if not yes then return end
      local PartyMenu = require("src.ui.PartyMenu")
      local menu = PartyMenu.new(game, {
        pickOnly = true,
        onSwitch = function(mon)
          local healthy = 0
          for _, m in ipairs(game.save.party) do if m ~= mon and (m.hp or 0) > 0 then healthy = healthy + 1 end end
          if healthy == 0 then
            say(game, Strings("That's your last\nPOKéMON!"))
            return
          end
          for i, m in ipairs(game.save.party) do
            if m == mon then table.remove(game.save.party, i) break end
          end
          st.lady, st.steps = mon, 0
          say(game, Strings("I'll raise your\n%s.\fCome back for it\nlater.", monName(mon)))
        end,
        onCancel = function() end,
      })
      game.stack:push(menu)
    end)
  end
  Breeding.talk = talk

  -- a step: Exp. for the lady's Pokemon, an EGG now and then, the carried EGG nearer hatching
  local stepCount = 0
  local function hatch(game, st)
    local egg = st.egg
    st.egg = nil
    local id = speciesForDex(game, egg.dex)
    if not id then return end
    local Pokemon = require("src.pokemon.Pokemon")
    local mon = Pokemon.new(game.data, id, 1)
    -- the DVs a Destiny Knot passed down, the stats worked out again from them
    if type(egg.dvs) == "table" and mon.dvs then
      for k, v in pairs(egg.dvs) do mon.dvs[k] = v end
      local d = mon.dvs
      d.hp = ((d.attack or 0) % 2) * 8 + ((d.defense or 0) % 2) * 4 + ((d.speed or 0) % 2) * 2 + ((d.special or 0) % 2)
      local okS, Stats = pcall(require, "src.pokemon.Stats")
      local def = game.data.pokemon[id]
      if okS and def then
        mon.stats = Stats.calc(def, mon.level or 1, mon.dvs, mon.statExp)
        mon.hp = mon.stats.hp
      end
    end
    for _, mid in ipairs(egg.moves or {}) do
      local known = false
      for _, mv in ipairs(mon.moves) do if mv.id == mid then known = true end end
      if not known then
        local m = game.data.moves[mid]
        local slot = { id = mid, pp = m and m.pp or 10, maxPp = m and m.pp or 10 }
        if #mon.moves < 4 then mon.moves[#mon.moves + 1] = slot else table.remove(mon.moves, 1); mon.moves[4] = slot end
      end
    end
    local where
    if #game.save.party < 6 then
      require("src.pokemon.Party").add(game.save.party, mon)
      where = "party"
    else
      require("src.pokemon.Boxes").deposit(game.save, mon)
      where = "PC"
    end
    local dex = game.save.pokedex
    if type(dex) == "table" then
      for _, k in ipairs({ "seen", "owned", "caught" }) do
        if type(dex[k]) == "table" then dex[k][id] = true end
      end
    end
    say(game, Strings("Huh?\fThe EGG is\nhatching!\f%s came out\nof the EGG!", mon.name or id)
      .. (where == "PC" and Strings("\fIt was sent\nto the PC.") or ""))
  end
  mod.events:on("world.stepped", function()
    local game = mod.game
    if not (game and game.save) then return end
    local st = stateOf(game.save)
    if st.lady then st.steps = (st.steps or 0) + 1 end
    if st.egg then
      st.egg.stepsLeft = st.egg.stepsLeft - 1
      if st.egg.stepsLeft <= 0 then pcall(hatch, game, st) end
    end
    stepCount = stepCount + 1
    if stepCount >= 256 then
      stepCount = 0
      local gentleman = game.save.daycare and game.save.daycare.mon
      if st.lady and gentleman and not st.eggReady then
        local chance = Breeding.chance(parent(game, gentleman), parent(game, st.lady))
        if chance > 0 and math.random(100) <= chance then st.eggReady = true end
      end
    end
  end)

  -- the lady: placed beside the gentleman whenever the Day Care is entered
  local function place()
    local world = mod.world
    if not world then return true end
    local okC, here = pcall(world.current, world)
    if not (okC and type(here) == "table" and here.mapId == Breeding.MAP) then return true end
    local okN, npc = pcall(world.npc, world, Breeding.MAP, Breeding.NAME)
    if okN and npc then return true end
    for _, sprite in ipairs(Breeding.SPRITES) do
      local okS, id = pcall(world.spawnNpc, world, Breeding.MAP, { name = Breeding.NAME, sprite = sprite,
        x = Breeding.SPOT.x, y = Breeding.SPOT.y, movement = "STAY", range = "DOWN" })
      if okS and id then return true end
    end
    return nil
  end
  local pending, tries = true, 0
  mod.events:on("map.entered", function() pending, tries = true, 0 end)
  mod.events:on("save.loaded", function() pending, tries = true, 0 end)
  mod.hooks:wrap("input.step", function(nxt, game, ...)
    local r = nxt(game, ...)
    if pending then
      local ok, done = pcall(place)
      tries = tries + 1
      if (ok and done) or tries > 600 then pending = false end
    end
    return r
  end)
  mod.hooks:wrap("world.talk", function(nxt, ow, npc, ...)
    if npc and npc.def and npc.def.name == Breeding.NAME then
      local game = (ow and ow.game) or mod.game
      local ok, err = pcall(talk, game)
      if not ok and log then log:warn("Day Care lady: %s", tostring(err)) end
      return
    end
    return nxt(ow, npc, ...)
  end)
  return Breeding
end

return Breeding
