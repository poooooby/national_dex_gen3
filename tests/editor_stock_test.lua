-- Standalone: luajit mods/national_dex_gen3/tests/editor_stock_test.lua (from the gen1recomp
-- root; needs Pokemon FireRed imported under firered/ and the stock tools/save-editor).
--
-- The save editor loads mods without starting a game (src/editor.lua). Loaded the way the stock
-- editor loads them (Data:load, Gen.bindGame3Data, then the mod loader), every species and form
-- this mod registers must be in the editor's species list, with its own slot, name and moves.
package.path = "./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua;"
  .. package.path
local ok, Gen = pcall(require, "Gen")
if not ok then print("skipped: the save editor is not in this checkout") os.exit(0) end

local T = require("tests.modkit")
love = love or require("tests.love_stub")
local CacheBlob = require("src.import.CacheBlob")
local function path(rel) return "firered/" .. rel end
local reader = {
  read = function(_, rel)
    local f = io.open(path(rel), "rb")
    if not f then return nil end
    local data = f:read("*a"); f:close()
    return CacheBlob.decode(rel, data)
  end,
  exists = function(_, rel)
    local f = io.open(path(rel), "rb")
    if f then f:close() return true end
    return false
  end,
}
if not reader:exists("data/generated/gba/pokemon/names.lua") then
  print("skipped: FireRed is not imported")
  os.exit(0)
end

require("src.core.GameVersion").set("firered")
local Dataset = require("src.core.game3.dataset")
Dataset.cache = function() return reader end
local Data = require("src.core.Data")
local MonOps = require("MonOps")
local P = require("src.core.game3.pokemon")

-- what App.load does, in its order; the player has turned Modern Moves on (the editor reads the
-- same saved options as the game; nothing is written back from this test)
local SaveData = require("src.core.SaveData")
local loadOptions, saveOptions = SaveData.loadOptions, SaveData.saveOptions
SaveData.loadOptions = function(...)
  local o = loadOptions(...) or {}
  o.modOptions = o.modOptions or {}
  o.modOptions.national_dex_gen3 = { modern_moves = true }
  return o
