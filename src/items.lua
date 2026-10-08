-- Registers the evolution items no Gen 3 game has, so this mod's own
-- evolutions (and anyone else's, via the same normal item lookup) light up
-- without waiting on a companion item mod. data/items.lua lists them
-- (payload built by tools/build_items.py); each gets a fixed slot at
-- index 900+ (every Gen 3 game's own items top out at 365).
--
-- This is a NORMAL registry write (mod.content.items:register), the same
-- as a held-item mod would do -- it needs no engine_internals widening.
-- Only the Bag icon (src/item_art.lua) reaches past the registry, because
-- no hook offers one.

local Items = {}

function Items.loadPayload(load)
  local list = load("data/items.lua")
  return type(list) == "table" and list or {}
end

-- Registers every item; returns the list actually registered.
function Items.register(mod, payload)
  local registered, failed, firstError = {}, 0, nil
  for _, r in ipairs(payload) do
    local ok, err = pcall(function()
      mod.content.items:register(r.id, {
        id = r.id, name = r.name, index = r.index,
        price = 0, pocket = "ITEMS",
      })
    end)
    if ok then
      registered[#registered + 1] = r
    else
      failed = failed + 1
      firstError = firstError or tostring(err)
    end
  end
  mod.log:info("registered %d evolution item(s) Gen 3 lacks", #registered)
  if failed > 0 then
    mod.log:warn("%d item(s) failed to register; first: %s", failed, firstError)
  end
  return registered
end

return Items
