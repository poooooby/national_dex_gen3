-- Standalone: luajit mods/national_dex_gen3/tests/gen3_fork_test.lua [game] [--write]
-- (from the gen1recomp root; needs the Gen 3 cart imported, FireRed by default).
--
-- The Gen 1/2 path (src/gen12/) forks off main.lua before anything Gen 3 loads, and Gen 3 must
-- not notice: this loads the mod on a Gen 3 cart as register_test does, fires game.ready, and
-- compares a fingerprint of everything a Gen 3 game gets from it (the exports, the species
-- listings, every species/form slot's rows in the live species tables, the National Dex bound)
-- with the one recorded from main before the fork (tests/fixtures/gen3_fork_<game>.lua).
-- --write records a new fingerprint; only do that on a tree whose Gen 3 behaviour is known good.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")

local game, write = "firered", false
for i = 1, #arg do
  if arg[i] == "--write" then write = true else game = arg[i] end
end

local data = H.gen3Data(game)
H.useCart(game)
data.gen3Moves = require("src.core.game3.battle.moves")
local P = data.gen3Pokemon
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
pcall(require("src.mods.Gen3Compat").applyMerged, { mods = run.loader, data = data })
T.eq(#run.errors, 0, "loads clean on " .. game .. " (" .. tostring(run.errors[1]) .. ")")
local mod = run.mods.national_dex_gen3
T.check(mod and mod.state == "loaded", "loaded on " .. game)
local api = run.loader.exports.national_dex_gen3

-- deterministic text for any value: keys sorted by type then value, functions by name only
local function ser(v, out)
  local t = type(v)
  if t == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
      local ta, tb = type(a), type(b)
      if ta ~= tb then return ta < tb end
      if ta == "number" or ta == "string" then return a < b end
      return tostring(a) < tostring(b)
    end)
    out[#out + 1] = "{"
    for _, k in ipairs(keys) do
      out[#out + 1] = tostring(k) .. "="
      ser(v[k], out)
      out[#out + 1] = ","
    end
    out[#out + 1] = "}"
  elseif t == "function" then
    out[#out + 1] = "fn"
  else
    out[#out + 1] = t:sub(1, 1) .. tostring(v)
  end
  return out
end

local bit = require("bit")
local function fnv(s)
  local h = 2166136261
  for i = 1, #s do
    h = bit.bxor(h, s:byte(i))
    h = bit.tobit(h * 16777619)
  end
  return bit.tohex(h)
end
local function hash(v) return fnv(table.concat(ser(v, {}))) end

-- the rows of every slot this mod owns (species 451-1089, forms 1090+)
local function slots(field)
  local out = {}
  local t = P[field] or {}
  for slot = 451, 1300 do out[slot] = t[slot] end
  return out
end

local function fingerprint(stage)
  local keys = {}
  for k, v in pairs(api) do keys[k] = type(v) end
  local fp = {
    exports = hash(keys),
    species = hash(api.listSpecies()),
    forms = hash(api.listForms and api.listForms() or {}),
    names = hash(slots("_names")),
    types = hash(slots("_types")),
    stats = hash(slots("_stats")),
    meta = hash(slots("_speciesMeta")),
    abilities = hash(slots("_abilities")),
    learnsets = hash(slots("_learnsets")),
    eggMoves = hash(slots("_eggMoves")),
    evolutions = hash(slots("_evolutions")),
    national = hash(P._national or {}),
  }
  local evo = {}
  for _, id in ipairs({ "TURTWIG", "RHYDON", "ROCKRUFF", "EEVEE", "LYCANROC_MIDNIGHT" }) do
    evo[id] = api.evolutionsOf(id)
  end
  fp.evolutionsOf = hash(evo)
  if stage == "ready" then
    fp.nationalMax = tostring(require("src.core.game3.dex").NATIONAL_MAX)
  end
  return fp
end

local result = { load = fingerprint("load") }
run.loader.events:emit("game.ready", {})
result.ready = fingerprint("ready")

local path = H.modRoot() .. "/tests/fixtures/gen3_fork_" .. game .. ".lua"
if write then
  local lines = { "-- written by tests/gen3_fork_test.lua --write; the Gen 3 fingerprint before the Gen 1/2 fork",
    "return {" }
  for _, stage in ipairs({ "load", "ready" }) do
    lines[#lines + 1] = ("  %s = {"):format(stage)
    local names = {}
    for k in pairs(result[stage]) do names[#names + 1] = k end
    table.sort(names)
    for _, k in ipairs(names) do
      lines[#lines + 1] = ("    %s = %q,"):format(k, result[stage][k])
    end
    lines[#lines + 1] = "  },"
  end
  lines[#lines + 1] = "}"
  local f = assert(io.open(path, "wb"))
  f:write(table.concat(lines, "\n"), "\n")
  f:close()
  print("wrote " .. path)
else
  local chunk = loadfile(path)
  T.check(chunk ~= nil, "a recorded fingerprint exists for " .. game .. " (run with --write on main)")
  if chunk then
    local want = chunk()
    for _, stage in ipairs({ "load", "ready" }) do
      for k, v in pairs(want[stage]) do
        T.eq(result[stage][k], v, ("%s: %s unchanged"):format(stage, k))
      end
    end
  end
end

run.release()
T.finish("national_dex_gen3 Gen 3 unchanged by the Gen 1/2 fork (" .. game .. ")")
