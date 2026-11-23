-- Standalone: luajit mods/national_dex_gen3/tests/doubles_test.lua [game] (from the gen1recomp
-- root; needs that cart imported, FireRed by default).
--
-- Double battles: what reaches both foes, the partner or everyone around, through the battle
-- engine's own functions (whole moves through Engine.resolveMove, every roll at its low end: moves
-- hit, added effects happen, no critical hits, the damage roll at 100). Battler ids: 0 the player's
-- left, 1 the foe's left, 2 the player's right, 3 the foe's right.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"

local data = H.gen3Data(GAME)
H.useCart(GAME)
local Moves = require("src.core.game3.battle.moves")
data.gen3Moves = Moves
local ItemsData = require("src.core.game3.items_data")
data.gen3Items = ItemsData

local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
pcall(require("src.mods.Gen3Compat").applyMerged, { mods = run.loader, data = data })
run.loader.events:emit("game.ready", {})

local Adapter = require("src.core.game3.battle.adapter")
local Ab = require("src.core.game3.battle.abilities")
local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Battle = require("src.core.game3.battle")
Adapter.textSink = function(id) return id end

local byId = {}
for _, r in ipairs(dofile("mods/national_dex_gen3/data/moves.lua")) do byId[r.id] = r.index end
local held = {}
for _, r in ipairs(dofile("mods/national_dex_gen3/data/held_items.lua")) do held[r.id] = r.index end
local TACKLE, GROWL, WATER_GUN, HYPNOSIS, TOXIC, TAUNT, SWORDS_DANCE, THUNDERBOLT = 33, 45, 55, 95, 92, 269, 14, 85
local BULBASAUR, PIDGEY, RATTATA, SQUIRTLE, GEODUDE = 1, 16, 19, 7, 74

local function mon(species, extra)
  local m = { species = species or 25, level = 50, hp = 150, maxHp = 150, moves = { TACKLE }, pp = { 35 },
              attack = 100, defense = 100, spAtk = 100, spDef = 100, speed = 100, personality = 0 }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end
