-- Held items on Red / Blue / Yellow, which have none of their own: Gold's held items
-- (data/gen12/held.lua) become Red items, sold at the Celadon Dept. Store 4F; a party Pokemon holds
-- one in its mod bag (mon.extra.national_dex_gen3.item, which the save keeps; a cable trade's
-- whitelist and a cartridge .sav leave it out); the party menu's ITEM gives one from the Bag or
-- takes it back. Their battle effects are src/gen12/mech/held.lua's; Everstone and the Smoke Ball
-- act outside the move pipeline, through the evolution.check and battle.run hooks here.

local HeldRed = {}

local function bagOf(mon, create)
  if type(mon) ~= "table" then return nil end
  if not mon.extra then
    if not create then return nil end
    mon.extra = {}
  end
  local bag = mon.extra.national_dex_gen3
  if not bag and create then bag = {}; mon.extra.national_dex_gen3 = bag end
  return bag
end

function HeldRed.itemOf(mon)
  local bag = bagOf(mon, false)
  return bag and bag.item or nil
end
function HeldRed.setItem(mon, id)
  local bag = bagOf(mon, id ~= nil)
  if bag then bag.item = id end
end

-- opts: { mod, rows (data/gen12/held.lua), require, log }. Returns { registered = { id } }.
function HeldRed.install(opts)
  local mod, require, log = opts.mod, opts.require, opts.log
  local items = mod.content.items
  local state = { registered = {}, effects = {} }
  for _, row in ipairs(opts.rows or {}) do
    state.effects[row.id] = row
    if items:get(row.id) == nil then
      local ok, err = pcall(items.register, items, row.id, { id = row.id, name = row.name, price = row.price })
      if ok then state.registered[#state.registered + 1] = row.id
      elseif log then log:warn("held item %s: %s", row.id, tostring(err)) end
    end
  end

  -- on sale at the Celadon Dept. Store 4F, beside the evolution items
  if #state.registered > 0 then
    pcall(function()
      local pointers = mod.content.text_pointers
      local map = pointers:get("CeladonMart4F")
      local clerk = map and map.TEXT_CELADONMART4F_CLERK
      if clerk and clerk.mart then
        local extra = {}
        for _, id in ipairs(state.registered) do extra[#extra + 1] = id end
        pointers:patch("CeladonMart4F", { TEXT_CELADONMART4F_CLERK = { mart = extra } })
      end
    end)
  end

  -- the party menu: ITEM gives one from the Bag, or takes back what it holds
  local Strings = require("src.core.Strings")
  local function name(game, id)
    local d = game.data.items[id]
    return (d and d.name) or tostring(id)
  end
  local function message(game, text)
    local top = game.stack and game.stack:top()
    if top and top.setMessage then
      top.submenu = nil
      top:setMessage(text)
    end
  end
  local function give(mon, game)
    local Bag = require("src.inventory.Bag")
    local ListMenu = require("src.ui.ListMenu")
    local rows = {}
    for _, r in ipairs(Bag.rows(game.save, game.data)) do
      local d = game.data.items[r.id]
      if not (d and d.keyItem) and not tostring(r.id):find("^HM_") then
        rows[#rows + 1] = { value = r.id, label = name(game, r.id), count = r.count, slot = r.slot }
      end
    end
    rows[#rows + 1] = { cancel = true, label = Strings("CANCEL") }
    local list
    list = ListMenu.new(game, Strings.source("ITEMS"), rows, {
      itemBox = true,
      onChoose = function(row)
        game.stack:pop()
        if row.cancel then return end
        if Bag.remove(game.save, row.value, 1, game.data, row.slot) == false then return end
        HeldRed.setItem(mon, row.value)
        message(game, Strings("%s is now\nholding %s.", mon.nickname or mon.name or mon.species, name(game, row.value)))
      end,
      onCancel = function() game.stack:pop() end,
    })
    game.stack:push(list)
  end
  local function take(mon, game)
    local Bag = require("src.inventory.Bag")
    local id = HeldRed.itemOf(mon)
    if not id then return end
    if Bag.add(game.save, id, 1, game.data) == false then
      message(game, Strings("The BAG is full."))
      return
    end
    HeldRed.setItem(mon, nil)
    message(game, Strings("Took %s\nfrom %s.", name(game, id), mon.nickname or mon.name or mon.species))
  end
  pcall(function()
    mod.hooks:wrap("ui.party.submenu", function(nextFn, game, items_, mon, ctx)
      local list = nextFn(game, items_, mon, ctx)
      if type(list) ~= "table" or (ctx and ctx.battle) or type(mon) ~= "table" then return list end
      local held = HeldRed.itemOf(mon)
      local row = { label = Strings(held and "TAKE" or "ITEM"), onSelect = function(m, g)
        if HeldRed.itemOf(m) then take(m, g) else give(m, g) end
      end }
      -- above STATS, the way Gold's party menu lists ITEM
      local at = #list + 1
      for i, r in ipairs(list) do if r.action == "stats" then at = i break end end
      table.insert(list, at, row)
      return list
    end)
  end)

  -- Everstone: no evolution; the Smoke Ball: a sure escape from a wild battle
  pcall(function()
    mod.hooks:wrap("evolution.check", function(nextFn, a, mon, row, trig)
      local ok = nextFn(a, mon, row, trig)
      if ok and HeldRed.itemOf(mon) == "EVERSTONE" then return false end
      return ok
    end)
  end)
  pcall(function()
    mod.hooks:wrap("battle.run", function(nextFn, c)
      local b = c and c.battle
      local mon = b and b.player and b.player.mon
      if mon and HeldRed.itemOf(mon) == "SMOKE_BALL" then return true end
      return nextFn(c)
    end)
  end)
  return state
end

return HeldRed
