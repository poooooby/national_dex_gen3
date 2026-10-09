# Changelog

All notable changes to this mod are documented here, in
[keep a changelog](https://keepachangelog.com/en/1.1.0/) format.

## [0.6.2] - 2026-10-09

### Added

- **Item descriptions** for the 36 evolution items, shown in the marts and the Bag: what the item is,
  in the cart's style, within the mart's 3 lines of about 21 characters.

### Changed

- **Item names** are in capitals like the cart's, and the long ones are abbreviated to the cart's 14
  characters (UNREMARK. CUP, MASTERPC. CUP, AUSPIC. ARMOR, MALIC. ARMOR, STRAWBRY SWEET, DARK SCROLL,
  WATER SCROLL).
- **Item icons** are no longer resampled (a smoothing filter left ghosting at the edges): the art is
  cropped and centred in its 24x24 cell, and only larger art is scaled, with nearest neighbour.

## [0.6.1] - 2026-10-09

### Added

- **Evolutions Gen 3 could not express**, decided by the `evolution.check` hook
  (`src/conditional_evos.lua`) with new `when` keys: `knows` (a move; real, or a TM / level-up
  stand-in the Pokemon can already learn), `party` (a species or a type), `weather` (rain),
  `uses` (Rage x20), `steps` (1000 as lead), `coins` (999, spent on evolving). Covers Lickitung,
  Piloswine, Tangela, Yanma, Aipom, Girafarig, Dunsparce, Bonsly, Mime Jr., Steenee, Clobbopus,
  Poipole, Dipplin, Eevee -> Sylveon, Mantyke, Pancham, Sliggoo, Primeape, Pawmo, Bramblin,
  Rellor, Gimmighoul, Sneasel, Gligar, Happiny and Bisharp. Cart species gain steps through
  `data/species/crossgen.lua`; no cart learnset changes.
- **Plain level-ups** for Stantler (31), Meltan (40), Karrablast and Shelmet (37), Toxel, Tandemaus,
  Inkay and Finizen.
- **6 items** (36 in all, indices 930-935): Razor Claw, Razor Fang, Oval Stone, Leader's Crest,
  Scroll of Darkness, Scroll of Waters, sold in the same stores as the other held and trade items.
  Kubfu -> Urshifu with a scroll (Waters gives Rapid Strike).
- **Qwilfish (Hisui)** form (`QWILFISH_HISUI`, slot 1174; 85 forms) evolving into Overqwil at 28.
- **Manaphy lays a Phione egg** (`src/breeding.lua`).
- `src/counters.lua` replaces `src/recoil.lua` (recoil, Rage uses, steps as lead, coins).
- Tests: `known_move_test.lua`, `counters_test.lua`.
- **National Dex option**: turns the National Pokedex on without the story unlock (`src/national_unlock.lua`).
  Nothing is written to the save.
- **Register Owned option** (on by default): opening the Pokedex marks every party and PC Pokemon as seen and
  caught, so Pokemon added with a save editor register (`src/dex_sync.lua`).
- **Pokedex summaries** for every added species (newest English PokeAPI entry that fits the Gen 3 text box)
  on FireRed, LeafGreen, Ruby, Sapphire and Emerald, plus category, height and weight on FRLG.
- **Pokedex on Ruby/Sapphire/Emerald scrolls past #386.** `fixups.installRseDexOrders` extends the cart's
  National / A-Z / weight / height orders; `src/dex_patch.lua` swaps the two literal `386`s in the
  engine's own `rse/pokedex.lua` (read as source) and merges a patched copy into the live module.
  Silent fallback to the stock Pokedex if the source is unreadable or different, with a logged
  warning. The A-Z, weight and height lists include the added species on all five games. Test:
  `rse_dex_patch_test.lua`.
- **FireRed / LeafGreen Pokedex**: left and right page the list instead of switching between the Kanto and
  National lists, which left the screen blank after pressing left (`DexPatch.installFrlg`).

## [0.6.0] - 2026-10-08

### Removed

- **1025Dex compatibility.** 1025Dex is now a manifest conflict, so this mod no longer checks
  for it and no longer steps aside; `isActive()` is always `true` and `provider()` always
  `"national_dex_gen3"`.

### Added

- **The tea set looks**: 4 forms (`SINISTEA_ANTIQUE`, `POLTEAGEIST_ANTIQUE`,
  `POLTCHAGEIST_ARTISAN`, `SINISTCHA_MASTERPIECE`, slots 1170-1173; 84 forms in all) and the item
  rule now matches the real games: Cracked Pot evolves the normal Sinistea, Chipped Pot the
  Antique one, Unremarkable Teacup the normal Poltchageist and Masterpiece Teacup the Artisan one,
  each into the same look. Before, either item of a pair worked on either look.
- **Basculin -> Basculegion by recoil** (`src/recoil.lua`): the recoil damage a Pokemon takes
  (a quarter or a third of a recoil move's damage, from the `battle.damage_dealt` event; none
  with Rock Head) is added to a `recoilTaken` total on the party Pokemon, saved with it. At
  294 the white-striped Basculin (new form `BASCULIN_WHITE_STRIPED`) is marked for the
  end-of-battle evolution check and becomes Basculegion (male) or the new
  `BASCULEGION_FEMALE` form. 80 forms now, slots 1090-1169.
- **More form-dependent evolutions.** 14 new forms (`tools/form_list.py`, slots 1154-1167):
  the east-sea Shellos and Gastrodon, and Flabébé, Floette and Florges in yellow, orange,
  blue and white; each evolves into its own kind (Shellos 30, Flabébé 19, Floette with a Shiny
  Stone). Pumpkaboo (average) now trades into Gourgeist (average) like the other sizes. Deerling
  -> Sawsbuck (spring), Scatterbug -> Spewpa -> Vivillon (base) now evolve. A female Burmy's
  Wormadam cloak follows the terrain of its last battle (`when.terrain`: grass / water Plant,
  sand / mountain / cave Sandy, buildings Trash, from `src.core.game3.battle.bg`).
  Meowstic and Oinkologne have a female look in the sprite mod only.
- **Gender-dependent evolutions** (`when.gender` in `src/conditional_evos.lua`): only female
  Combee -> Vespiquen and Salandit -> Salazzle; Burmy -> Wormadam (female, Plant Cloak) or
  Mothim (male); male Kirlia -> Gallade and female Snorunt -> Froslass with a Dawn Stone
  (item evolutions have no hook, so `Evolution.targetSpecies` is wrapped to veto the wrong
  gender); Espurr -> Meowstic and Lechonk -> Oinkologne, which reach the same species for
  both genders. Before, gender was ignored and either gender evolved.
- **Device clock for time-of-day evolutions** (`src/clock.lua`, `options.lua`). FireRed
  and LeafGreen, which have no clock, now use the device's; Ruby, Sapphire and Emerald get a
  **Clock Source** option (In-game, the default, or Device). Night is 20:00-04:00, dusk is
  19:00-20:00 and day is every other hour (dusk counts as day). The friendship day/night evolutions (Budew, Riolu, Chingling, Snom, and
  Eevee where the cart has them) are decided by this clock too, so they now work on
  FireRed and LeafGreen and use these hours instead of the engine's noon/midnight split.
- **Evolution and forms guide** (`docs/evolutions-and-forms.md`, written by hand) for players,
  and `docs/items.md` now lists held-item evolutions (Dusk Lycanroc, Alcremie) under their items.
- Cracked Pot and Chipped Pot cost 3000 (Bulbapedia's buy price).
- **Tea evolutions**: Cracked Pot / Chipped Pot (Sinistea -> Polteageist) and
  Unremarkable Teacup / Masterpiece Teacup (Poltchageist -> Sinistcha) are registered
  as items (indices 919-922, with Bag icons; see the tea set looks entry above for which goes with which). Item steps
  now ignore PokéAPI's form tags, which also gives Floette -> Florges (Shiny Stone)
  and Eevee -> Leafeon / Glaceon (Leaf / Ice Stone).
- **Milcery -> Alcremie** at level 25 while holding any of seven new sweets
  (Strawberry, Berry, Love, Star, Clover, Flower, Ribbon; items 923-929, with Bag
  icons): one of four creams by day (Vanilla, Ruby, Matcha, Mint) or four by night
  (Lemon, Salted, Ruby Swirl, Caramel Swirl), each 1 in 4 from the Pokemon's personality,
  or Rainbow Swirl at dusk (19:00-20:00). Day is 04:00-20:00 (see the
  clock entry above). The sweet is not consumed.
- The tea and sweet items are sold at the Gen 8-9 marts (Six Island, Mossdeep, Sootopolis).
- **Rockruff -> Lycanroc by the clock** (`src/conditional_evos.lua`,
  wrapping the `evolution.check` hook): at level 25 it becomes Midday Lycanroc,
  Midnight Lycanroc at night (20:00-04:00) or Dusk Lycanroc at dusk (19:00-20:00);
  no held item is needed.
- **64 alternate forms** (`tools/form_list.py`; see the entry above for the 14 added later), each registered as a species of its
  own at slots 1090-1153 (`SLOT_CAP` is now 1200), using the original `national_dex`
  mod's ids (`WORMADAM_SANDY`, `DARUMAKA_GALAR`, ...) so the sprite pack and other
  mods keyed to national_dex link up: 13 Galarian/Hisuian forms, 19 permanent forms
  (Wormadam cloaks, Rotom appliances, Oricorio styles, Pumpkaboo/Gourgeist sizes,
  Lycanroc Midnight/Dusk, Urshifu Rapid Strike) and 24 legendary item/fusion forms
  (Origin, Therian, Black/White Kyurem, Crowned, ...) and Alcremie's eight other creams. Megas, Gigantamax and
  in-battle/cosmetic forms are out. A form's slot is saved in player saves, so the
  list is append-only. Native saves are safe (a species is a plain number); a save
  holding a form still needs this mod on, as it already does for the 639.
  - A form reports its base's National number and never takes the base's place in
    the number map or its Pokédex entry. Marking a form seen/caught also marks its
    base, and the Pokédex counts skip form slots (otherwise each form would count as
    a species).
  - Records carry `baseSpecies`, `form` and `baseDex`; Modern Spawns skips such
    records, so forms never spawn by accident.
  - Form-to-form evolutions Gen 3 can express: Darumaka-Galar -> Darmanitan-Galar
    (Ice Stone), Zorua-Hisui -> Zoroark-Hisui (30), Pumpkaboo -> Gourgeist by trade.
  - API version 2: `listForms()`, `formsOf()`, `baseDexOf()`, `idOfSlot()`;
    `listSpecies()` still lists the 639 base species only.
  - Cries for each form (shared with the base where the pack has none).
  - Six abilities that appear only on forms are mapped (Gorilla Tactics, Mimicry,
    As One x2, Mind's Eye, Power Construct).
- `docs/`: a player reference, generated from the mod's own data. `items.md`
  lists every added item with its price, where it is sold in FireRed /
  LeafGreen and Ruby / Sapphire / Emerald, and what evolves with it;
  `pokemon.md` and `pokemon/gen4.md`-`gen9.md` list all 639 species with
  typing, Gen 3 ability and level-up learnset.
- The 19 evolution items are now sold, by item type and progression:
  stones and Sachet/Whipped Dream on Celadon Dept. Store 4F (FRLG) and the
  Lilycove supplements floor (RSE, which has no stone floor); the held trade
  items on the battle-item floors; the Gen 8-9 items in late marts (Six
  Island; Mossdeep, Sootopolis and the Ever Grande League mart). There is no
  shop registry, so `src/shops.lua` wraps `Marts.itemsFor`. Stores are found
  by their original stock, so one entry covers every game with that list.
- Real prices instead of 0 (which would have sold them for free): twice the
  earliest sell price Bulbapedia lists, else 2,100. Bulbapedia is credited in
  CREDITS.md.

### Changed

- Level-up learnsets keep their full modern length. A move Gen 3 lacks (3,047
  of 9,302 learnset moves, 382 distinct moves) is replaced at the same level
  by the closest Gen 3 move the species doesn't already learn
  (`tools/move_map.py`, scored against the cart's move table and PokéAPI:
  type first, then power, accuracy, priority and effect). 99% of attacks keep
  their type; the 4 that couldn't are listed in the build report.
- Togekiss is Normal/Flying again: the builder used today's typing and lost
  its Fairy half to pure Flying, ignoring PokéAPI's pre-Fairy typing
  (`past_types`). It was the only species affected.

## [0.5.1] - 2026-10-08

### Fixed

- On Emerald, every species past #386 was still missing from Kanto Gear's
  wild-encounter guide after 0.4.0, and its species cache could fail
  outright: it walks every National number and asserts a Pokédex entry
  exists for each, and Emerald's entries end at slot 411. This mod now
  answers `Mapsec.readLua("pokemon/pokedex/entries.lua")` with an entry
  (category, height, weight from PokéAPI; blank flavor text) for every
  species it registers. Other games fall back to a blank entry on their own
  and are untouched.

## [0.5.0] - 2026-10-07

### Added

- Registers the 19 evolution items no Gen 3 game has (Dusk Stone, Protector,
  Black Augurite, ...) at indices 900-918, so every evolution this mod
  generates is live with no companion item mod. Rhydon -> Rhyperior,
  Scyther -> Kleavor and the other 13 cart-species steps, and the new
  species' own item steps, no longer wait. Another mod registering one of
  the same items still works: whichever loads first (lower manifest
  priority number) keeps the slot, and the evolution resolves either way.
- Bag icons for all 19 (`assets/items/icons.png`, 24x24, from the
  third-party pokesprite pack), drawn on FireRed/LeafGreen and
  Ruby/Sapphire/Emerald by wrapping the Bag's icon draw. Not yet verified
  in-game. Six Gen 9 items missing from the pack (Auspicious/Malicious Armor,
  Black Augurite, Metal Alloy, Peat Block, Syrupy Apple) were added by hand.

- Cries for all 639 species (`assets/cries/cries.pak`, 10 MB, every Ogg packed into
  one file; `data/cries.lua` indexes it), played by wrapping `Audio.playCry`.
  Not yet verified in-game; the cart's pitch/pan modes and the music duck
  while a cry plays are not reproduced.

### Changed

- Species with no Gen 3 ability (277 of 639, e.g. Bidoof, Eiscue, Drifloon)
  now have one: every newer ability is mapped to the closest ability the
  cart has (`tools/ability_map.py`, 201 entries, each with a reason). The
  Gen 3 battle engine hard-codes abilities by name and a mod cannot add
  one, so a species shows and behaves like the Gen 3 ability it was given.
  Also fixes Air Lock, which was mapped onto the cart's unused Cacophony
  slot (PokéAPI 76 vs the cart's 77), and gives species whose Gen 4+ regular
  ability maps (e.g. Solid Rock on Rhyperior) a second slot.
- This is a deliberate exception to the mod's "never ship artwork" rule,
  scoped to these item icons; species art is still a sprite mod's job.
- `tests/register_test.lua` and `tests/companion_item_test.lua` updated for
  items no longer waiting.

## [0.4.0] - 2026-10-07

### Changed

- Raises the engine's `Dex.NATIONAL_MAX` from 386 to 1025 once this mod has
  registered its species (never when 1025Dex provides them, never lowered).
  Kanto Gear's wild-encounter guide builds its species cache over
  `1..Dex.NATIONAL_MAX`, so every species past #386 was silently missing
  from it and Modern Spawns' generated rows for them vanished from the
  guide. Side effect, accepted: the native National Pokédex list uses the
  same bound and now lists #387-1025, without art unless a sprite mod
  provides it. Seen/caught counting already handled species past the old
  bound and is unaffected.

## [0.3.2] - 2026-10-05

### Added

- `tests/rse_test.lua`, which actually proves 0.3.1's claim rather than
  just asserting it: loads this mod against real imported Emerald, Ruby
  and Sapphire carts and checks registration, reload repairs, TM/HM and
  egg-move compatibility, tutor compatibility (present on Emerald, and
  correctly absent with no error on Ruby/Sapphire), and the Magneton ->
  Magnezone cross-generation evolution -- the same checks `register_test.lua`
  already makes on FireRed, confirming they hold on the other three carts
  too. `tests/_gen3.lua`'s `H.gen3Data()` now takes a `game` argument (still
  defaulting to `"firered"`) and tolerates a cart with no `tutor.lua` at all
  (Ruby/Sapphire), the same way the real engine's own `MoveLearn` already
  does. No production code changed.

## [0.3.1] - 2026-10-05

### Changed

- Documented Ruby, Sapphire and Emerald as explicitly supported alongside
  FireRed and LeafGreen. `manifest.json` already targeted `games: ["gen3"]`
  (all five versions) and nothing under `src/` was ever tied to FireRed's
  own registries -- moves, items and species are always resolved against
  whichever game is running -- so this is a documentation and comment
  correction, not a behavior change. Docs that cited FireRed/LeafGreen-only
  facts (15 move tutors, which evolution items are present) now say so
  explicitly, since those numbers differ on Ruby/Sapphire (no tutors) and
  Emerald (its own larger tutor set).

## [0.3.0] - 2026-09-25

### Changed

- An evolution step whose item FireRed doesn't have is no longer dropped
  permanently. It now waits and is re-checked against the item registry
  every time the engine loads its species tables (boot and every reload),
  so it activates automatically the moment any installed mod registers a
  matching item — before or after this mod loads, this session or a later
  one — with no change to either mod. A one-line log summarizes what's
  waiting, if anything is.
- `evolutionsOf` now also answers for a cart species (#1–386) that gains a
  step into a new one (e.g. `evolutionsOf("RHYDON")`), not only for
  #387–1025.

## [0.2.0] - 2026-09-25

### Added

- TM/HM compatibility: every FireRed TM or HM whose move a species can be
  taught by machine or tutor in any game.
- Move tutors: FireRed's 15 tutors, added to the engine's tutor data whenever
  it loads.
- Egg moves limited to FireRed's moves.
- Evolutions from FireRed's own species into new ones where FireRed has the
  item (Magneton → Magnezone, Nosepass → Probopass).

## [0.1.0] - 2026-09-24

### Added

- National Dex species #387–1025 registered on FireRed and LeafGreen at slot
  dex + 64, with PokéAPI stats, Gen 3 typing, learnsets limited to FireRed's
  moves, Gen 3 abilities and evolutions.
- Reload repairs for evolution targets, name lookup and National Dex number
  lookup.
- An art seam (`setArtProvider`) for sprite mods. No art ships.
- Steps aside when 1025Dex is installed.
