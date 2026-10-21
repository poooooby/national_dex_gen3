-- Real moves newer than Gen 3 (data/moves.lua, tools/build_moves.py): each one works like a
-- Gen 3 move (it runs on one of the cart's own effect ids), with its own name, type, power,
-- accuracy, PP, priority, target, flags, summary text and contest data, at an index from 355.
--
-- The engine's registry write (src/mods/Schemas.lua moveWrite, engine 0.3.95+) puts each move
-- where the battle reads it -- its row in Moves._rom and the species module's mirror, its name in
-- the move names and the battle's name index (BY_NUM / _numByName), at its number -- and writes
-- them again after every reload; learnsets and egg moves name it by number. What it does not
-- cover, done here:
--   * "X used MOVE!" treats a number past the cart's last move as a typed move
--     (BattleText.MOVES_COUNT)
--   * the summary text (SummaryData.moveDescription, keyed by the cart's names): FireRed /
--     LeafGreen's 4-line box or Ruby/Sapphire/Emerald's 2-line one
--   * Ruby/Sapphire/Emerald's contest data (the summary's contest page, the move relearner and
--     contests index it by move and fail on a missing row): a row each, in the cached tables
-- FAIRY moves are registered FAIRY: src/types.lua registers the type in the engine's type_chart.

local NewMoves = {}

-- payload rows -> the registered ones (an id another mod already has is skipped)
function NewMoves.register(mod, payload)
  local registered, failed, firstError = {}, 0, nil
  for _, r in ipairs(payload or {}) do
    local ok, err = pcall(function()
      mod.content.moves:register(r.id, {
        id = r.id, name = r.name, index = r.index,
        type = r.type,
        power = r.power, accuracy = r.accuracy, pp = r.pp, effect = r.effect,
        secondaryChance = r.secondaryChance, target = r.target, priority = r.priority, flags = r.flags,
      })
    end)
    if ok then
      registered[#registered + 1] = r
    else
      failed = failed + 1
      firstError = firstError or tostring(err)
    end
  end
  if mod.log then
    mod.log:info("registered %d move(s) newer than Gen 3", #registered)
    if failed > 0 then
      mod.log:warn("%d move(s) not registered (another mod has the id?): %s", failed, firstError)
    end
  end
  return registered
end

-- the ids of the registered moves that are Fairy (src/types.lua retypes them)
function NewMoves.fairy(registered)
  local out = {}
  for _, r in ipairs(registered or {}) do
    if r.type == "FAIRY" then out[#out + 1] = r.id end
  end
  return out
end

local function const(name)
  return (tostring(name):upper():gsub("%s+", "_"):gsub("-", "_"))
end

-- opts: { moves = registered rows, require, log, family = "frlg"|"rse" }
function NewMoves.install(opts)
  local require = opts.require
  local byIndex, byConst = {}, {}
  for _, r in ipairs(opts.moves or {}) do
    byIndex[r.index] = r
    byConst[r.id] = r.index
    byConst[const(r.name)] = byConst[const(r.name)] or r.index
  end
  NewMoves._byIndex = byIndex                   -- a later install replaces what the wraps read

  local okB, BattleText = pcall(require, "src.core.game3.battle.battle_text")
  if okB and type(BattleText) == "table" and (tonumber(BattleText.MOVES_COUNT) or 0) < 1024 then
    BattleText.MOVES_COUNT = 1024
  end

  local okS, SummaryData = pcall(require, "src.core.game3.summary_data")
  if okS and type(SummaryData) == "table" and type(SummaryData.moveDescription) == "function"
      and not SummaryData.__nationalDexMoves then
    SummaryData.__nationalDexMoves = true
    local orig = SummaryData.moveDescription
    SummaryData.moveDescription = function(moveId, moveName, ...)
      local r = NewMoves._byIndex[tonumber(moveId) or -1]
      if r then return (opts.family == "frlg" and r.frlg or r.rse) or r.frlg or "---" end
      return orig(moveId, moveName, ...)
    end
  end

  -- contest rows (Ruby/Sapphire/Emerald), in whichever cached table is handed out
  local function addContest(t)
    if type(t) ~= "table" or type(t.moves) ~= "table" then return t end
    for index, r in pairs(NewMoves._byIndex) do
      if t.moves[index] == nil then
        local c = r.contest or {}
        t.moves[index] = { category = c.category or 0, effect = c.effect or 0,
                           comboStarterId = 0, comboMoves = { 0, 0, 0, 0 } }
      end
    end
    return t
  end
  local okK, Kit = pcall(require, "src.ui.game3.rse.scene_kit")
  if okK and type(Kit) == "table" and type(Kit.loadLua) == "function" and not Kit.__nationalDexMoves then
    Kit.__nationalDexMoves = true
    local loadLua = Kit.loadLua
    Kit.loadLua = function(path, ...)
      local t = loadLua(path, ...)
      if type(path) == "string" and path:find("contest_moves%.lua$") then addContest(t) end
      return t
    end
  end
  local okC, Contest = pcall(require, "src.core.game3.rse.contest")
  if okC and type(Contest) == "table" and type(Contest.data) == "function" and not Contest.__nationalDexMoves then
    Contest.__nationalDexMoves = true
    local data = Contest.data
    Contest.data = function(...)
      local d = data(...)
      if type(d) == "table" then addContest(d.moves and d or nil) end
      return d
    end
  end

  return true
end

return NewMoves
