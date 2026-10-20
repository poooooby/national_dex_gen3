-- Standalone: luajit mods/national_dex_gen3/tests/big_pc_test.lua [game] (from the gen1recomp root;
-- needs that cart imported, FireRed by default).
--
-- The Bigger PC option (src/big_pc.lua, option big_pc, on by default): 40 boxes; boxes 15-40 are
-- saved in this mod's save data, never in the save's own storage, so the core save stays a
-- 14-box save; turning the option off (or removing the mod) keeps them, and turning it on brings
-- them back; new boxes cycle the 16 cart wallpapers.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"

local data = H.gen3Data(GAME)
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local Storage = require("src.core.game3.storage")
local function setOption(on)
  run.loader.modOptions.national_dex_gen3 = { big_pc = on }
end

-- ------- on by default: 40 boxes, the 16 wallpapers past box 14

T.eq(Storage.TOTAL_BOXES_COUNT, 40, "on by default: 40 boxes")
T.eq(Storage.TOTAL_BOX_MONS, 1200, "1200 Pokemon")
local fresh = Storage.new()
T.eq(#fresh.boxes, 40, "a new game's PC has 40 boxes")
T.eq(fresh.boxes[40].name, "BOX 40", "named BOX 40")
T.eq(fresh.boxes[5].wallpaper, 1, "boxes 1-14 keep the cart's four wallpapers (box 5 is Forest again)")
T.eq(fresh.boxes[15].wallpaper, 15, "box 15 starts on wallpaper 15")
T.eq(fresh.boxes[17].wallpaper, 1, "and the 16 wallpapers go round (box 17 is wallpaper 1)")
T.eq(fresh.boxes[32].wallpaper, 16, "box 32 is wallpaper 16")

-- ------- saving: boxes 15-40 go to the mod's save data

local mon = { species = 451, level = 5, nickname = "" }
local storage = Storage.new()
storage.boxes[37].mons[4] = mon
storage.boxes[20].name = "FAVES"
storage.boxes[2].mons[1] = { species = 1, level = 5 }
storage.currentBox = 37
local session = { storage = storage, modData = {} }
local save = { storage = Storage.serialize(storage), modData = session.modData }
T.check(save.storage.boxes[37] ~= nil, "the engine serializes box 37 with 40 boxes")
run.loader.events:emit("save.writing", { save = save })
local maxBox = 0
for b in pairs(save.storage.boxes) do maxBox = math.max(maxBox, b) end
T.eq(maxBox, 2, "the written save's own storage holds boxes 1-14 only")
T.eq(save.storage.currentBox, 1, "and a current box a 14-box game can open")
local pc = save.modData.national_dex_gen3 and save.modData.national_dex_gen3.pc
T.check(pc and pc.boxes[37] and pc.boxes[37].mons[4] == mon, "box 37's Pokemon is in the mod's save data")
T.eq(pc and pc.boxes[20] and pc.boxes[20].name, "FAVES", "a renamed empty box is kept too")
T.eq(pc and pc.boxes[21], nil, "an untouched empty box is not stored")
T.eq(pc and pc.currentBox, 37, "and the real current box")

-- the same file read by a game without the mod (14 boxes): nothing is lost on its next save
Storage.TOTAL_BOXES_COUNT = 14
local stock = Storage.deserialize(save.storage)
T.eq(#stock.boxes, 14, "without the mod the save is a normal 14-box save")
local stockSave = { storage = Storage.serialize(stock), modData = save.modData }
T.check(stockSave.modData.national_dex_gen3.pc.boxes[37].mons[4] == mon, "and its next save still carries boxes 15-40")

-- ------- loading: back into the PC

local function load(raw)
  run.loader.events:emit("save.loading", { raw = raw })
  return Storage.restore(raw.storage)
end
local raw = { storage = stockSave.storage, modData = stockSave.modData }
local loaded = load(raw)
T.eq(#loaded.boxes, 40, "loading with the option on gives 40 boxes")
T.check(loaded.boxes[37].mons[4] == mon, "with the Pokemon back in box 37")
T.eq(loaded.boxes[20].name, "FAVES", "the renamed box")
T.eq(loaded.currentBox, 37, "and the current box")
T.eq(raw.modData.national_dex_gen3.pc, nil, "the save data copy is cleared once it is back in the PC")

-- ------- option off: hidden, never lost

local again = { storage = Storage.serialize(loaded), modData = {} }
run.loader.events:emit("save.writing", { save = again })
setOption(false)
local offLoaded = load({ storage = again.storage, modData = again.modData })
T.eq(Storage.TOTAL_BOXES_COUNT, 14, "option off: 14 boxes")
T.eq(#offLoaded.boxes, 14, "the PC shows 14 boxes")
local offSave = { storage = Storage.serialize(offLoaded), modData = again.modData }
run.loader.events:emit("save.writing", { save = offSave })
T.check(offSave.modData.national_dex_gen3.pc and offSave.modData.national_dex_gen3.pc.boxes[37].mons[4] == mon,
  "saving with the option off keeps boxes 15-40 in the save data")
setOption(true)
local backOn = load({ storage = offSave.storage, modData = offSave.modData })
T.check(backOn.boxes[37].mons[4] == mon, "option on again: the Pokemon is back in box 37")

-- ------- the option changed while playing

local BigPc = dofile("mods/national_dex_gen3/src/big_pc.lua")
local live = { storage = Storage.new(), modData = {} }
BigPc.setCount(Storage, true)
live.storage = Storage.new()
live.storage.boxes[30].mons[1] = mon
live.storage.currentBox = 30
BigPc.toggleLive(Storage, live, false)
T.eq(#live.storage.boxes, 14, "turned off while playing: the PC shrinks to 14 boxes")
T.eq(live.storage.currentBox, 1, "on a box that exists")
T.check(live.modData.national_dex_gen3.pc.boxes[30].mons[1] == mon, "box 30 waits in the save data")
BigPc.toggleLive(Storage, live, true)
T.eq(#live.storage.boxes, 40, "turned on again: 40 boxes")
T.check(live.storage.boxes[30].mons[1] == mon, "box 30's Pokemon is back")
T.eq(live.storage.currentBox, 30, "and so is the current box")

-- caught Pokemon spill into boxes past 14
BigPc.setCount(Storage, true)
local full = Storage.new()
for b = 1, 14 do for s = 1, 30 do full.boxes[b].mons[s] = { species = 1 } end end
full.currentBox = 14
local fb, fs = Storage.findOpenSlot(full)
T.eq(fb, 15, "with boxes 1-14 full, the next Pokemon goes to box 15")
T.eq(fs, 1, "slot 1")

T.finish("national_dex_gen3 bigger PC (" .. GAME .. ")")
