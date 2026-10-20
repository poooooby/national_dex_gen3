-- The "Bigger PC" option: 40 PC boxes (1200 Pokemon) instead of Gen 3's 14, on every Gen 3 game
-- and in the save editor.
--
-- The count: one module field, Storage.TOTAL_BOXES_COUNT (src.core.game3.storage), which every
-- storage function, the box screen (switching, SWITCH BOX, deposit), catching and the box-space
-- scripts read live. It is set while mods load, before a Continue restores the save.
--
-- Where boxes 15-40 are saved: NOT in the save's own storage. They go in this mod's save data
-- (save.modData.national_dex_gen3.pc = { boxes = { [15] = box, ... }, currentBox = n }), which the
-- engine carries through every load and save untouched, even without this mod. The core save
-- stays a normal 14-box save, so turning the option off, removing the mod, the cross-game Box
-- tool and .sav export never drop the Pokemon in them (with 14 boxes the engine would skip boxes
-- 15+ on load and the next save would lose them). On load (save.loading, the raw save) they are
-- put back into the storage before the engine restores it; on save (save.writing, the table about
-- to be written) they are taken out again. Turning the option off in the menu moves them from the
-- live PC into the save data the same way, and turning it on brings them back.
--
-- Boxes 15-40 start with the 16 cart wallpapers in turn (Storage.defaultWallpaper is wrapped for
-- them, so the engine also treats that wallpaper as the box's default); boxes 1-14 keep the cart's
-- own four.
local BigPc = {}

BigPc.BASE = 14
BigPc.COUNT = 40
BigPc.WALLPAPERS = 16
local KEY = "national_dex_gen3"

-- every box of `data` past BASE (a serialized storage or a live one: { boxes, currentBox }) into
-- modData[KEY].pc, leaving data a 14-box storage. Only boxes with a Pokemon, a name or a wallpaper
-- of their own are kept, as Storage.serialize does. Returns the modData table.
function BigPc.split(data, modData, defaultWallpaper)
  modData = type(modData) == "table" and modData or {}
  if type(data) ~= "table" then return modData end
  local pc = { boxes = {} }
  local any = false
  for b, box in pairs(type(data.boxes) == "table" and data.boxes or {}) do
    local n = tonumber(b)
    if n and n > BigPc.BASE then
      data.boxes[b] = nil
      if type(box) == "table" then
        local hasMon = false
        for _, mon in pairs(type(box.mons) == "table" and box.mons or {}) do
          if mon ~= nil then hasMon = true break end
        end
        local default = defaultWallpaper and defaultWallpaper(n)
        if hasMon or (box.name and box.name ~= string.format("BOX %d", n))
            or (box.wallpaper and default and box.wallpaper ~= default) then
          pc.boxes[n] = box
          any = true
        end
      end
    end
  end
  local current = tonumber(data.currentBox)
  if current and current > BigPc.BASE then
    pc.currentBox = current
    data.currentBox = 1
    any = true
  end
  local mine = type(modData[KEY]) == "table" and modData[KEY] or {}
  mine.pc = any and pc or nil
  modData[KEY] = mine
  return modData
end

-- the boxes stored by split back into `data` (boxes BASE+1 .. COUNT) and the current box; the
-- stored copy is removed once it is back in the storage (the next save writes it again)
function BigPc.merge(data, modData)
  local mine = type(modData) == "table" and type(modData[KEY]) == "table" and modData[KEY] or nil
  local pc = mine and type(mine.pc) == "table" and mine.pc or nil
  if not (pc and type(data) == "table") then return false end
  data.boxes = type(data.boxes) == "table" and data.boxes or {}
  local left = {}
  for b, box in pairs(type(pc.boxes) == "table" and pc.boxes or {}) do
    local n = tonumber(b)
    if n and n > BigPc.BASE and n <= BigPc.COUNT and type(box) == "table" then
      data.boxes[n] = box
    else
      left[b] = box
    end
  end
  local current = tonumber(pc.currentBox)
  if current and current > BigPc.BASE and current <= BigPc.COUNT then data.currentBox = current end
  mine.pc = next(left) and { boxes = left } or nil
  return true
end

-- Storage's box count and default wallpapers (once per Storage module)
function BigPc.setCount(Storage, on)
  if type(Storage) ~= "table" then return end
  if not Storage.__nationalDexBigPc and type(Storage.defaultWallpaper) == "function" then
    Storage.__nationalDexBigPc = true
    local default = Storage.defaultWallpaper
    Storage.defaultWallpaper = function(boxNumber, ...)
      local n = tonumber(boxNumber)
      if n and n > BigPc.BASE then return ((n - 1) % BigPc.WALLPAPERS) + 1 end
      return default(boxNumber, ...)
    end
  end
  Storage.TOTAL_BOXES_COUNT = on and BigPc.COUNT or BigPc.BASE
  Storage.TOTAL_BOX_MONS = Storage.TOTAL_BOXES_COUNT * (tonumber(Storage.IN_BOX_COUNT) or 30)
end

-- the option changed while playing: move boxes 15-40 between the live PC and the save data
function BigPc.toggleLive(Storage, session, on)
  BigPc.setCount(Storage, on)
  if type(session) ~= "table" then return end
  session.modData = type(session.modData) == "table" and session.modData or {}
  if on then
    Storage.ensure(session)
    BigPc.merge(session.storage, session.modData)
    for b = BigPc.BASE + 1, BigPc.COUNT do
      local box = session.storage.boxes[b]
      if type(box) == "table" and type(box.mons) ~= "table" then box.mons = {} end
    end
  elseif type(session.storage) == "table" then
    BigPc.split(session.storage, session.modData, Storage.defaultWallpaper)
  end
end

-- opts: { mod, require, enabled = fn() -> bool, log }
function BigPc.installGame(opts)
  local req, mod = opts.require, opts.mod
  local okS, Storage = pcall(req, "src.core.game3.storage")
  if not (okS and type(Storage) == "table" and type(Storage.ensure) == "function") then
    if opts.log then opts.log:warn("bigger PC is off: the PC storage module was not found") end
    return false
  end
  local function on()
    local ok, v = pcall(opts.enabled)
    return ok and v == true
  end
  BigPc.setCount(Storage, on())
  mod.events:on("save.loading", function(ev)
    local raw = type(ev) == "table" and ev.raw
    BigPc.setCount(Storage, on())
    if on() and type(raw) == "table" and type(raw.storage) == "table" then
      raw.modData = type(raw.modData) == "table" and raw.modData or {}
      BigPc.merge(raw.storage, raw.modData)
    end
  end)
  mod.events:on("save.writing", function(ev)
    local save = type(ev) == "table" and ev.save
    if on() and type(save) == "table" and type(save.storage) == "table" then
      save.modData = BigPc.split(save.storage, save.modData, Storage.defaultWallpaper)
    end
  end)
  mod.events:on("mod.options_changed", function(ev)
    if not (type(ev) == "table" and ev.mod == mod.id and ev.key == "big_pc") then return end
    local okR, Runtime = pcall(req, "src.core.game3.runtime")
    local session = okR and Runtime.getSession and Runtime.getSession() or nil
    local okT, err = pcall(BigPc.toggleLive, Storage, session, on())
    if not okT and opts.log then opts.log:warn("bigger PC: %s", tostring(err)) end
  end)
  if opts.log then opts.log:info("bigger PC: %d boxes", Storage.TOTAL_BOXES_COUNT) end
  return true
end

-- The save editor: its own 14s (Gen.boxCount, Game3Adapter.ensureStorage, Ops.deposit) and its load
-- (hydrate) / save (export). opts: { require, enabled = fn() -> bool, log }
function BigPc.installEditor(opts)
  local req = opts.require
  local okS, Storage = pcall(req, "src.core.game3.storage")
  local okG, Gen = pcall(req, "Gen")
  local okA, Adapter = pcall(req, "Game3Adapter")
  local okO, Ops = pcall(req, "Ops")
  if not (okS and okG and okA and okO and type(Adapter) == "table" and type(Adapter.ensureStorage) == "function") then
    if opts.log then opts.log:warn("bigger PC is off in the save editor: its storage modules were not found") end
    return false
  end
  local okE, enabled = pcall(opts.enabled)
  local on = okE and enabled == true
  BigPc.setCount(Storage, on)
  if not on or Adapter.__nationalDexBigPc then return on end
  Adapter.__nationalDexBigPc = true
  local count = function() return tonumber(Storage.TOTAL_BOXES_COUNT) or BigPc.BASE end

  local boxCount = Gen.boxCount
  Gen.boxCount = function(save, ...)
    if Gen.of(save) == 3 then return count() end
    return boxCount(save, ...)
  end

  -- Game3Adapter.ensureStorage with the box count in place of its 14
  local function equal(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
  end
  Adapter.ensureStorage = function(save)
    local n = count()
    local legacy = type(save.storage) ~= "table"
    local source = legacy and Storage.restore(nil, save.pc, save.pcItems or save.pc_items) or save.storage
    local storage = {}
    for k, v in pairs(source) do storage[k] = v end
    storage.boxes, storage.items = {}, source.items or {}
    local boxes, available = {}, {}
    for b = 1, n do
      local original = source.boxes and source.boxes[b]
        or { name = "BOX " .. b, wallpaper = Storage.defaultWallpaper(b) }
      local box = {}
      for k, v in pairs(original) do box[k] = v end
      box.mons = {}
      for s, mon in pairs(original.mons or {}) do
        box.mons[s] = mon
        available[#available + 1] = { mon = mon }
      end
      storage.boxes[b], boxes[b] = box, box.mons
    end
    for b, box in pairs(save.boxes or {}) do
      for s, mon in pairs(type(box) == "table" and box or {}) do
        if type(s) == "number" and type(mon) == "table" then
          local mirrored = false
          for _, entry in ipairs(available) do
            if not entry.used and equal(entry.mon, mon) then entry.used = true; mirrored = true; break end
          end
          if not mirrored then
            local targetB, targetS
            if boxes[b] and s >= 1 and s <= 30 and s == math.floor(s) and not boxes[b][s] then
              targetB, targetS = b, s
            else
              targetB, targetS = Storage.findOpenSlot(storage)
            end
            if not targetB then error("Cannot preserve legacy box Pokemon: native storage is full") end
            boxes[targetB][targetS] = mon
          end
        end
      end
    end
    save.storage = storage
    if legacy and type(save.pc) == "table" then save.pc.mons, save.pc.items = nil, nil end
    save.boxes = boxes
    save.currentBox = math.max(1, math.min(n, tonumber(storage.currentBox) or 1))
    return boxes
  end

  -- load: boxes 15-40 from this mod's save data into the storage first
  local hydrate = Adapter.hydrate
  Adapter.hydrate = function(data, save, ...)
    if type(save) == "table" and type(save.storage) == "table" then
      save.modData = type(save.modData) == "table" and save.modData or {}
      BigPc.merge(save.storage, save.modData)
    end
    return hydrate(data, save, ...)
  end
  -- save: and back out of the storage into it
  local export = Adapter.export
  Adapter.export = function(save, ...)
    local out = export(save, ...)
    if type(out) == "table" and type(out.storage) == "table" then
      out.modData = BigPc.split(out.storage, out.modData, Storage.defaultWallpaper)
      if tonumber(out.currentBox) and out.currentBox > BigPc.BASE then out.currentBox = out.storage.currentBox end
    end
    return out
  end

  -- deposit: the editor's own search covers boxes 1-14 only; a box past 14 is filled here
  local deposit = Ops.deposit
  Ops.deposit = function(S, ...)
    if not (Gen.ofState(S) == 3 and count() > BigPc.BASE) then return deposit(S, ...) end
    local i = S.selectedParty
    local mon = S.save and S.save.party and S.save.party[i]
    if not mon then return deposit(S, ...) end
    local boxes = Ops.boxes(S)
    local n = count()
    local first = S.selectedBox or S.save.currentBox or 1
    for offset = 0, n - 1 do
      local b = ((first - 1 + offset) % n) + 1
      if Ops.boxSize(S, boxes[b]) < 30 then
        if b <= BigPc.BASE then
          S.selectedBox = b
          return deposit(S, ...)
        end
        local box, slot = boxes[b], nil
        local wanted = S.selectedBoxSlot
        if wanted and wanted >= 1 and wanted <= 30 and not box[wanted] then slot = wanted
        else for s = 1, 30 do if not box[s] then slot = s break end end end
        box[slot] = mon
        table.remove(S.save.party, i)
        S.selectedParty = math.max(1, math.min(i, math.max(#S.save.party, 1)))
        S.selectedBox, S.selectedBoxSlot = b, slot
        if S.editingMon == mon then S.editingMon = nil end
        local name = Ops.speciesName and Ops.speciesName(S, mon.species) or tostring(mon.species)
        return Ops.mark(S, ("Deposited %s into box %d"):format(name, b))
      end
    end
    return Ops.say(S, "Every box is full")
  end
  return true
end

return BigPc
