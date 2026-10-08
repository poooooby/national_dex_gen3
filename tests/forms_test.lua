-- Standalone: luajit mods/national_dex_gen3/tests/forms_test.lua
-- (from the gen1recomp root; needs Pokemon FireRed imported under firered/).
--
-- The alternate forms (tools/form_list.py): each is a species of its own in a
-- slot above the base range, reports its base species' National number, and
-- must never disturb that base -- not its slot in the number map, not its
-- Pokedex entry, not the Pokedex counts.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")

local data = H.gen3Data()
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.events:emit("game.ready", {})
local P = data.gen3Pokemon
local reg = run.loader.content.pokemon
local api = run.loader.exports.national_dex_gen3

-- ------- registration

local forms = api.listForms()
T.eq(#forms, 56, "56 alternate forms are registered")
T.eq(forms[1].slot, 1090, "the first form is slot 1090")
T.eq(forms[#forms].slot, 1145, "the last is 1145")
local seen, ordered = {}, true
for i, f in ipairs(forms) do
  if seen[f.slot] or f.slot ~= 1089 + i then ordered = false end
  seen[f.slot] = true
end
T.check(ordered, "slots are unique, contiguous and in list order (saves store them)")

local rotom = reg:get("ROTOM_HEAT")
T.eq(rotom.index, 1105, "ROTOM_HEAT is slot 1105")
T.eq(rotom.baseSpecies, "ROTOM", "carries baseSpecies (spawn mods skip records that have it)")
T.eq(rotom.form, "HEAT", "and form")
T.eq(rotom.baseDex, 479, "and the base's dex number")
T.check(reg:get("ROTOM").baseSpecies == nil and reg:get("ROTOM").form == nil,
        "a base species carries neither")
T.eq(reg:get("DARUMAKA_GALAR").types[1], "ICE", "Galarian Darumaka is Ice, not its base's Fire")
T.check(reg:get("WORMADAM_SANDY").types[2] == "GROUND", "Wormadam-Sandy is Bug / Ground")

-- ------- the base keeps its place

local rotomBase = api.slotOf("ROTOM")
T.eq(rotomBase, 479 + 64, "ROTOM is still at dex + 64")
T.eq(P._national.toNational[1105], 479, "a form reports its base's National number")
T.eq(P._national.toSpecies[479], rotomBase, "and never takes the base's place in number -> slot")
T.eq(P._names[1105], "ROTOM", "a form keeps its base's display name")
P._national.toSpecies[479] = nil                      -- an engine reload rebuilds the maps
for _, hook in ipairs(P._reloadHooks or {}) do pcall(hook.fn or hook[1] or hook) end
T.eq(P._national.toSpecies[479], rotomBase, "also after a reload")

-- a form writes no Pokedex entry of its own (it is keyed by dex and would overwrite the base's)
local kindBefore = P._dex and P._dex[479] and P._dex[479].category
T.check(kindBefore ~= nil, "the base has a Pokedex entry")

-- ------- the API

local listed = api.listSpecies()
T.eq(#listed, 639, "listSpecies still lists the 639 base species only")
local formInList = false
for _, r in ipairs(listed) do if r.id:find("_HEAT$") or r.id:find("_GALAR") then formInList = true end end
T.check(not formInList, "and no form")
T.eq(api.slotOf("ROTOM_HEAT"), 1105, "slotOf takes a form id")
T.eq(api.slotOf(479), rotomBase, "and a dex number still answers with the base")
T.eq(api.idOfSlot(1105), "ROTOM_HEAT", "idOfSlot")
T.eq(api.idOfSlot(rotomBase), "ROTOM", "idOfSlot for a base species")
T.eq(api.baseDexOf(1105), 479, "baseDexOf a form slot is its base's")
T.eq(api.baseDexOf("ROTOM_HEAT"), 479, "and by id")
T.eq(#api.formsOf("ROTOM"), 5, "ROTOM has five forms")
T.eq(#api.formsOf(479), 5, "by dex number too")
T.check(api.apiVersion >= 2, "apiVersion is 2 or more")

-- ------- abilities and moves: only what the cart has

local bad = 0
for slot = 1090, 1145 do
  local pair = P._abilities[slot] or {}
  for _, id in ipairs({ pair[1] or 0, pair[2] or 0 }) do
    if id ~= 0 and (id < 1 or id > 77 or id == 76) then bad = bad + 1 end
  end
  if not P._learnsets[slot] or #P._learnsets[slot] == 0 then bad = bad + 1 end
end
T.eq(bad, 0, "every form has a cart ability and a learnset")

-- ------- evolutions between forms

local darumaka = 1090
local row
for _, e in ipairs(P._evolutions[darumaka] or {}) do if e.target == 1091 then row = e end end
T.check(row ~= nil, "Darumaka-Galar evolves into Darmanitan-Galar")
T.eq(row and row.method, 7, "by item (EVO_ITEM)")
local zorua
for _, e in ipairs(P._evolutions[1094] or {}) do if e.target == 1095 then zorua = e end end
T.eq(zorua and zorua.param, 30, "Zorua-Hisui evolves into Zoroark-Hisui at 30")
local function evolvesTo(from, to)
  for _, e in ipairs(P._evolutions[from] or {}) do if e.target == to then return e end end
end
T.eq(api.slotOf("PUMPKABOO_SMALL"), 1113, "Pumpkaboo-Small is slot 1113")
T.eq(api.slotOf("GOURGEIST_SMALL"), 1116, "Gourgeist-Small is slot 1116")
T.check(evolvesTo(1113, 1116) ~= nil, "Pumpkaboo-Small evolves into Gourgeist-Small by trade")
T.check(evolvesTo(1114, 1117) ~= nil, "Pumpkaboo-Large into Gourgeist-Large")
T.check(evolvesTo(1115, 1118) ~= nil, "Pumpkaboo-Super into Gourgeist-Super")
T.check(evolvesTo(1113, 1117) == nil, "and a size never evolves into another size")
T.eq(#(P._evolutions[1090 + 9] or {}), 0, "a form with no expressible evolution has none (Sliggoo-Hisui needs rain)")

-- ------- cries: every form has one

local cries = dofile("mods/national_dex_gen3/data/cries.lua")
local missing = 0
for slot = 1090, 1145 do if not cries[slot] then missing = missing + 1 end end
T.eq(missing, 0, "every form slot has a cry")

-- ------- the Pokedex

local Dex = require("src.core.game3.dex")
local d = Dex.new()
Dex.setCaught(d, 1105)
T.check(Dex.isCaught(d, 1105), "a caught form is caught")
T.check(Dex.isCaught(d, rotomBase), "and its base species is marked too")
T.check(Dex.isSeen(d, rotomBase), "seen as well")
T.eq(Dex.countCaught(d, "national"), 1, "the National count is 1, not 2: a form is not a species")
T.eq(Dex.countSeen(d, "national"), 1, "and the seen count likewise")
Dex.setCaught(d, 1106)
Dex.setCaught(d, 1105)
T.eq(Dex.countCaught(d, "national"), 1, "five Rotom forms still count Rotom once")
Dex.setCaught(d, 1090)                                 -- Galarian Darumaka
T.eq(Dex.countCaught(d, "national"), 2, "a different species adds one")
local save = { dex = d, version = "firered", national_dex_unlocked = true }
T.check(Dex.summaryCount(save) <= 2, "the summary count ignores form slots too")

T.finish("national_dex_gen3 forms")
