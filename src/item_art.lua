-- Bag icons for the items src/items.lua registers. No hook offers this
-- (unlike species pics, which Gen3Compat wraps as "pokemon.sprite", items
-- have nothing equivalent), so this wraps the Bag's own icon draw directly:
--   src.ui.game3.bag_chrome      FireRed / LeafGreen
--   src.ui.game3.rse.bag_chrome  Ruby / Sapphire / Emerald
-- Both read a RAW NUMERIC item id (what storage.items[i].id actually holds,
-- and what every call site already has); neither needs this mod's string
-- ids. An id this mod didn't register falls straight through to the
-- original function, so every vanilla and companion-mod item is untouched.
--
-- assets/items/icons.png + data/item_icons.lua are built by
-- tools/build_items.py from the third-party pokesprite pack; an item ORDER
-- lists but the pack had no art for simply has no cell and keeps whatever
-- the game already draws for an unknown id (nothing, same as before this
-- mod existed).

local ItemArt = {}

local ours = setmetatable({}, { __mode = "k" })

-- mod: for mod.path (asset loading) and mod.log; load: loadSibling-style reader
local function loadAtlas(mod, load)
  local data = load("data/item_icons.lua")
  if type(data) ~= "table" or type(data.cells) ~= "table" then return nil end
  local size = tonumber(data.size) or 24
  local pageFailed = false
  local page
  local function pageImage()
    if page then return page end
    if pageFailed then return nil end
    local ok, img = pcall(love.graphics.newImage, mod.path .. "/assets/items/icons.png")
    if ok and img then
      page = img
      return page
    end
    pageFailed = true
    if mod.log then
      mod.log:warn("could not load assets/items/icons.png: %s", tostring(img))
    end
    return nil
  end
  local quads = {}
  local function quadFor(index)
    local cell = data.cells[index]
    if not cell then return nil end
    local img = pageImage()
    if not img then return nil end
    local q = quads[index]
    if not q then
      q = love.graphics.newQuad(cell.x, cell.y, size, size, img:getDimensions())
      quads[index] = q
    end
    return img, q
  end
  return { quadFor = quadFor, size = size }
end

-- Wraps FireRed/LeafGreen's src.ui.game3.bag_chrome: drawItemIcon(itemId, px, py, scale)
local function installFrlg(atlas)
  local ok, BagChrome = pcall(require, "src.ui.game3.bag_chrome")
  if not (ok and type(BagChrome) == "table" and type(BagChrome.drawItemIcon) == "function")
    or ours[BagChrome.drawItemIcon] then
    return false
  end
  local orig = BagChrome.drawItemIcon
  BagChrome.drawItemIcon = function(itemId, px, py, scale)
    local img, quad = atlas.quadFor(tonumber(itemId))
    if img then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, quad, px or 0, py or 0, 0, scale or 1, scale or 1)
      return true
    end
    return orig(itemId, px, py, scale)
  end
  ours[BagChrome.drawItemIcon] = true
  return true
end

-- Wraps Ruby/Sapphire/Emerald's src.ui.game3.rse.bag_chrome:
-- drawItemIcon(index, x, y, rotation, ox, oy)
local function installRse(atlas)
  local ok, BagChrome = pcall(require, "src.ui.game3.rse.bag_chrome")
  if not (ok and type(BagChrome) == "table" and type(BagChrome.drawItemIcon) == "function")
    or ours[BagChrome.drawItemIcon] then
    return false
  end
  local orig = BagChrome.drawItemIcon
  BagChrome.drawItemIcon = function(index, x, y, rotation, ox, oy)
    local img, quad = atlas.quadFor(tonumber(index))
    if img then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, quad, x, y, rotation or 0, 1, 1, ox or 0, oy or 0)
      return
    end
    return orig(index, x, y, rotation, ox, oy)
  end
  ours[BagChrome.drawItemIcon] = true
  return true
end

-- Installs over whichever Bag chrome module(s) this boot has loaded. Safe to
-- call more than once: an already-wrapped function is left alone. Returns
-- how many of the two it reached.
function ItemArt.install(mod, load)
  local atlas = loadAtlas(mod, load)
  if not atlas then return 0 end
  local n = 0
  if installFrlg(atlas) then n = n + 1 end
  if installRse(atlas) then n = n + 1 end
  return n
end

return ItemArt
