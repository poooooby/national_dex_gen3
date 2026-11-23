-- OmniUI (1Jamie's omni_ui, optional): its overlay hides the battle's own HP boxes and redraws the
-- Summary, so the type badges, the Stat Hints and the Dynamax marks (which draw beside the game's own
-- boxes and on its own Summary) would not show. Through OmniUI's public API instead:
--   registerBattlerBadge: on each of OmniUI's battler cards, the battler's types as coloured pills
--     and its stat changes as chips ("ATK 2x"), in OmniUI's own badge style: a row under a foe's
--     card, above yours (OmniUI's deck is under it), wrapping at the card's width.
--   registerSummaryTab: a DYNAMAX tab (Dynamax Level, G-Max Factor and its G-Max Move).
-- Nothing changes without OmniUI, or with its overlay off (it draws no cards then, and the game's own
-- boxes carry the badges as always). Gen 3 only: the renders check the running generation.
--
-- OmniUI loads after this mod (priority 100), so this is installed on game.ready, and its registries
-- outlive a game switch: one badge per OmniUI (Healthbox.__ndxOmni, keyed by its register function),
-- whose render asks the hub, so a later install's options and modules are the ones used.
local Omni = {}

Omni.TAB_ID = "woobledex_dynamax"

-- type id (src/core/game3/battle/types.lua; FAIRY 18) -> the pill's label
Omni.TYPE_NAMES = {
  [0] = "NORMAL", [1] = "FIGHTING", [2] = "FLYING", [3] = "POISON", [4] = "GROUND", [5] = "ROCK",
  [6] = "BUG", [7] = "GHOST", [8] = "STEEL", [9] = "???", [10] = "FIRE", [11] = "WATER", [12] = "GRASS",
  [13] = "ELECTRIC", [14] = "PSYCHIC", [15] = "ICE", [16] = "DRAGON", [17] = "DARK", [18] = "FAIRY",
}

-- a pill's and a chip's size in OmniUI's units (window px), and the gaps
Omni.H, Omni.GAP, Omni.PAD, Omni.MARGIN = 16, 4, 6, 4

-- OmniUI's battler card sizes (renderers/BattleRenderer.lua draw): width from the view, height by side
function Omni.cardSize(side, vw, ultraCompact)
  local w = math.min(260, math.max(160, math.floor(vw * 0.44)))
  if side == "enemy" then return w, ultraCompact and 52 or 62 end
  return w, ultraCompact and 64 or 76
end

-- rows of items (each { w }) from (x, y): rightward, wrapping at `limit` wide; up = the rows go upward
-- from y (the first row nearest the card). place(i, x, y) for each; nothing is made.
function Omni.flow(items, n, x, y, limit, up, place)
  local H, G = Omni.H, Omni.GAP
  local cx, row = x, 0
  for i = 1, n do
    local w = items[i].w
    if cx > x and cx + w > x + limit then cx, row = x, row + 1 end
    local ry = up and (y - H - row * (H + G)) or (y + row * (H + G))
    place(i, cx, ry)
    cx = cx + w + G
  end
end

local function hex(h)
  return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, 1 }
end

-- opts: { require, log, colors = TypeBadges.COLORS, chips = StatHints module, dynamax = Dx (optional) }
-- api: OmniUI's exports (mod.find("omni_ui").exports). True when something was registered.
function Omni.install(api, opts)
  if type(api) ~= "table" or type(api.registerBattlerBadge) ~= "function" then return false end
  local require = opts.require
  local okH, Healthbox = pcall(require, "src.core.game3.battle.healthbox")
  if not (okH and type(Healthbox) == "table") then return false end
  local hub = Healthbox.__ndxOmni
  if not hub then
    hub = { registered = setmetatable({}, { __mode = "k" }) }
    Healthbox.__ndxOmni = hub
  end

  local Layout = api.Layout
  local SH = opts.chips
  local okGV, GV = pcall(require, "src.core.GameVersion")
  local function gen3()
    if not (okGV and GV and GV.generation) then return true end
    local ok, g = pcall(GV.generation)
    return not ok or g == 3
  end
  local okB, Battle = pcall(require, "src.core.game3.battle")
  if not (okB and type(Battle) == "table") then Battle = nil end
  local okT, Types = pcall(require, "src.core.game3.battle.types")
  if not okT then Types = nil end

  -- the pills' colours (fill, rim), made once
  local fills, rims = {}, {}
  for id, h in pairs(opts.colors or {}) do
    local c = hex(h)
    fills[id] = c
    rims[id] = { c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 1 }
  end
  local WHITE = { 1, 1, 1, 1 }

  -- widths by text, measured once in OmniUI's "tiny" font
  local widths = {}
  local function width(text)
    local w = widths[text]
    if not w then
      local ok, tw = pcall(Layout.textWidth, text, "tiny")
      w = (ok and tonumber(tw) or #text * 7) + 2 * Omni.PAD
      widths[text] = w
    end
    return w
  end

  local function typeId(v)
    if type(v) == "number" then return v end
    if type(v) == "string" and Types and Types.ID then return Types.ID[v:upper()] end
    return nil
  end

  -- the live battler behind one of OmniUI's cards: its adapter fills a foe's card from st.enemy and
  -- the second foe's from battlers[3]; yours from st.player
  local function matches(b, slot)
    local mon = type(b) == "table" and (b.mon or b.pokemon)
    return type(mon) == "table" and mon.species == slot.species and (mon.level or 1) == (slot.level or 1)
  end
  local function battlerFor(side, slot)
    if not Battle then return nil end
    local st = Battle.getState and Battle.getState() or rawget(Battle, "_st")
    if type(st) ~= "table" then return nil end
    local bs = rawget(st, "battlers")
    local a, b
    if side == "enemy" then
      a = st.enemy or (type(bs) == "table" and bs[1])
      b = type(bs) == "table" and bs[3] or nil
    else
      a = st.player or (type(bs) == "table" and bs[0])
      b = type(bs) == "table" and bs[2] or nil
    end
    if b and b ~= a and matches(b, slot) and not matches(a, slot) then return b end
    return a
  end

  local function stageOf(battler, k)
    local s = battler.stages
    return type(s) == "table" and s[k] or 0
  end

  -- this card's items (types, then chips), kept from frame to frame
  local items, chipList = {}, {}
  for i = 1, 12 do items[i] = { w = 0 } end
  local function collect(battler)
    local n = 0
    local badges = Healthbox.__ndxBadges
    local okOn, on = true, true
    if badges and badges.enabled then okOn, on = pcall(badges.enabled) end
    if not (okOn and on == false) then
      local t1, t2, t3 = typeId(battler.type1), typeId(battler.type2), typeId(battler.__ndxType3)
      if t2 == t1 then t2 = nil end
      if t3 == t1 or t3 == t2 then t3 = nil end
      if t1 == 9 and t2 then t1, t2 = t2, nil end
      if t2 == 9 then t2 = nil end
      if t3 == 9 then t3 = nil end
      for k = 1, 3 do
        local t = (k == 1 and t1) or (k == 2 and t2) or (k == 3 and t3) or nil
        local name = t and Omni.TYPE_NAMES[t]
        if name and n < #items then
          n = n + 1
          local it = items[n]
          it.kind, it.type, it.text, it.w = "type", t, name, width(name)
        end
      end
    end
    local hints = Healthbox.__ndxStatHints
    okOn, on = true, true
    if hints and hints.enabled then okOn, on = pcall(hints.enabled) end
    if SH and not (okOn and on == false) then
      local chips
      local hold = hints and hints.hold
      if hold and hints.playing and hints.playing() then
        chips = SH.chips(hold.read, battler, chipList)
      else
        if hold then hold.take(battler, stageOf, battler) end
        chips = SH.chips(stageOf, battler, chipList)
      end
      for i = 1, #chips do
        if n >= #items then break end
        n = n + 1
        local it = items[n]
        it.kind, it.text, it.up, it.w = "chip", chips[i].text, chips[i].up, width(chips[i].text)
      end
    end
    return n
  end

  local drawTheme
  local function place(i, x, y)
    local it = items[i]
    local C = drawTheme and (drawTheme.colors or drawTheme) or {}
    if it.kind == "type" then
      Layout.drawBadge(x, y, it.text, { font = "tiny", height = Omni.H, width = it.w,
        color = fills[it.type], textColor = WHITE, borderColor = rims[it.type] })
    else
      local ink = it.up and (C.hpGreen or { 0.3, 0.8, 0.4, 1 }) or (C.hpRed or { 0.9, 0.3, 0.3, 1 })
      Layout.drawBadge(x, y, it.text, { font = "tiny", height = Omni.H, width = it.w,
        color = C.surfaceHigh or C.surface, textColor = ink, borderColor = ink })
    end
  end

  -- OmniUI's badge render for one card (slot: OmniUI's battler info; x, y: the card's top left)
  hub.render = function(side, slot, x, y, theme)
    if not (gen3() and type(slot) == "table" and slot.active ~= false) then return end
    local battler = battlerFor(side, slot)
    if type(battler) ~= "table" then return end
    local n = collect(battler)
    if n == 0 then return end
    local vw, vh = 800, 600
    if love and love.graphics and love.graphics.getDimensions then vw, vh = love.graphics.getDimensions() end
    local ctx = Layout.getContext and Layout.getContext(vw, vh) or {}
    local cw, ch = Omni.cardSize(side, vw, ctx.isUltraCompact)
    drawTheme = theme
    if side == "enemy" then
      Omni.flow(items, n, x, y + ch + Omni.MARGIN, cw, false, place)
    else
      Omni.flow(items, n, x, y - Omni.MARGIN, cw, true, place)
    end
    drawTheme = nil
  end

  if not hub.registered[api.registerBattlerBadge] then
    hub.registered[api.registerBattlerBadge] = true
    api.registerBattlerBadge({ id = "woobledex_enemy", side = "enemy",
      render = function(slot, x, y, theme) local r = hub.render; if r then r("enemy", slot, x, y, theme) end end })
    api.registerBattlerBadge({ id = "woobledex_player", side = "player",
      render = function(slot, x, y, theme) local r = hub.render; if r then r("player", slot, x, y, theme) end end })
  end

  -- ------- the Summary's DYNAMAX tab
  local Dx = opts.dynamax
  -- "VINE_LASH" -> "G-Max Vine Lash", made once a move
  local gmaxNames = {}
  local function gmaxName(move)
    local s = gmaxNames[move]
    if not s then
      s = "G-Max " .. tostring(move):lower():gsub("_", " "):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end)
      gmaxNames[move] = s
    end
    return s
  end
  if Dx and type(api.registerSummaryTab) == "function" then
    hub.tab = function(game, mon, rx, ry, rw, rh, theme)
      local C = type(theme) == "table" and (theme.colors or theme) or {}
      local heading, dim = C.heading or WHITE, C.textDim or C.text or WHITE
      local x, y = rx + 24, ry + 18
      Layout.drawText("DYNAMAX", x, y, { font = "headline", color = heading, bold = true })
      y = y + 34
      local raw = type(mon) == "table" and (mon.raw or mon) or nil
      if not gen3() or type(raw) ~= "table" then
        Layout.drawText("Dynamax is part of FireRed to Emerald.", x, y, { font = "caption", color = dim })
        return
      end
      if not Dx.canDynamax(raw) then
        Layout.drawText("This Pokemon can't Dynamax.", x, y, { font = "body", color = dim })
        return
      end
      local level = Dx.level(raw)
      local max = (Dx.data and Dx.data.MAX_LEVEL) or 10
      Layout.drawText(("DYNAMAX LEVEL  %d / %d"):format(level, max), x, y, { font = "body", color = heading, bold = true })
      y = y + 24
      -- the gauge: one segment a level
      local segW = math.max(6, math.floor((math.min(rw - 48, 320) - (max - 1) * 3) / max))
      for i = 1, max do
        local on = i <= level
        local col = on and (C.hpRed or { 0.9, 0.3, 0.3, 1 }) or (C.surfaceHigh or C.surface or { 0.3, 0.3, 0.3, 1 })
        love.graphics.setColor(col[1], col[2], col[3], col[4] or 1)
        love.graphics.rectangle("fill", x + (i - 1) * (segW + 3), y, segW, 10, 2, 2)
      end
      y = y + 22
      local mult = ("%.2f"):format(Dx.hpMult(level)):gsub("0+$", ""):gsub("%.$", "")
      Layout.drawText("HP while Dynamaxed: x" .. mult, x, y, { font = "caption", color = dim })
      y = y + 30
      local move = Dx.gmaxMoveOf(raw)
      if not move then
        Layout.drawText("No Gigantamax form.", x, y, { font = "body", color = dim })
        return
      end
      local has = Dx.hasFactor(raw)
      Layout.drawText("G-MAX FACTOR", x, y, { font = "body", color = heading, bold = true })
      Layout.drawBadge(x + 140, y - 1, has and "YES" or "NO", { kind = has and "good" or "ghost", font = "tiny" })
      y = y + 26
      local name = gmaxName(move)
      Layout.drawText(has and ("Gigantamaxes, with " .. name .. ".") or ("Max Soup would let it use " .. name .. "."),
        x, y, { font = "caption", color = dim })
    end
    api.registerSummaryTab({ id = Omni.TAB_ID, label = "DYNAMAX",
      draw = function(...) local t = hub.tab; if t then return t(...) end end })
  end
  return true
end

-- Gen 1 / 2 (src/gen12/main.lua): the DYNAMAX tab off the Summary there (OmniUI's registry outlives a
-- game switch); the badges check the generation themselves
function Omni.uninstallTab(api)
  if type(api) == "table" and type(api.summaryTabs) == "table" then api.summaryTabs[Omni.TAB_ID] = nil end
end

return Omni
