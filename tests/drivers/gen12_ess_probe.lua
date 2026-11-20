-- Driver: the Gen 9 Move Animation Project's animations on Red/Blue/Yellow and Gold/Silver/Crystal
-- (src/gen12/ess_anims.lua) in a real battle. A wild battle, then each move's animation from your
-- side (and the foe's: FOE=1), a shot every SHOT_EVERY frames into SHOT_DIR (<MOVE>_p_NN.png,
-- <MOVE>_e_NN.png) for tools/ess_gallery.py. MOVES=NIGHT_SLASH,SURF, or ALL (every move this game
-- animates; the default is a few of each kind); WIDE=1 the wide battle layout. Both sides are Water
-- types (no type is immune to a move of theirs, and theirs hit everything); a battle a move ends
-- (Explosion, Roar, a one-hit KO) is started again. Each move logs "move <id> <side> <frames>"
-- (0: it did not animate: it failed, missed, or only animates under conditions), then a summary.
-- The user starts at half HP on Gold (a heal at full HP fails). A two-turn move is watched through
-- both turns. WHY=1 (Gold) logs the other animations a move that didn't animate played; POSE=1 (Red)
-- logs the battlers' poses at each shot.
-- From the gen1recomp root, in an identity of its own (never the player's options.lua):
--   SHOT_DIR=<dir> MOVES=... FOE=1 POKEPORT_VERSION=red|gold [POKEPORT_SPEED=3] \
--   POKEPORT_DRIVER=mods/national_dex_gen3/tests/drivers/gen12_ess_probe.lua love .

local U = require("tests.drivers.util")

local function body(game, log, dir)
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
  local version = require("src.core.GameVersion").get()
  local gen = (version == "gold" or version == "silver" or version == "crystal") and 2 or 1
  local every = tonumber(os.getenv("SHOT_EVERY") or "") or 6
  local foeToo = os.getenv("FOE") == "1"
  log("version " .. tostring(version) .. " (Gen " .. gen .. ")")
  local okV, VSync = pcall(require, "src.core.VSync")
  log("vsync " .. tostring(okV and VSync.effective and VSync.effective()) .. ", fps " .. tostring(love.timer.getFPS()))
  for _ = 1, 600 do
    if game.save and game.stack and game.stack:top() then break end
    U.wait(1)
  end
  U.wait(60)
  local data = game.data
  -- WIDE=1: the wide battle layout (this game's options only; the run's own options.lua)
  if os.getenv("WIDE") == "1" then
    local o = gen == 1 and game.save and game.save.options or game.options
    if o then o.battleLayout = "wide" end
  end
  if gen == 1 then
    U.teleport(game, "ROUTE_1", 5, 5, "down")
    U.wait(60)
  end
  local BS = require(gen == 1 and "src.battle.BattleState" or "src.ui.gen2.BattleState")
  local hub = BS.__ndxEss
  check(hub ~= nil and hub.state ~= nil, "the Gen 9 animations are installed")
  local list = {}
  local want = os.getenv("MOVES") or "NIGHT_SLASH,AXE_KICK,SURF,DARK_PULSE,ICE_BEAM,FLY,POISON_STING"
  if want == "ALL" and hub and hub.state then
    for key, l in pairs(hub.state.lines) do
      if l.kind == "move" then list[#list + 1] = (key:gsub("^ndx:", "")) end
    end
    table.sort(list)
  else
    for id in want:gmatch("[%w_]+") do list[#list + 1] = id end
  end
  log(("%d moves"):format(#list))
  local Mon = gen == 1 and require("src.pokemon.Pokemon") or require("src.battle.gen2.Mon")
  local party = { Mon.new(data, "BLASTOISE", 50) }
  game.save.party = party
  party[1].moves[1] = { id = list[1], pp = 15, maxPp = 15 }

  -- the party back on its feet (Explosion, Memento, Destiny Bond... faint their user)
  local function heal()
    for _, mon in ipairs(game.save.party or {}) do
      local max = (mon.stats and mon.stats.hp) or mon.maxHp or mon.maxHP or 150
      mon.hp, mon.status, mon.fainted = max, nil, nil
    end
  end

  local function shotName(id, foe, n)
    return ("%s/%s_%s_%02d.png"):format(dir, id, foe and "e" or "p", n)
  end
  -- advance text only: A on the FIGHT or move menu would play slot 1 again (spending its PP and
  -- giving the foe a turn), so the menus get nothing, and a move menu left open gets B
  local MENUS = { menu = true, moveSelect = true, mimicSelect = true, moves = true, submenu = true }
  local function advance(phase)
    if phase == "moveSelect" or phase == "mimicSelect" or phase == "moves" or phase == "submenu" then
      U.tap(game, "b")
    elseif not MENUS[phase] then
      U.tap(game, "a")
    end
  end
  local played, silent = 0, {}
  local function report(id, foe, seen)
    log(("move %s %s %d"):format(id, foe and "e" or "p", seen))
    if seen > 0 then played = played + 1 else silent[#silent + 1] = id .. (foe and " (foe)" or "") end
  end

  if gen == 1 then
    local battle
    local function inBattle()
      if not battle then return false end
      for _, s in ipairs(game.stack.states or {}) do
        if s == battle then return true end
      end
      return false
    end
    local function toMenu()
      for _ = 1, 400 do
        if not inBattle() then return false end
        if battle.phase == "menu" and not battle.animPlaying then return true end
        advance(battle.phase); U.wait(4)
      end
      return false
    end
    local function fresh()
      for _ = 1, 200 do
        if not inBattle() then break end
        U.tap(game, "b"); U.wait(4)
      end
      heal()
      battle = BS.newWild(game, "SQUIRTLE", 50)
      battle.onFinish = function() end
      game.overworld:pushBattle(battle)
      -- (the battle joins the stack after the entry wipe)
      for _ = 1, 600 do
        if inBattle() then break end
        U.wait(1)
      end
      return toMenu()
    end
    check(fresh(), "the battle reaches its menu")
    U.wait(20)
    log(("colour mode %s, wide %s"):format(tostring(battle:colorMode()), tostring(battle:wideLayout())))
    local function play(id, foe)
      if not toMenu() then fresh() end
      for _, b in ipairs({ battle.player, battle.enemy }) do
        b.mon.hp, b.mon.status = 999, nil
        b.charging, b.chargeReady, b.invulnerable, b.recharging, b.mustRecharge = nil, nil, nil, nil, nil
        -- (a stage left from the last move, an evasion or accuracy one above all, would make every
        -- move after it miss)
        b.stages = {}
      end
      battle.phase = "messages"; battle.afterQueue = "menu"
      local user, target = battle.player, battle.enemy
      if foe then user, target = target, user end
      battle:performMove(user, target, { id = id, pp = 5, maxPp = 5 }, false)
      -- a two-turn move: watched through both turns. Your side's locked menu releases the charge
      -- on its own; the foe's is used again (by the instance that charged: performMove's
      -- `user.charging == moveInst`) once the battle is back at its menu
      local inst = user.charging
      local seen, shots = 0, 0
      for i = 1, 900 do
        local idle = inBattle() and battle.phase == "menu" and not battle.animPlaying
        if inBattle() and battle.animPlaying and battle.animName == id and not (inst and user.charging == inst) then
          seen = seen + 1
          if seen % every == 1 then
            shots = shots + 1
            U.still(game, shotName(id, foe, shots))
            if os.getenv("POSE") == "1" then
              local st = hub.st
              local function f(p)
                if p == nil then return "-" elseif p == false then return "hidden" end
                return ("%d,%d %.2fx%.2f a%.2f"):format(p.dx, p.dy, p.sx, p.sy, p.a)
              end
              log(("  f%s player %s enemy %s"):format(tostring(st and st.frame), f(st and st.pose and st.pose.player),
                f(st and st.pose and st.pose.enemy)))
            end
          end
        elseif seen > 0 or not inBattle() then break
        elseif inst and idle then
          if user.charging == inst then
            battle.phase = "messages"; battle.afterQueue = "menu"
            battle:performMove(user, target, inst, false)
          end
          inst = nil
        elseif not inst and i > 240 and battle.phase == "menu" then break
        elseif i % 6 == 0 then advance(battle.phase) end
        U.wait(1)
      end
      return seen
    end
    local count = 0
    local function try(id, foe)
      local seen = 0
      count = count + 1
      if count % 10 == 0 then fresh() end
      for attempt = 1, 3 do
        if attempt > 1 then fresh() end
        -- the first try lands every chance roll; the retries roll as the game does
        battle.__probeRng = battle.__probeRng or battle.rng
        battle.rng = attempt == 1 and function(a) return a end or battle.__probeRng
        local ok, r = pcall(play, id, foe)
        if not ok then check(false, id .. (foe and " (foe): " or ": ") .. tostring(r)) break end
        seen = r
        if seen > 0 then break end
      end
      report(id, foe, seen)
    end
    for _, id in ipairs(list) do
      try(id, false)
      if foeToo then try(id, true) end
    end
  else
    local Battle = require("src.battle.gen2.Battle")
    local screen
    local function fresh()
      for _ = 1, 400 do
        if not (game.stack:top() or {}).battle then break end
        U.tap(game, "b"); U.wait(2)
      end
      heal()
      assert(game.world:startBattle({ wild = Mon.new(data, "SQUIRTLE", 50) }), "startBattle failed")
      screen = nil
      for _ = 1, 900 do
        local top = game.stack:top()
        if top and top.battle then screen = top break end
        U.wait(1)
      end
      assert(screen, "no battle screen")
      for _ = 1, 40 do
        if screen.showPlayerHud and not screen.anim and MENUS[screen.phase] then break end
        advance(screen.phase); U.wait(8)
      end
      U.wait(20)
    end
    fresh()
    local function settle()
      for _ = 1, 90 do
        if game.stack:top() ~= screen then return end
        if not screen.anim and (screen.queue == nil or #screen.queue == 0) and MENUS[screen.phase] then break end
        advance(screen.phase); U.wait(4)
      end
    end
    local function play(id, foe)
      if game.stack:top() ~= screen or not screen.battle or screen.battle.over then fresh() end
      local b = screen.battle
      for _, m in ipairs({ b.player, b.enemy }) do
        m.hp, m.status = 999, nil
      end
      local user0 = foe and b.enemy or b.player
      -- (half the user's HP: a heal at full HP fails)
      local max = user0.maxHp or (user0.stats and user0.stats.hp)
      if max then user0.hp = math.max(1, math.floor(max / 2)) end
      if b.stages and Battle.newStages then
        b.stages.player, b.stages.enemy = Battle.newStages(), Battle.newStages()
      end
      local user, target = b.player, b.enemy
      if foe then user, target = target, user end
      -- the move's events shown as a turn's are (BattleState:submit): the screen resolves them and
      -- comes back to its menu
      local function use()
        b:useMove(user, target, id)
        screen.phase = "resolving"
        screen:pushAll(b:takeEvents())
        screen.message, screen.messageTimer = nil, 0
        screen:advanceQueue()
      end
      use()
      -- a two-turn move: watched through both turns. Your side's locked menu releases the charge on
      -- its own; the foe's is used again once the screen is back at its menu
      local function charged()
        local vol = b.volatile and b:volatile(user)
        return vol and vol.chargeMove ~= nil
      end
      local waiting = charged()
      local seen, shots = 0, 0
      local other = {}
      for i = 1, 900 do
        local a = game.stack:top() == screen and screen.anim
        if a and not (a.__ndxKey == "ndx:" .. id and a.__ndxParam ~= 1) then
          other[tostring(a.__ndxKey or a.animId) .. "/" .. tostring(a.__ndxParam)] = true
        end
        local idle = not screen.anim and (screen.queue == nil or #screen.queue == 0) and MENUS[screen.phase]
        if a and a.__ndxKey == "ndx:" .. id and a.__ndxParam ~= 1 then
          seen = seen + 1
          if seen % every == 1 then
            shots = shots + 1
            U.still(game, shotName(id, foe, shots))
          end
        elseif seen > 0 or game.stack:top() ~= screen then break
        elseif waiting and idle then
          waiting = false
          if charged() then use() end
        elseif not waiting and i > 240 and not screen.anim then break
        elseif i % 6 == 0 then advance(screen.phase) end
        U.wait(1)
      end
      settle()
      if seen == 0 and os.getenv("WHY") == "1" then
        local o = {}
        for k in pairs(other) do o[#o + 1] = k end
        table.sort(o)
        log(("  %s: other animations %s"):format(id, table.concat(o, " ")))
      end
      return seen
    end
    local count = 0
    local function try(id, foe)
      local seen = 0
      count = count + 1
      if count % 10 == 0 then fresh() end
      for attempt = 1, 3 do
        if attempt > 1 then fresh() end
        local ok, r = pcall(play, id, foe)
        if not ok then check(false, id .. (foe and " (foe): " or ": ") .. tostring(r)) break end
        seen = r
        if seen > 0 then break end
      end
      report(id, foe, seen)
    end
    for _, id in ipairs(list) do
      try(id, false)
      if foeToo then try(id, true) end
    end
  end
  log(("animated %d; did not animate (%d): %s"):format(played, #silent, table.concat(silent, ", ")))
  log(("%d failures"):format(fails))
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/ndx"
  local logFile = io.open(dir .. "/driver.log", "w")
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    print("[driver]", line)
    if logFile then logFile:write(line, "\n"); logFile:flush() end
  end
  local ok, err = xpcall(function() body(game, log, dir) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  log("DONE")
  if logFile then logFile:close() end
  love.event.quit()
end