-- a double battle: me / ally against foe / foe2; `said` collects every line
local function doubles(me, ally, foe, foe2)
  local said = {}
  local st = State.new({ wild = false, double = true, playerParty = { me or mon(), ally or mon() },
                         foeParty = { foe or mon(PIDGEY), foe2 or mon(RATTATA) } })
  assert(st.double and st.battlers[3], "a headless doubles state")
  st.turn = 3
  st.rng = function(lo, hi) if lo == 85 or lo == 0 then return hi end return lo end
  local ad = Adapter.new(st, function() end)
  ad.roll = function(_, lo) return lo end
  -- every line said through the adapter (a move's own lines go to its output, not the sink)
  local say = ad.say
  ad.say = function(self, text, ...) said[#said + 1] = tostring(text) return say(self, text, ...) end
  Battle._adapter = ad
  local b = st.battlers
  return st, ad, b[0], b[2], b[1], b[3], said
end
local function use(st, ad, user, target, id)
  return Engine.resolveMove(user, target, id, 1, ad, st, {})
end
local function heard(said, pattern)
  local n = 0
  for _, s in ipairs(said) do if s:gsub("\n", " "):find(pattern) then n = n + 1 end end
  return n
end

-- ------- entering battle: every foe
do
  local st, ad, me, _, foe, foe2 = doubles(mon(25, { ability = "SUPERSWEET_SYRUP" }))
  Ab.switchIn(ad, me)
  T.check(foe.stages.evasion == -1 and foe2.stages.evasion == -1, "SUPERSWEET_SYRUP: both foes' evasion falls")
end
do
  -- one foe alone would say Sp. Atk (its Sp. Def is the lower); the two together say Attack
  local st, ad, me = doubles(mon(25, { ability = "DOWNLOAD" }), nil,
    mon(PIDGEY, { defense = 200, spDef = 50 }), mon(RATTATA, { defense = 50, spDef = 250 }))
  Ab.switchIn(ad, me)
  T.check(me.stages.attack == 1 and (me.stages.spAtk or 0) == 0, "DOWNLOAD: the foes' Defense and Sp. Def added up")
end
do
  local st, ad, me, _, _, _, said = doubles(mon(25, { ability = "FOREWARN" }), nil,
    mon(PIDGEY, { moves = { TACKLE } }), mon(RATTATA, { moves = { THUNDERBOLT } }))
  Ab.switchIn(ad, me)
  T.eq(heard(said, "FOREWARN alerted it to THUNDERBOLT"), 1, "FOREWARN: the strongest move of either foe")
end
do
  local st, ad, me, _, _, _, said = doubles(mon(SQUIRTLE, { ability = "ANTICIPATION" }), nil,
    mon(PIDGEY, { moves = { TACKLE } }), mon(RATTATA, { moves = { THUNDERBOLT } }))
  Ab.switchIn(ad, me)
  T.eq(heard(said, "shuddered"), 1, "ANTICIPATION: the second foe's move makes it shudder")
end
do
  local displayName = ItemsData.displayName
  ItemsData.displayName = function(i) return "ITEM" .. tostring(i) end   -- headless has no names
  local st, ad, me, _, foe, foe2, said = doubles(mon(25, { ability = "FRISK" }))
  foe.mon.item, foe2.mon.item = 1, 2
  Ab.switchIn(ad, me)
  ItemsData.displayName = displayName
  T.eq(heard(said, "frisked"), 2, "FRISK: both foes' items")
  T.check(heard(said, "ITEM2") == 1, "FRISK: the second foe's item named")
end
do
  local st, ad, me, ally = doubles(mon(25, { ability = "PASTEL_VEIL" }), mon(25, { status = "PSN" }))
  ally.mon.status = "PSN"
  Ab.switchIn(ad, me)
  T.check(ad:status(ally) == nil, "PASTEL_VEIL: a poisoned partner is cured as it comes in")
end

-- ------- the partner covered
do
  local st, ad, me, ally, foe = doubles(mon(25, { ability = "SWEET_VEIL" }))
  use(st, ad, foe, ally, HYPNOSIS)
  T.check(ad:status(ally) ~= "SLP", "SWEET_VEIL: its partner can't fall asleep")
  local st2, ad2, _, ally2, foe2 = doubles()
  use(st2, ad2, foe2, ally2, HYPNOSIS)
  T.eq(ad2:status(ally2), "SLP", "Hypnosis puts a Pokemon to sleep (control)")
end
do
  local st, ad, me, ally, foe = doubles(mon(25, { ability = "FLOWER_VEIL" }), mon(BULBASAUR))
  use(st, ad, foe, me, GROWL)
  T.check((ally.stages.attack or 0) == 0, "FLOWER_VEIL: its Grass-type partner's ATTACK holds")
  T.eq(me.stages.attack, -1, "FLOWER_VEIL: the holder itself is not Grass (falls)")
end
do
  local st, ad, me, ally, foe = doubles(mon(25, { ability = "PASTEL_VEIL" }))
  use(st, ad, foe, ally, TOXIC)
  T.check(ad:status(ally) == nil, "PASTEL_VEIL: its partner can't be poisoned")
end
do
  local st, ad, me, ally, foe, _, said = doubles(mon(25, { ability = "AROMA_VEIL" }))
  use(st, ad, foe, ally, TAUNT)
  T.eq(heard(said, "aromatic veil"), 1, "AROMA_VEIL: Taunt on its partner fails")
end
do
  local function tackle(partnerAbility)
    local st, ad, me, ally, foe = doubles(mon(25, { ability = partnerAbility }))
    st.weather, st.weatherTurns = "SUN", 5
    local hp = ad:hp(foe)
    use(st, ad, ally, foe, TACKLE)
    return hp - ad:hp(foe)
  end
  local plain, gift = tackle(nil), tackle("FLOWER_GIFT")
  T.check(plain > 0 and gift > plain * 1.4, "FLOWER_GIFT: its partner's ATTACK in the sun (" .. plain .. " -> " .. gift .. ")")
end

-- ------- everyone around
do
  local st, ad, me, ally, foe, foe2 = doubles(nil, nil, mon(PIDGEY, { ability = "COTTON_DOWN" }))
  use(st, ad, me, foe, TACKLE)
  T.check(me.stages.speed == -1 and ally.stages.speed == -1 and foe2.stages.speed == -1,
    "COTTON_DOWN: every other Pokemon's SPEED falls, its own partner's too")
  T.check((foe.stages.speed or 0) == 0, "COTTON_DOWN: not its own")
end

-- ------- moves
do
  local st, ad, me, ally, foe, foe2 = doubles()
  use(st, ad, me, foe, byId.MIND_BLOWN)
  T.eq(ad:hp(me), 75, "MIND_BLOWN: half its HP once, though it hits all three")
  T.check(ad:hp(foe) < 150 and ad:hp(foe2) < 150 and ad:hp(ally) < 150, "MIND_BLOWN: hits everyone around it")
end
do
  local st, ad, me, ally = doubles(mon(25, { hp = 100 }), mon(25, { hp = 100 }))
  use(st, ad, me, me, byId.LIFE_DEW)
  T.check(ad:hp(me) == 137 and ad:hp(ally) == 137, "LIFE_DEW: the user and its partner get a quarter back")
end
do
  local st, ad, me, _, foe, foe2 = doubles()
  use(st, ad, me, foe, byId.MATCHA_GOTCHA)
  T.check(ad:hp(foe) < 150 and ad:hp(foe2) < 150, "MATCHA_GOTCHA: both foes")
end
do
  local st, ad, me, _, foe, foe2 = doubles()
  use(st, ad, me, foe, byId.EXPANDING_FORCE)
  T.check(ad:hp(foe) < 150 and ad:hp(foe2) == 150, "EXPANDING_FORCE: one foe off Psychic Terrain")
  local st2, ad2, me2, _, f1, f2 = doubles()
  st2.__ndxField = { terrain = "PSYCHIC", terrainTurns = 3 }
  use(st2, ad2, me2, f1, byId.EXPANDING_FORCE)
  T.check(ad2:hp(f1) < 150 and ad2:hp(f2) < 150, "EXPANDING_FORCE: both foes on Psychic Terrain")
end
do
  local st, ad, me, ally, foe = doubles(nil, mon(25, { ability = "STORM_DRAIN" }))
  use(st, ad, foe, me, WATER_GUN)
  T.eq(ad:hp(me), 150, "STORM_DRAIN: a Water move at its partner is drawn away")
  T.eq(ally.stages.spAtk, 1, "STORM_DRAIN: and raises its SP. ATK")
  local st2, ad2, me2, ally2, f2 = doubles(nil, mon(25, { ability = "STORM_DRAIN" }))
  use(st2, ad2, f2, me2, TACKLE)
  T.check(ad2:hp(me2) < 150, "STORM_DRAIN: other types are not drawn")
end

-- ------- held items
do
  local st, ad, me, _, foe, foe2 = doubles(mon(25, { ability = "INTIMIDATE" }))
  foe.item, foe2.item = held.ADRENALINE_ORB, held.ADRENALINE_ORB
  foe.mon.item, foe2.mon.item = held.ADRENALINE_ORB, held.ADRENALINE_ORB
  pcall(Engine.switchInEffects, st, ad, me, {})
  T.check(foe.stages.speed == 1 and foe2.stages.speed == 1, "ADRENALINE_ORB: both foes' Orbs answer one Intimidate")
end
do
  local st, ad, me, _, foe, foe2 = doubles()
  foe2.item, foe2.mon.item = held.MIRROR_HERB, held.MIRROR_HERB
  use(st, ad, me, me, SWORDS_DANCE)
  T.eq(foe2.stages.attack, 2, "MIRROR_HERB: the foe on the far side copies the boost")
end

-- ------- a single battle is as before
do
  local st = State.new({ wild = true, playerParty = { mon(25, { ability = "SUPERSWEET_SYRUP" }) }, foeMon = mon(PIDGEY) })
  local ad = Adapter.new(st, function() end)
  ad.roll = function(_, lo) return lo end
  Battle._adapter = ad
  Ab.switchIn(ad, st.player)
  T.eq(st.enemy.stages.evasion, -1, "singles: SUPERSWEET_SYRUP still lowers the one foe")
end

run.release()
T.finish("national_dex_gen3 double battles (" .. GAME .. ")")
