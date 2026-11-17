-- The shape of a battle box picture another mod draws in place of the game's own (Facets' battle box
-- sets: XY, DP, HGSS, BW... on Gen 3, and its Gen 3 boxes in Red's and Gold's wide battles), so the
-- type badges and the stat chips sit by that box's own edges instead of the game's.
--
-- A picture is measured once (weakly cached by the picture): its first and last drawn column on each
-- row. A LOVE Image cannot be read back, so it is drawn once onto a small canvas of its own and that
-- canvas read (ImageData, or anything with getPixel/getDimensions, is read as it is). Nothing is
-- shipped or saved from it, and no file is read.
--
-- Gen 3 swaps the box pictures on BattleChrome while a box draws (src/type_badges.lua and
-- src/stat_hints.lua note the picture there). Gen 1/2 draw a mod's box themselves: Shape.watch runs a
-- draw with love.graphics.draw watched for a Gen 3-sized box picture (128 x 32 a foe's, 128 x 64
-- yours) and notes where it went.
local Shape = {}

local cache = setmetatable({}, { __mode = "k" })

-- the picture's pixels: ImageData as it is, an Image drawn onto a canvas and read back; or nil
function Shape.pixels(img)
  local t = type(img)
  if t ~= "userdata" and t ~= "table" then return nil end
  if type(img.getPixel) == "function" then return img end
  local G = love and love.graphics
  if not (G and G.newCanvas and G.push and G.pop and type(img.getDimensions) == "function") then return nil end
  local okD, w, h = pcall(img.getDimensions, img)
  if not (okD and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 and w <= 512 and h <= 512) then
    return nil
  end
  local okC, canvas = pcall(G.newCanvas, w, h)
  if not (okC and canvas) then return nil end
  G.push("all")
  local okR = pcall(function()
    G.setCanvas(canvas)
    G.origin()
    G.setScissor()
    if G.setShader then G.setShader() end
    if G.setStencilTest then G.setStencilTest() end
    G.setBlendMode("alpha")
    G.setColor(1, 1, 1, 1)
    G.clear(0, 0, 0, 0)
    G.draw(img, 0, 0)
  end)
  G.pop()
  if not okR then return nil end
  local okI, data = pcall(canvas.newImageData, canvas)
  pcall(canvas.release, canvas)
  return okI and data or nil
end

