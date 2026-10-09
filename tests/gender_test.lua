-- Standalone: luajit mods/national_dex_gen3/tests/gender_test.lua
-- (from the gen1recomp root; needs Pokemon FireRed imported under firered/).
--
-- Evolutions that depend on the Pokemon's gender (src/conditional_evos.lua): Combee and
-- Salandit (female only), Burmy (female Wormadam, male Mothim), and the Dawn Stone pair,
-- male Kirlia -> Gallade and female Snorunt -> Froslass, which go through the item scan.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")

local data = H.gen3Data()
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.events:emit("game.ready", {})

local api = run.loader.exports.national_dex_gen3
local Evolution = require("src.core.game3.evolution")
local Pokemon = require("src.core.game3.pokemon")
Evolution.nationalAllows = function() return true end

-- a personality that gives the species the wanted gender
local function personalityFor(slot, gender)
  for p = 0, 255 do
    if Pokemon.gender(slot, p) == gender then return p end
  end
  error("no " .. gender .. " personality for slot " .. slot)
end

local function levelUp(species, gender, level)
  local slot = type(species) == "number" and species or api.slotOf(species)
  return Evolution.levelTarget({ species = slot, level = level,
    personality = personalityFor(slot, gender) }, {})
end

local combee, vespiquen = api.slotOf("COMBEE"), api.slotOf("VESPIQUEN")
T.eq(levelUp("COMBEE", "F", 21), vespiquen, "a female Combee evolves into Vespiquen at 21")
T.eq(levelUp("COMBEE", "M", 21), nil, "a male Combee does not")
T.eq(levelUp("COMBEE", "F", 20), nil, "and not before 21")
T.eq(levelUp("SALANDIT", "F", 33), api.slotOf("SALAZZLE"), "a female Salandit evolves into Salazzle at 33")
T.eq(levelUp("SALANDIT", "M", 33), nil, "a male Salandit does not")
-- Burmy's cloak follows the ground of its last battle
local Bg = require("src.core.game3.battle.bg")
local function onGround(name, fn)
  local before = Bg.terrainId()
  Bg.setTerrain(Bg.TERRAIN[name])
  local result = fn()
  Bg.setTerrain(before)
  return result
end
for _, name in ipairs({ "GRASS", "LONG_GRASS", "WATER", "POND", "UNDERWATER", "PLAIN" }) do
  T.eq(onGround(name, function() return levelUp("BURMY", "F", 20) end), api.slotOf("WORMADAM"),
       "a female Burmy after a battle on " .. name .. " becomes the Plant Cloak Wormadam")
end
for _, name in ipairs({ "SAND", "MOUNTAIN", "CAVE" }) do
  T.eq(onGround(name, function() return levelUp("BURMY", "F", 20) end), api.slotOf("WORMADAM_SANDY"),
       "after " .. name .. ": the Sandy Cloak")
end
for _, name in ipairs({ "BUILDING", "GYM", "LEADER", "CHAMPION" }) do
  T.eq(onGround(name, function() return levelUp("BURMY", "F", 20) end), api.slotOf("WORMADAM_TRASH"),
       "after " .. name .. ": the Trash Cloak")
end
T.eq(onGround("CAVE", function() return levelUp("BURMY", "M", 20) end), api.slotOf("MOTHIM"),
     "a male Burmy becomes Mothim wherever it fought")
T.eq(onGround("GRASS", function() return levelUp("BURMY", "F", 19) end), nil, "and nothing before level 20")
T.eq(levelUp("ESPURR", "F", 25), api.slotOf("MEOWSTIC"), "Espurr evolves into Meowstic, female")
T.eq(levelUp("ESPURR", "M", 25), api.slotOf("MEOWSTIC"), "and male")
T.eq(levelUp("LECHONK", "F", 18), api.slotOf("OINKOLOGNE"), "Lechonk evolves into Oinkologne, female")
T.eq(levelUp("LECHONK", "M", 18), api.slotOf("OINKOLOGNE"), "and male")

