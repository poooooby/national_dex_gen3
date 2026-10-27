-- Standalone: luajit mods/national_dex_gen3/tests/dynamax_test.lua (from anywhere: paths are the
-- mod's, from this file's place). Dynamax (src/dynamax.lua) over
-- a stand-in engine: the marks on a Pokemon, Dynamax Candy, Max Soup (Max Mushrooms, Max Honey),
-- the species rules (no Dynamax for Zacian / Zamazenta / Eternatus, G-Max forms, regional forms),
-- the HP multiplier, a raid catch's starting level, and the item indices clear of the others.

local root = (arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/.."
local function read(path)
  local f = assert(io.open(root .. "/" .. path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end
local function loadFile(path) return assert(loadstring(read(path), "@" .. path))() end

local passed, failed = 0, 0
local function check(ok, what)
  if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. what) end
end

-- species slot = National Dex number, but forms: 1052 Galarian Meowth (52), 1100 Rapid Strike Urshifu (892)
local NAT = { [1052] = 52, [1100] = 892 }
local FORM = { [1052] = "MEOWTH_GALAR", [1100] = "URSHIFU_RAPID_STRIKE" }
local Pokemon = {
  speciesOf = function(mon) return mon.species end,
  national = function(s) return NAT[s] or s end,
  isEgg = function(mon) return mon.isEgg == true end,
  displayMonName = function(mon) return mon.name or "MON" end,
}
local bagCounts = {}
local Bag = {
  get = function(_, id) return bagCounts[id] or 0 end,
  remove = function(_, id, n) bagCounts[id] = (bagCounts[id] or 0) - n; return true end,
}
local fakeRequire = function(name)
  if name == "src.core.game3.pokemon" then return Pokemon end
  if name == "src.core.game3.bag" then return Bag end
  error("no " .. name)
end
local D = loadFile("data/dynamax.lua")
local Dx = loadstring(read("src/dynamax.lua"), "@src/dynamax.lua")()({}, { data = D, require = fakeRequire,
  formIdOf = function(slot) return FORM[slot] end })

local function mon(species, extra)
  local m = { species = species, name = "MON" }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end

-- the marks
local m = mon(6)
check(Dx.level(m) == 0 and not Dx.hasFactor(m) and m.extra == nil, "no marks: level 0, no factor, nothing written")
Dx.setLevel(m, 4); Dx.setFactor(m, true)
check(Dx.level(m) == 4 and Dx.hasFactor(m), "set")
check(m.extra.national_dex_gen3.dynamaxLevel == 4 and m.extra.national_dex_gen3.gmaxFactor == true, "kept in the mod bag")
check(Dx.setLevel(m, 99) == 10 and Dx.setLevel(m, -3) == 0, "the level clamped 0..10")
Dx.setFactor(m, false)
check(not Dx.hasFactor(m) and m.extra.national_dex_gen3.gmaxFactor == nil, "the factor cleared")

-- species
check(Dx.canDynamax(mon(6)) and not Dx.canDynamax(mon(888)) and not Dx.canDynamax(mon(889)) and not Dx.canDynamax(mon(890)),
  "Zacian, Zamazenta, Eternatus never Dynamax")
check(Dx.gmaxMoveOf(mon(6)) == "WILDFIRE" and Dx.gmaxMoveOf(mon(892)) == "ONE_BLOW", "G-Max Moves")
check(Dx.gmaxMoveOf(mon(1100)) == "RAPID_FLOW", "Rapid Strike Urshifu: Rapid Flow")
check(Dx.gmaxMoveOf(mon(52)) == "GOLD_RUSH" and Dx.gmaxMoveOf(mon(1052)) == nil, "Galarian Meowth has no G-Max form")
check(Dx.gmaxMoveOf(mon(10)) == nil, "Caterpie has none")
local c = mon(6); Dx.setFactor(c, true)
local b = mon(10); Dx.setFactor(b, true)
check(Dx.canGigantamax(c) and not Dx.canGigantamax(b) and not Dx.canGigantamax(mon(6)), "Gigantamax: the factor and a form")
local n = 0
for _ in pairs(D.GMAX) do n = n + 1 end
check(n == 32, "32 species with a Gigantamax form (" .. n .. ")")

-- HP and a raid catch's level
check(Dx.hpMult(0) == 1.5 and math.abs(Dx.hpMult(10) - 2.0) < 1e-9 and math.abs(Dx.hpMult(4) - 1.7) < 1e-9, "HP x1.5 .. x2")
local RANGE = { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 5 }, { 6, 8 } }
for stars = 1, 5 do
  local seen = {}
  for i = 1, 300 do
    local s = i
    local lv = Dx.raidStartLevel(stars, function(lo, hi) s = (s * 1103515245 + 12345) % 2147483648; return lo + s % (hi - lo + 1) end)
    seen[lv] = true
    check(lv >= RANGE[stars][1] and lv <= RANGE[stars][2], stars .. "-star catch level in range")
  end
  local all = true
  for lv = RANGE[stars][1], RANGE[stars][2] do all = all and seen[lv] end
  check(all, stars .. "-star: every level of the range comes up")
end

-- Dynamax Candy
local cm = mon(6)
local kind, text = Dx.useCandy(cm)
check(kind == "consumed" and Dx.level(cm) == 1 and text[1]:find("rose to 1"), "a candy: +1")
Dx.setLevel(cm, 10)
check(Dx.useCandy(cm) == "failed" and Dx.level(cm) == 10, "at 10: no effect")
check(Dx.useCandy(mon(888)) == "failed", "Zacian: no effect")
check(Dx.useCandy(mon(6, { isEgg = true })) == "failed", "an egg: no effect")

-- Max Soup
local function count(id) return bagCounts[id] or 0 end
local function take(id, k) bagCounts[id] = (bagCounts[id] or 0) - k end
local ids = Dx.ids
local sm = mon(6)
bagCounts = { [ids.MAX_MUSHROOMS] = 2 }
check(Dx.useSoup(sm, count, take) == "failed" and count(ids.MAX_MUSHROOMS) == 2, "two Max Mushrooms: not enough")
bagCounts[ids.MAX_MUSHROOMS] = 3
check(Dx.useSoup(sm, count, take) == "consumed" and Dx.hasFactor(sm) and count(ids.MAX_MUSHROOMS) == 1,
  "three: the factor (two taken here, the one used by the Bag)")
bagCounts[ids.MAX_MUSHROOMS] = 3
local _, t2 = Dx.useSoup(sm, count, take)
check(not Dx.hasFactor(sm) and t2[1]:find("lost"), "again: the factor taken away")
bagCounts[ids.MAX_MUSHROOMS] = 3
check(Dx.useSoup(mon(809), count, take) == "failed", "Melmetal: no Max Soup")
check(Dx.useSoup(mon(10), count, take) == "failed", "no G-Max form: no Max Soup")
check(Dx.useSoup(mon(1052), count, take) == "failed", "Galarian Meowth: no Max Soup")
local u = mon(892)
check(Dx.useSoup(u, count, take) == "failed" and not Dx.hasFactor(u), "Urshifu without Max Honey: refused")
bagCounts[ids.MAX_HONEY] = 1
check(Dx.useSoup(u, count, take) == "consumed" and Dx.hasFactor(u) and count(ids.MAX_HONEY) == 0, "with Max Honey")

-- the item indices: clear of the evolution items, the candies and the TMs
local used = {}
for line in read("data/items.lua"):gmatch("index%s*=%s*(%d+)") do used[tonumber(line)] = "items" end
for line in read("data/tms.lua"):gmatch("index%s*=%s*(%d+)") do used[tonumber(line)] = "tms" end
for i = 950, 954 do used[i] = "candies" end
used[960] = "the tm_case test's stub"
for _, it in ipairs(Dx.ITEMS) do
  check(not used[it.index], it.id .. " at " .. it.index .. " is free (" .. tostring(used[it.index]) .. ")")
  used[it.index] = it.id
  for line in (it.description .. "\n"):gmatch("([^\n]*)\n") do
    check(#line:gsub("é", "e") <= 19, it.id .. "'s description line fits 19: " .. line)
  end
end

print(("%d/%d checks passed  (national_dex_gen3 dynamax)"):format(passed, passed + failed))
if failed > 0 then os.exit(1) end
