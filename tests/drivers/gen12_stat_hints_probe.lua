-- Driver: Stat Hints on Red / Gold (src/gen12/stat_hints.lua) in a real battle: a Pokemon that knows
-- Shell Smash and Swords Dance uses both against a wild Snorlax; after each move the chips drawn by
-- the HUDs are read (the hint's drawChip seam) and checked: the stages as they are now (Shell Smash:
-- five chips; Swords Dance after it: ATK 3x), all on the screen, none on another. Shots in SHOT_DIR.
-- From the gen1recomp root:
--   SHOT_DIR=<dir> POKEPORT_GAME=red POKEPORT_VERSION=red \
--   POKEPORT_DRIVER=mods/national_dex_gen3/tests/drivers/gen12_stat_hints_probe.lua love .

local U = require("tests.drivers.util")

local function body(game, log, dir)
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
  local version = require("src.core.GameVersion").get()
  local gen = (version == "gold" or version == "silver" or version == "crystal") and 2 or 1
  log("version " .. tostring(version))
  for _ = 1, 600 do
    if game.save and game.stack and game.stack:top() then break end
    U.wait(1)
  end
  U.wait(60)
  local data = game.data
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
  game.save.party = { make("CLOYSTER", 50, { "SHELL_SMASH", "SWORDS_DANCE", "PROTECT", "SURF" }) }

  local hub = gen == 1 and require("src.battle.BattleState").__ndxStatHints
    or require("src.ui.gen2.BattleState").__ndxStatHints
  local state = hub and hub.state
  check(state ~= nil and type(state.drawChip) == "function", "Stat Hints are installed on the HUDs")
  if not state then log(("%d failures"):format(fails)) return end
  local SH = dofile("mods/national_dex_gen3/src/stat_hints.lua")
  local chips, seen = {}, {}
  local drawChip = state.drawChip
  state.drawChip = function(text, up, x, y, w, h)
    local key = text .. "@" .. x .. "," .. y
    if not seen[key] then
      seen[key] = true
      chips[#chips + 1] = { text = text, x = x, y = y, w = w or SH.width(text), h = h or SH.H }
    end
    return drawChip(text, up, x, y, w, h)
  end
  local function frame() U.wait(2); chips, seen = {}, {}; U.wait(2) end
  local function has(text)
    for _, c in ipairs(chips) do if c.text == text then return true end end
    return false
  end
  local function tidy(label, width)
    local bad = 0
    for i, a in ipairs(chips) do
      if a.x < 0 or a.y < 0 or a.x + a.w > width then bad = bad + 1 end
      for j = i + 1, #chips do
        local b = chips[j]
        if a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h then bad = bad + 1 end
      end
    end
    for _, c in ipairs(chips) do log(("  %s at %d,%d (%dx%d)"):format(c.text, c.x, c.y, c.w, c.h)) end
    check(bad == 0, ("%s: %d chips, all on the screen, none on another (%d)"):format(label, #chips, bad))
  end

  local function after(turn, wantMine)
    frame()
    for _, t in ipairs(wantMine) do check(has(t), ("turn %d: %s shows"):format(turn, t)) end
    tidy("turn " .. turn, 160)
    U.shot(game, ("%s/%s_hints_turn%d.png"):format(dir, version, turn))
  end

  if gen == 1 then
    local BattleState = require("src.battle.BattleState")
    local battle = BattleState.newWild(game, "SNORLAX", 20)
    battle.onFinish = function() end
    game.overworld:pushBattle(battle)
    local function toMenu()
      for _ = 1, 600 do
        if battle.phase == "menu" then return true end
        U.tap(game, "a"); U.wait(4)
      end
      return battle.phase == "menu"
    end
    check(toMenu(), "the battle reaches its menu")
    for turn, slot in ipairs({ 1, 2 }) do
      battle:resolveTurn(battle.player.curMoves[slot])
      check(toMenu(), ("turn %d: back at the menu"):format(turn))
      after(turn, turn == 1 and { "ATK 2x", "SPA 2x", "SPE 2x", "DEF 0.67x", "SPD 0.67x" }
        or { "ATK 3x", "SPA 2x", "SPE 2x" })
    end
  else
    assert(game.world:startBattle({ wild = make("SNORLAX", 20) }), "startBattle failed")
    local screen
    for _ = 1, 900 do
      local top = game.stack:top()
      if top and top.battle then screen = top break end
      U.wait(1)
    end
    assert(screen, "no battle screen")
    for _ = 1, 60 do
      if screen.showPlayerHud then break end
      U.tap(game, "a"); U.wait(8)
    end
    local b = screen.battle
    for turn, slot in ipairs({ 1, 2 }) do
      -- (the turn is run directly: no button presses, which would choose another move)
      b:takeTurn({ kind = "move", move = b.player.moves[slot].id })
      U.wait(30)
      after(turn, turn == 1 and { "ATK 2x", "SPA 2x", "SPE 2x", "DEF 0.67x", "SPD 0.67x" }
        or { "ATK 3x", "SPA 2x", "SPE 2x" })
    end
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
  local ok, err = xpcall(function() body(game, log, dir) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  log("DONE")
  if logFile then logFile:close() end
  love.event.quit()
end
