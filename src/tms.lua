-- New TMs for the newer moves (data/tms.lua, tools/build_tms.py): TM51 on, items at index 1100+
-- in the TM Case, sold where each game sells TMs (data/shops.lua).
--
-- Gen 3 has no registry field that ties an item to a move, and the engine knows a TM by its
-- item number (289-346) and machine index (0-57). Every check is a module function, so:
--   Pokemon.moveFromTmItem   the move an item teaches (TM Case, Bag, shops, the teach flow)
--   Pokemon.canLearnTmItem   who can learn it (from data/tms.lua: National numbers and forms;
--                            the species' 64-bit TM row has no room for more machines)
--   ItemsData.isTm           the party menu's TM teach flow and its ABLE / NOT ABLE labels
--   ItemsData.tmNumber       the number shown in the TM Case and the Bag
-- The TM Case grows by the number of new TMs (the game profile's bag.capacity, which
-- ItemsData.CAPACITY is refilled from), and a new TM's Bag icon is the cart's own TM icon for a
-- move of the same type. A new TM is used up when taught, like the cart's TMs.
-- What only counts the cart's 58 machines (a father's TM moves in breeding, link checks, the
-- Battle Frontier Apprentice) does not see these.
local Tms = {}

local INDEX_CAP = 2047
local GAMES = { "firered", "leafgreen", "ruby", "sapphire", "emerald" }

