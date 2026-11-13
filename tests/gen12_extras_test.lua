-- Standalone: luajit mods/national_dex_gen3/tests/gen12_extras_test.lua [red|blue|yellow|gold|silver|crystal ...]
-- (from the gen1recomp root; runs on red, yellow, gold and crystal when none is named).
-- The Gen 3 extras on Gen 1 / Gen 2, through each game's own code:
--   Linking Cord: a trade evolution on the spot (Red's Bag item use; Gold's item record, as if
--     traded: a held trade item is used up by Gold's own Evolution.apply); sold with the rest
--   Register Owned: the Pokedex screen's constructor counts the party and every box (eggs not)
--   Modern Moves: the cart's own species learn their newer moves while the option is on, and get
--     their own lists back when it is off
--   Day & Night: installed on Red / Blue / Yellow (the shared renderer hub), never on Gold
--   New TMs: taught through the game's own TM code to the species data/tms.lua names, sold at the
--     TM counter, kept out of Red's .sav export and Gold's TM / HM numbers; Gold's TM pocket grows
--   Exp. Candies: the Rare Candy's flow (Red: leveledTo + every move of the levels gained; Gold:
--     the "candy" action over Mon.gainExperience), sold with the vitamins
--   Type Badges: which badges, where, and only while the game draws the box
--   Bigger PC: 40 boxes; the save writer writes a cart-shaped save (the extra boxes in the mod's
--     save data) and puts the live save back; save.loading and the option move them back
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")
local Runtime = require("src.mods.Runtime")
local modernRows = H.module("data/gen12/modern.lua")
local Badges = H.module("src/gen12/type_badges.lua")
local Glyphs = H.module("src/type_badges.lua")

-- the save writers, stubbed before the mod wraps them: what a write would put on disk
local written
local function snapshot(save)
  local n = 0
  for _ in pairs(save.boxes or {}) do n = n + 1 end
  local bucket = save.modData and save.modData.national_dex_gen3
  written = { boxes = n, currentBox = save.currentBox, pc = bucket and bucket.pc,
    names = save.boxNames and save.boxNames[20] }
  return true
end
require("src.core.SaveData").save = snapshot
require("src.core.gen2.Save").save = snapshot

-- whether a vending machine (src/gen12/vending.lua) has an item in its stock
local function machineSells(run, data, which, id)
  local V = run.loader.exports.national_dex_gen3._vending
  if not V then return false end
  for _, e in ipairs(V.machines) do
    if e.m.id == which then
      for _, tab in ipairs(V.stock(e.m, data)) do
        for _, entry in ipairs(tab.entries) do if entry.id == id then return true end end
      end
    end
  end
  return false