-- the evolutions that follow a look (east / west sea, Flabebe's colours) or keep the base look
local function plain(species, level)
  local slot = api.slotOf(species)
  return Evolution.levelTarget({ species = slot, level = level, personality = 0, friendship = 0 }, {})
end
T.eq(plain("DEERLING", 34), api.slotOf("SAWSBUCK"), "Deerling evolves into Sawsbuck at 34")
T.eq(plain("SCATTERBUG", 9), api.slotOf("SPEWPA"), "Scatterbug evolves into Spewpa at 9")
T.eq(plain("SPEWPA", 12), api.slotOf("VIVILLON"), "Spewpa evolves into Vivillon at 12")
T.eq(plain("SHELLOS", 30), api.slotOf("GASTRODON"), "the west-sea Shellos becomes the west-sea Gastrodon")
T.eq(plain("SHELLOS_EAST", 30), api.slotOf("GASTRODON_EAST"), "and the east-sea Shellos the east-sea Gastrodon")
T.eq(plain("FLABEBE", 19), api.slotOf("FLOETTE"), "the red Flabebe becomes the red Floette")
for _, color in ipairs({ "YELLOW", "ORANGE", "BLUE", "WHITE" }) do
  T.eq(plain("FLABEBE_" .. color, 19), api.slotOf("FLOETTE_" .. color), color .. " Flabebe becomes the " .. color .. " Floette")
end
T.eq(plain("FLABEBE", 18), nil, "and not before 19")

-- Pumpkaboo trades into the Gourgeist of its own size, the average one included
local function tradeTarget(species)
  return Evolution.tradeTarget({ species = api.slotOf(species), level = 30, personality = 0 }, {})
end
T.eq(tradeTarget("PUMPKABOO"), api.slotOf("GOURGEIST"), "the average Pumpkaboo trades into the average Gourgeist")
for _, size in ipairs({ "SMALL", "LARGE", "SUPER" }) do
  T.eq(tradeTarget("PUMPKABOO_" .. size), api.slotOf("GOURGEIST_" .. size), size .. " Pumpkaboo trades into the " .. size .. " Gourgeist")
end

-- Dawn Stone, through the item scan
local dawn = run.loader.content.items:get("DAWN_STONE").index
local kirlia, snorunt = Pokemon.speciesFromName("KIRLIA"), Pokemon.speciesFromName("SNORUNT")
local function stone(slot, gender)
  return Evolution.itemTarget({ species = slot, level = 30, personality = personalityFor(slot, gender) }, dawn)
end
T.eq(stone(kirlia, "M"), api.slotOf("GALLADE"), "a male Kirlia evolves into Gallade with a Dawn Stone")
T.eq(stone(kirlia, "F"), nil, "a female Kirlia does not")
T.eq(stone(snorunt, "F"), api.slotOf("FROSLASS"), "a female Snorunt evolves into Froslass")
T.eq(stone(snorunt, "M"), nil, "a male Snorunt does not")
T.eq(Evolution.itemCheck({ species = kirlia, level = 30, personality = personalityFor(kirlia, "F") }, dawn), nil,
     "the party menu's can-it-evolve check agrees")

-- other item evolutions are untouched
local magneton = Pokemon.speciesFromName("MAGNETON")
local thunderStone = run.loader.content.items:get("THUNDER_STONE")
if magneton and thunderStone then
  T.eq(Evolution.itemTarget({ species = magneton, level = 30, personality = 0 }, thunderStone.index),
       api.slotOf("MAGNEZONE"), "an ungendered item evolution (Magneton) still works")
end

-- Floette -> Florges with a Shiny Stone, colour for colour
local shiny = run.loader.content.items:get("SHINY_STONE") and run.loader.content.items:get("SHINY_STONE").index
if shiny then
  local function floette(id)
    return Evolution.itemTarget({ species = api.slotOf(id), level = 30, personality = 0 }, shiny)
  end
  T.eq(floette("FLOETTE"), api.slotOf("FLORGES"), "the red Floette becomes the red Florges")
  for _, color in ipairs({ "YELLOW", "ORANGE", "BLUE", "WHITE" }) do
    T.eq(floette("FLOETTE_" .. color), api.slotOf("FLORGES_" .. color), color .. " Floette becomes the " .. color .. " Florges")
  end
end

-- Basculin (white-striped) -> Basculegion after 294 recoil damage (src/counters.lua)
local Recoil = dofile("mods/national_dex_gen3/src/counters.lua")
Recoil.of = Recoil.recoil
T.eq(Recoil.of(48, 100), 25, "a Take Down-style move recoils a quarter")
T.eq(Recoil.of(198, 100), 33, "a Volt Tackle-style move a third")
T.eq(Recoil.of(48, 2), 1, "and at least 1")
T.eq(Recoil.of(1, 100), 0, "any other move none")

local white = api.slotOf("BASCULIN_WHITE_STRIPED")
local function white_evolves(gender, recoil)
  return Evolution.levelTarget({ species = white, level = 30, recoilTaken = recoil,
    personality = personalityFor(white, gender) }, {})
end
T.eq(white_evolves("M", 294), api.slotOf("BASCULEGION"), "a male white-striped Basculin with 294 recoil becomes Basculegion")
T.eq(white_evolves("F", 294), api.slotOf("BASCULEGION_FEMALE"), "a female becomes the female Basculegion")
T.eq(white_evolves("M", 293), nil, "one short of 294: nothing")
T.eq(white_evolves("M", nil), nil, "and with no recoil taken")
T.eq(Evolution.levelTarget({ species = api.slotOf("BASCULIN"), level = 40, recoilTaken = 999,
  personality = 0 }, {}), nil, "the red-striped Basculin does not evolve")

-- the event: a hit by a recoil move adds to the party Pokemon's total and marks it for the
-- end-of-battle evolution check
local party = { { species = white, level = 30, personality = personalityFor(white, "M") } }
local Battle = require("src.core.game3.battle")
Battle._leveledUp = {}
local function hit(effect, damage, side)
  run.loader.events:emit("battle.damage_dealt", {
    battle = { playerParty = party }, user = { side = side or "player", partyIndex = 1 },
    move = { effect = effect }, damage = damage })
end
hit(1, 400)
T.eq(party[1].recoilTaken, nil, "a move without recoil adds nothing")
hit(48, 400)
T.eq(party[1].recoilTaken, 100, "a quarter of a 400-damage hit")
T.check(not Battle._leveledUp[1], "not marked while short of 294")
hit(198, 600)
T.eq(party[1].recoilTaken, 300, "a third of 600 added")
T.check(Battle._leveledUp[1] == true, "marked for the end-of-battle evolution check once past 294")
hit(48, 400, "enemy")
T.eq(party[1].recoilTaken, 300, "an enemy's hit is not counted")
party[2] = { species = api.slotOf("BASCULIN"), level = 30 }
run.loader.events:emit("battle.damage_dealt", { battle = { playerParty = party },
  user = { side = "player", partyIndex = 2 }, move = { effect = 48 }, damage = 400 })
T.eq(party[2].recoilTaken, nil, "a Pokemon that has no such evolution is not counted")
Battle._leveledUp = nil

-- the tea set: each pot and teacup evolves its own look into the same look
do
  local items = run.loader.content.items
  local function use(species, item)
    return Evolution.itemTarget({ species = api.slotOf(species), level = 30, personality = 0 },
      items:get(item).index)
  end
  T.eq(use("SINISTEA", "CRACKED_POT"), api.slotOf("POLTEAGEIST"), "a Cracked Pot evolves Sinistea into Polteageist")
  T.eq(use("SINISTEA", "CHIPPED_POT"), nil, "a Chipped Pot does nothing to the phony Sinistea")
  T.eq(use("SINISTEA_ANTIQUE", "CHIPPED_POT"), api.slotOf("POLTEAGEIST_ANTIQUE"), "a Chipped Pot evolves the antique Sinistea into the antique Polteageist")
  T.eq(use("SINISTEA_ANTIQUE", "CRACKED_POT"), nil, "and a Cracked Pot does not")
  T.eq(use("POLTCHAGEIST", "UNREMARKABLE_TEACUP"), api.slotOf("SINISTCHA"), "an Unremarkable Teacup evolves Poltchageist into Sinistcha")
  T.eq(use("POLTCHAGEIST", "MASTERPIECE_TEACUP"), nil, "a Masterpiece Teacup does nothing to the counterfeit one")
  T.eq(use("POLTCHAGEIST_ARTISAN", "MASTERPIECE_TEACUP"), api.slotOf("SINISTCHA_MASTERPIECE"), "a Masterpiece Teacup evolves the artisan Poltchageist into the masterpiece Sinistcha")
  T.eq(use("POLTCHAGEIST_ARTISAN", "UNREMARKABLE_TEACUP"), nil, "and an Unremarkable Teacup does not")
end

T.finish("national_dex_gen3 gender")
