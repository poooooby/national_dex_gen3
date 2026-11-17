-- Standalone: luajit mods/national_dex_gen3/tests/box_shape_test.lua [game] (from the gen1recomp
-- root; needs that cart imported, FireRed by default).
--
-- Another mod's battle box pictures (src/box_shape.lua): Facets' battle box sets swap their own
-- healthbox pictures onto BattleChrome while a box draws, each with its own frame (DP's foe box runs
-- 7 px further right than the game's; HGSS's sides slant). The type badges (src/type_badges.lua) and
-- the stat chips (src/stat_hints.lua) measure the picture being drawn and keep clear of its frame, row
-- by row; a picture framed as the game's (the game's own, a recolour) keeps the game's placement. On
-- Gen 1/2 a mod's Gen 3 box is seen through Shape.watch (love.graphics.draw watched for 128-wide box
-- pictures). The shapes below are Facets' sets' own rows (measured from its pictures).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"
local Shape = dofile("mods/national_dex_gen3/src/box_shape.lua")

-- a picture (ImageData-like) drawn from x = left[y] to right[y] on each row listed
local function pic(w, h, rows)
  return {
    getDimensions = function() return w, h end,
    getPixel = function(_, x, y)
      local r = rows[y]
      return 1, 1, 1, (r and x >= r[1] and x <= r[2]) and 1 or 0
    end,
  }
end
local function rowsOf(first, edges, fixed, side)
  local out = {}
  for i, e in ipairs(edges) do
    out[first + i - 1] = side == "enemy" and { fixed, e } or { e, fixed }
  end
  return out
end
-- DP's foe box (Facets' assets/battleui/dp): its right edge per row from row 2, an arrow out to 105
local DP_ENEMY = pic(128, 32, rowsOf(2, { 95, 97, 98, 98, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 101, 103,
  105, 105, 103, 101, 99, 99, 99, 99, 98, 98, 97, 95 }, 0, "enemy"))
-- HGSS's box of yours: its left edge per row from row 0, slanting out to 0 at the foot
local HGSS_PLAYER = pic(128, 64, rowsOf(0, { 14, 14, 13, 13, 13, 13, 13, 12, 12, 12, 12, 11, 11, 11, 11, 10, 10, 10,
  9, 9, 9, 8, 8, 8, 7, 7, 7, 6, 6, 6, 5, 3, 1, 0, 0, 0 }, 108, "player"))
-- a recolour of the game's foe box: its frame to 92 on the top rows, the shadow tail on to 100 under them
local GAME_LIKE = (function()
  local rows = {}
  for y = 2, 29 do rows[y] = { 1, y < 8 and 92 or 100 } end
  return pic(128, 32, rows)
end)()
-- DP's doubles foe box: the same arrow
local DP_DOUBLES = pic(128, 32, rowsOf(2, { 95, 97, 98, 98, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 101, 103,
  105, 105, 103, 101, 99, 99, 99, 98, 98, 97, 95 }, 0, "enemy"))

-- ------- the shapes
local s = Shape.of(DP_ENEMY)
T.check(s and s.top == 2 and s.bottom == 30 and s.minX == 0 and s.maxX == 105, "a picture's rows are measured")
T.eq(Shape.of(DP_ENEMY), s, "once: the same picture is not measured again")
T.eq(Shape.rightOver(s, 2, 13), 99, "the last drawn column over a band of rows")
local EDGES = { enemy = { right = 92, top = 2 }, player = { left = 9, top = 2 } }
T.check(not Shape.likeGame(s, EDGES.enemy, "enemy"), "DP's frame is not the game's")
T.check(Shape.likeGame(Shape.of(GAME_LIKE), EDGES.enemy, "enemy"), "a recolour of the game's box is")
local x, y = Shape.badgeSpot(s, "enemy", 1, 12, 8, 8, 2)
T.check(x == 102 and y == 2, ("one badge clears DP's frame by 2 px (%s,%s)"):format(x, y))
x = Shape.badgeSpot(s, "enemy", 2, 12, 8, 8, 2)
T.check(x == 102 and x + 8 >= 105 + 3, "a second, down and out, clears its arrow too")
local hp = Shape.of(HGSS_PLAYER)
x, y = Shape.badgeSpot(hp, "player", 2, 12, 8, 8, 2)
T.check(x == -13 and y == 0, ("yours clear HGSS's slanting side, each badge on its own rows (%s,%s)"):format(x, y))
T.eq(Shape.of(pic(128, 32, {})), nil, "an empty picture gives nothing to go by")

