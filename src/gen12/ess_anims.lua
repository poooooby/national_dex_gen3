-- The Gen 9 Move Animation Project's animations on Gen 1 / Gen 2 (Red, Blue, Yellow; Gold, Silver,
-- Crystal): the same data and pictures as Gen 3's (data/ess_anims.lua, data/ess, assets/ess; credited
-- in CREDITS.md), played by src/ess_core.lua over the Game Boy battle.
--
-- Neither game runs a mod's code inside a move animation, so each move the pack animates gets a cart
-- animation that only takes the pack animation's time (the battle waits for it, then plays the hit;
-- the battle-animations option skips it as it skips any):
--   Red   a battle_anims record of SE_DELAY_ANIMATION_10 rows (10 frames each), plus the cart
--         record's own lasting picture effects at its end (Minimize's, Explosion's, Fly's / Dig's
--         return)
--   Gold  a script of its own ("ndx:<move>": a wait), which the move's entry in `moves` names; a
--         two-turn move's charge turn (param 1) jumps to the cart's own script
-- and the animation is drawn with the battlers' pictures while that plays (Red: animPlaying /
-- animName / animPlayer.elapsed; Gold: the runner's script key and frames):
--   Red   BattleState:drawPicsLayer wrapped: the background and the cels behind the enemy, then the
--         pictures (the cels between them drawn just before your mon's), then the front cels and the
--         foreground; BattleState:drawBattlerPic wrapped to move, turn, scale and fade a battler by
--         its own cel (and to draw copies of it)
--   Gold  BattleState:drawPics wrapped the same way (inside the panel the animation view bakes, so
--         the cart's own shakes move the cels too); BattleState:drawPic moved by a transform (Gold's
--         pictures draw at full opacity: a battler under half opacity is hidden)
-- The text box covers the field's bottom as it does every animation. Sounds are the pack's
-- recordings (a Gen 3 cart sound, the fallback for one the pack lacks, is left out); a nameless one
-- is the attacker's cry.
local Ess12 = {}

-- where the pictures' centres are (160 x 144): the foe's front picture and your back one
Ess12.CENTRE = {
  [1] = { player = { 36, 68 }, enemy = { 124, 28 } },
  [2] = { player = { 40, 72 }, enemy = { 124, 28 } },
}
-- Red's wide layout (src/battle/WideBattle.lua): each side's 160 x 144 region moved apart on a
-- 304-wide field ending at row 104; the cels are drawn from battle.overlay there (Ess12.overlay)
Ess12.WIDE = { player = { 20, 8 }, enemy = { 136, 0 }, w = 304, field = 104 }
-- the cels' size against Gen 3's (the Game Boy's user -> target line is ~90% of Gen 3's)
Ess12.CEL_SCALE = 0.9
-- moves that keep the cart's animation: the cart decides by the turn (Curse, Bide), or its animation
-- changes the picture for good (Transform, Substitute)
Ess12.KEEP = { CURSE = true, BIDE = true, TRANSFORM = true, SUBSTITUTE = true }
-- the carts' names the pack spells otherwise (beyond the underscores, which the match ignores)
Ess12.ALIASES = {
  PSYCHIC_M = "PSYCHIC", HI_JUMP_KICK = "HIGH_JUMP_KICK", FAINT_ATTACK = "FEINT_ATTACK",
  VICEGRIP = "VISE_GRIP",
}
-- Red: cart record effects whose result outlasts the animation, kept at the end of ours
Ess12.LASTING = { SE_MINIMIZE_MON = true, SE_HIDE_ATTACKER_PIC = true }
-- the cart's other animations the pack has: Red's records, Gold's ids -> data/ess names (a function
-- picks by the battler's status)
local function burnOrPoison(status)
  return status == "BRN" and "C_BURN" or "C_POISON"
end
Ess12.RED_COMMONS = {
  BURN_PSN_ANIM = burnOrPoison, SLP_ANIM = "C_SLEEP", SLP_PLAYER_ANIM = "C_SLEEP",
  CONF_ANIM = "C_CONFUSION", CONF_PLAYER_ANIM = "C_CONFUSION",
}
Ess12.GOLD_COMMONS = {
  ANIM_PSN = "C_POISON", ANIM_BRN = "C_BURN", ANIM_IN_SANDSTORM = "C_SANDSTORM", ANIM_SAP = "C_LEECHSEED",
}

-- the pack's name for a cart / mod move id, or nil
function Ess12.essName(data, id)
  if type(id) ~= "string" then return nil end
  if data.moves[id] then return id end
  local a = Ess12.ALIASES[id]
  if a and data.moves[a] then return a end
  local idx = data.__ndxLoose
  if not idx then
    idx = {}
    for name in pairs(data.moves) do idx[(name:gsub("_", ""))] = name end
    data.__ndxLoose = idx
  end
  return idx[(id:gsub("_", ""))]
end

local function frameCount(state, Core, name)
  local info = state.data.moves[name]
  if info then return math.max(info.frames or 0, info.opp or 0) end
  local md = Core.moveData(state, name)
  if not md then return 0 end
  local n = 0
  for _, a in pairs(md) do n = math.max(n, #(a.frames or {})) end
  return n
end

local EMPTY = {}

local function copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = copy(v) end
  return o
end

-- ---------- registration (at load) --------------------------------------------------------------

-- opts: { mod, generation, data (data/ess_anims.lua), read, Core (src/ess_core.lua), require,
-- newer (the move ids this mod registered: their cart animation is a borrowed look), log }
-- -> state { lines = { [Red anim id / Gold script key] = { name, ticks, turns, user } }, count }
function Ess12.register(opts)
  local mod, gen, data, Core = opts.mod, opts.generation, opts.data, opts.Core
  local state = Core.setData({}, opts)
  state.generation, state.lines, state.count, state.kept = gen, {}, 0, {}
  local anims, moves = mod.content.battle_anims, mod.content.moves
  local newer = opts.newer or {}
  if not (anims and moves and type(data.moves) == "table") then return state end
  local ids = {}
  for id in moves:each() do ids[#ids + 1] = id end
  table.sort(ids)

  local function line(name, extra)
    local ticks = frameCount(state, Core, name) * Core.TICKS
    if ticks <= 0 then return nil end
    local info = data.moves[name] or {}
    local l = { name = name, ticks = ticks, turns = info.turns, user = (info.user or info.cartUser) and true or false }
    for k, v in pairs(extra or {}) do l[k] = v end
    return l
  end

  if gen == 1 then
    local function record(ticks, tail)
      local seq = {}
      for i = 1, math.max(1, math.ceil(ticks / 10)) do seq[i] = { effect = "SE_DELAY_ANIMATION_10" } end
      for _, row in ipairs(tail or {}) do seq[#seq + 1] = row end
      return { seq = seq }
    end
    local function put(id, rec)
      local ok
      if anims:get(id) ~= nil then ok = pcall(anims.override, anims, id, rec)
      else ok = pcall(anims.register, anims, id, rec) end
      return ok
    end
    for _, id in ipairs(ids) do
      local name = Ess12.essName(data, id)
      if name and not Ess12.KEEP[name] then
        local okC, cart = pcall(anims.get, anims, id)
        cart = okC and type(cart) == "table" and cart or nil
        local swaps, tail = false, {}
        for _, row in ipairs(not newer[id] and cart and cart.seq or {}) do
          local e = type(row) == "table" and row.effect
          if e == "SE_TRANSFORM_MON" or e == "SE_SUBSTITUTE_MON" then swaps = true end
          if e and Ess12.LASTING[e] then tail[#tail + 1] = { effect = e } end
        end
        local l = not swaps and line(name, { kind = "move" }) or nil
        if l then
          if l.turns == "hide" then tail[#tail + 1] = { effect = "SE_SHOW_MON_PIC" } end
          if put(id, record(l.ticks, tail)) then
            state.lines[id] = l
            state.count = state.count + 1
          end
        elseif swaps then
          state.kept[#state.kept + 1] = id
        end
      end
    end
    for id, pick in pairs(Ess12.RED_COMMONS) do
      local names = type(pick) == "function" and { pick("BRN"), pick("PSN") } or { pick }
      local ticks = 0
      for _, n in ipairs(names) do ticks = math.max(ticks, frameCount(state, Core, n) * Core.TICKS) end
      if ticks > 0 and anims:get(id) ~= nil and put(id, record(ticks)) then
        state.lines[id] = { name = type(pick) == "string" and pick or nil, pick = type(pick) == "function" and pick or nil,
          ticks = ticks, kind = "status" }
      end
    end
  else
    local okM, base = pcall(anims.get, anims, "moves")
    local okS, scripts = pcall(anims.get, anims, "scripts")
    base = okM and type(base) == "table" and base or {}
    scripts = okS and type(scripts) == "table" and scripts or {}
    local addScripts, addMoves, addIds = {}, {}, {}
    local SWAP_OPS = { transform = true, raisesub = true, dropsub = true, minimizeopp = true, beatup = true }
    local function swapsPicture(key, seen)
      seen = seen or {}
      if not key or seen[key] then return false end
      seen[key] = true
      for _, row in ipairs(type(scripts[key]) == "table" and scripts[key] or {}) do
        if type(row) == "table" then
          if SWAP_OPS[row[1]] then return true end
          if (row[1] == "call" or row[1] == "jump") and swapsPicture(row[2], seen) then return true end
        end
      end
      return false
    end
    for _, id in ipairs(ids) do
      local name = Ess12.essName(data, id)
      local cartKey = base[id]
      if name and not Ess12.KEEP[name] then
        if not newer[id] and swapsPicture(cartKey) then
          state.kept[#state.kept + 1] = id
        else
          local l = line(name, { kind = "move" })
          if l then
            local rows = {}
            if l.turns and cartKey then rows[#rows + 1] = { "if_param_equal", 1, cartKey } end
            rows[#rows + 1] = { "wait", l.ticks - 1 }
            rows[#rows + 1] = { "ret" }
            local key = "ndx:" .. id
            addScripts[key], addMoves[id] = rows, key
            state.lines[key] = l
            state.count = state.count + 1
          end
        end
      end
    end
    local okI, idTable = pcall(anims.get, anims, "ids")
    idTable = okI and type(idTable) == "table" and idTable or {}
    for animId, name in pairs(Ess12.GOLD_COMMONS) do
      local ticks = frameCount(state, Core, name) * Core.TICKS
      if ticks > 0 and idTable[animId] then
        local key = "ndx:" .. animId
        addScripts[key] = { { "wait", ticks - 1 }, { "ret" } }
        addIds[animId] = key
        state.lines[key] = { name = name, ticks = ticks, kind = "status" }
      end
    end
    local ok = next(addScripts) == nil or pcall(anims.patch, anims, "scripts", addScripts)
    ok = ok and (next(addMoves) == nil or pcall(anims.patch, anims, "moves", addMoves))
    ok = ok and (next(addIds) == nil or pcall(anims.patch, anims, "ids", addIds))
    if not ok then state.lines, state.count = {}, 0 end
  end
  return state
end

-- ---------- playing -----------------------------------------------------------------------------

local function level(b, gen)
  local o
  if gen == 1 then o = b.game and b.game.save and b.game.save.options
  else o = b.game and b.game.options end
  local v = tonumber(o and o.sfxVol) or 7
  return math.max(0, math.min(7, v)) / 7
end

-- the battle's two battlers: { side = { battler, mon, species, status } }
local function sides(b, gen)
  if gen == 1 then
    local function of(x)
      if not x then return nil end
      return { battler = x, mon = x.mon, species = x.mon and x.mon.species, status = x.mon and x.mon.status }
    end
    return { player = of(b.player), enemy = of(b.enemy) }
  end
  local battle = b.battle
  local function of(m)
    if not m then return nil end
    return { battler = m, mon = m, species = m.species, status = m.status }
  end
  return { player = of(battle and battle.player), enemy = of(battle and battle.enemy) }
end

-- Red's battle.overlay hook (set at load: hooks are wrapped then): in the wide layout, every layer
-- over the field (its side regions have no room for cels that cross between them)
function Ess12.overlayHook(require)
  local BS   -- (looked up once: a require every frame makes garbage through the mod's require)
  return function(nextFn, b, ...)
    local r = nextFn(b, ...)
    if type(b) ~= "table" or type(b.wideLayout) ~= "function" or not b:wideLayout() then return r end
    if BS == nil then
      local okB, mod = pcall(require, "src.battle.BattleState")
      BS = okB and type(mod) == "table" and mod or false
    end
    local h = BS and BS.__ndxEss
    local st = h and h.st
    if not (st and st.b == b and st.wide and not st.none and h.drawLayer and love and love.graphics) then return r end
    local G = love.graphics
    G.push("all")
    local x1, y1 = G.transformPoint(0, 0)
    local x2, y2 = G.transformPoint(Ess12.WIDE.w, Ess12.WIDE.field)
    G.intersectScissor(math.min(x1, x2), math.min(y1, y2), math.abs(x2 - x1), math.abs(y2 - y1))
    for k = st.backDrawn and 2 or 1, 3 do h.drawLayer(st, k) end
    st.backDrawn = nil
    G.pop()
    return r
  end
end

-- opts: { state (Ess12.register's), Core, require, log }
function Ess12.install(opts)
  local state, Core, require, log = opts.state, opts.Core, opts.require, opts.log
  local gen = state.generation
  if state.count == 0 then return false end
  local G = love and love.graphics
  local hub

  -- what is playing on this battle now: { key, ticks, side (the attacker's) , param }
  local function playing(b)
    if gen == 1 then
      if not (b.animPlaying and b.animName and state.lines[b.animName]) then return nil end
      local p = b.animPlayer
      return b.animName, tonumber(p and p.elapsed) or 0, b.animAttackerIsPlayer and "player" or "enemy", nil, p
    end
    local anim = b.anim
    if not (anim and not anim.stopped and anim.__ndxKey and state.lines[anim.__ndxKey]) then return nil end
    local env = anim.env or EMPTY
    return anim.__ndxKey, tonumber(anim.frames) or 0, (env.battleTurn or 0) == 0 and "player" or "enemy",
      anim.__ndxParam, anim
  end

  local function play(e, st)
    local id = e.se
    if id == "CRY" then
      local s = st.sideInfo[st.attacker]
      local okS, Sound = pcall(require, "src.core.Sound")
      local data = gen == 1 and st.b.data or (st.b.game and st.b.game.data)
      if okS and s and s.species and data then
        if gen == 1 and Sound.playMoveCry then pcall(Sound.playMoveCry, data, s.species)
        elseif Sound.playCry then pcall(Sound.playCry, data, s.species) end
      end
      return
    end
    if not (id and state.data.sounds and state.data.sounds[id]) then return end
    local okC, ChipAudio = pcall(require, "src.core.ChipAudio")
    local suspended = false
    if okC and type(ChipAudio) == "table" and ChipAudio.isSuspended then
      local okS, s = pcall(ChipAudio.isSuspended)
      suspended = okS and s and true or false
    end
    local okR, Sound = pcall(require, "src.core.Sound")
    local rate = okR and type(Sound) == "table" and Sound.rate and tonumber(Sound.rate()) or 1
    Core.playSound(state, id, level(st.b, gen), rate, suspended)
  end

  -- a battler's own cel: its pose while this frame lasts (false: Essentials hides it)
  local function setMon(st, which, c)
    local side = which == "user" and st.uSide or st.tSide
    if not c then
      st.pose[side] = false
      return
    end
    -- (one pose table per side for the whole animation, filled in place)
    local p = st.poses[side]
    if not p then p = {}; st.poses[side] = p end
    p.dx, p.dy, p.sx, p.sy, p.rot, p.a = Core.monPose(st, which, c)
    st.pose[side] = p
  end

  local C = Ess12.CENTRE[gen]
  local function begin(b, key, ticks, attacker, param)
    local l = state.lines[key]
    local info = sides(b, gen)
    local name = l.name
    if l.pick then
      local s = info[attacker]
      name = l.pick(s and s.status)
    end
    local md = name and Core.moveData(state, name)
    if not md then return false end
    local foe = attacker == "enemy"
    local defender = foe and "player" or "enemy"
    local anim, opp = md.move, false
    if l.kind == "status" then
      -- the afflicted battler is the animation's user and target
      defender = attacker
    elseif foe and md.opp then
      anim, opp = md.opp, true
    end
    if l.turns and param == 1 then return false end   -- a two-turn move's first turn: the cart's own
    local uSide, tSide = attacker, defender
    if opp then uSide, tSide = defender, attacker end
    if l.user then uSide, tSide = attacker, attacker end
    local u, t = C[uSide], C[tSide]
    local wide = gen == 1 and type(b.wideLayout) == "function" and b:wideLayout() and true or false
    local W = Ess12.WIDE
    local ux, uy, tx, ty = u[1], u[2], t[1], t[2]
    if wide then
      ux, uy = ux + W[uSide][1], uy + W[uSide][2]
      tx, ty = tx + W[tSide][1], ty + W[tSide][2]
    end
    local st = Core.start(state, anim, {
      ux = ux, uy = uy, tx = tx, ty = ty, uSide = uSide, tSide = tSide, w = wide and W.w or 160, h = 144,
      scale = (tonumber(state.data.scale) or 0.375) * Ess12.CEL_SCALE, celScale = Ess12.CEL_SCALE,
      setMon = setMon, play = play, drawCopy = hub.drawCopy, onUser = l.user and true or nil,
    })
    st.b, st.key, st.attacker, st.sideInfo, st.pose, st.poses, st.lastTicks = b, key, attacker, info, {}, {}, -1
    st.hideMove, st.wide = l.turns == "hide", wide
    if st.hideMove then
      -- Fly's / Dig's return: its user is back from the start, as the pack plays it (the cart's own
      -- script would have shown it as it went; Red: its picture's hide, Gold: the vanish latch,
      -- which revealVanished would have cleared)
      if gen == 1 then
        local battler = attacker == "player" and b.player or b.enemy
        local pf = battler and type(b.picFxFor) == "function" and b:picFxFor(battler)
        if pf then pf.hidden, pf.persistHide = false, nil end
      else
        if type(b.picHidden) == "table" then b.picHidden[attacker] = false end
        if type(b.vanishReveal) == "table" then b.vanishReveal[attacker] = nil end
      end
    end
    return st
  end

  -- the animation playing on this battle, stepped to now (every frame since the last draw, so a fast
  -- game speed keeps its sounds); nil when none of ours is
  local function current(b)
    local key, ticks, attacker, param, run = playing(b)
    local st = hub.st
    if not key then
      if st and st.b == b then hub.st = nil end
      return nil
    end
    if not st or st.b ~= b or st.key ~= key or st.run ~= run or ticks < st.lastTicks then
      st = begin(b, key, ticks, attacker, param)
      if not st then
        hub.st = { b = b, key = key, run = run, lastTicks = ticks, none = true }
        return nil
      end
      st.run = run
      hub.st = st
    end
    if st.none then
      st.lastTicks = ticks
      return nil
    end
    local frame = math.floor(ticks / Core.TICKS)
    if frame >= st.last then frame = st.last - 1 end
    while st.frame < frame do
      st.frame = st.frame + 1
      Core.step(state, st, st.frame)
    end
    st.lastTicks = ticks
    return st
  end

  local function drawLayer(st, k)
    if not G then return end
    local ok, err = pcall(Core.drawLayer, state, st, k)
    if not ok and log and not hub.warned then
      hub.warned = true
      log:warn("a Gen 9 project animation failed to draw: %s", tostring(err))
    end
    G.setColor(1, 1, 1, 1)
  end

  -- the sounds: decoded a little each frame ahead of their animation (battle.move_used queues them)
  local function stepQueue()
    local q = hub.queue
    if not q or #q == 0 or not (love and love.timer) then return end
    local deadline = love.timer.getTime() + 0.002
    repeat
      local id = table.remove(q, 1)
      if id and state.sources[id] == nil then Core.soundSource(state, id) end
    until #q == 0 or love.timer.getTime() >= deadline
  end

  -- one hub per process and generation (the engine modules outlive a mod reload)
  local okB, BS
  if gen == 1 then okB, BS = pcall(require, "src.battle.BattleState")
  else okB, BS = pcall(require, "src.ui.gen2.BattleState") end
  if not (okB and type(BS) == "table") then return false end
  hub = BS.__ndxEss
  local fresh = not hub
  if fresh then
    hub = {}
    BS.__ndxEss = hub
  end
  hub.state, hub.current, hub.drawLayer, hub.stepQueue, hub.queue = state, current, drawLayer, stepQueue, {}
  hub.st = nil

  if gen == 1 then
    -- a copy of a battler's picture (a free cel): the picture drawn again where the cel stands, with
    -- the arguments it was last drawn with
    function hub.drawCopy(st, which, x, y, sx, sy, rot, a)
      local side = which == "user" and st.uSide or st.tSide
      local s = st.sideInfo[side]
      local args = s and hub.args and hub.args[s.battler]
      if not args or not G then return end
      local cx, cy = args.cx, args.cy
      G.push()
      G.translate(x, y)
      G.rotate(rot)
      G.scale(sx, sy)
      G.translate(-cx, -cy)
      G.setColor(1, 1, 1, a)
      hub.rawPic(st.b, s.battler, args.x, args.y, args.scale, args.shakeX, args.shakeY)
      G.pop()
      G.setColor(1, 1, 1, 1)
    end
    if fresh and type(BS.drawPicsLayer) == "function" and type(BS.drawBattlerPic) == "function" then
      local drawPicsLayer, drawBattlerPic = BS.drawPicsLayer, BS.drawBattlerPic
      hub.rawPic = drawBattlerPic
      hub.args = setmetatable({}, { __mode = "k" })
      BS.drawPicsLayer = function(self, slide, sx, sy, onlySide, skipMenuClip, ...)
        local h = BS.__ndxEss
        if h.stepQueue then pcall(h.stepQueue) end
        local okC, st = pcall(h.current, self)
        if okC and st and onlySide and st.wide then
          -- the wide layout's side regions: the pictures' own cels; the back band (background, cels
          -- behind) under them from your side's region, drawn first, out of its clip and offset; the
          -- rest from the overlay
          if onlySide == "player" and G then
            local W = Ess12.WIDE
            G.push("all")
            G.translate(-W.player[1], -W.player[2])
            local x1, y1 = G.transformPoint(0, 0)
            local x2, y2 = G.transformPoint(W.w, W.field)
            G.setScissor(math.min(x1, x2), math.min(y1, y2), math.abs(x2 - x1), math.abs(y2 - y1))
            h.drawLayer(st, 1)
            G.pop()
            st.backDrawn = true
          end
          h.drawing = st
          local ok, err = pcall(drawPicsLayer, self, slide, sx, sy, onlySide, skipMenuClip, ...)
          h.drawing = nil
          if not ok then error(err, 0) end
          return
        end
        if not okC or not st or onlySide or self.grayPics or st.wide then
          h.drawing = nil
          return drawPicsLayer(self, slide, sx, sy, onlySide, skipMenuClip, ...)
        end
        h.drawing, st.mid = st, false
        local moved = (sx or 0) ~= 0 or (sy or 0) ~= 0
        if moved then G.push(); G.translate(sx or 0, sy or 0) end
        h.drawLayer(st, 1)
        if moved then G.pop() end
        local ok, err = pcall(drawPicsLayer, self, slide, sx, sy, onlySide, skipMenuClip, ...)
        if moved then G.push(); G.translate(sx or 0, sy or 0) end
        if not st.mid then h.drawLayer(st, 2) end
        h.drawLayer(st, 3)
        if moved then G.pop() end
        h.drawing = nil
        if not ok then error(err, 0) end
      end
      BS.drawBattlerPic = function(self, battler, x, y, scale, shakeX, shakeY, ...)
        local h = BS.__ndxEss
        local img = type(self.picImage) == "function" and battler and battler.sprite and self:picImage(battler.sprite)
        if img then
          -- (one record per battler, filled in place: this runs for every picture every frame)
          local s = scale or 1
          local a = h.args[battler]
          if not a then a = {}; h.args[battler] = a end
          a.x, a.y, a.scale, a.shakeX, a.shakeY = x, y, scale, shakeX, shakeY
          a.cx, a.cy = x + img:getWidth() * s / 2, y + img:getHeight() * s / 2
        end
        local st = h.drawing
        if not (st and st.b == self) then return drawBattlerPic(self, battler, x, y, scale, shakeX, shakeY, ...) end
        local side = battler == self.player and "player" or battler == self.enemy and "enemy" or nil
        if side == "player" and not st.mid and not st.wide then
          st.mid = true
          h.drawLayer(st, 2)
        end
        local pose = side and st.pose[side]
        if pose == nil then return drawBattlerPic(self, battler, x, y, scale, shakeX, shakeY, ...) end
        if pose == false or pose.a <= 0.01 then return end
        local a = h.args[battler]
        local cx, cy = a and a.cx or x, a and a.cy or y
        G.push()
        G.translate(cx + pose.dx, cy + pose.dy)
        G.rotate(pose.rot)
        G.scale(pose.sx, pose.sy)
        G.translate(-cx, -cy)
        G.setColor(1, 1, 1, pose.a)
        local ok, err = pcall(drawBattlerPic, self, battler, x, y, scale, shakeX, shakeY, ...)
        G.pop()
        G.setColor(1, 1, 1, 1)
        if not ok then error(err, 0) end
      end
    end
  else
    function hub.drawCopy(st, which, x, y, sx, sy, rot, a)
      local side = which == "user" and st.uSide or st.tSide
      local s = st.sideInfo[side]
      if not (s and s.mon and G) or a < 0.5 then return end
      local c = C[side]
      G.push()
      G.translate(x, y)
      G.rotate(rot)
      G.scale(sx, sy)
      G.translate(-c[1], -c[2])
      hub.copying = true
      pcall(hub.rawPic, st.b, s.mon, side == "player")
      hub.copying = nil
      G.pop()
      G.setColor(1, 1, 1, 1)
    end
    if fresh and type(BS.drawPics) == "function" and type(BS.drawPic) == "function"
        and type(BS.startAnim) == "function" then
      local drawPics, drawPic, startAnim = BS.drawPics, BS.drawPic, BS.startAnim
      hub.rawPic = drawPic
      -- both pictures with the cels between them (a function of its own: no closure a frame)
      local function both(self, h, st)
        self:drawPic(self:activeMon("enemy"), false)
        h.drawLayer(st, 2)
        self:drawPic(self:activeMon("player"), true)
      end
      BS.startAnim = function(self, key, opts2, ...)
        local r = startAnim(self, key, opts2, ...)
        if r and self.anim then
          self.anim.__ndxKey = key
          self.anim.__ndxParam = self.anim.param
        end
        return r
      end
      BS.drawPics = function(self, ...)
        local h = BS.__ndxEss
        if h.stepQueue then pcall(h.stepQueue) end
        local okC, st = pcall(h.current, self)
        if not okC or not st or self.captureScreen or type(self.activeMon) ~= "function" then
          h.drawing = nil
          return drawPics(self, ...)
        end
        h.drawing = st
        h.drawLayer(st, 1)
        local ok, err = pcall(both, self, h, st)
        h.drawLayer(st, 3)
        h.drawing = nil
        if not ok then error(err, 0) end
      end
      BS.drawPic = function(self, mon, back, ...)
        local h = BS.__ndxEss
        local st = h.drawing
        if not (st and st.b == self) or h.copying or self.liftedPass then return drawPic(self, mon, back, ...) end
        local side = back and "player" or "enemy"
        local pose = st.pose[side]
        if pose == nil then return drawPic(self, mon, back, ...) end
        if pose == false or pose.a < 0.5 then return end
        local c = Ess12.CENTRE[2][side]
        G.push()
        G.translate(c[1] + pose.dx, c[2] + pose.dy)
        G.rotate(pose.rot)
        G.scale(pose.sx, pose.sy)
        G.translate(-c[1], -c[2])
        local ok, err = pcall(drawPic, self, mon, back, ...)
        G.pop()
        if not ok then error(err, 0) end
      end
    end
  end

  -- the sounds ahead of time: every move in both parties and the common animations' when the battle
  -- starts, the move about to animate first; all of them go when the battle ends
  local function queue(names, first)
    local h = BS.__ndxEss
    if not (h and h.state == state) then return end
    for _, s in ipairs(Core.moveSounds(state, names)) do
      if first then table.insert(h.queue, 1, s) else h.queue[#h.queue + 1] = s end
    end
  end
  if opts.mod and opts.mod.events and opts.mod.events.on and not state.listening then
    state.listening = true
    opts.mod.events:on("battle.started", function(ev)
      local b = ev and ev.battle
      if type(b) ~= "table" then return end
      local parties
      if gen == 1 then
        local okP, mine = pcall(function() return b:playerPartyView() end)
        parties = { okP and mine or (b.game and b.game.save and b.game.save.party) or {}, b.enemyParty or {} }
      else
        parties = { b.party or {}, b.enemyParty or {} }
      end
      local names = {}
      for _, party in ipairs(parties) do
        for _, mon in ipairs(party) do
          for _, mv in ipairs(type(mon) == "table" and type(mon.moves) == "table" and mon.moves or {}) do
            local name = Ess12.essName(state.data, type(mv) == "table" and mv.id or mv)
            if name then names[#names + 1] = name end
          end
        end
      end
      queue(names)
      local h = BS.__ndxEss
      if h and h.state == state then
        for _, s in ipairs(state.data.commonSounds or {}) do h.queue[#h.queue + 1] = s end
      end
    end)
    opts.mod.events:on("battle.move_used", function(ev)
      local id = ev and (ev.moveId or (ev.move and (ev.move.id or ev.move.name)))
      local name = Ess12.essName(state.data, id)
      if name then queue({ name }, true) end
    end)
    opts.mod.events:on("battle.ended", function()
      local h = BS.__ndxEss
      if h and h.state == state then Core.dropSounds(state) end
    end)
  end
  if log then log:info("Gen 9 project animations: %d moves and animations", state.count) end
  return true
end

return Ess12
