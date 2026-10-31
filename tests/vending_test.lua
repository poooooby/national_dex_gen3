-- Standalone: luajit mods/national_dex_gen3/tests/vending_test.lua [game] (from the gen1recomp root;
-- needs that cart imported, Emerald by default).
--
-- The vending machines (data/vending.lua, src/vending.lua, src/vending_screen.lua): every machine's
-- map is in the cart; its stock resolves against the running game's items (names, prices, the TMs'
-- moves); the evolution items and TMs moved out of that game's Marts; and the screen works by
-- buttons alone and by taps alone (a purchase each way: the Bag gains the items, the money comes
-- off; too little money and a refused amount say so and buy nothing).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "emerald"
local root = H.modRoot()

require("src.core.GameVersion").set(GAME)
do
  local CacheBlob = require("src.import.CacheBlob")
  require("src.core.game3.dataset").cache = function()
    return {
      read = function(_, rel)
        local f = io.open(GAME .. "/" .. rel, "rb")
        if not f then return nil end
        local bytes = f:read("*a")
        f:close()
        return CacheBlob.decode(rel, bytes)
      end,
      exists = function(_, rel)
        local f = io.open(GAME .. "/" .. rel, "rb")
        if f then f:close() end
        return f ~= nil
      end,
    }
  end
end
local data = H.gen3Data(GAME)
local ItemsData = require("src.core.game3.items_data")
if ItemsData.ensureLoaded then ItemsData.ensureLoaded() end
data.gen3Items = ItemsData
local Moves = require("src.core.game3.battle.moves")
local P = require("src.core.game3.pokemon")
do
  local pack = GAME .. "/data/generated/gba/pokemon/battle_moves.lua"
  Moves._rom = dofile(pack).moves
  Moves._romLoaded = true
  P._battleMoves = dofile(pack).moves
  P._romMoveNames = P._romMoveNames or P._moveNames
  data.gen3Moves = Moves
end
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local okA, errA = pcall(require("src.mods.Gen3Compat").applyMerged, { mods = run.loader, data = data })
T.check(okA, "the registries apply (" .. tostring(errA) .. ")")
run.loader.events:emit("game.ready", {})
pcall(ItemsData.applyProfile, GAME)

local exports = run.loader.exports.national_dex_gen3
local V = exports and exports._vending
T.check(V ~= nil, "the vending machines are installed")
if not V then return T.finish() end

local machines = dofile(root .. "/data/vending.lua")
local items = dofile(root .. "/data/items.lua")
local tms = dofile(root .. "/data/tms.lua")
local shops = dofile(root .. "/data/shops.lua")
local byId = {}
for _, m in ipairs(machines) do byId[m.id] = m end

-- ------- the data

