-- Driver: the Dynamax marks on the summary (src/dynamax_summary.lua) and the Dynamax items
-- (src/dynamax.lua) in the engine. A party of Charizard (G-Max Factor, Dynamax Level 7), Butterfree
-- (level 0, no factor), Melmetal (the factor from a raid, level 3), Zacian (cannot Dynamax),
-- Urshifu; the summary's info page and the next page shot for the first three (d*.png); then the
-- items through their effects: Dynamax Candy to 10 and refused past it and on Zacian, Max
-- Mushrooms short of three, three giving and taking the factor, Melmetal refused, Urshifu without
-- and with Max Honey; the marks after a save round trip and a PC deposit and withdraw.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/national_dex_gen3/tests/drivers/dynamax_summary_probe.lua love .

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
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(90)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local s0 = Runtime.getSession()
  local nd = game.mods.exports.national_dex_gen3
  local Dx = nd and nd.dynamax
  if not Dx then log("FAIL national_dex_gen3 has no dynamax export"); return end
  local function slot(dex)
    return (nd.slotOf and nd.slotOf(dex)) or Pokemon.speciesFromNational(dex)
  end
  s0.party = {}
  for _, dex in ipairs({ 6, 12, 809, 888, 892 }) do Party.giveMon(s0, slot(dex), 50) end
  local char, bfree, melm, zac, ursh = s0.party[1], s0.party[2], s0.party[3], s0.party[4], s0.party[5]
  Dx.setFactor(char, true); Dx.setLevel(char, 7)
  Dx.setLevel(melm, 3); Dx.setFactor(melm, true)
  -- (poisoned: the strip under the level holds the status, so the gauge moves)
  melm.status = "PSN"
  log(("canDynamax: Charizard %s Zacian %s; G-Max: Charizard %s Butterfree %s Melmetal %s Urshifu %s"):format(
    tostring(Dx.canDynamax(char)), tostring(Dx.canDynamax(zac)), tostring(Dx.gmaxMoveOf(char)),
    tostring(Dx.gmaxMoveOf(bfree)), tostring(Dx.gmaxMoveOf(melm)), tostring(Dx.gmaxMoveOf(ursh))))
  check(Dx.canDynamax(char) and not Dx.canDynamax(zac), "Zacian cannot Dynamax, Charizard can")
  check(Dx.gmaxMoveOf(char) == "WILDFIRE" and Dx.gmaxMoveOf(ursh) == "ONE_BLOW", "G-Max Moves by species")

  -- the summary
  local SummaryMenu = require("src.ui.game3.summary_menu")
  for i = 1, 3 do
    SummaryMenu.openMenu(s0.party, i, { playerState = s0, session = s0 })
    U.wait(40)
    shot(("d%d_info"):format(i))
    U.tap(game, "right")
    U.wait(40)
    shot(("d%d_page2"):format(i))
    U.tap(game, "b")
    U.wait(40)
    pcall(SummaryMenu.close)
    U.wait(10)
  end

  -- the items, through the engine's own mod-effect path
  local ItemUse = require("src.core.game3.item_use")
  local Bag = require("src.core.game3.bag")
  local ids = Dx.ids
  local function use(id, slotIdx)
    local ok, kind, text = pcall(ItemUse.useField, s0, s0.bag, id, slotIdx)
    local words = type(text) == "table" and table.concat(text, " / ") or tostring(text)
    log(("  use %d on %d -> %s %s %s"):format(id, slotIdx, tostring(ok), tostring(kind), words:gsub("\n", " ")))
    return kind
  end
  Bag.add(s0.bag, ids.DYNAMAX_CANDY, 10)
  for _ = 1, 3 do use(ids.DYNAMAX_CANDY, 1) end
  check(Dx.level(char) == 10, "Dynamax Candy to 10 (" .. Dx.level(char) .. ")")
  local before = Bag.get(s0.bag, ids.DYNAMAX_CANDY)
  use(ids.DYNAMAX_CANDY, 1)
  check(Dx.level(char) == 10 and Bag.get(s0.bag, ids.DYNAMAX_CANDY) == before, "past 10: no effect, kept")
  use(ids.DYNAMAX_CANDY, 4)
  check(Dx.level(zac) == 0 and Bag.get(s0.bag, ids.DYNAMAX_CANDY) == before, "Zacian: no effect, kept")
  Bag.add(s0.bag, ids.MAX_MUSHROOMS, 2)
  use(ids.MAX_MUSHROOMS, 2)
  check(Bag.get(s0.bag, ids.MAX_MUSHROOMS) == 2, "two Max Mushrooms: not enough, kept")
  Bag.add(s0.bag, ids.MAX_MUSHROOMS, 7)
  use(ids.MAX_MUSHROOMS, 2)
  check(Dx.hasFactor(bfree) and Bag.get(s0.bag, ids.MAX_MUSHROOMS) == 6, "three: Butterfree gets the factor, three used")
  use(ids.MAX_MUSHROOMS, 2)
  check(not Dx.hasFactor(bfree) and Bag.get(s0.bag, ids.MAX_MUSHROOMS) == 3, "three more: the factor taken away")
  use(ids.MAX_MUSHROOMS, 3)
  check(Bag.get(s0.bag, ids.MAX_MUSHROOMS) == 3, "Melmetal: no Max Soup")
  use(ids.MAX_MUSHROOMS, 5)
  check(not Dx.hasFactor(ursh) and Bag.get(s0.bag, ids.MAX_MUSHROOMS) == 3, "Urshifu without Max Honey: refused")
  Bag.add(s0.bag, ids.MAX_HONEY, 1)
  use(ids.MAX_MUSHROOMS, 5)
  check(Dx.hasFactor(ursh) and Bag.get(s0.bag, ids.MAX_MUSHROOMS) == 0 and Bag.get(s0.bag, ids.MAX_HONEY) == 0,
    "Urshifu with Max Honey: the factor, all used")

  -- kept through a save round trip and the PC
  local SaveSerializer = require("src.core.SaveSerializer")
  local okE, enc = pcall(SaveSerializer.encode, { party = s0.party })
  local okD, dec = pcall(function() return SaveSerializer.decode(enc) end)
  local back = okD and type(dec) == "table" and dec.party and dec.party[1]
  check(back and Dx.level(back) == 10 and Dx.hasFactor(back), "the marks survive the save encoding")
  local Storage = require("src.core.game3.storage")
  local okDep, dep, boxId, slotIdx = pcall(Storage.deposit, s0, 1)
  log("deposit", tostring(okDep), tostring(dep), tostring(boxId), tostring(slotIdx), "party now", #s0.party)
  local inBox = boxId and Storage.ensure(s0).boxes[boxId].mons[slotIdx]
  check(inBox and Dx.level(inBox) == 10 and Dx.hasFactor(inBox), "the marks kept in the PC")
  -- the PC, its hovered Pokemon (box 1 slot 1, where the cursor starts): the G-MAX mark
  local Box = require("src.ui.game3.box_storage_ui")
  Box.show({ session = s0 })
  U.wait(90)
  shot("d9_pc")
  pcall(Box.close)
  U.wait(30)
  local okW, wd, at = pcall(Storage.withdraw, s0, boxId, slotIdx)
  local again = okW and wd and s0.party[at]
  check(again and Dx.level(again) == 10 and Dx.hasFactor(again), "and withdrawn again")
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
