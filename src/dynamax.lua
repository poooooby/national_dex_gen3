-- Dynamax (Sword / Shield), the part a Pokemon carries: its Dynamax Level (0-10: its HP while
-- Dynamaxed, x1.5 .. x2) and its Gigantamax Factor, and the three items that change them -
-- Dynamax Candy (a level), Max Mushrooms (three cook a Max Soup: the factor given, or taken away)
-- and Max Honey (Urshifu's soup takes one) - and the Dynamax Crystal (no use of its own: Max Raids
-- spends one at a den for a legendary Pokemon's raid). No battle here Dynamaxes: Max Raids does, in its raids,
-- through exports.dynamax (src/api.lua).
--
-- The marks live in the engine's mod bag on the Pokemon, mon.extra.national_dex_gen3 =
-- { dynamaxLevel, gmaxFactor }: saved with it, kept through the PC, evolution and the Union Room;
-- not sent by a cable trade. None = level 0, no factor (a wild or hatched Pokemon's).
--   Dx = Dynamax(mod, { data = data/dynamax.lua, formIdOf = fn(slot) -> form id | nil })
--   Dx.level(mon) ; Dx.setLevel(mon, n) ; Dx.hasFactor(mon) ; Dx.setFactor(mon, on)
--   Dx.canDynamax(monOrSlot) ; Dx.gmaxMoveOf(monOrSlot) -> G-Max Move id of its form | nil
--   Dx.canGigantamax(mon) (the factor and a form) ; Dx.hpMult(level) ; Dx.raidStartLevel(stars, rng)
--   Dx.registerItems(mod) ; Dx.icons() -> { [index] = Image } ; Dx.ids

local NS = "national_dex_gen3"

return function(mod, deps)
  local D = deps.data or {}
  local Dx = { data = D }
  Dx.ITEMS = {
    { id = "DYNAMAX_CANDY", name = "Dynamax Candy", index = 955, price = 3000,
      description = "A candy that raises\na Pokémon's\nDynamax Level." },
    { id = "MAX_MUSHROOMS", name = "Max Mushrooms", index = 956, price = 1500,
      description = "Three make a Max\nSoup: it gives or\ntakes G-Max Factor." },
    { id = "MAX_HONEY", name = "Max Honey", index = 957, price = 3000,
      description = "Sweet honey. With\nMax Mushrooms, a\nsoup for Urshifu." },
    -- (no use from the Bag: Max Raids takes one at a den for a legendary Pokemon's raid)
    { id = "DYNAMAX_CRYSTAL", name = "Dynamax Crystal", index = 958, price = 10000,
      description = "Dynamax energy in a\ncrystal. At a den,\na legendary awaits." },
  }
  Dx.ids = {}
  for _, it in ipairs(Dx.ITEMS) do Dx.ids[it.id] = it.index end

  local function req(name)
    local r = deps.require or require
    local ok, m = pcall(r, name)
    return ok and type(m) == "table" and m or nil
  end
  local function P() return req("src.core.game3.pokemon") end

  -- ------- the marks

  local function bag(mon, make)
    if type(mon) ~= "table" then return nil end
    local ex = mon.extra
    if type(ex) ~= "table" then
      if not make then return nil end
      ex = {}
      mon.extra = ex
    end
    local mine = ex[NS]
    if type(mine) ~= "table" then
      if not make then return nil end
      mine = {}
      ex[NS] = mine
    end
    return mine
  end
  function Dx.level(mon)
    local b = bag(mon)
    local n = b and tonumber(b.dynamaxLevel) or 0
    return math.max(0, math.min(D.MAX_LEVEL or 10, math.floor(n)))
  end
  function Dx.setLevel(mon, n)
    local b = bag(mon, true)
    if not b then return nil end
    b.dynamaxLevel = math.max(0, math.min(D.MAX_LEVEL or 10, math.floor(tonumber(n) or 0)))
    return b.dynamaxLevel
  end
  function Dx.hasFactor(mon)
    local b = bag(mon)
    return b ~= nil and b.gmaxFactor == true
  end
  function Dx.setFactor(mon, on)
    local b = bag(mon, true)
    if not b then return nil end
    b.gmaxFactor = on and true or nil
    return on and true or false
  end

  -- ------- species

  -- a Pokemon or a species slot -> slot, National Dex number, form id (nil for a base species)
  local function speciesOf(x)
    local Pk = P()
    local slot = x
    if type(x) == "table" then
      slot = Pk and Pk.speciesOf and select(2, pcall(Pk.speciesOf, x)) or x.species
    end
    slot = tonumber(slot)
    if not slot then return nil end
    local nat = Pk and Pk.national and select(2, pcall(Pk.national, slot))
    local form = deps.formIdOf and deps.formIdOf(slot) or nil
    return slot, tonumber(nat), form
  end
  Dx.speciesOf = speciesOf

  function Dx.canDynamax(x)
    local slot, nat = speciesOf(x)
    if not slot then return false end
    return not (nat and D.NO_DYNAMAX and D.NO_DYNAMAX[nat])
  end

  -- the G-Max Move of its species' Gigantamax form (regional forms have none)
  function Dx.gmaxMoveOf(x)
    local _, nat, form = speciesOf(x)
    local move = nat and D.GMAX and D.GMAX[nat]
    if not move then return nil end
    if form then
      if D.FORM_MOVE and D.FORM_MOVE[form] then return D.FORM_MOVE[form] end
      for _, suffix in ipairs(D.FORM_EXCLUDE or {}) do
        if form:sub(-#suffix) == suffix then return nil end
      end
    end
    return move
  end
  function Dx.hasGmaxForm(x) return Dx.gmaxMoveOf(x) ~= nil end
  -- it Gigantamaxes: the factor, and a species with the form
  function Dx.canGigantamax(mon)
    return Dx.hasFactor(mon) and Dx.hasGmaxForm(mon) and Dx.canDynamax(mon)
  end

  function Dx.hpMult(level)
    return (D.HP_BASE or 1.5) + (D.HP_PER or 0.05) * math.max(0, math.min(D.MAX_LEVEL or 10, tonumber(level) or 0))
  end

  -- a raid catch's starting Dynamax Level (rng(lo, hi) inclusive, else math.random)
  function Dx.raidStartLevel(stars, rng)
    local row = D.RAID_LEVEL and D.RAID_LEVEL[math.max(1, math.min(5, tonumber(stars) or 1))] or { 1, 2 }
    rng = rng or math.random
    return math.min(D.MAX_LEVEL or 10, row[1] + rng(0, row[2] - 1))
  end

  -- ------- the items

  local NO_EFFECT = "It won't have any effect."
  local function nameOf(mon)
    local Pk = P()
    local ok, n = pcall(Pk and (Pk.displayMonName or Pk.displayName) or error, mon)
    return ok and type(n) == "string" and n or "It"
  end
  local function isEgg(mon)
    local Pk = P()
    if Pk and Pk.isEgg then
      local ok, e = pcall(Pk.isEgg, mon)
      if ok then return e == true end
    end
    return type(mon) == "table" and mon.isEgg == true
  end

  -- Dynamax Candy: +1 Dynamax Level (not an egg, not past 10, never Zacian / Zamazenta / Eternatus)
  function Dx.useCandy(mon)
    if type(mon) ~= "table" or isEgg(mon) or not Dx.canDynamax(mon) then return "failed", { NO_EFFECT } end
    local lv = Dx.level(mon)
    if lv >= (D.MAX_LEVEL or 10) then return "failed", { NO_EFFECT } end
    Dx.setLevel(mon, lv + 1)
    return "consumed", { ("%s's Dynamax\nLevel rose to %d!"):format(nameOf(mon), lv + 1) }
  end

  -- Max Mushrooms: three (and a Max Honey for Urshifu) cook a Max Soup; it gives the Gigantamax
  -- Factor, or takes it from a Pokemon that has it. take(id, n) removes n more of an item; count(id)
  -- how many the Bag holds (the one used included)
  function Dx.useSoup(mon, count, take)
    if type(mon) ~= "table" or isEgg(mon) or not Dx.hasGmaxForm(mon) then return "failed", { NO_EFFECT } end
    local _, nat = speciesOf(mon)
    if nat and D.NO_SOUP and D.NO_SOUP[nat] then return "failed", { NO_EFFECT } end
    local need = D.SOUP_MUSHROOMS or 3
    local honey = nat and D.SOUP_HONEY and D.SOUP_HONEY[nat]
    if (count(Dx.ids.MAX_MUSHROOMS) or 0) < need then
      return "failed", { ("It takes %d Max\nMushrooms to make\na Max Soup."):format(need) }
    end
    if honey and (count(Dx.ids.MAX_HONEY) or 0) < 1 then
      return "failed", { ("Its Max Soup takes\n%d Max Mushrooms\nand a Max Honey."):format(need) }
    end
    -- (the one used goes as the effect is consumed; the rest here)
    take(Dx.ids.MAX_MUSHROOMS, need - 1)
    if honey then take(Dx.ids.MAX_HONEY, 1) end
    local name = nameOf(mon)
    if Dx.hasFactor(mon) then
      Dx.setFactor(mon, false)
      return "consumed", { ("%s drank the\nMax Soup and lost\nthe G-Max Factor!"):format(name) }
    end
    Dx.setFactor(mon, true)
    return "consumed", { ("%s drank the\nMax Soup! It can\nnow Gigantamax!"):format(name) }
  end

  local function bagOps(ctx)
    local Bag = req("src.core.game3.bag")
    local b = ctx and ctx.session and ctx.session.bag
    local function count(id)
      if not (Bag and b and Bag.get) then return 0 end
      local ok, n = pcall(Bag.get, b, id)
      return ok and tonumber(n) or 0
    end
    local function take(id, n)
      if Bag and b and n > 0 then pcall(Bag.remove, b, id, n) end
    end
    return count, take
  end

  local USE = {
    DYNAMAX_CANDY = function(ctx) return Dx.useCandy(ctx and ctx.target) end,
    MAX_MUSHROOMS = function(ctx)
      local count, take = bagOps(ctx)
      return Dx.useSoup(ctx and ctx.target, count, take)
    end,
  }

  function Dx.registerItems(m)
    local items, effects = m.content and m.content.items, m.content and m.content.item_effects
    if not items then return 0 end
    local n = 0
    for _, it in ipairs(Dx.ITEMS) do
      local okE = false
      if USE[it.id] and effects then
        okE = pcall(function()
          effects:register(it.id, { use = USE[it.id], needsTarget = true, field = true, battle = false })
        end)
      end
      local ok, err = pcall(function()
        items:register(it.id, { id = it.id, name = it.name, index = it.index, price = it.price, pocket = "ITEMS",
          description = it.description, effect = okE and it.id or nil })
      end)
      if ok then n = n + 1 elseif m.log then m.log:warn("%s not registered: %s", it.id, tostring(err)) end
    end
    return n
  end

  -- ------- the Bag icons: 24 x 24, drawn on the CPU (a Bag icon is drawn mid-frame: no canvas)

  local function plot(d, x, y, r, g, b)
    if x >= 0 and y >= 0 and x < 24 and y < 24 then d:setPixel(x, y, r, g, b, 1) end
  end
  local function disc(d, cx, cy, rx, ry, fn)
    for y = 0, 23 do
      for x = 0, 23 do
        local u, v = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
        if u * u + v * v <= 1 then fn(x, y, u, v) end
      end
    end
  end
  local function outline(d, r, g, b)
    local edge = {}
    for y = 0, 23 do
      for x = 0, 23 do
        local _, _, _, a = d:getPixel(x, y)
        if a == 0 then
          for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local nx, ny = x + o[1], y + o[2]
            if nx >= 0 and nx < 24 and ny >= 0 and ny < 24 and select(4, d:getPixel(nx, ny)) > 0 then
              edge[#edge + 1] = { x, y }
              break
            end
          end
        end
      end
    end
    for _, e in ipairs(edge) do d:setPixel(e[1], e[2], r, g, b, 1) end
  end

  local DRAW = {
    -- a wrapped candy, red and pink, with the Dynamax cloud's three dots
    DYNAMAX_CANDY = function(d)
      disc(d, 12, 12, 7, 6, function(x, y, u, v)
        local k = 1 - 0.35 * (u + v) * 0.5
        plot(d, x, y, 0.92 * k, 0.18 * k, 0.32 * k)
      end)
      for i = 0, 3 do
        plot(d, 2 + i, 12 - i, 0.98, 0.55, 0.7); plot(d, 2 + i, 12 + i, 0.98, 0.55, 0.7)
        plot(d, 21 - i, 12 - i, 0.98, 0.55, 0.7); plot(d, 21 - i, 12 + i, 0.98, 0.55, 0.7)
      end
      plot(d, 2, 11, 0.98, 0.55, 0.7); plot(d, 2, 13, 0.98, 0.55, 0.7)
      plot(d, 21, 11, 0.98, 0.55, 0.7); plot(d, 21, 13, 0.98, 0.55, 0.7)
      for _, p in ipairs({ { 10, 12 }, { 12, 10 }, { 14, 12 } }) do plot(d, p[1], p[2], 1, 0.85, 0.9) end
      outline(d, 0.32, 0.05, 0.12)
      plot(d, 9, 9, 1, 1, 1)
    end,
    -- three red-capped mushrooms with spots on pale stalks
    MAX_MUSHROOMS = function(d)
      local caps = { { 7, 11, 4.5, 3.2 }, { 16, 9, 5, 3.6 }, { 12, 15, 4.2, 3 } }
      for _, c in ipairs(caps) do
        for y = math.floor(c[2]), math.min(23, math.floor(c[2] + 6)) do
          for x = math.floor(c[1] - 1), math.floor(c[1] + 1) do plot(d, x, y, 0.95, 0.9, 0.78) end
        end
      end
      for _, c in ipairs(caps) do
        disc(d, c[1], c[2], c[3], c[4], function(x, y, u, v)
          if v <= 0.35 then
            local k = 1 - 0.3 * (u + v + 1) * 0.5
            plot(d, x, y, 0.88 * k, 0.12 * k, 0.16 * k)
          end
        end)
        plot(d, math.floor(c[1] - 1), math.floor(c[2] - 1), 1, 0.95, 0.9)
        plot(d, math.floor(c[1] + 2), math.floor(c[2]), 1, 0.95, 0.9)
      end
      outline(d, 0.28, 0.05, 0.06)
    end,
    -- a honey jar: amber body, a pale lid
    MAX_HONEY = function(d)
      disc(d, 12, 14, 7, 7, function(x, y, u, v)
        local k = 1 - 0.3 * (u + v) * 0.5
        plot(d, x, y, 0.98 * k, 0.68 * k, 0.12 * k)
      end)
      for y = 4, 7 do for x = 7, 16 do plot(d, x, y, 0.85, 0.74, 0.55) end end
      for x = 6, 17 do plot(d, x, 8, 0.6, 0.48, 0.3) end
      plot(d, 9, 11, 1, 0.95, 0.75); plot(d, 9, 12, 1, 0.95, 0.75)
      outline(d, 0.3, 0.16, 0.02)
    end,
  }

  function Dx.iconData(id)
    local d = love.image.newImageData(24, 24)
    local draw = DRAW[id]
    if draw then draw(d) end
    return d
  end

  local icons = nil
  -- each item's icon: its sprite (assets/items/dynamax/<id>.png, pokesprite's, 24 x 24), else the
  -- one drawn above
  function Dx.icons()
    if icons then return icons end
    icons = {}
    for _, it in ipairs(Dx.ITEMS) do
      local ok, img = pcall(function()
        local data
        local bytes = mod and mod.read and mod:read("assets/items/dynamax/" .. it.id:lower() .. ".png")
        if bytes then data = love.image.newImageData(love.filesystem.newFileData(bytes, it.id:lower() .. ".png")) end
        local im = love.graphics.newImage(data or Dx.iconData(it.id))
        im:setFilter("nearest", "nearest")
        return im
      end)
      if ok then icons[it.index] = img end
    end
    return icons
  end

  return Dx
end
