-- Driver: the newer abilities (src/abilities_more.lua) in a real Gen 3 battle. A new game, a Zacian
-- (Intrepid Sword, its own ability) against a wild Gastly (Levitate): its ATTACK rises on entry;
-- given Mold Breaker, its Earthquake hits the Levitate Gastly; given Disguise, the Gastly takes
-- the next Earthquake on its disguise. Shots and driver.log in SHOT_DIR. From the gen1recomp root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/national_dex_gen3/tests/drivers/abilities_probe.lua love .

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
  game:_handleBootAction({ action = "new_game", name = "ABIL", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local GAME = require("src.core.GameVersion").get()
  local C = require("src.core.game3.constants").of(GAME)
  local session = Runtime.getSession()
  check(session ~= nil, "field session exists")
  if not session then return end
  local api = game.mods and game.mods.exports and game.mods.exports.national_dex_gen3
  local zacian = api and api.slotOf("ZACIAN")
  check(zacian ~= nil, "Zacian has a slot")
  if not zacian then return end

  session.party = {}
  Party.giveMon(session, zacian, 10, "ZACIAN")
  local m = session.party[1]
  m.moves, m.pp = { 89, 33, 0, 0 }, { 10, 35, 0, 0 }            -- Earthquake, Tackle
  m.hp = m.maxHp or m.hp
  local started, serr = BattleBridge.startWild(Runtime._mod, game,
    { species = C.species.byName.SPECIES_GASTLY, level = 40 }, { fade = false })
  check(started == true, "wild battle started " .. tostring(serr or ""))
  if not started then return end
  local function toMenu()
    for _ = 1, 6000 do
      if Battle.isActive() and Ui._mode == "menu" and not Anim.busy() then return true end
      if not Battle.isActive() then return false end
      if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
    end
    return false
  end
  check(toMenu(), "battle reached the action menu")
  local st = Battle._st
  local ad = Battle._adapter
  check(ad:abilityOf(st.player) == "INTREPID_SWORD", "Zacian's ability is INTREPID_SWORD")
  check((st.player.stages.attack or 0) == 1, "its ATTACK rose on entry (" .. tostring(st.player.stages.attack) .. ")")
  U.still(game, dir .. "/abilities_menu.png")

  local BattleAPI = require("src.battle.game3.BattleAPI")
  local bapi = BattleAPI.new(game)
  local nextId = 0
  local function turn(slot)
    local hp0 = ad:hp(st.enemy)
    local chose = false
    for _ = 1, 3000 do
      U.wait(1)
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
    return hp0 - ad:hp(st.enemy)
  end

  check(ad:abilityOf(st.enemy) == "LEVITATE", "the wild Gastly has LEVITATE")
  -- (as Skill Swap gives one: Zacian's own ability answers ahead of a battler's `ability`)
  st.player.expTracedAbility = "MOLD_BREAKER"
  check(ad:abilityOf(st.player) == "MOLD_BREAKER", "Zacian now has MOLD_BREAKER")
  local d1 = turn(1)
  log("Earthquake with MOLD_BREAKER: " .. d1)
  check(d1 > 0, "MOLD_BREAKER: Earthquake hits the Levitate Gastly")
  U.still(game, dir .. "/abilities_mold.png")
  if Battle.isActive() and ad:hp(st.enemy) > 0 then
    st.enemy.ability = "DISGUISE"
    local d2 = turn(1)
    log("Earthquake on DISGUISE: " .. d2 .. " (max HP " .. ad:maxHp(st.enemy) .. ")")
    check(d2 == math.max(1, math.floor(ad:maxHp(st.enemy) / 8)), "DISGUISE: the hit only costs 1/8 HP")
    U.still(game, dir .. "/abilities_disguise.png")
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
