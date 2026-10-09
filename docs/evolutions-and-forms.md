# Evolution and forms guide

A player's guide to the evolutions and alternate forms this mod adds, especially the ones
that work differently from the games you know. For every Pokémon's stats and moves see
[Added Pokémon](pokemon.md); for every item's price and shop see [Added items](items.md).

*This page is written by hand; the two pages above are generated from the mod's data.*

**How do I catch them?** None of the five games has a Gen 4-9 Pokémon (or any alternate form)
in its own wild encounter tables, so this mod only adds them to the game. A mod that changes
the spawn tables puts them in the wild: [Modern Spawns](https://github.com/poooooby/g1r_modern_spawns)
re-picks the species on every map and also places the wild forms, and any other mod that edits
the encounter tables can do the same. **You do not need a save editor** to catch them, to find
the forms that appear in the wild, or to evolve them.

**Contents**

- [Which clock the game reads](#which-clock-the-game-reads)
- [Getting the evolution items](#getting-the-evolution-items)
- [Rockruff → Lycanroc](#rockruff--lycanroc)
- [Milcery → Alcremie](#milcery--alcremie)
- [Sinistea and Poltchageist](#sinistea-and-poltchageist)
- [Original Pokémon with new evolutions](#original-pokémon-with-new-evolutions)
- [Other evolutions worth knowing](#other-evolutions-worth-knowing)
- [Evolutions that do not work](#evolutions-that-do-not-work)
- [Alternate forms](#alternate-forms)

## Which clock the game reads

Some evolutions depend on the time of day: Midnight Lycanroc, the day and night Alcremie
creams, and the friendship evolutions of Budew, Riolu, Chingling and Snom. For all of them,
**night is 8 pm to 4 am, dusk is 7 pm to 8 pm, and day is every other hour.** Dusk is the last
hour of the day, so anything that asks for "day" also works at dusk.

- **FireRed and LeafGreen** have no clock of their own, so they use your **device's** clock.
- **Ruby, Sapphire and Emerald** have their own clock, which is your device's time shifted by
  whatever time you set in the game. By default they use that **in-game clock**. To use your
  device's clock instead, open the mod's settings in the Mod Manager and set **Clock Source**
  to **Device**.

## Getting the evolution items

Most of the newer evolutions need an item that none of the five games has. The mod adds
30 of them and puts them on sale, by kind and by how far into the game the store is:

| Kind of item | FireRed / LeafGreen | Ruby / Sapphire / Emerald |
|---|---|---|
| Stones, Sachet, Whipped Dream | Celadon Dept. Store 4F | Lilycove Dept. Store (supplements) |
| Trade items (Protector, Electirizer, Magmarizer, Dubious Disc, Reaper Cloth) | Celadon Dept. Store 5F | Lilycove Dept. Store (battle items) |
| Apples, pots, sweets | Six Island Mart | Mossdeep City Mart |
| Armors, Metal Alloy, teacups | Six Island Mart | Sootopolis City Mart |
| Black Augurite, Peat Block | Six Island Mart | Ever Grande City Pokémon League mart |

[Added items](items.md) lists every item with its exact price and shop.

## Rockruff → Lycanroc

Rockruff evolves when it levels up at **level 25 or higher**, and which Lycanroc you get
depends on when and how:

| When it levels up | You get |
|---|---|
| At **dusk** (7 pm to 8 pm) | **Dusk Lycanroc** |
| At **night** (8 pm to 4 am) | **Midnight Lycanroc** |
| At any other time | **Midday Lycanroc** |

See [the clock](#which-clock-the-game-reads) for which clock is used.

- All three are Lycanroc to the Pokédex (#745).

## Milcery → Alcremie

Milcery evolves when it levels up at **level 25 or higher while holding one of the seven
sweets** (Strawberry, Berry, Love, Star, Clover, Flower or Ribbon Sweet). Without a sweet
it does not evolve. All seven sweets do exactly the same thing, and the sweet is not used
up.

Which Alcremie you get depends on the time and on the Milcery itself:

| Condition | Alcremie |
|---|---|
| **Daytime** (4 am to 8 pm) | Vanilla Cream, Ruby Cream, Matcha Cream or Mint Cream |
| **Night** (8 pm to 4 am) | Lemon Cream, Salted Cream, Ruby Swirl or Caramel Swirl |
| **Dusk** (7 pm to 8 pm) | **Rainbow Swirl** |

- Each of the four creams is equally likely (one in four), but it is decided by that
  individual Milcery, so waiting for a different moment or leveling at a different time
  will not change which of the four it is. Daytime and night give a different set.
- Rainbow Swirl needs only the dusk hour and a held sweet; friendship does not matter. At
  any other time you get the day or night creams above.
- Day, dusk and night follow [the clock the game reads](#which-clock-the-game-reads).
- In the real games each cream also comes in seven decorations; here there is one Alcremie
  per cream, and the sweet does not change how it looks.
- With the [G9 Battle Sprites Gen3](https://github.com/poooooby/g9-battle-sprites-gen3)
  companion mod, every Alcremie uses the Vanilla Cream artwork, because that mod has only one
  Alcremie picture.

## Sinistea and Poltchageist

Use the item on the Pokémon, the usual way to use an evolution item. As in the real games,
each item goes with one of the two looks of the Pokémon, and it evolves into the same look:

| Pokémon | Item | Evolves into |
|---|---|---|
| Sinistea (the normal, phony look) | Cracked Pot | Polteageist |
| Sinistea (Antique) | Chipped Pot | Polteageist (Antique) |
| Poltchageist (the normal, counterfeit look) | Unremarkable Teacup | Sinistcha |
| Poltchageist (Artisan) | Masterpiece Teacup | Sinistcha (Masterpiece) |

The Antique and Artisan looks are [forms](#alternate-forms): they can turn up in the wild
with Modern Spawns (see [Alternate forms](#alternate-forms)), or come from the save editor. The
wrong item does nothing.

## Original Pokémon with new evolutions

These Pokémon already exist in your game and now have a newer evolution too. "Use" means
use the item on it; "trade" means trade it while it holds the item.

| Pokémon | Item | Evolves into |
|---|---|---|
| Magneton | Thunder Stone (use) | Magnezone |
| Nosepass | Thunder Stone (use) | Probopass |
| Eevee | Leaf Stone (use) | Leafeon |
| Eevee | Ice Stone (use) | Glaceon |
| Togetic | Shiny Stone (use) | Togekiss |
| Roselia | Shiny Stone (use) | Roserade |
| Murkrow | Dusk Stone (use) | Honchkrow |
| Misdreavus | Dusk Stone (use) | Mismagius |
| Kirlia | Dawn Stone (use) | Gallade |
| Snorunt | Dawn Stone (use) | Froslass |
| Scyther | Black Augurite (use) | Kleavor |
| Ursaring | Peat Block (use) | Ursaluna |
| Rhydon | Protector (trade) | Rhyperior |
| Electabuzz | Electirizer (trade) | Electivire |
| Magmar | Magmarizer (trade) | Magmortar |
| Porygon2 | Dubious Disc (trade) | Porygon-Z |
| Dusclops | Reaper Cloth (trade) | Dusknoir |

Pokémon this mod adds have their own item evolutions too (for example Lampent → Chandelure
with a Dusk Stone, or Doublade → Aegislash). They are listed under each item in
[Added items](items.md).

## Other evolutions worth knowing

- **Flabébé → Floette** at level 19 and **Floette → Florges** with a Shiny Stone, in the same
  flower colour all the way (red, yellow, orange, blue or white).
- **Shellos → Gastrodon** at level 30, the west-sea one into the west-sea Gastrodon and the
  east-sea one into the east-sea Gastrodon.
- **Deerling → Sawsbuck** (level 34) always gives the spring Sawsbuck, and **Scatterbug → Spewpa →
  Vivillon** (levels 9 and 12) always the base look; the other seasons and patterns are not
  modelled.
- **Darumaka (Galar) → Darmanitan (Galar)** with an Ice Stone, and
  **Zorua (Hisui) → Zoroark (Hisui)** at level 30. See [Alternate forms](#alternate-forms).
- **Pumpkaboo and Gourgeist** come in four sizes (average, small, large, super). Each
  Pumpkaboo evolves by trade into the Gourgeist of the same size.
- **Gender decides some evolutions**, as in the real games:
  - Only **female** Combee evolve into Vespiquen (level 21) and only **female** Salandit into
    Salazzle (level 33).
  - **Kirlia** evolves into Gallade with a Dawn Stone only if it is **male**, and **Snorunt**
    into Froslass with a Dawn Stone only if it is **female**.
  - **Burmy** at level 20 becomes Mothim if it is **male**. A **female** becomes Wormadam, and
    which cloak depends on **where its last battle was fought**: grass or water gives the Plant
    Cloak, sand, a mountain or a cave the Sandy Cloak, and a building (gyms, the Pokémon
    League and so on) the Trash Cloak. A level-up outside battle, such as a Rare Candy, uses
    the last battle's ground; before your first battle it counts as a building.
  - **Espurr** (level 25) and **Lechonk** (level 18) evolve into Meowstic and Oinkologne
    whatever their gender. Only the artwork differs: with the sprite mod, a female shows her own
    picture when she is the enemy or in the Pokédex and summary (her back view and menu icon
    are the male's). Stats, moves and abilities are the same.
- **White-striped Basculin → Basculegion** once it has taken **294 recoil damage** in total,
  counted across all its battles (moves like Take Down, Double-Edge and Volt Tackle; Rock Head
  takes none). A male becomes Basculegion and a female the female Basculegion, which has her own
  stats. It evolves at the end of the battle in which it reaches 294 (a battle you win), like a
  level-up evolution. Only the white-striped Basculin does this; the normal red-striped one never
  evolves. The white-striped form can turn up in the wild with Modern Spawns, or come from the save editor.
- **Friendship at day or night.** Budew → Roselia and Riolu → Lucario need friendship in the
  daytime, and Chingling → Chimecho and Snom → Frosmoth need it at night (friendship 220 or
  more). They follow [the clock the game reads](#which-clock-the-game-reads), so they work in all
  five games. The same goes for Eevee → Espeon or Umbreon where the game has that evolution.

## Evolutions that do not work

Gen 3 can only evolve a Pokémon by level, a stone, a trade, trading with an item, or
friendship, so these newer ways cannot be done and the Pokémon stays as it is.

**Needs to know a certain move**

| Pokémon | Would evolve into | Needs |
|---|---|---|
| Lickitung | Lickilicky | Rollout |
| Tangela | Tangrowth | Ancient Power |
| Yanma | Yanmega | Ancient Power |
| Piloswine | Mamoswine | Ancient Power |
| Aipom | Ambipom | Double Hit |
| Girafarig | Farigiraf | Twin Beam |
| Bonsly | Sudowoodo | Mimic |
| Mime Jr. | Mr. Mime | Mimic |
| Steenee | Tsareena | Stomp |
| Poipole | Naganadel | Dragon Pulse |
| Clobbopus | Grapploct | Taunt |
| Dipplin | Hydrapple | Dragon Cheer |

**Holding an item and leveling up at a time of day:** Sneasel → Weavile (Razor Claw,
night), Gligar → Gliscor (Razor Fang, night) and Happiny → Chansey (Oval Stone, day).

**Needs a regional form of the original Pokémon** that this mod does not include:
Meowth (Galar) → Perrserker, Farfetch'd (Galar) → Sirfetch'd, Mr. Mime (Galar) → Mr. Rime,
Corsola (Galar) → Cursola, Linoone (Galar) → Obstagoon, Wooper (Paldea) → Clodsire,
Qwilfish (Hisui) → Overqwil, Sneasel (Hisui) → Sneasler.
Yamask (Galar) → Runerigus is also out, since it needs taking damage in a specific place.

**Needs something Gen 3 has no way to check**

| Pokémon | Would evolve into | Needs |
|---|---|---|
| Eevee | Sylveon | A Fairy-type move and affection |
| Mantyke | Mantine | A Remoraid in the party |
| Pancham | Pangoro | A Dark-type Pokémon in the party |
| Inkay | Malamar | The console held upside down |
| Sliggoo | Goodra | Leveling up in rain |
| Finizen | Palafin | Leveling up in multiplayer |
| Karrablast / Shelmet | Escavalier / Accelgor | Trading with each other |
| Pawmo, Bramblin, Rellor | Pawmot, Brambleghast, Rabsca | Walking a number of steps |
| Gimmighoul | Gholdengo | Collecting coins |
| Meltan | Melmetal | Special candies |
| Bisharp | Kingambit | Beating three Bisharp |
| Primeape | Annihilape | Using Rage Fist 20 times |
| Stantler, Qwilfish (Hisui) | Wyrdeer, Overqwil | Special move styles |
| Kubfu | Urshifu | Special scrolls and a tower |
| Toxel | Toxtricity | Its nature |
| Dunsparce, Tandemaus | Dudunsparce, Maushold | A hidden random value |



## Alternate forms

A form is a Pokémon of its own with its own stats, typing and moves, but it counts as its
base Pokémon in the Pokédex. For example Darumaka (Galar) is Darumaka #554, and marking
it seen or caught also marks Darumaka. Forms never add to the Pokédex totals.

**How to get them.** None of the games has a form in its own wild tables, and the games have
no way to change one Pokémon into a form. A form can come from:

- **The wild**, with a spawn mod. [Modern Spawns](https://github.com/poooooby/g1r_modern_spawns)
  places the forms that are wild Pokémon in the real games: the Galarian and Hisuian forms
  (Darumaka, Darmanitan, Yamask, Stunfisk, Zorua, Zoroark, Lilligant, Braviary, Sliggoo, Goodra,
  Avalugg) and the looks of Rotom, Oricorio, Pumpkaboo, Gourgeist, Wormadam, Lycanroc (Midnight),
  Flabébé, Floette, Florges, Alcremie, Shellos, Gastrodon, Basculin, Basculegion and the tea set.
  A species with several looks shows up as itself or one of them with equal odds. Any other mod
  that edits the spawn tables can add forms the same way.
- **Evolution**, for the forms in the next table, and
- the gen1recomp **save editor**, which can create any form, but is **not required**.

| Form | How |
|---|---|
| Midnight and Dusk Lycanroc | Evolve Rockruff, see [above](#rockruff--lycanroc) |
| The eight Alcremie creams past Vanilla | Evolve Milcery, see [above](#milcery--alcremie) |
| Darmanitan (Galar, Standard) | Evolve Darumaka (Galar) with an Ice Stone |
| Zoroark (Hisui) | Evolve Zorua (Hisui) at level 30 |
| Gourgeist (small, large, super) | Trade the matching Pumpkaboo size |
| Wormadam (Sandy, Trash) | Evolve a female Burmy after a battle in a cave or a building |
| Gastrodon (East) | Evolve Shellos (East) at level 30 |
| Polteageist (Antique), Sinistcha (Masterpiece) | Use the matching pot or teacup on the Antique Sinistea or the Artisan Poltchageist |
| Basculegion (female) | Evolve a female white-striped Basculin, see [above](#other-evolutions-worth-knowing) |
| Floette and Florges in yellow, orange, blue and white | Evolve the same-colour Flabébé (level 19) and Floette (Shiny Stone) |

The starting forms of those lines (Darumaka (Galar), Zorua (Hisui), Shellos (East), the Antique
Sinistea, the Artisan Poltchageist, the white-striped Basculin and the yellow, orange, blue and
white Flabébé) are all forms Modern Spawns can put in the wild, so you can catch them and evolve
them. Only the forms that are not wild Pokémon need the save editor or a mod that places them:
the Origin, Therian, Black/White Kyurem, Crowned, Ogerpon-mask and other item or fusion forms,
Floette (Eternal), Bloodmoon Ursaluna, Rapid Strike Urshifu and the Hisuian Samurott and
Decidueye. (Dusk Lycanroc is not on that list: evolve a Rockruff at dusk.)

**All 84 forms**

| Group | Forms |
|---|---|
| Regional (13) | Darumaka (Galar), Darmanitan (Galar, Standard), Yamask (Galar), Stunfisk (Galar), Zorua (Hisui), Zoroark (Hisui), Samurott (Hisui), Lilligant (Hisui), Braviary (Hisui), Sliggoo (Hisui), Goodra (Hisui), Avalugg (Hisui), Decidueye (Hisui) |
| Permanent (19) | Wormadam (Sandy, Trash), Rotom (Heat, Wash, Frost, Fan, Mow), Oricorio (Pa'u, Pom-Pom, Sensu), Pumpkaboo and Gourgeist (small, large, super), Lycanroc (Midnight, Dusk), Urshifu (Rapid Strike) |
| Alcremie (8) | Ruby Cream, Matcha Cream, Mint Cream, Lemon Cream, Salted Cream, Ruby Swirl, Caramel Swirl, Rainbow Swirl (Vanilla Cream is the normal Alcremie) |
| Looks that stay one species (14) | Shellos and Gastrodon (East), Flabébé, Floette and Florges (yellow, orange, blue, white) |
| Basculin line (2) | Basculin (White-Striped), Basculegion (Female) |
| Tea set looks (4) | Sinistea (Antique), Polteageist (Antique), Poltchageist (Artisan), Sinistcha (Masterpiece) |
| Legendary (24) | Giratina, Dialga and Palkia (Origin), Shaymin (Sky), Tornadus, Thundurus, Landorus and Enamorus (Therian), Kyurem (Black, White), Hoopa (Unbound), Necrozma (Dusk Mane, Dawn Wings), Calyrex (Ice Rider, Shadow Rider), Zacian and Zamazenta (Crowned), Ogerpon (Wellspring, Hearthflame, Cornerstone masks), Ursaluna (Bloodmoon), Zygarde (10%, Complete), Floette (Eternal) |

Megas, Gigantamax and in-battle or purely cosmetic forms are not included.

Stats, typing, abilities and moves for each form are in [Alternate forms](pokemon/forms.md).

**Keep the mod on.** A Pokémon in a form is saved as a species number only this mod knows.
If you turn the mod off while a form is in your party or PC, the game cannot draw it and
can crash. The same is true of every other Pokémon this mod adds.

**Pictures.** The mod ships no artwork. Install
[G9 Battle Sprites Gen3](https://github.com/poooooby/g9-battle-sprites-gen3) to see them;
without it a form has no picture.
