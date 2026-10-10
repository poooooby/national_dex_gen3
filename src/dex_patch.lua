-- Lets the Ruby/Sapphire/Emerald Pokedex scroll past #386.
--
-- The engine's src/ui/game3/rse/pokedex.lua sizes its National list from the cart's order pack
-- (which fixups.installRseDexOrders extends), but two of its local functions still compare the
-- list position against a literal 386 (`spriteDexNum`, `setRow`), so rows and sprites past #386
-- stay blank. Locals cannot be wrapped, so this reads the engine's own source, swaps those two
-- literals for the length of the National order, runs the result as a second copy of the module
-- and copies its functions into the live module table (everything that requires the module,
-- e.g. the battle's caught-Pokemon page, then gets the fixed ones).
--
-- It is best effort and silent by design: the source is matched by exact text, so an engine
-- that has changed or fixed those lines simply gives no match; an unreadable source, a compile
-- error or an error while running the copy all leave the stock module untouched.

local DexPatch = {}

local PATH = "src/ui/game3/rse/pokedex.lua"
local LIMIT = "#Gfx.orders().numerical_national"
local MODULE = "src.ui.game3.rse.pokedex"

-- The two literals, each of which must match exactly once. Returns the patched source, or nil.
function DexPatch.patchSource(source)
  if type(source) ~= "string" then return nil end
  local out = source
  for _, pattern in ipairs({ "(or i >= )386( then return NONE end)", "(or entryNum >= )386( then)" }) do
    local count
    out, count = out:gsub(pattern, "%1" .. LIMIT .. "%2")
    if count ~= 1 then return nil end
  end
  -- `package` is not in a mod's sandbox (see packageStandIn); a local would risk the 200-local limit
  return (out:gsub("package%.loaded%[", "__nationalDexPackage.loaded["))
end

-- The `package` the module reads (three lookups of already-loaded engine modules) is not in a
-- mod's sandbox, so the copy is given a stand-in that answers through `require`.
local function packageStandIn(require)
  return { loaded = setmetatable({}, { __index = function(_, name)
    local ok, module = pcall(require, name)
    return ok and module or nil
  end }) }
end

-- opts: read(path) -> source|nil, load (the mod's), require (the mod's), log
-- Returns true when the live module was replaced, else false and why.
function DexPatch.install(opts)
  opts = opts or {}
  local log = opts.log
  local function fail(why)
    if log and log.warn then log:warn("the Pokedex keeps its stock list, capped at #386 (%s)", why) end
    return false, why
  end
  local require = opts.require or _G.require
  local okM, live = pcall(require, MODULE)
  if not (okM and type(live) == "table") then return fail("module unavailable") end
  if live.__nationalDexGen3 then DexPatch.applyPeek(require) return true end

  local okR, source = pcall(opts.read or function() return nil end, PATH)
  if not (okR and type(source) == "string") then return fail("engine source not readable") end
  local patched = DexPatch.patchSource(source)
  if not patched then return fail("engine source is not the expected one") end

  -- the peek patches are optional: without them the list fix still goes in
  local peeked = DexPatch.patchPeekSource(patched)
  if peeked then
    patched = peeked
  elseif log and log.warn then
    log:warn("undiscovered Pokedex entries stay closed (engine source is not the expected one)")
  end
  local withForms = DexPatch.patchFormsSource(patched)
  if withForms then
    patched = withForms
  elseif log and log.warn then
    log:warn("the Pokedex has no FORMS page (engine source is not the expected one)")
  end

  local env = opts.env or _G
  env.__nationalDexPackage = packageStandIn(require)
  local chunk, err = (opts.load or load)(patched, "@" .. PATH)
  if not chunk then return fail("compile: " .. tostring(err)) end
  local okC, copy = pcall(chunk)
  if not (okC and type(copy) == "table" and type(copy.show) == "function") then
    return fail("run: " .. tostring(copy))
  end
  DexPatch.extendNumbers(copy)
  for key, value in pairs(copy) do
    if key ~= "lastSelected" and key ~= "lastRotation" then live[key] = value end
  end
  live.__nationalDexGen3 = true
  -- the copied functions read `Pokedex.__peek` off the COPY's table
  live.__nationalDexCopy = copy
  live.__nationalDexPeek = peeked ~= nil
  live.__nationalDexRseForms = withForms ~= nil
  DexPatch.applyPeek(require)
  if log and log.info then log:info("the Pokedex list now runs past #386") end
  return true
end

-- The A-Z, weight and height lists keep a National number only if it has a Hoenn number
-- (`List.create` -> inRange -> Pokedex.hoennNumber), and the cart's table stops at #386, so the
-- added species were dropped from them. Past #386 a species answers with its own number: in the
-- National list (limit = its length) that is in range; in the Hoenn list (<= 386) it is out.
-- Applied to the module TABLE the screen's own code reads (`Pokedex.hoennNumber` is looked up
-- on it at call time), i.e. the patched copy: wrapping the live table would not reach it.
local function extendNumbers(module)
  if type(module) ~= "table" or type(module.hoennNumber) ~= "function" then return false end
  local original = module.hoennNumber
  module.hoennNumber = function(nat)
    local n = original(nat)
    if n == nil and type(nat) == "number" and nat > 386 and nat <= 1025 then return nat end
    return n
  end
  return true
