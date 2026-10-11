-- Standalone: luajit mods/national_dex_gen3/tests/mon_anim_test.lua (from the gen1recomp root;
-- needs Pokemon Emerald imported under emerald/: only Emerald animates front pictures).
--
-- A trainer leading with a species this mod registers used to stop the battle ("mon_anim: no
-- port for anim function nil"): the cart's front-animation table ends at its own species.
-- src/mon_anim.lua gives every species and form a cart species' animation.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")

local data = H.gen3Data("emerald")
local AnimData = require("src.core.game3.mon_anim_data")
local Anim = require("src.core.game3.mon_anim")
local Pokemon = require("src.core.game3.pokemon")
-- the animation pack off the imported cart's cache
local CacheBlob = require("src.import.CacheBlob")
AnimData.useCache({
  read = function(_, rel)
    local f = io.open("emerald/" .. rel, "rb")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return CacheBlob.decode(rel, s)
  end,
  exists = function(_, rel)
    local f = io.open("emerald/" .. rel, "rb")
    if f then f:close() return true end
    return false
  end,
})
AnimData.reset()
if not AnimData.available() then print("skipped: the cart's animation pack is not imported") os.exit(0) end

-- before: a slot past the cart's has no animation the engine can play
local failing = 0
for slot = 451, 1217 do
  if not pcall(function() return Anim.animFunction(AnimData.frontAnimId(slot)) end) then failing = failing + 1 end
end
T.check(failing > 0, "unpatched, slots past the cart's have no animation (" .. failing .. " fail)")

local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.events:emit("game.ready", {})
local api = run.loader.exports.national_dex_gen3

local bad = {}
local slots = 0
for slot = 451, 1217 do
  if Pokemon.national(slot) then
    slots = slots + 1
    local id = AnimData.frontAnimId(slot)
    local ok = id ~= nil and pcall(Anim.animFunction, id)
    if not ok then bad[#bad + 1] = slot end
    if type(AnimData.delay(slot)) ~= "number" then bad[#bad + 1] = slot .. "(delay)" end
  end
end
T.eq(slots, 639 + 128, "every species and form checked")
T.eq(#bad, 0, "each has an animation the engine can play (" .. table.concat(bad, ", "):sub(1, 120) .. ")")

local function same(a, b) return AnimData.frontAnimId(a) == AnimData.frontAnimId(b) end
T.check(same(api.slotOf("MEOWTH_ALOLA"), Pokemon.speciesFromName("MEOWTH")), "Alolan Meowth moves like Meowth")
T.check(same(api.slotOf("RHYPERIOR"), Pokemon.speciesFromName("RHYDON")), "Rhyperior moves like Rhydon")
T.check(same(api.slotOf("DARMANITAN_GALAR_STANDARD"), api.slotOf("DARMANITAN")), "a form of a new species moves like its base")
do
  local pikachu = Pokemon.speciesFromName("PIKACHU")
  T.check(AnimData.frontAnimId(pikachu) ~= nil and pcall(Anim.animFunction, AnimData.frontAnimId(pikachu)), "the cart's own species keep theirs")
end

-- a whole entrance runs: the battle's front animation, stepped to the end
do
  local sprite = Anim.newSprite(api.slotOf("TURTWIG"), { animationData = AnimData })
  local ok, err = pcall(function()
    Anim.battleFront(sprite, api.slotOf("TURTWIG"), true, 0, { cry = function() end })
    for _ = 1, 600 do
      Anim.step(sprite)
      if Anim.done(sprite) then break end
    end
  end)
  T.check(ok, "a trainer's TURTWIG plays its entrance without an error (" .. tostring(err) .. ")")
end

run.release()
T.finish("national_dex_gen3 front animations")
