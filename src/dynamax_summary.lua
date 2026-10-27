-- The Dynamax marks on the Pokemon summary (src/dynamax.lua): Sword / Shield show a Pokemon's
-- Dynamax Level as a gauge of ten and its Gigantamax Factor by the Dynamax icon. Drawn here over the
-- game's own summary, in its 240 x 160 space, after each skin's draw: FireRed / LeafGreen's
-- (src/ui/game3/summary_menu.lua SummaryMenu.draw), Emerald's (rse/summary_menu.lua
-- RseSummary.draw) and Ruby / Sapphire's (rs/summary_menu.lua S.draw). The engine has no summary
-- hook, so each draw is wrapped; Emerald's and Ruby / Sapphire's are rebuilt by src/type_icons.lua,
-- so this installs after it. The gauge on the info page with the icon beside it; the icon in the
-- picture's corner on the other pages; neither on an egg, nor the gauge for a Pokemon that cannot
-- Dynamax. The PC's hovered Pokemon (every game's) shows the icon too (DS.installPc).
--   DS.install({ which = "frlg" | "rse" | "rs", dynamax = Dx, require, icon = Image }) -> true | false, why
--   DS.drawMarks(mon, spot, page)   (spot = DS.SPOTS[which]; drivers)

local DS = {}

-- where the marks go, per skin: the icon's top left in the picture's frame (`gmax`); the gauge's top
-- left, its label over the bar ("stack") or beside it ("row"), the label's ink; Emerald's and Ruby /
-- Sapphire's gauge sits in the strip under the level, where the status shows - with a status it
-- moves into the picture frame's foot, the bar alone (`busy`)
-- The Gigantamax Factor is the Dynamax icon (assets/ui/icon_dynamax.png): beside the gauge on the info
-- page (`icon`, `busyIcon` with the gauge in the frame), in the picture frame's corner on the others
-- (`gmax`); `ICON` its size
DS.ICON = 12
DS.SPOTS = {
  -- (FireRed / LeafGreen's: the frame's bottom left, mirroring the Poke Ball in its bottom right -
  -- the ball 12 x 12 at 100..111 x 82..93 inside the frame's 4..116 x ..94)
  frlg = { gmax = { 9, 82 }, gauge = { 8, 143, "row" }, icon = { 105, 139 }, ink = { 0.25, 0.25, 0.3 }, infoPage = 0 },
  rse = { gmax = { 11, 35 }, gauge = { 5, 145, "stack" }, icon = { 61, 145 }, ink = { 0.94, 0.97, 0.94 },
    busy = { 11, 88 }, busyIcon = { 62, 84, 10 }, infoPage = 0 },
  rs = { gmax = { 11, 35 }, gauge = { 5, 145, "stack" }, icon = { 61, 145 }, ink = { 0.3, 0.22, 0.42 },
    busy = { 11, 88 }, busyIcon = { 62, 84, 10 }, infoPage = 0 },
}

-- ------- a 3 x 5 pixel font (the marks' own: the game's font has no room for them)
local GLYPH = {
  ["G"] = { "111", "100", "101", "101", "111" }, ["M"] = { "101", "111", "111", "101", "101" },
  ["A"] = { "010", "101", "111", "101", "101" }, ["X"] = { "101", "101", "010", "101", "101" },
  ["D"] = { "110", "101", "101", "101", "110" }, ["Y"] = { "101", "101", "010", "010", "010" },
  ["N"] = { "111", "101", "101", "101", "101" }, ["L"] = { "100", "100", "100", "100", "111" },
  ["V"] = { "101", "101", "101", "101", "010" }, ["-"] = { "000", "000", "111", "000", "000" },
  [" "] = { "000", "000", "000", "000", "000" },
  ["0"] = { "111", "101", "101", "101", "111" }, ["1"] = { "010", "110", "010", "010", "111" },
  ["2"] = { "111", "001", "111", "100", "111" }, ["3"] = { "111", "001", "111", "001", "111" },
  ["4"] = { "101", "101", "111", "001", "001" }, ["5"] = { "111", "100", "111", "001", "111" },
  ["6"] = { "111", "100", "111", "101", "111" }, ["7"] = { "111", "001", "001", "001", "001" },
  ["8"] = { "111", "101", "111", "101", "111" }, ["9"] = { "111", "101", "111", "001", "111" },
}
local function textWidth(s) return #s * 4 - 1 end
local function pixelText(G, s, x, y)
  for i = 1, #s do
    local g = GLYPH[s:sub(i, i)] or GLYPH[" "]
    for row = 1, 5 do
      local line = g[row]
      for col = 1, 3 do
        if line:sub(col, col) == "1" then G.rectangle("fill", x + (i - 1) * 4 + col - 1, y + row - 1, 1, 1) end
      end
    end
  end
end

DS.RED = { 0.86, 0.1, 0.24 }
DS.DARK = { 0.3, 0.02, 0.08 }
DS.ORANGE = { 1, 0.56, 0.08 }
DS.EMPTY = { 0.33, 0.33, 0.4 }

-- the Gigantamax Factor's mark: the Dynamax icon (DS.icon, set by install), `size` px at (x, y);
-- the G-MAX plate below stands in without it
DS.icon = nil
function DS.drawIcon(G, x, y, size)
  local img = DS.icon
  if not img then return DS.drawGmax(G, x, y) end
  size = size or DS.ICON
  local k = size / img:getWidth()
  G.setColor(1, 1, 1, 1)
  G.draw(img, x, y, 0, k, k)
end

-- the G-MAX mark: a red cloud-cornered plate with white letters (25 x 9)
function DS.drawGmax(G, x, y)
  local w, h = textWidth("G-MAX") + 6, 9
  G.setColor(DS.DARK)
  G.rectangle("fill", x + 1, y, w - 2, h)
  G.rectangle("fill", x, y + 1, w, h - 2)
  G.setColor(DS.RED)
  G.rectangle("fill", x + 1, y + 1, w - 2, h - 2)
  -- (the cloud's bumps over the top)
  G.setColor(DS.DARK)
  G.rectangle("fill", x + 4, y - 1, 4, 1); G.rectangle("fill", x + 12, y - 1, 5, 1)
  G.setColor(1, 1, 1, 1)
  pixelText(G, "G-MAX", x + 3, y + 2)
  return w, h
end

-- the Dynamax Level gauge: "DYNAMAX LV" and ten segments, the level's filled orange; layout
-- "stack" (label over the bar), "row" (beside it) or "bar" (the bar alone)
function DS.drawGauge(G, x, y, level, layout, ink)
  local bx, by = x, y
  if layout ~= "bar" then
    G.setColor(ink or { 0.2, 0.2, 0.25 })
    pixelText(G, "DYNAMAX LV", x, y)
    if layout == "row" then bx, by = x + textWidth("DYNAMAX LV") + 4, y - 0.5
    else by = y + 7 end
  end
  G.setColor(0.12, 0.12, 0.16, 1)
  G.rectangle("fill", bx, by, 10 * 5 + 1, 6)
  for i = 1, 10 do
    G.setColor(i <= level and DS.ORANGE or DS.EMPTY)
    G.rectangle("fill", bx + 1 + (i - 1) * 5, by + 1, 4, 4)
  end
  G.setColor(1, 1, 1, 1)
end

local Dx = nil
local function isEgg(mon, req)
  local ok, Pokemon = pcall(req, "src.core.game3.pokemon")
  if ok and Pokemon and Pokemon.isEgg then
    local okE, e = pcall(Pokemon.isEgg, mon)
    if okE then return e == true end
  end
  return false
end

-- the marks for one Pokemon on one page (in the summary's own space)
function DS.drawMarks(mon, spot, page, req)
  if not (Dx and type(mon) == "table" and spot and love and love.graphics) then return end
  req = req or require
  if isEgg(mon, req) then return end
  local G = love.graphics
  local pr, pg, pb, pa = G.getColor()
  local gmax = Dx.canGigantamax(mon)
  if page == spot.infoPage and Dx.canDynamax(mon) then
    -- the gauge, and the icon beside it
    local okSd, SD = pcall(req, "src.core.game3.summary_data")
    local ailing = false
    if spot.busy and okSd and SD and SD.statusAilment then
      local okA, a = pcall(SD.statusAilment, mon)
      ailing = okA and (tonumber(a) or 0) > 0
    end
    if ailing then
      DS.drawGauge(G, spot.busy[1], spot.busy[2], Dx.level(mon), "bar")
      if gmax then DS.drawIcon(G, spot.busyIcon[1], spot.busyIcon[2], spot.busyIcon[3]) end
    else
      DS.drawGauge(G, spot.gauge[1], spot.gauge[2], Dx.level(mon), spot.gauge[3], spot.ink)
      if gmax then DS.drawIcon(G, spot.icon[1], spot.icon[2]) end
    end
  elseif gmax then
    DS.drawIcon(G, spot.gmax[1], spot.gmax[2])
  end
  G.setColor(pr, pg, pb, pa)
end

-- the PC (every game's: src/ui/game3/pc_chrome.lua drawLeftDataPanel, the hovered Pokemon's picture
-- centred on (40, 48)): the G-MAX mark in the picture's top left corner
DS.PC_GMAX = { 11, 20 }
function DS.installPc(req)
  local ok, Pc = pcall(req, "src.ui.game3.pc_chrome")
  if not (ok and type(Pc) == "table" and Pc.drawLeftDataPanel) or Pc._ndxDynamax then return false end
  local orig = Pc.drawLeftDataPanel
  Pc.drawLeftDataPanel = function(mon, ...)
    local r = orig(mon, ...)
    if Dx and type(mon) == "table" and love and love.graphics then
      pcall(function()
        if isEgg(mon, req) or not Dx.canGigantamax(mon) then return end
        local G = love.graphics
        local pr, pg, pb, pa = G.getColor()
        DS.drawIcon(G, DS.PC_GMAX[1], DS.PC_GMAX[2], 12)
        G.setColor(pr, pg, pb, pa)
      end)
    end
    return r
  end
  Pc._ndxDynamax = true
  return true
end

function DS.install(opts)
  Dx = opts.dynamax
  DS.icon = opts.icon or DS.icon
  local req = opts.require or require
  local which = opts.which
  local spot = DS.SPOTS[which]
  if Dx then DS.installPc(req) end
  if not (Dx and spot) then return false, "no skin" end
  if which == "frlg" then
    local ok, Sm = pcall(req, "src.ui.game3.summary_menu")
    if not (ok and type(Sm) == "table" and Sm.draw) or Sm._ndxDynamax then return false, "no FRLG summary" end
    local orig = Sm.draw
    Sm.draw = function(...)
      local r = orig(...)
      if Sm.open and not Sm._nativeDelegate and not (Sm._slide and Sm._slide.active) then
        local mon = Sm._party and Sm._party[Sm._cursor]
        pcall(DS.drawMarks, mon, spot, Sm._page, req)
      end
      return r
    end
    Sm._ndxDynamax = true
    return true
  elseif which == "rse" then
    local ok, Rse = pcall(req, "src.ui.game3.rse.summary_menu")
    if not (ok and type(Rse) == "table" and Rse.draw) or Rse._ndxDynamax then return false, "no Emerald summary" end
    local orig = Rse.draw
    Rse.draw = function(Sm, ...)
      local r = orig(Sm, ...)
      local okS, S = pcall(req, "src.ui.game3.summary_menu")
      Sm = Sm or (okS and S) or nil
      if Sm and Sm.open then
        local mon = Sm._loaded or (Sm._party and Sm._party[Sm._cursor])
        local page = Rse.page and select(2, pcall(Rse.page, Sm)) or Sm._page
        pcall(DS.drawMarks, mon, spot, page, req)
      end
      return r
    end
    Rse._ndxDynamax = true
    return true
  elseif which == "rs" then
    local ok, S = pcall(req, "src.ui.game3.rs.summary_menu")
    if not (ok and type(S) == "table" and S.draw) or S._ndxDynamax then return false, "no Ruby / Sapphire summary" end
    local orig = S.draw
    S.draw = function(...)
      local r = orig(...)
      if S.open and not S._pageTask and S._state == "normal" then
        local mon = S._loaded or (S._party and S._party[S._cursor])
        pcall(DS.drawMarks, mon, spot, S._page, req)
      end
      return r
    end
    S._ndxDynamax = true
    return true
  end
  return false, "unknown skin"
end

return DS