end

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
    T.check(machineSells(run, data, "evo", "LINKING_CORD"), version .. ": sold by the EVO EXPRESS machine")
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
    T.check(machineSells(run, data, "evo", "LINKING_CORD"), version .. ": sold by the EVO EXPRESS machine")
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
  -- ------- New TMs
  local tm = data.items.TM74
  T.check(tm ~= nil, version .. ": TM74 is an item")
  local zen = gen == 1 and tm and tm.machine and tm.machine.move or (tm and tm.teaches)
  T.eq(zen and data.moves[zen] and data.moves[zen].name, "ZEN HEADBUTT", version .. ": TM74 teaches Zen Headbutt")
  local function knows(id, move)
    for _, m in ipairs(data.pokemon[id].tmhm or {}) do if m == move then return true end end
    return false
  end
  T.check(knows("ALAKAZAM", zen) and knows("LUCARIO", zen) and not knows("MAGIKARP", zen),
    version .. ": Alakazam and Lucario can learn it, Magikarp not")
  if gen == 1 then
    T.eq(tm.machine.number, 74, version .. ": machine number 74")
    local ItemEffects = require("src.inventory.ItemEffects")
    local save = require("src.core.SaveData").newGame()
    local r, move = ItemEffects.use(data, save, "TM74", make("ALAKAZAM", 40))
    T.eq(r, "learn", version .. ": the game's own TM code teaches it")
    T.eq(move, zen, version .. ": the move")
    T.check(ItemEffects.use(data, save, "TM74", make("MAGIKARP", 40)) ~= "learn", version .. ": not to Magikarp")
    T.check(machineSells(run, data, "tm", "TM74"), version .. ": sold by the TM EXPRESS machine")
    local cw = require("src.save_convert.GenSave").crosswalks(data)
    T.check(cw.itemsIndex.TM74 == nil and cw.itemsIndex.TM_SUBSTITUTE == 250,
      version .. ": left out of .sav export (the cart's TMs kept)")
  else
    T.check(tm.pocket == "TM_HM" and tm.tmNumber > 50 and tm.tmNumber < 51,
      version .. ": in the TM pocket, sorted between TM50 and HM01")
    local Bag = require("src.inventory.Bag")
    T.eq(Bag.capacity(data, "TM_HM"), 57 + 114, version .. ": the TM pocket holds the 114 new TMs too")
    T.eq(Bag.capacity(data, "ITEM"), 20, version .. ": the item pocket as it was")
    T.check(machineSells(run, data, "tm", "TM74"), version .. ": sold by the TM EXPRESS machine")
  end

  -- ------- Exp. Candies
  T.check(data.items.EXP_CANDY_XL ~= nil, version .. ": the candies are items")
  if gen == 1 then
    local Exp = require("src.battle.Experience")
    local ItemEffects = require("src.inventory.ItemEffects")
    local save = require("src.core.SaveData").newGame()
    local pidgey = make("PIDGEY", 5)
    local def = data.pokemon.PIDGEY
    local r, _, extra = ItemEffects.use(data, save, "EXP_CANDY_L", pidgey)
    T.eq(r, "consumed", version .. ": a candy is used")
    T.check(extra and extra.leveledTo and extra.leveledTo > 15 and pidgey.level == extra.leveledTo,
      version .. ": 10,000 Exp. takes Pidgey from Lv 5 to " .. tostring(extra and extra.leveledTo))
    local Stats = require("src.pokemon.Stats")
    T.eq(pidgey.stats.attack, Stats.calc(def, pidgey.level, pidgey.dvs, pidgey.statExp).attack,
      version .. ": its stats follow")
    local want, exact = 0, 0
    for _, row in ipairs(def.learnset) do
      if row.level > 5 and row.level <= pidgey.level then want = want + 1 end
      if row.level == pidgey.level then exact = exact + 1 end
    end
    T.eq(#Exp.movesLearnedAt(def, pidgey.level), want,
      version .. ": the moves of every level gained are offered (" .. want .. ")")
    T.eq(#Exp.movesLearnedAt(def, pidgey.level), exact, version .. ": once: then only that level's again")
    local old = make("PIDGEY", 50)
    local exp = old.exp
    r, _, extra = ItemEffects.use(data, save, "EXP_CANDY_XS", old)
    T.check(r == "consumed" and not (extra and extra.leveledTo) and old.exp == exp + 100,
      version .. ": a candy short of a level still gives its Exp.")
    T.eq(ItemEffects.use(data, save, "EXP_CANDY_XS", make("PIDGEY", 100)), "failed", version .. ": nothing at Lv 100")
    T.check(ItemEffects.keepsPartyMenuOpen("EXP_CANDY_S") and ItemEffects.notTimeInBattle("EXP_CANDY_S"),
      version .. ": the Rare Candy's menu rules")
    local clerk = data.text_pointers.CeladonMart5F.TEXT_CELADONMART5F_CLERK2.mart
    local sold = false
    for _, id in ipairs(clerk) do if id == "EXP_CANDY_XS" then sold = true end end
    T.check(sold, version .. ": sold with the vitamins (Celadon 5F)")
  else
    local Items = require("src.core.gen2.ItemEffects")
    local rec = Items.recordFor("EXP_CANDY_L", data)
    T.eq(rec and rec.action, "candy", version .. ": the Rare Candy's action")
    local pidgey = make("PIDGEY", 5)
    local out = rec.use({ mon = pidgey, item = "EXP_CANDY_L", data = data })
    T.check(out.used and out.level == pidgey.level and pidgey.level > 15,
      version .. ": Pidgey Lv 5 -> " .. tostring(pidgey.level))
    T.check(#(out.learned or {}) >= 2, version .. ": the moves of every level gained (" .. #(out.learned or {}) .. ")")
    T.check(not rec.use({ mon = make("PIDGEY", 100), item = "EXP_CANDY_L", data = data }).used,
      version .. ": nothing at Lv 100")
    T.check(not rec.use({ mon = make("PIDGEY", 5), item = "EXP_CANDY_L", data = data, battle = {} }).used,
      version .. ": not in battle")
    local sold = false
    for _, list in ipairs(data.gen2Marts.lists) do
      local c, v = false, false
      for _, id in ipairs(list) do
        if id == "EXP_CANDY_XS" then c = true end
        if id == "PROTEIN" then v = true end
      end
      if c and v then sold = true end
    end
    T.check(sold, version .. ": sold with the vitamins (Goldenrod 4F)")
  end
  T.eq(run.loader.exports.national_dex_gen3.expCandies.EXP_CANDY_XL, 954, version .. ": exports.expCandies")

  -- ------- Type Badges
  local function same(a, b) return table.concat(a, ",") == table.concat(b, ",") end
  T.check(same(Badges.ids({ "PSYCHIC_TYPE" }), { 14 }) and same(Badges.ids({ "FIRE", "FIRE" }), { 10 })
    and same(Badges.ids({ "CURSE_TYPE", "NORMAL" }), { 0 }) and same(Badges.ids({ "BIRD" }), { 2 }),
    version .. ": badge ids (each once, ??? only alone)")
  local drawn = {}
  local function stub(state)
    state.drawBadge = function(t, x, y) drawn[#drawn + 1] = t .. "@" .. x .. "," .. y end
  end
  local yes, no = function() return true end, function() return false end
  if gen == 1 then
    T.check(Runtime.wantsHook("battle.overlay"), version .. ": the badges are on the battle overlay")
    local state = Badges.install({ require = require, generation = 1, glyphs = Glyphs })
    stub(state)
    T.check(state.classicWithBoxes and require("src.battle.BattleState").__ndxBadges ~= nil,
      version .. ": the classic layout's badges go with the boxes")
    local b = { drawHUDs = yes, statusHUDVisible = yes, growInScale = no, wideLayout = no,
      colorMode = no, enemy = { curTypes = { "FIRE", "FLYING" } }, player = { curTypes = { "PSYCHIC_TYPE" } } }
    state.overlay(b)
    T.eq(#drawn, 0, version .. ": the classic layout's are not drawn from the overlay")
    state.hud(b, 0)
    T.eq(table.concat(drawn, " "), "10@89,2 2@89,13 14@69,57",
      version .. ": a foe's right of its name and HP bar, yours left of yours, a second type under the first (flat path: with the boxes)")
    drawn = {}
    b.colorMode = yes
    state.zone(b, 0, 0)
    T.eq(#drawn, 0, version .. ": coloured path: no zone pass draws them before the boxes were drawn")
    state.hud(b, 0)
    T.eq(#drawn, 0, version .. ": coloured path: not into the gray canvas the boxes go to")
    state.zone(b, 0, 0)
    T.eq(table.concat(drawn, " "), "10@89,2 2@89,13 14@69,57",
      version .. ": coloured path: drawn after the zone pass that puts the boxes on screen")
    drawn = {}
    state.zone(b, 0, 0)
    T.eq(#drawn, 0, version .. ": once per drawing of the boxes")
    state.hud(b, 4)
    state.zone(b, 0, 0)
    T.eq(#drawn, 0, version .. ": none while the intro slides in")
    b.wideLayout = yes
    state.overlay(b)
    T.eq(table.concat(drawn, " "), "10@130,2 2@130,13 14@173,58", version .. ": the wide layout's from the overlay")
    drawn = {}
    b.enemy.fainted, b.showPlayerBack = true, true
    state.overlay(b)
    b.wideLayout = no
    state.hud(b, 0); state.zone(b, 0, 0)
    T.eq(#drawn, 0, version .. ": none while the boxes are not drawn")
  else
    local hub = require("src.ui.gen2.BattleState").__ndxBadges
    T.check(hub and hub.after, version .. ": the HP boxes are wrapped")
    stub(hub.state)
    local foe, mine = { types = { "STEEL", "FAIRY" } }, { types = { "DARK" } }
    local self = { data = data, showEnemyHud = true, showPlayerHud = true, statusHUDVisible = yes,
      hudCleared = no, activeMon = function(_, side) return side == "enemy" and foe or mine end,
      battle = { battlerTypes = function(_, m) return m.types end } }
    hub.after(self, "enemy")
    hub.after(self, "player")
    T.eq(table.concat(drawn, " "), "8@89,2 18@89,13 17@69,57", version .. ": the foe's and yours")
    drawn = {}
    self.showEnemyHud = false
    hub.after(self, "enemy")
    T.eq(#drawn, 0, version .. ": none while the box is hidden")
    local other = setmetatable({ data = {}, showEnemyHud = true }, { __index = self })
    hub.after(other, "enemy")
    T.eq(#drawn, 0, version .. ": none in another game's battle")
    setOption(run, "type_badges", false)
    self.showEnemyHud = true
    hub.after(self, "enemy")
    T.eq(#drawn, 0, version .. ": none with the option off")
    setOption(run, "type_badges", true)
  end

  -- ------- Bigger PC
  local Boxes = require(gen == 1 and "src.pokemon.Boxes" or "src.core.gen2.Boxes")
  local field, base = gen == 1 and "COUNT" or "NUM_BOXES", gen == 1 and 12 or 14
  T.eq(Boxes[field], 40, version .. ": 40 boxes")
  local pcSave = { version = version, boxes = {}, currentBox = 1, boxNames = {} }
  if gen == 1 then Boxes.ensure(pcSave) end
  local box20 = gen == 1 and pcSave.boxes[20] or Boxes.box(pcSave, 20)
  T.check(type(box20) == "table", version .. ": box 20 is there")
  box20[1] = make("ZORUA", 12)
  pcSave.currentBox = 20
  if gen == 2 then pcSave.boxNames[20] = "FAVES" end
  local writer = require(gen == 1 and "src.core.SaveData" or "src.core.gen2.Save")
  writer.save(pcSave)
  T.check(written and written.boxes <= base and written.currentBox == 1,
    version .. ": the file holds the cart's boxes only (current box 1)")
  local pc = written and written.pc
  T.check(pc and pc.boxes[20] and pc.boxes[20][1] and pc.boxes[20][1].species == "ZORUA" and pc.currentBox == 20,
    version .. ": box 20 and the current box in the mod's save data")
  if gen == 2 then
    T.check(written.names == nil and pc and pc.names[20] == "FAVES", version .. ": box 20's name too")
  end
  T.eq(pcSave.currentBox, 20, version .. ": the live save as it was")
  T.check(pcSave.boxes[20] == box20 and (pcSave.modData == nil or pcSave.modData.national_dex_gen3 == nil),
    version .. ": its box 20, no save data left behind")
  local raw = { version = version, boxes = {}, currentBox = 1, boxNames = {},
    modData = { national_dex_gen3 = { pc = pc } } }
  if gen == 1 then for i = 1, 12 do raw.boxes[i] = {} end end
  Runtime.emit("save.loading", { raw = raw })
  T.check(raw.boxes[20] and raw.boxes[20][1] and raw.currentBox == 20 and raw.modData.national_dex_gen3.pc == nil,
    version .. ": loading puts box 20 back")
  if gen == 1 then T.eq(#raw.boxes, 40, version .. ": every box, 1-40") end
  if gen == 2 then T.eq(raw.boxNames[20], "FAVES", version .. ": with its name") end
  game.save = pcSave
  setOption(run, "big_pc", false)
  T.eq(Boxes[field], base, version .. ": off: the cart's count")
  T.check(pcSave.boxes[20] == nil and pcSave.modData.national_dex_gen3.pc.boxes[20] == box20,
    version .. ": box 20 kept in the save data")
  setOption(run, "big_pc", true)
  T.check(Boxes[field] == 40 and pcSave.boxes[20] == box20 and pcSave.currentBox == 20,
    version .. ": on: box 20 back")

  run.release()
end

T.finish("national_dex_gen3 Gen 1/2 extras")
