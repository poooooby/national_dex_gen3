-- Cries for species #387-1025. The engine plays a cry through one function,
-- src.core.game3.audio's Audio.playCry(species, mode, pan), which looks the
-- species up in the cart's own cry table (a new slot has none, so it is
-- silent). No hook offers a way in, so this wraps playCry directly; a slot
-- this mod has no cry for falls through to the original untouched.
--
-- assets/cries/cries.pak holds every Ogg back to back and data/cries.lua
-- says where each sits (tools/build_cries.py). The pak is read once, on the
-- first new-species cry; a cry is sliced out, decoded, and kept (bounded).
-- Not reproduced from the original: the cart's pitch/pan modes and the
-- music duck while a cry plays.

local CryArt = {}

local CACHE_CAP = 64
local ours = setmetatable({}, { __mode = "k" })

local function loadPack(mod, load)
  local index = load("data/cries.lua")
  if type(index) ~= "table" then return nil end
  local pak, failed
  local function bytes()
    if pak then return pak end
    if failed then return nil end
    local ok, data = pcall(function() return mod:read("assets/cries/cries.pak") end)
    if ok and type(data) == "string" and #data > 4 and data:sub(1, 4) == "OggS" then
      pak = data
      return pak
    end
    failed = true
    if mod.log then
      mod.log:warn("could not read assets/cries/cries.pak (%s) -- species #387-1025 stay silent",
        ok and "not an Ogg file" or tostring(data))
    end
    return nil
  end
  local cache, order, decodeFailed = {}, {}, false
  local function sound(slot)
    local hit = cache[slot]
    if hit then return hit end
    local row = index[slot]
    local all = row and bytes()
    if not all then return nil end
    local ok, sd = pcall(function()
      local fd = love.filesystem.newFileData(all:sub(row[1] + 1, row[1] + row[2]), "cry.ogg")
      return love.sound.newSoundData(fd)
    end)
    if not ok then
      if not decodeFailed and mod.log then
        decodeFailed = true
        mod.log:warn("could not decode a cry (%s) -- species #387-1025 stay silent", tostring(sd))
      end
      return nil
    end
    cache[slot] = sd
    order[#order + 1] = slot
    if #order > CACHE_CAP then cache[table.remove(order, 1)] = nil end
    return sd
  end
  return { sound = sound, has = function(slot) return index[slot] ~= nil end }
end

-- Installs over Audio.playCry. Safe to repeat. Returns true when wrapped.
-- aliases: { [form slot] = cart species slot } for forms of the cart's own species, which
-- have no cry in the pack and play their base's through the original function.
function CryArt.install(mod, load, aliases)
  aliases = aliases or {}
  local ok, Audio = pcall(require, "src.core.game3.audio")
  if not (ok and type(Audio) == "table" and type(Audio.playCry) == "function")
    or ours[Audio.playCry] then
    return false
  end
  local pack = loadPack(mod, load)
  if not pack then return false end
  local orig = Audio.playCry
  Audio.playCry = function(species, mode, pan)
    local slot = tonumber(species)
    if slot and pack.has(slot) then
      local sd = pack.sound(slot)
      if sd and love and love.audio then
        if type(Audio.stopCry) == "function" then Audio.stopCry() end
        local src = love.audio.newSource(sd, "static")
        src:setVolume(Audio._sfxVolume or 1)
        src:play()
        Audio._crySource = src
        Audio._cryUntil = (Audio._cryClock or 0) + sd:getDuration() * 60
        return true
      end
    end
    return orig(aliases[slot or -1] or species, mode, pan)
  end
  ours[Audio.playCry] = true
  return true
end

return CryArt
