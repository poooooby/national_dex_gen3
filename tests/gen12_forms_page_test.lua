-- Standalone: luajit mods/national_dex_gen3/tests/gen12_forms_page_test.lua [red|blue|yellow|gold|silver|crystal ...]
-- (from the gen1recomp root; runs on red, yellow, gold and crystal when none is named).
-- The Pokedex FORMS page (src/gen12/dex_forms.lua) through each game's own entry screen:
--   Red   A on the entry's last page opens the forms (Vulpix: Alolan) when the entry came from the
--         Pokedex list, and not after a catch; A on the last form closes the entry; B goes back
--   Gold  PAGE goes 1 -> 2 -> FORMS -> 1 on a species with forms; Up / Down step them (Alcremie)
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")
local Runtime = require("src.mods.Runtime")
local Forms = H.module("src/gen12/dex_forms.lua")
local Labels = H.module("src/dex_forms.lua")

local by = Forms.byBase({ { id = "VULPIX_ALOLA", base = "VULPIX", data = { form = "ALOLA" } },
  { id = "ALCREMIE_RUBY_CREAM", base = "ALCREMIE", data = { form = "RUBY_CREAM" } } }, Labels.label)
T.eq(by.VULPIX[1].label, "ALOLAN", "a form's words")
T.eq(by.ALCREMIE[1].label, "RUBY CREAM", "and a flavour's")

local function stack(states)
  local s = { states = states }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end
local function input()
  local i = { down = {} }
  function i:wasPressed(k) return self.down[k] == true end
  function i:press(k) self.down = { [k] = true } end
  return i
end

for _, version in ipairs(H.versions()) do
  local gen = H.GENERATION[version]
  local run = H.load(version)
  local data = run.data
  local inp = input()
  local game = { data = data, input = inp }
  Runtime.emit("game.ready", { game = game })

  if gen == 1 then
    local Entry = require("src.ui.DexEntryMenu")
    local List = require("src.ui.PokedexMenu")
    local done = 0
    local function entryFor(species, below)
      game.stack = stack({ below })
      local e = setmetatable({ game = game, def = data.pokemon[species], species = species, page = 1,
        pageCount = 1, picDelay = 0, blink = 0, onDone = function() done = done + 1 end }, Entry)
      game.stack:push(e)
      return e
    end
    local e = entryFor("VULPIX", setmetatable({}, List))
    inp:press("a"); Entry.update(e, 0)
    local page = game.stack:top()
    T.check(page ~= e and page.list and page.list[1].id == "VULPIX_ALOLA",
      version .. ": A on Vulpix's last page opens its forms (Alolan)")
    T.eq(page.list[1].label, "ALOLAN", version .. ": named ALOLAN")
    inp:press("b"); page:update(0)
    T.check(game.stack:top() == e and done == 0, version .. ": B goes back to the entry")
    inp:press("a"); Entry.update(e, 0)
    T.check(#game.stack.states == 1 and done == 1, version .. ": then A closes the entry, as it would")
    e = entryFor("VULPIX", setmetatable({}, List))
    inp:press("a"); Entry.update(e, 0)
    page = game.stack:top()
    inp:press("a"); page:update(0)
    T.check(#game.stack.states == 1 and done == 2, version .. ": A on the last form closes the entry too")
    e = entryFor("VULPIX", { battle = true })
    inp:press("a"); Entry.update(e, 0)
    T.check(#game.stack.states == 1 and done == 3, version .. ": after a catch: no forms page")
    e = entryFor("PIDGEY", setmetatable({}, List))
    inp:press("a"); Entry.update(e, 0)
    T.check(#game.stack.states == 1, version .. ": a species without forms closes as ever")
  else
    local Menu = require("src.ui.gen2.PokedexMenu")
    T.check(Menu.__ndxForms ~= nil, version .. ": the entry is wrapped")
    local row = { species = "ALCREMIE" }
    local m = setmetatable({ game = game, view = "entry", page = 2, entryAction = 1,
      current = function() return row end }, Menu)
    inp:press("a"); Menu.update(m, 0)
    T.eq(m.page, 3, version .. ": PAGE on page 2 goes on to the forms")
    inp:press("down"); Menu.update(m, 0)
    T.eq(m.ndxForm, 2, version .. ": Down steps to the next form")
    inp:press("up"); Menu.update(m, 0); Menu.update(m, 0)
    local n = #Menu.__ndxForms.hub.byBase.ALCREMIE
    T.eq(m.ndxForm, n, version .. ": Up wraps round (" .. n .. " forms)")
    inp:press("a"); Menu.update(m, 0)
    T.eq(m.page, 1, version .. ": PAGE again: back to page 1")
    m.page = 2
    row.species = "PIDGEY"
    inp:press("a"); Menu.update(m, 0)
    T.eq(m.page, 1, version .. ": no forms: page 2 -> 1 as ever")
    m.page, m.newEntry, row.species = 2, true, "ALCREMIE"
    inp:press("a"); pcall(Menu.update, m, 0)
    T.check(m.page ~= 3, version .. ": not on the entry after a catch")
  end
  run.release()
end

T.finish("national_dex_gen3 Gen 1/2 FORMS page")
