-- Exp. Candies (Sword / Shield's): XS, S, M, L and XL, used on a Pokemon from the Bag for 100 / 800 /
-- 3,000 / 10,000 / 30,000 Exp. Points. Gen 3 has no such items, so they are registered here (indexes
-- 950-954, between the evolution items and the TMs) with an item effect, for any mod to give - Max
-- Raids drops them.
--
-- The effect gives the Exp. at once (levels and stats, HP rising with the max as a Rare Candy does),
-- and when it levels the Pokemon up the Party menu then plays the Rare Candy's own steps through its
-- public calls: the "grew to Lv. N" window with the stat growth, each new level's moves (LearnMove's
-- queue, the forget prompt through the Summary), and a level evolution. The Party menu shows a mod
-- effect's words and goes back to its list; the steps run when those words are dismissed (a wrap of
-- PartyMenu.showMessage, active only while a candy's steps are waiting).
--
-- Their Bag icons are drawn here, on the CPU (no canvas: a Bag icon is drawn mid-frame), as small
-- crystals: XS a pyramid, S a cube, M a diamond, L and XL cut gems, bluer to violet as they grow.
--   C = ExpCandies(mod) ; C.register() ; C.icons() -> { [index] = Image } ; C.installMenu() ; C.ids

local C = {}
C.LIST = {
  { id = "EXP_CANDY_XS", name = "Exp. Candy XS", index = 950, exp = 100, price = 20, shape = "pyramid",
    rgb = { 0.62, 0.88, 1.0 }, amount = "100" },
  { id = "EXP_CANDY_S", name = "Exp. Candy S", index = 951, exp = 800, price = 240, shape = "cube",
    rgb = { 0.42, 0.76, 1.0 }, amount = "800" },
  { id = "EXP_CANDY_M", name = "Exp. Candy M", index = 952, exp = 3000, price = 1000, shape = "diamond",
    rgb = { 0.32, 0.62, 0.98 }, amount = "3,000" },
  { id = "EXP_CANDY_L", name = "Exp. Candy L", index = 953, exp = 10000, price = 3000, shape = "gem",
    rgb = { 0.3, 0.46, 0.98 }, amount = "10,000" },
  { id = "EXP_CANDY_XL", name = "Exp. Candy XL", index = 954, exp = 30000, price = 10000, shape = "bigGem",
    rgb = { 0.52, 0.4, 1.0 }, amount = "30,000" },
}
C.ids = {}
local byIndex = {}
for _, c in ipairs(C.LIST) do C.ids[c.id] = c.index; byIndex[c.index] = c end

local function req(name)
  local ok, m = pcall(require, name)
  return ok and m or nil
end

-- the Party menu's steps waiting on the candy's words: { mon, oldStats, newStats, levels, session, bag }
local pending = nil

local function statsOf(mon)
  return {
    maxHp = tonumber(mon.maxHp or mon.maxhp) or 1,
    atk = tonumber(mon.attack or mon.atk) or 1, def = tonumber(mon.defense or mon.def) or 1,
    spa = tonumber(mon.spAtk or mon.spa) or 1, spd = tonumber(mon.spDef or mon.spd) or 1,
    spe = tonumber(mon.speed or mon.spe) or 1,
  }
end

