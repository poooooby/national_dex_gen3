-- Standalone: luajit mods/national_dex_gen3/tests/ess_anims_test.lua [game] (from the gen1recomp
-- root; needs that cart imported, FireRed by default).
--
-- The Gen 9 Move Animation Project's animations (src/ess_anims.lua, data/ess_anims.lua, data/ess/,
-- assets/ess, from tools/build_ess_anims.py): every newer move and every cart move the pack names
-- resolves on this cart to our NdxEss task and plays to the end from either side in the engine's
-- animation player for as long as its frames last, putting the battlers back; two-turn moves charge
-- and hide as they should; the cart's status, weather and trap animations play the pack's; Curse and
-- contests keep the cart's; every atlas page, cel, background and sound it names ships.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"
local ROOT = "mods/national_dex_gen3/"

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

local ess = dofile(ROOT .. "data/ess_anims.lua")
local byId = {}
for _, r in ipairs(dofile(ROOT .. "data/moves.lua")) do byId[r.id] = r end

local function exists(rel)
  local f = io.open(ROOT .. rel, "rb")
  if f then f:close() end
  return f ~= nil
end

-- every name the index gives: its moves, then the common animations' files
local files = {}
for name in pairs(ess.moves) do files[#files + 1] = name end
for _, t in pairs(ess.commons) do for _, name in pairs(t) do files[#files + 1] = name end end
for _, name in pairs(ess.trap) do files[#files + 1] = name end

-- the data: every file, sheet, cel, background and sound
local badData, loaded = {}, {}
for _, name in ipairs(files) do
  local info = ess.moves[name]
  local ok, md = pcall(dofile, ROOT .. "data/ess/" .. name .. ".lua")
  if not ok or type(md) ~= "table" or type(md.move) ~= "table" then
    badData[#badData + 1] = name .. " (no data/ess file)"
  else
    loaded[name] = md
    for kind, a in pairs(md) do
      local want = info and (kind == "move" and info.frames or kind == "opp" and info.opp or kind == "charge" and info.charge)
      if want and #a.frames ~= want then
        badData[#badData + 1] = ("%s %s: %d frames, index says %s"):format(name, kind, #a.frames, tostring(want))
      end
      local sheet = a.sheet and ess.sheets[a.sheet]
      if a.sheet and not sheet then badData[#badData + 1] = name .. " sheet " .. a.sheet end
      for _, f in ipairs(a.frames) do
        for _, c in ipairs(f) do
          if c[1] >= 0 and not (sheet and c[1] < sheet.count) then
            badData[#badData + 1] = ("%s cel %d past its sheet"):format(name, c[1])
            break
          end
        end
      end
      for _, e in ipairs(a.timing) do
        if e.bg and not ess.bgs[e.bg] then badData[#badData + 1] = name .. " background " .. e.bg end
        if e.se and e.se:find("^NDX_ESS_") and not ess.sounds[e.se] then badData[#badData + 1] = name .. " sound " .. e.se end
      end
    end
  end
end
T.eq(#badData, 0, "every animation's data is whole (" .. table.concat(badData, "; "):sub(1, 400) .. ")")
local missing = {}
for _, pg in ipairs(ess.pages) do if not exists(pg.file) then missing[#missing + 1] = pg.file end end
for _, file in pairs(ess.sounds) do if not exists(file) then missing[#missing + 1] = file end end
T.eq(#missing, 0, "every atlas page and sound ships (" .. table.concat(missing, ", "):sub(1, 300) .. ")")

-- the atlas: a few pages (not hundreds of files), none over 2048 a side (Android), each a 256-colour
-- PNG (colour type 3) the size the index says; every cel and background a rect inside its page
do
  local function be32(str, i) return ((str:byte(i) * 256 + str:byte(i + 1)) * 256 + str:byte(i + 2)) * 256 + str:byte(i + 3) end
  T.check(#ess.pages > 0 and #ess.pages <= 16, ("%d atlas pages"):format(#ess.pages))
  local bad = {}
  for n, pg in ipairs(ess.pages) do
    local f = io.open(ROOT .. pg.file, "rb")
    local head = f and f:read(26)
    if f then f:close() end
    if not head or be32(head, 17) ~= pg.w or be32(head, 21) ~= pg.h then bad[#bad + 1] = pg.file .. " size"
    elseif pg.w > 2048 or pg.h > 2048 then bad[#bad + 1] = pg.file .. " over 2048"
    elseif head:byte(26) ~= 3 then bad[#bad + 1] = pg.file .. " not 256 colours" end
  end
  local function inside(pgN, x, y, w, h)
    local pg = ess.pages[pgN]
    return pg and x >= 0 and y >= 0 and x + w <= pg.w and y + h <= pg.h
  end
  for name, sh in pairs(ess.sheets) do
    if #sh.r ~= sh.count * 7 then bad[#bad + 1] = name .. " rects" end
    for i = 0, sh.count - 1 do
      local b = i * 7
      if not inside(sh.r[b + 1], sh.r[b + 2], sh.r[b + 3], sh.r[b + 4], sh.r[b + 5]) then
        bad[#bad + 1] = name .. " cel " .. i
        break
      end
    end
  end
  for name, bg in pairs(ess.bgs) do
    if not inside(bg.page, bg.x, bg.y, bg.w, bg.h) then bad[#bad + 1] = "background " .. name end
  end
  T.eq(#bad, 0, "each page is right and every rect lies inside it (" .. table.concat(bad, ", "):sub(1, 300) .. ")")
end

-- the cart sounds it names are this cart's
do
  local SE = require("src.core.game3.se_ids")
  local okF, songs = pcall(SE.forVersion, GAME)
  if not (okF and type(songs) == "table") then songs = SE end
  local unknown, seen = {}, {}
  for _, md in pairs(loaded) do
    for _, a in pairs(md) do
      for _, e in ipairs(a.timing) do
        if e.se and e.se:find("^SE_") and not songs[e.se] and not seen[e.se] then
          seen[e.se] = true
          unknown[#unknown + 1] = e.se
        end
      end
    end
  end
  T.eq(#unknown, 0, "every cart sound is one " .. GAME .. " has (" .. table.concat(unknown, ", ") .. ")")
end

-- every newer move has one, and the carts' own moves the pack names
local newer, carts = 0, 0
for _, info in pairs(ess.moves) do
  if info.num then carts = carts + 1 else newer = newer + 1 end
end
T.eq(newer, #dofile(ROOT .. "data/moves.lua"), "every newer move has one (" .. newer .. ")")
T.check(carts >= 340, ("and %d of the carts' own moves"):format(carts))

-- plays a script headlessly: its ticks, and the frames NdxEss played (false: none)
local function play(script, foe, turn)
  AnimTasks.reset()
  AnimSprites.reset()
  local vm = AnimVm.new()
  vm:setPack(Anim._pack)
  vm:launch(script, { attackerSide = foe and "enemy" or "player", isReversed = foe, moveTurn = turn or 0 })
  local ticks, saw = 0, false
  while vm:busy() and ticks < 1500 do
    ticks = ticks + 1
    vm:update(1 / 60)
    for i = 1, AnimTasks.MAX do
      local t = AnimTasks._pool[i]
      if t.active and t.name == "NdxEss" and t._ndxEss then saw = t._ndxEss.anim end
    end
  end
  if vm:busy() then error("still running after 1500 frames", 0) end
  return ticks, saw
end

-- each plays to the end from both sides, as long as its frames
local played, bad, total = 0, {}, 0
for name, info in pairs(ess.moves) do
  total = total + 1
  local script = Anim.scriptForMove(info.num or byId[name].index)
  local usesEss = false
  for _, row in ipairs(script or {}) do
    if row.task == "NdxEss" or row.op == "choosetwoturnanim" then usesEss = true end
  end
  if not usesEss then
    bad[#bad + 1] = name .. " (not resolved)"
  else
    for _, foe in ipairs({ false, true }) do
      local ok, err = pcall(function()
        -- (a two-turn move: its second turn, the attack)
        local ticks, saw = play(script, foe, info.turns and 1 or 0)
        if not saw then error("no NdxEss task ran", 0) end
        local frames = (foe and info.opp) or info.frames
        if math.abs(ticks - frames * 3) > 8 then error(("%d ticks for %d frames"):format(ticks, frames), 0) end
      end)
      if ok then played = played + 1 else bad[#bad + 1] = name .. (foe and " foe" or "") .. " (" .. tostring(err) .. ")" end
    end
  end
end
table.sort(bad)
T.eq(played, total * 2, ("all %d moves play on %s, from both sides (%s)"):format(total, GAME,
  table.concat(bad, "; "):sub(1, 400)))

-- two-turn moves: Solar Beam charges with the pack's charging animation, then fires
do
  local info = ess.moves.SOLAR_BEAM
  T.check(info and info.turns == "charge" and info.charge ~= nil, "Solar Beam has a charging turn")
  if info and info.charge then
    local script = Anim.scriptForMove(info.num)
    local t0 = play(script, false, 0)
    local t1 = play(script, false, 1)
    T.check(math.abs(t0 - info.charge * 3) <= 8, ("its first turn plays the charge (%d ticks)"):format(t0))
    T.check(math.abs(t1 - info.frames * 3) <= 8, ("its second the beam (%d ticks)"):format(t1))
  end
  -- Fly: the cart's first turn (it hides the user), then the pack's attack, which shows it again
  local fly = ess.moves.FLY
  local script = Anim.scriptForMove(fly.num)
  T.eq(script[1] and script[1].op, "choosetwoturnanim", "Fly keeps the cart's first turn")
  local p = Anim.present("player")
  if p then
    p.invisible = true
    local _, saw = play(script, false, 1)
    T.check(saw ~= false and p.invisible == false, "and its second turn shows the user again")
  end
end

-- what keeps the cart's: Curse (its version by the turn), Transform and Substitute (they change the
-- user's picture), and a contest (outside a battle)
do
  T.eq(Anim.scriptForMove(174), Anim._pack.moves[174], "Curse keeps the cart's own animation")
  T.eq(Anim.scriptForMove(144), Anim._pack.moves[144], "so does Transform (it gives the user the target's picture)")
  T.eq(Anim.scriptForMove(164), Anim._pack.moves[164], "and Substitute (it turns the user into the doll)")
  local hub = Anim.__ndxEss
  hub.state.contest = true
  T.eq(Anim.scriptForMove(85), Anim._pack.moves[85], "a contest's Thunderbolt is the cart's")
  hub.state.contest = false
  T.check(Anim.scriptForMove(85) ~= Anim._pack.moves[85], "a battle's is the pack's")
  -- Anim.launchMove outside a battle (no battle runs here) marks it
  if not Anim._vm then Anim.reset({ headless = true }) end
  local vm = Anim._vm
  local seen
  local launch = vm.launch
  vm.launch = function(self, script, o)
    seen = script
    return launch(self, script, o)
  end
  Anim.launchMove(85, { attackerSide = "player" })
  vm.launch = launch
  T.eq(seen, Anim._pack.moves[85], "a move launched outside a battle plays the cart's")
  AnimTasks.reset()
end

-- the cart's table animations: poison, rain and the trap ones
do
  local psn = Anim.tableScript("status", "STATUS_PSN")
  T.check(psn and psn[1] and psn[1].task == "NdxEss", "being poisoned plays the pack's Poison")
  local rain = Anim.tableScript("general", "RAIN_CONTINUES")
  T.check(rain and rain[1] and rain[1].task == "NdxEss", "rain plays the pack's Rain")
  local trap = Anim.tableScript("general", "TURN_TRAP")
  local usesEss, toCart = false, false
  for _, r in ipairs(trap or {}) do
    if r.task == "NdxEss" then usesEss = true end
    if r.op == "jumpargeq" and r.value == 0 then toCart = true end
  end
  T.check(trap and trap[1] and trap[1].task == "GetTrappedMoveAnimId" and usesEss,
    "a trap turn asks the cart which trap, then plays the pack's")
  T.check(toCart, "but Bind and Wrap (the cart can't tell them apart) keep the cart's")
  -- the cart's task reads the battle (none here): a stand-in reports Fire Spin (1), then Bind / Wrap (0)
  local function trapAs(arg)
    AnimTasks.REGISTRY.NdxTestTrap = function(t, vm)
      vm.args[0] = arg
      AnimTasks.destroy(t)
    end
    local r = {}
    for i, row in ipairs(trap) do r[i] = row end
    r[1] = { op = "createvisualtask", task = "NdxTestTrap", priority = 2, args = {} }
    local okP, saw = pcall(function() return select(2, play(r, false, 0)) end)
    AnimTasks.REGISTRY.NdxTestTrap = nil
    return okP and saw
  end
  T.check(trapAs(1) ~= false, "Fire Spin's turn plays the pack's")
  T.check(trapAs(0) == false, "Bind's or Wrap's plays the cart's")
end

-- a move on its user (Minimize) plays with the user as its target: the foe never shrinks
do
  local script = Anim.scriptForMove(107)
  T.eq(script and script[1] and script[1].args and script[1].args[3], 1, "Minimize is a move on its user")
  local e = Anim.present("enemy")
  local p = Anim.present("player")
  if e and p then
    AnimTasks.reset()
    local vm = AnimVm.new()
    vm:setPack(Anim._pack)
    vm:launch(script, { attackerSide = "player", targetSide = "enemy", isReversed = false })
    local foeShrank, userShrank = false, false
    for _ = 1, 600 do
      if not vm:busy() then break end
      vm:update(1 / 60)
      if (e.sx or 1) < 1 then foeShrank = true end
      if (p.sx or 1) < 1 then userShrank = true end
    end
    T.check(userShrank and not foeShrank, "Minimize shrinks its user, not the foe")
  end
end

-- copies of a battler's picture: Quick Attack's afterimages are the user's (-3)
do
  local md = loaded.QUICK_ATTACK
  local copies = 0
  for _, f in ipairs(md and md.move.frames or {}) do
    for _, c in ipairs(f) do if c[1] == -3 then copies = copies + 1 end end
  end
  T.check(copies > 0, ("Quick Attack draws copies of its user (%d cels)"):format(copies))
end

-- a sound with no name is the attacker's cry: Growl
do
  local Audio = require("src.core.game3.audio")
  local cry, heard = Audio.playCry, nil
  Audio.playCry = function(sp) heard = sp; return true end
  local ok = pcall(function()
    AnimTasks.reset()
    local vm = AnimVm.new()
    vm:setPack(Anim._pack)
    -- (the battle names the attacker's species; there is no battle here)
    vm:launch(Anim.scriptForMove(45), { attackerSide = "player", isReversed = false, attackerSpecies = 25 })
    for _ = 1, 600 do
      if not vm:busy() then break end
      vm:update(1 / 60)
    end
  end)
  Audio.playCry = cry
  T.check(ok and heard == 25, "Growl plays the attacker's cry (" .. tostring(heard) .. ")")
end

-- the battlers are put back: a move that moves its user (Axe Kick lunges) leaves no offset behind
do
  local p = Anim.present("player")
  local e = Anim.present("enemy")
  if p and e then
    AnimTasks.reset()
    local vm = AnimVm.new()
    vm:setPack(Anim._pack)
    vm:launch(Anim.scriptForMove(byId.AXE_KICK.index), { attackerSide = "player", isReversed = false })
    local moved = false
    local ticks = 0
    while vm:busy() and ticks < 1200 do
      ticks = ticks + 1
      vm:update(1 / 60)
      if (p.ox or 0) ~= 0 or (p.oy or 0) ~= 0 then moved = true end
    end
    T.check(moved, "Axe Kick moves its user")
    T.check((p.ox or 0) == 0 and (p.oy or 0) == 0 and (p.alpha or 1) == 1, "and puts it back")
    T.check((e.ox or 0) == 0 and (e.oy or 0) == 0 and (e.alpha or 1) == 1, "and the target")
  end
end

-- an unknown move ends its task at once rather than hang the script
do
  AnimTasks.reset()
  local vm = AnimVm.new()
  vm:setPack(Anim._pack)
  local gone = AnimVm.spawnTask(vm, "NdxEss", 2, { "ESS:NO_SUCH_MOVE" }, "visual")
  AnimTasks.update(vm)
  T.check(not gone.active, "an unknown move ends its task at once")
end

run.release()
T.finish("national_dex_gen3 Gen 9 project animations (" .. GAME .. ")")
