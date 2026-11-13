-- The vending machines on Gen 1 / Gen 2: the Gen 3 path's two machines (data/vending.lua: EVO
-- EXPRESS for the evolution items, TM EXPRESS for the new TMs; their pictures, bezels, tabs and
-- badge gates) and its touch screen (src/vending_screen.lua, loaded as it is: everything it needs
-- from a game comes through its deps), in the Celadon / Goldenrod Dept. Stores:
--   Red / Blue / Yellow        EVO EXPRESS on Celadon 4F (19, 2), TM EXPRESS on Celadon 2F (19, 2)
--   Gold / Silver / Crystal    EVO EXPRESS on Goldenrod 4F (10, 1), TM EXPRESS on Goldenrod 5F (4, 1)
-- where they replace the Marts' stock of those items (src/gen12/main.lua stops stocking them).
--
--   - the machines are runtime NPCs (mod.world:spawnNpc), placed once a run per map: on entering
--     their map (or after a load) the input.step hook asks mod.world:npc for ours and spawns it
--     if it is not there (a spawned object stays in its map for the run); nothing goes in a save
--   - A on one: Red's world.talk hook, Gold's world.interacted event (Gold has no talk hook)
--   - the screen: a state of ours on game.stack takes the buttons (the field stops under it); the
--     screen itself is drawn over the whole window from render.hud and takes taps and the wheel
--     (input.pointer / input.wheel); the touch pad is put away while it is up
--   - money: Red save.money, Gold save.player.money; the Bag: src/inventory/Bag.lua (a purchase
--     that would not fit is refused before any money changes hands); badges: Red's
--     Badges.count, Gold's Johto and Kanto badges
-- Item pictures come from this mod's own icon atlas (assets/items/icons.png); a TM is drawn as a
-- disc in its move's type colour by the screen itself.

local Vending = {}

Vending.PLACES = {
  evo = { [1] = { map = "CELADON_MART_4F", x = 19, y = 2, store = "Celadon Dept. Store 4F" },
          [2] = { map = "GOLDENROD_DEPT_STORE_4F", x = 10, y = 1, store = "Goldenrod Dept. Store 4F" } },
  tm = { [1] = { map = "CELADON_MART_2F", x = 19, y = 2, store = "Celadon Dept. Store 2F" },
         [2] = { map = "GOLDENROD_DEPT_STORE_5F", x = 4, y = 1, store = "Goldenrod Dept. Store 5F" } },
}
Vending.ANCHOR = { x = 8, y = 28 }       -- the 16 x 32 picture's foot row on its tile
-- the screen's sounds, in each game's own
Vending.SOUNDS = {
  [1] = { SE_VEND = "Purchase", SE_FAILURE = "Denied", SE_PC_ON = "Turn_On_PC", SE_PC_OFF = "Turn_Off_PC",
          SE_PC_LOGIN = "Turn_On_PC", SE_SELECT = "Press_AB" },
  [2] = { SE_VEND = "Sfx_Transaction", SE_FAILURE = "Sfx_WrongWay", SE_PC_ON = "Sfx_BootPc",
          SE_PC_OFF = "Sfx_ShutDownPc", SE_PC_LOGIN = "Sfx_ChooseAPcOption", SE_SELECT = "Sfx_ReadText2" },
}
-- the evolution machine's tab for an item no tab names (by data/gen12/items.lua kind)
local KIND_TAB = { stone = "STONES", trade = "TRADE", cord = "TRADE", hold = "HELD" }

local function upper(s) return tostring(s):upper() end

