# National Dex Gen 3: developer guide

For mod authors and contributors. Players only need the [README](README.md).

Try it (from a gen1recomp checkout, with this repo linked as `mods/national_dex_gen3`):

```bash
luajit mods/national_dex_gen3/tests/register_test.lua   # needs FireRed imported (the test fixture; the mod itself isn't FireRed-only)
python tools/modkit.py lint mods/national_dex_gen3
# launch any Gen 3 game; species #387-1025 exist for other mods to use
```

Keep [README.md](README.md) describing the mod as it is now (players read it); what changed
goes in [CHANGELOG.md](CHANGELOG.md).

## What gets registered

Each species is registered through the running game's own species registry (one schema shared
by FireRed, LeafGreen, Ruby, Sapphire and Emerald) at slot **dex + 64** (451–1089). That's above
every slot the cart uses, and the same numbering throughout, so a save's species numbers never
move. Forms are registered as species of their own, each reporting its base species' dex number.

| Field | Source |
|---|---|
| Name, dex number, base stats, catch rate, base experience (capped at 255), growth rate, gender ratio, egg cycles, friendship, Pokédex kind/height/weight | PokéAPI |
| Types | PokéAPI. Gen 3 has no Fairy type, so Fairy is dropped; a pure Fairy type becomes Normal |
| Learnset | The level-up list from the newest game that has one, at its full length. A move Gen 3 lacks is replaced, at the same level, by the closest Gen 3 move the species doesn't already learn (`tools/move_map.py`: same type, then similar power, accuracy, priority and effect). Move names are read from the running game's own move registry |
| TM/HM compatibility | Every TM or HM (the same 58 machines in all five games) whose move the species can be taught by machine or tutor in any game (636 species; 37 of 58 machines on average) |
| Move tutors | Whichever tutors the running game has (FireRed/LeafGreen's 15, Ruby/Sapphire's none, or Emerald's own larger set) whose move the species can be taught in any game |
| Egg moves | Egg moves Gen 3 has (315 species) |
| Abilities | Gen 3 abilities only: the cart's own are kept, and each newer ability is mapped to the closest Gen 3 one (`tools/ability_map.py`), e.g. Simple → Own Tempo, Moxie → Guts. The Gen 3 battle engine cannot take new abilities from a mod |
| Evolutions | Level, item, friendship and trade steps between species 1–1025, plus steps from the cart's own species into new ones (Magneton → Magnezone, Nosepass → Probopass ...) |

**Shops** (`data/shops.lua`), by item type and how far into the game a store is:

| | FireRed / LeafGreen | Ruby / Sapphire / Emerald |
|---|---|---|
| Dusk, Dawn, Shiny and Ice Stone, Sachet, Whipped Dream | Celadon Dept. Store 4F | Lilycove Dept. Store, supplements floor |
| Protector, Electirizer, Magmarizer, Dubious Disc, Reaper Cloth | Celadon Dept. Store 5F | Lilycove Dept. Store, battle-item floor |
| Gen 8-9 items | Six Island Mart (after the Elite Four) | Apples at Mossdeep, Armors and Metal Alloy at Sootopolis, Black Augurite and Peat Block at the Ever Grande League mart |

Prices are twice the sell price Bulbapedia lists for the earliest game that has one (2,100 for
most; Ice Stone and Metal Alloy 3,000; Black Augurite and Peat Block 1,000). A store is found by
its original stock, so each entry covers every game with that list.

**Evolution items.** The mod registers the 19 items its evolutions need at indices 900–918
(Items pocket, no other use), with Bag icons in `assets/items/`. A step whose item doesn't exist
yet is never dropped: the item registry is checked again whenever the engine loads its species
tables, so an item another mod registers makes the evolution live with no changes to either mod.

When the engine reloads its species tables, the mod also repairs evolution targets (the
registry write can point them at slot 0) and name / National Dex number lookup, and adds tutor
compatibility to the engine's tutor data.

## Art

Pictures (battle, summary and Pokédex) come from a sprite mod:

```lua
local dex = mod:find("national_dex_gen3")
if dex then
  dex.exports.setArtProvider(function(speciesId, side, slot)
    return mod.assets:path(side .. "/" .. speciesId .. ".png")  -- or nil
  end)
end
```

`side` is `"front"` or `"back"`. Return a PNG path (the engine centres and crops it to 64×64),
or nil to let the next provider answer.

## API (`mod.exports`)

| Export | Returns |
|---|---|
| `isActive()` | always `true` |
| `provider()` | always `"national_dex_gen3"` |
| `listSpecies()` | `{ { dex, id, slot, name, legendary, mythical } }` |
| `slotOf(idOrDex)` | the running game's slot |
| `idOfSlot(slot)` / `listForms()` | (apiVersion 2) a slot's species id, and the registered forms (a form has `baseSpecies`) |
| `evolutionsOf(idOrDex)` | `{ id, dex, evolvesFrom = { id, methods }, evolvesInto = { … } }`, also for a cart species that gains a step into a new one, e.g. `evolutionsOf("RHYDON")` |
| `setArtProvider(fn)` | registers an art provider |
| `setDexPeek(fn)` | `fn(speciesSlot) -> true` lets that unseen species open in the Pokédex in a limited view (number shown, name dashed, "?" picture, no cry, only the AREA page). `nil` turns it off. Modern Spawns uses it |

## Technical limits

- Without an art provider, battles show whatever the engine decodes for an unknown slot.
- Cries come from `assets/cries/cries.pak` (the Gen 9 pack) by wrapping `Audio.playCry`; the
  cart's pitch/pan modes and the music duck are not reproduced.
- The mod raises the engine's `Dex.NATIONAL_MAX` (386) to 1025, because a mod enumerating species
  up to that bound (Kanto Gear's guide) would otherwise never see the new ones. On Emerald it
  also supplies a Pokédex entry (category and size, no flavour text) for each new species.
- Gen 3's evolution methods are a closed list of six on every Gen 3 game (the engine turns the
  `evolution_methods` registry off on Gen 3), so conditions like a held item at a time of day,
  a location, a known move or gender have no trigger to attach to; the mod adds stand-in
  conditions where it can (see the player guide).
- Level-up learnsets keep their modern length (9,302 moves across 639 species; 6,255 real Gen 3
  moves, 3,047 substitutes). TM/HM, tutor and egg moves are limited to Gen 3's own moves.

## Regenerating the data

```bash
python -m pip install requests
python tools/build_species.py            # PokéAPI responses cached in tools/.cache
```
