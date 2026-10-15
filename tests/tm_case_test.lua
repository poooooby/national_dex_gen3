-- Standalone: luajit mods/national_dex_gen3/tests/tm_case_test.lua [game] (from the gen1recomp
-- root; needs that cart imported, FireRed by default).
--
-- A TM at index 900+ (the range this mod's items use): a registered item with pocket TM_CASE is
-- filed in the TM Case, survives the save slot round trip (Schema.toSaveTable's bag, encoded and
-- decoded as a slot file, Bag.migrate on load), and the TM Case's capacity (ItemsData.CAPACITY,
-- refilled from the game profile's bag.capacity) can be raised so it fits next to all 58 TMs/HMs.
-- The stub mod tests/fixtures/tm_item registers the item.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"

require("src.core.GameVersion").set(GAME)
-- the item and bag packs are read through the dataset cache, as a game reads them
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
-- the registry writes items into the live item module, as a game binds it
local ItemsData = require("src.core.game3.items_data")
if ItemsData.ensureLoaded then ItemsData.ensureLoaded() end
data.gen3Items = ItemsData
local run = T.sdk.loadMods({ "mods/national_dex_gen3", "mods/national_dex_gen3/tests/fixtures/tm_item" },
  { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
-- what a game does before game.ready: the registries onto the live tables (items included)
local okA, errA = pcall(require("src.mods.Gen3Compat").applyMerged, { mods = run.loader, data = data })
T.check(okA, "the registries apply (" .. tostring(errA) .. ")")
run.loader.events:emit("game.ready", {})

local Bag = require("src.core.game3.bag")
local SaveData = require("src.core.SaveData")
local Profile = require("src.core.game3.profile")
pcall(ItemsData.applyProfile, GAME)
local TM = 950

T.eq(ItemsData.pocketOf(TM), "TM_CASE", "a 900+ item with pocket TM_CASE belongs in the TM Case")

local bag = Bag.new()
T.check((Bag.add(bag, TM, 1)), "it can be put in the bag")
local inCase = false
for _, slot in ipairs(bag.pockets.TM_CASE or {}) do if tonumber(slot.id) == TM then inCase = true end end
T.check(inCase, "and is filed in the TM Case")

-- the save slot round trip: the bag as the save table holds it, written and read as a slot file
local text = SaveData.encode({ bag = bag, inventory = bag })
local loaded = SaveData.decode(text)
local back = Bag.migrate(loaded and loaded.bag)
local qty
for _, slot in ipairs(back.pockets.TM_CASE or {}) do if tonumber(slot.id) == TM then qty = slot.qty end end
T.eq(qty, 1, "after saving and loading, it is still in the TM Case")
T.check(Bag.has(back, TM, 1), "and the bag knows it")

-- capacity: a full TM Case (every TM and HM) has no room at the stock size
local cap = ItemsData.CAPACITY.TM_CASE
local full = Bag.new()
for id = ItemsData.FIRST_TM, ItemsData.LAST_HM do Bag.add(full, id, 1) end
T.eq(#(full.pockets.TM_CASE or {}), ItemsData.LAST_HM - ItemsData.FIRST_TM + 1, "all " .. (ItemsData.LAST_HM - ItemsData.FIRST_TM + 1) .. " TMs and HMs fit")
local roomStock = Bag.canAdd(full, TM, 1)
print(("%s: TM Case holds %s; room for a new TM next to all of them: %s"):format(GAME, tostring(cap), tostring(roomStock)))
-- raised on the game profile (what ItemsData.CAPACITY is refilled from), it fits
local profileBag = Profile.of(GAME).bag
profileBag.capacity.TM_CASE = cap + 40
ItemsData.applyProfile(GAME)
T.eq(ItemsData.CAPACITY.TM_CASE, cap + 40, "the TM Case's capacity follows the game profile")
T.check(Bag.canAdd(full, TM, 1), "raised, a new TM fits next to every TM and HM")
T.check((Bag.add(full, TM, 1)), "and goes in")
profileBag.capacity.TM_CASE = cap
ItemsData.applyProfile(GAME)

run.release()
T.finish("national_dex_gen3 TM Case (" .. GAME .. ")")
