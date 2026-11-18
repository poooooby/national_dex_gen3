-- Standalone: luajit mods/national_dex_gen3/tests/bigger_bag_test.lua [game] (from the gen1recomp
-- root; FireRed by default, needs that cart imported; red / gold / ... run the Gen 1/2 half,
-- src/gen12/bigger_bag.lua: the Bag's pockets, Red's PC limit and Gold's PC menu).
--
-- The Bigger Bag option (src/bigger_bag.lua): on by default, the Items pocket holds 300 different
-- items, Key Items 60, Poke Balls 30, Berries 60 and the PC 300; the TM Case keeps its own (grown)
-- size; off gives the game's own limits back, and nothing is ever dropped: a save's PC loads
-- whole, and a pocket over the limit keeps its items and only refuses new ones.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"
local OWN = {
  firered = { ITEMS = 42, PC = 30 }, leafgreen = { ITEMS = 42, PC = 30 },
  emerald = { ITEMS = 30, PC = 50 }, ruby = { ITEMS = 20, PC = 50 }, sapphire = { ITEMS = 20, PC = 50 },
}

local GEN12 = ({ red = 1, blue = 1, yellow = 1, gold = 2, silver = 2, crystal = 2 })[GAME]
if GEN12 then
  local H12 = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")
  local run = H12.load(GAME)
  T.eq(#run.errors, 0, GAME .. ": loads clean (" .. tostring(run.errors[1]) .. ")")
  local Runtime = require("src.mods.Runtime")
  local Bag = require("src.inventory.Bag")
  local data = run.data
  run.loader.modOptions.national_dex_gen3 = {}
  local function setOption(on)
    run.loader.modOptions.national_dex_gen3.bigger_bag = on
    Runtime.emit("mod.options_changed", { mod = "national_dex_gen3", key = "bigger_bag", value = on })
  end
  local game = { data = data, save = { inventory = {}, pcItems = {} } }
  Runtime.emit("game.ready", { game = game })
  T.eq(Bag.capacity(data), 300, GAME .. ": on by default: the Bag holds 300 kinds")
  T.eq(Bag.capacity(data, "ITEM"), 300, GAME .. ": the ITEM pocket too")
  T.eq(data.field.pcItemCap, 300, GAME .. ": the PC holds 300 kinds")
  if GEN12 == 2 then
    T.eq(Bag.capacity(data, "BALL"), 30, GAME .. ": 30 kinds of Balls")
    T.eq(Bag.capacity(data, "KEY_ITEM"), 60, GAME .. ": 60 Key Items")
  end
  local tmhm = Bag.capacity(data, "TM_HM")
  -- the Bag past the game's 20
  local ids = {}
  for id, def in pairs(data.items) do
    if type(def) == "table" and (def.pocket == nil or def.pocket == "ITEM") and def.price and def.price > 0
        and not tostring(id):match("^TM") and not tostring(id):match("^HM") then ids[#ids + 1] = id end
  end
  table.sort(ids)
  local save = game.save
  local added = 0
  for i = 1, 30 do if ids[i] and Bag.add(save, ids[i], 1, data) then added = added + 1 end end
  T.eq(added, 30, GAME .. ": on: the Bag takes 30 kinds (the game's own holds 20)")
  local ItemPcMenu = GEN12 == 2 and require("src.ui.gen2.ItemPcMenu") or nil
  local pcSelf = { save = { pcItems = {} } }
  if ItemPcMenu then
    local stored = 0
    for i = 1, 60 do if ids[i] and ItemPcMenu.pcAdd(pcSelf, ids[i], 1) then stored = stored + 1 end end
    T.eq(stored, math.min(60, #ids), GAME .. ": on: Gold's PC menu stores past 50")
  end

  setOption(false)
  T.eq(Bag.capacity(data), 20, GAME .. ": off: the game's own Bag")
  T.eq(data.field.pcItemCap, nil, GAME .. ": off: the game's own PC")
  T.eq(Bag.capacity(data, "TM_HM"), tmhm, GAME .. ": the TM pocket unchanged")
  local kinds = 0
  for _ in pairs(save.inventory) do kinds = kinds + 1 end
  T.check(kinds >= 30, GAME .. ": off: a fuller Bag keeps every item")
  T.check(not Bag.add(save, ids[31], 1, data), GAME .. ": off: and takes no new kind")
  if ItemPcMenu and ids[61] then
    T.check(not ItemPcMenu.pcAdd(pcSelf, ids[61], 1), GAME .. ": off: Gold's PC menu over 50 takes no new kind")
  end
  setOption(true)
  T.eq(Bag.capacity(data), 300, GAME .. ": on again")
  T.eq(data.field.pcItemCap, 300, GAME .. ": the PC too")
  run.release()
  T.finish("national_dex_gen3 bigger bag (" .. GAME .. ")")
  return
end

local data = H.gen3Data(GAME)
H.useCart(GAME)
data.gen3Moves = require("src.core.game3.battle.moves")
data.gen3Items = require("src.core.game3.items_data")
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.modOptions.national_dex_gen3 = {}
pcall(require("src.mods.Gen3Compat").applyMerged, { mods = run.loader, data = data })
run.loader.events:emit("game.ready", {})

local ItemsData = require("src.core.game3.items_data")
local Storage = require("src.core.game3.storage")
local Bag = require("src.core.game3.bag")
local own = OWN[GAME]
local SESSION = { version = GAME }

local function setOption(on)
  run.loader.modOptions.national_dex_gen3.bigger_bag = on
  run.loader.events:emit("mod.options_changed", { mod = "national_dex_gen3", key = "bigger_bag", value = on })
end

ItemsData.applyProfile(GAME)
local tmCase = ItemsData.CAPACITY.TM_CASE
T.eq(ItemsData.CAPACITY.ITEMS, 300, "on by default: 300 kinds in the Items pocket")
T.eq(ItemsData.CAPACITY.KEY_ITEMS, 60, "60 Key Items")
T.eq(ItemsData.CAPACITY.POKE_BALLS, 30, "30 kinds of Poke Balls")
T.eq(ItemsData.CAPACITY.BERRY_POUCH, 60, "60 kinds of Berries")
T.eq(Storage.pcItemsCount(SESSION), 300, "the PC holds 300 kinds of items")
T.check(tmCase > 58, "the TM Case keeps its own grown size (" .. tostring(tmCase) .. ")")

-- items to fill a pocket with: every ITEMS-pocket item the game knows, in index order
local ids = {}
for id = 1, 2047 do
  local okP, pocket = pcall(ItemsData.pocketOf, id)
  if okP and pocket == "ITEMS" then ids[#ids + 1] = id end
end
T.check(#ids > own.ITEMS + 20, "enough Items-pocket items to pass the game's limit (" .. #ids .. ")")
local bag = Bag.new()
local added = 0
for i = 1, own.ITEMS + 20 do if Bag.add(bag, ids[i], 1) then added = added + 1 end end
T.eq(added, own.ITEMS + 20, "on: the Items pocket takes more than the game's " .. own.ITEMS)

setOption(false)
T.eq(ItemsData.CAPACITY.ITEMS, own.ITEMS, "off: the game's own Items pocket")
T.eq(Storage.pcItemsCount(SESSION), own.PC, "off: the game's own PC")
T.eq(ItemsData.CAPACITY.TM_CASE, tmCase, "off: the TM Case unchanged")
T.eq(#(bag.pockets.ITEMS or {}), own.ITEMS + 20, "off: a fuller pocket keeps every item")
T.check(not Bag.canAdd(bag, ids[own.ITEMS + 21], 1), "off: and takes no new kind")
T.check(Bag.canAdd(bag, ids[1], 1), "off: but more of one it holds")
ItemsData.applyProfile(GAME)
T.eq(ItemsData.CAPACITY.ITEMS, own.ITEMS, "off: a profile refill keeps the game's own size")

-- a save's PC loads whole either way (the legacy shapes trim to the limit)
local pcItems = {}
for i = 1, own.PC + 15 do pcItems[i] = { id = ids[i], qty = 1 } end
local storage = Storage.restore(nil, nil, pcItems)
T.eq(#storage.items, own.PC + 15, "off: a save's fuller PC loads with every item")
T.eq(Storage.pcItemsCount(SESSION), own.PC, "and the limit is the game's own again after loading")

setOption(true)
T.eq(ItemsData.CAPACITY.ITEMS, 300, "on again: 300")
ItemsData.applyProfile(GAME)
T.eq(ItemsData.CAPACITY.ITEMS, 300, "on: a profile refill keeps the bigger size")
T.eq(ItemsData.CAPACITY.TM_CASE, tmCase, "on: the TM Case unchanged")

run.release()
T.finish("national_dex_gen3 bigger bag (" .. GAME .. ")")
