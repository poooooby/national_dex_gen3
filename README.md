# National Dex Gen 3

**National Dex Gen 3 adds Generation 4 to 9 Pokémon to the Game Boy Advance games**
in [gen1recomp](https://github.com/bryanthaboi/gen1recomp): FireRed, LeafGreen,
Ruby, Sapphire and Emerald.

Those games only know 386 Pokémon. This mod teaches them the other 639, from
Turtwig (#387) to Pecharunt (#1025), so Sinnoh, Unova, Kalos, Alola, Galar and
Paldea Pokémon can exist in Kanto and Hoenn. Each one gets its stats, typing,
moves, ability, Pokédex entry, cry, and the evolutions that lead to it.

On its own it is the *foundation*: it adds the Pokémon, but not their pictures
and not a way to meet them in the wild. For the full experience, add the two
companion mods [below](#companion-mods-recommended).

## What it does

- **Adds 639 Pokémon** (#387–1025) that behave like any other Pokémon in the
  game: you can catch, train, evolve, trade and battle with them.
- **Gives them Gen 3 moves.** Gen 3 only has 354 moves, so a newer move is
  swapped, at the same level, for the closest Gen 3 move of the same type. Each
  Pokémon keeps the same number of moves as in the modern games.
- **Gives them an ability.** Gen 3 can't have new abilities, so each Pokémon gets
  the closest Gen 3 one (for example Bidoof's Simple becomes Own Tempo). It acts
  like that Gen 3 ability, not the real one.
- **Lets old Pokémon evolve into new ones**, such as Rhydon into Rhyperior,
  Magneton into Magnezone, Nosepass into Probopass, Scyther into Kleavor and
  Togetic into Togekiss.
- **Adds the evolution items** those evolutions need (Dusk Stone, Protector,
  Dubious Disc and 16 more), and **sells them in shops**: stones and trade items
  in Celadon's and Lilycove's department stores, the newest items in late-game
  marts. See [the item guide](docs/items.md) for prices and locations.
- **Adds 85 alternate forms** as Pokémon of their own: Galarian and Hisuian forms (Darumaka,
  Zorua, Goodra and more), Wormadam's cloaks, the five Rotom appliances, Oricorio's styles, Gourgeist
  and Pumpkaboo sizes, Lycanroc, Alcremie's creams, Urshifu Rapid Strike, and legendary forms like Giratina Origin and
  Kyurem Black. They show their normal Pokémon's Pokédex number. See [the forms guide](docs/pokemon/forms.md).
- **Adds cries** for all 639 Pokémon, and for each form.
- **Adds them to the Pokédex.** They appear in the National Pokédex list.
- **Pokédex pictures for every species, animated.** Every Pokédex entry, #1–1025 and each form,
  shows its sprite (from pokeemerald-expansion) centred and moving between its two frames.
- **A FORMS page in the Pokédex** for species with alternate forms: each form's picture with its
  name. On Ruby/Sapphire/Emerald choose FORMS (where CANCEL usually is); on FireRed/LeafGreen
  press A on the size/area page.
- **Fast Pokédex scrolling.** Hold a direction to keep moving through the Pokédex, faster the
  longer you hold it, instead of pressing again for every entry.
- **Keeps each Pokémon's real typing.** Gen 3 has no Fairy type, so a Fairy half is
  dropped (a pure Fairy becomes Normal). Togekiss stays Normal / Flying.

## What it does not do

- **It does not add battle sprites.** Without the sprite mod below, a new 
  Pokémon shows a wrong, blank or garbled picture. No party icons either.
- **It does not give forms a way to appear.** Gen 3 can't change a Pokémon's form, and nothing places
  forms in the wild, so for now they only come from a save editor, plus a few that evolve into each
  other. Megas and Gigantamax forms aren't included.
- **It does not put the new Pokémon in the wild.** Nothing here changes where
  Pokémon appear. Use Modern Spawns below; otherwise you'd have to
  cheat to get them.
- **It does not add new moves or abilities.** You'll never see Moonblast, Close
  Combat or modern abilities like Protean. Everything is mapped to what
  Gen 3 has, so a Pokémon plays like its modern self in spirit, not in detail.
- **It does not change the 386 original Pokémon**, the story, the trainers or
  the maps. Original Pokémon only gain the new evolutions.
- **A few evolutions are adapted.** Conditions Gen 3 can't check (a known move, a
  party member, rain, steps walked, coins, a held item at a time of day) are
  added on top and changed where needed, e.g. Piloswine → Mamoswine while
  knowing Rock Tomb. Only evolutions needing a regional form this mod lacks
  (Galarian Meowth and so on) do not work. See the
  [guide](docs/evolutions-and-forms.md).
- **TM, tutor and egg moves stay limited to what Gen 3 has.** Only the
  level-up moves are swapped for stand-ins.

## Companion mods (recommended)

These two aren't required to start the game, but without them most of the new
Pokémon will be missing or unseen.

### [G9 Battle Sprites (Gen 3)](https://github.com/poooooby/g9-battle-sprites-gen3)

**Why you need it: it adds the battle pictures.** This mod draws the Pokédex
pictures itself but ships no battle artwork. G9 Battle Sprites (Gen 3) gives every
new Pokémon animated battle sprites (front and back, normal and shiny), its summary
picture, and a party-menu icon. The original 386 Pokémon keep the game's own sprites. It's a
Gen 3 rewrite of [g9-battle-sprites](https://github.com/tectorifter/g9-battle-sprites)
by tectorifter.

### [Modern Spawns](https://github.com/poooooby/g1r_modern_spawns)

**Why you need it: it puts the new Pokémon in the wild.** Modern Spawns replaces
the wild Pokémon in each area with Pokémon from all generations, picked to fit
the place, by level, terrain, habitat, type and rarity. Each map keeps the game's
own encounter rates and levels, so the game feels the same, just with a modern
roster. It has options for how many generations can appear, how often rosters
change, and rare legendaries, in **OPTIONS → MODS → Modern Spawns**. It needs this
mod to know the new Pokémon on Gen 3 games.

With Modern Spawns installed, the Pokédex can also open a species you haven't
seen yet, as long as Modern Spawns puts it somewhere: scroll to its number and
press A. Its name and picture stay hidden, but its AREA page shows where it lives.

**Suggested setup:** install all three (National Dex Gen 3, G9 Battle Sprites (Gen
3), Modern Spawns) and start a new game or load an existing save.

## Installing

1. Install [gen1recomp](https://github.com/bryanthaboi/gen1recomp) and import your
   own FireRed, LeafGreen, Ruby, Sapphire or Emerald game.
2. Download the latest `national_dex_gen3-….zip` from the
   [Releases page](https://github.com/poooooby/national_dex_gen3/releases/latest).
3. In the game, go to **MODS → Import mod .zip** and choose the file.
4. Do the same for the companion mods (links above), then make sure all are turned on.

## Player guides

- [Added items](docs/items.md): every item's price, where to buy it in FireRed /
  LeafGreen and Ruby / Sapphire / Emerald, and which Pokémon evolve with it.
- [Added Pokémon](docs/pokemon.md): all 639 Pokémon by generation, with typing,
  the Gen 3 ability each has in this game, and its level-up moves.
- [Alternate forms](docs/pokemon/forms.md): the 85 forms, with the same details.
- [Evolution and forms guide](docs/evolutions-and-forms.md): the special evolutions (Rockruff,
  Milcery, Sinistea and more), which evolutions do not work, and how to get each form.

## Credits

Cries and item sprites are fan-made; see [CREDITS.md](CREDITS.md). Pokémon and
all related names are the property of Nintendo, Creatures Inc. and GAME FREAK
inc. This is an unofficial fan project.

---

# For mod authors and developers

The rest of this page is technical.

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
the same numbering throughout, so a save's species numbers never move.

| Field | Source |
|---|---|
| Name, dex number, base stats, catch rate, base experience (capped at 255), growth rate, gender ratio, egg cycles, friendship, Pokédex kind/height/weight | PokéAPI |
| Types | PokéAPI. Gen 3 has no Fairy type, so Fairy is dropped; a pure Fairy type becomes Normal |
| Learnset | The level-up list from the newest game that has one, at its full length. A move Gen 3 lacks is replaced, at the same level, by the closest Gen 3 move the species doesn't already learn (`tools/move_map.py`: same type, then similar power, accuracy, priority and effect). Move names are read from the running game's own move registry |
| TM/HM compatibility | Every TM or HM (the same 58 machines in all five games) whose move the species can be taught by machine or tutor in any game (636 species; 37 of 58 machines on average) |
| Move tutors | Whichever tutors the running game has — FireRed/LeafGreen's 15, Ruby/Sapphire's none, or Emerald's own larger set — whose move the species can be taught in any game (628 species on FireRed/LeafGreen) |
| Egg moves | Egg moves Gen 3 has (315 species; many modern egg moves don't exist in Gen 3) |
| Abilities | Gen 3 abilities only: the cart's own (ids 1–75 and Air Lock at 77) are kept, and each newer ability is mapped to the closest Gen 3 one (`tools/ability_map.py`), e.g. Simple → Own Tempo, Moxie → Guts. The Gen 3 battle engine cannot take new abilities from a mod, so a species shows and behaves like the Gen 3 ability it was given, not its real one |
| Evolutions | Level, item, friendship and trade steps between species 1–1025 |
| Evolutions from the cart's species | Steps from the cart's own species into new ones, such as Magneton → Magnezone and Nosepass → Probopass with a Thunder Stone |

**Where to buy them.** The real games sell almost none of these, so placement
is by item type and how far into the game a store is (`data/shops.lua`):

| | FireRed / LeafGreen | Ruby / Sapphire / Emerald |
|---|---|---|
| Dusk, Dawn, Shiny and Ice Stone, Sachet, Whipped Dream | Celadon Dept. Store 4F (the stone floor) | Lilycove Dept. Store, supplements floor (Hoenn has no stone floor) |
| Protector, Electirizer, Magmarizer, Dubious Disc, Reaper Cloth | Celadon Dept. Store 5F (battle items) | Lilycove Dept. Store, battle-item floor |
| Gen 8-9 items | Six Island Mart (after the Elite Four) | Apples at Mossdeep, Armors and Metal Alloy at Sootopolis, Black Augurite and Peat Block at the Ever Grande League mart |

Prices are twice the sell price Bulbapedia lists for the earliest game that has
one (2,100 for most; Ice Stone and Metal Alloy 3,000; Black Augurite and Peat
Block 1,000), and 2,100 where it lists none. A store is found by its original
stock, so each entry covers every game with that list. LeafGreen's 23 stores are
identical to FireRed's (checked against both carts).

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

This mod draws the Pokédex pictures itself (every species and form; see CREDITS.md). Battle
sprites come from a sprite mod:

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

## API (`mod.exports`, `apiVersion = 1`)

| Export | Returns |
|---|---|
| `isActive()` | always `true` (kept for callers of version 1) |
| `provider()` | always `"national_dex_gen3"` (same) |
| `listSpecies()` | `{ { dex, id, slot, name, legendary, mythical } }` |
| `slotOf(idOrDex)` | the running game's slot |
| `evolutionsOf(idOrDex)` | national_dex's shape: `{ id, dex, evolvesFrom = { id, methods }, evolvesInto = { … } }`. Works for a cart species (#1–386) that gains a step into a new one, e.g. `evolutionsOf("RHYDON")`, not only for #387–1025. Lists a step whether or not its item currently resolves — this call doesn't say which |
| `setArtProvider(fn)` | registers an art provider |
| `setDexPeek(fn)` | `fn(speciesSlot) -> true` lets that **unseen** species open in the Pokédex in a limited view: the number shows, the name is dashes, the picture is the "?" one, no cry plays, and the Cry and Size pages stay closed, but its AREA page shows. The numerical list runs on to the last entry that can be opened. `nil` turns it off. Modern Spawns uses it so you can look up where an undiscovered species lives. Since 0.7.0 |

## Known limits

- **Without an art provider, battles show whatever the engine decodes for an
  unknown slot**: a wrong or garbled picture, which the engine may cache. Pair
  this mod with a sprite mod.
- No party icons. The engine has no sanctioned path for them on Gen 3.
- Cries play for every new species (`assets/cries/cries.pak`, from the Gen 9
  pack), by wrapping `Audio.playCry`. Not yet verified in-game; the cart's
  pitch/pan modes and the music duck are not reproduced.
- **The native Pokédex list now includes #387–1025 in National mode.** This mod raises the engine's `Dex.NATIONAL_MAX` (386) to 1025 because a mod that enumerates species up to that
  bound (Kanto Gear's wild-encounter guide builds its species cache that way)
  otherwise never sees a new species and silently drops its rows. The
  Pokédex list uses the same bound; this mod draws those entries' pictures
  itself. On Emerald this mod also supplies a
  Pokédex entry (category and size; no flavor text) for each new species,
  since a mod walking every National number asserts one exists. Seen/caught counting is unaffected
  (plain tables, no size limit).
- Moves newer than Gen 3 don't exist: the Gen 3 battle engine only has its own
  354, and a mod can't add a move with a new effect. A species' newer moves
  are replaced by the closest Gen 3 move (99% of attacks keep their type), so
  it plays like its modern self in spirit, not in detail. EV yields are 0.
- Evolutions into species past #151 need the National Dex unlocked, as in
  vanilla FireRed/LeafGreen/Emerald. (Ruby and Sapphire never had a National
  Dex at all in the original games; this still works there because
  gen1recomp's own National Dex support isn't gated on the cart.)
- Every item evolution this mod generates is live, because the mod provides
  the items (see above): the 15 steps from the cart's own species (Magneton
  → Magnezone, Rhydon → Rhyperior, Scyther → Kleavor, …) and the new
  species' own item steps. The items are sold in shops (see "Where to buy
  them" above and [the item guide](docs/items.md)).
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
- Level-up learnsets keep their modern length (9,302 moves across 639 species;
  6,255 of them are real Gen 3 moves and 3,047 are substitutes). Eight
  species still have fewer than 4 distinct moves because their real learnsets
  are that short (Spewpa, Wimpod, Cosmog, Cosmoem, Blipbug, Applin, Snom,
  Gimmighoul). TM/HM, tutor and egg moves are still limited to Gen 3's own
  moves, not substituted: of 639 species, 636 get at least one TM/HM and 315
  get at least one egg move. Tutor coverage (628 species get at least one
  tutor move) is counted against FireRed/LeafGreen's 15 tutors; it's lower
  on Ruby/Sapphire (no tutors at all) and may be higher on Emerald, whose
  own, larger tutor set this mod reads live rather than assumes.

## Regenerating the data

```bash
python -m pip install requests
python tools/build_species.py            # PokéAPI responses cached in tools/.cache
```
