-- Standalone: luajit mods/national_dex_gen3/tests/gen12_species_test.lua [red|blue|yellow|gold|silver|crystal ...]
-- (from the gen1recomp root; runs on red, yellow, gold and crystal when none is named).
-- src/gen12/species.lua + project.lua: every species past the cart's own and all 128 forms are
-- registered in the game's own record shape; every move they name is one the game has (learnset
-- sorted, no duplicates, machines only the game's own); the placeholder pictures exist; Red's
-- entries read through its text labels and Gold's through its Pokedex; Gold's indices are their
-- own (none 255, none shared); forms carry a dex number of their own. Then the game's own code
-- makes them: a new species and a form built at level 50 with four real moves, and a wild battle
-- against a new species where it uses its moves.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")
local Project = H.module("src/gen12/project.lua")

local records = {}
for _, shard in ipairs(H.module("data/gen12/species/index.lua").shards) do
  for _, r in ipairs(H.module("data/gen12/species/" .. shard)) do records[#records + 1] = r end
end
local forms = H.module("data/gen12/forms.lua")

local function fileExists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function chars(s)
  local n = 0
  for i = 1, #s do if bit.band(s:byte(i), 0xC0) ~= 0x80 then n = n + 1 end end
  return n
end
bit = require("bit")

for _, version in ipairs(H.versions()) do
  local gen = H.GENERATION[version]
  local maxDex = gen == 1 and 151 or 251
  local run = H.load(version)
  for i = 1, math.min(5, #run.errors) do print("load error: " .. tostring(run.errors[i])) end
  T.eq(#run.errors, 0, version .. ": loads clean")
  local data = run.data
  local pokemon, moves = data.pokemon, data.moves

  -- what should be there
  local want = {}
  for _, r in ipairs(records) do if r.dex > maxDex then want[#want + 1] = r end end
  for _, f in ipairs(forms) do want[#want + 1] = f end
  local present = 0
  for _, r in ipairs(want) do if type(pokemon[r.id]) == "table" then present = present + 1 end end
  T.eq(present, #want, version .. ": " .. #want .. " species and forms registered")

  -- the cart's machine moves (as the mod reads them)
  local machines = {}
  for _, rec in pairs(pokemon) do
    if type(rec) == "table" and rec.tmhm and not rec.slot then
      for _, m in ipairs(rec.tmhm) do machines[m] = true end
    end
  end

  local bad = {}
  local function fail(what, id) bad[what] = bad[what] or id end
  local indices, dexes = {}, {}
  for _, rec in pairs(pokemon) do
    if type(rec) == "table" and rec.dex and not rec.slot then dexes[rec.dex] = rec.id end
  end
  for n, r in ipairs(want) do
    local rec = pokemon[r.id]
    if rec then
      local isForm = r.baseSpecies ~= nil
      if isForm then
        local formN
        for i, f in ipairs(forms) do if f.id == r.id then formN = i end end
        if rec.dex ~= Project.FORM_DEX + formN then fail("form dex numbers", r.id) end
        if not (rec.baseSpecies and rec.form and pokemon[rec.baseSpecies]) then fail("form fields", r.id) end
      elseif rec.dex ~= r.dex then fail("dex numbers", r.id) end
      if dexes[rec.dex] then fail("a dex number of its own", r.id) end
      dexes[rec.dex] = r.id
      if rec.slot ~= r.slot then fail("the Gen 3 slot", r.id) end
      if not (rec.spAttack and rec.spDefense) then fail("spAttack / spDefense for modern_spawns", r.id) end
      if not (fileExists(rec.spriteFront) and fileExists(rec.spriteBack)) then fail("pictures exist", r.id) end
      for _, t in ipairs(rec.types) do if not data.type_chart.types[t] then fail("types", r.id) end end
      if not data.growth_rates[rec.growthRate] and not (pokemon.growthRates or {})[rec.growthRate] then
        fail("growth rate", r.id)
      end
      for _, m in ipairs(rec.tmhm or {}) do
        if not machines[m] then fail("machines are the game's", r.id) end
      end
      local list = gen == 1 and rec.learnset or rec.levelMoves
      local last, seen = 0, {}
      for _, m in ipairs(gen == 1 and rec.level1Moves or {}) do
        if not moves[m] then fail("every move exists", r.id) end
        seen[m] = true
      end
      for _, row in ipairs(list) do
        if row.level < last then fail("learnset sorted", r.id) end
        last = row.level
        if not moves[row.move] then fail("every move exists", r.id) end
        if seen[row.move] then fail("each move once", r.id) end
        seen[row.move] = true
      end
      if gen == 1 then
        if #rec.level1Moves > 4 or #rec.level1Moves == 0 then fail("one to four level-1 moves", r.id) end
        if rec.baseStats.special ~= r.baseStats.specialAttack then fail("Special", r.id) end
        if rec.dexEntry then
          local text = data.text[rec.dexEntry.text]
          if not text then fail("entry text by label", r.id)
          else
            for line in text:gsub("{DONE}$", ""):gsub("\f", "\n"):gmatch("[^\n]+") do
              if chars(line) > 18 then fail("entry lines of 18", r.id) end
            end
          end
          if rec.dexEntry.heightIn > 11 then fail("height in feet and inches", r.id) end
        elseif not isForm then fail("species have an entry", r.id) end
      else
        local idx = rec.index
        local wantIdx = Project.GEN2_INDEX + (isForm and r.slot or r.dex)
        if idx ~= wantIdx then fail("Gold index 1000 + dex (forms + slot)", r.id) end
        if idx == 255 or indices[idx] then fail("indices of their own", r.id) end
        indices[idx] = r.id
        if #rec.eggGroups ~= 2 then fail("two egg groups", r.id) end
        for _, m in ipairs(rec.eggMoves) do if not moves[m] then fail("egg moves exist", r.id) end end
        if rec.types[2] == nil then fail("two type slots", r.id) end
      end
    end
  end
  if gen == 2 then
    for id, rec in pairs(pokemon) do
      if type(rec) == "table" and not rec.slot and rec.index and indices[rec.index] then
        fail("indices clear of the cart's", id)
      end
    end
  end
  for what, who in pairs(bad) do print("FAIL " .. version .. ": " .. what .. " (" .. tostring(who) .. ")") end
  T.check(next(bad) == nil, version .. ": every record well formed")

  -- the game's own code makes every one of them, at level 5 and 50, with at least one move
  do
    local make = gen == 1 and function(id, lv) return require("src.pokemon.Pokemon").new(data, id, lv) end
      or function(id, lv) return require("src.battle.gen2.Mon").new(data, id, lv) end
    local broken, first = 0, nil
    for _, r in ipairs(want) do
      for _, lv in ipairs({ 5, 50 }) do
        local ok, mon = pcall(make, r.id, lv)
        if not (ok and type(mon) == "table" and mon.moves and #mon.moves > 0 and (mon.hp or 0) > 0) then
          broken = broken + 1
          first = first or (r.id .. " Lv" .. lv .. ": " .. tostring(ok and "no moves / hp" or mon))
        end
      end
    end
    T.eq(broken, 0, version .. ": every one built at Lv 5 and 50" .. (first and (" -- " .. first) or ""))
  end

  if gen == 1 then
    local Pokemon = require("src.pokemon.Pokemon")
    require("src.battle.TypeChart").load(data)
    pcall(require("src.render.Font").load, data)
    local mon = Pokemon.new(data, "LUCARIO", 50)
    T.check(mon and #mon.moves == 4 and mon.stats and mon.stats.special > 0,
      version .. ": a level 50 Lucario with four moves")
    local exp = require("src.pokemon.Growth").expForLevel(pokemon.LUCARIO.growthRate, 50, data.growth_rates)
    T.eq(mon.exp, exp, version .. ": at its curve's Exp.")
    local form = Pokemon.new(data, "VULPIX_ALOLA", 30)
    T.check(form and #form.moves > 0, version .. ": an Alolan Vulpix")
    local Game = require("src.core.Game")
    Game.data = data
    Game.save = require("src.core.SaveData").newGame()
    Game.save.options.animations = false
    Game.save.party = { Pokemon.new(data, "BLASTOISE", 60) }
    local tb = require("src.battle.BattleState").newWild(Game, "GARCHOMP", 50)
    tb.queue, tb.nextInsert = {}, 0
    tb.rng = function(a) return a end
    local errs = 0
    for _, m in ipairs(tb.enemy.mon.moves) do
      local ok, err = pcall(tb.performMove, tb, tb.enemy, tb.player, { id = m.id, pp = 10 }, false)
      if not ok then errs = errs + 1; print("  " .. m.id .. ": " .. tostring(err)) end
    end
    T.eq(errs, 0, version .. ": a wild Garchomp uses its moves in Red's battle")
  else
    local Mon = require("src.battle.gen2.Mon")
    local Battle = require("src.battle.gen2.Battle")
    local mon = Mon.new(data, "LUCARIO", 50)
    T.check(mon and #mon.moves == 4 and mon.stats and mon.stats.specialAttack > 0,
      version .. ": a level 50 Lucario with four moves")
    local form = Mon.new(data, "VULPIX_ALOLA", 30)
    T.check(form and #form.moves > 0, version .. ": an Alolan Vulpix")
    local wild = Mon.new(data, "GARCHOMP", 50)
    local player = Mon.new(data, "FERALIGATR", 60)
    local battle = Battle.new({ data = data, party = { player }, wild = wild,
      save = { player = { id = 7, badges = {}, kantoBadges = {} } },
      random = function(n) return (n or 1) > 1 and 1 or 0 end })
    local errs = 0
    for _, m in ipairs(wild.moves) do
      local ok, err = pcall(battle.useMove, battle, battle.enemy, battle.player, m.id)
      if not ok then errs = errs + 1; print("  " .. m.id .. ": " .. tostring(err)) end
    end
    T.eq(errs, 0, version .. ": a wild Garchomp uses its moves in Gold's battle")
    -- the Pokedex takes registered records' entries (src/core/gen2/PokedexText.lua)
    require("src.core.gen2.PokedexText").apply(data)
    local entry = data.gen2Pokedex.entries.LUCARIO
    T.check(entry and entry.kind == pokemon.LUCARIO.dexEntry.kind and entry.text:find("<NEXT>", 1, true),
      version .. ": Lucario's Pokedex entry")
  end
  run.release()
end

T.finish("national_dex_gen3 Gen 1/2 species")
