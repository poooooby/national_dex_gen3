-- Type badges on Gen 1 / Gen 2 (option type_badges): the Gen 3 badges' colours and symbols
-- (src/type_badges.lua, loaded as it is), 10 x 10 here: a darker rim round the 8 x 8 symbol, to
-- suit a 160 x 144 screen whose boxes leave little room. They show the battler's types as they are
-- now (Conversion, Transform).
--
-- Where: the one clear block between the two boxes (x 64-96, rows 28-56 on both games): a foe's
-- badges hang just under the underline at the right end of its box, yours sit on your name's line,
-- at the left end of your box; seven clear rows between the two.
--   Red   drawn from the battle.overlay hook (after the whole battle screen), only while the
--         game draws that box (the same tests as BattleState:drawHUDs); the wide layout puts
--         its panels elsewhere, and the badges follow them.
--   Gold  BattleState.drawEnemyHud / drawPlayerHud are wrapped (the game calls them through the
--         module, in every layout), and the badges are drawn right after the box when it was
--         drawn; what is drawn later (menus) covers them as it covers the boxes.
local Badges = {}

Badges.SIZE = 10
Badges.STEP = 11          -- one badge to the next, left to right
-- top left of the badges, and which way a row of them grows from it
Badges.CLASSIC = {
  enemy = { right = 88, y = 29 },     -- under the foe's box (x 8-88; its underline is row 27)
  player = { left = 72, y = 46 },     -- over your box (x 72-160, rows 56-96)
}
Badges.WIDE1 = {                      -- Red's wide layout (src/battle/WideBattle.lua panels)
  enemy = { right = 128, y = 33 },    -- the foe's panel: x 0-128, rows 0-32
  player = { left = 184, y = 46 },    -- yours: x 184-304, rows 56-96
}

-- type names of both games -> the Gen 3 badge ids (src/type_badges.lua COLORS / GLYPHS)
Badges.ID = {
  NORMAL = 0, FIGHTING = 1, FLYING = 2, BIRD = 2, POISON = 3, GROUND = 4, ROCK = 5, BUG = 6,
  GHOST = 7, STEEL = 8, CURSE = 9, FIRE = 10, WATER = 11, GRASS = 12, ELECTRIC = 13, PSYCHIC = 14,
  ICE = 15, DRAGON = 16, DARK = 17, FAIRY = 18,
}

function Badges.idOf(name)
  if type(name) ~= "string" then return nil end
  return Badges.ID[(name:upper():gsub("_TYPE$", ""))]
end

