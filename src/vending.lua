-- The vending machines (data/vending.lua): stationary NPCs on a map that open a touch-screen shop
-- (src/vending_screen.lua) instead of the Mart's menu.
--   - the sprites are registered at load (mod.content.sprites: one frame, 16 x 32, standing on
--     its tile); the machines are spawned with mod.world:spawnNpc on entering their map and again
--     after a load (runtime objects are not saved, so nothing of them is in a save)
--   - A on one (the world.talk hook) opens its screen, pushed on the Gen 3 UI stack as a layer
--     that takes the buttons and holds the field; it is drawn over the game's rectangle from
--     render.hud, taps and clicks come from input.pointer and the wheel from input.wheel
--   - the on-screen touch pad is put away while a screen is up (it would take the taps first) and
--     put back as it was (src/core/TouchControls, engine internals)
--   V = vending(mod, { require, log, screen = vending_screen factory, data = data/vending.lua,
--                      itemIndex = Species.itemIndex(mod), tms = data/tms.lua, game = () -> version,
--                      moves = data/moves.lua (the newer moves' full names, for the screen) })
--   V.registerSprites() (load) ; V.install() (load: the hooks) ; V.stock(machine) ; V.open(machine)

return function(mod, deps)
  local req = deps.require or require
  local log = deps.log
  local floor = math.floor
  local V = { machines = deps.data or {} }
  V.ANCHOR = { x = 8, y = 28 }
  -- the Pokédollar sign (charmap.asm 0xB7, every Gen 3 game's), its size against the screen's font
  -- (BOLD: drawn again that many font pixels to the right, so its one-pixel strokes don't look thin
  -- beside the screen's text)
  V.CURRENCY_GLYPH, V.CURRENCY_EM, V.CURRENCY_DROP, V.CURRENCY_BOLD = 0xB7, 11, -0.04, 0.6
  local glyphOpts = setmetatable({}, { __mode = "k" })
  local signAdvance, signAdvanceFor
  local NONE = { 0, 0, 0, 0 }   -- Gen 3 puts the anchor's row 12 px down the tile: row 28 of 32
  local LAYER_ID = "national_dex_gen3_vending"

  local engineMods = {}
  local function engine(name)
    local m = engineMods[name]
    if m then return m end
    local ok
    ok, m = pcall(req, name)
    m = ok and type(m) == "table" and m or nil
    engineMods[name] = m
    return m
  end

  local function spriteId(machine) return "NATIONAL_DEX_VENDING_" .. tostring(machine.id):upper() end
  V.spriteId = spriteId

  -- (the version module kept, not required again: the screen asks a few dozen times a frame, and
  -- a mod's require checks every call)
  local function gameName()
    local GV = engine("src.core.GameVersion")
    if GV and GV.current then return tostring(GV.current) end
    return tostring(deps.game and deps.game() or "")
  end
  local bagIcon
  local function inGame(place, game)
    for _, g in ipairs(place.games or {}) do
      if game:find(g, 1, true) then return true end
    end
    return false
  end
  -- where a machine stands in this game, if it does (data/vending.lua `places`)
  function V.placeIn(machine, game)
    for _, place in ipairs(machine.places or {}) do
      if inGame(place, game or gameName()) then return place end
    end
    return nil
  end

  -- a map id without its game's prefix (EM_, FR_ ...)
  local function bareMap(mapId) return (tostring(mapId):gsub("^%u%u_", "")) end
  V.bareMap = bareMap

  -- ------- the stock: data/vending.lua's slugs, resolved now (another mod's item of a slug sells)

  local tmNumber, tmMove = {}, {}
  for _, t in ipairs(deps.tms or {}) do
    tmNumber[t.id:lower()], tmMove[t.id:lower()] = t.number, t.move
  end

  function V.entry(slug)
    local id = deps.itemIndex and deps.itemIndex(slug)
    if not id then return nil end
    local ItemsData = engine("src.core.game3.items_data")
    local function call(fn, ...)
      if not (ItemsData and type(ItemsData[fn]) == "function") then return nil end
      local ok, v = pcall(ItemsData[fn], ...)
      return ok and v or nil
    end
    local info = call("info", id)
    local e = { slug = slug, id = id,
                name = call("displayName", id) or slug:upper():gsub("%-", " "),
                price = floor(tonumber(info and info.price) or 0),
                description = call("description", id) }
    -- the newer moves' full names ("DRAINING KISS"): the cart's are squeezed into 12 letters
    -- ("DRAININGKISS"), which only the screen has room to undo
    if not V.fullMoveNames then
      local names = {}
      for _, m in ipairs(deps.moves or {}) do
        if m.full then
          if m.name then names[m.name] = m.full:upper() end
          if m.index then names[m.index] = m.full:upper() end
        end
      end
      V.fullMoveNames = names
    end
    local number = tmNumber[slug]
    if number then
      local P = engine("src.core.game3.pokemon")
      local move = P and P.moveFromTmItem and P.moveFromTmItem(id)
      local row = move and P.battleMove and P.battleMove(move)
      local okN, moveName = pcall(function() return P.moveName(move) end)
      local full = V.fullMoveNames[move] or (okN and V.fullMoveNames[moveName]) or nil
      e.tm = { number = number, move = full or (okN and moveName) or nil,
               type = row and tonumber(row.type), power = row and row.power,
               accuracy = row and row.accuracy, pp = row and row.pp }
    end
    return e
  end

  function V.stock(machine)
    local tabs = {}
    for _, tab in ipairs(machine.tabs or {}) do
      local entries = {}
      for _, slug in ipairs(tab.add or {}) do
        local e = V.entry(slug)
        if e and e.price > 0 then
          -- (the Gym Badges it needs: by slug, or a TM by its move)
          local gates = machine.badges or {}
          e.badges = gates[slug] or gates[tmMove[slug] or ""] or 0
          entries[#entries + 1] = e
        end
      end
      tabs[#tabs + 1] = { label = tab.label, entries = entries }
    end
    return tabs
  end

  -- ------- the screen

  local padPrev, padHidden = nil, false
  local function pad(hide)
    local TC = engine("src.core.TouchControls")
    if not TC then return end
    if hide then
      if not padHidden then
        padPrev, padHidden = TC.enabled, true
      end
      if TC.enabled ~= false then
        TC.enabled = false
        if TC.reset then pcall(TC.reset, TC) end
      end
    elseif padHidden then
      padHidden = false
      TC.enabled = padPrev
      if TC.enabled ~= false and TC.reset then pcall(TC.reset, TC) end
    end
  end

  -- the running game's Bag drawing (FireRed / LeafGreen's, or Ruby / Sapphire / Emerald's)
  local function bagChrome()
    local family = gameName():find("firered", 1, true) or gameName():find("leafgreen", 1, true)
    return engine(family and "src.ui.game3.bag_chrome" or "src.ui.game3.rse.bag_chrome")
  end
  -- the Bag's icons, each drawn once into a 24 x 24 canvas of its own and kept: the engine's
  -- draw makes garbage on every call, and the screen draws a dozen a frame. Kept per game; drawn
  -- again into the same canvases each time a machine opens (V.staleIcons), so an icon pack that
  -- finished loading late still shows.
  local icons = { game = nil, canvas = {}, fresh = {} }
  local function paintIcon(G, canvas, id)
    local Chrome = bagChrome()
    if not (Chrome and Chrome.drawItemIcon) then return false end
    G.push("all")
    local ok = pcall(function()
      G.setCanvas(canvas)
      G.origin()
      G.setScissor()
      G.setShader()
      G.clear(0, 0, 0, 0)
      G.setColor(1, 1, 1, 1)
      Chrome.drawItemIcon(id, 0, 0)
    end)
    G.pop()
    return ok
  end
  function bagIcon(G, id)
    if not G.newCanvas then return nil end
    local game = gameName()
    if icons.game ~= game then icons.game, icons.canvas, icons.fresh = game, {}, {} end
    local c = icons.canvas[id]
    if c == nil then
      local ok, made = pcall(G.newCanvas, 24, 24, { dpiscale = 1 })
      c = ok and made or false
      if c then c:setFilter("nearest", "nearest") end
      icons.canvas[id] = c
    end
    if c and not icons.fresh[id] then
      icons.fresh[id] = true
      if not paintIcon(G, c, id) then
        icons.canvas[id] = false
        return nil
      end
    end
    return c or nil
  end
  function V.staleIcons() icons.fresh = {} end

  local Layer = { isMenu = true }
  local Screen
  Screen = deps.screen({
    session = function()
      local Runtime = engine("src.core.game3.runtime")
      return Runtime and Runtime.getSession and Runtime.getSession() or nil
    end,
    Bag = engine("src.core.game3.bag"),
    -- the Gym Badges the player has (0-8), by the running game's own badge flags
    badges = function()
      local Flags, Space = engine("src.core.game3.scripting.flags"), engine("src.core.game3.scripting.space")
      if not (Flags and Flags.countBadges) then return 8 end
      local store = Space and Space.store
      if not store then
        local Runtime = engine("src.core.game3.runtime")
        store = Runtime and Runtime.getSession and Runtime.getSession()
      end
      return tonumber(Flags.countBadges(store)) or 0
    end,
    se = function(name)
      local Ids, Audio = engine("src.core.game3.se_ids"), engine("src.core.game3.audio")
      local id = Ids and Ids[name]
      if id and Audio and Audio.playSe then Audio.playSe(id) end
    end,
    -- the Bag's own icon, drawn at `size` px (the Bag draws 24 x 24; ItemArt and the TMs' wraps
    -- answer for this mod's items there)
    icon = function(G, id, x, y, size)
      local c = bagIcon(G, id)
      if c then
        G.setColor(1, 1, 1, 1)
        G.draw(c, x, y, 0, size / 24, size / 24)
        return
      end
      local Chrome = bagChrome()
      if not (Chrome and Chrome.drawItemIcon) then return end
      G.push()
      G.translate(x, y)
      G.scale(size / 24, size / 24)
      pcall(Chrome.drawItemIcon, id, 0, 0)
      G.pop()
    end,
    now = function() return love and love.timer and love.timer.getTime() or os.clock() end,
    typeName = function(t)
      local Types = engine("src.core.game3.battle.types")
      return Types and Types.name and Types.name(t)
    end,
    -- the game's Pokédollar sign: glyph 0xB7 of the running cart's own font (the one its Marts
    -- print), scaled so CURRENCY_EM font pixels make a `px` tall line of the screen's text
    currency = function(G, x, y, px, rgba)
      local Font = engine("src.ui.game3.frlg_font")
      if not (Font and Font.drawGlyph) then return nil end
      local k = px / V.CURRENCY_EM
      G.push()
      G.translate(x, y + px * V.CURRENCY_DROP)
      G.scale(k, k)
      -- (the glyph's options, kept per colour: the screen hands the same rgba table each frame)
      local opts = glyphOpts[rgba]
      if not opts then
        opts = { colors = { fg = rgba, shadow = NONE, bg = NONE } }
        glyphOpts[rgba] = opts
      end
      local adv = Font.drawGlyph(V.CURRENCY_GLYPH, 0, 0, opts)
      Font.drawGlyph(V.CURRENCY_GLYPH, V.CURRENCY_BOLD, 0, opts)
      G.pop()
      return ((tonumber(adv) or 7) + V.CURRENCY_BOLD) * k
    end,
    currencyWidth = function(px)
      -- (the glyph's width, read once per game: the font's own lookup makes garbage)
      local game = gameName()
      if signAdvanceFor ~= game then
        local Font = engine("src.ui.game3.frlg_font")
        if not (Font and Font.advance) then return nil end
        local ok, adv = pcall(Font.advance, V.CURRENCY_GLYPH)
        signAdvance, signAdvanceFor = (ok and tonumber(adv) or 7) + V.CURRENCY_BOLD, game
      end
      return signAdvance * px / V.CURRENCY_EM
    end,
    -- the window's safe area (a phone's notch and rounded corners), where the screen lays out
    safeArea = function()
      local SafeArea = engine("src.core.SafeArea")
      if SafeArea and SafeArea.windowRect then return SafeArea.windowRect() end
    end,
    onClose = function()
      local Stack = engine("src.ui.game3.stack")
      if Stack then pcall(Stack.pop, LAYER_ID) end
      pad(false)
    end,
  })
  V.screen = Screen

  function Layer.handleInput(input) Screen.input(input) end
  function Layer.update() end
  function Layer.draw()
    local G = love and love.graphics
    if G then
      G.setColor(0, 0, 0, 1)
      G.rectangle("fill", 0, 0, 240, 160)
      G.setColor(1, 1, 1, 1)
    end
  end

  function V.open(machine)
    if Screen.isOpen() then return false end
    local Stack = engine("src.ui.game3.stack")
    if not Stack then return false end
    V.staleIcons()
    Screen.open(machine, V.stock(machine))
    local ok, err = pcall(Stack.push, LAYER_ID, Layer, { hideBelow = true, fullscreen = true })
    if not ok then
      if log then log:warn("the vending machine could not open: %s", tostring(err)) end
      Screen.close()
      return false
    end
    pad(true)
    return true
  end

  -- ------- the machines on the map

  local spawned = {}   -- raw map id -> machine id -> runtime NPC id
  V.spawned = spawned

  local function alive(mapId, id)
    local Objects = engine("src.core.game3.objects")
    for _, def in ipairs(Objects and Objects.runtimeByMap and Objects.runtimeByMap[mapId] or {}) do
      if def.id == id then return true end
    end
    return false
  end

  function V.byObject(id)
    if not id then return nil end
    for _, ids in pairs(spawned) do
      for machineId, oid in pairs(ids) do
        if oid == id then
          for _, m in ipairs(V.machines) do
            if m.id == machineId then return m end
          end
        end
      end
    end
    return nil
  end

  -- this map's machines placed: true when done, false when none belong here, nil to try again
  -- (the field not running yet)
  function V.ensure()
    local M = engine("src.core.game3.map")
    local mapId = M and M.current
    if not mapId then return nil end
    local game, here = gameName(), bareMap(mapId)
    local any, retry = false, false
    for _, m in ipairs(V.machines) do
      local place = V.placeIn(m, game)
      if place and place.map == here then
        any = true
        spawned[mapId] = spawned[mapId] or {}
        local id = spawned[mapId][m.id]
        if not (id and alive(mapId, id)) then
          local newId, why = mod.world:spawnNpc(place.map, { x = place.x, y = place.y, sprite = spriteId(m),
            movement = "MOVEMENT_TYPE_FACE_DOWN", facing = "down" })
          if newId then
            spawned[mapId][m.id] = newId
          elseif tostring(why):find("overworld", 1, true) then
            retry = true
          elseif log then
            log:warn("vending machine %s not placed: %s", tostring(m.id), tostring(why))
          end
        end
      end
    end
    if retry then return nil end
    return any
  end

  function V.registerSprites()
    local reg = mod.content and mod.content.sprites
    if not reg then return false end
    for _, m in ipairs(V.machines) do
      local ok, err = pcall(reg.register, reg, spriteId(m), { image = mod.path .. "/" .. m.sprite, frames = 1,
        frameWidth = 16, frameHeight = 32, anchorX = V.ANCHOR.x, anchorY = V.ANCHOR.y })
      if not ok and log then log:warn("vending machine sprite %s not registered: %s", tostring(m.id), tostring(err)) end
    end
    return true
  end

  function V.install()
    -- A on a machine
    mod.hooks:wrap("world.talk", function(nxt, game, eo)
      local m = V.byObject(eo and eo.def and eo.def.id)
      if m then
        V.open(m)
        return
      end
      return nxt(game, eo)
    end)
    -- placed on entering a map, and after a load once the field runs
    V.pending = true
    mod.events:on("map.entered", function() V.pending = true end)
    mod.events:on("save.loaded", function() V.pending = true end)
    mod.hooks:wrap("input.step", function(nxt, game, dt, ...)
      local res = nxt(game, dt, ...)
      if V.pending then
        local ok, done = pcall(V.ensure)
        if not ok then
          if log then log:warn("vending machines: %s", tostring(done)) end
          V.pending = false
        elseif done ~= nil then
          V.pending = false
        end
      end
      return res
    end)
    -- the screen over the game
    mod.hooks:wrap("render.hud", function(nxt, game, viewport)
      local res = nxt(game, viewport)
      -- (the layer taken away under it, a reset: the screen goes too)
      local Stack = engine("src.ui.game3.stack")
      if Screen.isOpen() and Stack and Stack.has and not Stack.has(LAYER_ID) then Screen.close() end
      if Screen.isOpen() then
        local G = love and love.graphics
        if G and type(viewport) == "table" then
          pad(true)
          G.push("all")
          G.origin()
          G.setScissor()
          G.setShader()
          G.setBlendMode("alpha")
          local ok, err = pcall(Screen.draw, G, viewport)
          G.pop()
          if not ok and log then log:warn("vending screen draw failed: %s", tostring(err)) end
        end
      end
      return res
    end)
    mod.hooks:wrap("input.pointer", function(nxt, game, ev)
      if Screen.isOpen() then return Screen.pointer(ev) end
      return nxt(game, ev)
    end)
    mod.hooks:wrap("input.wheel", function(nxt, game, dy)
      if Screen.isOpen() then return Screen.wheel(dy) end
      return nxt(game, dy)
    end)
    return true
  end

  return V
end
