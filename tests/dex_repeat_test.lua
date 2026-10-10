-- Standalone: luajit mods/national_dex_gen3/tests/dex_repeat_test.lua (from the gen1recomp root).
--
-- src/dex_repeat.lua: holding a direction in the Pokedex repeats it -- nothing for DELAY, then a
-- press every INTERVAL, every FAST_INTERVAL once held FAST_AFTER -- and nothing else about the
-- input changes. Driven with a fake input and a fake clock.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

local here = (arg[0]:gsub("\\", "/"):match("^(.*)/") or ".")
local R = assert(loadfile(here .. "/../src/dex_repeat.lua"))()

local function fakeInput(down, pressed)
  return {
    state = down,
    isDown = function(self, k) return self.state[k] == true end,
    wasPressed = function(_, k) return pressed[k] == true end,
  }
end

-- hold Down for 3 seconds at 60 frames a second, counting the presses the screen sees
local function presses(seconds, key)
  local tracker = R.tracker()
  local count, first = 0, nil
  for frame = 0, math.floor(seconds * 60) do
    local t = frame / 60
    local seen = tracker.step(fakeInput({ [key] = true }, { [key] = frame == 0 }), t)
    if seen:wasPressed(key) then
      count = count + 1
      if frame > 0 and not first then first = t end
    end
  end
  return count, first
end

local count, first = presses(3, "down")
T.check(first ~= nil and first >= R.DELAY - 1e-9 and first < R.DELAY + 0.05,
  "the first repeat comes after the delay (" .. tostring(first) .. " s)")
T.check(count > 40, "held for 3 s, Down repeats many times (" .. count .. ")")
local slow = presses(R.FAST_AFTER, "left")
T.check(count - slow > (3 - R.FAST_AFTER) / R.INTERVAL, "and it speeds up the longer it is held")

-- a tap is one press, no repeat
local tracker = R.tracker()
local taps = 0
for frame = 0, 60 do
  local down = frame < 5
  local seen = tracker.step(fakeInput({ up = down }, { up = frame == 0 }), frame / 60)
  if seen:wasPressed("up") then taps = taps + 1 end
end
T.eq(taps, 1, "a short tap is one step")

-- other buttons and fields pass through
local input = fakeInput({ a = true }, { a = true })
local seen = R.tracker().step(input, 0)
T.eq(seen:wasPressed("a"), true, "A is passed through")
T.eq(seen:isDown("a"), true, "isDown is passed through")

-- install wraps both screens' entry points once, and the screen sees the repeats
local frlg = { calls = 0 }
frlg.handleInput = function(inp) frlg.calls = frlg.calls + 1; frlg.last = inp end
local rse = { Host = {} }
rse.Host.handleInput = function(inp) rse.last = inp end
local modules = { ["src.ui.game3.pokedex"] = frlg, ["src.ui.game3.rse.pokedex"] = rse }
local fakeRequire = function(name) return assert(modules[name]) end
R.install(fakeRequire)
local wrapped = frlg.handleInput
R.install(fakeRequire)
T.eq(frlg.handleInput, wrapped, "installed once per screen")
frlg.handleInput(fakeInput({}, { b = true }))
T.eq(frlg.calls, 1, "the screen's own handler still runs")
T.eq(frlg.last:wasPressed("b"), true, "with the input it was given")
rse.Host.handleInput(fakeInput({}, { start = true }))
T.eq(rse.last:wasPressed("start"), true, "Ruby/Sapphire/Emerald's Host is wrapped too")

T.finish("national_dex_gen3 dex repeat")
