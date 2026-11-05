-- Type badges beside the battle HP boxes (option type_badges): a small square per type, to the right
-- of a foe's box and to the left of the player's, showing the battler's types as they are now
-- (Soak, Conversion, Roost, Transform; Forest's Curse's third type, __ndxType3).
--
-- Every box is drawn by the engine's Healthbox.draw (src/core/game3/battle/healthbox.lua), looked up
-- on the module at call time, which skips a hidden box, applies the slide-in and bounce, and hands the
-- box's top left to BattleChrome.drawEnemyBox / drawPlayerBox / drawDoublesBox. Those three are
-- wrapped to note where the box went (only inside Healthbox.draw), and Healthbox.draw is wrapped to
-- draw the badges beside it afterwards. They are drawn on the battle's own UI canvas, in the box's own
-- rows, so whatever moves that UI (WoobleView's Fill Screen) moves them with their box.
--
-- A box's edges are where its picture is drawn (EDGES: the same on all five carts, singles and
-- doubles, measured from each cart's box pictures). The badges are 12 x 12, drawn on the CPU once
-- per type (no art files); nothing is made per frame.
local TypeBadges = {}

local SIZE = 12
local STEP = 8    -- a second (and third) type's badge, down and out from the first (corners touching)
local GAP = 2     -- between the box and the badges

-- where a box's frame is, from its picture's top left, in its top 8 rows (the shadow tail runs on below
-- them: to the right under a foe's box, to the left under the player's): a foe's ends at x 92, the
-- player's starts at x 9; both start at row 2. GAP clear pixels on either side.
TypeBadges.EDGES = { enemy = { right = 92, top = 2 }, player = { left = 9, top = 2 } }

-- type id (src/core/game3/battle/types.lua; FAIRY 18 from src/types.lua) -> fill colour
TypeBadges.COLORS = {
  [0] = "a8a878", [1] = "c03028", [2] = "a890f0", [3] = "a040a0", [4] = "e0c068", [5] = "b8a038",
  [6] = "a8b820", [7] = "705898", [8] = "b8b8d0", [9] = "68a090", [10] = "f08030", [11] = "6890f0",
  [12] = "78c850", [13] = "f8d030", [14] = "f85888", [15] = "98d8d8", [16] = "7038f8", [17] = "705848",
  [18] = "ee99ac",
}

-- an 8 x 8 white symbol per type (our own; each kept readable at 12 px: a gear for Steel so it is not a
-- second ring beside Normal, a skull for Poison so it is not a second drop beside Water, a solid
-- feather for Flying so it is not a second leaf beside Grass)
TypeBadges.GLYPHS = {
  [0] = { "..####..", ".#....#.", "#......#", "#......#", "#......#", "#......#", ".#....#.", "..####.." }, -- normal
  [1] = { "##.##.##", "########", "########", "#####.##", "#####.##", ".######.", "..####..", "..####.." }, -- fighting
  [2] = { ".....###", "....####", "...####.", "..####..", ".####...", ".#.#....", "#.......", "#......." }, -- flying
  [3] = { "..####..", ".######.", "#..##..#", "#..##..#", "########", ".######.", "..#..#..", "..####.." }, -- poison
  [4] = { "........", "...##...", "..####..", ".######.", "########", "........", "########", "........" }, -- ground
  [5] = { "..####..", ".######.", "###.####", "#####.##", "##.#####", "########", "########", ".######." }, -- rock
  [6] = { ".#....#.", "..#..#..", "..####..", ".##..##.", "########", ".######.", "#.####.#", "..#..#.." }, -- bug
  [7] = { "..####..", ".######.", "#..##..#", "#..##..#", "########", "########", "########", "#.#..#.#" }, -- ghost
  [8] = { "...##...", ".######.", ".######.", "###..###", "###..###", ".######.", ".######.", "...##..." }, -- steel
  [9] = { "..####..", ".##..##.", ".....##.", "....##..", "...##...", "...##...", "........", "...##..." }, -- ???
  [10] = { "....#...", "...##...", "..###.#.", "..#####.", ".###.##.", ".##..##.", ".##..##.", "..####.." }, -- fire
  [11] = { "...##...", "...##...", "..####..", ".######.", ".######.", ".######.", ".######.", "..####.." }, -- water
  [12] = { "......##", "....####", "..####.#", ".###..##", ".##..###", ".#..###.", "..####..", "##......" }, -- grass
  [13] = { "....####", "...###..", "..###...", ".######.", "...###..", "..###...", ".##.....", "#......." }, -- electric
  [14] = { "........", "..####..", ".#....#.", "#..##..#", "#..##..#", ".#....#.", "..####..", "........" }, -- psychic
  [15] = { "...##...", ".#.##.#.", "..####..", "########", "########", "..####..", ".#.##.#.", "...##..." }, -- ice
  [16] = { "##....##", "###..###", ".######.", "..####..", "..####..", "..####..", "...##...", "...##..." }, -- dragon
  [17] = { "...####.", "..###...", ".###....", ".##.....", ".##.....", ".###....", "..###...", "...####." }, -- dark
  [18] = { "...##...", "...##...", "########", ".######.", "..####..", "..####..", ".##..##.", "##....##" }, -- fairy
}

local function hex(h)
  return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end

-- the badge's pixels: a rounded square in the type's colour, a darker rim, the white symbol
function TypeBadges.imageData(typeId)
  local color, glyph = TypeBadges.COLORS[typeId], TypeBadges.GLYPHS[typeId]
  if not (color and glyph) then return nil end
  local r, g, b = hex(color)
  local d = love.image.newImageData(SIZE, SIZE)
  for y = 0, SIZE - 1 do
    for x = 0, SIZE - 1 do
      local edgeX, edgeY = x == 0 or x == SIZE - 1, y == 0 or y == SIZE - 1
      if not (edgeX and edgeY) then
        if edgeX or edgeY then
          d:setPixel(x, y, r * 0.55, g * 0.55, b * 0.55, 1)
        else
          d:setPixel(x, y, r, g, b, 1)
        end
      end
    end
  end
  for gy = 1, 8 do
    local row = glyph[gy]
    for gx = 1, 8 do
      if row:sub(gx, gx) == "#" then d:setPixel(gx + 1, gy + 1, 1, 1, 1, 1) end
    end
  end
  return d
end

-- opts: { require, enabled = fn() -> bool, log }
function TypeBadges.install(opts)
  local require = opts.require
  local okH, Healthbox = pcall(require, "src.core.game3.battle.healthbox")
  local okC, Chrome = pcall(require, "src.ui.game3.battle_chrome")
  if not (okH and okC and type(Healthbox) == "table" and type(Chrome) == "table"
    and type(Healthbox.draw) == "function" and type(Chrome.drawEnemyBox) == "function") then
    if opts.log then opts.log:warn("type badges are off: the battle's HP boxes were not found") end
    return false
  end
  -- one set of wraps for the process (games switch in-process); a later install brings its own option
  local state = Healthbox.__ndxBadges
  state = state or {}
  state.enabled = opts.enabled or function() return true end
  state.require = require
  if Healthbox.__ndxBadges then return true end
  Healthbox.__ndxBadges = state

  local hasLove = love and love.graphics and love.image and love.image.newImageData and true or false
  local images = {}          -- type id -> Image, or false
  local inside, boxX, boxY, boxSide = 0, nil, nil, nil

  local function badge(t)
    local img = images[t]
    if img == nil then
      img = false
      if hasLove then
        local ok, made = pcall(function()
          local d = TypeBadges.imageData(t)
          if not d then return false end
          local im = love.graphics.newImage(d)
          im:setFilter("nearest", "nearest")
          return im
        end)
        img = ok and made or false
      end
      images[t] = img
    end
    return img
  end

  local function note(side, x, y)
    if inside == 0 then return end
    boxSide, boxX, boxY = side, x, y
  end

  local drawEnemyBox, drawPlayerBox, drawDoublesBox = Chrome.drawEnemyBox, Chrome.drawPlayerBox, Chrome.drawDoublesBox
  Chrome.drawEnemyBox = function(x, y, ...)
    note("enemy", x, y)
    return drawEnemyBox(x, y, ...)
  end
  Chrome.drawPlayerBox = function(x, y, ...)
    note("player", x, y)
    return drawPlayerBox(x, y, ...)
  end
  if type(drawDoublesBox) == "function" then
    Chrome.drawDoublesBox = function(isPlayer, x, y, ...)
      note(isPlayer and "player" or "enemy", x, y)
      return drawDoublesBox(isPlayer, x, y, ...)
    end
  end

  local function typeId(v)
    if type(v) == "number" then return v end
    if type(v) == "string" then
      local okT, Types = pcall(state.require, "src.core.game3.battle.types")
      return okT and Types and Types.ID and Types.ID[v:upper()] or nil
    end
    return nil
  end

  -- draws one badge (state.drawBadge: the seam tests watch)
  state.drawBadge = function(t, x, y)
    local img = badge(t)
    if img then love.graphics.draw(img, x, y) end
  end

  local function drawBadges(battler)
    if not (boxX and type(battler) == "table") then return end
    local okOn, on = pcall(state.enabled)
    if okOn and on == false then return end
    local t1, t2, t3 = typeId(battler.type1), typeId(battler.type2), typeId(battler.__ndxType3)
    if t2 == t1 then t2 = nil end
    if t3 == t1 or t3 == t2 then t3 = nil end
    -- the ??? type only when it is all there is
    if t1 == 9 and t2 then t1, t2 = t2, nil end
    if t2 == 9 then t2 = nil end
    if t3 == 9 then t3 = nil end
    if not t1 then return end
    local e = TypeBadges.EDGES[boxSide]
    local n = 1 + (t2 and 1 or 0) + (t3 and 1 or 0)
    local x, y, dx
    if boxSide == "enemy" then
      x, dx = boxX + e.right + 1 + GAP, STEP
    else
      x, dx = boxX + e.left - GAP - SIZE - (n - 1) * STEP, STEP
    end
    y = boxY + e.top
    if love and love.graphics and love.graphics.setColor then love.graphics.setColor(1, 1, 1, 1) end
    state.drawBadge(t1, x, y)
    if t2 then state.drawBadge(t2, x + dx, y + STEP) end
    if t3 then state.drawBadge(t3, x + dx * 2, y + STEP * 2) end
  end

  local draw = Healthbox.draw
  Healthbox.draw = function(side, battler, o, ...)
    inside = inside + 1
    boxX = nil
    local ok, a, b = pcall(draw, side, battler, o, ...)
    inside = inside - 1
    if not ok then error(a, 0) end
    if inside == 0 and boxX then
      local okB, err = pcall(drawBadges, battler)
      if not okB and opts.log and not state.warned then
        state.warned = true
        opts.log:warn("type badge draw failed: %s", tostring(err))
      end
      boxX = nil
    end
    return a, b
  end
  return true
end

return TypeBadges
