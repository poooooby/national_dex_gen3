-- The FAIRY type (Gen 6+) on Gen 3, as type id 18, with the Gen 6 type chart.
--
-- Gen 3 has 17 types. The battle engine reads every matchup from the exported flat chart
-- Types.TABLE (src/core/game3/battle/types.lua, read fresh by every damage path, the AI's
-- switch scan and Conversion2) and every species' and move's type from live tables
-- (Pokemon._types, the move rows), so FAIRY is added at runtime:
--   * the chart gains Fairy's rows, inserted BEFORE its -1 sentinel (rows after it are the
--     Ghost immunities Foresight lifts) and loses Steel's resistance to Ghost and Dark
--     (the Gen 6 chart); the AI's own effectiveness (Types.effectiveness, a private chart)
--     is answered from the same table
--   * "FAIRY" is the type's name (gTypeNames[18], and Types.name for Ruby/Sapphire's
--     native table); a Fairy move's type text would otherwise stop the game
--   * species and forms that are Fairy today get their whole modern typing, and the cart's
--     moves that became Fairy (Charm, Sweet Kiss, Moonlight) their new type, on install and
--     after every reload of the species or move tables
--   * the Emerald Battle Factory's type count (an array of 18) sees a Fairy half as the
--     Pokemon's other type
--   * FireRed/LeafGreen's type badge (summary, Pokedex, TM case) draws this mod's own Fairy
--     icon instead of failing (the Pokedex asserts) or showing NORMAL
-- Fairy is special (Gen 3 decides physical/special by type, and Types.PHYSICAL ends at 8).
-- Data: data/types.lua (tools/build_types.py). Icons: assets/types (tools/build_type_icons.py).
-- Ruby/Sapphire/Emerald's summary icon draws through a local; src/type_icons.lua patches it.

local FairyTypes = {}

FairyTypes.FAIRY = 18

-- Gen 6: Steel no longer resists Ghost or Dark (atk, def as type names)
FairyTypes.GEN6_REMOVED = { { "GHOST", "STEEL" }, { "DARK", "STEEL" } }

