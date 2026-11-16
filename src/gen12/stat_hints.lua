-- Stat Hints on Gen 1 / Gen 2 (option stat_hints): src/stat_hints.lua's chips (loaded as it is) by
-- the battle HUDs, read every time a HUD is drawn from the battler's stages as the mechanics layer
-- keeps them (src/gen12/battle/red.lua / gold.lua A:stage: Red's Sp. Def stage is ours), so they
-- follow every move as it happens.
--
-- Where (160 x 144; no doubles on these games):
--   the foe's  under its HUD: name, level, HP bar and the underline fill rows 0-31 (x 8-87); the
--              chips start on row 33 at x 8, wrapping downward
--   yours      its HUD runs from row 56 to its underline at 88-95 and the text box starts at 96:
--              nothing fits under it, so the chips sit just above it (rows 47-55), ending at its
--              right edge and growing leftward, 64 wide (clear of the foe's chips, which end at
--              x 88), further rows above
-- Red's wide layout (WideBattle's panels) the same by its panels. Drawn as the type badges are
-- (src/gen12/type_badges.lua): Red with the HUDs (drawHUDs, and after the coloured path's
-- drawZonePass), or from battle.overlay for the wide layout; Gold after drawEnemyHud /
-- drawPlayerHud.
local Hints = {}

Hints.CLASSIC = {
  enemy = { mode = "down", x = 8, y = 33, limit = 80 },
  player = { mode = "left", x = 152, y = 47, limit = 64 },
}
Hints.WIDE1 = {
  enemy = { mode = "down", x = 2, y = 34, limit = 126 },
  player = { mode = "left", x = 304, y = 47, limit = 128 },
}

-- opts: { require, generation, core (src/stat_hints.lua), stage = fn(battle, battler, key) ->
-- stage, enabled = fn() -> bool, data, log }. Returns the state (state.overlay: Red's hook body).
function Hints.install(opts)
  local require, gen, SH = opts.require, opts.generation, opts.core
  local state = { enabled = opts.enabled or function() return true end, log = opts.log, data = opts.data }
  local image = SH.cache()
  state.drawChip = function(text, up, x, y)
    local img = image(text, up)
    if img then love.graphics.draw(img, x, y) end
  end
  local function on()
    local ok, v = pcall(state.enabled)
    return not ok or v ~= false
  end
  -- one context and one chip list for every frame (nothing made per draw)
  local ctx, chips = {}, {}
  local function get(c, key)
    local ok, v = pcall(opts.stage, c.battle, c.battler, key)
    return ok and v or 0
  end
  local current
  local function place(i, x, y) state.drawChip(current[i].text, current[i].up, x, y) end
  local function drawFor(battle, battler, spot)
    ctx.battle, ctx.battler = battle, battler
    current = SH.chips(get, ctx, chips)
    if #current == 0 then return end
    local g = love and love.graphics
    local shader = g and g.getShader and g.getShader()
    if shader then g.setShader() end
    if g and g.setColor then g.setColor(1, 1, 1, 1) end
    SH.layout(current, spot, place)
    if shader then g.setShader(shader) end
  end
  local function safely(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and state.log and not state.warned then
      state.warned = true
      state.log:warn("stat hint draw failed: %s", tostring(err))
    end
  end

  if gen == 1 then
    -- the tests BattleState:drawHUDs makes before drawing each HUD (as the type badges ask)
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
    local function drawSides(b, spots, wide)
      if enemyShown(b, wide) then
        local shake = not wide and b.fx and b.fx.hudShakeX or 0
        if shake ~= 0 then love.graphics.push(); love.graphics.translate(shake, 0) end
        local ok, err = pcall(drawFor, b, b.enemy, spots.enemy)
        if shake ~= 0 then love.graphics.pop() end
        if not ok then error(err, 0) end
      end
      if playerShown(b) then drawFor(b, b.player, spots.player) end
    end
    local function ours(b)
      if type(b) ~= "table" or b.blankForAskName or b.blackoutBlank or not on() then return false end
      return not (state.data and b.data and b.data ~= state.data)
    end
    local okB, BS = pcall(require, "src.battle.BattleState")
    if okB and type(BS) == "table" and type(BS.drawHUDs) == "function"
      and type(BS.drawZonePass) == "function" then
      local hub = BS.__ndxStatHints
      if not hub then
        hub = {}
        BS.__ndxStatHints = hub
        local drawHUDs, drawZonePass = BS.drawHUDs, BS.drawZonePass
        BS.drawHUDs = function(self, slide, ...)
          local a, b = drawHUDs(self, slide, ...)
          if hub.hud then hub.safely(hub.hud, self, slide) end
          return a, b
        end
        BS.drawZonePass = function(self, src, sx, sy, ...)
          local a, b = drawZonePass(self, src, sx, sy, ...)
          if hub.zone then hub.safely(hub.zone, self, sx, sy) end
          return a, b
        end
      end
      function state.hud(b, slide)
        state.pending = nil
        if (slide or 0) ~= 0 or not ours(b) then return end
        local colour = type(b.colorMode) == "function" and b:colorMode()
        if colour then state.pending = b; return end
        drawSides(b, Hints.CLASSIC, false)
      end
      function state.zone(b, sx, sy)
        if state.pending ~= b then return end
        state.pending = nil
        local g = love.graphics
        local moved = (sx or 0) ~= 0 or (sy or 0) ~= 0
        if moved then g.push(); g.translate(sx or 0, sy or 0) end
        local ok, err = pcall(drawSides, b, Hints.CLASSIC, false)
        if moved then g.pop() end
        if not ok then error(err, 0) end
      end
      hub.hud, hub.zone, hub.safely, hub.state = state.hud, state.zone, safely, state
      state.classicWithBoxes = true
    end
    function state.overlay(b)
      if not ours(b) or type(b.drawHUDs) ~= "function" then return end
      local wide = type(b.wideLayout) == "function" and b:wideLayout()
      if not wide and state.classicWithBoxes then return end
      drawSides(b, wide and Hints.WIDE1 or Hints.CLASSIC, wide)
    end
    return state
  end

  -- Gold
  local okS, GS = pcall(require, "src.ui.gen2.BattleState")
  if not (okS and type(GS) == "table" and type(GS.drawEnemyHud) == "function"
    and type(GS.drawPlayerHud) == "function") then
    if opts.log then opts.log:warn("stat hints are off: the battle's HP boxes were not found") end
    return nil
  end
  local function after(self, side)
    if not on() then return end
    local data = self.data or (self.game and self.game.data)
    if state.data and data and data ~= state.data then return end
    local shown
    if side == "enemy" then shown = self.showEnemyHud else shown = self.showPlayerHud end
    if not (shown and self:statusHUDVisible() and not self:hudCleared(side)) then return end
    local mon = self:activeMon(side)
    if type(mon) ~= "table" or type(self.battle) ~= "table" then return end
    drawFor(self.battle, mon, Hints.CLASSIC[side])
  end
  local hub = GS.__ndxStatHints
  if not hub then
    hub = {}
    GS.__ndxStatHints = hub
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

-- Red: the battle.overlay hook body (state from Hints.install)
function Hints.overlayHook(state)
  return function(next, b, ...)
    local r = next(b, ...)
    local ok, err = pcall(state.overlay, b)
    if not ok and state.log and not state.warned then
      state.warned = true
      state.log:warn("stat hint draw failed: %s", tostring(err))
    end
    return r
  end
end

return Hints
