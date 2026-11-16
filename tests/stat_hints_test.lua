-- Standalone: luajit mods/national_dex_gen3/tests/stat_hints_test.lua [game] (from the gen1recomp
-- root; needs that cart imported, FireRed by default).
--
-- Stat Hints (src/stat_hints.lua): a chip per raised or lowered stat by each battle HP box, its text
-- the stage's multiplier, redrawn from the battler's stages every time the box is drawn (so after
-- every move: stacking, a drop after a rise); under the box in singles, in a column beside it in
-- doubles, never on another box; none with the option off.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"

local data = H.gen3Data(GAME)
require("src.core.GameVersion").set(GAME)

-- the engine's Healthbox.draw needs a window: a stand-in that places the boxes as it does
local Healthbox = require("src.core.game3.battle.healthbox")
local Chrome = require("src.ui.game3.battle_chrome")
Chrome.drawDoublesBox = function() end
Chrome.drawEnemyBox = function() end
Chrome.drawPlayerBox = function() end
Healthbox.draw = function(side, battler, opts)
  if not battler then return end
  local ox = opts and opts.ox or 0
  if type(side) == "number" then
    local c = Healthbox.CENTERS[true][side]
    return Chrome.drawDoublesBox(side % 2 == 0, c.x - 32 + ox, c.y - 16)
  end
  local c = side == "player" and Healthbox.PLAYER_CENTER or Healthbox.ENEMY_CENTER
  if side == "player" then Chrome.drawPlayerBox(c.x - 32 + ox, c.y - 16) else Chrome.drawEnemyBox(c.x - 32 + ox, c.y - 16) end
end

local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.events:emit("game.ready", {})

