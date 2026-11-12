-- Standalone: luajit mods/national_dex_gen3/tests/gen12_battle_test.lua [red|blue|yellow|gold|silver|crystal ...]
-- (from the gen1recomp root; runs on red, yellow, gold and crystal when none is named).
-- Every newer move this mod registers runs in the game's own battle: Red's BattleState
-- (performMove, as the engine's parity tests drive it) and Gold's Battle (useMove), one fresh
-- wild battle per move, user and target both ways. A move that raises an error fails the test.
-- A Dark move hits a Psychic Pokemon super effectively, and a Fairy one a Dragon.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")
local rows = H.module("data/gen12/moves.lua")

local function registered(data, key)
  local out = {}
  for _, r in ipairs(rows) do
    if r[key] and data.moves[r.id] then out[#out + 1] = r.id end
  end
  return out
end

local function gen1(version)
  local run = H.load(version)
  local data = run.data
  require("src.battle.TypeChart").load(data)
  local Font = require("src.render.Font")
  pcall(Font.load, data)
  local Game = require("src.core.Game")
  Game.data = data
  Game.save = require("src.core.SaveData").newGame()
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local function fresh(foe)
    Game.save.options.animations = false
    Game.save.party = { Pokemon.new(data, "SQUIRTLE", 40) }
    local tb = BattleState.newWild(Game, foe or "RATTATA", 40)
    tb.queue, tb.nextInsert = {}, 0
    tb.rng = function(a, b) return b end
    return tb
  end

  local ids = registered(data, "gen1")
  local failed, first = 0, nil
  for _, id in ipairs(ids) do
    for _, enemy in ipairs({ false, true }) do
      local tb = fresh()
      local user, target = tb.player, tb.enemy
      if enemy then user, target = tb.enemy, tb.player end
      local ok, err = pcall(tb.performMove, tb, user, target, { id = id, pp = 10 }, false)
      if not ok then failed = failed + 1; first = first or (id .. ": " .. tostring(err)) end
    end
  end
  T.check(#ids > 150, version .. ": " .. #ids .. " newer moves tried")
  T.eq(failed, 0, version .. ": every one runs in Red's battle" .. (first and (" -- " .. first) or ""))

  -- type matchups reach the damage: Night Slash on a Psychic Pokemon
  local tb = fresh("ABRA")
  tb.rng = function(a) return a end               -- the low roll: the move lands
  local hp = tb.enemy.mon.hp
  pcall(tb.performMove, tb, tb.player, tb.enemy, { id = "NIGHT_SLASH", pp = 10 }, false)
  local said = {}
  for _, row in ipairs(tb.queue) do if row.text then said[#said + 1] = row.text end end
  local super = table.concat(said, " "):find("super", 1, true) ~= nil
  T.check(tb.enemy.mon.hp < hp and super, version .. ": Night Slash is super effective on Abra")
  run.release()
end

local function gen2(version)
  local run = H.load(version)
  local data = run.data
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
    local battle = Battle.new({ data = data, party = { player }, wild = wild,
      save = { player = { id = 7, badges = {}, kantoBadges = {} } },
      random = function(n) return (n or 1) > 1 and 1 or 0 end })
    return battle
  end

  local ids = registered(data, "gen2")
  local failed, first = 0, nil
  for _, id in ipairs(ids) do
    for _, enemy in ipairs({ false, true }) do
      local battle = fresh()
      local user, target = battle.player, battle.enemy
      if enemy then user, target = battle.enemy, battle.player end
      local ok, err = pcall(battle.useMove, battle, user, target, id)
      if not ok then failed = failed + 1; first = first or (id .. ": " .. tostring(err)) end
    end
  end
  T.check(#ids > 150, version .. ": " .. #ids .. " newer moves tried")
  T.eq(failed, 0, version .. ": every one runs in Gold's battle" .. (first and (" -- " .. first) or ""))

  local battle = fresh("DRATINI")
  local hp = battle.enemy.hp
  local ok, err = pcall(battle.useMove, battle, battle.player, battle.enemy, "MOONBLAST")
  if not data.moves.MOONBLAST then
    ok, err = pcall(battle.useMove, battle, battle.player, battle.enemy, "DAZZLING_GLEAM")
  end
  T.check(ok and battle.enemy.hp < hp, version .. ": a Fairy move hurts Dratini (" .. tostring(err) .. ")")
  run.release()
end

for _, version in ipairs(H.versions()) do
  if H.GENERATION[version] == 1 then gen1(version) else gen2(version) end
end

T.finish("national_dex_gen3 Gen 1/2 battles")
