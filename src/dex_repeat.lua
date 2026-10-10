-- Fast scrolling: holding a direction in the Pokedex keeps moving, instead of one step per press.
-- Always on.
--
-- FireRed/LeafGreen's screen (src/ui/game3/pokedex.lua) moves only on a fresh press of each
-- direction. Ruby/Sapphire/Emerald's list already scrolls while Up/Down is held, as the cart
-- does, but its Left/Right page jumps and the entry pages' Up/Down step once per press. Both
-- screens read input through one public entry point (`Pokedex.handleInput`, `Pokedex.Host.handleInput`),
-- so this wraps that and hands the screen an input that also reports a held direction as newly
-- pressed on a repeat timer: after `DELAY` seconds, every `INTERVAL`, speeding up to every
-- `FAST_INTERVAL` once held for `FAST_AFTER`. Everything else about the input is passed through.
-- Installed after src/dex_patch.lua, which replaces the RSE screen's functions (and its Host).

local DexRepeat = {}

DexRepeat.DIRECTIONS = { "up", "down", "left", "right" }
DexRepeat.DELAY = 0.25
DexRepeat.INTERVAL = 0.07
DexRepeat.FAST_AFTER = 1.2
DexRepeat.FAST_INTERVAL = 0.03

local function now()
  local ok, t = pcall(function() return love.timer.getTime() end)
  if ok and type(t) == "number" then return t end
  return os.clock()
end

-- A per-screen tracker. step(input, t) -> a stand-in for `input` whose wasPressed(dir) is also
-- true on this call's repeat ticks; `t` (seconds) defaults to the clock.
function DexRepeat.tracker()
  local held = {}
  local tracker = {}
  function tracker.step(input, t)
    t = t or now()
    local fire = {}
    for _, dir in ipairs(DexRepeat.DIRECTIONS) do
      local down = false
      if type(input) == "table" and type(input.isDown) == "function" then
        local ok, v = pcall(input.isDown, input, dir)
        down = ok and v == true
      end
      if not down then
        held[dir] = nil
      elseif not held[dir] then
        held[dir] = { start = t, nextAt = t + DexRepeat.DELAY }
      elseif t >= held[dir].nextAt then
        fire[dir] = true
        local fast = t - held[dir].start >= DexRepeat.FAST_AFTER
        held[dir].nextAt = t + (fast and DexRepeat.FAST_INTERVAL or DexRepeat.INTERVAL)
      end
    end
    if not next(fire) then return input end
    return setmetatable({
      wasPressed = function(_, key)
        if fire[key] then return true end
        return input:wasPressed(key)
      end,
    }, { __index = input })
  end
  return tracker
end

-- Wrapped once per module table (engine modules outlive a mod reload).
local function wrap(module, name)
  if type(module) ~= "table" or type(module[name]) ~= "function" then return false end
  module.__nationalDexRepeat = module.__nationalDexRepeat or {}
  if module.__nationalDexRepeat[name] then return true end
  module.__nationalDexRepeat[name] = true
  local original = module[name]
  local tracker = DexRepeat.tracker()
  module[name] = function(input, ...)
    local ok, stepped = pcall(tracker.step, input)
    if ok then return original(stepped, ...) end
    return original(input, ...)
  end
  return true
end

-- require: the mod's
function DexRepeat.install(require)
  require = require or _G.require
  local okF, frlg = pcall(require, "src.ui.game3.pokedex")
  if okF then wrap(frlg, "handleInput") end
  local okR, rse = pcall(require, "src.ui.game3.rse.pokedex")
  if okR and type(rse) == "table" then wrap(rse.Host, "handleInput") end
end

return DexRepeat
