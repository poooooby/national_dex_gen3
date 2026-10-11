-- Standalone: luajit mods/national_dex_gen3/tests/regional_test.lua (from the gen1recomp root;
-- needs Pokemon FireRed imported under firered/).
--
-- The regional forms of the cart's own species (Alola, Galar, Hisui, Paldea): each evolves into
-- the same region's form of its evolution, or into the new species only its regional form
-- becomes (Perrserker, Sirfetch'd, Mr. Rime, Cursola, Obstagoon, Runerigus, Sneasler, Clodsire).
-- The cart's own species are untouched.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")

local data = H.gen3Data()
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.events:emit("game.ready", {})

local api = run.loader.exports.national_dex_gen3
local Evolution = require("src.core.game3.evolution")
local Pokemon = require("src.core.game3.pokemon")
local Rtc = require("src.core.game3.rtc")
local items = run.loader.content.items
Evolution.nationalAllows = function() return true end

local function slot(name) return api.slotOf(name) or Pokemon.speciesFromName(name) end
local function item(slug) return items:get(slug).index end
local cartItem = { ["fire-stone"] = 95, ["leaf-stone"] = 98 }   -- FireRed's own (its Ice Stone is ours)

local function withClock(hour, fn)
  local enabled, host = Rtc.enabled, Rtc.hostInfo
  Rtc.enabled = function() return false end
  Rtc.hostInfo = function() return { hour = hour } end
  local ok, result = pcall(fn)
  Rtc.enabled, Rtc.hostInfo = enabled, host
  assert(ok, result)
  return result
end

local function mon(name, level, extra)
  local m = { species = slot(name), level = level, personality = 0, friendship = 0 }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end
local function up(name, level, extra, hour)
  return withClock(hour or 12, function() return Evolution.levelTarget(mon(name, level, extra), {}) end)
end
local function use(name, stone)
  return Evolution.itemTarget(mon(name, 30), cartItem[stone] or item(stone:upper():gsub("-", "_")))
end
local function trade(name)
  local target = Evolution.targetSpecies(mon(name, 30), Evolution.EVO_MODE_TRADE)
  return target ~= 0 and target or nil
end

-- ------- the form list

T.eq(#api.listForms(), 128, "128 forms")
T.eq(slot("TAUROS_PALDEA_AQUA_BREED"), 1217, "the last is Paldean Tauros (Aqua Breed) at 1217")
T.eq(slot("MEOWTH"), 52, "a cart species keeps its own name (MEOWTH is the cart's)")
T.check(slot("MR_MIME") ~= slot("MR_MIME_GALAR"), "and MR_MIME is not the Galarian form")
T.eq(api.baseDexOf("MEOWTH_ALOLA"), 52, "a regional form counts as its base in the Pokedex")

-- ------- into the same region's form

T.eq(use("SANDSHREW_ALOLA", "ice-stone"), slot("SANDSLASH_ALOLA"), "Alolan Sandshrew + Ice Stone -> Alolan Sandslash")
T.eq(use("SANDSHREW", "ice-stone"), nil, "the cart's Sandshrew does not use an Ice Stone")
T.eq(use("VULPIX_ALOLA", "ice-stone"), slot("NINETALES_ALOLA"), "Alolan Vulpix + Ice Stone -> Alolan Ninetales")
T.eq(use("VULPIX", "fire-stone"), Pokemon.speciesFromName("NINETALES"), "the cart's Vulpix still takes a Fire Stone")
T.eq(up("RATTATA_ALOLA", 20, nil, 22), slot("RATICATE_ALOLA"), "Alolan Rattata at 20, at night -> Alolan Raticate")
T.eq(up("RATTATA_ALOLA", 20, nil, 12), nil, "not by day")
T.eq(up("DIGLETT_ALOLA", 26), slot("DUGTRIO_ALOLA"), "Alolan Diglett at 26")
T.eq(up("DIGLETT_ALOLA", 25), nil, "not at 25")
T.eq(up("MEOWTH_ALOLA", 10, { friendship = 255 }), slot("PERSIAN_ALOLA"), "Alolan Meowth with high friendship")
T.eq(up("MEOWTH_ALOLA", 10, { friendship = 0 }), nil, "not without it")
T.eq(up("GEODUDE_ALOLA", 25), slot("GRAVELER_ALOLA"), "Alolan Geodude at 25")
T.eq(trade("GRAVELER_ALOLA"), slot("GOLEM_ALOLA"), "Alolan Graveler by trade -> Alolan Golem")
T.eq(up("GRIMER_ALOLA", 38), slot("MUK_ALOLA"), "Alolan Grimer at 38")
T.eq(up("PONYTA_GALAR", 40), slot("RAPIDASH_GALAR"), "Galarian Ponyta at 40")
T.eq(up("ZIGZAGOON_GALAR", 20), slot("LINOONE_GALAR"), "Galarian Zigzagoon at 20")
T.eq(use("SLOWPOKE_GALAR", "GALARICA_CUFF"), slot("SLOWBRO_GALAR"), "Galarian Slowpoke + Galarica Cuff")
T.eq(use("SLOWPOKE_GALAR", "GALARICA_WREATH"), slot("SLOWKING_GALAR"), "Galarian Slowpoke + Galarica Wreath")
T.eq(use("GROWLITHE_HISUI", "fire-stone"), slot("ARCANINE_HISUI"), "Hisuian Growlithe + Fire Stone")
T.eq(use("VOLTORB_HISUI", "leaf-stone"), slot("ELECTRODE_HISUI"), "Hisuian Voltorb + Leaf Stone")

-- ------- into a new species

T.eq(up("MEOWTH_GALAR", 28), slot("PERRSERKER"), "Galarian Meowth at 28 -> Perrserker")
T.eq(up("MEOWTH", 28), Pokemon.speciesFromName("PERSIAN"), "the cart's Meowth still becomes Persian")
T.eq(up("MR_MIME_GALAR", 42), slot("MR_RIME"), "Galarian Mr. Mime at 42 -> Mr. Rime")
T.eq(up("CORSOLA_GALAR", 38), slot("CURSOLA"), "Galarian Corsola at 38 -> Cursola")
T.eq(up("WOOPER_PALDEA", 20), slot("CLODSIRE"), "Paldean Wooper at 20 -> Clodsire")
T.eq(up("WOOPER", 20), Pokemon.speciesFromName("QUAGSIRE"), "the cart's Wooper still becomes Quagsire")
T.eq(up("LINOONE_GALAR", 35, nil, 22), slot("OBSTAGOON"), "Galarian Linoone at 35, at night -> Obstagoon")
T.eq(up("LINOONE_GALAR", 35, nil, 12), nil, "not by day")
T.eq(up("SNEASEL_HISUI", 30, { item = item("RAZOR_CLAW") }, 12), slot("SNEASLER"),
     "Hisuian Sneasel holding a Razor Claw by day -> Sneasler")
T.eq(up("SNEASEL_HISUI", 30, { item = item("RAZOR_CLAW") }, 22), nil, "not at night")
T.eq(up("FARFETCHD_GALAR", 30, { critsThisBattle = 3 }), slot("SIRFETCHD"),
     "Galarian Farfetch'd after 3 critical hits in a battle -> Sirfetch'd")
T.eq(up("FARFETCHD_GALAR", 30, { critsThisBattle = 2 }), nil, "not after 2")
T.eq(up("YAMASK_GALAR", 30, { hp = 10, maxHp = 60 }), slot("RUNERIGUS"),
     "Galarian Yamask 49+ HP down when it levels up -> Runerigus")
T.eq(up("YAMASK_GALAR", 30, { hp = 60, maxHp = 60 }), nil, "not at full HP")

-- ------- no evolution

for _, id in ipairs({ "RATICATE_ALOLA", "RAICHU_ALOLA", "EXEGGUTOR_ALOLA", "MAROWAK_ALOLA", "ARTICUNO_GALAR",
                      "WEEZING_GALAR", "TYPHLOSION_HISUI", "TAUROS_PALDEA_COMBAT_BREED" }) do
  T.eq(up(id, 100, { friendship = 255 }), nil, id .. " does not evolve")
end

-- ------- critical hits counted in battle (src/counters.lua)

do
  local Battle = require("src.core.game3.battle")
  local farfetchd = mon("FARFETCHD_GALAR", 30)
  local st = { playerParty = { farfetchd } }
  local function hit(crit)
    run.loader.events:emit("battle.damage_dealt", { battle = st, user = { side = "player", partyIndex = 1 },
      damage = 10, crit = crit, move = { effect = 0 } })
  end
  Battle._leveledUp = {}
  hit(true); hit(false); hit(true)
  T.eq(farfetchd.critsThisBattle, 2, "two critical hits counted, not the normal one")
  hit(true)
  T.check(Battle._leveledUp[1] == true, "the third marks it for the end-of-battle check")
  run.loader.events:emit("battle.started", { battle = st })
  T.eq(farfetchd.critsThisBattle, 0, "a new battle starts the count again")
  Battle._leveledUp = nil
end

run.release()
T.finish("national_dex_gen3 regional forms")
