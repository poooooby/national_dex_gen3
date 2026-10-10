-- The gen1recomp save editor.
--
-- The editor loads mods to read and write saves, but never starts a game: it does not hand the
-- loader the move and item modules a game does, never applies the registries to the live species
-- tables, and never fires game.ready. So the species this mod registers have no learnsets, no
-- names, no National numbers, and are missing from the editor's species list, which it builds
-- from the cart's own name table before any mod loads.
--
-- When the editor is the host, this does what a game would:
--   bindModules  (before registration) hands the dataset the move and item modules, as
--                Game3:_exposeModData does, so learnsets, TMs and evolution items resolve
--   prepare      (on mods.loaded) applies the registries to the live tables
--                (Gen3Compat.applyMerged + a species reload) and runs this mod's own
--                repairs, the ones game.ready runs in a game
--   addToCatalog adds every species and form this mod registered to the editor's list
--                (data.pokemon), a form under its own id and labelled with its form
--   addItems     adds this mod's items (index 900+) to the editor's item list (data.items),
--                which it builds from the cart's own items only
-- In a game none of this runs.

local Editor = {}

-- Is the save editor the host? It is the only host with its own `Gen` module.
function Editor.detect(require)
  local ok, Gen = pcall(require, "Gen")
  if not (ok and type(Gen) == "table" and type(Gen.bindGame3Data) == "function") then return false end
  local okV, GameVersion = pcall(require, "src.core.GameVersion")
  return okV and type(GameVersion.generation) == "function" and GameVersion.generation() == 3
end

function Editor.bindModules(data, require)
  if type(data) ~= "table" then return end
  local okMv, Moves = pcall(require, "src.core.game3.battle.moves")
  if okMv and type(Moves) == "table" then
    if not Moves._romLoaded and Moves.loadRomPack then
      local okD, Dataset = pcall(require, "src.core.game3.dataset")
      if okD and Dataset and Dataset.cache then pcall(Moves.loadRomPack, Dataset.cache()) end
    end
    data.gen3Moves = data.gen3Moves or Moves
  end
  local okIt, ItemsData = pcall(require, "src.core.game3.items_data")
  if okIt and type(ItemsData) == "table" then
    if ItemsData.ensureLoaded then pcall(ItemsData.ensureLoaded) end
    data.gen3Items = data.gen3Items or ItemsData
  end
end

-- The editor's growth-rate ids (include/constants/pokemon.h), by the registry's names.
local GROWTH = { MEDIUM_FAST = 0, ERRATIC = 1, FLUCTUATING = 2, MEDIUM_SLOW = 3, FAST = 4, SLOW = 5 }

local function formLabel(form)
  return (tostring(form):gsub("_", " "))
end

-- species, forms: Species.register's lists; registry: the loader's pokemon registry, for the
-- stats and types the editor shows. Returns how many rows were added.
function Editor.addToCatalog(data, species, forms, registry)
  if type(data) ~= "table" then return 0 end
  data.pokemon = data.pokemon or {}
  local added = 0
  local function add(r, key, label, dex)
    local record = registry and registry.get and registry:get(r.id) or {}
    local row = {
      id = key, name = label, baseName = r.name, species = r.slot, speciesId = r.slot, dex = dex,
      growthRate = GROWTH[record.growthRate] or 0, baseStats = record.baseStats, types = record.types,
    }
    data.pokemon[key], data.pokemon[r.slot] = row, row
    added = added + 1
  end
  for _, r in ipairs(species or {}) do add(r, r.id, r.name, r.dex) end
  for _, f in ipairs(forms or {}) do
    add(f, f.id, tostring(f.name) .. " (" .. formLabel(f.form) .. ")", f.baseDex or f.dex)
  end
  return added
end

-- items: Items.register's list ({ id, name, index }). Keyed the way the editor keys the cart's
-- own items: the name in capitals with "_" for anything else, the number, and its string.
function Editor.addItems(data, items, require)
  if type(data) ~= "table" then return 0 end
  data.items = data.items or {}
  local okI, ItemsData = pcall(require, "src.core.game3.items_data")
  local added = 0
  for _, r in ipairs(items or {}) do
    local index = tonumber(r.index)
    if index then
      local info = okI and ItemsData.info and select(2, pcall(ItemsData.info, index)) or nil
      local name = (type(info) == "table" and info.name) or r.name
      local key = tostring(name):upper():gsub("[^A-Z0-9_]", "_"):gsub("_+", "_")
      local row = { id = key, name = name, itemId = index,
                    pocket = (type(info) == "table" and info.pocket) or "ITEMS" }
      data.items[key], data.items[index], data.items[tostring(index)] = row, row, row
      added = added + 1
    end
  end
  return added
end

-- ev: the mods.loaded payload ({ loader, data }); repair: this mod's own game.ready work.
function Editor.prepare(ev, require, repair, log)
  local okC, Compat = pcall(require, "src.mods.Gen3Compat")
  local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
  if not (okC and okP and Compat.applyMerged and Pokemon.install) then return false end
  local okA, errA = pcall(Compat.applyMerged, { mods = ev and ev.loader, data = ev and ev.data })
  if not okA and log then log:warn("save editor: could not apply the registries (%s)", tostring(errA)) end
  pcall(Pokemon.install, nil)
  local okR, errR = pcall(repair)
  if not okR and log then log:warn("save editor: repairs failed (%s)", tostring(errR)) end
  return okA and okR
end

return Editor