-- At load: the Gen 3 item registry caps `index` at 1023 (a schema constant, no mod API: the
-- same engine_internals reach as the species slot cap), then one item per TM.
-- list: data/tms.lua; moveRows: data/moves.lua rows by id (a fallback description).
function Tms.register(mod, list, moveRows, require)
  local okS, Schemas = pcall(require, "src.mods.Schemas")
  local fields = okS and type(Schemas) == "table" and Schemas.REGISTRIES and Schemas.REGISTRIES.items
    and Schemas.REGISTRIES.items.gen3Fields
  if not (fields and Schemas.f and Schemas.f.opt and Schemas.f.int) then
    mod.log:warn("new TMs are off: could not raise the item index cap")
    return {}
  end
  fields.index = Schemas.f.opt(Schemas.f.int(1, INDEX_CAP))
  local okV, GV = pcall(require, "src.core.GameVersion")
  local game = okV and GV and tostring(GV.current) or ""
  local frlg = game:find("firered", 1, true) or game:find("leafgreen", 1, true)
  local registered, failed, firstError = {}, 0, nil
  for _, t in ipairs(list or {}) do
    -- the item text, wrapped for this game's Bag / TM Case box (tools/build_tms.py); the
    -- move's own summary text if the data has none
    local row = moveRows[t.move] or {}
    local text = (frlg and t.frlg or t.rse) or (frlg and row.frlg or row.rse) or ""
    local ok, err = pcall(function()
      mod.content.items:register(t.id, {
        id = t.id, name = t.id, index = t.index, price = t.price, pocket = "TM_CASE",
        description = text,
      })
    end)
    if ok then registered[#registered + 1] = t
    else failed = failed + 1; firstError = firstError or tostring(err) end
  end
  mod.log:info("registered %d new TM(s)", #registered)
  if failed > 0 then mod.log:warn("%d TM(s) failed to register; first: %s", failed, firstError) end
  return registered
end

-- opts: { list (registered TMs), moves ({ id -> move number }), formSlots ({ form id -> slot }),
--         require, log }
function Tms.install(opts)
  local require, log = opts.require, opts.log
  local okP, P = pcall(require, "src.core.game3.pokemon")
  local okI, ItemsData = pcall(require, "src.core.game3.items_data")
  if not (okP and okI and type(P.moveFromTmItem) == "function" and type(ItemsData.isTm) == "function") then
    if log then log:warn("new TMs are off: the engine's TM functions were not found") end
    return false
  end

  -- item number / id -> { number, move, can = { [slot] = true } }
  local byIndex, byKey = {}, {}
  for _, t in ipairs(opts.list or {}) do
    local move = opts.moves[t.move]
    if move then
      local can = {}
      for _, dex in ipairs(t.dex or {}) do
        local slot = P.speciesFromNational and P.speciesFromNational(dex)
        if slot then can[slot] = true end
      end
      for _, fid in ipairs(t.forms or {}) do
        local slot = opts.formSlots and opts.formSlots[fid]
        if slot then can[slot] = true end
      end
      local e = { number = t.number, move = move, can = can, index = t.index }
      byIndex[t.index], byKey[t.id] = e, e
    end
  end
  Tms._byIndex = byIndex
  local function ours(id)
    local n = tonumber(id)
    if n then return byIndex[n] end
    if type(id) == "string" then return byKey[id] or byKey[id:upper()] end
    return nil
  end

  if not P.__nationalDexTms then
    P.__nationalDexTms = true
    local moveFrom, canLearn = P.moveFromTmItem, P.canLearnTmItem
    P.moveFromTmItem = function(itemId, ...)
      local t = ours(itemId)
      if t then return t.move end
      return moveFrom(itemId, ...)
    end
    P.canLearnTmItem = function(species, itemId, ...)
      local t = ours(itemId)
      if t then return t.can[tonumber(species) or -1] == true end
      return canLearn(species, itemId, ...)
    end
  end
  if not ItemsData.__nationalDexTms then
    ItemsData.__nationalDexTms = true
    local isTm, tmNumber = ItemsData.isTm, ItemsData.tmNumber
    ItemsData.isTm = function(id, ...)
      if ours(id) then return true end
      return isTm(id, ...)
    end
    if type(tmNumber) == "function" then
      ItemsData.tmNumber = function(id, ...)
        local t = ours(id)
        if t then return t.number end
        return tmNumber(id, ...)
      end
    end
  end

  -- a bigger TM Case: every game's profile, so the size holds whenever the bag model is
  -- refilled; then the live table for the game that is running
  local n = 0
  for _ in pairs(byIndex) do n = n + 1 end
  local okPr, Profile = pcall(require, "src.core.game3.profile")
  if okPr and Profile.of then
    for _, game in ipairs(GAMES) do
      local okR, row = pcall(Profile.of, game)
      local bag = okR and type(row) == "table" and row.bag
      if type(bag) == "table" and type(bag.capacity) == "table" and bag.capacity.TM_CASE then
        bag.__nationalDexTmCase = bag.__nationalDexTmCase or bag.capacity.TM_CASE
        bag.capacity.TM_CASE = bag.__nationalDexTmCase + n
      end
    end
    local okA, active = pcall(Profile.active)
    local bag = okA and type(active) == "table" and active.bag
    if type(bag) == "table" and bag.capacity and type(ItemsData.CAPACITY) == "table" then
      ItemsData.CAPACITY.TM_CASE = bag.capacity.TM_CASE
    end
  end

  -- the Bag icon: the cart's TM icon for a move of the same type (Normal's for a type the cart
  -- has no TM of, e.g. Fairy)
  local iconOf = {}
  local function cartTmFor(move)
    local row = P.battleMove and P.battleMove(move)
    local want = tonumber(row and row.type)
    local first
    for id = tonumber(ItemsData.FIRST_TM) or 289, tonumber(ItemsData.LAST_TM) or 338 do
      local m = P._tmhm and P._tmhm.machines and P._tmhm.machines[id - (tonumber(ItemsData.FIRST_TM) or 289)]
      local r = m and P.battleMove and P.battleMove(m)
      local ty = tonumber(r and r.type)
      if ty == want then return id end
      if ty == 0 and not first then first = id end
    end
    return first or tonumber(ItemsData.FIRST_TM) or 289
  end
  local function iconFor(id)
    local t = ours(id)
    if not t then return nil end
    if iconOf[t.index] == nil then
      local ok, cart = pcall(cartTmFor, t.move)
      iconOf[t.index] = ok and cart or false
    end
    return iconOf[t.index] or nil
  end
  for _, name in ipairs({ "src.ui.game3.bag_chrome", "src.ui.game3.rse.bag_chrome" }) do
    local okC, Chrome = pcall(require, name)
    if okC and type(Chrome) == "table" and type(Chrome.drawItemIcon) == "function" and not Chrome.__nationalDexTms then
      Chrome.__nationalDexTms = true
      local draw = Chrome.drawItemIcon
      Chrome.drawItemIcon = function(id, ...)
        local cart = iconFor(id)
        if cart then return draw(cart, ...) end
        return draw(id, ...)
      end
    end
  end

  -- FireRed / LeafGreen's TM Case: the disc slides along the rack by TM number (pokefirered
  -- SetDiscSpritePosition, over 58 machines), so a new TM's would slide off the case: it sits
  -- where the last cart TM's does. A Fairy move has no disc of its own: Normal's, tinted pink.
  local okD, Disc = pcall(require, "src.ui.game3.tm_case_chrome")
  if okD and type(Disc) == "table" and type(Disc.drawDisc) == "function" and not Disc.__nationalDexTms then
    Disc.__nationalDexTms = true
    local drawDisc = Disc.drawDisc
    local LAST_X, LAST_Y = 41 - math.floor(14 * 57 / 58) - 16, 46 + math.floor(8 * 57 / 58) - 16
    Disc.drawDisc = function(typeIdx, x, y, isHm, ...)
      if not isHm and tonumber(x) and tonumber(y) then
        x, y = math.max(x, LAST_X), math.min(y, LAST_Y)
      end
      if tonumber(typeIdx) == 18 and type(Disc.loadDisc) == "function" then
        local img = Disc.loadDisc(0, isHm)
        if img and love and love.graphics then
          love.graphics.setColor(1, 0.62, 0.82, 1)
          love.graphics.draw(img, x, y)
          love.graphics.setColor(1, 1, 1, 1)
          return true
        end
      end
      return drawDisc(typeIdx, x, y, isHm, ...)
    end
  end

  if log then log:info("new TMs: %d (TM Case holds %s)", n, tostring(ItemsData.CAPACITY and ItemsData.CAPACITY.TM_CASE)) end
  return true
end

return Tms
