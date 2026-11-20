# WoobleDex: developer guide

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
| Types | PokéAPI. The species shards keep the Gen V typing (Fairy dropped, pure Fairy → Normal); `data/types.lua` carries the modern Fairy typings, which `src/types.lua` patches onto the records through the engine's `type_chart` (FAIRY = type 18) |
| Learnset | The level-up list from the newest game that has one, at its full length. A move Gen 3 lacks is replaced, at the same level, by the closest Gen 3 move the species doesn't already learn (`tools/move_map.py`: same type, then similar power, accuracy, priority and effect). Move names are read from the running game's own move registry |
| TM/HM compatibility | Every TM or HM (the same 58 machines in all five games) whose move the species can be taught by machine or tutor in any game (636 species; 37 of 58 machines on average) |
| Move tutors | Whichever tutors the running game has (FireRed/LeafGreen's 15, Ruby/Sapphire's none, or Emerald's own larger set) whose move the species can be taught in any game |
| Egg moves | Egg moves Gen 3 has (315 species) |
| Abilities | The cart's own are kept; 178 newer ones are real (`data/abilities.lua`, ids 78-255, `src/abilities.lua` + `src/abilities_more.lua`, see Abilities below). The other twelve (partner-only or nothing to act on) and any that fails to install are the closest Gen 3 one (`tools/ability_map.py`), which saves and species records still carry |
| Evolutions | Level, item, friendship and trade steps between species 1–1025, plus steps from the cart's own species into new ones (Magneton → Magnezone, Nosepass → Probopass ...) |

**Shops** (`data/shops.lua`): the Marts sell only Dynamax Candy, Max Mushrooms and Max Honey,
beside the vitamins (Celadon Dept. Store 5F, Lilycove Dept. Store); the evolution items and the new
TMs are sold by the vending machines, below.

**Vending machines** (`data/vending.lua`, `src/vending.lua`, `src/vending_screen.lua`): stationary
NPCs placed with `mod.world:spawnNpc` on entering their map (runtime objects: never saved), with
16 x 32 sprites registered in `content.sprites` (anchor row 28: the bottom half stands on the
tile). A on one (the `world.talk` hook) pushes a layer on the Gen 3 UI stack (it takes the
buttons and holds the field) and opens a touch screen drawn from `render.hud` over the whole
window (its safe area), laid out for its shape by `S.layout`: landscape is a page 160 units tall
and up to 380 wide (more grid columns beside the card), portrait 180 wide (the card under the
grid, more rows). Taps and clicks come from `input.pointer`, the wheel from `input.wheel`, and
the on-screen touch pad is put away while it is up. Up from the grid's top row focuses the tabs.
Opening plays a boot (`S.BOOT`: black, a tube line, the W logo `S.drawLogo` with a loading bar,
the reveal); until the reveal only the close button answers, and any button or tap skips to it.
The screen is drawn every frame, so its draw makes next to no garbage: colours are derived once
(`mix` memoised; gradient meshes kept by those colour tables), rectangles and hit records come from
pools refilled each frame, per-item text is worked out once, item icons are painted once into 24 x 24
canvases (the engine's icon draw allocates), and the Bag is asked only when the card's item, amount
or money changes. `vending_probe.lua` meters the draw in the engine (under 0.5 KB a frame). The bezel's colours are
in each machine's data, read off its sprite. Stock is by item slug, resolved live through
`Species.itemIndex` (names, prices and descriptions from the running game's items; a TM's move,
type, power, accuracy and PP from its battle row). Buying takes the money and fills the Bag
through `src.core.game3.bag`, as the Mart does. Each machine has a `place` per group of carts (`V.placeIn`):
EVO EXPRESS at Celadon Dept. Store 4F (9,5) and TM EXPRESS at 2F (9,5) in FireRed / LeafGreen
(LeafGreen's maps are FireRed's); EVO EXPRESS at Lilycove Dept. Store 2F (5,2) and TM EXPRESS at 4F
(8,2) in Ruby / Sapphire / Emerald. Tests: `tests/vending_test.lua [game]` (headless: the
data, the stock, a purchase by buttons and one by taps, the tabs by D-pad, seven window shapes),
`tests/drivers/vending_probe.lua` (in the engine: both machines, buttons, then the mouse, then
16:9, portrait and 21:9 windows).

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

## TMs

`data/tms.lua` (`python tools/build_tms.py`, after `tools/build_moves.py`): `ORDER` is
append-only (item index 1100 + position, TM number 51 + position; both are in saves), each with
its price, item texts wrapped for the FRLG (19x4) and RSE (19x3) boxes (`TEXT` for hand-written
ones) and who learns it (National numbers and form ids with the PokeAPI "machine" method in any
version group). `src/tms.lua`: `Tms.register` (load: raises `Schemas.REGISTRIES.items.gen3Fields.index`
to 2047, registers `pocket = "TM_CASE"` items) and `Tms.install` (game.ready and the editor's
mods.loaded: wraps `Pokemon.moveFromTmItem`, `Pokemon.canLearnTmItem`, `ItemsData.isTm`,
`ItemsData.tmNumber`; adds the TM count to every game profile's `bag.capacity.TM_CASE`, which
`ItemsData.CAPACITY` is refilled from; Bag icons via both `bag_chrome.drawItemIcon`; the FRLG
`tm_case_chrome.drawDisc` clamp and Fairy tint). The engine's species TM row is 64 bits with 58
used and the registry drops unknown TM moves, so compatibility lives in the mod. Not covered:
breeding's father TM moves, link checks and the Apprentice loop over the cart's 58 machines, and
the R/S Bag draws three-digit numbers into the name (fixed positions in a local). Tests:
`tests/tms_test.lua [game]`, `tests/tm_case_test.lua` (a 900+ TM Case item through a save).

## Modern Moves (option)

`data/species/modern.lua` (`python tools/build_modern_learnsets.py`, after `tools/build_moves.py`):
for National #1-386, the level-up rows of the newest game that lists the species
(`build_species.VERSION_GROUPS`) whose move Gen 3 has (1-354) or is a real newer move here, and
the egg moves that are real newer moves. `src/modern_learnsets.lua` replaces each cart list with
a merged copy while `modern_moves` is on: a move in both lists is learned at the EARLIER of its
two levels (the cart's row copied with today's level, never edited in place; Squirtle's Water Gun
13 -> 3, so a Lv 5 starter from `Party` / `movesAtLevel` knows it), a move only today's list has
is added, a cart-only move stays. Before 1.15.3 only newer moves were added, so a starter missed
moves today's games teach earlier (player report, 2026-11-17). The swap (weak-keyed `ours[list]`
remembers the cart's list, so turning it off restores it and a reload re-applies), on
`game.ready`, `mod.options_changed` and, in the save editor, `mods.loaded`. Egg moves only go to
species that already have a cart egg-move list. `ModernLearnsets.installRelearner` (always on)
wraps `MoveLearn.relearnableMoves`, whose local cap of 20 rows would hide the rest of a modern
learnset. Test: `tests/modern_learnsets_test.lua`; the editor half is in `editor_stock_test.lua`.

## Bigger Bag (option `bigger_bag`)

Every limit is read live, so nothing is edited, only wrapped (process-wide, guarded on the
module; a reload hands over the new `enabled`):

- Gen 3 (`src/bigger_bag.lua`): `ItemsData.applyProfile` re-raises `ItemsData.CAPACITY` after each
  refill from the profile's `bag.capacity` (ITEMS 300, KEY_ITEMS 60, POKE_BALLS 30, BERRY_POUCH 60;
  a pocket already bigger keeps its size: the TM Case src/tms.lua grows); `Storage.pcItemsCount`
  answers 300; `Storage.restore` lifts the PC limit while it runs (its legacy shapes trim to the
  limit; the Bag never trims on load). `mod.options_changed` re-raises. Not in the editor.
- Gen 1/2 (`src/gen12/bigger_bag.lua`): `Bag.capacity(data, pocket)` (shared `src.inventory.Bag`,
  every add asks it; ITEM / nil 300, BALL 30, KEY_ITEM 60, TM_HM left to src/gen12/tms.lua);
  `data.field.pcItemCap` = 300 on the live game's data (Red's PlayerPC and Gold's Mom read it;
  cleared on off only if we wrote it); Gold's `ItemPcMenu.pcAdd` overridden (its 50 is a file
  local) with the same 99-a-stack count.
- Off loses nothing: saves never trim, so a fuller pocket / PC keeps its items and refuses new
  kinds. Cartridge .sav: Red's export keeps the first 20 / 50, Gold's refuses an over-full Bag
  (Gen2Save `refuse`).

Test: `tests/bigger_bag_test.lua [game]` (both halves).

## Move Split on Gen 3 (option `move_split`, `src/move_split.lua`)

The same key as Red to Crystal's (`src/gen12/mech/split.lua`), default off. The Gen 3 engine
asks one function for every physical / special decision: `Types.isPhysical(moveType)`
(`src/core/game3/battle/types.lua`), from the damage formula (stats, stages, burn, screens, type
boosting items), `Hit.dealDamage` (`lastPhysicalDamageTaken` / `lastSpecialDamageTaken`, what
Counter and Mirror Coat read), Hustle's accuracy, and this mod's move rules and abilities. So
`Types.isPhysical` is wrapped to answer by the move being resolved, when there is one:

- **Which move:** a stack per coroutine (`coroutine.running()`, weak-keyed; the engine runs a move
  in a coroutine that can pause for a prompt), pushed by wraps of `Damage.calc` (the battle and
  the AI's estimate), `Hit.run` (`M.mnum`) and `Hit.dealDamage` (whose `info.physical`, computed
  by the engine from the type for its own fixed-damage calls, is corrected too). A move with no
  class pushes NATIVE, so a typeless hit inside another move gets the game's answer. `Effects.run`
  is wrapped too: Future Sight and Doom Desire work out their damage in their effect script
  (`Setup.futureSight`, `Damage.base`); an effect with no move of its own keeps the move around
  it. A called move (Metronome, Sleep Talk, Mirror Move, Assist) is its own `Engine.resolveMove`,
  so it pushes its own class.
- **Link battles** (`st.link`, `st.kinds.recordedLink`) keep the game's split: both games must
  work out the same damage, and `src/link/Fingerprint.lua` compares `Types.PHYSICAL`, not this
  option.
- **Code that classifies a move itself:** `hub.categoryOf(num, st)`. The held items' Gen 3
  adapter (`src/held/gen3.lua` `GA:category`) asks it, since its move views carry the category
  `Moves.get` worked out by type at load (Choice Specs, Muscle Band, Wise Glasses, the
  category berries).
- **Classes:** `data/move_split.lua` by Gen 3 index (`tools/build_move_split.py`: the cart's
  1-354 are National numbers, ours carry `api`; damage classes from `data/gen12/api/moves.lua`).
