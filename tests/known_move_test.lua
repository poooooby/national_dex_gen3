-- Standalone: luajit mods/national_dex_gen3/tests/known_move_test.lua (from the gen1recomp
-- root; needs Pokemon FireRed imported under firered/).
--
-- The evolutions Gen 3's method table cannot express, decided by the evolution.check hook
-- (src/conditional_evos.lua): a known move (real, or a stand-in a TM teaches), a party member,
-- the weather, held items by time of day, and the plain level-ups that replace the ones that
-- needed a console trick or the other player. Counters (steps, Rage, recoil) and the coins
-- are in counters_test.lua.
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
local Weather = require("src.core.game3.weather")
local items = run.loader.content.items
Evolution.nationalAllows = function() return true end

local function slot(name)
  return api.slotOf(name) or Pokemon.speciesFromName(name)
    or (name == "MR_MIME" and 122 or nil)       -- the cart's own slot; its name has a full stop
end

local function withClock(hour, fn)
  local enabled, calc, host = Rtc.enabled, Rtc.calcLocalTime, Rtc.hostInfo
  Rtc.enabled = function() return false end
  Rtc.hostInfo = function() return { hour = hour } end
  local ok, result = pcall(fn)
  Rtc.enabled, Rtc.calcLocalTime, Rtc.hostInfo = enabled, calc, host
  assert(ok, result)
  return result
end

-- level-up check of a Pokemon of `species` at `level`
local function up(species, level, extra, session)
  local mon = { species = slot(species), level = level, personality = 0, friendship = 0 }
  for k, v in pairs(extra or {}) do mon[k] = v end
  return Evolution.levelTarget(mon, session or {})
end

-- ------- a known move (the real one, or a stand-in)

local MOVE = { ROCK_TOMB = 317, GIGA_DRAIN = 202, AERIAL_ACE = 332, FURY_SWIPES = 154, PSYBEAM = 60,
               TAKE_DOWN = 36, MIMIC = 102, STOMP = 23, TAUNT = 269, OUTRAGE = 200,
               DRAGONBREATH = 225, CHARM = 204, SWEET_KISS = 186, TACKLE = 33 }

local function knows(from, to, move, level)
  local what = from .. " knowing " .. tostring(move)
  T.eq(up(from, level, { moves = { MOVE[move] } }), slot(to), what .. " becomes " .. to)
  T.eq(up(from, level, { moves = { MOVE.TACKLE } }), nil, from .. " without it does not evolve")
  T.eq(up(from, level, {}), nil, from .. " with no moves does not evolve")
end
knows("LICKITUNG", "LICKILICKY", "ROCK_TOMB", 40)
knows("PILOSWINE", "MAMOSWINE", "ROCK_TOMB", 40)
knows("TANGELA", "TANGROWTH", "GIGA_DRAIN", 40)
knows("YANMA", "YANMEGA", "AERIAL_ACE", 40)
knows("AIPOM", "AMBIPOM", "FURY_SWIPES", 40)
knows("GIRAFARIG", "FARIGIRAF", "PSYBEAM", 40)
knows("DUNSPARCE", "DUDUNSPARCE", "TAKE_DOWN", 40)
knows("BONSLY", "SUDOWOODO", "MIMIC", 16)
knows("MIME_JR", "MR_MIME", "MIMIC", 16)
knows("STEENEE", "TSAREENA", "STOMP", 28)
knows("CLOBBOPUS", "GRAPPLOCT", "TAUNT", 35)
knows("POIPOLE", "NAGANADEL", "OUTRAGE", 45)
knows("DIPPLIN", "HYDRAPPLE", "DRAGONBREATH", 40)
T.eq(up("LICKITUNG", 29, { moves = { MOVE.ROCK_TOMB } }), nil, "Lickitung has a level floor (30)")
T.eq(up("POIPOLE", 39, { moves = { MOVE.OUTRAGE } }), nil, "and Poipole one (40)")

-- the stand-in moves are teachable (TM) or learnt by level-up by the cart species that use them
do
  local tm = Pokemon._tmhm
  local function teaches(species, moveId)
    local bits = tm.learnsets[Pokemon.speciesFromName(species)]
    for n = 0, 57 do
      if tm.machines[n] == moveId then
        local lo, hi = bits.lo or 0, bits.hi or 0
        local word = n < 32 and lo or hi
        return require("bit").band(word, require("bit").lshift(1, n % 32)) ~= 0
      end
    end
    return false
  end
  T.check(teaches("LICKITUNG", MOVE.ROCK_TOMB), "Lickitung can be taught Rock Tomb")
  T.check(teaches("PILOSWINE", MOVE.ROCK_TOMB), "Piloswine can be taught Rock Tomb")
  T.check(teaches("TANGELA", MOVE.GIGA_DRAIN), "Tangela can be taught Giga Drain")
  T.check(teaches("YANMA", MOVE.AERIAL_ACE), "Yanma can be taught Aerial Ace")
  local function learns(species, moveId)
    for _, row in ipairs(Pokemon.learnset(Pokemon.speciesFromName(species))) do
      if row[2] == moveId then return true end
    end
    return false
  end
  T.check(learns("AIPOM", MOVE.FURY_SWIPES), "Aipom learns Fury Swipes")
  T.check(learns("GIRAFARIG", MOVE.PSYBEAM), "Girafarig learns Psybeam")
  T.check(learns("DUNSPARCE", MOVE.TAKE_DOWN), "Dunsparce learns Take Down")
end

