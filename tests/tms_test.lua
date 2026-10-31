-- Standalone: luajit mods/national_dex_gen3/tests/tms_test.lua [game] (from the gen1recomp root;
-- needs that cart imported, FireRed by default).
--
-- The new TMs (src/tms.lua, data/tms.lua): TM51 on, items 1100+ in the TM Case; the engine's
-- TM checks answer for them (isTm, tmNumber, moveFromTmItem, canLearnTmItem), a compatible
-- Pokemon learns the move through the game's own teach flow and the TM is used up, an
-- incompatible one is refused, the TM Case is big enough for every TM, the TM counters sell
-- them, and they survive a save.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"

require("src.core.GameVersion").set(GAME)
do
  local CacheBlob = require("src.import.CacheBlob")
  require("src.core.game3.dataset").cache = function()
    return {
      read = function(_, rel)
        local f = io.open(GAME .. "/" .. rel, "rb")
        if not f then return nil end
        local bytes = f:read("*a")
        f:close()
        return CacheBlob.decode(rel, bytes)
      end,
      exists = function(_, rel)
        local f = io.open(GAME .. "/" .. rel, "rb")
        if f then f:close() end
        return f ~= nil
      end,
    }
  end
end
local data = H.gen3Data(GAME)
local ItemsData = require("src.core.game3.items_data")
if ItemsData.ensureLoaded then ItemsData.ensureLoaded() end
data.gen3Items = ItemsData
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
local okA, errA = pcall(require("src.mods.Gen3Compat").applyMerged, { mods = run.loader, data = data })
T.check(okA, "the registries apply (" .. tostring(errA) .. ")")
run.loader.events:emit("game.ready", {})
pcall(ItemsData.applyProfile, GAME)

local tms = dofile("mods/national_dex_gen3/data/tms.lua")
local byMove = {}
for _, t in ipairs(tms) do byMove[t.move] = t end

-- the item and the engine's TM checks
local first = tms[1]
local info = ItemsData.info(first.index)
T.eq(info and info.name, "TM51", "item " .. first.index .. " is TM51")
T.eq(ItemsData.pocketOf(first.index), "TM_CASE", "in the TM Case")
T.check(ItemsData.isTm(first.index), "the engine counts it as a TM")
T.check(not ItemsData.isHm(first.index), "not an HM (used up when taught)")
T.eq(ItemsData.tmNumber(first.index), 51, "numbered 51")
T.eq(P.moveFromTmItem(first.index), Moves.numForName(first.move), "it teaches " .. first.move)
local last = tms[#tms]
T.eq(ItemsData.tmNumber(last.index), 50 + #tms, "the last is TM" .. (50 + #tms))
T.eq(P.moveFromTmItem(289), P._tmhm.machines[0], "the cart's TM01 is unchanged")

-- who can learn it
local gleam = byMove.DAZZLING_GLEAM
local clefairy, magikarp = P.speciesFromNational(35), P.speciesFromNational(129)
local sylveon = P.speciesFromName("SYLVEON")
T.check(P.canLearnTmItem(sylveon, gleam.index), "Sylveon can learn Dazzling Gleam")
T.check(P.canLearnTmItem(clefairy, gleam.index), "and so can the cart's Clefairy")
T.check(not P.canLearnTmItem(magikarp, gleam.index), "Magikarp cannot")
local form = gleam.forms[1]
if form then
  T.check(P.canLearnTmItem(P.speciesFromName(form), gleam.index), "a form learns it by its own list (" .. form .. ")")
end

-- the game's own teach flow
local ItemUse = require("src.core.game3.item_use")
local Bag = require("src.core.game3.bag")
local bag = Bag.new()
Bag.add(bag, gleam.index, 1)
local mon = { species = sylveon, speciesId = sylveon, level = 50, moves = { 33, 0, 0, 0 }, pp = { 35, 0, 0, 0 },
              personality = 0, otId = 1 }
local session = { party = { mon }, bag = bag }
T.eq((ItemUse.checkTmPreflight(mon, gleam.index)), "ok", "Sylveon may learn it")
local ok, kind = ItemUse.useTm(session, bag, gleam.index, 1)
T.check(ok and kind == "tm", "the TM is used (" .. tostring(kind) .. ")")
T.check(P.knowsMove(mon, Moves.numForName("DAZZLING_GLEAM")), "Sylveon knows Dazzling Gleam")
T.check(not Bag.has(bag, gleam.index, 1), "and the TM is used up")
local karp = { species = magikarp, speciesId = magikarp, level = 20, moves = { 150, 0, 0, 0 }, pp = { 40, 0, 0, 0 } }
T.eq((ItemUse.checkTmPreflight(karp, gleam.index)), "incompatible", "Magikarp is refused")

-- the TM Case fits every TM
local Profile = require("src.core.game3.profile")
local stock = Profile.of(GAME).bag.__nationalDexTmCase
T.eq(ItemsData.CAPACITY.TM_CASE, stock + #tms, "the TM Case holds " .. stock .. " + " .. #tms)
local full = Bag.new()
for id = ItemsData.FIRST_TM, ItemsData.LAST_HM do Bag.add(full, id, 1) end
local all = true
for _, t in ipairs(tms) do all = (Bag.add(full, t.index, 1)) and all end
T.check(all, "every cart TM and HM and every new TM fit at once")

-- sold by the TM vending machine (data/vending.lua), which stands somewhere in this game
local V = run.loader.exports and run.loader.exports.national_dex_gen3 and run.loader.exports.national_dex_gen3._vending
local tmMachine
for _, m in ipairs(V and V.machines or {}) do if m.id == "tm" then tmMachine = m end end
T.check(tmMachine ~= nil and V.placeIn(tmMachine, "firered") ~= nil, "the TM machine stands in FireRed")
local sold = {}
for _, tab in ipairs(tmMachine and V.stock(tmMachine) or {}) do
  for _, e in ipairs(tab.entries) do sold[e.id] = true end
end
local n = 0
for _, t in ipairs(tms) do if sold[t.index] then n = n + 1 end end
T.eq(n, #tms, "every new TM is sold somewhere")

-- saved and loaded
local SaveData = require("src.core.SaveData")
local back = Bag.migrate(SaveData.decode(SaveData.encode({ bag = full })).bag)
local kept = 0
for _, slot in ipairs(back.pockets.TM_CASE or {}) do if tonumber(slot.id) >= 1100 then kept = kept + 1 end end
T.eq(kept, #tms, "after saving and loading, every new TM is still in the TM Case")

run.release()
T.finish("national_dex_gen3 TMs (" .. GAME .. ")")
