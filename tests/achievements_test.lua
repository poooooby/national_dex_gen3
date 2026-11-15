-- Standalone: luajit mods/national_dex_gen3/tests/achievements_test.lua [firered|red|gold|crystal ...]
-- (from the gen1recomp root; runs on firered, red and crystal when none is named; needs those
-- carts imported and mods/recomp_achievements beside this mod).
--
-- WoobleDex's achievements (src/achievements.lua, data/achievements.lua) in the real Recomp
-- Achievements mod: every definition fits its limits, all 33 register with the right goals,
-- and progress follows the Pokedex once a save is attached (base species by National number, a
-- form by its own slot / id), unlocks at the goal (the record then keeps no count), and credits a save's earlier catches on load.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local here = (arg[0]:gsub("\\", "/"):match("^(.*)/") or ".")
local ACH = "mods/recomp_achievements"
local SOURCE = "mod:national_dex_gen3"

local rows = dofile(here .. "/../data/achievements.lua")

-- ------- the definitions
local ids = {}
for _, e in ipairs(rows.list) do
  T.check(not ids[e.id], "unique id " .. e.id)
  ids[e.id] = true
  T.check(e.id:match("^[a-z0-9_%-]+$") and #e.id <= 48, e.id .. ": a valid id")
  T.check(#e.title <= 32, e.id .. ": title fits 32 characters")
  T.check(#e.description <= 160, e.id .. ": description fits 160 characters")
  T.check(e.points >= 0 and e.points <= 100, e.id .. ": points 0..100")
  T.check(#e.category <= 16, e.id .. ": category fits 16 characters")
end
T.eq(#rows.list, 33, "33 achievements")

local GOALS = {
  dex_complete = 1025, dex_seen = 1025, dex_master = 1153,
  dex_100 = 100, dex_250 = 250, dex_500 = 500, dex_750 = 750,
  gen_1 = 151, gen_2 = 100, gen_3 = 135, gen_4 = 107, gen_5 = 156, gen_6 = 72, gen_7 = 88,
  gen_8 = 96, gen_9 = 120,
  starters = 27, legendary = 71, mythical = 23, ultra_beasts = 11, paradox = 20, fossils = 25,
  babies = 19,
  regional_alola = 18, regional_galar = 19, regional_hisui = 16, regional_paldea = 4, regional_all = 57,
  family_eevee = 8, family_alcremie = 9, family_rotom = 6, family_lycanroc = 3, family_oricorio = 4,
}

local function versions()
  local out = {}
  for i = 1, #arg do
    if ({ firered = 1, leafgreen = 1, emerald = 1, ruby = 1, sapphire = 1, red = 1, blue = 1, yellow = 1,
      gold = 1, silver = 1, crystal = 1 })[arg[i]] then out[#out + 1] = arg[i] end
  end
  if #out == 0 then out = { "firered", "red", "crystal" } end
  return out
end

local function checkRegistered(ach, version)
  local list = ach.list({ source = SOURCE }) or {}
  T.eq(#list, 33, version .. ": all 33 registered")
  local wrong
  for _, r in ipairs(list) do
    if GOALS[r.id] ~= r.goal then wrong = wrong or (r.id .. " " .. tostring(r.goal)) end
  end
  T.eq(wrong, nil, version .. ": every goal is its group's size")
end

local function progress(ach, id)
  local r = ach.get(SOURCE .. ":" .. id)
  return r and r.progress, r and r.unlocked
end

-- ------- Gen 3
local function gen3(version)
  local H = dofile(here .. "/_gen3.lua")
  local data = H.gen3Data(version)
  H.useCart(version)
  data.gen3Moves = require("src.core.game3.battle.moves")
  local run = T.sdk.loadMods({ ACH, "mods/national_dex_gen3" }, { data = data, generation = 3 })
  T.eq(#run.errors, 0, version .. ": loads clean (" .. tostring(run.errors[1]) .. ")")
  pcall(require("src.mods.Gen3Compat").applyMerged, { mods = run.loader, data = data })
  run.loader.events:emit("game.ready", {})
  local ach = run.loader.exports.recomp_achievements
  checkRegistered(ach, version)

  local Runtime = require("src.core.game3.runtime")
  local Dex = require("src.core.game3.dex")
  local P = require("src.core.game3.pokemon")
  local api = run.loader.exports.national_dex_gen3
  local function session(dex)
    return { dex = dex or Dex.new(), party = {}, version = version, modData = {}, flags = {}, vars = {} }
  end
  local s = session()
  Runtime.session = s
  run.loader.events:emit("save.loaded", { save = s, session = s })
  T.eq(progress(ach, "dex_complete"), 0, version .. ": a new save starts at 0")

  -- Bulbasaur, Treecko (the cart's slot 277), Turtwig, Heat Rotom (its own slot; the base too)
  for _, n in ipairs({ 1, 252, 387 }) do Dex.setCaught(s.dex, P.speciesFromNational(n)) end
  Dex.setCaught(s.dex, api.slotOf("ROTOM_HEAT"))
  Dex.setSeen(s.dex, P.speciesFromNational(4))
  run.loader.events:emit("pokemon.caught", {})
  T.eq(progress(ach, "dex_complete"), 4, version .. ": four species caught (Rotom by its form)")
  T.eq(progress(ach, "dex_seen"), 5, version .. ": five seen")
  T.eq(progress(ach, "gen_3"), 1, version .. ": Treecko counts for Generation III")
  T.eq(progress(ach, "starters"), 3, version .. ": three starters")
  T.eq(progress(ach, "family_rotom"), 2, version .. ": Rotom and Heat Rotom")
  T.eq(progress(ach, "dex_master"), 5, version .. ": four species and a form")

  for _, f in ipairs(api.listForms()) do
    if f.id:match("_PALDEA") then Dex.setCaught(s.dex, f.slot) end
  end
  run.loader.events:emit("battle.ended", {})
  T.check(select(2, progress(ach, "regional_paldea")), version .. ": the four Paldean forms unlock Paldean Variants")
  for n = 1, 100 do Dex.setCaught(s.dex, P.speciesFromNational(n)) end
  run.loader.events:emit("map.entered", {})
  T.check(select(2, progress(ach, "dex_100")), version .. ": 100 species unlock Rising Collector")
  T.check(not select(2, progress(ach, "dex_250")), version .. ": but not the 250")

  -- another save, with its catches made before: credited when it loads
  local old = Dex.new()
  for n = 1, 151 do Dex.setCaught(old, P.speciesFromNational(n)) end
  local s2 = session(old)
  s2.modData = {}
  Runtime.session = s2
  run.loader.events:emit("save.loading", {})
  run.loader.events:emit("save.loaded", { save = s2, session = s2 })
  T.check(select(2, progress(ach, "gen_1")), version .. ": a save with all 151 is credited Generation I on load")
  T.eq(progress(ach, "dex_complete"), 151, version .. ": and 151 toward the National Dex")
  run.release()
end

-- ------- Red / Gold
local function gen12(version)
  local H = dofile(here .. "/_gen12.lua")
  local gen = H.GENERATION[version]
  local run = H.load(version, { ACH })
  T.eq(#run.errors, 0, version .. ": loads clean (" .. tostring(run.errors[1]) .. ")")
  local ach = run.loader.exports.recomp_achievements
  checkRegistered(ach, version)

  local owned = gen == 1 and "owned" or "caught"
  local save = { version = version, pokedex = { seen = {}, owned = {}, caught = {} }, party = {}, modData = {} }
  local game = { data = run.data, save = save }
  run.loader.game = game
  run.loader.events:emit("game.ready", { game = game })
  run.loader.events:emit("save.loaded", { save = save })
  T.eq(progress(ach, "dex_complete"), 0, version .. ": a new save starts at 0")
  local p = save.pokedex
  for _, id in ipairs({ "BULBASAUR", "CHIKORITA", "TURTWIG", "ROTOM", "ROTOM_HEAT" }) do
    p[owned][id], p.seen[id] = true, true
  end
  p.seen.CHARMANDER = true
  run.loader.events:emit("pokemon.caught", {})
  T.eq(progress(ach, "dex_complete"), 4, version .. ": four species caught")
  T.eq(progress(ach, "dex_seen"), 5, version .. ": five seen")
  T.eq(progress(ach, "gen_2"), 1, version .. ": Chikorita counts for Generation II")
  T.eq(progress(ach, "starters"), 3, version .. ": three starters")
  T.eq(progress(ach, "family_rotom"), 2, version .. ": Rotom and Heat Rotom")
  T.eq(progress(ach, "dex_master"), 5, version .. ": four species and a form")
  for _, id in ipairs({ "WOOPER_PALDEA", "TAUROS_PALDEA_COMBAT_BREED", "TAUROS_PALDEA_BLAZE_BREED",
      "TAUROS_PALDEA_AQUA_BREED" }) do
    p[owned][id] = true
  end
  run.loader.events:emit("battle.ended", {})
  T.check(select(2, progress(ach, "regional_paldea")), version .. ": the four Paldean forms unlock Paldean Variants")
  run.release()
end

for _, v in ipairs(versions()) do
  if ({ red = 1, blue = 1, yellow = 1, gold = 1, silver = 1, crystal = 1 })[v] then gen12(v) else gen3(v) end
end
T.finish("national_dex_gen3 achievements")
