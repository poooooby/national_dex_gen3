-- What the summary screens show of the parity systems (src/gen12/mech/traits.lua, abilities.lua,
-- held_red.lua):
--   Red   a third page after the moves: the first page's header (picture, name, level, HP),
--         then NATURE, ABILITY, ITEM (held) and gender in place of the stats box. A and B step
--         through it as through the other two (SummaryMenu.update / draw wrapped once a process).
--   Gold  the nature and ability under OT on the third page (the stats page), whose left column
--         has four free rows (SummaryMenu.drawPanel wrapped once a process).

local Summary = {}

-- opts: { require, generation, core, data = fn() -> game data }
function Summary.install(opts)
  local require, gen, core = opts.require, opts.generation, opts.core
  local Font = require("src.render.Font")
  local Strings = require("src.core.Strings")
  local function natureOf(mon) return core.traits and core.traits.nature(mon.dvs or {}) or nil end
  local function abilityOf(data, mon)
    local id = core.abilityForMon and core.abilityForMon(data.pokemon[mon.species], mon.dvs or {})
    return id and core.abilityName(id) or nil
  end
  local function genderOf(data, mon)
    if not core.traits then return nil end
    local r = data.pokemon[mon.species]
    local dex = r and (r.baseDex or r.dex)
    local rates = core.facts and core.facts.genderRates
    local rate = dex and rates and rates[dex]
    if r and r.genderRatio then
      return core.traits.gender(r.genderRatio, mon.dvs or {})
    end
    if rate == nil or rate < 0 then return nil end
    local ratio = rate == 0 and 0 or rate == 8 and 254 or rate * 32 - 1
    return core.traits.gender(ratio, mon.dvs or {})
  end

  if gen == 1 then
    local SummaryMenu = require("src.ui.SummaryMenu")
    local hub = SummaryMenu.__ndxInfo
    if not hub then
      hub = {}
      SummaryMenu.__ndxInfo = hub
      local update, draw = SummaryMenu.update, SummaryMenu.draw
      SummaryMenu.update = function(self, dt, ...)
        local input = self.game and self.game.input
        if hub.on and not self.closing and not (self.whiteHold and self.whiteHold > 0) and self.page == 2
            and input and (input:wasPressed("a") or input:wasPressed("b")) then
          self.page = 3
          return
        end
        return update(self, dt, ...)
      end
      SummaryMenu.draw = function(self, ...)
        if self.page ~= 3 or not hub.on then return draw(self, ...) end
        self.page = 1
        local ok, err = pcall(draw, self, ...)
        self.page = 3
        if not ok then error(err, 0) end
        pcall(hub.drawInfo, self)
      end
    end
    hub.on = true
    hub.drawInfo = function(self)
      local mon, data = self.mon, self.game.data
      local g = love.graphics
      g.setColor(1, 1, 1, 1)
      g.rectangle("fill", 0, 64, 160, 80)
      g.setColor(0, 0, 0, 1)
      local held = mon.extra and mon.extra.national_dex_gen3 and mon.extra.national_dex_gen3.item
      local itemDef = held and data.items[held]
      local gender = genderOf(data, mon)
      Font.draw(Strings("NATURE/"), 8, 72)
      Font.draw(natureOf(mon) or "-", 24, 80)
      Font.draw(Strings("ABILITY/"), 8, 96)
      Font.draw(abilityOf(data, mon) or "-", 24, 104)
      Font.draw(Strings("ITEM/"), 8, 120)
      Font.draw(itemDef and itemDef.name or (held and tostring(held)) or Strings("NONE"), 24, 128)
      if gender then Font.draw(gender == "F" and "♀" or "♂", 144, 72) end
    end
    return hub
  end

  local SummaryMenu = require("src.ui.gen2.SummaryMenu")
  local hub = SummaryMenu.__ndxInfo
  if not hub then
    hub = {}
    SummaryMenu.__ndxInfo = hub
    -- both draw and drawWidescreen paint through drawPanel
    local drawPanel = SummaryMenu.drawPanel
    SummaryMenu.drawPanel = function(self, ...)
      local a, b = drawPanel(self, ...)
      if hub.on and self.page == 3 then pcall(hub.drawInfo, self) end
      return a, b
    end
  end
  hub.on = true
  hub.drawInfo = function(self)
    local party = self.party
    local mon = self.mon or (party and party[self.index or 1])
    local game = self.game
    local data = (game and game.data) or (opts.data and opts.data())
    if not (mon and data and mon.species) or mon.isEgg then return end
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(natureOf(mon) or "-", 0, 120)
    local name = abilityOf(data, mon) or "-"
    local first, rest = name, nil
    if #name > 9 then
      local cut = name:sub(1, 10):match("^.*() ")
      if cut and cut > 1 then first, rest = name:sub(1, cut - 1), name:sub(cut + 1) end
    end
    Font.draw(first, 0, 128)
    if rest then Font.draw(rest, 8, 136) end
  end
  return hub
end

return Summary
