-- Standalone: luajit mods/national_dex_gen3/tests/dex_peek_test.lua (from the gen1recomp root;
-- reads the engine's own Pokedex sources, no cart needed).
--
-- src/dex_patch.lua's peek: another mod registers fn(speciesSlot) and an UNSEEN species it
-- answers true for opens in a limited view (dashes for the name, the "?" picture, no cry, the
-- cry and size pages closed; its AREA page shows). The patches must apply to the real engine
-- sources, compile, leave the #386 / paging fixes alone when they do not apply, and the
-- numerical lists must run on to the last entry that can be opened only while a fn is set.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local here = (arg[0]:gsub("\\", "/"):match("^(.*)/") or ".")
local DexPatch = assert(loadfile(here .. "/../src/dex_patch.lua"))()

-- ------- the patches apply to the engine's own sources

local rse = slurp("src/ui/game3/rse/pokedex.lua")
T.check(rse ~= nil, "the engine's RSE Pokedex source is readable")
if rse then
  local listFixed = DexPatch.patchSource(rse)
  T.check(listFixed ~= nil, "the #386 fix applies")
  local peeked = DexPatch.patchPeekSource(listFixed)
  T.check(peeked ~= nil, "every RSE peek patch applies exactly")
  if peeked then
    T.check(loadstring(peeked, "@peeked") ~= nil, "the RSE source with both compiles")
    T.check(peeked:find("s.peeking = not it.seen", 1, true) ~= nil, "an opened entry knows it is a peek")
    T.check(peeked:find("monPic(s, s.peeking and 0 or info.dexNum)", 1, true) ~= nil, "a peek shows the \"?\" picture")
    T.check(peeked:find("if not info.skipCry and not s.peeking then", 1, true) ~= nil, "a peek plays no cry")
  end
end

local frlg = slurp("src/ui/game3/pokedex.lua")
T.check(frlg ~= nil, "the engine's FRLG Pokedex source is readable")
if frlg then
  local paged = DexPatch.patchFrlgSource(frlg)
  T.check(paged ~= nil, "the FRLG paging fix applies")
  local peeked = DexPatch.patchPeekFrlgSource(paged)
  T.check(peeked ~= nil, "every FRLG peek patch applies exactly")
  if peeked then
    T.check(loadstring(peeked, "@peeked") ~= nil, "the FRLG source with both compiles")
    T.check(peeked:find("Dex.isSeen(dex, sp) and species_label(sp)", 1, true) ~= nil, "a peek hides the name")
    local islands = DexPatch.patchFrlgIslandsSource(peeked)
    T.check(islands ~= nil, "the Sevii island AREA patch applies after the others")
    T.check(islands and loadstring(islands, "@islands") ~= nil, "and the result compiles")
  end
  T.check(DexPatch.patchFrlgIslandsSource(frlg) ~= nil, "the island patch also applies to the stock screen")
end
T.eq(DexPatch.patchFrlgIslandsSource("local x = 1"), nil, "an unexpected FRLG source is not island-patched")

-- a source that has moved on loses only the peek, never the other fix
T.eq(DexPatch.patchPeekSource("local x = 1"), nil, "an unexpected RSE source is not peek-patched")
T.eq(DexPatch.patchPeekFrlgSource("local x = 1"), nil, "an unexpected FRLG source is not peek-patched")
T.eq(DexPatch.patchPeekSource(nil), nil, "nothing to patch is fine")

-- ------- the lists run on only while a fn is set

-- stand-ins for the engine modules the wraps reach (require is the test's own)
local seen = { [1] = true, [4] = true }
local List = {
  DEX_MODE_HOENN = 0, DEX_MODE_NATIONAL = 1, ORDER_NUMERICAL = 0,
  create = function(ctx, mode)
    -- the cart's rule: the National list runs from the first to the last SEEN number
    local items, count, last = {}, 0, 0
    for nat = 1, ctx.nationalCount do
      if nat >= 1 and nat <= 4 then
        items[count] = { dexNum = nat, seen = ctx.seen(nat), owned = false }
        count = count + 1
        if ctx.seen(nat) then last = count end
      end
    end
    return { items = items, count = last }
  end,
}
local Screen = { __nationalDexGen3 = true, __nationalDexPeek = true,
                 speciesOf = function(nat) return nat end }
local modules = {
  ["src.ui.game3.rse.pokedex"] = Screen,
  ["src.ui.game3.rse.pokedex_list"] = List,
}
local fakeRequire = function(name)
  if modules[name] then return modules[name] end
  error("not here: " .. name)
end

local ctx = { nationalEnabled = true, nationalCount = 10,
  orders = { numerical_national = {}, numerical_hoenn = {} },
  seen = function(nat) return seen[nat] == true end, owned = function() return false end }

DexPatch.applyPeek(fakeRequire)
T.eq(List.create(ctx, List.DEX_MODE_NATIONAL, List.ORDER_NUMERICAL).count, 4,
  "with no fn, the list ends at the last seen number")

DexPatch.setPeek(function(slot) return slot == 7 end)
T.eq(Screen.__peek and Screen.__peek(7), true, "the screen asks the registered fn")
T.eq(Screen.__peek(5), false, "and only what it answers true for")
local list = List.create(ctx, List.DEX_MODE_NATIONAL, List.ORDER_NUMERICAL)
T.eq(list.count, 7, "with a fn, the list runs on to the last entry that can be opened")
T.eq(list.items[6].dexNum, 7, "that entry is #7")
T.eq(list.items[6].seen, false, "and it is still unseen (its row stays dashes)")

DexPatch.setPeek(function() error("boom") end)
T.eq(Screen.__peek(7), false, "a fn that errors answers no")

DexPatch.setPeek(nil)
T.eq(Screen.__peek, nil, "clearing the fn removes the peek")
T.eq(List.create(ctx, List.DEX_MODE_NATIONAL, List.ORDER_NUMERICAL).count, 4, "and the list is the cart's again")

T.finish("national_dex_gen3 dex peek")
