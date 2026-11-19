-- Driver: the Move Split option (src/move_split.lua) in a real Gen 3 battle. A new game, a level 50
-- Machamp (strong Attack, weak Sp. Atk) with Crunch and Fire Punch (Dark and Fire: special by type
-- in Gen 3, physical today) against a wild level 50 Chansey (Defense 5, Sp. Def 105). Off, both
-- moves hit Chansey's Sp. Def with Machamp's Sp. Atk; on, its Defense with Machamp's Attack, many
-- times harder. The option is set in memory only (as the Mod Manager does, without saving).
-- Shots and driver.log in SHOT_DIR. From the gen1recomp root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/national_dex_gen3/tests/drivers/move_split_probe.lua love .

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
  game:_handleBootAction({ action = "new_game", name = "SPLIT", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local Types = require("src.core.game3.battle.types")
  local GAME = require("src.core.GameVersion").get()
  local C = require("src.core.game3.constants").of(GAME)
  local session = Runtime.getSession()
  check(session ~= nil, "field session exists")
  if not session then return end
  check(Types.__ndxSplit ~= nil, "the Move Split wraps are installed")

  -- the option, in memory (what the Mod Manager's setOption does, minus writing options.lua)
  local loader = game.mods
  local function setSplit(on)
    loader.modOptions = loader.modOptions or {}
    loader.modOptions.national_dex_gen3 = loader.modOptions.national_dex_gen3 or {}
    loader.modOptions.national_dex_gen3.move_split = on
    loader.events:emit("mod.options_changed", { mod = "national_dex_gen3", key = "move_split", value = on })
  end
  setSplit(false)

  local CRUNCH, FIRE_PUNCH = 242, 7
  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_MACHAMP, 50, "MACHAMP")
  local m = session.party[1]
  m.moves, m.pp = { CRUNCH, FIRE_PUNCH, 0, 0 }, { 15, 15, 0, 0 }
  m.hp = m.maxHp or m.hp
  log(("Machamp: Attack %s, Sp. Atk %s"):format(tostring(m.attack), tostring(m.spAtk)))

  local BattleAPI = require("src.battle.game3.BattleAPI")
  local bapi = BattleAPI.new(game)
  local nextId = 0
  local function toMenu()
    for _ = 1, 6000 do
      if Battle.isActive() and Ui._mode == "menu" and not Anim.busy() then return true end
      if not Battle.isActive() then return false end
      if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
    end
    return false
  end
  -- one turn with the move in `slot`; the damage it did to the foe
  local function turn(st, ad, slot)
    st.enemy.mon.hp = ad:maxHp(st.enemy)
    if st.enemy.hp then st.enemy.hp = st.enemy.mon.hp end
    local hp0 = ad:hp(st.enemy)
    local low = hp0
    local chose = false
    for _ = 1, 3000 do
      U.wait(1)
      if Battle.isActive() and Battle._st == st then low = math.min(low, ad:hp(st.enemy)) end
      local sn = bapi:snapshot()
      local p = sn and sn.prompt
      if not Battle.isActive() then break end
      if chose and Ui._mode == "menu" and not Anim.busy() then break end
      if p == "advance" then U.tap(game, "a"); U.wait(4)
      elseif not chose and Ui._mode == "menu" then
        nextId = nextId + 1
        bapi:submit({ id = nextId, revision = sn.revision, kind = "menu", choice = "fight" })
      elseif not chose and Ui._mode == "moves" then
        nextId = nextId + 1
        chose = bapi:submit({ id = nextId, revision = sn.revision, kind = "move", slot = slot }) and true or false
      end
    end
    return hp0 - low
  end

  local function fight(label)
    local started, serr = BattleBridge.startWild(Runtime._mod, game,
      { species = C.species.byName.SPECIES_CHANSEY, level = 50 }, { fade = false })
    check(started == true, label .. ": wild Chansey battle started " .. tostring(serr or ""))
    if not started then return nil end
    check(toMenu(), label .. ": battle reached the action menu")
    local st, ad = Battle._st, Battle._adapter
    st.enemy.mon.defense, st.enemy.mon.spDef = st.enemy.mon.defense or 5, st.enemy.mon.spDef or 105
    log(("%s: Chansey Defense %s, Sp. Def %s, HP %d"):format(label, tostring(st.enemy.mon.defense),
      tostring(st.enemy.mon.spDef), ad:maxHp(st.enemy)))
    local out = {}
    for _, mv in ipairs({ { 1, "Crunch" }, { 2, "Fire Punch" } }) do
      local best = 0
      -- (a miss or a roll: the larger of two tries)
      for _ = 1, 2 do
        if Battle.isActive() then best = math.max(best, turn(st, ad, mv[1])) end
      end
      out[mv[2]] = best
      log(("%s: %s did %d"):format(label, mv[2], best))
    end
    U.still(game, dir .. "/split_" .. label .. ".png")
    -- (end the battle: knock the foe out with one more hit at 1 HP)
    if Battle.isActive() then
      st.enemy.mon.hp = 1
      turn(st, ad, 1)
      for _ = 1, 3000 do
        if not Battle.isActive() then break end
        U.tap(game, "a"); U.wait(4)
      end
    end
    U.wait(120)
    return out
  end

  local off = fight("off")
  setSplit(true)
  local on = fight("on")
  if off and on then
    check(on["Crunch"] > 2 * off["Crunch"], ("Crunch hits physical with Move Split on (%d -> %d)"):format(off["Crunch"], on["Crunch"]))
    check(on["Fire Punch"] > 2 * off["Fire Punch"], ("Fire Punch too (%d -> %d)"):format(off["Fire Punch"], on["Fire Punch"]))
  end
  check(Types.isPhysical(Types.ID.GHOST) and not Types.isPhysical(Types.ID.DARK), "outside battle: still by type")
  setSplit(false)
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
