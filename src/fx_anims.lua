-- Battle animations drawn with pixelfx (https://github.com/patch-gg/pixelfx, MIT): data/fx.lua and
-- assets/fx/atlas.png, built by tools/build_fx.mjs, for new moves whose pokeemerald-expansion script needs
-- graphics no Gen 3 cart has. Each move is an ordinary script (data/fx.lua's labels, merged into
-- data/anims.lua's by FxAnims.merge, so src/anims.lua resolves and plays it like the others), and its
-- pixelfx parts are one visual task of ours, "NdxFx", in the engine's task registry:
--
--   createvisualtask NdxFx { "FX:" .. sheet, mode, dx, dy, frames, flags, "FX:" .. ramp }
--     mode   0 on the attacker, 1 on the target (its centre + dx, dy; dx mirrored for the foe),
--            2 travelling from the attacker to the target, 3 a beam from the attacker stretched to it
--     frames how long it plays (60 a second); 0 = the sheet's own length
--     flags  1 on the battler's feet, 2 turned toward the target, 4 behind the battlers
--     ramp   the colours (data/fx.lua's ramps); none = the sheet's own
--
-- Every sheet is in one gray + alpha atlas, each frame trimmed to what it draws (`rects`). A shader maps
-- the gray onto the ramp (an 8 x 1 picture, blended between its steps), so the same orb is Aura Sphere's
-- blue and Focus Blast's orange; without shaders the gray is tinted by the ramp's bright step. The task
-- draws its frame itself (task.draw, at its z band) and ends when it has played, so waitforvisualfinish
-- waits for it. The atlas loads the first time a move plays; without it (headless, or a missing file) the
-- task still takes its time and the script plays as written.
local FxAnims = {}

local FEET = 24   -- a battler's feet below its centre

-- GAMMA: the grays bent toward the ramp's darker steps; the glow pixelfx adds on top lands near white,
-- and a straight mapping washes a beam's or a burst's colour out
local RAMP_SHADER = [[
#define GAMMA 1.5
extern Image ramp;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec4 p = Texel(tex, uv);
  vec3 c = Texel(ramp, vec2(pow(p.r, GAMMA) * 0.875 + 0.0625, 0.5)).rgb;
  return vec4(c, p.a) * color;
}
]]

-- data/fx.lua's moves and labels into data/anims.lua's (a move with an expansion script keeps it)
function FxAnims.merge(anims, fx)
  if type(anims) ~= "table" or type(fx) ~= "table" then return anims end
  anims.moves = anims.moves or {}
  anims.labels = anims.labels or {}
  for move, label in pairs(fx.moves or {}) do
    if not anims.moves[move] and fx.labels and fx.labels[label] then
      anims.moves[move] = label
      anims.labels[label] = fx.labels[label]
      if anims.looks then anims.looks[move] = nil end
    end
  end
  return anims
end

-- opts: { mod (for mod.path), data (data/fx.lua), require, log }
function FxAnims.install(opts)
  local require, log, data = opts.require, opts.log, opts.data
  if type(data) ~= "table" or type(data.sheets) ~= "table" or type(data.atlas) ~= "table" then return false end
  local okT, AnimTasks = pcall(require, "src.core.game3.battle.anim_tasks")
  local okS, AnimSprites = pcall(require, "src.core.game3.battle.anim_sprites")
  if not (okT and okS and type(AnimTasks) == "table" and type(AnimTasks.REGISTRY) == "table") then
    if log then log:warn("pixelfx move animations are off: the engine's animation tasks were not found") end
    return false
  end
  -- one task for the whole process (games switch in-process); a later install brings its own data
  local state = AnimTasks.__ndxFx
  if not state then
    state = {}
    AnimTasks.__ndxFx = state
  end
  if state.data ~= data then state.art = nil end
  state.data, state.root, state.log = data, opts.mod and opts.mod.path or "", log
  if state.task then
    AnimTasks.REGISTRY.NdxFx = state.task
    return true
  end

  local Z = AnimSprites.Z
  local hasLove = love and love.graphics and love.graphics.newImage and true or false
  local MODE_ATTACKER, MODE_TRAVEL, MODE_BEAM = 0, 2, 3
  local FLAG_GROUND, FLAG_AIM, FLAG_BACK = 1, 2, 4

  -- the atlas, a quad per frame of every sheet, the shader and the ramps' pictures, or false
  local function art()
    local a = state.art
    if a ~= nil then return a end
    a = false
    if hasLove then
      local d = state.data
      local ok, img = pcall(love.graphics.newImage, state.root .. "/" .. d.atlas.file)
      if ok and img then
        pcall(img.setFilter, img, "nearest", "nearest")
        local iw, ih = img:getWidth(), img:getHeight()
        a = { image = img, quads = {}, ramps = {}, tints = {} }
        for name, sheet in pairs(d.sheets) do
          local q, r = {}, sheet.rects or {}
          for i = 0, sheet.frames - 1 do
            local b = i * 6
            if (r[b + 3] or 0) > 0 then q[i] = love.graphics.newQuad(r[b + 1], r[b + 2], r[b + 3], r[b + 4], iw, ih) end
          end
          a.quads[name] = q
        end
        local okSh, sh = pcall(love.graphics.newShader, RAMP_SHADER)
        a.shader = okSh and sh or nil
        for name, ramp in pairs(d.ramps or {}) do
          local id = love.image.newImageData(8, 1)
          for i = 1, 8 do
            local h = tostring(ramp[i] or ramp[#ramp]):gsub("#", "")
            id:setPixel(i - 1, 0, tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255,
              tonumber(h:sub(5, 6), 16) / 255, 1)
          end
          local rimg = love.graphics.newImage(id)
          rimg:setFilter("linear", "linear")
          rimg:setWrap("clamp", "clamp")
          a.ramps[name] = rimg
          local r6, g6, b6 = id:getPixel(5, 0)
          a.tints[name] = { r6, g6, b6 }
        end
      elseif state.log then
        state.log:warn("could not load %s: %s", tostring(d.atlas.file), tostring(img))
      end
    end
    state.art = a
    return a
  end

  local function flagged(flags, bit) return math.floor(flags / bit) % 2 == 1 end

  local function frontZ(side, back)
    if side == "player" then return back and Z.PLAYER_BEHIND or Z.PLAYER_FRONT end
    return back and Z.ENEMY_BEHIND or Z.ENEMY_FRONT
  end

  local function draw(t, vm)
    local st = t._ndxFx
    if not st then return end
    local a = art()
    if not a then return end
    local sheet = st.sheet
    local i = math.floor(st.tick * sheet.fps / 60)
    if sheet.loop then i = i % sheet.frames elseif i >= sheet.frames then i = sheet.frames - 1 end
    local q = a.quads[st.name][i]
    if not q then return end
    local b = i * 6
    local ox, oy = sheet.rects[b + 5], sheet.rects[b + 6]
    local x, y = st.x, st.y
    if st.mode == MODE_TRAVEL then
      local u = st.life > 1 and st.tick / (st.life - 1) or 1
      if u > 1 then u = 1 end
      x, y = st.ax + (st.tx - st.ax) * u, st.ay + (st.ty - st.ay) * u
    end
    love.graphics.setBlendMode("alpha", "alphamultiply")
    local ramp = a.ramps[st.ramp]
    local prev = love.graphics.getShader()
    if a.shader and ramp then
      love.graphics.setShader(a.shader)
      a.shader:send("ramp", ramp)
      love.graphics.setColor(1, 1, 1, 1)
    else
      local tint = a.tints[st.ramp]
      if tint then love.graphics.setColor(tint[1], tint[2], tint[3], 1) else love.graphics.setColor(1, 1, 1, 1) end
    end
    love.graphics.draw(a.image, q, math.floor(x + 0.5), math.floor(y + 0.5), st.rot, st.sx, 1,
      sheet.px - ox, sheet.py - oy)
    love.graphics.setShader(prev)
    love.graphics.setColor(1, 1, 1, 1)
  end

  local function start(t, vm)
    local name = tostring(t.data[0] or ""):gsub("^FX:", "")
    local sheet = state.data.sheets[name]
    if not sheet then return nil end
    local mode = tonumber(t.data[1]) or 1
    local dx, dy = tonumber(t.data[2]) or 0, tonumber(t.data[3]) or 0
    local frames = tonumber(t.data[4]) or 0
    local flags = tonumber(t.data[5]) or 0
    local ramp = type(t.data[6]) == "string" and t.data[6]:gsub("^FX:", "") or sheet.ramp
    local st = { name = name, sheet = sheet, mode = mode, ramp = ramp, tick = 0, rot = 0, sx = 1 }
    st.life = frames > 0 and frames or math.ceil(sheet.frames * 60 / sheet.fps)
    local foe = vm.isReversed and true or false
    if foe then dx = -dx end
    local ax, ay = vm:battlerCenter("attacker")
    local tx, ty = vm:battlerCenter("target")
    local feet = flagged(flags, FLAG_GROUND) and FEET or 0
    local back = flagged(flags, FLAG_BACK)
    ax, ay, tx, ty = ax + dx, ay + dy + feet, tx + dx, ty + dy + feet
    -- pixelfx draws facing right; turned or mirrored to face the target
    local vx, vy = tx - ax, ty - ay
    local aim = flagged(flags, FLAG_AIM) or mode == MODE_BEAM
    if aim then
      if vx < 0 then st.sx, st.rot = -1, math.atan2(-vy, -vx) else st.rot = math.atan2(vy, vx) end
    elseif foe then
      st.sx = -1
    end
    if mode == MODE_ATTACKER then
      st.x, st.y, t.z = ax, ay, frontZ(vm:attackerSide(), back)
    elseif mode == MODE_TRAVEL then
      st.ax, st.ay, st.tx, st.ty, t.z = ax, ay, tx, ty, Z.PLAYER_FRONT
    elseif mode == MODE_BEAM then
      local reach = tonumber(sheet.reach) or 100
      st.x, st.y, t.z = ax, ay, Z.PLAYER_FRONT
      st.sx = st.sx * math.sqrt(vx * vx + vy * vy) / reach
    else
      st.x, st.y, t.z = tx, ty, frontZ(vm:targetSide(), back)
    end
    return st
  end

  local function task(t, vm)
    local st = t._ndxFx
    if not st then
      st = start(t, vm)
      if not st then
        AnimTasks.destroy(t)
        return
      end
      t._ndxFx = st
      t.draw = draw
      return
    end
    st.tick = st.tick + 1
    if st.tick >= st.life then AnimTasks.destroy(t) end
  end
  state.task = task
  AnimTasks.REGISTRY.NdxFx = task
  if log then
    local n = 0
    for _ in pairs(data.sheets) do n = n + 1 end
    log:info("pixelfx move animations: %d sheets from %s", n, tostring(data.source))
  end
  return true
end

FxAnims.RAMP_SHADER = RAMP_SHADER
return FxAnims
