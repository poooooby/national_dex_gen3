-- Standalone: luajit mods/national_dex_gen3/tests/dex_forms_test.lua (from the gen1recomp root;
-- reads the engine's own Pokedex sources, no cart needed).
--
-- src/dex_forms.lua (which forms a species shows, their names, where their pictures go) and the
-- FORMS patch sets in src/dex_patch.lua (Emerald's CANCEL tab, FireRed/LeafGreen's third page).
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

local here = (arg[0]:gsub("\\", "/"):match("^(.*)/") or ".")
local DexForms = assert(loadfile(here .. "/../src/dex_forms.lua"))()
local DexPatch = assert(loadfile(here .. "/../src/dex_patch.lua"))()
local forms = assert(loadfile(here .. "/../data/species/forms.lua"))()

-- ------- which forms

local byDex = DexForms.byDex(forms)
T.eq(#(byDex[479] or {}), 5, "Rotom has 5 forms")
T.eq(#(byDex[869] or {}), 8, "Alcremie has 8")
T.eq(byDex[392], nil, "Infernape has none")
T.eq(#(byDex[211] or {}), 1, "a cart species with a form (Qwilfish) has it")

-- ------- names

T.eq(DexForms.label({ form = "GALAR_STANDARD" }), "GALARIAN", "Galarian Darmanitan")
T.eq(DexForms.label({ form = "HISUI" }), "HISUIAN", "Hisuian")
T.eq(DexForms.label({ form = "WELLSPRING_MASK" }), "WELLSPRING", "Ogerpon's masks")
T.eq(DexForms.label({ form = "RUBY_CREAM" }), "RUBY CREAM", "Alcremie's creams")
T.eq(DexForms.label({ form = "10" }), "10%", "Zygarde 10%")

-- ------- layout: smaller pictures for more forms, all inside the page

local area = { x = 4, y = 32, w = 232, h = 110 }
local sizes = {}
for _, n in ipairs({ 1, 2, 3, 4, 5, 8, 12, 20 }) do
  local L = DexForms.layout(n, area)
  sizes[n] = L.size
  T.eq(#L.cells, n, n .. " forms: a cell each")
  for i, c in ipairs(L.cells) do
    T.check(c.x >= area.x and c.x + L.size <= area.x + area.w, n .. " forms: picture " .. i .. " fits across")
    T.check(c.y >= area.y and c.y + L.size + DexForms.NAME_H <= area.y + area.h, n .. " forms: picture " .. i .. " and its name fit down")
  end
end
T.check(sizes[1] == 64 and sizes[2] == 64, "one or two forms: full size")
T.check(sizes[4] < sizes[2] and sizes[8] < sizes[4], "pictures shrink as forms are added")

-- ------- Emerald's FORMS tab: the cart's tab body, lettered inside it

local tab = DexForms.formsTabIndices()
T.eq(#tab, 16, "the tab is 16 rows, like the cart's")
local wide, outside, strokes = true, 0, 0
for y = 1, 16 do
  if #tab[y] ~= 56 then wide = false end
  for x = 1, 56 do
    local v = tab[y][x]
    if v == 0xF then
      strokes = strokes + 1
      if x < 7 or x > 50 or y < 5 or y > 14 then outside = outside + 1 end
    end
  end
end
T.check(wide, "every row is the tab's 56 px")
T.check(strokes > 60, "FORMS is lettered (" .. strokes .. " stroke pixels)")
T.eq(outside, 0, "no letter touches the tab's border")
T.eq(tab[4][7], 0xC, "the body is the AREA/CRY/SIZE fill, not CANCEL's")

-- ------- the patches apply to the engine's own screens

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
local rse = slurp("src/ui/game3/rse/pokedex.lua")
if T.check(rse ~= nil, "the RSE Pokedex source is readable") then
  local all = DexPatch.patchFormsSource(DexPatch.patchPeekSource(DexPatch.patchSource(rse)))
  T.check(all ~= nil, "Emerald's FORMS patches apply after the list and peek ones")
  T.check(all and loadstring(all) ~= nil, "and the result compiles")
  T.check(DexPatch.patchFormsSource(rse) ~= nil, "they also apply to the stock screen")
end
local frlg = slurp("src/ui/game3/pokedex.lua")
if T.check(frlg ~= nil, "the FRLG Pokedex source is readable") then
  local all = DexPatch.patchFrlgFormsSource(DexPatch.patchFrlgIslandsSource(
    DexPatch.patchPeekFrlgSource(DexPatch.patchFrlgSource(frlg))))
  T.check(all ~= nil, "FireRed's FORMS patches apply after the others")
  T.check(all and loadstring(all) ~= nil, "and the result compiles")
end
T.eq(DexPatch.patchFormsSource("local x = 1"), nil, "an unexpected source is not patched")
T.eq(DexPatch.patchFrlgFormsSource("local x = 1"), nil, "nor on FireRed")

T.finish("national_dex_gen3 dex forms")