-- ------- Gen 1/2: love.graphics.draw watched for a Gen 3 box
do
  local real = love.graphics.draw
  local calls = 0
  love.graphics.draw = function() calls = calls + 1 end
  local quad = setmetatable({}, { __index = function() return nil end })
  Shape.watch(function()
    love.graphics.draw(DP_ENEMY, 2, 2)
    love.graphics.draw(HGSS_PLAYER, 40, 31)
    love.graphics.draw(DP_ENEMY, quad, 5, 5)
    Shape.watch(function() love.graphics.draw(pic(16, 16, {}), 0, 0) end)
  end)
  T.eq(calls, 4, "every draw still reaches LOVE, once (a watch inside another adds nothing)")
  T.check(Shape.seen.enemy.img == DP_ENEMY and Shape.seen.enemy.x == 2 and Shape.seen.enemy.y == 2,
    "a foe's box (128 x 32) is seen where it went")
  T.check(Shape.seen.player.img == HGSS_PLAYER and Shape.seen.player.x == 40, "and yours (128 x 64)")
  local hooked = love.graphics.draw
  T.check(pcall(Shape.watch, function() error("boom") end) == false and love.graphics.draw == hooked,
    "an error inside puts love.graphics.draw back")
  Shape.watch(function() end)
  T.check(Shape.seen.enemy.img == nil and Shape.seen.player.img == nil, "each watch starts with nothing seen")
  love.graphics.draw = real
end

-- ------- Gen 3: the badges and chips by a set's boxes
local data = H.gen3Data(GAME)
require("src.core.GameVersion").set(GAME)
local Healthbox = require("src.core.game3.battle.healthbox")
local Chrome = require("src.ui.game3.battle_chrome")
Chrome.drawDoublesBox = function() end
Chrome.drawEnemyBox = function() end
Chrome.drawPlayerBox = function() end
Healthbox.draw = function(side, battler, opts)
  if not battler then return end
  if type(side) == "number" then
    local c = Healthbox.CENTERS[true][side]
    return Chrome.drawDoublesBox(side % 2 == 0, c.x - 32, c.y - 16)
  end
  local c = side == "player" and Healthbox.PLAYER_CENTER or Healthbox.ENEMY_CENTER
  if side == "player" then Chrome.drawPlayerBox(c.x - 32, c.y - 16) else Chrome.drawEnemyBox(c.x - 32, c.y - 16) end
end

local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.events:emit("game.ready", {})
local badges, hints = Healthbox.__ndxBadges, Healthbox.__ndxStatHints
T.check(badges and badges.shape and hints and hints.shape, "both are given the shapes")
local SH = dofile("mods/national_dex_gen3/src/stat_hints.lua")