-- opts: { mod, generation, require, log, machines (data/vending.lua), screen (src/vending_screen.lua's
-- factory), items (data/gen12/items.lua), itemId (fn slug -> this game's id), tms (data/tms.lua),
-- moves (data/moves.lua: the newer moves' full names), gen3Items (data/items.lua), icons
-- (data/item_icons.lua), typeId (fn type name -> Gen 3 type id) }
function Vending.new(opts)
  local mod, gen, require, log = opts.mod, opts.generation, opts.require, opts.log
  local V = { machines = {}, open = false }
  for _, m in ipairs(opts.machines or {}) do
    local place = Vending.PLACES[m.id] and Vending.PLACES[m.id][gen]
    if place then V.machines[#V.machines + 1] = { m = m, place = place } end
  end

  local function spriteId(m) return "NATIONAL_DEX_VENDING_" .. upper(m.id) end
  local function npcName(m) return "NDX_VENDING_" .. upper(m.id) end
  V.spriteId, V.npcName = spriteId, npcName
  local byName = {}
  for _, e in ipairs(V.machines) do byName[npcName(e.m)] = e.m end

  local engineMods = {}
  local function engine(name)
    local m = engineMods[name]
    if m == nil then
      local ok, v = pcall(require, name)
      m = ok and type(v) == "table" and v or false
      engineMods[name] = m
    end
    return m or nil
  end

  -- ------- the stock
  local tmNumber, tmMove, tmText = {}, {}, {}
  for _, t in ipairs(opts.tms or {}) do
    local slug = t.id:lower()
    tmNumber[slug], tmMove[slug] = t.number, t.move
    tmText[slug] = (t.rse or t.frlg or ""):gsub("\n", " ")
  end
  local fullName = {}
  for _, row in ipairs(opts.moves or {}) do
    if row.full then fullName[row.id] = upper(row.full) end
  end
  local gen3 = {}
  for _, row in ipairs(opts.gen3Items or {}) do gen3[row.slug] = row end
  local kindOf = {}
  for _, row in ipairs(opts.items or {}) do kindOf[row.slug] = row.kind end

  -- one item for sale: { slug, id, name, price, description, tm }
  function V.entry(slug, data)
    local tm = tmNumber[slug]
    local id = tm and upper(slug) or (opts.itemId and opts.itemId(slug))
    local def = id and data.items and data.items[id]
    if type(def) ~= "table" then return nil end
    local text = def.description
    if type(text) ~= "string" or text == "?" or text == "" then
      text = tm and tmText[slug] or (gen3[slug] and gen3[slug].description) or nil
    end
    if type(text) == "string" then text = text:gsub("<NEXT>", " "):gsub("\n", " ") end
    local e = { slug = slug, id = id, name = def.name or id, price = math.floor(tonumber(def.price) or 0),
      description = text }
    if tm then
      local moveId = gen == 1 and def.machine and def.machine.move or def.teaches
      local m = moveId and data.moves and data.moves[moveId]
      e.tm = { number = tm, move = fullName[tmMove[slug]] or (m and m.name) or nil,
        type = m and opts.typeId and opts.typeId(m.type), power = m and m.power, accuracy = m and m.accuracy,
        pp = m and m.pp }
    end
    return e
  end

  function V.stock(machine, data)
    local tabs, seen = {}, {}
    local function add(tab, slug)
      if seen[slug] then return end
      local e = V.entry(slug, data)
      if e and e.price > 0 then
        local gates = machine.badges or {}
        e.badges = gates[slug] or gates[tmMove[slug] or ""] or 0
        tab.entries[#tab.entries + 1] = e
        seen[slug] = true
      end
    end
    local byLabel = {}
    for _, t in ipairs(machine.tabs or {}) do
      local tab = { label = t.label, entries = {} }
      for _, slug in ipairs(t.add or {}) do add(tab, slug) end
      tabs[#tabs + 1] = tab
      byLabel[t.label] = tab
    end
    -- the evolution items this game sells that no tab names (Red's Metal Coat, King's Rock...)
    if machine.id == "evo" then
      for _, row in ipairs(opts.items or {}) do
        local tab = byLabel[KIND_TAB[row.kind] or ""]
        if tab then add(tab, row.slug) end
      end
    end
    local out = {}
    for _, tab in ipairs(tabs) do if #tab.entries > 0 then out[#out + 1] = tab end end
    return out
  end

  -- ------- what the screen needs from the game
  local current          -- the game the machine was opened in
  local function save() return current and current.save end
  local Bag = engine("src.inventory.Bag")
  local function copyTable(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
  end
  local bagApi = {
    get = function(s, id) return tonumber((s.inventory or {})[id]) or 0 end,
    canAdd = function(s, id, qty)
      if not Bag then return false end
      local trial = { inventory = copyTable(s.inventory), bagOrder = s.bagOrder and copyTable(s.bagOrder),
        bagStacks = s.bagStacks and copyTable(s.bagStacks) }
      local ok, added = pcall(Bag.add, trial, id, qty, current and current.data)
      return ok and added and true or false
    end,
    add = function(s, id, qty)
      if not Bag then return false end
      return Bag.add(s, id, qty, current and current.data) and true or false
    end,
  }
  local session = setmetatable({}, {
    __index = function(_, k)
      local s = save()
      if not s then return nil end
      if k == "bag" then return s end
      if k == "money" then
        if gen == 1 then return tonumber(s.money) or 0 end
        return tonumber(s.player and s.player.money) or 0
      end
    end,
    __newindex = function(_, k, v)
      local s = save()
      if not (s and k == "money") then return end
      v = math.max(0, math.min(999999, math.floor(tonumber(v) or 0)))
      if gen == 1 then s.money = v elseif s.player then s.player.money = v end
    end,
  })

  local padPrev, padHidden = nil, false
  local function pad(hide)
    local TC = engine("src.core.TouchControls")
    if not TC then return end
    if hide and not padHidden then
      padPrev, padHidden = TC.active, true
      TC.active = false
      if TC.reset then pcall(TC.reset, TC) end
    elseif not hide and padHidden then
      padHidden = false
      TC.active = padPrev
      if TC.reset then pcall(TC.reset, TC) end
    end
  end

  -- the icon atlas: slug -> quad
  local atlas
  local function iconFor(id)
    if atlas == nil then
      atlas = false
      local G = love and love.graphics
      if G and G.newImage and opts.icons then
        local ok, img = pcall(G.newImage, mod.path .. "/assets/items/icons.png")
        if ok and img then
          pcall(img.setFilter, img, "nearest", "nearest")
          atlas = { image = img, quads = {} }
        end
      end
    end
    if not atlas then return nil end
    local q = atlas.quads[id]
    if q == nil then
      q = false
      for _, row in ipairs(opts.items or {}) do
        local slugId = opts.itemId and opts.itemId(row.slug)
        local g = gen3[row.slug]
        local cell = g and opts.icons.cells[g.index]
        if slugId == id and cell then
          q = love.graphics.newQuad(cell.x, cell.y, opts.icons.size or 24, opts.icons.size or 24,
            atlas.image:getDimensions())
          break
        end
      end
      atlas.quads[id] = q
    end
    return q or nil
  end

  local layer = { isMenu = true }
  local Screen
  Screen = opts.screen({
    session = function() return save() and session or nil end,
    Bag = bagApi,
    badges = function()
      local s = save()
      if not s then return 8 end
      if gen == 1 then
        local B = engine("src.inventory.Badges")
        if B and B.count then
          local ok, n = pcall(B.count, current.data, s)
          if ok and tonumber(n) then return tonumber(n) end
        end
        return 0
      end
      local n = 0
      local p = s.player or {}
      for _, list in ipairs({ p.badges or {}, p.kantoBadges or {} }) do
        for _, v in pairs(list) do if v then n = n + 1 end end
      end
      return n
    end,
    se = function(name)
      local Sound = engine("src.core.Sound")
      local sfx = Vending.SOUNDS[gen][name]
      if Sound and sfx and current then pcall(Sound.play, current.data, sfx) end
    end,
    icon = function(G, id, x, y, size)
      local q = iconFor(id)
      if not q then return end
      G.setColor(1, 1, 1, 1)
      G.draw(atlas.image, q, x, y, 0, size / 24, size / 24)
    end,
    now = function() return love and love.timer and love.timer.getTime() or os.clock() end,
    safeArea = function()
      local SafeArea = engine("src.core.SafeArea")
      if SafeArea and SafeArea.windowRect then return SafeArea.windowRect() end
    end,
    onClose = function()
      local stack = current and current.stack
      if stack and stack:top() == layer then stack:pop() end
      pad(false)
    end,
  })
  V.screen = Screen

  function layer.update()
    if current and current.input then Screen.input(current.input) end
  end
  function layer.draw() end

  function V.open(machine, game)
    if Screen.isOpen() or not (game and game.stack) then return false end
    current = game
    Screen.open(machine, V.stock(machine, game.data))
    game.stack:push(layer)
    pad(true)
    return true
  end

  -- ------- the machines on their maps
  function V.registerSprites()
    local reg = mod.content and mod.content.sprites
    if not reg then return 0 end
    local n = 0
    for _, e in ipairs(V.machines) do
      local ok, err = pcall(reg.register, reg, spriteId(e.m), { image = mod.path .. "/" .. e.m.sprite,
        frames = 1, frameWidth = 16, frameHeight = 32, anchorX = Vending.ANCHOR.x, anchorY = Vending.ANCHOR.y,
        trueColor = true })
      if ok then n = n + 1 elseif log then log:warn("vending machine picture %s: %s", e.m.id, tostring(err)) end
    end
    return n
  end

  -- this map's machine placed: true when done or none belongs here, nil to try again
  function V.ensure()
    local world = mod.world
    if not world then return true end
    local okC, here = pcall(world.current, world)
    local mapId = okC and type(here) == "table" and here.mapId
    if not mapId then return nil end
    local retry = false
    for _, e in ipairs(V.machines) do
      if e.place.map == mapId then
        local okN, npc = pcall(world.npc, world, mapId, npcName(e.m))
        if not (okN and npc) then
          local def = { name = npcName(e.m), sprite = spriteId(e.m), x = e.place.x, y = e.place.y }
          if gen == 1 then def.movement, def.range = "STAY", "DOWN" end
          local okS, id, why = pcall(world.spawnNpc, world, mapId, def)
          if not (okS and id) then
            retry = true
            V.lastError = okS and why or id
          end
        end
      end
    end
    if retry then return nil end
    return true
  end

  function V.install()
    V.pending = true
    mod.events:on("map.entered", function() V.pending = true; V.tries = 0 end)
    mod.events:on("save.loaded", function() V.pending = true; V.tries = 0 end)
    mod.hooks:wrap("input.step", function(nxt, game, ...)
      local r = nxt(game, ...)
      if V.pending then
        local ok, done = pcall(V.ensure)
        V.tries = (V.tries or 0) + 1
        if (ok and done) or not ok or V.tries > 600 then
          if (not ok or not done) and log then
            log:warn("vending machine not placed: %s", tostring(ok and V.lastError or done))
          end
          V.pending = false
        end
      end
      return r
    end)
    if gen == 1 then
      mod.hooks:wrap("world.talk", function(nxt, ow, npc, ...)
        local m = npc and npc.def and byName[npc.def.name]
        if m then
          V.open(m, ow and ow.game or mod.game)
          return
        end
        return nxt(ow, npc, ...)
      end)
    else
      mod.events:on("world.interacted", function(ev)
        local t = type(ev) == "table" and ev.target
        local m = ev and ev.kind == "npc" and t and t.def and byName[t.def.name]
        if m then V.open(m, mod.game) end
      end)
    end
    mod.hooks:wrap("render.hud", function(nxt, game, viewport, ...)
      local r = nxt(game, viewport, ...)
      if Screen.isOpen() then
        if current and current.stack then
          local inStack = false
          for _, s in ipairs(current.stack.states or {}) do if s == layer then inStack = true end end
          if not inStack then Screen.close(); pad(false); return r end
        end
        local G = love and love.graphics
        if G and type(viewport) == "table" then
          G.push("all")
          G.origin()
          G.setScissor()
          G.setShader()
          G.setBlendMode("alpha")
          local ok, err = pcall(Screen.draw, G, viewport)
          G.pop()
          if not ok and log and not V.warned then
            V.warned = true
            log:warn("vending screen draw failed: %s", tostring(err))
          end
        end
      end
      return r
    end)
    mod.hooks:wrap("input.pointer", function(nxt, game, ev, ...)
      if Screen.isOpen() then return Screen.pointer(ev) end
      return nxt(game, ev, ...)
    end)
    mod.hooks:wrap("input.wheel", function(nxt, game, dy, ...)
      if Screen.isOpen() then return Screen.wheel(dy) end
      return nxt(game, dy, ...)
    end)
    return true
  end

  return V
end

return Vending
