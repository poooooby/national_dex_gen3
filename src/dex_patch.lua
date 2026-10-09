-- Lets the Ruby/Sapphire/Emerald Pokedex scroll past #386.
--
-- The engine's src/ui/game3/rse/pokedex.lua sizes its National list from the cart's order pack
-- (which fixups.installRseDexOrders extends), but two of its local functions still compare the
-- list position against a literal 386 (`spriteDexNum`, `setRow`), so rows and sprites past #386
-- stay blank. Locals cannot be wrapped, so this reads the engine's own source, swaps those two
-- literals for the length of the National order, runs the result as a second copy of the module
-- and copies its functions into the live module table (everything that requires the module,
-- e.g. the battle's caught-Pokemon page, then gets the fixed ones).
--
-- It is best effort and silent by design: the source is matched by exact text, so an engine
-- that has changed or fixed those lines simply gives no match; an unreadable source, a compile
-- error or an error while running the copy all leave the stock module untouched.

local DexPatch = {}

local PATH = "src/ui/game3/rse/pokedex.lua"
local LIMIT = "#Gfx.orders().numerical_national"
local MODULE = "src.ui.game3.rse.pokedex"

-- The two literals, each of which must match exactly once. Returns the patched source, or nil.
function DexPatch.patchSource(source)
  if type(source) ~= "string" then return nil end
  local out = source
  for _, pattern in ipairs({ "(or i >= )386( then return NONE end)", "(or entryNum >= )386( then)" }) do
    local count
    out, count = out:gsub(pattern, "%1" .. LIMIT .. "%2")
    if count ~= 1 then return nil end
  end
  -- `package` is not in a mod's sandbox (see packageStandIn); a local would risk the 200-local limit
  return (out:gsub("package%.loaded%[", "__nationalDexPackage.loaded["))
end

-- The `package` the module reads (three lookups of already-loaded engine modules) is not in a
-- mod's sandbox, so the copy is given a stand-in that answers through `require`.
local function packageStandIn(require)
  return { loaded = setmetatable({}, { __index = function(_, name)
    local ok, module = pcall(require, name)
    return ok and module or nil
  end }) }
end

-- opts: read(path) -> source|nil, load (the mod's), require (the mod's), log
-- Returns true when the live module was replaced, else false and why.
function DexPatch.install(opts)
  opts = opts or {}
  local log = opts.log
  local function fail(why)
    if log and log.warn then log:warn("the Pokedex keeps its stock list, capped at #386 (%s)", why) end
    return false, why
  end
  local require = opts.require or _G.require
  local okM, live = pcall(require, MODULE)
  if not (okM and type(live) == "table") then return fail("module unavailable") end
  if live.__nationalDexGen3 then return true end

  local okR, source = pcall(opts.read or function() return nil end, PATH)
  if not (okR and type(source) == "string") then return fail("engine source not readable") end
  local patched = DexPatch.patchSource(source)
  if not patched then return fail("engine source is not the expected one") end

  local env = opts.env or _G
  env.__nationalDexPackage = packageStandIn(require)
  local chunk, err = (opts.load or load)(patched, "@" .. PATH)
  if not chunk then return fail("compile: " .. tostring(err)) end
  local okC, copy = pcall(chunk)
  if not (okC and type(copy) == "table" and type(copy.show) == "function") then
    return fail("run: " .. tostring(copy))
  end
  DexPatch.extendNumbers(copy)
  for key, value in pairs(copy) do
    if key ~= "lastSelected" and key ~= "lastRotation" then live[key] = value end
  end
  live.__nationalDexGen3 = true
  if log and log.info then log:info("the Pokedex list now runs past #386") end
  return true
end

-- The A-Z, weight and height lists keep a National number only if it has a Hoenn number
-- (`List.create` -> inRange -> Pokedex.hoennNumber), and the cart's table stops at #386, so the
-- added species were dropped from them. Past #386 a species answers with its own number: in the
-- National list (limit = its length) that is in range; in the Hoenn list (<= 386) it is out.
-- Applied to the module TABLE the screen's own code reads (`Pokedex.hoennNumber` is looked up
-- on it at call time), i.e. the patched copy: wrapping the live table would not reach it.
local function extendNumbers(module)
  if type(module) ~= "table" or type(module.hoennNumber) ~= "function" then return false end
  local original = module.hoennNumber
  module.hoennNumber = function(nat)
    local n = original(nat)
    if n == nil and type(nat) == "number" and nat > 386 and nat <= 1025 then return nat end
    return n
  end
  return true
end
DexPatch.extendNumbers = extendNumbers

-- ------- FireRed / LeafGreen

local FRLG_PATH = "src/ui/game3/pokedex.lua"
local FRLG_MODULE = "src.ui.game3.pokedex"

-- Left and right on the list screen switch between the Kanto and National lists, and the way
-- back (left from National) keeps the National list's scroll, which is past the end of the
-- Kanto list, so the screen goes blank. In the real games left and right page up and down the
-- list you are in (the lists are chosen on the contents screen), which is what the screen's own
-- paging branches already do, so switch the list-changing branches off. The copy also runs on
-- the LIVE module table, so the state other code reads (`open`, `_dex`) stays in one place.
-- Returns the patched source, or nil unless each pattern matches once.
function DexPatch.patchFrlgSource(source)
  if type(source) ~= "string" then return nil end
  local out, count = source:gsub("local Pokedex = { isMenu = true }",
    'local Pokedex = require("' .. FRLG_MODULE .. '"); Pokedex.isMenu = true')
  if count ~= 1 then return nil end
  out, count = out:gsub('if Pokedex%.currentOrder == "numerical_national" then(%s+Pokedex%.currentOrder = "numerical_kanto")',
    "if false then%1")
  if count ~= 1 then return nil end
  out, count = out:gsub('if Pokedex%.currentOrder == "numerical_kanto" and Pokedex%.mode == "kanto" then(%s+Pokedex%.currentOrder = "numerical_national")',
    "if false then%1")
  if count ~= 1 then return nil end
  return out
end

-- Same opts as install(). Silent fallback to the stock screen, with a warning.
function DexPatch.installFrlg(opts)
  opts = opts or {}
  local log = opts.log
  local function fail(why)
    if log and log.warn then log:warn("the FireRed/LeafGreen Pokedex keeps its stock screen (%s)", why) end
    return false, why
  end
  local require = opts.require or _G.require
  local okM, live = pcall(require, FRLG_MODULE)
  if not (okM and type(live) == "table") then return fail("module unavailable") end
  if live.__nationalDexFrlg then return true end
  local okR, source = pcall(opts.read or function() return nil end, FRLG_PATH)
  if not (okR and type(source) == "string") then return fail("engine source not readable") end
  local patched = DexPatch.patchFrlgSource(source)
  if not patched then return fail("engine source is not the expected one") end
  local chunk, err = (opts.load or load)(patched, "@" .. FRLG_PATH)
  if not chunk then return fail("compile: " .. tostring(err)) end
  local okC, copy = pcall(chunk)
  if not (okC and copy == live) then return fail("run: " .. tostring(copy)) end
  live.__nationalDexFrlg = true
  if log and log.info then log:info("the FireRed/LeafGreen Pokedex scroll fix is in") end
  return true
end

return DexPatch
