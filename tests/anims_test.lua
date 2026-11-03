-- Standalone: luajit mods/national_dex_gen3/tests/anims_test.lua [game] (from the gen1recomp
-- root; needs that cart imported, FireRed by default).
--
-- The newer moves' battle animations (src/anims.lua, data/anims.lua from pokeemerald-expansion):
-- every script resolves against this cart's templates, graphics, sounds and tasks, and plays to
-- the end in the engine's animation player; a move without one keeps its `look` animation, or plays
-- the pixelfx one data/fx.lua gives it (src/fx_anims.lua).
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
local fx = dofile("mods/national_dex_gen3/data/fx.lua")
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
-- a move without one plays the closest cart animation: Force Palm chops like Karate Chop
T.eq(anims.looks.FORCE_PALM, 2, "Force Palm borrows KARATE_CHOP")
T.eq(Anim.scriptForMove(byId.FORCE_PALM.index), Anim._pack.moves[2], "and plays it")

-- the pixelfx ones (src/fx_anims.lua, data/fx.lua): each resolves on this cart, starts our NdxFx task
-- and plays to the end from either side; the task runs as long as its row says
do
  local played, bad = 0, {}
  for id, label in pairs(fx.moves) do
    T.check(not anims.moves[id], id .. " has no expansion script (pixelfx fills a gap only)")
    local script = Anim.scriptForMove(byId[id].index)
    local look = Anim.scriptForMove(byId[id].look)
    local usesFx = false
    for _, row in ipairs(script or {}) do
      if row.task == "NdxFx" then usesFx = true end
    end
    if script == look or not usesFx then
      bad[#bad + 1] = id .. " (not resolved)"
    else
      for _, foe in ipairs({ false, true }) do
        AnimTasks.reset()
        AnimSprites.reset()
        local vm = AnimVm.new()
        vm:setPack(Anim._pack)
        local ok, err = pcall(function()
          vm:launch(script, { attackerSide = foe and "enemy" or "player", isReversed = foe })
          local ticks, saw = 0, false
          while vm:busy() and ticks < 900 do
            ticks = ticks + 1
            vm:update(1 / 60)
            for i = 1, AnimTasks.MAX do
              local t = AnimTasks._pool[i]
              if t.active and t.name == "NdxFx" and t._ndxFx then saw = true end
            end
          end
          if vm:busy() then error("still running after 900 frames", 0) end
          if not saw then error("no NdxFx task ran", 0) end
          if ticks < 20 then error("over in " .. ticks .. " frames", 0) end
        end)
        if ok then played = played + 1 else bad[#bad + 1] = id .. (foe and " foe" or "") .. " (" .. tostring(err) .. ")" end
      end
    end
  end
  table.sort(bad)
  local n = 0
  for _ in pairs(fx.moves) do n = n + 1 end
  T.eq(played, n * 2, ("every pixelfx animation plays on %s, from both sides (%s)"):format(GAME, table.concat(bad, "; "):sub(1, 400)))
  -- a sheet's task lasts its frames: Dragon Pulse's beam row says 44
  local row
  for _, r in ipairs(fx.labels[fx.moves.DRAGON_PULSE]) do if r.task == "NdxFx" then row = r end end
  AnimTasks.reset()
  local vm = AnimVm.new()
  vm:setPack(Anim._pack)
  local t = AnimVm.spawnTask(vm, "NdxFx", 2, row.args, "visual")
  local life = 0
  while t.active and life < 200 do
    life = life + 1
    AnimTasks.update(vm)
  end
  T.eq(life, 44, "the beam plays its 44 frames")
  -- an unknown sheet ends at once rather than hang the script
  AnimTasks.reset()
  local gone = AnimVm.spawnTask(vm, "NdxFx", 2, { "FX:NO_SUCH_SHEET", 1, 0, 0, 0, 0 }, "visual")
  T.check(not gone.active, "an unknown sheet ends its task at once")
  -- one atlas, the size data/fx.lua says (the PNG header's width and height), every frame's rect inside it,
  -- and every ramp a sheet or a row names
  local function be32(s, i) return ((s:byte(i) * 256 + s:byte(i + 1)) * 256 + s:byte(i + 2)) * 256 + s:byte(i + 3) end
  local f = io.open("mods/national_dex_gen3/" .. fx.atlas.file, "rb")
  T.check(f ~= nil, "the atlas " .. fx.atlas.file .. " is shipped")
  if f then
    local head = f:read(26)
    f:close()
    T.check(be32(head, 17) == fx.atlas.w and be32(head, 21) == fx.atlas.h,
      ("the atlas is %dx%d, as laid out (%dx%d)"):format(be32(head, 17), be32(head, 21), fx.atlas.w, fx.atlas.h))
    T.eq(head:byte(26), 4, "and gray + alpha")
  end
  local outside, frames = {}, 0
  for name, sheet in pairs(fx.sheets) do
    T.eq(#sheet.rects, sheet.frames * 6, name .. " has a rect per frame")
    T.check(fx.ramps[sheet.ramp] ~= nil, name .. "'s own ramp " .. tostring(sheet.ramp) .. " exists")
    for i = 0, sheet.frames - 1 do
      local x, y, w, h = sheet.rects[i * 6 + 1], sheet.rects[i * 6 + 2], sheet.rects[i * 6 + 3], sheet.rects[i * 6 + 4]
      frames = frames + 1
      if x < 0 or y < 0 or x + w > fx.atlas.w or y + h > fx.atlas.h then outside[#outside + 1] = name .. " " .. i end
    end
  end
  T.eq(#outside, 0, ("all %d frames lie inside the atlas (%s)"):format(frames, table.concat(outside, ", ")))
  local unknown = {}
  for label, rows in pairs(fx.labels) do
    for _, r in ipairs(rows) do
      if r.task == "NdxFx" and r.args[7] and not fx.ramps[(r.args[7]:gsub("^FX:", ""))] then unknown[#unknown + 1] = label end
    end
  end
  T.eq(#unknown, 0, "every ramp a script names exists (" .. table.concat(unknown, ", ") .. ")")
  -- one orb, three colours
  local orbRamps = {}
  for _, move in ipairs({ "AURA_SPHERE", "FOCUS_BLAST", "ENERGY_BALL" }) do
    for _, r in ipairs(fx.labels[fx.moves[move]]) do
      if r.task == "NdxFx" and r.args[1] == "FX:ORB" then orbRamps[r.args[7]] = true end
    end
  end
  local n = 0
  for _ in pairs(orbRamps) do n = n + 1 end
  T.eq(n, 3, "Aura Sphere, Focus Blast and Energy Ball colour the same orb three ways")
end
-- a move with neither a script nor a closer look of its own plays data/moves.lua's `look`
-- (one wrap answers all three cases)
do
  local plain
  for _, r in ipairs(dofile("mods/national_dex_gen3/data/moves.lua")) do
    if r.look and not (anims.moves and anims.moves[r.id]) and not (anims.looks and anims.looks[r.id])
      and not fx.moves[r.id] then
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
  if not anims.moves[id] and not anims.looks[id] and not fx.moves[id] then plain = r break end
end
T.eq(Anim.scriptForMove(plain.index), Anim.scriptForMove(plain.look), plain.id .. " keeps its look animation")
-- the cart's own moves are untouched
T.eq(Anim.scriptForMove(1), Anim._pack.moves[1], "POUND plays the cart's own animation")

run.release()
T.finish("national_dex_gen3 move animations (" .. GAME .. ")")
