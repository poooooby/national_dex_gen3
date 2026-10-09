-- Counters kept on a party Pokemon for the evolutions that ask for something it has done
-- (src/conditional_evos.lua reads them as `when` conditions):
--
--   recoilTaken  the recoil damage it has taken in battle, in total (Basculin: 294)
--   moveUses     how often it has used a move (Primeape: Rage 20 times, for Rage Fist)
--   stepsAsLead  steps walked while it was first in the party (Pawmo, Bramblin, Rellor: 1000)
--
-- plus the Coin Case coins Gimmighoul spends when it evolves.
--
-- The engine tells mods nothing about recoil, but it does emit the damage of every hit
-- ("battle.damage_dealt"), and a recoil move's recoil is a fixed share of that: a quarter
-- for the Take Down family (ROM effect 48), a third for Volt Tackle's (198), at least 1.
-- Rock Head takes none. Moves come from "battle.move_used", steps from "world.stepped".
-- The totals live on the party Pokemon itself, so they are saved with it.
--
-- The end-of-battle evolution scan only looks at Pokemon that gained a level, so a Pokemon
-- whose counter is met is marked for it (Battle._mergeLeveledSet), at the moment it is met
-- or, for steps walked outside battle, on the next turn of the next battle.

local Counters = {}

local ROCK_HEAD = 69          -- the cart's own ability id
local SHARE = { [48] = 4, RECOIL = 4, RECOIL_25 = 4, [198] = 3, RECOIL_33 = 3 }

-- how much recoil one hit's damage causes with this move (0 for a move without)
function Counters.recoil(effect, damage)
  local share = SHARE[effect]
  if not share then return 0 end
  return math.max(1, math.floor((tonumber(damage) or 0) / share))
end

-- Is every counter this Pokemon's evolution asks for met?
-- need: { recoil = n, uses = { move, count }, steps = n }
function Counters.met(mon, need)
  if type(mon) ~= "table" or type(need) ~= "table" then return false end
  if need.recoil and (tonumber(mon.recoilTaken) or 0) < need.recoil then return false end
  if need.uses then
    local uses = type(mon.moveUses) == "table" and mon.moveUses or {}
    if (tonumber(uses[need.uses.move]) or 0) < need.uses.count then return false end
  end
  if need.steps and (tonumber(mon.stepsAsLead) or 0) < need.steps then return false end
  return true
end

-- needs: { [species slot] = { recoil?, uses?, steps?, coins? } }, from the evolution steps
function Counters.install(mod, needs)
  if next(needs) == nil then return end
  local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
  if not okP then return end

  local function mark(partyIndex)
    local okB, Battle = pcall(require, "src.core.game3.battle")
    if okB and type(Battle) == "table" and Battle._mergeLeveledSet then
      Battle._mergeLeveledSet({ [partyIndex] = true })
    end
  end

  -- the party Pokemon behind a battler of ours, with the need its species has
  local function ours(ev)
    local user, st = ev and ev.user, ev and ev.battle
    if type(user) ~= "table" or user.side ~= "player" or type(st) ~= "table" then return end
    local mon = type(st.playerParty) == "table" and st.playerParty[user.partyIndex or 0] or nil
    if type(mon) ~= "table" then return end
    local slot = Pokemon.speciesOf(mon)
    return mon, slot and needs[slot], user.partyIndex, slot
  end

  mod.events:on("battle.damage_dealt", function(ev)
    local mon, need, index, slot = ours(ev)
    if not (need and need.recoil) then return end
    local recoil = Counters.recoil(ev.move and ev.move.effect, ev.damage)
    if recoil == 0 then return end
    if Pokemon.abilityId and Pokemon.abilityId(slot, tonumber(mon.personality) or 0) == ROCK_HEAD then return end
    mon.recoilTaken = (tonumber(mon.recoilTaken) or 0) + recoil
    if Counters.met(mon, need) then mark(index) end
  end)

  mod.events:on("battle.move_used", function(ev)
    local mon, need, index = ours(ev)
    if not (need and need.uses) or ev.isCalled or tonumber(ev.moveNum) ~= need.uses.move then return end
    mon.moveUses = type(mon.moveUses) == "table" and mon.moveUses or {}
    mon.moveUses[need.uses.move] = (tonumber(mon.moveUses[need.uses.move]) or 0) + 1
    if Counters.met(mon, need) then mark(index) end
  end)

  -- steps walked while it is first in the party (it follows you)
  mod.events:on("world.stepped", function()
    local session = mod.game and mod.game.session
    local lead = type(session) == "table" and type(session.party) == "table" and session.party[1]
    if type(lead) ~= "table" then return end
    local slot = Pokemon.speciesOf(lead)
    local need = slot and needs[slot]
    if need and need.steps then lead.stepsAsLead = (tonumber(lead.stepsAsLead) or 0) + 1 end
  end)

  -- a counter met outside battle (steps) joins the end-of-battle scan on the next turn
  mod.events:on("battle.turn_started", function(ev)
    local party = ev and ev.battle and ev.battle.playerParty
    if type(party) ~= "table" then return end
    for index, mon in ipairs(party) do
      local slot = type(mon) == "table" and Pokemon.speciesOf(mon)
      local need = slot and needs[slot]
      if need and (need.steps or need.uses or need.recoil) and Counters.met(mon, need) then
        mark(index)
      end
    end
  end)

  -- the coins an evolution asked for are spent when it happens
  mod.events:on("pokemon.evolved", function(ev)
    local need = ev and needs[tonumber(ev.fromSpeciesId) or -1]
    if not (need and need.coins) then return end
    local session = mod.game and mod.game.session
    local okB, Bag = pcall(require, "src.core.game3.bag")
    if type(session) == "table" and okB and Bag.Coins then
      Bag.Coins.set(session, Bag.Coins.get(session) - need.coins)
    end
  end)
end

return Counters
