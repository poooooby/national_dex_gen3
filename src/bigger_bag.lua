-- The "Bigger Bag" option (on by default) on FireRed to Emerald: the Bag's pockets and the PC's
-- item storage hold more different items, room for the evolution items, held items, candies and
-- Dynamax items this mod adds (about 230, nearly all in the Items pocket).
--
-- Every limit is read live: the Bag's from ItemsData.CAPACITY (refilled from the game profile's
-- bag.capacity by ItemsData.applyProfile, which src/tms.lua grows for the TM Case), the PC's from
-- Storage.pcItemsCount. So applyProfile is wrapped to raise the pockets after each refill, and
-- pcItemsCount to answer the bigger PC; the profiles themselves are never edited.
--
-- Nothing is ever dropped: loading a save trims the PC to its limit (Storage.restore), so the
-- limit is lifted while a save loads, and the Bag never trims a pocket on load. With the option
-- off, a pocket or the PC holding more than the game's own limit keeps everything; it only takes
-- no new item until it is back under the limit, as a full Bag does. A cartridge .sav export still
-- holds the game's own amounts.
local Bag = {}

-- slots per pocket while on (a pocket keeps a bigger size it already has: the TM Case)
Bag.POCKETS = { ITEMS = 300, KEY_ITEMS = 60, POKE_BALLS = 30, BERRY_POUCH = 60 }
Bag.PC_ITEMS = 300

local LIFTED = 100000

-- opts: { require, enabled() -> bool, log }. Returns refresh() (re-reads the option), or nil.
function Bag.install(opts)
  local require, log = opts.require, opts.log
  local okI, ItemsData = pcall(require, "src.core.game3.items_data")
  local okS, Storage = pcall(require, "src.core.game3.storage")
  if not (okI and type(ItemsData) == "table" and type(ItemsData.applyProfile) == "function"
      and okS and type(Storage) == "table" and type(Storage.pcItemsCount) == "function") then
    if log then log:warn("bigger bag is off: the bag or PC module was not found") end
    return nil
  end
  -- process-wide wraps (a reload hands the new enabled() over)
  local hub = ItemsData.__ndxBiggerBag
  if not hub then
    hub = { pockets = Bag.POCKETS, pc = Bag.PC_ITEMS, restoring = 0 }
    ItemsData.__ndxBiggerBag = hub
    local applyProfile = ItemsData.applyProfile
    ItemsData.applyProfile = function(...)
      local bag = applyProfile(...)
      hub.raise()
      return bag
    end
    local pcItemsCount = Storage.pcItemsCount
    Storage.pcItemsCount = function(...)
      local n = pcItemsCount(...)
      if hub.restoring > 0 then return LIFTED end
      if hub.enabled() and type(n) == "number" and n < hub.pc then return hub.pc end
      return n
    end
    local restore = Storage.restore
    if type(restore) == "function" then
      Storage.restore = function(...)
        hub.restoring = hub.restoring + 1
        local ok, a, b, c = pcall(restore, ...)
        hub.restoring = hub.restoring - 1
        if not ok then error(a, 0) end
        return a, b, c
      end
    end
  end
  hub.enabled = opts.enabled

  -- the live pocket sizes: the profile's own (TM Case grown by src/tms.lua), raised while on
  function hub.raise()
    local cap, model = ItemsData.CAPACITY, ItemsData._bagModel
    local base = type(model) == "table" and model.capacity
    if type(cap) ~= "table" or type(base) ~= "table" then return end
    local on = hub.enabled()
    for pocket, n in pairs(base) do
      local want = hub.pockets[pocket]
      cap[pocket] = (on and want and want > n) and want or n
    end
  end

  hub.raise()
  if log then
    log:info("bigger bag: %s (Items %d, PC %d)", hub.enabled() and "on" or "off", Bag.POCKETS.ITEMS,
      Bag.PC_ITEMS)
  end
  return hub.raise
end

return Bag
