# National Dex Gen 3

National Dex Gen 3 adds National Dex species #387–1025 (Generations 4–9) to
every Gen 3 Pokémon game in gen1recomp — FireRed, LeafGreen, Ruby, Sapphire
and Emerald — as data. It gives them stats, typing, learnsets, abilities and
evolutions. It's for mods that need the full roster on a Gen 3 game (such as
Modern Spawns, on FireRed) and for players pairing it with a sprite mod. It
is a framework: no sprites or party icons ship with it. It does ship cries
for every species, and Bag icons for its own evolution items.

Try it (from a gen1recomp checkout, with this repo linked as `mods/national_dex_gen3`):

```bash
luajit mods/national_dex_gen3/tests/register_test.lua   # needs FireRed imported (the test fixture; the mod itself isn't FireRed-only)
python tools/modkit.py lint mods/national_dex_gen3
# launch any Gen 3 game; species #387-1025 exist for other mods to use
```

## What gets registered

Each species is registered through the running game's own species registry
— one schema shared by FireRed, LeafGreen, Ruby, Sapphire and Emerald — at
slot **dex + 64** (451–1089). That's above every slot the cart uses, and it's
the same numbering 1025Dex uses, so a save moves between the two intact.

| Field | Source |
|---|---|
| Name, dex number, base stats, catch rate, base experience (capped at 255), growth rate, gender ratio, egg cycles, friendship, Pokédex kind/height/weight | PokéAPI |
| Types | PokéAPI. Gen 3 has no Fairy type, so Fairy is dropped; a pure Fairy type becomes Normal |
| Learnset | Level-up moves from the newest game that has them, limited to the 354 moves Gen 3 has. Move names are read from the running game's own move registry |
| TM/HM compatibility | Every TM or HM (the same 58 machines in all five games) whose move the species can be taught by machine or tutor in any game (636 species; 37 of 58 machines on average) |
| Move tutors | Whichever tutors the running game has — FireRed/LeafGreen's 15, Ruby/Sapphire's none, or Emerald's own larger set — whose move the species can be taught in any game (628 species on FireRed/LeafGreen) |
| Egg moves | Egg moves Gen 3 has (315 species; many modern egg moves don't exist in Gen 3) |
| Abilities | Gen 3 abilities only: the cart's own (ids 1–75 and Air Lock at 77) are kept, and each newer ability is mapped to the closest Gen 3 one (`tools/ability_map.py`), e.g. Simple → Own Tempo, Moxie → Guts. The Gen 3 battle engine cannot take new abilities from a mod, so a species shows and behaves like the Gen 3 ability it was given, not its real one |
| Evolutions | Level, item, friendship and trade steps between species 1–1025 |
| Evolutions from the cart's species | Steps from the cart's own species into new ones, such as Magneton → Magnezone and Nosepass → Probopass with a Thunder Stone |

**Evolution items.** No Gen 3 game has every item PokéAPI's evolutions call
for, so this mod registers the 19 it needs itself (Dusk Stone, Dawn Stone,
Shiny Stone, Ice Stone, Protector, Electirizer, Magmarizer, Dubious Disc,
Reaper Cloth, Sachet, Whipped Dream, Tart/Sweet/Syrupy Apple, Auspicious/
Malicious Armor, Metal Alloy, Black Augurite and Peat Block) at indices
900–918. They sit in the Items pocket and have no other use. All have a Bag
icon (24×24, from the third-party pokesprite pack plus six added by hand, in
`assets/items/`). The Bag icons are not yet verified in-game.

A step whose item still doesn't exist is never dropped — it waits. The mod
checks the running game's item registry again every time the engine loads
its species tables, so if another mod registers a matching item the
evolution goes live with no changes to either mod. If another mod registers
one of the same items, whichever loads first (lower manifest priority
number) keeps the slot and the evolution works either way.

When the engine reloads its species tables, the mod also repairs two other
things: evolution targets (the engine's registry write can point them at
slot 0) and name/National Dex number lookup. Tutor compatibility, which the
running game keeps outside the species registry, is added to the engine's
tutor data each time the engine loads it.

## Art

This mod draws nothing. A sprite mod supplies pictures:

```lua
local dex = mod:find("national_dex_gen3")
if dex then
  dex.exports.setArtProvider(function(speciesId, side, slot)
    return mod.assets:path(side .. "/" .. speciesId .. ".png")  -- or nil
  end)
end
```

`side` is `"front"` or `"back"`. Return a PNG path (the engine centres and
crops it to 64×64), or nil to let the next provider answer.

## Beside 1025Dex

1025Dex registers the same species into the same slots and ships art for
them. When it's installed, this mod registers nothing and reports
`provider() == "1025dex"`.

## API (`mod.exports`, `apiVersion = 1`)

| Export | Returns |
|---|---|
| `isActive()` | false when 1025Dex provides the species instead |
| `provider()` | `"national_dex_gen3"` or `"1025dex"` |
| `listSpecies()` | `{ { dex, id, slot, name, legendary, mythical } }` |
| `slotOf(idOrDex)` | the running game's slot |
| `evolutionsOf(idOrDex)` | national_dex's shape: `{ id, dex, evolvesFrom = { id, methods }, evolvesInto = { … } }`. Works for a cart species (#1–386) that gains a step into a new one, e.g. `evolutionsOf("RHYDON")`, not only for #387–1025. Lists a step whether or not its item currently resolves — this call doesn't say which |
| `setArtProvider(fn)` | registers an art provider |

## Known limits

- **Without an art provider, battles show whatever the engine decodes for an
  unknown slot**: a wrong or garbled picture, which the engine may cache. Pair
  this mod with a sprite mod.
- No party icons. The engine has no sanctioned path for them on Gen 3.
- Cries play for every new species (`assets/cries/cries.pak`, from the Gen 9
  pack), by wrapping `Audio.playCry`. Not yet verified in-game; the cart's
  pitch/pan modes and the music duck are not reproduced.
- **The native Pokédex list now includes #387–1025 in National mode, without
  art.** This mod raises the engine's `Dex.NATIONAL_MAX` (386) to 1025 — the
  same value 1025Dex sets — because a mod that enumerates species up to that
  bound (Kanto Gear's wild-encounter guide builds its species cache that way)
  otherwise never sees a new species and silently drops its rows. The
  Pokédex list uses the same bound, so without a sprite mod those entries
  show missing or garbled pictures. On Emerald this mod also supplies a
  Pokédex entry (category and size; no flavor text) for each new species,
  since a mod walking every National number asserts one exists. Seen/caught counting is unaffected
  (plain tables, no size limit).
- Moves newer than Gen 3 aren't learnable (Gen 3 has no data for them). EV
  yields are 0.
- Evolutions into species past #151 need the National Dex unlocked, as in
  vanilla FireRed/LeafGreen/Emerald. (Ruby and Sapphire never had a National
  Dex at all in the original games; this still works there because
  gen1recomp's own National Dex support isn't gated on the cart.)
- Every item evolution this mod generates is live, because the mod provides
  the items (see above): the 15 steps from the cart's own species (Magneton
  → Magnezone, Rhydon → Rhyperior, Scyther → Kleavor, …) and the new
  species' own item steps. Nothing in the world gives you these items yet:
  this mod only registers them, so players need another mod (or a cheat) to
  obtain one.
- **Held-item level-ups, and other conditions no Gen 3 game has a trigger
  for at all** (location, a known move, gender, and similar) — Happiny →
  Chansey (Oval Stone, by day), Gligar → Gliscor (Razor Fang, at night),
  Sneasel → Weavile (Razor Claw, at night), Eevee → Leafeon/Glaceon,
  Piloswine → Mamoswine — aren't a missing-item problem an item mod can fix.
  This mod doesn't even generate a step for them: there's no method id to
  attach one to. Adding the item wouldn't help, because there'd be nothing
  to make it matter.

  This is specifically a Gen 3 limit, not a Pokémon-engine one. Gen 3's
  evolution methods are a closed, hardcoded list of six, the same six on
  every Gen 3 game (the engine turns off the `evolution_methods` registry
  entirely on Gen 3); no mod can add a seventh. Gen 1 and Gen 2 don't have
  that ceiling — `mod.content.evolution_methods` is a real, open registry
  there, which is exactly how the Gen 1 mod `g9-battle-engine` added a
  friendship-evolution trigger Red never had natively. On Gen 3, only a mod
  willing to patch the engine's own evolution-check code (not merely
  register data) could add a trigger like this; nothing here attempts that.
- Learnsets are level-up only: 6,255 of the 9,331 level-up moves PokéAPI
  lists are moves Gen 3 has (67%), so 20 species (Kricketot, Budew, Burmy,
  Combee, the three Simisage/Simisear/Simipour monkeys, Tynamo, …) end up
  with fewer than 4 learnable moves. TM/HM and egg-move coverage is partial
  for the same reason: of 639 species, 636 get at least one TM/HM and 315
  get at least one egg move. Tutor coverage (628 species get at least one
  tutor move) is counted against FireRed/LeafGreen's 15 tutors; it's lower
  on Ruby/Sapphire (no tutors at all) and may be higher on Emerald, whose
  own, larger tutor set this mod reads live rather than assumes.

## Credits

Cries and item sprites are fan-made; see [CREDITS.md](CREDITS.md).

## Regenerating the data

```bash
python -m pip install requests
python tools/build_species.py            # PokéAPI responses cached in tools/.cache
```