local drawn, chips = {}, {}
badges.drawBadge = function(t, bx, by) drawn[#drawn + 1] = { t = t, x = bx, y = by } end
hints.drawChip = function(text, up, cx, cy, w, h)
  chips[#chips + 1] = { text = text, x = cx, y = cy, w = w or SH.width(text), h = h or SH.H }
end
hints.view = function() return nil end

-- a set's picture on BattleChrome while each box draws, as Facets swaps them (outside our wraps)
local set = {}
local function swapping(name, field)
  local inner = Chrome[name]
  Chrome[name] = function(...)
    local saved = Chrome[field]
    if set[field] then Chrome[field] = set[field] end
    local ok, err = pcall(inner, ...)
    Chrome[field] = saved
    if not ok then error(err, 0) end
  end
end
swapping("drawEnemyBox", "_enemyBox")
swapping("drawPlayerBox", "_playerBox")
local doublesInner = Chrome.drawDoublesBox
Chrome.drawDoublesBox = function(isPlayer, ...)
  local field = isPlayer and "_doublesPlayerBox" or "_doublesOpponentBox"
  local saved = Chrome[field]
  if set[field] then Chrome[field] = set[field] end
  local ok, err = pcall(doublesInner, isPlayer, ...)
  Chrome[field] = saved
  if not ok then error(err, 0) end
end
local function draw(side, battler)
  drawn, chips = {}, {}
  Healthbox.draw(side, battler)
end

local ec, pc = Healthbox.ENEMY_CENTER, Healthbox.PLAYER_CENTER
local ex, ey, px, py = ec.x - 32, ec.y - 16, pc.x - 32, pc.y - 16
local foe = { type1 = 2, type2 = 0, stages = { attack = 1, defense = -1, speed = 2, spAtk = 1, spDef = -1,
  accuracy = -1, evasion = 1 } }
local mine = { type1 = 11, type2 = 14, stages = { attack = 2, spAtk = -1, speed = 1, defense = 1 } }

-- the game's own boxes (nothing swapped): the game's placement
draw("enemy", foe)
T.check(drawn[1] and drawn[1].x == ex + 95 and drawn[1].y == ey + 2, "the game's foe box: badges where they always were")
local gameFoeChipY = chips[1] and chips[1].y

set._enemyBox = GAME_LIKE
draw("enemy", foe)
T.check(drawn[1] and drawn[1].x == ex + 95 and drawn[1].y == ey + 2, "a recolour of it: the same place")
T.eq(chips[1] and chips[1].y, gameFoeChipY, "and its chips too")

set._enemyBox = DP_ENEMY
draw("enemy", foe)
T.check(drawn[1] and drawn[1].x == ex + 102 and drawn[1].y == ey + 2,
  ("DP's foe box: the badges clear its frame (%s,%s; box at %d,%d)"):format(drawn[1] and drawn[1].x, drawn[1] and drawn[1].y, ex, ey))
local under = #chips == 7
for _, c in ipairs(chips) do
  if c.y < ey + 32 then under = false end
end
T.check(under, "its chips start under its arrow and the badges' rows")

set._playerBox = HGSS_PLAYER
draw("player", mine)
T.check(drawn[1] and drawn[1].x == px - 13 and drawn[1].y == py,
  ("HGSS's box of yours: the badges clear its slanting side (%s,%s; box at %d,%d)"):format(drawn[1] and drawn[1].x, drawn[1] and drawn[1].y, px, py))
local clear = #chips == 4
for _, c in ipairs(chips) do
  local rel0, rel1 = c.y - py, c.y - py + c.h - 1
  local l = Shape.leftOver(hp, rel0, rel1)
  if c.x + c.w > px - 13 - 1 or (l and c.x + c.w > px + l - 2) then clear = false end
end
T.check(clear, "your chips sit left of the badges and the box, on every row they take")

set._doublesOpponentBox = DP_DOUBLES
draw(1, foe)
local c1 = Healthbox.CENTERS[true][1]
local dx0 = c1.x - 32
T.check(drawn[1] and drawn[1].x == dx0 + 102, ("doubles: a set's foe box moves its badges too (%s)"):format(drawn[1] and drawn[1].x))
local outward = #chips > 0
for _, c in ipairs(chips) do if c.x < dx0 + 102 + 21 then outward = false end end
T.check(outward, "and its chips go outward of them")

-- Facets' wrap outside ours (a second game started in the same run): still followed
set = {}
local hbInner = Healthbox.draw
Healthbox.draw = function(side, ...)
  local saved = Chrome._enemyBox
  Chrome._enemyBox = DP_ENEMY
  local ok, err = pcall(hbInner, side, ...)
  Chrome._enemyBox = saved
  if not ok then error(err, 0) end
end
draw("enemy", foe)
T.check(drawn[1] and drawn[1].x == ex + 102, "a set swapped in outside our wraps is followed as well")
Healthbox.draw = hbInner

run.release()
T.finish("national_dex_gen3 box shapes (" .. GAME .. ")")
