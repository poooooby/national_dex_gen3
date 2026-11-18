-- A WOOBLEDEX row on the top level of the game's own OPTIONS menu, on every game (the
-- ui.options.rows hook, which Red / Blue / Yellow, Gold / Silver / Crystal and the three Gen 3
-- option screens all raise). A opens the mod manager straight on this mod's settings page (the one
-- OPTIONS > MODS > WoobleDex reaches, with each setting's description); B from there goes back to
-- OPTIONS. The settings are stored where the manager stores them, so the two can never disagree.
--
-- There is no API for "open this mod's page": it goes through the manager's own steps
-- (ManagerState:openOptions over the record ManagerState:refresh listed). Anything missing, and the
-- manager just opens at its list, as OPTIONS > MODS does.
local Row = {}

Row.ID = "national_dex_gen3:options"
Row.LABEL = "WOOBLEDEX"

-- the open manager (a ManagerState) for this game, or nil
function Row.openManager(game, generation)
  if type(game) ~= "table" then return nil end
  if generation == 3 then
    local MM = require("src.ui.game3.mod_manager")
    MM.show({ game = game })
    return MM._mgr
  end
  return require("src.ui.Screens").push(game, "ManagerState")
end

-- moves an open manager onto modId's settings page, B leading straight out of the manager;
-- true when it got there
function Row.showPage(m, modId)
  if type(m) ~= "table" or type(m.openOptions) ~= "function" then return false end
  if type(m.byId) ~= "table" and type(m.refresh) == "function" then m:refresh() end
  local rec = type(m.byId) == "table" and m.byId[modId] or nil
  if not rec then return false end
  m:openOptions(rec)
  if m.screen ~= "options" then return false end
  m.backStack = {}
  return true
end

-- opts: { generation = 1 | 2 | 3, count = how many settings the page lists }
function Row.install(mod, opts)
  opts = opts or {}
  local generation = opts.generation or 3
  local modId = mod.id or "national_dex_gen3"
  local value = string.format("%d OPTIONS", tonumber(opts.count) or 0)
  local function activate(game)
    local okM, m = pcall(Row.openManager, game, generation)
    if not okM then
      mod.log:warn("WOOBLEDEX options row: the mod manager did not open (%s)", tostring(m))
      return
    end
    local okP, err = pcall(Row.showPage, m, modId)
    if not okP then mod.log:warn("WOOBLEDEX options row: settings page not opened (%s)", tostring(err)) end
  end
  local row = {
    id = Row.ID, label = Row.LABEL,
    value = function() return value end,
    activate = activate,
  }
  mod.hooks:wrap("ui.options.rows", function(nextFn, game, rows)
    local out = nextFn(game, rows)
    if type(out) ~= "table" then return out end
    for _, r in ipairs(out) do
      if type(r) == "table" and r.id == Row.ID then return out end
    end
    out[#out + 1] = row
    return out
  end)
  return row
end

return Row