local PREFIX = { emerald = "EM_", ruby = "RU_", sapphire = "SA_", firered = "FR_", leafgreen = "LG_" }
for _, m in ipairs(machines) do
  T.check(type(m.sprite) == "string" and io.open(root .. "/" .. m.sprite) ~= nil, m.id .. ": its sprite ships")
  for _, k in ipairs({ "body", "lower", "trim", "outline", "screen", "accent" }) do
    T.check(type(m.bezel[k]) == "table" and #m.bezel[k] == 3, m.id .. ": bezel " .. k)
  end
  for _, g in ipairs(m.games) do
    if g == GAME then
      T.check(data.maps[PREFIX[g] .. m.map] ~= nil, m.id .. ": " .. m.map .. " is a map in " .. g)
    end
  end
end
-- every evolution item in one machine, every new TM in the other, each once
local sells = {}
for _, m in ipairs(machines) do
  for _, tab in ipairs(m.tabs) do
    for _, slug in ipairs(tab.add) do
      T.check(sells[slug] == nil, slug .. " is in one machine, once")
      sells[slug] = m.id
    end
  end
end
for _, it in ipairs(items) do T.eq(sells[it.slug], "evo", it.slug .. " is in the evolution item machine") end
for _, t in ipairs(tms) do T.eq(sells[t.id:lower()], "tm", t.id .. " is in the TM machine") end
-- and no longer in a Mart of a game with the machines
for _, rule in ipairs(shops) do
  local hoenn = false
  for _, g in ipairs(rule.games) do if g == "emerald" then hoenn = true end end
  if hoenn then
    for _, slug in ipairs(rule.add) do
      T.check(sells[slug] == nil, rule.store .. " no longer sells " .. slug .. " (a machine does)")
    end
  end
end

-- ------- the stock, resolved in this game

local evoTabs, tmTabs = V.stock(byId.evo), V.stock(byId.tm)
local n = 0
for _, tab in ipairs(evoTabs) do n = n + #tab.entries end
T.eq(n, #items, "every evolution item resolves, with a price")
local dusk
for _, e in ipairs(evoTabs[1].entries) do if e.slug == "dusk-stone" then dusk = e end end
T.check(dusk and dusk.name == "DUSK STONE" and dusk.price == 2100, "Dusk Stone: its name and price")
T.check(dusk and type(dusk.description) == "string" and dusk.description ~= "", "and its description")
T.eq(#tmTabs[1].entries, #tms, "every new TM resolves")
local fang = tmTabs[1].entries[1]
local fangRow = P.battleMove(Moves.numForName("FIRE_FANG"))
T.eq(fang.tm and fang.tm.number, 51, "TM51 first")
T.eq(fang.tm and fang.tm.type, 10, "TM51's move is Fire")
T.eq(fang.tm and fang.tm.power, fangRow and fangRow.power, "with the move's power")
T.check(fang.tm and type(fang.tm.move) == "string" and fang.tm.move:upper():find("FIRE FANG", 1, true) ~= nil,
  "and its name (" .. tostring(fang.tm and fang.tm.move) .. ")")

-- ------- the screen, on a session of its own

local Bag = require("src.core.game3.bag")
local session = { money = 100000, bag = Bag.new() }
local clock, sounds, closed = 0, {}, 0
local makeScreen = dofile(root .. "/src/vending_screen.lua")
local S = makeScreen({
  session = function() return session end, Bag = Bag,
  se = function(name) sounds[#sounds + 1] = name end,
  now = function() return clock end,
  onClose = function() closed = closed + 1 end,
})

local function input(press, down)
  local p, d = {}, {}
  for _, k in ipairs(press or {}) do p[k] = true end
  for _, k in ipairs(down or {}) do d[k] = true end
  return { wasPressed = function(_, k) return p[k] == true end, isDown = function(_, k) return d[k] == true end }
end
local function press(k) S.input(input({ k }, { k })) end

-- buttons
S.open(byId.evo, evoTabs)
local st = S.state()
-- the A that opened the machine, still held: not read as a choice
S.input(input({ "a" }, { "a" }))
S.input(input({}, { "a" }))
T.eq(st.focus, "grid", "the A that opened it chooses nothing")
T.eq(#st.tabs, 1 + #byId.evo.tabs, "an ALL tab before the machine's own")
T.eq(#st.tabs[1].entries, #items, "ALL lists every item")
press("right")
T.eq(st.cursor, 2, "Right moves along the row")
press("down")
T.eq(st.cursor, 2 + st.cols, "Down moves a row")
press("left")
press("up")
T.eq(st.cursor, 1, "and back")
press("left")
T.eq(st.cursor, #items, "Left from the first wraps to the last")
T.check(st.scroll > 0, "the grid scrolled to show it")
press("right")
T.eq(st.cursor, 1, "Right from the last wraps to the first")
T.eq(st.scroll, 0, "scrolled back")
-- held: one step, then the repeat
local held = input({ "down" }, { "down" })
S.input(held)
local still = input({}, { "down" })
for _ = 1, S.REPEAT_START - 1 do S.input(still) end
T.eq(st.cursor, 1 + st.cols, "held Down: one row, then a wait")
S.input(still)
T.eq(st.cursor, 1 + 2 * st.cols, "then it repeats")
S.input(input())
-- Up from the top row: the tabs, where Left / Right change tab and Down goes back
press("up")
press("up")
T.eq(st.cursor, 1, "Up to the top row")
press("up")
T.eq(st.focus, "tabs", "Up from the top row: the tabs")
press("right")
T.eq(st.tab, 2, "Right on the tabs: the next tab")
T.eq(st.focus, "tabs", "and stays on the tabs")
press("left")
T.eq(st.tab, 1, "Left: the one before")
press("down")
T.eq(st.focus, "grid", "Down: back to the grid")
T.eq(st.cursor, 1, "on its first item")
press("up")
press("b")
T.eq(st.focus, "grid", "B on the tabs: back to the grid")
T.check(S.isOpen(), "and still open")
-- a held Up running on through the rows stops at the top row
press("down")
S.input(input({}, { "up" }))
for _ = 1, S.REPEAT_START + 2 * S.REPEAT_EVERY do S.input(input({}, { "up" })) end
press("up")
T.eq(st.focus, "tabs", "(a fresh press reaches them)")
press("down")
S.input(input())
press("r")
T.eq(st.tab, 2, "R: the next tab")
T.eq(st.cursor, 1, "from its first item")
press("l")
press("l")
T.eq(st.tab, #st.tabs, "L from the first tab wraps to the last")
press("r")
-- buy three of the first item
local first = st.tabs[1].entries[1]
press("a")
T.eq(st.focus, "card", "A opens the item's card")
press("right")
press("right")
T.eq(st.qty, 3, "Right raises the amount")
press("up")
T.eq(st.qty, 13, "Up adds ten")
press("down")
press("left")
press("right")
T.eq(st.qty, 3, "Down takes ten, Left one")
press("a")
T.eq(st.focus, "confirm", "A asks first")
press("right")
T.check(not st.yes, "a direction moves to NO")
press("a")
T.eq(st.focus, "card", "NO buys nothing")
T.eq(Bag.get(session.bag, first.id), 0, "nothing in the Bag")
press("a")
press("a")
T.eq(Bag.get(session.bag, first.id), 3, "YES: three in the Bag")
T.eq(session.money, 100000 - 3 * first.price, "and their price off the money")
T.eq(sounds[#sounds], "SE_VEND", "the machine's sound")
T.check(st.vend and st.vend.id == first.id, "the item drops into the tray")
T.eq(st.qty, 1, "the amount back to one")
-- too little money: the amount stops at what it pays for, and a refusal buys nothing
session.money = first.price * 2 + 1
press("left")
T.eq(st.qty, 2, "Left from one wraps to what the money pays for")
session.money = 5
press("a")
T.eq(st.focus, "card", "too little money: no question")
T.eq(st.toast and st.toast.text, S.TEXT.noMoney, "it says so")
T.eq(sounds[#sounds], "SE_FAILURE", "with the failure sound")
T.eq(Bag.get(session.bag, first.id), 3, "and nothing is bought")
session.money = 10000
press("b")
T.eq(st.focus, "grid", "B: back to the grid")
press("b")
T.check(not S.isOpen(), "B again leaves")
T.eq(closed, 1, "and the machine is told")

-- taps, against what the last draw recorded
local hits
local G = setmetatable({}, { __index = function() return function() end end })
local fontStub = { getWidth = function(_, s) return #s * 4 end, getHeight = function() return 8 end,
  getWrap = function(_, s) return 0, { s } end }
G.newFont = function() return fontStub end
G.getFont = function() return fontStub end
local VP = { gameX = 0, gameY = 0, gameWidth = 960, gameHeight = 640, width = 960, height = 640 }
local function draw()
  S.draw(G, VP)
  hits = S.state().hit
end
local function find(kind, arg)
  for _, h in ipairs(hits) do
    if h.kind == kind and (arg == nil or h.arg == arg) then return h end
  end
end
local function tapOn(kind, arg)
  draw()
  local h = find(kind, arg)
  T.check(h ~= nil, "a " .. kind .. " to tap" .. (arg and (" (" .. tostring(arg) .. ")") or ""))
  if not h then return end
  local x, y = h[1] + h[3] / 2, h[2] + h[4] / 2
  S.pointer({ phase = "pressed", id = 1, x = x, y = y })
  S.pointer({ phase = "released", id = 1, x = x, y = y })
end

S.open(byId.tm, tmTabs)
st = S.state()
T.check(#st.tabs > 2, "the TM machine: ALL and a tab per move type")
local fire
for i, tab in ipairs(st.tabs) do if tab.type == 10 then fire = i end end
T.check(fire ~= nil, "a Fire tab")
tapOn("nextTab")
T.eq(st.tab, 2, "the arrow after the tabs: the next tab")
tapOn("prevTab")
tapOn("prevTab")
T.eq(st.tab, #st.tabs, "the arrow before them wraps to the last")
tapOn("nextTab")
T.eq(st.tab, 1, "and the one after wraps to the first")
tapOn("tab", 2)
T.eq(st.tab, 2, "tapping a tab opens it")
tapOn("tab", 1)
draw()
T.check(find("tab", fire) == nil, "a tab past the strip's end can't be tapped yet")
for _ = 1, fire - 1 do tapOn("nextTab") end
T.eq(st.tab, fire, "the arrows reach it")
draw()
T.check(find("tab", fire) ~= nil, "and bring it into view")
for _, e in ipairs(st.tabs[fire].entries) do T.eq(e.tm.type, 10, e.name .. " is a Fire TM") end
for _ = 1, fire - 1 do tapOn("prevTab") end
T.eq(st.tab, 1, "back to ALL")
tapOn("tile", 2)
T.eq(st.cursor, 2, "tapping a tile chooses it")
T.eq(st.focus, "card", "and opens its card")
local tm2 = st.tabs[1].entries[2]
tapOn("plus")
T.eq(st.qty, 2, "+ raises the amount")
tapOn("minus")
tapOn("plus")
T.eq(st.qty, 2, "- lowers it")
tapOn("buy")
T.eq(st.focus, "confirm", "BUY asks first")
tapOn("no")
T.eq(st.focus, "card", "NO buys nothing")
tapOn("buy")
tapOn("yes")
T.eq(Bag.get(session.bag, tm2.id), 2, "YES: two TMs in the Bag")
-- a drag scrolls the grid, and is not a tap
draw()
local g = st.gridRect
local x0, y0 = g[1] + 10, g[2] + g[4] - 10
S.pointer({ phase = "pressed", id = 2, x = x0, y = y0 })
S.pointer({ phase = "moved", id = 2, x = x0, y = y0 - 400 })
T.check(st.scroll > 1, "dragging up scrolls down (" .. st.scroll .. ")")
S.pointer({ phase = "released", id = 2, x = x0, y = y0 - 400 })
T.eq(st.scroll, math.floor(st.scroll), "it settles on a row")
T.eq(st.cursor, 2, "and chose nothing")
S.wheel(1)
local afterWheel = st.scroll
S.wheel(-1)
T.eq(st.scroll, afterWheel + 1, "the wheel scrolls a row")
tapOn("close")
T.check(not S.isOpen(), "the close button leaves")
T.eq(closed, 2, "and the machine is told")

-- the window's shape: widescreen gets more columns beside the card, portrait the card under the
-- grid and more rows; every button stays inside the window, and taps still work
local shapes = {
  { name = "3:2", w = 960, h = 640 }, { name = "16:9", w = 1280, h = 720 }, { name = "21:9", w = 2520, h = 1080 },
  { name = "4:3", w = 1024, h = 768 }, { name = "portrait 9:19.5", w = 390, h = 844 },
  { name = "portrait 3:4", w = 768, h = 1024 }, { name = "square", w = 800, h = 800 },
}
local layouts = {}
for _, shape in ipairs(shapes) do
  VP = { gameX = 0, gameY = 0, gameWidth = shape.w, gameHeight = shape.h, width = shape.w, height = shape.h }
  session.money = 100000
  S.open(byId.evo, evoTabs)
  st = S.state()
  draw()
  local L = st.layout
  layouts[shape.name] = L
  T.check(L.cols >= 3 and L.rows >= 2, shape.name .. ": a grid of at least 3 x 2 (" .. L.cols .. " x " .. L.rows .. ")")
  local inside = true
  for _, h in ipairs(hits) do
    if h[1] < -0.5 or h[2] < -0.5 or h[1] + h[3] > shape.w + 0.5 or h[2] + h[4] > shape.h + 0.5 then inside = false end
  end
  T.check(inside, shape.name .. ": everything to tap is inside the window")
  local g, c = L.grid, L.card
  local apart = L.portrait and (g[2] + g[4] <= c[2]) or (g[1] + g[3] <= c[1])
  T.check(apart, shape.name .. ": the grid and the card don't overlap")
  tapOn("tile", 2)
  T.eq(st.focus, "card", shape.name .. ": a tile opens its card")
  tapOn("plus")
  T.eq(st.qty, 2, shape.name .. ": + works")
  tapOn("close")
end
T.check(not layouts["3:2"].portrait and not layouts["16:9"].portrait, "3:2 and 16:9 are laid out wide")
T.check(layouts["portrait 9:19.5"].portrait and layouts["portrait 3:4"].portrait, "a tall window is portrait")
T.check(layouts["16:9"].cols > layouts["3:2"].cols, "16:9 has more columns than 3:2")
T.check(layouts["portrait 9:19.5"].rows > layouts["3:2"].rows, "a phone held upright has more rows")
T.check(layouts["21:9"].pw <= S.PAGE.MAX_WIDTH, "a very wide window keeps the page to its widest")

T.finish()
