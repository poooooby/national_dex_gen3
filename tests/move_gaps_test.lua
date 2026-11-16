-- Standalone: luajit mods/national_dex_gen3/tests/move_gaps_test.lua [game] (from the gen1recomp
-- root; needs that cart imported, FireRed by default).
--
-- The newer moves, abilities and held items on FireRed to Emerald, each run as a whole move
-- through the engine (Engine.resolveMove: the real accuracy check, hit, added effects and the
-- battle's own text), where the other suites stand the hit in: the gaps an audit found
-- (2026-11-16) stay fixed.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"

local data = H.gen3Data(GAME)
H.useCart(GAME)
local Moves = require("src.core.game3.battle.moves")
data.gen3Moves = Moves
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
pcall(require("src.mods.Gen3Compat").applyMerged, { mods = run.loader, data = data })
run.loader.events:emit("game.ready", {})

local Adapter = require("src.core.game3.battle.adapter")
local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Residuals = require("src.core.game3.battle.residuals")
local Battle = require("src.core.game3.battle")
-- the battle's text by key (headless Ruby lacks some of the cart's strings); a missing key stops
-- the battle, as the real lookup does
Adapter.textSink = function(id)
  assert(id ~= nil, "no message for a nil text id")
  return id
end

local byId = {}
for _, r in ipairs(dofile("mods/national_dex_gen3/data/moves.lua")) do byId[r.id] = r end
local function num(id) return type(id) == "number" and id or byId[id].index end

local function mon(extra)
  local m = { species = 25, level = 50, hp = 300, maxHp = 300, moves = { 33 }, pp = { 35 },
              attack = 100, defense = 100, spAtk = 100, spDef = 100, speed = 100, personality = 0 }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end
-- a wild battle; rolls in the middle of their range (hits land, 100% effects happen, chances
-- under 50% do not)
local function battle(opts)
  opts = opts or {}
  local st = State.new({ wild = true, playerParty = opts.party or { mon() }, foeMon = opts.foe or mon() })
  st.turn = 3
  local ad = Adapter.new(st, function() end)
  ad.roll = opts.roll or function(_, lo, hi) return math.floor((lo + (hi or lo)) / 2) end
  Battle._adapter = ad
  local said = {}
  local say = ad.say
  ad.say = function(self, s, ...) said[#said + 1] = tostring(s); return say(self, s, ...) end
  return st, ad, said
end
-- the player's Pokemon uses `id` on the foe (or `user` on `target`); nil, or the error
local function use(st, ad, id, user, target)
  local ok, err = pcall(Engine.resolveMove, user or st.player, target or st.enemy, num(id), 1, ad, st, {}, {})
  return not ok and tostring(err) or nil
end

-- ------- the newer binding moves: trapped, with their own message (the cart had no text for them)
for _, id in ipairs({ "INFESTATION", "SNAP_TRAP", "THUNDER_CAGE", "MAGMA_STORM" }) do
  local st, ad = battle()
  T.eq(use(st, ad, id), nil, id .. " runs to the end")
  T.check((st.enemy.expTrapTurns or 0) > 0, id .. " traps the foe")
end

-- ------- moves that can't miss (accuracy 0): the engine read it as a 0% chance
do
  local st, ad = battle()
  use(st, ad, "PLAY_NICE")
  T.eq(st.enemy.stages.attack, -1, "Play Nice lands")
  local st2, ad2 = battle()
  use(st2, ad2, "DEFOG")
  T.eq(st2.enemy.stages.evasion, -1, "Defog lands")
end

-- ------- abilities that guard their holder only against moves aimed at it
local function withAbility(ad, b, name)
  local of = ad.abilityOf
  ad.abilityOf = function(self, x) if x == b then return name end return of(self, x) end
end
do
  local st, ad = battle()
  withAbility(ad, st.player, "GOOD_AS_GOLD")
  use(st, ad, 14, st.enemy, st.player)                                   -- the foe's SWORDS DANCE
  T.eq(st.enemy.stages.attack, 2, "Good as Gold lets the foe's Swords Dance work")
  use(st, ad, 45, st.enemy, st.player)                                   -- GROWL at it
  T.eq(st.player.stages.attack, 0, "but blocks Growl")
  local st2, ad2 = battle()
  withAbility(ad2, st2.player, "QUEENLY_MAJESTY")
  use(st2, ad2, 182, st2.enemy, st2.player)                              -- the foe's PROTECT
  T.check(st2.enemy.expProtected, "Queenly Majesty lets the foe's Protect work")
  local hp = st2.player.mon.hp
  use(st2, ad2, 98, st2.enemy, st2.player)                               -- QUICK ATTACK at it
  T.eq(st2.player.mon.hp, hp, "but blocks Quick Attack")
end

T.finish("national_dex_gen3 move gaps (" .. GAME .. ")")
