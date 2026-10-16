-- Standalone: luajit mods/national_dex_gen3/tests/day_night_test.lua (from the gen1recomp root;
-- needs Pokemon FireRed imported under firered/).
--
-- The Day & Night look (src/day_night.lua, src/clock.lua, the day_night option): which time of
-- day an hour is, which maps are graded, that the grade is decided on entering an area (eased on
-- a walking route change, at once on a warp), and the draw seam -- the world blit goes through a
-- scratch canvas and the shader, the UI blit is untouched, the wrap stays outermost when another
-- mod wraps blitCanvas later, and battles (no world pass) are never graded. love.graphics and
-- the Renderer are stubs: this runs without a window.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")

-- ------- the option

local data = H.gen3Data()
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local row
for _, r in ipairs(run.loader.optionSchemas.national_dex_gen3 or {}) do
  if r.key == "day_night" then row = r end
end
T.check(row ~= nil and row.type == "toggle", "the mod defines a day_night toggle")
T.check(row and #row.label <= 14, "its label fits the Mod Manager (14 characters)")
T.eq(row and row.default, true, "on by default")

-- ------- the hours

local Clock = dofile("mods/national_dex_gen3/src/clock.lua")
local bands = {
  [0] = "night", [3] = "night", [4] = "morning", [9] = "morning", [10] = "afternoon",
  [16] = "afternoon", [17] = "evening", [19] = "evening", [20] = "night", [23] = "night",
}
for hour, want in pairs(bands) do
  T.eq(Clock.phaseOf(hour), want, string.format("%02d:00 is %s", hour, want))
end
for h = 0, 23 do
  if (Clock.phaseOf(h) == "night") ~= (h >= 20 or h < 4) then T.check(false, "night matches isNight at " .. h) end
end
local Rtc = require("src.core.game3.rtc")
do
  local enabled, calc, host = Rtc.enabled, Rtc.calcLocalTime, Rtc.hostInfo
  Rtc.enabled = function() return true end
  Rtc.calcLocalTime = function() return { hours = 21 } end
  Rtc.hostInfo = function() return { hour = 13 } end
  T.eq(Clock.phase({}, "game"), "night", "a cart clock at 21:00, Clock Source In-game: night")
  T.eq(Clock.phase({}, "device"), "afternoon", "the device at 13:00, Clock Source Device: afternoon")
  Rtc.enabled = function() return false end
  T.eq(Clock.phase({}, "game"), "afternoon", "no cart clock (FireRed): the device, whatever the source")
  Rtc.enabled, Rtc.calcLocalTime, Rtc.hostInfo = enabled, calc, host
end

-- ------- stubs: love.graphics records what is drawn; a Renderer with blitCanvas / endFrame

local log = {}
local function rec(...) log[#log + 1] = table.concat({ ... }, " ") end
local canvasTarget, shaderSet, sent = nil, nil, {}
local function newCanvas(name, w, h)
  return { name = name, getWidth = function() return w end, getHeight = function() return h end,
           getDPIScale = function() return 1 end }
end
local screenW, screenH = 960, 640
local shaderObj = { send = function(_, k, v) sent[k] = type(v) == "table" and { v[1], v[2], v[3] } or v end }
local timeNow = 100
love = {
  timer = { getTime = function() return timeNow end },
  graphics = {
    newShader = function() return shaderObj end,
    newCanvas = function(w, h) rec("newCanvas", w, h) return newCanvas("scratch", w, h) end,
    getCanvas = function() return canvasTarget end,
    setCanvas = function(c) canvasTarget = c rec("setCanvas", c and c.name or "screen") end,
    getDimensions = function() return screenW, screenH end,
    getDPIScale = function() return 1 end,
    getScissor = function() return nil end, setScissor = function() end,
    clear = function() rec("clear") end,
    getShader = function() return shaderSet end,
    setShader = function(s) shaderSet = s end,
    getBlendMode = function() return "alpha", "alphamultiply" end, setBlendMode = function(m) rec("blend", m) end,
    getColor = function() return 1, 1, 1, 1 end, setColor = function() end,
    push = function() end, pop = function() end, origin = function() end,
    draw = function(img) rec("draw", img.name, shaderSet and "shaded" or "plain", canvasTarget and canvasTarget.name or "screen") end,
    rectangle = function() rec("rect") end,
  },
}

local Renderer = { worldCanvas = newCanvas("world", 240, 160), canvas = newCanvas("ui", 240, 160), worldActive = true }
function Renderer:blitCanvas(canvas) love.graphics.draw(canvas) end
function Renderer:endFrame()
  if self.worldActive and not self.tilted then self:blitCanvas(self.worldCanvas) end
  self:blitCanvas(self.canvas)
end
function Renderer:frameRects() return { vux = 0, vuy = 0, vuw = screenW, vuh = screenH } end

local mapType, enabled, phase = 3, true, "night"
local stubs = {
  ["src.render.Renderer"] = Renderer,
  ["src.core.game3.map"] = { currentDef = function() return { mapType = mapType } end },
}
local DayNight = dofile("mods/national_dex_gen3/src/day_night.lua")
local function frame()
  log = {}
  Renderer:endFrame()
  return table.concat(log, "\n")
end

T.check(DayNight.install({ require = function(n) return stubs[n] or require(n) end,
  enabled = function() return enabled end, phase = function() return phase end }), "installs on the Renderer")
T.eq(DayNight.current, "night", "a route at night: the night grade")

-- ------- the draw seam

local f = frame()
T.check(f:find("setCanvas scratch", 1, true) and f:find("draw world plain scratch", 1, true),
  "the world blit is drawn into the scratch canvas")
T.check(f:find("draw scratch shaded screen", 1, true), "and the scratch onto the screen through the shader")
T.check(f:find("draw ui plain screen", 1, true), "the UI (menus, text) is drawn plain on top")
T.eq(sent.sat, DayNight.PHASES.night.sat, "the night saturation reaches the shader")
T.eq(sent.gain and sent.gain[3], DayNight.PHASES.night.gain[3], "and its gain")
T.check(not frame():find("newCanvas", 1, true), "the scratch canvas is made once, not every frame")

Renderer.worldActive = false
f = frame()
T.check(not f:find("scratch", 1, true) and not f:find("rect", 1, true), "a battle or full-screen menu (no world pass) is never graded")
Renderer.worldActive = true

-- another mod (gen3-hd-sprites) wraps blitCanvas after us: we go back on the outside
local inner = Renderer.blitCanvas
Renderer.blitCanvas = function(self, canvas, ...)
  if canvas == self.worldCanvas then rec("hd sprites", canvasTarget and canvasTarget.name or "screen") end
  return inner(self, canvas, ...)
end
f = frame()
T.check(f:find("hd sprites scratch", 1, true), "a later blitCanvas wrap (HD sprites) draws inside our grade")
local _, shadedCount = f:gsub("draw scratch shaded", "")
T.eq(shadedCount, 1, "and the world is graded once, not twice")

-- ------- when it changes: entering an area

mapType = 8
DayNight.refresh({ map = { mapType = 8 }, via = "warp" })
T.eq(DayNight.current, "afternoon", "indoors: the game's own look")
T.check(not frame():find("scratch", 1, true), "and nothing is graded")
for _, t in ipairs({ 4, 7, 9 }) do
  T.eq(DayNight.phaseFor(t, true, "night"), "afternoon", "map type " .. t .. " (cave / unknown / secret base) is never graded")
end
for _, t in ipairs({ 1, 2, 3, 5, 6 }) do
  T.eq(DayNight.phaseFor(t, true, "evening"), "evening", "map type " .. t .. " (outdoors) is graded")
end

phase = "evening"
DayNight.refresh({ map = { mapType = 3 }, via = "warp" })
T.eq(DayNight.grade().gain[3], DayNight.PHASES.evening.gain[3], "a warp switches at once")

phase = "night"
DayNight.refresh({ map = { mapType = 3 }, via = "connection" })
local g0 = DayNight.grade().gain[3]
T.eq(g0, DayNight.PHASES.evening.gain[3], "walking across a route border starts from the old grade")
timeNow = timeNow + DayNight.EASE / 2
DayNight.step()
local half = DayNight.grade().gain[3]
T.check(half > DayNight.PHASES.evening.gain[3] and half < DayNight.PHASES.night.gain[3], "eases halfway after half the time")
timeNow = timeNow + DayNight.EASE
DayNight.step()
T.eq(DayNight.grade().gain[3], DayNight.PHASES.night.gain[3], "and arrives")

phase = "afternoon"
DayNight.refresh({ map = { mapType = 3 }, via = "warp" })
T.check(not frame():find("scratch", 1, true), "afternoon is the game's own look: nothing extra is drawn")

mapType, phase, enabled = 3, "night", false
DayNight.refresh(nil)
T.eq(DayNight.current, "afternoon", "option off: the game's own look")
enabled = true
DayNight.refresh(nil)
T.eq(DayNight.current, "night", "option on again: back to the time of day")

-- the overlay (tilt draws the world without blitCanvas): multiply + add before the UI
Renderer.tilted = true
f = frame()
T.check(f:find("blend multiply", 1, true) and f:find("blend add", 1, true), "tilt: the world gets the overlay before the UI")
Renderer.tilted = nil

T.finish("national_dex_gen3 day & night")
