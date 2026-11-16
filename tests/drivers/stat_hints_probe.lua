-- Driver: Stat Hints (src/stat_hints.lua) in real battles. A new game, a Gyarados that knows Swords
-- Dance against a wild Spearow: Swords Dance twice through the battle's own menu, the chip by your box
-- checked against your Attack stage after every move (stacking; Spearow's Growl in between lowers
-- it); then several changes on both sides (shots), and a doubles battle with five changes on each of
-- the four Pokemon: every chip checked clear of every HP box. Shots in SHOT_DIR.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/national_dex_gen3/tests/drivers/stat_hints_probe.lua love .

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
  game:_handleBootAction({ action = "new_game", name = "HINT", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local Healthbox = require("src.core.game3.battle.healthbox")
  local Chrome = require("src.ui.game3.battle_chrome")
  local GAME = require("src.core.GameVersion").get()
  local C = require("src.core.game3.constants").of(GAME)
  local session = Runtime.getSession()
  check(session ~= nil, "field session exists")
  if not session then return end
  local function sp(name) return C.species.byName["SPECIES_" .. name] end

  local state = Healthbox.__ndxStatHints
  check(state ~= nil, "Stat Hints are installed")
  if not state then return end
  local SH = dofile("mods/national_dex_gen3/src/stat_hints.lua")
  local drawChip = state.drawChip
  local chips, boxes = {}, {}
  local seenChip, seenBox = {}, {}
  state.drawChip = function(text, up, x, y, w, h)
    local key = text .. "@" .. x .. "," .. y
    if not seenChip[key] then
      seenChip[key] = true
      chips[#chips + 1] = { text = text, up = up, x = x, y = y, w = w or SH.width(text), h = h or SH.H }
    end
    return drawChip(text, up, x, y, w, h)
  end
  log("drawn at " .. (state.view() and "window resolution (WoobleView)" or "the game's pixels"))
  -- every HP box drawn, from the cart's own draws (their pictures' frames: SH.FRAME)
  for _, f in ipairs({ { "drawEnemyBox", "enemy" }, { "drawPlayerBox", "player" } }) do
    local inner, side = Chrome[f[1]], f[2]
    Chrome[f[1]] = function(x, y, ...)
      local key = side .. "@" .. x .. "," .. y
      if not seenBox[key] then seenBox[key] = true; boxes[#boxes + 1] = { side = side, x = x, y = y } end
      return inner(x, y, ...)
    end
  end
  local innerD = Chrome.drawDoublesBox
  Chrome.drawDoublesBox = function(isPlayer, x, y, ...)
    local key = "d" .. tostring(isPlayer) .. "@" .. x .. "," .. y
    if not seenBox[key] then
      seenBox[key] = true
      boxes[#boxes + 1] = { side = isPlayer and "player" or "enemy", x = x, y = y, doubles = true }
    end
    return innerD(isPlayer, x, y, ...)
  end
  local function frame()
    U.wait(2)
    chips, boxes, seenChip, seenBox = {}, {}, {}, {}
    U.wait(1)
  end

  session.party = {}
  Party.giveMon(session, sp("GYARADOS"), 30, "MON")
  local mon = session.party[1]
  mon.hp = mon.maxHp or mon.hp
  mon.moves = { 14, 44, 0, 0 }                              -- SWORDS DANCE, BITE
  mon.pp = { 30, 25, 0, 0 }
  local started, serr = BattleBridge.startWild(Runtime._mod, game, { species = sp("SPEAROW"), level = 5 }, { fade = false })
  check(started == true, "wild battle started " .. tostring(serr or ""))
  if not started then return end
  local function toMenu()
    for _ = 1, 6000 do
      if Battle.isActive() and Ui._mode == "menu" and not Anim.busy() then return true end
      if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
    end
    return false
  end
  check(toMenu(), "battle reached the action menu")
  local BattleAPI = require("src.battle.game3.BattleAPI")
  local bapi = BattleAPI.new(game)
  local intentId = 0
  local function submit(intent)             -- every intent a fresh id (the API refuses a replayed one)
    intentId = intentId + 1
    intent.id = intentId
    return bapi:submit(intent)
  end
  local st = Battle._st
  local function myAttackChip()
    for _, c in ipairs(chips) do if c.text:sub(1, 3) == "ATK" and c.y > 60 then return c.text end end
    return nil
  end
  -- Swords Dance twice, through the battle's own menu: after each, the chip is the stage as it is now
  -- (Spearow's Growl may take one back each turn: the chip follows that too)
  local after = {}
  for turn = 1, 2 do
    local sn = bapi:snapshot()
    submit({ revision = sn.revision, kind = "menu", choice = "fight" })
    waitFor(function() return Ui._mode == "moves" end, 240)
    U.wait(4)
    sn = bapi:snapshot()
    local ok, why = submit({ revision = sn.revision, kind = "move", slot = 1 })
    check(ok and true or false, ("turn %d: Swords Dance chosen %s"):format(turn, tostring(why or "")))
    check(toMenu(), ("turn %d: back at the menu"):format(turn))
    frame()
    local stage = st.player.stages.attack or 0
    after[turn] = stage
    local want = SH.text("attack", "ATK", stage)
    log(("turn %d: Attack stage %d, chip %s"):format(turn, stage, tostring(myAttackChip())))
    check(myAttackChip() == want, ("turn %d: the chip shows the stage as it is now (%s)"):format(turn, tostring(want)))
    U.still(game, ("%s/hints_turn%d.png"):format(dir, turn))
  end
  check((after[2] or 0) > (after[1] or 0) and (after[1] or 0) > 0,
    ("the second Swords Dance stacked on the first (+%s, then +%s)"):format(tostring(after[1]), tostring(after[2])))

  -- several changes on both sides, singles
  st.player.stages.spAtk, st.player.stages.speed = -2, 1
  st.enemy.stages.defense, st.enemy.stages.speed, st.enemy.stages.accuracy, st.enemy.stages.evasion = -1, 2, -1, 1
  frame()
  U.still(game, dir .. "/hints_singles.png")
  local function clearOfBoxes(label)
    local bad = 0
    for _, c in ipairs(chips) do
      for _, b in ipairs(boxes) do
        local F = SH.FRAME
        local x0, x1, y0, y1
        if b.doubles then
          x0 = b.x + (b.side == "player" and F.doubles.playerLeft or 0)
          x1 = b.x + (b.side == "player" and 103 or F.doubles.enemyRight)
          y0, y1 = b.y + F.doubles.top, b.y + F.doubles.bottom
        else
          local e = b.side == "player" and F.player or F.enemy
          x0, x1, y0, y1 = b.x + e.left, b.x + e.right, b.y + 2, b.y + e.bottom
        end
        if c.x < x1 and c.x + c.w > x0 and c.y < y1 and c.y + c.h > y0 then bad = bad + 1 end
      end
    end
    log(("%s: %d chips, %d boxes"):format(label, #chips, #boxes))
    for _, c in ipairs(chips) do log(("  %s at %d,%d"):format(c.text, c.x, c.y)) end
    for _, b in ipairs(boxes) do log(("  box %s%s at %d,%d"):format(b.side, b.doubles and " (doubles)" or "", b.x, b.y)) end
    check(bad == 0, ("%s: no chip on any HP box (%d)"):format(label, bad))
  end
  local want = 0
  for _, side in ipairs({ st.player, st.enemy }) do
    for _, s in ipairs(SH.STATS) do if (side.stages[s.key] or 0) ~= 0 then want = want + 1 end end
  end
  check(#chips == want, ("singles: a chip per changed stat, both sides (%d of %d)"):format(#chips, want))
  clearOfBoxes("singles")

  -- run, then a doubles battle
  local ran = false
  for _ = 1, 1500 do
    U.wait(1)
    local sn = bapi:snapshot()
    local p = sn and sn.prompt
    if p == "advance" then U.tap(game, "a"); U.wait(4)
    elseif p == "menu" and not ran then
      ran = submit({ revision = sn.revision, kind = "menu", choice = "run" }) and true or false
    elseif not Battle.isActive() then break end
  end
  check(not Battle.isActive(), "ran from the wild battle")
  waitFor(function() return not Battle.isActive() end, 1200)
  U.wait(60)
  local Trainers = require("src.core.game3.scripting.trainers")
  local foe, foeId
  for id = 1, 900 do
    local info = Trainers.info(id)
    if info and info.doubleBattle and (info.partySize or 0) >= 2 then foe, foeId = info, id break end
  end
  check(foe ~= nil, "found a double trainer " .. tostring(foeId))
  if not foe then log(("%d failures"):format(fails)) return end
  Party.giveMon(session, sp("PIKACHU"), 30, "SPARK")
  for _, m in ipairs(session.party) do m.hp = m.maxHp or m.hp end
  local okD, why = BattleBridge.start(Runtime._mod, game, foe, { wild = false, trainerId = foeId, double = true, noWhiteout = true })
  check(okD == true, "doubles battle started " .. tostring(why or ""))
  if okD then
    check(toMenu() and Battle._st and Battle._st.double, "the doubles battle reached the action menu")
    local State = require("src.core.game3.battle.state")
    local dst = Battle._st
    for id = 0, 3 do
      local b = State.battler(dst, id)
      if b and b.stages then
        b.stages.attack, b.stages.defense, b.stages.speed, b.stages.spAtk, b.stages.spDef = 2, -1, 1, -2, 1
      end
    end
    frame()
    U.still(game, dir .. "/hints_doubles.png")
    check(#chips == 20, ("doubles: five chips on each of four (%d)"):format(#chips))
    clearOfBoxes("doubles")
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
