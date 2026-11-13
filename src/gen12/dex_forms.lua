-- The Pokedex FORMS page on Gen 1 / Gen 2: a species' alternate forms (the ones this mod
-- registers, src/gen12/species.lua), one at a time: its picture, its form ("ALOLAN", "RUBY
-- CREAM": src/dex_forms.lua's label, loaded as it is) and its types, with Up / Down (and Left /
-- Right on Red) to step through them.
--
--   Red   one more page after the entry's last text page, when the entry was opened from the
--         Pokedex list (not after a catch): A there opens it instead of closing the entry. On it,
--         A steps to the next form and, on the last, closes the entry as the last page would;
--         B goes back to the entry, whose next A or B closes it. Our own screen pushed over the
--         entry (DexEntryMenu.update is wrapped for that one A), coloured like the entry: the
--         form's picture in its own palette (sgbPalettes).
--   Gold  a third page of the entry: PAGE goes 1 -> 2 -> FORMS -> 1 on a species with forms
--         (PokedexMenu.update is wrapped for that one A; the cart's arrow, AREA, CRY and PRNT are
--         untouched). The page is the entry with the form's picture, the height and weight
--         cleared, and the form, its types and "FORM 1/2" where the text goes
--         (PokedexMenu.drawEntryBody is wrapped). Not after a catch (that entry has no actions).
-- The wraps are made once per process and ask the last install's forms (games switch
-- in-process); a game without this mod's forms shows none.

local Forms = {}

-- { [base species id] = { { id, label }, ... } } in slot order
function Forms.byBase(forms, label)
  local out = {}
  for _, e in ipairs(forms or {}) do
    if e.base and e.id then
      out[e.base] = out[e.base] or {}
      table.insert(out[e.base], { id = e.id, label = label(e.data or e) })
    end
  end
  return out
end

