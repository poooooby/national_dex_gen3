-- Standalone: luajit mods/national_dex_gen3/tests/clock_test.lua
-- (from the gen1recomp root; needs Pokemon FireRed imported under firered/).
--
-- Which clock the time-of-day rules read (src/clock.lua, options.lua): the
-- device's on a cart with no clock (FireRed, LeafGreen), and on a cart with one
-- (Ruby, Sapphire, Emerald) whichever the player picked -- the in-game clock by
-- default. Also the friendship day/night evolutions, which follow that clock.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")

local data = H.gen3Data()
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.events:emit("game.ready", {})

local api = run.loader.exports.national_dex_gen3
local Evolution = require("src.core.game3.evolution")
local Rtc = require("src.core.game3.rtc")
local Clock = dofile("mods/national_dex_gen3/src/clock.lua")

-- ------- the option

local schema = run.loader.optionSchemas.national_dex_gen3
T.check(type(schema) == "table" and schema[1] and schema[1].key == "clock_source",
        "the mod defines a clock_source option")
T.check(#schema[1].label <= 14, "its label fits the Mod Manager (14 characters)")
T.eq(schema[1].default, "game", "which defaults to the in-game clock")
local function setSource(value) run.loader.modOptions.national_dex_gen3 = { clock_source = value } end

-- ------- Clock: which clock answers

local function withClock(cart, device, fn)
  local enabled, calc, host = Rtc.enabled, Rtc.calcLocalTime, Rtc.hostInfo
  Rtc.enabled = function() return cart ~= nil end
  Rtc.calcLocalTime = function() return { hours = cart or 0 } end
  Rtc.hostInfo = function() return { hour = device } end
  local ok, result = pcall(fn)
  Rtc.enabled, Rtc.calcLocalTime, Rtc.hostInfo = enabled, calc, host
  assert(ok, result)
  return result
end

T.eq(withClock(nil, 9, function() return Clock.hours({}, "game") end), 9,
     "no cart clock (FireRed/LeafGreen): the device clock, even when asked for the game's")
T.eq(withClock(nil, 9, function() return Clock.hours({}, "device") end), 9, "and when asked for the device's")
T.eq(withClock(14, 9, function() return Clock.hours({}, "game") end), 14, "cart clock, game source: the in-game hour")
T.eq(withClock(14, 9, function() return Clock.hours({}, nil) end), 14, "an unset source means the game's")
T.eq(withClock(14, 9, function() return Clock.hours({}, "device") end), 9, "cart clock, device source: the device hour")

local function night(h) return withClock(nil, h, function() return Clock.isNight({}, "device") end) end
T.check(not night(19), "19:00 is day")
T.check(night(20), "20:00 is night")
T.check(night(23) and night(0) and night(3), "late evening to 03:59 is night")
T.check(not night(4), "04:00 is day")

local function dusk(h) return withClock(nil, h, function() return Clock.isDusk({}, "device") end) end
T.check(not dusk(18) and dusk(19) and not dusk(20), "dusk is 19:00 to 20:00")
T.check(not dusk(3), "and not the small hours")

local hostInfo = Rtc.hostInfo
Rtc.hostInfo = nil
local fallback = Clock.deviceHour()
Rtc.hostInfo = hostInfo
T.eq(fallback, tonumber(os.date("*t").hour), "without Rtc.hostInfo it falls back to os.date")

-- ------- the friendship evolutions follow the clock

Evolution.nationalAllows = function() return true end

-- cart: the in-game hour (nil on FireRed/LeafGreen); device: the device hour
local function friends(species, friendship, cart, device)
  return withClock(cart, device, function()
    return Evolution.levelTarget({ species = api.slotOf(species), level = 20, friendship = friendship }, {})
  end)
end

T.check(friends("BUDEW", 220, nil, 12) ~= nil, "Budew evolves by day at friendship 220 (FireRed/LeafGreen, device clock)")
T.eq(friends("BUDEW", 220, nil, 22), nil, "but not at night")
T.eq(friends("BUDEW", 219, nil, 12), nil, "and not at friendship 219")
T.check(friends("RIOLU", 255, nil, 9) ~= nil, "Riolu evolves in the morning, which the engine's own rule called night")
T.eq(friends("RIOLU", 255, nil, 21), nil, "and not at night")
T.check(friends("CHINGLING", 220, nil, 21) ~= nil, "Chingling evolves at night")
T.eq(friends("CHINGLING", 220, nil, 12), nil, "but not by day")
T.check(friends("SNOM", 220, nil, 3) ~= nil, "Snom evolves at night")
T.eq(friends("SNOM", 220, nil, 15), nil, "but not by day")

T.check(friends("BUDEW", 220, 12, 23) ~= nil, "Emerald, in-game clock: the cart's noon, not the device's night")
T.eq(friends("BUDEW", 220, 23, 12), nil, "and the cart's night, not the device's noon")
setSource("device")
T.check(friends("BUDEW", 220, 23, 12) ~= nil, "Emerald, device clock: the device's noon")
T.eq(friends("BUDEW", 220, 12, 23), nil, "and not the cart's")
T.check(friends("CHINGLING", 220, 12, 22) ~= nil, "Chingling follows the device's night")
setSource("game")

-- the cart's own Eevee has the same rows
local eevee = Evolution and require("src.core.game3.pokemon").speciesFromName("EEVEE")
if eevee and #(data.gen3Pokemon._evolutions[eevee] or {}) > 0 then
  local function eve(device)
    return withClock(nil, device, function()
      return Evolution.levelTarget({ species = eevee, level = 20, friendship = 255 }, {})
    end)
  end
  local dayRow = false
  for _, row in ipairs(data.gen3Pokemon._evolutions[eevee]) do if row.method == 2 then dayRow = true end end
  if dayRow then
    T.check(eve(12) ~= nil and eve(22) ~= nil and eve(12) ~= eve(22),
            "Eevee: one form by day, another by night")
  end
end

T.finish("national_dex_gen3 clock")
