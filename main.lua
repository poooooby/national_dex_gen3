-- National Dex Gen 3: species #387-1025 for every Gen 3 game -- Pokémon
-- FireRed, LeafGreen, Ruby, Sapphire and Emerald (manifest.json: games =
-- ["gen3"]).
--
-- Data + framework only. The payload (data/species/*.lua, built from PokéAPI
-- by tools/build_species.py) is registered through the engine's own species
-- registry; no artwork, icons or cries ship. A sprite mod supplies pictures
-- through mod.exports.setArtProvider (src/art.lua).
--
-- Module map:
--   src/species.lua  payload -> records, resolved against the running
--                    game's move / item / species registries, and registered
--   src/fixups.lua   Pokemon.onReload repairs the engine cannot do from a
--                    registry write (evolution targets, name + national lookup)
--                    and the move-tutor compatibility the running game keeps
--                    outside the species registry
--   src/items.lua    registers the evolution items no Gen 3 game has (data/items.lua,
--                    built by tools/build_items.py), so this mod's own evolutions
--                    (and anyone else's) stop waiting on a companion item mod
--   src/item_art.lua Bag icons for those items (no hook offers this; wraps the
--                    Bag's own icon draw directly -- see its own header)
--   src/shops.lua    puts those items on sale (data/shops.lua; wraps Marts.itemsFor)
--   src/cry_art.lua  cries for #387-1025 (wraps Audio.playCry; assets/cries/cries.pak)
--   src/conditional_evos.lua  Rockruff's Midday/Midnight/Dusk Lycanroc, Milcery's Alcremie and
--                    the friendship day/night evolutions (evolution.check hook)
--   src/counters.lua  recoil taken, move uses, steps led and coins spent, for the evolutions that
--                    ask for them (Basculin, Primeape, Pawmo, Gimmighoul)
--   src/breeding.lua  a bred Manaphy lays a Phione egg
--   src/national_unlock.lua  the "National Dex" option: the National Pokedex without the story unlock
--   src/dex_sync.lua  the "Register Owned" option: party and PC Pokemon count as seen and caught when the Pokedex opens
--   src/mon_anim.lua  a cart species' front animation for every species and form (none = softlock)
--   src/dex_patch.lua Ruby/Sapphire/Emerald's Pokedex list past #386 (patched copy of the engine screen)
--   src/clock.lua    the hour for those rules: the device clock, or on Ruby/Sapphire/Emerald
--                    the player's choice of device or in-game (options.lua)
--   src/art.lua      pokemon.sprite seam for art providers
--   src/api.lua      mod.exports
--
-- Slot numbering: species dex + 64 (451..1089), above every ROM slot, the
-- dex + 64 numbering, so a save's species numbers never move.

local function loadSibling(mod, name)
  local source = mod:read(name)
  if not source then
    mod.log:error("%s is missing -- reinstall the mod", name)
    return nil
  end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. name)
  if not chunk then
    mod.log:error("%s failed to compile (%s) -- reinstall the mod", name, tostring(err))
    return nil
  end
  local ok, result = pcall(chunk)
  if not ok then
    mod.log:error("%s errored while loading (%s) -- reinstall the mod", name, tostring(result))
    return nil
  end
  return result
end

return function(mod)
  local Species = loadSibling(mod, "src/species.lua")
  local Fixups = loadSibling(mod, "src/fixups.lua")
  local Items = loadSibling(mod, "src/items.lua")
  local ItemArt = loadSibling(mod, "src/item_art.lua")
  local CryArt = loadSibling(mod, "src/cry_art.lua")
  local Shops = loadSibling(mod, "src/shops.lua")
  local Art = loadSibling(mod, "src/art.lua")
  local ConditionalEvos = loadSibling(mod, "src/conditional_evos.lua")
  local Clock = loadSibling(mod, "src/clock.lua")
  local Counters = loadSibling(mod, "src/counters.lua")
  local Breeding = loadSibling(mod, "src/breeding.lua")
  local DexPatch = loadSibling(mod, "src/dex_patch.lua")
  local NationalUnlock = loadSibling(mod, "src/national_unlock.lua")
  local DexSync = loadSibling(mod, "src/dex_sync.lua")
  local DexRepeat = loadSibling(mod, "src/dex_repeat.lua")
  -- optional: without it the Pokedex has no FORMS page
  local DexForms = loadSibling(mod, "src/dex_forms.lua")
  local Editor = loadSibling(mod, "src/editor.lua")
  local MonAnim = loadSibling(mod, "src/mon_anim.lua")
  -- optional: without it the game keeps Gen 3's 17 types
  local FairyTypes = loadSibling(mod, "src/types.lua")
  -- moves newer than Gen 3 that run on a Gen 3 effect; without it, the learnset rows that name
  -- one of them are left out
  local NewMoves = loadSibling(mod, "src/moves.lua")
  local TypeIcons = loadSibling(mod, "src/type_icons.lua")
  -- optional: without it every new move plays the cart animation named in data/moves.lua
  local MoveAnims = loadSibling(mod, "src/anims.lua")
  -- the Modern Moves option: the original 386 also learn their newer moves
  local ModernLearnsets = loadSibling(mod, "src/modern_learnsets.lua")
  -- optional: without it every newer ability stays the closest Gen 3 one
  local RealAbilities = loadSibling(mod, "src/abilities.lua")
  -- optional: without it the moves with new mechanics are plain hits or do nothing
  local MoveEffects = loadSibling(mod, "src/move_effects.lua")
  local MoveRules = loadSibling(mod, "src/move_rules.lua")
  if MoveRules then MoveRules.hooks(mod) end
  local MoveField = loadSibling(mod, "src/move_field.lua")
  if MoveField then MoveField.hooks(mod) end
  if RealAbilities then RealAbilities.hooks(mod) end
  local Api = loadSibling(mod, "src/api.lua")
  if not (Species and Fixups and Items and ItemArt and CryArt and Shops and Art and ConditionalEvos and Clock and Counters and Breeding and DexPatch and NationalUnlock and DexSync and DexRepeat and Editor and MonAnim and Api) then return end

  local read = function(path) return loadSibling(mod, path) end

  local payload = Species.loadPayload(read)
  if not payload then
    mod.log:error("data/species is missing or empty -- reinstall the mod")
    return
  end

  -- before species registration, so Species.register's own eager item lookup
  -- (species.lua's evolutionRow, a load-time snapshot) sees these too, not
  -- only the live bookkeeping path fixups drives
  -- the save editor loads mods without starting a game (src/editor.lua): hand the dataset the
  -- move and item modules first, as a game does, so the registration below resolves moves
  local inEditor = Editor.detect(require)
  if inEditor then Editor.bindModules(require("src.core.Data"), require) end

  local itemPayload = Items.loadPayload(read)
  local registeredItems = Items.register(mod, itemPayload)
  -- moves newer than Gen 3 that run on a Gen 3 effect (src/moves.lua), before the species,
  -- whose learnsets name them
  local registeredMoves = NewMoves and NewMoves.register(mod, read("data/moves.lua") or {}) or {}

  local crossgen = Species.loadCrossGeneration(read)
  local forms = Species.loadForms(read)
  local registered, bridges, registeredForms = Species.register(mod, payload, crossgen, forms)
  local fixups = Fixups.new(registered, Species.itemIndex(mod), bridges, mod.log, registeredForms)
  -- a bred Manaphy lays a Phione egg (src/breeding.lua)
  local manaphySlot, phioneSlot
  for _, r in ipairs(registered) do
    if r.id == "MANAPHY" then manaphySlot = r.slot elseif r.id == "PHIONE" then phioneSlot = r.slot end
  end
  -- a form of a cart species (Hisuian Qwilfish) has no cry of its own: it plays its base's
  -- the Fairy type's data (data/types.lua) plus this mod's own Fairy moves
  local function fairyData()
    local data = read("data/types.lua") or {}
    data.moves = data.moves or {}
    for _, id in ipairs(NewMoves and NewMoves.fairy(registeredMoves) or {}) do
      data.moves[#data.moves + 1] = id
    end
    return data
  end

  -- the Modern Moves option (src/modern_learnsets.lua): after the repairs and the new moves'
  -- numbers; follows the option when it changes in the mod menu
  local applyModern
  local function installModern()
    if not (ModernLearnsets and NewMoves) or applyModern then return end
    local okM, fn = pcall(ModernLearnsets.install, { data = read("data/species/modern.lua") or {},
      require = require, log = mod.log,
      enabled = function()
        local okGet, value = pcall(function() return mod.options:get("modern_moves") end)
        return okGet and value == true
      end })
    if okM then applyModern = fn else mod.log:warn("modern moves are off: %s", tostring(fn)) end
    -- the Move Reminder past a learnset's 20th row (this mod's species have longer ones too)
    pcall(ModernLearnsets.installRelearner, require)
  end
  mod.events:on("mod.options_changed", function(ev)
    if type(ev) == "table" and ev.mod == mod.id and ev.key == "modern_moves" and applyModern then
      pcall(applyModern)
    end
  end)

  -- in the save editor, do on mods.loaded what a game does before game.ready, plus this mod's
  -- own repairs, and list every species and form in the editor's picker
  if inEditor then
    mod.events:on("mods.loaded", function(ev)
      Editor.prepare(ev, require, function() fixups.install(nil) end, mod.log)
      -- the new moves: learnset numbers, names, texts (src/moves.lua)
      if NewMoves then pcall(NewMoves.install, { moves = registeredMoves, require = require, log = mod.log, family = "frlg" }) end
      -- the Modern Moves option, as the player set it
      installModern()
      -- the real abilities' names, texts and ability pairs (src/abilities.lua)
      if RealAbilities then
        local formSlots = {}
        for _, f in ipairs(registeredForms) do formSlots[f.id] = f.slot end
        pcall(RealAbilities.install, { data = read("data/abilities.lua") or {}, require = require, log = mod.log,
          formSlots = formSlots })
      end
      local n = Editor.addToCatalog(ev and ev.data, registered, registeredForms, mod.content.pokemon)
      local items = Editor.addItems(ev and ev.data, registeredItems, require)
      local moves = Editor.addMoves(ev and ev.data, registeredMoves)
      -- the Fairy type (src/types.lua): species types, the chart and the type's name; the editor
      -- writes type names as text, so no badge art
      if FairyTypes then
        local okF, errF = pcall(function()
          local formSlots = {}
          for _, f in ipairs(registeredForms) do formSlots[f.id] = f.slot end
          local data = fairyData()
          FairyTypes.install({ data = data, require = require, log = mod.log, formSlots = formSlots })
          local nums = {}
          for _, name in ipairs(data.moves) do nums[#nums + 1] = FairyTypes.moveNum(require, name) end
          Editor.retypeMoves(ev and ev.data, nums, "FAIRY")
        end)
        if not okF then mod.log:warn("save editor: the Fairy type is off (%s)", tostring(errF)) end
      end
      mod.log:info("save editor: %d species and forms, %d items, %d moves listed", n, items, moves)
    end)
  end

  -- in a game, the species tables hold the new moves' numbers from the moment mods finish
  -- loading (src/moves.lua repairs the registry's write); game.ready installs again
  if NewMoves and not inEditor then
    mod.events:on("mods.loaded", function()
      local okVerL, GVerL = pcall(require, "src.core.GameVersion")
      local current = okVerL and GVerL and tostring(GVerL.current) or ""
      pcall(NewMoves.install, { moves = registeredMoves, require = require, log = mod.log,
        family = (current:find("firered", 1, true) or current:find("leafgreen", 1, true)) and "frlg" or "rse" })
    end)
  end

  local cryAliases = {}
  do
    local okN, PokemonG3 = pcall(require, "src.core.game3.pokemon")
    local isRegistered = {}
    for _, r in ipairs(registered) do isRegistered[r.id] = true end
    for _, f in ipairs(registeredForms) do
      if okN and not isRegistered[f.baseSpecies] then
        local base = PokemonG3.speciesFromName and PokemonG3.speciesFromName(f.baseSpecies)
        if base then cryAliases[f.slot] = base end
      end
    end
  end
  -- after Gen3Compat's own reload hook (registered while the game boots), so
  -- its re-apply of registry data does not undo these repairs
  mod.events:on("game.ready", function(ev)
    fixups.install(ev and ev.game or mod.game)
    -- the new moves' names, texts, contest rows and animations (src/moves.lua); before the
    -- Fairy type, which retypes the Fairy ones by name
    local okVerM, GVerM = pcall(require, "src.core.GameVersion")
    local gameName = okVerM and GVerM and tostring(GVerM.current) or ""
    if NewMoves then
      local okMoves, movesErr = pcall(NewMoves.install, { moves = registeredMoves, require = require, log = mod.log,
        family = (gameName:find("firered", 1, true) or gameName:find("leafgreen", 1, true)) and "frlg" or "rse" })
      if not okMoves then mod.log:warn("the new moves are incomplete: %s", tostring(movesErr)) end
    end
    -- their battle animations from pokeemerald-expansion (src/anims.lua), outside src/moves.lua's
    if NewMoves and MoveAnims then
      local okAn, anErr = pcall(MoveAnims.install, { data = read("data/anims.lua") or {}, moves = registeredMoves,
        require = require, log = mod.log })
      if not okAn then mod.log:warn("new move animations are off: %s", tostring(anErr)) end
    end
    installModern()
    -- the new moves' mechanics Gen 3 lacks (src/move_effects.lua)
    if MoveEffects then
      local okFx, fxErr = pcall(MoveEffects.install, { moves = registeredMoves, require = require, log = mod.log })
      if not okFx then mod.log:warn("new move mechanics are off: %s", tostring(fxErr)) end
    end
    -- moves whose power or outcome depends on the battle (src/move_rules.lua)
    if MoveRules then
      local formWeight = {}
      for _, f in ipairs(registeredForms) do formWeight[f.slot] = f.weight end
      local okRu, ruErr = pcall(MoveRules.install, { moves = registeredMoves, require = require, log = mod.log,
        formWeight = formWeight })
      if not okRu then mod.log:warn("move rules are off: %s", tostring(ruErr)) end
    end
    -- hazards, terrains, Tailwind / Trick Room and the moves that switch Pokemon out
    -- (src/move_field.lua); after the abilities, whose turn-order hook it feeds
    -- real abilities (src/abilities.lua): after the repairs, so National numbers resolve
    if RealAbilities then
      local formSlots = {}
      for _, f in ipairs(registeredForms) do formSlots[f.id] = f.slot end
      local okAb, abErr = pcall(RealAbilities.install, { data = read("data/abilities.lua") or {}, require = require,
        log = mod.log, formSlots = formSlots })
      if not okAb then mod.log:warn("real abilities are off: %s", tostring(abErr)) end
    end
    if MoveField then
      local okFi, fiErr = pcall(MoveField.install, { moves = registeredMoves, require = require, log = mod.log,
        abilities = RealAbilities })
      if not okFi then mod.log:warn("field moves are off: %s", tostring(fiErr)) end
    end
    -- the Fairy type (src/types.lua): after the repairs, so National numbers resolve to this
    -- mod's slots and its reload hook runs after theirs
    if FairyTypes then
      local okFairy, fairyErr = pcall(function()
        local formSlots = {}
        for _, f in ipairs(registeredForms) do formSlots[f.id] = f.slot end
        local frlgIcon
        if love and love.graphics and love.graphics.newImage then
          local okImg, img = pcall(love.graphics.newImage, mod.path .. "/assets/types/fairy_frlg.png")
          if okImg and img then
            if img.setFilter then img:setFilter("nearest", "nearest") end
            frlgIcon = img
          end
        end
        FairyTypes.install({ data = fairyData(), require = require, log = mod.log,
          formSlots = formSlots, art = { frlg = frlgIcon } })
        -- Ruby/Sapphire/Emerald's summary icon draws through a local (src/type_icons.lua)
        local okVer, GVer = pcall(require, "src.core.GameVersion")
        local game = okVer and GVer and tostring(GVer.current) or ""
        local which = game:find("emerald", 1, true) and "rse"
          or ((game:find("ruby", 1, true) or game:find("sapphire", 1, true)) and "rs") or nil
        if TypeIcons and which then
          local rseIcon
          if love and love.graphics and love.graphics.newImage then
            local okImg, img = pcall(love.graphics.newImage, mod.path .. "/assets/types/fairy_rse.png")
            if okImg and img then
              if img.setFilter then img:setFilter("nearest", "nearest") end
              rseIcon = img
            end
          end
          TypeIcons.install({ which = which, icon = rseIcon, require = require, load = load, log = mod.log,
            read = function(path)
              local okB, Blob = pcall(require, "src.import.CacheBlob")
              return okB and Blob and Blob.readFs and Blob.readFs(path) or nil
            end })
        end
      end)
      if not okFairy then mod.log:warn("the Fairy type is off: %s", tostring(fairyErr)) end
    end
    -- every species and form gets a cart species' front animation (src/mon_anim.lua): without
    -- one, a trainer leading with it stops the battle
    do
      local PokemonG3 = require("src.core.game3.pokemon")
      local anim = { ours = {}, like = {}, dexOf = {} }
      local slotOfId = {}
      for _, r in ipairs(registered) do
        anim.ours[r.slot], anim.dexOf[r.slot], slotOfId[r.id] = true, r.dex, r.slot
      end
      for _, f in ipairs(registeredForms) do
        anim.ours[f.slot], anim.dexOf[f.slot] = true, f.baseDex or f.dex
        anim.like[f.slot] = slotOfId[f.baseSpecies]
          or (PokemonG3.speciesFromName and PokemonG3.speciesFromName(f.baseSpecies)) or nil
      end
      for _, b in ipairs(bridges) do
        if b.targetSlot and b.sourceSlot and not anim.like[b.targetSlot] then
          anim.like[b.targetSlot] = b.sourceSlot
        end
      end
      MonAnim.install(anim, require)
    end
    ConditionalEvos.installItemGender(bridges)
    NationalUnlock.install(function()
      local okGet, value = pcall(function() return mod.options:get("unlock_national") end)
      return okGet and value == true
    end)
    -- the Pokedex screens (src/dex_patch.lua): RSE's list past #386, FRLG's blank screen after left
    local okV, GV = pcall(require, "src.core.GameVersion")
    local current = okV and GV and tostring(GV.current) or ""
    local patchOpts = {
      read = function(path)
        local okB, Blob = pcall(require, "src.import.CacheBlob")
        return okB and Blob and Blob.readFs and Blob.readFs(path) or nil
      end,
      load = load, require = require, log = mod.log,
    }
    if current:find("firered", 1, true) or current:find("leafgreen", 1, true) then
      DexPatch.installFrlg(patchOpts)
    else
      DexPatch.install(patchOpts)
    end
    Breeding.install(manaphySlot, phioneSlot)
    ItemArt.install(mod, read)
    -- after DexPatch, which replaces the RSE screen's functions (and its Host) with its copy's
    DexRepeat.install(require)
    -- the FORMS page (src/dex_forms.lua): after DexPatch, whose patches it needs. Each form's
    -- picture is the Pokedex picture the game (or a sprite mod, g9-battle-sprites-gen3) gives
    -- its slot; this mod ships no Pokedex art of its own
    if DexForms then
      local okForms, formsErr = pcall(function()
        local slotById = {}
        for _, f in ipairs(registeredForms) do slotById[f.id] = f.slot end
        local PokemonG3 = require("src.core.game3.pokemon")
        local function artFor(id)
          local slot = slotById[id]
          if not slot then return nil end
          local ok, entry = pcall(PokemonG3.frontPic, slot, 0, false, 0, "dex")
          return ok and type(entry) == "table" and entry.image and entry or nil
        end
        DexForms.install({ byDex = DexForms.byDex(registeredForms), artFor = artFor, log = mod.log }, require)
      end)
      if not okForms then mod.log:warn("the Pokedex FORMS page is off: %s", tostring(formsErr)) end
    end
    DexSync.install(function()
      local okGet, value = pcall(function() return mod.options:get("register_owned") end)
      return okGet and value ~= false
    end, mod.log)
    CryArt.install(mod, read, cryAliases)
    Shops.install(read("data/shops.lua") or {}, Species.itemIndex(mod), function()
      local okV, GV = pcall(require, "src.core.GameVersion")
      return okV and GV and GV.current or nil
    end, mod.log)
  end, -100)

  -- art providers are asked about forms too, by their own id and slot
  local everySpecies = {}
  for _, r in ipairs(registered) do everySpecies[#everySpecies + 1] = r end
  for _, r in ipairs(registeredForms) do everySpecies[#everySpecies + 1] = r end
  local art = Art.install(mod, everySpecies)
  -- the player's clock choice (options.lua); not defined, "game" is the default
  local okOptions, optionsSource = pcall(function() return mod:read("options.lua") end)
  if okOptions and optionsSource then
    local chunk = load(optionsSource, "@" .. mod.path .. "/options.lua")
    local okSchema, schema = pcall(chunk or function() end)
    if okSchema and type(schema) == "table" then pcall(function() mod.options:define(schema) end) end
  end
  local function clockSource()
    local okGet, value = pcall(function() return mod.options:get("clock_source") end)
    return okGet and value or "game"
  end
  -- what each species' evolutions count: slot -> { recoil, uses, steps, coins } (src/counters.lua)
  local needs = {}
  local function collect(slot, step)
    local when = step.when
    if not (slot and when) then return end
    if when.recoil or when.uses or when.steps or when.coins or when.crits then
      local need = needs[slot] or {}
      need.recoil, need.uses = when.recoil or need.recoil, when.uses or need.uses
      need.steps, need.coins = when.steps or need.steps, when.coins or need.coins
      need.crits = when.crits or need.crits
      needs[slot] = need
    end
  end
  for _, r in ipairs(everySpecies) do
    for _, step in ipairs(r.evolutions or {}) do collect(r.slot, step) end
  end
  for _, b in ipairs(bridges) do collect(b.sourceSlot, b) end
  Counters.install(mod, needs)
  ConditionalEvos.install(mod, everySpecies, Species.itemIndex(mod), {
    bridges = bridges,
    isNight = function(session) return Clock.isNight(session, clockSource()) end,
    isDusk = function(session) return Clock.isDusk(session, clockSource()) end,
  })
  Api(mod, { species = registered, forms = registeredForms, bridges = bridges, art = art, dexPatch = DexPatch })
end
