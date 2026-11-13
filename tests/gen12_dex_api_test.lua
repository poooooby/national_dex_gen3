-- Standalone: luajit mods/national_dex_gen3/tests/gen12_dex_api_test.lua [red|blue|yellow|gold|silver|crystal ...]
-- (from the gen1recomp root; runs on red, yellow, gold and crystal when none is named).
-- src/gen12/dex_api.lua: the read API (apiVersion 9) a battle or stats mod calls on a National
-- Dex, checked the way those mods call it: moves by the id the game registers (and the
-- separator-free spelling), flags, abilities by the name a species record carries, items and
-- their facts, species records with stats / abilities / EV yield / learnsets, evolution
-- families, and patch().
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")

local function strip(s) return (s:upper():gsub("[^%w]", "")) end

for _, version in ipairs(H.versions()) do
  local gen = H.GENERATION[version]
  local run, api = H.load(version)
  T.eq(#run.errors, 0, version .. ": loads clean")
  T.check((api.apiVersion or 0) >= 9, version .. ": apiVersion 9")
  local moves = run.loader.content.moves
  local pokemon = run.loader.content.pokemon

  -- moves ---------------------------------------------------------------------------------
  local tb = api.moveById("THUNDERBOLT")
  T.check(tb and tb.id == "THUNDERBOLT" and tb.type == "ELECTRIC" and tb.power == 90
    and tb.damageClass == "special" and tb.target == "selected-pokemon" and tb.priority == 0
    and tb.ailment == "paralysis" and tb.ailmentChance == 10 and tb.engineMove == true,
    version .. ": moveById THUNDERBOLT")
  local psy = api.moveById("PSYCHIC_M")
  T.check(psy and psy.strippedId == "PSYCHIC" and psy.type == "PSYCHIC_TYPE",
    version .. ": PSYCHIC_M strips to PSYCHIC, this game's type id")
  local aj = api.moveById("AQUA_JET")
  T.check(aj and aj.id == "AQUA_JET" and aj.priority == 1 and aj.registered
    and aj.engineMove == false and aj.effectModeled == true, version .. ": a newer registered move")
  T.eq(api.moveById("AQUAJET") and api.moveById("AQUAJET").id, "AQUA_JET",
    version .. ": found by its separator-free spelling")
  local swift = api.moveById("SWIFT")
  T.eq(swift and swift.accuracy, 0, version .. ": a move that never misses has accuracy 0")
  local cc = api.moveById("CLOSE_COMBAT")
  T.check(cc and #cc.statChanges == 2 and cc.statChanges[1].change == -1,
    version .. ": Close Combat's stat changes")
  local gd = api.moveById("GIGA_DRAIN")
  T.check(gd and gd.drain == 50, version .. ": Giga Drain drains 50%")
  local sr = api.moveById("STEALTHROCK")
  T.check(sr and sr.registered == false and sr.effectModeled == false and sr.target == "opponents-field",
    version .. ": a move this game does not register is still described")
  T.eq(api.moveById("NOT_A_MOVE"), nil, version .. ": an unknown move is nil")
  T.eq(api.moveById(nil), nil, version .. ": nil is nil")

  local listed, allRegistered, allBack = api.listMoves(), true, true
  for _, id in ipairs(listed) do
    if moves:get(id) == nil then allRegistered = false end
    local m = api.moveById(id)
    if not (m and m.id == id) then allBack = false end
  end
  T.check(#listed >= (gen == 1 and 400 or 500), version .. ": listMoves (" .. #listed .. ")")
  T.check(allRegistered, version .. ": every listed move is registered here")
  T.check(allBack, version .. ": moveById answers each listed id with itself")

  local fl = api.moveFlags("THUNDERPUNCH")
  T.check(fl and fl.contact and fl.punch and fl.protect and fl.contact == true,
    version .. ": moveFlags THUNDERPUNCH")
  T.check(api.moveFlags("SWIFT") and not api.moveFlags("SWIFT").contact, version .. ": Swift makes no contact")
  T.check(api.moveFlags("BOOMBURST") and api.moveFlags("BOOMBURST").sound, version .. ": a sound move")

  -- learnset_ownership's reverse map: separator-free spelling -> registered id
  local reverse = {}
  for _, id in ipairs(listed) do reverse[api.moveById(id).strippedId] = id end

  -- abilities -----------------------------------------------------------------------------
  local intim = api.abilityById("INTIMIDATE")
  T.check(intim and intim.name == "Intimidate" and intim.generation == 3 and intim.shortEffect ~= "",
    version .. ": abilityById INTIMIDATE")
  T.eq(api.abilityById("Vital Spirit") and api.abilityById("Vital Spirit").id, "VITALSPIRIT",
    version .. ": by display name")
  T.eq(api.abilityById("NOPE"), nil, version .. ": an unknown ability is nil")
  T.check(#api.listAbilities() >= 300, version .. ": listAbilities")
  local ib = intim and intim.behaviour
  T.check(ib and ib.scope == "foes" and ib.effects[1].kind == "stat_change"
    and ib.effects[1].stat == "attack" and ib.effects[1].stages == -1, version .. ": Intimidate's behaviour")
  local lev = api.abilityById("LEVITATE")
  T.eq(lev and lev.behaviour.effects[1].moveType, "GROUND", version .. ": Levitate's type")
  T.eq(api.abilityById("SNOWWARNING").behaviour.effects[1].weather, "hail", version .. ": Snow Warning")
  T.eq(api.abilityById("Dragon's Maw") and api.abilityById("Dragon's Maw").name, "Dragon's Maw",
    version .. ": names are plain ASCII")
  -- every behaviour type is one this game has
  local typeIds, badType = {}, {}
  for _, rec in pairs(run.data.type_chart and run.data.type_chart.types or {}) do
    if type(rec) == "table" and rec.id then typeIds[rec.id] = true end
  end
  for id in pairs(run.data.type_chart and run.data.type_chart.types or {}) do typeIds[id] = true end
  for _, aid in ipairs(api.listAbilities()) do
    for _, e in ipairs(api.abilityById(aid).behaviour and api.abilityById(aid).behaviour.effects or {}) do
      if e.moveType and next(typeIds) and not typeIds[e.moveType] then badType[#badType + 1] = aid end
    end
  end
  T.eq(#badType, 0, version .. ": behaviour types are this game's " .. table.concat(badType, " "))

  -- items ---------------------------------------------------------------------------------
  local lo = api.itemById("LEFTOVERS")
  T.check(lo and lo.name == "Leftovers" and lo.category == "held-items", version .. ": itemById LEFTOVERS")
  T.check(api.itemById("NORMALIUMZ") ~= nil, version .. ": a miss is retried with HELD")
  T.eq(api.itemById("NOPE"), nil, version .. ": an unknown item is nil")
  local kr = api.itemFlags("KINGSROCK")
  T.check(kr and kr.fling and kr.fling.basePower == 30 and kr.fling.volatileStatus == "flinch",
    version .. ": itemFlags KINGSROCK")
  local plate = api.itemFlags("FLAMEPLATE")
  T.eq(plate and plate.onPlate, "Fire", version .. ": a Plate's type")
  local berry = api.itemFlags("SITRUSBERRY")
  T.check(berry and berry.isBerry and berry.naturalGift and berry.naturalGift.type == "Psychic",
    version .. ": a Berry's facts")

  -- species -------------------------------------------------------------------------------
  local bulba = api.statsBySpecies("BULBASAUR")
  T.check(bulba and bulba.stats.spAttack == 65 and bulba.stats.spDefense == 65 and bulba.hasSplit,
    version .. ": Bulbasaur's split specials")
  if gen == 1 then
    T.eq(bulba and bulba.stats.special, 65, version .. ": and Red's one Special")
  else
    T.eq(bulba and bulba.stats.special, nil, version .. ": no Special on Gold")
  end
  T.check(bulba and #bulba.abilities == 2 and bulba.abilities[1].name == "Overgrow"
    and bulba.abilities[2].hidden == true, version .. ": Bulbasaur's abilities")
  T.check(bulba and bulba.evYield.spAttack == 1 and bulba.evYield.hp == 0, version .. ": EV yield")
  T.check(bulba and #bulba.movesFull > 5 and type(bulba.movesFull[1].move) == "string"
    and type(bulba.movesFull[1].level) == "number", version .. ": movesFull")
  T.check(bulba and #bulba.movesByMethod.egg > 0 and #bulba.movesByMethod.machine > 0,
    version .. ": movesByMethod")
  T.eq(api.statsByDex(1) and api.statsByDex(1).id, "BULBASAUR", version .. ": statsByDex")
  local split = api.splitStats("LUCARIO")
  T.check(split and split.spAttack == 115 and api.hasSplitStats("LUCARIO"), version .. ": splitStats")
  local rotom = api.statsBySpecies("ROTOM")
  T.check(rotom and #rotom.forms >= 5 and rotom.forms[1].baseSpecies == "ROTOM"
    and rotom.forms[1].forms == nil, version .. ": a base lists its forms")
  local vulpix = api.statsBySpecies("VULPIX_ALOLA")
  T.check(vulpix and vulpix.baseDex == 37 and vulpix.form and vulpix.abilities[1].name == "Snow Cloak",
    version .. ": a form's own record")
  T.eq(api.statsBySpecies("NOPE"), nil, version .. ": an unknown species is nil")
  T.check(#api.formsOf("ROTOM") >= 5 and api.formsOf("ROTOM")[1].stats ~= nil, version .. ": formsOf")

  -- every species: a record, abilities that name an ability record, and its level-up moves
  -- mostly resolvable through the reverse map
  local list = api.listSpecies()
  local missing, badAbility, noEvo, resolved, total = {}, {}, {}, 0, 0
  for _, s in ipairs(list) do
    local rec = api.statsBySpecies(s.id)
    if not rec then
      missing[#missing + 1] = s.id
    else
      for _, a in ipairs(rec.abilities) do
        if not api.abilityById(strip(a.name)) then badAbility[#badAbility + 1] = s.id .. ":" .. a.name end
      end
      for _, m in ipairs(rec.movesFull) do
        total = total + 1
        if reverse[m.move] then resolved = resolved + 1 end
      end
    end
    local evo = api.evolutionsOf(s.id)
    if not (evo and type(evo.evolvesInto) == "table") then noEvo[#noEvo + 1] = s.id end
  end
  T.eq(#list, 1025, version .. ": listSpecies")
  T.eq(#missing, 0, version .. ": statsBySpecies for every species " .. table.concat(missing, " ", 1, math.min(5, #missing)))
  T.eq(#badAbility, 0, version .. ": every ability name finds its record "
    .. table.concat(badAbility, " ", 1, math.min(5, #badAbility)))
  T.eq(#noEvo, 0, version .. ": evolutionsOf for every species " .. table.concat(noEvo, " ", 1, math.min(5, #noEvo)))
  T.check(resolved / math.max(total, 1) > 0.5,
    ("%s: %d of %d level-up moves resolve to a move here"):format(version, resolved, total))
  T.check(list[25].formIds and list[25].forms == #list[25].formIds, version .. ": listSpecies form ids")

  -- evolutions ----------------------------------------------------------------------------
  local eevee = api.evolutionsOf("EEVEE")
  T.check(eevee and #eevee.evolvesInto == 8 and eevee.chain[1] == "EEVEE" and eevee.stage == 0
    and eevee.chainId ~= nil, version .. ": Eevee's eight")
  local stone
  for _, e in ipairs(eevee and eevee.evolvesInto or {}) do
    if e.id == "VAPOREON" then stone = e.methods[1] end
  end
  T.check(stone and stone.trigger == "use-item" and stone.item == "water-stone",
    version .. ": Vaporeon by Water Stone")
  local torterra = api.evolutionsOf("TORTERRA")
  T.check(torterra and torterra.stage == 2 and torterra.evolvesFrom.id == "GROTLE"
    and #torterra.evolvesInto == 0, version .. ": a last stage")
  local lv = api.evolutionsOf("GROTLE")
  T.check(lv and lv.evolvesFrom.methods[1].trigger == "level-up" and lv.evolvesFrom.methods[1].level == 18,
    version .. ": a level step")
  T.eq(api.evolutionsOf(133) and api.evolutionsOf(133).id, "EEVEE", version .. ": by dex number")
  T.eq(api.evolutionsOf("NOPE"), nil, version .. ": an unknown species is nil")
  T.check(#api.listEvolutions() >= 1025, version .. ": listEvolutions")

  -- patch ---------------------------------------------------------------------------------
  T.check(api.patch("species", "LUCARIO", { abilities = { { name = "Justified", slot = 1 } } }),
    version .. ": patch species")
  T.eq(api.statsBySpecies("LUCARIO").abilities[1].name, "Justified", version .. ": the patch shows")
  T.eq(#api.statsBySpecies("LUCARIO").abilities, 1, version .. ": lists replace whole")
  T.check(api.patch("move", "AQUA_JET", { power = 45, shortEffect = "x" }), version .. ": patch move")
  -- (the registry half lands while mods load; the registries are closed by now)
  T.eq(api.moveById("AQUA_JET").power, 45, version .. ": the patched power shows")
  T.check(api.patch("moveFlags", "AQUAJET", { wind = true }) and api.moveFlags("AQUA_JET").wind
    and api.moveFlags("AQUA_JET").contact, version .. ": patch moveFlags merges")
  T.check(api.patch("ability", "Intimidate", { behaviour = { chance = 50 } })
    and api.abilityById("INTIMIDATE").behaviour.chance == 50, version .. ": patch ability")
  T.check(not api.patch("nonsense", "X", {}), version .. ": an unknown kind is refused")
  T.check(pokemon:get("LUCARIO") ~= nil, version .. ": records still there")

  -- every reply is a copy
  local a = api.moveById("THUNDERBOLT")
  a.power = 1
  T.eq(api.moveById("THUNDERBOLT").power, 90, version .. ": replies are copies")
end

T.finish("national_dex_gen3 Gen 1/2 read API")
