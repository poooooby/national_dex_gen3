-- Real moves newer than Gen 3 (data/moves.lua, tools/build_moves.py): each one works like a
-- Gen 3 move (it runs on one of the cart's own effect ids), with its own name, type, power,
-- accuracy, PP, priority, target, flags, summary text and contest data, at an index from 355.
--
-- The registry already writes a move row where the battle reads it (Moves._rom, the
-- species module's mirror and move names; src/mods/Schemas.lua moveWrite). What it does not
-- cover, done here:
--   * the battle's move-name index stops at the cart's last move (battle/moves.lua
--     build_names, rebuilt on every reload), and Moves.get errors on a number it has no name
--     for: Moves.constName / Moves.numForName answer for these moves too
--   * "X used MOVE!" treats a number past the cart's last move as a typed move
--     (BattleText.MOVES_COUNT)
--   * the summary text (SummaryData.moveDescription, keyed by the cart's names): FireRed /
--     LeafGreen's 4-line box or Ruby/Sapphire/Emerald's 2-line one
--   * Ruby/Sapphire/Emerald's contest data (the summary's contest page, the move relearner and
--     contests index it by move and fail on a missing row): a row each, in the cached tables
--   * the battle animation: the cart move it borrows (`look`), instead of the plain hit
-- FAIRY moves are registered as NORMAL; src/types.lua turns them Fairy.

local NewMoves = {}

-- payload rows -> the registered ones (an id another mod already has is skipped)
function NewMoves.register(mod, payload)
  local registered, failed, firstError = {}, 0, nil
  for _, r in ipairs(payload or {}) do
    local ok, err = pcall(function()
      mod.content.moves:register(r.id, {
        id = r.id, name = r.name, index = r.index,
        type = r.type == "FAIRY" and "NORMAL" or r.type,
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

-- The registry writes a new move into the move-name index with its NAME where its number
-- belongs (src/mods/Schemas.lua moveWrite: `index.num[id], index.id[num] = id, id`), so every
-- learnset row and egg move that names a new move is stored as that name ("LEAF_STORM")
-- instead of its number. Put the numbers back, after every write of the species tables.
-- resolve(name) -> number or nil. Returns how many entries were repaired.
function NewMoves.repairLearnsets(P, resolve)
  local fixed = 0
  for _, rows in pairs(type(P._learnsets) == "table" and P._learnsets or {}) do
    if type(rows) == "table" then
      for _, row in ipairs(rows) do
        if type(row) == "table" and type(row[2]) == "string" then
          local n = resolve(row[2])
          if n then row[2] = n; fixed = fixed + 1 end
        end
      end
    end
  end
  for _, list in pairs(type(P._eggMoves) == "table" and P._eggMoves or {}) do
    if type(list) == "table" then
      for i, move in ipairs(list) do
        if type(move) == "string" then
          local n = resolve(move)
          if n then list[i] = n; fixed = fixed + 1 end
        end
      end
    end
  end
  return fixed
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

  local okM, Moves = pcall(require, "src.core.game3.battle.moves")
  if okM and type(Moves) == "table" and not Moves.__nationalDexMoves then
    Moves.__nationalDexMoves = true
    local constName, numForName = Moves.constName, Moves.numForName
    Moves.constName = function(num)
      local r = NewMoves._byIndex[tonumber(num) or -1]
      if r then return r.id end
      return constName(num)
    end
    Moves.numForName = function(name)
      local n = numForName(name)
      if n then return n end
      if type(name) == "string" then return byConst[name] or byConst[const(name)] end
      return nil
    end
  end

  -- the rows themselves. The same registry fault (see repairLearnsets) makes its re-write after
  -- a reload of the move tables put a new move under its NAME (rows["MOONBLAST"]), so after
  -- every reload the battle's table, the species module's mirror and the move names lose them:
  -- write each row back at its number. Type FAIRY is written as NORMAL; src/types.lua, whose
  -- reload hooks run after these, turns it Fairy.
  local okP, P = pcall(require, "src.core.game3.pokemon")
  local okT, Types = pcall(require, "src.core.game3.battle.types")
  local function rowOf(r)
    local t = r.type == "FAIRY" and "NORMAL" or r.type
    return { effect = r.effect, power = r.power, type = okT and Types.ID[t] or 0, accuracy = r.accuracy,
             pp = r.pp, secondaryChance = r.secondaryChance, target = r.target, priority = r.priority,
             flags = r.flags }
  end
  local function writeRows()
    for index, r in pairs(NewMoves._byIndex) do
      if okM and type(rawget(Moves, "_rom")) == "table" and type(Moves._rom[index]) ~= "table" then
        Moves._rom[index] = rowOf(r)
      end
      if okP and type(P._battleMoves) == "table" and type(P._battleMoves[index]) ~= "table" then
        P._battleMoves[index] = rowOf(r)
      end
      if okP and type(P._moveNames) == "table" and P._moveNames[index] == nil then
        P._moveNames[index] = r.name
      end
    end
  end
  writeRows()
  if okM and Moves.onReload then Moves.onReload(writeRows, "national_dex_gen3.moves") end

  -- learnsets and egg moves: numbers, not names (see repairLearnsets), now and after reloads
  if okP and type(P) == "table" then
    local function resolve(name)
      local n = byConst[name] or byConst[const(name)]
      if n then return n end
      if okM and type(Moves) == "table" and Moves.numForName then
        local ok, num = pcall(Moves.numForName, name)
        if ok and tonumber(num) then return tonumber(num) end
      end
      return nil
    end
    NewMoves.repairLearnsets(P, resolve)
    -- registered again by each install: the same key moves it to the end of the hooks, after
    -- the registry's own re-write of the species tables (the install on game.ready is last)
    if P.onReload then
      P.onReload(function() writeRows() NewMoves.repairLearnsets(P, resolve) end, "national_dex_gen3.moves")
    end
  end

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

  -- animation: the cart move it borrows
  local okA, Anim = pcall(require, "src.core.game3.battle.anim")
  if okA and type(Anim) == "table" and type(Anim.scriptForMove) == "function" and not Anim.__nationalDexMoves then
    Anim.__nationalDexMoves = true
    local scriptForMove = Anim.scriptForMove
    Anim.scriptForMove = function(moveId, ...)
      local num = tonumber(moveId)
      if not num and type(moveId) == "string" then num = byConst[moveId] or byConst[const(moveId)] end
      local r = num and NewMoves._byIndex[num]
      if r and r.look then return scriptForMove(r.look, ...) end
      return scriptForMove(moveId, ...)
    end
  end
  return true
end

return NewMoves
