-- Standalone: luajit mods/national_dex_gen3/tests/anims_test.lua [game] (from the gen1recomp
-- root; needs that cart imported, FireRed by default).
--
-- The newer moves' battle animations (src/anims.lua, data/anims.lua from pokeemerald-expansion):
-- every script resolves against this cart's templates, graphics, sounds and tasks, and plays to
-- the end in the engine's animation player; a move without one keeps its `look` animation.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"

local data = H.gen3Data(GAME)
local Moves = require("src.core.game3.battle.moves")
local Pokemon = require("src.core.game3.pokemon")
do
  local pack = GAME .. "/data/generated/gba/pokemon/battle_moves.lua"
  Moves._rom = dofile(pack).moves
  Moves._romLoaded = true
  Pokemon._battleMoves = dofile(pack).moves
  data.gen3Moves = Moves
end
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.events:emit("game.ready", {})

-- the animation pack is read through the dataset cache, as a game reads it
do
  local CacheBlob = require("src.import.CacheBlob")
  require("src.core.game3.dataset").cache = function()
    return {
      read = function(_, rel)
        local f = io.open(GAME .. "/" .. rel, "rb")
        if not f then return nil end
        local bytes = f:read("*a")
        f:close()
        return CacheBlob.decode(rel, bytes)
      end,
      exists = function(_, rel)
        local f = io.open(GAME .. "/" .. rel, "rb")
        if f then f:close() end
        return f ~= nil
      end,
    }
  end
end
require("src.core.GameVersion").set(GAME)
local Anim = require("src.core.game3.battle.anim")
Anim._packLoaded, Anim._pack = false, nil
local AnimVm = require("src.core.game3.battle.anim_vm")
local AnimTasks = require("src.core.game3.battle.anim_tasks")
local AnimSprites = require("src.core.game3.battle.anim_sprites")
Anim.reset({ headless = true })

local anims = dofile("mods/national_dex_gen3/data/anims.lua")
local byId = {}
for _, r in ipairs(dofile("mods/national_dex_gen3/data/moves.lua")) do byId[r.id] = r end

local resolved, failed, stuck = 0, {}, {}
for id in pairs(anims.moves) do
  local r = byId[id]
  local script = Anim.scriptForMove(r.index)
  local look = Anim.scriptForMove(r.look)
  if script == look then
    failed[#failed + 1] = id
  else
    resolved = resolved + 1
    AnimTasks.reset()
    AnimSprites.reset()
    local vm = AnimVm.new()
    vm:setPack(Anim._pack)
    local ok, err = pcall(function()
      vm:launch(script, { attackerSide = "player", isReversed = false })
      local ticks = 0
      while vm:busy() and ticks < 900 do
        ticks = ticks + 1
        vm:update(1 / 60)
      end
      if vm:busy() then error("still running after 900 frames", 0) end
    end)
    if not ok then stuck[#stuck + 1] = id .. " (" .. tostring(err):sub(1, 80) .. ")" end
  end
end
table.sort(failed)
table.sort(stuck)
local total = 0
for _ in pairs(anims.moves) do total = total + 1 end
print(("%s: %d of %d expansion animations resolve; left on their look: %s"):format(GAME, resolved, total,
  table.concat(failed, ", ")))
T.check(resolved >= total - 10, ("nearly every animation resolves on %s (%d of %d)"):format(GAME, resolved, total))
T.eq(#stuck, 0, "and each plays to the end (" .. table.concat(stuck, "; "):sub(1, 400) .. ")")

-- a move with one: Moonblast plays the moon, not Crush Claw
local moon = Anim.scriptForMove(byId.MOONBLAST.index)
local usesMoon = false
for _, row in ipairs(moon) do
  if row.op == "createsprite" and row.template == "gMoonSpriteTemplate" then usesMoon = true end
end
T.check(usesMoon, "Moonblast shows the moon")
T.eq(moon[1].op, "loadspritegfx", "and loads its graphics first")
-- a move without one plays the closest cart animation: Bulldoze shakes the ground like Earthquake
T.eq(anims.looks.BULLDOZE, 89, "Bulldoze borrows EARTHQUAKE")
T.eq(Anim.scriptForMove(byId.BULLDOZE.index), Anim._pack.moves[89], "and plays it")
-- a move with neither a script nor a closer look of its own plays data/moves.lua's `look`
-- (one wrap answers all three cases)
do
  local plain
  for _, r in ipairs(dofile("mods/national_dex_gen3/data/moves.lua")) do
    if r.look and not (anims.moves and anims.moves[r.id]) and not (anims.looks and anims.looks[r.id]) then
      plain = r break
    end
  end
  T.check(plain ~= nil, "some move only has data/moves.lua's look")
  if plain then
    T.eq(Anim.scriptForMove(plain.index), Anim.scriptForMove(plain.look),
      plain.id .. " plays the cart animation it borrows (" .. tostring(plain.look) .. ")")
  end
end
-- and a move with neither keeps its look
local plain
for id, r in pairs(byId) do
  if not anims.moves[id] and not anims.looks[id] then plain = r break end
end
T.eq(Anim.scriptForMove(plain.index), Anim.scriptForMove(plain.look), plain.id .. " keeps its look animation")
-- the cart's own moves are untouched
T.eq(Anim.scriptForMove(1), Anim._pack.moves[1], "POUND plays the cart's own animation")

run.release()
T.finish("national_dex_gen3 move animations (" .. GAME .. ")")
