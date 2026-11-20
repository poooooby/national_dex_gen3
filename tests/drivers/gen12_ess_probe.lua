-- Driver: the Gen 9 Move Animation Project's animations on Red/Blue/Yellow and Gold/Silver/Crystal
-- (src/gen12/ess_anims.lua) in a real battle. A wild battle, then each move's animation from your
-- side (and the foe's: FOE=1), a shot every SHOT_EVERY frames into SHOT_DIR (<MOVE>_p_NN.png,
-- <MOVE>_e_NN.png) for tools/ess_gallery.py. MOVES=NIGHT_SLASH,SURF (default: a few of each kind).
-- From the gen1recomp root, in an identity of its own (never the player's options.lua):
--   SHOT_DIR=<dir> MOVES=... FOE=1 POKEPORT_VERSION=red|gold \
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
  local list = {}
  for id in (os.getenv("MOVES") or "NIGHT_SLASH,AXE_KICK,SURF,DARK_PULSE,ICE_BEAM,FLY,POISON_STING"):gmatch("[%w_]+") do
    list[#list + 1] = id
  end
  local Mon = gen == 1 and require("src.pokemon.Pokemon") or require("src.battle.gen2.Mon")
  local party = { Mon.new(data, "LUCARIO", 50) }
  game.save.party = party
  party[1].moves[1] = { id = list[1], pp = 15, maxPp = 15 }

  local function shotName(id, foe, n)
    return ("%s/%s_%s_%02d.png"):format(dir, id, foe and "e" or "p", n)
  end

  if gen == 1 then
    local BattleState = require("src.battle.BattleState")
    local battle = BattleState.newWild(game, "GARCHOMP", 50)
    battle.onFinish = function() end
    battle.rng = function(a) return a end
    game.overworld:pushBattle(battle)
    local function toMenu()
      for _ = 1, 400 do
        if battle.phase == "menu" and not battle.animPlaying then return true end
        U.tap(game, "a"); U.wait(4)
      end
      return battle.phase == "menu"
    end
    check(toMenu(), "the battle reaches its menu")
    U.wait(20)
    U.still(game, dir .. "/menu.png")
    log(("colour mode %s, wide %s, player sprite %s, enemy sprite %s"):format(tostring(battle:colorMode()),
      tostring(battle:wideLayout()), tostring(battle.player and battle.player.sprite),
      tostring(battle.enemy and battle.enemy.sprite)))
    local function play(id, foe)
      battle.player.mon.hp, battle.enemy.mon.hp = 999, 999
      -- (every chance roll lands here: a freeze or a sleep would stop the next move)
      battle.player.mon.status, battle.enemy.mon.status = nil, nil
      battle.phase = "messages"; battle.afterQueue = "menu"
      local user, target = battle.player, battle.enemy
      if foe then user, target = target, user end
      battle:performMove(user, target, { id = id, pp = 5, maxPp = 5 }, false)
      if user.charging then
        -- a two-turn move: its first turn, then the one that animates
        toMenu()
        battle.phase = "messages"; battle.afterQueue = "menu"
        battle:performMove(user, target, { id = id, pp = 5, maxPp = 5 }, false)
      end
      local seen, n, shots = 0, 0, 0
      for i = 1, 900 do
        if battle.animPlaying and battle.animName == id then
          seen = seen + 1
          if seen % every == 1 then
            shots = shots + 1
            U.still(game, shotName(id, foe, shots))
          end
        elseif seen > 0 then break
        elseif i % 6 == 0 then U.tap(game, "a") end
        U.wait(1)
      end
      local h = BattleState.__ndxEss
      check(seen > 0 and h ~= nil, ("%s%s: played %d frames"):format(id, foe and " (foe)" or "", seen))
      toMenu()
      local pf = battle.picFx or {}
      local p, e = pf[battle.player] or {}, pf[battle.enemy] or {}
      check(not p.hidden and not e.hidden, id .. ": both pictures shown after")
    end
    for _, id in ipairs(list) do
      play(id, false)
      if foeToo then play(id, true) end
    end
  else
    local wild = Mon.new(data, "GARCHOMP", 50)
    assert(game.world:startBattle({ wild = wild }), "startBattle failed")
    local screen
    for _ = 1, 900 do
      local top = game.stack:top()
      if top and top.battle then screen = top break end
      U.wait(1)
    end
    assert(screen, "no battle screen")
    for _ = 1, 30 do
      if screen.showPlayerHud and not screen.anim then break end
      U.tap(game, "a"); U.wait(8)
    end
    U.wait(20)
    local b = screen.battle
    local function play(id, foe)
      b.player.hp, b.enemy.hp = 999, 999
      b.player.status, b.enemy.status = nil, nil
      local user, target = b.player, b.enemy
      if foe then user, target = target, user end
      b:useMove(user, target, id)
      local vol = b.volatile and b:volatile(user)
      if vol and (vol.charging or vol.chargeMove) then
        for _ = 1, 120 do
          if not screen.anim then break end
          U.tap(game, "a"); U.wait(4)
        end
        b:useMove(user, target, id)
      end
      local seen, shots = 0, 0
      for i = 1, 900 do
        local a = screen.anim
        if a and a.__ndxKey == "ndx:" .. id and a.__ndxParam ~= 1 then
          seen = seen + 1
          if seen % every == 1 then
            shots = shots + 1
            U.still(game, shotName(id, foe, shots))
          end
        elseif seen > 0 then break
        elseif i % 6 == 0 then U.tap(game, "a") end
        U.wait(1)
      end
      check(seen > 0, ("%s%s: played %d frames"):format(id, foe and " (foe)" or "", seen))
      for _ = 1, 60 do
        if not screen.anim and (screen.queue == nil or #screen.queue == 0) then break end
        U.tap(game, "a"); U.wait(4)
      end
    end
    for _, id in ipairs(list) do
      play(id, false)
      if foeToo then play(id, true) end
    end
  end
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
