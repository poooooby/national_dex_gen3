-- Standalone: luajit mods/national_dex_gen3/tests/move_split_test.lua [game] (from the gen1recomp
-- root; needs that cart imported, FireRed by default).
--
-- The Move Split option on FireRed to Emerald (src/move_split.lua): off, a move's type decides
-- physical or special as Gen 3 does; on, the move itself does (data/move_split.lua), in the
-- damage formula, burn, the hit's bookkeeping for Counter / Mirror Coat, and nowhere else.
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
run.loader.modOptions.national_dex_gen3 = {}
pcall(require("src.mods.Gen3Compat").applyMerged, { mods = run.loader, data = data })
run.loader.events:emit("game.ready", {})

local Adapter = require("src.core.game3.battle.adapter")
local State = require("src.core.game3.battle.state")
local Damage = require("src.core.game3.battle.damage")
local Types = require("src.core.game3.battle.types")
local Hit = require("src.core.game3.battle.effects.hit")
Adapter.textSink = function(id) return id end

local function setOption(on)
  run.loader.modOptions.national_dex_gen3.move_split = on
  run.loader.events:emit("mod.options_changed", { mod = "national_dex_gen3", key = "move_split", value = on })
end

local byId = {}
for _, r in ipairs(dofile("mods/national_dex_gen3/data/moves.lua")) do byId[r.id] = r end
local SHADOW_BALL, CRUNCH, THUNDERBOLT, FIRE_PUNCH, SHADOW_CLAW, MOONBLAST =
  247, 242, 85, 7, byId.SHADOW_CLAW.index, byId.MOONBLAST.index

-- a strong attacker with a weak special side, against a plain foe
local function mon(extra)
  local m = { species = 25, level = 50, hp = 150, maxHp = 150, moves = { 33 }, pp = { 35 },
              attack = 200, defense = 100, spAtk = 50, spDef = 100, speed = 100, personality = 0 }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end
local function battle(p)
  local st = State.new({ wild = true, playerParty = { p or mon() }, foeMon = mon({ species = 1, attack = 100, spAtk = 100 }) })
  st.turn = 3
  local ad = Adapter.new(st, function() end)
  ad.roll = function(_, lo) return lo end
  return st, ad
end
local function dmg(num, p)
  local st, ad = battle(p)
  local d, info = Damage.calc(st.player, st.enemy, Moves.get(num),
    { adapter = ad, noRandom = true, forceCrit = false })
  return d, info
end

local GHOST, DARK = Types.ID.GHOST, Types.ID.DARK
T.check(Types.isPhysical(GHOST) and not Types.isPhysical(DARK), "Gen 3: Ghost is a physical type, Dark special")

-- off (the default): by type
local offSB = dmg(SHADOW_BALL)
local offCr = dmg(CRUNCH)
local offTb = dmg(THUNDERBOLT)
local offSC = dmg(SHADOW_CLAW)
local offMB = dmg(MOONBLAST)
local offFP = dmg(FIRE_PUNCH)

setOption(true)
local onSB, infoSB = dmg(SHADOW_BALL)
local onCr, infoCr = dmg(CRUNCH)
local onTb = dmg(THUNDERBOLT)
local onSC = dmg(SHADOW_CLAW)
local onMB = dmg(MOONBLAST)
local onFP = dmg(FIRE_PUNCH)
T.check(onSB < offSB, ("Shadow Ball turns special: it reads the weak Sp. Atk (%d -> %d)"):format(offSB, onSB))
T.eq(infoSB and infoSB.physical, false, "and the hit is reported special")
T.check(onCr > offCr, ("Crunch turns physical: it reads the strong Attack (%d -> %d)"):format(offCr, onCr))
T.eq(infoCr and infoCr.physical, true, "and the hit is reported physical")
T.check(onFP > offFP, ("Fire Punch turns physical (%d -> %d)"):format(offFP, onFP))
T.eq(onTb, offTb, "Thunderbolt is special either way")
T.eq(onSC, offSC, "Shadow Claw is physical either way")
T.check(onMB <= offMB or onMB == offMB, "Moonblast is special")

-- this mod's stat-swap moves still read the right stats once the split decides their class
do
  local function with(num, user, foe)
    local st, ad = battle(mon(user))
    for k, v in pairs(foe or {}) do st.enemy.mon[k] = v end
    return (Damage.calc(st.player, st.enemy, Moves.get(num), { adapter = ad, noRandom = true, forceCrit = false }))
  end
  local BODY_PRESS, PSYSHOCK, FOUL_PLAY = byId.BODY_PRESS.index, byId.PSYSHOCK.index, byId.FOUL_PLAY.index
  T.check(with(BODY_PRESS, { defense = 250 }) > with(BODY_PRESS, { defense = 60 }),
    "Body Press (physical) hits with the user's Defense")
  T.check(with(PSYSHOCK, nil, { defense = 40 }) > with(PSYSHOCK, nil, { defense = 250 }),
    "Psyshock (special) hits the foe's Defense")
  T.check(with(FOUL_PLAY, nil, { attack = 250 }) > with(FOUL_PLAY, nil, { attack = 60 }),
    "Foul Play (physical) hits with the foe's Attack")
end

-- burn halves a physical hit: Crunch is now one
local burnedCr = dmg(CRUNCH, mon({ status = "BRN" }))
T.check(burnedCr < onCr, "a burned Pokemon's Crunch is halved once it is physical")

-- outside a move the game's own answer stands
T.check(Types.isPhysical(GHOST) and not Types.isPhysical(DARK), "outside a move: still by type")

-- the hit's bookkeeping: Counter answers a physical Crunch
do
  local st, ad = battle()
  local M = { adapter = ad, user = st.player, target = st.enemy, mnum = CRUNCH, move = Moves.get(CRUNCH),
              moveType = DARK, st = st, anim = { hits = {} } }
  Hit.dealDamage(M, 10, { physical = false })
  T.eq(st.enemy.lastPhysicalDamageTaken, 10, "a Crunch hit is recorded as physical (Counter answers it)")
  T.check((st.enemy.lastSpecialDamageTaken or 0) == 0, "not as special (Mirror Coat doesn't)")
end

-- a move paused mid-way (a coroutine) doesn't leak its answer to anything else
do
  local hub = Types.__ndxSplit
  local co = coroutine.create(function()
    hub.within(SHADOW_BALL, function()
      assert(Types.isPhysical(GHOST) == false)
      coroutine.yield()
    end)
  end)
  coroutine.resume(co)
  T.check(coroutine.status(co) == "suspended", "the move is paused inside")
  T.check(Types.isPhysical(GHOST), "and outside it Ghost is still physical")
end

setOption(false)
T.eq(dmg(SHADOW_BALL), offSB, "off again: by type")
T.eq(dmg(CRUNCH), offCr, "Crunch too")

run.release()
T.finish("national_dex_gen3 move split (" .. GAME .. ")")