-- the effect: Exp. Points to the chosen Pokemon; "failed" at Lv 100 or fainted (as a Rare Candy)
local function useOf(candy)
  return function(ctx)
    local mon = ctx and ctx.target
    local Pokemon = req("src.core.game3.pokemon")
    local SD = req("src.core.game3.summary_data")
    if not (mon and Pokemon and SD) then return "failed", { "It won't have any effect." } end
    local level = tonumber(mon.level) or 1
    if level >= 100 or (tonumber(mon.hp) or 0) <= 0 then return "failed", { "It won't have any effect." } end
    local species = Pokemon.speciesOf and Pokemon.speciesOf(mon) or tonumber(mon.species)
    local rate = Pokemon.growthRate(species)
    local cap = SD.expForLevel(rate, 100)
    local exp = math.max(tonumber(mon.exp) or 0, SD.expForLevel(rate, level))
    local gained = math.min(candy.exp, cap - exp)
    exp = exp + gained
    local newLevel = level
    while newLevel < 100 and SD.expForLevel(rate, newLevel + 1) <= exp do newLevel = newLevel + 1 end
    local name = Pokemon.displayMonName and Pokemon.displayMonName(mon) or "It"
    local text = ("%s gained\n%d Exp. Points!"):format(name, gained)
    mon.exp = exp
    if newLevel > level then
      local before = statsOf(mon)
      local oldHp = tonumber(mon.hp) or 0
      mon.level = newLevel
      Pokemon.applyStats(mon)
      local after = statsOf(mon)
      mon.hp = math.min(after.maxHp, oldHp + math.max(0, after.maxHp - before.maxHp))
      local ItemUse = req("src.core.game3.item_use")
      local levels = {}
      for lv = level + 1, newLevel do
        levels[#levels + 1] = lv
        if ItemUse and ItemUse.levelUpEvent then pcall(ItemUse.levelUpEvent, mon, lv) end
      end
      pending = { mon = mon, oldStats = before, newStats = after, levels = levels, session = ctx.session }
    end
    return "consumed", { text }
  end
end

function C.register(mod)
  local items, effects = mod.content and mod.content.items, mod.content and mod.content.item_effects
  if not items then return 0 end
  local n = 0
  for _, c in ipairs(C.LIST) do
    local okE = effects and pcall(function()
      effects:register(c.id, { use = useOf(c), needsTarget = true, field = true, battle = false })
    end)
    local ok, err = pcall(function()
      items:register(c.id, {
        id = c.id, name = c.name, index = c.index, price = c.price, pocket = "ITEMS",
        -- (the Bag's three lines of at most 19)
        description = ("A candy packed with\nenergy. It gives\n%s Exp. Points."):format(c.amount),
        effect = okE and c.id or nil,
      })
    end)
    if ok then n = n + 1 elseif mod.log then mod.log:warn("Exp. Candy %s not registered: %s", c.id, tostring(err)) end
  end
  return n
end

-- the Rare Candy's steps after a candy's words: "grew to Lv. N" with the stat growth, the moves of
-- each level gained, a level evolution; then what the Party menu meant to do next
local function follow(p, done)
  local PM = req("src.ui.game3.party_menu")
  local Pokemon = req("src.core.game3.pokemon")
  local Audio = req("src.core.game3.audio")
  if not (PM and Pokemon) then return done() end
  local mon = p.mon
  local name = Pokemon.displayMonName and Pokemon.displayMonName(mon) or "It"
  pcall(function() Audio.playFanfare("MUS_LEVEL_UP") end)
  local RomText = req("src.core.game3.rom_text")
  local ok, lvlMsg = pcall(function()
    return RomText.plain("gText_PkmnElevatedToLvVar2", { stringVars = { name, tostring(mon.level) } })
  end)
  if not ok or type(lvlMsg) ~= "string" then lvlMsg = ("%s grew to\nLv. %d!"):format(name, mon.level) end
  local function evolve()
    local Evolution = req("src.core.game3.evolution")
    local okT, target = pcall(function() return Evolution and Evolution.levelTarget(mon, p.session) end)
    local Scene = req("src.ui.game3.evolution_scene")
    if okT and tonumber(target) and Scene and Scene.start then
      local okS = pcall(Scene.start, mon, target, {
        session = p.session, bag = PM._bag, canStop = true, savedSong = Audio and Audio._mapSong,
        onDone = function()
          pcall(PM.reloadSprites)
          PM.mode = "list"
        end,
      })
      if okS then return end
    end
    done()
  end
  local function moves()
    local LearnMove = req("src.core.game3.battle.learn_move")
    if not (LearnMove and LearnMove.beginQueue) then return evolve() end
    local okQ, started = pcall(LearnMove.beginQueue, mon, p.levels, {
      displayName = name,
      pushMsg = function(t, cb) PM.showMessage(t, cb) end,
      askYesNo = function(a, b)
        local cb = (type(a) == "function") and a or b
        local prompt = (type(a) == "string") and a or PM._messageText or ""
        PM.showYesNo(prompt, function(yes) if cb then cb(yes == true) end end)
      end,
      askForget = function(a, b, c)
        local cb = (type(b) == "function") and b or c
        local SummaryMenu = req("src.ui.game3.summary_menu")
        SummaryMenu.openMenu(PM._party, PM.cursor, {
          mode = "select_move",
          moveToLearn = LearnMove._moveId,
          onSelectMove = function(slotIdx)
            pcall(PM.reloadSprites)
            if cb then cb(slotIdx) end
          end,
        })
      end,
      onDone = function() evolve() end,
    })
    if not (okQ and started) then evolve() end
  end
  PM._messageText = lvlMsg
  PM.showStatGrowth(mon, p.oldStats, p.newStats, moves)
end

-- the Party menu: a candy's words, once dismissed, go on into its steps
function C.installMenu()
  local PM = req("src.ui.game3.party_menu")
  if not (PM and type(PM.showMessage) == "function") or PM._ndxCandy then return false end
  local orig = PM.showMessage
  PM.showMessage = function(text, onDismiss)
    if pending then
      local p = pending
      pending = nil
      return orig(text, function()
        follow(p, function() if onDismiss then onDismiss() end end)
      end)
    end
    return orig(text, onDismiss)
  end
  PM._ndxCandy = true
  return true
end

-- ------- the icons: 24 x 24 crystals, faces filled on the CPU, an outline round them, a glint

local function inside(px, py, pts)
  local c = false
  local n = #pts / 2
  local j = n
  for i = 1, n do
    local xi, yi, xj, yj = pts[i * 2 - 1], pts[i * 2], pts[j * 2 - 1], pts[j * 2]
    if ((yi > py) ~= (yj > py)) and (px < (xj - xi) * (py - yi) / (yj - yi) + xi) then c = not c end
    j = i
  end
  return c
end

-- faces: { pts, shade } (shade multiplies the colour; > 1 lightens toward white)
local SHAPES = {
  pyramid = {
    { { 12, 5, 5, 17, 12, 20 }, 1.25 },
    { { 12, 5, 12, 20, 19, 17 }, 0.8 },
  },
  cube = {
    { { 12, 4, 19, 8, 12, 12, 5, 8 }, 1.3 },
    { { 5, 8, 12, 12, 12, 21, 5, 17 }, 1.0 },
    { { 12, 12, 19, 8, 19, 17, 12, 21 }, 0.72 },
  },
  diamond = {
    { { 12, 2, 4, 11, 12, 14 }, 1.3 },
    { { 12, 2, 12, 14, 20, 11 }, 1.0 },
    { { 4, 11, 12, 14, 12, 22 }, 0.8 },
    { { 12, 14, 20, 11, 12, 22 }, 0.6 },
  },
  gem = {
    { { 8, 6, 16, 6, 15, 9, 9, 9 }, 1.35 },
    { { 3, 10, 8, 6, 9, 9, 8, 10 }, 1.05 },
    { { 8, 10, 9, 9, 15, 9, 16, 10 }, 1.15 },
    { { 16, 10, 15, 9, 16, 6, 21, 10 }, 0.85 },
    { { 3, 10, 8, 10, 12, 21 }, 0.9 },
    { { 8, 10, 16, 10, 12, 21 }, 0.75 },
    { { 16, 10, 21, 10, 12, 21 }, 0.58 },
  },
  bigGem = {
    { { 7, 3, 17, 3, 16, 7, 8, 7 }, 1.35 },
    { { 1, 8, 7, 3, 8, 7, 7, 8 }, 1.05 },
    { { 7, 8, 8, 7, 16, 7, 17, 8 }, 1.15 },
    { { 17, 8, 16, 7, 17, 3, 23, 8 }, 0.85 },
    { { 1, 8, 7, 8, 12, 23 }, 0.9 },
    { { 7, 8, 17, 8, 12, 23 }, 0.75 },
    { { 17, 8, 23, 8, 12, 23 }, 0.58 },
  },
}

local function shadeOf(rgb, k)
  if k <= 1 then return rgb[1] * k, rgb[2] * k, rgb[3] * k end
  local t = k - 1
  return rgb[1] + (1 - rgb[1]) * t, rgb[2] + (1 - rgb[2]) * t, rgb[3] + (1 - rgb[3]) * t
end

local function iconData(c)
  local d = love.image.newImageData(24, 24)
  local faces = SHAPES[c.shape] or SHAPES.cube
  for y = 0, 23 do
    for x = 0, 23 do
      for _, f in ipairs(faces) do
        if inside(x + 0.5, y + 0.5, f[1]) then
          local r, g, b = shadeOf(c.rgb, f[2])
          d:setPixel(x, y, r, g, b, 1)
        end
      end
    end
  end
  -- the outline: a dark blue ring round the opaque pixels
  local edge = {}
  for y = 0, 23 do
    for x = 0, 23 do
      local _, _, _, a = d:getPixel(x, y)
      if a == 0 then
        for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          local nx, ny = x + o[1], y + o[2]
          if nx >= 0 and nx < 24 and ny >= 0 and ny < 24 then
            local _, _, _, na = d:getPixel(nx, ny)
            if na > 0 then edge[#edge + 1] = { x, y }; break end
          end
        end
      end
    end
  end
  for _, e in ipairs(edge) do d:setPixel(e[1], e[2], 0.09, 0.11, 0.3, 1) end
  -- a glint on its lit face
  local g = faces[1][1]
  local gx, gy = math.floor((g[1] + g[3] + g[5]) / 3), math.floor((g[2] + g[4] + g[6]) / 3)
  d:setPixel(math.max(0, gx - 1), math.max(0, gy - 1), 1, 1, 1, 1)
  if c.shape == "bigGem" or c.shape == "gem" then d:setPixel(gx, gy - 1, 1, 1, 1, 1) end
  return d
end

local icons = nil
function C.icons()
  if icons then return icons end
  icons = {}
  for _, c in ipairs(C.LIST) do
    local ok, img = pcall(function()
      local im = love.graphics.newImage(iconData(c))
      im:setFilter("nearest", "nearest")
      return im
    end)
    if ok then icons[c.index] = img end
  end
  return icons
end
C.iconData = iconData

return C
