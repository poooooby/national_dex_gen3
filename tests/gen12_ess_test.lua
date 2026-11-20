-- Standalone: luajit mods/national_dex_gen3/tests/gen12_ess_test.lua [red|blue|yellow|gold|silver|crystal ...]
-- (from the gen1recomp root; runs on red, yellow, gold and crystal when none is named).
-- src/gen12/ess_anims.lua: the Gen 9 Move Animation Project's animations on Gen 1 / Gen 2. Every
-- move of the game (the cart's and the newer ones) the pack animates gets a cart animation that
-- takes its time (Red: SE_DELAY_ANIMATION_10 rows, plus the cart record's lasting picture effects;
-- Gold: an "ndx:" script, a two-turn move's charge turn the cart's own), save the ones whose cart
-- animation changes a picture for good; the status animations the games play are the pack's; every
-- pack recording a timing names ships in the sound file; and while one plays its frames step with
-- the cart animation's clock, the battlers' poses follow their cels, and nothing is left when it ends.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")
local ROOT = H.modRoot() .. "/"
local Ess12 = dofile(ROOT .. "src/gen12/ess_anims.lua")
local ess = dofile(ROOT .. "data/ess_anims.lua")

-- what the pack has no animation for (or keeps the cart's on purpose, Ess12.KEEP)
local NONE = {}
for _, id in ipairs({ "BESTOW", "BIDE", "CURSE", "DOUBLE_TEAM", "DRAGON_ASCENT", "DUAL_CHOP", "FAKE_OUT",
  "HEART_STAMP", "MEMENTO", "ME_FIRST", "NATURE_POWER", "ORIGIN_PULSE", "PRECIPICE_BLADES", "PSYSTRIKE",
  "SECRET_POWER", "SKETCH", "SUBSTITUTE", "TEATIME", "TOXIC_THREAD", "TRANSFORM" }) do NONE[id] = true end

-- every pack recording the timings name is in the sound file
do
  local missing = {}
  for name in pairs(ess.moves) do
    local md = dofile(ROOT .. "data/ess/" .. name .. ".lua")
    for _, a in pairs(md) do
      for _, e in ipairs(a.timing or {}) do
        if e.se and e.se:find("^NDX_ESS_") and not ess.sounds[e.se] then missing[#missing + 1] = name .. " " .. e.se end
      end
    end
  end
  T.eq(#missing, 0, "every pack recording a timing names is in the sound file (" .. table.concat(missing, ", "):sub(1, 200) .. ")")
end

for _, version in ipairs(H.versions()) do
  local gen = H.GENERATION[version]
  local run, api = H.load(version)
  T.eq(#run.errors, 0, version .. ": loads clean")
  local data = run.data
  local st = api and api._ess
  T.check(st and st.count > 300, version .. ": " .. tostring(st and st.count) .. " animations from the pack")
  if not st then goto continue end

  -- every move resolves to a pack animation, or is one the pack lacks
  do
    local unknown = {}
    for id, rec in pairs(data.moves) do
      if type(id) == "string" and type(rec) == "table" and not Ess12.essName(ess, id) and not NONE[id] then unknown[#unknown + 1] = id end
    end
    table.sort(unknown)
    T.eq(#unknown, 0, version .. ": every move is the pack's or one it lacks (" .. table.concat(unknown, " "):sub(1, 200) .. ")")
  end

  local function ticks(name)
    local info = ess.moves[name]
    if info then return math.max(info.frames, info.opp or 0) * 3 end
    local md = dofile(ROOT .. "data/ess/" .. name .. ".lua")
    local n = 0
    for _, a in pairs(md) do n = math.max(n, #a.frames) end
    return n * 3
  end

  if gen == 1 then
    local anims = data.battle_anims.moveAnims
    local function delays(rec)
      local n = 0
      for _, row in ipairs(rec.seq) do if row.effect == "SE_DELAY_ANIMATION_10" then n = n + 1 end end
      return n
    end
    local bad = {}
    for key, l in pairs(st.lines) do
      local rec = anims[key]
      if not (rec and delays(rec) == math.max(1, math.ceil(l.ticks / 10))) then bad[#bad + 1] = key end
    end
    T.eq(#bad, 0, version .. ": each record takes its animation's time (" .. table.concat(bad, " "):sub(1, 200) .. ")")
    T.eq(math.max(1, math.ceil(ticks("NIGHT_SLASH") / 10)), delays(anims.NIGHT_SLASH), version .. ": Night Slash's, for one")
    local last = function(id) local s = anims[id].seq return s[#s].effect end
    T.eq(last("FLY"), "SE_SHOW_MON_PIC", version .. ": Fly ends showing its user again")
    T.eq(last("DIG"), "SE_SHOW_MON_PIC", version .. ": and Dig")
    T.eq(last("MINIMIZE"), "SE_MINIMIZE_MON", version .. ": Minimize still leaves the blob")
    T.check(st.lines.BURN_PSN_ANIM and st.lines.SLP_ANIM and st.lines.CONF_ANIM, version .. ": the status animations are the pack's")
    T.check(not st.lines.TRANSFORM and not st.lines.SUBSTITUTE, version .. ": Transform and Substitute keep the cart's")
  else
    local ga = data.gen2BattleAnims
    local bad = {}
    for key, l in pairs(st.lines) do
      local rows = ga.scripts[key]
      local wait
      for _, r in ipairs(rows or {}) do if r[1] == "wait" then wait = r[2] end end
      if wait ~= l.ticks - 1 then bad[#bad + 1] = key end
    end
    T.eq(#bad, 0, version .. ": each script takes its animation's time (" .. table.concat(bad, " "):sub(1, 200) .. ")")
    T.eq(ga.moves.NIGHT_SLASH, "ndx:NIGHT_SLASH", version .. ": Night Slash plays its own")
    local sb = ga.scripts[ga.moves.SOLARBEAM]
    T.check(sb and sb[1][1] == "if_param_equal" and sb[1][2] == 1 and ga.scripts[sb[1][3]] ~= nil,
      version .. ": Solar Beam's charge turn is the cart's own")
    T.eq(ga.ids.ANIM_PSN, "ndx:ANIM_PSN", version .. ": the poison animation is the pack's")
    T.eq(ga.ids.ANIM_SAP, "ndx:ANIM_SAP", version .. ": and Leech Seed's drain")
    T.check(ga.moves.BEAT_UP ~= "ndx:BEAT_UP", version .. ": Beat Up keeps the cart's (it shows the party's pictures)")
  end

  -- playing: the hub steps with the cart animation's clock, poses the battlers, and lets go
  do
    require("src.mods.Runtime").emit("game.ready", { game = { data = data } })
    local BS = require(gen == 1 and "src.battle.BattleState" or "src.ui.gen2.BattleState")
    local hub = BS.__ndxEss
    T.check(hub and hub.state == st and hub.current, version .. ": installed on the battle screen")
    if hub then
      local b
      if gen == 1 then
        b = { animPlaying = true, animName = "AXE_KICK", animPlayer = { elapsed = 0 }, animAttackerIsPlayer = true,
          player = { mon = { species = "LUCARIO" } }, enemy = { mon = { species = "GARCHOMP" } },
          wideLayout = function() return false end }
      else
        b = { anim = { __ndxKey = "ndx:AXE_KICK", frames = 0, env = { battleTurn = 0 } },
          battle = { player = { species = "LUCARIO" }, enemy = { species = "GARCHOMP" } } }
      end
      local function at(t)
        if gen == 1 then b.animPlayer.elapsed = t else b.anim.frames = t end
        return hub.current(b)
      end
      local s0 = at(0)
      T.check(s0 and s0.frame == 0, version .. ": Axe Kick starts at its first frame")
      local s1 = at(30)
      T.check(s1 == s0 and s1.frame == 10, version .. ": and is at frame 10 after 30 ticks (" .. tostring(s1 and s1.frame) .. ")")
      b = gen == 1 and { animPlaying = true, animName = "AXE_KICK", animPlayer = { elapsed = 0 }, animAttackerIsPlayer = true,
          player = b.player, enemy = b.enemy, wideLayout = b.wideLayout }
        or { anim = { __ndxKey = "ndx:AXE_KICK", frames = 0, env = { battleTurn = 0 } }, battle = b.battle }
      local moved = false
      for t = 1, ticks("AXE_KICK") - 1 do
        local s = at(t)
        local p = s and s.pose.player
        if p and (p.dx ~= 0 or p.dy ~= 0) then moved = true end
      end
      T.check(moved, version .. ": its user lunges")
      if gen == 1 then b.animPlaying = false else b.anim.stopped = true end
      T.eq(hub.current(b), nil, version .. ": nothing plays once the cart animation ends")
      T.eq(hub.st, nil, version .. ": and nothing is kept")
    end
  end
  run.release()
  ::continue::
end

T.finish("national_dex_gen3 Gen 9 project animations on Gen 1/2")
