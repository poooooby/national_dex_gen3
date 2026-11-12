-- Test helper for the Gen 1 / Gen 2 path (the "_" prefix keeps tests/tier_runner.lua from running it).
-- Builds a Red/Blue/Yellow or Gold/Silver/Crystal dataset headlessly from an imported cart under
-- <version>/data/generated, shaped the way the game hands it to mods:
--   Gen 1: every generated module under its own name, then Data.seedDefaults (as Data:load does);
--   Gen 2: the keys src/core/Game2.lua builds before mods load (pokemon, items, moves, type_chart,
--          gen2Pokedex, gen2Constants, ...).
-- H.load(version, extra) loads the mod (plus any extra mod paths) on that cart.
--
-- Suites run from the gen1recomp root: luajit mods/national_dex_gen3/tests/<name>_test.lua [version]

local H = {}

H.GENERATION = { red = 1, blue = 1, yellow = 1, gold = 2, silver = 2, crystal = 2 }
-- what a suite runs on when it is given no version: one cart of each layout
H.DEFAULT_VERSIONS = { "red", "yellow", "gold", "crystal" }

function H.modRoot()
  local script = ((arg and arg[0]) or ""):gsub("\\", "/")
  return script:match("^(.*)/tests/[^/]+$") or "mods/national_dex_gen3"
end

function H.module(name)
  local chunk = assert(loadfile(H.modRoot() .. "/" .. name))
  return chunk()
end

-- the versions a suite should run: the ones named on its command line, else the defaults
function H.versions()
  local out = {}
  for i = 1, #(arg or {}) do
    if H.GENERATION[arg[i]] then out[#out + 1] = arg[i] end
  end
  if #out == 0 then
    for _, v in ipairs(H.DEFAULT_VERSIONS) do out[#out + 1] = v end
  end
  return out
end

local function generated(version, name)
  local chunk = loadfile(version .. "/data/generated/" .. name .. ".lua")
  if not chunk then return nil end
  local ok, value = pcall(chunk)
  return ok and value or nil
end

local function listModules(version)
  local names = {}
  local pipe = io.popen('ls "' .. version .. '/data/generated"')
  for file in pipe:lines() do
    local name = file:match("^(.-)%.lua$")
    if name then names[#names + 1] = name end
  end
  pipe:close()
  return names
end

function H.gen1Data(version)
  local Data = require("src.core.Data")
  local data = {}
  for _, name in ipairs(listModules(version)) do data[name] = generated(version, name) end
  Data.seedDefaults(data, version)
  return data
end

local GEN2_KEYS = {
  pokemon = "pokemon", items = "items", moves = "moves", type_chart = "type_chart",
  audio = "audio", gen2Pokedex = "pokedex", gen2Constants = "constants",
  gen2Encounters = "encounters", gen2Maps = "maps", gen2Landmarks = "landmarks",
  gen2Marts = "marts", gen2Icons = "icons", gen2Trainers = "trainers",
  gen2BattleAnims = "battle_anims", gen2Text = "text",
}

function H.gen2Data(version)
  local data = {}
  for key, name in pairs(GEN2_KEYS) do data[key] = generated(version, name) end
  data.audio = data.audio or {}
  return data
end

function H.data(version)
  assert(H.GENERATION[version], "not a Gen 1/2 version: " .. tostring(version))
  require("src.core.GameVersion").set(version)
  if H.GENERATION[version] == 1 then return H.gen1Data(version) end
  return H.gen2Data(version)
end

-- Loads the mod on <version>; extra = more mod paths to load beside it (e.g. a stub national_dex).
-- Returns the sdk run (run.loader, run.data, run.mods, run.errors, run.release) and the mod's exports.
function H.load(version, extra)
  local T = require("tests.modkit")
  local data = H.data(version)
  local paths = { H.modRoot() }
  for _, p in ipairs(extra or {}) do paths[#paths + 1] = p end
  local run = T.sdk.loadMods(paths, { data = data, generation = H.GENERATION[version] })
  return run, run.loader.exports.national_dex_gen3
end

return H