-- a record's types as words ("FIRE/FLYING"), each once
function Forms.typeText(def, data, require)
  local okT, TypeChart = pcall(require, "src.battle.TypeChart")
  local words, seen = {}, {}
  for _, t in ipairs(def and def.types or {}) do
    if not seen[t] then
      seen[t] = true
      local name
      if okT and TypeChart.displayName then
        local ok, n = pcall(TypeChart.displayName, t, data)
        if ok and type(n) == "string" then name = n end
      end
      words[#words + 1] = (name or tostring(t):gsub("_TYPE$", "")):upper()
    end
  end
  return table.concat(words, "/")
end

-- ------------------------------------------------------------------ Red
local function gen1Page(entry, list, require)
  local Font = require("src.render.Font")
  local Strings = require("src.core.Strings")
  local game = entry.game
  local data = game.data
  local page = { game = game, entry = entry, list = list, index = 1, isMenu = true, isOpaque = true }
  local pics = {}
  local function pic(id)
    local p = pics[id]
    if p == nil then
      p = false
      local okS, Sprites = pcall(require, "src.pokemon.Sprites")
      if okS then
        local path, trueColor = Sprites.path(data, id, "front", { kind = "dex" })
        local ok, img = false, nil
        if path then ok, img = pcall(love.graphics.newImage, path) end
        if ok and img then p = { img = img, trueColor = trueColor } end
      end
      pics[id] = p
    end
    return p or nil
  end

  function page:sgbPalettes()
    local P = require("src.render.PaletteFX")
    local base = P.pal(data, "BROWNMON")
    if not base then return nil end
    local f = self.list[self.index]
    return { P.whole(base), P.zone(P.monPal(data, f and f.id), 1, 1, 8, 8) }
  end

  local function closeAll()
    game.stack:pop()                       -- this page
    if game.stack:top() == entry then game.stack:pop() end
    if entry.onDone then entry.onDone() end
  end

  function page:update()
    local input = game.input
    local n = #self.list
    if input:wasPressed("down") or input:wasPressed("right") then
      self.index = self.index % n + 1
    elseif input:wasPressed("up") or input:wasPressed("left") then
      self.index = (self.index - 2) % n + 1
    elseif input:wasPressed("a") then
      if self.index < n then self.index = self.index + 1 else closeAll() end
    elseif input:wasPressed("b") then
      game.stack:pop()
    end
  end

  function page:draw()
    local G = love.graphics
    local f = self.list[self.index]
    local def = f and data.pokemon[f.id]
    G.setColor(1, 1, 1, 1)
    G.rectangle("fill", 0, 0, 160, 144)
    Font.drawBox(0, 0, 20, 12)
    Font.drawBox(0, 12, 20, 6)
    local p = f and pic(f.id)
    if p then
      local w, h = p.img:getDimensions()
      local x = 8 + math.max(0, 56 - math.floor((8 - w / 8) / 2) * 8 - w)
      local y = 8 + (7 - h / 8) * 8
      G.setColor(1, 1, 1, 1)
      G.draw(p.img, x + w, y, 0, -1, 1)
      if p.trueColor then pcall(function() require("src.render.PaletteFX").markTrueColor(x, y, w, h) end) end
    end
    G.setColor(0, 0, 0, 1)
    if def then
      Font.draw(def.name or f.id, 80, 16)
      local types = Forms.typeText(def, data, require)
      local first, second = types:match("^([^/]+)/?(.*)$")
      Font.draw(first or "", 80, 40)
      if second and second ~= "" then Font.draw(second, 80, 56) end
      Font.draw(Strings(f.label), 8, 112)
      Font.draw(Strings("FORM %d/%d", self.index, #self.list), 8, 128)
    end
    G.setColor(1, 1, 1, 1)
  end
  return page
end

local function installGen1(require, hub)
  local okE, Entry = pcall(require, "src.ui.DexEntryMenu")
  local okL, List = pcall(require, "src.ui.PokedexMenu")
  if not (okE and type(Entry) == "table" and type(Entry.update) == "function") then return false end
  if Entry.__ndxForms then Entry.__ndxForms.hub = hub; return true end
  local own = { hub = hub }
  Entry.__ndxForms = own
  local update = Entry.update
  Entry.update = function(self, dt, ...)
    local h = own.hub
    local list = h and self.def and h.byBase[self.def.id]
    if list and not self.ndxFormsShown and (self.picDelay or 0) == 0
        and self.page >= (self.pageCount or 1) and not self:crying() then
      local input = self.game and self.game.input
      local states = self.game.stack and self.game.stack.states or {}
      local below
      for i = #states, 2, -1 do if states[i] == self then below = states[i - 1] break end end
      local fromList = okL and below and getmetatable(below) == List
      if fromList and input and input:wasPressed("a") and self.game.data == h.data then
        self.ndxFormsShown = true
        local ok, page = pcall(gen1Page, self, list, require)
        if ok and page then
          self.game.stack:push(page)
          return
        end
      end
    end
    return update(self, dt, ...)
  end
  return true
end

-- ------------------------------------------------------------------ Gold
local function installGen2(require, hub)
  local okP, Menu = pcall(require, "src.ui.gen2.PokedexMenu")
  if not (okP and type(Menu) == "table" and type(Menu.update) == "function"
      and type(Menu.drawEntryBody) == "function") then return false end
  if Menu.__ndxForms then Menu.__ndxForms.hub = hub; return true end
  local own = { hub = hub }
  Menu.__ndxForms = own
  local Strings = require("src.core.Strings")

  local function formsOf(self, row)
    local h = own.hub
    if not (h and row) or self.newEntry or (self.game and self.game.data ~= h.data) then return nil end
    return h.byBase[row.species]
  end

  local update = Menu.update
  Menu.update = function(self, dt, ...)
    if self.view == "entry" and not self.newEntry then
      local input = self.game and self.game.input
      local list = formsOf(self, self.current and self:current())
      if input and list then
        if self.page == 2 and input:wasPressed("a") and (self.entryAction or 1) == 1 then
          self.page, self.ndxForm = 3, 1                       -- PAGE: on to the forms
          return
        end
        if self.page == 3 then
          local n = #list
          if input:wasPressed("down") then self.ndxForm = (self.ndxForm or 1) % n + 1; return end
          if input:wasPressed("up") then self.ndxForm = ((self.ndxForm or 1) - 2) % n + 1; return end
        end
      end
    end
    local r = update(self, dt, ...)
    if self.page == 3 and (self.view ~= "entry" or not formsOf(self, self.current and self:current())) then
      self.page = 1
    end
    return r
  end

  -- the form's picture where the species' goes: Gold's own drawPic, in the form's colours or,
  -- when the form has none of its own, its base species'
  local function drawFormPic(self, formId, baseId, tx, ty)
    local okPal, Palettes = pcall(require, "src.world.gen2.Palettes")
    local okG, GbcPalette = pcall(require, "src.render.GbcPalette")
    local colors
    if okPal and self.palettes then
      colors = Palettes.monColors(self.palettes, formId) or Palettes.monColors(self.palettes, baseId)
    end
    local image, trueColor = self:picFor(formId)
    if not image then return end
    local G = love.graphics
    local blank = colors and okG and GbcPalette.color(colors, 1) or { 255, 255, 255 }
    G.setColor(blank[1] / 255, blank[2] / 255, blank[3] / 255, 1)
    G.rectangle("fill", tx * 8, ty * 8, 56, 56)
    local w, h = image:getDimensions()
    local x = tx * 8 + math.floor((56 - w) / 16) * 8
    local y = ty * 8 + (56 - h)
    G.setColor(1, 1, 1, 1)
    local function body() G.draw(image, x, y) end
    if colors and okG and not (trueColor and GbcPalette.mode == "gbc") and GbcPalette.available() then
      GbcPalette.with(colors, body)
    else
      body()
    end
  end

  local drawBody = Menu.drawEntryBody
  Menu.drawEntryBody = function(self, row, entry, ...)
    local list = self.page == 3 and formsOf(self, row)
    if not list then return drawBody(self, row, entry, ...) end
    local f = list[self.ndxForm or 1] or list[1]
    self.page = 1
    local ok, err = pcall(drawBody, self, row, entry, ...)
    self.page = 3
    if not ok then error(err, 0) end
    pcall(function()
      drawFormPic(self, f.id, row.species, 1, 1)
      self:blank(9, 7, 10, 3)                              -- the base's height and weight
      self:blank(2, 11, 18, 5)                             -- its text
      local def = self.game.data.pokemon[f.id]
      self:text(Strings(f.label), 2, 11)
      self:text(Strings(Forms.typeText(def, self.game.data, require)), 2, 13)
      self:text(Strings("FORM %d/%d", self.ndxForm or 1, #list), 2, 15)
    end)
  end
  return true
end

-- opts: { require, generation, forms (src/gen12/species.lua state.forms), label (fn(form) ->
-- words: src/dex_forms.lua DexForms.label), data (the game's data, at game.ready) }
function Forms.install(opts)
  local hub = { byBase = Forms.byBase(opts.forms, opts.label), data = opts.data }
  if opts.generation == 1 then return installGen1(opts.require, hub) end
  return installGen2(opts.require, hub)
end

return Forms
