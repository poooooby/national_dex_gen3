-- Stat Hints (option stat_hints): small chips by each battle HP box naming every stat a Pokemon
-- has raised or lowered and what it multiplies by ("ATK 2x", "SPA 0.5x", "DEF 0.67x"), read from
-- the battler's stages each time the box is drawn, so they follow every move as it happens (Swords
-- Dance twice: ATK 3x; a Growl after: ATK 2.5x).
--
-- Where: a foe's under its box in singles, in rows from the box's left wrapping downward into the
-- field. Yours, and every box in doubles, in columns beside the box, outward of its type badges:
-- under your box there is no room before the text box (its EXP bar is the last rows). In doubles
-- each box has its own band of rows (FRAME.doubles.bands: a side's two bands stacked, the foes'
-- from the screen's top, yours from row 66 to the text box), the band nearest the box, so a box's
-- columns never reach the partner's chips or any box. No chip crosses row 66 (SPLIT): Battle Fit
-- views (gen3-hd-sprites) draw the screen's rows above and below it apart. A column that would
-- leave the screen (seven changes on one of your doubles Pokemon) is held at its edge. Another mod's
-- box picture (Facets' battle box sets) is measured (src/box_shape.lua, opts.shape) and the chips
-- go by its own frame and the type badges' place beside it, as the badges do. Red to Crystal
-- (src/gen12/stat_hints.lua) place them by their own HUDs.
--
-- A chip: its text inside a rounded outline, both green for a rise and red for a drop, on a white
-- ground a quarter see-through. The multiplier is a decimal rounded to hundredths, trailing zeros
-- dropped. Two ways to draw it:
--   window resolution, with WoobleView (gen3-hd-sprites, its uiMap export): smaller chips in a smooth
--     font (LOVE's own), queued while the boxes draw and drawn from render.hud (StatHints.hud) where
--     the UI canvas went: WoobleView's uiMap when it placed the UI (Fill Screen), else the
--     Renderer's own UI blits (a Renderer:blitCanvas wrap notes them). Sizes in StatHints.HI.
--   the game's pixels, without it: a 3 x 5 font of their own, each chip made on the CPU once per
--     text and drawn on the UI canvas.
-- Neither makes anything per frame.
local StatHints = {}

-- the stats in the order they are shown, with their labels
StatHints.STATS = {
  { key = "attack", label = "ATK" }, { key = "defense", label = "DEF" }, { key = "spAtk", label = "SPA" },
  { key = "spDef", label = "SPD" }, { key = "speed", label = "SPE" },
  { key = "accuracy", label = "ACC" }, { key = "evasion", label = "EVA" },
}
-- a chip's colour: green for a rise, red for a drop
StatHints.UP = { 0.16, 0.74, 0.30 }
StatHints.DOWN = { 0.90, 0.20, 0.18 }
StatHints.FILL = { 1, 1, 1, 0.75 }                -- the ground: white, 25% see-through
function StatHints.color(up) return up and StatHints.UP or StatHints.DOWN end
local ACCURACY = { accuracy = true, evasion = true }

-- what a stage multiplies by: the five stats (2 + n) / 2 or 2 / (2 - n); accuracy and evasion
-- (3 + n) / 3 or 3 / (3 - n). As text: rounded to hundredths, no trailing zeros ("0.67", "2").
function StatHints.multiplier(key, n)
  local b = ACCURACY[key] and 3 or 2
  return n >= 0 and (b + n) / b or b / (b - n)
end
local function decimal(v)
  local s = string.format("%.2f", math.floor(v * 100 + 0.5) / 100)
  return (s:gsub("0+$", ""):gsub("%.$", ""))
end

-- every chip's text, made once (a frame makes no string): TEXT[label][stage]
local TEXT = {}
local function build(key, label)
  TEXT[label] = TEXT[label] or {}
  for n = -6, 6 do
    if n ~= 0 then TEXT[label][n] = label .. " " .. decimal(StatHints.multiplier(key, n)) .. "x" end
  end
end
for _, s in ipairs(StatHints.STATS) do build(s.key, s.label) end

-- a chip's text for a stat at a stage ("ATK 2x", "SPA 0.5x"), or nil at 0
function StatHints.text(key, label, stage)
  stage = math.max(-6, math.min(6, math.floor(tonumber(stage) or 0)))
  if stage == 0 then return nil end
  if not TEXT[label] then build(key, label) end
  return TEXT[label][stage]
end

-- the chips for a battler: { { text, up }, ... } in STATS order; get(src, key) -> stage (a fixed
-- function and its source, so a frame makes no closure)
function StatHints.chips(get, src, out)
  out = out or {}
  local n = 0
  for _, s in ipairs(StatHints.STATS) do
    local st = tonumber(get(src, s.key)) or 0
    local t = StatHints.text(s.key, s.label, st)
    if t then
      n = n + 1
      local c = out[n] or {}
      c.text, c.up = t, st > 0
      out[n] = c
    end
  end
  for i = n + 1, #out do out[i] = nil end
  return out
end

-- ------- the font and the chips
local GLYPH = {
  ["A"] = { "010", "101", "111", "101", "101" }, ["C"] = { "011", "100", "100", "100", "011" },
  ["D"] = { "110", "101", "101", "101", "110" }, ["E"] = { "111", "100", "110", "100", "111" },
  ["F"] = { "111", "100", "110", "100", "100" }, ["K"] = { "101", "101", "110", "101", "101" },
  ["P"] = { "110", "101", "110", "100", "100" }, ["S"] = { "011", "100", "010", "001", "110" },
  ["T"] = { "111", "010", "010", "010", "010" }, ["V"] = { "101", "101", "101", "101", "010" },
  ["x"] = { "000", "000", "101", "010", "101" },
  -- the decimal point: its own column with clear space either side ("1.5x", never "15x")
  ["."] = { "000", "000", "000", "000", "100" }, [" "] = { "000", "000", "000", "000", "000" },
  ["0"] = { "111", "101", "101", "101", "111" }, ["1"] = { "010", "110", "010", "010", "111" },
  ["2"] = { "111", "001", "111", "100", "111" }, ["3"] = { "111", "001", "111", "001", "111" },
  ["4"] = { "101", "101", "111", "001", "001" }, ["5"] = { "111", "100", "111", "001", "111" },
  ["6"] = { "111", "100", "111", "101", "111" }, ["7"] = { "111", "001", "001", "001", "001" },
  ["8"] = { "111", "101", "111", "101", "111" }, ["9"] = { "111", "101", "111", "001", "111" },
}
StatHints.GLYPH = GLYPH
StatHints.H = 9                                   -- a chip's height: 5 px letters, a clear pixel, the outline
StatHints.GAP = 1                                 -- between chips

-- a character's advance: the space is narrow; the dot takes 3 (its pixel, then two clear before
-- the next digit, as the digit before it leaves two)
local function advance(ch)
  if ch == " " then return 2 end
  if ch == "." then return 3 end
  return 4
end
function StatHints.width(text)
  local w = 0
  for i = 1, #text do w = w + advance(text:sub(i, i)) end
  return w - 1 + 4                                -- the last character's gap; a clear pixel and the outline each side
end

-- the chip's pixels: a rounded outline and the letters in green (a rise) or red (a drop) on white
function StatHints.imageData(text, up)
  local w, h = StatHints.width(text), StatHints.H
  local c = StatHints.color(up)
  local d = love.image.newImageData(w, h)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local edgeX, edgeY = x == 0 or x == w - 1, y == 0 or y == h - 1
      if (edgeX or edgeY) and not (edgeX and edgeY) then d:setPixel(x, y, c[1], c[2], c[3], 1)
      elseif not (edgeX or edgeY) then
        local f = StatHints.FILL
        d:setPixel(x, y, f[1], f[2], f[3], f[4])
      end
    end
  end
  local x0 = 2
  for i = 1, #text do
    local ch = text:sub(i, i)
    local g = GLYPH[ch]
    if g then
      for gy = 1, 5 do
        local row = g[gy]
        for gx = 1, #row do
          if row:sub(gx, gx) == "1" then d:setPixel(x0 + gx - 1, gy + 1, c[1], c[2], c[3], 1) end
        end
      end
    end
    x0 = x0 + advance(ch)
  end
  return d
end

-- the chip images, made once each (false when there is no LOVE: headless)
function StatHints.cache()
  local images = {}
  local hasLove = love and love.graphics and love.image and love.image.newImageData and true or false
  return function(text, up)                       -- (a text is always the same way: > 1 a rise)
    local img = images[text]
    if img == nil then
      img = false
      if hasLove then
        local ok, made = pcall(function()
          local im = love.graphics.newImage(StatHints.imageData(text, up))
          im:setFilter("nearest", "nearest")
          return im
        end)
        img = ok and made or false
      end
      images[text] = img
    end
    return img
  end
end

-- the game's pixels' measure
StatHints.PIXEL = { H = StatHints.H, GAP = StatHints.GAP, width = StatHints.width }

-- ------- window resolution (with WoobleView): sizes in game pixels, drawn at the window's scale
-- H the chip's height, EM the font's size, PAD the room each side of the text, LINE the outline
-- (window px per game px), RADIUS its corners
StatHints.HI = { H = 6, GAP = 1, EM = 5, PAD = 1, LINE = 0.3, RADIUS = 1.2 }
local REF = 64                                    -- the size the widths are measured at
local metric                                      -- that font, or false (no LOVE: headless)
local hiWidths = {}
function StatHints.HI.width(text)
  local w = hiWidths[text]
  if w then return w end
  if metric == nil then
    local ok, f = pcall(function() return love.graphics.newFont(REF) end)
    metric = ok and f or false
  end
  local HI = StatHints.HI
  local tw = metric and metric:getWidth(text) / REF * HI.EM or #text * 0.6 * HI.EM
  w = math.floor((tw + 2 * HI.PAD) * 4 + 0.5) / 4  -- (a quarter pixel: positions stay exact)
  hiWidths[text] = w
  return w
end
-- the window-sized fonts, by pixel size (a few: the window's size changes rarely)
local fonts, fontCount = {}, 0
local function fontOf(px)
  local f = fonts[px]
  if f == nil then
    if fontCount >= 8 then fonts, fontCount = {}, 0 end
    local ok, made = pcall(love.graphics.newFont, px)
    f = ok and made or false
    fonts[px], fontCount = f, fontCount + 1
  end
  return f
end
-- the queue: this frame's chips at window resolution (slots kept from frame to frame)
local queue, queued = {}, 0
StatHints.QUEUE_MAX = 64
function StatHints.enqueue(text, up, x, y, w, h)
  if queued >= StatHints.QUEUE_MAX then return end
  queued = queued + 1
  local q = queue[queued]
  if not q then q = {}; queue[queued] = q end
  q.text, q.up, q.x, q.y, q.w, q.h = text, up, x, y, w, h
end
function StatHints.queued() return queued, queue end
function StatHints.clearQueue() queued = 0 end

-- one chip at window (X, Y), s window px per game px
local function drawHi(q, X, Y, sx, sy)
  local G, HI = love.graphics, StatHints.HI
  local x, y = math.floor(X + q.x * sx + 0.5), math.floor(Y + q.y * sy + 0.5)
  local w, h = math.floor(q.w * sx + 0.5), math.floor(q.h * sy + 0.5)
  local r = HI.RADIUS * sy
  local f = StatHints.FILL
  G.setColor(f[1], f[2], f[3], f[4])
  G.rectangle("fill", x, y, w, h, r, r)
  local c = StatHints.color(q.up)
  G.setColor(c[1], c[2], c[3], 1)
  local lw = math.max(1, math.floor(HI.LINE * sy + 0.5))
  G.setLineWidth(lw)
  G.rectangle("line", x + lw / 2, y + lw / 2, w - lw, h - lw, r, r)
  local font = fontOf(math.max(6, math.floor(HI.EM * sy + 0.5)))
  if not font then return end
  G.setFont(font)
  -- the capitals centred in the chip (a cap is ~0.73 of the font's size)
  local cap = font:getHeight() / 1.164 * 0.73
  local ty = y + (h - cap) / 2 + cap - font:getBaseline()
  G.print(q.text, math.floor(x + HI.PAD * sx + 0.5), math.floor(ty + 0.5))
end

-- every queued chip, where the UI canvas went: map = WoobleView's uiMap (banded: rows above its
-- split moved up: row 66 in singles, 58 in doubles, which the layout keeps chips off), or the
-- Renderer's own UI blits (blits[i] = { bx, by, sx, sy, x, y, w, h })
function StatHints.drawQueue(map, blits, nBlits)
  if queued == 0 then return end
  local G = love.graphics
  G.push("all")
  G.origin()
  G.setShader()
  G.setBlendMode("alpha", "alphamultiply")
  if map then
    -- (banded: a chip goes with the band its top row is in, clipped to that band's box)
    for i = 1, queued do
      local q = queue[i]
      local top = map.banded and q.y < map.split
      local b = map.banded and (top and map.topBox or map.lowBox) or map.box
      G.setScissor(b[1], b[2], b[3], b[4])
      drawHi(q, map.x, top and map.topY or map.y, map.sx, map.sy)
    end
  else
    for k = 1, nBlits or 0 do
      local t = blits[k]
      if t[7] and t[7] > 0 then G.setScissor(t[5], t[6], t[7], t[8]) else G.setScissor() end
      for i = 1, queued do drawHi(queue[i], t[1], t[2], t[3], t[4]) end
    end
  end
  G.pop()
end

-- ------- where the chips go
-- spot = { x, y, mode, limit }:
--   "down"    rows from (x, y) rightward, `limit` wide, wrapping downward (a foe's, under its box)
--   "left"    rows ending at x, growing leftward; past `limit` wide (if given) a new row above
--   "column"  a column from (x, y) downward `limit` tall, the next column outward (`dir` +1 / -1)
-- spot.split: a row no chip crosses (a row of "down" that would starts on it instead); spot.right:
-- the screen's width, a column's chips kept on it. place(i, x, y, w, h) is called for each chip;
-- nothing is made. size: the chips' measure (StatHints.PIXEL or StatHints.HI: width(text), H, GAP)
function StatHints.layout(chips, spot, place, size)
  size = size or StatHints.PIXEL
  local H, G, width = size.H, size.GAP, size.width
  if spot.mode == "left" then
    local x, y = spot.x, spot.y
    for i = 1, #chips do
      local w = width(chips[i].text)
      if spot.limit and x - w < spot.x - spot.limit and x < spot.x then
        x, y = spot.x, math.max(0, y - H - G)
      end
      x = x - w
      place(i, x, y, w, H)
      x = x - G
    end
  elseif spot.mode == "column" then
    local dir = spot.dir or 1
    local x, y, colW = spot.x, spot.y, 0
    for i = 1, #chips do
      local w = width(chips[i].text)
      if y + H > spot.y + spot.limit and y > spot.y then
        x = x + dir * (colW + G)
        y, colW = spot.y, 0
      end
      local px = dir > 0 and x or (x - w)
      if spot.right then px = math.max(0, math.min(spot.right - w, px)) end
      place(i, px, y, w, H)
      if w > colW then colW = w end
      y = y + H + G
    end
  else
    local x, y = spot.x, spot.y
    for i = 1, #chips do
      local w = width(chips[i].text)
      if x + w > spot.x + spot.limit and x > spot.x then
        x, y = spot.x, y + H + G
        if spot.split and y < spot.split and y + H > spot.split then y = spot.split end
      end
      place(i, x, y, w, H)
      x = x + w + G
    end
  end
end

-- ------- Gen 3: the HP boxes (src/core/game3/battle/healthbox.lua), as the type badges find them
-- A box's frame, from its picture's top left (the cart's box pictures, the same on all five carts):
StatHints.FRAME = {
  enemy = { left = 0, right = 92, bottom = 29,         -- singles: the foe's box
    rows = 120 },                                      -- its chips' rows: into the field's open middle
  player = { left = 9, right = 103, bottom = 37 },     -- singles: yours (its EXP bar the last rows)
  doubles = { top = 2, bottom = 23, enemyRight = 92, playerLeft = 9,
    -- each box's chip rows (the cart's doubles boxes: foes' at y 3 and 28, yours at 60 and 84): a
    -- box takes the band whose top is nearest its own. The foes' three chips tall above the split,
    -- yours two between it and the text box.
    bands = { enemy = { tops = { 0, 29 }, height = 29 }, player = { tops = { 66, 89 }, height = 23 } } },
}
StatHints.SPLIT = 66                                  -- Battle Fit's split row: no chip crosses it
-- a doubles box's band: its top row and height
function StatHints.doublesBand(side, y)
  local b = StatHints.FRAME.doubles.bands[side == "enemy" and "enemy" or "player"]
  local best = b.tops[1]
  for _, t in ipairs(b.tops) do if math.abs(t - y) < math.abs(best - y) then best = t end end
  return best, b.height
end
StatHints.SCREEN_W = 240
StatHints.TEXT_TOP = 112                              -- the battle's text box: nothing below this
StatHints.BADGES = 2 + 12 + 8 + 2                     -- room for the type badges (two, a step apart)
-- the type badges (src/type_badges.lua): size, step (down and out), gap to the box; and the game's
-- own box edges they are placed by (TypeBadges.EDGES)
StatHints.BADGE = { size = 12, step = 8, gap = 2,
  edges = { enemy = { right = 92, top = 2 }, player = { left = 9, top = 2 } } }

-- where a box's chips go by a measured box picture (src/box_shape.lua's shape s, from the picture's
-- top left at x, y), into out; false when the picture gives nothing to go by (the caller keeps FRAME)
-- partner: a doubles partner's box ({ s, x, y } from this one's top left), as the badges clear it
function StatHints.spotByShape(Shape, s, side, x, y, doubles, out, partner)
  local B = StatHints.BADGE
  local bx = Shape.badgeSpot(s, side, 2, B.size, B.step, B.step, B.gap, partner)
  if not bx then return false end
  local NONE = -1e9
  out.split, out.right = StatHints.SPLIT, StatHints.SCREEN_W
  if doubles then
    out.mode = "column"
    out.y, out.limit = StatHints.doublesBand(side, y)
    local r0, r1 = out.y - y, out.y - y + out.limit - 1
    if side == "enemy" then
      out.x, out.dir = x + math.max(bx + B.size + B.step + 1, (Shape.rightOver(s, r0, r1) or NONE) + 3), 1
    else
      out.x, out.dir = x + math.min(bx - 2, (Shape.leftOver(s, r0, r1) or -NONE) - 2), -1
    end
    return out
  end
  if side == "enemy" then
    out.mode, out.dir, out.limit = "down", 1, StatHints.FRAME.enemy.rows
    out.x = x + s.minX
    out.y = y + math.max(s.bottom + 2, s.top + B.size + 2 * B.step + 1)
    return out
  end
  out.mode, out.dir = "column", -1
  out.y = y + s.top + 1
  out.limit = math.min(s.bottom - s.top - 1, StatHints.TEXT_TOP - out.y)
  out.x = x + math.min(bx - 2, (Shape.leftOver(s, s.top + 1, s.top + out.limit) or -NONE) - 2)
  return out
end

-- opts: { require, enabled = fn() -> bool, log, view = fn() -> WoobleView's exports or nil,
--   shape = src/box_shape.lua (optional) }
function StatHints.install(opts)
  local require = opts.require
  local okH, Healthbox = pcall(require, "src.core.game3.battle.healthbox")
  local okC, Chrome = pcall(require, "src.ui.game3.battle_chrome")
  if not (okH and okC and type(Healthbox) == "table" and type(Chrome) == "table"
    and type(Healthbox.draw) == "function" and type(Chrome.drawEnemyBox) == "function") then
    if opts.log then opts.log:warn("stat hints are off: the battle's HP boxes were not found") end
    return false
  end
  local state = Healthbox.__ndxStatHints or {}
  state.enabled = opts.enabled or function() return true end
  state.shape = opts.shape or state.shape
  -- WoobleView's exports when they can place window-resolution chips (features.uiMap), else nil
  local viewOf = opts.view or function() return nil end
  state.view = function()
    local okV, ex = pcall(viewOf)
    if not (okV and type(ex) == "table" and type(ex.features) == "table" and ex.features.uiMap
      and type(ex.uiMap) == "function") then return nil end
    local okA, active = pcall(ex.isActive)
    return (okA and active) and ex or nil
  end
  if Healthbox.__ndxStatHints then return state end
  Healthbox.__ndxStatHints = state

  -- the Renderer's own blits of the UI canvas this frame (for window-resolution chips without
  -- WoobleView's map): a process-wide note on the Renderer, read by StatHints.hud
  local okR, Renderer = pcall(require, "src.render.Renderer")
  local blits, nBlits = {}, 0
  for i = 1, 4 do blits[i] = { 0, 0, 1, 1, 0, 0, 0, 0 } end
  if okR and type(Renderer) == "table" and type(Renderer.blitCanvas) == "function"
    and not Renderer.__ndxStatHintsBlit then
    local blitCanvas = Renderer.blitCanvas
    Renderer.__ndxStatHintsBlit = true
    Renderer.blitCanvas = function(self, canvas, sx, sy, zl, zsx, zsy, bx, by, boxX, boxY, boxW, boxH, ...)
      if canvas == self.canvas and nBlits < 4 and queued > 0 then
        nBlits = nBlits + 1
        local t = blits[nBlits]
        t[1], t[2], t[3], t[4] = bx or 0, by or 0, sx or 1, sy or sx or 1
        t[5], t[6], t[7], t[8] = boxX or 0, boxY or 0, boxW or 0, boxH or 0
      end
      return blitCanvas(self, canvas, sx, sy, zl, zsx, zsy, bx, by, boxX, boxY, boxW, boxH, ...)
    end
  end
  state.queued = function() return queued end         -- (tests: this frame's queue)
  -- render.hud (main.lua's hook): this frame's queued chips, then the queue and notes cleared
  state.hud = function()
    if queued > 0 then
      local ex = state.view()
      local okM, map = false, nil
      if ex then okM, map = pcall(ex.uiMap) end
      if not okM then map = nil end
      if map or nBlits > 0 then
        local okD, err = pcall(StatHints.drawQueue, map, blits, nBlits)
        if not okD and opts.log and not state.warned then
          state.warned = true
          opts.log:warn("stat hint draw failed: %s", tostring(err))
        end
      end
    end
    queued, nBlits = 0, 0
  end

  local image = StatHints.cache()
  local inside, boxX, boxY, boxSide, boxDoubles, boxImg, boxId = 0, nil, nil, nil, false, nil, nil
  -- a doubles box's partner (the same side's other box, the same picture), from Healthbox.CENTERS
  local partnerT = { x = 0, y = 0 }
  local function partnerOf(s)
    local centers = boxId and Healthbox.CENTERS and Healthbox.CENTERS[true]
    local me, other = centers and centers[boxId], centers and centers[(boxId + 2) % 4]
    if not (me and other) then return nil end
    partnerT.s, partnerT.x, partnerT.y = s, other.x - me.x, other.y - me.y
    return partnerT
  end
  -- the picture on BattleChrome as the box draws (a mod's set swaps it in for the draw, whichever
  -- side of our wraps it is); measured once each, the game's own keeps FRAME
  local FIELD = { enemy = "_enemyBox", player = "_playerBox",
    doublesEnemy = "_doublesOpponentBox", doublesPlayer = "_doublesPlayerBox" }
  local function note(side, x, y, doubles, field)
    if inside == 0 then return end
    boxSide, boxX, boxY, boxDoubles = side, x, y, doubles
    boxImg = Chrome[field]
  end
  local drawEnemyBox, drawPlayerBox, drawDoublesBox = Chrome.drawEnemyBox, Chrome.drawPlayerBox, Chrome.drawDoublesBox
  Chrome.drawEnemyBox = function(x, y, ...) note("enemy", x, y, false, FIELD.enemy) return drawEnemyBox(x, y, ...) end
  Chrome.drawPlayerBox = function(x, y, ...) note("player", x, y, false, FIELD.player) return drawPlayerBox(x, y, ...) end
  if type(drawDoublesBox) == "function" then
    Chrome.drawDoublesBox = function(isPlayer, x, y, ...)
      note(isPlayer and "player" or "enemy", x, y, true, isPlayer and FIELD.doublesPlayer or FIELD.doublesEnemy)
      return drawDoublesBox(isPlayer, x, y, ...)
    end
  end

  -- one chip (state.drawChip: the seam tests watch): queued at window resolution, or drawn now
  state.drawChip = function(text, up, x, y, w, h)
    if state.hiNow then return StatHints.enqueue(text, up, x, y, w, h) end
    local img = image(text, up)
    if img then love.graphics.draw(img, x, y) end
  end
  -- where a box's chips go (into `out`, one table for every frame); img: another mod's box picture
  function state.spot(side, x, y, doubles, out, img)
    out = out or {}
    local Shape = state.shape
    local s = img and Shape and Shape.of(img)
    if s and not Shape.likeGame(s, StatHints.BADGE.edges[side], side)
      and StatHints.spotByShape(Shape, s, side, x, y, doubles, out, doubles and partnerOf(s) or nil) then
      return out
    end
    local F = StatHints.FRAME
    if doubles then
      local D = F.doubles
      out.mode, out.split, out.right = "column", StatHints.SPLIT, StatHints.SCREEN_W
      out.y, out.limit = StatHints.doublesBand(side, y)
      if side == "enemy" then
        out.x, out.dir = x + D.enemyRight + StatHints.BADGES, 1
      else
        out.x, out.dir = x + D.playerLeft - StatHints.BADGES, -1
      end
      return out
    end
    if side == "enemy" then
      local e = F.enemy
      out.mode, out.x, out.y, out.limit, out.dir = "down", x + e.left, y + e.bottom + 2, e.rows, 1
      out.split, out.right = StatHints.SPLIT, StatHints.SCREEN_W
      return out
    end
    local p = F.player
    -- (from y + 3: a foe's third row of chips ends on y + 2)
    out.mode, out.x, out.y, out.dir = "column", x + p.left - StatHints.BADGES, y + 3, -1
    out.limit = math.min(p.bottom - 3, StatHints.TEXT_TOP - out.y)
    out.split, out.right = StatHints.SPLIT, StatHints.SCREEN_W
    return out
  end
  local spotT = {}

  local chips = {}
  local function stageOf(battler, k)
    local s = battler.stages
    return type(s) == "table" and s[k] or 0
  end
  local spotNow, chipsNow
  local function place(i, x, y, w, h) state.drawChip(chipsNow[i].text, chipsNow[i].up, x, y, w, h) end
  local function drawChips(battler)
    if not (boxX and type(battler) == "table") then return end
    local okOn, on = pcall(state.enabled)
    if okOn and on == false then return end
    chipsNow = StatHints.chips(stageOf, battler, chips)
    if #chipsNow == 0 then return end
    spotNow = state.spot(boxSide, boxX, boxY, boxDoubles, spotT, boxImg)
    state.hiNow = state.view() ~= nil
    if state.hiNow then
      StatHints.layout(chipsNow, spotNow, place, StatHints.HI)
      return
    end
    if love and love.graphics and love.graphics.setColor then love.graphics.setColor(1, 1, 1, 1) end
    StatHints.layout(chipsNow, spotNow, place, StatHints.PIXEL)
  end

  local draw = Healthbox.draw
  Healthbox.draw = function(side, battler, o, ...)
    if inside == 0 then boxId = type(side) == "number" and side or nil end
    inside = inside + 1
    boxX, boxImg = nil, nil
    local ok, a, b = pcall(draw, side, battler, o, ...)
    inside = inside - 1
    if not ok then error(a, 0) end
    if inside == 0 and boxX then
      local okD, err = pcall(drawChips, battler)
      if not okD and opts.log and not state.warned then
        state.warned = true
        opts.log:warn("stat hint draw failed: %s", tostring(err))
      end
      boxX = nil
    end
    return a, b
  end
  return state
end

return StatHints
