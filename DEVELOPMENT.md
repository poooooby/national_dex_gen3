# National Dex Gen 3: developer guide

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

**Shops** (`data/shops.lua`), by item type and how far into the game a store is:

| | FireRed / LeafGreen | Ruby / Sapphire / Emerald |
|---|---|---|
| Dusk, Dawn, Shiny and Ice Stone, Sachet, Whipped Dream | Celadon Dept. Store 4F | Lilycove Dept. Store, supplements floor |
| Protector, Electirizer, Magmarizer, Dubious Disc, Reaper Cloth | Celadon Dept. Store 5F | Lilycove Dept. Store, battle-item floor |
| Gen 8-9 items | Six Island Mart (after the Elite Four) | Apples at Mossdeep, Armors and Metal Alloy at Sootopolis, Black Augurite and Peat Block at the Ever Grande League mart |

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

## Art

Pictures (battle, summary and Pokédex) come from a sprite mod:

```lua
local dex = mod:find("national_dex_gen3")
if dex then
  dex.exports.setArtProvider(function(speciesId, side, slot)
    return mod.assets:path(side .. "/" .. speciesId .. ".png")  -- or nil
  end)
end
```

`side` is `"front"` or `"back"`. Return a PNG path (the engine centres and crops it to 64×64),
or nil to let the next provider answer.

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

## Regenerating the data

```bash
python -m pip install requests
python tools/build_species.py            # PokéAPI responses cached in tools/.cache
```
