-- New TMs on Gen 1 / Gen 2: the Gen 3 path's TM list (data/tms.lua, TM51 on) for the moves that
-- run on this game (a newer move registered here with an effect of the cart's own; on Red and
-- Gold the same 43). Each keeps its Gen 3 id and number, so TM74 is Zen Headbutt on every game.
--
-- Both games already teach any item that names its move, through their own Bag and party menu
-- (the "Booted up a TM!" prompt, ABLE / NOT ABLE, the forget-a-move prompt) and decide who can
-- learn it from the species' own `tmhm` list:
--   Red   the item's `machine` = { kind = "TM", move, number }
--   Gold  `teaches` = move, in the TM pocket; `tmNumber` only sorts the pocket, so ours are
--         50 + number / 1000 (after TM50, before HM01): Gold's .sav import / export maps TMs by
--         whole tmNumber 1-57, and TM57 must never stand in for HM07
-- so registering the items and adding the move to each compatible species' `tmhm` (cart species,
-- ours and forms, from data/tms.lua's National numbers and form ids) is all it takes.
--
-- Two process-wide wraps keep the rest of the game whole (each acts only on these item ids):
--   Red's .sav export (GenSave.crosswalks) would give a machine with no index the byte
--     200 + number, which wraps past 255 from TM55; ours are left out, as every mod item is
--   Gold's TM pocket holds the cart's 57 (Bag.capacity): it grows by the new TMs present
-- Sold at the game's TM counter (src/gen12/shops.lua): Red's Celadon Dept. Store 2F, Gold's
-- Goldenrod Dept. Store 5F.

local Tms = {}

Tms.GEN1_SHOP = { map = "CeladonMart2F", text = "TEXT_CELADONMART2F_CLERK2" }
-- Goldenrod Dept. Store 5F: four stocks (pokegold MartGoldenrod5F_*), all starting with these
Tms.GEN2_SHOP = { "TM_THUNDERPUNCH", "TM_FIRE_PUNCH", "TM_ICE_PUNCH" }
Tms.TM_POCKET = 57

-- The TMs whose move runs on this game: { t (data/tms.lua row), move (this game's id) }
function Tms.select(list, moveRows, generation, direct)
  local key = "gen" .. generation
  local byId = {}
  for _, m in ipairs(moveRows or {}) do byId[m.id] = m end
  local out = {}
  for _, t in ipairs(list or {}) do
    local row = byId[t.move]
    local move = row and row[key] and direct(row.n)
    if move then out[#out + 1] = { t = t, move = move } end
  end
  return out
end

-- opts: { mod, generation, list = Tms.select(...), species (src/gen12/species.lua state), log }
-- Returns { registered = { ids }, ids = { [id] = true }, compatible = species patched }
function Tms.register(opts)
  local mod, gen, log = opts.mod, opts.generation, opts.log
  local items, pokemon = mod.content.items, mod.content.pokemon
  local state = { registered = {}, ids = {}, compatible = 0, failed = 0 }
  local learns = {}        -- species id -> { moves }
  local function learn(id, move)
    if not id then return end
    local l = learns[id]
    if not l then l = {}; learns[id] = l end
    l[#l + 1] = move
  end
  local species = opts.species
  local maxDex = gen == 1 and 151 or 251
  local firstError
  for _, e in ipairs(opts.list) do
    local t = e.t
    local rec = { id = t.id, name = t.id, price = t.price }
    if gen == 1 then
      rec.machine = { kind = "TM", move = e.move, number = t.number }
    else
      rec.index, rec.pocket = t.index, "TM_HM"
      rec.teaches, rec.tmNumber, rec.tmLabel = e.move, 50 + t.number / 1000, t.id
      rec.fieldMenu, rec.battleMenu = "ITEMMENU_PARTY", "ITEMMENU_NOUSE"
      rec.canToss, rec.canSelect = true, false
      rec.heldEffect, rec.heldParameter = "HELD_NONE", 0
      rec.description = "?"
    end
    local ok, err = true, nil
    if items:get(t.id) == nil then ok, err = pcall(items.register, items, t.id, rec) end
    if ok then
      state.registered[#state.registered + 1] = t.id
      state.ids[t.id] = true
      for _, dex in ipairs(t.dex or {}) do
        if dex <= maxDex then learn(species.cartIdOf[dex], e.move)
        else learn(species.byDex[dex] and species.byDex[dex].id, e.move) end
      end
      for _, fid in ipairs(t.forms or {}) do
        learn(species.byId[fid] and species.byId[fid].id, e.move)
      end
    else
      state.failed = state.failed + 1
      firstError = firstError or (t.id .. ": " .. tostring(err))
    end
  end
  for id, moves in pairs(learns) do
    local ok, err = pcall(pokemon.patch, pokemon, id, { tmhm = { __append = moves } })
    if ok then state.compatible = state.compatible + 1
    else firstError = firstError or (id .. ": " .. tostring(err)) end
  end
  if firstError and log then log:warn("new TMs: %s", firstError) end
  return state
end

-- The two wraps, once per process; `ids` (this load's TM ids) joins the set they act on.
function Tms.install(require, ids)
  local okB, Bag = pcall(require, "src.inventory.Bag")
  if okB and type(Bag) == "table" and type(Bag.capacity) == "function" then
    local hub = Bag.__ndxGen12Tms
    if not hub then
      hub = { ids = {} }
      Bag.__ndxGen12Tms = hub
      local base = Bag.capacity
      Bag.capacity = function(data, pocket, ...)
        local n = base(data, pocket, ...)
        if pocket == "TM_HM" and type(n) == "number" then
          local items = (data or require("src.core.Data") or {}).items
          if type(items) == "table" then
            for id in pairs(hub.ids) do
              local def = items[id]
              if type(def) == "table" and def.pocket == "TM_HM" then n = n + 1 end
            end
          end
        end
        return n
      end
    end
    for id in pairs(ids) do hub.ids[id] = true end
  end
  local okS, GenSave = pcall(require, "src.save_convert.GenSave")
  if okS and type(GenSave) == "table" and type(GenSave.crosswalks) == "function" then
    local hub = GenSave.__ndxGen12Tms
    if not hub then
      hub = { ids = {} }
      GenSave.__ndxGen12Tms = hub
      local base = GenSave.crosswalks
      GenSave.crosswalks = function(data, ...)
        local cw = base(data, ...)
        if type(cw) == "table" and type(cw.itemsIndex) == "table" then
          for id in pairs(hub.ids) do
            local n = cw.itemsIndex[id]
            if n ~= nil then
              cw.itemsIndex[id] = nil
              if cw.itemsByIndex and cw.itemsByIndex[n] == id then cw.itemsByIndex[n] = nil end
            end
          end
        end
        return cw
      end
    end
    for id in pairs(ids) do hub.ids[id] = true end
  end
end

return Tms
