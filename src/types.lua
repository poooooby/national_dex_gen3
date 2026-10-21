-- The FAIRY type (Gen 6+) on Gen 3, as type id 18, with the Gen 6 type chart.
--
-- The engine (0.3.95+) builds the Gen 3 type chart from its `type_chart` registry on every mods
-- load (src/core/game3/progression.lua -> Types.useOverlay): custom types take ids 18..255, the
-- overlay supplies the chart every damage path and the AI read, the type's name (Types.name)
-- and its physical/special category. So FAIRY is content, registered while the mod loads
-- (FairyTypes.register):
--   * the type itself (index 18, special) and its matchups as "FAIRY>DRAGON"-style rows from
--     data/types.lua; the Gen 6 chart's removals (Steel no longer resists Ghost or Dark) are
--     removals of the engine's own rows
--   * the typings: the cart's species and forms that are Fairy today are patched to their
--     modern typing, the cart's moves that became Fairy (Charm, Sweet Kiss, Moonlight) to FAIRY,
--     and this mod's own Fairy species and moves are registered FAIRY; the engine writes them
--     again after every reload
-- What the registry does not reach stays in FairyTypes.install (game.ready / the editor):
--   * "FAIRY" in the cart's gTypeNames[18] (union room reads that table directly)
--   * the Emerald Battle Factory's type count (an array of 18) sees a Fairy half as the
--     Pokemon's other type
--   * FireRed/LeafGreen's type badge (summary, Pokedex, TM case) draws this mod's own Fairy
--     icon instead of failing (the Pokedex asserts) or showing NORMAL
-- Data: data/types.lua (tools/build_types.py). Icons: assets/types (tools/build_type_icons.py).
-- Ruby/Sapphire/Emerald's summary icon draws through a local; src/type_icons.lua patches it.

local FairyTypes = {}

FairyTypes.FAIRY = 18

-- Gen 6: Steel no longer resists Ghost or Dark (the engine's own type_chart rows)
FairyTypes.GEN6_REMOVED = { "GHOST>STEEL", "DARK>STEEL" }

local function sorted(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

-- { ["FAIRY>DRAGON"] = 20, ... } from data.offense / data.defense (type name -> tenths)
function FairyTypes.matchups(data)
  local out = {}
  for _, def in ipairs(sorted(data.offense)) do out["FAIRY>" .. def] = data.offense[def] end
  for _, atk in ipairs(sorted(data.defense)) do out[atk .. ">FAIRY"] = data.defense[atk] end
  return out
end

-- At load, before the registries freeze. opts: { mod, data (data/types.lua + moves), log }.
-- Returns the number of typings patched.
function FairyTypes.register(opts)
  local mod, data, log = opts.mod, opts.data or {}, opts.log
  local chart, pokemon, moves = mod.content.type_chart, mod.content.pokemon, mod.content.moves
  if not (chart and pokemon and moves) then
    if log then log:warn("the Fairy type is off: this engine has no type_chart registry") end
    return 0
  end
  local ok, err = pcall(function()
    chart:register("FAIRY", { name = "FAIRY", category = "special", index = FairyTypes.FAIRY })
    local rows = FairyTypes.matchups(data)
    for _, id in ipairs(sorted(rows)) do chart:register(id, { multiplier = rows[id] }) end
    for _, id in ipairs(FairyTypes.GEN6_REMOVED) do
      if chart:get(id) ~= nil then chart:remove(id) end
    end
  end)
  if not ok then
    if log then log:warn("the Fairy type is off: %s", tostring(err)) end
    return 0
  end
  -- species by National number: the cart's and this mod's base species (forms are keyed by id)
  local byDex = {}
  for id, rec in pokemon:each() do
    if type(rec) == "table" and rec.baseSpecies == nil and tonumber(rec.dex) and byDex[rec.dex] == nil then
      byDex[rec.dex] = id
    end
  end
  local n, failed, firstError = 0, 0, nil
  local function patch(registry, id, partial)
    local okP, errP = pcall(registry.patch, registry, id, partial)
    if okP then n = n + 1 else failed = failed + 1; firstError = firstError or tostring(errP) end
  end
  for _, dex in ipairs(sorted(data.species)) do
    local id = byDex[dex]
    if id then patch(pokemon, id, { types = data.species[dex] }) end
  end
  for _, fid in ipairs(sorted(data.forms)) do
    if pokemon:get(fid) ~= nil then patch(pokemon, fid, { types = data.forms[fid] }) end
  end
  for _, id in ipairs(data.moves or {}) do
    if moves:get(id) ~= nil then patch(moves, id, { type = "FAIRY" }) end
  end
  if failed > 0 and log then log:warn("%d Fairy typing(s) not applied; first: %s", failed, firstError) end
  return n
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
  local okT, T = pcall(require, "src.core.game3.battle.types")
  local okP, P = pcall(require, "src.core.game3.pokemon")
  if not (okT and okP and type(T) == "table" and type(P) == "table") then
    if log then log:warn("the Fairy type's screens are off: the engine's type module was not found") end
    return false
  end
  local FAIRY = FairyTypes.FAIRY
  -- this mod's own lookups by name (abilities, rules); the engine's chart is the registry's
  if type(T.ID) == "table" then T.ID.FAIRY = FAIRY end
  -- the cart's gTypeNames table (union room reads it directly; Types.name has the overlay's)
  local okR, RomText = pcall(require, "src.core.game3.rom_text")
  local okI, TextIR = pcall(require, "src.core.game3.scripting.text_ir")
  if okR and okI and RomText.overrides and TextIR.fromAscii then
    RomText.overrides[RomText.key("gTypeNames", FAIRY)] = TextIR.fromAscii("FAIRY")
  end

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

  if log then log:info("Fairy type: chart %s", T.name and tostring(T.name(FAIRY)) or "?") end
  return true
end

return FairyTypes
