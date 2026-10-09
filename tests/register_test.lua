-- Standalone: luajit mods/national_dex_gen3/tests/register_test.lua (from the
-- gen1recomp root; needs Pokemon FireRed imported under firered/).
-- Species #387-1025 register into FireRed's species tables at slot dex+64,
-- resolved against the cart's own moves / items / species, with the reload
-- repairs (evolution targets, name + national lookup) and the art seam.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local Runtime = require("src.mods.Runtime")

local data = H.gen3Data()
local P = data.gen3Pokemon
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
for i = 1, math.min(5, #run.errors) do print("load error: " .. tostring(run.errors[i])) end
T.eq(#run.errors, 0, "loads clean: every move, item and species reference resolves")
local mod = run.mods.national_dex_gen3
T.check(mod and mod.state == "loaded", "loaded on FireRed")
local api = run.loader.exports.national_dex_gen3
T.check(api.isActive(), "active")

-- ------- registration

local list = api.listSpecies()
T.eq(#list, 639, "species #387-1025 are registered")
T.eq(list[1].dex, 387, "starting at Turtwig")
T.eq(list[#list].dex, 1025, "ending at Pecharunt")
for _, s in ipairs(list) do
  if s.slot ~= s.dex + 64 then T.check(false, s.id .. " sits at dex + 64") break end
end

local turtwig = run.loader.content.pokemon:get("TURTWIG")
T.eq(turtwig.index, 451, "TURTWIG is FireRed slot 451")
T.eq(turtwig.dex, 387, "national dex 387")
T.eq(P._stats[451].hp, 55, "its base stats are in the species tables")
T.eq(P._names[451], "TURTWIG", "and its name")
T.eq(P._types[451][1], P._types[1][1], "Grass typing, the engine's own type number")

-- Abilities: every newer ability is mapped to the closest one the cart has
-- (tools/ability_map.py), never a new id: the Gen 3 battle engine only
-- implements the cart's own (1-75, and Air Lock at 77). Cacophony (76) is
-- unused. Each species ends up with at least one.
local abilityIds, noAbility, badAbility = {}, 0, nil
for slot = 451, 1089 do
  local pair = P._abilities[slot]
  if not pair or ((pair[1] or 0) == 0 and (pair[2] or 0) == 0) then
    noAbility = noAbility + 1
  else
    for _, id in ipairs({ pair[1] or 0, pair[2] or 0 }) do
      if id ~= 0 and (id < 1 or id > 77 or id == 76) then badAbility = badAbility or (slot .. ":" .. id) end
    end
  end
end
T.eq(noAbility, 0, "every new species has a Gen 3 ability")
T.eq(badAbility, nil, "and only ever one the cart has (1-75 or 77)")
T.eq(P._abilities[451][1], 65, "Turtwig keeps Overgrow")
T.check(P._abilities[875 + 64][1] ~= 0, "Eiscue (Ice Face has no Gen 3 id) gets a mapped ability")

-- Typing: the Gen 3-era typing. Togekiss was Normal/Flying before Fairy
-- existed (PokeAPI past_types); dropping Fairy from today's typing alone would
-- leave it pure Flying.
local togekiss = run.loader.content.pokemon:get("TOGEKISS")
T.eq(togekiss.types[1], "NORMAL", "Togekiss keeps its pre-Fairy Normal half")
T.eq(togekiss.types[2], "FLYING", "and Flying")
T.eq(run.loader.content.pokemon:get("SYLVEON").types[1], "NORMAL", "a pure Gen 6+ Fairy is Normal")

-- Learnsets keep the modern games' length: a move Gen 3 lacks is replaced by
-- the closest Gen 3 move (tools/move_map.py), never dropped.
local emptyLearnset = 0
for _, r in ipairs(list) do
  local rec = run.loader.content.pokemon:get(r.id)
  if #(rec.learnset or {}) == 0 then emptyLearnset = emptyLearnset + 1 end
end
T.eq(emptyLearnset, 0, "every new species has a level-up learnset")
T.check(#(run.loader.content.pokemon:get("BLIPBUG").learnset or {}) >= 1,
        "even Blipbug, whose moves are all newer than Gen 3")
T.check(#(run.loader.content.pokemon:get("GARGANACL").learnset or {}) >= 15,
        "and a late species keeps a full-length list")

local unresolved = 0
for slot = 451, 1089 do
  local rows = P._learnsets[slot]
  if type(rows) ~= "table" then
    T.check(false, "slot " .. slot .. " has a learnset table")
    break
  end
  local last = 0
  for _, row in ipairs(rows) do
    local level, move = row[1] or row.level, row[2] or row.move
    if (tonumber(move) or 0) == 0 then unresolved = unresolved + 1 end
    if (level or 0) < last then T.check(false, "slot " .. slot .. " learnset sorted") end
    last = level or last
  end
end
T.eq(unresolved, 0, "every learnset move is one FireRed has")

-- Fairy is dropped: Sylveon (pure Fairy) is Normal, Flabebe too
local sylveon = run.loader.content.pokemon:get("SYLVEON")
T.eq(sylveon.types[1], "NORMAL", "pure Fairy becomes Normal")

-- ------- reload repairs

run.loader.events:emit("game.ready", {})
local evo = P._evolutions[451] and P._evolutions[451][1]
T.check(evo ~= nil, "TURTWIG has an evolution row")
T.eq(evo and evo.target, 452, "that evolves into GROTLE's slot, not slot 0")
T.eq(evo and evo.param, 18, "at level 18")
T.eq(P.speciesFromName("TURTWIG"), 451, "name lookup finds new species")
T.eq(P.national(451), 387, "slot -> national dex")
T.eq(P.speciesFromNational(387), 451, "national dex -> slot")
T.eq(P.speciesFromNational(25), 25, "the cart's own species are untouched")

-- item evolutions resolve to FireRed item numbers where FireRed has the item
local itemRows = 0
for slot = 451, 1089 do
  for _, row in ipairs(P._evolutions[slot] or {}) do
    if row.method == 7 then
      itemRows = itemRows + 1
      T.check(row.param > 0, "slot " .. slot .. " item evolution has an item")
    end
  end
end
T.check(itemRows > 0, "some item evolutions survive (" .. itemRows .. ")")

-- reapplied after the engine reloads its tables
P._evolutions[451] = { { method = 4, param = 18, target = 0 } }
P._runReloadHooks()
T.eq(P._evolutions[451][1].target, 452, "repairs are re-applied on reload")

-- ------- TMs/HMs, egg moves, tutors

local function has(list, name)
  for _, v in ipairs(list or {}) do if v == name then return true end end
  return false
end
local tw = run.loader.content.pokemon:get("TURTWIG")
T.check(has(tw.tmhm, "TOXIC"), "TURTWIG is TM-compatible with Toxic")
T.check(has(tw.tmhm, "SOLARBEAM"), "and Solar Beam")
T.check(not has(tw.tmhm, "TACKLE"), "never with a move FireRed has no TM for")
local lo = P._tmhm.learnsets[451]
T.check(type(lo) == "table" and (lo.lo or 0) + (lo.hi or 0) > 0, "its TM/HM bits are set")
T.check(#(tw.eggMoves or {}) > 0, "TURTWIG has egg moves (" .. #(tw.eggMoves or {}) .. ")")
local compatible = 0
for slot = 451, 1089 do
  if P._tmhm.learnsets[slot] then compatible = compatible + 1 end
end
T.check(compatible > 600, "most new species can use TMs/HMs (" .. compatible .. ")")

local ML = require("src.core.game3.move_learn")
local bodySlam
for tutor, move in pairs(ML.tutorMoves()) do if move == 34 then bodySlam = tutor end end
T.check(bodySlam ~= nil, "Body Slam is one of FireRed's tutors")
T.check(ML.canLearnTutorMove(451, bodySlam), "TURTWIG can learn it from the tutor")
T.check(ML.canLearnTutorMove(143, bodySlam), "the cart's own tutor data is kept (Snorlax)")
ML.resetTutorPack()
ML._tutorPack, ML._tutorLoaded = dofile("firered/data/generated/gba/pokemon/tutor.lua"), true
T.check(ML.canLearnTutorMove(451, bodySlam), "and again after the tutor pack reloads")

-- ------- evolutions from the cart's own species

local magneton = run.loader.content.pokemon:get("MAGNETON")
local toMagnezone
for _, e in ipairs(magneton.evolutions or {}) do
  if e.species == "MAGNEZONE" then toMagnezone = e end
end
T.check(toMagnezone ~= nil, "MAGNETON gains an evolution into MAGNEZONE")
T.eq(toMagnezone and toMagnezone.method, "EVO_ITEM", "by item")
local row
for _, r in ipairs(P._evolutions[82] or {}) do if r.target == 462 + 64 then row = r end end
T.check(row ~= nil, "the species table points Magneton at Magnezone's slot")
T.eq(row and row.method, 7, "EVO_ITEM")
T.eq(row and row.param, 96, "with FireRed's Thunder Stone")
-- SCYTHER -> KLEAVOR needs a Black Augurite, which src/items.lua now
-- registers itself; both evolutions are live.
T.eq(#(run.loader.content.pokemon:get("SCYTHER").evolutions or {}), 2,
     "Scyther gains both Scizor (trade) and Kleavor (national_dex_gen3's own Black Augurite)")

-- every item has a description for the Bag and the marts: at most 3 lines of 22 characters (the mart's box is about 21 wide)
do
  local itemsPayload = dofile("mods/national_dex_gen3/data/items.lua")
  local without, tooLong = 0, 0
  for _, r in ipairs(itemsPayload) do
    local d = run.loader.content.items:get(r.id).description
    if type(d) ~= "string" or d == "" then without = without + 1
    else
      local lines = 0
      for line in (d .. "\n"):gmatch("(.-)\n") do
        lines = lines + 1
        if #line:gsub("é", "e") > 22 then tooLong = tooLong + 1 end
      end
      if lines > 3 then tooLong = tooLong + 1 end
    end
  end
  T.eq(without, 0, "every registered item has a description")
  T.eq(tooLong, 0, "and each fits 3 lines of 22 characters")
end

-- ------- evolutionsOf

local grotle = api.evolutionsOf("GROTLE")
T.eq(grotle.evolvesFrom.id, "TURTWIG", "evolutionsOf: GROTLE comes from TURTWIG")
T.eq(grotle.evolvesFrom.methods[1].level, 18, "at level 18")
T.eq(grotle.evolvesInto[1].id, "TORTERRA", "and becomes TORTERRA")

-- ------- art seam

local function sprite(slot, side)
  return Runtime.call("pokemon.sprite", function(path) return path end,
    "data/generated/gba/pokemon/" .. side .. "/" .. slot .. ".rgba",
    { gen3Species = slot, side = side })
end
T.eq(sprite(451, "front"), "data/generated/gba/pokemon/front/451.rgba",
     "no provider: the engine's own path passes through")
T.check(api.setArtProvider(function(id, side)
  if id == "TURTWIG" then return "art/" .. side .. "/turtwig.png" end
  return "art/unused.rgba"
end), "a provider can register")
T.eq(sprite(451, "back"), "art/back/turtwig.png", "a provider's PNG is used")
T.eq(sprite(452, "front"), "data/generated/gba/pokemon/front/452.rgba",
     "an .rgba answer is ignored")
T.eq(sprite(25, "front"), "data/generated/gba/pokemon/front/25.rgba",
     "the cart's own species are never asked about")

run.release()
T.finish("national_dex_gen3 register")
