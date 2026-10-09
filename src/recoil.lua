-- Counts the recoil damage a Pokemon takes in battle, for the evolutions that ask for it
-- (Basculin, white-striped, after 294: `when.recoil` in src/conditional_evos.lua).
--
-- The engine applies recoil inside the move (src/core/game3/battle/effects/secondary.lua) and
-- tells mods nothing about it, but it does tell them how much damage every hit did
-- ("battle.damage_dealt"), and a recoil move's recoil is a fixed share of that: a quarter
-- for the Take Down family (ROM effect 48), a third for Volt Tackle's (198), at least 1.
-- Rock Head takes none. The total is kept on the party Pokemon itself (`recoilTaken`), so it
-- is saved with it, and carries from battle to battle.
--
-- A Pokemon whose total is reached during a battle is marked for the end-of-battle
-- evolution scan, which otherwise only looks at those that gained a level.

local Recoil = {}

local ROCK_HEAD = 69          -- the cart's own ability id
local SHARE = { [48] = 4, RECOIL = 4, RECOIL_25 = 4, [198] = 3, RECOIL_33 = 3 }

-- how much recoil one hit's damage causes with this move (0 for a move without)
function Recoil.of(effect, damage)
  local share = SHARE[effect]
  if not share then return 0 end
  return math.max(1, math.floor((tonumber(damage) or 0) / share))
end

-- species: { [slot] = recoil total that evolves it } for the species the evolution asks about
function Recoil.install(mod, species)
  if next(species) == nil then return end
  local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
  if not okP then return end
  mod.events:on("battle.damage_dealt", function(ev)
    local user, st = ev and ev.user, ev and ev.battle
    if type(user) ~= "table" or user.side ~= "player" or type(st) ~= "table" then return end
    local party = st.playerParty
    local mon = type(party) == "table" and party[user.partyIndex or 0] or nil
    if type(mon) ~= "table" then return end
    local slot = Pokemon.speciesOf(mon)
    local needed = slot and species[slot]
    if not needed then return end
    local effect = ev.move and ev.move.effect
    local recoil = Recoil.of(effect, ev.damage)
    if recoil == 0 then return end
    if Pokemon.abilityId and Pokemon.abilityId(slot, tonumber(mon.personality) or 0) == ROCK_HEAD then return end
    mon.recoilTaken = (tonumber(mon.recoilTaken) or 0) + recoil
    if mon.recoilTaken >= needed then
      local okB, Battle = pcall(require, "src.core.game3.battle")
      if okB and type(Battle) == "table" and Battle._mergeLeveledSet then
        Battle._mergeLeveledSet({ [user.partyIndex] = true })
      end
    end
  end)
end

return Recoil
