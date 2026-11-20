-- The Gen 9 Move Animation Project's animations, the part every generation shares (data/ess_anims.lua,
-- data/ess/<NAME>.lua and assets/ess, from tools/build_ess_anims.py): loading a move's frames, the
-- atlas pages, placing and drawing an Essentials animation's cels and planes on a battle screen, its
-- timings, and the pack's sounds. src/ess_anims.lua plays them on Gen 3 (the animation VM's visual
-- task) and src/gen12/ess_anims.lua on Gen 1 / Gen 2 (over the cart's own animation player).
--
-- Every function takes a `state`: { data (data/ess_anims.lua), read (path -> loaded table), root (the
-- mod's path), mod, log, known (the data/ess names there are), moves, images, sources (caches) }.
-- An animation in play is an `st` (Core.start): its frames, where its user and target stand and the
-- screen it draws on (a `stage`), and hooks for what the generation does itself: setMon (a battler's
-- own cel), play (a sound timing), copyPic (a battler's picture, for a copy cel), drawCopy.
local Core = {}

Core.TICKS = 3                          -- 60 a second; Essentials plays 20 frames a second
Core.SRC_UX, Core.SRC_UY, Core.SRC_TX, Core.SRC_TY = 128, 224, 384, 96   -- FOCUSUSER / FOCUSTARGET
local SRC_UX, SRC_UY, SRC_TX, SRC_TY = Core.SRC_UX, Core.SRC_UY, Core.SRC_TX, Core.SRC_TY

-- a cel: pattern, x, y, focus, zoom x, zoom y, angle, opacity, blend, mirror, priority,
-- colour r g b a, tone r g b gray (data/ess/*.lua leaves trailing defaults off)
local C = {
  P = 1, CX = 2, CY = 3, FOCUS = 4, ZX = 5, ZY = 6, ANGLE = 7, OPACITY = 8, BLEND = 9, MIRROR = 10,
  PRIO = 11, CR = 12, CG = 13, CB = 14, CA = 15, TR = 16, TG = 17, TB = 18, TGRAY = 19,
}
Core.CEL = C
local P, CX, CY, FOCUS, ZX, ZY, ANGLE, OPACITY, BLEND, MIRROR, PRIO =
  C.P, C.CX, C.CY, C.FOCUS, C.ZX, C.ZY, C.ANGLE, C.OPACITY, C.BLEND, C.MIRROR, C.PRIO
local CR, CG, CB, CA, TR, TG, TB, TGRAY = C.CR, C.CG, C.CB, C.CA, C.TR, C.TG, C.TB, C.TGRAY

-- Essentials' subtract blend (the screen minus the cel), as the cel's inverse drawn over it: what
-- subtracting gives on the light battle backgrounds (a battle's canvas holds no backdrop to subtract
-- from, so LOVE's subtract and multiply leave nothing)
local SUB_SHADER = [[
extern vec4 ecol;
extern vec4 etone;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec4 p = Texel(tex, uv);
  vec3 c = p.rgb;
  float g = dot(c, vec3(0.299, 0.587, 0.114));
  c = mix(c, vec3(g), etone.a);
  c = clamp(c + etone.rgb, 0.0, 1.0);
  c = mix(c, ecol.rgb, ecol.a);
  return vec4(vec3(1.0) - c, p.a) * color;
}
]]

local TINT_SHADER = [[
extern vec4 ecol;
extern vec4 etone;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec4 p = Texel(tex, uv);
  vec3 c = p.rgb;
  float g = dot(c, vec3(0.299, 0.587, 0.114));
  c = mix(c, vec3(g), etone.a);
  c = clamp(c + etone.rgb, 0.0, 1.0);
  c = mix(c, ecol.rgb, ecol.a);
  return vec4(c, p.a) * color;
}
]]

local function hasLove()
  return love and love.graphics and love.graphics.newImage and true or false
end
Core.hasLove = hasLove

-- (re)points a state at this install's data: its caches start over when the data is new
function Core.setData(state, opts)
  local data = opts.data
  if state.data ~= data then state.images, state.moves, state.sources, state.soundBytes = {}, {}, {}, nil end
  state.images, state.moves, state.sources = state.images or {}, state.moves or {}, state.sources or {}
  state.data, state.read, state.root, state.log = data, opts.read, opts.mod and opts.mod.path or "", opts.log
  state.mod, state.require = opts.mod, opts.require
  -- the data/ess files there are: the moves', the common animations'
  state.known = {}
  for name in pairs(data.moves or {}) do state.known[name] = true end
  for _, t in pairs(data.commons or {}) do for _, name in pairs(t) do state.known[name] = true end end
  for _, name in pairs(data.trap or {}) do state.known[name] = true end
  return state
end

-- a move's (or common animation's) data/ess file, loaded once; nil when there is none
function Core.moveData(state, move)
  local m = state.moves[move]
  if m == nil then
    m = false
    if state.read and state.known and state.known[move] then
      local ok, t = pcall(state.read, "data/ess/" .. move .. ".lua")
      if ok and type(t) == "table" and type(t.move) == "table" then m = t end
    end
    state.moves[move] = m
  end
  return m or nil
end

-- an image from the mod's folder, or nil
function Core.image(state, file)
  local img = state.images[file]
  if img ~= nil then return img or nil end
  img = false
  if hasLove() then
    local ok, im = pcall(love.graphics.newImage, state.root .. "/" .. file)
    if ok and im then
      im:setFilter("nearest", "nearest")
      img = im
    elseif state.log then
      state.log:warn("could not load %s: %s", tostring(file), tostring(im))
    end
  end
  state.images[file] = img
  return img or nil
end

-- an atlas page (data.pages[n]), or nil
function Core.page(state, n)
  local pg = n and state.data.pages and state.data.pages[n]
  return pg and Core.image(state, pg.file) or nil
end

local function shaderOf(state, key, code)
  if state[key] == nil then
    local ok, sh = false, nil
    if hasLove() and love.graphics.newShader then ok, sh = pcall(love.graphics.newShader, code) end
    state[key] = ok and sh or false
  end
  return state[key] or nil
end
function Core.shader(state) return shaderOf(state, "shader", TINT_SHADER) end
function Core.subShader(state) return shaderOf(state, "subShader", SUB_SHADER) end

-- ---------- an animation in play ----------------------------------------------------------------

-- anim: one version's { frames, timing, sheet }; stage: {
--   ux, uy, tx, ty      where the animation's user and target stand (their centres)
--   uSide, tSide        "player" / "enemy" (for the layers)
--   w, h                the screen (Essentials' 512 x 384 maps onto it)
--   scale               Essentials pixels -> screen pixels around a battler (data.scale on Gen 3)
--   celScale            the cels' size against the atlas's (1 on Gen 3)
--   setMon, play, copyPic, drawCopy   the generation's hooks }
function Core.start(state, anim, stage)
  local S = stage.scale or tonumber(state.data.scale) or 0.375
  local st = {
    anim = anim, frame = -1, tick = 0, last = #anim.frames,
    ux = stage.ux, uy = stage.uy, tx = stage.tx, ty = stage.ty, uSide = stage.uSide, tSide = stage.tSide,
    w = stage.w or 240, h = stage.h or 160, S = S, celScale = stage.celScale or 1,
    reversed = stage.ux > stage.tx,   -- Essentials' isReversed for the line between them
    cels = { {}, {}, {} },  -- this frame's cels by layer: behind the enemy, between, in front
    bg = { o = 0, x = 0, y = 0, c = { 0, 0, 0, 0 } }, fg = { o = 0, x = 0, y = 0, c = { 0, 0, 0, 0 } },
    oldbg = {}, oldfo = {},
    setMon = stage.setMon, play = stage.play, copyPic = stage.copyPic, drawCopy = stage.drawCopy,
  }
  st.screenX, st.screenY = st.w / 512, st.h / 384
  st.lineX = math.max(1, math.abs(st.tx - st.ux) / (SRC_TX - SRC_UX) / S)
  st.lineY = math.max(1, math.abs(st.ty - st.uy) / (SRC_UY - SRC_TY) / S)
  st.sheet = anim.sheet and state.data.sheets[anim.sheet] or nil
  return st
end

-- a cel's place on the screen
function Core.place(st, c)
  local x, y, f, S = c[CX], c[CY], c[FOCUS], st.S
  if f == 1 then
    return st.tx + (x - SRC_TX) * S, st.ty + (y - SRC_TY) * S
  elseif f == 2 then
    return st.ux + (x - SRC_UX) * S, st.uy + (y - SRC_UY) * S
  elseif f == 3 then
    local fx = (x - SRC_UX) / (SRC_TX - SRC_UX)
    local fy = (y - SRC_UY) / (SRC_TY - SRC_UY)
    return st.ux + fx * (st.tx - st.ux), st.uy + fy * (st.ty - st.uy)
  end
  return x * st.screenX, y * st.screenY
end

-- which band: 1 behind the enemy, 2 between the battlers, 3 in front of the player
function Core.layerOf(st, c)
  local pr, f = c[PRIO] or 1, c[FOCUS]
  if pr == 0 then return 1 end
  local side = (f == 1 and st.tSide) or (f == 2 and st.uSide) or nil
  if pr == 2 then
    if side == "player" then return 2 end
    return 1
  elseif pr == 3 then
    if side == "enemy" then return 2 end
    return 3
  end
  return 3
end

-- Essentials' playTiming (the background's ox moves by bgX's change, as there)
local function plane(st, kind)
  return kind == "bg" and st.bg or st.fg
end
function Core.timings(state, st, frame)
  for _, e in ipairs(st.anim.timing or {}) do
    local d = e.d or 0
    if (e.t == 2 or e.t == 4) and d > 0 and frame > e.f and frame <= e.f + d then
      local fr = (frame - e.f) / d
      local pl = plane(st, e.t == 2 and "bg" or "fg")
      local old = e.t == 2 and st.oldbg or st.oldfo
      if old.o then
        if pl.img then
          if e.x then pl.x = old.x - (e.x - old.x) * fr end
          if e.y then pl.y = old.y - (e.y - old.y) * fr end
        end
        if e.o then pl.o = old.o + (e.o - old.o) * fr end
        if e.c then
          for i = 1, 4 do
            if e.c[i] and e.c[i] >= 0 then pl.c[i] = old.c[i] + (e.c[i] - old.c[i]) * fr end
          end
        end
      end
    end
  end
  for _, e in ipairs(st.anim.timing or {}) do
    if e.f == frame then
      if e.t == 0 then
        if e.se and st.play then st.play(e, st) end
      elseif e.t == 1 or e.t == 3 then
        local pl = plane(st, e.t == 1 and "bg" or "fg")
        local b = e.bg and state.data.bgs and state.data.bgs[e.bg]
        pl.img = b and Core.page(state, b.page) or nil
        pl.rect = b
        pl.x, pl.y = -(e.x or 0), -(e.y or 0)
        pl.o = e.o or 0
        pl.c = { e.c and e.c[1] or 0, e.c and e.c[2] or 0, e.c and e.c[3] or 0, e.c and e.c[4] or 0 }
        pl.solid = not e.bg
      elseif e.t == 2 or e.t == 4 then
        local pl = plane(st, e.t == 2 and "bg" or "fg")
        local old = e.t == 2 and st.oldbg or st.oldfo
        old.x, old.y, old.o = pl.img and pl.x or 0, pl.img and pl.y or 0, pl.o or 0
        old.c = { pl.c[1], pl.c[2], pl.c[3], pl.c[4] }
      end
    end
  end
end

-- one frame: its cels into their layers, the battlers' own cels to setMon, its timings
function Core.step(state, st, frame)
  local cels = st.anim.frames[frame + 1] or {}
  local layers = { {}, {}, {} }
  local user, target
  for _, c in ipairs(cels) do
    local p = c[P]
    if p == -1 then
      user = c
    elseif p == -2 then
      target = c
    elseif p >= 0 or p <= -3 then
      local l = layers[Core.layerOf(st, c)]
      l[#l + 1] = c
    end
  end
  -- the user, then the target: when it is the user too (a status, a move on itself), the target's
  -- cel wins, as in Essentials (cel 1 after cel 0 on the one picture)
  if st.setMon then
    st.setMon(st, "user", user)
    st.setMon(st, "target", target)
  end
  st.cels = layers
  Core.timings(state, st, frame)
end

-- a battler's own cel as offsets from where it stands: dx, dy, sx, sy, rotation, alpha
function Core.monPose(st, which, c)
  local x, y = Core.place(st, c)
  local hx, hy = st.ux, st.uy
  if which == "target" then hx, hy = st.tx, st.ty end
  return math.floor(x - hx + 0.5), math.floor(y - hy + 0.5), (c[ZX] or 100) / 100, (c[ZY] or 100) / 100,
    -math.rad(c[ANGLE] or 0), (c[OPACITY] or 255) / 255
end

-- ---------- drawing -----------------------------------------------------------------------------

function Core.drawPlane(state, st, pl)
  if not pl or (pl.o or 0) <= 0 then return end
  local a = pl.o / 255
  local W, H = st.w, st.h
  if pl.img and pl.rect then
    -- Essentials' plane repeats its picture across the screen, shifted by (x, y): the copies that
    -- cover it (the pictures are sized for 240 x 160: scaled to this screen)
    local r = pl.rect
    local k = W / 240
    local q = state.planeQuad
    local iw, ih = pl.img:getDimensions()
    if not q then
      q = love.graphics.newQuad(r.x, r.y, r.w, r.h, iw, ih)
      state.planeQuad = q
    end
    q:setViewport(r.x, r.y, r.w, r.h, iw, ih)
    local sh = (pl.c[4] or 0) > 0 and Core.shader(state) or nil
    if sh then
      love.graphics.setShader(sh)
      sh:send("ecol", { pl.c[1] / 255, pl.c[2] / 255, pl.c[3] / 255, pl.c[4] / 255 })
      sh:send("etone", { 0, 0, 0, 0 })
    end
    love.graphics.setColor(1, 1, 1, a)
    local tw, th = r.w * k, r.h * k
    local x0 = -((math.floor((pl.x or 0) * st.screenX)) % tw)
    local y0 = -((math.floor((pl.y or 0) * st.screenY)) % th)
    for y = y0, H - 1, th do
      for x = x0, W - 1, tw do
        love.graphics.draw(pl.img, q, x, y, 0, k, k)
      end
    end
    if sh then love.graphics.setShader() end
  elseif pl.solid then
    love.graphics.setColor(pl.c[1] / 255, pl.c[2] / 255, pl.c[3] / 255, a * ((pl.c[4] or 0) / 255))
    love.graphics.rectangle("fill", 0, 0, W, H)
  end
end

function Core.drawCels(state, st, list)
  if #list == 0 then return end
  local sheet = st.sheet
  local rects = sheet and sheet.r
  local half = sheet and sheet.cell / 2 or 0
  local q = state.celQuad
  if not q and love.graphics.newQuad then
    q = love.graphics.newQuad(0, 0, 1, 1, 1, 1)
    state.celQuad = q
  end
  local S, K = st.S, st.celScale
  for _, c in ipairs(list) do
    local n = c[P]
    local x, y = Core.place(st, c)
    local mirror = (c[MIRROR] or 0) > 0
    if c[FOCUS] == 3 and st.reversed then mirror = not mirror end
    if n < 0 and st.drawCopy then
      -- a copy of a battler's picture (-3 the user's, -4 the target's), drawn by the generation
      local sx, sy = (c[ZX] or 100) / 100, (c[ZY] or 100) / 100
      st.drawCopy(st, n == -3 and "user" or "target", x, y, mirror and -sx or sx, sy,
        -math.rad(c[ANGLE] or 0), (c[OPACITY] or 255) / 255)
      goto continue
    end
    do
      -- what to draw: a cel of the sheet (its rect on an atlas page, trimmed: centred where it sat in
      -- its cell), or a copy of a battler's picture (copyPic: the image and its scale to the battle's)
      local src, quad, ox, oy, k = nil, nil, 0, 0, K
      if n < 0 then
        if st.copyPic then
          local kk
          src, kk = st.copyPic(st, n == -3 and "user" or "target")
          if src then
            local pw, ph = src:getDimensions()
            ox, oy, k = pw / 2, ph / 2, kk or 1
          end
        end
      elseif rects then
        local b = n * 7
        src = Core.page(state, rects[b + 1])
        if src then
          local iw, ih = src:getDimensions()
          q:setViewport(rects[b + 2], rects[b + 3], rects[b + 4], rects[b + 5], iw, ih)
          quad, ox, oy = q, half - rects[b + 6], half - rects[b + 7]
        end
      end
      if not src then goto continue end
      local sx, sy = (c[ZX] or 100) / 100 * k, (c[ZY] or 100) / 100 * k
      -- a cel placed on the line or the screen spreads by that axis's scale, wider than the sheets':
      -- grown to match, so tiled pieces still meet
      local f = c[FOCUS]
      if f == 3 then
        sx, sy = sx * st.lineX, sy * st.lineY
      elseif f == 4 then
        sx, sy = sx * math.max(1, st.screenX / S), sy * math.max(1, st.screenY / S)
      end
      if mirror then sx = -sx end
      local blend = c[BLEND] or 0
      local ca, tr, tg, tb, tgray = c[CA] or 0, c[TR] or 0, c[TG] or 0, c[TB] or 0, c[TGRAY] or 0
      local sh = (ca > 0 or tr ~= 0 or tg ~= 0 or tb ~= 0 or tgray > 0) and Core.shader(state) or nil
      if blend == 2 and Core.subShader(state) then
        sh = Core.subShader(state)
        love.graphics.setBlendMode("alpha", "alphamultiply")
      elseif blend == 1 then
        love.graphics.setBlendMode("add", "alphamultiply")
      else
        love.graphics.setBlendMode("alpha", "alphamultiply")
      end
      if sh then
        love.graphics.setShader(sh)
        sh:send("ecol", { (c[CR] or 0) / 255, (c[CG] or 0) / 255, (c[CB] or 0) / 255, ca / 255 })
        sh:send("etone", { tr / 255, tg / 255, tb / 255, tgray / 255 })
      end
      love.graphics.setColor(1, 1, 1, (c[OPACITY] or 255) / 255)
      local rx, ry, rot = math.floor(x + 0.5), math.floor(y + 0.5), -math.rad(c[ANGLE] or 0)
      if quad then
        love.graphics.draw(src, quad, rx, ry, rot, sx, sy, ox, oy)
      else
        love.graphics.draw(src, rx, ry, rot, sx, sy, ox, oy)
      end
      if sh then love.graphics.setShader() end
    end
    ::continue::
  end
  love.graphics.setBlendMode("alpha", "alphamultiply")
end

-- a layer: 1 the background plane and the cels behind the enemy, 2 between, 3 in front and the
-- foreground plane
function Core.drawLayer(state, st, k)
  if k == 1 then Core.drawPlane(state, st, st.bg) end
  Core.drawCels(state, st, st.cels[k] or {})
  if k == 3 then Core.drawPlane(state, st, st.fg) end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---------- the pack's sounds -------------------------------------------------------------------
-- data.soundFile holds every pack sound as a whole ogg, end to end (one file shipped, not hundreds);
-- data.sounds[id] = { byte offset, length }. A sound is decoded from its own bytes the first time it
-- plays, or ahead of time (Core.prewarm, on a queue the generation gives), widened to stereo as the
-- engine widens its mono ones (Sound.lua's widenMono), and kept until the battle ends. It plays as the
-- engine plays a mod sound: 0.8 x the sound volume option, at the engine's sound rate, and not while
-- the audio device is suspended.
Core.BASE_VOLUME = 0.8

local function soundBytes(state)
  if state.soundBytes == nil then
    local file, bytes = state.data.soundFile, nil
    if file and state.mod and state.mod.read then
      local ok, b = pcall(state.mod.read, state.mod, file)
      if ok and type(b) == "string" then bytes = b end
    end
    if not bytes and file and love and love.filesystem and love.filesystem.read then
      local ok, b = pcall(love.filesystem.read, state.root .. "/" .. file)
      if ok and type(b) == "string" then bytes = b end
    end
    if not bytes and file and state.log then state.log:warn("could not read %s", tostring(file)) end
    state.soundBytes = bytes or false
  end
  return state.soundBytes or nil
end

-- the sound's Source, decoded now if it isn't yet; nil without audio or when it can't be
function Core.soundSource(state, id)
  local src = state.sources[id]
  if src ~= nil then return src or nil end
  src = false
  local at = state.data.sounds and state.data.sounds[id]
  if at and love and love.sound and love.sound.newSoundData and love.audio and love.audio.newSource
      and love.filesystem and love.filesystem.newFileData then
    local bytes = soundBytes(state)
    if bytes then
      local ok, made = pcall(function()
        local fd = love.filesystem.newFileData(bytes:sub(at[1] + 1, at[1] + at[2]), id .. ".ogg")
        local sd = love.sound.newSoundData(fd)
        if sd:getChannelCount() == 1 then
          local n = sd:getSampleCount()
          local stereo = love.sound.newSoundData(n, sd:getSampleRate(), 16, 2)
          for i = 0, n - 1 do
            local v = sd:getSample(i)
            stereo:setSample(i, 1, v)
            stereo:setSample(i, 2, v)
          end
          sd = stereo
        end
        return love.audio.newSource(sd, "static")
      end)
      if ok and made then
        src = made
      elseif state.log then
        state.log:warn("could not decode sound %s: %s", tostring(id), tostring(made))
      end
    end
  end
  state.sources[id] = src
  return src or nil
end

-- decode these sounds ahead of time: schedule(key, fn, priority) queues each (lower runs sooner)
function Core.prewarm(state, ids, priority, schedule)
  if not (state and type(ids) == "table" and state.data and state.data.sounds and schedule) then return 0 end
  local n = 0
  for _, id in ipairs(ids) do
    if state.sources[id] == nil and state.data.sounds[id] then
      schedule("ndxess:" .. id, function() Core.soundSource(state, id) end, priority)
      n = n + 1
    end
  end
  return n
end

-- the pack sounds these moves play (field: the moves' list of them, "se" by default); a move is a
-- name, or a number state.byNum knows
function Core.moveSounds(state, moves, out, field)
  out = out or {}
  for _, mv in ipairs(moves) do
    if type(mv) == "table" then mv = mv.id or mv.move or mv.num end
    local name = type(mv) == "string" and mv or (state.byNum and state.byNum[tonumber(mv)])
    local m = name and state.data.moves[name]
    for _, id in ipairs(m and m[field or "se"] or {}) do out[#out + 1] = id end
  end
  return out
end

-- play a pack sound at `level` (the sound volume option, 0-1) and `rate`; false when the id isn't
-- one (true when it is, played or not)
function Core.playSound(state, id, level, rate, suspended)
  if not (state and state.data and state.data.sounds and state.data.sounds[id]) then return false end
  if suspended then return true end
  local src = Core.soundSource(state, id)
  if not src then return true end
  pcall(src.stop, src)
  pcall(src.setVolume, src, Core.BASE_VOLUME * (level or 1))
  pcall(src.setPitch, src, rate or 1)
  pcall(src.play, src)
  return true
end

-- the battle's end: every decoded sound stops and goes
function Core.dropSounds(state)
  for _, src in pairs(state.sources or {}) do
    if src then pcall(src.stop, src) end
  end
  state.sources = {}
end

return Core