local SH = dofile("mods/national_dex_gen3/src/stat_hints.lua")
-- ------- the text
T.eq(SH.text("attack", "ATK", 2), "ATK 2x", "+2 Attack: ATK 2x")
T.eq(SH.text("attack", "ATK", 1), "ATK 1.5x", "+1: 1.5x")
T.eq(SH.text("attack", "ATK", -1), "ATK 0.67x", "-1: 0.67x (hundredths)")
T.eq(SH.text("spAtk", "SPA", -2), "SPA 0.5x", "-2 Sp. Atk: SPA 0.5x (no trailing zero)")
T.eq(SH.text("spDef", "SPD", -5), "SPD 0.29x", "-5: 2/7 is 0.29x")
T.eq(SH.text("speed", "SPE", 6), "SPE 4x", "+6 Speed: SPE 4x")
T.eq(SH.text("accuracy", "ACC", -1), "ACC 0.75x", "accuracy's own scale: -1 is 0.75x")
T.eq(SH.text("accuracy", "ACC", 1), "ACC 1.33x", "and +1 is 1.33x")
T.eq(SH.text("evasion", "EVA", -5), "EVA 0.38x", "3/8 rounds up: 0.38x")
T.eq(SH.text("evasion", "EVA", 3), "EVA 2x", "evasion +3 is 2x")
T.eq(SH.text("defense", "DEF", 0), nil, "no chip at 0")
local missing = {}
for _, s in ipairs(SH.STATS) do
  for n = -6, 6 do
    local t = SH.text(s.key, s.label, n)
    for i = 1, #(t or "") do
      if not SH.GLYPH[t:sub(i, i)] then missing[#missing + 1] = t:sub(i, i) end
    end
  end
end
T.eq(#missing, 0, "every character has a glyph (" .. table.concat(missing, "") .. ")")

-- ------- drawn by the boxes
local state = Healthbox.__ndxStatHints
T.check(type(state) == "table" and type(state.drawChip) == "function", "the hints are installed on the HP boxes")
local drawn = {}
local drawChipOwn = state.drawChip
state.drawChip = function(text, up, x, y, w, h)
  drawn[#drawn + 1] = { text = text, up = up, x = x, y = y, w = w or SH.width(text), h = h or SH.H }
end
local function draw(side, battler, opts)
  drawn = {}
  Healthbox.draw(side, battler, opts)
  return drawn
end
local function texts(list)
  local out = {}
  for _, c in ipairs(list) do out[#out + 1] = c.text end
  return table.concat(out, ", ")
end

-- every move redraws from the stages as they now are: Swords Dance twice, then Growl
local mine = { stages = { attack = 0 } }
T.eq(#draw("player", mine), 0, "no change: no chips")
mine.stages.attack = 2
T.eq(texts(draw("player", mine)), "ATK 2x", "after Swords Dance: ATK 2x")
mine.stages.attack = 4
T.eq(texts(draw("player", mine)), "ATK 3x", "after a second: ATK 3x")
mine.stages.attack = 3
T.eq(texts(draw("player", mine)), "ATK 2.5x", "after a Growl: ATK 2.5x")
mine.stages.spAtk = -2
local two = draw("player", mine)
T.eq(texts(two), "ATK 2.5x, SPA 0.5x", "a drop beside it: SPA 0.5x")
T.check(two[1].up == true and two[2].up == false, "a rise and a drop told apart")
T.check(SH.color(true) ~= SH.color(false) and SH.UP[2] > SH.UP[1] and SH.DOWN[1] > SH.DOWN[2],
  "a rise is green, a drop red")

-- ------- singles: a foe's under its box, yours above the text box
local ec = Healthbox.ENEMY_CENTER
local ex, ey = ec.x - 32, ec.y - 16
local foe = draw("enemy", { stages = { attack = 1, defense = -1, speed = 2, spAtk = 1, spDef = -1, accuracy = -1, evasion = 1 } })
T.eq(#foe, 7, "all seven stats can show")
local under, inWidth = true, true
for _, c in ipairs(foe) do
  if c.y < ey + SH.FRAME.enemy.bottom + 1 then under = false end
  if c.x < ex or c.x + c.w > ex + SH.FRAME.enemy.rows then inWidth = false end
end
T.check(under, "a foe's chips sit under its box")
T.check(inWidth, "within its rows' width, wrapping downward")
local pc = Healthbox.PLAYER_CENTER
local px, py = pc.x - 32, pc.y - 16
local yours = draw("player", { stages = { attack = 2, speed = -1, defense = 1, spAtk = 1, spDef = -1,
  accuracy = 1, evasion = -2 } })
T.eq(#yours, 7, "all seven by your box too")
local clear, beside = true, true
for _, c in ipairs(yours) do
  if c.y + SH.H > SH.TEXT_TOP or c.y < py + 2 or c.y + SH.H > py + SH.FRAME.player.bottom then clear = false end
  if c.x + c.w > px + SH.FRAME.player.left - SH.BADGES then beside = false end
end
T.check(clear, "yours stay in your box's rows, above the text box (its EXP bar not covered)")
T.check(beside, "yours sit left of your box, past its type badges")

-- ------- doubles: columns beside each box, in its own band of rows, never on another box
local boxes = {}
for id = 0, 3 do
  local c = Healthbox.CENTERS[true][id]
  local x, y = c.x - 32, c.y - 16
  local D = SH.FRAME.doubles
  boxes[id] = { x0 = x + (id % 2 == 0 and D.playerLeft or 0), x1 = x + (id % 2 == 0 and 103 or D.enemyRight),
    y0 = y + D.top, y1 = y + D.bottom, x = x, y = y }
  local top, height = SH.doublesBand(id % 2 == 0 and "player" or "enemy", y)
  boxes[id].bandTop, boxes[id].band = top, top + height
end
local function overlaps(c, b)
  return c.x < b.x1 and c.x + c.w > b.x0 and c.y < b.y1 and c.y + SH.H > b.y0
end
local full = { stages = { attack = 2, defense = -1, speed = 1, spAtk = -2, spDef = 1 } }
for id = 0, 3 do
  local list = draw(id, full)
  local own, others, rows = boxes[id], 0, true
  for _, c in ipairs(list) do
    for j = 0, 3 do if overlaps(c, boxes[j]) then others = others + 1 end end
    if c.y < own.bandTop or c.y + SH.H > own.band then rows = false end
  end
  T.eq(#list, 5, ("doubles box %d: five chips"):format(id))
  T.eq(others, 0, ("doubles box %d: none on any HP box, its partner's included"):format(id))
  T.check(rows, ("doubles box %d: all in its own band of rows"):format(id))
  local outward = true
  for _, c in ipairs(list) do
    if id % 2 == 1 and c.x <= own.x1 then outward = false end
    if id % 2 == 0 and c.x + c.w >= own.x0 then outward = false end
  end
  T.check(outward, ("doubles box %d: on its outer side, past its type badges"):format(id))
end

-- no chip crosses Battle Fit's split row, anywhere
local function crossesSplit(list)
  for _, c in ipairs(list) do if c.y < SH.SPLIT and c.y + SH.H > SH.SPLIT then return true end end
  return false
end
-- six at their widest on all four: on the screen, and no chip on another's chip or any box (a
-- seventh on one of yours is held at the screen's edge)
local widest = { stages = { attack = -6, defense = -6, spAtk = -6, spDef = -6, speed = -6, accuracy = -6 } }
local all, onScreen, onBox, split = {}, true, 0, false
for id = 0, 3 do
  local list = draw(id, widest)
  split = split or crossesSplit(list)
  for _, c in ipairs(list) do
    c.id = id
    all[#all + 1] = c
    if c.x < 0 or c.x + c.w > SH.SCREEN_W or c.y + SH.H > SH.TEXT_TOP then onScreen = false end
    for j = 0, 3 do if overlaps(c, boxes[j]) then onBox = onBox + 1 end end
  end
end
local crossed = 0
for i = 1, #all do
  for j = i + 1, #all do
    local a, b = all[i], all[j]
    if a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + SH.H and b.y < a.y + SH.H then crossed = crossed + 1 end
  end
end
T.eq(#all, 24, "doubles: six chips on each of four")
T.check(onScreen, "doubles: six at their widest stay on the screen")
T.eq(onBox + crossed, 0, "doubles: and none on a box or on another chip")
T.check(not split, "doubles: no chip crosses the split row")
local seven = { stages = { attack = -6, defense = -6, spAtk = -6, spDef = -6, speed = -6, accuracy = -6, evasion = -6 } }
local held = true
for id = 0, 3 do
  for _, c in ipairs(draw(id, seven)) do if c.x < 0 or c.x + c.w > SH.SCREEN_W then held = false end end
end
T.check(held, "doubles: seven changes stay on the screen")
-- singles: both sides' seven at their widest, none on the other's, a box, or the split
local s1, s2 = draw("enemy", seven), draw("player", seven)
local bad = crossesSplit(s1) or crossesSplit(s2)
local sb = { { x0 = ex, x1 = ex + SH.FRAME.enemy.right, y0 = ey + 2, y1 = ey + SH.FRAME.enemy.bottom },
  { x0 = px + SH.FRAME.player.left, x1 = px + SH.FRAME.player.right, y0 = py + 2, y1 = py + SH.FRAME.player.bottom } }
for _, a in ipairs(s1) do
  if a.x + a.w > SH.SCREEN_W then bad = true end
  for _, b in ipairs(s2) do
    if a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + SH.H and b.y < a.y + SH.H then bad = true end
  end
end
for _, list in ipairs({ s1, s2 }) do
  for _, c in ipairs(list) do
    if c.x < 0 then bad = true end
    for _, b in ipairs(sb) do if overlaps(c, b) then bad = true end end
  end
end
T.check(not bad, "singles: seven a side at their widest: on the screen, apart, off the boxes and the split")

-- ------- window resolution, with WoobleView (its uiMap export)
T.check(state.view() == nil, "no WoobleView: the game's pixels")
local map = { x = 100, y = 50, sx = 4, sy = 4, box = { 100, 50, 960, 640 }, banded = false, split = 66, topY = 0 }
local wooble = { features = { uiMap = true }, isActive = function() return true end, uiMap = function() return map end }
local viewOwn = state.view
state.view = function() return wooble end
local hi = draw(3, seven)
T.check(#hi == 7 and hi[1].h == SH.HI.H and hi[1].w < SH.width(hi[1].text),
  "with it: smaller chips, measured in the font")
local hiAll, hiOk = {}, true
for id = 0, 3 do
  local list = draw(id, seven)
  for _, c in ipairs(list) do
    hiAll[#hiAll + 1] = c
    if c.x < 0 or c.x + c.w > SH.SCREEN_W or c.y < boxes[id].bandTop or c.y + c.h > boxes[id].band then hiOk = false end
    if c.y < SH.SPLIT and c.y + c.h > SH.SPLIT then hiOk = false end
    for j = 0, 3 do if overlaps(c, boxes[j]) then hiOk = false end end
  end
end
for i = 1, #hiAll do
  for j = i + 1, #hiAll do
    local a, b = hiAll[i], hiAll[j]
    if a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h then hiOk = false end
  end
end
T.check(#hiAll == 28 and hiOk, "doubles at window resolution: seven a box, in its band, apart, on the screen")
-- queued while the boxes draw, drawn from render.hud where WoobleView put the UI, then cleared
state.drawChip = drawChipOwn
local Gsaved = love.graphics
local prints = {}
local stubFont = { getHeight = function() return 23 end, getBaseline = function() return 18 end,
  getWidth = function(_, t) return #t * 12 end }
love.graphics = setmetatable({
  print = function(t, x, y) prints[#prints + 1] = { t = t, x = x, y = y } end,
  newFont = function() return stubFont end,
}, { __index = function() return function() end end })
Healthbox.draw("enemy", { stages = { attack = 2 } })
local n = state.queued()
state.hud()
local n2 = state.queued()
love.graphics = Gsaved
local p = prints[1]
T.check(n == 1 and n2 == 0 and #prints == 1 and p.t == "ATK 2x", "one chip queued, drawn from render.hud, the queue cleared")
T.check(p and p.x >= map.x + ex * map.sx and p.x < map.x + (ex + 4) * map.sx
  and p.y > map.y + (ey + SH.FRAME.enemy.bottom) * map.sy, "at WoobleView's placement of the UI, scaled")
state.view = viewOwn
state.drawChip = function(text, up, x, y, w, h)
  drawn[#drawn + 1] = { text = text, up = up, x = x, y = y, w = w or SH.width(text), h = h or SH.H }
end

-- ------- the option, and no garbage made by a draw
local saved = state.enabled
state.enabled = function() return false end
T.eq(#draw("enemy", { stages = { attack = 2 } }), 0, "Stat Hints off: none")
state.enabled = saved
state.drawChip = function() end
local foeB = { stages = { attack = 2, spAtk = -1, speed = 1 } }
-- the same two boxes with the hints on and off (the box's other wraps make their own)
local function per()
  collectgarbage("collect")
  collectgarbage("stop")
  local kb0 = collectgarbage("count")
  for _ = 1, 2000 do Healthbox.draw("enemy", foeB); Healthbox.draw(3, foeB) end
  local b = (collectgarbage("count") - kb0) * 1024 / 2000
  collectgarbage("restart")
  return b
end
-- (the headless LOVE stand-in's setColor makes a table a call; LOVE's own makes none)
local setColor = love.graphics.setColor
love.graphics.setColor = function() end
local withHints = per()
state.enabled = function() return false end
local without = per()
state.enabled = saved
love.graphics.setColor = setColor
T.check(withHints - without < 24, ("the hints make no garbage of their own (%.1f bytes with, %.1f without)"):format(withHints, without))

local schema = run.loader.optionSchemas.national_dex_gen3
local opt
for _, o in ipairs(schema or {}) do if o.key == "stat_hints" then opt = o end end
T.check(opt and opt.default == true and opt.label == "Stat Hints", "a Stat Hints option, on by default")

run.release()
T.finish("national_dex_gen3 stat hints (" .. GAME .. ")")
