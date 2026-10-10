-- Pokedex art: every species' dex picture from this mod's own atlas, animated.
--
-- assets/dex/dex_<n>.png + data/dex_atlas_index.lua are built by tools/build_dex_atlas.py from
-- pokeemerald-expansion's front sprites: a 64x64 cell per frame, two frames where the sprite has
-- two. Both Pokedex screens ask the engine for a "dex" front picture -- FireRed/LeafGreen through
-- Pokemon.dexFrontPic, Ruby/Sapphire/Emerald by calling Pokemon.frontPic with kind "dex" -- and
-- dexFrontPic itself goes through frontPic, so wrapping frontPic (only for kind "dex") covers
-- both. Installed at game.ready, so it sits outside a battle-sprite mod's own frontPic wrap and
-- its battle frames no longer end up in the Pokedex; battle pictures are untouched.
--
-- The answer is { image = canvas, w = 64, h = 64 }: one 64x64 canvas per species, redrawn when
-- its frame changes. Emerald keeps the image it was handed for as long as the entry is open, so
-- the canvas has to change in place; tick() is called every update by both screens (wrapped
-- below). A species with no cell (Spinda, whose spots depend on the Pokemon; anything the atlas
-- lacks) falls through to the next answer.

local DexArt = {}

DexArt.FRAME_SECONDS = 0.5   -- each animation frame stays this long
DexArt.CANVAS_CAP = 48       -- most canvases kept at once, least recently used dropped first
DexArt.SPINDA = 327

local function now()
  local ok, t = pcall(function() return love.timer.getTime() end)
  if ok and type(t) == "number" then return t end
  return os.clock()
end

-- Which frame of `frames` shows at time `t`. Pure.
function DexArt.frameAt(t, frames)
  frames = tonumber(frames) or 1
  if frames <= 1 then return 0 end
  return math.floor((t or 0) / DexArt.FRAME_SECONDS) % frames
end