-- { {atk, def, mult}, ... } for Fairy, from data.offense / data.defense (type name -> tenths)
function FairyTypes.rows(data, ID)
  local out = {}
  local function sorted(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
  end
  for _, def in ipairs(sorted(data.offense)) do
    if ID[def] then out[#out + 1] = { FairyTypes.FAIRY, ID[def], data.offense[def] } end
  end
  for _, atk in ipairs(sorted(data.defense)) do
    if ID[atk] then out[#out + 1] = { ID[atk], FairyTypes.FAIRY, data.defense[atk] } end
  end
  return out
end

-- Fairy's rows in, Gen 6 removals out, all before the sentinel. Returns rows added.
function FairyTypes.patchChart(T, data)
  local t = T.TABLE
  local ID = T.ID
  local drop = {}
  for _, pair in ipairs(FairyTypes.GEN6_REMOVED) do
    drop[ID[pair[1]] .. ":" .. ID[pair[2]]] = true
  end
  local before, after, inBefore = {}, {}, true
  for i = 1, #t, 3 do
    local a, d, m = t[i], t[i + 1], t[i + 2]
    if a == -1 then inBefore = false end
    if inBefore then
      if not drop[a .. ":" .. d] then before[#before + 1] = { a, d, m } end
    else
      after[#after + 1] = { a, d, m }
    end
  end
  local rows = FairyTypes.rows(data, ID)
  for _, r in ipairs(rows) do before[#before + 1] = r end
  for i = #t, 1, -1 do t[i] = nil end
  for _, r in ipairs(before) do t[#t + 1], t[#t + 2], t[#t + 3] = r[1], r[2], r[3] end
  for _, r in ipairs(after) do t[#t + 1], t[#t + 2], t[#t + 3] = r[1], r[2], r[3] end
  return #rows
end

-- the multiplier (tenths) of atk on one defending type, from the chart (every row: the AI's
-- chart has the Ghost immunities too)
local function one(T, atk, def)
  if not def or def == 9 then return 10 end
  local t = T.TABLE
  local mult = 10
  for i = 1, #t, 3 do
    if t[i] == atk and t[i + 1] == def then mult = t[i + 2] end
  end
  return mult
end

local function typesOf(list)
  return { list[1], list[2] or list[1] }
end

local function norm(name)
  return (tostring(name):upper():gsub("[%.']", ""):gsub("[%s%-]+", "_"))
end

-- a cart move's number by name (CHARM, SWEET_KISS): the battle's own index first, else the
-- species module's move names (both are the cart's 1..354)
function FairyTypes.moveNum(require, name)
  local okM, Moves = pcall(require, "src.core.game3.battle.moves")
  local num = okM and Moves.numForName and Moves.numForName(name)
  if num then return num end
  -- the loaded name table only: asking Pokemon.moveName with no table loaded reinstalls every
  -- species table, which would undo the typings this module sets
  local okP, P = pcall(require, "src.core.game3.pokemon")
  local names = okP and (P._romMoveNames or P._moveNames)
  if type(names) ~= "table" then return nil end
  local want = norm(name)
  for id = 1, 354 do
    local n = names[id]
    if type(n) == "string" and norm(n) == want then return id end
  end
  return nil
end

-- opts: { data, require, log, formSlots = { [formId] = slot }, art = { frlg = Image } }
function FairyTypes.install(opts)
  local require, log = opts.require, opts.log
  local data = opts.data
  local okT, T = pcall(require, "src.core.game3.battle.types")
  local okP, P = pcall(require, "src.core.game3.pokemon")
  if not (okT and okP and type(T) == "table" and type(T.TABLE) == "table" and type(P) == "table") then
    if log then log:warn("the Fairy type is off: the engine's type chart was not found") end
    return false
  end
  local FAIRY = FairyTypes.FAIRY
  local ID = T.ID

  if not T.__nationalDexFairy then
    T.__nationalDexFairy = true
    ID.FAIRY = FAIRY
    FairyTypes.patchChart(T, data)
    -- the AI's matchup check (Types.aiTypeCalcUnits) reads a private copy of the chart
    T.effectiveness = function(atk, def1, def2)
      atk, def1, def2 = tonumber(atk) or 0, tonumber(def1) or 0, tonumber(def2)
      local m1, m2 = one(T, atk, def1), 10
      if def2 and def2 ~= def1 then m2 = one(T, atk, def2) end
      return (m1 * m2) / 100
    end
    -- the name: battle move menu, Color Change, Conversion, Camouflage text
    local okR, RomText = pcall(require, "src.core.game3.rom_text")
    local okI, TextIR = pcall(require, "src.core.game3.scripting.text_ir")
    if okR and okI and RomText.overrides and TextIR.fromAscii then
      RomText.overrides[RomText.key("gTypeNames", FAIRY)] = TextIR.fromAscii("FAIRY")
    end
    local name = T.name
    T.name = function(id, ...)
      if tonumber(id) == FAIRY then return "FAIRY" end
      return name(id, ...)
    end
  end

  -- live types: species, forms, the cart's retyped moves
  local function apply()
    if not P._types then pcall(P.types, 1) end
    local set = 0
    if type(P._types) == "table" then
      for dex, list in pairs(data.species or {}) do
        local slot = P.speciesFromNational and P.speciesFromNational(dex)
        if slot and P._types[slot] ~= nil then
          local ok = true
          local nums = {}
          for i, n in ipairs(typesOf(list)) do nums[i] = ID[n]; ok = ok and nums[i] ~= nil end
          if ok then P._types[slot] = nums; set = set + 1 end
        end
      end
      for fid, list in pairs(data.forms or {}) do
        local slot = opts.formSlots and opts.formSlots[fid]
        if slot then
          local nums = {}
          for i, n in ipairs(typesOf(list)) do nums[i] = ID[n] end
          if nums[1] and nums[2] then P._types[slot] = nums; set = set + 1 end
        end
      end
    end
    local okM, Moves = pcall(require, "src.core.game3.battle.moves")
    for _, name in ipairs(data.moves or {}) do
      local num = FairyTypes.moveNum(require, name)
      if num then
        if okM and type(Moves._rom) == "table" and Moves._rom[num] then Moves._rom[num].type = FAIRY end
        if type(P._battleMoves) == "table" and P._battleMoves[num] then P._battleMoves[num].type = FAIRY end
      end
    end
    return set
  end
  local n = apply()
  if P.onReload then P.onReload(function() apply() end, "national_dex_gen3.types") end
  local okM, Moves = pcall(require, "src.core.game3.battle.moves")
  if okM and Moves.onReload then Moves.onReload(function() apply() end, "national_dex_gen3.types") end

  -- Emerald's Battle Factory counts types in an array of 18
  local okF, Factory = pcall(require, "src.core.game3.rse.frontier.factory")
  if okF and type(Factory) == "table" and type(Factory.opponentMostCommonType) == "function"
      and not Factory.__nationalDexFairy then
    Factory.__nationalDexFairy = true
    local orig = Factory.opponentMostCommonType
    Factory.opponentMostCommonType = function(...)
      local types = P.types
      P.types = function(sp)
        local t = types(sp)
        if t[1] == FAIRY then t[1] = t[2] ~= FAIRY and t[2] or 0 end
        if t[2] == FAIRY then t[2] = t[1] end
        return t
      end
      local ok, out = pcall(orig, ...)
      P.types = types
      if not ok then error(out, 0) end
      return out
    end
  end

  -- FireRed/LeafGreen badges: two chrome modules every badge goes through
  local frlg = opts.art and opts.art.frlg
  for _, modName in ipairs({ "src.ui.game3.summary_chrome", "src.ui.game3.pokedex_chrome" }) do
    local okC, Chrome = pcall(require, modName)
    if okC and type(Chrome) == "table" and type(Chrome.drawTypeBadge) == "function"
        and not Chrome.__nationalDexFairy then
      Chrome.__nationalDexFairy = true
      local orig = Chrome.drawTypeBadge
      Chrome.drawTypeBadge = function(typeId, x, y, ...)
        local id = typeId
        if type(id) == "string" then id = (id:upper() == "FAIRY") and FAIRY or id end
        if tonumber(id) == FAIRY then
          if frlg and love and love.graphics then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(frlg, x, y)
          end
          return
        end
        return orig(typeId, x, y, ...)
      end
    end
  end

  if log then log:info("Fairy type: %d species and forms, %d cart moves retyped", n, #(data.moves or {})) end
  return true
end

return FairyTypes
