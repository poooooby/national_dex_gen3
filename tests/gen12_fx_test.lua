-- Standalone: luajit mods/national_dex_gen3/tests/gen12_fx_test.lua [red|blue|yellow|gold|silver|crystal ...]
-- (from the gen1recomp root; runs on red, yellow, gold and crystal when none is named).
-- The pixelfx move animations on Gen 1 / Gen 2 (src/gen12/fx_anims.lua): data/fx.lua's scripts read
-- as timelines, each move's own timing animation in the game's registry (Red: SE_DELAY_ANIMATION_10
-- rows with the move's sound; Gold: a script that waits, named by the move), and the overlay draws
-- only while that move's animation plays. Also: the atlas and every rect in it.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")
local Fx = H.module("src/gen12/fx_anims.lua")
local data = H.module("data/fx.lua")

local line = Fx.timeline(data.labels[data.moves.AURA_SPHERE], data.sheets)
T.eq(#line.parts, 3, "Aura Sphere: three effects (charge, flight, burst)")
T.check(line.parts[2].start >= line.parts[1].start + line.parts[1].life and line.parts[2].mode == 2,
  "the flight starts when the charge has played, and travels")
T.check(line.length >= line.parts[3].start + line.parts[3].life, "the timeline lasts until the burst ends")
local inside = true
for _, sheet in pairs(data.sheets) do
  for i = 0, sheet.frames - 1 do
    local b = i * 6
    local x, y, w, h = sheet.rects[b + 1], sheet.rects[b + 2], sheet.rects[b + 3], sheet.rects[b + 4]
    if w > 0 and (x + w > data.atlas.w or y + h > data.atlas.h) then inside = false end
  end
end
T.check(inside, "every frame is inside the atlas")

for _, version in ipairs(H.versions()) do
  local gen = H.GENERATION[version]
  local run = H.load(version)
  local d = run.data
  local fxState = run.loader.exports.national_dex_gen3._fx
  T.check(fxState and fxState.count >= 15, version .. ": " .. tostring(fxState and fxState.count) .. " moves drawn with pixelfx")
  local lines = fxState and fxState.lines or {}
  if gen == 1 then
    local rec = d.battle_anims and (d.battle_anims.moveAnims or d.battle_anims).AURA_SPHERE
    local seq = rec and rec.seq or {}
    T.check(#seq == math.ceil(lines.AURA_SPHERE.length / 10) and seq[1].effect == "SE_DELAY_ANIMATION_10"
      and seq[1].sound == "AURA_SPHERE", version .. ": Aura Sphere's animation takes the effect's time, with its sound")
  else
    local anims = d.gen2BattleAnims or d.battle_anims
    local key = anims and anims.moves and anims.moves.AURA_SPHERE
    local script = key and anims.scripts and anims.scripts[key] or {}
    local waits = 0
    for _, row in ipairs(script) do if row[1] == "wait" then waits = waits + row[2] end end
    T.check(key == "ndx:AURA_SPHERE" and waits == lines.AURA_SPHERE.length,
      version .. ": Aura Sphere's script waits for the effect (" .. tostring(key) .. ")")
  end
  local _, state, playing = Fx.overlay({ generation = gen, data = data, lines = lines, root = "." })
  local b
  if gen == 1 then
    b = { animPlaying = true, animName = "AURA_SPHERE", animPlayer = { elapsed = 12 }, animAttackerIsPlayer = true }
  else
    b = { anim = { animId = "AURA_SPHERE", frames = 12, env = { battleTurn = 0 } } }
  end
  local id, frame, mine = playing(b)
  T.check(id == "AURA_SPHERE" and frame == 12 and mine, version .. ": drawn while Aura Sphere plays, frame 12, from you")
  if gen == 1 then b.animName = "TACKLE" else b.anim.animId = "TACKLE" end
  T.check(playing(b) == nil, version .. ": not for a cart move")
  run.release()
end

T.finish("national_dex_gen3 Gen 1/2 move animations")
