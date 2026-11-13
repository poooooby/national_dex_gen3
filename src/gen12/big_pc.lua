-- The "Bigger PC" option on Gen 1 / Gen 2: 40 PC boxes (800 Pokemon) instead of Red's 12 /
-- Gold's 14, as on Gen 3.
--
-- The count is one module field each game reads live: Red's Boxes.COUNT (src.pokemon.Boxes:
-- CHANGE BOX, catching's overflow into the next box), Gold's Boxes.NUM_BOXES (src.core.gen2.Boxes:
-- the PC's box list, which already scrolls, the box screens, catching). Red's CHANGE BOX list is a
-- fixed 12-row box, so with more boxes this mod's own copy of it scrolls (BoxMenu.new is wrapped
-- to hand the CHANGE BOX row to it). Red's Boxes.ensure is wrapped to make the extra boxes of an
-- older save (it only fills a save that has none).
--
-- Where the extra boxes are saved: NOT in the save's own box list. The save writer (Red's
-- SaveData.save, Gold's Save.save; every write goes through them) is wrapped: for the write only,
-- the boxes past the cart's count (and Gold's names for them) move into this mod's save data,
-- save.modData.national_dex_gen3.pc = { boxes = { [13] = box, ... }, names, currentBox }, and the
-- current box is box 1 if it was one of them; then everything is put back. So the file is always
-- a normal 12 / 14-box save: removing the mod, turning the option off or exporting a .sav never
-- loses them, and they come back when the mod and the option are on again. On load (save.loading,
-- the raw save) they are moved back into the box list.
-- Turning the option off in the menu moves them into the save data at once; on brings them back.

local BigPc = {}

BigPc.COUNT = 40
BigPc.BASE = { [1] = 12, [2] = 14 }
local KEY = "national_dex_gen3"

local unpack = table.unpack or unpack
local function pack(...) return { n = select("#", ...), ... } end

local function nonEmpty(t) return type(t) == "table" and next(t) ~= nil end

local function bucketOf(save, make)
  local md = save.modData
  if type(md) ~= "table" then
    if not make then return nil end
    md = {}
    save.modData = md
  end
  local b = md[KEY]
  if type(b) ~= "table" then
    if not make then return nil end
    b = {}
    md[KEY] = b
  end
  return b
end

-- Boxes past `base` (and their names) out of `save` into the save data. Returns what to hand to
-- BigPc.unsplit to undo it exactly.
function BigPc.split(save, base)
  local undo = { boxes = {}, names = {}, hadModData = save.modData ~= nil }
  if type(save.boxes) ~= "table" then return undo end
  local md = save.modData
  undo.hadBucket = type(md) == "table" and md[KEY] ~= nil
  local bucket = bucketOf(save, true)
  undo.pc = bucket.pc
  local pc = { boxes = {}, names = {} }
  local old = type(bucket.pc) == "table" and bucket.pc or {}
  for k, v in pairs(old.boxes or {}) do pc.boxes[k] = v end
  for k, v in pairs(old.names or {}) do pc.names[k] = v end
  pc.currentBox = old.currentBox
  for b, box in pairs(save.boxes) do
    local n = tonumber(b)
    if n and n > base then
      undo.boxes[b] = box
      if nonEmpty(box) then pc.boxes[n] = box else pc.boxes[n] = nil end
    end
  end
  for b in pairs(undo.boxes) do save.boxes[b] = nil end
  if type(save.boxNames) == "table" then
    for b, name in pairs(save.boxNames) do
      local n = tonumber(b)
      if n and n > base then undo.names[b] = name end
    end
    for b, name in pairs(undo.names) do
      save.boxNames[b] = nil
      if type(name) == "string" and name ~= "" then pc.names[tonumber(b)] = name end
    end
  end
  local cur = tonumber(save.currentBox)
  if cur and cur > base then
    undo.currentBox = save.currentBox
    pc.currentBox = cur
    save.currentBox = 1
  end
  if next(pc.boxes) or next(pc.names) or pc.currentBox then bucket.pc = pc else bucket.pc = nil end
  return undo
end

function BigPc.unsplit(save, undo)
  for b, box in pairs(undo.boxes) do save.boxes[b] = box end
  if next(undo.names) then
    save.boxNames = save.boxNames or {}
    for b, name in pairs(undo.names) do save.boxNames[b] = name end
  end
  if undo.currentBox then save.currentBox = undo.currentBox end
  local md = save.modData
  if type(md) == "table" then
    if undo.hadBucket then
      md[KEY].pc = undo.pc
    else
      md[KEY] = nil
      if not undo.hadModData and next(md) == nil then save.modData = nil end
    end
  end