end
SaveData.saveOptions = function() end
Data:load()
Gen.bindGame3Data(Data)
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = Data, generation = 3 })
SaveData.loadOptions, SaveData.saveOptions = loadOptions, saveOptions
T.eq(#run.errors, 0, "the mod loads in the editor (" .. tostring(run.errors[1]) .. ")")

for _, id in ipairs({ "TURTWIG", "ABOMASNOW", "PECHARUNT" }) do
  local row = Data.pokemon[id]
  T.check(row ~= nil, id .. " is in the editor's species list")
  T.eq(row and row.speciesId, row and P.speciesFromName(id), id .. " has its own slot")
  local mon = MonOps.create(Data, id, 30, 3)
  T.eq(mon.speciesId, row and row.speciesId, id .. " made in the editor is that species, not Bulbasaur")
  T.eq(mon.name, id, id .. " made in the editor has its name")
  T.check(#mon.moves > 0, id .. " made in the editor has moves")
end
T.eq(Data.pokemon[P.speciesFromName("TURTWIG")], Data.pokemon.TURTWIG, "the list finds it by slot too")
T.eq(Data.pokemon.TURTWIG.dex, 387, "and by its National number")

local galar = Data.pokemon.DARUMAKA_GALAR
T.check(galar ~= nil, "a form is in the list under its own id")
T.eq(galar and galar.name, "DARUMAKA (GALAR)", "labelled with its form")
T.eq(galar and galar.dex, 554, "with its base's National number")
T.check(Data.pokemon.DARUMAKA and Data.pokemon.DARUMAKA ~= galar, "and the base keeps its own row")
local formMon = MonOps.create(Data, "DARUMAKA_GALAR", 20, 3)
T.eq(formMon.speciesId, galar and galar.speciesId, "a form made in the editor keeps its slot")
T.check(#formMon.moves > 0, "and has moves")

T.eq(P.national(P.speciesFromName("TURTWIG")), 387, "the live tables know its National number")
T.check(Data.pokemon.BULBASAUR ~= nil, "the cart's own species are still listed")

-- pictures: the editor asks Pokemon.frontPic for the species' slot, which a sprite mod
-- (g9-battle-sprites-gen3) answers; here a stand-in records what was asked
do
  local MonEditor = require("MonEditor")
  local asked = {}
  local frontPic = P.frontPic
  P.frontPic = function(slot, ...) asked[#asked + 1] = slot return { image = { slot = slot } } end
  local S = { data = Data, save = { version = "firered", generation = 3 } }
  local okGen = pcall(function() return Gen.ofState(S) end)
  local turtwigPic = MonEditor.sprite(S, "TURTWIG", { personality = 0 })
  local formPic = MonEditor.sprite(S, "DARUMAKA_GALAR", { personality = 0 })
  P.frontPic = frontPic
  T.check(okGen, "the editor state stand-in is accepted")
  T.eq(turtwigPic and turtwigPic.slot, P.speciesFromName("TURTWIG"), "the editor asks for TURTWIG's own picture")
  T.eq(formPic and formPic.slot, galar and galar.speciesId, "and the form's own picture")
end

-- learnsets: every species and form has the level-up moves this mod registered for it, row
-- for row, on the live tables the editor reads (and a new one made there knows them)
do
  local registry = run.loader.content.pokemon
  local index = dofile("mods/national_dex_gen3/data/species/index.lua")
  local checked, wrong, empty = 0, {}, 0
  local function compare(id)
    local record = registry:get(id)
    local slot = P.speciesFromName(id)
    if not (record and slot) then wrong[#wrong + 1] = id .. " (missing)" return end
    local want = record.learnset or {}
    local have = P.learnset(slot) or {}
    if #want == 0 then empty = empty + 1 end
    if #have ~= #want then wrong[#wrong + 1] = id return end
    for i, r in ipairs(want) do
      local level = tonumber(r.level or r[1])
      if tonumber(have[i] and have[i][1]) ~= level or not tonumber(have[i][2]) or have[i][2] == 0 then
        wrong[#wrong + 1] = id .. " row " .. i
        return
      end
    end
    checked = checked + 1
  end
  local ids = {}
  for _, shard in ipairs(index.shards) do
    for _, r in ipairs(dofile("mods/national_dex_gen3/data/species/" .. shard)) do ids[#ids + 1] = r.id end
  end
  for _, f in ipairs(dofile("mods/national_dex_gen3/data/species/forms.lua")) do ids[#ids + 1] = f.id end
  for _, id in ipairs(ids) do compare(id) end
  T.eq(#wrong, 0, "every species and form has its full learnset in the editor (" .. table.concat(wrong, ", "):sub(1, 120) .. ")")
  T.eq(checked, 639 + 128, "all 639 species and 128 forms checked")
  T.eq(empty, 0, "none of them is empty")
  -- what the editor gives a new one: the last four moves it knows at that level
  local row = P.learnset(P.speciesFromName("TURTWIG"))
  local mon = MonOps.create(Data, "TURTWIG", 30, 3)
  local learnt = {}
  for _, m in ipairs(mon.moves) do learnt[tonumber(m.moveId or m.id or m)] = true end
  local expect = 0
  for _, r in ipairs(row) do if r[1] <= 30 then expect = expect + 1 end end
  T.eq(#mon.moves, math.min(4, expect), "a level 30 TURTWIG made in the editor knows its last four moves")
  T.check(learnt[row[1][2]] ~= nil or expect > 4, "taken from its own learnset")
end

-- items: this mod's items (index 900+) are in the editor's item list, by name and by number
do
  local ItemsData = require("src.core.game3.items_data")
  local items = dofile("mods/national_dex_gen3/data/items.lua")
  local missing = {}
  for _, it in ipairs(items) do
    local row = Data.items[it.index]
    if not (row and row.itemId == it.index and row.name == it.name and Data.items[row.id] == row) then
      missing[#missing + 1] = it.id
    end
  end
  T.eq(#missing, 0, "every item is in the editor's item list (" .. table.concat(missing, ", ") .. ")")
  T.eq(Data.items.DAWN_STONE and Data.items.DAWN_STONE.itemId, 900, "found by name (DAWN_STONE)")
  T.eq(Data.items.LEADER_S_CREST and Data.items.LEADER_S_CREST.name, "LEADER'S CREST", "a name with an apostrophe")
  T.eq(ItemsData.info(900) and ItemsData.info(900).name, "DAWN STONE", "and the item data answers for it")
  local found = false
  for _, id in ipairs(require("Catalog").build(Data, { version = "firered", generation = 3 }, "firered").items) do
    if Data.items[id] and Data.items[id].itemId == 935 then found = true end
  end
  T.check(found, "the editor's item picker lists the last of them (935)")
end

-- moves: this mod's newer moves are in the editor's move list, and one can be set on a Pokemon
do
  local moon = Data.moves.MOONBLAST
  T.check(moon ~= nil and moon.moveId >= 355, "MOONBLAST is in the editor's move list")
  T.eq(Data.moves[moon and moon.moveId or 0], moon, "by number too")
  local mon = MonOps.create(Data, "SYLVEON", 50, 3)
  local okSet = pcall(MonOps.setMove, Data, mon, 1, "MOONBLAST")
  T.check(okSet, "the editor can teach it")
end

-- abilities: the editor's ability picker reads Pokemon.abilities / abilityName, which carry the
-- real newer abilities (src/abilities.lua), and a Pokemon made there has one
do
  local slot = P.speciesFromName("AMBIPOM")
  local pair = P.abilities(slot)
  T.eq(P.abilityName(pair[1]), "TECHNICIAN", "AMBIPOM's first ability in the editor is TECHNICIAN")
  T.eq(P.abilityName(pair[2]), "PICKUP", "and its second the cart's PICKUP")
  local mon = MonOps.create(Data, "AMBIPOM", 30, 3)
  T.check(mon.ability == pair[1] or mon.ability == pair[2], "an AMBIPOM made in the editor has one of them")
  local Legality = require("Legality")
  local okC, report = pcall(Legality.mon, { data = Data, save = { version = "firered", generation = 3 } }, mon)
  T.check(okC and type(report) == "table", "the editor's legality check runs (" .. tostring(not okC and report or "") .. ")")
  local bad
  for _, issue in ipairs(okC and type(report) == "table" and report.checks or {}) do
    if issue.field == "ability" then bad = issue.message end
  end
  T.eq(bad, nil, "and accepts its ability")
end

-- the Fairy type: the editor shows species and move types from the live tables and its own move
-- rows; SYLVEON is Fairy, Moonblast and the cart's Charm are Fairy moves
do
  local Types = require("src.core.game3.battle.types")
  T.eq(Types.ID.FAIRY, 18, "the editor knows the Fairy type")
  T.eq(P.types(P.speciesFromName("SYLVEON"))[1], 18, "SYLVEON is Fairy in the editor")
  T.eq(P.types(P.speciesFromName("CLEFAIRY"))[1], 18, "and so is the cart's CLEFAIRY")
  T.eq(Data.moves.MOONBLAST and Data.moves.MOONBLAST.type, "FAIRY", "MOONBLAST is listed as a Fairy move")
  local charm = Data.moves.CHARM
  T.check(charm and (charm.type == "FAIRY" or charm.type == 18), "and so is the cart's CHARM (" .. tostring(charm and charm.type) .. ")")
end

-- the new TMs: listed like the other items, in the TM Case, which holds them all
do
  local ItemsData = require("src.core.game3.items_data")
  local tm = Data.items.TM51
  T.check(tm ~= nil and tm.itemId == 1100, "TM51 is in the editor's item list")
  T.eq(tm and tm.pocket, "TM_CASE", "as a TM Case item")
  T.eq(ItemsData.isTm(1100) and ItemsData.tmNumber(1100), 51, "the editor knows it as TM51")
  local tms = dofile("mods/national_dex_gen3/data/tms.lua")
  T.eq(P.moveFromTmItem(1100), require("src.core.game3.battle.moves").numForName(tms[1].move), "teaching " .. tms[1].move)
  T.check((ItemsData.CAPACITY.TM_CASE or 0) >= 58 + #tms, "and its TM Case holds every TM")
end

-- Modern Moves: on in the player's options, so the editor's learnsets have the newer moves
do
  local MOONBLAST = Data.moves.MOONBLAST and Data.moves.MOONBLAST.moveId
  local clefairy = P.speciesFromNational(35)
  local function knows(list)
    for _, r in ipairs(list) do if (r[2] or r) == MOONBLAST then return true end end
    return false
  end
  T.check(knows(P.learnset(clefairy)), "with Modern Moves on, the editor's Clefairy learns Moonblast")
  local mon = MonOps.create(Data, "CLEFAIRY", 50, 3)
  local has = false
  for _, m in ipairs(mon.moves) do if tonumber(m.moveId or m.id or m) == MOONBLAST then has = true end end
  T.check(has, "and a level 50 Clefairy made in the editor knows it")
  run.loader.modOptions.national_dex_gen3 = { modern_moves = false }
  run.loader.events:emit("mod.options_changed", { mod = "national_dex_gen3", key = "modern_moves", value = false })
  T.check(not knows(P.learnset(clefairy)), "turned off, the cart's learnset is back")
end

-- Bigger PC (on by default): 40 boxes in the editor; boxes 15-40 are read from and written back to
-- this mod's save data, so the core save stays a 14-box save (src/big_pc.lua)
do
  local Adapter = require("Game3Adapter")
  local Ops = require("Ops")
  local Storage = require("src.core.game3.storage")
  T.eq(Gen.boxCount({ version = "firered", generation = 3 }), 40, "the editor shows 40 boxes")
  local kept = { species = P.speciesFromName("TURTWIG"), level = 5 }
  local save = {
    version = "firered", generation = 3, party = {}, inventory = {},
    storage = { currentBox = 1, boxes = {}, items = {} },
    modData = { national_dex_gen3 = { pc = { boxes = { [37] = { name = "BOX 37", wallpaper = 5, mons = { [4] = kept } } },
      currentBox = 37 } } },
  }
  local okH, errH = pcall(Adapter.hydrate, Data, save)
  T.check(okH, "a save with boxes past 14 loads in the editor (" .. tostring(errH) .. ")")
  T.check(save.storage.boxes[37] and save.storage.boxes[37].mons[4] == kept, "box 37's Pokemon is in the editor's box 37")
  T.eq(#save.storage.boxes, 40, "with all 40 boxes")
  local S = { data = Data, save = save, selectedBox = 20, selectedParty = 1 }
  save.party[1] = { species = P.speciesFromName("ROWLET"), level = 5 }
  Ops.deposit(S)
  T.check(save.storage.boxes[20].mons[1] ~= nil and #save.party == 0, "depositing into box 20 works")
  local out = Adapter.export(save)
  local maxBox = 0
  for b in pairs(out.storage.boxes) do if b > maxBox then maxBox = b end end
  T.check(maxBox <= 14, "the exported save's own storage holds boxes 1-14 only (got " .. maxBox .. ")")
  local pc = out.modData and out.modData.national_dex_gen3 and out.modData.national_dex_gen3.pc
  T.check(pc and pc.boxes[37] and pc.boxes[20], "boxes 20 and 37 are written to the mod's save data")
  T.check(Storage.TOTAL_BOXES_COUNT == 40, "the engine storage count matches")
end

run.release()
T.finish("national_dex_gen3 stock save editor")
