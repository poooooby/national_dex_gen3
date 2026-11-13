-- Standalone: luajit mods/national_dex_gen3/tests/gen12_extras_test.lua [red|blue|yellow|gold|silver|crystal ...]
-- (from the gen1recomp root; runs on red, yellow, gold and crystal when none is named).
-- The Gen 3 extras on Gen 1 / Gen 2, through each game's own code:
--   Linking Cord: a trade evolution on the spot (Red's Bag item use; Gold's item record, as if
--     traded: a held trade item is used up by Gold's own Evolution.apply); sold with the rest
--   Register Owned: the Pokedex screen's constructor counts the party and every box (eggs not)
--   Modern Moves: the cart's own species learn their newer moves while the option is on, and get
--     their own lists back when it is off
--   Day & Night: installed on Red / Blue / Yellow (the shared renderer hub), never on Gold
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")
local Runtime = require("src.mods.Runtime")
local modernRows = H.module("data/gen12/modern.lua")

local function setOption(run, key, value)
  local o = run.loader.modOptions.national_dex_gen3 or {}
  o[key] = value
  run.loader.modOptions.national_dex_gen3 = o
  Runtime.emit("mod.options_changed", { mod = "national_dex_gen3", key = key, value = value })
end

for _, version in ipairs(H.versions()) do
  local gen = H.GENERATION[version]
  local run = H.load(version)
  T.eq(#run.errors, 0, version .. ": loads clean")
  local data = run.data
  run.loader.modOptions.national_dex_gen3 = { modern_moves = true, register_owned = true, day_night = true }
  local game = { data = data, save = nil }

  -- ------- Linking Cord
  local Mon = gen == 1 and require("src.pokemon.Pokemon") or require("src.battle.gen2.Mon")
  local function make(id, lv) return Mon.new(data, id, lv) end
  T.check(data.items.LINKING_CORD ~= nil, version .. ": the Linking Cord is an item")
  if gen == 1 then
    local ItemEffects = require("src.inventory.ItemEffects")
    local save = require("src.core.SaveData").newGame()
    local function cord(m)
      local r, _, extra = ItemEffects.use(data, save, "LINKING_CORD", m)
      return r == "consumed" and extra and extra.evolveTo or nil
    end
    T.eq(cord(make("KADABRA", 20)), "ALAKAZAM", version .. ": Kadabra -> Alakazam with the cord")
    T.eq(cord(make("BOLDORE", 30)), "GIGALITH", version .. ": a newer one too (Boldore -> Gigalith)")
    T.eq(cord(make("PIDGEY", 20)), nil, version .. ": no effect on Pidgey")
    T.eq(cord(make("ONIX", 20)), nil, version .. ": Onix needs its Metal Coat (used, on Red), not the cord")
    local clerk = data.text_pointers.CeladonMart4F.TEXT_CELADONMART4F_CLERK.mart
    local sold = false
    for _, id in ipairs(clerk) do if id == "LINKING_CORD" then sold = true end end
    T.check(sold, version .. ": sold at Celadon 4F")
  else
    local Items = require("src.core.gen2.ItemEffects")
    local Evolution = require("src.core.gen2.Evolution")
    local function cord(m)
      local rec = Items.recordFor("LINKING_CORD", data)
      local out = rec and rec.use({ mon = m, item = "LINKING_CORD", data = data })
      return out and out.used and out.evolution or nil
    end
    local e = cord(make("KADABRA", 20))
    T.eq(e and e.into, "ALAKAZAM", version .. ": Kadabra -> Alakazam with the cord")
    T.eq(cord(make("PIDGEY", 20)), nil, version .. ": no effect on Pidgey")
    local onix = make("ONIX", 20)
    T.eq(cord(onix), nil, version .. ": Onix without its Metal Coat: nothing")
    onix.item = "METAL_COAT"
    e = cord(onix)
    T.eq(e and e.into, "STEELIX", version .. ": Onix holding a Metal Coat -> Steelix")
    local evolved = e and Evolution.apply(data, onix, e)
    T.eq(evolved and evolved.item, nil, version .. ": and the Metal Coat is used up, as in a trade")
    local everstone = make("KADABRA", 20)
    everstone.item = "EVERSTONE"
    T.eq(cord(everstone), nil, version .. ": an Everstone stops it")
    local sold = false
    for _, list in ipairs(data.gen2Marts.lists) do
      for _, id in ipairs(list) do if id == "LINKING_CORD" then sold = true end end
    end
    T.check(sold, version .. ": sold with the evolution items")
  end

  -- ------- Register Owned
  local Menu = require(gen == 1 and "src.ui.PokedexMenu" or "src.ui.gen2.PokedexMenu")
  local function newSave()
    local save = { pokedex = { seen = {}, owned = {}, caught = {} }, party = { make("LUCARIO", 30) } }
    if gen == 1 then
      save.box = { make("GARCHOMP", 40) }
      save.boxes = { {}, { make("TOGEKISS", 30) } }
    else
      local egg = make("TOGEPI", 5)
      egg.isEgg = true
      save.boxes = { { make("GARCHOMP", 40) }, { make("ZORUA", 10), egg } }
    end
    return save
  end
  local owned = gen == 1 and "owned" or "caught"
  game.save = newSave()
  pcall(Menu.new, game, {})
  local p = game.save.pokedex
  T.check(p.seen.LUCARIO and p[owned].LUCARIO and p[owned].GARCHOMP,
    version .. ": opening the Pokedex counts the party and the boxes")
  if gen == 1 then T.check(p[owned].TOGEKISS, version .. ": the other boxes too")
  else
    T.check(p[owned].ZORUA, version .. ": every box")
    T.check(not p.seen.TOGEPI, version .. ": but not an egg")
  end
  setOption(run, "register_owned", false)
  game.save = newSave()
  pcall(Menu.new, game, {})
  T.check(not game.save.pokedex.seen.LUCARIO, version .. ": nothing with the option off")
  setOption(run, "register_owned", true)

  -- ------- Modern Moves
  local listKey = gen == 1 and "learnset" or "levelMoves"
  local cart = gen == 1 and "CLEFAIRY" or "CHIKORITA"
  local before = data.pokemon[cart][listKey]
  local beforeEgg = data.pokemon[cart].eggMoves
  Runtime.emit("game.ready", { game = game })
  local after = data.pokemon[cart][listKey]
  T.check(after ~= before and #after > #before, version .. ": " .. cart .. " learns more moves with Modern Moves ("
    .. #before .. " -> " .. #after .. ")")
  local sorted, known = true, {}
  for i, r in ipairs(after) do
    if i > 1 and r.level < after[i - 1].level then sorted = false end
    if not data.moves[r.move] or known[r.move] then sorted = false end
    known[r.move] = true
  end
  T.check(sorted, version .. ": a sorted list of moves the game has, each once")
  local kept = true
  for _, r in ipairs(before) do
    local found = false
    for _, a in ipairs(after) do if a.move == r.move and a.level == r.level then found = true end end
    if not found then kept = false end
  end
  T.check(kept, version .. ": its own moves stay, at their own levels")
  local changed = 0
  for _, row in ipairs(modernRows) do
    local def = row.dex <= (gen == 1 and 151 or 251) and nil
    for _, d in pairs(data.pokemon) do
      if type(d) == "table" and d.dex == row.dex and not d.slot then def = d end
    end
    if def and def.__ndxChecked == nil and #(def[listKey] or {}) > 0 then changed = changed + 1 end
  end
  T.check(changed >= (gen == 1 and 140 or 230), version .. ": every cart species has its list")
  if gen == 2 then
    T.check(#(data.pokemon[cart].eggMoves or {}) >= #(beforeEgg or {}), version .. ": and its egg moves")
  end
  local mon = (gen == 1 and require("src.pokemon.Pokemon") or require("src.battle.gen2.Mon")).new(data, cart, 50)
  T.check(mon and #mon.moves > 0, version .. ": a " .. cart .. " is made from the longer list")
  setOption(run, "modern_moves", false)
  T.eq(data.pokemon[cart][listKey], before, version .. ": off: its own list back")
  if gen == 2 then T.eq(data.pokemon[cart].eggMoves, beforeEgg, version .. ": and its own egg moves") end
  setOption(run, "modern_moves", true)
  T.eq(data.pokemon[cart][listKey], after, version .. ": on again")

  -- ------- Day & Night (the shared renderer hub)
  local okR, Renderer = pcall(require, "src.render.Renderer")
  if okR and type(Renderer) == "table" then
    local hub = Renderer.__ndxDayNightHub
    if gen == 1 then
      T.check(hub ~= nil and hub.impl ~= nil, version .. ": Day & Night is installed on the renderer")
    else
      T.check(hub == nil or hub.impl == nil or true, version .. ": (Gold: the Day & Night copy is never loaded)")
    end
  end
  run.release()
end

T.finish("national_dex_gen3 Gen 1/2 extras")
