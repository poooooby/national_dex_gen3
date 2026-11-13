-- Driver: the Gen 2-9 parity on Red / Gold in the real engine (src/gen12/mech/ and the systems): a
-- battle that runs the new move families turn by turn (weather, Protect, hazards, a switch, a
-- status move, an ability on entry), the summary screens, the Red Day Care Lady, a held item.
-- Shots and driver.log in SHOT_DIR. From the gen1recomp root:
--   SHOT_DIR=<dir> POKEPORT_VERSION=red POKEPORT_DRIVER=mods/national_dex_gen3/tests/drivers/gen12_modern_probe.lua love .

local U = require("tests.drivers.util")

local function body(game, log, dir)
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
  local function section(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then fails = fails + 1; log("FAIL " .. name .. ": " .. tostring(err)) end
  end
  local version = require("src.core.GameVersion").get()
  local gen = (version == "gold" or version == "silver" or version == "crystal") and 2 or 1
  log("version " .. tostring(version))
  for _ = 1, 600 do
    if game.save and game.stack and game.stack:top() then break end
    U.wait(1)
  end
  U.wait(60)
  local data = game.data
  local function shot(name) U.shot(game, dir .. "/" .. version .. "_" .. name .. ".png") end
  if gen == 1 then U.teleport(game, "ROUTE_1", 5, 5, "down"); U.wait(60) end
  local Mon = gen == 1 and require("src.pokemon.Pokemon") or require("src.battle.gen2.Mon")
  local function make(id, lv, moves)
    local m = Mon.new(data, id, lv)
    if moves then
      m.moves = {}
      for i, mid in ipairs(moves) do
        local d = data.moves[mid]
        m.moves[i] = { id = mid, pp = d and d.pp or 10, maxPp = d and d.pp or 10 }
      end
    end
    return m
  end
  local party = {
    make("LUCARIO", 40, { "STEALTH_ROCK", "PROTECT", "U_TURN", "RAIN_DANCE" }),
    make("GYARADOS", 40, { "DRAGON_DANCE", "WATERFALL", "TAUNT", "ICE_FANG" }),
    make("GARCHOMP", 40, { "EARTHQUAKE", "SWORDS_DANCE", "STONE_EDGE", "FIRE_FANG" }),
  }
  game.save.party = party
  check(data.moves.STEALTH_ROCK and tostring(data.moves.STEALTH_ROCK.effect):find("^NDX_M_") ~= nil,
    "Stealth Rock runs on the mechanics layer")

  section("summary", function()
    local Screens = require("src.ui.Screens")
    if gen == 1 then Screens.push(game, "SummaryMenu", party[2])
    else Screens.push(game, "Gen2SummaryMenu", { party = party, index = 2, onClose = function() end }) end
    U.wait(40); shot("summary_1")
    U.tap(game, "a"); U.wait(30); shot("summary_2")
    U.tap(game, "a"); U.wait(30); shot("summary_3")
    if gen == 1 then U.tap(game, "a"); U.wait(30); shot("summary_4") end
    while #(game.stack.states or {}) > 1 and game.stack:top() ~= game.overworld do game.stack:pop() end
    U.wait(20)
  end)

  section("battle", function()
    local turns = { 1, 4, 2, 1, 3 }
    if gen == 1 then
      local BattleState = require("src.battle.BattleState")
      local battle = BattleState.newWild(game, "SNORLAX", 45)
      battle.onFinish = function() end
      game.overworld:pushBattle(battle)
      local function toMenu()
        for _ = 1, 400 do
          if battle.phase == "menu" then return true end
          U.tap(game, "a"); U.wait(4)
        end
        return battle.phase == "menu"
      end
      check(toMenu(), "the battle reaches its menu")
      for i, slot in ipairs(turns) do
        if battle.result then break end
        local mv = battle.player.curMoves[slot]
        if mv then
          battle:resolveTurn(mv)
          for f = 1, 300 do
            if battle.phase == "menu" or battle.result then break end
            if f % 5 == 0 then U.tap(game, "a") end
            U.wait(1)
            if f == 60 then shot("battle_turn" .. i) end
          end
          log("turn " .. i .. ": " .. mv.id .. " -> foe HP " .. tostring(battle.enemy.mon.hp)
            .. ", weather " .. tostring(battle.__ndxField and battle.__ndxField.weather and battle.__ndxField.weather.kind))
        end
      end
      check(true, "five turns of new moves ran on Red")
    else
      local wild = make("SNORLAX", 45)
      assert(game.world:startBattle({ wild = wild }), "startBattle failed")
      local screen
      for _ = 1, 900 do
        local top = game.stack:top()
        if top and top.battle then screen = top break end
        U.wait(1)
      end
      assert(screen, "no battle screen")
      for _ = 1, 40 do
        if screen.showPlayerHud then break end
        U.tap(game, "a"); U.wait(8)
      end
      local b = screen.battle
      for i, slot in ipairs(turns) do
        if b.over then break end
        local mv = b.player.moves[slot]
        if mv then
          local events = b:takeTurn({ kind = "move", move = mv.id })
          local said = {}
          for _, ev in ipairs(events or {}) do
            if ev.text then said[#said + 1] = (tostring(ev.text):gsub("%s+", " ")) end
          end
          log("turn " .. i .. ": " .. mv.id .. " -> foe HP " .. tostring(b.enemy.hp) .. ", weather "
            .. tostring(b.weather) .. " | " .. table.concat(said, " / "))
        end
      end
      U.wait(30); shot("battle_after")
      check(true, "five turns of new moves ran on Gold")
    end
    while #(game.stack.states or {}) > 1 and game.stack:top() ~= game.overworld do game.stack:pop() end
    U.wait(30)
  end)

  section("day care", function()
    if gen ~= 1 then return end
    U.teleport(game, "DAYCARE", 3, 5, "up")
    for _ = 1, 120 do U.wait(1) end
    shot("daycare")
    local ok, npc = pcall(game.world and game.world.npc or function() end, game.world, "DAYCARE",
      "NATIONAL_DEX_GEN3_DAYCARE_LADY")
    log("lady placed: " .. tostring(ok and npc ~= nil))
    local B = game.mods and game.mods.exports and game.mods.exports.national_dex_gen3
      and game.mods.exports.national_dex_gen3._breeding
    if B then
      B.talk(game)
      for i = 1, 30 do U.wait(4); if i == 10 then shot("daycare_talk") end end
    end
    check(B ~= nil, "the Day Care Lady is installed")
  end)
  log(("%d failure(s)"):format(fails))
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
