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
-- `present` offsets, put back when it ends. Sounds are the cart's (by name) or the pack's (one file
-- of them, played here: see "the pack's sounds"). Without graphics (headless, or a missing file) the
-- task still takes its time.
local EssAnims = {}

-- The shared part (src/ess_core.lua: the data, the atlas, placing and drawing cels, the pack's
-- sounds) is EssAnims.Core, which main.lua sets after loading both.
EssAnims.Core = nil

-- ---------- the pack's sounds ----------------------------------------------------------------
-- (src/ess_core.lua decodes and plays them.) Here they warm on the engine's own queue
-- (src/core/game3/warm.lua, a little each frame): battle.started queues the sounds of every move in
-- both parties and the common animations', battle.move_used the move about to animate; battle.ended
-- drops them. The volume is the engine's for a mod sound (0.8 x Audio._sfxVolume, the sound volume
-- option), at Sound.rate(), and nothing while ChipAudio is suspended.

-- the sound's Source, decoded now if it isn't yet; nil without audio or when it can't be
function EssAnims.soundSource(state, id)
  return EssAnims.Core.soundSource(state, id)
end

-- decode these sounds ahead of time on the engine's warm queue (lower priority runs sooner)
function EssAnims.prewarm(state, ids, priority)
  local ok, Warm = pcall(state and state.require or require, "src.core.game3.warm")
  if not (ok and type(Warm) == "table" and Warm.add) then return 0 end
  return EssAnims.Core.prewarm(state, ids, priority, Warm.add)
end

