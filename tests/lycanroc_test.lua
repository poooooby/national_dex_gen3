-- Standalone: luajit mods/national_dex_gen3/tests/lycanroc_test.lua
-- (from the gen1recomp root; needs Pokemon FireRed imported under firered/).
--
-- Rockruff -> Lycanroc at level 25 picks Midday, Midnight or Dusk from the
-- clock and the held item (src/conditional_evos.lua). The clock is stubbed:
-- FireRed has none, which is itself a case under test.
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

local rockruff = api.slotOf("ROCKRUFF")
local midday, midnight, dusk = api.slotOf("LYCANROC"), api.slotOf("LYCANROC_MIDNIGHT"),
  api.slotOf("LYCANROC_DUSK")
local items = run.loader.content.items

-- Run fn with the clocks stubbed. cart: the in-game hour on a cart that has a clock
-- (Ruby/Sapphire/Emerald), nil on one that has none (FireRed/LeafGreen); device: the
-- hour of the device clock (default noon).
local function withClock(cart, device, fn)
  local enabled, calc, host = Rtc.enabled, Rtc.calcLocalTime, Rtc.hostInfo
  Rtc.enabled = function() return cart ~= nil end
  Rtc.calcLocalTime = function() return { hours = cart or 0 } end
  Rtc.hostInfo = function() return { hour = device or 12 } end
  local ok, result = pcall(fn)
  Rtc.enabled, Rtc.calcLocalTime, Rtc.hostInfo = enabled, calc, host
  assert(ok, result)
  return result
end

-- the Pokedex gate (National Dex not yet unlocked) is not what is under test
Evolution.nationalAllows = function() return true end

-- hours: the in-game clock on a cart that has one (nil = FireRed/LeafGreen, device at noon)
local function evolve(level, held, hours, device)
  return withClock(hours, device, function()
    return Evolution.levelTarget({ species = rockruff, level = level, item = held }, {})
  end)
end

T.eq(#(data.gen3Pokemon._evolutions[rockruff]), 3, "Rockruff has one level row per outcome")
T.eq(evolve(24, nil, 12), nil, "not before level 25")
T.eq(evolve(25, nil, 12), midday, "midday by day")
T.eq(evolve(25, nil, 18), midday, "still midday at 18:00")
T.eq(evolve(25, nil, 19), dusk, "dusk from 19:00")
T.eq(evolve(25, nil, 20), midnight, "midnight from 20:00, where dusk ends")
T.eq(evolve(25, nil, 3), midnight, "and until 04:00")
T.eq(evolve(25, nil, 4), midday, "midday again at 04:00")
T.eq(evolve(25, nil, nil), midday, "no cart clock (FireRed, LeafGreen), device at noon: midday")
T.eq(evolve(25, nil, nil, 22), midnight, "FireRed/LeafGreen use the device clock: midnight at 22:00")
T.eq(evolve(25, nil, nil, 3), midnight, "and at 03:00")
T.eq(evolve(25, nil, nil, 4), midday, "midday at 04:00")
T.eq(evolve(25, nil, 12, 23), midday, "Emerald's default is the in-game clock, not the device's")
T.eq(evolve(25, nil, nil, 19), dusk, "FireRed/LeafGreen: dusk on the device clock at 19:00")
T.eq(evolve(25, nil, nil, 20), midnight, "and midnight at 20:00")
T.eq(evolve(25, nil, 12, 19), midday, "Emerald's in-game noon beats the device's dusk")
T.eq(evolve(25, 106, 12), midday, "no held item matters now (a Dusk Stone does nothing by day)")
T.eq(evolve(25, 106, 19), dusk, "and none is needed for dusk")
T.eq(evolve(40, nil, 22), midnight, "a higher level still evolves")

-- ------- Milcery -> Alcremie: a cream by day or night from a held sweet

local milcery = api.slotOf("MILCERY")
local function creamSlot(id) return api.slotOf(id) end
local day = { creamSlot("ALCREMIE"), creamSlot("ALCREMIE_RUBY_CREAM"),
              creamSlot("ALCREMIE_MATCHA_CREAM"), creamSlot("ALCREMIE_MINT_CREAM") }
local night = { creamSlot("ALCREMIE_LEMON_CREAM"), creamSlot("ALCREMIE_SALTED_CREAM"),
                creamSlot("ALCREMIE_RUBY_SWIRL"), creamSlot("ALCREMIE_CARAMEL_SWIRL") }
local rainbow = creamSlot("ALCREMIE_RAINBOW_SWIRL")
local sweet = items:get("STRAWBERRY_SWEET").index
local otherSweet = items:get("RIBBON_SWEET").index

local function milk(held, hours, bucket, friendship, level, device)
  return withClock(hours, device, function()
    return Evolution.levelTarget({ species = milcery, level = level or 25, item = held,
      personality = bucket * 65536 + 12345, friendship = friendship or 70 }, {})
  end)
end

T.eq(#(data.gen3Pokemon._evolutions[milcery]), 9, "Milcery has one level row per outcome")
T.eq(milk(nil, 12, 0), nil, "no sweet, no evolution")
T.eq(milk(sweet, 12, 0, 70, 24), nil, "and not before level 25")
for bucket = 0, 3 do
  T.eq(milk(sweet, 12, bucket), day[bucket + 1], "by day, bucket " .. bucket .. " is cream " .. bucket)
  T.eq(milk(sweet, 22, bucket), night[bucket + 1], "at night, bucket " .. bucket)
  T.eq(milk(otherSweet, 3, bucket), night[bucket + 1], "any sweet works, and 03:00 is still night")
end
T.eq(milk(sweet, nil, 2), day[3], "no cart clock, device at noon: the day creams")
T.eq(milk(sweet, nil, 2, 70, 25, 22), night[3], "FireRed/LeafGreen use the device clock: a night cream at 22:00")
T.eq(milk(sweet, 19, 1), rainbow, "at dusk (19:00): Rainbow Swirl")
T.eq(milk(sweet, 19, 3, 0), rainbow, "whatever the friendship")
T.eq(milk(sweet, nil, 0, 70, 25, 19), rainbow, "and on the device clock")
T.eq(milk(sweet, 12, 1, 255), day[2], "max friendship by day changes nothing: a day cream")
T.eq(milk(sweet, 18, 1, 255), day[2], "nor at 18:00")
T.eq(milk(sweet, 23, 3, 255), night[4], "nor at night")
T.eq(milk(sweet, 20, 3), night[4], "dusk ends at 20:00")
T.eq(milk(nil, 19, 1), nil, "dusk without a sweet: nothing")
T.eq(milk(sweet, 19, 1, 70, 24), nil, "and not before level 25")

T.finish("national_dex_gen3 lycanroc")
