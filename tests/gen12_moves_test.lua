-- Standalone: luajit mods/national_dex_gen3/tests/gen12_moves_test.lua [red|blue|yellow|gold|silver|crystal ...]
-- (from the gen1recomp root; runs on red, yellow, gold and crystal when none is named).
-- src/gen12/moves.lua: every newer move that runs on an effect the game has is a real move there,
-- with the cart effect the data names, its priority / high-critical rate where the game reads
-- them, and a cart move's battle animation (Red: and its sound); Gold's keep their National number
-- as their index; and the resolver turns every National move number into a move the game has.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")
local Moves = H.module("src/gen12/moves.lua")
local rows = H.module("data/gen12/moves.lua")
local byId = {}
for _, r in ipairs(rows) do byId[r.id] = r end

for _, version in ipairs(H.versions()) do
  local gen = H.GENERATION[version]
  local key = "gen" .. gen
  local maxMove = gen == 1 and 165 or 251
  local run = H.load(version)
  for i = 1, math.min(5, #run.errors) do print("load error: " .. tostring(run.errors[i])) end
  T.eq(#run.errors, 0, version .. ": loads clean")
  local data = run.data
  local moves = data.moves

  -- every real row is there, as the data says
  local real, wrong, firstWrong = 0, 0, nil
  for _, r in ipairs(rows) do
    local want = r[key]
    if want then
      real = real + 1
      local m = moves[r.id]
      local ok = m and m.effect == want.effect and m.power == r.power and m.pp == r.pp
        and m.name == r.name
      if ok and gen == 2 then
        ok = m.index == r.n and m.effectChanceRaw == math.floor((want.chance or 0) * 255 / 100)
      end
      if not ok then wrong = wrong + 1; firstWrong = firstWrong or r.id end
    end
  end
  T.check(real > 150, version .. ": " .. real .. " newer moves run here")
  T.eq(wrong, 0, version .. ": each registered as the data says" .. (firstWrong and (" (" .. firstWrong .. ")") or ""))

  -- a sample: Night Slash (Dark, high critical), Aqua Jet (priority)
  local ns, aj = moves.NIGHT_SLASH, moves.AQUA_JET
  T.eq(ns and ns.type, "DARK", version .. ": Night Slash is Dark")
  T.eq(aj and aj.type, "WATER", version .. ": Aqua Jet is Water")
  if gen == 1 then
    local Damage = require("src.battle.Damage")
    require("src.battle.TypeChart").load(data)     -- what a battle does first
    T.check(ns and ns.highCrit == true, version .. ": Night Slash crits often")
    T.eq(aj and aj.priority, 1, version .. ": Aqua Jet moves first")
    T.check(Damage.isSpecial("DARK"), version .. ": Night Slash hits with Special")
    local look = byId.NIGHT_SLASH.look.gen1
    local anims = data.battle_anims and data.battle_anims.moveAnims or {}
    T.check(anims.NIGHT_SLASH ~= nil and #anims.NIGHT_SLASH.seq == #anims[look].seq,
      version .. ": Night Slash plays " .. look .. "'s animation")
    T.eq(ns and ns.anim and ns.anim.sound, moves[look].anim.sound, version .. ": and its sound")
    local noAnim = 0
    for _, r in ipairs(rows) do
      if r[key] and moves[r.id] and not anims[r.id] then noAnim = noAnim + 1 end
    end
    T.eq(noAnim, 0, version .. ": every newer move has an animation")
  else
    T.eq(aj and aj.effect, "EFFECT_PRIORITY_HIT", version .. ": Aqua Jet moves first (by its effect)")
    local Battle = require("src.battle.gen2.Battle")
    T.eq(Battle.PRIORITY and Battle.PRIORITY.EFFECT_PRIORITY_HIT, 1, version .. ": that effect is priority 1")
    T.eq(ns and ns.index, 400, version .. ": Night Slash keeps #400 as its index")
    local scripts = data.gen2BattleAnims.moves
    local look = byId.NIGHT_SLASH.look.gen2
    T.eq(scripts.NIGHT_SLASH, scripts[look], version .. ": Night Slash plays " .. look .. "'s animation")
    local noAnim = 0
    for _, r in ipairs(rows) do
      if r[key] and moves[r.id] and not scripts[r.id] then noAnim = noAnim + 1 end
    end
    T.eq(noAnim, 0, version .. ": every newer move has an animation")
    -- high-critical moves join the battle rules when the game is ready
    local list = data.type_chart.battleRules.highCriticalMoves
    T.check(not list.NIGHT_SLASH, version .. ": not before game.ready")
    require("src.mods.Runtime").emit("game.ready", { game = { data = data } })
    T.check(list.NIGHT_SLASH == true and list.SLASH == true, version .. ": Night Slash crits often after it")
  end

  -- the resolver: a cart move, the registered move, or a stand-in the game has
  local state = { generation = gen, rows = rows, byNumber = {}, highCrit = {} }
  for _, r in ipairs(rows) do
    if r[key] and moves[r.id] then state.byNumber[r.n] = r.id end
  end
  local resolve = Moves.resolver(state, moves)
  local missing, notThere = nil, nil
  for n = 1, maxMove do
    local id = resolve(n)
    if not (id and moves[id] and moves[id].index == n) then missing = missing or n end
  end
  for _, r in ipairs(rows) do
    if r.n > maxMove then
      local id = resolve(r.n)
      if not (id and moves[id]) then notThere = notThere or r.n end
      if r[key] and id ~= r.id then notThere = notThere or r.n end
    end
  end
  T.check(missing == nil, version .. ": the cart's own moves by number (" .. tostring(missing) .. ")")
  T.check(notThere == nil, version .. ": every newer move resolves to one the game has (" .. tostring(notThere) .. ")")
  -- a stand-in the Pokemon already knows is skipped for the next
  local sketchRow
  for _, r in ipairs(rows) do if r.subs and r.subs[key] then sketchRow = r break end end
  local first = resolve(sketchRow.n)
  local second = resolve(sketchRow.n, { [first] = true })
  T.check(second and second ~= first, version .. ": a known stand-in gives way to the next ("
    .. tostring(first) .. " -> " .. tostring(second) .. ")")
  run.release()
end

T.finish("national_dex_gen3 Gen 1/2 moves")
