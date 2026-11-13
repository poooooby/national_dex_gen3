-- Driver: the held items in the real engine, on any game. The HELD EXPRESS machine (where it
-- stands, its screen), and on Red the summary's SP.ATK / SP.DEF and a shiny star, then a battle turn
-- with a Life Orb. Shots and driver.log in SHOT_DIR. From the gen1recomp root:
--   SHOT_DIR=<dir> POKEPORT_VERSION=<red|gold|firered|emerald> \
--     POKEPORT_DRIVER=mods/national_dex_gen3/tests/drivers/held_probe.lua love .

local U = require("tests.drivers.util")

local function body(game, log, dir)
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
  local function section(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then fails = fails + 1; log("FAIL " .. name .. ": " .. tostring(err)) end
  end
  local version = require("src.core.GameVersion").get()
  local gen = (version == "red" or version == "blue" or version == "yellow") and 1
    or (version == "gold" or version == "silver" or version == "crystal") and 2 or 3
  log("version " .. tostring(version) .. " gen " .. gen)
  local function shot(name) U.shot(game, dir .. "/" .. version .. "_" .. name .. ".png") end
  local function waitFor(fn, n) for _ = 1, n or 600 do if fn() then return true end U.wait(1) end return fn() end
  if gen == 3 then
    if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
    game:_handleBootAction({ action = "new_game", name = "HELD", gender = 0 })
    U.wait(120)
  else
    waitFor(function() return game.save and game.stack and game.stack:top() end, 600)
    U.wait(60)
  end
  local nd = game.mods and game.mods.exports and game.mods.exports.national_dex_gen3
  local V = nd and nd._vending
  check(V ~= nil, "the vending machines are installed")
  if not V then return log(("%d failure(s)"):format(fails + 1)) end

  section("machine", function()
    local held
    for _, m in ipairs(V.machines) do
      local mm = m.m or m
      if mm.id == "held" then held = m end
    end
    check(held ~= nil, "HELD EXPRESS is one of the machines")
    if gen == 3 then
      local Map = require("src.core.game3.map")
      local Warp = require("src.core.game3.warp")
      local Runtime = require("src.core.game3.runtime")
      local Profile = require("src.core.game3.profile")
      local Flags = require("src.core.game3.scripting.flags")
      local Space = require("src.core.game3.scripting.space")
      local s0 = Runtime.getSession()
      s0.money = 99999
      for i = 1, 8 do Flags.setBadge(Space.store or s0, i, true) end
      local place = V.placeIn(held)
      local mapId = Profile.forSession(s0).map.enginePrefix .. place.map
      Warp.request(nil, game, mapId, place.x, place.y + 1, "up", {})
      check(waitFor(function() return Map.current == mapId and not Warp.isBusy() end, 1200), "warped to " .. mapId)
      U.wait(90)
      shot("held_floor")
      U.tap(game, "a")
      check(waitFor(function() return V.screen.isOpen() end, 120), "A opens HELD EXPRESS")
      U.wait(200); shot("held_screen")
      U.tap(game, "down"); U.wait(10); U.tap(game, "a"); U.wait(30); shot("held_card")
      for _ = 1, 8 do U.tap(game, "b"); U.wait(10) end
      return
    end
    local place = held.place
    if gen == 1 then
      game.save.money = 99999
      U.teleport(game, place.map, place.x, place.y + 1, "up")
    else
      game.save.player.money = 99999
      game.world:warpToMapId(place.map, place.x, place.y + 1, "up")
    end
    for _ = 1, 150 do U.wait(1); if not V.pending then break end end
    U.wait(40); shot("held_floor")
    U.tap(game, "a")
    check(waitFor(function() return V.screen.isOpen() end, 90), "A opens HELD EXPRESS")
    U.wait(200); shot("held_screen")
    U.tap(game, "down"); U.wait(10); U.tap(game, "a"); U.wait(30); shot("held_card")
    for _ = 1, 8 do U.tap(game, "b"); U.wait(10) end
    U.wait(20)
  end)

  if gen == 1 then
    section("summary and battle", function()
      local Mon = require("src.pokemon.Pokemon")
      local Stats = require("src.pokemon.Stats")
      local data = game.data
      local m = Mon.new(data, "ALAKAZAM", 50)
      m.dvs = { attack = 10, defense = 10, speed = 10, special = 10, hp = 0 }     -- shiny
      m.stats = Stats.calc(data.pokemon.ALAKAZAM, 50, m.dvs, m.statExp)
      m.hp = m.stats.hp
      m.extra = { national_dex_gen3 = { item = "LIFE_ORB" } }
      game.save.party = { m }
      local Screens = require("src.ui.Screens")
      Screens.push(game, "SummaryMenu", m)
      U.wait(40); shot("summary_1")
      U.tap(game, "a"); U.wait(30); U.tap(game, "a"); U.wait(30); shot("summary_3")
      while #(game.stack.states or {}) > 1 and game.stack:top() ~= game.overworld do game.stack:pop() end
      U.teleport(game, "ROUTE_1", 5, 5, "down"); U.wait(30)
      local BattleState = require("src.battle.BattleState")
      local battle = BattleState.newWild(game, "SNORLAX", 50)
      battle.onFinish = function() end
      game.overworld:pushBattle(battle)
      for f = 1, 400 do
        if battle.phase == "menu" then break end
        if f == 90 then shot("battle_sendout") end
        U.tap(game, "a"); U.wait(4)
      end
      check(battle.phase == "menu", "the battle reaches its menu")
      local hp0 = battle.player.mon.hp
      local mv = battle.player.curMoves[1]
      battle:resolveTurn(mv)
      for f = 1, 300 do
        if battle.phase == "menu" or battle.result then break end
        if f % 5 == 0 then U.tap(game, "a") end
        U.wait(1)
      end
      log("Life Orb: user HP " .. hp0 .. " -> " .. battle.player.mon.hp .. " after " .. tostring(mv and mv.id))
      check(battle.player.mon.hp < hp0, "Life Orb cost the user HP")
      shot("battle_after")
      while #(game.stack.states or {}) > 1 and game.stack:top() ~= game.overworld do game.stack:pop() end
    end)
  end
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
