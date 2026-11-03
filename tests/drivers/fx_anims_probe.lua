-- Driver: the pixelfx move animations (src/fx_anims.lua, data/fx.lua) in a real battle. A new game, a wild
-- battle, then every move data/fx.lua draws, from the player's side and the foe's: each plays to the end,
-- its NdxFx task draws from the atlas, once it has loaded, and the battle's memory stays flat. Shots fx_<move>_<side>_<f>.png
-- at FX_SHOTS frames (default 10,24,40).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald FX_MOVES=DRAGON_PULSE,HEX \
--   POKEPORT_DRIVER=mods/national_dex_gen3/tests/drivers/fx_anims_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/ndx"
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "PIXEL", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local AnimCtx = require("src.core.game3.battle.anim_ctx")
  local AnimTasks = require("src.core.game3.battle.anim_tasks")
  local Ui = require("src.core.game3.battle.ui")
  local Moves = require("src.core.game3.battle.moves")
  local GAME = require("src.core.GameVersion").get()
  local C = require("src.core.game3.constants").of(GAME)
  local session = Runtime.getSession()
  check(session ~= nil, "field session exists")
  if not session then return end
  local function sp(name) return C.species.byName["SPECIES_" .. name] end

  session.party = {}
  Party.giveMon(session, sp("GARDEVOIR") or sp("ALAKAZAM"), 50, "MON")
  session.party[1].hp = session.party[1].maxHp or session.party[1].hp
  local started, serr = BattleBridge.startWild(Runtime._mod, game, { species = sp("GOLEM") or sp("GEODUDE"), level = 50 }, { fade = false })
  check(started == true, "wild battle started " .. tostring(serr or ""))
  if not started then return end
  local ready = false
  for _ = 1, 6000 do
    if Battle.isActive() and Ui._mode == "menu" and not Anim.busy() then ready = true break end
    if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
  end
  check(ready, "battle reached the action menu")
  if not ready then return end
  U.wait(20)

  local fx = dofile("mods/national_dex_gen3/data/fx.lua")
  local state = AnimTasks.__ndxFx
  check(state ~= nil and AnimTasks.REGISTRY.NdxFx ~= nil, "the NdxFx task is registered")
  local st = Battle._st
  local pSpecies = st and st.player and st.player.mon and st.player.mon.species
  local eSpecies = st and st.enemy and st.enemy.mon and st.enemy.mon.species
  local function opts(side, moveId)
    local target = side == "player" and "enemy" or "player"
    return {
      attackerSide = side, targetSide = target, isReversed = side == "enemy",
      attackerSpecies = side == "player" and pSpecies or eSpecies,
      targetSpecies = side == "player" and eSpecies or pSpecies,
      moveTurn = 0, turn = 0, ctx = AnimCtx.build(side, target, { moveId = moveId }),
    }
  end
  local shots = {}
  for n in (os.getenv("FX_SHOTS") or "10,24,40"):gmatch("%d+") do shots[tonumber(n)] = true end
  local only = os.getenv("FX_MOVES")
  local names = {}
  for id in pairs(fx.moves) do
    if not only or ("," .. only .. ","):find("," .. id .. ",", 1, true) then names[#names + 1] = id end
  end
  table.sort(names)
  -- what the battle makes anyway: idle, and a cart move (Thunderbolt) playing
  local function rate(frames, launch)
    collectgarbage("collect")
    local kb0, f = collectgarbage("count"), 0
    collectgarbage("stop")
    if launch then launch() end
    while f < frames do
      U.wait(1)
      f = f + 1
      if launch and not Anim.busy() and f > 4 then break end
    end
    local kb = (collectgarbage("count") - kb0) / f
    collectgarbage("restart")
    return kb
  end
  log(("garbage idle: %.2f KB a frame; Thunderbolt: %.2f"):format(rate(60),
    rate(900, function() Anim.launchMove(85, opts("player", 85)) end)))
  U.wait(10)
  if os.getenv("FX_SHOTS") == "0" then
    for _, id in ipairs(names) do
      local num = Moves.numForName and Moves.numForName(id)
      if num then
        local play = function() Anim.launchMove(num, opts("player", num)) end
        local first = rate(900, play)
        U.wait(6)
        log(("garbage %s: %.2f KB a frame (%.2f the first time, loading its sheets)"):format(id, rate(900, play), first))
      end
      U.wait(6)
    end
  end
  local worstKb = 0
  for _, id in ipairs(names) do
    local num = Moves.numForName and Moves.numForName(id)
    check(num ~= nil, id .. " has a move number")
    for _, side in ipairs({ "player", "enemy" }) do
      if num then
        local sawTask, drew = false, false
        local okL, e = pcall(Anim.launchMove, num, opts(side, num))
        check(okL, id .. " " .. side .. " launches " .. tostring(e or ""))
        local f, kb0 = 0, collectgarbage("count")
        local peak = 0
        while f < 900 do
          U.wait(1)
          f = f + 1
          for i = 1, AnimTasks.MAX do
            local t = AnimTasks._pool[i]
            if t.active and t._ndxFx then
              sawTask = true
              if state.art then drew = true end
            end
          end
          if shots[f] then U.still(game, ("%s/fx_%s_%s_%03d.png"):format(dir, id:lower(), side, f)) end
          if not Anim.busy() and f > 4 then break end
        end
        local kb = (collectgarbage("count") - kb0) / math.max(1, f)
        if kb > worstKb then worstKb = kb end
        check(not Anim.busy(), ("%s %s ends (%d frames)"):format(id, side, f))
        check(sawTask and drew, id .. " " .. side .. " drew its sheet")
        U.wait(6)
      end
    end
  end
  log(("garbage while playing: at most %.2f KB a frame"):format(worstKb))
  log(("%d failures"):format(fails))
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/ndx"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  local logFile = io.open(dir .. "/driver.log", "w")
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    print("[driver]", line)
    if logFile then logFile:write(line, "\n"); logFile:flush() end
  end
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  log("DONE")
  if logFile then logFile:close() end
  love.event.quit()
end
