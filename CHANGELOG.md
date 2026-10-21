# Changelog

All notable changes to this mod are documented here, in
[keep a changelog](https://keepachangelog.com/en/1.1.0/) format.

## [Unreleased]

### Fixed

- **Requires gen1recomp 0.3.95 or newer** (manifest `game_version`): the first release with
  both the API 3 registry write and the raised native index cap. Older engines keep 1.1.4.
- **Works again on the updated engine (API 3, Oct 20).** The engine's API 3 update broke the
  mod; its index cap was fixed upstream (bryanthaboi 79ea62f4: native slots up to 65535), and
  the rest is handled here:
  - The new Gen 3 registry write records each species' display name in `P._byName` and maps
    its National number back to its slot. A form shares its base's name and number, so it took
    the base over: MEOWTH resolved to the Galarian form and Modern Moves' rows for #211 landed
    on Hisuian Qwilfish. `src/schema_patch.lua` re-runs the engine's own write (dex_patch-style
    source patch) with forms kept to their own id key and out of `toSpecies`, as this mod's
    fixups always did. On a build from before the cap fix it also raises the 1023 ceiling to
    2047 so the species still register.
  - The species and item caps this mod sets (`gen3Fields.index`) are only ever raised now, so
    they no longer pull the engine's 65535 back down for other mods.
  - **Fairy through the engine's `type_chart` registry.** The engine now rebuilds the Gen 3 type
    chart from that registry on every mods load, which wiped the chart this mod rebuilt by hand
    (Fairy moves went neutral after a second load in one run, e.g. a hot reload) and crashed the
    engine's seeding on Fairy rows. FAIRY is now content: the type (index 18, special), its
    matchups from `data/types.lua`, the two Gen 6 Steel removals, and record patches for every
    Fairy typing (cart species, forms, Charm/Sweet Kiss/Moonlight); this mod's own Fairy species
    and moves register FAIRY directly. Removed: the chart rebuild, the `Types.effectiveness` /
    `Types.name` wraps and the live retyping with its reload hooks. Kept: gTypeNames[18], the
    Battle Factory count, the FRLG badges, the RSE summary icon. `fairy_test.lua` now also checks
    a second mods load in one process.
  - The rewritten battle moves module caches move names per table: `src/moves.lua` hands it a
    fresh name table after adding the new moves', or the editor dropped learnset rows naming one.
  - **Engine work no longer duplicated** (engine 0.3.95+ does it): `src/moves.lua` drops its
    repair layer (learnset/egg-move numbers, the `Moves.constName`/`numForName` wraps, re-writing
    rows into `Moves._rom` / `P._battleMoves` / `P._moveNames` after reloads); the species and TM
    index-cap raises and `schema_patch`'s 1023 branch go (it keeps only the form rules);
    `src/fixups.lua` stops writing `_byName` keys and `_national` maps and matching slot-0
    evolution targets. Kept: "used MOVE!" count, move descriptions, contest rows, animations,
    late-item / conditional evolution rows, Safari flee rates, tutors, the Pokedex data.
  - **Magic Room** keeps held items held: only their effects stop (`HeldItems.of`), so Knock Off,
    Trick, Thief and Fling still see the item, as in the real games (it used to hide the item).
    A plain wrap rather than the engine's `held_item.trigger` hook, which would make every
    held-item check in every battle copy the item's info table. In game on Emerald: no Leftovers
    heal while the room is up, the item stays held, Leftovers heals again once it ends.
  - **One animation hookup.** `src/anims.lua`'s `Anim.scriptForMove` wrap now answers every new
    move (its own script, a closer cart look, or data/moves.lua's `look`); `src/moves.lua`'s
    second wrap is gone. The engine's `battle_anims` registry was considered and not used: it
    takes one fixed script per move at load, with no per-cart resolution, no pack labels and no
    "borrow another move's animation". `anims_test.lua` covers the look-only case; in game the
    four driver animations play on Emerald and FireRed.
  - **Evolutions through the engine's `evolution_methods` registry**: overrides of the native
    `EVO_FRIENDSHIP_DAY` / `_NIGHT` (friendship 220+, day or night from this mod's clock) and
    `EVO_ITEM` (the engine's item check plus the Dawn Stone gender pair). Overrides keep every
    evolution row numeric, so other readers (Kanto Gear, Modern Spawns, the Pokedex) see the same
    tables. Removed: the `Evolution.targetSpecies` wrap and the friendship branch of the
    `evolution.check` hook (which keeps the conditional `when` steps). In game on Emerald and
    FireRed: Dawn Stone evolves male Kirlia only (use and the Bag check), Budew by day only.
  - **Art providers hear `shiny` and `kind`**: `setArtProvider(fn)` providers are now called as
    `fn(speciesId, side, slot, shiny, kind)` from the engine's sprite ctx, so a sprite mod can
    give the new species shiny pictures (providers taking three arguments are unaffected).
  - Cries stay in `cries.pak` with this mod's player: the engine's `cries` registry was
    considered and not used (one decoded source per species kept for the whole session instead
    of this mod's small cache, 639 files instead of one pack, and our player already follows the
    sound-effect volume).
  - README: a cartridge .sav export leaves Hall of Fame entries past slot 511 out (engine).
  - Test harness: `H.useCart` points the engine's dataset cache at the imported cart and the tests
    bind the live move module and run `Gen3Compat.applyMerged`, as a game does, instead of
    hand-loading move packs and names.

## [1.1.4] - 2026-10-20

### Added

- **Bigger PC** (option `big_pc`, on by default): 40 boxes (1200 Pokemon) on every Gen 3 game and
  in the save editor (`src/big_pc.lua`). `Storage.TOTAL_BOXES_COUNT` is set while mods load, so a
  Continue restores 40 boxes; every storage function, the box screen and catching read it live.
  Boxes 15-40 are saved in `modData.national_dex_gen3.pc` (moved out on `save.writing`, back in on
  `save.loading`), never in the save's own storage, so the core save stays a 14-box save:
  option off, mod removed, the Box tool and .sav export keep them. Toggling in the menu moves them
  live. `Storage.defaultWallpaper` gives boxes 15+ the 16 cart wallpapers in turn. Save editor:
  `Gen.boxCount`, `Game3Adapter.ensureStorage` (its own 14) and the Gen 3 deposit replaced,
  `hydrate`/`export` merge and split the save data. Tests: `big_pc_test.lua` (FireRed, Emerald,
  Ruby), `editor_stock_test.lua`; in game: box 1 <-> 40 wrap and boxes 37/40 on FireRed,
  Emerald, Ruby.

## [1.1.3] - 2026-10-16

### Fixed

- **Kanto Gear also gets the Fairy typing, new move names and ability texts.** 1.1.2 moved only
  the National Dex repairs ahead of Kanto Gear's game.ready snapshot; the Fairy type, the new
  moves' names and the real abilities still installed after it, so its party screen showed a
  Fairy Pokemon's pre-Fairy typing (Sylveon as Normal). The whole game.ready install now runs at
  priority 1, in its old internal order. Alternate forms still show a slot number there: Kanto
  Gear lists species by National number and a form has none of its own. Test:
  `register_test.lua` (the default-priority listener also sees Types.ID.FAIRY, Sylveon's Fairy
  typing and a new move's name).

## [1.1.2] - 2026-10-16

### Fixed

- **Kanto Gear shows the new Pokemon's names.** Kanto Gear (checked on 4.0.5 and 4.2.0) builds its species list on
  `game.ready` at the default priority, over `1..Dex.NATIONAL_MAX` with
  `Pokemon.speciesFromNational`, which ran before this mod's repairs (priority -100): it saw
  #1-386 only, and its party screen showed a bare number for every newer Pokemon without a
  nickname. The National Dex repairs (`fixups.install`) now run at priority 1, before it,
  instead of -100 (Gen3Compat has applied the registries before game.ready, and later reloads
  go through fixups' own reload hook). Test: `register_test.lua` (a default-priority listener sees #387-1025).

## [1.1.1] - 2026-10-16

### Fixed

- The package no longer includes `docs/fairy.md` (a developer-side docs page; `.modkitignore`).

## [1.1.0] - 2026-10-15

### Added

- **Day & Night** (option `day_night`, on by default): outdoor maps (town, city, route, ocean
  route, underwater) get a colour grade by time of day: morning 4-10, afternoon 10-17 (the
  game's own look), evening 17-20, night 20-4 (`Clock.phase`, same clock as the time-of-day
  evolutions). Decided on `map.entered` / load / option change, eased over 1 s on a walking route
  change. `src/day_night.lua` wraps `Renderer.blitCanvas` and draws the world blit (with
  gen3-hd-sprites' HD sprites, drawn inside it) into a scratch canvas, then through a
  gain / saturation / lift shader; `Renderer.endFrame` keeps the wrap outermost. Tilt mode, or a
  shader that fails to compile, gets a multiply + add overlay instead. Battles and full-screen
  menus have no world pass and are never graded. Test: `day_night_test.lua`; in-game on FireRed
  and Emerald at 07/13/18/22.

### Changed

- **Ability descriptions:** `docs/abilities.md` gives each added ability's full effect (every
  number, and what works differently from the newer games: Fluffy's double Fire damage, Sand
  Force not blocking sandstorm, Leaf Guard not stopping added effects...) beside the one-line
  summary text, from a `DETAILS` table in `tools/build_abilities.py` (`detail` in
  `data/abilities.lua`). Clearer summary texts for Fluffy, Weak Armor, Rattled and Rivalry;
  Healer, Telepathy and Honey Gather say they have no effect here. `abilities_test.lua` checks
  Fluffy's Fire doubling.

## [1.0.1] - 2026-10-15 (prerelease)

### Changed

- **Modern Moves is on by default** (`options.lua`): a player who never set it gets the newer
  moves on the original 386; turning it off in the mod menu still puts the cart's learnsets back.
  `modern_learnsets_test.lua` checks the default.

## [1.0.0] - 2026-10-15 (prerelease)

### Added

- **114 new TMs (TM51-TM164)** for every newer move that is a TM in Scarlet/Violet or
  Sword/Shield and real here, in Scarlet/Violet's TM order (then the Sword/Shield-only TMs and
  TRs) (`data/tms.lua` from `tools/build_tms.py`; items 1100-1213,
  append-only, item index cap raised to 2047 like the species cap). Compatibility: every species
  and form that learns the move by TM in any main game (16408 pairs). `src/tms.lua` wraps
  `Pokemon.moveFromTmItem` / `canLearnTmItem` and `ItemsData.isTm` / `tmNumber`, grows the TM
  Case by 114 on every game profile, draws a cart TM icon of the same type in the Bag, and in the
  FRLG TM Case keeps the disc on the rack (pink Normal disc for Fairy). Sold at Celadon Dept.
  Store 2F and Lilycove's two TM counters; item texts re-wrapped to the Bag box. Save editor:
  listed like the other items, same wraps and TM Case size. Tests: `tms_test.lua`,
  `editor_stock_test.lua`; in-game: taught from the TM Case / Bag on FireRed, Emerald, Sapphire.
- **Modern Moves option** (off by default; on from 1.0.1): the original 386 also learn the newer moves they
  learn today (`data/species/modern.lua` from `tools/build_modern_learnsets.py`: the real newer
  moves of the newest game listing the species, 1307 level-up rows on 374 species, and newer
  egg moves). `src/modern_learnsets.lua` swaps each cart list for a merged copy while the option
  is on and puts the cart's own back when it's off, live on `mod.options_changed`; the save
  editor applies it on `mods.loaded` from the player's saved options. Test:
  `modern_learnsets_test.lua`, `editor_stock_test.lua`.
- **The Move Reminder past 20 rows:** the engine reads only a learnset's first 20 rows (as the cart
  does); a wrap of `MoveLearn.relearnableMoves` lists every row up to the level for longer ones
  (many of this mod's species, and the 386 with Modern Moves on).
- **Move animations from pokeemerald-expansion.** 134 newer moves play their modern-style
  animation, translated from RHH's pokeemerald-expansion 1.17.2 (credited in README, CREDITS.md,
  LICENSE) by `tools/build_anims.py` into `data/anims.lua`: only scripts built from the templates,
  graphics, tasks and opcodes the engine and the carts already have (no graphics copied); sounds
  and tags resolved per cart, calls inlined (the VM keeps one return address). `src/anims.lua`
  wraps `Anim.scriptForMove`; a missing piece falls back to the move's `look`. 108 others borrow
  a closer cart animation (`looks`: the cart move whose expansion animation is most alike, plus a
  reviewed `REJECT`/`HAND` list; Trick Room no longer plays Rest). Test: `anims_test.lua`, all 134
  on FireRed, LeafGreen, Ruby, Sapphire and Emerald; in-game Moonblast, Psychic Fangs, Bulldoze
  and Trick Room on Emerald, FireRed and Sapphire.
- **Save editor: the Fairy type.** On `mods.loaded` the editor installs `src/types.lua` as a game
  does on `game.ready` (species typings, the chart, the type's name), and `Editor.retypeMoves`
  retypes the editor's own rows for Charm, Sweet Kiss and Moonlight, built before mods load. The
  real abilities and the 419 moves were already there. Test: `editor_stock_test.lua` (Ambipom's
  Technician in the ability picker and the legality check, Sylveon/Clefairy Fairy, Moonblast and
  Charm Fairy moves).
- **The last 94 newer moves as real moves** (419 in all, 4482 learnset/egg uses; 7 left: After
  You, Quash, Instruct, Me First, Ally Switch, Bestow, Teatime, which need a battler to act out
  of turn or swap places). `src/move_field.lua`: the protection variants (Spiky Shield, King's
  Shield, Baneful Bunker, Obstruct, Silk Trap, Burning Bulwark: `expProtected` + a streak stamp of
  this mod's, the punishment on `M.missReason == "protected"`), Feint, Hyperspace Hole, Phantom
  Force / Shadow Force (a `"VANISHED"` semi-invulnerable kind), Geomancy, Wide / Quick Guard and
  Crafty Shield, Gravity, Wonder Room, Magic Room (`HeldItems.itemOf`), Fairy Lock (`canSwitch` /
  `canRun`), Aurora Veil, Lucky Chant (`battle.crit`), Court Change, Mortal Spin, Ceaseless Edge,
  Stone Axe, Healing Wish / Lunar Dance (a side flag read on entry), Shed Tail (the cart's
  Substitute by id, then the switch), Chilly Reception, Revival Blessing, Purify, Jungle Healing /
  Lunar Blessing, Pollen Puff (heals a partner), Jaw Lock, Thousand Waves, Spirit Shackle, Anchor
  Shot, Octolock, Salt Cure, Heal Block (the adapter's `heal`), Throat Chop (`soundproofBlocks`,
  `selectionError`, `moveLimitations`), Magnet Rise, Smack Down, Thousand Arrows, Spectral Thief.
  `src/move_rules.lua`: Worry Seed, Entrainment, Simple Beam, Gastro Acid, Core Enforcer, Doodle,
  Soak, Magic Powder, Reflect Type, Trick-or-Treat, Forest's Curse (a third type honoured by the
  damage wrap), Tar Shot, Electrify, Ion Deluge, Plasma Fists, Power / Guard Split, Power / Guard
  / Heart / Speed Swap, Power Trick (stat overrides on the battler, never the saved mon),
  Topsy-Turvy, Strength Sap, Venom Drench, Captivate, Acupressure, Clangorous Soul, No Retreat,
  Fillet Away, Gear Up, Magnetic Flux, Rototiller, Flower Shield, Decorate, Aromatic Mist, Fling,
  Natural Gift, Bug Bite, Pluck, Incinerate, Belch, Stuff Cheeks, Powder, Shell Trap, Eerie Spell,
  Psycho Shift, Miracle Eye, Beak Blast. Doubles-only moves fail in singles and work on the
  partner in doubles. Tests: `tests/move_field_test.lua` (107), `tests/move_rules_test.lua` (125).
- **Field moves and the rest of the attacks: 68 more real moves** (325 in all, 3659 learnset/egg
  uses; 101 still substituted). `src/move_field.lua` keeps battle state Gen 3 never had, on the
  engine's own side/field tables (`side.__ndx`, `st.__ndxField`), through exported seams only:
  - **entry hazards** Stealth Rock, Toxic Spikes, Sticky Web (a wrap of `Engine.switchInEffects`,
    before the cart's Spikes; the cart's Rapid Spin clears them, Defog clears both sides and the
    foe's screens);
  - **turn counters** Tailwind, Trick Room, the four Terrains (a residual phase of this mod's,
    `ndx_field`, inserted in `Rules.FIELD_PHASES_ORDER`) with the terrain boosts in `Damage.calc`,
    the status guards in the adapter's `canApplyStatus`, Grassy healing in the `ingrain` phase,
    Psychic Terrain's priority block in `Hit.run`; Terrain Pulse, Rising Voltage, Expanding Force,
    Steel Roller, Ice Spinner; Aqua Ring;
  - **turn order** Tailwind and Trick Room through the real abilities' `battle.turn_order` hook
    (`RealAbilities.effectiveSpeed` / `speedModifiers` / `reverseSpeed`, new exports);
  - **switching** U-turn, Volt Switch, Flip Turn, Parting Shot (the cart's Baton Pass choice:
    `Engine.switchCandidates` -> the `baton_pass` party prompt / `mostSuitableMon` ->
    `Engine.performSwitch` -> `switchInEffects`), Dragon Tail and Circle Throw (a wild battle
    ends, a trainer's Pokemon is dragged out).
  `src/move_rules.lua` adds the stateless ones: multi-hit (`hits` on the row: Water Shuriken,
  Surging Strikes, Triple Dive, Dragon Darts, Scale Shot, Population Bomb), Stomping Tantrum,
  Rage Fist, Last Respects, Metal Burst, Comeuppance, Burn Up, Double Shock, Revelation Dance,
  Flying Press, Synchronoise, Fusion Flare/Bolt, Glaive Rush, Gigaton Hammer, Fickle Beam, Laser
  Focus, Dire Claw, Take Heart; and plain hits / cart effects / extras for Sunsteel Strike,
  Moongeist Beam, Dynamax Cannon, Tera Starstorm, Techno Blast, Judgment, Multi-Attack, Snipe
  Shot, Round, Flame Burst, Freeze Shock, Ice Burn, Electro Shot, Axe Kick, Esper Wing, Triple
  Arrows, Shell Smash, Syrup Bomb and the four Storm moves. MANUAL may now set a move's `target`
  (PokeAPI's "all-allies") and `hits`; a rule on a status move runs on effect byte 250.
  Driver-verified on Emerald, FireRed and Sapphire: Trick Room's order, Stealth Rock's entry
  damage, U-turn through the real party prompt, Dragon Tail ending a wild battle. Tests:
  `tests/move_field_test.lua`, `tests/move_rules_test.lua`.
- **Form weights** (`data/species/forms.lua` `weight`, from PokeAPI): Heavy Slam, Heat Crash, Low
  Kick and Grass Knot read them (a form has no Pokedex entry to read).

### Fixed

- **Poipole evolves again.** Its Naganadel step asked for Outrage, a stand-in from when Dragon
  Pulse was swapped out; with Dragon Pulse real, nothing taught Poipole Outrage. The step now asks
  for Dragon Pulse (363), as in the real games (`tools/form_list.py`). `known_move_test.lua` checks
  each of this mod's species learns the move its evolution needs.
- Ten move texts were cut off at an abbreviation ("The user boosts the Sp.": Aromatic Mist, Work
  Up, Shell Smash, Decorate, Geomancy, Gear Up, Fillet Away, Double Hit) or said only "The user
  faints." (Healing Wish, Lunar Dance); hand-written texts now, and `build_moves.py` no longer
  splits a sentence after "Sp." or "etc.".
- **Quark Drive works** on Electric Terrain (the best stat x1.3, SPEED x1.5), as Protosynthesis does
  in sun (`src/abilities.lua` `boosterOn`). Test: `move_field_test.lua`.
- Player docs: the Pokémon, move and ability pages describe real abilities, real moves and the
  Fairy type (`tools/build_docs.lua`).
- Retaliate counts any faint on the user's side last turn (`battle.fainted`), not only one from
  a hit; Sacred Sword, Darkest Lariat and Chip Away ignore evasion as well as the defensive
  stages; Damp stops Mind Blown and Chloroblast.
- **Move rules: 87 more real moves** (257 in all, 3142 learnset/egg uses; `src/move_rules.lua`).
  Newer attacks whose power, stats or outcome depend on the battle are set by hand in
  `tools/build_moves.py` `MANUAL` (`rule`, `like`, `effect`, `extra`) and carried out by wraps of
  `Damage.calc` (which the AI's estimate uses too) and `Hit.run`, with `battle.move_used` /
  `battle.damage_dealt` keeping who moved and who fainted this turn:
  - power: Hex, Infernal Parade, Venoshock, Barb Barrage, Brine, Acrobatics, Assurance, Payback,
    Bolt Beak, Fishious Rend, Retaliate, Wake-Up Slap, Stored Power, Power Trip, Punishment, Heavy
    Slam, Heat Crash, Gyro Ball, Electro Ball, Wring Out, Crush Grip, Trump Card, Echoed Voice;
    the variable-power ones are power 1 to the cart, like Flail
  - stats: Foul Play, Body Press, Secret Sword, Psyshock (the real move's stat goes into whichever
    one Gen 3's type-based split reads); Sacred Sword, Darkest Lariat, Chip Away ignore Defense
    boosts
  - always a critical hit: Frost Breath, Storm Throw, Wicked Blow, Flower Trick; Final Gambit
    deals the user's HP; Electro Drift and Collision Course hit 1.33x harder when super effective
  - can fail: Sucker Punch and Thunderclap (the foe must be about to attack), First Impression
    (first turn only), Last Resort (every other move used first)
  - after the hit: Clear Smog, Fell Stinger (+3 Attack on a knockout), Final Gambit, Chloroblast,
    Mind Blown, Sparkling Aria, Wake-Up Slap
  - and existing Gen 3 effects or descriptions: Boomburst, Petal Blizzard, Jet Punch, Grass Knot,
    Nature's Madness, Snowscape, Aqua Cutter, Wave Crash, Raging Fury, Twin Beam, Head
    Smash, Bitter Blade, Spin Out, Armor Cannon, Torch Song, Aqua Step, Lumina Crash, Shelter,
    Victory Dance and more.
  Hand-written summary texts and 12-letter names where the official ones don't fit.
  Tests: `tests/move_rules_test.lua`.
- **New move mechanics: 52 more real moves** (170 in all, 2377 learnset/egg uses;
  `src/move_effects.lua`). A newer move whose effect Gen 3 lacks but which PokeAPI's move `meta`
  describes completely (stat changes on the user or the foe, a status or flinch chance, drain or
  recoil, healing) is built with that description (`tools/build_moves.py` `generic_extra`). Status
  moves (Nasty Plot, Hone Claws, Work Up, Quiver Dance, Noble Roar, Shore Up ...) run on effect byte
  250, which the cart never uses, mapped in the engine's effect table to this mod's handler (a
  wrap of `Effects.run`); attacks (Close Combat, Flame Charge, Lunge, Fire Fang, Flare Blitz,
  Draining Kiss ...) are plain hits whose extra a wrap of `Hit.run` applies once the hit lands,
  through the engine's own stat-change and status functions. Moves with a condition or a
  mechanic the description leaves out (Captivate, Parting Shot, Geomancy ...) keep a substitute.
  Tests: `tests/move_effects_test.lua`.
- **52 newer abilities as real abilities** (`src/abilities.lua`, data from
  `tools/build_abilities.py` -> `data/abilities.lua`): ids from 78 (append-only), names in the
  adapter's id table, the species module and the battle's id lookups, summary texts; a species'
  ability pair is set live from its real slots (a slot without one keeps the closest Gen 3
  ability) and the adapter's `abilityOf` answers from species + ability slot, so Pokemon in saves
  get them. Effects through `Damage.base`, the `battle.damage` / `battle.crit` /
  `battle.accuracy` / `battle.turn_order` hooks and wraps of the ability, stat-change and effect
  functions; each needs only its own target and falls back to the Gen 3 ability without it.
  Known limits: Leaf Guard / Sweet Veil / Flower Veil don't stop a move's secondary status, Super
  Luck doesn't stack with high-crit moves, Ice Body / Snow Cloak don't block hail damage.
  `docs/abilities.md` lists them. Tests: `tests/abilities_test.lua`.
- **118 newer moves as real moves** (`src/moves.lua`, data from `tools/build_moves.py` ->
  `data/moves.lua`): a newer move whose effect is one Gen 3 already has (matched by PokeAPI's
  effect description against the cart's own moves, attacks only onto attacking effects) is
  registered at its own index (append-only from 355) with today's power, accuracy, PP, priority,
  target, flags (Pokemon Showdown's data), contest category/appeal and a summary text for each
  box; learnsets and egg moves use it instead of a substitute (1705 uses). The battle's move-name
  index, "used MOVE!" text, summary text, Ruby/Sapphire/Emerald contest rows and the battle
  animation (the closest cart move's) answer for them; Fairy ones are Fairy. The other 308 newer
  moves keep their substitutes. Works around a registry fault that writes a new move into the
  move index by name (learnsets and, after a reload, the move rows end up under the name): the
  numbers are put back after every write. Save editor: the moves are in its move list.
  `docs/moves.md` lists them. Tests: `tests/moves_test.lua`.
- **The Fairy type** (Gen 6+) as a real type, id 18 (`src/types.lua`, data from
  `tools/build_types.py` -> `data/types.lua`):
  - the Gen 6 type chart: Fairy's 12 matchups, inserted before the chart's Foresight sentinel, and
    Steel no longer resisting Ghost and Dark; the AI's own effectiveness check reads the same chart
  - every species and form that is Fairy today gets its modern typing (64 species, the cart's
    Clefairy/Jigglypuff/Togepi/Snubbull/Marill/Mr. Mime/Ralts/Mawile lines included, and 26 forms),
    set on the live tables after every reload; STAB follows automatically
  - Charm, Sweet Kiss and Moonlight are Fairy moves
  - the name FAIRY, and an original Fairy type icon (`tools/build_type_icons.py`) laid out like the
    cart's: FireRed/LeafGreen badges through the summary and Pokedex chrome, Ruby/Sapphire/Emerald
    summary icons through a patched copy of the summary screen (`src/type_icons.lua`; contest icons
    unchanged); any mismatch leaves the stock screen
  - Emerald's Battle Factory type count reads a Fairy half as the Pokemon's other type
  - tests: `tests/fairy_test.lua` (FireRed, Emerald, Ruby)

### Fixed

- Pokemon met in the FireRed / LeafGreen Safari Zone that don't belong there (a spawn mod such as
  Modern Spawns can put any species there, new or not) run away like the Safari Zone's own. The
  game only gives its Safari species a flee rate, so every other species had none and almost
  never ran. Each now gets the rate its catch rate's band has in FireRed's own Safari table: 50
  for easy-to-catch species (catch rate 150 and up), 75 for middling ones (60-149), 125 for rare
  ones (under 60). The Safari Zone's own species keep their rates.

## [0.8.3] - 2026-10-13

### Fixed

- An egg's summary screen on Ruby and Sapphire is no longer blank: the cart draws the egg from a
  picture slot with no name (412), and the sprite hook asked for one, the same fault 0.8.2 fixed
  for Unown's letters. That slot now answers EGG.
- The Pokedex FORMS page names Alolan and Paldean forms the way it names Galarian and Hisuian
  ones ("ALOLAN", "PALDEAN AQUA BREED"), not "ALOLA" / "PALDEA".

## [0.8.2] - 2026-10-13

### Fixed

- The game no longer stops when an Unown other than A appears (for example a wild Unown N):
  the cart's Unown letter slots have no name of their own, and the sprite hook asked for one.
  They now answer as Unown.

## [0.8.0] - 2026-10-10

### Added

- **43 regional forms of the original Pokemon** (128 forms in all, slots 1175-1217; the form slot
  cap is now 1300): Alolan Rattata, Raticate, Raichu, Sandshrew, Sandslash, Vulpix, Ninetales,
  Diglett, Dugtrio, Meowth, Persian, Geodude, Graveler, Golem, Grimer, Muk, Exeggutor and Marowak;
  Galarian Meowth, Ponyta, Rapidash, Slowpoke, Slowbro, Slowking, Farfetch'd, Weezing, Mr. Mime,
  Articuno, Zapdos, Moltres, Corsola, Zigzagoon and Linoone; Hisuian Growlithe, Arcanine, Voltorb,
  Electrode, Typhlosion and Sneasel; Paldean Wooper and the three Tauros breeds. Each evolves into
  its own region's form (Alolan Sandshrew -> Alolan Sandslash) or into the species only that form
  becomes: Perrserker, Sirfetch'd, Mr. Rime, Cursola, Obstagoon, Runerigus (Galarian Yamask, now
  live), Sneasler, Clodsire. The original Pokemon are unchanged.
- New `when` keys: `crits` (critical hits landed in one battle, counted by `src/counters.lua`)
  and `hpLost` (HP down when it levels up).
- **Galarica Cuff and Galarica Wreath** (38 items), sold with the apples.
- Test: `regional_test.lua`.

### Fixed

- **A trainer leading with a Gen 4+ Pokemon no longer stops the battle** (Emerald: "mon_anim: no
  port for anim function nil"). The cart's front-animation table ends at its own species, so
  `src/mon_anim.lua` gives every species and form a cart species' entrance animation: a regional
  form moves like its base, a new evolution of a cart species like that species (Rhyperior like
  Rhydon), and the rest like a cart species of their primary type. Test: `mon_anim_test.lua`.
- A form of an original Pokemon no longer takes that Pokemon's name in the species lookup (the
  Galarian Mr. Mime answered for `MR_MIME`).

- **Save editor support** on stock gen1recomp (`src/editor.lua`): when the save editor is the host,
  the mod hands the dataset the move and item modules before registering, and on `mods.loaded`
  applies the registries to the live tables and runs its own repairs (what a game does before and
  on `game.ready`), then lists every species and form in the editor's picker (a form labelled, e.g.
  "DARUMAKA (GALAR)") and its 36 items in the item list. New Pokemon can be picked, keep their names and get their moves; pictures
  come from G9 Battle Sprites. No engine patch needed. Test: `editor_stock_test.lua` (replaces the
  fork-only `editor_learnset_test.lua` and `editor_sprite_box_test.lua`).

## [0.7.0] - 2026-10-09

### Added

- **A FORMS page in the Pokédex.** A species with alternate forms shows each one's picture with
  its name underneath (Galarian, Wash, Ruby Cream, ...), the pictures shrinking to fit as there
  are more (Alcremie's 8 fit on one page). On Ruby/Sapphire/Emerald the entry's CANCEL tab reads
  FORMS for those species: A on it opens the page, A or B closes it, and B still leaves the entry
  as before. On FireRed/LeafGreen it is a third page after the size/area one: A goes on to it, B
  steps back. Never offered on an undiscovered entry.

- **Fast scrolling in the Pokédex.** Hold Up, Down, Left or Right to keep moving instead of
  pressing again for every step: after a quarter of a second it repeats about 14 times a second,
  and about 33 once held for over a second. On FireRed/LeafGreen this covers the lists, the
  habitat pages and stepping between entries; on Ruby/Sapphire/Emerald (whose list already
  scrolls while Up/Down is held) the Left/Right page jumps and stepping between entries.

- **Undiscovered Pokédex entries can be opened, for another mod to show where they live.** A new
  export, `setDexPeek(fn)`: when `fn(speciesSlot)` answers true for an unseen species, its entry
  opens in a limited view on Ruby/Sapphire/Emerald and FireRed/LeafGreen. The number shows; the
  name is dashes, the picture is the cart's "?" one, no cry plays, and the Cry and Size pages stay
  closed (category, height, weight and description were already owned-only), but the AREA page
  shows. Up/down on the entry steps to the next entry that can be opened, and the numerical list
  runs on to the last one. With no fn registered nothing changes. Modern Spawns registers one for
  every species it places under the current settings.
- **FireRed/LeafGreen AREA page draws the Sevii Islands.** The engine drew only the Kanto map, so
  a Pokémon found only on the islands read AREA UNKNOWN, cart species included. The page now draws
  each island the species lives on in the cart's own layout (pokefirered: island windows beside
  and below Kanto, everything shifted up when islands 4-7 are shown) with its markers. The cart
  shows the islands you have unlocked; the engine does not track that, so the islands where the
  species has a marker are shown.
  Each island map has its name (ONE to SEVEN) above it, since the cart's island art is just a
  route line and they are hard to tell apart.
- These are more text patches on the engine's own Pokédex screens, applied the same way as the
  list fix (`src/dex_patch.lua`). They are a separate set: if the engine's screen has changed and
  they no longer match exactly, only this feature is skipped, with one warning; the list fix still
  goes in.

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
