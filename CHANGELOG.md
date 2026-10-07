# Changelog

All notable changes to this mod are documented here, in
[keep a changelog](https://keepachangelog.com/en/1.1.0/) format.

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
