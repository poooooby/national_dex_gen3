-- A vending machine's screen (src/vending.lua opens it on the A press): a touch screen in a bezel
-- coloured like the machine's sprite (data/vending.lua `bezel`). Tabs along the top, a grid of the
-- stock (icon, and the price or the TM number), the chosen item's card on the right (name, TM move
-- and its type / power / accuracy / PP, description, how many are in the Bag, the amount and BUY),
-- the tray below where a bought item drops. Buttons and touch both drive all of it:
--   grid     D-pad moves (Up from the top row: the tabs), A chooses, L / R change tab, B leaves
--   tabs     Left / Right change tab, Down / A / B back to the grid
--   card     Left / Right amount -1 / +1 (wrapping), Up / Down +10 / -10, A buys, B back to the grid
--   confirm  any direction toggles YES / NO, A answers (a purchase goes back to the grid), B is NO
--   touch    tap a tab (or the arrows at the strip's ends, which also show where L and R go), a
--            tile, - / +, BUY, YES / NO or the close button; drag the grid (or the mouse wheel)
--            to scroll
-- Drawn over the whole window (its safe area) from render.hud, laid out for its shape: landscape
-- (a page 160 units tall, as wide as the window allows up to MAX_WIDTH: the card beside the grid,
-- more columns when wider) or portrait (180 units wide: the card under the grid, more rows when
-- taller). Taps are hit-tested against the rectangles the last draw recorded (window units).
--   S = vending_screen(deps)
--   deps: session() -> the game session (money, bag); Bag (src.core.game3.bag); se(name) plays a
--         sound effect; icon(G, id, x, y, size) draws an item's Bag icon; now() -> seconds;
--         typeName(id); onClose(); safeArea() -> x, y, w, h (window units) or nil;
--         currency(G, x, y, px, rgba) draws the game font's Pokédollar sign as tall as a px font
--         and returns its width (px), currencyWidth(px) -> that width (without them: "$")
--   S.open(machine, tabs) ; S.close() ; S.isOpen() ; S.input(input) ; S.pointer(ev) -> true
--   S.wheel(dy) ; S.draw(G, viewport) ; S.state() (tests)
--   tabs: { { label, entries = { { id, name, price, description, tm = { number, move, type, power,
--         accuracy, pp } | nil } } } }

return function(deps)
  local floor, max, min, abs, ceil = math.floor, math.max, math.min, math.abs, math.ceil
  -- (COLS / ROWS: the grid before the first draw lays it out for the window)
  local S = { COLS = 4, ROWS = 3, MAX_QTY = 99 }
  -- held D-pad: first repeat after REPEAT_START steps, then every REPEAT_EVERY (the game's menus)
  S.REPEAT_START, S.REPEAT_EVERY = 20, 4
  -- the money box's flash when there isn't enough (seconds, flashes)
  S.MONEY_FLASH, S.MONEY_FLASHES = 0.6, 2
  -- the boot (seconds): the glass black, a line opening it like a tube, the W logo with its
  -- loading bar, then the logo zooming away to reveal the shop. Any button or tap skips to the
  -- reveal; the shop takes input from the reveal on.
  S.BOOT = { BLACK = 0.35, LINE = 0.18, LOGO = 1.1, REVEAL = 0.35 }
  local function bootLength() return S.BOOT.BLACK + S.BOOT.LINE + S.BOOT.LOGO + S.BOOT.REVEAL end
  -- the page, in units: a landscape window is 160 tall and MIN_WIDTH .. MAX_WIDTH wide (centred
  -- past it), a portrait one (narrower than PORTRAIT_ASPECT) 180 wide and at least 260 tall
  S.PAGE = { HEIGHT = 160, MIN_WIDTH = 200, MAX_WIDTH = 380, PORTRAIT_WIDTH = 180, PORTRAIT_HEIGHT = 260,
             PORTRAIT_ASPECT = 1.15 }
  -- a tile's size the grid aims for (columns and rows are as many as fit), the gap between tiles
  S.TILE = { w = 34, h = 26, maxH = 40, gap = 2 }

  -- move types' colours (the modern games'), by Gen 3 type id; 18 is this mod's Fairy
  S.TYPE_COLORS = {
    [0] = { 168, 167, 122 }, [1] = { 194, 46, 40 }, [2] = { 169, 143, 243 }, [3] = { 163, 62, 161 },
    [4] = { 226, 191, 101 }, [5] = { 182, 161, 54 }, [6] = { 166, 185, 26 }, [7] = { 115, 87, 151 },
    [8] = { 183, 183, 206 }, [9] = { 104, 160, 144 }, [10] = { 238, 129, 48 }, [11] = { 99, 144, 240 },
    [12] = { 122, 199, 76 }, [13] = { 247, 208, 44 }, [14] = { 249, 85, 135 }, [15] = { 150, 217, 214 },
    [16] = { 111, 53, 252 }, [17] = { 112, 87, 70 }, [18] = { 214, 133, 173 },
  }
  local TYPE_NAMES = { [0] = "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST",
    "STEEL", "???", "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC", "ICE", "DRAGON", "DARK", "FAIRY" }

  S.TEXT = {
    noMoney = "You don't have enough money.",
    noRoom = "There's no more room in the BAG.",
    soldOut = "Nothing for sale here.",
    hints = {
      grid = { { "A", "Choose" }, { "B", "Exit" }, { "L R", "Tab" } },
      tabs = { { "< >", "Tab" }, { "A", "Items" }, { "B", "Back" } },
      card = { { "< >", "Amount" }, { "A", "Buy" }, { "B", "Back" } },
      confirm = { { "A", "OK" }, { "B", "Cancel" } },
      boot = { { "A", "Skip" } },
    },
  }

  local r = nil   -- the open machine

  local function now() return deps.now and deps.now() or 0 end
  local function se(name) if deps.se then pcall(deps.se, name) end end
  local function session() return deps.session and deps.session() or nil end
  local function money()
    local s = session()
    return max(0, floor(tonumber(s and s.money) or 0))
  end
  local function inBag(id)
    local s = session()
    if not (s and s.bag and deps.Bag and deps.Bag.get) then return 0 end
    local ok, n = pcall(deps.Bag.get, s.bag, id)
    return ok and tonumber(n) or 0
  end
  local function typeName(t)
    if deps.typeName then
      local ok, n = pcall(deps.typeName, t)
      if ok and type(n) == "string" and n ~= "" then return n:upper() end
    end
    return TYPE_NAMES[t] or "???"
  end
  -- an amount's digits, in thousands ("2,100"); the Pokédollar sign is drawn before it (sign())
  local function amount(n)
    local s = tostring(floor(n))
    repeat
      local k
      s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return s
  end
  S.amount = amount

  -- ------- the stock

  local function tabsFor(machine, given)
    local tabs = {}
    if #given > 1 then
      local all, seen = {}, {}
      for _, t in ipairs(given) do
        for _, e in ipairs(t.entries) do
          if not seen[e.id] then
            seen[e.id] = true
            all[#all + 1] = e
          end
        end
      end
      tabs[1] = { label = "ALL", entries = all }
    end
    for _, t in ipairs(given) do tabs[#tabs + 1] = { label = t.label, entries = t.entries } end
    if machine.typeTabs then
      local byType, order = {}, {}
      for _, e in ipairs(tabs[1] and tabs[1].entries or {}) do
        local t = e.tm and tonumber(e.tm.type)
        if t then
          if not byType[t] then
            byType[t] = {}
            order[#order + 1] = t
          end
          table.insert(byType[t], e)
        end
      end
      table.sort(order)
      for _, t in ipairs(order) do
        tabs[#tabs + 1] = { label = typeName(t), entries = byType[t], type = t }
      end
    end
    return tabs
  end

  local function list() return r and r.tabs[r.tab] and r.tabs[r.tab].entries or {} end
  local function selected() return list()[r and r.cursor or 0] end
  local function rowsOf(n) return ceil(n / r.cols) end
  local function maxScroll() return max(0, rowsOf(#list()) - r.rows) end
  local function clampScroll(v) return max(0, min(maxScroll(), v)) end
  local function ensureVisible()
    local row = floor((r.cursor - 1) / r.cols)
    local scroll = floor(r.scroll + 0.5)
    if row < scroll then scroll = row end
    if row > scroll + r.rows - 1 then scroll = row - r.rows + 1 end
    r.scroll = clampScroll(scroll)
  end
  -- (any amount up to MAX_QTY, whatever the money: one that can't be paid for greys BUY, and
  -- BUY says why; capping it by the money left a player who can afford one with an amount that
  -- wouldn't move)
  local function maxQty() return S.MAX_QTY end

  local function toast(text, bad)
    r.toast = { text = text, bad = bad, t = now() }
    -- (too little money: the money box flashes red too)
    if text == S.TEXT.noMoney then r.moneyFlash = now() end
  end

  -- ------- the actions (buttons and taps both end here)

  function S.open(machine, tabs)
    r = { machine = machine, tabs = tabsFor(machine, tabs or {}), tab = 1, cursor = 1, scroll = 0,
          focus = "grid", qty = 1, yes = true, t0 = now(), held = {}, hit = {}, tabScroll = 0,
          cols = S.COLS, rows = S.ROWS, shown = 0,
          -- (the A that opened it is still down: nothing until it is let go)
          waitRelease = true }
    se("SE_PC_ON")
    return true
  end

  -- seconds into the boot, or nil once it has run (or was skipped) to the reveal's end
  local function bootAge()
    if not r or r.booted then return nil end
    local age = now() - r.t0
    if age >= bootLength() then
      r.booted = true
      return nil
    end
    return age
  end
  -- still booting: the shop doesn't answer yet
  local function booting()
    local age = bootAge()
    return age ~= nil and age < bootLength() - S.BOOT.REVEAL
  end
  function S.booting() return r ~= nil and booting() end
  function S.skipBoot()
    if booting() then r.t0 = now() - (bootLength() - S.BOOT.REVEAL) end
  end

  function S.close()
    if not r then return end
    r = nil
    se("SE_PC_OFF")
    if deps.onClose then pcall(deps.onClose) end
  end

  function S.isOpen() return r ~= nil end
  function S.state() return r end

  -- (keepFocus: the D-pad on the tabs stays there)
  function S.setTab(i, keepFocus)
    if not r or #r.tabs == 0 then return end
    i = ((i - 1) % #r.tabs) + 1
    if i ~= r.tab then se("SE_SELECT") end
    r.tab, r.cursor, r.scroll, r.shown, r.qty = i, 1, 0, 0, 1
    if not (keepFocus and r.focus == "tabs") then r.focus = "grid" end
  end

  function S.moveCursor(d)
    local n = #list()
    if n == 0 then return end
    local c = r.cursor
    if d == 1 or d == -1 then
      c = ((c - 1 + d) % n) + 1
    else
      c = c + d
      if c > n then
        -- down from a row above the last: onto the last item
        if floor((r.cursor - 1) / r.cols) < rowsOf(n) - 1 then c = n else return end
      elseif c < 1 then
        return
      end
    end
    if c ~= r.cursor then
      r.cursor = c
      se("SE_SELECT")
    end
    ensureVisible()
  end

  function S.choose(i)
    if not list()[i] then return end
    r.cursor, r.focus, r.qty = i, "card", 1
    ensureVisible()
    se("SE_SELECT")
  end

  function S.setQty(q, wrap)
    local top = maxQty(selected())
    if wrap then
      if q < 1 then q = top elseif q > top then q = 1 end
    end
    q = max(1, min(top, q))
    if q ~= r.qty then se("SE_SELECT") end
    r.qty = q
  end

  -- why the chosen amount can't be bought, or nil
  local function refusal(e, qty)
    if (e.price or 0) * qty > money() then return S.TEXT.noMoney end
    local s = session()
    local Bag = deps.Bag
    if not (s and Bag and Bag.canAdd) then return S.TEXT.noRoom end
    if not s.bag and Bag.new then s.bag = Bag.new() end
    local ok, can = pcall(Bag.canAdd, s.bag, e.id, qty)
    if not (ok and can) then return S.TEXT.noRoom end
    return nil
  end

  -- what the card shows from the Bag (how many are in it, whether this amount can be bought),
  -- asked again only when the item, the amount or the money changes, or after a purchase: the
  -- Bag's own calls make garbage, and the card is drawn every frame
  local function cardFacts(e)
    local m = money()
    if r.factsFor ~= e or r.factsQty ~= r.qty or r.factsMoney ~= m then
      r.factsFor, r.factsQty, r.factsMoney = e, r.qty, m
      r.factsInBag = inBag(e.id)
      r.factsAble = refusal(e, r.qty) == nil
    end
    return r.factsInBag, r.factsAble
  end
  S.cardFacts = cardFacts

  function S.askBuy()
    local e = selected()
    if not e then return end
    r.focus = "card"
    local why = refusal(e, r.qty)
    if why then
      toast(why, true)
      se("SE_FAILURE")
      return
    end
    r.focus, r.yes = "confirm", true
    se("SE_SELECT")
  end

  -- the purchase: true when the item went into the Bag and the money came off
  function S.buy()
    local e = selected()
    if not e then return false end
    r.focus = "card"
    local qty = r.qty
    local why = refusal(e, qty)
    if why then
      toast(why, true)
      se("SE_FAILURE")
      return false
    end
    local s = session()
    local ok, added = pcall(deps.Bag.add, s.bag, e.id, qty)
    if not (ok and added) then
      toast(S.TEXT.noRoom, true)
      se("SE_FAILURE")
      return false
    end
    s.money = money() - (e.price or 0) * qty
    -- (bought: back to browsing, on the same item; the card's Bag numbers asked again)
    r.qty, r.focus, r.factsFor = 1, "grid", nil
    r.vend = { id = e.id, entry = e, t = now() }
    toast((qty > 1 and (e.name .. " x" .. qty) or e.name) .. " dropped down.")
    se("SE_VEND")
    if deps.onBuy then pcall(deps.onBuy, e, qty) end
    return true
  end

  -- ------- buttons

  local DIRS = { "up", "down", "left", "right" }
  local function repeated(input, key)
    local held = r.held
    if input:wasPressed(key) then
      held[key] = 0
      return true
    end
    local okD, down = pcall(input.isDown, input, key)
    if not (okD and down) then
      held[key] = nil
      return false
    end
    held[key] = (held[key] or 0) + 1
    local n = held[key] - S.REPEAT_START
    return n >= 0 and n % S.REPEAT_EVERY == 0
  end

  function S.input(input)
    if not (r and input) then return end
    if r.waitRelease then
      local okD, down = pcall(input.isDown, input, "a")
      if input:wasPressed("a") or (okD and down) then return end
      r.waitRelease = false
    end
    if booting() then
      for _, k in ipairs({ "a", "b", "start", "select", "l", "r", "up", "down", "left", "right" }) do
        if input:wasPressed(k) then return S.skipBoot() end
      end
      return
    end
    local p = {}
    for _, k in ipairs(DIRS) do p[k] = input.isDown and repeated(input, k) or input:wasPressed(k) end
    local function pressed(k) return input:wasPressed(k) end
    if r.focus == "confirm" then
      if p.up or p.down or p.left or p.right then
        r.yes = not r.yes
        se("SE_SELECT")
      elseif pressed("a") then
        if r.yes then S.buy() else r.focus = "card"; se("SE_SELECT") end
      elseif pressed("b") then
        r.focus = "card"
        se("SE_SELECT")
      end
      return
    end
    if pressed("l") then return S.setTab(r.tab - 1, true) end
    if pressed("r") then return S.setTab(r.tab + 1, true) end
    if r.focus == "tabs" then
      if p.left then S.setTab(r.tab - 1, true)
      elseif p.right then S.setTab(r.tab + 1, true)
      elseif pressed("a") or pressed("b") or p.down then
        r.focus = "grid"
        se("SE_SELECT")
      end
      return
    end
    if r.focus == "card" then
      if pressed("b") then
        r.focus = "grid"
        se("SE_SELECT")
      elseif pressed("a") then S.askBuy()
      elseif p.left then S.setQty(r.qty - 1, true)
      elseif p.right then S.setQty(r.qty + 1, true)
      elseif p.up then S.setQty(r.qty + 10)
      elseif p.down then S.setQty(r.qty - 10)
      end
      return
    end
    if pressed("b") then return S.close() end
    if pressed("a") then return S.choose(r.cursor) end
    if p.left then S.moveCursor(-1)
    elseif p.right then S.moveCursor(1)
    elseif p.up then
      -- Up from the top row (a fresh press, not a held one running on): the tabs
      if r.cursor <= r.cols or #list() == 0 then
        if pressed("up") and #r.tabs > 1 then
          r.focus = "tabs"
          se("SE_SELECT")
        end
      else
        S.moveCursor(-r.cols)
      end
    elseif p.down then S.moveCursor(r.cols)
    end
  end

  function S.wheel(dy)
    if not r then return false end
    if booting() then return true end
    r.scroll = clampScroll(floor(r.scroll + 0.5) - (dy > 0 and 1 or (dy < 0 and -1 or 0)))
    return true
  end

  -- a window resized: the grid's shape from the draw that saw it
  local function reshape(cols, rows)
    if cols == r.cols and rows == r.rows then return end
    r.cols, r.rows = cols, rows
    r.scroll = clampScroll(r.scroll)
    if r.focus ~= "tabs" then ensureVisible() end
  end

  -- ------- touch and mouse (window units, against the last draw's rectangles)

  local function inside(t, x, y) return x >= t[1] and y >= t[2] and x < t[1] + t[3] and y < t[2] + t[4] end

  local function tap(x, y)
    for i = #r.hit, 1, -1 do
      local h = r.hit[i]
      if inside(h, x, y) then
        local kind, arg = h.kind, h.arg
        if kind == "close" then S.close()
        elseif kind == "skip" then S.skipBoot()
        elseif kind == "dim" or kind == "no" then r.focus = "card"; se("SE_SELECT")
        elseif kind == "yes" then S.buy()
        elseif kind == "tab" then S.setTab(arg)
        elseif kind == "prevTab" then S.setTab(r.tab - 1)
        elseif kind == "nextTab" then S.setTab(r.tab + 1)
        elseif kind == "tile" then
          if not (arg == r.cursor and r.focus == "card") then S.choose(arg) end
        elseif kind == "minus" then r.focus = "card"; S.setQty(r.qty - 1, true)
        elseif kind == "plus" then r.focus = "card"; S.setQty(r.qty + 1, true)
        elseif kind == "buy" then S.askBuy()
        end
        return true
      end
    end
    return false
  end
  S.tap = function(x, y) return r ~= nil and tap(x, y) end

  function S.pointer(ev)
    if not (r and type(ev) == "table") then return false end
    local x, y = tonumber(ev.x) or 0, tonumber(ev.y) or 0
    local press = r.press
    if ev.phase == "pressed" then
      local grid = r.gridRect
      r.press = { id = ev.id, x = x, y = y, scroll = r.scroll, drag = false,
                  grid = grid ~= nil and r.focus ~= "confirm" and inside(grid, x, y) }
    elseif ev.phase == "moved" then
      if press and press.id == ev.id and press.grid then
        local rowPx = r.rowPx or (S.TILE.h + S.TILE.gap) * (r.sc or 1)
        local dy = y - press.y
        if press.drag or abs(dy) > 3 * (r.sc or 1) then
          press.drag = true
          r.scroll = clampScroll(press.scroll - dy / rowPx)
          r.shown = r.scroll
        end
      end
    elseif ev.phase == "released" then
      if press and press.id == ev.id then
        r.press = nil
        if press.drag then
          r.scroll = clampScroll(floor(r.scroll + 0.5))
        else
          tap(x, y)
        end
      end
    elseif ev.phase == "cancelled" then
      if press and press.id == ev.id then r.press = nil end
    end
    return true
  end

  -- ------- drawing

  local fonts = {}
  local function font(G, px)
    px = max(6, floor(px + 0.5))
    local f = fonts[px]
    if not f then
      local ok, made = pcall(G.newFont, px)
      f = ok and made or G.getFont()
      fonts[px] = f
    end
    return f
  end

  -- colours are { r, g, b [, a] }: r, g, b 0..255, a 0..1
  local WHITE, BLACK = { 255, 255, 255 }, { 0, 0, 0 }
  -- derived colours are made once and kept (by their parents and the amount, in 64ths), so the
  -- same table comes back every frame: no garbage, and the gradient meshes can be kept by them.
  -- Bounded: a long animation through many amounts starts the store over.
  local mixed, mixedCount = {}, 0
  local function memo(a, b, t)
    t = floor(t * 64 + 0.5)
    local byB = mixed[a]
    if not byB then
      byB = {}
      mixed[a] = byB
    end
    local byT = byB[b]
    if not byT then
      byT = {}
      byB[b] = byT
    end
    return byT, t
  end
  local function mix(a, b, t)
    local cache, k = memo(a, b, t)
    local c = cache[k]
    if not c then
      if mixedCount > 4000 then
        mixed, mixedCount = {}, 0
        cache, k = memo(a, b, t)
      end
      t = k / 64
      c = { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t,
            (a[4] or 1) + ((b[4] or 1) - (a[4] or 1)) * t }
      cache[k] = c
      mixedCount = mixedCount + 1
    end
    return c
  end
  local function light(c, t) return mix(c, WHITE, t) end
  local function dark(c, t) return mix(c, BLACK, t) end
  local FADE = {}
  local function fade(c, a)
    local cache, k = memo(c, FADE, a)
    local f = cache[k]
    if not f then
      f = { c[1], c[2], c[3], k / 64 }
      cache[k] = f
      mixedCount = mixedCount + 1
    end
    return f
  end

  -- a rounded rectangle's outline, as points (rad 0: its corners)
  local function roundPoints(x, y, w, h, rad)
    rad = max(0, min(rad, w / 2, h / 2))
    local seg = rad > 0 and max(2, min(10, ceil(rad / 1.5))) or 0
    local pts, hp = {}, math.pi / 2
    for k, c in ipairs({ { x + w - rad, y + rad }, { x + w - rad, y + h - rad }, { x + rad, y + h - rad },
                          { x + rad, y + rad } }) do
      local a0 = -hp + (k - 1) * hp
      for i = 0, seg do
        local a = a0 + (seg == 0 and 0 or hp * i / seg)
        pts[#pts + 1] = { c[1] + math.cos(a) * rad, c[2] + math.sin(a) * rad }
      end
    end
    return pts
  end

  -- a rounded rectangle shaded from `top` to `foot` (window pixels): a fan mesh, kept by its
  -- colours (the same tables every frame: constants or mix()'s) and size (the layout is steady, so
  -- the same few are drawn every frame); flat without meshes
  local meshes, meshCount = {}, 0
  -- (alpha: the whole of it fainter, the same mesh)
  local function gradient(G, x, y, w, h, rad, top, foot, alpha)
    if w <= 0 or h <= 0 then return end
    local byFoot = meshes[top]
    if not byFoot then
      byFoot = {}
      meshes[top] = byFoot
    end
    local bySize = byFoot[foot]
    if not bySize then
      bySize = {}
      byFoot[foot] = bySize
    end
    local key = floor(w * 2) + floor(h * 2) * 16384 + floor(rad * 2) * 268435456
    local m = bySize[key]
    if m == nil then
      local function vertex(px, py)
        local c = mix(top, foot, py / h)
        return { px, py, 0, 0, c[1] / 255, c[2] / 255, c[3] / 255, c[4] }
      end
      local verts = { vertex(w / 2, h / 2) }
      for _, p in ipairs(roundPoints(0, 0, w, h, rad)) do verts[#verts + 1] = vertex(p[1], p[2]) end
      verts[#verts + 1] = verts[2]
      local ok, made = pcall(G.newMesh, verts, "fan", "static")
      m = ok and made or false
      if meshCount > 400 then
        meshes, meshCount = {}, 0
        bySize = {}
        meshes[top] = { [foot] = bySize }
      end
      bySize[key], meshCount = m, meshCount + 1
    end
    if m then
      G.setColor(1, 1, 1, alpha or 1)
      G.draw(m, x, y)
    else
      local c = mix(top, foot, 0.5)
      G.setColor(c[1] / 255, c[2] / 255, c[3] / 255, (c[4] or 1) * (alpha or 1))
      G.rectangle("fill", x, y, w, h, rad, rad)
    end
  end

  -- a TM: a disc in its move type's colour (the same in every game; Ruby and Sapphire have no TM
  -- icon art), at window pixels
  local function disc(G, x, y, size, c)
    local rad = size / 2
    local cx, cy = x + rad, y + rad
    c = c or { 160, 160, 170 }
    gradient(G, x + rad * 0.08, y + rad * 0.08, rad * 1.84, rad * 1.84, rad * 0.92, light(c, 0.25), dark(c, 0.15))
    G.setColor(1, 1, 1, 0.4)
    G.arc("fill", cx, cy, rad * 0.8, -math.pi * 0.95, -math.pi * 0.55)
    G.arc("fill", cx, cy, rad * 0.8, math.pi * 0.05, math.pi * 0.45)
    G.setColor(c[1] / 400, c[2] / 400, c[3] / 400, 1)
    G.setLineWidth(max(1, size / 18))
    G.circle("line", cx, cy, rad * 0.92)
    G.setColor(0.95, 0.95, 0.97, 1)
    G.circle("fill", cx, cy, rad * 0.3)
    G.setColor(c[1] / 400, c[2] / 400, c[3] / 400, 1)
    G.circle("fill", cx, cy, rad * 0.11)
  end
  local function itemIcon(G, e, x, y, size)
    if e.tm then
      disc(G, x + size * 0.08, y + size * 0.08, size * 0.84, S.TYPE_COLORS[e.tm.type])
    elseif deps.icon then
      pcall(deps.icon, G, e.id, x, y, size)
    end
  end

  -- what an entry shows, worked out once (weak: entries come and go with the machine)
  local shown = setmetatable({}, { __mode = "k" })
  local function entryText(e)
    local c = shown[e]
    if c then return c end
    c = { lines = {} }
    for line in tostring(e.description or ""):gmatch("[^\n]+") do c.lines[#c.lines + 1] = line end
    if e.tm then
      c.tag = "TM" .. tostring(e.tm.number)
      c.pricePrefix = c.tag .. "  ·  "
      local function num(v, none) v = tonumber(v) or 0; return v > none and tostring(v) or "---" end
      c.stats = { "PWR " .. num(e.tm.power, 1), "ACC " .. num(e.tm.accuracy, 0), "PP " .. num(e.tm.pp, 0) }
    end
    shown[e] = c
    return c
  end
  -- numbers as text, kept ("IN BAG  3", "×12", amounts)
  local function textCache(make)
    local cache, count = {}, 0
    return function(n)
      local v = cache[n]
      if not v then
        if count > 500 then cache, count = {}, 0 end
        v = make(n)
        cache[n], count = v, count + 1
      end
      return v
    end
  end
  local amountText = textCache(amount)

  -- the page's rectangles (units) for a pw x ph page
  function S.layout(pw, ph, portrait)
    local L = { pw = pw, ph = ph, portrait = portrait }
    L.close = { pw - 21, 4.5, 15, 15 }
    L.footY = portrait and ph - 42 or ph - 30
    L.glass = { 6, 22, pw - 12, L.footY - 26 }
    local g = L.glass
    local gx2, gy2 = g[1] + g[3], g[2] + g[4]
    local stripX1
    if portrait then
      local ch = max(84, min(112, floor(g[4] * 0.36)))
      L.card = { g[1] + 4, gy2 - 4 - ch, g[3] - 8, ch }
      stripX1 = gx2 - 4
    else
      local cw = max(70, min(104, floor(g[3] * 0.31)))
      L.card = { gx2 - 4 - cw, g[2] + 3, cw, g[4] - 6 }
      stripX1 = L.card[1] - 4
    end
    local x0, ty = g[1] + 4, g[2] + 3
    L.prevTab = { x0, ty, 11, 11 }
    L.nextTab = { stripX1 - 11, ty, 11, 11 }
    L.tabs = { x0 + 13, ty, stripX1 - 13 - x0 - 13, 11 }
    local gridBottom = portrait and (L.card[2] - 4) or (gy2 - 3)
    -- (4 to the right: the scroll bar)
    L.grid = { x0, ty + 14, stripX1 - 4 - x0, gridBottom - ty - 14 }
    local T = S.TILE
    L.cols = max(2, floor((L.grid[3] + T.gap) / (T.w + T.gap) + 0.5))
    L.rows = max(1, floor((L.grid[4] + T.gap) / (T.h + T.gap)))
    L.tileW = (L.grid[3] - (L.cols - 1) * T.gap) / L.cols
    L.tileH = min(T.maxH, (L.grid[4] - (L.rows - 1) * T.gap) / L.rows)
    L.tray = { pw / 2 - 32, portrait and L.footY + 15 or L.footY + 4, 64, 22 }
    L.hints = portrait and { 10, L.footY + 3, pw - 20, 9 } or { 12, L.footY + 4, L.tray[1] - 18, 23 }
    L.coins = (not portrait) and { pw - 40, L.footY + 5, 28, 21 } or nil
    local aw = min(156, g[3] - 20)
    L.ask = { g[1] + (g[3] - aw) / 2, g[2] + (g[4] - 70) / 2, aw, 70 }
    return L
  end

  -- the frame being drawn, for the helpers below (set by S.draw)
  local G, ox, oy, sc, t
  local hit, hitPool, nHitRec = {}, {}, 0
  -- rectangles made while drawing, kept and handed out again each frame (R(x, y, w, h); valid
  -- until the next draw)
  local rects, nRect = {}, 0
  local function R(x, y, w, h)
    nRect = nRect + 1
    local q = rects[nRect]
    if not q then
      q = {}
      rects[nRect] = q
    end
    q[1], q[2], q[3], q[4] = x, y, w, h
    return q
  end
  -- a colour as LÖVE's 0..1 rgba, kept (the Pokédollar sign's)
  local rgbaOf = setmetatable({}, { __mode = "k" })
  local function rgba(c, a)
    local byA = rgbaOf[c]
    if not byA then
      byA = {}
      rgbaOf[c] = byA
    end
    local k = floor(a * 64 + 0.5)
    local v = byA[k]
    if not v then
      v = { c[1] / 255, c[2] / 255, c[3] / 255, k / 64 }
      byA[k] = v
    end
    return v
  end

  local function X(v) return ox + v * sc end
  local function Y(v) return oy + v * sc end
  local function col(c, a)
    c = c or WHITE
    G.setColor(c[1] / 255, c[2] / 255, c[3] / 255, (a or 1) * (c[4] or 1))
  end
  local function box(mode, b, rad)
    G.rectangle(mode, X(b[1]), Y(b[2]), b[3] * sc, b[4] * sc, (rad or 0) * sc, (rad or 0) * sc)
  end
  local function grad(b, rad, top, foot, alpha)
    gradient(G, X(b[1]), Y(b[2]), b[3] * sc, b[4] * sc, (rad or 0) * sc, top, foot, alpha)
  end
  -- a soft shadow under b, `lift` units down
  local function shadow(b, rad, lift, a)
    for i = 1, 3 do
      local s = i * 0.7
      col(BLACK, (a or 0.18) / 3)
      box("fill", R(b[1] - s * 0.6, b[2] - s * 0.4 + lift, b[3] + s * 1.2, b[4] + s * 1.2), (rad or 0) + s)
    end
  end
  local function ring(b, rad, c, a, w)
    col(c, a)
    G.setLineWidth(max(1, (w or 1) * sc))
    box("line", b, rad)
  end
  local function addHit(b, kind, arg, clip)
    local x, y, w, h = X(b[1]), Y(b[2]), b[3] * sc, b[4] * sc
    if clip then
      local cx, cy, cw, ch = X(clip[1]), Y(clip[2]), clip[3] * sc, clip[4] * sc
      local x2, y2 = min(x + w, cx + cw), min(y + h, cy + ch)
      x, y = max(x, cx), max(y, cy)
      w, h = x2 - x, y2 - y
      if w <= 0 or h <= 0 then return end
    end
    -- (the records are kept and filled again each frame)
    nHitRec = nHitRec + 1
    local rec = hitPool[nHitRec]
    if not rec then
      rec = {}
      hitPool[nHitRec] = rec
    end
    rec[1], rec[2], rec[3], rec[4], rec.kind, rec.arg = x, y, w, h, kind, arg
    hit[#hit + 1] = rec
  end
  local function width(s, size) return font(G, size * sc):getWidth(s) / sc end
  local function text(s, x, y, size, c, align, w, a)
    local f = font(G, size * sc)
    G.setFont(f)
    col(c, a)
    if align then
      G.printf(s, X(x), Y(y), w * sc, align)
    else
      G.print(s, X(x), Y(y))
    end
    return f
  end
  -- text that sits on colour: a faint shadow under it
  local function label(s, x, y, size, c, align, w, a)
    text(s, x, y + 0.5, size, BLACK, align, w, 0.22 * (a or 1))
    return text(s, x, y, size, c, align, w, a)
  end
  -- the game's Pokédollar sign at x, y (units) for a `size` font -> its width (units)
  local function sign(x, y, size, c, a, measure)
    local px = size * sc
    if deps.currency then
      local w
      if measure then
        local ok, got = pcall(deps.currencyWidth, px)
        w = ok and tonumber(got)
      else
        local ok, got = pcall(deps.currency, G, X(x), Y(y), px, rgba(c or WHITE, (a or 1) * ((c or WHITE)[4] or 1)))
        w = ok and tonumber(got)
      end
      if w then return w / sc end
    end
    if not measure then text("$", x, y, size, c, nil, nil, a) end
    return width("$", size)
  end
  -- a font size that fits s in w units (smaller only, never under 3.5)
  local function fit(s, size, w)
    local tw = width(s, size)
    if w and tw > w and tw > 0 then return max(3.5, size * w / tw * 0.97) end
    return size
  end
  -- an amount: `prefix`, the sign, the digits, as one line in w (aligned; smaller when it would
  -- run past it; shade: on colour)
  local function cash(prefix, n, x, y, size, c, align, w, a, shade)
    local digits = amountText(n)
    local preW, signW, total
    for pass = 1, 2 do
      preW = prefix ~= "" and width(prefix, size) or 0
      signW = sign(0, 0, size, c, a, true)
      total = preW + signW + width(digits, size)
      if pass == 2 or not (w and total > w) then break end
      local was = size
      size = max(3.5, size * w / total * 0.97)
      -- (kept on the line's middle)
      y = y + (was - size) * 0.5
    end
    local x0 = x
    if align == "center" then x0 = x + (w - total) / 2 elseif align == "right" then x0 = x + w - total end
    local put = shade and label or text
    if prefix ~= "" then put(prefix, x0, y, size, c, nil, nil, a) end
    if shade then sign(x0 + preW, y + 0.5, size, BLACK, 0.22 * (a or 1)) end
    sign(x0 + preW, y, size, c, a)
    put(digits, x0 + preW + signW, y, size, c, nil, nil, a)
  end
  local function scissor(b)
    if b then G.setScissor(X(b[1]), Y(b[2]), max(0, b[3] * sc), max(0, b[4] * sc)) else G.setScissor() end
  end
  local function pulse() return 0.7 + 0.3 * math.sin(t * 6) end

  -- the colours the screen draws in besides the machine's own
  local INK, SOFT = { 38, 40, 56 }, { 112, 116, 136 }
  local C = {
    body = { 150, 150, 170 }, accent = { 240, 160, 60 }, outline = { 82, 82, 106 }, screen = { 225, 235, 240 },
    plateTop = { 242, 244, 248 }, plateFoot = { 146, 152, 166 }, clear = { 255, 255, 255, 0 },
    shine = { 255, 255, 255, 0.4 }, screwTop = { 250, 250, 252 }, screwFoot = { 120, 124, 136 },
    coinTop = { 255, 222, 110 }, coinFoot = { 222, 160, 40 }, coinMark = { 120, 80, 10 },
    grey = { 168, 170, 182 }, bad = { 196, 56, 70 }, badDot = { 255, 210, 215 }, goodDot = { 120, 230, 160 },
    mouthTop = { 14, 14, 22 }, mouthFoot = { 44, 44, 58 }, lip = { 0, 0, 0, 0.55 }, none = { 0, 0, 0, 0 },
    slot = { 18, 18, 26 }, off = { 8, 8, 12 },
  }
  local OUTLINE_AT = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }
  local PAGER, STEPPER, ANSWERS = { "prevTab", "nextTab" }, { "minus", "plus" }, { "yes", "no" }
  local ANSWER_LABEL = { yes = "YES", no = "NO" }
  local tabX, tabW = {}, {}
  local layoutKey = {}
  local typeLabel = {}
  local bagText = textCache(function(n) return "IN BAG  " .. tostring(n) end)
  local qtyText = textCache(function(n) return "×" .. tostring(n) end)
  local titleChars = {}
  local function charsOf(title)
    local cs = titleChars[title]
    if not cs then
      cs = {}
      for ch in title:gmatch(".") do cs[#cs + 1] = ch end
      cs.split = #(title:match("^(%S+)") or title)
      titleChars[title] = cs
    end
    return cs
  end

  -- the plate's letters, slanted, one by one (a little apart): in one colour, or the first word's
  -- and the rest's (c2)
  local function plateLetters(chars, split, size, spacing, x, y, c, c2, alpha)
    G.push()
    G.translate(X(x), Y(y))
    G.shear(-0.2, 0)
    local cx = 0
    for i, ch in ipairs(chars) do
      col(c2 and i > split and c2 or c, alpha)
      G.print(ch, cx * sc, 0)
      cx = cx + width(ch, size) + spacing
    end
    G.pop()
  end

  -- the name on a metal plate: brushed silver, a bevel, a screw at each end; the letters
  -- italic and outlined, the first word in the accent, the rest in the body's colour, a gloss
  -- over their top half. x, y: its top left, maxW: the room it has (units)
  local function drawPlate(title, x, y, maxW, accent, body, outline)
    local chars = charsOf(title)
    local split = chars.split
    local SPACING, PAD, SCREW = 0.55, 8.5, 3.6
    local size = 7.5
    local tw
    for pass = 1, 2 do
      tw = -SPACING
      for _, ch in ipairs(chars) do tw = tw + width(ch, size) + SPACING end
      if pass == 2 or tw + PAD * 2 <= maxW then break end
      size = max(4, size * (maxW - PAD * 2) / tw)
    end
    local plate = R(x, y, min(maxW, tw + PAD * 2), 15)
    local px, py, pw2, ph2 = plate[1], plate[2], plate[3], plate[4]
    shadow(plate, 3.5, 0.9, 0.35)
    grad(plate, 3.5, C.plateTop, C.plateFoot)
    -- the reflection across its lower half, the brushing, the bevel
    grad(R(px + 2.5, py + ph2 * 0.52, pw2 - 5, ph2 * 0.4), 0, C.clear, C.shine)
    for i = 1, 4 do
      col(WHITE, 0.12)
      box("fill", R(px + 3, py + 2 + i * 2.4, pw2 - 6, 0.35))
    end
    col(WHITE, 0.85)
    box("fill", R(px + 2.5, py + 0.7, pw2 - 5, 0.6), 0.3)
    ring(R(px + 0.6, py + 0.6, pw2 - 1.2, ph2 - 1.2), 3, WHITE, 0.45, 0.6)
    ring(plate, 3.5, dark(outline, 0.3), 1, 0.8)
    -- the screws
    for k = 0, 1 do
      local sx, sy = px + SCREW + k * (pw2 - SCREW * 2), py + ph2 / 2
      gradient(G, X(sx - 1.5), Y(sy - 1.5), 3 * sc, 3 * sc, 1.5 * sc, C.screwTop, C.screwFoot)
      col(dark(outline, 0.2), 0.8)
      G.setLineWidth(max(1, 0.45 * sc))
      G.line(X(sx - 1), Y(sy + 0.7), X(sx + 1), Y(sy - 0.7))
    end
    -- the letters, slanted, one by one (a little apart)
    local f = font(G, size * sc)
    G.setFont(f)
    local lineH = f:getHeight() / sc
    local tx = px + (pw2 - tw) / 2 + 0.6
    local ty = py + (ph2 - lineH) / 2 - 0.2
    local firstColor = dark(accent, 0.12)
    local restColor = dark(body, 0.15)
    local edge = dark(outline, 0.45)
    -- the outline (all round), the fill (bolder: twice, a little apart), the gloss
    for _, d in ipairs(OUTLINE_AT) do
      plateLetters(chars, split, size, SPACING, tx + d[1] * 0.5, ty + d[2] * 0.5 + 0.2, edge, nil, 1)
    end
    plateLetters(chars, split, size, SPACING, tx, ty, firstColor, restColor, 1)
    plateLetters(chars, split, size, SPACING, tx + 0.3, ty, firstColor, restColor, 1)
    G.setScissor(X(px), Y(py), pw2 * sc, (ty - py + lineH * 0.48) * sc)
    plateLetters(chars, split, size, SPACING, tx + 0.15, ty, WHITE, nil, 0.3)
    G.setScissor()
    return plate
  end

  -- a tile's picture and its tag (a TM's number, or the price), `is` units square
  local function tileFace(b, e, tagColor, is)
    itemIcon(G, e, X(b[1] + (b[3] - is) / 2), Y(b[2] + 1.5), is * sc)
    if e.tm then
      local tag = entryText(e).tag
      text(tag, b[1], b[2] + b[4] - 7, fit(tag, 5, b[3] - 2), tagColor, "center", b[3])
    else
      cash("", e.price or 0, b[1] + 1, b[2] + b[4] - 7, 5, tagColor, "center", b[3] - 2)
    end
  end

  -- (the draw's constants and helpers, handed over in one: a function may only reach 60 outside it)
  local K = { INK = INK, SOFT = SOFT, C = C, OUTLINE_AT = OUTLINE_AT, PAGER = PAGER, STEPPER = STEPPER,
              ANSWERS = ANSWERS, ANSWER_LABEL = ANSWER_LABEL, tabX = tabX, tabW = tabW, layoutKey = layoutKey,
              typeLabel = typeLabel, bagText = bagText, qtyText = qtyText, charsOf = charsOf,
              pulse = pulse, fit = fit, cash = cash, sign = sign, label = label, scissor = scissor,
              drawPlate = drawPlate, tileFace = tileFace }

  function S.draw(g, vp)
    if not (r and g and vp) then return end
    G = g
    nRect, nHitRec = 0, 0
    local INK, SOFT, C, OUTLINE_AT, PAGER, STEPPER = K.INK, K.SOFT, K.C, K.OUTLINE_AT, K.PAGER, K.STEPPER
    local ANSWERS, ANSWER_LABEL, tabX, tabW, layoutKey = K.ANSWERS, K.ANSWER_LABEL, K.tabX, K.tabW, K.layoutKey
    local typeLabel, bagText, qtyText, charsOf = K.typeLabel, K.bagText, K.qtyText, K.charsOf
    local pulse, fit, cash, sign, label, scissor = K.pulse, K.fit, K.cash, K.sign, K.label, K.scissor
    local drawPlate, tileFace = K.drawPlate, K.tileFace
    local ww = tonumber(vp.width) or (tonumber(vp.gameX) or 0) * 2 + (tonumber(vp.gameWidth) or 240)
    local wh = tonumber(vp.height) or (tonumber(vp.gameY) or 0) * 2 + (tonumber(vp.gameHeight) or 160)
    local ax, ay, aw, ah = 0, 0, ww, wh
    if deps.safeArea then
      local ok, sx, sy, sw, sh = pcall(deps.safeArea)
      if ok and tonumber(sx) and tonumber(sy) and tonumber(sw) and tonumber(sh) then
        -- (inside the window the hud was handed)
        local x2, y2 = min(ww, sx + sw), min(wh, sy + sh)
        sx, sy = max(0, sx), max(0, sy)
        if x2 - sx > ww * 0.5 and y2 - sy > wh * 0.5 then ax, ay, aw, ah = sx, sy, x2 - sx, y2 - sy end
      end
    end
    local P = S.PAGE
    local portrait = aw / ah < P.PORTRAIT_ASPECT
    local pw, ph
    if portrait then
      sc = min(aw / P.PORTRAIT_WIDTH, ah / P.PORTRAIT_HEIGHT)
      pw, ph = aw / sc, ah / sc
    else
      sc = min(ah / P.HEIGHT, aw / P.MIN_WIDTH)
      pw, ph = min(P.MAX_WIDTH, aw / sc), ah / sc
    end
    ox, oy = ax + (aw - pw * sc) / 2, ay
    -- (the layout again only when the window changed)
    local L = layoutKey.L
    if not (L and layoutKey.pw == pw and layoutKey.ph == ph and layoutKey.portrait == portrait) then
      L = S.layout(pw, ph, portrait)
      layoutKey.L, layoutKey.pw, layoutKey.ph, layoutKey.portrait = L, pw, ph, portrait
    end
    r.sc, r.layout = sc, L
    reshape(L.cols, L.rows)
    for i = #hit, 1, -1 do hit[i] = nil end
    r.hit = hit
    local bz = r.machine.bezel or {}
    local clock = now()
    t = clock - r.t0
    local dt = max(0, min(0.1, clock - (r.lastDraw or clock)))
    r.lastDraw = clock
    -- the grid glides to its scroll
    local d = r.scroll - (r.shown or 0)
    r.shown = abs(d) < 0.01 and r.scroll or (r.shown + d * min(1, dt * 14))

    local body = bz.body or C.body
    local lower = bz.lower or dark(body, 0.2)
    local accent = bz.accent or C.accent
    local outline = bz.outline or C.outline
    local screenC = bz.screen or C.screen

    -- the room around the machine; the machine's front (the top body, the foot), its outline
    col(dark(outline, 0.55))
    G.rectangle("fill", 0, 0, ww, wh)
    local front = R(1.5, 1.5, pw - 3, ph - 3)
    shadow(front, 10, 1.5, 0.35)
    grad(front, 10, dark(lower, 0.05), dark(lower, 0.25))
    grad(R(front[1], front[2], front[3], L.footY - front[2]), 10, light(body, 0.18), body)
    grad(R(front[1], L.footY - 10, front[3], 10), 0, body, dark(body, 0.04))
    col(WHITE, 0.3)
    box("fill", R(12, 2.2, pw - 24, 1), 0.5)
    col(bz.trim or light(body, 0.2))
    box("fill", R(front[1], L.footY - 1.5, front[3], 1.5))
    col(BLACK, 0.18)
    box("fill", R(front[1], L.footY, front[3], 1.2))
    ring(front, 10, outline, 1, 1.5)

    -- the header: name, money, close (the name smaller if the money would cover it)
    local held = amountText(money())
    local mw = max(48, min(pw * 0.4, width(held, 6.5) + 20))
    local mb = R(L.close[1] - 4 - mw, 5.5, mw, 14)
    drawPlate(r.machine.title or "", 7, 4, mb[1] - 4 - 7, accent, body, outline)
    -- (not enough money: flashing red and shaking, S.MONEY_FLASH long)
    local flash = 0
    if r.moneyFlash then
      local age = clock - r.moneyFlash
      if age >= S.MONEY_FLASH then
        r.moneyFlash = nil
      else
        local k = age / S.MONEY_FLASH
        flash = abs(math.sin(k * math.pi * S.MONEY_FLASHES))
        mb[1] = mb[1] + math.sin(age * 55) * 1.2 * (1 - k)
      end
    end
    grad(mb, 7, fade(dark(outline, 0.35), 0.8), fade(dark(outline, 0.5), 0.8))
    if flash > 0 then
      col(C.bad, 0.9 * flash)
      box("fill", mb, 7)
    end
    ring(mb, 7, flash > 0 and C.badDot or WHITE, flash > 0 and (0.12 + 0.6 * flash) or 0.12, 0.6)
    gradient(G, X(mb[1] + 3), Y(mb[2] + 3), 8 * sc, 8 * sc, 4 * sc, C.coinTop, C.coinFoot)
    local sw = sign(0, 0, 4.6, nil, nil, true)
    sign(mb[1] + 7 - sw / 2, mb[2] + 4.1, 4.6, C.coinMark)
    local hs = fit(held, 6.5, mw - 17)
    text(held, mb[1] + 12, mb[2] + 3 + (6.5 - hs) * 0.5, hs, WHITE, "right", mw - 17)
    local cb = L.close
    shadow(cb, 7.5, 0.8, 0.2)
    grad(cb, 7.5, light(body, 0.35), dark(body, 0.1))
    ring(cb, 7.5, WHITE, 0.5, 0.8)
    col(WHITE)
    G.setLineWidth(max(1, 1.6 * sc))
    local ccx, ccy, k = cb[1] + cb[3] / 2, cb[2] + cb[4] / 2, 3
    G.line(X(ccx - k), Y(ccy - k), X(ccx + k), Y(ccy + k))
    G.line(X(ccx - k), Y(ccy + k), X(ccx + k), Y(ccy - k))
    addHit(cb, "close")

    -- the glass in its recess
    local gl = L.glass
    grad(R(gl[1] - 1.5, gl[2] - 1.5, gl[3] + 3, gl[4] + 3), 7, dark(body, 0.45), dark(body, 0.2))
    grad(gl, 6, light(screenC, 0.55), screenC)
    col(WHITE, 0.25)
    box("fill", R(gl[1] + 4, gl[2] + 1, gl[3] - 8, 1.2), 0.6)

    -- the tabs: a strip that scrolls to keep the open one in view
    local tabsB = L.tabs
    local xs, ws, total = tabX, tabW, 0
    for i, tab in ipairs(r.tabs) do
      ws[i] = width(tab.label, 5.5) + (tab.type and 15 or 9)
      xs[i] = total
      total = total + ws[i] + 2
    end
    if r.tabs[r.tab] then
      local a, b = xs[r.tab], xs[r.tab] + ws[r.tab]
      if a < r.tabScroll then r.tabScroll = a end
      if b > r.tabScroll + tabsB[3] then r.tabScroll = b - tabsB[3] end
      r.tabScroll = max(0, min(r.tabScroll, max(0, total - 2 - tabsB[3])))
    end
    col(dark(screenC, 0.5), 0.12)
    box("fill", R(tabsB[1] - 1, tabsB[2] - 1, tabsB[3] + 2, tabsB[4] + 2), 6.5)
    scissor(tabsB)
    for i, tab in ipairs(r.tabs) do
      local b = R(tabsB[1] + xs[i] - r.tabScroll, tabsB[2], ws[i], tabsB[4])
      local on = i == r.tab
      local tc = tab.type and S.TYPE_COLORS[tab.type]
      if on then
        local c = tc or body
        grad(b, 5.5, light(c, 0.2), dark(c, 0.08))
        if r.focus == "tabs" then ring(R(b[1] + 0.6, b[2] + 0.6, b[3] - 1.2, b[4] - 1.2), 5, accent, pulse(), 1.4) end
      end
      local lx = b[1]
      if tc then
        col(on and WHITE or tc)
        G.circle("fill", X(b[1] + 5.5), Y(b[2] + b[4] / 2), 2 * sc)
        lx = b[1] + 6
      end
      if on then
        label(tab.label, lx, b[2] + 2, 5.5, WHITE, "center", b[3] - (lx - b[1]))
      else
        text(tab.label, lx, b[2] + 2, 5.5, SOFT, "center", b[3] - (lx - b[1]))
      end
      addHit(b, "tab", i, tabsB)
    end
    scissor(nil)
    -- L / R at the strip's ends: the tab before / after (taps too)
    if #r.tabs > 1 then
      for _, which in ipairs(PAGER) do
        local b = L[which]
        shadow(b, 5.5, 0.5, 0.15)
        grad(b, 5.5, light(body, 0.25), dark(body, 0.05))
        col(WHITE)
        local acx, acy, ak = b[1] + b[3] / 2, b[2] + b[4] / 2, 2.2
        if which == "prevTab" then
          G.polygon("fill", X(acx - ak), Y(acy), X(acx + ak * 0.8), Y(acy - ak), X(acx + ak * 0.8), Y(acy + ak))
        else
          G.polygon("fill", X(acx + ak), Y(acy), X(acx - ak * 0.8), Y(acy - ak), X(acx - ak * 0.8), Y(acy + ak))
        end
        addHit(b, which)
      end
    end

    -- the grid
    local gridB = L.grid
    local gap, tw, th = S.TILE.gap, L.tileW, L.tileH
    local rowH = th + gap
    local gr = r.gridRect or {}
    gr[1], gr[2], gr[3], gr[4] = X(gridB[1]), Y(gridB[2]), gridB[3] * sc, gridB[4] * sc
    r.gridRect = gr
    r.rowPx = rowH * sc
    local entries = list()
    -- (a little room past the tiles for the chosen one's lift and ring)
    scissor(R(gridB[1] - 1.5, gridB[2] - 1.5, gridB[3] + 3, gridB[4] + 3))
    if #entries == 0 then
      text(S.TEXT.soldOut, gridB[1], gridB[2] + gridB[4] / 2 - 4, 6, SOFT, "center", gridB[3])
    end
    local is = min(20, th - 8)
    local chosenB, chosenE
    for i, e in ipairs(entries) do
      local row, c = floor((i - 1) / r.cols), (i - 1) % r.cols
      local ty = gridB[2] + (row - r.shown) * rowH
      if ty + th > gridB[2] - 2 and ty < gridB[2] + gridB[4] + 2 then
        local b = R(gridB[1] + c * (tw + gap), ty, tw, th)
        if i == r.cursor then
          chosenB, chosenE = b, e
        else
          shadow(b, 4, 0.6, 0.12)
          grad(b, 4, WHITE, light(screenC, 0.45))
          tileFace(b, e, SOFT, is)
        end
        addHit(b, "tile", i, gridB)
      end
    end
    -- the chosen tile, lifted over the rest
    if chosenB then
      local b0 = chosenB
      local lift = r.focus == "tabs" and 0.3 or 0.8
      local b = R(b0[1] - lift, b0[2] - lift * 1.5, b0[3] + lift * 2, b0[4] + lift * 2)
      shadow(b, 4.5, 1.4, 0.24)
      grad(b, 4.5, WHITE, light(accent, 0.82))
      tileFace(b, chosenE, dark(accent, 0.45), is)
      ring(R(b[1] + 0.5, b[2] + 0.5, b[3] - 1, b[4] - 1), 4, accent,
        r.focus == "grid" and pulse() or (r.focus == "tabs" and 0.35 or 0.75), 1.5)
    end
    scissor(nil)
    -- the scroll bar
    local rowsTotal = ceil(#entries / r.cols)
    if rowsTotal > r.rows then
      local trackH = gridB[4]
      local thumbH = max(10, trackH * r.rows / rowsTotal)
      local sy = gridB[2] + (trackH - thumbH) * (r.shown / max(1, rowsTotal - r.rows))
      col(dark(screenC, 0.4), 0.18)
      box("fill", R(gridB[1] + gridB[3] + 1.2, gridB[2], 2, trackH), 1)
      col(body)
      box("fill", R(gridB[1] + gridB[3] + 1.2, sy, 2, thumbH), 1)
    end

    -- the card
    local e = selected()
    local cardB = L.card
    shadow(cardB, 6, 1, 0.16)
    grad(cardB, 6, WHITE, light(screenC, 0.6))
    if e then
      local pad = 4
      local x, y, w = cardB[1] + pad, cardB[2] + pad, cardB[3] - pad * 2
      -- the foot first (the amount and BUY), from the card's bottom: one row on a wide card
      local buyB, stepB
      if cardB[3] >= 140 then
        local fy = cardB[2] + cardB[4] - pad - 14
        stepB = R(x, fy + 1, 64, 12)
        buyB = R(x + 68, fy, w - 68, 14)
      else
        buyB = R(x, cardB[2] + cardB[4] - pad - 14, w, 14)
        stepB = R(x, buyB[2] - 4 - 12, w, 12)
      end
      local footTop = min(stepB[2], buyB[2])
      -- the picture in a tinted badge; beside it the name (a TM's: its move, the TM's number by the
      -- price), the price and how many are in the Bag
      local badge = 22
      local tint = e.tm and S.TYPE_COLORS[e.tm.type] or accent
      gradient(G, X(x), Y(y), badge * sc, badge * sc, 6 * sc, light(tint, 0.8), light(tint, 0.6))
      itemIcon(G, e, X(x + 1), Y(y + 1), (badge - 2) * sc)
      local nx, nw = x + badge + 4, w - badge - 4
      local et = entryText(e)
      local title = e.tm and e.tm.move or e.name or ""
      -- (broken only between words: smaller when one word alone wouldn't fit; worked out again
      -- only when the card's width or the scale changes)
      if et.wrapW ~= nw or et.wrapSc ~= sc then
        local ts = 6.5
        for word in title:gmatch("%S+") do ts = min(ts, fit(word, 6.5, nw)) end
        local _, wrapped = font(G, ts * sc):getWrap(title, nw * sc)
        et.wrapW, et.wrapSc, et.titleSize, et.titleLines = nw, sc, ts, #wrapped
      end
      local ts = et.titleSize
      local nf = font(G, ts * sc)
      text(title, nx, y + 0.5, ts, INK, "left", nw)
      local ny = y + 1 + et.titleLines * nf:getHeight() / sc
      cash(et.pricePrefix or "", e.price or 0, nx, ny, 5.5, dark(accent, 0.35), "left", nw)
      local held, able = cardFacts(e)
      text(bagText(held), nx, ny + 7, 5, SOFT, "left", nw)
      y = max(y + badge, ny + 13) + 3
      if e.tm then
        -- the type and the numbers, as chips that flow onto a second row when narrow
        local tmType = e.tm.type
        local tName = typeLabel[tmType or -1]
        if not tName then
          tName = typeName(tmType)
          typeLabel[tmType or -1] = tName
        end
        local cx = x
        for k = 0, #et.stats do
          -- (0: the type, in its colour; then the numbers)
          local chipText = k == 0 and tName or et.stats[k]
          local chipColor = k == 0 and (S.TYPE_COLORS[tmType] or outline) or nil
          local cw = width(chipText, 4.6) + 6
          if cx > x and cx + cw > x + w then
            cx, y = x, y + 9
          end
          if y + 7.5 > footTop - 2 then break end
          local b = R(cx, y, cw, 7.5)
          if chipColor then
            grad(b, 3.75, light(chipColor, 0.15), dark(chipColor, 0.08))
            label(chipText, b[1], b[2] + 1.3, 4.6, WHITE, "center", b[3])
          else
            col(dark(screenC, 0.35), 0.16)
            box("fill", b, 3.75)
            text(chipText, b[1], b[2] + 1.3, 4.6, INK, "center", b[3])
          end
          cx = cx + cw + 2
        end
        y = y + 10
      end
      local df = font(G, 5 * sc)
      local lh = df:getHeight() / sc
      for _, line in ipairs(et.lines) do
        if y + lh > footTop - 2 then break end
        text(line, x, y, 5, SOFT, "left", w + 4)
        y = y + lh
      end
      -- the amount: - ×N + in a capsule
      local onCard = r.focus == "card" or r.focus == "confirm"
      col(dark(screenC, 0.35), 0.14)
      box("fill", stepB, stepB[4] / 2)
      if r.focus == "card" then ring(stepB, stepB[4] / 2, accent, pulse(), 1.3) end
      for _, which in ipairs(STEPPER) do
        local s = stepB[4] - 2
        local b = which == "minus" and R(stepB[1] + 1, stepB[2] + 1, s, s)
          or R(stepB[1] + stepB[3] - 1 - s, stepB[2] + 1, s, s)
        grad(b, s / 2, light(body, onCard and 0.25 or 0.5), onCard and body or light(body, 0.3))
        col(WHITE)
        G.setLineWidth(max(1, 1.3 * sc))
        local mx, my, mk = b[1] + s / 2, b[2] + s / 2, 2.2
        G.line(X(mx - mk), Y(my), X(mx + mk), Y(my))
        if which == "plus" then G.line(X(mx), Y(my - mk), X(mx), Y(my + mk)) end
        addHit(b, which)
      end
      text(qtyText(r.qty), stepB[1], stepB[2] + 2.2, 6.5, INK, "center", stepB[3])
      -- BUY and the total (grey while it can't be bought)
      local bc = able and accent or C.grey
      shadow(buyB, 7, 0.9, able and 0.22 or 0.1)
      grad(buyB, 7, light(bc, 0.22), dark(bc, 0.08))
      col(WHITE, 0.3)
      box("fill", R(buyB[1] + 5, buyB[2] + 1, buyB[3] - 10, 1), 0.5)
      cash("BUY  ", (e.price or 0) * r.qty, buyB[1] + 3, buyB[2] + 3, 6.5, WHITE, "center", buyB[3] - 6, nil, true)
      addHit(buyB, "buy")
    end

    -- the toast: a pill rising from the foot of the grid's side of the glass
    if r.toast then
      local age = clock - r.toast.t
      local a = age < 2.2 and min(1, age / 0.15 + 0.01) or max(0, 1 - (age - 2.2) / 0.4)
      if a <= 0 then
        r.toast = nil
      else
        local area = portrait and R(gl[1], gl[2], gl[3], cardB[2] - gl[2]) or R(gl[1], gl[2], cardB[1] - gl[1], gl[4])
        local tw2 = min(area[3] - 10, width(r.toast.text, 5.5) + 20)
        local tb = R(area[1] + (area[3] - tw2) / 2, area[2] + area[4] - 17 + (1 - min(1, age / 0.15)) * 4, tw2, 12)
        local tc = r.toast.bad and C.bad or dark(outline, 0.2)
        shadow(tb, 6, 1, 0.25 * a)
        col(tc, 0.94 * a)
        box("fill", tb, 6)
        col(r.toast.bad and C.badDot or C.goodDot, a)
        G.circle("fill", X(tb[1] + 6.5), Y(tb[2] + 6), 1.8 * sc)
        local fs = fit(r.toast.text, 5.5, tb[3] - 14)
        text(r.toast.text, tb[1] + 6, tb[2] + 2.6 + (5.5 - fs) * 0.5, fs, WHITE, "center", tb[3] - 8, a)
      end
    end

    -- the foot: the hints, the tray, the coin slots
    local hb = L.hints
    local hx, hy = hb[1], hb[2]
    local hints = (booting() and S.TEXT.hints.boot) or S.TEXT.hints[r.focus] or {}
    local hintW = 0
    for _, h in ipairs(hints) do hintW = hintW + max(8, width(h[1], 4.5) + 4) + 2 + width(h[2], 5) + 6 end
    if portrait then hx = hb[1] + max(0, (hb[3] - hintW + 6) / 2) end
    for _, h in ipairs(hints) do
      local kw = max(8, width(h[1], 4.5) + 4)
      local lw = width(h[2], 5)
      if hx > hb[1] and hx + kw + 2 + lw > hb[1] + hb[3] then hx, hy = hb[1], hy + 10 end
      if hy + 8 <= hb[2] + hb[4] + 0.5 then
        col(WHITE, 0.9)
        box("fill", R(hx, hy, kw, 8), 4)
        text(h[1], hx, hy + 1.4, 4.5, dark(lower, 0.5), "center", kw)
        label(h[2], hx + kw + 2, hy + 1.2, 5, WHITE)
      end
      hx = hx + kw + 2 + lw + 6
    end
    local tray = L.tray
    grad(tray, 5, dark(lower, 0.45), dark(lower, 0.3))
    ring(tray, 5, WHITE, 0.12, 0.6)
    local mouth = R(tray[1] + 3, tray[2] + 3, tray[3] - 6, tray[4] - 6)
    grad(mouth, 3, C.mouthTop, C.mouthFoot)
    if r.vend then
      local age = clock - r.vend.t
      if age > 3 then
        r.vend = nil
      else
        -- slides down from under the tray's lip, lands on its floor, bounces once
        local vs = 15
        local rest = mouth[2] + mouth[4] - vs - 0.5
        local fall = min(1, age / 0.3)
        local dy = (1 - fall * fall) * -(vs + 3)
        if age > 0.3 and age < 0.45 then dy = -1.8 * math.sin((age - 0.3) / 0.15 * math.pi) end
        scissor(mouth)
        itemIcon(G, r.vend.entry, X(mouth[1] + (mouth[3] - vs) / 2), Y(rest + dy), vs * sc)
        scissor(nil)
      end
    end
    -- the lip's shadow over the mouth, and its clear flap
    grad(R(mouth[1], mouth[2], mouth[3], 5), 0, C.lip, C.none)
    col(WHITE, 0.07)
    box("fill", mouth, 3)
    col(WHITE, 0.22)
    box("fill", R(mouth[1] + 2, mouth[2] + 0.6, mouth[3] - 4, 0.7))
    if L.coins then
      local cs = L.coins
      grad(cs, 4, dark(lower, 0.2), dark(lower, 0.32))
      ring(cs, 4, WHITE, 0.1, 0.6)
      -- the coin slot in its plate, the coin return button, the ready light
      grad(R(cs[1] + 4, cs[2] + 3.5, 8, 14), 2.5, light(lower, 0.25), lower)
      col(C.slot)
      box("fill", R(cs[1] + 7.2, cs[2] + 6, 1.6, 9), 0.8)
      gradient(G, X(cs[1] + 15), Y(cs[2] + 5), 9 * sc, 9 * sc, 4.5 * sc, light(lower, 0.35), dark(lower, 0.1))
      ring(R(cs[1] + 15, cs[2] + 5, 9, 9), 4.5, dark(lower, 0.5), 0.6, 0.6)
      col(C.goodDot, 0.6 + 0.4 * math.sin(t * 2.5))
      G.circle("fill", X(cs[1] + 19.5), Y(cs[2] + 17), 1.1 * sc)
    end

    -- YES / NO over everything
    if r.focus == "confirm" and e then
      for i = #hit, 1, -1 do
        if hit[i].kind ~= "close" then table.remove(hit, i) end
      end
      col(BLACK, 0.4)
      G.rectangle("fill", 0, 0, ww, wh)
      addHit(gl, "dim")
      local ab = L.ask
      shadow(ab, 8, 2, 0.35)
      grad(ab, 8, WHITE, light(screenC, 0.5))
      local qs = 18
      local tint = e.tm and S.TYPE_COLORS[e.tm.type] or accent
      gradient(G, X(ab[1] + (ab[3] - qs - 4) / 2), Y(ab[2] + 5), (qs + 4) * sc, (qs + 4) * sc, 6 * sc,
        light(tint, 0.8), light(tint, 0.6))
      itemIcon(G, e, X(ab[1] + (ab[3] - qs) / 2), Y(ab[2] + 7), qs * sc)
      if r.askFor ~= e or r.askQty ~= r.qty then
        r.askFor, r.askQty = e, r.qty
        r.askText = "Buy " .. (r.qty > 1 and (e.name .. " ×" .. r.qty) or e.name) .. "?"
      end
      local q = r.askText
      local qf = fit(q, 6.5, ab[3] - 10)
      text(q, ab[1] + 4, ab[2] + 30 + (6.5 - qf) * 0.5, qf, INK, "center", ab[3] - 8)
      cash("", (e.price or 0) * r.qty, ab[1] + 4, ab[2] + 39, 6, dark(accent, 0.35), "center", ab[3] - 8)
      local bw = (ab[3] - 20) / 2
      for i, which in ipairs(ANSWERS) do
        local b = R(ab[1] + 8 + (i - 1) * (bw + 4), ab[2] + ab[4] - 20, bw, 14)
        local on = (which == "yes") == r.yes
        if on then
          shadow(b, 7, 0.9, 0.22)
          grad(b, 7, light(accent, 0.22), dark(accent, 0.08))
          label(ANSWER_LABEL[which], b[1], b[2] + 3, 6.5, WHITE, "center", b[3])
          ring(R(b[1] - 1.2, b[2] - 1.2, b[3] + 2.4, b[4] + 2.4), 8, accent, pulse(), 1)
        else
          col(dark(screenC, 0.35), 0.16)
          box("fill", b, 7)
          text(ANSWER_LABEL[which], b[1], b[2] + 3, 6.5, SOFT, "center", b[3])
        end
        addHit(b, which)
      end
    end

    -- the boot over the glass
    local bt = bootAge()
    if bt then
      local B = S.BOOT
      local backdrop, backdropFoot = dark(body, 0.62), dark(body, 0.8)
      local logoAt = B.BLACK + B.LINE
      local revealAt = logoAt + B.LOGO
      if bt < revealAt then
        -- nothing to tap behind it but the close button; a tap anywhere else skips (the skip
        -- first in the list: taps try the last first)
        local n = 0
        for i = 1, #hit do
          if hit[i].kind == "close" then
            n = n + 1
            hit[n] = hit[i]
          end
        end
        for i = #hit, n + 1, -1 do hit[i] = nil end
        addHit(R(0, 0, pw, ph), "skip")
        table.insert(hit, 1, table.remove(hit))
      end
      if bt < B.BLACK then
        col(C.off)
        box("fill", gl, 6)
      elseif bt < logoAt then
        -- the tube opening: a bright line that grows to the glass's height
        local k = (bt - B.BLACK) / B.LINE
        col(C.off)
        box("fill", gl, 6)
        local h = max(0.8, gl[4] * k * k)
        local band = R(gl[1], gl[2] + (gl[4] - h) / 2, gl[3], h)
        -- (flat: it changes size every frame, which a gradient mesh would have to follow)
        col(backdrop)
        box("fill", band, min(6, h / 2))
        col(WHITE, 1 - k)
        box("fill", band, min(6, h / 2))
      else
        -- the logo, then (the reveal) the logo zooming away as the backdrop fades
        local into = bt - logoAt
        local out = max(0, bt - revealAt) / B.REVEAL
        local fadeA = 1 - out * out
        grad(gl, 6, backdrop, backdropFoot, fadeA)
        if not r.chimed then
          r.chimed = true
          se("SE_PC_LOGIN")
        end
        -- (pops in a little past full size and settles)
        local p = min(1, into / 0.4)
        local pop = 1 + 0.24 * math.sin(p * math.pi) * (1 - p)
        local size = min(gl[4] * 0.42, gl[3] * 0.3) * (0.82 + 0.18 * p) * pop * (1 + out * 0.5)
        local la = min(1, into / 0.25) * (1 - out)
        local cx, cy = gl[1] + gl[3] / 2, gl[2] + gl[4] / 2 - 5
        S.drawLogo(G, X(cx), Y(cy), size * sc, accent, la)
        -- the loading bar, filling over the logo's time
        if out == 0 then
          local fill = min(1, max(0, (into - 0.15) / (B.LOGO - 0.3)))
          local bw = min(60, gl[3] * 0.4)
          local bar = R(cx - bw / 2, cy + size * 0.31 + 9, bw, 2.5)
          col(WHITE, 0.15 * la)
          box("fill", bar, 1.25)
          if fill > 0 then
            -- (flat: it grows every frame)
            col(accent, la)
            box("fill", R(bar[1], bar[2], max(bar[4], bar[3] * fill), bar[4]), 1.25)
          end
        end
        -- a shine sweeping across the glass once
        local sweep = (into - 0.55) / 0.45
        if sweep > 0 and sweep < 1 and out == 0 then
          local sx = gl[1] - 30 + (gl[3] + 60) * sweep
          scissor(gl)
          col(WHITE, 0.12)
          G.polygon("fill", X(sx), Y(gl[2]), X(sx + 14), Y(gl[2]), X(sx - 6), Y(gl[2] + gl[4]),
            X(sx - 20), Y(gl[2] + gl[4]))
          scissor(nil)
        end
      end
    end
    G.setColor(1, 1, 1, 1)
  end

  -- the W: four slanted strokes folded like a ribbon (the outer two in the machine's accent, the
  -- inner two lighter, under them), over a soft glow; centred on cx, cy (window pixels), `size` wide
  local STROKES = { { 0, 0.25, 0, 1 }, { 0.25, 0.5, 1, 0.3 }, { 0.5, 0.75, 0.3, 1 }, { 0.75, 1, 1, 0 } }
  local STROKE_ORDER, OUTER = { 2, 3, 1, 4 }, { 1, 4 }
  local logoQuad = { 0, 0, 0, 0, 0, 0, 0, 0 }
  function S.drawLogo(G, cx, cy, size, accent, a)
    if a <= 0 then return end
    local w, h = size, size * 0.62
    local x0, y0 = cx - w / 2, cy - h / 2
    local th = w * 0.17      -- a stroke's width, across
    local slant = w * 0.07   -- (leaning forward)
    -- each stroke: its top and bottom x (0..1 of the width less a stroke), its ends' heights (0..1)
    local strokes = STROKES
    -- (one polygon buffer, filled again for each stroke)
    local q = logoQuad
    local function quad(sx)
      local span = w - th - slant
      local ax, ay = x0 + sx[1] * span + (1 - sx[3]) * slant, y0 + sx[3] * h
      local bx, by = x0 + sx[2] * span + (1 - sx[4]) * slant, y0 + sx[4] * h
      q[1], q[2], q[3], q[4], q[5], q[6], q[7], q[8] = ax, ay, ax + th, ay, bx + th, by, bx, by
      return q
    end
    local soft = light(accent, 0.45)
    -- the glow
    for i = 3, 1, -1 do
      G.setColor(accent[1] / 255, accent[2] / 255, accent[3] / 255, 0.07 * a)
      G.push()
      G.translate(cx, cy)
      G.scale(1 + i * 0.07, 1 + i * 0.1)
      G.translate(-cx, -cy)
      for _, sx in ipairs(strokes) do G.polygon("fill", quad(sx)) end
      G.pop()
    end
    -- the shadow, then the strokes
    G.setColor(0, 0, 0, 0.3 * a)
    G.push()
    G.translate(size * 0.02, size * 0.03)
    for _, sx in ipairs(strokes) do G.polygon("fill", quad(sx)) end
    G.pop()
    for _, i in ipairs(STROKE_ORDER) do
      local c = (i == 1 or i == 4) and accent or soft
      G.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a)
      G.polygon("fill", quad(strokes[i]))
    end
    -- a highlight along the outer strokes' leading edges
    G.setColor(1, 1, 1, 0.35 * a)
    G.setLineWidth(math.max(1, size * 0.012))
    for _, i in ipairs(OUTER) do
      local q = quad(strokes[i])
      G.line(q[1], q[2], q[7], q[8])
    end
  end

  return S
end
