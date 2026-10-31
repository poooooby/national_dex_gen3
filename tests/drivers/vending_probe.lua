-- Driver: the vending machines (src/vending.lua, src/vending_screen.lua) in the engine. A new game,
-- money, then Lilycove Dept. Store 4F: both machines stand at their tiles; A on the evolution item
-- machine opens its screen, and the buttons buy three of an item (the Bag and the money checked);
-- back on the grid after it, B leaves and the player walks again; A on the TM machine, then the mouse alone (through
-- the engine's pointer path): a tab, a tile, +, BUY, YES, the close button. Shots v*.png.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/national_dex_gen3/tests/drivers/vending_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/ndx"
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "VEND", gender = 0 })
  U.wait(90)
  local Runtime = require("src.core.game3.runtime")
  local Bag = require("src.core.game3.bag")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Field = require("src.core.game3.field")
  local Stack = require("src.ui.game3.stack")
  local Profile = require("src.core.game3.profile")
  local s0 = Runtime.getSession()
  s0.money = 50000
  local nd = game.mods.exports.national_dex_gen3
  local V = nd and nd._vending
  if not V then log("FAIL national_dex_gen3 has no _vending"); return end
  local S = V.screen

  local prefix = Profile.forSession(s0).map.enginePrefix
  local byId = {}
  for _, m in ipairs(V.machines) do byId[m.id] = m end
  -- in front of a machine, facing it
  local function goTo(id)
    local place = V.placeIn(byId[id])
    if not place then
      check(false, id .. " stands somewhere in this game")
      return nil
    end
    local mapId = prefix .. place.map
    Warp.request(nil, game, mapId, place.x, place.y + 1, "up", {})
    check(waitFor(function() return Map.current == mapId and not Warp.isBusy() end, 1200), "warped to " .. mapId)
    U.wait(60)
    local placed = V.spawned[mapId] or {}
    check(placed[id] ~= nil, id .. " placed at " .. place.x .. "," .. place.y .. " (" .. tostring(placed[id]) .. ")")
    return place
  end
  goTo("evo")
  shot("v1_store")

  -- the evolution item machine, by buttons
  U.tap(game, "a")
  check(waitFor(function() return S.isOpen() end, 120), "A on the evolution item machine opens its screen")
  -- the boot, frame by frame: black, the tube opening, the logo, its shine, the reveal
  U.wait(4)
  shot("b1_black")
  check(S.booting(), "it boots first")
  for i, at in ipairs({ 0.44, 0.75, 1.25, 1.75 }) do
    waitFor(function() return S.state() and (love.timer.getTime() - S.state().t0) >= at end, 240)
    shot("b" .. (i + 1) .. "_boot")
  end
  check(waitFor(function() return not S.booting() end, 240), "then reveals the shop")
  U.wait(30)
  shot("v2_evo_grid")
  -- the garbage the whole game makes per second with the screen up (idle on the grid)
  local function kbPerSecond()
    collectgarbage("collect")
    local t0, kb0 = love.timer.getTime(), collectgarbage("count")
    collectgarbage("stop")
    U.wait(120)
    local kb = collectgarbage("count") - kb0
    collectgarbage("restart")
    return kb / math.max(0.001, love.timer.getTime() - t0)
  end
  local openKb = kbPerSecond()
  log(("  garbage, screen open: %.0f KB/s"):format(openKb))
  -- the screen's own share: its draw, measured around each call
  -- (and the engine calls it makes, each metered on its own)
  local metered = {}
  local function meter(mod, fname, label)
    local orig = mod and mod[fname]
    if type(orig) ~= "function" then return end
    local m = { label = label, kb = 0, calls = 0 }
    metered[#metered + 1] = { mod = mod, fname = fname, orig = orig, m = m }
    mod[fname] = function(...)
      local kb0 = collectgarbage("count")
      local a, b2, c = orig(...)
      m.kb, m.calls = m.kb + (collectgarbage("count") - kb0), m.calls + 1
      return a, b2, c
    end
  end
  meter(Bag, "get", "Bag.get")
  meter(Bag, "canAdd", "Bag.canAdd")
  meter(require("src.ui.game3.frlg_font"), "drawGlyph", "FrlgFont.drawGlyph")
  meter(require("src.ui.game3.frlg_font"), "advance", "FrlgFont.advance")
  meter(require("src.ui.game3.rse.bag_chrome"), "drawItemIcon", "BagChrome.drawItemIcon")
  meter(Runtime, "getSession", "Runtime.getSession")
  meter(require("src.core.SafeArea"), "windowRect", "SafeArea.windowRect")
  local draw, drawKb, draws = S.draw, 0, 0
  S.draw = function(...)
    local was = collectgarbage("isrunning")
    collectgarbage("stop")
    local kb0 = collectgarbage("count")
    draw(...)
    drawKb, draws = drawKb + (collectgarbage("count") - kb0), draws + 1
    if was then collectgarbage("restart") end
  end
  U.wait(120)
  S.draw = draw
  for _, e in ipairs(metered) do
    e.mod[e.fname] = e.orig
    log(("    %s: %.3f KB per frame (%d calls)"):format(e.m.label, e.m.kb / math.max(1, draws), e.m.calls))
  end
  local perFrame = drawKb / math.max(1, draws)
  log(("  the screen's draw: %.3f KB per frame over %d frames (%.1f KB/s at 60 fps)"):format(perFrame, draws,
    perFrame * 60))
  check(perFrame < 0.5, "the screen's draw makes next to no garbage")
  local st = S.state()
  -- Up from the top row: the tabs; Right there changes tab; Left and Down come back
  U.tap(game, "up"); U.wait(4)
  check(st.focus == "tabs", "Up from the top row reaches the tabs")
  U.tap(game, "right"); U.wait(4)
  check(st.tab == 2 and st.focus == "tabs", "Right on the tabs: the next tab (" .. st.tab .. ")")
  shot("v2b_tabs")
  U.tap(game, "left"); U.wait(4)
  U.tap(game, "down"); U.wait(4)
  check(st.tab == 1 and st.focus == "grid", "Left, Down: the first tab's grid")
  U.tap(game, "right"); U.wait(4)
  U.tap(game, "down"); U.wait(4)
  local item = st.tabs[st.tab].entries[st.cursor]
  check(st.cursor == 2 + st.cols, "the D-pad moves the cursor (" .. tostring(st.cursor) .. ")")
  U.tap(game, "a"); U.wait(6)
  check(st.focus == "card", "A opens the card")
  U.tap(game, "right"); U.wait(4)
  U.tap(game, "right"); U.wait(4)
  shot("v3_evo_card")
  U.tap(game, "a"); U.wait(6)
  check(st.focus == "confirm", "A asks")
  shot("v4_confirm")
  local before, money0 = Bag.get(s0.bag, item.id), s0.money
  U.tap(game, "a"); U.wait(8)
  shot("v5_bought")
  U.wait(30)
  shot("v5b_in_tray")
  check(Bag.get(s0.bag, item.id) == before + 3, "three " .. tostring(item.name) .. " in the Bag")
  check(s0.money == money0 - 3 * item.price, "money " .. money0 .. " -> " .. s0.money)
  check(st.focus == "grid", "bought: back to browsing")
  U.tap(game, "b"); U.wait(20)
  check(not S.isOpen() and not Stack.has("national_dex_gen3_vending"), "B leaves")
  U.wait(30)
  local closedKb = kbPerSecond()
  log(("  garbage, screen closed: %.0f KB/s"):format(closedKb))
  log(("  (the whole game's, open - closed: %.0f KB/s; the engine draws other things in each)"):format(openKb - closedKb))
  -- the player walks again: a step whichever way is clear
  local x0, y0 = Player.cellX, Player.cellY
  for _, dir in ipairs({ "left", "right", "down" }) do
    U.hold(game, dir, 16); U.wait(20)
    if Player.cellX ~= x0 or Player.cellY ~= y0 then break end
  end
  check(Player.cellX ~= x0 or Player.cellY ~= y0, "the player walks again (" .. tostring(Player.cellX) .. ","
    .. tostring(Player.cellY) .. ")")
  goTo("tm")
  shot("v1b_tm_store")

  -- the TM machine, by the mouse alone
  U.tap(game, "a")
  check(waitFor(function() return S.isOpen() end, 120), "A on the TM machine opens its screen")
  -- (a tap skips the boot)
  U.wait(10)
  local skip
  for _, h in ipairs(S.state().hit) do if h.kind == "skip" then skip = h end end
  check(skip ~= nil, "booting: a tap to skip")
  if skip then
    game:mousepressed(skip[1] + skip[3] / 2, skip[2] + skip[4] / 2, 1, false)
    U.wait(2)
    game:mousereleased(skip[1] + skip[3] / 2, skip[2] + skip[4] / 2, 1, false)
  end
  U.wait(4)
  check(not S.booting(), "a click skips the boot")
  U.wait(30)
  shot("v6_tm_grid")
  st = S.state()
  local function click(kind, arg)
    for _, h in ipairs(st.hit) do
      if h.kind == kind and (arg == nil or h.arg == arg) then
        local x, y = h[1] + h[3] / 2, h[2] + h[4] / 2
        game:mousepressed(x, y, 1, false)
        U.wait(2)
        game:mousereleased(x, y, 1, false)
        U.wait(6)
        return true
      end
    end
    log("  no " .. kind .. " to click")
    return false
  end
  click("nextTab"); click("nextTab"); click("nextTab")
  check(st.tab == 4, "the tab arrow, clicked three times (" .. st.tab .. ")")
  shot("v7_tm_type")
  click("tile", 1)
  check(st.focus == "card", "a click on a tile opens its card")
  local tm = st.tabs[st.tab].entries[st.cursor]
  click("plus")
  check(st.qty == 2, "+ clicked")
  shot("v8_tm_card")
  click("buy")
  check(st.focus == "confirm", "BUY clicked asks")
  local tmBefore = Bag.get(s0.bag, tm.id)
  click("yes")
  U.wait(10)
  shot("v9_tm_bought")
  check(Bag.get(s0.bag, tm.id) == tmBefore + 2, "two " .. tostring(tm.name) .. " in the Bag")
  check(st.focus == "grid", "bought: back to browsing")
  -- too little money: BUY refuses, the money box flashes red
  local money1 = s0.money
  s0.money = 10
  click("tile", 1)
  click("plus")
  check(st.qty == 2, "the amount still moves with too little money")
  click("buy")
  U.wait(4)
  shot("v9b_no_money")
  check(st.toast and st.toast.text == S.TEXT.noMoney and st.moneyFlash ~= nil,
    "BUY with too little money: refused, the money box flashing")
  s0.money = money1
  click("close")
  U.wait(20)
  check(not S.isOpen() and not Field.isLocked(), "the close button leaves")
  shot("v10_back")

  -- the window's shape: the screen lays out for each (then the window goes back as it was)
  local W0, H0, flags = love.window.getMode()
  for _, shape in ipairs({ { "w16x9", 1280, 720 }, { "portrait", 430, 900 }, { "w21x9", 1680, 720 },
                          { "w4x3", 1024, 768 }, { "small", 640, 480 }, { "portrait_small", 360, 760 } }) do
    love.window.setMode(shape[2], shape[3], flags)
    if love.resize then pcall(love.resize, shape[2], shape[3]) end
    U.wait(20)
    U.tap(game, "a")
    check(waitFor(function() return S.isOpen() end, 120), shape[1] .. ": A opens the TM machine")
    U.wait(50)
    shot("v11_" .. shape[1] .. "_boot")
    waitFor(function() return not S.booting() end, 240)
    U.wait(30)
    st = S.state()
    local L = st.layout or {}
    log(("  %s: %s, page %.0f x %.0f, grid %d x %d"):format(shape[1], L.portrait and "portrait" or "landscape",
      L.pw or 0, L.ph or 0, L.cols or 0, L.rows or 0))
    check((shape[1]:find("portrait", 1, true) ~= nil) == (L.portrait == true),
      shape[1] .. ": laid out " .. (L.portrait and "portrait" or "wide"))
    shot("v11_" .. shape[1])
    click("tile", 2)
    check(st.focus == "card", shape[1] .. ": a click on a tile opens its card")
    shot("v12_" .. shape[1] .. "_card")
    -- the longest amounts: the most money a save holds, 99 of a TM
    local money0 = s0.money
    s0.money = 999999
    S.setQty(99)
    U.wait(4)
    shot("v12b_" .. shape[1] .. "_most")
    S.setQty(1)
    s0.money = money0
    -- a newer move with a two-word name, in full and broken between its words
    for i, e in ipairs(st.tabs[st.tab].entries) do
      if e.tm and e.tm.number == 111 then
        S.choose(i)
        check(e.tm.move == "MISTY TERRAIN", shape[1] .. ": TM111 reads " .. tostring(e.tm.move))
      end
    end
    U.wait(20)
    shot("v12c_" .. shape[1] .. "_misty")
    click("buy")
    click("yes")
    U.wait(8)
    shot("v13_" .. shape[1] .. "_bought")
    click("close")
    U.wait(20)
    check(not S.isOpen(), shape[1] .. ": closed")
  end
  love.window.setMode(W0, H0, flags)
  if love.resize then pcall(love.resize, W0, H0) end
  U.wait(10)
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
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  log("DONE")
  if logFile then logFile:close() end
  love.event.quit()
end
