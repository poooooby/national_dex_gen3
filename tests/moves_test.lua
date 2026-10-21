-- Standalone: luajit mods/national_dex_gen3/tests/moves_test.lua [game] (from the gen1recomp
-- root; needs that cart imported, FireRed by default).
--
-- Moves newer than Gen 3 that run on a Gen 3 effect (src/moves.lua, data/moves.lua): registered
-- at their own numbers, named by the battle's move index, in learnsets and egg moves as numbers
-- (the registry writes them as names), with a summary text, Fairy where they are Fairy.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"

local data = H.gen3Data(GAME)
local Pokemon = require("src.core.game3.pokemon")
local Moves = require("src.core.game3.battle.moves")
-- the battle's move rows and the species module's mirror, as a game loads them
do
  local pack = GAME .. "/data/generated/gba/pokemon/battle_moves.lua"
  Moves._rom = dofile(pack).moves
  Moves._romLoaded = true
  Pokemon._battleMoves = dofile(pack).moves
  Pokemon._romMoveNames = Pokemon._romMoveNames or Pokemon._moveNames
  data.gen3Moves = Moves                    -- the battle's own module, as a game binds it
end
local payload = dofile("mods/national_dex_gen3/data/moves.lua")

local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local api = run.loader.exports.national_dex_gen3
local content = run.loader.content.moves

local registered = 0
for _, r in ipairs(payload) do if content:get(r.id) then registered = registered + 1 end end
T.eq(registered, #payload, "every move in data/moves.lua is registered (" .. #payload .. ")")
T.check(#payload >= 100, "over a hundred real newer moves")

local byId = {}
for _, r in ipairs(payload) do byId[r.id] = r end
local moon = byId.MOONBLAST
T.check(moon ~= nil and moon.index >= 355, "Moonblast has a number past the cart's moves")

-- before game.ready too: the learnsets carry numbers from the moment mods finish loading
local sylveon = api.slotOf("SYLVEON")
local function learns(slot, num)
  for _, row in ipairs(Pokemon._learnsets[slot] or {}) do
    if row[2] == num then return row[1] end
  end
end
T.eq(learns(sylveon, moon.index), 50, "Sylveon learns MOONBLAST at 50 (a number, not a name)")

-- as a game does after loading mods: the registries go into the live tables, and the engine
-- re-applies them after every reload (Gen3Compat)
pcall(require("src.mods.Gen3Compat").applyMerged, { mods = run.loader, data = data })
run.loader.events:emit("game.ready", {})

-- the row and the names
local row = Pokemon.battleMove(moon.index)
T.check(row ~= nil, "the move row is where the species module reads it")
T.eq(row and row.power, 95, "power 95")
T.eq(row and row.accuracy, 100, "accuracy 100")
T.eq(row and row.pp, 15, "PP 15")
T.eq(row and row.type, 18, "Fairy (src/types.lua)")
T.eq(row and row.secondaryChance, 30, "a 30% secondary effect")
T.eq(Moves._rom[moon.index] and Moves._rom[moon.index].effect, moon.effect, "the battle runs the Gen 3 effect it was given")
T.eq(Moves.constName(moon.index), "MOONBLAST", "the battle's move index names it")
T.eq(Moves.numForName("MOONBLAST"), moon.index, "and finds it by name")
T.eq(Moves.get(moon.index).power, 95, "Moves.get answers for it")
T.eq(Moves.get(moon.index).category, "special", "a Fairy move is special")
T.eq(Pokemon.moveName(moon.index), "MOONBLAST", "the name the game shows")
T.eq(Moves.get(byId.SHADOW_CLAW.index).category, "physical", "Shadow Claw (Ghost) is physical, as Gen 3 splits by type")
T.eq(Moves.get(byId.AQUA_JET.index).priority, 1, "Aqua Jet keeps +1 priority")

-- every learnset and egg move is a number the game has a row for
local bad = {}
local new = 0
for slot, rows in pairs(Pokemon._learnsets) do
  for _, r in ipairs(rows) do
    local n = r[2]
    if type(n) ~= "number" or (n > 0 and not Pokemon.battleMove(n)) then bad[#bad + 1] = slot .. ":" .. tostring(n) end
    if type(n) == "number" and n >= 355 then new = new + 1 end
  end
end
for slot, list in pairs(Pokemon._eggMoves or {}) do
  for _, n in ipairs(list) do
    if type(n) ~= "number" then bad[#bad + 1] = slot .. ":egg:" .. tostring(n) end
  end
end
T.eq(#bad, 0, "every learnset and egg move is a known number (" .. table.concat(bad, ", "):sub(1, 100) .. ")")
T.check(new > 1000, "over a thousand learnset rows are real newer moves (" .. new .. ")")

-- a real reload: Pokemon.install hands out FRESH species tables (move names, the battle-move
-- mirror, learnsets) while the battle keeps its move table; the engine's re-apply (Gen3Compat,
-- moves before species) puts the new moves back at their numbers, Fairy, in every table
do
  local pack = GAME .. "/data/generated/gba/pokemon/battle_moves.lua"
  Pokemon._battleMoves = dofile(pack).moves
  local names = {}
  for k, v in pairs(Pokemon._moveNames) do if type(k) == "number" and k < 355 then names[k] = v end end
  Pokemon._moveNames = names
  Pokemon._runReloadHooks()
  T.eq(Moves._rom[moon.index] and Moves._rom[moon.index].power, 95, "after fresh tables, the battle has MOONBLAST again")
  T.eq(Moves.get(moon.index).type, 18, "still Fairy")
  T.eq(Pokemon.battleMove(moon.index) and Pokemon.battleMove(moon.index).power, 95, "and so does the species module")
  T.eq(Pokemon.moveName(moon.index), "MOONBLAST", "with its name")
  T.eq(learns(sylveon, moon.index), 50, "and Sylveon still learns it at 50")
end

-- text and "used MOVE!"
local SummaryData = require("src.core.game3.summary_data")
local text = SummaryData.moveDescription(moon.index, "MOONBLAST")
T.check(type(text) == "string" and text:find("moon", 1, true) ~= nil, "the summary shows its own text: " .. tostring(text))
local lines = 0
for line in (text .. "\n"):gmatch("(.-)\n") do
  lines = lines + 1
  T.check(#line <= 28, "line fits: " .. line)
end
T.check(lines <= 4, "at most 4 lines")
T.check(require("src.core.game3.battle.battle_text").MOVES_COUNT > moon.index, "battle text names it like a cart move")

run.release()
T.finish("national_dex_gen3 new moves (" .. GAME .. ")")
