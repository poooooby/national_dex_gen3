-- Standalone: luajit mods/national_dex_gen3/tests/options_row_test.lua [firered|emerald|red|gold ...]
-- (from the gen1recomp root; runs on firered, red and gold when none is named).
--
-- The WOOBLEDEX row (src/options_row.lua): the ui.options.rows hook adds it once to the game's own
-- OPTIONS list, it shows how many settings there are, and A opens the mod manager straight on this
-- mod's settings page (this game's own list of settings), where B leads back out to OPTIONS.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local here = (arg[0]:gsub("\\", "/"):match("^(.*)/") or ".")
local MOD = "national_dex_gen3"

local function versions()
  local out = {}
  for i = 1, #arg do
    if ({ firered = 1, leafgreen = 1, emerald = 1, ruby = 1, sapphire = 1, red = 1, blue = 1, yellow = 1,
      gold = 1, silver = 1, crystal = 1 })[arg[i]] then out[#out + 1] = arg[i] end
  end
  if #out == 0 then out = { "firered", "red", "gold" } end
  return out
end

-- the hooked OPTIONS list (rows: the game's own, as the menu hands them over)
local function hooked(game, rows)
  local Runtime = require("src.mods.Runtime")
  return Runtime.call("ui.options.rows", function(_, r) return r end, game, rows)
end

local function find(rows, id)
  local n, hit = 0, nil
  for _, r in ipairs(rows) do
    if r.id == id then n, hit = n + 1, r end
  end
  return hit, n
end

-- the keys of a schema (key) or of the manager's rows (id = the key; its own __reset row left out)
local function keysOf(list)
  local out = {}
  for _, r in ipairs(list or {}) do
    local k = type(r) == "table" and (r.key or r.id) or nil
    if k and k:sub(1, 2) ~= "__" then out[#out + 1] = k end
  end
  table.sort(out)
  return table.concat(out, ",")
end

local function checkRows(version, game, schema)
  local rows = hooked(game, { { id = "mods", label = "MODS" } })
  local row, n = find(rows, MOD .. ":options")
  T.eq(n, 1, version .. ": one WOOBLEDEX row")
  T.eq(row and row.label, "WOOBLEDEX", version .. ": labelled WOOBLEDEX")
  T.eq(rows[1] and rows[1].id, "mods", version .. ": the game's own rows stay first")
  T.eq(row and row.value(game), #schema .. " OPTIONS", version .. ": shows the number of settings")
  T.check(row and type(row.activate) == "function", version .. ": A opens it")
  return row
end

local function checkPage(version, m, schema)
  T.check(m ~= nil, version .. ": the mod manager opened")
  if not m then return end
  T.eq(m.screen, "options", version .. ": on a settings page")
  T.eq(keysOf(m.optionRows), keysOf(schema), version .. ": WoobleDex's page, this game's settings")
  T.eq(#(m.backStack or {}), 0, version .. ": B leads straight out")
end

-- ------- Gen 3
local function gen3(version)
  local H = dofile(here .. "/_gen3.lua")
  local data = H.gen3Data(version)
  H.useCart(version)
  data.gen3Moves = require("src.core.game3.battle.moves")
  local run = T.sdk.loadMods({ "mods/" .. MOD }, { data = data, generation = 3 })
  T.eq(#run.errors, 0, version .. ": loads clean (" .. tostring(run.errors[1]) .. ")")
  local schema = dofile(here .. "/../options.lua")
  local game = { data = data, mods = run.loader, save = { options = {} }, options = {} }
  run.loader.game = game
  local row = checkRows(version, game, schema)
  if not row then return end
  local MM = require("src.ui.game3.mod_manager")
  row.activate(game)
  T.check(MM.open, version .. ": the Gen 3 mod manager is open")
  checkPage(version, MM._mgr, schema)
  if MM._mgr then MM._mgr:goBack() end
  T.check(not MM.open, version .. ": B closes the manager, back on OPTIONS")
  if MM.open then MM.close() end
end

-- ------- Gen 1 / Gen 2
local function gen12(version)
  local H = dofile(here .. "/_gen12.lua")
  local run = H.load(version)
  T.eq(#run.errors, 0, version .. ": loads clean (" .. tostring(run.errors[1]) .. ")")
  local schema = dofile(here .. "/../src/gen12/options.lua").forGeneration(H.GENERATION[version])
  -- the engine's own stack: push calls the screen's enter, as in a game
  local StateStack = require("src.core.StateStack")
  local stack = setmetatable({}, { __index = StateStack })
  stack:init()
  local items = stack.states
  local game = { data = run.data, mods = run.loader, save = { options = {} }, stack = stack }
  run.loader.game = game
  local row = checkRows(version, game, schema)
  if row then
    row.activate(game)
    T.eq(#items, 1, version .. ": the mod manager pushed")
    local m = items[1]
    checkPage(version, m, schema)
    if m then m:goBack() end
    T.eq(#items, 0, version .. ": B pops the manager, back on OPTIONS")
  end
  run.release()
end

for _, v in ipairs(versions()) do
  if ({ red = 1, blue = 1, yellow = 1, gold = 1, silver = 1, crystal = 1 })[v] then gen12(v) else gen3(v) end
end
T.finish("national_dex_gen3 options row")
