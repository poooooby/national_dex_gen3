-- Driver: the type badges beside the battle's HP boxes (src/type_badges.lua) in a real battle. A new game,
-- a Gyarados (Water / Flying) against a wild Spearow (Normal / Flying): each box gets its badges, beside it
-- (shots to check against the cart's box pictures), and they make no garbage of their own. Then the same
-- again and a doubles battle, both in the BADGES_SHAPE window (WoobleView's Fill Screen). Shots in SHOT_DIR.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/national_dex_gen3/tests/drivers/type_badges_probe.lua love .

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
  -- BADGES_SHAPE=WxH: the window both battles are fought in (set before either starts, as a player's is)
  local shapeW, shapeH = (os.getenv("BADGES_SHAPE") or ""):match("(%d+)x(%d+)")
  if shapeW then
    love.window.setMode(tonumber(shapeW), tonumber(shapeH), { resizable = true, highdpi = true })
    U.wait(2)
  end
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "BADGE", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local Healthbox = require("src.core.game3.battle.healthbox")
  local GAME = require("src.core.GameVersion").get()
  local C = require("src.core.game3.constants").of(GAME)
  local session = Runtime.getSession()
  check(session ~= nil, "field session exists")
  if not session then return end
  local function sp(name) return C.species.byName["SPECIES_" .. name] end

  local state = Healthbox.__ndxBadges
  check(state ~= nil, "the badges are installed")
  if not state then return end
  local seen = {}
  local draw = state.drawBadge
  state.drawBadge = function(t, x, y)
    seen[#seen + 1] = ("%d@%d,%d"):format(t, x, y)
    return draw(t, x, y)
  end

  session.party = {}
  Party.giveMon(session, sp("GYARADOS"), 30, "MON")
  session.party[1].hp = session.party[1].maxHp or session.party[1].hp
  local started, serr = BattleBridge.startWild(Runtime._mod, game, { species = sp("SPEAROW"), level = 5 }, { fade = false })
  check(started == true, "wild battle started " .. tostring(serr or ""))
  if not started then return end
  local shot, frame = 0, 0
  local ready = false
  for _ = 1, 6000 do
    frame = frame + 1
    if frame % 40 == 0 and shot < 4 then
      shot = shot + 1
      U.still(game, ("%s/badges_intro_%d.png"):format(dir, shot))
    end
    if Battle.isActive() and Ui._mode == "menu" and not Anim.busy() then ready = true break end
    if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
  end
  check(ready, "battle reached the action menu")
  if not ready then return end
  U.wait(30)
  seen = {}
  U.still(game, dir .. "/badges_menu.png")
  log("badges drawn: " .. table.concat(seen, " "))
  -- two frames' worth: Spearow (Normal 0 / Flying 2) right of its box, Gyarados (Water 11 / Flying 2) left of its
  local has = {}
  for _, s in ipairs(seen) do has[s:match("^(%d+)@")] = true end
  check(has["0"] and has["2"] and has["11"], "Normal, Flying and Water badges are drawn")

  local function rate(frames)
    collectgarbage("collect")
    local kb0 = collectgarbage("count")
    collectgarbage("stop")
    U.wait(frames)
    local kb = (collectgarbage("count") - kb0) / frames
    collectgarbage("restart")
    return kb
  end
  -- (measured without this probe's own recording, which makes a string a badge)
  local recording = state.drawBadge
  state.drawBadge = draw
  -- the HP box draw alone, 2000 times with the badges and 2000 without (the battle's own garbage
  -- swings by 20 KB a frame, far more than a draw could make)
  local enabled = state.enabled
  local disabled = function() return false end
  local st = Battle._st
  local function per(times)
    collectgarbage("collect")
    collectgarbage("stop")
    local kb0 = collectgarbage("count")
    for _ = 1, times do
      Healthbox.draw("enemy", st.enemy, {})
      Healthbox.draw("player", st.player, {})
    end
    local kb = (collectgarbage("count") - kb0) * 1024 / times
    collectgarbage("restart")
    return kb
  end
  state.enabled = enabled
  local on = per(2000)
  state.enabled = disabled
  local off = per(2000)
  state.enabled = enabled
  state.drawBadge = function() end
  local noDraw = per(2000)
  state.drawBadge = draw
  log(("... %.1f with the badges' own LOVE draw calls left out"):format(noDraw))
  log(("bytes a frame's two HP boxes make: %.1f with badges, %.1f without"):format(on, off))
  state.enabled = disabled
  state.drawBadge = recording
  seen = {}
  U.still(game, dir .. "/badges_off.png")
  check(#seen == 0, "Type Badges off: none drawn")
  state.enabled = enabled
  -- (LOVE's own draw calls make a few bytes each, as every sprite does)
  check(noDraw <= off + 1, "the badges' own code makes no garbage")
  check(on <= off + 96, "and their draws next to none")

  -- singles again, then doubles, in this window: each badge is checked against the box it was drawn
  -- beside (in the battle's own 240 x 160 pixels, as the engine placed it), and shot as the window
  -- shows it (WoobleView's Fill Screen moves the UI)
  local boxes = {}
  local function noteBox(side)
    return function(x, y) boxes[#boxes + 1] = { side = side, x = x, y = y } end
  end
  local Chrome = require("src.ui.game3.battle_chrome")
  for _, f in ipairs({ { "drawEnemyBox", "enemy" }, { "drawPlayerBox", "player" } }) do
    local inner, note = Chrome[f[1]], noteBox(f[2])
    Chrome[f[1]] = function(x, y, ...) note(x, y); return inner(x, y, ...) end
  end
  local innerD = Chrome.drawDoublesBox
  Chrome.drawDoublesBox = function(isPlayer, x, y, ...)
    boxes[#boxes + 1] = { side = isPlayer and "player" or "enemy", x = x, y = y }
    return innerD(isPlayer, x, y, ...)
  end
  local marks = {}
  state.drawBadge = function(t, x, y)
    marks[#marks + 1] = { t = t, x = x, y = y }
    return draw(t, x, y)
  end
  -- every badge beside one box, 2 px clear of its frame: a foe's at its right (x + 95), the player's
  -- ending at its left (x + 7);
  -- the first of a set at the box's row 2
  local function placed(label, wantBoxes)
    boxes, marks = {}, {}
    U.shot(game, dir .. "/" .. label .. ".png")
    local w, h = love.graphics.getDimensions()
    check(#boxes == wantBoxes, ("%s (%dx%d): %d HP boxes drawn"):format(label, w, h, #boxes))
    local lonely = 0
    for _, m in ipairs(marks) do
      local near = false
      for _, b in ipairs(boxes) do
        local dy = m.y - (b.y + 2)
        if dy >= 0 and dy <= 16 and dy % 8 == 0 then
          local k = dy / 8
          if b.side == "enemy" and m.x == b.x + 95 + k * 8 then near = true end
          if b.side == "player" and m.x + 12 <= b.x + 7 and m.x >= b.x + 7 - 12 - 16 then near = true end
        end
      end
      if not near then lonely = lonely + 1 end
    end
    check(#marks >= wantBoxes and lonely == 0, ("%s: %d badges, each beside its box (%d not)"):format(label, #marks, lonely))
  end
  local w0, h0 = love.graphics.getDimensions()
  local shape = (h0 > w0 and "portrait_" or "landscape_") .. w0 .. "x" .. h0
  -- the touch surface out of the way (no cutout, no split), as WoobleView's own portrait driver does
  local loader = game.mods
  for _, id in ipairs({ "play_nav", "ds_touch" }) do
    if loader and loader.modOptions then
      loader.modOptions[id] = loader.modOptions[id] or {}
      loader.modOptions[id].display = "off"
    end
  end
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  log("WoobleView: " .. (hd and ("fill " .. tostring(hd.fillEnabled and hd.fillEnabled())) or "not loaded"))
  U.wait(30)
  placed("singles_" .. shape, 2)

  -- a doubles battle: this cart's first double trainer, against Gyarados and a Pikachu
  local BattleAPI = require("src.battle.game3.BattleAPI")
  local bapi = BattleAPI.new(game)
  local ran = false
  for _ = 1, 1500 do
    U.wait(1)
    local sn = bapi:snapshot()
    local p = sn and sn.prompt
    if p == "advance" then U.tap(game, "a"); U.wait(4)
    elseif p == "menu" and not ran then
      ran = bapi:submit({ id = 1, revision = sn.revision, kind = "menu", choice = "run" }) and true or false
    elseif not Battle.isActive() then break end
  end
  check(not Battle.isActive(), "ran from the wild battle")
  U.wait(30)
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
    local inMenu = false
    for _ = 1, 6000 do
      if Battle.isActive() and Ui._mode == "menu" and not Anim.busy() then inMenu = true break end
      if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
    end
    check(inMenu and Battle._st and Battle._st.double, "the doubles battle reached the action menu")
    U.wait(30)
    placed("doubles_" .. shape, 4)
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
