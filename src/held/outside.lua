-- What the held items do outside the moves on Red / Blue / Yellow and Gold / Silver / Crystal
-- (src/held/effects.lua is the battle's part; the Gen 3 games run these items' own hold effects):
--   exp.gain            the Lucky Egg on Red (x1.5; Gold has its own); the Macho Brace doubles the
--                       stat experience a win gives, a Power item adds 2,080 to its stat's (about
--                       today's 8 effort points; Power Lens and Band: the shared Special)
--   battle.exp_award    Red: a Pokemon holding an Exp. Share that did not fight gets half a share
--   happiness.changed   Gold: the Soothe Bell adds half again to a rise (Red's hidden friendship
--                       asks Outside.friendshipBoost, src/gen12/evolutions.lua)
--   encounter.roll      Pure Incense on the first healthy Pokemon: a third of the wild
--                       encounters do not happen
-- The Luck Incense (Gold's prize money) is src/held/effects.lua's, on switching in.

local Outside = {}

Outside.POWER_STAT = { POWER_WEIGHT = "hp", POWER_BRACER = "attack", POWER_BELT = "defense",
  POWER_LENS = "special", POWER_BAND = "special", POWER_ANKLET = "speed" }
Outside.POWER_GAIN = 2080

-- a party Pokemon's held item id (Red keeps it in the mod's bag on the mon, Gold on the mon)
function Outside.heldOf(gen, mon)
  if type(mon) ~= "table" then return nil end
  if gen == 1 then
    local bag = mon.extra and mon.extra.national_dex_gen3
    return bag and bag.item or nil
  end
  return mon.item
end

-- Red's friendship: a rise with a Soothe Bell held is half again (at least 1 more)
function Outside.friendshipBoost(mon, amount)
  if (amount or 0) > 0 and Outside.heldOf(1, mon) == "SOOTHE_BELL" then
    return amount + math.max(1, math.floor(amount / 2))
  end
  return amount
end

-- opts: { mod, generation, log }
function Outside.install(opts)
  local mod, gen = opts.mod, opts.generation
  local function held(mon) return Outside.heldOf(gen, mon) end
  local KEYS = { "hp", "attack", "defense", "speed", "special" }

  pcall(function()
    mod.hooks:wrap("exp.gain", function(nextFn, c)
      local gained = nextFn(c)
      local mon = type(c) == "table" and c.mon
      local id = held(mon)
      if not id then return gained end
      if gen == 1 and id == "LUCKY_EGG" and tonumber(gained) then gained = math.floor(gained * 1.5) end
      mon.statExp = mon.statExp or {}
      if id == "MACHO_BRACE" and c.defeatedDef and c.defeatedDef.baseStats then
        local share = math.max(1, tonumber(c.participants) or 1)
        local base = c.defeatedDef.baseStats
        for _, k in ipairs(KEYS) do
          local b = base[k] or (k == "special" and base.specialAttack) or 0
          mon.statExp[k] = math.min(65535, (mon.statExp[k] or 0) + math.floor(b / share))
        end
      end
      local stat = Outside.POWER_STAT[id]
      if stat then mon.statExp[stat] = math.min(65535, (mon.statExp[stat] or 0) + Outside.POWER_GAIN) end
      return gained
    end)
  end)

  if gen == 1 then
    pcall(function()
      mod.hooks:wrap("battle.exp_award", function(nextFn, ctx)
        local r = nextFn(ctx)
        local battle = type(ctx) == "table" and ctx.battle
        local party = battle and battle.game and battle.game.save and battle.game.save.party
        if type(party) ~= "table" or type(ctx.applyShare) ~= "function" then return r end
        local fought = {}
        for _, m in ipairs(ctx.alive or {}) do fought[m] = true end
        for _, m in ipairs(party) do
          if not fought[m] and (m.hp or 0) > 0 and held(m) == "EXP_SHARE" then
            pcall(ctx.applyShare, m, math.max(1, tonumber(ctx.participants) or 1) * 2, true)
          end
        end
        return r
      end)
    end)
  else
    mod.events:on("happiness.changed", function(ev)
      local mon = type(ev) == "table" and ev.mon
      if not mon or (tonumber(ev.delta) or 0) <= 0 or held(mon) ~= "SOOTHE_BELL" then return end
      mon.happiness = math.min(255, (mon.happiness or ev.to or 0) + math.max(1, math.floor(ev.delta / 2)))
    end)
  end

  -- Pure Incense: the first healthy Pokemon in the party keeps a third of the wild ones away
  pcall(function()
    mod.hooks:wrap("encounter.roll", function(nextFn, ...)
      local game = mod.game
      local save = game and game.save
      local party = save and save.party
      if type(party) == "table" then
        for _, m in ipairs(party) do
          if type(m) == "table" and (m.hp or 0) > 0 and not m.isEgg then
            if held(m) == "PURE_INCENSE" and love.math.random(3) == 1 then return nil end
            break
          end
        end
      end
      return nextFn(...)
    end)
  end)
  return true
end

return Outside
