-- Driver: the Gen 9 Move Animation Project's animations (src/ess_anims.lua) in a real Gen 3 battle.
-- A new game, a wild battle, then each move's animation played from the player's side (and the
-- foe's: FOE=1), a shot every SHOT_EVERY frames into SHOT_DIR (<MOVE>_p_NN.png, <MOVE>_e_NN.png), for
-- tools/ess_gallery.py to turn into a review page. MOVES=AXE_KICK,THUNDERBOLT (default: all of
-- data/ess_anims.lua's, the newer and the carts' own); TURN=0 plays a two-turn move's first turn. From the gen1recomp root:
--   SHOT_DIR=<dir> MOVES=... FOE=1 POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/national_dex_gen3/tests/drivers/ess_anims_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/ndx"
  local every = tonumber(os.getenv("SHOT_EVERY") or "") or 6
  local foeToo = os.getenv("FOE") == "1"
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
  game:_handleBootAction({ action = "new_game", name = "ANIM", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local AnimTasks = require("src.core.game3.battle.anim_tasks")
  local GAME = require("src.core.GameVersion").get()
  local C = require("src.core.game3.constants").of(GAME)
  local session = Runtime.getSession()
  check(session ~= nil, "field session exists")
  if not session then return end

  local root = "mods/national_dex_gen3/"
  local ess = dofile(root .. "data/ess_anims.lua")
  local byId = {}
  for _, r in ipairs(dofile(root .. "data/moves.lua")) do byId[r.id] = r end
  local list = {}
  local want = os.getenv("MOVES")
  if want and want ~= "" then
    for id in want:gmatch("[%w_]+") do list[#list + 1] = id end
  else
    for id in pairs(ess.moves) do list[#list + 1] = id end
    table.sort(list)
  end

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_BLAZIKEN or C.species.byName.SPECIES_CHARIZARD, 50, "HERO")
  local started, serr = BattleBridge.startWild(Runtime._mod, game,
    { species = C.species.byName.SPECIES_SWAMPERT or C.species.byName.SPECIES_BLASTOISE, level = 50 }, { fade = false })
  check(started == true, "wild battle started " .. tostring(serr or ""))
  if not started then return end
  local ok = waitFor(function()
    if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") end
    return Battle.isActive() and Ui._mode == "menu" and not Anim.busy()
  end, 3000)
  check(ok, "battle reached the action menu")
  U.wait(30)

  -- a newer move by its slot, a cart's by its number; a two-turn move's second turn (TURN=0: its first)
  local turn = tonumber(os.getenv("TURN") or "")
  local function play(id, foe)
    local info = ess.moves[id]
    local num = (byId[id] and byId[id].index) or (info and info.num)
    if not num then check(false, id .. " is a move the pack animates"); return end
    local saw = false
    Anim.launchMove(num, { attackerSide = foe and "enemy" or "player", targetSide = foe and "player" or "enemy",
      isReversed = foe, moveTurn = turn or (info and info.turns and 1 or 0) })
    local n, ticks = 0, 0
    while Anim.busy() and ticks < 1500 do
      if ticks % every == 0 then
        n = n + 1
        U.still(game, ("%s/%s_%s_%02d.png"):format(dir, id, foe and "e" or "p", n))
      end
      U.wait(1)
      ticks = ticks + 1
      for i = 1, AnimTasks.MAX do
        local t = AnimTasks._pool[i]
        if t.active and t.name == "NdxEss" then saw = true end
      end
    end
    check(saw and not Anim.busy(), ("%s%s: NdxEss played, %d ticks"):format(id, foe and " (foe)" or "", ticks))
    U.wait(10)
  end

  for _, id in ipairs(list) do
    play(id, false)
    if foeToo then play(id, true) end
  end
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
