-- Custom move animations on Gen 1 / Gen 2: the pixelfx effects of the Gen 3 path (data/fx.lua and
-- assets/fx/atlas.png, tools/build_fx.mjs; pixelfx is MIT, credited in README / CREDITS / LICENSE)
-- for the newer moves that have one (Aura Sphere, Dark Pulse, Flash Cannon, Night Slash...), in
-- place of the cart move's animation they borrow.
--
-- Neither game can run a mod's code inside a move animation, so each move gets an animation that
-- only takes the effect's time (the game waits for it, then plays the hit, and skips it with
-- animations off) and starts with the borrowed move's sound:
--   Red   a battle_anims record of SE_DELAY_ANIMATION_10 rows (10 frames each; the first carries
--         the move's own sound, the borrowed move's)
--   Gold  a script of its own ("ndx:<move>": the borrowed script's first sound, then a wait),
--         which the move's entry in `moves` names
-- and the effect itself is drawn from the battle.overlay hook while that animation plays (Red:
-- animPlaying / animName / animPlayer.elapsed; Gold: anim.animId / anim.frames), over the
-- pictures and under the text box, at three quarters of its Gen 3 size (these screens are smaller).
--
-- data/fx.lua's labels are Gen 3 animation scripts; only their NdxFx tasks, delays and waits are
-- read here (Fx.timeline): each task { sheet, mode, dx, dy, frames, flags, ramp } starts at its time
-- and plays its frames, tasks started together run together, and waitforvisualfinish waits for
-- them. The colours: a gradient-map shader onto the task's ramp (the same as Gen 3's), or the
-- ramp's bright step as a tint without shaders; Red's four-shade palettes (OG, CLASSIC) then shade
-- them as they do everything else.

local Fx = {}

Fx.SCALE = 0.75
Fx.FEET = 18                     -- a battler's feet below its centre, at this scale
-- the battlers' centres (classic 160 x 144 layout): the foe's front picture and your back one
Fx.CENTRE = {
  [1] = { player = { 36, 68 }, enemy = { 124, 28 } },
  [2] = { player = { 40, 72 }, enemy = { 124, 28 } },
}
Fx.TEXT_TOP = 96                 -- the text box starts here: nothing is drawn below it

local MODE_ATTACKER, MODE_TRAVEL, MODE_BEAM = 0, 2, 3
local FLAG_GROUND, FLAG_AIM = 1, 2

-- a label's parts in time: { length, parts = { { start, life, sheet, mode, dx, dy, flags, ramp } } }
function Fx.timeline(label, sheets)
  local t, groupEnd, parts = 0, 0, {}
  for _, op in ipairs(label or {}) do
    if op.op == "createvisualtask" and op.task == "NdxFx" then
      local a = op.args or {}
      local name = tostring(a[1] or ""):gsub("^FX:", "")
      local sheet = sheets[name]
      if sheet then
        local frames = tonumber(a[5]) or 0
        local life = frames > 0 and frames or math.ceil(sheet.frames * 60 / sheet.fps)
        parts[#parts + 1] = { start = t, life = life, name = name, sheet = sheet, mode = tonumber(a[2]) or 1,
          dx = tonumber(a[3]) or 0, dy = tonumber(a[4]) or 0, flags = tonumber(a[6]) or 0,
          ramp = type(a[7]) == "string" and a[7]:gsub("^FX:", "") or sheet.ramp }
        groupEnd = math.max(groupEnd, t + life)
      end
    elseif op.op == "waitforvisualfinish" then
      t = math.max(t, groupEnd)
    elseif op.op == "delay" then
      t = t + (tonumber(op.frames) or 0)
    end
  end
  return { length = math.max(t, groupEnd), parts = parts }
end

