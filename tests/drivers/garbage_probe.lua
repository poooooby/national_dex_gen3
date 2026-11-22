-- Driver: how much Lua garbage a frame makes in a real game, where WoobleDex draws every frame: the
-- overworld standing still (Day & Night), a battle's menu with stat changes on both sides (type
-- badges, Stat Hints, the animation wraps), and Gen 9 Move Animation Project animations as they play.
-- Each figure is bytes made a frame, the collector held still (the engine's own garbage included:
-- run it again with WoobleDex off for the baseline, or before and after a change). Any game:
--   SHOT_DIR=<dir> POKEPORT_VERSION=red|gold|emerald [POKEPORT_GAME=emerald] \
--   POKEPORT_DRIVER=mods/national_dex_gen3/tests/drivers/garbage_probe.lua love .
-- FRAMES=600 the idle stretches; MOVES=NIGHT_SLASH,... the animations (each played twice, the second
-- measured: the first loads its frames and pictures). Run it with only WoobleDex in the game's mod
-- list (other mods' hooks cost the engine garbage too). 2026-11-21, bytes a frame (WoobleDex off):
--   Red      overworld 3383 (3494)   battle menu 10718 (8591)    animations ~10.8K
--   Gold     overworld 3913 (4103)   battle menu 10390 (7489)    animations ~8.6K
--   Emerald  overworld 7198 (7200)   battle menu 15236 (12008)   animations ~15.5K (cart's ~13.3K)

local U = require("tests.drivers.util")

-- The engine steps the collector itself every frame (Game3.stepGC; Game every fourth frame), and a
-- "step" collects even while the collector is stopped: a measurement would count what was made
-- less what those steps freed (with a small heap, every frame's garbage, so ~0). While measuring,
-- the global collectgarbage ignores "step" and "collect".
local realGC = collectgarbage
local function quiet(opt, ...)
  if opt == "step" or opt == "collect" then return 0 end
  return realGC(opt, ...)
end
local function stopGC()
  realGC("collect")
  realGC("stop")
  _G.collectgarbage = quiet
end
local function startGC()
  _G.collectgarbage = realGC
  realGC("restart")
end
local function kb() return realGC("count") end

local FRAMES = tonumber(os.getenv("FRAMES") or "") or 600
local MOVES = os.getenv("MOVES") or "NIGHT_SLASH,DARK_PULSE,AXE_KICK,FLAMETHROWER,SURF,PSYCHIC"

-- PROFILE=1: each idle stretch also says which Lua functions made its garbage (a call / return hook
-- on the game's main thread charges the memory made since the last event to the function running:
-- a C function's to its Lua caller). TOP=n lines.
local PROFILE = os.getenv("PROFILE") == "1"
local TOP = tonumber(os.getenv("TOP") or "") or 30
local plog

local function where(level)
  local info = debug.getinfo(level, "Sn")
  if not info then return "?" end
  if info.what == "C" then
    local up = debug.getinfo(level + 1, "Sl")
    return (up and (up.short_src .. ":" .. tostring(up.currentline)) or "?") .. " (" .. tostring(info.name) .. ")"
  end
  return info.short_src .. ":" .. tostring(info.linedefined)
end

-- the nearest WoobleDex line on the stack from `level` up (what set the engine's code going), or nil
local function ours(level)
  for l = level, level + 40 do
    local info = debug.getinfo(l, "Sl")
    if not info then return nil end
    if info.short_src:find("national_dex_gen3", 1, true) and not info.short_src:find("garbage_probe", 1, true) then
      return info.short_src:gsub("^.*national_dex_gen3/", "") .. ":" .. tostring(info.currentline)
    end
  end
  return nil
end

-- for the engine's mod plumbing (Hooks / UnifiedCallbacks / Events): the hook or event name it
-- is calling, read off a function's `name` local or upvalue on the stack
local PLUMBING = { ["src/mods/Hooks.lua"] = true, ["src/mods/UnifiedCallbacks.lua"] = true,
  ["src/mods/Events.lua"] = true, ["src/mods/Loader.lua"] = true }
local function plumbing(level)
  local info = debug.getinfo(level, "S")
  if not (info and PLUMBING[info.short_src]) then return nil end
  for l = level, level + 30 do
    local i = debug.getinfo(l, "f")
    if not i then break end
    for k = 1, 60 do
      local n, v = debug.getlocal(l, k)
      if not n then break end
      if n == "name" and type(v) == "string" then return v end
    end
    for k = 1, 60 do
      local n, v = debug.getupvalue(i.func, k)
      if not n then break end
      if n == "name" and type(v) == "string" then return v end
    end
  end
  return "?"
end

local function profile(frames, label)
  local bytes, last = {}, nil
  local function hook(ev)
    local now = kb()
    if last then
      local d = now - last
      if d > 0 then
        local lv = ev == "return" and 3 or 4
        local k = where(lv)
        bytes[k] = (bytes[k] or 0) + d
        local pl = plumbing(lv)
        if pl then
          local kk = "  <- hook/event " .. pl
          bytes[kk] = (bytes[kk] or 0) + d
        end
        local o = ours(lv)
        if o then
          local kk = "  <- " .. o
          bytes[kk] = (bytes[kk] or 0) + d
        end
      end
    end
    last = kb()
  end
  -- set and cleared from inside a frame's own draw (the main thread's), not this coroutine
  local G = love.graphics
  local origin = G.origin
  local want, done = "on", false
  G.origin = function(...)
    if want == "on" then debug.sethook(hook, "cr"); want = nil
    elseif want == "off" then debug.sethook(); want = nil; done = true end
    return origin(...)
  end
  stopGC()
  U.wait(frames)
  want = "off"
  for _ = 1, 30 do if done then break end U.wait(1) end
  G.origin = origin
  startGC()
  local list = {}
  for k, v in pairs(bytes) do list[#list + 1] = { k, v * 1024 / frames } end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  plog(("  profile %s (bytes a frame):"):format(label))
  local mine = 0
  for _, e in ipairs(list) do if e[1]:find("national_dex_gen3", 1, true) and not e[1]:find("<-", 1, true) then mine = mine + e[2] end end
  plog(("    WoobleDex's own functions: %.0f"):format(mine))
  local shown = 0
  for i = 1, #list do
    if not list[i][1]:find("<-", 1, true) and shown < TOP then
      shown = shown + 1
      plog(("    %7.0f  %s"):format(list[i][2], list[i][1]))
    end
  end
  plog("    with a WoobleDex line on the stack (the line nearest the allocation):")
  for i = 1, #list do
    if list[i][1]:find("<-", 1, true) and list[i][2] >= 8 then plog(("    %7.0f %s"):format(list[i][2], list[i][1])) end
  end
end

-- bytes a frame over `frames` frames, the collector stopped
local function rate(frames, label)
  stopGC()
  local kb0 = kb()
  U.wait(frames)
  local b = (kb() - kb0) * 1024 / frames
  startGC()
  if PROFILE and label then profile(math.min(frames, 120), label) end
  return b
end

-- a meter for frames only while busy() holds: step() once a frame
local function meter()
  local m = { bytes = 0, frames = 0 }
  function m.frame(busy)
    local kb0 = kb()
    U.wait(1)
    if busy() then
      m.bytes = m.bytes + (kb() - kb0) * 1024
      m.frames = m.frames + 1
    end
  end
  function m.per() return m.frames > 0 and m.bytes / m.frames or 0 end
  return m
end

local function moveList()
  local list = {}
  for id in MOVES:gmatch("[%w_]+") do list[#list + 1] = id end
  return list
end

local function gen3(game, log)
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "GC", gender = 0 })
  U.wait(240)
  -- JITV=1: the JIT's trace aborts over 300 frames of the overworld, by line, into
  -- SHOT_DIR/jit_events.txt (error number: lj_traceerr.h's order; 7 is "NYI: bytecode"). A mod
  -- function on the frame's path that cannot be compiled leaves the engine's frame code around it
  -- interpreted, making garbage compiled code would not.
  local okJU, JU = pcall(require, "jit.util")
  if os.getenv("JITV") == "1" and jit and jit.attach and okJU then
    local counts = {}
    local function at(func, pc)
      local okI, i = pcall(JU.funcinfo, func, pc)
      return okI and i and ((i.source or "?"):gsub("^@", "") .. ":" .. tostring(i.currentline)) or "?"
    end
    local function cb(what, tr, func, pc, otr, oex)
      if what == "abort" then
        local k = "abort e" .. tostring(otr) .. (oex and ("/" .. tostring(oex)) or "") .. " " .. at(func, pc)
        counts[k] = (counts[k] or 0) + 1
      elseif what == "stop" then
        counts["stop " .. at(func, pc)] = (counts["stop " .. at(func, pc)] or 0) + 1
      end
    end
    jit.flush()
    jit.attach(cb, "trace")
    U.wait(300)
    jit.attach(cb)
    local list = {}
    for k, n in pairs(counts) do list[#list + 1] = { k, n } end
    table.sort(list, function(x, y) return x[2] > y[2] end)
    local f = io.open((os.getenv("SHOT_DIR") or ".") .. "/jit_events.txt", "w")
    for _, e in ipairs(list) do f:write(("%5d %s"):format(e[2], e[1]), string.char(10)) end
    f:close()
    log(("jit events: %d kinds"):format(#list))
  end
  log(("overworld, standing still: %.0f bytes a frame"):format(rate(FRAMES, "overworld")))

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local Healthbox = require("src.core.game3.battle.healthbox")
  local GAME = require("src.core.GameVersion").get()
  local C = require("src.core.game3.constants").of(GAME)
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_BLAZIKEN or C.species.byName.SPECIES_CHARIZARD, 50, "HERO")
  local started = BattleBridge.startWild(Runtime._mod, game,
    { species = C.species.byName.SPECIES_SWAMPERT or C.species.byName.SPECIES_BLASTOISE, level = 50 }, { fade = false })
  if not started then log("FAIL wild battle"); return end
  waitFor(function()
    if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") end
    return Battle.isActive() and Ui._mode == "menu" and not Anim.busy()
  end, 3000)
  U.wait(60)
  local st = Battle._st
  st.player.stages.attack, st.player.stages.speed = 2, 1
  st.enemy.stages.defense = -1
  U.wait(10)
  log(("battle menu, stat changes on both sides: %.0f bytes a frame"):format(rate(FRAMES, "battle menu")))
  local badges, hints = Healthbox.__ndxBadges, Healthbox.__ndxStatHints
  if badges and hints then
    local b, h = badges.enabled, hints.enabled
    local off = function() return false end
    badges.enabled, hints.enabled = off, off
    U.wait(10)
    log(("  ... the badges and hints off: %.0f bytes a frame"):format(rate(FRAMES)))
    badges.enabled, hints.enabled = b, h
  end

  local root = "mods/national_dex_gen3/"
  local okE, ess = pcall(dofile, root .. "data/ess_anims.lua")
  if not okE then return end
  local byId = {}
  for _, r in ipairs(dofile(root .. "data/moves.lua")) do byId[r.id] = r end
  for _, id in ipairs(moveList()) do
    local info = ess.moves[id]
    local num = (byId[id] and byId[id].index) or (info and info.num)
    if num then
      local m
      for pass = 1, 2 do
        m = meter()
        stopGC()
        Anim.launchMove(num, { attackerSide = "player", targetSide = "enemy", isReversed = false,
          moveTurn = info and info.turns and 1 or 0 })
        local ticks = 0
        while Anim.busy() and ticks < 1500 do
          m.frame(Anim.busy)
          ticks = ticks + 1
        end
        startGC()
        U.wait(10)
      end
      log(("animation %s: %.0f bytes a frame over %d frames"):format(id, m.per(), m.frames))
    end
  end
end

local function gen12(game, log)
  local version = require("src.core.GameVersion").get()
  local gen = (version == "gold" or version == "silver" or version == "crystal") and 2 or 1
  for _ = 1, 600 do
    if game.save and game.stack and game.stack:top() then break end
    U.wait(1)
  end
  U.wait(60)
  if gen == 1 then
    U.teleport(game, "ROUTE_1", 5, 5, "down")
    U.wait(120)
  end
  log(("overworld, standing still: %.0f bytes a frame"):format(rate(FRAMES, "overworld")))
  local data = game.data
  local Mon = gen == 1 and require("src.pokemon.Pokemon") or require("src.battle.gen2.Mon")
  game.save.party = { Mon.new(data, "BLASTOISE", 50) }
  local MENUS = { menu = true, moveSelect = true, mimicSelect = true, moves = true, submenu = true }
  local function advance(phase)
    if phase == "moveSelect" or phase == "mimicSelect" or phase == "moves" or phase == "submenu" then
      U.tap(game, "b")
    elseif not MENUS[phase] then
      U.tap(game, "a")
    end
  end
  local list = moveList()
  if gen == 1 then
    local BS = require("src.battle.BattleState")
    local battle = BS.newWild(game, "SQUIRTLE", 50)
    battle.onFinish = function() end
    game.overworld:pushBattle(battle)
    local function inBattle()
      for _, s in ipairs(game.stack.states or {}) do
        if s == battle then return true end
      end
      return false
    end
    for _ = 1, 600 do
      if inBattle() then break end
      U.wait(1)
    end
    local function toMenu()
      for _ = 1, 400 do
        if not inBattle() then return false end
        if battle.phase == "menu" and not battle.animPlaying then return true end
        advance(battle.phase); U.wait(4)
      end
      return false
    end
    if not toMenu() then log("FAIL the battle's menu"); return end
    battle.rng = function(a) return a end
    local function play(id, user, target, measure)
      for _, b in ipairs({ battle.player, battle.enemy }) do b.mon.hp, b.mon.status = 999, nil end
      battle.phase = "messages"; battle.afterQueue = "menu"
      battle:performMove(user, target, { id = id, pp = 5, maxPp = 5 }, false)
      local m = meter()
      local busy = function() return battle.animPlaying and battle.animName == id end
      if measure then stopGC() end
      local seen = false
      for _ = 1, 900 do
        if busy() then seen = true elseif seen then break end
        if measure then m.frame(busy) else U.wait(1) end
      end
      if measure then startGC() end
      toMenu()
      return m
    end
    -- stat changes on both sides, for the chips
    play("SWORDS_DANCE", battle.player, battle.enemy)
    play("GROWL", battle.player, battle.enemy)
    U.wait(30)
    log(("battle menu, stat changes on both sides: %.0f bytes a frame"):format(rate(FRAMES, "battle menu")))
    for _, id in ipairs(list) do
      play(id, battle.player, battle.enemy)
      local m = play(id, battle.player, battle.enemy, true)
      log(("animation %s: %.0f bytes a frame over %d frames"):format(id, m.per(), m.frames))
    end
  else
    assert(game.world:startBattle({ wild = Mon.new(data, "SQUIRTLE", 50) }), "startBattle failed")
    local screen
    for _ = 1, 900 do
      local top = game.stack:top()
      if top and top.battle then screen = top break end
      U.wait(1)
    end
    if not screen then log("FAIL no battle screen"); return end
    local function settle()
      for _ = 1, 200 do
        if game.stack:top() ~= screen then return end
        if screen.showPlayerHud and not screen.anim and (screen.queue == nil or #screen.queue == 0)
          and MENUS[screen.phase] then return end
        advance(screen.phase); U.wait(4)
      end
    end
    settle()
    local b = screen.battle
    local function play(id, measure)
      for _, mm in ipairs({ b.player, b.enemy }) do mm.hp, mm.status = 999, nil end
      b:useMove(b.player, b.enemy, id)
      screen.phase = "resolving"
      screen:pushAll(b:takeEvents())
      screen.message, screen.messageTimer = nil, 0
      screen:advanceQueue()
      local m = meter()
      local busy = function()
        local a = game.stack:top() == screen and screen.anim
        return a and a.__ndxKey == "ndx:" .. id
      end
      if measure then stopGC() end
      local seen = false
      for i = 1, 900 do
        if busy() then seen = true elseif seen then break end
        if measure then m.frame(busy) else
          if i % 6 == 0 and not screen.anim then advance(screen.phase) end
          U.wait(1)
        end
      end
      if measure then startGC() end
      settle()
      return m
    end
    play("SWORDS_DANCE")
    b:useMove(b.enemy, b.player, "GROWL")
    screen.phase = "resolving"
    screen:pushAll(b:takeEvents())
    screen:advanceQueue()
    settle()
    U.wait(30)
    log(("battle menu, stat changes on both sides: %.0f bytes a frame"):format(rate(FRAMES, "battle menu")))
    for _, id in ipairs(list) do
      play(id)
      local m = play(id, true)
      log(("animation %s: %.0f bytes a frame over %d frames"):format(id, m.per(), m.frames))
    end
  end
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "."
  local logFile = io.open(dir .. "/driver.log", "w")
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    print("[driver]", line)
    if logFile then logFile:write(line, "\n"); logFile:flush() end
  end
  plog = log
  local ok, err = xpcall(function()
    local okV, GameVersion = pcall(require, "src.core.GameVersion")
    local v = okV and GameVersion.get() or "?"
    log("version " .. tostring(v))
    if v == "red" or v == "blue" or v == "yellow" or v == "gold" or v == "silver" or v == "crystal" then
      gen12(game, log)
    else
      gen3(game, log)
    end
  end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  log("DONE")
  if logFile then logFile:close() end
  love.event.quit()
end
