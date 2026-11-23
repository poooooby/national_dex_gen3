-- Standalone: luajit mods/national_dex_gen3/tests/omni_test.lua [game] (from the gen1recomp root;
-- needs that cart imported, FireRed by default).
--
-- OmniUI (src/omni.lua): through a stand-in of OmniUI's public API (registerBattlerBadge,
-- registerSummaryTab, Layout), each battler card gets the battler's types as pills and its stat
-- changes as chips, under a foe's card and above yours, the second foe's from its own battler; the
-- options turn each part off; the cause-then-effect hold is read while a move plays; a second install
-- registers nothing twice; a Gen 1 game draws nothing; the DYNAMAX Summary tab shows the level and the
-- G-Max Factor, and comes off for Gen 1 / 2.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"

local data = H.gen3Data(GAME)
local GV = require("src.core.GameVersion")
GV.set(GAME)

local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.events:emit("game.ready", {})

local Healthbox = require("src.core.game3.battle.healthbox")
T.check(Healthbox.__ndxBadges and Healthbox.__ndxStatHints, "the badges and the hints are installed")

local Omni = dofile("mods/national_dex_gen3/src/omni.lua")
local SH = dofile("mods/national_dex_gen3/src/stat_hints.lua")
local TB = dofile("mods/national_dex_gen3/src/type_badges.lua")
local Dx = dofile("mods/national_dex_gen3/src/dynamax.lua")(nil, { data = dofile("mods/national_dex_gen3/data/dynamax.lua"),
  require = require })

