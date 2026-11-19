-- Standalone: luajit mods/national_dex_gen3/tests/ev_berries_test.lua [game] (from the gen1recomp
-- root; FireRed by default, needs that cart imported).
--
-- The EV-lowering berries (src/ev_berries.lua): used from the Bag, Pomeg / Kelpsy / Qualot / Hondew /
-- Grepa / Tamato lower one stat's EVs by 10 and raise friendship, on every Gen 3 game (Emerald by
-- its own data, the others through this mod's effect).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"

local data = H.gen3Data(GAME)
H.useCart(GAME)
data.gen3Moves = require("src.core.game3.battle.moves")
data.gen3Items = require("src.core.game3.items_data")
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
pcall(require("src.mods.Gen3Compat").applyMerged, { mods = run.loader, data = data })
run.loader.events:emit("game.ready", {})

local ItemsData = require("src.core.game3.items_data")
local ItemUse = require("src.core.game3.item_use")
local Pokemon = require("src.core.game3.pokemon")
local Bag = require("src.core.game3.bag")
ItemsData.applyProfile(GAME)
local session = { version = GAME, party = {} }

local function mon(evs, friendship)
  local m = { species = 25, level = 50, hp = 100, maxHp = 100, personality = 1, otId = 1,
    friendship = friendship or 70, evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 } }
  for k, v in pairs(evs or {}) do m.evs[k] = v end
  pcall(Pokemon.recalcStats, m)
  return m
end
-- the Bag's use, as the party menu runs it
local function use(id, m)
  local bag = Bag.new()
  Bag.add(bag, id, 1)
  local kind = ItemsData.fieldUseKind(id)
  local ok
  if kind == "mod" then
    ok = ItemUse.runModEffect(session, bag, id, m, 1)
  else
    local okU, used = pcall(ItemUse.useVitamin, session, m, id)
    ok = okU and used
  end
  return ok and true or false, Bag.count and Bag.count(bag, id) or nil, kind
end

local BERRIES = { { 153, "hp" }, { 154, "atk" }, { 155, "def" }, { 156, "spa" }, { 157, "spd" }, { 158, "spe" } }
for _, b in ipairs(BERRIES) do
  local id, stat = b[1], b[2]
  local m = mon({ [stat] = 200 })
  local ok, left, kind = use(id, m)
  T.check(ok, ("item %d (%s): used (%s)"):format(id, stat, tostring(kind)))
  T.eq(Pokemon.evsOf(m)[stat], 190, ("item %d: %s EVs 200 -> 190"):format(id, stat))
  T.eq(Pokemon.friendshipOf(m), 80, ("item %d: friendship 70 -> 80"):format(id))
end

local m = mon({ hp = 5 }, 150)
use(153, m)
T.eq(Pokemon.evsOf(m).hp, 0, "never below 0 EVs")
T.eq(Pokemon.friendshipOf(m), 155, "friendship 150 rises by 5")
local maxed = mon({ hp = 0 }, 255)
local ok = use(153, maxed)
T.check(not ok, "no EVs to lose and friendship maxed: it won't have any effect")
local friendly = mon({ hp = 0 }, 70)
T.check((use(153, friendly)), "no EVs to lose but friendship can rise: still used")
T.eq(Pokemon.friendshipOf(friendly), 80, "and friendship rises")

run.release()
T.finish("national_dex_gen3 EV berries (" .. GAME .. ")")