end

-- The save data's boxes back into the box list, up to `count`; Red's list made whole (1..count).
function BigPc.merge(save, base, count, dense)
  local bucket = bucketOf(save, false)
  local pc = bucket and bucket.pc
  if type(pc) == "table" and type(save.boxes) == "table" then
    for b, box in pairs(pc.boxes or {}) do
      local n = tonumber(b)
      if n and n > base and n <= count and type(box) == "table" then
        save.boxes[n] = box
        pc.boxes[b] = nil
      end
    end
    for b, name in pairs(pc.names or {}) do
      local n = tonumber(b)
      if n and n > base and n <= count then
        save.boxNames = save.boxNames or {}
        save.boxNames[n] = name
        pc.names[b] = nil
      end
    end
    local cur = tonumber(pc.currentBox)
    if cur and cur <= count then
      save.currentBox = cur
      pc.currentBox = nil
    end
    if not (nonEmpty(pc.boxes) or nonEmpty(pc.names) or pc.currentBox) then bucket.pc = nil end
  end
  if dense and type(save.boxes) == "table" then
    for i = 1, count do save.boxes[i] = save.boxes[i] or {} end
  end
end

-- ------------------------------------------------------------------ Red's CHANGE BOX list
-- the mark beside a box that holds Pokemon: a small ball of our own, drawn once on the CPU
BigPc.BALL = { "..####..", ".######.", "##....##", "###..###", "#..##..#", "#......#", ".#....#.",
  "..####.." }
local ballImg
function BigPc.ballImage()
  if ballImg ~= nil then return ballImg or nil end
  ballImg = false
  local ok, img = pcall(function()
    local d = love.image.newImageData(8, 8)
    for y, row in ipairs(BigPc.BALL) do
      for x = 1, 8 do
        if row:sub(x, x) == "#" then d:setPixel(x - 1, y - 1, 0, 0, 0, 1) end
      end
    end
    local im = love.graphics.newImage(d)
    im:setFilter("nearest", "nearest")
    return im
  end)
  if ok and img then ballImg = img end
  return ballImg or nil
end

-- engine/menus/save.asm DisplayChangeBoxMenu, as src/ui/BoxMenu.lua draws it, with the list
-- scrolling 12 rows at a time
local function changeBoxMenu(game, require)
  local Boxes = require("src.pokemon.Boxes")
  local Menu = require("src.ui.Menu")
  local Font = require("src.render.Font")
  local TextBox = require("src.render.TextBox")
  local Strings = require("src.core.Strings")
  local boxes = Boxes.ensure(game.save)
  local items = {}
  for i = 1, Boxes.COUNT do
    items[i] = {
      label = Strings("BOX%2d", i),
      onSelect = function()
        game.save.currentBox = i
        if game.writeSave then game:writeSave() end
        require("src.core.Sound").play(game.data, "Save")
      end,
    }
  end
  local menu = Menu.new(game, items, {
    tx = 11, ty = 0, tw = 9, th = 14, rowStep = 1, itemY = 1, noSound = true,
    maxVisible = 12, noWrap = false,
  })
  menu.kind = "pc_box_change"
  menu.index = math.max(1, math.min(Boxes.COUNT, game.save.currentBox or 1))
  menu:clampScroll()
  local ball = BigPc.ballImage()
  local t = game.data.text or {}
  local baseDraw = menu.draw
  function menu:draw()
    Font.drawBox(0, 12, 20, 6)
    love.graphics.setColor(0, 0, 0, 1)
    local y = 112
    local prompt = TextBox.strip(t._ChooseABoxText or Strings("Choose a\n<PK><MN> BOX."))
    for line in (prompt .. "\n"):gmatch("([^\n]*)\n") do
      Font.draw(line, 8, y)
      y = y + 16
    end
    Font.drawBox(0, 0, 11, 4)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings("BOX No."), 8, 16)
    local n = game.save.currentBox or 1
    Font.draw(tostring(n), n >= 10 and 64 or 72, 16)
    baseDraw(self)
    if ball then
      love.graphics.setColor(1, 1, 1, 1)
      for row = 1, 12 do
        local box = boxes[self.scroll + row]
        if type(box) == "table" and #box > 0 then love.graphics.draw(ball, 18 * 8, row * 8) end
      end
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
  game.stack:push(menu)
end

