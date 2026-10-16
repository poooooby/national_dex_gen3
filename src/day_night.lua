-- The overworld by time of day (the "Day & Night" option): morning, afternoon (the game's own
-- look), evening and night, on outdoor maps of every Gen 3 game.
--
-- When: the time of day and whether the map is outdoors are decided when the player enters an
-- area (map.entered), on game start / load and when the option or the clock source changes,
-- never per frame. A warp switches at once (the screen is black); walking across a route
-- border eases over EASE seconds. The clock is src/clock.lua's (Clock Source; FireRed and
-- LeafGreen always the device).
--
-- Where: Gen 3 draws the world (tiles, people, weather, cave darkness) into the Renderer's world
-- canvas and the menus, text and HUD into its UI canvas; Renderer:endFrame blits the world with
-- Renderer:blitCanvas, then the UI. The grade goes on that world blit: the blit is drawn into a
-- scratch canvas and the scratch onto the screen through the shader. gen3-hd-sprites draws its
-- HD overworld sprites inside the same blit (its own blitCanvas wrap), so they are graded with
-- the world: this wrap must be the OUTERMOST, which endFrame re-checks every frame. Battles,
-- the Bag, the Pokedex and other full-screen menus have no world pass, so they are never graded.
-- Tilt mode draws the world without blitCanvas: there (and if the shader cannot compile) the
-- grade is a multiply + add overlay on the view, painted just before the UI blit.
local DayNight = {}

-- gain: per channel; sat: 1 = unchanged; lift: the shadow floor (black becomes this colour)
DayNight.PHASES = {
  morning = { gain = { 1.00, 0.96, 0.92 }, sat = 0.95, lift = { 0.02, 0.02, 0.03 } },
  afternoon = { gain = { 1, 1, 1 }, sat = 1, lift = { 0, 0, 0 } },
  evening = { gain = { 1.00, 0.86, 0.72 }, sat = 1.05, lift = { 0.03, 0.01, 0.02 } },
  night = { gain = { 0.62, 0.70, 0.92 }, sat = 0.70, lift = { 0.06, 0.07, 0.12 } },
}
-- map types that are outdoors: TOWN, CITY, ROUTE, UNDERWATER, OCEAN_ROUTE (field_moves.lua
-- MAP_TYPES); caves, indoors, secret bases and UNKNOWN keep the game's look
DayNight.OUTDOOR = { [1] = true, [2] = true, [3] = true, [5] = true, [6] = true }
DayNight.EASE = 1.0

local SHADER = [[
extern vec3 gain;
extern vec3 lift;
extern float sat;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec4 p = Texel(tex, uv);
  if (p.a <= 0.0) return p;
  vec3 c = p.rgb / p.a;
  c *= gain;
  float l = dot(c, vec3(0.299, 0.587, 0.114));
  c = mix(vec3(l), c, sat);
  c = clamp(lift + c * (1.0 - lift), 0.0, 1.0);
  return vec4(c * p.a, p.a) * color;
}
]]

-- the grade now, where an ease started from, where it goes
local cur = { gain = { 1, 1, 1 }, lift = { 0, 0, 0 }, sat = 1 }
local from = { gain = { 1, 1, 1 }, lift = { 0, 0, 0 }, sat = 1 }
local to = DayNight.PHASES.afternoon
local easeStart, easing = 0, false
local dirty = true

local opts = {}
local shader, shaderFailed = nil, false
local scratch, scratchW, scratchH, scratchDpi = nil, 0, 0, 0
local disabled = false
local graded = false                         -- the world blit was graded this frame
local busy = false                           -- inside our own grade (an inner copy of the wrap passes through)
local ourBlit, ourEndFrame

local function now()
  local t = love and love.timer and love.timer.getTime
  return t and t() or os.clock()
end

local function copy(dst, src)
  dst.gain[1], dst.gain[2], dst.gain[3] = src.gain[1], src.gain[2], src.gain[3]
  dst.lift[1], dst.lift[2], dst.lift[3] = src.lift[1], src.lift[2], src.lift[3]
  dst.sat = src.sat
