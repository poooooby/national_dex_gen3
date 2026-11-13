-- Shiny Pokemon on Red / Blue / Yellow. The engine already decides it by Gold's rule from the DVs
-- (Stats.isShiny: Defense, Speed and Special 10, Attack 2/3/6/7/10/11/14/15, about 1 in 8,192) and
-- hands `shiny` to the pokemon.sprite hook, so a sprite mod can draw shiny art. What this adds:
--   * a sparkle around a shiny Pokemon's picture as it comes out in battle (the battle.overlay
--     hook: four-point stars that spread from the picture's middle and fade, about 0.8 s; the
--     classic layout only)
--   * a star on its summary (src/gen12/summary.lua asks ShinyRed.isShiny)
-- No palette changes: Red's colours are per species, and the mod ships no shiny palettes.

local ShinyRed = {}

ShinyRed.FRAMES = 48
-- the pictures' middles in the 160x144 battle: the foe's 7x7 slot at (12,0), yours at (1,5) 2x
ShinyRed.CENTER = { enemy = { 124, 28 }, player = { 40, 66 } }
-- the stars' directions (x, y) and how far they travel
ShinyRed.RAYS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0.7, -0.7 }, { 0.7, 0.7 }, { -0.7, 0.7 }, { -0.7, -0.7 } }
ShinyRed.REACH = 26

function ShinyRed.isShiny(require, mon)
  if type(mon) ~= "table" or type(mon.dvs) ~= "table" then return false end
  local ok, Stats = pcall(require, "src.pokemon.Stats")
  return ok and Stats.isShiny and Stats.isShiny(mon.dvs) or false
end

-- a 7x7 four-point star with its middle at (x, y), size 1 (a dot) to 3
function ShinyRed.star(x, y, size)
  local g = love.graphics
  x, y = math.floor(x), math.floor(y)
  g.rectangle("fill", x - size, y, size * 2 + 1, 1)
  g.rectangle("fill", x, y - size, 1, size * 2 + 1)
  if size >= 2 then g.rectangle("fill", x - 1, y - 1, 3, 3) end
end

-- opts: { mod, require }
function ShinyRed.install(opts)
  local mod, require = opts.mod, opts.require
  local function visible(battle, side)
    local b = battle[side]
    if not (b and b.sprite and b.mon) or battle.fieldCleared then return false end
    if side == "enemy" then
      if battle.showEnemyTrainer or battle.enemyHidden or battle.enemySendingOut then return false end
    else
      if battle.showPlayerBack or battle.sendingOut or battle.safari or battle.demo then return false end
    end
    local ok, grow = pcall(battle.growInScale, battle, b)
    return not (ok and grow)
  end
  mod.hooks:wrap("battle.overlay", function(nextFn, battle, ...)
    local r = nextFn(battle, ...)
    if type(battle) ~= "table" or type(battle.drawPicsLayer) ~= "function" then return r end
    -- the wide layout puts the pictures elsewhere: the sparkle is the classic screen's
    if type(battle.wideLayout) == "function" then
      local okW, wide = pcall(battle.wideLayout, battle)
      if okW and wide then return r end
    end
    local st = rawget(battle, "__ndxShiny")
    if not st then st = { seen = setmetatable({}, { __mode = "k" }) }; battle.__ndxShiny = st end
    for side, c in pairs(ShinyRed.CENTER) do
      local b = battle[side]
      if b and visible(battle, side) then
        local f = st.seen[b]
        if f == nil then
          f = ShinyRed.isShiny(require, b.mon) and 0 or false
          st.seen[b] = f
        end
        if f and f < ShinyRed.FRAMES then
          st.seen[b] = f + 1
          local t = f / ShinyRed.FRAMES
          local g = love.graphics
          g.setColor(0.25, 0.25, 0.25, 1 - t * 0.6)
          for i, ray in ipairs(ShinyRed.RAYS) do
            local d = ShinyRed.REACH * t * (i > 4 and 0.75 or 1)
            local size = (f % 8 < 4) and 3 or 2
            if t > 0.75 then size = 1 end
            ShinyRed.star(c[1] + ray[1] * d, c[2] + ray[2] * d, size)
          end
          g.setColor(1, 1, 1, 1)
        end
      end
    end
    return r
  end)
end

return ShinyRed