- **Order:** installed last of the battle's wraps on game.ready (after MoreAbilities), so it is
  the outermost on `Damage.calc` and `Hit.run` and every other wrap asks inside the move (move
  rules' stat swaps put Body Press's Defense into the slot the move's class reads). Process-wide
  (`Types.__ndxSplit`); a later install only refreshes the classes and the option reader.
- The option is read once and on `mod.options_changed` (the engine asks on every hit).
- Test: `tests/move_split_test.lua [game]` (all five carts).

## EV-lowering berries (`src/ev_berries.lua`)

Pomeg, Kelpsy, Qualot, Hondew, Grepa and Tamato (cart items 153-158) lower an EV in Emerald by its
own item data (the engine's `ItemUse.useVitamin` -> `ev_berry` / `use_ev_berry`, after
`ItemUseCB_ReduceEV`); FireRed, LeafGreen, Ruby and Sapphire's data has no EV change, so the Bag
said "It won't have any effect". Each berry is patched at load with an `item_effects` record
(`items:patch(id, { effect = "EV_<ID>" })`; Schemas `itemWrite` keeps the ROM effect bytes beside
the mod effect, so `fieldUseKind` answers `"mod"`). The effect: EVs -10 (never below 0),
`Pokemon.itemFriendship(mon, { 10, 5, 2 })`, Emerald's three messages, "It won't have any effect"
when neither changes. Where the cart's own bytes already lower the EV (Emerald), it hands the use
to `ItemUse.useVitamin`, so Emerald is unchanged. Test: `tests/ev_berries_test.lua [game]` (all
five carts).

## Day & Night (option)

`src/day_night.lua`, option `day_night` (default on), hours from `Clock.phase` (src/clock.lua:
morning 4-10, afternoon 10-17, evening 17-20, night 20-4; night = `Clock.isNight`). The grade
(per-phase gain, saturation, lift in `DayNight.PHASES`; afternoon is identity and draws nothing
extra) is decided on `map.entered` (eased over `EASE` seconds when `via == "connection"`),
`map.reloaded`, `save.loaded`, `game.ready` and `mod.options_changed` (day_night, clock_source),
never per frame. Only map types 1, 2, 3, 5, 6 (`DayNight.OUTDOOR`).

Seam: Gen 3's world (tiles, people, weather, Flash) is the Renderer's world canvas, the menus its
UI canvas. The wrap of `Renderer.blitCanvas` redirects the world blit into a window-size scratch
canvas and draws that through the shader. gen3-hd-sprites draws its HD overworld sprites inside
the same blit (its own `blitCanvas` wrap), so ours has to be outermost: the `Renderer.endFrame`
wrap re-wraps if anything wrapped `blitCanvas` after us (an inner copy passes through on `busy`).
Tilt mode draws the world without `blitCanvas`, so there (and with no shader) a multiply + add
overlay goes on the view just before the UI blit. Battles and full-screen menus never open a
world pass. Test: `tests/day_night_test.lua` (stubbed `love.graphics` and Renderer).

## Engine registry write (schema patch)

`src/schema_patch.lua`, run first in the entry (game and editor). The API 3 engine writes Gen 3
species/moves/items through a local `prepareNativeWrite` + per-registry `gen3Write` closures
(`src/mods/Schemas.lua`). They record each species' DISPLAY name in `P._byName` (last wins) and
set `toSpecies[dex] = slot` for every record, so a form (named and numbered like its base) took
its base over. The module reads the engine source (CacheBlob in a game, `tests.fs_io` headless),
makes those two writes skip records with a `baseSpecies` (and other display names first-wins),
runs the copy (its one `package.loaded` read goes through require), and installs the fresh
`gen3Write` closures on `Schemas.REGISTRIES[name]`, on the `shapeFor`-cached derived specs the
loader already holds, and the whole `Schemas.gen3View` (preindex shares the name-index cache).
On a build from before bryanthaboi's cap fix (79ea62f4, 1023 -> 65535) it also raises the two
cap literals to 2047. Exact-match failures log once and leave stock. Retire it if the engine
skips forms in `updateNativeNames` / `writeMon`.

## Bigger PC (option)

`src/big_pc.lua`, option `big_pc` (default on). The engine reads one field for the box count,
`Storage.TOTAL_BOXES_COUNT` (src/core/game3/storage.lua), set while mods load (before a Continue's
`fromSaveTable`) and on `save.loading`. Boxes 15-40 never stay in the save's own `storage`: with a
14 count the engine skips them on load and the next save loses them (option off, mod removed),
the Box tool refuses such a save, and .sav export keeps 14. So `save.writing` moves them into
`save.modData.national_dex_gen3.pc` (only boxes with a Pokemon, a name or a non-default
wallpaper, plus `currentBox` when > 14) and `save.loading` puts them back into the raw save before
the engine restores it. `modData` is the session's own table (`toSaveTable`), carried whole by
the engine. The menu toggle moves them live (`BigPc.toggleLive`). Boxes 15+ default to the 16
cart wallpapers (`Storage.defaultWallpaper` wrapped). Save editor (on `mods.loaded`):
`Gen.boxCount`, `Game3Adapter.ensureStorage` (a copy with the count for its 14) and the Gen 3
deposit replaced; `hydrate`/`export` merge and split. Only boxes 1-14: RS lottery
(`natives_rs.lua:345`), RS PokéNav condition search (`condition_data.lua:44`), online team
picking, the Box tool, .sav export. FireRed/LeafGreen page boxes with L/R only in Button Mode LR,
as on the cart; the box-name header switches in every mode. Test: `tests/big_pc_test.lua [game]`.

## Move animations

`src/anims.lua` wraps `Anim.scriptForMove` (outside `src/moves.lua`'s, which plays the cart move
named in `look`). `data/anims.lua`, built by `tools/build_anims.py` from RHH's pokeemerald-expansion
(1.17.2; credit it as its README asks), holds:

- `moves`: 134 moves whose expansion script uses only templates, graphics tags, tasks and opcodes
  the engine and the imported carts already have, expanded (macros, constants, `.if`) into the
  rows the animation VM runs. Calls are inlined, since the VM (like the cart) keeps one return
  address and expansion's subroutines call others; a branching one (a background by side) stays
  a real call if nothing it reaches calls again. Sounds (`"SE_M_X"`, `"SE:"` in arguments) and
  graphics tags in arguments (`"TAG:X"`) stay names, resolved against the running cart, and a
  template takes the cart's own tag, palette, callback and size; the script then starts with the
  `loadspritegfx` rows its tags need (expansion loads graphics implicitly). Any piece missing on
  the running cart falls back to the `look`.
- `looks`: for 108 others, the cart move whose expansion animation shares the most with the
  move's (weighted by rarity), when clearly closer than `look`; `REJECT`/`HAND` in the tool
  hold the reviewed exceptions.

Rebuild with `python tools/build_anims.py` (needs luajit and an imported cart under the engine
root; `tools/anim_known.lua` lists what the engine and carts offer). The report
(`tools/.cache/anims_report.txt`) lists what each left-out move lacks: mostly expansion's own
sprite templates (215), then tasks (32) and its newer backgrounds (24). Test:
`tests/anims_test.lua [game]` resolves and plays every script headlessly on that cart.

### Gen 9 Move Animation Project (`src/ess_anims.lua`)

In battle, every move the [Gen 9 Move Animation Project](https://eeveeexpo.com/resources/1480/) names
plays its animation: all 419 newer moves (over the expansion scripts and borrowed looks above, which
stay as the fallback and play in contests) and 344 of the carts' own Gen 1-3 moves; so do the cart's
status, weather, trap, Leech Seed and Focus Punch animations it has a "Common:" one for. It is a
Pokémon Essentials v21.1 pack (credited in CREDITS.md and LICENSE). `tools/build_ess_anims.py`
reads its `Data/PkmnAnimations.rxdata` with a small Ruby Marshal reader (`tools/ess_marshal.py`; no
Ruby needed), matches `Move:` / `OppMove:` names to `data/moves.lua`'s ids and the carts' move
constants (pokeemerald-expansion's `include/constants/moves.h`, 1-354), keeps those that are real
(more than one frame, something visible), and writes:

- `data/ess/<NAME>.lua`: the frames, each a list of cels (pattern, x, y, focus, zoom x/y, angle,
  opacity, blend, mirror, priority, colour rgba, tone rgb+gray; trailing defaults dropped; pattern
  -1 / -2 the user / the target themselves, -3 / -4 a copy of their picture), and the
  timings (sounds; background and foreground set/change). `opp` is the foe's version when the pack
  has one; `charge` / `charge_opp` a two-turn move's charging turn ("Fly charging", "Common:Dig
  charging"...). `C_<NAME>` files are the common animations. Loaded the first time one plays.
- `assets/ess/<sheet>.png`: only the 192 px cels used, shrunk to `SCALE` 0.375 (Essentials' user ->
  target line is 286 px, Gen 3's 111) with their colours weighted by alpha and alpha raised 1.4x (a
  thin stroke would fade to nothing), in a grid; `bg/` the background pictures, scaled to 240 x 160.
- `assets/ess/se/*.ogg`: the pack's sounds, mono 22 kHz, a file per volume/pitch used. A
  `PRSFX- <Move>N` sound of a Gen 1-3 move is that move's Nth cart sound instead (from
  pokeemerald-expansion's scripts).
- `data/ess_anims.lua`: the sheets, backgrounds, sounds (registered as mod sounds at load, with the
  mod's path); `moves` (frame counts, `num` for a cart move, `turns` for a two-turn one, `from` for
  a borrowed one); `commons` (`Anim.tableScript` kind -> cart name -> file) and `trap`.

The tool's tables: `SKIP` (vetoes), `CART_KEEPS` (Curse and Bide: the cart picks their version by
the turn number; Transform and Substitute: the cart's animation changes the user's picture for good), `BORROW` (Ivy Cudgel, which the pack lacks, plays Wood Hammer's), `TWO_TURN_CART`
and `TWO_TURN_EFFECTS` (`charge`: Razor Wind, Solar Beam, Skull Bash, Sky Attack and the newer moves
on those effects; `hide`: Fly, Dig, Dive, Bounce), `COMMONS` and `TRAP`.

`EssAnims.install` (after `src/anims.lua`'s, on game.ready) maps the running game's move numbers to
names and wraps, once per process (`Anim.__ndxEss`, asking the current install's state):

- `Anim.scriptForMove`: a move with an animation answers `createvisualtask NdxEss { "ESS:" .. NAME,
  mode }` (mode 1 for `charge`: its charging animation on an even turn, as the cart's
  `choosetwoturnanim`; a `hide` move answers `choosetwoturnanim` between the cart's own script,
  which hides the user, and mode 2, which shows it again: `present.invisible = false`).
- `Anim.tableScript`: the `commons`; `TURN_TRAP` keeps the cart's first row (its
  `GetTrappedMoveAnimId` task sets argument 0) and then `"ESS:@TRAP"`, which picks from `trap`; Bind and
  Wrap (the cart gives both 0) jump back to the cart's own script, so neither borrows the other's.
- `Anim.launchMove`: a move launched outside a battle (a contest) plays what lies underneath.

The `NdxEss` task plays the frames as Essentials' `PBAnimationPlayerX` does, at 20 a second (3
ticks each): focus 1/2 cels offset from the target's/user's centre times 0.375, focus 3 by
Essentials' per-axis line transform onto the attacker -> target centres (mirrored when the line runs
right to left), focus 4 on the screen; a line or screen cel is grown by that axis's scale over 0.375
(1.08 across the line, 1.25 / 1.11 on the screen), so tiled pieces still meet. A foe's move plays
the `opp` version with the roles swapped. A move on its user (`MOVE_TARGET_USER`, 16: Minimize, Swords Dance; the
carts' move rows, `user` in the index for the newer ones) plays with the user as its target too, as
Essentials plays it, whatever target the battle names: the third task argument. Cels 0 and 1 move, zoom, turn and fade the battlers
through their `present` fields; tone and colour become the battle's `palAffine` (each channel times
1 - alpha plus tone and colour: exact, gray aside); all put back at the end. One task draws only at
one z, so `NdxEss` (z 50: background, back cels, cels behind the enemy) spawns two `NdxEssLayer`
helpers (z 150 between the battlers, z 500 in front, with the foreground). Add blends add; subtract
draws the cel's inverse over the screen (the battle's canvas holds no backdrop to subtract from,
and a colour mask misdraws there).

A free cel showing a copy of a battler's picture (pattern -3 the user's, -4 the target's: Quick
Attack's afterimages, Foul Play's and Psychic's doubles, 54 animations) draws that battler's picture
as the battle shows it (`Ui.battlerPic`, 64 px), placed, zoomed, turned, tinted and blended like any
cel. A sound with no name is the attacker's cry (Essentials plays its user's: the attacker, whichever
version plays), through `Audio.playCry` with the species the cart's own cry tasks use
(`vm:speciesForSide`, else the battle's record), panned to the attacker; Gen 3's cries have no free
pitch, so the pack's pitch is not kept.

Not done: the cart's stat-change, item and switch animations (no exact counterpart), Double Team, Memento, Nature Power and Secret Power (the
pack has no real one), and Red/Blue/Yellow/Gold/Silver/Crystal, which play their borrowed cart
animations.

Rebuild with `python tools/build_ess_anims.py [--pack <dir>]` (Pillow, numpy, ffmpeg, and
pokeemerald-expansion beside this repo; `--no-sounds` keeps the converted sounds). Tests:
`tests/ess_anims_test.lua [game]` checks every file, sheet, cel, background and sound, resolves and
plays every move from both sides headlessly, the two-turn ones, the table animations, Curse and a
contest; `tests/drivers/ess_anims_probe.lua` plays them in a real battle (`MOVES=`, `FOE=1`,
`TURN=0`) and `tools/ess_gallery.py <shots>` turns the shots into a review page of GIFs.

## Type badges (option)

`src/type_badges.lua` draws a 12 x 12 badge per type beside each battle HP box: right of a foe's,
left of the player's, the second and third types 8 px down and out (corners touching). Every box
goes through the engine's `Healthbox.draw` (looked up on the module at call time), which skips a
hidden box, applies the slide-in and bounce, and hands the top left to `BattleChrome.drawEnemyBox`
/ `drawPlayerBox` / `drawDoublesBox`. Those are wrapped to note the box (only inside
`Healthbox.draw`; the Safari box is not noted), and `Healthbox.draw` to draw the badges after it.

- Placement uses `TypeBadges.EDGES`, where the box frames are in their top 8 rows (the shadow tail
  runs on below them, right of a foe's box and left of the player's): a foe's ends at x 92, the
  player's starts at x 9, both at row 2; the badges keep 2 px clear on either side. Measured
  from every cart's `pokemon/battle/healthbox_*.rgba`, singles and doubles: the same on all five,
  within a pixel. (Mod code may not read the ROM-derived cache files; see "Other mods' battle
  boxes" below for the pictures it does measure.)
- Types: the battler's `type1`, `type2` and `__ndxType3` (Forest's Curse), as numbers or names;
  a repeat is dropped, and `???` (9) only shows alone.
- The badges are on the battle's own UI canvas in their box's rows, so WoobleView's Fill Screen
  (which moves the UI's rows above y 66 up and docks the rest) carries them with their box.
  FRLG_VOXEL keeps its own reference to `Healthbox.draw`, so its battles show none.
- The wraps are process-wide (`Healthbox.__ndxBadges`); the option is read once and on
  `mod.options_changed`, never per frame. The badges' own code makes no garbage; LOVE's four draw
  calls make about 35 bytes a frame.

Tests: `tests/type_badges_test.lua [game]` (a stand-in `Healthbox.draw`: placement, slide-in,
hidden box, doubles, types, option), driver `tests/drivers/type_badges_probe.lua` (a real battle:
the badges' positions from the cart's box pictures, shots, garbage).

## Stat Hints (option `stat_hints`)

`src/stat_hints.lua` puts a chip per raised or lowered stat by each battle HP box: the label and the
stage's multiplier as a decimal rounded to hundredths (`(2+n)/2` or `2/(2-n)`; accuracy and evasion
`(3+n)/3` or `3/(3-n)`), green for a rise, red for a drop, in a rounded outline on white at 75%.
Every chip's text is built once (`TEXT[label][stage]`); a frame makes no string, table or closure.
It wraps `Healthbox.draw` and the three `BattleChrome` box draws the same way the type badges do
(process-wide on `Healthbox.__ndxStatHints`; `state.drawChip(text, up, x, y, w, h)` is the test
seam) and reads the battler's `stages` each draw, so the chips follow every move.

- Cause, then effect (`StatHints.holder`): every engine works a move out before playing it, so a
  stage is already changed while the move's animation and lines play. While a turn plays back the
  chips read a HOLD, a copy of the stages per battler (Gen 1/2: per side, with the battler it was
  taken for; another battler on that side shows nothing until it catches up). The hold is taken
  on every box drawn while nothing plays, and at these points while a turn plays:
  - **Gen 3:** "playing" is `AnimSeq.busy()`. Each action is worked out and played as its own
    sequence, and so is the end of the turn. A wrap of `AnimSeq.update`
    (`AnimSeq.__ndxStatHintsHold`) takes every battler on `Battle._st` when it returns true, which
    is before `after_anim_sequence` works out the next action.
  - **Red:** "playing" is queued rows, `current` or `animPlaying`. Each action is worked out when
    its queued row runs, so wraps of `BattleState:executeAction` and `:endOfTurn` (`hub.act`) take
    the hold first.
  - **Gold:** "playing" is the screen's `phase == "resolving"`. The whole turn is worked out first.
    A wrap of `Battle:useMove` (outermost call only) reads both sides' stages before the move and
    keeps them, weakly, on the first event the move makes (`state.marks`). A wrap of the screen's
    `advanceQueue` takes them into the hold when that event comes up.
  - **Tests:** `tests/stat_hints_test.lua` and `tests/gen12_extras_test.lua`. The probes
    (`stat_hints_probe.lua`, `gen12_stat_hints_probe.lua`) check in game that the new chip is not
    drawn before its move's "ATTACK ... rose" line has played.