local function changeBox(game, require)
  local TextBox = require("src.render.TextBox")
  local Strings = require("src.core.Strings")
  local t = game.data.text or {}
  local ask = TextBox.new(game, t._WhenYouChangeBoxText
    or Strings("When you change a\nPOKéMON BOX, data\vwill be saved.\fIs that okay?"),
    nil, {
    noSound = true,
    choice = function(yes) if yes then changeBoxMenu(game, require) end end,
  })
  ask.kind = "pc_box_change"
  game.stack:push(ask)
end

-- ------------------------------------------------------------------ install
-- opts: { require, generation, enabled = fn() -> bool, log }
-- Returns state: on(save) / off(save) for the option, loading(raw) for save.loading.
function BigPc.install(opts)
  local require, gen = opts.require, opts.generation
  local base = BigPc.BASE[gen]
  local okB, Boxes = pcall(require, gen == 1 and "src.pokemon.Boxes" or "src.core.gen2.Boxes")
  local okW, Writer = pcall(require, gen == 1 and "src.core.SaveData" or "src.core.gen2.Save")
  local field = gen == 1 and "COUNT" or "NUM_BOXES"
  local writerName = "save"
  if not (okB and okW and type(Boxes) == "table" and type(Boxes[field]) == "number"
    and type(Writer) == "table" and type(Writer[writerName]) == "function") then
    if opts.log then opts.log:warn("bigger PC is off: the PC was not found") end
    return nil
  end
  local okV, GV = pcall(require, "src.core.GameVersion")
  local function sameGeneration(save)
    if not (okV and GV and GV.generation) then return true end
    local ok, g = pcall(GV.generation, type(save) == "table" and save.version or nil)
    return not ok or g == nil or g == gen
  end
  local state = { base = base, count = BigPc.COUNT }
  local function enabled()
    local ok, v = pcall(opts.enabled or function() return true end)
    return not ok or v ~= false
  end

  -- the writer: once per process; a save of this generation is always written cart-shaped
  local hub = Writer.__ndxGen12BigPc
  if not hub then
    hub = { base = base }
    Writer.__ndxGen12BigPc = hub
    local write = Writer[writerName]
    Writer[writerName] = function(save, ...)
      if type(save) ~= "table" or type(save.boxes) ~= "table" or not sameGeneration(save) then
        return write(save, ...)
      end
      local undo = BigPc.split(save, hub.base)
      local r = pack(pcall(write, save, ...))
      BigPc.unsplit(save, undo)
      if not r[1] then error(r[2], 0) end
      return unpack(r, 2, r.n)
    end
  end

  if gen == 1 then
    -- an older save's extra boxes: Boxes.ensure only fills a save that has none
    if not Boxes.__ndxGen12BigPc then
      Boxes.__ndxGen12BigPc = true
      local ensure = Boxes.ensure
      Boxes.ensure = function(save, ...)
        local boxes = ensure(save, ...)
        if type(boxes) == "table" then
          for i = 1, Boxes.COUNT do boxes[i] = boxes[i] or {} end
        end
        return boxes
      end
    end
    -- the CHANGE BOX row: this mod's scrolling list while there are more than 12 boxes
    local okM, BoxMenu = pcall(require, "src.ui.BoxMenu")
    local okS, Strings = pcall(require, "src.core.Strings")
    if okM and okS and type(BoxMenu) == "table" and type(BoxMenu.new) == "function"
      and not BoxMenu.__ndxGen12BigPc then
      BoxMenu.__ndxGen12BigPc = true
      local new = BoxMenu.new
      local label = Strings("CHANGE BOX")
      BoxMenu.new = function(game, ...)
        local menu = new(game, ...)
        if Boxes.COUNT > base and type(menu) == "table" and type(menu.items) == "table" then
          for _, item in ipairs(menu.items) do
            if item.label == label then
              item.onSelect = function()
                menu.hollowIndex = menu.index
                changeBox(game, require)
              end
            end
          end
        end
        return menu
      end
    end
  end

  local function setCount(on)
    Boxes[field] = on and BigPc.COUNT or base
  end
  setCount(enabled())

  -- save.loading: the raw save, before the game takes it
  function state.loading(raw)
    if type(raw) ~= "table" or not sameGeneration(raw) then return end
    setCount(enabled())
    if enabled() then BigPc.merge(raw, base, BigPc.COUNT, gen == 1) end
  end
  -- the option, in the menu: the live save's extra boxes in or out
  function state.toggle(save)
    local on = enabled()
    setCount(on)
    if type(save) ~= "table" or type(save.boxes) ~= "table" then return end
    if on then BigPc.merge(save, base, BigPc.COUNT, gen == 1)
    else BigPc.split(save, base) end
  end
  return state
end

return BigPc
