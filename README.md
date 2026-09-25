# National Dex Gen 3

National Dex Gen 3 adds National Dex species #387–1025 (Generations 4–9) to
Pokémon FireRed and LeafGreen in gen1recomp, as data. It gives them stats,
typing, learnsets, abilities and evolutions. It's for mods that need the full
roster on FireRed (such as Modern Spawns) and for players pairing it with a
sprite mod. It is a framework: no sprites, icons or cries ship with it.

Try it (from a gen1recomp checkout, with this repo linked as `mods/national_dex_gen3`):

```bash
luajit mods/national_dex_gen3/tests/register_test.lua   # needs FireRed imported
python tools/modkit.py lint mods/national_dex_gen3
# launch FireRed; species #387-1025 exist for other mods to use
```

## What gets registered

Each species is registered through FireRed's own species registry, at slot
**dex + 64** (451–1089). That's above every slot the cart uses, and it's the
same numbering 1025Dex uses, so a save moves between the two intact.

| Field | Source |
|---|---|
| Name, dex number, base stats, catch rate, base experience (capped at 255), growth rate, gender ratio, egg cycles, friendship, Pokédex kind/height/weight | PokéAPI |
| Types | PokéAPI. Gen 3 has no Fairy type, so Fairy is dropped; a pure Fairy type becomes Normal |
| Learnset | Level-up moves from the newest game that has them, limited to the 354 moves FireRed has. Move names are read from the running game's move registry |
| TM/HM compatibility | Every FireRed TM or HM whose move the species can be taught by machine or tutor in any game (636 species; 37 of 58 machines on average) |
| Move tutors | Each of FireRed's 15 tutors whose move the species can be taught in any game (628 species) |
| Egg moves | Egg moves FireRed has (315 species; many modern egg moves don't exist in Gen 3) |
| Abilities | PokéAPI abilities that exist in Gen 3 (ids 1–76) |
| Evolutions | Level, item, friendship and trade steps between species 1–1025 |
| Evolutions from the cart's species | Steps from FireRed's own species into new ones, such as Magneton → Magnezone and Nosepass → Probopass with a Thunder Stone |

**An item-gated evolution is never dropped for missing an item — it waits.**
FireRed doesn't have every item PokéAPI's evolutions call for (Dusk Stone,
Protector, and so on); a step needing one is kept, unresolved, and this mod
checks the item registry again every time the engine loads its species
tables — at boot and on every reload — regardless of whether the item-adding
mod loads before or after this one. The moment *any* installed mod registers
a matching item, the evolution goes live with no changes to either mod. Until
then it simply doesn't fire, the same as if FireRed had never heard of it.

When the engine reloads its species tables, the mod also repairs two other
things: evolution targets (the engine's registry write can point them at
slot 0) and name/National Dex number lookup. Tutor compatibility, which
FireRed keeps outside the species registry, is added to the engine's tutor
data each time the engine loads it.

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
| `slotOf(idOrDex)` | the FireRed slot |
| `evolutionsOf(idOrDex)` | national_dex's shape: `{ id, dex, evolvesFrom = { id, methods }, evolvesInto = { … } }`. Works for a cart species (#1–386) that gains a step into a new one, e.g. `evolutionsOf("RHYDON")`, not only for #387–1025. Lists a step whether or not its item currently resolves — this call doesn't say which |
| `setArtProvider(fn)` | registers an art provider |

## Known limits

- **Without an art provider, battles show whatever the engine decodes for an
  unknown slot**: a wrong or garbled picture, which the engine may cache. Pair
  this mod with a sprite mod.
- No party icons and no cries (silent). The engine has no sanctioned path for
  either on Gen 3.
- New species don't appear in the Pokédex lists, which FireRed caps at 386.
- Moves newer than Gen 3 aren't learnable (FireRed has no data for them).
  EV yields are 0.
- Evolutions into species past #151 need the National Dex unlocked, as in
  vanilla FireRed.
- Evolutions that need an item FireRed doesn't have (Dusk Stone, Dawn Stone,
  Shiny Stone, Protector, Electirizer, Magmarizer, Dubious Disc, Reaper
  Cloth, Black Augurite, Peat Block, …) don't fire *yet* — see above; they
  activate the moment some mod adds the item, with no update to this mod.
  Right now, nothing does. (The Gen 1 mod `g9-battle-engine` takes a
  different approach for the same problem on Red: rather than wait for a
  companion mod, it registers its own replacement items directly. This mod
  stays data-only and doesn't do that.) Of the 15 evolutions FireRed's own
  species could gain into #387–1025, 2 are already live because FireRed itself has the
  item (Magneton → Magnezone and Nosepass → Probopass, both Thunder Stone);
  the other 13 are waiting: Rhydon → Rhyperior, Scyther → Kleavor,
  Electabuzz → Electivire, Magmar → Magmortar, Togetic → Togekiss,
  Murkrow → Honchkrow, Misdreavus → Mismagius, Ursaring → Ursaluna,
  Porygon2 → Porygon-Z, Kirlia → Gallade, Roselia → Roserade,
  Dusclops → Dusknoir, Snorunt → Froslass.
- Of the new species' own 224 possible evolution steps, 211 are already live
  (most item evolutions resolve fine: FireRed has the Thunder, Fire, Water,
  Leaf, Sun and Moon Stones). 13 are waiting the same way: Minccino →
  Cinccino (Shiny Stone), Lampent → Chandelure and Doublade → Aegislash
  (Dusk Stone), Crabrawler → Crabominable and Cetoddle → Cetitan (Ice
  Stone), Applin's three evolutions (Tart, Sweet and Syrupy Apple),
  Duraludon → Archaludon (Metal Alloy), Charcadet's two evolutions
  (Auspicious/Malicious Armor), and Spritzee → Aromatisse / Swirlix →
  Slurpuff (trade holding Sachet / Whipped Dream).
- **Held-item level-ups, and other conditions FireRed has no trigger for at
  all** (location, a known move, gender, and similar) — Happiny → Chansey
  (Oval Stone, by day), Gligar → Gliscor (Razor Fang, at night), Sneasel →
  Weavile (Razor Claw, at night), Eevee → Leafeon/Glaceon, Piloswine →
  Mamoswine — aren't a missing-item problem an item mod can fix. This mod
  doesn't even generate a step for them: there's no method id to attach one
  to. Adding the item wouldn't help, because there'd be nothing to make it
  matter.

  This is specifically a FireRed limit, not a Pokémon-engine one. FireRed's
  evolution methods are a closed, hardcoded list of six (the engine turns
  off the `evolution_methods` registry entirely on Gen 3); no mod can add a
  seventh. Gen 1 and Gen 2 don't have that ceiling — `mod.content.evolution_methods`
  is a real, open registry there, which is exactly how the Gen 1 mod
  `g9-battle-engine` added a friendship-evolution trigger Red never had
  natively. On FireRed, only a mod willing to patch the engine's own
  evolution-check code (not merely register data) could add a trigger like
  this; nothing here attempts that.
- Learnsets are level-up only: 6,255 of the 9,331 level-up moves PokéAPI
  lists are moves FireRed has (67%), so 20 species (Kricketot, Budew, Burmy,
  Combee, the three Simisage/Simisear/Simipour monkeys, Tynamo, …) end up
  with fewer than 4 learnable moves. TM/HM, tutor and egg-move coverage is
  partial for the same reason: of 639 species, 636 get at least one TM/HM,
  628 get at least one tutor move, and 315 get at least one egg move.

## Regenerating the data

```bash
python -m pip install requests
python tools/build_species.py            # PokéAPI responses cached in tools/.cache
```
