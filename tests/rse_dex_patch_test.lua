-- Standalone: luajit mods/national_dex_gen3/tests/rse_dex_patch_test.lua (from the gen1recomp
-- root; reads the engine's own src/ui/game3/rse/pokedex.lua, no cart needed).
--
-- src/dex_patch.lua swaps the two literal 386s in the Ruby/Sapphire/Emerald Pokedex for the
-- length of the National order and merges a copy of the module into the live one. It must patch
-- the real engine source, run a stand-in module end to end, and do NOTHING (and not raise)
-- when the source is unreadable, different, or breaks.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local here = (arg[0]:gsub("\\", "/"):match("^(.*)/") or ".")
local DexPatch = assert(loadfile(here .. "/../src/dex_patch.lua"))()

-- the engine's own file
local real = slurp("src/ui/game3/rse/pokedex.lua")
T.check(real ~= nil, "the engine's RSE Pokedex source is readable")
if real then
  local patched = DexPatch.patchSource(real)
  T.check(patched ~= nil, "both literals are found in the engine source")
  if patched then
    T.check(not patched:find(">= 386", 1, true), "no 386 comparison is left")
    T.check(not patched:find("package.loaded[", 1, true), "package.loaded is routed through the stand-in")
    T.check(loadstring(patched, "@patched") ~= nil, "the patched source compiles")
  end
end
T.eq(DexPatch.patchSource("local x = 1"), nil, "a source without the literals is not patched")
T.eq(DexPatch.patchSource("if i < 0 or i >= 386 then return NONE end"), nil, "one literal alone is not enough")
T.eq(DexPatch.patchSource(nil), nil, "nothing to patch is fine")

-- a stand-in module: same two lines, plus a use of package.loaded
local STUB = [[
local Gfx = { orders = function() return { numerical_national = { 1, 2, 3 } } end }
local NONE = -1
local P = {}
P.lastSelected = 0
local function spriteDexNum(i)
  if i < 0 or i >= 386 then return NONE end
  return i
end
local function setRow(entryNum)
  if entryNum < 0 or entryNum >= 386 then
    return false
  end
  return true
end
function P.show() return "new" end
function P.sprite(i) return spriteDexNum(i) end
function P.row(i) return setRow(i) end
function P.loaded() return package.loaded["some.module"] end
return P
]]
-- the stub's Gfx.orders has 3 entries, so its limit is 3

local function live()
  return { show = function() return "old" end, sprite = function() return "old" end, lastSelected = 7 }
end
local log = { info = function() end }
local seen = {}
local function opts(module, source, extra)
  local o = { require = function(name)
    if name == "src.ui.game3.rse.pokedex" then return module end
    seen[name] = true
    return { name = name }
  end, read = function() return source end, load = load, log = log }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end

local module = live()
local ok = DexPatch.install(opts(module, STUB))
T.eq(ok, true, "a good source replaces the module's functions")
T.eq(module.show(), "new", "the live module now runs the copy")
T.eq(module.sprite(2), 2, "a position inside the list works")
T.eq(module.sprite(3), -1, "and one past the list length is the stub's NONE (limit is the order length)")
T.eq(module.row(2), true, "setRow accepts a position in the list")
T.eq(module.row(3), false, "and not one past it")
T.eq(module.lastSelected, 7, "the screen's remembered position is kept")
T.eq(module.loaded().name, "some.module", "package.loaded is answered through require")
T.eq(DexPatch.install(opts(module, STUB)), true, "a second install does nothing")

-- the A-Z / size lists: a species past #386 answers with its own number, the cart's keep theirs,
-- and the screen's own code (which reads the module table it was compiled with) sees it
local numbered
T.eq(DexPatch.extendNumbers({ hoennNumber = function() end }), true, "the Hoenn-number lookup can be extended")
T.eq(DexPatch.extendNumbers({}), false, "and a module without one is left alone")
local patchedModule = {}
local withNumbers = (STUB:gsub("return P%s*$", "function P.hoennNumber(nat) return nat <= 386 and nat + 1000 or nil end function P.numberFor(nat) return P.hoennNumber(nat) end return P"))
T.eq(DexPatch.install(opts(patchedModule, withNumbers)), true, "a module with a Hoenn lookup is patched")
T.eq(patchedModule.numberFor(5), 1005, "a cart species keeps its Hoenn number")
T.eq(patchedModule.numberFor(500), 500, "an added species answers with its own number, for the screen's own code")
T.eq(patchedModule.numberFor(1026), nil, "and nothing past #1025")

-- every failure leaves the stock module alone
local function untouched(label, source, extra)
  local m = live()
  local installed, why = DexPatch.install(opts(m, source, extra))
  T.eq(installed, false, label .. ": reports no patch (" .. tostring(why) .. ")")
  T.eq(m.show(), "old", label .. ": the stock module is untouched")
end
untouched("no source", nil)
untouched("a different source", "return {}")
untouched("a source that does not compile", STUB .. "\nthis is not lua", nil)
untouched("a chunk that errors", (STUB:gsub("return P%s*$", "error('boom')")))
untouched("a chunk that returns no module", (STUB:gsub("return P%s*$", "return 5")))
untouched("a reader that raises", STUB, { read = function() error("no disk") end })
local gone = DexPatch.install({ require = function() error("no module") end, read = function() return STUB end, log = log })
T.eq(gone, false, "a missing module is not an error")

-- FireRed / LeafGreen: left and right page the list instead of switching lists
local frlg = slurp("src/ui/game3/pokedex.lua")
if frlg then
  local patched = DexPatch.patchFrlgSource(frlg)
  T.check(patched ~= nil, "the FRLG Pokedex source has the lines the patch expects")
  if patched then
    T.check(loadstring(patched, "@frlg") ~= nil, "the patched FRLG source compiles")
    T.check(patched:find("local Pokedex = require", 1, true) ~= nil, "it runs on the live module table")
    T.check(select(2, patched:gsub("if false then", "")) == 2, "and turns off the two list-switching branches")
  end
end
T.eq(DexPatch.patchFrlgSource("local Pokedex = { isMenu = true }"), nil, "one pattern alone is not enough")
T.eq(DexPatch.patchFrlgSource(nil), nil, "nothing to patch is fine")
local frlgLive = { show = function() return "old" end }
local rebuilt = DexPatch.installFrlg({ require = function() return frlgLive end,
  read = function() return "return 1" end, load = load, log = log })
T.eq(rebuilt, false, "an unexpected FRLG source leaves the screen alone")
T.eq(frlgLive.show(), "old", "and untouched")

-- end to end, in the mod's sandbox: the mod reads the engine source through the game's file
-- reader (stubbed here with the real file) when the game is ready, on an Emerald cart
local okH, H = pcall(dofile, here .. "/_gen3.lua")
local okD, data = false, nil
if okH then okD, data = pcall(H.gen3Data, "emerald") end
if okD and data then
  rawset(_G, "love", { filesystem = { read = slurp } })
  local engine = require("src.ui.game3.rse.pokedex")
  local before = engine.show
  local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
  T.eq(#run.errors, 0, "the mod loads clean (" .. tostring(run.errors[1]) .. ")")
  run.loader.events:emit("game.ready", {})
  T.check(engine.show ~= before and engine.__nationalDexGen3 == true, "on game.ready the live RSE Pokedex module is the patched copy")
  -- Register Owned survives the patch: opening the screen still registers the party first
  local Dex = require("src.core.game3.dex")
  local session = { dex = Dex.new(), party = { { species = 25 } } }
  pcall(engine.show, session.dex, { session = session })   -- the screen itself needs the cart's art
  T.check(Dex.isCaught(session.dex, 25), "opening the patched Pokedex registers the party (Register Owned)")
  run.release()
  rawset(_G, "love", nil)
else
  print("(Emerald not imported: skipping the end-to-end check)")
end

T.finish("national_dex_gen3 Pokedex patch")
