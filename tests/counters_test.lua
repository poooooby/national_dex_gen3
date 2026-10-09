-- Standalone: luajit mods/national_dex_gen3/tests/counters_test.lua (from the gen1recomp
-- root; needs Pokemon FireRed imported under firered/).
--
-- The counters a few evolutions ask for (src/counters.lua): Rage used 20 times (Primeape),
-- 1000 steps walked while first in the party (Pawmo, Bramblin, Rellor), the coins Gimmighoul
-- spends, and a bred Manaphy laying a Phione egg (src/breeding.lua).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")

local data = H.gen3Data()
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.events:emit("game.ready", {})

local api = run.loader.exports.national_dex_gen3
local Evolution = require("src.core.game3.evolution")
local Pokemon = require("src.core.game3.pokemon")
local Battle = require("src.core.game3.battle")
Evolution.nationalAllows = function() return true end

local function slot(name) return api.slotOf(name) or Pokemon.speciesFromName(name) end
local function emit(name, payload) run.loader.events:emit(name, payload) end

-- ------- Rage x 20 (Primeape -> Annihilape)

local primeape = { species = slot("PRIMEAPE"), level = 40, personality = 0, moves = { 99 } }
local party = { primeape }
local st = { playerParty = party }
Battle._leveledUp = {}
local function rage(n, move)
  for _ = 1, n do
    emit("battle.move_used", { battle = st, user = { side = "player", partyIndex = 1 },
      moveNum = move or 99, isCalled = false })
  end
end
rage(19)
T.eq(primeape.moveUses and primeape.moveUses[99], 19, "19 uses of Rage are counted")
T.eq(Evolution.levelTarget(primeape, {}), nil, "19 is not enough")
T.check(not Battle._leveledUp[1], "and it is not yet marked for the end-of-battle scan")
rage(1)
T.eq(Evolution.levelTarget(primeape, {}), slot("ANNIHILAPE"), "the 20th use lets it evolve")
T.check(Battle._leveledUp[1] == true, "and marks it for the end-of-battle scan")
rage(3, 33)
T.eq(primeape.moveUses[99], 20, "another move is not counted")
emit("battle.move_used", { battle = st, user = { side = "enemy", partyIndex = 1 }, moveNum = 99 })
T.eq(primeape.moveUses[99], 20, "nor is the enemy's Rage")
emit("battle.move_used", { battle = st, user = { side = "player", partyIndex = 1 }, moveNum = 99, isCalled = true })
T.eq(primeape.moveUses[99], 20, "nor a move called by another (Metronome)")
Battle._leveledUp = nil

-- ------- 1000 steps as the lead (Pawmo, Bramblin, Rellor)

local pawmo = { species = slot("PAWMO"), level = 20, personality = 0 }
local other = { species = slot("PIKACHU"), level = 20, personality = 0 }
run.loader.game = { session = { party = { pawmo, other }, coins = 0 } }
for _ = 1, 999 do emit("world.stepped", {}) end
T.eq(pawmo.stepsAsLead, 999, "999 steps counted for the lead")
T.eq(Evolution.levelTarget(pawmo, {}), nil, "999 steps is not enough")
emit("world.stepped", {})
T.eq(Evolution.levelTarget(pawmo, {}), slot("PAWMOT"), "the 1000th step lets it evolve")
T.eq(other.stepsAsLead, nil, "a Pokemon not in front is not counted")

-- a counter met outside battle joins the end-of-battle scan on the next turn
Battle._leveledUp = {}
emit("battle.turn_started", { battle = { playerParty = { other, pawmo } }, turn = 1 })
T.check(Battle._leveledUp[2] == true, "a met step counter marks the Pokemon for the scan on the next turn")
T.check(not Battle._leveledUp[1], "and only that one")
Battle._leveledUp = nil

-- lead swap: a Pokemon that is not first stops counting
run.loader.game.session.party = { other, pawmo }
emit("world.stepped", {})
T.eq(pawmo.stepsAsLead, 1000, "behind the lead it stops")

-- ------- 999 coins (Gimmighoul -> Gholdengo)

local gimmighoul = { species = slot("GIMMIGHOUL"), level = 20, personality = 0 }
local session = { party = { gimmighoul }, coins = 998 }
T.eq(Evolution.levelTarget(gimmighoul, session), nil, "998 coins is not enough")
session.coins = 1500
T.eq(Evolution.levelTarget(gimmighoul, session), slot("GHOLDENGO"), "999 or more is")
run.loader.game = { session = session }
emit("pokemon.evolved", { mon = gimmighoul, fromSpeciesId = slot("GIMMIGHOUL"), toSpeciesId = slot("GHOLDENGO") })
T.eq(session.coins, 501, "evolving spends 999 coins")
emit("pokemon.evolved", { mon = primeape, fromSpeciesId = slot("PRIMEAPE"), toSpeciesId = slot("ANNIHILAPE") })
T.eq(session.coins, 501, "another species spends none")

-- ------- Manaphy lays Phione (breeding)

local Breeding = require("src.core.game3.breeding")
local manaphy, phione = slot("MANAPHY"), slot("PHIONE")
T.check(manaphy and phione, "Manaphy and Phione are registered")
T.eq(Breeding.eggSpecies(manaphy), phione, "a Manaphy lays a Phione egg")
T.eq(Breeding.eggSpecies(phione), phione, "Phione lays itself")
T.eq(Breeding.eggSpecies(Pokemon.speciesFromName("PIKACHU")), Pokemon.speciesFromName("PICHU"),
     "other species are untouched (Pikachu lays Pichu)")
T.eq(Breeding.eggSpecies(Pokemon.speciesFromName("DITTO")), Pokemon.speciesFromName("DITTO"), "Ditto is untouched")
T.eq(#(data.gen3Pokemon._evolutions[phione] or {}), 0, "and Phione has no evolution")

T.finish("national_dex_gen3 counters")
