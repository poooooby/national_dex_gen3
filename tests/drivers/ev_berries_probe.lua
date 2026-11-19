-- Driver: the EV-lowering berries (src/ev_berries.lua) through the game's own screens. A new game,
-- a Pikachu with 200 HP / 200 Speed EVs and friendship 70. FireRed / LeafGreen: the Berry Pouch,
-- Pomeg, USE, the Pikachu; every game: the party menu's use-item screen (what the Bag opens after
-- USE) with a Tamato Berry. Each must lower the EV by 10, raise friendship and use one berry up.
-- Shots and driver.log in SHOT_DIR. From the gen1recomp root:
--   SHOT_DIR=<dir> POKEPORT_GAME=firered POKEPORT_VERSION=firered \
--   POKEPORT_DRIVER=mods/national_dex_gen3/tests/drivers/ev_berries_probe.lua love .

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
  game:_handleBootAction({ action = "new_game", name = "BERRY", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local Pokemon = require("src.core.game3.pokemon")
  local ItemsData = require("src.core.game3.items_data")
  local GAME = require("src.core.GameVersion").get()
  local C = require("src.core.game3.constants").of(GAME)
  local session = Runtime.getSession()
  check(session ~= nil, "field session exists")
  if not session then return end
  log("game: " .. tostring(GAME) .. ", Pomeg's use: " .. tostring(ItemsData.fieldUseKind(153)))

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_PIKACHU, 30, "PIKACHU")
  local m = session.party[1]
  local evs = Pokemon.evsOf(m)
  evs.hp, evs.spe = 200, 200
  m.friendship = 70
  local bag = session.bag
  local PartyMenu = require("src.ui.game3.party_menu")

  -- after choosing the Pokemon: each page of the use's message (logged and shot), dismissed with A;
  -- then B out of the party menu (it stays open for another use)
  local function readMessage(shot)
    local pages = {}
    waitFor(function() return PartyMenu.mode == "message" end, 120)
    -- (a party menu drawn by another mod shows the words its own way: shots as it types)
    for i, wait in ipairs({ 60, 240 }) do
      U.wait(wait)
      U.still(game, dir .. "/" .. shot .. "_typing" .. i .. ".png")
    end
    for i = 1, 6 do
      if PartyMenu.mode ~= "message" then break end
      U.wait(120)
      pages[#pages + 1] = tostring(PartyMenu._messageText)
      U.still(game, dir .. "/" .. shot .. "_" .. i .. ".png")
      U.tap(game, "a"); U.wait(30)
    end
    for _ = 1, 6 do
      if not PartyMenu.open then break end
      U.tap(game, "b"); U.wait(30)
    end
    local text = (table.concat(pages, " / "):gsub("%c", " "))
    log("message: " .. text)
    return text
  end

  -- the Berry Pouch (FireRed / LeafGreen): Pomeg -> USE -> Pikachu
  if GAME == "firered" or GAME == "leafgreen" then
    Bag.add(bag, 153, 3)
    local BerryPouch = require("src.ui.game3.berry_pouch")
    BerryPouch.show(session, bag)
    U.wait(30)
    U.still(game, dir .. "/ev_pouch_list.png")
    U.tap(game, "a"); U.wait(20)            -- Pomeg: the action menu
    U.still(game, dir .. "/ev_pouch_actions.png")
    U.tap(game, "a"); U.wait(40)            -- USE: the party menu
    check(PartyMenu.open == true, "USE opens the party menu")
    U.still(game, dir .. "/ev_pouch_party.png")
    U.tap(game, "a")                         -- the Pikachu
    local text = readMessage("ev_pouch_message")
    check(evs.hp == 190, "Pomeg from the Berry Pouch: HP EVs 200 -> 190 (" .. tostring(Pokemon.evsOf(m).hp) .. ")")
    check(Pokemon.friendshipOf(m) > 70, "friendship rises (70 -> " .. tostring(Pokemon.friendshipOf(m)) .. ")")
    check(Bag.get(bag, 153) == 2, "one Pomeg used (" .. tostring(Bag.get(bag, 153)) .. " left)")
    for _ = 1, 10 do
      if not BerryPouch.open then break end
      U.tap(game, "b"); U.wait(20)
    end
    pcall(function() BerryPouch.open = false end)
  end

  -- the party menu's use-item screen, as the Bag opens it after USE: a Tamato Berry
  Bag.add(bag, 158, 2)
  local f0 = Pokemon.friendshipOf(m)
  PartyMenu.show(session.party, session.moveOverlay, { session = session, bag = bag, item = 158, mode = "use",
    onClose = function() end })
  U.wait(30)
  U.still(game, dir .. "/ev_party_use.png")
  U.tap(game, "a")
  local text2 = readMessage("ev_party_message")
  check(Pokemon.evsOf(m).spe == 190, "Tamato: Speed EVs 200 -> 190 (" .. tostring(Pokemon.evsOf(m).spe) .. ")")
  check(Pokemon.friendshipOf(m) > f0, ("friendship rises (%d -> %d)"):format(f0, Pokemon.friendshipOf(m)))
  check(Bag.get(bag, 158) == 1, "one Tamato used (" .. tostring(Bag.get(bag, 158)) .. " left)")
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