- Placement (`state.spot`, `StatHints.layout`, game pixels): a foe's in rows under its box, from its
  left, 120 wide (`FRAME.enemy.rows`); yours in columns left of your box, past its type badges
  (`BADGES`), from y + 3 (a foe's third row ends on y + 2) to the text box (`TEXT_TOP` 112).
  Doubles: each box takes the band of rows whose top is nearest its own
  (`FRAME.doubles.bands`: the foes' at 0 and 29, 29 tall; yours at 66 and 89, 23 tall), columns
  outward of its badges, held on the screen (`spot.right`). No chip crosses `SPLIT` (row 66),
  where WoobleView's Battle Fit splits the UI in singles; in doubles its split is row 58, between
  the foes' bands and yours.
- Two ways to draw. With WoobleView (gen3-hd-sprites 0.8.6+, `exports.features.uiMap`, found with
  `mod.find` in main.lua) the chips are measured in LOVE's own font (`StatHints.HI`: 6 tall, size
  5, pad 1), queued while the boxes draw (`StatHints.enqueue`, slots reused), and drawn from
  `render.hud` (main.lua's hook, `state.hud`) at window resolution: where `exports.uiMap()` says
  WoobleView put the UI canvas this frame (banded: a chip above `map.split` goes with the top
  band, clipped to `topBox`), else by the Renderer's own UI canvas blits, noted by a
  `Renderer:blitCanvas` wrap (`Renderer.__ndxStatHintsBlit`). Fonts are cached by pixel size.
  Without WoobleView: a 3 x 5 font of our own, each chip an image made on the CPU once per text
  (`StatHints.PIXEL`: 9 tall), drawn on the UI canvas.
- Red to Crystal (`src/gen12/stat_hints.lua`) use the pixel chips by their HUDs (`CLASSIC`,
  `WIDE1`): a foe's under its HUD from (8, 33), yours in rows ending at x 152 above your HUD
  (row 47), 64 wide (clear of the foe's chips), further rows above. Stages come from the
  mechanics layer's `A:stage` (Red's Sp. Def is ours). Red draws with the HUDs (`drawHUDs` +
  `drawZonePass` hub `BS.__ndxStatHints`) or from `battle.overlay` in the wide layout; Gold after
  `drawEnemyHud` / `drawPlayerHud` (`GS.__ndxStatHints`).

Tests: `tests/stat_hints_test.lua [game]` (text, every move redrawn, singles and doubles placement,
seven changes on all four doubles boxes, the split row, the window-resolution path through a stub
WoobleView, the option, garbage), drivers `tests/drivers/stat_hints_probe.lua` (Emerald: Swords
Dance twice through the battle's menu, singles and doubles, every chip clear of every box) and
`tests/drivers/gen12_stat_hints_probe.lua` (Red / Gold: Shell Smash, then Swords Dance).

## Other mods' battle boxes (Facets)

Facets' BATTLE UI box sets (XY, DP, HGSS, BW, B2W2, GAIA, PLATINUM, the ZEKE recolours...) swap their
own healthbox pictures onto `BattleChrome` (`_enemyBox`, `_playerBox`, `_doublesOpponentBox`,
`_doublesPlayerBox`) for the length of each `Healthbox.draw`, at the same 128 x 32 / 128 x 64 sizes
and top left, but with their own frames: DP's foe box runs to x 99 with an arrow out to 105,
HGSS's sides slant, BW and B2W2 start at row 4. On Red / Gold (its `classic_hud.lua`) it draws a
Gen 3 box in place of each HUD in the wide layout only: Gold from `drawEnemyHud` / `drawPlayerHud`,
Red from `battle.overlay`, hiding Red's own HUD through `battle.status_hud_visible`.

- `src/box_shape.lua` measures a box picture once (weak cache by picture): each row's first and
  last drawn column. A LOVE Image is drawn onto a small canvas of its own and read back
  (`push("all")`, `newImageData`); ImageData (and test stubs with `getPixel`) is read as it is.
  Nothing is saved or shipped and no file is read. The canvas is made with `{ dpiscale = 1 }`.
  LOVE's default is the screen's DPI scale (2.625 on many Android phones), which read every edge
  back 2.625× too far out. That was 1.15.0's Android bug: badges far right of the foe's box and on
  yours, the foe's chips down by your Pokémon. A read-back larger than the picture is still
  sampled at each picture pixel, so the shape is always in the picture's own pixels.
- Gen 3: the badges' and chips' box wraps note the picture on `BattleChrome` as the box draws
  (whichever side of our wraps the swap happens, so a second game in the same run, where Facets'
  wrap ends up outside ours, still works). `Shape.likeGame` keeps `EDGES` / `FRAME` for a picture
  whose top 8 rows end where the game's do (the game's own on all five carts, measured: 20 of 20,
  and the recolour-only sets); any other goes by `Shape.badgeSpot`, which clears the frame on each
  badge's own rows, and `StatHints.spotByShape` (chips outward of the badges, under the foe's box
  past `max(bottom + 2, badge rows)`). In doubles the partner's box (same picture, offset from
  `Healthbox.CENTERS`) counts too: the taller sets' boxes reach into each other's rows.
- Gen 1/2: `Shape.watch(fn, ...)` runs the HUD draw (Gold's hub wraps) or the overlay's `next`
  (Red's overlay hooks, now at priority 1 so they run outside Facets' priority-0 wrap) with
  `love.graphics.draw` swapped for a recorder of 128-wide box pictures (`Shape.seen.enemy` /
  `.player`: picture, x, y; nested watches share the outer's notes; the draw is put back on an
  error). The badges then stack beside that box (`badgeSpot` with dx 0), the foe's chips start
  under it and yours end at its right edge above it; on Red a seen box counts as shown even though
  `statusHUDVisible()` says no.

Tests: `tests/box_shape_test.lua [game]` (Facets' DP and HGSS rows as stubs: shapes, badge spots,
the watch, the badges and chips by a swapped set in singles and doubles, a recolour kept in place,
a swap outside our wraps), `tests/gen12_extras_test.lua` (Red's overlay and Gold's HUD calls with
a mod's boxes drawn). In game: `tests/drivers/stat_hints_probe.lua` checks every chip and badge
against the picture actually drawn when it is a mod's (`WANT_MOD_BOXES=1` fails a run where the
set did not apply); run with Facets on and `gbcHud` set to a set (DP and HGSS: 0 failures on
Emerald, 2026-11-16), and `gen12_stat_hints_probe.lua` on Red / Gold with Facets' boxes and
`battleLayout = "wide"` (0 failures).

## Art

Pictures (battle, summary and Pokédex) come from a sprite mod:

```lua
local dex = mod:find("national_dex_gen3")
if dex then
  dex.exports.setArtProvider(function(speciesId, side, slot, shiny, kind)
    return mod.assets:path(side .. "/" .. speciesId .. ".png")  -- or nil
  end)
end
```

`side` is `"front"` or `"back"`; `shiny` is true for a shiny Pokémon's picture and `kind` says
where it is drawn (`"battle"`, `"dex"`, ...), both from the engine's `pokemon.sprite` ctx (a
provider written for three arguments ignores them). Return a PNG path (the engine centres and
crops it to 64×64), or nil to let the next provider answer.

## The WOOBLEDEX options row (`src/options_row.lua`)

A `ui.options.rows` wrap appends one row (`id = "national_dex_gen3:options"`, value "N OPTIONS", the
count of the schema this game defined) to the game's own OPTIONS list on every game: Red's and
Gold's `OptionsMenu` and Gen 3's three option screens all raise the hook, and a row in no group
lands after the engine's ordered rows (after MODS). A opens the mod manager and moves it onto this
mod's settings page through the manager's own steps, since no API opens one mod's page:

- Gen 3: `src.ui.game3.mod_manager` `show({ game })`, then its `_mgr` (a `ManagerState`);
- Gen 1/2: `Screens.push(game, "ManagerState")` (the stack's push runs `enter`, which fills `byId`);
- then `m:openOptions(m.byId[mod.id])` and `m.backStack = {}`, so B (`goBack`) pops the manager
  straight back to OPTIONS instead of to the mod list.

Values go through the manager's `setOption` (save options, the loader's copy, the file and
`mod.options_changed`), so nothing here stores a setting. Any step failing leaves the manager on
its list, as MODS does. Not wired in the Gen 3 save editor. Test: `tests/options_row_test.lua [game]`
(the real Gen 3 manager and the real `StateStack`; 84 checks over seven games).

## API (`mod.exports`)

| Export | Returns |
|---|---|
| `isActive()` | always `true` |
| `provider()` | always `"national_dex_gen3"` |
| `listSpecies()` | `{ { dex, id, slot, name, legendary, mythical } }` |
| `slotOf(idOrDex)` | the running game's slot |
| `idOfSlot(slot)` / `listForms()` | (apiVersion 2) a slot's species id, and the registered forms (a form has `baseSpecies`) |
| `evolutionsOf(idOrDex)` | `{ id, dex, evolvesFrom = { id, methods }, evolvesInto = { … } }`, also for a cart species that gains a step into a new one, e.g. `evolutionsOf("RHYDON")` |
| `registerOwned(session)` / `formLabel(slot)` | (apiVersion 3) Register Owned's step as the game's Pokédex runs it on opening (every party and PC Pokémon marked caught; `0` while the option is off), and a form's name as the FORMS page shows it (`"GALARIAN"`, `"RUBY CREAM"`; `nil` for a base species). For a Pokédex that opens in the game's place (WoobOS) |
| `setArtProvider(fn)` | registers an art provider |
| `setDexPeek(fn)` | `fn(speciesSlot) -> true` lets that unseen species open in the Pokédex in a limited view (number shown, name dashed, "?" picture, no cry, only the AREA page). `nil` turns it off. Modern Spawns uses it |
| `artHeightOf(idOrDex)` / `artHeights()` | (1.17.0, by presence; every game) each WoobleSprite front picture's measured size in metres, for height charts (WoobleOS's Pokédex): `{ id, dex, slot, pokedex, standing, art, width, long }`. `standing` is the resting picture feet to top (the height to draw beside a person), `art` feet to the top over the whole animation (WoobleView's battle size), `long` when the Pokédex number is a length. A string is a sprite id (`"VULPIX_ALOLA"`, `"MEOWSTIC_FEMALE"`), a number the base species' National number. `src/art_heights.lua`, `data/art_heights.lua` |

## Achievements (`src/achievements.lua`, `data/achievements.lua`)

33 achievements in Recomp Achievements (its provider API 1.x, `docs/PROVIDER_API.md` in that mod;
`optional_dependencies` keeps it loading first). Without that mod, `mod.find` returns nil and
nothing runs. Ids are saved by that mod (`mod:national_dex_gen3:<id>`): never change or reuse one.

- **Every one is a progress achievement counted from the Pokédex**, never from our own
  counters: nothing of ours is saved, a save from before this is credited when it loads, and
  catching, evolving, hatching, trading and Register Owned all count the same way.
- **The definitions** in `data/achievements.lua` combine `range`, `dex` (a group name or a list),
  `flag` (legendary / mythical: the cart's 386 from `groups`, the newer species from their own
  flags), `forms` (`"all"`, or `"regional"` with an optional `region`: a form whose `form` starts
  with ALOLA / GALAR / HISUI / PALDEA), `family` (a base species id plus its forms) and `goal`
  (a milestone). `Achievements.build` turns them into National numbers plus form ids; the goal
  is the group's size, worked out at load.
- **The reader** each path hands over: Gen 3 reads the session's Pokédex by species slot
  (`P.speciesFromNational`, a form's own slot; fixups' form wrap marks the base too), Red and Gold
  read `save.pokedex` (Red `owned`, Gold `caught`) by species id, a form by its own id, the
  National number from `data.pokemon[id].dex`.
- **Progress is written only when it changed**, on the achievements mod's `ready` event,
  `save.loaded` (both reset the cache), and after a catch, evolution, trade, battle, map change or
  closed screen. A refresh is one pass over 1025 numbers and 128 forms. Reaching the goal unlocks
  it; the record then keeps no count.
- Test: `tests/achievements_test.lua [game ...]` loads the real Recomp Achievements beside this
  mod (FireRed, Red and Crystal by default) and attaches a save through `save.loaded`.

## The games' own paths (gap audit, 2026-11-16)

An audit of moves, abilities and held items on both families found the same two causes behind
most gaps; keep to these when adding a mechanic:

- **A hook only counts where something asks it.** The shared held-item family
  (`src/held/effects.lua`) registers hooks every game must consult. Gen 3's core asks them at its
  seams in `src/held/gen3.lua` (`battle.damage` for `dropTypes`, `Effects.run` for
  `screenTurns` / `weatherTurns` via `hub.lengthen`, `Secondary.set` for Covert Cloak, Hit.run /
  `Engine.moveEndEffects` for Protective Pads, an `Adapter.new` heal wrap bracketed around the
  drains for Big Root); `src/move_field.lua` asks `terrainTurns` / `ungrounded` through
  `heldHook`. Other Gen 3 modules reach a battler's item through `HeldItems.__ndxHeldHub.kindOf`.
  The Gen 3 adapter's `weather()` goes through `Rules.weather.kind` (Rain Dance's weather is
  "RAINY").
