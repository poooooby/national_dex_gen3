-- Test helper (the "_" prefix keeps tests/tier_runner.lua from running it).
-- Builds a FireRed dataset headlessly from the imported cart under
-- firered/data/generated/gba, shaped the way Game3 exposes it to mods
-- (src/core/Game3.lua _exposeModData). The species tables live on the real
-- src.core.game3.pokemon module, as in the game, so repairs made through it
-- are visible to the registry and the tests alike.
--
-- Suites run from the gen1recomp root: luajit mods/<id>/tests/<name>_test.lua

local H = {}

local ROOT = "firered/data/generated/gba/"

local function load(path) return dofile(ROOT .. path) end

function H.modRoot()
  local script = ((arg and arg[0]) or ""):gsub("\\", "/")
  return script:match("^(.*)/tests/[^/]+$") or "mods/national_dex_gen3"
end

function H.module(name)
  local chunk = assert(loadfile(H.modRoot() .. "/" .. name))
  return chunk()
end

-- data.maps: one record per map header (id, mapType, region section)
local function maps()
  local Json = require("src.link.Json")
  local MapCatalog = require("src.import.gba.map_catalog")
  local out = {}
  local pipe = io.popen('ls "' .. ROOT .. 'map_tree/maps"')
  for dir in pipe:lines() do
    local f = io.open(ROOT .. "map_tree/maps/" .. dir .. "/header.json")
    if f then
      local ok, h = pcall(Json.decode, f:read("*a"))
      f:close()
      if ok and type(h) == "table" then
        local id = MapCatalog.mapIdFor(h.group, h.num) or MapCatalog.pretToEngine(h.id)
        if id then
          out[id] = { id = id, name = id, mapType = h.mapType,
                      regionMapSectionId = h.regionMapSectionId,
                      width = h.width, height = h.height }
        end
      end
    end
  end
  pipe:close()
  return out
end

function H.gen3Data()
  local P = require("src.core.game3.pokemon")
  P._names = load("pokemon/names.lua")
  P._types = load("pokemon/types.lua")
  P._stats = load("pokemon/stats.lua")
  P._speciesMeta = load("pokemon/meta.lua")
  P._abilities = load("pokemon/abilities.lua")
  P._abilityNames = load("pokemon/ability_names.lua")
  P._learnsets = load("pokemon/learnsets.lua")
  P._eggMoves = load("pokemon/egg_moves.lua")
  P._evolutions = load("pokemon/evolutions.lua")
  P._dex = load("pokemon/dex.lua")
  P._moveNames = load("pokemon/move_names.lua")
  P._national = load("pokemon/national.lua")
  P._tmhm = load("pokemon/tmhm.lua")
  -- FireRed's move tutors live on MoveLearn, loaded lazily from the cache
  local ML = require("src.core.game3.move_learn")
  ML._tutorPack, ML._tutorLoaded = load("pokemon/tutor.lua"), true
  P._byName = {}
  for id, name in pairs(P._names) do
    if type(id) == "number" and type(name) == "string" then
      P._byName[(name:upper():gsub("[%.']", ""):gsub("[%s%-]+", "_"))] = id
    end
  end
  return {
    maps = maps(), tilesets = {},
    gen3Pokemon = P,
    gen3Moves = { _rom = load("pokemon/battle_moves.lua").moves },
    gen3Items = { _byId = load("items/pack.lua").items },
    gen3Encounters = load("encounters.lua"),
  }
end

return H