-- Eevee: friendship and a Fairy-ish move, ahead of Espeon / Umbreon
do
  local eevee = Pokemon.speciesFromName("EEVEE")
  local function eve(hour, moves, friendship)
    return withClock(hour, function()
      return Evolution.levelTarget({ species = eevee, level = 30, personality = 0,
        friendship = friendship, moves = moves }, {})
    end)
  end
  T.eq(eve(12, { MOVE.CHARM }, 255), slot("SYLVEON"), "Eevee knowing Charm becomes Sylveon, by day")
  T.eq(eve(23, { MOVE.SWEET_KISS }, 255), slot("SYLVEON"), "Sweet Kiss counts, at night")
  T.eq(eve(12, { MOVE.TACKLE }, 255), slot("ESPEON"), "without one it is Espeon by day")
  T.eq(eve(23, { MOVE.TACKLE }, 255), slot("UMBREON"), "and Umbreon at night")
  T.eq(eve(12, { MOVE.CHARM }, 100), nil, "Sylveon needs the friendship")
end

-- ------- the party, the weather

local function partyMon(name) return { species = slot(name), level = 20 } end
T.eq(up("MANTYKE", 20, {}, { party = { partyMon("REMORAID") } }), slot("MANTINE"),
     "Mantyke with a Remoraid in the party becomes Mantine")
T.eq(up("MANTYKE", 20, {}, { party = { partyMon("PIKACHU") } }), nil, "with anyone else it does not")
T.eq(up("PANCHAM", 32, {}, { party = { partyMon("UMBREON") } }), slot("PANGORO"),
     "Pancham with a Dark-type in the party becomes Pangoro")
T.eq(up("PANCHAM", 32, {}, { party = { partyMon("PIKACHU") } }), nil, "with no Dark-type it does not")
T.eq(up("PANCHAM", 31, {}, { party = { partyMon("UMBREON") } }), nil, "and not before level 32")

local function inWeather(id, fn)
  local before = Weather.current
  Weather.current = id
  local get = Weather.get
  Weather.get = function() return Weather.current end
  local result = fn()
  Weather.current, Weather.get = before, get
  return result
end
T.eq(inWeather(Weather.RAIN, function() return up("SLIGGOO", 50) end), slot("GOODRA"), "Sliggoo in the rain becomes Goodra")
T.eq(inWeather(Weather.DOWNPOUR, function() return up("SLIGGOO", 50) end), slot("GOODRA"), "and in a downpour")
T.eq(inWeather(Weather.SUNNY, function() return up("SLIGGOO", 50) end), nil, "not in sunshine")
T.eq(inWeather(Weather.RAIN, function() return up("SLIGGOO", 49) end), nil, "and not before level 50")

-- ------- held items by the time of day

local function holding(slug, name, level, hour)
  local held = items:get(slug).index
  return withClock(hour, function() return up(name, level, { item = held }) end)
end
T.eq(holding("RAZOR_CLAW", "SNEASEL", 25, 22), slot("WEAVILE"), "Sneasel holding a Razor Claw at night becomes Weavile")
T.eq(holding("RAZOR_CLAW", "SNEASEL", 25, 12), nil, "not by day")
T.eq(holding("RAZOR_FANG", "GLIGAR", 25, 2), slot("GLISCOR"), "Gligar holding a Razor Fang at night becomes Gliscor")
T.eq(holding("RAZOR_FANG", "GLIGAR", 25, 15), nil, "not by day")
T.eq(holding("OVAL_STONE", "HAPPINY", 10, 12), slot("CHANSEY"), "Happiny holding an Oval Stone by day becomes Chansey")
T.eq(holding("OVAL_STONE", "HAPPINY", 10, 22), nil, "not at night")
T.eq(holding("RAZOR_CLAW", "HAPPINY", 10, 12), nil, "and not holding the wrong item")
T.eq(holding("LEADERS_CREST", "BISHARP", 55, 12), slot("KINGAMBIT"), "Bisharp holding a Leader's Crest becomes Kingambit")
T.eq(up("BISHARP", 55, {}), nil, "Bisharp without it does not")

-- ------- the plain level-ups and Kubfu's scrolls

local function plain(from, to, level)
  T.eq(up(from, level), slot(to), from .. " becomes " .. to .. " at " .. level)
  T.eq(up(from, level - 1), nil, "and not at " .. (level - 1))
end
plain("STANTLER", "WYRDEER", 31)
plain("MELTAN", "MELMETAL", 40)
plain("KARRABLAST", "ESCAVALIER", 37)
plain("SHELMET", "ACCELGOR", 37)
plain("TOXEL", "TOXTRICITY", 30)
plain("TANDEMAUS", "MAUSHOLD", 25)
plain("INKAY", "MALAMAR", 30)
plain("FINIZEN", "PALAFIN", 38)
plain("QWILFISH_HISUI", "OVERQWIL", 28)
T.eq(up("QWILFISH", 40), nil, "the normal Qwilfish never evolves")

do
  local function scroll(item)
    return Evolution.itemTarget({ species = slot("KUBFU"), level = 30, personality = 0 }, items:get(item).index)
  end
  T.eq(scroll("SCROLL_OF_DARKNESS"), slot("URSHIFU"), "a Scroll of Darkness makes Kubfu a Single Strike Urshifu")
  T.eq(scroll("SCROLL_OF_WATERS"), slot("URSHIFU_RAPID_STRIKE"), "a Scroll of Waters a Rapid Strike Urshifu")
end

T.finish("national_dex_gen3 known move")
