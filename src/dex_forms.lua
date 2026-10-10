-- The Pokedex FORMS page: every alternate form of a species this mod registers, each as its
-- (animated) dex picture with the form's name under it.
--
--   Ruby/Sapphire/Emerald  the entry's CANCEL tab reads FORMS on a species that has forms; A on
--                          it opens the page over the entry, A or B closes it (B on the entry
--                          still exits, as it always has)
--   FireRed/LeafGreen      a third data page after the size/area one: A on page 2 goes on to it,
--                          B steps back, A on it exits, up/down steps entries as on any page
--
-- The entry screens gate on code that is local to them, so src/dex_patch.lua patches those few
-- spots to ask the module-table functions set here (__formsAvailable, __formsOpen, __formsTab,
-- __page2Controls); the page itself is drawn from wraps of the screens' public draw. An entry
-- opened without being seen (src/dex_patch.lua's peek) never offers FORMS.
--
-- The top half (formsByDex, label, layout) is pure, for tests.

local DexForms = {}

-- { [baseDex] = { { id, form }, ... } } from the forms this mod registers, in slot order.
function DexForms.byDex(forms)
  local out = {}
  for _, r in ipairs(forms or {}) do
    local dex = tonumber(r.baseDex or r.dex)
    if dex and r.id then
      out[dex] = out[dex] or {}
      table.insert(out[dex], { id = r.id, form = r.form, slot = r.slot })
    end
  end
  return out
end

local WORDS = { GALAR = "GALARIAN", HISUI = "HISUIAN", ["10"] = "10%" }
local DROP = { STANDARD = true, MASK = true }

-- The name under a form's picture: its form, in words ("GALAR_STANDARD" -> "GALARIAN",
-- "WELLSPRING_MASK" -> "WELLSPRING", "RUBY_CREAM" -> "RUBY CREAM").
function DexForms.label(form)
  local words = {}
  for w in tostring(form.form or form.id or ""):gmatch("[^_]+") do
    if not DROP[w] then words[#words + 1] = WORDS[w] or w end
  end
  return table.concat(words, " ")
end

-- Where `n` pictures go inside `area` { x, y, w, h }: { size, cols, rows, cells = { { x, y,
-- cx, colW } } } -- (x, y) a picture's top-left, cx the centre of its column (for its name),
-- colW the room its name has. Pictures shrink as there are more: 64 px for 1-2, 48 for 3-4,
-- 32 for 5-15 (4 or 5 to a row), 24 beyond.
DexForms.NAME_H = 10
function DexForms.layout(n, area)
  local size, cols
  if n <= 2 then size, cols = 64, math.max(1, n)
  elseif n <= 4 then size, cols = 48, n
  elseif n <= 8 then size, cols = 32, 4
  elseif n <= 15 then size, cols = 32, 5
  else size, cols = 24, 6 end
  local rows = math.max(1, math.ceil(n / cols))
  -- never taller than the page: shrink until every row and its names fit
  size = math.max(8, math.min(size, math.floor(area.h / rows) - DexForms.NAME_H))
  local rowH = size + DexForms.NAME_H
  local colW = math.floor(area.w / cols)
  local top = area.y + math.floor((area.h - rows * rowH) / 2)
  local cells = {}
  for i = 1, n do
    local r, c = math.floor((i - 1) / cols), (i - 1) % cols
    local inRow = math.min(cols, n - r * cols)            -- a short last row is centred
    local left = area.x + math.floor((area.w - inRow * colW) / 2)
    local cx = left + c * colW + math.floor(colW / 2)
    cells[i] = { x = cx - math.floor(size / 2), y = top + r * rowH, cx = cx, colW = colW }
  end
  return { size = size, cols = cols, rows = rows, cells = cells }
end

-- ------- drawing (LOVE)

local function shorten(FrlgFont, text, maxW, opts)
  if FrlgFont.measure(text, opts) <= maxW then return text end
  while #text > 1 and FrlgFont.measure(text .. ".", opts) > maxW do text = text:sub(1, -2) end
  return text .. "."
end

-- The pictures and names of `forms` inside `area`. artFor(id) -> { image } or nil.
function DexForms.drawGrid(forms, area, artFor, colors, require)
  local FrlgFont = require("src.ui.game3.frlg_font")
  local L = DexForms.layout(#forms, area)
  local small = { small = true, colors = colors }
  for i, f in ipairs(forms) do
    local c = L.cells[i]
    local pic = artFor(f.id)
    if pic and pic.image then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(pic.image, c.x, c.y, 0, L.size / 64, L.size / 64)
    end
    local name = shorten(FrlgFont, DexForms.label(f), c.colW - 2, small)
    local w = FrlgFont.measure(name, small)
    FrlgFont.draw(name, c.cx - math.floor(w / 2), c.y + L.size + 1, small)
  end
end

-- ------- FireRed / LeafGreen

local FRLG_TEXT = { fg = { 0, 0, 0, 1 }, shadow = { 230 / 255, 222 / 255, 197 / 255, 1 } }

local function installFrlg(st, require)
  local okP, Pokedex = pcall(require, "src.ui.game3.pokedex")
  if not (okP and type(Pokedex) == "table" and Pokedex.__nationalDexFrlgForms) then return end
  local Pokemon = require("src.core.game3.pokemon")
  local Dex = require("src.core.game3.dex")

  Pokedex.__nationalDexFormsState = st         -- the draw wrap reads the newest load's
  local function formsOf(sp)
    local cur = Pokedex.__nationalDexFormsState
    local ok, n = pcall(Pokemon.national, sp)
    return ok and cur.byDex[tonumber(n) or -1] or nil
  end
  Pokedex.__formsAvailable = function(sp)
    return formsOf(sp) ~= nil and Dex.isSeen(Pokedex._dex, sp) == true
  end
  -- page 2's hint when A goes on to FORMS: the cart's "A NEXT DATA" and "B PREVIOUS DATA" halves
  Pokedex.__page2Controls = function(sp)
    if not Pokedex.__formsAvailable(sp) then return nil end
    local RomText = require("src.core.game3.rom_text")
    local nextData = RomText.plain("gText_NextDataCancel")
    local prevData = RomText.plain("gText_CancelPreviousData")
    local a = nextData:find("{B_BUTTON}", 1, true)
    local b = prevData:find("{B_BUTTON}", 1, true)
    if not (a and b) then return nil end
    return nextData:sub(1, a - 1) .. prevData:sub(b)
  end

  if Pokedex.__nationalDexFormsDraw then return end
  Pokedex.__nationalDexFormsDraw = true
  local original = Pokedex.draw
  Pokedex.draw = function(...)
    if not (Pokedex.open and Pokedex.screen == "data" and Pokedex.dataPage == 3) then
      return original(...)
    end
    local ok, err = pcall(function()
      local Chrome = require("src.ui.game3.pokedex_chrome")
      local FrlgFont = require("src.ui.game3.frlg_font")
      local RomText = require("src.core.game3.rom_text")
      local sp = Pokedex._regSpecies or Pokedex.selectedSpecies
      Chrome.drawPaperBg()
      Chrome.drawHeader(RomText.plain("gText_PokemonListNoColor"), nil, 2)
      local nat = Pokemon.national(sp) or 0
      FrlgFont.draw(string.format("№%03d", nat), 8, 20, { small = true, colors = FRLG_TEXT })
      FrlgFont.draw(Pokemon.name(sp) or "", 40, 18, { colors = FRLG_TEXT })
      DexForms.drawGrid(formsOf(sp) or {}, { x = 4, y = 32, w = 232, h = 110 },
        Pokedex.__nationalDexFormsState.artFor, FRLG_TEXT, require)
      Chrome.drawControlInfoLeft(RomText.plain("gText_Cry"), 8, 146)
      Chrome.drawControlInfo(RomText.plain("gText_CancelPreviousData"), 236, 146)
    end)
    if not ok then
      Pokedex.dataPage = 2                 -- never leave the player on a page that cannot draw
      local log = Pokedex.__nationalDexFormsState.log
      if log and log.warn then log:warn("the FORMS page could not draw: %s", tostring(err)) end
      return original(...)
    end
  end
end

-- ------- Ruby / Sapphire / Emerald

local PANEL = { 248 / 255, 248 / 255, 240 / 255 }
local EDGE = { 140 / 255, 136 / 255, 120 / 255 }
local RSE_TEXT = { fg = { 64 / 255, 64 / 255, 64 / 255, 1 }, shadow = { 216 / 255, 216 / 255, 200 / 255, 1 } }

-- Emerald's tab bar, as the cart draws it (graphics/pokedex/menu tiles, select_main tilemap):
-- 4 tabs of 7 tiles (56 px) from x = 8, 16 px tall, in palette bank 2 when selected and 4 when
-- not. AREA, CRY and SIZE share one body -- border 6, fill C, letters F with a D shadow one
-- pixel right and below -- while CANCEL has a red/pink body of its own. So FORMS is the AREA
-- body, label cleared, with FORMS lettered in the same strokes: R and S as the cart draws them,
-- F = its E without the foot, O = its C closed on the right, M drawn to match.
local TAB_X, TAB_W, TAB_H = 8 + 3 * 56, 56, 16

local TAB_BODY = {
  "77777777777777777777777777777777777777777777777777777777",
  "77777777777777777777777777777777777777777777777777777777",
  "77777766666666666666666666666666666666666666666666777777",
  "777776CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC677777",
  "77776CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC67777",
  "77776CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC67777",
  "77776CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC67777",
  "77776CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC67777",
  "77776CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC67777",
  "77776CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC67777",
  "77776CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC67777",
  "77776CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC67777",
  "77776CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC67777",
  "77776CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC67777",
  "777776CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC677777",
  "77777766666666666666666666666666666666666666666666777777",
}

-- 5 x 9 strokes (rows 4-12 of the tab); "#" is a stroke pixel
local GLYPHS = {
  F = { "#####", "#....", "#....", "#....", "####.", "#....", "#....", "#....", "#...." },
  O = { ".###.", "#...#", "#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###." },
  R = { "####.", "#...#", "#...#", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#" },
  M = { "#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#", "#...#", "#...#" },
  S = { ".###.", "#...#", "#....", "#....", ".###.", "....#", "....#", "#...#", ".###." },
}

-- The FORMS tab as palette indices: rows of 56 numbers (0 = transparent). Pure.
function DexForms.formsTabIndices(word)
  word = word or "FORMS"
  local grid = {}
  for y = 1, TAB_H do
    grid[y] = {}
    local row = TAB_BODY[y]
    for x = 1, TAB_W do grid[y][x] = tonumber(row:sub(x, x), 16) end
  end
  local width = #word * 6 - 1
  local left = math.floor((TAB_W - width) / 2)          -- 0-based column of the first stroke
  local strokes = {}
  for i = 1, #word do
    local g = GLYPHS[word:sub(i, i)]
    for r = 1, #g do
      for c = 1, 5 do
        if g[r]:sub(c, c) == "#" then
          strokes[(4 + r - 1) * 100 + left + (i - 1) * 6 + c - 1] = true
        end
      end
    end
  end
  local function at(x, y) return strokes[y * 100 + x] end
  for y = 4, 13 do
    for x = 6, TAB_W - 7 do
      if at(x, y) then
        grid[y + 1][x + 1] = 0xF
      elseif at(x - 1, y) or at(x, y - 1) or at(x - 1, y - 1) then
        grid[y + 1][x + 1] = 0xD
      end
    end
  end
  return grid
end

local tabImages = {}

-- The bar image with its 4th tab (CANCEL) replaced by FORMS, coloured from the bar's own
-- palette (`pal`, the engine's 256-entry BGR555 table) in the bank the cart would use.
local function formsTab(img, selected, pal, require)
  local Gfx = require("src.ui.game3.rse.pokedex_gfx")
  local bank = selected == 3 and 2 or 4
  local sig = { bank }
  for v = 0, 15 do sig[#sig + 1] = pal[bank * 16 + v] or 0 end
  sig = table.concat(sig, ",")
  local tab = tabImages[sig]
  if not tab then
    local grid = DexForms.formsTabIndices()
    local data = love.image.newImageData(TAB_W, TAB_H)
    for y = 1, TAB_H do
      for x = 1, TAB_W do
        local v = grid[y][x]
        if v ~= 0 then
          local r, g, b = Gfx.rgb8(pal[bank * 16 + v] or 0)
          data:setPixel(x - 1, y - 1, r, g, b, 1)
        end
      end
    end
    tab = love.graphics.newImage(data)
    tab:setFilter("nearest", "nearest")
    tabImages[sig] = tab
  end
  local w, h = img:getDimensions()
  local canvas = love.graphics.newCanvas(w, h)
  canvas:setFilter("nearest", "nearest")
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.origin()
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, 0, 0)
  love.graphics.setBlendMode("replace")
  love.graphics.draw(tab, TAB_X, 0)
  love.graphics.pop()
  return canvas
end

local function installRse(st, require)
  local okR, live = pcall(require, "src.ui.game3.rse.pokedex")
  if not (okR and type(live) == "table" and live.__nationalDexRseForms) then return end
  local Pokedex = live.__nationalDexCopy or live      -- the copy's functions read their own table
  local Pokemon = require("src.core.game3.pokemon")

  Pokedex.__nationalDexFormsState = st
  local function formsFor(s)
    if type(s) ~= "table" or type(s.info) ~= "table" or s.peeking then return nil end
    return Pokedex.__nationalDexFormsState.byDex[tonumber(s.info.dexNum) or -1]
  end
  Pokedex.__formsTab = function(s, img, submenu, selected, pal)
    if submenu or type(pal) ~= "table" or not formsFor(s) then return nil end
    local ok, out = pcall(formsTab, img, selected, pal, require)
    return ok and out or nil
  end
  Pokedex.__formsOpen = function(s)
    local forms = formsFor(s)
    if not forms then return false end
    s.nationalDexForms = forms
    s.fn = "nationalDexForms"
    return true
  end
  local tasks = Pokedex.tasks or live.tasks
  if type(tasks) == "table" then
    tasks.nationalDexForms = function(s, inp)
      local new = inp and inp.new or {}
      if new.a or new.b then
        s.nationalDexForms = nil
        s.fn = "infoInput"
      end
    end
  end

  if Pokedex.__nationalDexFormsDraw then return end
  Pokedex.__nationalDexFormsDraw = true
  local original = Pokedex.draw
  Pokedex.draw = function(s, ...)
    local out = original(s, ...)
    if type(s) == "table" and s.nationalDexForms and s.page == (Pokedex.PAGE or {}).INFO then
      local ok, err = pcall(function()
        love.graphics.push("all")
        love.graphics.setColor(EDGE[1], EDGE[2], EDGE[3], 1)
        love.graphics.rectangle("fill", 0, 16, 240, 144)
        love.graphics.setColor(PANEL[1], PANEL[2], PANEL[3], 1)
        love.graphics.rectangle("fill", 2, 18, 236, 140)
        local FrlgFont = require("src.ui.game3.frlg_font")
        local nat = tonumber(s.info.dexNum) or 0
        local sp = Pokedex.speciesOf and Pokedex.speciesOf(nat) or nat
        FrlgFont.draw(string.format("No%03d  %s", nat, Pokemon.name(sp) or ""), 8, 22,
          { colors = RSE_TEXT })
        DexForms.drawGrid(s.nationalDexForms, { x = 4, y = 38, w = 232, h = 118 },
          Pokedex.__nationalDexFormsState.artFor, RSE_TEXT, require)
        love.graphics.pop()
      end)
      if not ok then
        s.nationalDexForms = nil
        if s.fn == "nationalDexForms" then s.fn = "infoInput" end
        local log = Pokedex.__nationalDexFormsState.log
        if log and log.warn then log:warn("the FORMS page could not draw: %s", tostring(err)) end
      end
    end
    return out
  end
end

-- st: { byDex, artFor(id) -> picture, log }. Installed after src/dex_patch.lua.
function DexForms.install(st, require)
  require = require or _G.require
  installFrlg(st, require)
  installRse(st, require)
end

return DexForms