end

local function identity(g)
  return g.gain[1] == 1 and g.gain[2] == 1 and g.gain[3] == 1 and g.sat == 1
    and g.lift[1] == 0 and g.lift[2] == 0 and g.lift[3] == 0
end

-- the phase name for a map: the clock's, outdoors with the option on; else "afternoon"
function DayNight.phaseFor(mapType, enabled, phase)
  if not enabled or not DayNight.OUTDOOR[tonumber(mapType) or -1] then return "afternoon" end
  return DayNight.PHASES[phase] and phase or "afternoon"
end

local function currentMapType()
  local okM, Map = pcall(opts.require or require, "src.core.game3.map")
  local def = okM and type(Map) == "table" and Map.currentDef and Map.currentDef()
  return type(def) == "table" and def.mapType or nil
end

-- re-decide the grade. ev: a map.entered payload ({ map = def, via }) or nil (the current map,
-- switched at once)
function DayNight.refresh(ev)
  local mapType = ev and type(ev.map) == "table" and ev.map.mapType
  if mapType == nil then mapType = currentMapType() end
  local okE, on = pcall(opts.enabled or function() return false end)
  local okP, phase = pcall(opts.phase or function() return "afternoon" end)
  local name = DayNight.phaseFor(mapType, okE and on, okP and phase)
  DayNight.current = name
  local target = DayNight.PHASES[name]
  if target == to and not easing then return name end
  to = target
  if ev and ev.via == "connection" and DayNight.EASE > 0 then
    copy(from, cur)
    easeStart, easing = now(), true
  else
    copy(cur, to)
    easing = false
  end
  dirty = true
  return name
end

-- advance an ease (once per frame, from endFrame)
function DayNight.step(t)
  if not easing then return end
  local k = ((t or now()) - easeStart) / DayNight.EASE
  if k >= 1 then
    copy(cur, to)
    easing = false
  else
    for i = 1, 3 do
      cur.gain[i] = from.gain[i] + (to.gain[i] - from.gain[i]) * k
      cur.lift[i] = from.lift[i] + (to.lift[i] - from.lift[i]) * k
    end
    cur.sat = from.sat + (to.sat - from.sat) * k
  end
  dirty = true
end

function DayNight.grade() return cur end

local function getShader(G)
  if shader or shaderFailed then return shader end
  local ok, s = pcall(G.newShader, SHADER)
  if ok and s then shader = s else
    shaderFailed = true
    if opts.log then opts.log:warn("day & night: the shader did not compile (%s); using a simple overlay", tostring(s)) end
  end
  return shader
end

local function sendGrade(s)
  if not dirty then return end
  s:send("gain", cur.gain)
  s:send("lift", cur.lift)
  s:send("sat", cur.sat)
  dirty = false
end

-- the world blit, drawn into the scratch canvas, then onto the target through the shader
local function gradeBlit(orig, self, canvas, ...)
  local G = love.graphics
  local s = getShader(G)
  if not s then return false end
  local target = G.getCanvas()
  local w, h, dpi
  if target then w, h, dpi = target:getWidth(), target:getHeight(), target:getDPIScale()
  else w, h = G.getDimensions(); dpi = G.getDPIScale() end
  if not scratch or w ~= scratchW or h ~= scratchH or dpi ~= scratchDpi then
    if scratch and scratch.release then scratch:release() end
    scratch = G.newCanvas(w, h, { dpiscale = dpi })
    scratchW, scratchH, scratchDpi = w, h, dpi
  end
  local sx, sy, sw, sh = G.getScissor()
  G.setCanvas(scratch)
  G.setScissor()
  G.clear(0, 0, 0, 0)
  if sx then G.setScissor(sx, sy, sw, sh) end
  busy = true
  local ok, err = pcall(orig, self, canvas, ...)
  busy = false
  G.setCanvas(target)
  if not ok then error(err, 0) end
  sendGrade(s)
  local prevShader = G.getShader()
  local mode, alphaMode = G.getBlendMode()
  local r, g, b, a = G.getColor()
  sx, sy, sw, sh = G.getScissor()
  G.push()
  G.origin()
  G.setScissor()
  G.setShader(s)
  G.setBlendMode("alpha", "premultiplied")
  G.setColor(1, 1, 1, 1)
  G.draw(scratch, 0, 0)
  G.pop()
  G.setShader(prevShader)
  G.setBlendMode(mode, alphaMode)
  G.setColor(r, g, b, a)
  if sx then G.setScissor(sx, sy, sw, sh) else G.setScissor() end
  return true
