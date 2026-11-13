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
| Abilities | Gen 3 abilities only: the cart's own are kept, and each newer ability is mapped to the closest Gen 3 one (`tools/ability_map.py`), e.g. Simple → Own Tempo, Moxie → Guts. The Gen 3 battle engine cannot take new abilities from a mod |
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
for National #1-386, the level-up rows and egg moves of the newest game that lists the species
(`build_species.VERSION_GROUPS`) whose move is a real newer move here. `src/modern_learnsets.lua`
replaces each cart list with a merged copy while `modern_moves` is on (weak-keyed `ours[list]`
remembers the cart's list, so turning it off restores it and a reload re-applies), on
`game.ready`, `mod.options_changed` and, in the save editor, `mods.loaded`. Egg moves only go to
species that already have a cart egg-move list. `ModernLearnsets.installRelearner` (always on)
wraps `MoveLearn.relearnableMoves`, whose local cap of 20 rows would hide the rest of a modern
learnset. Test: `tests/modern_learnsets_test.lua`; the editor half is in `editor_stock_test.lua`.

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

### pixelfx effects

For moves whose expansion script needs graphics no cart has, `tools/build_fx.mjs` renders effects
from [pixelfx](https://github.com/patch-gg/pixelfx) (MIT; cloned at a pinned commit into
`tools/.cache/pixelfx_src`) in grays, `tools/fx_atlas.py` packs every frame into one gray + alpha
atlas (`assets/fx/atlas.png`), and `data/fx.lua` gets the layout, the ramps and the scripts:

- `SHEETS`: the effect, the seconds kept, a speed-up, a scale (down for the ones made too big for
  the battle screen, up pixel for pixel), and the pin (the point placed on the battler). The
  effect's palette is rendered as an even gray ramp, its other colours as their brightness.
  Pixels fainter than alpha 72 (or a sheet's `cut`) and see-through dark ones are dropped (a soft
  glow over nothing is a grey box on a bright background); the packer trims each frame to what it
  draws, keeps 16 grays and alphas and shelf-packs them (`rects`: x, y, w, h, ox, oy a frame).
- `PAL`: the ramps (8 steps) a move colours with; each sheet also gets its effect's own palette as a
  ramp of its name, used when a row names none. One effect serves several moves (the orb is Aura
  Sphere's blue, Focus Blast's orange, Energy Ball's green).
- `MOVES`: each move's script, as rows for the animation VM: the cart's own sounds, lunge and
  shake, plus `NdxFx` rows, `{ "FX:" .. sheet, mode, dx, dy, frames, flags, "FX:" .. ramp }`
  (mode 0 attacker, 1 target, 2 travel, 3 beam; flags 1 feet, 2 aim, 4 behind).

`src/fx_anims.lua` registers the `NdxFx` visual task in `AnimTasks.REGISTRY` (once per process,
`AnimTasks.__ndxFx`) and `FxAnims.merge` adds `data/fx.lua`'s moves and labels to
`data/anims.lua`'s, so `src/anims.lua` resolves them like its own (`"FX:"` arguments pass through).
The task draws its frame through `task.draw` (no sprite slot) with a gradient-map shader (the
gray, bent by a gamma of 1.5 so the glow keeps its colour, looks up an 8 x 1 ramp picture; without
shaders, a tint), loads the atlas the first time a move plays, and ends after its frames, so a
missing picture costs nothing but the drawing. A move with
an expansion script of its own keeps that one.

Rebuild with `node tools/build_fx.mjs` (Node 18+, Python with Pillow; `--preview` writes contact
sheets to `tools/.cache/fx_preview`). Tests: `tests/anims_test.lua [game]` plays each from both
sides headlessly and checks the atlas (its size, every rect inside it, every ramp named); `tests/drivers/fx_anims_probe.lua` plays them in a
real battle (shots `FX_SHOTS`, `FX_SHOTS=0` measures garbage instead).

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
  within a pixel. (Mod code may not read the ROM-derived cache, so it is not measured at run time.)
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
- **What is published:** `apiVersion` 2, `isActive`, `provider`, `listSpecies`, `slotOf`,
  `listForms`, `formsOf`, `baseDexOf`, `idOfSlot`, `evolutionsOf`, `setArtProvider`, and
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
    appears once and the cart's own rows come first at a level.
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

### In the real engine (`tests/drivers/gen12_probe.lua`)

One driver for both games: a party of new species (long names, #1000), the party and summary
screens, our own and a borrowed cry, a wild battle against a new species (Night Slash, then a
catch), the Pokédex list near #1025 and Gholdengo's entry (it waits for the cry, which plays in
real time while the driver runs faster), a stone and a level evolution through each game's own
screens, and a save and reload (Red: the hidden friendship survives).

```bash
# from the gen1recomp root; SHOT_DIR gets the shots and driver.log
SHOT_DIR=/tmp/ndx-red  POKEPORT_VERSION=red  POKEPORT_DRIVER=mods/national_dex_gen3/tests/drivers/gen12_probe.lua love .
SHOT_DIR=/tmp/ndx-gold POKEPORT_VERSION=gold POKEPORT_DRIVER=mods/national_dex_gen3/tests/drivers/gen12_probe.lua love .
```

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
python tools/build_placeholder.py        # assets/gen12 (the Gen 1/2 placeholder pictures)
```

`build_species.py` empties `data/species/` before it writes, which takes `modern.lua` with it
(`tools/build_modern_learnsets.py` writes that one): rerun that tool afterwards, or restore the file.