end
DexPatch.extendNumbers = extendNumbers

-- ------- FireRed / LeafGreen

local FRLG_PATH = "src/ui/game3/pokedex.lua"
local FRLG_MODULE = "src.ui.game3.pokedex"

-- Left and right on the list screen switch between the Kanto and National lists, and the way
-- back (left from National) keeps the National list's scroll, which is past the end of the
-- Kanto list, so the screen goes blank. In the real games left and right page up and down the
-- list you are in (the lists are chosen on the contents screen), which is what the screen's own
-- paging branches already do, so switch the list-changing branches off. The copy also runs on
-- the LIVE module table, so the state other code reads (`open`, `_dex`) stays in one place.
-- Returns the patched source, or nil unless each pattern matches once.
function DexPatch.patchFrlgSource(source)
  if type(source) ~= "string" then return nil end
  local out, count = source:gsub("local Pokedex = { isMenu = true }",
    'local Pokedex = require("' .. FRLG_MODULE .. '"); Pokedex.isMenu = true')
  if count ~= 1 then return nil end
  out, count = out:gsub('if Pokedex%.currentOrder == "numerical_national" then(%s+Pokedex%.currentOrder = "numerical_kanto")',
    "if false then%1")
  if count ~= 1 then return nil end
  out, count = out:gsub('if Pokedex%.currentOrder == "numerical_kanto" and Pokedex%.mode == "kanto" then(%s+Pokedex%.currentOrder = "numerical_national")',
    "if false then%1")
  if count ~= 1 then return nil end
  return out
end

-- Same opts as install(). Silent fallback to the stock screen, with a warning.
function DexPatch.installFrlg(opts)
  opts = opts or {}
  local log = opts.log
  local function fail(why)
    if log and log.warn then log:warn("the FireRed/LeafGreen Pokedex keeps its stock screen (%s)", why) end
    return false, why
  end
  local require = opts.require or _G.require
  local okM, live = pcall(require, FRLG_MODULE)
  if not (okM and type(live) == "table") then return fail("module unavailable") end
  if live.__nationalDexFrlg then DexPatch.applyPeek(require) return true end
  local okR, source = pcall(opts.read or function() return nil end, FRLG_PATH)
  if not (okR and type(source) == "string") then return fail("engine source not readable") end
  local patched = DexPatch.patchFrlgSource(source)
  if not patched then return fail("engine source is not the expected one") end
  local peeked = DexPatch.patchPeekFrlgSource(patched)
  if peeked then
    patched = peeked
  elseif log and log.warn then
    log:warn("undiscovered Pokedex entries stay closed (engine source is not the expected one)")
  end
  local islands = DexPatch.patchFrlgIslandsSource(patched)
  if islands then
    patched = islands
  elseif log and log.warn then
    log:warn("the AREA page keeps to the Kanto map (engine source is not the expected one)")
  end
  local withForms = DexPatch.patchFrlgFormsSource(patched)
  if withForms then
    patched = withForms
  elseif log and log.warn then
    log:warn("the Pokedex has no FORMS page (engine source is not the expected one)")
  end
  local chunk, err = (opts.load or load)(patched, "@" .. FRLG_PATH)
  if not chunk then return fail("compile: " .. tostring(err)) end
  local okC, copy = pcall(chunk)
  if not (okC and copy == live) then return fail("run: " .. tostring(copy)) end
  live.__nationalDexFrlg = true
  live.__nationalDexFrlgPeek = peeked ~= nil
  live.__nationalDexFrlgForms = withForms ~= nil
  DexPatch.applyPeek(require)
  if log and log.info then log:info("the FireRed/LeafGreen Pokedex scroll fix is in") end
  return true