-- { w, h, top, bottom, minX, maxX, left = { [row] = first column }, right = { [row] = last column } }
-- (rows and columns from 0, the picture's top left), or nil when it cannot be read or is empty
function Shape.of(img)
  if img == nil then return nil end
  local hit = cache[img]
  if hit ~= nil then return hit or nil end
  cache[img] = false
  local d = Shape.pixels(img)
  if not d then return nil end
  local okD, w, h = pcall(d.getDimensions, d)
  if not (okD and type(w) == "number" and type(h) == "number") then return nil end
  local s = { w = w, h = h, left = {}, right = {} }
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local _, _, _, a = d:getPixel(x, y)
      if a and a > 0 then
        if s.left[y] == nil then s.left[y] = x end
        s.right[y] = x
      end
    end
    local l, r = s.left[y], s.right[y]
    if l then
      s.top = s.top or y
      s.bottom = y
      if not s.minX or l < s.minX then s.minX = l end
      if not s.maxX or r > s.maxX then s.maxX = r end
    end
  end
  if not s.top then return nil end
  cache[img] = s
  return s
end

-- the last drawn column over rows y0..y1 (nil: none drawn there)
function Shape.rightOver(s, y0, y1)
  local best
  for y = math.max(0, y0), math.min(s.h - 1, y1) do
    local r = s.right[y]
    if r and (not best or r > best) then best = r end
  end
  return best
end

-- the first drawn column over rows y0..y1 (nil: none drawn there)
function Shape.leftOver(s, y0, y1)
  local best
  for y = math.max(0, y0), math.min(s.h - 1, y1) do
    local l = s.left[y]
    if l and (not best or l < best) then best = l end
  end
  return best
end

-- true when the picture's frame is where the game's own is (edges: { right = , top = } for a foe's,
-- { left = , top = } for yours; its top 8 rows, as those edges were measured): the game's own box,
-- or a set that only recolours it, keeps the game's placement exactly
function Shape.likeGame(s, edges, side)
  if not (s and edges) or s.top ~= edges.top then return false end
  if side == "enemy" then return Shape.rightOver(s, 0, 7) == edges.right end
  return Shape.leftOver(s, 0, 7) == edges.left
end

-- the last (first) drawn column over rows y0..y1 of this box and of `other` ({ s, x, y }: another box
-- whose picture's top left is at x, y from this one's), in this box's columns
local function rightBoth(s, y0, y1, other)
  local r = Shape.rightOver(s, y0, y1)
  if other then
    local o = Shape.rightOver(other.s, y0 - other.y, y1 - other.y)
    if o and (not r or o + other.x > r) then r = o + other.x end
  end
  return r
end
local function leftBoth(s, y0, y1, other)
  local l = Shape.leftOver(s, y0, y1)
  if other then
    local o = Shape.leftOver(other.s, y0 - other.y, y1 - other.y)
    if o and (not l or o + other.x < l) then l = o + other.x end
  end
  return l
end

-- where the first of n badges goes, from the picture's top left: x, y. Badge k (from 0) is at
-- (x + k * dx, y + k * dy), size x size; each clears the box's drawn columns on its own rows by gap
-- (a foe's to the right of its box, yours to the left), and those of `other` (a doubles partner's
-- box, { s, x, y } from this one's top left: a set's taller boxes reach each other's rows). nil when
-- no row of the box is beside them.
function Shape.badgeSpot(s, side, n, size, dx, dy, gap, other)
  local y = s.top
  local x
  for k = 0, n - 1 do
    local r0, r1 = y + k * dy, y + k * dy + size - 1
    if side == "enemy" then
      local r = rightBoth(s, r0, r1, other)
      if r then
        local want = r + 1 + gap - k * dx
        if not x or want > x then x = want end
      end
    else
      local l = leftBoth(s, r0, r1, other)
      if l then
        local want = l - gap - size - k * dx
        if not x or want < x then x = want end
      end
    end
  end
  if not x then return nil end
  return x, y
end

-- ------- Gen 1/2: a mod's Gen 3-sized box drawn during fn
-- Shape.seen.enemy / .player: { img, x, y } of the last such box drawn inside the outermost watch
-- (img nil: none). Nested watches share the outer one's notes.
Shape.seen = { enemy = { x = 0, y = 0 }, player = { x = 0, y = 0 } }
local depth, realDraw = 0, nil

local function boxSide(img)
  local t = type(img)
  if t ~= "userdata" and t ~= "table" then return nil end
  local getDimensions = img.getDimensions
  if type(getDimensions) ~= "function" then return nil end
  local ok, w, h = pcall(getDimensions, img)
  if not ok or w ~= 128 then return nil end
  if h == 32 then return "enemy" end
  if h == 64 then return "player" end
  return nil
end

local function watchedDraw(img, x, y, ...)
  if type(x) == "number" then
    local side = boxSide(img)
    if side then
      local n = Shape.seen[side]
      n.img, n.x, n.y = img, x, y or 0
    end
  end
  return realDraw(img, x, y, ...)
end

-- clears the notes (the outermost watch does this itself)
function Shape.forget()
  Shape.seen.enemy.img, Shape.seen.player.img = nil, nil
end

-- runs fn(...) with love.graphics.draw watched; returns fn's first two results
function Shape.watch(fn, ...)
  local G = love and love.graphics
  if depth > 0 or not (G and G.draw) then return fn(...) end
  Shape.forget()
  realDraw = G.draw
  G.draw = watchedDraw
  depth = 1
  local ok, a, b = pcall(fn, ...)
  depth = 0
  if G.draw == watchedDraw then G.draw = realDraw end
  if not ok then error(a, 0) end
  return a, b
end

return Shape
