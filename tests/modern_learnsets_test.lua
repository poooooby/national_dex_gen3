-- Standalone: luajit mods/national_dex_gen3/tests/modern_learnsets_test.lua [game] (from the
-- gen1recomp root; needs that cart imported, FireRed by default).
--
-- The Modern Moves option (src/modern_learnsets.lua, data/species/modern.lua): on by default;
-- off, the original 386 keep the cart's learnsets; on, they also learn their newer moves at the modern
-- level (and the egg species their newer egg moves); off again puts the cart's own lists back.
-- The option follows the mod menu (mod.options_changed).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"

local data = H.gen3Data(GAME)
local Moves = require("src.core.game3.battle.moves")
local P = require("src.core.game3.pokemon")
do
  local pack = GAME .. "/data/generated/gba/pokemon/battle_moves.lua"
  Moves._rom = dofile(pack).moves
  Moves._romLoaded = true
  P._battleMoves = dofile(pack).moves
  P._romMoveNames = P._romMoveNames or P._moveNames
  data.gen3Moves = Moves
end
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
-- never set by the player: options.lua's default (on)
run.loader.modOptions.national_dex_gen3 = {}
run.loader.events:emit("game.ready", {})

local modern = dofile("mods/national_dex_gen3/data/species/modern.lua")
local MOONBLAST = Moves.numForName("MOONBLAST")
local clefairy = P.speciesFromNational(35)
local cleffa = P.speciesFromNational(173)
local function knowsAt(slot, move)
  for _, row in ipairs(P.learnset(slot)) do if row[2] == move then return row[1] end end
  return nil
end
local function eggHas(slot, move)
  for _, m in ipairs(P.eggMoves(slot) or {}) do if m == move then return true end end
  return false
end
local function setOption(on)
  run.loader.modOptions.national_dex_gen3.modern_moves = on
  run.loader.events:emit("mod.options_changed", { mod = "national_dex_gen3", key = "modern_moves", value = on })
end

T.eq(knowsAt(clefairy, MOONBLAST), 44, "on by default: Clefairy learns Moonblast at 44")
setOption(false)
local cartList = P._learnsets[clefairy]
local cartCount = #P.learnset(clefairy)
T.eq(knowsAt(clefairy, MOONBLAST), nil, "off: Clefairy keeps the cart's learnset")

setOption(true)
T.eq(knowsAt(clefairy, MOONBLAST), 44, "on: Clefairy learns Moonblast at 44, as today")
T.eq(#P.learnset(clefairy), cartCount + #modern[35].learnset, "its Gen 3 moves stay, the newer ones are added")
local sorted = true
local list = P.learnset(clefairy)
for i = 2, #list do if list[i][1] < list[i - 1][1] then sorted = false end end
T.check(sorted, "still in level order")
local eggMove = modern[173] and modern[173].eggMoves and modern[173].eggMoves[1]
if eggMove then T.check(eggHas(cleffa, eggMove), "Cleffa's eggs can have its newer egg moves") end
T.eq(P._learnsets[P.speciesFromName("TURTWIG")] ~= nil, true, "this mod's own species are untouched")

-- the Move Reminder: a level 50 Clefable can relearn Moonblast (a level 1 row today)
local MoveLearn = require("src.core.game3.move_learn")
local clefable = { species = P.speciesFromNational(36), level = 50, moves = { 1, 0, 0, 0 }, pp = { 35, 0, 0, 0 } }
local function offers(mon, move)
  for _, m in ipairs(MoveLearn.relearnableMoves(mon)) do if m == move then return true end end
  return false
end
T.check(offers(clefable, MOONBLAST), "the Move Reminder offers a Clefable Moonblast")
-- and past a learnset's 20th row (the engine stops at 20)
local long, longSlot
for _, id in ipairs({ "SYLVEON", "DECIDUEYE", "GARCHOMP", "LUCARIO", "TOXAPEX" }) do
  local slot = P.speciesFromName(id)
  if slot and #P.learnset(slot) > 20 then long, longSlot = id, slot break end
end
if long then
  local last = P.learnset(longSlot)[#P.learnset(longSlot)]
  T.check(offers({ species = longSlot, level = 100, moves = { 1, 0, 0, 0 }, pp = { 35, 0, 0, 0 } }, last[2]),
    long .. "'s last level-up move (row " .. #P.learnset(longSlot) .. ") is in the Move Reminder")
end

setOption(false)
T.eq(knowsAt(clefairy, MOONBLAST), nil, "off again: Moonblast is gone from the list")
T.eq(P._learnsets[clefairy], cartList, "and the cart's own list is back")
if eggMove then T.check(not eggHas(cleffa, eggMove), "and the egg moves too") end

setOption(true)
setOption(true)
T.eq(#P.learnset(clefairy), cartCount + #modern[35].learnset, "turning it on twice adds the rows once")

run.release()
T.finish("national_dex_gen3 modern moves (" .. GAME .. ")")