end

-- ------- FireRed / LeafGreen: the Sevii Islands on the AREA page
--
-- The engine's AREA page draws only the Kanto map, so a species found only on the Sevii Islands
-- reads AREA UNKNOWN although the cart's area data has markers for it (and the cache has the
-- seven island maps). pokefirered (src/pokedex_screen.c DexScreen_DrawMonAreaPage) draws each
-- island in its own window -- tiles (13,4) (13,7) (13,10) (13,13) (17,13) (21,13) (25,13) --
-- and moves everything up 4 tiles when one of islands 4-7 is shown, so the bottom row fits; the
-- markers (pokedex_area_markers.c) share one origin with Kanto's. The cart shows the islands
-- the player has unlocked; the engine tracks no such thing, so this shows the islands where the
-- species has a marker, each with its name (ONE .. SEVEN) above it, which the cart does not
-- draw. Applied whether or not anything registers a peek.

local FRLG_AREA_OLD = [[
    local areaW = FrlgFont.measure(RomText.plain("gText_Area"), { small = true })
    FrlgFont.draw(RomText.plain("gText_Area"), 136 + math.floor((96 - areaW) / 2), 52, { small = true, colors = upperColors })

    -- pokefirered/src/pokedex_screen.c:678
    local mapX, mapY = 136, 64
    PokedexChrome.drawMap("kanto", mapX, mapY)

    -- pokefirered/src/pokedex_screen.c:3129
    local drawn = 0
    for _, aKey in ipairs(PokedexData.getWildAreasForSpecies(sp)) do
      if PokedexData.getAreaMapKey(aKey) == "kanto" then
        local m = PokedexData.getAreaMarker(aKey)
        if m then
          PokedexChrome.drawAreaMarker(m.shape, mapX + (m.x - 32), mapY + m.y)
          drawn = drawn + 1
        end
      end
    end
]]

