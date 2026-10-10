-- Standalone: luajit mods/national_dex_gen3/tests/dex_art_test.lua (from the gen1recomp root).
--
-- src/dex_art.lua + data/dex_atlas_index.lua: every National Dex species and every form this mod
-- registers has Pokedex art; a "dex" picture comes from the atlas and animates; a battle picture
-- and anything the atlas lacks fall through. Drawing is stubbed (a canvas records what was drawn
-- into it), so this runs without a window.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

local here = (arg[0]:gsub("\\", "/"):match("^(.*)/") or ".")
local DexArt = assert(loadfile(here .. "/../src/dex_art.lua"))()
local index = assert(loadfile(here .. "/../data/dex_atlas_index.lua"))()
local forms = assert(loadfile(here .. "/../data/species/forms.lua"))()

-- ------- the atlas covers everything

local missing = {}
for n = 1, 1025 do if not index.entries[n] then missing[#missing + 1] = n end end
T.eq(#missing, 0, "every National Dex number #1-1025 has art (" .. table.concat(missing, ",", 1, math.min(#missing, 10)) .. ")")
local noForm = {}
for _, f in ipairs(forms) do if not index.entries[f.id] then noForm[#noForm + 1] = f.id end end
T.eq(#noForm, 0, "every registered form has art (" .. table.concat(noForm, ",", 1, math.min(#noForm, 10)) .. ")")
local two = 0
for _, e in pairs(index.entries) do
  T.check(e.frames == 1 or e.frames == 2, "an entry has one or two frames")
  if e.frames == 2 then two = two + 1 end
end
T.check(two > 800, "most entries animate (" .. two .. " with two frames)")
for s = 0, index.sheets - 1 do
  local f = io.open(here .. "/../assets/dex/dex_" .. s .. ".png", "rb")
  T.check(f ~= nil, "sheet " .. s .. " is shipped")
  if f then f:close() end
end

-- ------- frames

T.eq(DexArt.frameAt(0, 2), 0, "frame 0 first")
T.eq(DexArt.frameAt(DexArt.FRAME_SECONDS + 0.01, 2), 1, "then frame 1")
T.eq(DexArt.frameAt(2 * DexArt.FRAME_SECONDS + 0.01, 2), 0, "and back")
T.eq(DexArt.frameAt(5, 1), 0, "a one-frame entry stays still")

-- ------- pictures, with a fake clock and fake canvases

local t = 0
local drawn = {}
local function art()
  return DexArt.new({
    index = index,
    clock = function() return t end,
    sheet = function(n) return { sheet = n } end,
    newCanvas = function() return { draws = 0 } end,
    newQuad = function(x, y) return { x = x, y = y } end,
    render = function(canvas, img, q)
      canvas.draws = canvas.draws + 1
      canvas.last = { sheet = img.sheet, x = q.x, y = q.y }
      drawn[#drawn + 1] = canvas
    end,
  })
end
local a = art()
local infernape = a.entry(392)
T.check(infernape ~= nil and infernape.w == 64 and infernape.h == 64, "Infernape's dex picture is a 64x64 entry")
local e = index.entries[392]
local per = index.perRow
T.eq(infernape.image.last.x, (e.cell % per) * 64, "drawn from its own cell")
t = DexArt.FRAME_SECONDS + 0.01
a.tick()
T.eq(infernape.image.last.x, ((e.cell + 1) % per) * 64, "tick moves it to its second frame, in place")
T.check(a.entry(392).image == infernape.image, "the same canvas is reused (Emerald keeps the image it was given)")
T.check(a.entry("ROTOM_WASH") ~= nil, "a form answers by its id")
T.eq(a.entry(99999), nil, "an unknown key has no picture")

-- ------- slot -> key

local key = DexArt.keyResolver({ [1105] = "ROTOM_HEAT" }, function(slot) return ({ [6] = 6, [327] = 327 })[slot] end)
T.eq(key(1105), "ROTOM_HEAT", "a form slot answers its form id")
T.eq(key(6), 6, "a species answers its National Dex number")
T.eq(key(327), nil, "Spinda is left to the game (its spots depend on the Pokemon)")
T.eq(key(9999), nil, "an unknown slot has no key")

-- ------- the frontPic wrap: "dex" only, falling through

local Pokemon = {
  frontPic = function(species, form, shiny, personality, kind) return { original = true, kind = kind } end,
}
local modules = { ["src.core.game3.pokemon"] = Pokemon }
local fakeRequire = function(name) return modules[name] or error("no " .. name) end
DexArt.install({ art = art(), keyOf = function(sp) return sp end }, fakeRequire)
T.check(Pokemon.frontPic(392, 0, false, 0, "dex").original == nil, "a dex picture comes from the atlas")
T.eq(Pokemon.frontPic(392, 0, false, 0, "battle").original, true, "a battle picture is the game's")
T.eq(Pokemon.frontPic(99999, 0, false, 0, "dex").original, true, "no art: falls through")
local wrapped = Pokemon.frontPic
DexArt.install({ art = art(), keyOf = function(sp) return sp end }, fakeRequire)
T.eq(Pokemon.frontPic, wrapped, "wrapped once")

T.finish("national_dex_gen3 dex art")