-- battle.started: every move in both parties, and the common animations' sounds
function EssAnims.prewarmBattle(state, battle)
  if not (state and state.data) then return 0 end
  local ids = {}
  for _, party in ipairs({ battle and battle.playerParty or {}, battle and battle.foeParty or {} }) do
    for _, mon in ipairs(party) do
      if type(mon) == "table" and type(mon.moves) == "table" then EssAnims.Core.moveSounds(state, mon.moves, ids) end
    end
  end
  for _, id in ipairs(state.data.commonSounds or {}) do ids[#ids + 1] = id end
  return EssAnims.prewarm(state, ids, 6)
end

-- play a pack sound; false when the id isn't one
function EssAnims.playSound(state, id, require)
  if not (state and state.data and state.data.sounds and state.data.sounds[id]) then return false end
  local okC, ChipAudio = pcall(require, "src.core.ChipAudio")
  local suspended = false
  if okC and type(ChipAudio) == "table" and ChipAudio.isSuspended then
    local okS, susp = pcall(ChipAudio.isSuspended)
    suspended = okS and susp and true or false
  end
  local okA, Audio = pcall(require, "src.core.game3.audio")
  local level = okA and type(Audio) == "table" and tonumber(Audio._sfxVolume) or 1
  local okR, Sound = pcall(require, "src.core.Sound")
  local rate = okR and type(Sound) == "table" and Sound.rate and tonumber(Sound.rate()) or 1
  return EssAnims.Core.playSound(state, id, level, rate, suspended)
end

-- the battle events that warm and drop the sounds; once per mod load, from main.lua
function EssAnims.listen(mod, require)
  local events = mod and mod.events
  if not (events and events.on) then return false end
  local function state()
    local ok, AnimTasks = pcall(require, "src.core.game3.battle.anim_tasks")
    local st = ok and type(AnimTasks) == "table" and AnimTasks.__ndxEss or nil
    return st and st.data and st.sources and st or nil
  end
  events:on("battle.started", function(ev)
    local st = state()
    if st then EssAnims.prewarmBattle(st, ev and ev.battle) end
  end)
  events:on("battle.move_used", function(ev)
    local st = state()
    if st and ev and ev.moveNum then EssAnims.prewarm(st, EssAnims.Core.moveSounds(st, { ev.moveNum }), 1) end
  end)
  events:on("battle.ended", function()
    local st = state()
    if st then EssAnims.Core.dropSounds(st) end
  end)
  return true
end

local PREFIX = "national_dex_gen3:ess:"

-- opts: { mod (for mod.path), data (data/ess_anims.lua), read (path -> loaded table), moves
-- (src/moves.lua's registered rows: id, index), require, log }; after src/anims.lua's install
function EssAnims.install(opts)
  local require, log, data = opts.require, opts.log, opts.data
  local Core = EssAnims.Core
  if type(data) ~= "table" or type(data.moves) ~= "table" or type(data.sheets) ~= "table" then return false end
  if type(Core) ~= "table" then
    if log then log:warn("Gen 9 project move animations are off: src/ess_core.lua did not load") end
    return false
  end
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
  Core.setData(state, opts)
  -- the running game's move numbers: the newer moves' slots, the carts' own numbers
  state.byNum = {}
  for _, r in ipairs(opts.moves or {}) do
    if r.index and r.id and data.moves[r.id] then state.byNum[tonumber(r.index)] = r.id end
  end
  for name, m in pairs(data.moves) do
    if m.num then state.byNum[m.num] = name end
  end
  state.scripts = setmetatable({}, { __mode = "k" })   -- pack -> name -> script
  EssAnims.wrap(state, Anim, require)
  if state.task then
    AnimTasks.REGISTRY.NdxEss = state.task
    AnimTasks.REGISTRY.NdxEssLayer = state.layer
    return true
  end

  local hasLove = Core.hasLove()
  local C = Core.CEL

  local function moveData(move) return Core.moveData(state, move) end

  local function sideOf(id, fallback)
    if AnimCoords and AnimCoords.sideOf and id ~= nil then
      local ok, s = pcall(AnimCoords.sideOf, id)
      if ok and s then return s end
    end
    return fallback
  end

  -- the battlers' `present` fields this task changes, to put back
  local KEEP = { "ox", "oy", "sx", "sy", "rotation", "alpha", "palAffine" }

  -- a battler's own cel: its picture's `present` offsets, tone and colour
  local function setMon(st, which, c)
    local id = which == "user" and st.uId or st.tId
    local m = id ~= nil and st.mons[id]
    if not m then return end
    local p = m.p
    if not c then
      p.alpha = 0   -- Essentials hides a battler with no cel in the frame
      return
    end
    p.ox, p.oy, p.sx, p.sy, p.rotation, p.alpha = Core.monPose(st, which, c)
    -- Essentials' tone (added to each channel) then colour (mixed in by its alpha), as the battle's
    -- palette affine (each channel times m, plus an offset): exact, gray aside
    local a = (c[C.CA] or 0) / 255
    local tr, tg, tb = (c[C.TR] or 0) / 255, (c[C.TG] or 0) / 255, (c[C.TB] or 0) / 255
    if a > 0 or tr ~= 0 or tg ~= 0 or tb ~= 0 then
      local k = 1 - a
      -- (one table per battler for the whole animation, filled in place: the battle reads it fresh)
      local aff = m.aff
      if not aff then aff = {}; m.aff = aff end
      aff.m, aff.r, aff.g, aff.b = k, tr * k + (c[C.CR] or 0) / 255 * a, tg * k + (c[C.CG] or 0) / 255 * a,
        tb * k + (c[C.CB] or 0) / 255 * a
      p.palAffine = aff
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

  -- a sound timing: the cart's sound by name, the pack's, or (no name) the attacker's cry
  local function play(e, st)
    local se = e.se
    if not se then return end
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
    if EssAnims.playSound(state, se, require) then return end
    if Audio.playSe then pcall(Audio.playSe, se, { pan = 0 }) end
  end

  -- a battler's picture as the battle shows it (Ui.battlerPic), once per animation: 64 px wide
  local function copyPic(st, which)
    local id = which == "user" and st.uId or st.tId
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
    if not pic then return nil end
    return pic, 64 / pic:getWidth()
  end

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
    local onUser = (tonumber(t.data[2]) or 0) == 1
    if onUser then uKey, tKey = "attacker", "attacker" end   -- a move on its user
    local ux, uy = vm:battlerCenter(uKey)
    local tx, ty = vm:battlerCenter(tKey)
    local uId = uKey == "attacker" and vm:attackerId() or vm:targetId()
    local tId = tKey == "attacker" and vm:attackerId() or vm:targetId()
    local st = Core.start(state, anim, {
      ux = ux, uy = uy, tx = tx, ty = ty, w = 240, h = 160,
      uSide = sideOf(uId, uKey == "attacker" and vm:attackerSide() or vm:targetSide()),
      tSide = sideOf(tId, tKey == "attacker" and vm:attackerSide() or vm:targetSide()),
      setMon = setMon, play = play, copyPic = copyPic, onUser = onUser,
    })
    st.move, st.vm, st.mons, st.uId, st.tId = move, vm, {}, uId, tId
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
    return st
  end

  local function drawMain(t)
    local st = t._ndxEss
    if st then Core.drawLayer(state, st, 1) end
  end

  local function layer(t, vm)
    local parent = t._ndxEssParent
    if not (parent and parent.active and parent._ndxEss == t._ndxEssState) then AnimTasks.destroy(t) end
  end
  local function drawHelper(t)
    local st = t._ndxEssState
    if st then Core.drawLayer(state, st, t._ndxEssLayer) end
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
      Core.step(state, st, 0)
      return
    end
    st.tick = st.tick + 1
    local frame = math.floor(st.tick / Core.TICKS)
    if frame >= st.last then
      restore(st)
      t._ndxEss = nil
      AnimTasks.destroy(t)
      return
    end
    if frame ~= st.frame then
      st.frame = frame
      Core.step(state, st, frame)
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