- **A guard on one seam misses the game's other paths.** Gen 3 forces statuses past
  `canApplyStatus` (Rest, the drowsy turn, `Abilities.applyStatus`): `terrainGuard` and
  `More.statusGuard` (which includes `RealAbilities.guarded`) are asked at each. On Red to
  Crystal the games write confusion, flinches, Rest's sleep, drains, residual damage, multi-hit
  counts, Protect, Roar and their own Spikes / sandstorm directly: the before-move snapshot
  (`src/gen12/mech/abilities_more.lua` `snap`) notes confusion and flinches and the after-move
  corrects them (blockStatus, noFlinch, statusInflicted, the drain hooks); the adapters wrap
  `Status.residualStatus` / `residualSeed` (Red: corrected after, they return their lines) and
  `Battle.tickStatus` / `tickSeedAndCurse` / `spikesDamage` / `tickWeather` (Gold: decided before,
  they emit as they go), Red's `effectRecord` and Gold's `Effects.hitCount` (Skill Link),
  `Battle.moveEffectRecordFor` (Gold's Roar: the battle runs the merged record), and the field
  puts Protect / Substitute / Gold's screens aside for one move (Unseen Fist, Infiltrator).
- **Data the runner can't act on is not an effect.** `src/gen12/mech/abilities.lua`'s `BY_HAND`
  skips a kind for abilities written out (Flash Fire after absorbing, the charge abilities, Hadron
  Engine / Orichalcum Pulse under their terrain / sun); `gen12_mech_test`'s coverage counts an
  ability only when every effect's trigger and kind are ones the runner handles, or it is named
  in the code.
- **Tests that run whole moves.** `tests/move_gaps_test.lua [game]` resolves real moves through
  `Engine.resolveMove` (the real accuracy check and hit; a text sink that fails on a nil id),
  `tests/gen12_gaps_test.lua [version ...]` runs Red / Gold through `H.sim` and the games' own
  residual ticks. Compare damage inside one battle or through `damageMult`: a fresh battle rolls
  new stats and abilities, and Gold's simulator lifts every fourth roll.

## Abilities (Gen 3)

- `tools/build_abilities.py` `IMPLEMENTED` (append-only: a Pokemon's ability pair is by id) writes
  `data/abilities.lua`; the ids run 78-255, so check nothing keeps an ability id in a byte before
  adding one past 255.
  `src/abilities.lua` gives each its number, name, text and the species' pairs, answers
  `abilityOf` by species and slot, and acts for its 52 (header).
- `src/abilities_more.lua` acts for the other 126, on the same seams plus a few more (its header
  lists them): `battle.damage` / `battle.crit` / `battle.accuracy` / `battle.turn_order` hooks
  at load; on game.ready wraps of `Adapter.new` (abilityOf for Neutralizing Gas and Mold
  Breaker's whole move, canApplyStatus guards and Corrosion, applyHpLoss + sayText for Magic
  Guard / Overcoat: a known indirect-damage message id with that battler as subject drops the
  loss and the message), `Damage.calc` (Unaware, Scrappy, Infiltrator, Refrigerate), `Hit.run`,
  `Effects.run`, the move context's `accuracyCheck` / `isProtected` (patched on its metatable),
  `Engine.resolveMove` / `selfHit` / `switchInEffects`, `Ab.switchIn` / `absorb` / `onDamage` /
  `endTurn` / `switchOut` / `runIntimidate`, `Secondary.changeStat` / `withChance`,
  `HeldItems.of` / `has` / `normal`, `RealAbilities.speedModifiers` / `priorityOf`, and the held
  items' core (`itemSuppressed`, `gluttony`, `ripen`, `ateBerry`, `noIndirect`). Process-wide
  wraps read the newest install through `Abilities.__ndxMoreHub`. It also sets
  `MoveField.startTerrain` / `MoveField.noIndirect` (Stealth Rock) and `MoveRules.weightScale`.
- Forms that change in battle have no registered slot: their stats go on `__ndxStat` (computed
  from hand-written base stats with the Pokemon's IVs, EVs, level and nature), which move_rules'
  Damage.calc wrap and `RealAbilities.effectiveSpeed` read; the picture stays.
- Tests: `tests/abilities_test.lua`, `tests/abilities_more_test.lua [game]` (whole moves through
  `Engine.resolveMove`: `ad.roll` low, `st.rng` high for the damage and critical rolls). Driver
  `tests/drivers/abilities_probe.lua` (a real battle: Intrepid Sword on entry, Mold Breaker's
  Earthquake on a Levitate Gastly, Disguise; Emerald and FireRed 0 failures 2026-11-13). The game
  hands `Engine.resolveMove` a side or slot, not a battler: resolve it with `State.occupant`.
  A species of this mod answers its own ability ahead of a battler's `ability` field: give one
  by `expTracedAbility`, as Skill Swap does.

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
- Level-up learnsets keep their modern length (9,302 rows across 639 species). Newer moves are
  real where `tools/build_moves.py` could build them (419 moves, 4,482 level-up/egg uses); the
  other 7 are swapped for the closest cart move (`tools/.cache/move_substitutions.txt`).
  TM/HM and tutor moves are Gen 3's own.

## Rough areas

Things that work but not exactly as in today's games, or are only partly verified.

- In-game (driver) checks cover Moonblast, Nasty Plot, Close Combat, Snow Warning, Wicked Blow,
  Heavy Slam, Mind Blown, Trick Room's turn order, Stealth Rock damage on entry, U-turn (through
  the real party prompt), Dragon Tail, Spiky Shield's and King's Shield's punishment and Soak, on
  Emerald, FireRed and Sapphire. Everything else is checked headlessly only (`tests/moves_test.lua`,
  `move_effects_test.lua`, `move_rules_test.lua`, `move_field_test.lua`, `abilities_test.lua`).
- Double battles: only a headless doubles state (Decorate, Pollen Puff on a partner) is tested.
  The turn stamps (Sucker Punch, Payback, Bolt Beak, Fusion Flare/Bolt) and the switch-out moves
  were written with singles in mind.
- Protection variants keep their own "used last turn" streak; the cart's Protect after one of
  them doesn't see it (and vice versa). Shed Tail makes the cart's Substitute (a quarter of HP,
  not half). Phantom Force / Shadow Force vanish with a kind of their own (`"VANISHED"`): only
  this mod's wraps make attacks miss them, so a cart status move can still reach them.
- Ability changes write `expTracedAbility` (+ `ability` for the AI); Simple Beam gives "SIMPLE",
  which nothing in the cart's battle engine implements, so it works as "no ability". Power Split
  / Guard Split / Power Trick / Speed Swap keep their numbers on the battler (`__ndxStat`, read by
  this mod's damage wrap and turn order only); the cart's own speed ties and the AI's estimates
  read the real stats.
- Wonder Room swaps DEFENSE and SP. DEF in this mod's damage wrap only; Magic Room hides items
  from `HeldItems.itemOf` (the battle's reads), not from the Bag. Fairy Lock uses `canSwitch` /
  `canRun`, so a Roar-style forced switch still works.
- Fling's powers cover the items Gen 3 has (a berry is 10, an unlisted item 30) and the item is
  used up (as in the real games); Natural Gift uses the Gen 6+ 80/90/100 table. Bug Bite / Pluck
  remove the foe's berry without eating its effect; Belch remembers a berry eaten since the
  battler came in (`expUsedHeldItem`). Beak Blast is a plain hit (no burn on contact); Shell Trap
  needs a physical hit taken this turn but doesn't go last.
- Gen 3 splits physical/special by type: Foul Play (Dark) is a special hit with the foe's Attack
  standing in for Sp. Atk; Body Press / Secret Sword / Psyshock swap into the stat the move's
  type reads; Dragon Tail is special.
- Trump Card: the AI's damage estimate reads PP before this use's PP comes off.
- Population Bomb is 10 hits on one accuracy roll; Scale Shot's stat change applies once.
- Rage Fist's count is kept on the battle, keyed by the party mon (survives switches, never
  saved); Last Respects counts the user's side's faints this battle.
- Hazards: Defog clears both sides' hazards and the foe's screens; the cart's Rapid Spin clears
  its user's side. Toxic Spikes ignore Safeguard (as in the real games); Misty Terrain's guard
  applies.
- Terrains boost 1.3x (Gen 8+). Psychic Terrain blocks priority attacks, not priority status
  moves; Grassy Terrain does not halve Earthquake; Misty Terrain does not block confusion.
- Terrain guards (`terrainGuard`: Misty every status, Electric sleep) also cover what the cart
  forces past `canApplyStatus`: `Status.cantMakeAsleep` (Rest, the sleep moves), the Yawn move
  (`EXP_YAWN_EFFECT` in the `Effects.run` wrap), a drowsy Pokemon (battler phase
  `ndx_yawn_guard` before the cart's `yawn`) and `Abilities.applyStatus` (Effect Spore, Static).
  Turns and grounding ask the held items' core through `HeldItems.__ndxHeldHub` (Terrain
  Extender's `terrainTurns`, Air Balloon's `ungrounded`). Nature Power: `Engine.NATURE_POWER_MOVES`
  is a lookup table that answers the running battle's terrain (`Battle._adapter`) before the
  background. Secret Power / Camouflage: `Engine.terrainOf` answers ids 101-104 on a terrain,
  added to `EffectIds.SECRET_POWER_BY_TERRAIN` and `Setup.TERRAIN_TYPE`; Ruby / Sapphire's
  `effect_chance_rs.prepare` is wrapped (its table is local). Red to Crystal: Rest fails through `beforeMove` (`mech/field.lua`), Yawn asks
  `blockStatus`, Nature Power picks by terrain (`mech/power.lua`). Tests: `move_field_test`,
  `gen12_mech_test`.
- Tailwind and Trick Room order the two battlers the engine compares; ties keep the cart's coin
  flip. Both go through the real abilities' turn-order hook, so they need the abilities on.
- Evolution item icons are not verified in-game.
- `clock_test` / `lycanroc_test` fail when the local `options.lua` sets `clock_source = "device"`.

**Messages.** Lines Gen 3 has no string for are English text in code (hazards, terrains, Clear
Smog, Sparkling Aria, Mind Blown, several abilities). 12-letter names and both-box summary texts
are hand-written where the official ones don't fit; animations are borrowed from the closest
cart move (`look`); contest data for the newest moves is basic.

**Abilities.** Leaf Guard / Sweet Veil / Flower Veil don't stop a move's secondary status; Super
Luck doesn't stack with high-crit moves; Ice Body / Snow Cloak don't block hail damage;
Adaptability is approximated through the `battle.damage` hook.

**Engine-side** (not this mod's to fix; worth reporting upstream):
- The registry writes a new move's/species'/item's NAME into the index where the number belongs
  (`Schemas` `index.num[id] = id`); `src/moves.lua` puts numbers back after every write.
- Facade, Revenge and SmellingSalt never double through `Hit.run`: `calc_opts` passes
  `dmgMultiplier = 1` and damage.lua only doubles when that field is falsy. Confirmed headlessly:
  a burned Facade deals 17 where a healthy one deals 34 (the burn halves it, nothing doubles it).
- Removing the mod from a save whose Pokemon know its moves breaks that battle (`Moves.get`
  errors on an unknown number); the same holds for its species.
- Link play: the Fairy type changes the type chart fingerprint; cross-gen online has no type 18.
- Source patches (`dex_patch.lua`, `type_icons.lua`) match engine text exactly and fall back to
  the stock behaviour (logged once) when an engine update changes it.

## Moves still substituted (7)

`tools/.cache/moves_new.txt` lists them. The engine fixes the turn order once per turn and has
no way to make a battler act out of turn or repeat a move mid-turn, and nothing lets a mod swap
two battlers' positions or hand an item over with the Bag's bookkeeping: After You, Quash,
Instruct, Me First, Ally Switch, Bestow, Teatime.

## Gen 1 and Gen 2

Red/Blue/Yellow and Gold/Silver/Crystal get their own path. `main.lua` hands over to
`src/gen12/main.lua` when `mod.generation` is 1 or 2, before any Gen 3 module loads. A host that
names no generation stays on the Gen 3 path; the SDK's `loadMods` defaults to 1, so every Gen 3
test passes `generation = 3`.

- **Where things live:** Gen 1/2 code is in `src/gen12/` and data in `data/gen12/`. The existing
  `src/*.lua` and `data/**` files are not edited for this path.
- **Proof Gen 3 is untouched:** `tests/gen3_fork_test.lua [firered|emerald]` compares a fingerprint
  of everything a Gen 3 game gets from the mod with the one recorded before the fork
  (`tests/fixtures/gen3_fork_<game>.lua`).
- **Conflicts:** `manifest.json` lists `national_dex` in `conflicts`. The loader skips mods made for
  other games before it weighs conflicts (`Loader:_gateGeneration`, then `_enforceConflicts`), so the
  conflict only matters on Gen 1/2. There, WoobleDex is the one that steps aside.
- **Options:** the manifest's `options_schema` is Gen 3's. The Gen 1/2 path declares its own list
  with `mod.options:define`, which the Mod Manager reads first.
- **Tests:** `tests/_gen12.lua` builds a Red/Yellow (Gen 1: every generated module plus
  `Data.seedDefaults`) or Gold/Crystal (Gen 2: the keys `Game2` builds) dataset from the imported
  cart. The `tests/gen12_*_test.lua` suites (load, data, types, moves, battle, species,
  evolutions, art, api, extras) run on red, yellow, gold and crystal (name others on the command
  line).

### The Gen 1/2 data (`tools/build_gen12.py` -> `data/gen12/`)

Generation-neutral: `src/gen12/` shapes it for the running game. Red has species #1-151 and
moves #1-165, Gold #1-251 of each; the data covers everything past that.

- **`species/NNN.lua`** (#152-1025, 80 per shard) and **`forms.lua`** (the 128 of
  `tools/form_list.py`):
  - **Typing and stats:** modern typing, with Fairy, and Dark/Steel on Red.
  - **Names and Pokédex text:** names and kinds fit in 10 characters. The 33 longer names and 52
    longer kinds are shortened by hand (`NAMES`, `KINDS`); any other two-word kind just drops its
    space. Pokédex text is reflowed to 2 pages of 3 lines of 18 characters, with over-long words
    broken at a hyphen.
  - **Moves:** listed by National move number: the newest full level-up list, moves #1-251 any
    game teaches by machine or tutor, and egg moves.
  - **Evolutions:** tools/build_species.py's steps, plus `EXTRA_EVOLUTIONS` (Tyrogue by stats,
    Wurmple by a 1-in-2 pick). A Gold species' conditional steps are its own record's too, so they
    work on Red, where it is new.
  - **`proxy`:** per generation, the cart's own species id (Gold spells some its way: `MR__MIME`)
    whose party icon and cry the species borrows. That is the nearest relative in its evolution
    family, else the same body shape and type at the closest stat total.
  - **Keys:** ids and slots equal the Gen 3 path's (the test checks this).
- **`moves.lua`:** every move past #165 that some list names.
  - **A real move or a stand-in:** a move runs natively on a game (`gen1`/`gen2` =
    `{ effect, chance }`) when its Gen 3 effect (FireRed's table, or `data/moves.lua` for #355+,
    with rules and extras excluded) is also the effect of a cart move on that game. The cart's
    effect for that move is then used: the family most such moves share, then the Red variant
    closest in chance. Dizzy Punch confuses only from Gen 3, so it must not outvote Psybeam.
  - **Gen 2 priority:** Gold orders moves by effect, so a plain hit with priority becomes
    `EFFECT_PRIORITY_HIT`, and an effect whose priority sign differs is refused.
  - **Stand-ins:** every other move gets `subs[genN]`, the 8 closest moves (tools/move_map.py,
    with Fairy kept). The candidates are the cart's moves plus the newer moves that run natively
    there, minus `STAND_IN_EXCLUDED`. The mod takes the first stand-in the species does not
    already learn.
  - **`look`:** per generation, for each real move, the cart move whose battle animation it
    borrows: the Gen 3 path's pick (`data/anims.lua` `looks`, then `data/moves.lua` `look`) when
    that cart has the move, else the closest cart move by type, class and power.
  - **Report:** `tools/.cache/gen12_moves.txt`.
- **`crossgen.lua`:** evolutions from species #1-251 into newer ones. The mod keeps the steps whose
  source the running cart has and whose target it lacks. A `knows` condition names the real move;
  Gen 3's stand-ins are replaced through `REAL_KNOWS`.
- **`cart.lua`:** per generation:
  - the cart species and moves whose modern typing differs. Red: 7 species and 4 moves (Bite,
    Gust, Karate Chop, Sand-Attack). Gold: 13 species and 3 moves;
  - the types the game gains (`types`) and the matchup rows that make every pair with Dark, Steel
    or Fairy read as today's chart. These are computed from PokéAPI's damage relations against the
    cart's own rows: `add` (Red 38, Gold 12), `change` (none today) and `remove` (Gold's Ghost and
    Dark rows against Steel). The cart's other rows stay as the game has them, so Red keeps Ghost
    doing nothing to Psychic.
  - Type names are the modern spellings (`PSYCHIC`); the mod turns them into cart ids.
- `tools/gen12_cart.lua` is the build tool's only window into the carts (it prints them as JSON);
  the mod never reads cart files.

### Types and growth rates (`src/gen12/types.lua`)

Registered at load, first, so every record after can name them.

- **Types:** the `type_chart` registry owns the whole chart on these games (the engine registers
  the cart's records and rows first; the merge rebuilds `types` and `matchups`), so the new types
  are plain registrations: Red gets DARK, STEEL and FAIRY, Gold FAIRY. Categories are Steel
  physical and Dark special (as Gold), Fairy special (as the Gen 3 path). Gen 2 types also need an
  `index` (Present and Conversion2 read it), so FAIRY takes 28, after Gold's 0-9 and 19-27.
- **Rows:** `cart.lua`'s `add`/`change`/`remove`, turned into cart ids (`PSYCHIC_TYPE`).
- **Typing:** the cart's species and moves are patched (a patch replaces a list whole).
  `Types.forCart` writes a single type twice on Gen 2, as Gold does.
- **Growth rates:** ERRATIC and FLUCTUATING (`GROWTH_` prefix on Gen 2), pret's formulas with level
  1 = 1 Exp. Gen 1 reads them through `Growth.expForLevel(..., data.growth_rates)`, Gen 2 through
  `Mon.growthFor`. A few engine paths call Growth without the registry (link trade's level check,
  box migration) and fall back to Medium Fast for these two.
- **Known limit:** exporting a `.sav` writes a fresh Gen 1 Pokémon's type bytes from the species'
  types, and Red has no byte for Steel or Fairy (0 = Normal). Only cart species retyped by this
  mod are affected (new species are refused by the export anyway).
- **Test:** `tests/gen12_types_test.lua`: the chart, categories, typing and curves through the
  engine's own Gen 1 and Gen 2 code, and both curves equal to the Gen 3 tables at every level.

### Moves (`src/gen12/moves.lua`)

- **Real moves:** every `moves.lua` row with `gen1`/`gen2` is registered on that game (Red 182,
  Gold 172):
  - the cart's effect; Gold also gets `effectChance`, which the registry write turns into the
    `effectChanceRaw` byte the battle rolls against;
  - an accuracy of 0 (PokéAPI's "never misses" for status moves) becomes 100, as the carts store
    them;
  - Red reads `priority` and `highCrit` off the move. Gold orders moves by effect (Aqua Jet runs
    on `EFFECT_PRIORITY_HIT`) and keeps its high-critical list in
    `type_chart.battleRules.highCriticalMoves`, outside any registry, so `Moves.installHighCrit`
    adds ours to the live table on `game.ready`;
  - Gold's moves keep their National number as `index`. If that number is taken, the engine picks
    one.
  - An id another mod already registered is used as it is (`borrowed`).
- **Animations:**
  - Red: `battle_anims:register(id, <look's moveAnims record>)`, plus the look's `anim` (the
    move's sound) on the record.
  - Gold: one `battle_anims:patch("moves", { [id] = <look's script pointer> })`.
- **The resolver:** `Moves.resolver(state, cartMoves)` returns `resolve(n, taken)`. It gives the
  cart's move for #1-165 (Red) or #1-251 (Gold), else the registered move, else the first
  stand-in the game has that is not in `taken`. Every learnset goes through it (`project.lua`).
- **No index on Red:** Red's battle, Metronome and saves work by move id, so a registered move
  needs no `index` there. A `.sav` export writes a move it has no number for as 0, an empty slot
  (`GenSave.lua`, `movesIndex[id] or 0`). Gold's #252+ do not fit the cart's move byte either.
  The README says so.
- **Tests:**
  - `tests/gen12_moves_test.lua`: every row registered as the data says, animations, Gold's
    index and high-crit list, and the resolver over every number.
  - `tests/gen12_battle_test.lua`: fires every registered move in a fresh wild battle in Red's
    `BattleState` (`performMove`) and Gold's `Battle` (`useMove`), both directions, and checks
    that type matchups reach the damage (Night Slash on Abra).

### Species and forms (`src/gen12/species.lua`, `src/gen12/project.lua`)

- **What is registered:** every data species past the cart's own (Red 874, Gold 774) and all
  128 forms. An id the registry already has (another mod's) is left alone (`kept`).
- **`project.lua`** is pure: data record + what the game supplies -> the engine's own record.
  - **Both games:**
    - types through `Types.forCart`, growth through `Types.growthId`;
    - evolutions left empty (`evolutions.lua` fills them);
    - extra top-level fields: `slot` (the Gen 3 slot, the stable key), `legendary`/`mythical`,
      and `spAttack`/`spDefense` (modern_spawns reads them on Gen 1);
    - forms carry `baseSpecies` (the running game's own id for that dex: Gold spells
      Farfetch'd `FARFETCH_D`), `form` and `baseDex`.
  - **Moves:** the level-up list goes through the resolver.
    - A stand-in is never a move the species learns for real anywhere in its list.
    - Each move appears once.
    - The first move is always at level 1 (Crabrawler's comes at 5, and a Pokémon with no move
      cannot battle).
    - Machine and egg moves are never substituted (as on Gen 3): only moves the game has, and
      machines only from the game's own TM/HM set. That set is the union of the cart species'
      `tmhm` lists, since Gold keeps its machine list outside any registry; on Crystal it takes
      in the three tutor moves.
  - **Gen 1:**
    - `special` = Special Attack;
    - `level1Moves` = the last four level-1 moves, `learnset` = the rest;
    - height in ft/in and weight in tenths of a pound (plus `heightM`/`weightKg`);
    - the entry `text` is a label: Red's Pokédex reads `data.text[label]`, pages split by ``.
      `species.lua` registers one `text` record per species (`_national_dex_gen3_<ID>`), ending
      in `{DONE}` so the Pokédex adds no period of its own.
  - **Gen 2:**
    - split specials, `levelMoves`;
    - a single type and a single egg group written twice;
    - `eggSteps` = egg cycles;
    - the entry inline (`<NEXT>` between lines, `text2` the second page), which Gold's
      `PokedexText.apply` merges into its Pokédex;
    - `index` = 1000 + dex for species and 1000 + slot for forms: past every cart index, never
      255, never shared. On a collision the engine picks one.
  - **Forms** get dex `20000 + n` (n = place in `forms.lua`): Red's Pokédex lists species with
    `pairs`, so a form sharing its base's number would randomly stand in for it.
- **Save editor** (`src/gen12/editor.lua`): the stock editor lists `data.pokemon` as it is, so a
  form read "VULPIX #20091". While the editor loads mods (`Gen` and `App` requirable,
  `App.getState()` a session with no `mods`/`cat` yet; a Gen 1 `mod.game` is never nil, so the
  Gen 3 check can't be used), a `mods.loaded` listener at priority -1000 relabels every form
  "VULPIX (ALOLAN)" (`src/dex_forms.lua` `label`) with its base's number, as the Gen 3 editor
  does. Nothing reaches a game: none runs there, Gold rewrites a mon's copied `name` on every
  save load (`Mon.syncSaveIdentity`), and a game after the editor closes builds fresh records
  (`App.unload` drops the session). Test: `tests/gen12_editor_test.lua` (the real Gen / App /
  Catalog modules, only the session faked).
- **Placeholder pictures** (`assets/gen12/`, drawn by `tools/build_placeholder.py`, our own art):
  a grey ball with a "?" (front 56x56, `frontSize`/`picSize` 7) and the ball from behind (32x32
  on Red, 48x48 on Gold). They use the carts' four shades on transparent white, so each game
  tints them as it tints its own. Stage 7 lets sprite mods draw over them.
- **Test:** `tests/gen12_species_test.lua`. It checks every record's shape, that every move
  exists, the pictures, Red's entry labels (lines of 18) and Gold's Pokédex merge, and Gold's
  indices. Then each game's own code builds every species and form at Lv 5 and 50, and a wild
  Garchomp uses its moves in each battle.

### Evolutions and items (`src/gen12/evolutions.lua`, `src/gen12/items.lua`)

- **Rows:** every registered species and form gets its evolutions. Each cart species gets the
  newer ones it lacks from `crossgen.lua` (source on the cart, target not), added after its own
  rows. Data steps become the game's own rows:
  - **Gold:** `EVOLVE_LEVEL`, `_ITEM`, `_TRADE` (+ held item), `_HAPPINESS` (+ `MORNDAY`/`NITE`)
    and `_STAT` (+ `comparison`).
  - **Red:** `LEVEL`, `ITEM`, `TRADE`, plus `FRIENDSHIP`, which this mod registers in
    `evolution_methods` (Red's registry takes mod methods; `describe` says "Friendship"). Red has
    no held items, so trade and held items become `ITEM` rows: the item is used on the Pokémon.
- **Conditions:** rows are strict records, so a step's `when` (the keys of
  `src/conditional_evos.lua`, whose pure `qualifies` decides them) lives in a side table keyed by
  `source>target#method`.
  - A wrap of `evolution.check` lets a row through only when its conditions hold. Both games run
    every row through it (Red: `game, mon, row, trigger`; Gold: `data, mon, row, ctx`) and take
    the first row that passes.
  - A species' rows with conditions come first, highest `priority` first, so a plain row at the
    same level (Midday Lycanroc) fires only when none of them does.
  - **Facts:** time (Red: the device clock through `src/clock.lua`; Gold: its own `timeOfDay`
    when the check has one); friendship (Red: the counter below; Gold: `happiness`); the held
    item (Gold) or the item being used (Red); gender, by Gold's own rule from the Attack and Speed
    DVs on both games (`Evolutions.gender`, inlined because Red's sandbox cannot require Gold
    modules); a stable 1-in-n pick from the DVs; the moves known; the party (`mod.game.save`);
    and coins (Red `save.coins`, Gold `save.player.coins`).
  - **Counters** on the Pokémon (`mon.extra.national_dex_gen3`): `stepsAsLead`
    (`world.stepped`), `moveUses` (`battle.move_used`) and `crits` (`battle.damage_dealt`, reset
    by `battle.started`). They are kept only for species with such a condition.
  - **What these games cannot know:** rain and the battle's terrain are left out (Burmy's female
    cloak is Plant; the Sandy and Trash steps are dropped). Recoil taken is replaced by level 36
    (White-Striped Basculin). A `knows` move the game lacks makes the step a plain level-up.
  - **On `pokemon.evolved`:** a held item that a level-up step asked for is used up (Gold), and
    Gimmighoul's 999 coins are spent.
- **Red's friendship:** a hidden counter, `mon.extra.national_dex_gen3.friendship` (Red saves and
  trades keep `mon.extra`). It starts at the species' base friendship (data, 70 for the cart's).
  It rises by 5/3/2 per level-up below 100/200/after (`pokemon.level_up`, battle levels only:
  the Rare Candy emits none) and by 1 per 256 steps for the whole party, Gold's own rates.
  Evolution needs 220. Vitamins and fainting do not change it (no event for either).
- **Items** (`data/gen12/items.lua`, from `tools/build_gen12.py`): every item a step names or
  wants held, with a 12-column name, a price and its kind (stone, trade or hold). The cart's own
  id is used where the cart has the item; otherwise it is registered.
  - **Red:** every new item carries one `item_effects` record (`Items.GEN1_EFFECT`), which picks
    the first `ITEM` row naming it (or listing it as the held item) whose conditions hold, and
    returns `"consumed", nil, { evolveTo }` so the Bag plays the evolution. The cart's own stones
    keep the cart's code, which evolves any `ITEM` row naming them.
  - **Gold:** an item to hold (pocket `ITEM`). A stone also gets an `item_effects` record of its
    own id with `action = "stone"`, whose `use` runs `Evolution.checkMon(..., { force = true,
    item })` as Gold's stones do.
- **Shops:** Red's Celadon Dept. Store 4F clerk (`text_pointers` `mart`, a deep registry, so the
  patch appends) and Gold's Goldenrod Dept. Store 4F, found by its own stock (the vitamins), so
  the list number never matters.
- **Test:** `tests/gen12_evolutions_test.lua` drives each game's own code (Red
  `Evolution.pendingFor` and `ItemEffects.use`; Gold `Evolution.checkMon`, its item records and
  `Evolution.apply`). It covers level, friendship, stat, 1-in-2, gender, a known move, the party,
  steps and coins, new and cart items, trade and held items, a held item used up, and both shops.

### Pictures, icons, cries and the Pokédex (`src/gen12/art.lua`, `src/gen12/dex.lua`)

- **Pictures:** a species no sprite mod draws keeps the placeholder. `exports.setArtProvider(fn)`
  is the Gen 3 contract, `fn(speciesId, side, slot, shiny, kind) -> PNG path or nil`, asked
  from a `pokemon.sprite` wrap. Both games resolve every Pokémon picture through that hook
  (Red `Sprites.path`/`Sprites.pic`, Gold `BattleState` via `Sprites.pic`), and `ctx.species`
  is the id. An answer sets `ctx.trueColor`, so it is drawn in its own colours, not the game's
  four shades. Only this mod's species are asked about.
- **Icons:** each species borrows its proxy's party icon (the builder writes `icon = { gen1 =
  <Red icon kind>, gen2 = <Gold ICON_ sheet> }`), registered through `icons` (Red
  `icons.bySpecies`, Gold `gen2Icons.species`).
- **Palettes:** Gold has none for the new species, so the placeholder draws in plain greys
  (`Palettes.monColors` -> nil). That is deliberate.
- **Cries:**
  - Each species registers `{ base = <proxy> }` in `cries`, which `Sound` resolves to the
    proxy's chip program (`resolveCry`). Gold's screens play a cry only when
    `audio.cries[species]` exists.
  - Species #387-1025 and their forms also have their own cry in `assets/cries/cries.pak` (the
    Gen 3 path's, indexed by slot in `data/cries.lua`, read here, never edited).
  - A wrap of `Sound.playCry` plays that one. The wrap is process-wide on
    `Sound.__ndxGen12Cry` (Sound is never reloaded, and the player may switch games in one run)
    and asks the current load's handler, which only answers for this mod's species.
  - It also wraps `Sound.setVolumeLevel` to follow the player's volume. Its scale is private to
    Sound.
- **Red's Pokédex:** the list runs to `constants.dexSize` (151, derived before mods load) in
  `dexDigits`; both are overridden to 1025 and 4. Forms (dex 20000+) stay off.
- **Gold's Pokédex:** `PokedexText.apply` adds every registered species with a dex number,
  forms included, once at boot. On `game.ready` (priority 1) the forms come out of `entries`,
  `newOrder` and `alphabeticalOrder`. Catching a form then skips the new-entry page
  (`openDexEntry` needs an entry).
- **Seen and caught:** a form marks its base (Red `seen`/`owned`, Gold `seen`/`caught`). This is
  synced on `pokemon.caught`, `pokemon.evolved`, `pokemon.received`, `battle.ended` and
  `save.loaded`.
- **Test:** `tests/gen12_art_test.lua`. It checks the pak's rows; that every new species has a
  cart icon and a cry that resolves; the provider through the engine's own `Sprites.pic` (and
  the cart's species untouched); Red's list (#1-1025 once each, no form); Gold's after
  `game.ready`; and the form-to-base marking. Audio cannot be decoded headless, so the pak's
  cries are heard only in game (the probe below).

### Exports and modern_spawns (`src/gen12/api.lua`)

- **Exports:** the same `src/api.lua` as Gen 3, loaded as it is and handed this path's lists in
  its shape:
  - `species` (`byDex`, sorted) and `forms` (`baseSpecies` is the running game's own id), each
    with `evolutions` as `{ species, method, level }` from the rows `evolutions.lua` wrote;
  - `bridges`: the steps added to cart species, recorded by `Evolutions.install`, so
    `evolutionsOf("GOLBAT")` finds Crobat on Red.
- **What is published:** `apiVersion` 3 (9 with the read API below), `isActive`, `provider`, `listSpecies`, `slotOf`,
  `listForms`, `formsOf`, `baseDexOf`, `idOfSlot`, `evolutionsOf`, `setArtProvider`,
  `registerOwned` / `formLabel` (Gen 3 only: `0` / `nil` here), and
  `clockSource` (Red `"device"`, Gold `"game"`: the clocks the time-of-day evolutions read), plus
  `generation`.
  - The slot is the Gen 3 slot (dex + 64, forms 1090+), the key shared by every game.
  - Method names are the running game's own (Red `LEVEL`/`ITEM`/`TRADE`/`FRIENDSHIP`, Gold
    `EVOLVE_*`); modern_spawns reads `LEVEL` and `EVOLVE_LEVEL` as levels.
  - `src/api.lua` also defines `setDexPeek`, `moveExtra` and `moveRule`, which answer nothing
    here, so they are removed again; callers test for them by presence.
- **modern_spawns** (`runtime.lua` looks for `national_dex` and then `national_dex_gen3`) reads
  the live records plus `evolutionsOf`. 785 of Red's 874 new species and 691 of Gold's 774 are
  spawn candidates (the rest are legendary or mythical, kept out unless asked for).
- **Test:** `tests/gen12_api_test.lua` covers the exports (lists, slots, forms, evolutions both
  ways, a cart species' bridge, the clock, no Gen 3 extras). It then loads `mods/modern_spawns`
  beside the mod and checks the candidate count, Turtwig's family and stages, a bridge in one
  family, and Red's Route 1 rolling only species the game has.

### The National Dex read API on Gen 1/2 (`src/gen12/dex_api.lua`, `data/gen12/api/`)

The g9 battle mods (g9-battle-engine, g9-Battle-Scene, g9-battle-sample) and battle_forms read a
National Dex through `mod.find("national_dex").exports`. The Gen 1/2 exports answer every call
they make (`apiVersion` 9), worked out from those mods' calls and national_dex's own README,
INSTRUCTION and CHANGELOG. National_dex's code and data were never opened. The engine resolves
`mod.find` and hard `dependencies` by exact id, so those mods only use WoobleDex once they look
for `national_dex_gen3` too.

- **Moves.**
  - `moveById(id)`: PokéAPI's facts for a move, found by the id this game registers it under
    (`AQUA_JET`, `PSYCHIC_M`), its separator-free spelling (`AQUAJET`) or its number.
    - Fields: `type` is this game's own id; `accuracy` 0 means it never misses; `damageClass`,
      `target`, `category`, `drain`, `healing`, `ailment`, `statChanges` and the hit counts are
      PokéAPI's words; `meta` keeps PokéAPI's shape.
    - `engineMove` is true for the cart's own moves.
    - `effectModeled` / `gen1EffectModeled` / `gen2EffectModeled`: whether the move runs as
      itself. The other generation's flag is only true when this game runs the move too. g9
      reads `isGen2 and gen2 or gen1`, which falls through to the Gen 1 flag.
  - `listMoves()`: only ids registered here. g9 patches each one.
  - `moveFlags(id)`: Showdown's flags as a set.
- **Abilities.** `abilityById(id)`: name, effect text, `effectChanges`, and a `behaviour` block
  written by hand in `tools/ability_behaviour.py`.
  - Ids are upper case with only letters and digits; names are plain ASCII, so `mon.ability`
    strips back to the id.
  - `behaviour` has `trigger`, `scope` and `chance`, plus `effects` from a small vocabulary:
    `stat_multiplier`, `damage_dealt_multiplier`, `type_immunity`, `heal`, `stat_change`,
    `set_weather` and others.
  - g9 lists the abilities each of its handlers takes and reads only the numbers from here.
  - `moveType` is stored modern and handed out as this game's id (`PSYCHIC_TYPE`).
- **Items.** `itemById` covers every PokéAPI item, retried with `HELD` on the end.
  `itemFlags` returns Showdown's facts (fling, natural gift, berry, plate type, holder).
- **Species.**
  - `statsBySpecies` / `statsByDex`: a deep copy of the registered record plus a normalised view:
    - `stats`, with Red's `special` and the split specials;
    - `abilities` (`{ name, slot, hidden }`) and `evYield` (all six keys);
    - `movesFull` (`{ level, move = separator-free id }`), the newest level-up list;
    - `movesByMethod` (machine, tutor, egg, other);
    - breeding facts, and `forms` on a base.
  - `listSpecies()` here covers all 1,025 species, the cart's included. g9 patches every listed
    species' learnset from `movesFull`, keeping the moves it can use.
- **Evolutions.**
  - `evolutionsOf`: PokéAPI's chain (`chainId`, `chain`, `stage`, methods with `trigger`,
    `item`, `heldItem`, `minHappiness`, ... and `text`).
  - The game's own rows fill in forms and any step the chain lacks. A row's engine method is
    kept as `method`, and `trigger` is PokéAPI's.
  - modern_spawns reads only ids and levels.
- **`patch(kind, id, partial)`.**
  - Overlay kinds: species, move, ability, item, moveFlags, evolution, itemFlags. Maps merge and
    lists replace.
  - Species and move fields the registered record has also go to the registry. That only lands
    while mods load.
  - The engine kinds (`typeChart`, `moveEffect`, ...) go to their registries whole.
- **Data:** `python tools/build_api.py`. It reads PokéAPI from `tools/.cache` and Showdown's
  `moves.ts` / `items.ts` at a pinned commit, cached under `tools/.cache/showdown/`. Output is
  2.5 MB of Lua in `data/gen12/api/`, loaded lazily on the first call that needs each file.
- **Gold item numbers:** the evolution items have fixed indices 850–901 in `data/gen12/items.lua`'s
  order (`Items.GEN2_FIRST_INDEX`).
  - Before, the engine numbered them from 251 in load order, which took battle_forms' fixed
    TM171 number (252).
  - Gold's save keeps the bag by id, so nothing saved changes.
- **Tests:**
  - `tests/gen12_dex_api_test.lua` makes the calls the way those mods do: every species' ability
    names find their record, every listed move answers with itself, replies are copies, patch.
  - g9-battle-engine itself, loaded headless beside WoobleDex from a copy that asks for
    `national_dex_gen3`, boots 148/148 subsystems on Red and 147/148 on Gold. The one failure
    is g9's own: it needs a Gen 1-only battle module.
  - battle_forms loads clean on Red. On Gold it fails at its own TM171 (fixed index 252),
    which its own Dynamax Band, numbered automatically, has already taken.

### Gen 3 extras on Gen 1/2 (Phase A: `options.lua`, `dex_sync.lua`, `modern_moves.lua`, Day & Night)

The owner asked for the Gen 3 extras on Gen 1/2 (2026-11-12). Phase A is the four small ones.

- **Options** (`src/gen12/options.lua`): this path declares Modern Moves, Register Owned and, on
  Gen 1 only, Day & Night, with the Gen 3 keys. A mod's option values are one bucket per mod
  (`options.lua` `modOptions.national_dex_gen3`), so a setting holds on every game it shows on.
- **Linking Cord** (`data/gen12/items.lua` kind `cord`, `items.lua`, `evolutions.lua`):
  - Red: the Bag effect returns `evolveTo` for the first `TRADE` row whose conditions hold. Red's
    trade-item steps are `ITEM` rows (the item is used), so the cord never stands in for them.
  - Gold: an `item_effects` record with `action = "stone"` whose use runs
    `Evolution.checkMon(data, mon, { link = true })`. Gold's own TRADE check then asks for the
    held item, and Gold's `Evolution.apply` drops it (`heldItem = nil` for a TRADE row with an
    item).
- **Register Owned** (`src/gen12/dex_sync.lua`): a wrap of `PokedexMenu.new` (Red
  `src.ui.PokedexMenu`, Gold `src.ui.gen2.PokedexMenu`), installed once per run on the module
  (`__ndxGen12Sync`), asking the current load's handler. It marks party, `save.box` (Red) and
  every `save.boxes` list; eggs (`isEgg`) are skipped; forms mark their base (`Dex.sync`).
- **Modern Moves** (`src/gen12/modern_moves.lua`, `data/gen12/modern.lua`):
  - The cart species' newest lists (#1-251) are added to `used` in the builder, so their moves
    get rows too.
  - At runtime only moves the game has outright (`direct`) are added, at their level; each move
    appears once and the cart's own rows come first at a level. A move the cart already teaches
    is learned at the earlier of its own level and today's (Squirtle's Water Gun: Red 8 / Gold
    15 -> 3); a Red `level1Moves` move is left alone. Same rule as Gen 3.
  - Records are frozen, so `apply(data, on)` swaps the live `learnset`/`levelMoves` (and Gold's
    `eggMoves`) on `game.ready` and `mod.options_changed`, keeping the originals.
  - It applies to the game `game.ready` handed over: in a headless run `mod.game` on Gen 1 is
    the engine's `Game` singleton with another dataset.
- **Day & Night** (`src/day_night.lua`, shared with Gen 3):
  - The renderer wraps are installed once per run (`Renderer.__ndxDayNightHub`) and ask the copy
    that installed last (`hub.impl`).
  - A copy grades only its `opts.generations` (Gen 3 by default, `{ [1] = true }` here) and
    decides outdoors with `opts.outdoor(ev)`: Red's map `tileset` OVERWORLD, PLATEAU or FOREST.
  - The phase is the device's (`Clock.phase(nil, "device")`). `POKEPORT_RTC` does not reach
    Red's sandbox, so it is the real time.
  - `mod.exports._dayNight` is for the probe.
- **Tests:** `tests/gen12_extras_test.lua` (all four through each game's own code) and
  `tests/day_night_test.lua` (the hub: a second copy for Red takes over, grades Red, never
  Emerald or Gold, with one end-of-frame wrap).
- **In game** (2026-11-12, probe 0 failures on Red and Gold): Route 1 in the evening is tinted
  and Red's house is not. Gold loads no Day & Night. A saved `day_night = false` turns it off on
  Red too (the shared bucket), so the probe's options switch it on for the run.

### Gen 3 extras on Gen 1/2 (Phase B: `tms.lua`, `exp_candies.lua`, `type_badges.lua`, `big_pc.lua`, `shops.lua`)

- **New TMs** (`src/gen12/tms.lua`): `data/tms.lua` (the Gen 3 list) filtered to moves that run
  natively here (`row[gen1|gen2]`, resolved through `directMove`): 43 on both games, same ids and
  numbers (TM51+). Both engines teach from data alone: Red's item `machine = { kind, move,
  number }` (`ItemEffects.use` -> `"learn"`, BagMenu's TM flow, PartyMenu's ABLE column), Gold's
  `teaches` in the `TM_HM` pocket (`PackMenu:openTeachParty`, `PartyMenu:tmhmAble`); both read
  the species' `tmhm`, which gets `{ __append = moves }` patches (cart species via `cartIdOf`,
  ours and forms via the species state). Gold's `tmNumber` only sorts the pocket and is
  `50 + number / 1000`, because `Gen2Save`'s `tmNumbers` maps whole numbers 1-57 (TM57 would
  become HM07 on import/export). Two process-wide wraps act on our ids only: `Bag.capacity`
  (`TM_HM` + each of our TMs in `data.items`) and Red's `GenSave.crosswalks` (drops our ids: a
  machine with no index exports as 200 + number, which passes 255 from TM55). Shops:
  `src/gen12/shops.lua` (Red: deep `text_pointers` patch of Celadon 2F clerk 2; Gold: every
  `marts` list that STARTS with the store's stock, so Goldenrod 5F's four lists and a list another
  addition already grew).
- **Exp. Candies** (`src/gen12/exp_candies.lua`, ids and Gold indices 950-954 as on Gen 3):
  Red: one `item_effects` record the five items name; `use` adds the Exp. (`Growth.levelForExp`,
  `Stats.calc`, HP by the max's rise, Pikachu's happiness, our friendship via
  `evoState.leveledUp`) and returns `"consumed", text, { leveledTo }`, which BagMenu turns into the
  Rare Candy's text, StatBox, moves and evolution. `Experience.movesLearnedAt` is wrapped
  (process-wide, one-shot `pending = { def, from, to }`) so every level gained is offered;
  `keepsPartyMenuOpen` / `usesMedicineMenu` / `notTimeInBattle` answer true for our ids. Gold: a
  record per item with `action = "candy"` over `Mon.gainExperience` (stats, `pokemon.level_up`
  per level, every move in `(from, to]`); `Game2:afterRareCandy` does the moves and
  `Evolution.checkMon`. Sold with the vitamins (Celadon 5F clerk 2 / Goldenrod 4F).
- **Type badges** (`src/gen12/type_badges.lua`): `src/type_badges.lua`'s `COLORS` / `GLYPHS`
  (loaded as it is), 10 x 10 (rim + 8 x 8 glyph), Gen 3 badge ids by type name (`_TYPE` stripped,
  `BIRD` = Flying, `CURSE` = ???). Placed as on Gen 3 (owner, 2026-11-13): beside each box, level
  with its name and HP lines. The foe's at x 89, y 2: its name and HP bar end at x 87 and its
  picture starts at x 96. Yours at x 69, y 57: your name and HP bar start at x 80 and the back
  picture ends at x 64. The same on Red and Gold. A second type sits 11 rows under the first.
  Gen 3's diagonal step would cover the Pokemon in these 8 px gutters.
  Red, classic layout: drawn WITH the boxes, never from `battle.overlay`. gen3-hd-sprites' Battle
  Fit draws the field (pictures, animations, the overlay hook) zoomed to the window and the boxes
  plus text box on a canvas of its own at another scale. Badges drawn from the overlay drifted
  off the boxes (seen in Red 2026-11-13). So `BattleState.drawHUDs` and `drawZonePass` are wrapped
  once per process (`BattleState.__ndxBadges` hub, the last install's state). On the flat path the
  badges are drawn right after drawHUDs. On the coloured path drawHUDs only marks the battle, and
  the next `drawZonePass` (the one that composites the boxes' gray canvas) draws them after itself,
  so the shade shader never recolours them and they follow the window shake. A drawHUDs shadowed
  on the instance (Battle Fit's field pass) never reaches the wrap, so that frame's field gets
  none. The enemy row follows `fx.hudShakeX`. The tests are the same as drawHUDs'. The wide layout
  (WideBattle's local panels, no seam) stays on `mod.hooks:wrap("battle.overlay")` with
  `Badges.WIDE1` (panels at (0,0) and (184,56)). Gold: `BattleState.drawEnemyHud` / `drawPlayerHud` wrapped once per process
  (`GS.__ndxBadges` hub, the last install's state; badges only in the battle of the game whose
  data that install got at game.ready), gated by `showEnemyHud` / `showPlayerHud`,
  `statusHUDVisible`, `hudCleared`; types from `battle:battlerTypes(activeMon)`.
- **Bigger PC** (`src/gen12/big_pc.lua`): `Boxes.COUNT` (Red) / `Boxes.NUM_BOXES` (Gold) = 40.
  The save writers (Red `SaveData.save`, which Gen 3 shares, so only for a save of this
  generation; Gold `Save.save`) are wrapped once per process: for the write only,
  `BigPc.split` moves boxes (and Gold names) past 12 / 14 into
  `save.modData.national_dex_gen3.pc = { boxes, names, currentBox }` and sets the current box to
  1, then `unsplit` restores the live save exactly. `save.writing` was not enough: it hands over
  the live save and some writes skip it. `save.loading` (raw) merges them back; the option moves
  them live. Red only: `Boxes.ensure` is wrapped to fill boxes 13-40 of an older save, and
  `BoxMenu.new` to hand the CHANGE BOX row to our scrolling copy of the cart's list (`Menu`
  `maxVisible = 12`, wraps; our own CPU-drawn ball, since modkit lint bans the cart's tile).
  Gold's list already scrolls.
- **Tests:** `tests/gen12_extras_test.lua` (218 checks over Red, Yellow, Gold, Crystal: the save
  writers are stubbed before the mod loads, so nothing is written).
- **In game** (2026-11-12, probe 0 failures on Red and Gold): an Exp. Candy L took Lucario from
  30 to 33 through Red's Bag and Gold's party-item flow; TM74's party screen shows ABLE / NOT
  ABLE; Gold's TM pocket reads 01, 74, 98, H1; both box lists reach BOX40; a Pokemon in box 30
  saves into the mod's data with a 12 / 14-box file and stays in the live save. The driver
  can't open Gold's pack submenu with A (it never reacts), so it starts the candy at
  `Game2:usePartyItem` and the TM at `PackMenu:openTeachParty`, the calls the pack makes.

### Gen 3 extras on Gen 1/2 (Phase C: `move_fx.lua`, `dex_forms.lua`, `vending.lua`)

- **Move mechanics** (`src/gen12/move_fx.lua`, since folded into the mechanics layer below; this is
  the history): every `data/gen12/moves.lua` row that has no
  native effect here but a Gen 3 `extra` (data/moves.lua) becomes a real move, registered right
  after `Moves.register` and before the species (it fills `moveState.byNumber`, so the resolver
  and learnsets name it): 88 on both games. Red: one `move_effects` record per move
  (`NDX_FX_<id>`): status kind = `"primary"` (`accuracyChecked` when it aims at the foe; returns
  the messages, `failed`, `hpBarFirst`), hit kind = `"full"` with `afterDamage` (user stats,
  drain via `drainNext` + `_SuckedHealthText`, recoil via `applyRecoil`) and `run` (foe stats,
  `ctx.inflict` with `secondary`, flinch; skipped behind a Substitute). Red's single SPECIAL
  takes Sp. Atk's change, else Sp. Def's (`MoveFx.changes`). Gold: an attack is
  `EFFECT_NORMAL_HIT` and `Battle.useMove` is wrapped once per process (`Battle.__ndxMoveFx`,
  specs by move id): after the hit's own events, if the foe's HP or Substitute went down, the
  extra runs with `changeStage` / `changeStageAgainstMist`, `applyStatus(..., {secondary})`,
  `flinch`, `heal` and the cart's "energy was drained" / "is hit with recoil" texts. A status
  move gets a `move_effects` record (`run(self, a, d, def, id, sureHit)`, its own accuracy roll
  when aimed); self-only ones join `Effects.NO_CHECKHIT` (Protect lets them through, as Gold's
  stat-ups). Chances roll 0-255 on the battle's RNG. Animation: the first stand-in that is a cart
  move. Hex and Mystical Fire (Gen 3 rules) stay stand-ins.
- **Animations**: the newer moves play the cart animation they borrow (`look`). (Until 2026-11-19
  18 of them drew pixelfx effects over a timing-only animation from the `battle.overlay` hook; the
  pixelfx effects were removed with the Gen 9 Move Animation Project's arrival on Gen 3.)
- **FORMS page** (`src/gen12/dex_forms.lua`): Red wraps `DexEntryMenu.update`: on the last page
  with the cry done, A pushes our page (one form at a time: picture via `Sprites.path`, the form's
  words via `src/dex_forms.lua`'s `label`, types, "FORM n/m"; `sgbPalettes` colours the picture),
  only when the state under the entry is the Pokédex list (`getmetatable == PokedexMenu`), never
  after a catch. Gold wraps `PokedexMenu.update` (PAGE on page 2 -> page 3; Up / Down step) and
  `drawEntryBody` (page 1 drawn, then the form's picture in its own or its base's colours, height /
  weight and text blanked, the form, types and count written); not in `newEntry` mode.
- **Vending** (`src/gen12/vending.lua`): `data/vending.lua`'s machines and `src/vending_screen.lua`
  as they are, with Gen 1/2 places (`Vending.PLACES`: Red CELADON_MART_4F / _2F (19,2), Gold
  GOLDENROD_DEPT_STORE_4F (10,1) / _5F (4,1)). api 2's `mod.world` is the generation's own
  WorldAPI; a spawned object stays in its map for the run, so `input.step` asks
  `mod.world:npc(map, name)` before `spawnNpc` (and retries while the map loads). Talk: Red's
  `world.talk` hook, Gold's `world.interacted` event (no talk hook there). The screen's deps: a
  session proxy (Red `save.money`, Gold `save.player.money`), `Bag.add` (a refusal tried on a copy
  first), badges (Red `Badges.count`, Gold Johto + Kanto), each game's sounds, item icons from
  `assets/items/icons.png` by the slug's Gen 3 index. A state of ours on `game.stack` takes the
  buttons; `render.hud` draws the screen; `input.pointer` / `input.wheel` while open; the touch
  pad's `active` off. With the machines on, `Items.stock` and the TM Mart stock are skipped.
- **Tests:** `tests/gen12_mechanics_test.lua`, `gen12_forms_page_test.lua`, `gen12_fx_test.lua`,
  `gen12_vending_test.lua`.
- **In game** (2026-11-12, probe 0 failures on Red and Gold): Night Slash plays its slash (57
  frames on Red, 76 on Gold), Close Combat lowers the user's defences by one each, Alcremie's
  FORMS page shows 8 creams, the machines stand in the stores, open, and lock gated items with no
  badges. Gold shows the new species grey during ANY move animation (it colours pictures from
  `gen2Palettes` there, and they have none): a separate fix, noted in the README.

### Gen 2-9 parity (`src/gen12/mech/`, `src/gen12/battle/`, the systems; branch gen12-modern)

The goal: Red gets everything from Gens 2-9 and Gold everything from Gens 3-9, with today's
rules, as Gen 3 has. Every newer move is real on both games except the ten doubles-only moves
(Follow Me, Helping Hand, Rage Powder, After You, Ally Switch, Quash, Aromatic Mist, Spotlight,
Instruct, Decorate), which keep stand-ins. Neither the engine nor any Gen 3 file was edited.

- **One mechanics layer, two adapters.** `src/gen12/mech/core.lua` describes a move as a spec
  (`kind = "hit"`: `fail`, `sureHit`, `power`, `fixed`, `crit`, `highCrit`, `hits`, `stats`,
  `type`, `mult`, `cap`, `after`, `secondary`, `onMiss`, `charge`, `ignoresProtect`;
  `kind = "status"`: `aimed`, `selfOnly`, `run`) and finds one per row with `specFor`: by move,
  then `mech.rule`, `extra`, `g3`, `api`. It also keeps a hook bus (`core:on` / `fire` / `ask` /
  `fold`: damageMult, damageCap, speed, priority, trickRoom, accuracy, immune, moveType,
  blockStatus, blocks, beforeMove, endTurn, afterMove, switchedIn, fainted, gender, nature,
  ability, noHeal ...) that the families and abilities share. `src/gen12/battle/red.lua` and
  `gold.lua` give every spec the same adapter (who / where: `foe`, `side`, `field`, `vol`; facts:
  `hp`, `stat`, `stage`, `types`, `status`, `item`, `dvs`, `chosen`, `category`; actions:
  `damage`, `heal`, `stages`, `ailment`, `callMove`, `switchOut`, `setWeather`, `say`, `rng`).
  State is on the battle's tables (`battler.__ndx` / `volatile(mon).__ndx`,
  `battle.__ndxSides[side]`, `battle.__ndxField`), never the party mon.
- **Families** (`Core.FAMILIES`, loaded in order, each `function(core, opts)`): `track`
  (turn facts the moves read: hits taken for Rage Fist, faints, last moves, the chosen moves),
  `meta` (PokeAPI meta: stat moves, ailments, flinch, drain, recoil, multi-hit), `power`
  (variable power, stat swaps, crits, fixed damage, conditional failure), `field` (weather, the
  Protect family, hazards, screens, terrains, rooms, Tailwind), `volatile` (Taunt to Perish Song,
  type changes, two-turn moves, callers), `switching` (U-turn and kin, Dragon Tail, trapping),
  `traits` (natures, gender), `held` (Red's held items in battle, the item moves on both),
  `abilities`, `split`.
- **Registration** (`mech/install.lua`): each row with no cart effect gets a `move_effects`
  record `NDX_M_<id>` the adapter builds, before the species (the learnsets name them).
  `mod.exports._mech` exposes the core, the adapter and the moves still missing a mechanic
  (none).
- **Seams** (process-wide hubs, `__ndxMech`): the `battle.damage` / `crit` / `accuracy` /
  `turn_order` / `charge_required` hooks; Red `performMove`, an `effectRecord` proxy whose
  `perform` stops a protected move, `statusInterrupt`, `resolveSwitch`; Gold `movePriority`,
  `battlerTypes`, `betweenTurnEffects`, `useMove`, `applyStatus` / `applyConfusion`,
  `switchLocked`.
- **Swapped abilities** (`mech/abilities.lua` `SWAP`, `core.ABILITY_SWAP`): the partner abilities
  and the ones with nothing to act on (Battery, Power Spot, Friend Guard, Hospitality, Healer,
  Plus, Minus, Commander, Receiver, Telepathy, Ball Fetch...) are answered as a working one by
  `rawAbility` and `abilityForMon`, so the battle and the summary agree. The test checks every
  ability works or has a working stand-in.
- **The other abilities** (`mech/abilities_more.lua`, after `abilities.lua`): every ability without
  a `b` block, written out on the hooks (the file's header lists them). `abilities.lua` `abilityOf`
  answers Neutralizing Gas (`A:field().gasOn` + a scan) and a Mold Breaker's target
  (`A:field().moldBreaking`, set in beforeMove for that move); `core.rawAbility` ignores both.
  beforeMove snapshots both sides (stages, status, HP) and afterMove compares (`core.reactToDrops`
  is also called by Intimidate). New hooks the adapters ask: `weight`, `noWeather`, `chanceScale`
  (Serene Grace; `A:field().mover`), `noFlinch`, `noRecoil` (Red's `applyRecoil` wrapped; Gold's
  recoil moves run as a plain hit via a swapped move record), `drainReversed`, `ignoreStages`
  (Unaware, in both damage wraps), `infiltrates`, `bypassProtect`, `noForceSwitch`, `itemLocked`,
  `itemSuppressed`, `gluttony`, `ripen`, `ateBerry`, `noIndirect`, `skillLink`, `loadedDice`.
  Forms that change stats in battle (Stance Change, Zero to Hero, Schooling, Zen Mode) use
  `A:vol(b).statOver` from hand-written form base stats. The test checks every ability has a
  `b` block, is named in the code, or is on the names-only list.
- **Natures and abilities** come from the DVs (`traits.natureIndex`, the ability slot), so
  nothing is saved; natures apply in Red `Stats.calc` and Gold `Mon.stats` (Red's SPECIAL is the
  Sp. Atk and takes Sp. Atk's factor). Abilities run `data/gen12/abilities.lua`'s `b` behaviour
  (`tools/ability_behaviour.py`), plus hand code for the rest.
- **Red systems:** `src/gen12/held_red.lua` (`data/gen12/held.lua`, hand-written and kept by the
  build: Gold's held set as Red items, `mon.extra.national_dex_gen3.item`, the party ITEM submenu,
  Everstone through `evolution.check`, Smoke Ball through `battle.run`, sold at Celadon 4F);
  `src/gen12/breeding_red.lua` (the Day Care Lady at DAYCARE, `save.modData.national_dex_gen3
  .breeding`, eggs carried and hatched on `world.stepped`, babies from `battle.lua` `baby`);
  gender by Gold's rule; Destiny Knot passes three of the four DVs to an Egg.
- **Red's Sp. Def** (`mech/traits.lua` `Traits.spDef`, `core.spDefOf`): base Sp. Def from
  `battle.lua` `spDef` / `formSpDef` by dex / form id, the Special DV and stat experience in
  Gen 1's formula, Sp. Def's nature factor; never saved. Its stage is `A:vol(b).spDefStage`
  (`RedA:stage/setStage/stages`, `RedA:spDefStage` texts; Haze clears it on `moveUsed`). Red's
  battle.damage wrap swaps the target's `curStats.special` / `stages.special` for a special move
  (before `statOver` and `ndxStats`, which may override it). The summary relabels SPECIAL as
  SP.ATK (`hub.relabel`) and prints SP.DEF on the third page.
- **Modern Rules** (`src/gen12/modern_rules.lua`, option `modern_rules`, Red only, default on): a
  hidden `rulesets` record `national_dex_gen3_modern` (modern_clean's switches plus stages kept on
  a crit, badge boosts once, end-of-round residuals) put on the battle at `battle.started`; a
  battle.damage wrap rolls today's crits (1/24, 1/8, 1/2, always by stage: highCrit +1, Focus
  Energy +2; core noCrit / forceCrit first), runs the formula with `forceCrit = false`
  (`screens = false` on a crit) and scales by 1.5. An always-crit move (`forceCrit = true`) takes
  the same path.
- **Shiny on Red** (`src/gen12/shiny_red.lua`): the engine's `Stats.isShiny` (Gold's rule);
  battle.overlay sparkle while `drawPicsLayer`'s pictures show (classic layout only, `seen` per
  battler table), the summary star in `hub.relabel`. The engine already passes `shiny` to
  pokemon.sprite.
- **Gold's colours for newer species** (`src/gen12/art.lua` `installPalettes`): a process-wide
  wrap of `src.world.gen2.Palettes.monColors` (`__ndxColors`) answers a species of ours with no
  pair from its picture (the pokemon.sprite chain's answer, `love.image.newImageData`): opaque
  pixels between near-white and near-black sorted by luminance, the lighter half's and the darker
  half's averages. Once per species and shininess.
- **Summary** (`src/gen12/summary.lua`): Red's third page (`SummaryMenu.update` / `draw`,
  `__ndxInfo`), Red's HUD gender sign (`BattleState.drawHUDs`, `__ndxGender`); Gold's page 3 via
  `drawPanel`.
- **Move Split** (`mech/split.lua`, option `move_split`, default off): `battle.lua` `split` by
  move id; Red's damage reads the move's `category`, Gold picks by type, so the stats are
  swapped for the call.
- **TMs:** all 114 (`tms.lua` keeps every `direct(row.n)`).
- **Type chart:** `tools/build_gen12.py` `chart_changes` compares every cart row with today's
  chart (`modern_rows` over all 18 types): Red's Ghost > Psychic, Bug > Poison, Poison > Bug, and
  Gold's Steel resisting Ghost and Dark.
- **Gold's texts:** `tools/gold_text.json` (moves, items) is read by `build_gen12.py` and
  `build_held.py` before any official text; every line at most 18 characters.
- **Tests:** `tests/gen12_mech_test.lua` (a battle sim per family on red / yellow / gold /
  crystal, `H.sim` in `tests/_gen12.lua`), plus the existing gen12 suites. In game:
  `tests/drivers/gen12_modern_probe.lua` (summary pages, five turns of new moves, the Day Care
  Lady) ran with 0 failures on Red and Gold 2026-11-13.

### Held items on every game (`src/held/`, `data/held_items.lua`)

- **Data:** `tools/build_held.py` -> `data/held_items.lua` (176 rows: slug, id, `index` 1300+
  append-only, name of at most 12, price, Gen 3 Bag text `desc`, Gold's `desc2`, `effect` written
  by hand in the tool's HELD table, `icon` cell) and `assets/items/held_icons.png` (pokesprite, or
  the Gen 9 Pack's Graphics/Items for the newest; 16 cells a row). Also `data/move_flags.lua`
  (contact, punch, sound, powder ... from `data/gen12/api/moves.lua`).
- **Registration:** a game registers the rows it has no item for (by id or normalized name), so
  Emerald keeps its own Choice Band and Gold its Exp. Share. Gen 1/2: `src/held/gen12.lua` (Gold:
  ITEM pocket, HELD_NONE, `desc2`, the row's index). Gen 3: `src/held/gen3.lua` `register` at load
  (ITEMS pocket, `desc`; Choice Scarf / Specs carry hold effect 29 for the cart's lock; Luck
  Incense 32, Pure Incense 33, the Power items 24 (the Macho Brace's): the cart's own effects).
  Razor Claw / Fang are the evolution items: Gen 1/2 adds the effect to them, Gen 3 patches them
  to Scope Lens's / King's Rock's hold effect.
- **Effects:** `src/held/effects.lua`, a mechanics family on the core hook bus, the same file on
  every game. Red and Gold load it with the families (`src/gen12/main.lua`). Gen 3:
  `src/held/gen3.lua` builds a core of its own (`src/gen12/mech/core.lua`) and an adapter over the
  Gen 3 battle adapter (`GA`: the adapter calls the family uses), and fires the hooks from
  battle.damage / battle.accuracy / battle.crit / battle.charge_required (`Held.hooks`, at load),
  and from process-wide wraps of `Hit.run`, `Effects.run`, `HeldItems.of`,
  `Engine.switchInEffects`, `Engine.canSwitch`, a Residuals field phase `ndx_held` and
  `RealAbilities.speedModifiers.heldModern` (a hub on `HeldItems.__ndxHeldHub`, so a reload's
  state is the one asked). Red gained an `afterMove` hook (its performMove wrap) and both adapters
  a `missed` hook; field.lua / abilities.lua fold `weatherTurns`, `screenTurns`,
  `terrainTurns` and ask `hazardImmune`, `weatherImmune`, `ignoresWeather`, `noContact`,
  `abilityLocked`; the adapters' drain folds `drainHeal`. Gen 3's Protosynthesis / Quark Drive
  read `b.__ndxBooster` (Booster Energy) through `boosterOn(ad, ab, b)` in `src/abilities.lua`.
- **Outside battle:** `src/held/outside.lua` (Red / Gold): exp.gain (Red's Lucky Egg, Macho Brace
  and Power items' stat experience), battle.exp_award (Red's Exp. Share), happiness.changed
  (Gold's Soothe Bell; Red's is in `Evolutions.addFriendship`), encounter.roll (Pure Incense).
- **Not modelled:** Binding Band; Grip Claw on Red; Booster Energy on Red / Gold; Amulet Coin and
  Luck Incense on Red; Mental Herb against the games' own Disable / Encore; Loaded Dice on the
  carts' own multi-strike moves; Power items as anything but the Macho Brace on Gen 3.
- **Selling:** the HELD EXPRESS machine (`data/vending.lua` `held`; `assets/shop/HELDvendor2.png`
  is EVOvendor2 recoloured): Celadon 4F (8,5) / Lilycove 2F (6,2), Red Celadon 4F (18,2), Gold
  Goldenrod 4F (11,1). Gen 1/2 vending resolves a held slug to this game's id (ours or the game's
  own of that name) and draws its icon from the held atlas; Gen 3 draws the Bag's icon, which
  `src/item_art.lua` now answers from the held atlas too.
- **Tests:** `tests/held_items_test.lua [game]` (Gen 3), the held checks in
  `tests/gen12_mech_test.lua`, `tests/gen12_vending_test.lua`.

### In the real engine (`tests/drivers/gen12_probe.lua`)

One driver for both games: a party of new species (long names, #1000), the party and summary
screens, our own and a borrowed cry, a wild battle against a new species (Night Slash, then a
catch, with the type badges up), the Pokédex list near #1025 and Gholdengo's entry (it waits for
the cry, which plays in real time while the driver runs faster), a stone and a level evolution
through each game's own screens, an Exp. Candy, a new TM's party screen, the PC's box list, and a
save and reload (Red: the hidden friendship survives; box 30 lands in the mod's save data).

```bash
# from the gen1recomp root; SHOT_DIR gets the shots and driver.log
SHOT_DIR=/tmp/ndx-red  POKEPORT_VERSION=red  POKEPORT_DRIVER=mods/national_dex_gen3/tests/drivers/gen12_probe.lua love .
SHOT_DIR=/tmp/ndx-gold POKEPORT_VERSION=gold POKEPORT_DRIVER=mods/national_dex_gen3/tests/drivers/gen12_probe.lua love .
```

- **Driver timing (gen1recomp 0.4.6+):** a driver's frames run far faster than 60 a second
  (about 300 measured), so anything on the clock (the vending screen's boot, cries, animations)
  needs a wait on its own state, not a frame count. `U.wait(240)` is under a second now.
- **Headless Gold / Crystal data (0.4.6+):** Gen 2's UI text, landmarks and swarms are required
  cache reads with no hand-typed fallback, and battle lines are ROM text by label. A built
  `game.data` needs the real `rom_text` (as `data.text`), `text`, `landmarks`, `encounters` and
  `events` (`tests/_gen12.lua` `GEN2_KEYS`). Battle text is the cart's own wording, capitals
  included ("PROTECTED itself!"): match it without regard to case.
- **Portable mode:** a checkout with `portable.txt` keeps its saves and `options.lua` in the
  checkout itself, and `POKEPORT_IDENTITY` does not move them. The probe starts a new game in the
  active slot and saves it, and the game rewrites `options.lua`, up to about 10 seconds after
  the driver's last line while it shuts down. Copy `options.lua` first, wait until no
  `love`/`lovec` process is left, then put it back and check its md5. The headless tests read
  `options.lua` too (their filesystem root is the checkout), so a probe's mod switches left in
  it make `tests/gen12_load_test.lua` fail.
- **Which mods load** comes from `options.lua`'s `modsByVersion[<version>]`, not the Mod
  Manager's `modProfiles`. For a clean run, set `red` and `gold` there to every mod off but
  this one. The original `national_dex` blocks this mod on these games (a manifest conflict).
- **Checked 2026-11-12 on Red and Gold: 0 failures.** Night Slash took Garchomp from 105 to 60
  HP. The entry pages show ft/in and pounds as the carts do: a Red record that carries
  `heightM` is drawn metric, so the projector only writes metres on a metric cart. Gold's
  summary prints `No.1000:L50` with no gap (the engine's layout), which the README notes.

Engine facts the design rests on (checked against the source, 2026-11-11):

- **Pictures:** `spriteFront`/`spriteBack` are required on Gen 1/2 records (`Schemas.lua`), and a
  missing file crashes the image load. New species point at our own placeholder pictures through
  `mod.path .. "/assets/..."`, as the engine's `example_mini_conversion` does.
- **New types in Gen 1 battle:** Gen 1 splits physical/special by type through
  `TypeChart.category`, which reads the merged `type_chart` records (`Damage.isSpecial`). A
  registered DARK/STEEL/FAIRY with a category works.
- **Extra fields on a Pokémon:** a Gen 1 save deep-copies the save tree whole (`SaveSerializer`),
  `scrubKnownMon` keeps unknown fields, and link trades carry `mon.extra` (`Protocol.lua`). So
  `mon.extra.national_dex_gen3` survives, which is where the Gen 1 friendship counter lives.
- **Evolution items, Gen 1:** a registered `item_effects` record's `use` runs before the cart's own
  item code (`ItemEffects.use`). Returning `"consumed", nil, { evolveTo = species }` makes the Bag
  play the evolution (`BagMenu`). The cart's stones are a fixed table (`STONES`), so new stones need
  this.
- **Evolution items, Gen 2:** `gen2ItemEffects[itemId]` with `action = "stone"` (top-level records
  keep unknown fields) and a `use` that calls `Evolution.checkMon(data, mon, { force = true, item })`.
  `Game2` then plays the evolution exactly as for a cart stone.
- **Gen 2 indices:** automatic species indices can hand out 255, the `.sav` list terminator, so the
  Gen 2 records set their own.
- **Gen 2 saves:** they have no orphan quarantine (`Gen2Compat.lua`), so removing the mod strands its
  species in a Gen 2 save. The README says to keep it installed.

## Regenerating the data

```bash
python -m pip install requests
python tools/build_species.py            # PokéAPI responses cached in tools/.cache
python tools/build_gen12.py              # data/gen12 (needs red, gold and firered imported, luajit)
python tools/build_api.py                # data/gen12/api (the read API's reference data)
python tools/build_move_split.py         # data/move_split.lua (Move Split's classes, from data/gen12/api)
python tools/build_art_heights.py        # data/art_heights.lua (from ../poke-scale-realism/data/scale.json)
python tools/build_placeholder.py        # assets/gen12 (the Gen 1/2 placeholder pictures)
```

`build_species.py` empties `data/species/` before it writes, which takes `modern.lua` with it
(`tools/build_modern_learnsets.py` writes that one): rerun that tool afterwards, or restore the file.
