# Changelog

All notable changes to this mod are documented here, in
[keep a changelog](https://keepachangelog.com/en/1.1.0/) format.

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
