-- Stat Hints on Gen 1 / Gen 2 (option stat_hints): src/stat_hints.lua's chips (loaded as it is) by
-- the battle HUDs, read every time a HUD is drawn from the battler's stages as the mechanics layer
-- keeps them (src/gen12/battle/red.lua / gold.lua A:stage: Red's Sp. Def stage is ours), so they
-- follow every move. A change shows once the move that made it has finished playing, as on Gen 3
-- (src/stat_hints.lua "cause, then effect"): while the battle plays a turn back the chips read a
-- hold per side, taken when it last caught up. Red works each action out as its turn comes (a
-- queued row runs BattleState:executeAction, then its animation and lines play): the hold is taken
-- as each action and the end of the turn start. Gold works the whole turn out first: each move's
-- stages are read as Battle:useMove starts, kept on the first event it makes, and taken into the
-- hold when the screen reaches that event. Both catch up on every HUD drawn while nothing plays.
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
-- drawPlayerHud. A mod's Gen 3 box drawn in place of a HUD (Facets' BATTLE UI in wide battles) is
-- seen as the type badges see it (src/box_shape.lua, opts.shape): the foe's chips then start under
-- that box, yours end at its right edge just above it.
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
-- stage, enabled = fn() -> bool, data, log, shape = src/box_shape.lua (optional) }. Returns the
-- state (state.overlay: Red's hook body).
function Hints.install(opts)
  local require, gen, SH = opts.require, opts.generation, opts.core
  local state = { enabled = opts.enabled or function() return true end, log = opts.log, data = opts.data,
    shape = opts.shape }
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
  -- the hold (cause, then effect): one per side, with the battler it was taken for
  local hold = SH.holder()
  state.hold = hold
  local heldMon, hctx = {}, {}
  local function takeSide(battle, side, battler)
    if type(battler) ~= "table" then return end
    hctx.battle, hctx.battler = battle, battler
    hold.take(side, get, hctx)
    heldMon[side] = battler
  end
  state.takeSide = takeSide
  -- a stand-in Gold shows (a transformed mon's picture: its __index is the mon) is that mon
  local function under(m)
    local mt = type(m) == "table" and getmetatable(m)
    local i = type(mt) == "table" and rawget(mt, "__index")
    return type(i) == "table" and i or m
  end
  local function same(a, b)
    return a ~= nil and (rawequal(a, b) or rawequal(under(a), b) or rawequal(a, under(b)))
  end
  local function heldOf(side, key) return hold.read(side, key) end
  local current
  local function place(i, x, y) state.drawChip(current[i].text, current[i].up, x, y) end
  -- a mod's box for `side` drawn just now (Shape.seen): the spot by that box, else nil
  local boxSpot = { enemy = {}, player = {} }
  local function byBox(side, spot)
    local Shape = state.shape
    local seen = side and Shape and Shape.seen[side]
    local s = seen and seen.img and Shape.of(seen.img)
    if not s then return nil end
    local out = boxSpot[side]
    out.mode, out.limit = spot.mode, spot.limit
    if side == "enemy" then
      out.x, out.y = seen.x + s.minX, seen.y + s.bottom + 2
    else
      out.x, out.y = seen.x + s.maxX + 1, math.max(0, seen.y + s.top - SH.PIXEL.H - 1)
    end
    return out
  end
  -- who: the battler's side; playing: the battle is playing a turn back (read the hold)
  local function drawFor(battle, battler, spot, side, who, playing)
    if playing and who then
      if not same(heldMon[who], battler) then return end
      current = SH.chips(heldOf, who, chips)
    else
      if who then takeSide(battle, who, battler) end
      ctx.battle, ctx.battler = battle, battler
      current = SH.chips(get, ctx, chips)
    end
    if #current == 0 then return end
    spot = byBox(side, spot) or spot
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
    -- a mod's box for that side drawn this frame (it may hide the game's own through
    -- battle.status_hud_visible, as Facets' BATTLE UI does: the box is shown, as the mod's)
    local function modBox(side)
      local Shape = state.shape
      return Shape ~= nil and Shape.seen[side].img ~= nil
    end
    -- a turn playing back: a row queued, one running, or a move's animation
    local function playing(b)
      local q = b.queue
      return (type(q) == "table" and #q > 0) or b.current ~= nil or b.animPlaying == true
    end
    state.playing = playing
    -- boxed: from battle.overlay, where a mod's boxes were watched (wide)
    local function drawSides(b, spots, wide, boxed)
      local busy = playing(b)
      if enemyShown(b, wide) or (boxed and b.enemy and modBox("enemy")) then
        local shake = not wide and b.fx and b.fx.hudShakeX or 0
        if shake ~= 0 then love.graphics.push(); love.graphics.translate(shake, 0) end
        local ok, err = pcall(drawFor, b, b.enemy, spots.enemy, boxed and "enemy" or nil, "enemy", busy)
        if shake ~= 0 then love.graphics.pop() end
        if not ok then error(err, 0) end
      end
      if playerShown(b) or (boxed and b.player and modBox("player")) then
        drawFor(b, b.player, spots.player, boxed and "player" or nil, "player", busy)
      end
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
        -- the hold: as each action (its queued row running) and the end of the turn start
        for _, name in ipairs({ "executeAction", "endOfTurn" }) do
          local own = BS[name]
          if type(own) == "function" then
            BS[name] = function(self, ...)
              if hub.act then hub.safely(hub.act, self) end
              return own(self, ...)
            end
          end
        end
      end
      hub.act = function(b)
        if type(b) ~= "table" or (state.data and b.data and b.data ~= state.data) then return end
        takeSide(b, "enemy", b.enemy)
        takeSide(b, "player", b.player)
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
      drawSides(b, wide and Hints.WIDE1 or Hints.CLASSIC, wide, wide)
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
    drawFor(self.battle, mon, Hints.CLASSIC[side], side, side, self.phase == "resolving")
  end
  -- the hold on Gold: each move's stages read as Battle:useMove starts, kept on the first event it
  -- makes (weak: gone with the event), taken when the screen pops that event
  local marks = setmetatable({}, { __mode = "k" })
  state.marks = marks
  local function rawStage(t, key) return t[key] end
  local function before(battle)
    local snap = { enemyMon = battle.enemy, playerMon = battle.player, enemy = {}, player = {} }
    hctx.battle = battle
    for _, s in ipairs(SH.STATS) do
      local k = s.key
      hctx.battler = battle.enemy
      snap.enemy[k] = type(battle.enemy) == "table" and get(hctx, k) or 0
      hctx.battler = battle.player
      snap.player[k] = type(battle.player) == "table" and get(hctx, k) or 0
    end
    return snap
  end
  local function note(battle, mark, snap)
    local ev = type(battle.events) == "table" and battle.events[mark]
    if type(ev) == "table" and not marks[ev] then marks[ev] = snap end
  end
  local function popped(ui)
    local q = ui.queue
    local snap = type(q) == "table" and q[1] and marks[q[1]]
    if not snap then return end
    hold.take("enemy", rawStage, snap.enemy)
    heldMon.enemy = snap.enemyMon
    hold.take("player", rawStage, snap.player)
    heldMon.player = snap.playerMon
  end
  state.popped = popped
  local hub = GS.__ndxStatHints
  if not hub then
    hub = {}
    GS.__ndxStatHints = hub
    local drawEnemy, drawPlayer = GS.drawEnemyHud, GS.drawPlayerHud
    -- (a mod's box drawn inside is watched: hub.watch, src/box_shape.lua)
    GS.drawEnemyHud = function(self, ...)
      local a, b
      if hub.watch then a, b = hub.watch(drawEnemy, self, ...) else a, b = drawEnemy(self, ...) end
      if hub.after then hub.safely(hub.after, self, "enemy") end
      return a, b
    end
    GS.drawPlayerHud = function(self, ...)
      local a, b
      if hub.watch then a, b = hub.watch(drawPlayer, self, ...) else a, b = drawPlayer(self, ...) end
      if hub.after then hub.safely(hub.after, self, "player") end
      return a, b
    end
  end
  if type(GS.advanceQueue) == "function" and not hub.queueWrapped then
    hub.queueWrapped = true
    local advanceQueue = GS.advanceQueue
    GS.advanceQueue = function(self, ...)
      if hub.popped then hub.safely(hub.popped, self) end
      return advanceQueue(self, ...)
    end
  end
  local okG, Battle = pcall(require, "src.battle.gen2.Battle")
  if okG and type(Battle) == "table" and type(Battle.useMove) == "function" and not hub.moveWrapped then
    hub.moveWrapped = true
    local useMove, depth = Battle.useMove, 0
    Battle.useMove = function(self, ...)
      depth = depth + 1
      local mark = depth == 1 and type(self) == "table" and type(self.events) == "table" and #self.events + 1
      local snap
      if mark and hub.before then
        local okS, got = pcall(hub.before, self)
        if okS then snap = got end
      end
      local ok, a, b = pcall(useMove, self, ...)
      depth = depth - 1
      if snap and hub.note then pcall(hub.note, self, mark, snap) end
      if not ok then error(a, 0) end
      return a, b
    end
  end
  hub.after, hub.safely, hub.state = after, safely, state
  hub.popped, hub.before, hub.note = popped, before, note
  hub.watch = state.shape and state.shape.watch or nil
  return state
end

-- Red: the battle.overlay hook body (state from Hints.install)
function Hints.overlayHook(state)
  local watch = state.shape and state.shape.watch
  return function(next, b, ...)
    local r
    if watch then r = watch(next, b, ...) else r = next(b, ...) end
    local ok, err = pcall(state.overlay, b)
    if not ok and state.log and not state.warned then
      state.warned = true
      state.log:warn("stat hint draw failed: %s", tostring(err))
    end
    return r
  end
end

return Hints