end

-- multiply + add over the view (tilt, or no shader): per channel, no saturation change
local function overlay(self)
  local G = love.graphics
  local okR, R = pcall(self.frameRects, self)
  if not (okR and type(R) == "table" and R.vuw) then return end
  local mode, alphaMode = G.getBlendMode()
  local r, g, b, a = G.getColor()
  local sx, sy, sw, sh = G.getScissor()
  G.setScissor(R.vux, R.vuy, R.vuw, R.vuh)
  local gn, l = cur.gain, cur.lift
  G.setBlendMode("multiply", "premultiplied")
  G.setColor(gn[1] * (1 - l[1]), gn[2] * (1 - l[2]), gn[3] * (1 - l[3]), 1)
  G.rectangle("fill", R.vux, R.vuy, R.vuw, R.vuh)
  G.setBlendMode("add", "premultiplied")
  G.setColor(l[1], l[2], l[3], 1)
  G.rectangle("fill", R.vux, R.vuy, R.vuw, R.vuh)
  G.setBlendMode(mode, alphaMode)
  G.setColor(r, g, b, a)
  if sx then G.setScissor(sx, sy, sw, sh) else G.setScissor() end
end

local function fail(err)
  disabled = true
  if opts.log then opts.log:warn("day & night is off for this session: %s", tostring(err)) end
end

local function makeBlit(Renderer, orig)
  return function(self, canvas, ...)
    if busy or disabled or identity(cur) or not (love and love.graphics) then return orig(self, canvas, ...) end
    if canvas == self.worldCanvas and self.worldActive and not self.worldOverride then
      local ok, done = pcall(gradeBlit, orig, self, canvas, ...)
      if ok and done then graded = true return end
      if not ok then fail(done) end
      return orig(self, canvas, ...)
    end
    if canvas == self.canvas and self.worldActive and not self.worldOverride and not graded then
      local ok, err = pcall(overlay, self)
      if not ok then fail(err) end
      graded = true
    end
    return orig(self, canvas, ...)
  end
end

-- keep our blitCanvas wrap outermost (a mod wrapping it later would draw outside the grade)
local wraps = 0
local function ensureOutermost(Renderer)
  if Renderer.blitCanvas == ourBlit or wraps >= 8 then return end
  wraps = wraps + 1
  ourBlit = makeBlit(Renderer, Renderer.blitCanvas)
  Renderer.blitCanvas = ourBlit
end

-- opts: { require, log, enabled = fn() -> bool, phase = fn() -> phase name }
function DayNight.install(o)
  opts = o or {}
  local okR, Renderer = pcall(opts.require or require, "src.render.Renderer")
  if not (okR and type(Renderer) == "table" and type(Renderer.blitCanvas) == "function"
      and type(Renderer.endFrame) == "function") then
    if opts.log then opts.log:warn("day & night is off: the renderer was not found") end
    return false
  end
  ensureOutermost(Renderer)
  if Renderer.endFrame ~= ourEndFrame and not Renderer.__nationalDexDayNight then
    Renderer.__nationalDexDayNight = true
    local endFrame = Renderer.endFrame
    ourEndFrame = function(self, ...)
      graded = false
      if not disabled then
        ensureOutermost(Renderer)
        DayNight.step()
      end
      return endFrame(self, ...)
    end
    Renderer.endFrame = ourEndFrame
  end
  DayNight.refresh(nil)
  if opts.log then opts.log:info("day & night: %s", tostring(DayNight.current)) end
  return true
end

return DayNight