-- ------- a stand-in OmniUI
local badges, tabs = {}, {}
local drawn, texts = {}, {}
local api = {
  summaryTabs = tabs,
  registerBattlerBadge = function(def) badges[#badges + 1] = def end,
  registerSummaryTab = function(def) tabs[def.id] = def end,
  Layout = {
    textWidth = function(t) return #t * 7 end,
    getContext = function() return { isUltraCompact = false } end,
    drawBadge = function(x, y, text, o) drawn[#drawn + 1] = { x = x, y = y, text = text, o = o } end,
    drawText = function(text, x, y) texts[#texts + 1] = text end,
  },
}
love.graphics.getDimensions = function() return 1024, 768 end
local THEME = { colors = { hpGreen = { 0, 1, 0, 1 }, hpRed = { 1, 0, 0, 1 }, surfaceHigh = { 0.2, 0.2, 0.2, 1 } } }

T.check(Omni.install(api, { require = require, colors = TB.COLORS, chips = SH, dynamax = Dx }), "installs")
T.eq(#badges, 2, "a badge for each side")
T.check(tabs[Omni.TAB_ID] and tabs[Omni.TAB_ID].label == "DYNAMAX", "a DYNAMAX Summary tab")

local Types = require("src.core.game3.battle.types")
local W, F = Types.ID.WATER, Types.ID.FLYING
local foe = { mon = { species = 130, level = 30 }, type1 = W, type2 = F, stages = { attack = 2 } }
local me = { mon = { species = 6, level = 36 }, type1 = Types.ID.FIRE, type2 = F, stages = { speed = -1, accuracy = 1 } }
local Battle = require("src.core.game3.battle")
local stOwn = Battle._st
Battle._st = { enemy = foe, player = me, battlers = { [0] = me, [1] = foe } }

local function render(side, slot, x, y)
  drawn = {}
  for _, b in ipairs(badges) do if b.side == side then b.render(slot, x, y, THEME) end end
  return drawn
end
local function list(d)
  local out = {}
  for _, c in ipairs(d) do out[#out + 1] = c.text end
  return table.concat(out, ", ")
end

-- a foe's card at (12, 10): 0.44 x 1024 is wider than 260, so the card is 260 x 62
local f = render("enemy", { active = true, species = 130, level = 30 }, 12, 10)
T.eq(list(f), "WATER, FLYING, ATK 2x", "a foe's card: its types, then its chip")
T.check(f[1] and f[1].x == 12 and f[1].y == 10 + 62 + Omni.MARGIN, "under the foe's card, from its left")
T.check(f[2] and f[2].x == f[1].x + f[1].o.width + Omni.GAP and f[2].y == f[1].y, "side by side")
T.check(f[3] and f[3].o.textColor == THEME.colors.hpGreen and f[3].o.borderColor == THEME.colors.hpGreen,
  "a rise in OmniUI's green")
local p = render("player", { active = true, species = 6, level = 36 }, 700, 500)
T.eq(list(p), "FIRE, FLYING, SPE 0.67x, ACC 1.33x", "your card: types, then chips")
T.check(p[1] and p[1].y == 500 - Omni.MARGIN - Omni.H, "above your card")
T.check(p[3] and p[3].o.textColor == THEME.colors.hpRed, "a drop in OmniUI's red")

-- wrapping at the card's width, rows away from the card
me.stages = { attack = 6, defense = 6, spAtk = 6, spDef = 6, speed = 6, accuracy = 6, evasion = 6 }
local wide = render("player", { active = true, species = 6, level = 36 }, 700, 500)
local maxX, rows = 0, {}
for _, c in ipairs(wide) do
  maxX = math.max(maxX, c.x + c.o.width)
  rows[c.y] = true
end
local nRows = 0
for y in pairs(rows) do nRows = nRows + 1; T.check(y < 500, "every row above your card") end
T.check(#wide == 9 and nRows >= 2 and maxX <= 700 + 260, "nine items wrap at the card's width")
me.stages = { speed = -1 }

-- doubles: the second foe's card is the second foe's battler
local foe2 = { mon = { species = 25, level = 20 }, type1 = Types.ID.ELECTRIC, stages = { defense = -2 } }
Battle._st = { enemy = foe, player = me, battlers = { [0] = me, [1] = foe, [3] = foe2 } }
T.eq(list(render("enemy", { active = true, species = 25, level = 20 }, 284, 10)), "ELECTRIC, DEF 0.5x",
  "the second foe's card: its own battler")
T.eq(list(render("enemy", { active = true, species = 130, level = 30 }, 12, 10)), "WATER, FLYING, ATK 2x",
  "the first foe's card: still the first")

-- the options
local bOn, hOn = Healthbox.__ndxBadges.enabled, Healthbox.__ndxStatHints.enabled
Healthbox.__ndxBadges.enabled = function() return false end
T.eq(list(render("enemy", { active = true, species = 130, level = 30 }, 12, 10)), "ATK 2x", "Type Badges off: chips only")
Healthbox.__ndxBadges.enabled = bOn
Healthbox.__ndxStatHints.enabled = function() return false end
T.eq(list(render("enemy", { active = true, species = 130, level = 30 }, 12, 10)), "WATER, FLYING", "Stat Hints off: types only")
Healthbox.__ndxStatHints.enabled = hOn

-- cause, then effect: while a move plays, the chips are the hold's
local hs = Healthbox.__ndxStatHints
local playingOwn = hs.playing
render("enemy", { active = true, species = 130, level = 30 }, 12, 10)  -- (caught up: ATK 2x held)
foe.stages.attack = 4
hs.playing = function() return true end
T.eq(list(render("enemy", { active = true, species = 130, level = 30 }, 12, 10)), "WATER, FLYING, ATK 2x",
  "while the move plays: the held ATK 2x")
hs.playing = playingOwn
T.eq(list(render("enemy", { active = true, species = 130, level = 30 }, 12, 10)), "WATER, FLYING, ATK 3x",
  "once it has played: ATK 3x")

-- once per OmniUI
T.check(Omni.install(api, { require = require, colors = TB.COLORS, chips = SH, dynamax = Dx }) and #badges == 2,
  "a second install registers no second badge")

-- another generation: nothing
GV.set("red")
T.eq(#render("enemy", { active = true, species = 130, level = 30 }, 12, 10), 0, "Gen 1: nothing drawn")
GV.set(GAME)

-- ------- the DYNAMAX tab
local zard = { species = 6, level = 50, extra = { national_dex_gen3 = { dynamaxLevel = 7, gmaxFactor = true } } }
texts = {}
tabs[Omni.TAB_ID].draw({}, { raw = zard }, 0, 52, 600, 300, THEME.colors)
local all = table.concat(texts, " | ")
T.check(all:find("DYNAMAX LEVEL  7 / 10", 1, true) and all:find("G-Max Wildfire", 1, true),
  "the tab: Dynamax Level 7 and G-Max Wildfire (" .. all .. ")")
texts = {}
tabs[Omni.TAB_ID].draw({}, { raw = { species = 6, level = 5 } }, 0, 52, 600, 300, THEME.colors)
all = table.concat(texts, " | ")
T.check(all:find("DYNAMAX LEVEL  0 / 10", 1, true) and all:find("Max Soup", 1, true), "no marks: level 0, no factor")
Omni.uninstallTab(api)
T.check(tabs[Omni.TAB_ID] == nil, "the tab comes off for Gen 1 / 2")

Battle._st = stOwn
run.release()
T.finish("national_dex_gen3 OmniUI (" .. GAME .. ")")