-- the badge ids to show for a list of type names: each once, ??? only alone
function Badges.ids(types)
  local out, seen = {}, {}
  for _, t in ipairs(type(types) == "table" and types or {}) do
    local id = Badges.idOf(t)
    if id and not seen[id] then seen[id] = true; out[#out + 1] = id end
  end
  if #out > 1 then
    for i = #out, 1, -1 do if out[i] == 9 then table.remove(out, i) end end
  end
  return out
end

-- the x of each badge in a row of n
function Badges.layout(spot, n)
  local xs = {}
  local x0 = spot.left or (spot.right - n * Badges.SIZE - (n - 1) * (Badges.STEP - Badges.SIZE))
  for i = 1, n do xs[i] = x0 + (i - 1) * Badges.STEP end
  return xs
end

function Badges.imageData(G, typeId)
  local color, glyph = G.COLORS[typeId], G.GLYPHS[typeId]
  if not (color and glyph) then return nil end
  local r = tonumber(color:sub(1, 2), 16) / 255
  local g = tonumber(color:sub(3, 4), 16) / 255
  local b = tonumber(color:sub(5, 6), 16) / 255
  local S = Badges.SIZE
  local d = love.image.newImageData(S, S)
  for y = 0, S - 1 do
    for x = 0, S - 1 do
      local edgeX, edgeY = x == 0 or x == S - 1, y == 0 or y == S - 1
      if not (edgeX and edgeY) then
        if edgeX or edgeY then d:setPixel(x, y, r * 0.55, g * 0.55, b * 0.55, 1)
        else d:setPixel(x, y, r, g, b, 1) end
      end
    end
  end
  for gy = 1, 8 do
    local row = glyph[gy]
    for gx = 1, 8 do
      if row:sub(gx, gx) == "#" then d:setPixel(gx, gy, 1, 1, 1, 1) end
    end
  end
  return d
end

-- opts: { require, generation, glyphs (src/type_badges.lua), enabled = fn() -> bool, data, log }
-- Returns the state (state.overlay: Red's hook body), or nil. Gold's wraps are made once per
-- process (games switch in-process) and ask the last install's state; `data` is that game's
-- data, so a later game without this mod draws none.
function Badges.install(opts)
  local require, gen = opts.require, opts.generation
  local G = opts.glyphs
  local state = { enabled = opts.enabled or function() return true end, log = opts.log,
    data = opts.data }
  local images = {}

  local function badge(t)
    local img = images[t]
    if img == nil then
      img = false
      if love and love.graphics and love.image and love.image.newImageData then
        local ok, made = pcall(function()
          local d = Badges.imageData(G, t)
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
  -- one badge (state.drawBadge: the seam tests watch)
  state.drawBadge = function(t, x, y)
    local img = badge(t)
    if img then love.graphics.draw(img, x, y) end
  end

  local function on()
    local ok, v = pcall(state.enabled)
    return not ok or v ~= false
  end
  local function drawRow(types, spot)
    local ids = Badges.ids(types)
    if #ids == 0 then return end
    local g = love and love.graphics
    local shader = g and g.getShader and g.getShader()
    if shader then g.setShader() end
    if g and g.setColor then g.setColor(1, 1, 1, 1) end
    for i, x in ipairs(Badges.layout(spot, #ids)) do state.drawBadge(ids[i], x, spot.y) end
    if shader then g.setShader(shader) end
  end
  local function safely(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and state.log and not state.warned then
      state.warned = true
      state.log:warn("type badge draw failed: %s", tostring(err))
    end
  end

  if gen == 1 then
    -- the tests BattleState:drawHUDs / WideBattle's drawHUDs make before drawing each box
    local function enemyShown(b, wide)
      local e = b.enemy
      return not b.fieldCleared and b:statusHUDVisible() and e and not b.showEnemyTrainer
        and not b.enemySendingOut and (wide or not b.enemyHudPending)
        and not b:growInScale(e) and (b.introSlide or 0) == 0 and not b.introBalls
        and not e.fainted
    end
    local function playerShown(b)
      local p = b.player
      return not b.fieldCleared and b:statusHUDVisible() and p and not b.safari and not b.demo
        and not b.showPlayerBack and (b.introSlide or 0) == 0 and not p.fainted
    end
    local function typesOf(battler)
      return battler.curTypes or (battler.def and battler.def.types)
        or (battler.mon and battler.mon.types)
    end
    function state.overlay(b)
      if type(b) ~= "table" or type(b.drawHUDs) ~= "function" or b.blankForAskName
        or b.blackoutBlank or not on() then return end
      if state.data and b.data and b.data ~= state.data then return end
      local wide = type(b.wideLayout) == "function" and b:wideLayout()
      local spots = wide and Badges.WIDE1 or Badges.CLASSIC
      if enemyShown(b, wide) then drawRow(typesOf(b.enemy), spots.enemy) end
      if playerShown(b) then drawRow(typesOf(b.player), spots.player) end
    end
    return state
  end

  -- Gold
  local okS, GS = pcall(require, "src.ui.gen2.BattleState")
  if not (okS and type(GS) == "table" and type(GS.drawEnemyHud) == "function"
    and type(GS.drawPlayerHud) == "function") then
    if opts.log then opts.log:warn("type badges are off: the battle's HP boxes were not found") end
    return nil
  end
  local function typesOf(self, mon)
    local battle = self.battle
    if battle and type(battle.battlerTypes) == "function" then
      local ok, t = pcall(battle.battlerTypes, battle, mon)
      if ok and type(t) == "table" then return t end
    end
    return mon.types
  end
  local function after(self, side)
    if not on() then return end
    local data = self.data or (self.game and self.game.data)
    if state.data and data and data ~= state.data then return end
    local shown
    if side == "enemy" then shown = self.showEnemyHud else shown = self.showPlayerHud end
    if not (shown and self:statusHUDVisible() and not self:hudCleared(side)) then return end
    local mon = self:activeMon(side)
    if type(mon) ~= "table" then return end
    drawRow(typesOf(self, mon), Badges.CLASSIC[side])
  end
  local hub = GS.__ndxBadges
  if not hub then
    hub = {}
    GS.__ndxBadges = hub
    local drawEnemy, drawPlayer = GS.drawEnemyHud, GS.drawPlayerHud
    GS.drawEnemyHud = function(self, ...)
      local a, b = drawEnemy(self, ...)
      if hub.after then hub.safely(hub.after, self, "enemy") end
      return a, b
    end
    GS.drawPlayerHud = function(self, ...)
      local a, b = drawPlayer(self, ...)
      if hub.after then hub.safely(hub.after, self, "player") end
      return a, b
    end
  end
  hub.after, hub.safely, hub.state = after, safely, state
  return state
end

-- Red: the battle.overlay hook body for mod.hooks:wrap (state from Badges.install)
function Badges.overlayHook(state)
  return function(next, b, ...)
    local r = next(b, ...)
    local ok, err = pcall(state.overlay, b)
    if not ok and state.log and not state.warned then
      state.warned = true
      state.log:warn("type badge draw failed: %s", tostring(err))
    end
    return r
  end
end

return Badges
