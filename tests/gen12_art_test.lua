-- Standalone: luajit mods/national_dex_gen3/tests/gen12_art_test.lua [red|blue|yellow|gold|silver|crystal ...]
-- (from the gen1recomp root; runs on red, yellow, gold and crystal when none is named).
-- src/gen12/art.lua + dex.lua: every species and form has a party icon and a cry the game can
-- play (its proxy's, resolved as Sound does), species #387+ also their own from cries.pak; a
-- sprite mod's setArtProvider answer replaces the placeholder (in its own colours) for this
-- mod's species only, through the engine's own Sprites; Red's Pokedex runs to #1025 in four
-- digits with no form on it; Gold's Pokedex keeps no form after game.ready; a form seen or
-- caught marks its base.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen12.lua")
local Runtime = require("src.mods.Runtime")
local cryIndex = H.module("data/cries.lua")

local records = {}
for _, shard in ipairs(H.module("data/gen12/species/index.lua").shards) do
  for _, r in ipairs(H.module("data/gen12/species/" .. shard)) do records[#records + 1] = r end
end
for _, f in ipairs(H.module("data/gen12/forms.lua")) do records[#records + 1] = f end

-- the pak the cries come from: present, an Ogg stream, every index row inside it
do
  local f = io.open(H.modRoot() .. "/assets/cries/cries.pak", "rb")
  local pak = f and f:read("*a")
  if f then f:close() end
  local inside = pak ~= nil
  for _, row in pairs(cryIndex) do
    if not pak or row[1] + row[2] > #pak or pak:sub(row[1] + 1, row[1] + 4) ~= "OggS" then inside = false end
  end
  T.check(inside, "cries.pak holds an Ogg at every row of data/cries.lua")
end

for _, version in ipairs(H.versions()) do
  local gen = H.GENERATION[version]
  local key = "gen" .. gen
  local maxDex = gen == 1 and 151 or 251
  local run, api = H.load(version)
  for i = 1, math.min(5, #run.errors) do print("load error: " .. tostring(run.errors[i])) end
  T.eq(#run.errors, 0, version .. ": loads clean")
  local data = run.data

  -- icons and cries for every species and form here
  local cries = data.audio.cries
  local icons = gen == 1 and data.icons.bySpecies or data.gen2Icons.species
  local cartIcons = {}
  if gen == 1 then for _, kind in pairs(data.icons.byDex) do cartIcons[kind] = true end
  else for _, sheet in pairs(data.gen2Icons.species) do cartIcons[sheet] = true end end
  local noIcon, noCry, own = nil, nil, 0
  for _, r in ipairs(records) do
    if data.pokemon[r.id] and (r.baseSpecies or r.dex > maxDex) then
      if not (icons[r.id] and cartIcons[icons[r.id]]) then noIcon = noIcon or r.id end
      local c = cries[r.id]
      local base = c and c.base and cries[c.base]
      if not (base and base.header) then noCry = noCry or r.id end
      if cryIndex[r.slot] then own = own + 1 end
    end
  end
  T.check(noIcon == nil, version .. ": every new species has a cart party icon (" .. tostring(noIcon) .. ")")
  T.check(noCry == nil, version .. ": every new species has a cry the game can play (" .. tostring(noCry) .. ")")
  T.check(own > 700, version .. ": " .. own .. " of them also have their own cry")
  local Sound = require("src.core.Sound")
  T.check(Sound.__ndxGen12Cry and type(Sound.__ndxGen12Cry.handler) == "function",
    version .. ": Sound.playCry plays the pak's cries")

  -- a sprite mod's pictures (Red's and Gold's battle pics both resolve through Sprites.pic)
  local Sprites = require("src.pokemon.Sprites")
  local asked
  T.check(api.setArtProvider(function(id, side, slot, shiny, kind)
    asked = { id = id, side = side, slot = slot, shiny = shiny, kind = kind }
    return "mods/sprites/" .. id .. "_" .. side .. ".png"
  end), version .. ": setArtProvider takes a provider")
  local path, trueColor = Sprites.pic(data.pokemon.LUCARIO.spriteFront,
    { species = "LUCARIO", side = "front", kind = "battle", data = data })
  T.eq(path, "mods/sprites/LUCARIO_front.png", version .. ": Lucario drawn by the provider")
  T.check(trueColor == true and asked.slot == 448 + 64 and asked.side == "front"
    and asked.kind == "battle", version .. ": in its own colours, asked by id, side, slot and kind")
  local cart = gen == 1 and "PIKACHU" or "CHIKORITA"
  local cartPath = Sprites.pic(data.pokemon[cart].spriteFront, { species = cart, side = "front", data = data })
  T.eq(cartPath, data.pokemon[cart].spriteFront, version .. ": the cart's own species untouched")

  -- the Pokedex
  if gen == 1 then
    T.eq(data.constants.dexSize, 1025, version .. ": Red's Pokedex runs to #1025")
    T.eq(data.constants.dexDigits, 4, version .. ": in four digits")
    local byDex, dup, formOn = {}, nil, nil
    for id, def in pairs(data.pokemon) do
      if type(def) == "table" and def.dex and def.dex <= 1025 then
        if byDex[def.dex] then dup = dup or def.dex end
        byDex[def.dex] = id
        if def.baseSpecies then formOn = formOn or id end
      end
    end
    local holes = 0
    for n = 1, 1025 do if not byDex[n] then holes = holes + 1 end end
    T.check(holes == 0 and dup == nil and formOn == nil,
      version .. ": #1-1025 once each, no form on the list")
    local Game = require("src.core.Game")
    Game.data = data
    Game.save = require("src.core.SaveData").newGame()
    Game.save.pokedex.seen.VULPIX_ALOLA = true
    Game.save.pokedex.owned.VULPIX_ALOLA = true
    Runtime.emit("pokemon.caught", {})
    T.check(Game.save.pokedex.seen.VULPIX and Game.save.pokedex.owned.VULPIX,
      version .. ": catching Alolan Vulpix counts Vulpix")
  else
    require("src.core.gen2.PokedexText").apply(data)
    local dex = data.gen2Pokedex
    T.check(dex.entries.VULPIX_ALOLA ~= nil, version .. ": (Gold's own code adds forms)")
    Runtime.emit("game.ready", { game = { data = data } })
    local formIn = nil
    for id in pairs(dex.entries) do if data.pokemon[id] and data.pokemon[id].baseSpecies then formIn = id end end
    for _, list in ipairs({ dex.newOrder or {}, dex.alphabeticalOrder or {} }) do
      for _, id in ipairs(list) do if data.pokemon[id] and data.pokemon[id].baseSpecies then formIn = id end end
    end
    T.check(formIn == nil, version .. ": no form left in the Pokedex (" .. tostring(formIn) .. ")")
    local missing
    for _, r in ipairs(records) do
      if not r.baseSpecies and r.dex > maxDex and not (dex.entries[r.id] and dex.entries[r.id].dex == r.dex) then
        missing = missing or r.id
      end
    end
    T.check(missing == nil, version .. ": every new species in it at its own number (" .. tostring(missing) .. ")")
    local Dex = H.module("src/gen12/dex.lua")
    local save = { pokedex = { seen = { FARFETCHD_GALAR = true }, caught = { FARFETCHD_GALAR = true } } }
    Dex.sync(save, 2, { { id = "FARFETCHD_GALAR", base = data.pokemon.FARFETCHD_GALAR.baseSpecies } })
    T.check(save.pokedex.seen.FARFETCH_D and save.pokedex.caught.FARFETCH_D,
      version .. ": catching Galarian Farfetch'd counts Gold's FARFETCH_D")
  end
  run.release()
end

T.finish("national_dex_gen3 Gen 1/2 art and Pokedex")
