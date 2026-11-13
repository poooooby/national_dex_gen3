-- Standalone: luajit mods/national_dex_gen3/tests/gen12_vending_test.lua [red|blue|yellow|gold|silver|crystal ...]
-- (from the gen1recomp root; runs on red, yellow, gold and crystal when none is named).
-- The vending machines on Gen 1 / Gen 2 (src/gen12/vending.lua over src/vending_screen.lua): both
-- machines stand in this game's Dept. Store, stock what this game has (the evolution items, the new
-- TMs with their move's type and power), gate by badges, and a purchase through the screen takes
-- the money from the game's own field (Red save.money, Gold save.player.money) and puts the item in
-- the Bag; one that would not fit is refused. The Marts no longer stock them.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")

local function stack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end
local input = { wasPressed = function() return false end, isDown = function() return false end }

for _, version in ipairs(H.versions()) do
  local gen = H.GENERATION[version]
  local run = H.load(version)
  local data = run.data
  local V = run.loader.exports.national_dex_gen3._vending
  T.check(V and #V.machines == 2, version .. ": two machines")
  if V then
    local where = {}
    for _, e in ipairs(V.machines) do where[e.m.id] = e.place.map end
    T.eq(where.evo, gen == 1 and "CELADON_MART_4F" or "GOLDENROD_DEPT_STORE_4F", version .. ": EVO EXPRESS")
    T.eq(where.tm, gen == 1 and "CELADON_MART_2F" or "GOLDENROD_DEPT_STORE_5F", version .. ": TM EXPRESS")
    local evo, tm
    for _, e in ipairs(V.machines) do if e.m.id == "evo" then evo = e.m else tm = e.m end end
    local count, labels = 0, {}
    for _, tab in ipairs(V.stock(evo, data)) do
      labels[#labels + 1] = tab.label
      count = count + #tab.entries
    end
    T.check(count >= 30, version .. ": EVO EXPRESS sells " .. count .. " items (" .. table.concat(labels, ", ") .. ")")
    local tms, typed = 0, true
    for _, tab in ipairs(V.stock(tm, data)) do
      for _, e in ipairs(tab.entries) do
        tms = tms + 1
        if not (e.tm and e.tm.number and e.tm.type and e.tm.move) then typed = false end
      end
    end
    T.eq(tms, 43, version .. ": TM EXPRESS sells the 43 new TMs")
    T.check(typed, version .. ": each with its number, move and type")

    -- a purchase
    local save
    if gen == 1 then
      save = require("src.core.SaveData").newGame()
      save.money, save.inventory = 50000, {}
      for _, b in ipairs({ "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE", "SOULBADGE",
          "MARSHBADGE", "VOLCANOBADGE", "EARTHBADGE" }) do save.inventory[b] = 1 end
    else
      save = { player = { money = 50000, badges = { true, true, true, true, true, true, true, true },
        kantoBadges = {} }, inventory = {} }
    end
    local game = { data = data, save = save, stack = stack(), input = input }
    T.check(V.open(evo, game), version .. ": the machine opens")
    T.check(game.stack:top() ~= nil, version .. ": its screen takes the buttons")
    local e = V.stock(evo, data)[1].entries[1]
    T.check(V.screen.buy(), version .. ": buying " .. e.name)
    local money = gen == 1 and save.money or save.player.money
    T.eq(money, 50000 - e.price, version .. ": the money came off")
    T.eq(save.inventory[e.id], 1, version .. ": and it is in the Bag")
    V.screen.close()
    pcall(function() V.screen.state() end)
    game.stack:pop()

    -- the badge gates: with none, a gated item is refused
    if gen == 1 then
      for k in pairs(save.inventory) do if k:find("BADGE") then save.inventory[k] = nil end end
    else
      save.player.badges = {}
    end
    V.open(evo, game)
    local gated
    for _, tab in ipairs(V.stock(evo, data)) do
      for _, x in ipairs(tab.entries) do if x.badges > 0 then gated = x; break end end
      if gated then break end
    end
    T.check(gated and V.screen.locked(gated), version .. ": with no badges, " .. tostring(gated and gated.name) .. " is locked")
    V.screen.close()

    -- the Marts no longer stock them
    local inMart = false
    if gen == 1 then
      for _, id in ipairs(data.text_pointers.CeladonMart2F.TEXT_CELADONMART2F_CLERK2.mart) do
        if id == "TM74" then inMart = true end
      end
    else
      for _, list in ipairs(data.gen2Marts.lists) do
        for _, id in ipairs(list) do if id == "TM74" or id == "LINKING_CORD" then inMart = true end end
      end
    end
    T.check(not inMart, version .. ": the Marts leave them to the machines")
  end
  run.release()
end

T.finish("national_dex_gen3 Gen 1/2 vending machines")