-- opts:
--   index       data/dex_atlas_index.lua
--   sheet(n)    -> the Image of sheet n, or nil
--   newCanvas() -> a 64x64 canvas (tests pass a stand-in)
--   render(canvas, sheetImage, quad) draws one cell into a canvas
--   newQuad(x, y, w, h, sheetImage)
--   clock()     seconds
function DexArt.new(opts)
  local index = opts.index or {}
  local entries = index.entries or {}
  local cell, perRow = index.cell or 64, index.perRow or 32
  local clock = opts.clock or now
  local live, order = {}, {}
  local quads = {}

  local function quad(sheet, n, img)
    local key = sheet .. ":" .. n
    if not quads[key] then
      local row, col = math.floor(n / perRow), n % perRow
      quads[key] = opts.newQuad(col * cell, row * cell, cell, cell, img)
    end
    return quads[key]
  end

  local function touch(key)
    for i, k in ipairs(order) do
      if k == key then table.remove(order, i) break end
    end
    order[#order + 1] = key
    while #order > DexArt.CANVAS_CAP do
      local old = table.remove(order, 1)
      live[old] = nil
    end
  end

  local function draw(key, held, frame)
    local e = entries[key]
    local img = opts.sheet(e.sheet)
    if not img then return false end
    opts.render(held.entry.image, img, quad(e.sheet, e.cell + frame, img))
    held.frame = frame
    return true
  end

  local art = {}

  -- The picture for an atlas key (a National Dex number, or a form id), or nil.
  function art.entry(key)
    local e = key ~= nil and entries[key]
    if not e then return nil end
    local held = live[key]
    if not held then
      local canvas = opts.newCanvas()
      if not canvas then return nil end
      held = { entry = { image = canvas, w = cell, h = cell, dexArt = key } }
      if not draw(key, held, DexArt.frameAt(clock(), e.frames)) then return nil end
      live[key] = held
    else
      local frame = DexArt.frameAt(clock(), e.frames)
      if frame ~= held.frame then draw(key, held, frame) end
    end
    touch(key)
    return held.entry
  end

  -- Advance every live picture to the current frame.
  function art.tick()
    local t = clock()
    for key, held in pairs(live) do
      local frame = DexArt.frameAt(t, entries[key].frames)
      if frame ~= held.frame then draw(key, held, frame) end
    end
  end

  function art.has(key) return entries[key] ~= nil end
  function art.liveCount() local n = 0 for _ in pairs(live) do n = n + 1 end return n end
  return art
end

-- The atlas key for a species slot: a form this mod registers answers by its id, everything else
-- by its National Dex number. nil for Spinda and for anything unknown.
function DexArt.keyResolver(formIdBySlot, national)
  return function(slot)
    slot = tonumber(slot)
    if not slot then return nil end
    if formIdBySlot[slot] then return formIdBySlot[slot] end
    local ok, n = pcall(national, slot)
    n = ok and tonumber(n) or nil
    if not n or n == DexArt.SPINDA then return nil end
    return n
  end
end

-- The LOVE side of DexArt.new: sheets loaded once each from assets/dex/.
function DexArt.loveOptions(modPath, index, log)
  local sheets, failed = {}, {}
  return {
    index = index,
    sheet = function(n)
      if sheets[n] then return sheets[n] end
      if failed[n] then return nil end
      local ok, img = pcall(love.graphics.newImage, modPath .. "/assets/dex/dex_" .. n .. ".png")
      if ok and img then
        pcall(img.setFilter, img, "nearest", "nearest")
        sheets[n] = img
        return img
      end
      failed[n] = true
      if log and log.warn then log:warn("could not load assets/dex/dex_%d.png: %s", n, tostring(img)) end
      return nil
    end,
    newCanvas = function()
      local ok, c = pcall(love.graphics.newCanvas, index.cell or 64, index.cell or 64)
      if not ok then return nil end
      pcall(c.setFilter, c, "nearest", "nearest")
      return c
    end,
    newQuad = function(x, y, w, h, img)
      return love.graphics.newQuad(x, y, w, h, img:getDimensions())
    end,
    render = function(canvas, img, q)
      love.graphics.push("all")
      love.graphics.setCanvas(canvas)
      love.graphics.origin()
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, q, 0, 0)
      love.graphics.pop()
    end,
  }
end

-- Wraps Pokemon.frontPic (kind "dex" only) and both screens' update, once per module table
-- (engine modules outlive a mod reload); `state.art` / `state.keyOf` are read at call time, so a
-- reload re-points them.
function DexArt.install(state, require)
  require = require or _G.require
  local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
  if okP and type(Pokemon) == "table" and type(Pokemon.frontPic) == "function" then
    Pokemon.__nationalDexArt = state
    if not Pokemon.__nationalDexArtWrapped then
      Pokemon.__nationalDexArtWrapped = true
      local original = Pokemon.frontPic
      Pokemon.frontPic = function(species, form, shiny, personality, kind, ...)
        if kind == "dex" then
          local st = Pokemon.__nationalDexArt
          local ok, entry = pcall(function()
            return st.art.entry(st.keyOf(species))
          end)
          if ok and entry then return entry end
        end
        return original(species, form, shiny, personality, kind, ...)
      end
    end
  end
  local function tickOn(module, name)
    if type(module) ~= "table" or type(module[name]) ~= "function" then return end
    module.__nationalDexArtTick = module.__nationalDexArtTick or {}
    if module.__nationalDexArtTick[name] then return end
    module.__nationalDexArtTick[name] = true
    local original = module[name]
    module[name] = function(...)
      local st = okP and Pokemon.__nationalDexArt
      if st then pcall(st.art.tick) end
      return original(...)
    end
  end
  local okF, frlg = pcall(require, "src.ui.game3.pokedex")
  if okF then tickOn(frlg, "update") end
  local okR, rse = pcall(require, "src.ui.game3.rse.pokedex")
  if okR and type(rse) == "table" then tickOn(rse.Host, "update") end
end

return DexArt
