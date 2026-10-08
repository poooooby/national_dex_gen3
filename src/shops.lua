-- Puts the evolution items on sale (data/shops.lua). The engine has no shop
-- registry or hook: a store's stock is the item list its script opens, kept
-- by src.core.game3.marts, so this wraps Marts.itemsFor and appends to the
-- stored list the first time it is handed out. The list keeps its identity
-- (shop_menu finds a store by comparing the table), and a store is found by
-- its original stock, in order, so one entry covers every game with that list.
--
-- Each `add` slug is resolved LIVE (Species.itemIndex: the registry as it is
-- now), so an item another mod registered under the same slug is the one
-- sold; a slug nothing provides is skipped. Prices come from the item itself
-- (data/items.lua), and the shop already sells back at half.

local Shops = {}

local ours = setmetatable({}, { __mode = "k" })

local function sameList(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if tonumber(a[i]) ~= b[i] then return false end
  end
  return true
end

-- rules: data/shops.lua; itemIndex: Species.itemIndex(mod); game: () -> the
-- current game's version id ("firered", "emerald", ...) or nil
function Shops.install(rules, itemIndex, game, log)
  local ok, Marts = pcall(require, "src.core.game3.marts")
  if not (ok and type(Marts) == "table" and type(Marts.itemsFor) == "function")
    or ours[Marts.itemsFor] then
    return false
  end
  local orig = Marts.itemsFor
  local done = setmetatable({}, { __mode = "k" })
  Marts.itemsFor = function(key)
    local items, entry = orig(key)
    if type(items) == "table" and not done[items] then
      done[items] = true
      local version = game and game()
      for _, rule in ipairs(rules) do
        local applies = not version
        for _, g in ipairs(rule.games or {}) do
          if g == version then applies = true end
        end
        if applies and sameList(items, rule.match) then
          local added = 0
          for _, slug in ipairs(rule.add) do
            local id = itemIndex(slug)
            local present = false
            for _, have in ipairs(items) do
              if tonumber(have) == id then present = true end
            end
            if id and not present then
              items[#items + 1] = id
              added = added + 1
            end
          end
          if log and added > 0 then
            log:info("%s now also sells %d evolution item(s)", rule.store, added)
          end
        end
      end
    end
    return items, entry
  end
  ours[Marts.itemsFor] = true
  return true
end

Shops._sameList = sameList

return Shops
