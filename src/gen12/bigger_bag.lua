-- The "Bigger Bag" option on Red to Crystal (same key as Gen 3's src/bigger_bag.lua): the Bag and
-- the PC's item storage hold more, room for the items this mod adds.
--
-- The engine's limits:
--   the Bag: every add asks Bag.capacity(data, pocket) on the shared module (src.inventory.Bag;
--     Red's one list is the ITEM pocket, Gold's pockets ITEM / BALL / KEY_ITEM; TM_HM is grown by
--     src/gen12/tms.lua and left alone here). Wrapped once per process.
--   the PC: Red's PlayerPC and Gold's Mom read data.field.pcItemCap (50 when unset), set on the
--     live game's data; Gold's own PC menu checks a fixed 50 in ItemPcMenu:pcAdd, overridden with
--     the same stack count (99 a stack) against the bigger limit.
-- Loading a save never trims the Bag or the PC, so turning the option off loses nothing: a fuller
-- pocket or PC keeps its items and only takes no new kind until it is back under the limit.
-- A cartridge .sav export holds the game's own amounts (Red's export keeps the first 20 / 50,
-- Gold's refuses an over-full Bag).
local BiggerBag = {}

BiggerBag.POCKETS = { ITEM = 300, BALL = 30, KEY_ITEM = 60 }
BiggerBag.PC = 300
local MAX_STACK = 99

-- opts: { require, generation, enabled() -> bool, log }. Returns state:
--   apply(data) -> the PC limit on this game's data (the option as it is now)
function BiggerBag.install(opts)
  local require, log = opts.require, opts.log
  local okB, Bag = pcall(require, "src.inventory.Bag")
  if not (okB and type(Bag) == "table" and type(Bag.capacity) == "function") then
    if log then log:warn("bigger bag is off: the Bag module was not found") end
    return nil
  end
  local hub = Bag.__ndxBiggerBag
  if not hub then
    hub = { pockets = BiggerBag.POCKETS, pc = BiggerBag.PC }
    Bag.__ndxBiggerBag = hub
    local capacity = Bag.capacity
    Bag.capacity = function(data, pocket, ...)
      local n = capacity(data, pocket, ...)
      local want = hub.pockets[pocket or "ITEM"]
      if want and type(n) == "number" and n < want and hub.enabled() then return want end
      return n
    end
  end
  hub.enabled = opts.enabled

  if opts.generation == 2 then
    local okM, Menu = pcall(require, "src.ui.gen2.ItemPcMenu")
    if okM and type(Menu) == "table" and type(Menu.pcAdd) == "function" and not Menu.__ndxBiggerBag then
      Menu.__ndxBiggerBag = true
      local pcAdd = Menu.pcAdd
      local function stacksFor(n) return math.ceil((n or 0) / MAX_STACK) end
      Menu.pcAdd = function(self, id, qty, ...)
        local pc = type(self) == "table" and type(self.save) == "table" and self.save.pcItems
        if not (Bag.__ndxBiggerBag.enabled() and type(pc) == "table") then return pcAdd(self, id, qty, ...) end
        local held = pc[id] or 0
        local used = 0
        for _, count in pairs(pc) do used = used + stacksFor(count) end
        local need = stacksFor(held + qty) - stacksFor(held)
        if used + need > Bag.__ndxBiggerBag.pc then return false end
        pc[id] = held + qty
        return true
      end
    end
  end

  local state = {}
  -- marked[data] = the limit this module wrote (it only ever clears its own)
  local marked = setmetatable({}, { __mode = "k" })
  function state.apply(data)
    local field = type(data) == "table" and data.field
    if type(field) ~= "table" then
      if type(data) == "table" and data.field == nil then
        data.field = {}
        field = data.field
      else
        return
      end
    end
    if hub.enabled() then
      local cur = field.pcItemCap
      if cur == nil or cur == marked[data] or (type(cur) == "number" and cur < hub.pc) then
        field.pcItemCap = hub.pc
        marked[data] = hub.pc
      end
    elseif marked[data] ~= nil and field.pcItemCap == marked[data] then
      field.pcItemCap = nil
      marked[data] = nil
    end
  end
  return state
end

return BiggerBag
