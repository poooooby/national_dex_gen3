-- Pictures, party icons and cries on Gen 1 / Gen 2.
--
-- Pictures: a species no sprite mod draws keeps the placeholder (src/gen12/project.lua). A sprite
-- mod draws through setArtProvider, the same call as on Gen 3:
--   provider(speciesId, side, slot, shiny, kind) -> PNG path or nil
-- (slot is the Gen 3 slot, dex + 64 / forms 1090+), asked from the pokemon.sprite hook, which
-- both games resolve every Pokemon picture through. An answer is drawn in its own colours
-- (ctx.trueColor), not the game's four shades.
-- Icons: each species gets its proxy's party icon (data `icon`: Red's icon kind, Gold's ICON_
-- sheet), through the `icons` registry.
-- Cries: each species gets its proxy's cry as a registered cry ({ base = proxy }), so every screen
-- that only plays a cry when the game has one plays it. Species #387-1025 and their forms have
-- their own cry in assets/cries/cries.pak (the Gen 3 path's, data/cries.lua, by slot); a wrap of
-- Sound.playCry plays that one instead. The wrap is process-wide (Sound is never reloaded and
-- the player may switch games in one run) and asks the current load's handler, which only
-- answers for this mod's species.

local Art = {}

Art.CACHE_CAP = 32

-- At load. opts: { mod, generation, species = Species state, log }
function Art.register(opts)
  local mod, key, log = opts.mod, "gen" .. opts.generation, opts.log
  local icons, cries = mod.content.icons, mod.content.cries
  local counts = { icons = 0, cries = 0 }
  for id, entry in pairs(opts.species.byId) do
    local r = entry.data
    local icon = r.icon and r.icon[key]
    if icon and icons and icons:get(id) == nil then
      if pcall(icons.register, icons, id, icon) then counts.icons = counts.icons + 1 end
    end
    local proxy = r.proxy and r.proxy[key]
    if proxy and cries and cries:get(id) == nil and cries:get(proxy) ~= nil then
      if pcall(cries.register, cries, id, { base = proxy }) then counts.cries = counts.cries + 1 end
    end
  end
  return counts
end

-- The sprite providers (setArtProvider). Returns { add, count }.
function Art.installPictures(mod, species)
  local byId = species.byId
  local providers = {}
  mod.hooks:wrap("pokemon.sprite", function(nextFn, path, ctx)
    local out = nextFn(path, ctx)
    local entry = type(ctx) == "table" and byId[ctx.species]
    if not entry or #providers == 0 then return out end
    for _, provider in ipairs(providers) do
      local ok, result = pcall(provider, entry.id, ctx.side, entry.data.slot, ctx.shiny == true, ctx.kind)
      if ok and type(result) == "string" and result ~= "" then
        ctx.trueColor = true
        return result
      end
    end
    return out
  end)
  return {
    add = function(fn)
      if type(fn) ~= "function" then return false end
      providers[#providers + 1] = fn
      return true
    end,
    count = function() return #providers end,
  }
end

-- The cries in cries.pak, by slot: { has(slot), sound(slot) -> SoundData or nil }
function Art.pack(mod, index, log)
  local pak, failed, decodeFailed = nil, false, false
  local cache, order = {}, {}
  local function bytes()
    if pak or failed then return pak end
    local ok, data = pcall(function() return mod:read("assets/cries/cries.pak") end)
    if ok and type(data) == "string" and data:sub(1, 4) == "OggS" then pak = data
    else
      failed = true
      if log then log:warn("could not read assets/cries/cries.pak: the new species borrow cries") end
    end
    return pak
  end
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
      if not decodeFailed and log then
        decodeFailed = true
        log:warn("could not decode a cry (%s): the new species borrow cries", tostring(sd))
      end
      return nil
    end
    cache[slot] = sd
    order[#order + 1] = slot
    if #order > Art.CACHE_CAP then cache[table.remove(order, 1)] = nil end
    return sd
  end
  return { has = function(slot) return index[slot] ~= nil end, sound = sound }
end

-- The process-wide wrap over Sound.playCry; this load's handler plays our species' own cries.
function Art.installCries(opts)
  local req, species = opts.require or require, opts.species
  local ok, Sound = pcall(req, "src.core.Sound")
  if not (ok and type(Sound) == "table" and type(Sound.playCry) == "function") then return false end
  local hook = Sound.__ndxGen12Cry
  if not hook then
    hook = { orig = Sound.playCry, origVolume = Sound.setVolumeLevel, scale = 1 }
    Sound.__ndxGen12Cry = hook
    Sound.playCry = function(data, sp, pikaClip)
      local handler = hook.handler
      if handler then
        local okH, src = pcall(handler, data, sp)
        if okH and src then return src end
      end
      return hook.orig(data, sp, pikaClip)
    end
    if type(hook.origVolume) == "function" then
      Sound.setVolumeLevel = function(level, ...)
        hook.scale = math.max(0, math.min(7, level or 7)) / 7
        return hook.origVolume(level, ...)
      end
    end
  end
  local pack = Art.pack(opts.mod, opts.index or {}, opts.log)
  local byId = species.byId
  hook.handler = function(_, sp)
    local entry = byId[sp]
    local slot = entry and entry.data.slot
    if not (slot and pack.has(slot) and love and love.audio) then return nil end
    local sd = pack.sound(slot)
    if not sd then return nil end
    if hook.playing then pcall(hook.playing.stop, hook.playing) end
    local src = love.audio.newSource(sd, "static")
    src:setVolume(0.8 * hook.scale)
    src:play()
    hook.playing = src
    return src
  end
  return true
end

return Art
