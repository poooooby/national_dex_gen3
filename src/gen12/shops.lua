-- Putting items on sale on Gen 1 / Gen 2.
--   Red: a clerk's `mart` list in the text_pointers registry, which is deep, so a patch's list is
--        added to the clerk's (where = { map, text }).
--   Gold: the marts registry's lists "0".."33"; a patch replaces a whole list, so every list that
--        STARTS with the store's own stock (where = { ids... }) gets ours appended. Matching the
--        start, not the whole list, still finds a store another addition already extended, and
--        covers a store whose stock grows in the story (Goldenrod 5F's four TM lists).
-- Shops.add(mod, generation, where, ids) -> number of stores stocked (raises on none).

local Shops = {}

local function startsWith(list, prefix)
  if type(list) ~= "table" or #list < #prefix then return false end
  for i = 1, #prefix do if list[i] ~= prefix[i] then return false end end
  return true
end

function Shops.add(mod, generation, where, ids)
  if #ids == 0 then return 0 end
  if generation == 1 then
    local pointers = mod.content.text_pointers
    local map = pointers:get(where.map)
    local clerk = map and map[where.text]
    if not (clerk and clerk.mart) then error("no " .. where.map .. " " .. where.text) end
    local extra = {}
    for i, id in ipairs(ids) do extra[i] = id end
    pointers:patch(where.map, { [where.text] = { mart = extra } })
    return 1
  end
  local marts, n = mod.content.marts, 0
  for i = 0, 33 do
    local list = marts:get(tostring(i))
    if startsWith(list, where) then
      local stock, have = {}, {}
      for _, id in ipairs(list) do stock[#stock + 1] = id; have[id] = true end
      for _, id in ipairs(ids) do
        if not have[id] then stock[#stock + 1] = id end
      end
      marts:patch(tostring(i), stock)
      n = n + 1
    end
  end
  if n == 0 then error("no store sells " .. table.concat(where, ", ")) end
  return n
end

return Shops
