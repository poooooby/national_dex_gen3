-- Battle animations from the Gen 9 Move Animation Project, a Pokémon Essentials v21.1 animation pack
-- (https://eeveeexpo.com/resources/1480/, credited in CREDITS.md): data/ess_anims.lua, data/ess/<NAME>.lua
-- and assets/ess, built by tools/build_ess_anims.py. Every move the pack names plays the pack's
-- animation in battle: the newer moves (over pokeemerald-expansion's scripts and the borrowed looks)
-- and the carts' own Gen 1-3 moves; so do the cart's status, weather, trap, Leech Seed, Focus Punch
-- animations it has (`commons`). Contests keep the cart's (and so do Curse, Bide, Transform and
-- Substitute: tools/build_ess_anims.py's CART_KEEPS).
--
-- An Essentials animation is frames (20 a second) of cels: a 192 x 192 pattern of the move's sheet,
-- placed relative to the target, the user, the line between them, or the screen, zoomed, turned,
-- faded, blended and tinted; cel 0 and 1 are the user's and target's own pictures, moved the same
-- way, and a free cel may show a copy of either picture (an afterimage). Timings play sounds (one
-- with no name: the attacker's cry) and set or change a background and a foreground.
-- This plays one as a visual task of ours, "NdxEss", the way Essentials' PBAnimationPlayerX does,
-- with Essentials' 512 x 384 battle mapped onto Gen 3's 240 x 160 (its user -> target line onto the
-- attacker's and target's centres; the sheets are already scaled by data.scale):
--
--   createvisualtask NdxEss { "ESS:" .. NAME, mode, onUser }
--     mode 0 plain; 1 a two-turn move: its charging animation on the first turn; 2 the second turn of
--     one that hid its user (Fly, Dig, Dive, Bounce: the cart's own first turn hides it), shown again
--     onUser 1: a move on its user (Minimize): the user is its target too, as Essentials plays it
--     "ESS:@TRAP" picks the trap animation by the cart's GetTrappedMoveAnimId task (argument 0)
--
-- One wrap of Anim.scriptForMove (outside src/anims.lua's) and one of Anim.tableScript answer with
-- these scripts; anything without one falls through to the previous answer.
--
-- The task draws behind the enemy (with the background), between the two battlers and in front of
-- the player (with the foreground): itself and two helper tasks, one per band the battle draws. A
-- foe's move plays the pack's OppMove version when it has one (made for the foe's side), else the
-- Move version, mirrored on the line between them. The battlers' moves, fades and tints are their
-- `present` offsets, put back when it ends. Sounds are the cart's (by name) or the pack's (registered
-- as mod sounds). Without graphics (headless, or a missing file) the task still takes its time.
local EssAnims = {}

local TICKS = 3                        -- 60 a second; Essentials plays 20 frames a second
local SRC_UX, SRC_UY, SRC_TX, SRC_TY = 128, 224, 384, 96   -- Essentials' FOCUSUSER / FOCUSTARGET
local SCREEN_X, SCREEN_Y = 240 / 512, 160 / 384

-- a cel: pattern, x, y, focus, zoom x, zoom y, angle, opacity, blend, mirror, priority,
-- colour r g b a, tone r g b gray (data/ess/*.lua leaves trailing defaults off)
local P, CX, CY, FOCUS, ZX, ZY, ANGLE, OPACITY, BLEND, MIRROR, PRIO = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
local CR, CG, CB, CA, TR, TG, TB, TGRAY = 12, 13, 14, 15, 16, 17, 18, 19

-- Essentials' subtract blend (the screen minus the cel), as the cel's inverse drawn over it: what
-- subtracting gives on Gen 3's light battle backgrounds (the battle's canvas holds no backdrop to
-- subtract from, so LOVE's subtract and multiply leave nothing)
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

-- the pack's sounds as mod sounds; at load (registries are applied before game.ready)
function EssAnims.registerSounds(mod, ess)
  local sfx = mod and mod.content and mod.content.sfx
  if not (sfx and type(ess) == "table" and type(ess.sounds) == "table") then return 0 end
  local n = 0
  for id, file in pairs(ess.sounds) do
    -- (a sound file's path is the engine's, not the mod's)
    local path = (mod.path and mod.path ~= "") and (mod.path .. "/" .. file) or file
    if pcall(function() sfx:register(id, { file = path }) end) then n = n + 1 end
  end
  return n
end

local PREFIX = "national_dex_gen3:ess:"

-- opts: { mod (for mod.path), data (data/ess_anims.lua), read (path -> loaded table), moves
-- (src/moves.lua's registered rows: id, index), require, log }; after src/anims.lua's install
function EssAnims.install(opts)
  local require, log, data = opts.require, opts.log, opts.data
  if type(data) ~= "table" or type(data.moves) ~= "table" or type(data.sheets) ~= "table" then return false end
  local okT, AnimTasks = pcall(require, "src.core.game3.battle.anim_tasks")
  local okA, Anim = pcall(require, "src.core.game3.battle.anim")
  if not (okT and okA and type(AnimTasks) == "table" and type(AnimTasks.REGISTRY) == "table") then
    if log then log:warn("Gen 9 project move animations are off: the engine's animation tasks were not found") end
    return false
  end
  local okC, AnimCoords = pcall(require, "src.core.game3.battle.anim_coords")
  if not okC then AnimCoords = nil end

  -- one task for the whole process (games switch in-process); a later install brings its own data
  local state = AnimTasks.__ndxEss
  if not state then
    state = {}
    AnimTasks.__ndxEss = state
  end
  if state.data ~= data then state.images, state.moves = {}, {} end
  state.data, state.read, state.root, state.log = data, opts.read, opts.mod and opts.mod.path or "", log
  -- the running game's move numbers: the newer moves' slots, the carts' own numbers
  state.byNum = {}
  for _, r in ipairs(opts.moves or {}) do
    if r.index and r.id and data.moves[r.id] then state.byNum[tonumber(r.index)] = r.id end
  end
  for name, m in pairs(data.moves) do
    if m.num then state.byNum[m.num] = name end
  end
  state.scripts = setmetatable({}, { __mode = "k" })   -- pack -> name -> script
  -- the data/ess files there are: the moves', the common animations'
  state.known = {}
  for name in pairs(data.moves) do state.known[name] = true end
  for _, t in pairs(data.commons or {}) do for _, name in pairs(t) do state.known[name] = true end end
  for _, name in pairs(data.trap or {}) do state.known[name] = true end
  EssAnims.wrap(state, Anim, require)
  if state.task then
    AnimTasks.REGISTRY.NdxEss = state.task
    AnimTasks.REGISTRY.NdxEssLayer = state.layer
    return true
  end

  local hasLove = love and love.graphics and love.graphics.newImage and true or false
  local S = tonumber(data.scale) or 0.375

  local function moveData(move)
    local m = state.moves[move]
    if m == nil then
      m = false
      if state.read and state.known[move] then
        local ok, t = pcall(state.read, "data/ess/" .. move .. ".lua")
        if ok and type(t) == "table" and type(t.move) == "table" then m = t end
      end
      state.moves[move] = m
    end
    return m or nil
  end

  -- an image from the mod's folder, or false
  local function image(file, wrap)
    local img = state.images[file]
    if img ~= nil then return img end
    img = false
    if hasLove then
      local ok, im = pcall(love.graphics.newImage, state.root .. "/" .. file)
      if ok and im then
        im:setFilter("nearest", "nearest")
        if wrap then pcall(im.setWrap, im, "repeat", "repeat") end
        img = im
      elseif state.log then
        state.log:warn("could not load %s: %s", tostring(file), tostring(im))
      end
    end
    state.images[file] = img
    return img
  end

  local function shader()
    if state.shader == nil then
      local ok, sh = false, nil
      if hasLove and love.graphics.newShader then ok, sh = pcall(love.graphics.newShader, TINT_SHADER) end
      state.shader = ok and sh or false
    end
    return state.shader or nil
  end
  local function subShader()
    if state.subShader == nil then
      local ok, sh = false, nil
      if hasLove and love.graphics.newShader then ok, sh = pcall(love.graphics.newShader, SUB_SHADER) end
      state.subShader = ok and sh or false
    end
    return state.subShader or nil
  end

  local function sideOf(id, fallback)
    if AnimCoords and AnimCoords.sideOf and id ~= nil then
      local ok, s = pcall(AnimCoords.sideOf, id)
      if ok and s then return s end
    end
    return fallback
  end

  -- the battlers' `present` fields this task changes, to put back
  local KEEP = { "ox", "oy", "sx", "sy", "rotation", "alpha", "palAffine" }

  local function start(t, vm)
    local move = tostring(t.data[0] or ""):gsub("^ESS:", "")
    if move == "@TRAP" then
      move = (state.data.trap or {})[tonumber(vm.args and vm.args[0]) or 0] or ""
    end
    local md = moveData(move)
    if not md then return nil end
    local mode = tonumber(t.data[1]) or 0
    local foe = vm.isReversed and true or false
    if not foe and vm.attackerSide then foe = vm:attackerSide() ~= "player" end
    local anim, opp = md.move, false
    if foe and md.opp then anim, opp = md.opp, true end
    -- a two-turn move's first turn (the cart's choosetwoturnanim: an even turn)
    if mode == 1 and md.charge and (tonumber(vm._turn) or 0) % 2 == 0 then
      anim, opp = md.charge, false
      if foe and md.charge_opp then anim, opp = md.charge_opp, true end
    end
    if mode == 2 then
      -- its user comes back from where the cart's first turn hid it
      local p = Anim.present(vm:attackerId())
      if p then p.invisible = false end
    end
    -- the animation's "user" and "target": an OppMove version is made with the roles swapped
    local uKey, tKey = "attacker", "target"
    if opp then uKey, tKey = "target", "attacker" end
    if (tonumber(t.data[2]) or 0) == 1 then uKey, tKey = "attacker", "attacker" end   -- a move on its user
    local ux, uy = vm:battlerCenter(uKey)
    local tx, ty = vm:battlerCenter(tKey)
    local uId = uKey == "attacker" and vm:attackerId() or vm:targetId()
    local tId = tKey == "attacker" and vm:attackerId() or vm:targetId()
    local uSide = sideOf(uId, uKey == "attacker" and vm:attackerSide() or vm:targetSide())
    local tSide = sideOf(tId, tKey == "attacker" and vm:attackerSide() or vm:targetSide())
    local st = {
      move = move, anim = anim, frame = -1, tick = 0, last = #anim.frames,
      ux = ux, uy = uy, tx = tx, ty = ty, uSide = uSide, tSide = tSide,
      reversed = ux > tx,   -- Essentials' isReversed for the line between them
      vm = vm,
      lineX = math.max(1, math.abs(tx - ux) / (SRC_TX - SRC_UX) / S),
      lineY = math.max(1, math.abs(ty - uy) / (SRC_UY - SRC_TY) / S),
      cels = { {}, {}, {} },  -- this frame's cels by layer: behind the enemy, between, in front
      bg = { o = 0, x = 0, y = 0, c = { 0, 0, 0, 0 } }, fg = { o = 0, x = 0, y = 0, c = { 0, 0, 0, 0 } },
      oldbg = {}, oldfo = {},
      mons = {},
    }
    -- the battlers' pictures: what to put back
    local function mon(id)
      if id == nil or st.mons[id] then return end
      local p = Anim.present(id)
      if not p then return end
      local keep = {}
      for _, k in ipairs(KEEP) do keep[k] = p[k] end
      st.mons[id] = { p = p, keep = keep }
    end
    mon(uId)
    mon(tId)
    st.uId, st.tId = uId, tId
    st.sheet = anim.sheet and data.sheets[anim.sheet] or nil
    return st
  end

  -- a cel's place on the Gen 3 screen
  local function place(st, c)
    local x, y, f = c[CX], c[CY], c[FOCUS]
    if f == 1 then
      return st.tx + (x - SRC_TX) * S, st.ty + (y - SRC_TY) * S
    elseif f == 2 then
      return st.ux + (x - SRC_UX) * S, st.uy + (y - SRC_UY) * S
    elseif f == 3 then
      local fx = (x - SRC_UX) / (SRC_TX - SRC_UX)
      local fy = (y - SRC_UY) / (SRC_TY - SRC_UY)
      return st.ux + fx * (st.tx - st.ux), st.uy + fy * (st.ty - st.uy)
    end
    return x * SCREEN_X, y * SCREEN_Y
  end

  -- which band: 1 behind the enemy, 2 between the battlers, 3 in front of the player
  local function layerOf(st, c)
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

  local function setMon(st, id, home, c)
    local m = id ~= nil and st.mons[id]
    if not m then return end
    local p = m.p
    if not c then
      p.alpha = 0   -- Essentials hides a battler with no cel in the frame
      return
    end
    local x, y = place(st, c)
    p.ox = math.floor(x - home[1] + 0.5)
    p.oy = math.floor(y - home[2] + 0.5)
    p.sx = (c[ZX] or 100) / 100
    p.sy = (c[ZY] or 100) / 100
    p.rotation = -math.rad(c[ANGLE] or 0)
    p.alpha = (c[OPACITY] or 255) / 255
    -- Essentials' tone (added to each channel) then colour (mixed in by its alpha), as the battle's
    -- palette affine (each channel times m, plus an offset): exact, gray aside
    local a = (c[CA] or 0) / 255
    local tr, tg, tb = (c[TR] or 0) / 255, (c[TG] or 0) / 255, (c[TB] or 0) / 255
    if a > 0 or tr ~= 0 or tg ~= 0 or tb ~= 0 then
      local k = 1 - a
      p.palAffine = { m = k,
        r = tr * k + (c[CR] or 0) / 255 * a, g = tg * k + (c[CG] or 0) / 255 * a, b = tb * k + (c[CB] or 0) / 255 * a }
    else
      p.palAffine = nil
    end
  end

  local function restore(st)
    for _, m in pairs(st.mons) do
      for _, k in ipairs(KEEP) do m.p[k] = m.keep[k] end
    end
  end

  local SOUND_PAN_ATTACKER = -64

  -- the attacker's species, as the cart's own cry tasks find it (the battle's record if the
  -- animation was not told)
  local function attackerSpecies(vm)
    local sp
    if vm.speciesForSide then
      local side = vm.resolveBattlerSide and vm:resolveBattlerSide(0) or vm:attackerSide()
      local ok, s = pcall(vm.speciesForSide, vm, side)
      if ok then sp = s end
    end
    if sp == nil and AnimCoords and AnimCoords.battler then
      local ok, b = pcall(AnimCoords.battler, nil, vm:attackerId())
      if ok and type(b) == "table" then
        sp = (b.expTransform and b.expTransform.species) or b.species or (b.mon and (b.mon.species or b.mon.speciesId))
      end
    end
    return sp
  end

  local function play(se, st)
    local ok, Audio = pcall(require, "src.core.game3.audio")
    if not (ok and Audio) then return end
    if se == "CRY" then
      -- the attacker's cry (Essentials: the move's user, whichever version plays)
      local vm = st and st.vm
      local sp = vm and attackerSpecies(vm)
      if sp and Audio.playCry then
        local pan = vm.adjustPanning and vm:adjustPanning(SOUND_PAN_ATTACKER) or SOUND_PAN_ATTACKER
        pcall(Audio.playCry, sp, { pan = pan })
      end
      return
    end
    if Audio.playSe then pcall(Audio.playSe, se, { pan = 0 }) end
  end

  -- Essentials' playTiming (the background's ox moves by bgX's change, as there)
  local function plane(st, kind)
    return kind == "bg" and st.bg or st.fg
  end
  local function timings(st, frame)
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
          if e.se then play(e.se, st) end
        elseif e.t == 1 or e.t == 3 then
          local pl = plane(st, e.t == 1 and "bg" or "fg")
          local b = e.bg and data.bgs and data.bgs[e.bg]
          pl.img = b and image(b.file, true) or nil
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

  local function step(st, frame)
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
        local l = layers[layerOf(st, c)]
        l[#l + 1] = c
      end
    end
    -- the user, then the target: when it is the user too (a status, a move on itself), the target's
    -- cel wins, as in Essentials (cel 1 after cel 0 on the one picture)
    setMon(st, st.uId, { st.ux, st.uy }, user)
    setMon(st, st.tId, { st.tx, st.ty }, target)
    st.cels = layers
    timings(st, frame)
  end

  local function drawPlane(pl)
    if not pl or (pl.o or 0) <= 0 then return end
    local a = pl.o / 255
    if pl.img then
      local q = state.planeQuad
      if not q then
        q = love.graphics.newQuad(0, 0, 240, 160, 1, 1)
        state.planeQuad = q
      end
      local w, h = pl.img:getDimensions()
      q:setViewport((pl.x or 0) * SCREEN_X, (pl.y or 0) * SCREEN_Y, 240, 160, w, h)
      local sh = (pl.c[4] or 0) > 0 and shader() or nil
      if sh then
        love.graphics.setShader(sh)
        sh:send("ecol", { pl.c[1] / 255, pl.c[2] / 255, pl.c[3] / 255, pl.c[4] / 255 })
        sh:send("etone", { 0, 0, 0, 0 })
      end
      love.graphics.setColor(1, 1, 1, a)
      love.graphics.draw(pl.img, q, 0, 0)
      if sh then love.graphics.setShader() end
    elseif pl.solid then
      love.graphics.setColor(pl.c[1] / 255, pl.c[2] / 255, pl.c[3] / 255, a * ((pl.c[4] or 0) / 255))
      love.graphics.rectangle("fill", 0, 0, 240, 160)
    end
  end

  -- a battler's picture as the battle shows it (Ui.battlerPic), once per animation, or false
  local function monPic(st, id)
    st.pics = st.pics or {}
    local pic = st.pics[id]
    if pic == nil then
      pic = false
      local okU, Ui = pcall(require, "src.core.game3.battle.ui")
      if okU and type(Ui) == "table" and Ui.battlerPic and id ~= nil then
        local okP, e = pcall(Ui.battlerPic, id)
        if okP and type(e) == "table" and e.image then pic = e.image end
      end
      st.pics[id] = pic
    end
    return pic or nil
  end

  local function drawCels(st, list)
    if #list == 0 then return end
    local sheet = st.sheet
    local img = sheet and image(sheet.file) or nil
    local iw, ih, cell, cols, q, half
    if img then
      iw, ih = img:getDimensions()
      cell, cols = sheet.cell, sheet.cols
      q = state.celQuad
      if not q then
        q = love.graphics.newQuad(0, 0, cell, cell, iw, ih)
        state.celQuad = q
      end
      half = cell / 2
    end
    for _, c in ipairs(list) do
      local n = c[P]
      -- what to draw: a cel of the sheet, or a copy of a battler's picture (-3 the user's, -4 the
      -- target's; 64 px as the battle draws it)
      local src, quad, ox, oy, k = img, q, half, half, 1
      if n < 0 then
        src = monPic(st, n == -3 and st.uId or st.tId)
        if src then
          local pw, ph = src:getDimensions()
          quad, ox, oy, k = nil, pw / 2, ph / 2, 64 / pw
        end
      elseif img then
        q:setViewport((n % cols) * cell, math.floor(n / cols) * cell, cell, cell, iw, ih)
      end
      if not src then goto continue end
      local x, y = place(st, c)
      local sx, sy = (c[ZX] or 100) / 100 * k, (c[ZY] or 100) / 100 * k
      -- a cel placed on the line or the screen spreads by that axis's scale, wider than the sheets'
      -- (0.406 across the line, 0.469 across the screen): grown to match, so tiled pieces still meet
      local f = c[FOCUS]
      if f == 3 then
        sx, sy = sx * st.lineX, sy * st.lineY
      elseif f == 4 then
        sx, sy = sx * math.max(1, SCREEN_X / S), sy * math.max(1, SCREEN_Y / S)
      end
      local mirror = (c[MIRROR] or 0) > 0
      if c[FOCUS] == 3 and st.reversed then mirror = not mirror end
      if mirror then sx = -sx end
      local blend = c[BLEND] or 0
      local ca, tr, tg, tb, tgray = c[CA] or 0, c[TR] or 0, c[TG] or 0, c[TB] or 0, c[TGRAY] or 0
      local sh = (ca > 0 or tr ~= 0 or tg ~= 0 or tb ~= 0 or tgray > 0) and shader() or nil
      if blend == 2 and subShader() then
        sh = subShader()
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
      ::continue::
    end
    love.graphics.setBlendMode("alpha", "alphamultiply")
  end

  local function drawLayer(st, k)
    if k == 1 then drawPlane(st.bg) end
    drawCels(st, st.cels[k] or {})
    if k == 3 then drawPlane(st.fg) end
    love.graphics.setColor(1, 1, 1, 1)
  end

  local function drawMain(t)
    local st = t._ndxEss
    if st then drawLayer(st, 1) end
  end

  local function layer(t, vm)
    local parent = t._ndxEssParent
    if not (parent and parent.active and parent._ndxEss == t._ndxEssState) then AnimTasks.destroy(t) end
  end
  local function drawHelper(t)
    local st = t._ndxEssState
    if st then drawLayer(st, t._ndxEssLayer) end
  end

  local function task(t, vm)
    local st = t._ndxEss
    if not st then
      st = start(t, vm)
      if not st then
        AnimTasks.destroy(t)
        return
      end
      t._ndxEss = st
      t.draw, t.z = drawMain, 50
      if hasLove and AnimTasks.spawn then
        for k, z in pairs({ [2] = 150, [3] = 500 }) do
          local h = AnimTasks.spawn("NdxEssLayer", 2, {}, vm)
          if h then
            h._ndxEssParent, h._ndxEssState, h._ndxEssLayer = t, st, k
            h.draw, h.z = drawHelper, z
          end
        end
      end
      st.frame = 0
      step(st, 0)
      return
    end
    st.tick = st.tick + 1
    local frame = math.floor(st.tick / TICKS)
    if frame >= st.last then
      restore(st)
      t._ndxEss = nil
      AnimTasks.destroy(t)
      return
    end
    if frame ~= st.frame then
      st.frame = frame
      step(st, frame)
    end
  end

  state.task, state.layer = task, layer
  state.moveData = moveData
  AnimTasks.REGISTRY.NdxEss = task
  AnimTasks.REGISTRY.NdxEssLayer = layer
  EssAnims._moveData = moveData
  if log then
    local n = 0
    for _ in pairs(data.moves) do n = n + 1 end
    local c = 0
    for _, t in pairs(data.commons or {}) do for _ in pairs(t) do c = c + 1 end end
    log:info("Gen 9 project animations: %d moves, %d of the cart's other animations", n, c)
  end
  return true
end

-- the scripts that start the task
local function rows(name, mode, onUser)
  return {
    { op = "createvisualtask", task = "NdxEss", priority = 2, args = { "ESS:" .. name, mode or 0, onUser and 1 or 0 } },
    { op = "waitforvisualfinish" },
    { op = "end" },
  }
end

-- Anim.scriptForMove and Anim.tableScript, once per process (Anim is shared across games): each asks
-- the current install's `state`; Anim.launchMove marks a move played outside a battle (a contest),
-- which keeps the cart's
function EssAnims.wrap(state, Anim, require)
  state.Anim = Anim
  if Anim.__ndxEss then
    Anim.__ndxEss.state = state
    return
  end
  local hub = { state = state }
  Anim.__ndxEss = hub
  local okB, Battle = pcall(require, "src.core.game3.battle")
  if not okB then Battle = nil end

  local function cached(pack, key, build)
    local st = hub.state
    local byPack = st.scripts[pack]
    if not byPack then
      byPack = {}
      st.scripts[pack] = byPack
    end
    local s = byPack[key]
    if s == nil then
      s = build() or false
      byPack[key] = s
    end
    return s or nil
  end

  local scriptForMove = Anim.scriptForMove
  Anim.scriptForMove = function(moveId, ...)
    local st = hub.state
    local fallback = scriptForMove(moveId, ...)   -- also loads the pack
    if st.contest then return fallback end
    local num = tonumber(moveId)
    if not num and type(moveId) == "string" then
      local okM, Moves = pcall(require, "src.core.game3.battle.moves")
      num = okM and Moves.numForName and Moves.numForName(moveId) or nil
    end
    local name = num and st.byNum and st.byNum[num]
    local info = name and st.data.moves[name]
    local pack = Anim._pack
    if not (info and type(pack) == "table") then return fallback end
    -- a move on its user (MOVE_TARGET_USER: Minimize, Swords Dance) plays with the user as its target,
    -- as Essentials plays it, whatever target the battle names
    local onUser = info.user and true or false
    if not onUser then
      local okM, Moves = pcall(require, "src.core.game3.battle.moves")
      local okG, mv = false, nil
      if okM and Moves.get then okG, mv = pcall(Moves.get, num) end
      if not (okG and type(mv) == "table") and okM and type(Moves._rom) == "table" then
        okG, mv = true, Moves._rom[num]   -- (the rows themselves, when names aren't loaded)
      end
      onUser = okG and type(mv) == "table" and tonumber(mv.target) == 16 or false
    end
    return cached(pack, name, function()
      if info.turns == "hide" and type(fallback) == "table" then
        -- the cart's first turn (it hides the user), the pack's second
        pack.labels = pack.labels or {}
        pack.labels[PREFIX .. name .. ":1"] = fallback
        pack.labels[PREFIX .. name .. ":2"] = rows(name, 2, onUser)
        return { { op = "choosetwoturnanim", label1 = PREFIX .. name .. ":1", label2 = PREFIX .. name .. ":2" } }
      end
      return rows(name, info.turns == "charge" and 1 or 0, onUser)
    end) or fallback
  end

  local tableScript = Anim.tableScript
  if type(tableScript) == "function" then
    Anim.tableScript = function(kind, which, ...)
      local script, idx = tableScript(kind, which, ...)
      local st = hub.state
      local pack = Anim._pack
      local names = type(pack) == "table" and idx ~= nil and pack[tostring(kind) .. "Names"]
      local canon = names and names[idx]
      canon = canon and tostring(canon):gsub("^B_ANIM_", "") or nil
      if not canon or st.contest then return script, idx end
      if kind == "general" and canon == "TURN_TRAP" and next(st.data.trap or {}) ~= nil then
        -- the cart's own first step finds the trapping move (argument 0)
        local first = type(script) == "table" and script[1]
        if not (first and first.op == "createvisualtask") then return script, idx end
        return cached(pack, "@TRAP", function()
          local r = rows("@TRAP", 0)
          table.insert(r, 1, first)
          -- a trap the pack has no one animation for (Bind and Wrap share 0) plays the cart's
          pack.labels = pack.labels or {}
          for arg = 0, 7 do
            if not st.data.trap[arg] then
              pack.labels[PREFIX .. "trap:cart"] = script
              table.insert(r, 2, { op = "jumpargeq", argId = 0, value = arg, label = PREFIX .. "trap:cart" })
            end
          end
          return r
        end) or script, idx
      end
      local commons = st.data.commons and st.data.commons[kind]
      local name = commons and commons[canon]
      if not (name and st.moveData and st.moveData(name)) then return script, idx end
      return cached(pack, name, function() return rows(name, 0) end) or script, idx
    end
  end

  local launchMove = Anim.launchMove
  if type(launchMove) == "function" then
    Anim.launchMove = function(moveId, opts, ...)
      local st = hub.state
      local outside = Battle and Battle.isActive and not Battle.isActive() or false
      st.contest = outside and true or false
      local ok, a, b = pcall(launchMove, moveId, opts, ...)
      st.contest = false
      if not ok then error(a, 0) end
      return a, b
    end
  end
end

return EssAnims