-- opts: { mod, generation, data (data/fx.lua), looks ({ [move id] = the cart move it borrows }),
-- log }. At load: the timing animations. Returns { lines = { [move id] = timeline }, count }.
function Fx.register(opts)
  local mod, gen, data = opts.mod, opts.generation, opts.data
  local anims, moves = mod.content.battle_anims, mod.content.moves
  local out = { lines = {}, count = 0 }
  if not (anims and type(data) == "table" and type(data.moves) == "table") then return out end
  local goldScripts = nil
  if gen == 2 then
    local ok, base = pcall(anims.get, anims, "moves")
    goldScripts = ok and type(base) == "table" and base or nil
  end
  local addScripts, addMoves = {}, {}
  for id, labelName in pairs(data.moves) do
    local label = data.labels and data.labels[labelName]
    if moves:get(id) ~= nil and label then
      local line = Fx.timeline(label, data.sheets or {})
      if #line.parts > 0 and line.length > 0 then
        local ok = true
        if gen == 1 then
          local seq = {}
          for i = 1, math.max(1, math.ceil(line.length / 10)) do
            seq[i] = { effect = "SE_DELAY_ANIMATION_10" }
          end
          seq[1].sound = id                          -- the move's own sound (its borrowed one)
          local rec = { seq = seq }
          if anims:get(id) ~= nil then
            ok = pcall(anims.override, anims, id, rec)
          else
            ok = pcall(anims.register, anims, id, rec)
          end
        else
          local rows = {}
          local look = opts.looks and opts.looks[id]
          local base = look and goldScripts and goldScripts[look]
          local okS, scripts = pcall(anims.get, anims, "scripts")
          local script = base and okS and type(scripts) == "table" and scripts[base]
          for _, row in ipairs(type(script) == "table" and script or {}) do
            if type(row) == "table" and row[1] == "sound" then rows[1] = { row[1], row[2], row[3] }; break end
          end
          rows[#rows + 1] = { "wait", line.length }
          rows[#rows + 1] = { "ret" }
          addScripts["ndx:" .. id] = rows
          addMoves[id] = "ndx:" .. id
        end
        if ok then out.lines[id] = line; out.count = out.count + 1 end
      end
    end
  end
  if gen == 2 and next(addMoves) then
    local okA = pcall(anims.patch, anims, "scripts", addScripts)
    local okB = okA and pcall(anims.patch, anims, "moves", addMoves)
    if not (okA and okB) then out.lines, out.count = {}, 0 end
  end
  return out
end

-- ------------------------------------------------------------------ drawing
local RAMP_SHADER = [[
#define GAMMA 1.5
extern Image ramp;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec4 p = Texel(tex, uv);
  vec3 c = Texel(ramp, vec2(pow(p.r, GAMMA) * 0.875 + 0.0625, 0.5)).rgb;
  return vec4(c, p.a) * color;
}
]]

-- opts: { generation, data (data/fx.lua), lines (Fx.register's), root (the mod's path), log }
-- Returns the battle.overlay hook body: fn(next, battle, ...).
function Fx.overlay(opts)
  local gen, data, lines = opts.generation, opts.data, opts.lines
  local hasLove = love and love.graphics and love.graphics.newImage and true or false
  local art
  local function getArt()
    if art ~= nil then return art end
    art = false
    if not hasLove then return art end
    local ok, img = pcall(love.graphics.newImage, opts.root .. "/" .. data.atlas.file)
    if not (ok and img) then
      if opts.log then opts.log:warn("could not load the move effects: %s", tostring(img)) end
      return art
    end
    pcall(img.setFilter, img, "nearest", "nearest")
    local iw, ih = img:getWidth(), img:getHeight()
    local a = { image = img, quads = {}, ramps = {}, tints = {} }
    for name, sheet in pairs(data.sheets) do
      local q, r = {}, sheet.rects or {}
      for i = 0, sheet.frames - 1 do
        local b = i * 6
        if (r[b + 3] or 0) > 0 then q[i] = love.graphics.newQuad(r[b + 1], r[b + 2], r[b + 3], r[b + 4], iw, ih) end
      end
      a.quads[name] = q
    end
    local okSh, sh = pcall(love.graphics.newShader, RAMP_SHADER)
    a.shader = okSh and sh or nil
    for name, ramp in pairs(data.ramps or {}) do
      local id = love.image.newImageData(8, 1)
      for i = 1, 8 do
        local h = tostring(ramp[i] or ramp[#ramp]):gsub("#", "")
        id:setPixel(i - 1, 0, tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255,
          tonumber(h:sub(5, 6), 16) / 255, 1)
      end
      local rimg = love.graphics.newImage(id)
      rimg:setFilter("linear", "linear")
      a.ramps[name] = rimg
      local r6, g6, b6 = id:getPixel(5, 0)
      a.tints[name] = { r6, g6, b6 }
    end
    art = a
    return art
  end

  local function flagged(flags, bit) return math.floor(flags / bit) % 2 == 1 end

  -- one part at frame `tick` of its own life
  local function drawPart(a, p, tick, playerAttacks)
    local sheet = p.sheet
    local i = math.floor(tick * sheet.fps / 60)
    if sheet.loop then i = i % sheet.frames elseif i >= sheet.frames then i = sheet.frames - 1 end
    local q = a.quads[p.name][i]
    if not q then return end
    local b = i * 6
    local ox, oy = sheet.rects[b + 5], sheet.rects[b + 6]
    local C = Fx.CENTRE[gen]
    local from = playerAttacks and C.player or C.enemy
    local to = playerAttacks and C.enemy or C.player
    local S = Fx.SCALE
    local dx, dy = p.dx * S, p.dy * S
    if not playerAttacks then dx = -dx end
    local feet = flagged(p.flags, FLAG_GROUND) and Fx.FEET or 0
    local ax, ay = from[1] + dx, from[2] + dy + feet
    local tx, ty = to[1] + dx, to[2] + dy + feet
    local vx, vy = tx - ax, ty - ay
    local rot, sx = 0, 1
    if flagged(p.flags, FLAG_AIM) or p.mode == MODE_BEAM then
      if vx < 0 then sx, rot = -1, math.atan2(-vy, -vx) else rot = math.atan2(vy, vx) end
    elseif not playerAttacks then
      sx = -1
    end
    local x, y = tx, ty
    if p.mode == MODE_ATTACKER then
      x, y = ax, ay
    elseif p.mode == MODE_TRAVEL then
      local u = p.life > 1 and math.min(1, tick / (p.life - 1)) or 1
      x, y = ax + vx * u, ay + vy * u
    elseif p.mode == MODE_BEAM then
      x, y = ax, ay
      sx = sx * math.sqrt(vx * vx + vy * vy) / ((tonumber(sheet.reach) or 100) * S)
    end
    local G = love.graphics
    local ramp = a.ramps[p.ramp]
    if a.shader and ramp then
      G.setShader(a.shader)
      a.shader:send("ramp", ramp)
      G.setColor(1, 1, 1, 1)
    else
      G.setShader()
      local tint = a.tints[p.ramp]
      if tint then G.setColor(tint[1], tint[2], tint[3], 1) else G.setColor(1, 1, 1, 1) end
    end
    G.draw(a.image, q, math.floor(x + 0.5), math.floor(y + 0.5), rot, sx * S, S, sheet.px - ox, sheet.py - oy)
  end

  -- what is playing now: move id, frame, whether the player attacks
  local function playing(b)
    if gen == 1 then
      if not (b.animPlaying and b.animName and lines[b.animName]) then return nil end
      if type(b.wideLayout) == "function" and b:wideLayout() then return nil end
      local p = b.animPlayer
      return b.animName, p and tonumber(p.elapsed) or 0, b.animAttackerIsPlayer and true or false
    end
    local anim = b.anim
    if not (anim and anim.animId and lines[anim.animId]) then return nil end
    if type(anim.done) == "function" and anim:done() then return nil end
    local env = anim.env or {}
    return anim.animId, tonumber(anim.frames) or 0, (env.battleTurn or 0) == 0
  end

  local state = { drawn = 0 }
  local function draw(b)
    local id, frame, playerAttacks = playing(b)
    if not id then return end
    state.last = id
    local a = getArt()
    if not a then return end
    local G = love.graphics
    G.push("all")
    -- (the scissor is in window pixels: Gold draws the battle through a scaled transform)
    local x1, y1 = G.transformPoint(0, 0)
    local x2, y2 = G.transformPoint(160, Fx.TEXT_TOP)
    G.intersectScissor(math.min(x1, x2), math.min(y1, y2), math.abs(x2 - x1), math.abs(y2 - y1))
    G.setBlendMode("alpha", "alphamultiply")
    for _, p in ipairs(lines[id].parts) do
      local tick = frame - p.start
      if tick >= 0 and tick < p.life then drawPart(a, p, tick, playerAttacks) end
    end
    G.pop()
    state.drawn = state.drawn + 1
  end
  local function hook(next, b, ...)
    local r = next(b, ...)
    if type(b) == "table" then
      local ok, err = pcall(draw, b)
      if not ok and opts.log and not state.warned then
        state.warned = true
        opts.log:warn("a move effect failed to draw: %s", tostring(err))
      end
    end
    return r
  end
  return hook, state, playing
end

return Fx
