-- Driver: Stat Hints on Red / Gold (src/gen12/stat_hints.lua) in a real battle: a Pokemon that knows
-- Shell Smash and Swords Dance uses both against a wild Snorlax; after each move the chips drawn by
-- the HUDs are read (the hint's drawChip seam) and checked: the stages as they are now (Shell Smash:
-- five chips; Swords Dance after it: ATK 3x), all on the screen, none on another. The type badges
-- are read too, and when a mod draws Gen 3 boxes in place of the HUDs (Facets' BATTLE UI in the wide
-- layout: a 128-wide picture drawn through love.graphics.draw) every chip and badge is checked
-- clear of that picture, row by row (src/box_shape.lua); WANT_MOD_BOXES=1 fails a run where no such
-- box was drawn. Shots in SHOT_DIR.
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
  -- FACETS_UI=<set>: Facets' BATTLE UI for this run only, in the loader's live options (the save's
  -- own Facets settings would otherwise win); nothing is written
  local facetsUi = os.getenv("FACETS_UI")
  if facetsUi and type(game.mods) == "table" then
    game.mods.modOptions = game.mods.modOptions or {}
    game.mods.modOptions.facets = game.mods.modOptions.facets or {}
    game.mods.modOptions.facets.classicBattleUi = facetsUi
    log("Facets BATTLE UI: " .. facetsUi)
  end
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
  local Shape = dofile("mods/national_dex_gen3/src/box_shape.lua")
  local chips, seen = {}, {}
  local badges, seenBadge, boxes, seenBox = {}, {}, {}, {}
  local badgeHub = gen == 1 and require("src.battle.BattleState").__ndxBadges
    or require("src.ui.gen2.BattleState").__ndxBadges
  local badgeState = badgeHub and badgeHub.state
  check(badgeState ~= nil, "Type Badges are installed on the HUDs")
  if badgeState then
    local drawBadge = badgeState.drawBadge
    badgeState.drawBadge = function(t, x, y)
      local key = t .. "@" .. x .. "," .. y
      if not seenBadge[key] then
        seenBadge[key] = true
        badges[#badges + 1] = { text = "badge " .. t, x = x, y = y, w = 10, h = 10 }
      end
      return drawBadge(t, x, y)
    end
  end
  -- a mod's Gen 3 box pictures (128 x 32 a foe's, 128 x 64 yours), wherever they are drawn
  local realDraw = love.graphics.draw
  love.graphics.draw = function(img, x, y, ...)
    if type(x) == "number" and (type(img) == "userdata" or type(img) == "table") and img.getDimensions then
      local ok, w, h = pcall(img.getDimensions, img)
      -- (not src/box_shape.lua measuring a picture: drawn alone onto a canvas its own size)
      local target = love.graphics.getCanvas()
      local tw, th
      if target then tw, th = target:getDimensions() end
      if ok and w == 128 and (h == 32 or h == 64) and not (tw == w and th == h) then
        local key = tostring(img) .. "@" .. x .. "," .. (y or 0)
        if not seenBox[key] then
          seenBox[key] = true
          boxes[#boxes + 1] = { side = h == 32 and "enemy" or "player", img = img, x = x, y = y or 0 }
        end
      end
    end
    return realDraw(img, x, y, ...)
  end
  local drawChip = state.drawChip
  state.drawChip = function(text, up, x, y, w, h)
    local key = text .. "@" .. x .. "," .. y
    if not seen[key] then
      seen[key] = true
      chips[#chips + 1] = { text = text, x = x, y = y, w = w or SH.width(text), h = h or SH.H }
    end
    return drawChip(text, up, x, y, w, h)
  end
  local function frame()
    U.wait(2)
    chips, seen, badges, seenBadge, boxes, seenBox = {}, {}, {}, {}, {}, {}
    U.wait(2)
  end
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
    -- the badges: on the screen, not on a chip; chips and badges off every mod box's drawn pixels
    local onChip, onBox, off = 0, 0, 0
    for _, a in ipairs(badges) do
      if a.x < 0 or a.y < 0 or a.x + a.w > width then off = off + 1 end
      for _, c in ipairs(chips) do
        if c.x < a.x + a.w and a.x < c.x + c.w and c.y < a.y + a.h and a.y < c.y + c.h then onChip = onChip + 1 end
      end
    end
    for _, b in ipairs(boxes) do
      local sh = Shape.of(b.img)
      if sh then
        log(("  %s box at %d,%d: rows %d-%d, columns %d-%d"):format(b.side, b.x, b.y, sh.top, sh.bottom, sh.minX, sh.maxX))
        for _, list in ipairs({ chips, badges }) do
          for _, c in ipairs(list) do
            for y = math.max(0, c.y - b.y), math.min(sh.h - 1, c.y + c.h - 1 - b.y) do
              local l, r = sh.left[y], sh.right[y]
              if l and c.x < b.x + r + 1 and c.x + c.w > b.x + l then
                onBox = onBox + 1
                log("  ON A BOX: " .. c.text)
                break
              end
            end
          end
        end
      end
    end
    for _, c in ipairs(badges) do log(("  %s at %d,%d"):format(c.text, c.x, c.y)) end
    check(#badges > 0 and off == 0, ("%s: %d badges, all on the screen (%d off)"):format(label, #badges, off))
    check(onChip == 0, ("%s: no chip on a badge (%d)"):format(label, onChip))
    check(onBox == 0, ("%s: no chip or badge on a mod's box (%d)"):format(label, onBox))
    if os.getenv("WANT_MOD_BOXES") then
      local e, pl = 0, 0
      for _, b in ipairs(boxes) do if b.side == "enemy" then e = e + 1 else pl = pl + 1 end end
      check(e > 0 and pl > 0, ("%s: the mod's boxes were drawn (foe %d, yours %d)"):format(label, e, pl))
    end
  end

  local screenW = 160      -- Red's wide layout: WideBattle's width (set when its battle starts)
  local function after(turn, wantMine)
    frame()
    local GS = gen == 2 and require("src.ui.gen2.BattleState")
    if GS and game.stack:top() and game.stack:top().battle then
      local top = game.stack:top()
      local okW, wide = pcall(function() return top:isWideBattleLayout() end)
      if okW and wide then
        local okM, WB = pcall(require, "src.ui.gen2.WideBattle")
        screenW = okM and tonumber(WB.WIDTH) or screenW
      end
      log(("layout %s, %d wide"):format(okW and wide and "wide" or "standard", screenW))
    end
    for _, t in ipairs(wantMine) do check(has(t), ("turn %d: %s shows"):format(turn, t)) end
    tidy("turn " .. turn, screenW)
    U.shot(game, ("%s/%s_hints_turn%d.png"):format(dir, version, turn))
  end

  -- cause, then effect: while a turn plays, the chip a move makes must not show before that move's
  -- "ATTACK ... rose" line has played. lineAhead() says whether that line is still to come (Red: not
  -- yet the row on screen; Gold: still in the screen's queue); done() when the turn has played out.
  local function rising(t)
    t = type(t) == "string" and t:upper() or ""
    return t:find("ATTACK") ~= nil and (t:find("ROSE") ~= nil or t:find("RISE") ~= nil)
  end
  local function watch(turn, want, lineAhead, done)
    local seenAt, early, f = nil, false, 0
    for _ = 1, 1500 do
      if done() then break end
      local ahead = lineAhead()
      chips, seen = {}, {}
      U.tap(game, "a"); U.wait(3); f = f + 1
      if not seenAt and has(want) then
        seenAt = f
        early = ahead and lineAhead()
      end
    end
    log(("turn %d: %s first drawn on step %s"):format(turn, want, tostring(seenAt)))
    check(seenAt ~= nil, ("turn %d: %s showed during the turn"):format(turn, want))
    check(not early, ("turn %d: %s not drawn before its move's line played"):format(turn, want))
  end

  if gen == 1 then
    local BattleState = require("src.battle.BattleState")
    local battle = BattleState.newWild(game, "SNORLAX", 20)
    battle.onFinish = function() end
    if type(battle.wideLayout) == "function" and battle:wideLayout() then
      local okW, WideBattle = pcall(require, "src.battle.WideBattle")
      screenW = okW and tonumber(WideBattle.WIDTH) or 304
      log("wide layout, " .. screenW .. " wide")
    end
    game.overworld:pushBattle(battle)
    local function toMenu()
      for _ = 1, 600 do
        if battle.phase == "menu" then return true end
        U.tap(game, "a"); U.wait(4)
      end
      return battle.phase == "menu"
    end
    check(toMenu(), "the battle reaches its menu")
    local lineSeen
    local function redAhead()
      local cur = battle.current
      if type(cur) == "table" and rising(cur.text) then lineSeen = true end
      if not lineSeen then return true end
      return false
    end
    for turn, slot in ipairs({ 1, 2 }) do
      lineSeen = false
      battle:resolveTurn(battle.player.curMoves[slot])
      watch(turn, turn == 1 and "ATK 2x" or "ATK 3x", redAhead, function()
        return battle.phase == "menu" and #battle.queue == 0 and battle.current == nil
      end)
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
    local function goldAhead()
      for _, e in ipairs(screen.queue or {}) do
        if type(e) == "table" and rising(e.text) then return true end
      end
      return false
    end
    for turn, slot in ipairs({ 1, 2 }) do
      -- (the screen's own submit: the turn worked out, then played with its lines)
      screen:submit({ kind = "move", move = b.player.moves[slot].id })
      watch(turn, turn == 1 and "ATK 2x" or "ATK 3x", goldAhead, function()
        return screen.phase ~= "resolving"
      end)
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
