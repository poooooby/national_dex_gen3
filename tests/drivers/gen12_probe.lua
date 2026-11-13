-- Driver: WoobleDex on Red/Blue/Yellow and Gold/Silver/Crystal in the real engine. A party of new
-- species (long names, #1000+), the party and summary screens, a wild battle against a new
-- species with a newer move used and a catch, the Pokedex list near #1000 and an entry, a stone
-- evolution and a level evolution, cries (the pak's own and a borrowed one), and a save and
-- reload. Shots and driver.log in SHOT_DIR. Run from the gen1recomp root, in an identity of its
-- own (options.lua there switches the other mods off; the player's saves are never touched):
--   SHOT_DIR=<dir> POKEPORT_VERSION=red POKEPORT_IDENTITY=ndx-gen12-probe \
--   POKEPORT_DRIVER=mods/national_dex_gen3/tests/drivers/gen12_probe.lua love .

local U = require("tests.drivers.util")

local function body(game, log, dir)
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
  local function section(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then fails = fails + 1; log("FAIL " .. name .. ": " .. tostring(err)) end
  end
  local Screens = require("src.ui.Screens")
  local version = require("src.core.GameVersion").get()
  local gen = (version == "gold" or version == "silver" or version == "crystal") and 2 or 1
  log("version " .. tostring(version) .. " (Gen " .. gen .. ")")
  for _ = 1, 600 do
    if game.save and game.stack and game.stack:top() then break end
    U.wait(1)
  end
  U.wait(60)
  local data = game.data
  check(data.pokemon.LUCARIO ~= nil and data.pokemon.GHOLDENGO ~= nil, "the new species are registered")
  local function shot(name) U.shot(game, dir .. "/" .. version .. "_" .. name .. ".png") end
  local function depth() return #(game.stack.states or {}) end
  local function popTo(n) while depth() > n do game.stack:pop() end end
  if gen == 1 then
    -- into the overworld (a new identity boots at the title)
    U.teleport(game, "ROUTE_1", 5, 5, "down")
    U.wait(60)
  end
  local base = depth()

  local Mon = gen == 1 and require("src.pokemon.Pokemon") or require("src.battle.gen2.Mon")
  local function make(id, lv) return Mon.new(data, id, lv) end
  local party = { make("LUCARIO", 30), make("CORVIKNIGHT", 40), make("EEVEE", 25),
    make(gen == 1 and "CHIKORITA" or "TURTWIG", gen == 1 and 15 or 17), make("GHOLDENGO", 50),
    make("VULPIX_ALOLA", 20) }
  game.save.party = party
  -- a newer move that runs natively on both games
  party[1].moves[1] = { id = "NIGHT_SLASH", pp = 15, maxPp = 15 }
  check(#party[1].moves > 0, "Lucario knows " .. #party[1].moves .. " moves")

  section("party screen", function()
    Screens.push(game, gen == 1 and "PartyMenu" or "Gen2PartyMenu", { onCancel = function() end })
    U.wait(40); shot("party"); popTo(base)
  end)
  section("summary", function()
    if gen == 1 then Screens.push(game, "SummaryMenu", party[5])
    else Screens.push(game, "Gen2SummaryMenu", { party = party, index = 5, onClose = function() end }) end
    U.wait(40); shot("summary_gholdengo")
    U.tap(game, "a"); U.wait(30); shot("summary_gholdengo_2")
    popTo(base)
  end)

  section("cries", function()
    local Sound = require("src.core.Sound")
    local cart = Sound.playCry(data, "BULBASAUR")
    log("the cart's own Bulbasaur cry: " .. tostring(cart))
    U.wait(60)
    local own = Sound.playCry(data, "LUCARIO")
    check(own ~= nil and own.isPlaying and own:isPlaying(), "Lucario's own cry plays (" .. tostring(own and own.getDuration and own:getDuration()) .. " s)")
    U.wait(90)
    local borrowed = Sound.playCry(data, gen == 1 and "CHIKORITA" or "TOGEKISS")
    check(borrowed ~= nil, "a borrowed cry plays")
    U.wait(60)
  end)

  section("battle", function()
    if gen == 1 then
      local BattleState = require("src.battle.BattleState")
      local battle = BattleState.newWild(game, "GARCHOMP", 30)
      battle.onFinish = function() end
      battle.rng = function(a) return a end
      game.overworld:pushBattle(battle)
      local function toMenu(tag)
        for i = 1, 300 do
          if battle.phase == "menu" then return true end
          if i == 40 and tag then shot(tag) end
          U.tap(game, "a"); U.wait(4)
        end
        return battle.phase == "menu"
      end
      check(toMenu("battle_intro"), "the battle reaches its menu")
      U.wait(20); shot("battle_menu")
      local hp = battle.enemy.mon.hp
      battle.phase = "messages"; battle.afterQueue = "menu"
      battle:performMove(battle.player, battle.enemy, party[1].moves[1], false)
      U.wait(30); shot("battle_move")
      toMenu()
      log("Lucario used " .. tostring(party[1].moves[1].id) .. ": Garchomp HP " .. hp .. " -> " .. battle.enemy.mon.hp)
      check(battle.enemy.mon.hp < hp, "Night Slash hurt Garchomp")
      battle.phase = "messages"; battle.afterQueue = "menu"
      battle:throwBall("MASTER_BALL")
      for i = 1, 120 do
        U.tap(game, "a"); U.wait(6)
        if i == 25 then shot("battle_catch") end
        if i == 45 then shot("battle_dex_page") end
      end
      local caught = false
      for _, m in ipairs(game.save.party) do if m.species == "GARCHOMP" then caught = true end end
      check(caught or (game.save.pokedex and game.save.pokedex.owned.GARCHOMP), "Garchomp caught")
    else
      local wild = make("GARCHOMP", 30)
      assert(game.world:startBattle({ wild = wild }), "startBattle failed")
      local screen
      for _ = 1, 900 do
        local top = game.stack:top()
        if top and top.battle then screen = top break end
        U.wait(1)
      end
      assert(screen, "no battle screen")
      for i = 1, 20 do U.tap(game, "a"); U.wait(8); if i == 4 then shot("battle_intro") end end
      shot("battle_menu")
      local b = screen.battle
      local move = party[1].moves[1].id
      local hp = b.enemy.hp
      b:useMove(b.player, b.enemy, move)
      log("Lucario used " .. tostring(move) .. ": Garchomp HP " .. hp .. " -> " .. tostring(b.enemy.hp))
      for _ = 1, 400 do
        if not (game.stack:top() or {}).battle then break end
        U.tap(game, "b"); U.wait(2)
      end
    end
    popTo(base)
  end)

  section("pokedex", function()
    local dex = game.save.pokedex
    local seen = dex.seen
    for id, def in pairs(data.pokemon) do
      if type(def) == "table" and def.dex and def.dex >= 990 and def.dex <= 1025 then seen[id] = true end
    end
    if gen == 1 then (dex.owned or {}).GHOLDENGO = true else (dex.caught or {}).GHOLDENGO = true end
    if gen == 1 then
      Screens.push(game, "PokedexMenu", { onCancel = function() end })
      U.wait(30)
      for _ = 1, 145 do U.tap(game, "right"); U.wait(1) end
      U.wait(20); shot("dex_list_end")
      Screens.push(game, "DexEntryMenu", "GHOLDENGO")
      -- the entry shows its numbers and text once the cry has finished (real time)
      for _ = 1, 3000 do
        local top = game.stack:top()
        if top and (top.picDelay or 0) == 0 and top.crying and not top:crying() then break end
        U.wait(1)
      end
      U.wait(10); shot("dex_entry_1000")
      U.tap(game, "a"); U.wait(30); shot("dex_entry_1000_p2")
    else
      Screens.push(game, "Gen2PokedexMenu", { entrySpecies = "GHOLDENGO", onClose = function() end })
      U.wait(150); shot("dex_entry_1000")
      U.tap(game, "a"); U.wait(30); shot("dex_entry_1000_p2")
      U.tap(game, "b"); U.wait(30); shot("dex_list")
    end
    popTo(base)
  end)

  section("evolutions", function()
    if gen == 1 then
      local Evolution = require("src.pokemon.Evolution")
      local ItemEffects = require("src.inventory.ItemEffects")
      local result, msgs, extra = ItemEffects.use(data, game.save, "ICE_STONE", party[3])
      check(result == "consumed" and extra and extra.evolveTo == "GLACEON", "Ice Stone on Eevee -> Glaceon ("
        .. tostring(result) .. " " .. tostring(msgs and msgs[1]) .. ")")
      local done = false
      Evolution.evolve(game, party[3], "GLACEON", function() done = true end, "ITEM")
      for i = 1, 900 do
        if done then break end
        if i == 120 then shot("evolution_stone") end
        U.tap(game, "a"); U.wait(2)
      end
      check(party[3].species == "GLACEON", "Eevee became Glaceon")
      party[4].level = 16
      local done2 = false
      local to = Evolution.request(game, party[4], { kind = "levelup" }, function() done2 = true end)
      check(to == "BAYLEEF", "Chikorita at 16 -> " .. tostring(to))
      for i = 1, 900 do
        if done2 then break end
        if i == 120 then shot("evolution_level") end
        U.tap(game, "a"); U.wait(2)
      end
      check(party[4].species == "BAYLEEF", "Chikorita became Bayleef")
    else
      local Evolution = require("src.core.gen2.Evolution")
      local GenItems = require("src.core.gen2.ItemEffects")
      party[3].species = "TOGETIC"
      local rec = GenItems.recordFor("SHINY_STONE", data)
      local out = rec and rec.use({ mon = party[3], item = "SHINY_STONE", data = data })
      check(out and out.used and out.evolution and out.evolution.into == "TOGEKISS", "Shiny Stone on Togetic -> Togekiss")
      local function play(index, entry, name)
        local done = false
        Screens.push(game, "Gen2EvolutionAnim", { mon = party[index], entry = entry, index = index,
          party = party, save = game.save, onDone = function() done = true; game.stack:pop() end })
        for i = 1, 1200 do
          if done then break end
          if i == 150 then shot(name) end
          U.tap(game, "a"); U.wait(2)
        end
      end
      if out and out.evolution then play(3, out.evolution, "evolution_stone") end
      check(party[3].species == "TOGEKISS", "Togetic became Togekiss")
      party[4].level = 18
      local entry = Evolution.checkMon(data, party[4], { timeOfDay = "DAY" })
      check(entry and entry.into == "GROTLE", "Turtwig at 18 -> " .. tostring(entry and entry.into))
      if entry then play(4, entry, "evolution_level") end
      check(party[4].species == "GROTLE", "Turtwig became Grotle")
    end
    popTo(base)
  end)

  section("save and reload", function()
    local first = game.save.party[1]
    if gen == 1 then
      local bag = first.extra and first.extra.national_dex_gen3
      first.extra = first.extra or {}
      first.extra.national_dex_gen3 = bag or { friendship = 123 }
      local SaveData = require("src.core.SaveData")
      SaveData.save(game.save)
      local back = SaveData.load(version)
      local m = back and back.party and back.party[1]
      check(m and m.species == "LUCARIO", "Lucario saved and loaded back")
      check(m and m.extra and m.extra.national_dex_gen3 and m.extra.national_dex_gen3.friendship ~= nil,
        "its hidden friendship survives the save")
    else
      local Save = require("src.core.gen2.Save")
      check(Save.save(game.save) ~= false, "saved")
      local back = Save.load(version)
      local species = {}
      for _, m in ipairs(back and back.party or {}) do species[#species + 1] = m.species end
      log("party after reload: " .. table.concat(species, ", "))
      check(species[1] == "LUCARIO" and species[3] == "TOGEKISS", "the new species saved and loaded back")
    end
  end)

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
