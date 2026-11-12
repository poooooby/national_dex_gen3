-- Prints, as JSON, what tools/build_gen12.py needs from an imported Gen 1 or Gen 2 cart:
-- its moves (number, id, name, type, power, accuracy, pp, effect and, on Gen 2, the effect id
-- and chance), its species (dex, id, types), each species' party icon, and the cart's
-- high-critical move list (Gen 2 keeps it in the type chart's battle rules).
--
--   luajit tools/gen12_cart.lua <gen1recomp>/<version>/data/generated
--   luajit tools/gen12_cart.lua --lua <file.lua>     (any data file that returns a table, as JSON)
--
-- Only the build tool runs this; the mod never reads a cart's files.

local dir = assert(arg[1], "usage: luajit tools/gen12_cart.lua <cart>/data/generated")

local function load(name)
  local chunk = loadfile(dir .. "/" .. name .. ".lua")
  if not chunk then return nil end
  local ok, value = pcall(chunk)
  return ok and value or nil
end

local function json(v, out)
  local t = type(v)
  if t == "table" then
    if #v > 0 or next(v) == nil then
      out[#out + 1] = "["
      for i, x in ipairs(v) do
        if i > 1 then out[#out + 1] = "," end
        json(x, out)
      end
      out[#out + 1] = "]"
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = tostring(k) end
      table.sort(keys)
      out[#out + 1] = "{"
      for i, k in ipairs(keys) do
        if i > 1 then out[#out + 1] = "," end
        json(k, out)
        out[#out + 1] = ":"
        local x = v[k]
        if x == nil then x = v[tonumber(k)] end
        json(x, out)
      end
      out[#out + 1] = "}"
    end
  elseif t == "string" then
    out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c)
      return string.format("\\u%04x", c:byte())
    end) .. '"'
  elseif t == "number" or t == "boolean" then
    out[#out + 1] = tostring(v)
  else
    out[#out + 1] = "null"
  end
  return out
end

if dir == "--lua" then
  io.write(table.concat(json(assert(dofile(assert(arg[2], "--lua needs a file"))), {})), "\n")
  return
end

local result = { moves = {}, species = {}, icons = {}, highCrit = {} }

for id, m in pairs(load("moves") or {}) do
  if type(m) == "table" and m.effect and m.index then
    result.moves[#result.moves + 1] = {
      n = m.index, id = id, name = m.name, type = m.type, power = m.power,
      accuracy = m.accuracy, pp = m.pp, effect = m.effect,
      effectId = m.effectId, effectChance = m.effectChance,
    }
  end
end
table.sort(result.moves, function(a, b) return a.n < b.n end)

for id, s in pairs(load("pokemon") or {}) do
  if type(s) == "table" and s.dex and s.types then
    result.species[#result.species + 1] = { dex = s.dex, id = id, types = s.types }
  end
end
table.sort(result.species, function(a, b) return a.dex < b.dex end)

local icons = load("icons") or {}
if icons.byDex then                       -- Gen 1: an icon kind per dex number
  for dex, kind in pairs(icons.byDex) do result.icons[tostring(dex)] = kind end
elseif icons.species then                 -- Gen 2: an ICON_ sheet per species id
  local byId = {}
  for _, s in ipairs(result.species) do byId[s.id] = s.dex end
  for id, kind in pairs(icons.species) do
    if byId[id] then result.icons[tostring(byId[id])] = kind end
  end
end

local chart = load("type_chart") or {}
local rules = chart.battleRules or {}
for id in pairs(rules.highCriticalMoves or {}) do result.highCrit[#result.highCrit + 1] = id end
table.sort(result.highCrit)

io.write(table.concat(json(result, {})), "\n")