local FRLG_AREA_NEW = [[
    -- national_dex_gen3: the Sevii Islands too (src/dex_patch.lua)
    local areaKeys = PokedexData.getWildAreasForSpecies(sp)
    local isles = {}
    for _, aKey in ipairs(areaKeys) do
      local k = PokedexData.getAreaMapKey(aKey)
      if k ~= "kanto" and PokedexData.getAreaMarker(aKey) then isles[k] = true end
    end
    local voff = (isles.four_island or isles.five_island or isles.six_island or isles.seven_island) and 0 or 4
    local areaW = FrlgFont.measure(RomText.plain("gText_Area"), { small = true })
    FrlgFont.draw(RomText.plain("gText_Area"), 136 + math.floor((96 - areaW) / 2), 20 + voff * 8, { small = true, colors = upperColors })

    -- pokefirered/src/pokedex_screen.c:678
    local mapX, mapY = 136, 32 + voff * 8
    PokedexChrome.drawMap("kanto", mapX, mapY)
    local isleTiles = { one_island = { 13, 4 }, two_island = { 13, 7 }, three_island = { 13, 10 },
      four_island = { 13, 13 }, five_island = { 17, 13 }, six_island = { 21, 13 }, seven_island = { 25, 13 } }
    for key, t in pairs(isleTiles) do
      if isles[key] then PokedexChrome.drawMap(key, t[1] * 8, (t[2] + voff) * 8) end
    end
    -- the island's name above its map (the cart's maps carry none); drawn after every map, as
    -- the windows touch and a name can sit on the edge of the one above it
    local isleNames = { one_island = "ONE", two_island = "TWO", three_island = "THREE",
      four_island = "FOUR", five_island = "FIVE", six_island = "SIX", seven_island = "SEVEN" }
    for key, t in pairs(isleTiles) do
      if isles[key] then
        local nameW = FrlgFont.measure(isleNames[key], { small = true })
        FrlgFont.draw(isleNames[key], t[1] * 8 + math.floor((32 - nameW) / 2), (t[2] + voff) * 8 - 8,
          { small = true, colors = upperColors })
      end
    end

    -- pokefirered/src/pokedex_screen.c:3129
    local drawn = 0
    for _, aKey in ipairs(areaKeys) do
      local m = PokedexData.getAreaMarker(aKey)
      if m then
        PokedexChrome.drawAreaMarker(m.shape, mapX + (m.x - 32), mapY + m.y)
        drawn = drawn + 1
      end
    end
]]

function DexPatch.patchFrlgIslandsSource(source)
  if type(source) ~= "string" then return nil end
  local out = source:gsub("\r\n", "\n")
  return DexPatch._replace(out, FRLG_AREA_OLD, FRLG_AREA_NEW, 1)
end

-- ------- The FORMS page (src/dex_forms.lua)
--
-- Only the gates are patched here; the page, the tab label and the forms list live in
-- src/dex_forms.lua, which sets the module-table functions these call. Each set is optional:
-- a screen that has moved on keeps working without FORMS.

