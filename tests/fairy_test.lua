-- Standalone: luajit mods/national_dex_gen3/tests/fairy_test.lua [game] (from the gen1recomp
-- root; needs that cart imported, FireRed by default).
--
-- The FAIRY type (src/types.lua): type id 18 in the engine's type_chart registry, the Gen 6
-- chart, every species and form that is Fairy today, the cart's moves that became Fairy, kept
-- across reloads -- and across a second mods load in the same process (the engine rebuilds the
-- chart on every load).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"

local data = H.gen3Data(GAME)
local Types = require("src.core.game3.battle.types")
local Pokemon = require("src.core.game3.pokemon")
local Moves = require("src.core.game3.battle.moves")
local ID = Types.ID
local before = #Types.TABLE
-- the battle's move rows and the species module's mirror, as a game loads them
do
  local pack = GAME .. "/data/generated/gba/pokemon/battle_moves.lua"
  Moves._rom = dofile(pack).moves
  Moves._romLoaded = true
  Pokemon._battleMoves = dofile(pack).moves
  Pokemon._romMoveNames = Pokemon._romMoveNames or Pokemon._moveNames
  data.gen3Moves = Moves
end

-- as a game does: load the mods, apply the registries to the live tables, then game.ready
local function load(fresh)
  if fresh then                                   -- a real second load starts from fresh data
    data = H.gen3Data(GAME)
    data.gen3Moves = Moves
  end
  local r = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
  T.eq(#r.errors, 0, "loads clean (" .. tostring(r.errors[1]) .. ")")
  local okA, errA = pcall(require("src.mods.Gen3Compat").applyMerged, { mods = r.loader, data = data })
  T.check(okA, "the registries apply (" .. tostring(errA) .. ")")
  r.loader.events:emit("game.ready", {})
  return r
end
local run = load()
local api = run.loader.exports.national_dex_gen3

local FAIRY = 18
T.eq(ID.FAIRY, FAIRY, "FAIRY is type 18")
T.eq(Types.name(FAIRY), "FAIRY", "and is named FAIRY")

-- ------- the chart
local function x(atk, def1, def2, foresight)
  local _, _, product = Types.typeCalc(atk, def1, def2, nil, foresight)
  return product
end
T.eq(x(FAIRY, ID.DRAGON), 2, "Fairy hits Dragon x2")
T.eq(x(FAIRY, ID.DARK), 2, "Fairy hits Dark x2")
T.eq(x(FAIRY, ID.FIGHTING), 2, "Fairy hits Fighting x2")
T.eq(x(FAIRY, ID.FIRE), 0.5, "Fire resists Fairy")
T.eq(x(FAIRY, ID.STEEL), 0.5, "Steel resists Fairy")
T.eq(x(FAIRY, ID.POISON), 0.5, "Poison resists Fairy")
T.eq(x(ID.DRAGON, FAIRY), 0, "Dragon can't touch Fairy")
T.eq(x(ID.POISON, FAIRY), 2, "Poison hits Fairy x2")
T.eq(x(ID.STEEL, FAIRY), 2, "Steel hits Fairy x2")
T.eq(x(ID.FIGHTING, FAIRY), 0.5, "Fairy resists Fighting")
T.eq(x(ID.BUG, FAIRY), 0.5, "and Bug")
T.eq(x(ID.DARK, FAIRY), 0.5, "and Dark")
T.eq(x(ID.STEEL, FAIRY, ID.PSYCHIC), 2, "Steel into Psychic/Fairy (Gardevoir) x2")
T.eq(x(ID.DRAGON, ID.WATER, FAIRY), 0, "Dragon into Water/Fairy (Azumarill) does nothing")
T.eq(x(ID.GHOST, ID.STEEL), 1, "Gen 6: Steel no longer resists Ghost")
T.eq(x(ID.DARK, ID.STEEL), 1, "or Dark")
T.eq(x(ID.FIRE, ID.STEEL), 2, "the rest of Steel is untouched")
T.eq(x(ID.NORMAL, ID.GHOST), 0, "Normal still can't hit Ghost")
T.eq(x(ID.NORMAL, ID.GHOST, nil, true), 1, "unless Foresight is up")
T.eq(x(FAIRY, ID.DRAGON, nil, true), 2, "and Fairy's rows still apply under Foresight (before the sentinel)")
T.eq(#Types.TABLE, before + 12 * 3 - 2 * 3, "12 Fairy rows in, 2 Steel rows out")
T.eq(Types.effectiveness(FAIRY, ID.DRAGON), 2, "the AI's own check agrees (Fairy into Dragon)")
T.eq(Types.effectiveness(ID.DRAGON, FAIRY), 0, "(Dragon into Fairy)")
T.eq(Types.effectiveness(ID.GHOST, ID.STEEL), 1, "(Ghost into Steel)")
T.eq(Types.effectiveness(ID.NORMAL, ID.GHOST), 0, "(Normal into Ghost)")
T.check(not Types.isPhysical(FAIRY), "Fairy is special, as Gen 3 splits by type")

-- ------- species
local function types(slot) local t = Pokemon.types(slot) return t[1] .. "/" .. t[2] end
local function nat(dex) return Pokemon.speciesFromNational(dex) end
T.eq(types(nat(35)), "18/18", "Clefairy is Fairy")
T.eq(types(nat(39)), ID.NORMAL .. "/18", "Jigglypuff is Normal/Fairy")
T.eq(types(nat(183)), ID.WATER .. "/18", "Marill is Water/Fairy")
T.eq(types(nat(282)), ID.PSYCHIC .. "/18", "Gardevoir is Psychic/Fairy")
T.eq(types(nat(303)), ID.STEEL .. "/18", "Mawile is Steel/Fairy")
T.eq(types(nat(176)), "18/" .. ID.FLYING, "Togetic is Fairy/Flying")
T.eq(types(api.slotOf("TOGEKISS")), "18/" .. ID.FLYING, "Togekiss is Fairy/Flying")
T.eq(types(api.slotOf("SYLVEON")), "18/18", "Sylveon is Fairy")
T.eq(types(api.slotOf("NINETALES_ALOLA")), ID.ICE .. "/18", "Alolan Ninetales is Ice/Fairy")
T.eq(types(api.slotOf("ALCREMIE_RUBY_CREAM")), "18/18", "every Alcremie cream is Fairy")
T.eq(types(nat(25)), ID.ELECTRIC .. "/" .. ID.ELECTRIC, "Pikachu is untouched")
T.eq(types(api.slotOf("TURTWIG")), ID.GRASS .. "/" .. ID.GRASS, "Turtwig is untouched")

-- ------- the cart's moves
local FairyTypes = dofile("mods/national_dex_gen3/src/types.lua")
local function num(name) return FairyTypes.moveNum(require, name) end
local function battleType(n) return Moves._rom and Moves._rom[n] and Moves._rom[n].type end
for _, name in ipairs({ "CHARM", "SWEET_KISS", "MOONLIGHT" }) do
  T.check(num(name) ~= nil, name .. " is found")
  T.eq(battleType(num(name)), FAIRY, name .. " is a Fairy move in battle")
  T.eq(Pokemon.battleMove(num(name)).type, FAIRY, name .. " shows as Fairy")
end
T.eq(battleType(num("TACKLE")), ID.NORMAL, "Tackle is still Normal")

-- ------- reloads put it back
Pokemon._types[nat(35)] = { 0, 0 }
Moves._rom[num("CHARM")].type = 0
Pokemon._runReloadHooks()
Moves._runReloadHooks()
T.eq(types(nat(35)), "18/18", "a species reload re-applies Fairy")
T.eq(battleType(num("CHARM")), FAIRY, "a move reload re-applies Charm's type")

-- ------- FireRed/LeafGreen badges draw instead of failing
love = love or require("tests.love_stub")
local okC, PokedexChrome = pcall(require, "src.ui.game3.pokedex_chrome")
if okC then
  T.check(pcall(PokedexChrome.drawTypeBadge, FAIRY, 0, 0), "the Pokedex badge for Fairy does not assert")
end

run.release()
-- ------- a second mods load in the same process (another cart, the editor, a hot reload): the
-- engine rebuilds the chart from the registries, and Fairy comes back with them
run.release()
local run2 = load(true)
T.eq(Types.name(FAIRY), "FAIRY", "after a second load FAIRY is still named")
T.eq(x(FAIRY, ID.DRAGON), 2, "and still beats Dragon")
T.eq(x(ID.DRAGON, FAIRY), 0, "and Dragon still can't touch it")
run2.release()

T.finish("national_dex_gen3 Fairy type (" .. GAME .. ")")
