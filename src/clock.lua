-- The one place this mod reads a clock: which hour it is for the time-of-day
-- rules (Midnight Lycanroc, the day and night Alcremie creams, the friendship
-- day/night evolutions).
--
-- Two sources:
--   "device"  the real-world time of the machine (Rtc.hostInfo(nil): os.date,
--             plus the engine's test overrides such as POKEPORT_RTC)
--   "game"    the cart's own clock (Rtc.calcLocalTime), which is the device time
--             shifted by whatever the player set in-game. Only Ruby, Sapphire and
--             Emerald have one (Rtc.enabled); on FireRed and LeafGreen a "game"
--             request falls back to the device clock, so those games always use it.
-- Night is 20:00-04:00 and day is every other hour; dusk is the hour 19:00-20:00
-- (part of the day, the last hour before night).

local Clock = {}

local NIGHT_BEGIN, NIGHT_END = 20, 4
local DUSK_BEGIN = 19

local function rtc()
  local ok, Rtc = pcall(require, "src.core.game3.rtc")
  return ok and type(Rtc) == "table" and Rtc or nil
end

function Clock.deviceHour()
  local Rtc = rtc()
  if Rtc and type(Rtc.hostInfo) == "function" then
    local ok, info = pcall(Rtc.hostInfo, nil)
    if ok and type(info) == "table" and tonumber(info.hour) then return tonumber(info.hour) end
  end
  return tonumber(os.date("*t").hour)
end

-- 0-23. source: "game" (also nil) or "device".
function Clock.hours(session, source)
  if source ~= "device" then
    local Rtc = rtc()
    if Rtc and Rtc.enabled(session) then
      local hours = tonumber(Rtc.calcLocalTime(session).hours)
      if hours then return hours end
    end
  end
  return Clock.deviceHour()
end

function Clock.isNight(session, source)
  local hours = Clock.hours(session, source)
  return hours >= NIGHT_BEGIN or hours < NIGHT_END
end

function Clock.isDusk(session, source)
  local hours = Clock.hours(session, source)
  return hours >= DUSK_BEGIN and hours < NIGHT_BEGIN
end

return Clock
