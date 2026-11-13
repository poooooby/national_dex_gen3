-- Standalone: luajit mods/national_dex_gen3/tests/gen12_mechanics_test.lua [red|blue|yellow|gold|silver|crystal ...]
-- (from the gen1recomp root; runs on red, yellow, gold and crystal when none is named).
-- The mechanics layer (src/gen12/mech/, src/gen12/battle/): the 88 newer moves data/moves.lua
-- describes as data (`extra`) are real moves on both games, each runs in the game's own battle both ways, and they do
-- what they say: Close Combat lowers the user's defences, Nasty Plot raises its Sp. Atk (Red: its
-- SPECIAL), Draining Kiss heals, Flare Blitz costs recoil, Fire Fang burns and flinches,
-- Shell Smash changes five stats. Every chance is rolled low here, so each one lands.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")
local gen3 = H.module("data/moves.lua")
local Red = H.module("src/gen12/battle/red.lua")

local described = {}
for _, r in ipairs(gen3) do if r.extra then described[#described + 1] = r.id end end

T.eq(#described, 88, "88 newer moves are described as data")
T.eq(Red.wrap("Enemy PIDGEOTTO's attack was blocked by the barrier"),
  table.concat({ "Enemy PIDGEOTTO's", "attack was blocked", "by the barrier" }, "\n"),
  "Red text breaks at 18 columns")

local function gen1(version)
  local run, api = H.load(version)
  local data = run.data
  for _, id in ipairs(described) do
    if not (data.moves[id] and tostring(data.moves[id].effect):find("^NDX_M_")) then
      T.check(false, version .. ": " .. id .. " is a real move")
    end
  end
  require("src.battle.TypeChart").load(data)
  pcall(require("src.render.Font").load, data)
  local Game = require("src.core.Game")
  Game.data = data
  Game.save = require("src.core.SaveData").newGame()
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local function fresh(foe, mine)
    Game.save.options.animations = false
    Game.save.party = { Pokemon.new(data, mine or "SQUIRTLE", 40) }
    local tb = BattleState.newWild(Game, foe or "RATTATA", 40)
    tb.queue, tb.nextInsert = {}, 0
    tb.rng = function(a) return a end            -- the low roll: every move and chance lands
    return tb
  end
  local failed, first = 0, nil
  for _, id in ipairs(described) do
    for _, enemy in ipairs({ false, true }) do
      local tb = fresh()
      local user, target = tb.player, tb.enemy
      if enemy then user, target = tb.enemy, tb.player end
      local ok, err = pcall(tb.performMove, tb, user, target, { id = id, pp = 10 }, false)
      if not ok then failed = failed + 1; first = first or (id .. ": " .. tostring(err)) end
    end
  end
  T.eq(failed, 0, version .. ": all 88 run in Red's battle" .. (first and (" -- " .. first) or ""))

  local function use(id, foe, setup)
    local tb = fresh(foe)
    if setup then setup(tb) end
    local hpFoe = tb.enemy.mon.hp
    tb:performMove(tb.player, tb.enemy, { id = id, pp = 10 }, false)
    return tb, hpFoe
  end
  local tb, hp = use("CLOSE_COMBAT")
  local A = api._mech.adapter.adapter(tb, api._mech.deps)
  T.check(tb.enemy.mon.hp < hp and tb.player.stages.defense == -1 and (tb.player.stages.special or 0) == 0
      and A:stage(tb.player, "spDef") == -1,
    version .. ": Close Combat hits and lowers the user's DEFENSE and Sp. Def (not its SPECIAL)")
  tb = use("NASTY_PLOT")
  T.eq(tb.player.stages.special, 2, version .. ": Nasty Plot: SPECIAL +2")
  tb = use("SHELL_SMASH")
  T.check(tb.player.stages.attack == 2 and tb.player.stages.speed == 2 and tb.player.stages.defense == -1
    and tb.player.stages.special == 2, version .. ": Shell Smash")
  tb = use("DRAINING_KISS", nil, function(t) t.player.mon.hp = 10 end)
  T.check(tb.player.mon.hp > 10, version .. ": Draining Kiss heals the user (" .. tb.player.mon.hp .. ")")
  local full
  tb = use("FLARE_BLITZ", nil, function(t) full = t.player.mon.hp end)
  T.check(tb.player.mon.hp < full, version .. ": Flare Blitz costs recoil")
  tb = use("FIRE_FANG")
  T.check(tb.enemy.mon.status == "BRN" and tb.enemy.flinched, version .. ": Fire Fang burns and flinches")
  tb = use("NOBLE_ROAR")
  T.check(tb.enemy.stages.attack == -1 and tb.enemy.stages.special == -1, version .. ": Noble Roar lowers the foe")
  run.release()
end

local function gen2(version)
  local run = H.load(version)
  local data = run.data
  for _, id in ipairs(described) do
    if not data.moves[id] then T.check(false, version .. ": " .. id .. " is a real move") end
  end
  local Battle = require("src.battle.gen2.Battle")
  local Mon = require("src.battle.gen2.Mon")
  local ok0, text = pcall(require("tests.gen2_battle_text_fixture"))
  data.text = data.text or (ok0 and text) or nil
  require("src.mods.Runtime").emit("game.ready", { game = { data = data } })
  local function fresh(foe)
    local player = Mon.new(data, "TOTODILE", 40)
    local wild = Mon.new(data, foe or "RATTATA", 40)
    player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    return Battle.new({ data = data, party = { player }, wild = wild,
      save = { player = { id = 7, badges = {}, kantoBadges = {} } },
      random = function(n) return (n or 1) > 1 and 1 or 0 end })
  end
  local failed, first = 0, nil
  for _, id in ipairs(described) do
    for _, enemy in ipairs({ false, true }) do
      local battle = fresh()
      local user, target = battle.player, battle.enemy
      if enemy then user, target = battle.enemy, battle.player end
      local ok, err = pcall(battle.useMove, battle, user, target, id)
      if not ok then failed = failed + 1; first = first or (id .. ": " .. tostring(err)) end
    end
  end
  T.eq(failed, 0, version .. ": all 88 run in Gold's battle" .. (first and (" -- " .. first) or ""))

  local function use(id, setup)
    local b = fresh()
    if setup then setup(b) end
    local hp = b.enemy.hp
    b:useMove(b.player, b.enemy, id)
    return b, hp, b.stages[b:sideOf(b.player)], b.stages[b:sideOf(b.enemy)]
  end
  local b, hp, mine, foe = use("CLOSE_COMBAT")
  T.check(b.enemy.hp < hp and mine.defense == -1 and mine.specialDefense == -1,
    version .. ": Close Combat hits and lowers the user's Defense and Sp. Def")
  b, hp, mine = use("NASTY_PLOT")
  T.eq(mine.specialAttack, 2, version .. ": Nasty Plot: Sp. Atk +2")
  b, hp, mine = use("SHELL_SMASH")
  T.check(mine.attack == 2 and mine.specialAttack == 2 and mine.speed == 2 and mine.defense == -1
    and mine.specialDefense == -1, version .. ": Shell Smash")
  b = use("DRAINING_KISS", function(x) x.player.hp = 10 end)
  T.check(b.player.hp > 10, version .. ": Draining Kiss heals the user (" .. b.player.hp .. ")")
  local full
  b = use("FLARE_BLITZ", function(x) full = x.player.hp end)
  T.check(b.player.hp < full, version .. ": Flare Blitz costs recoil")
  b = use("FIRE_FANG")
  T.eq(b.enemy.status, "burn", version .. ": Fire Fang burns")
  b, hp, mine, foe = use("NOBLE_ROAR")
  T.check(foe.attack == -1 and foe.specialAttack == -1, version .. ": Noble Roar lowers the foe")
  local NoCheck = require("src.battle.gen2.Effects").NO_CHECKHIT
  T.check(NoCheck["NDX_M_NASTY_PLOT"] and not NoCheck["NDX_M_NOBLE_ROAR"],
    version .. ": a self-only move gets past Protect as Gold's own stat-ups do")
  run.release()
end

for _, version in ipairs(H.versions()) do
  if H.GENERATION[version] == 1 then gen1(version) else gen2(version) end
end

T.finish("national_dex_gen3 Gen 1/2 move mechanics")
