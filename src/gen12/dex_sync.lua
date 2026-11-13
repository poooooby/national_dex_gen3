-- The "Register Owned" option on Gen 1 / Gen 2: opening the Pokedex first marks every Pokemon in
-- the party and the PC boxes as seen and caught (Red: save.pokedex seen / owned; Gold: seen /
-- caught), so a Pokemon put in with a save editor counts. Eggs are skipped (Gold). A form also
-- marks its base, through src/gen12/dex.lua's sync.
--
-- The seam is each game's Pokedex screen constructor (src/ui/PokedexMenu.lua and
-- src/ui/gen2/PokedexMenu.lua, both `PokedexMenu.new(game, opts)`), which builds its counts from
-- the save. The wrap goes on the module once per run (modules outlive a mod load, and the player
-- can switch games without restarting) and asks the current load's handler.

local DexSync = {}

DexSync.MODULES = { [1] = "src.ui.PokedexMenu", [2] = "src.ui.gen2.PokedexMenu" }

-- Mark everything the save holds. Returns how many Pokemon it looked at.
function DexSync.sync(save, gen, forms, syncForms)
  if type(save) ~= "table" then return 0 end
  save.pokedex = save.pokedex or { seen = {} }
  local p = save.pokedex
  p.seen = p.seen or {}
  local key = gen == 1 and "owned" or "caught"
  p[key] = p[key] or {}
  local n = 0
  local function mark(mon)
    if type(mon) ~= "table" or not mon.species or mon.isEgg == true then return end
    p.seen[mon.species] = true
    p[key][mon.species] = true
    n = n + 1
  end
  local function list(t) for _, mon in ipairs(type(t) == "table" and t or {}) do mark(mon) end end
  list(save.party)
  if gen == 1 then list(save.box) end
  for _, box in pairs(type(save.boxes) == "table" and save.boxes or {}) do list(box) end
  if syncForms then syncForms(save, gen, forms) end
  return n
end

-- opts: { require, generation, enabled = fn() -> bool, forms, syncForms, log }
function DexSync.install(opts)
  local req = opts.require or require
  local ok, Menu = pcall(req, DexSync.MODULES[opts.generation])
  if not (ok and type(Menu) == "table" and type(Menu.new) == "function") then
    if opts.log then opts.log:warn("Register Owned is off: the Pokedex screen was not found") end
    return false
  end
  local hub = Menu.__ndxGen12Sync
  if not hub then
    hub = { orig = Menu.new }
    Menu.__ndxGen12Sync = hub
    Menu.new = function(game, ...)
      local handler = hub.handler
      if handler then pcall(handler, game) end
      return hub.orig(game, ...)
    end
  end
  hub.handler = function(game)
    if not opts.enabled() then return end
    DexSync.sync(game and game.save, opts.generation, opts.forms, opts.syncForms)
  end
  return true
end

return DexSync