function DexPatch.patchFormsSource(source)
  if type(source) ~= "string" then return nil end
  local out = source:gsub("\r\n", "\n")
  local edits = {
    -- the CANCEL tab reads FORMS on a species that has forms
    { [[  return layer("select", Gfx.renderMap(m, "menu", bgPal(s)), 0)]],
      [[  local barImg = Gfx.renderMap(m, "menu", bgPal(s))
  if Pokedex.__formsTab ~= nil then barImg = Pokedex.__formsTab(s, barImg, submenu, selected, bgPal(s)) or barImg end
  return layer("select", barImg, 0)]], 1 },
    -- A on it opens the FORMS page instead of leaving the entry (Emerald's bar; B still exits)
    { [[      se("SE_FAILURE")
    else
      s.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
      s.fn = "exitInfo"
      se("SE_PC_OFF")
    end]],
      [[      se("SE_FAILURE")
    elseif not nativeRs() and sc == SCREEN.CANCEL and Pokedex.__formsOpen ~= nil and Pokedex.__formsOpen(s) then
      se("SE_PIN")
    else
      s.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
      s.fn = "exitInfo"
      se("SE_PC_OFF")
    end]], 1 },
  }
  for _, e in ipairs(edits) do
    out = DexPatch._replace(out, e[1], e[2], e[3])
    if not out then return nil end
  end
  return out
end

function DexPatch.patchFrlgFormsSource(source)
  if type(source) ~= "string" then return nil end
  local out = source:gsub("\r\n", "\n")
  local edits = {
    -- A on page 2 goes on to page 3 when the species has forms
    { [[    else
      -- On page 2, A is CANCEL (returns to list/grid)]],
      [[    elseif Pokedex.dataPage == 2 and Pokedex.__formsAvailable ~= nil and Pokedex.__formsAvailable(Pokedex.selectedSpecies) then
      Pokedex.dataPage = 3
      se("SE_SELECT")
    else
      -- On page 2, A is CANCEL (returns to list/grid)]], 1 },
    -- B on page 3 steps back to page 2
    { [[    if Pokedex.dataPage == 2 then
      -- On page 2, B is PREVIOUS DATA (returns to page 1)]],
      [[    if Pokedex.dataPage == 3 then
      Pokedex.dataPage = 2
      se("SE_SELECT")
    elseif Pokedex.dataPage == 2 then
      -- On page 2, B is PREVIOUS DATA (returns to page 1)]], 1 },
    -- page 2's hint says A goes on, not A cancels
    { [[PokedexChrome.drawControlInfo(RomText.plain("gText_CancelPreviousData"), 236, 146)]],
      [[PokedexChrome.drawControlInfo((Pokedex.__page2Controls ~= nil and Pokedex.__page2Controls(sp)) or RomText.plain("gText_CancelPreviousData"), 236, 146)]], 1 },
  }
  for _, e in ipairs(edits) do
    out = DexPatch._replace(out, e[1], e[2], e[3])
    if not out then return nil end
  end
  return out
end

-- ------- Peek: open an undiscovered species in a limited view
--
-- Another mod (Modern Spawns) registers fn(speciesSlot) -> true for an unseen species the
-- player may open anyway, to read where it lives (the AREA page). Both screens gate opening an
-- entry, and stepping between entries, on "seen" inside local functions, so the gates are
-- patched in the same way as above: an unseen entry opens when `Pokedex.__peek` says so. In that
-- view the name reads as dashes, the picture is the cart's "?" one, no cry plays, the
-- footprint is hidden, and the cry and size pages stay closed (category, height, weight and
-- description are already owned-only). The list runs on to the last entry that can be opened.
-- With no fn registered nothing changes. Each set must match exactly, or it is skipped whole.

-- Replace every occurrence of `old` (plain text) with `new`, expecting exactly `count` of them.
local function replace(source, old, new, count)
  if not source then return nil end
  local out, n, from = {}, 0, 1
  while true do
    local i, j = source:find(old, from, true)
    if not i then break end
    out[#out + 1] = source:sub(from, i - 1)
    out[#out + 1] = new
    from = j + 1
    n = n + 1
  end
  if n ~= count then return nil end
  out[#out + 1] = source:sub(from)
  return table.concat(out)
end
DexPatch._replace = replace

local function rsePeek(nat)
  return "(Pokedex.__peek ~= nil and Pokedex.__peek(Pokedex.speciesOf(" .. nat .. ")) == true)"
end

function DexPatch.patchPeekSource(source)
  if type(source) ~= "string" then return nil end
  local out = source:gsub("\r\n", "\n")
  local edits = {
    -- list: A opens an entry
    { "if new.a and item(s, s.selected).seen then",
      "if new.a and (item(s, s.selected).seen or " .. rsePeek("item(s, s.selected).dexNum") .. ") then", 1 },
    -- info page: up/down steps to the next entry that can be opened
    { "if item(s, nextMon).seen then",
      "if item(s, nextMon).seen or " .. rsePeek("item(s, nextMon).dexNum") .. " then", 2 },
    -- loading an entry remembers whether it is a peek
    { "info.owned = it.owned", "info.owned = it.owned\n    s.peeking = not it.seen", 1 },
    -- the name (Ruby/Sapphire and Emerald layouts)
    { "text = pokemon().name(Pokedex.speciesOf(nat)) or Gfx.manifest().tenDashes",
      "text = (not s.peeking and pokemon().name(Pokedex.speciesOf(nat))) or Gfx.manifest().tenDashes", 1 },
    { "text = sp ~= 0 and pokemon().name(sp) or Gfx.manifest().tenDashes",
      "text = sp ~= 0 and not s.peeking and pokemon().name(sp) or Gfx.manifest().tenDashes", 1 },
    -- footprint, picture, cry
    { "info.footprint = (not nativeRs() or info.owned) and footprintImage(info.dexNum) or nil",
      "info.footprint = not s.peeking and (not nativeRs() or info.owned) and footprintImage(info.dexNum) or nil", 1 },
    { "img = monPic(s, info.dexNum)", "img = monPic(s, s.peeking and 0 or info.dexNum)", 1 },
    { "if not info.skipCry then", "if not info.skipCry and not s.peeking then", 1 },
    -- the cry page stays closed (the size page already needs the species owned)
    { "or sc == (nativeRs() and 2 or SCREEN.CRY) or (sc",
      "or (sc == (nativeRs() and 2 or SCREEN.CRY) and not s.peeking) or (sc", 1 },
    { "elseif sc == (nativeRs() and 3 or SCREEN.SIZE) then",
      "elseif sc == (nativeRs() and 3 or SCREEN.SIZE) or sc == (nativeRs() and 2 or SCREEN.CRY) then", 1 },
  }
  for _, e in ipairs(edits) do
    out = replace(out, e[1], e[2], e[3])
    if not out then return nil end
  end
  return out
end

local FRLG_PEEK = "(Pokedex.__peek ~= nil and Pokedex.__peek(sp) == true)"

function DexPatch.patchPeekFrlgSource(source)
  if type(source) ~= "string" then return nil end
  local out = source:gsub("\r\n", "\n")
  local edits = {
    -- no cry for an unseen species (opening it, stepping to it, SELECT/START)
    { "local function play_cry(speciesId)\n  pcall(function()",
      "local function play_cry(speciesId)\n  if Pokedex.__peek ~= nil and not Dex.isSeen(Pokedex._dex, speciesId) then return end\n  pcall(function()", 1 },
    -- category grid and list: A opens an entry
    { "if sp and Dex.isSeen(dex, sp) then\n      Pokedex.selectedSpecies = sp",
      "if sp and (Dex.isSeen(dex, sp) or " .. FRLG_PEEK .. ") then\n      Pokedex.selectedSpecies = sp", 1 },
    { "if sp and Dex.isSeen(Pokedex._dex, sp) then\n      Pokedex.selectedSpecies = sp",
      "if sp and (Dex.isSeen(Pokedex._dex, sp) or " .. FRLG_PEEK .. ") then\n      Pokedex.selectedSpecies = sp", 1 },
    -- data screen: up/down steps to the next entry that can be opened
    { "if Dex.isSeen(Pokedex._dex, sp) then\n      return cur, sp",
      "if Dex.isSeen(Pokedex._dex, sp) or " .. FRLG_PEEK .. " then\n      return cur, sp", 1 },
    -- the name, the picture (page 1) and the icon (page 2); the size chart is owned-only already
    { "local name = species_label(sp)",
      "local name = Dex.isSeen(dex, sp) and species_label(sp) or \"----------\"", 1 },
    { "local pic = Pokemon.dexFrontPic(sp, Dex.defaultPersonality(Pokedex._dex, sp))\n    if pic and pic.image then\n      love.graphics.setColor(1, 1, 1, 1)\n      love.graphics.draw(pic.image, 152, 24)",
      "local pic = Dex.isSeen(dex, sp) and Pokemon.dexFrontPic(sp, Dex.defaultPersonality(Pokedex._dex, sp)) or nil\n    if pic and pic.image then\n      love.graphics.setColor(1, 1, 1, 1)\n      love.graphics.draw(pic.image, 152, 24)", 1 },
    { "local icon = Pokemon.dexIcon(sp, Dex.defaultPersonality(Pokedex._dex, sp))",
      "local icon = Dex.isSeen(dex, sp) and Pokemon.dexIcon(sp, Dex.defaultPersonality(Pokedex._dex, sp)) or nil", 1 },
  }
  for _, e in ipairs(edits) do
    out = replace(out, e[1], e[2], e[3])
    if not out then return nil end
  end
  return out
end

-- The numerical lists end at the highest SEEN number; with a peek fn they run on to the highest
-- number that can be opened. Wrapped on the public list builders, read at call time.
local function wrapRseList(List)
  if type(List) ~= "table" or type(List.create) ~= "function" or List.__nationalDexPeekWrap then return end
  List.__nationalDexPeekWrap = true
  local original = List.create
  List.create = function(ctx, dexMode, order, ...)
    local list = original(ctx, dexMode, order, ...)
    local peek = List.__peekNat
    if not peek or order ~= List.ORDER_NUMERICAL or type(list) ~= "table" or type(ctx) ~= "table" then
      return list
    end
    local ok, out = pcall(function()
      if dexMode == List.DEX_MODE_NATIONAL and ctx.nationalEnabled then
        local n = ctx.nationalCount or #ctx.orders.numerical_national
        local first, last
        for nat = 1, n do
          if ctx.seen(nat) or peek(nat) then
            first = first or nat
            last = nat
          end
        end
        if not first then return list end
        local items, count = {}, 0
        for nat = first, last do
          items[count] = { dexNum = nat, seen = ctx.seen(nat), owned = ctx.owned(nat) }
          count = count + 1
        end
        return { items = items, count = count }
      end
      local last = list.count or 0
      for i, nat in ipairs(ctx.orders.numerical_hoenn or {}) do
        list.items[i - 1] = list.items[i - 1] or { dexNum = nat, seen = ctx.seen(nat), owned = ctx.owned(nat) }
        if i > last and (list.items[i - 1].seen or peek(nat)) then last = i end
      end
      list.count = last
      return list
    end)
    return ok and out or list
  end
end

local function wrapFrlgOrders(PD, require)
  if type(PD) ~= "table" or type(PD.getOrderList) ~= "function" or PD.__nationalDexPeekWrap then return end
  PD.__nationalDexPeekWrap = true
  local original = PD.getOrderList
  PD.getOrderList = function(orderKey, dex, ...)
    local list = original(orderKey, dex, ...)
    local peek = PD.__peekSlot
    if not (peek and dex and type(list) == "table"
        and (orderKey == "numerical_national" or orderKey == "numerical_kanto")) then
      return list
    end
    local ok, out = pcall(function()
      local Dex = require("src.core.game3.dex")
      local Pokemon = require("src.core.game3.pokemon")
      local national = orderKey == "numerical_national"
      local max = national and (Dex.NATIONAL_MAX or 386) or (Dex.KANTO_MAX or 151)
      local function slotOf(n) return national and Pokemon.speciesFromNational(n) or n end
      local highest = #list
      for n = #list + 1, max do
        local slot = slotOf(n)
        if slot and peek(slot) then highest = n end
      end
      local result = {}
      for n = 1, highest do result[n] = list[n] or slotOf(n) end
      return result
    end)
    return ok and out or list
  end
end

local peekFn, peekRequire
-- fn(speciesSlot) -> true when that unseen species may open in the limited view; nil clears it.
function DexPatch.setPeek(fn)
  peekFn = type(fn) == "function" and fn or nil
  DexPatch.applyPeek(peekRequire)
end

-- Points every patched screen (and the list wraps) at the current fn. Called from setPeek and
-- after each install, so the order the two happen in does not matter.
function DexPatch.applyPeek(require)
  require = require or peekRequire
  if not require then return end
  peekRequire = require
  local fn = peekFn
  local guarded = fn and function(slot)
    local ok, v = pcall(fn, slot)
    return ok and v == true
  end or nil
  local okR, rse = pcall(require, MODULE)
  if okR and type(rse) == "table" and rse.__nationalDexPeek then
    local target = rse.__nationalDexCopy or rse
    target.__peek = guarded
    rse.__peek = guarded
    local okL, List = pcall(require, "src.ui.game3.rse.pokedex_list")
    if okL then
      wrapRseList(List)
      List.__peekNat = guarded and function(nat)
        local slot = target.speciesOf(nat)
        return slot ~= nil and slot ~= 0 and guarded(slot)
      end or nil
    end
  end
  local okF, frlg = pcall(require, FRLG_MODULE)
  if okF and type(frlg) == "table" and frlg.__nationalDexFrlgPeek then
    frlg.__peek = guarded
    local okD, PD = pcall(require, "src.core.game3.pokedex_data")
    if okD then
      wrapFrlgOrders(PD, require)
      PD.__peekSlot = guarded
    end
  end
end

return DexPatch
