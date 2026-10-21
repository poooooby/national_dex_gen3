#!/usr/bin/env python3
"""Generate data/moves.lua: real moves newer than Gen 3 that work like a Gen 3 move.

The Gen 3 battle engine runs every move through an effect id from the cart's own effect
table (EFFECT_HIT, EFFECT_BURN_HIT, ...); a mod can register a move row with any of those
effects (src/mods/Schemas.lua R.moves, index up to 1023) but cannot add a new effect. So a
newer move becomes a real move when its effect is one Gen 3 already has:

  effect    PokeAPI gives each move its effect description, shared word for word by every
            move with that effect. The cart's 354 moves pair each description with the cart's
            effect id (the most common one, where a description covers a special case too);
            a newer move whose description is one of those gets that effect. Every other
            newer move keeps its closest-Gen-3 substitute (tools/move_map.py).
  numbers   power, accuracy, PP, priority, secondary chance: PokeAPI (today's values)
  target    PokeAPI's target, as the cart pairs it with its own target ids
  flags     contact / Protect / Magic Coat / Snatch / Mirror Move from Pokemon Showdown's move
            data (they agree with the cart's own flags for 96-99% of its moves); King's Rock
            for a damaging move with no secondary effect, as the cart mostly does
  contest   category and appeal effect (Ruby/Sapphire/Emerald), PokeAPI paired with the
            cart's own contest data the same way
  name      the English name in capitals, at most 12 letters (Gen 3's limit; NAME_OVERRIDES
            shortens the longer ones)
  text      an English flavor text that fits each summary box: FireRed/LeafGreen 4 lines of
            19, Ruby/Sapphire/Emerald 2 lines of 28
  type      FAIRY moves are registered FAIRY (src/types.lua registers the type in the engine's type_chart)

Only moves the species of this mod learn (level-up or egg) are built. Indices start at 355
and are append-only (a move's index is saved in a Pokemon's moves): a move already in
data/moves.lua keeps its index.

    python tools/build_moves.py
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import urllib.request
from pathlib import Path
from typing import Any

import build_species as bs
import form_list
import move_map

ROOT = Path(__file__).resolve().parent.parent
FIRST_INDEX = 355
NAME_LIMIT = 12
FRLG_COLS, FRLG_ROWS = 19, 4
RSE_COLS, RSE_ROWS = 28, 2
SHOWDOWN = "https://play.pokemonshowdown.com/data/moves.json"

# names over 12 letters, shortened the way the Gen 3 games shorten theirs (DYNAMICPUNCH,
# SELFDESTRUCT): words run together or clipped
NAME_OVERRIDES: dict[str, str] = {
    "BABY-DOLL EYES": "BABYDOLLEYES",
    "DISARMING VOICE": "DISARM VOICE",
    "DAZZLING GLEAM": "DAZZLE GLEAM",
    "MYSTICAL FIRE": "MYSTICALFIRE",
    "HIGH HORSEPOWER": "HIGHHORSEPWR",
    "DUAL WINGBEAT": "DUALWINGBEAT",
    "PSYCHIC FANGS": "PSYCHICFANGS",
    "PRISMATIC LASER": "PRISM LASER",
    "PHOTON GEYSER": "PHOTONGEYSER",
    "DRAGON HAMMER": "DRAGONHAMMER",
    "FALSE SURRENDER": "FALSESURRNDR",
    "STEAM ERUPTION": "STEAM ERUPTN",
    "DOUBLE IRON BASH": "DBL IRONBASH",
    "STRANGE STEAM": "STRANGESTEAM",
    "METEOR ASSAULT": "METEOR ASSLT",
    "DRAGON ENERGY": "DRAGONENERGY",
    "FREEZING GLARE": "FREEZE GLARE",
    "GLACIAL LANCE": "GLACIALLANCE",
    "ASTRAL BARRAGE": "ASTRLBARRAGE",
    "NATURE'S MADNESS": "NATURMADNESS",
    "THOUSAND WAVES": "THOUSNDWAVES",
    "DRAINING KISS": "DRAININGKISS",
    "POWER-UP PUNCH": "POWERUPPUNCH",
    "BREAKING SWIPE": "BREAKNGSWIPE",
    "SKITTER SMACK": "SKITTERSMACK",
    "PARABOLIC CHARGE": "PARABOLICCHG",
    "EERIE IMPULSE": "EERIEIMPULSE",
    "DIAMOND STORM": "DIAMONDSTORM",
    "OBLIVION WING": "OBLIVIONWING",
    "HYPERSPACE FURY": "HYPRSPACFURY",
    "FLORAL HEALING": "FLORALHEALNG",
    "CLANGING SCALES": "CLANGNGSCALE",
    "SHELL SIDE ARM": "SHELLSIDEARM",
    "THUNDEROUS KICK": "THUNDERSKICK",
    "PETAL BLIZZARD": "PETALBLIZZRD",
    "FIRST IMPRESSION": "FIRSTIMPRESS",
    "HEADLONG RUSH": "HEADLONGRUSH",
    "MYSTICAL POWER": "MYSTICALPOWR",
    "FISHIOUS REND": "FISHIOUSREND",
    "BITTER MALICE": "BITTERMALICE",
    "MATCHA GOTCHA": "MATCHAGOTCHA",
    "LIGHT OF RUIN": "LIGHTOFRUIN",
    "DARKEST LARIAT": "DARKSTLARIAT",
    "SPARKLING ARIA": "SPARKLNGARIA",
    "PSYSHIELD BASH": "PSYSHIELDBSH",
    "MOUNTAIN GALE": "MOUNTAINGALE",
    "INFERNAL PARADE": "INFRNLPARADE",
    "KOWTOW CLEAVE": "KOWTOWCLEAVE",
    "COLLISION COURSE": "COLLISIONCRS",
    "ELECTRO DRIFT": "ELECTRODRIFT",
    "MIGHTY CLEAVE": "MIGHTYCLEAVE",
    "TACHYON CUTTER": "TACHYONCUTTR",
    "MALIGNANT CHAIN": "MALIGNNTCHAN",
    "VICTORY DANCE": "VICTORYDANCE",
    "AROMATIC MIST": "AROMATICMIST",
    "PHANTOM FORCE": "PHANTOMFORCE",
    "TRICK-OR-TREAT": "TRICKORTREAT",
    "MAGNETIC FLUX": "MAGNETICFLUX",
    "CRAFTY SHIELD": "CRAFTYSHIELD",
    "THOUSAND ARROWS": "THOUSNDARROW",
    "CORE ENFORCER": "COREENFORCER",
    "FOREST'S CURSE": "FORESTSCURSE",
    "FLOWER SHIELD": "FLOWERSHIELD",
    "REVIVAL BLESSING": "REVIVALBLESS",
    "KING'S SHIELD": "KINGS SHIELD",
    "HYPERSPACE HOLE": "HYPRSPACHOLE",
    "BANEFUL BUNKER": "BANEFLBUNKER",
    "SPIRIT SHACKLE": "SPIRTSHACKLE",
    "SPECTRAL THIEF": "SPECTRLTHIEF",
    "CLANGOROUS SOUL": "CLANGORSSOUL",
    "JUNGLE HEALING": "JUNGLHEALING",
    "CEASELESS EDGE": "CEASELESEDGE",
    "LUNAR BLESSING": "LUNARBLESSNG",
    "CHILLY RECEPTION": "CHILLYRECEPT",
    "BURNING BULWARK": "BURNNBULWARK",
    "MISTY TERRAIN": "MISTYTERRAIN",
    "GRASSY TERRAIN": "GRASSYTERRAN",
    "ELECTRIC TERRAIN": "ELECTRCTERRN",
    "PSYCHIC TERRAIN": "PSYCHCTERRAN",
    "STOMPING TANTRUM": "STOMPTANTRUM",
    "REVELATION DANCE": "REVELATNDNCE",
    "LAST RESPECTS": "LASTRESPECTS",
    "TERRAIN PULSE": "TERRAINPULSE",
    "WATER SHURIKEN": "WATRSHURIKEN",
    "SPRINGTIDE STORM": "SPRINGTSTORM",
    "BLEAKWIND STORM": "BLEAKWNSTORM",
    "WILDBOLT STORM": "WILDBLTSTORM",
    "SANDSEAR STORM": "SANDSRSTORM",
    "POPULATION BOMB": "POPULATNBOMB",
    "SUNSTEEL STRIKE": "SUNSTLSTRIKE",
    "MOONGEIST BEAM": "MOONGSTBEAM",
    "DYNAMAX CANNON": "DYNAMXCANNON",
    "EXPANDING FORCE": "EXPANDNFORCE",
    "RISING VOLTAGE": "RISINGVOLTGE",
    "SURGING STRIKES": "SURGNSTRIKES",
    "TRIPLE ARROWS": "TRIPLEARROWS",
    "GIGATON HAMMER": "GIGATNHAMMER",
    "TERA STARSTORM": "TERASTARSTRM",
    "SPICY EXTRACT": "SPICYEXTRACT",
}

# Summary text, in the Gen 3 manner, for moves whose official texts are too long for the
# boxes (Ruby/Sapphire/Emerald's is 2 lines). Used in both boxes. Our own words.
DESCRIPTIONS = {
    "DOUBLE_HIT": "Slams the foe with a tail or the like. Hits twice.",
    "WORK_UP": "The user is roused. Raises ATTACK and SP. ATK.",
    "SHELL_SMASH": "Drops defenses to sharply raise ATK, SP. ATK, SPEED.",
    "AROMATIC_MIST": "A mysterious mist that raises an ally's SP. DEF.",
    "DECORATE": "Sharply raises the target's ATTACK and SP. ATK.",
    "GEOMANCY": "Charges, then sharply raises SP. ATK, SP. DEF and SPEED.",
    "GEAR_UP": "Raises ATTACK and SP. ATK of allies with PLUS or MINUS.",
    "FILLET_AWAY": "Uses half its HP to sharply raise ATK, SP. ATK, SPEED.",
    "HEALING_WISH": "The user faints. The next Pokémon is fully healed.",
    "LUNAR_DANCE": "The user faints. The next Pokémon is fully restored.",
    "NIGHT_SLASH": "Slashes at a vital spot. High critical-hit ratio.",
    "DISCHARGE": "A flare of electricity hits all around. May paralyze.",
    "MOONBLAST": "Attacks with the moon's power. May lower SP. ATK.",
    "BABY_DOLL_EYES": "An innocent look that lowers the foe's ATTACK first.",
    "AIR_SLASH": "Attacks with a blade of air. It may cause flinching.",
    "DRAGON_PULSE": "Fires a shock wave from its gaping mouth.",
    "AQUA_JET": "Lunges at the foe at speed. It strikes first.",
    "SEED_BOMB": "Slams a barrage of hard seeds down on the foe.",
    "SWITCHEROO": "Swaps items with the foe faster than the eye can see.",
    "EARTH_POWER": "Makes the ground erupt. It may lower SP. DEF.",
    "FAIRY_WIND": "Stirs up a fairy wind and strikes the foe with it.",
    "AQUA_TAIL": "Swings its tail like a vicious wave in a storm.",
    "SHADOW_SNEAK": "Extends its shadow to attack. It strikes first.",
    "BULLDOZE": "Stomps down on the ground. Lowers the foe's SPEED.",
    "ZEN_HEADBUTT": "A focused headbutt. It may cause flinching.",
    "DISARMING_VOICE": "Lets out a charming cry that never misses.",
    "DAZZLING_GLEAM": "Damages the foes with a powerful flash.",
    "ENERGY_BALL": "Fires a ball of nature's power. May lower SP. DEF.",
    "BUG_BUZZ": "A damaging sound wave. It may lower SP. DEF.",
    "GIGA_IMPACT": "A powerful charge. The user must rest next turn.",
    "DRAGON_RUSH": "A menacing tackle that may cause flinching.",
    "POWER_GEM": "Attacks with a ray of light that sparkles like gems.",
    "PLAY_NICE": "Befriends the foe to lower its ATTACK. Never misses.",
    "BRAVE_BIRD": "A low dive that also hurts the user quite a lot.",
    "HURRICANE": "Wraps the foe in a fierce wind. It may confuse.",
    "LIQUIDATION": "Slams into the foe with water. May lower DEFENSE.",
    "X_SCISSOR": "Slashes the foe with crossed scythes or claws.",
    "ICE_SHARD": "Hurls chunks of ice at the foe. It strikes first.",
    "POWER_WHIP": "Lashes the foe violently with vines or tentacles.",
    "POISON_JAB": "Stabs with a toxic barb. It may poison the foe.",
    "WILD_CHARGE": "An electric charge that also hurts the user a bit.",
    "ICICLE_CRASH": "Drops large icicles on the foe. It may cause flinching.",
    "FLASH_CANNON": "Fires a burst of light energy. May lower SP. DEF.",
    "AVALANCHE": "Hits harder if the user was hurt this turn.",
    "PSYCHO_CUT": "Cuts with psychic blades. High critical-hit ratio.",
    "INFESTATION": "Swarms the foe for 2 to 5 turns. It can't flee.",
    "BRUTAL_SWING": "Swings its body around violently to strike.",
    "AURA_SPHERE": "Fires a blast of aura power. It never misses.",
    "SNARL": "Yells as if ranting. Lowers the foe's SP. ATK.",
    "NUZZLE": "Rubs its electric cheeks on the foe to paralyze it.",
    "RAGE_POWDER": "Scatters powder to draw the foe's attacks to itself.",
    "GUNK_SHOT": "Shoots filthy garbage at the foe. May poison.",
    "SHADOW_CLAW": "Slashes with a shadow claw. High critical-hit ratio.",
    "LAVA_PLUME": "A blast of fire hits all around. It may burn.",
    "INFERNO": "Engulfs the foe in an intense fire. It may burn.",
    "MYSTICAL_FIRE": "Breathes a special hot fire. Lowers the foe's SP. ATK.",
    "CROSS_POISON": "A slash that may poison. High critical-hit ratio.",
    "TAIL_SLAP": "Strikes the foe with its hard tail 2 to 5 times.",
    "HIGH_HORSEPOWER": "Fiercely attacks the foe using its entire body.",
    "SLUDGE_WAVE": "A giant wave of sludge hits all around. May poison.",
    "DRILL_RUN": "Spins its body like a drill. High critical-hit ratio.",
    "BRANCH_POKE": "Pokes the foe with a sharply pointed branch.",
    "VACUUM_WAVE": "Punches a vacuum wave at the foe. It strikes first.",
    "LEAF_TORNADO": "Engulfs the foe in sharp leaves. May lower accuracy.",
    "SOLAR_BLADE": "Absorbs light, then slashes with it on the next turn.",
    "BULLET_PUNCH": "A punch as fast as a bullet. It strikes first.",
    "ROCK_WRECKER": "Launches a huge boulder. The user must rest next turn.",
    "NIGHT_DAZE": "Looses a dark shock wave. It may lower accuracy.",
    "GEAR_GRIND": "Throws two steel gears to hit the foe twice.",
    "THOUSAND_WAVES": "Sends a wave through the ground. The foe can't flee.",
    "LANDS_WRATH": "Gathers the land's energy to strike the foes.",
    "PSYCHIC_FANGS": "Bites with psychic power. Breaks REFLECT and the like.",
    "PRISMATIC_LASER": "Fires a prism laser. The user must rest next turn.",
    "ROAR_OF_TIME": "A roar that warps time. The user must rest next turn.",
    "DRAGON_HAMMER": "Swings its body like a hammer to strike the foe.",
    "ZING_ZAP": "A strong electric blast. It may cause flinching.",
    "SPIRIT_BREAK": "Attacks with great force. Lowers the foe's SP. ATK.",
    "FALSE_SURRENDER": "Bows its head, then stabs the foe. It never misses.",
    "FOCUS_BLAST": "Unleashes all its mental power. May lower SP. DEF.",
    "ATTACK_ORDER": "Its underlings strike. High critical-hit ratio.",
    "DEFEND_ORDER": "Underlings shield it. Raises DEF and SP. DEF.",
    "DARK_VOID": "Drags the foe into a world of darkness to sleep.",
    "HEAD_CHARGE": "A charge with its hard head that also hurts the user.",
    "SEARING_SHOT": "Torches everything around in fire. It may burn.",
    "BOLT_STRIKE": "A huge electric charge. It may paralyze.",
    "BLUE_FLARE": "Engulfs the foe in a blue flame. It may burn.",
    "SHADOW_BONE": "Strikes with a haunted bone. May lower DEFENSE.",
    "DOUBLE_IRON_BASH": "Spins and hits twice with the nut on its chest.",
    "DRUM_BEATING": "Roots strike to the drum's beat. Lowers SPEED.",
    "SNAP_TRAP": "Snares the foe in a trap for 2 to 5 turns.",
    "PYRO_BALL": "Kicks a burning stone at the foe. It may burn.",
    "OVERDRIVE": "Strums a guitar or bass to hit the foes.",
    "THUNDER_CAGE": "Traps the foe in an electric cage for 2 to 5 turns.",
    "DRAGON_ENERGY": "Turns its life force into power. Stronger at full HP.",
    "FREEZING_GLARE": "Shoots psychic power from its eyes. It may freeze.",
    "FIERY_WRATH": "An aura of wrath hits the foes. May cause flinching.",
    "GLACIAL_LANCE": "Hurls a blizzard-cloaked lance of ice at the foes.",
    "ASTRAL_BARRAGE": "Sends out a frightful mass of small ghosts.",
    "NASTY_PLOT": "Thinks bad thoughts. Sharply raises SP. ATK.",
    "HONE_CLAWS": "Sharpens its claws. Raises ATTACK and accuracy.",
    "CLOSE_COMBAT": "Fights up close. Lowers its own DEF and SP. DEF.",
    "HEAL_PULSE": "Emits a healing pulse. Restores half the HP.",
    "NOBLE_ROAR": "A noble roar. Lowers the foe's ATTACK and SP. ATK.",
    "LIFE_DEW": "Scatters mystical water. Restores some HP.",
    "TEARFUL_LOOK": "Gets teary. Lowers the foe's ATTACK and SP. ATK.",
    "LUNGE": "Lunges at the foe with all its might. Lowers ATTACK.",
    "POWER_UP_PUNCH": "Each hard punch raises the user's ATTACK.",
    "AUTOTOMIZE": "Sheds part of its body. Sharply raises SPEED.",
    "LOW_SWEEP": "A swift low attack. Lowers the foe's SPEED.",
    "COTTON_GUARD": "Wraps itself in fluff. Drastically ups DEFENSE.",
    "BREAKING_SWIPE": "Swings its tough tail. Lowers the foes' ATTACK.",
    "SHIFT_GEAR": "Spins its gears. Raises ATTACK, sharply ups SPEED.",
    "ELECTROWEB": "Traps the foes in an electric net. Lowers SPEED.",
    "CONFIDE": "Tells the foe a secret. Lowers the foe's SP. ATK.",
    "CHATTER": "Chatters noisily at the foe. It confuses the foe.",
    "RELIC_SONG": "Sings an ancient song. It may put foes to sleep.",
    "GLACIATE": "Blows freezing air at the foes. Lowers SPEED.",
    "V_CREATE": "A fiery charge. Lowers its own DEF, SP. DEF, SPEED.",
    "DIAMOND_STORM": "A storm of diamonds. May sharply raise DEFENSE.",
    "HYPERSPACE_FURY": "Unleashes many arms in a flurry. Lowers its DEF.",
    "FLORAL_HEALING": "Restores half the foe's HP with flowers.",
    "TROP_KICK": "An intense tropical kick. Lowers the foe's ATTACK.",
    "CLANGING_SCALES": "Rubs its scales loudly. Lowers its own DEFENSE.",
    "AURA_WHEEL": "Fires its stored energy. Raises the user's SPEED.",
    "APPLE_ACID": "Attacks with acidic apple juice. Lowers SP. DEF.",
    "GRAV_APPLE": "Drops an apple from high up. Lowers DEFENSE.",
    "SHELL_SIDE_ARM": "Fires a shell at the foe. It may poison the foe.",
    "THUNDEROUS_KICK": "A lightning-fast kick. Lowers the foe's DEFENSE.",
    "ASSURANCE": "Hits twice as hard if the foe was hurt this turn.",
    "SUCKER_PUNCH": "Strikes first, but only if the foe is about to attack.",
    "ENTRAINMENT": "Makes the foe's ability the same as the user's.",
    "SOAK": "Shoots water to make the foe a WATER type.",
    "PHANTOM_FORCE": "Vanishes, then strikes. It goes through PROTECT.",
    "POWER_SPLIT": "Shares its ATTACK and SP. ATK with the foe.",
    "GUARD_SPLIT": "Shares its DEFENSE and SP. DEF with the foe.",
    "THROAT_CHOP": "Stops the foe from using sound moves for 2 turns.",
    "MAGNET_RISE": "Levitates for 5 turns to dodge GROUND moves.",
    "GRAVITY": "Pulls down flying POKeMON. Ups accuracy for 5 turns.",
    "STRENGTH_SAP": "Heals the user by the foe's ATTACK, then lowers it.",
    "WONDER_ROOM": "Swaps all DEFENSE and SP. DEF stats for 5 turns.",
    "VENOM_DRENCH": "Lowers a poisoned foe's ATTACK, SP. ATK and SPEED.",
    "AURORA_VEIL": "In hail, halves damage to the team for 5 turns.",
    "GUARD_SWAP": "Swaps DEFENSE and SP. DEF changes with the foe.",
    "SPIKY_SHIELD": "Protects the user. Hurts a foe that makes contact.",
    "MAGIC_ROOM": "Held items lose their effects for 5 turns.",
    "POWER_SWAP": "Swaps ATTACK and SP. ATK changes with the foe.",
    "SIMPLE_BEAM": "Changes the foe's ability to SIMPLE.",
    "MAGNETIC_FLUX": "Raises the DEFENSE and SP. DEF of PLUS and MINUS users.",
    "JAW_LOCK": "Bites down. Neither POKeMON can switch out.",
    "CRAFTY_SHIELD": "Protects the team from status moves this turn.",
    "WIDE_GUARD": "Protects the team from wide moves this turn.",
    "ACUPRESSURE": "Sharply raises one stat at random.",
    "QUICK_GUARD": "Protects the team from priority moves this turn.",
    "SMACK_DOWN": "Knocks a flying foe down to the ground.",
    "POWER_TRICK": "Switches the user's ATTACK and DEFENSE.",
    "REFLECT_TYPE": "The user becomes the same type as the foe.",
    "TOPSY_TURVY": "Reverses all of the foe's stat changes.",
    "ELECTRIFY": "Makes the foe's next move an ELECTRIC move.",
    "CORE_ENFORCER": "Removes the ability of a foe that already moved.",
    "STUFF_CHEEKS": "Eats its held Berry. Sharply raises DEFENSE.",
    "PSYCHO_SHIFT": "Passes the user's status problem to the foe.",
    "FLOWER_SHIELD": "Raises the DEFENSE of every GRASS type in battle.",
    "REVIVAL_BLESSING": "Revives a fainted ally with half its HP.",
    "SALT_CURE": "The foe loses HP every turn. Worse on WATER and STEEL.",
    "SHED_TAIL": "Makes a substitute, then switches out.",
    "FAIRY_LOCK": "Locks the field. No one can switch out next turn.",
    "KINGS_SHIELD": "Protects the user. Lowers a touching foe's ATTACK.",
    "HYPERSPACE_HOLE": "Strikes through PROTECT and DETECT.",
    "BANEFUL_BUNKER": "Protects the user. Poisons a foe that makes contact.",
    "SPIRIT_SHACKLE": "Shoots a stitching shot. The foe can't switch out.",
    "POLLEN_PUFF": "Explodes on a foe, but heals an ally instead.",
    "ANCHOR_SHOT": "Entangles the foe in a chain. It can't switch out.",
    "BEAK_BLAST": "Heats up its beak, then strikes the foe.",
    "SPECTRAL_THIEF": "Steals the foe's stat boosts, then attacks.",
    "NO_RETREAT": "Raises all stats, but the user can't switch out.",
    "TAR_SHOT": "Pours tar. Lowers SPEED and makes FIRE moves hurt more.",
    "MAGIC_POWDER": "A powder that makes the foe a PSYCHIC type.",
    "OCTOLOCK": "Traps the foe. Cuts DEFENSE and SP. DEF each turn.",
    "COURT_CHANGE": "Swaps the effects on each side of the field.",
    "CLANGOROUS_SOUL": "Spends a third of its HP to raise all its stats.",
    "OBSTRUCT": "Protects the user. Harshly cuts a toucher's DEFENSE.",
    "JUNGLE_HEALING": "Heals the user's HP and status problem.",
    "LUNAR_BLESSING": "Heals the user's HP and status problem.",
    "SILK_TRAP": "Protects the user. Lowers the SPEED of a touching foe.",
    "MORTAL_SPIN": "Attacks, poisons, and frees the user from traps.",
    "DOODLE": "Copies the foe's ability onto the user.",
    "CHILLY_RECEPTION": "Tells a bad joke, summons hail and switches out.",
    "BURNING_BULWARK": "Protects the user. Burns a foe that makes contact.",
    "TAKE_HEART": "Cures its status. Raises SP. ATK and SP. DEF.",
    "MISTY_TERRAIN": "Mist covers the field. It guards against status.",
    "TAILWIND": "A tailwind that doubles the team's SPEED for 4 turns.",
    "U_TURN": "Attacks, then switches places with a party POKeMON.",
    "ELECTRIC_TERRAIN": "Electrifies the field for 5 turns. No POKeMON can sleep.",
    "TOXIC_SPIKES": "Lays poisoned spikes that poison foes that switch in.",
    "METAL_BURST": "Strikes back with 1.5 times the damage taken this turn.",
    "PARTING_SHOT": "Lowers the foe's ATTACK and SP. ATK, then switches out.",
    "STICKY_WEB": "Lays a sticky web that slows foes that switch in.",
    "VOLT_SWITCH": "Attacks, then switches places with a party POKeMON.",
    "PSYCHIC_TERRAIN": "A psychic field. It blocks moves that strike first.",
    "TRICK_ROOM": "Twists space for 5 turns. Slower POKeMON move first.",
    "COMEUPPANCE": "Strikes back with 1.5 times the damage taken this turn.",
    "WATER_SHURIKEN": "Hits 2 to 5 times in a row. It strikes first.",
    "FLIP_TURN": "Attacks, then switches places with a party POKeMON.",
    "SPRINGTIDE_STORM": "A storm of love and hate. May lower the foe's ATTACK.",
    "BLEAKWIND_STORM": "A cold, brutal wind. It may lower the foe's SPEED.",
    "WILDBOLT_STORM": "A thunderous storm. It may paralyze the foe.",
    "SANDSEAR_STORM": "A storm of hot sand. It may burn the foe.",
    "AXE_KICK": "May confuse the foe. Hurts the user if it misses.",
    "POPULATION_BOMB": "The user's friends gather to hit up to 10 times.",
    "ICE_SPINNER": "Spins on ice to attack. Wipes away any terrain.",
    "SYRUP_BOMB": "Sticky syrup that lowers the foe's SPEED.",
    "FREEZE_SHOCK": "Charges, then strikes. It may paralyze the foe.",
    "ICE_BURN": "Charges, then strikes. It may burn the foe.",
    "SUNSTEEL_STRIKE": "Slams into the foe with the force of a meteor.",
    "MULTI_ATTACK": "Rapidly attacks with high energy.",
    "SNIPE_SHOT": "A precise shot. Can't be drawn to another target.",
    "SCALE_SHOT": "Hits 2 to 5 times. Raises SPEED but lowers DEFENSE.",
    "RISING_VOLTAGE": "Twice as hard on a foe on electrified ground.",
    "SURGING_STRIKES": "Three fierce blows. Always a critical hit.",
    "TRIPLE_DIVE": "Three perfectly timed dives that each do damage.",
    "DOUBLE_SHOCK": "All-out electricity. The user loses ELECTRIC type.",
    "GIGATON_HAMMER": "A huge hammer swing. Can't be used two turns in a row.",
    "ELECTRO_SHOT": "Gathers electricity to raise SP. ATK, then fires.",
    "TERA_STARSTORM": "Fires the energy of crystals at the foe.",
    "TIDY_UP": "Tidies up the field. Raises ATTACK and SPEED.",
    "SHELTER": "Hardens its skin. Sharply raises DEFENSE.",
    "SPICY_EXTRACT": "Sharply raises the foe's ATTACK and cuts DEFENSE.",
    "LAST_RESORT": "Works only after every other move it knows is used.",
    "PETAL_BLIZZARD": "Stirs up a violent storm of petals at all around.",
    "HEAD_SMASH": "A reckless headbutt. The user is badly hurt too.",
    "BRINE": "Hits twice as hard if the foe is under half HP.",
    "PSYSHOCK": "A psychic wave that hits the foe's DEFENSE.",
    "VENOSHOCK": "Soaks the foe in poison. Twice as hard if poisoned.",
    "FELL_STINGER": "If it knocks out the foe, ATTACK drastically rises.",
    "WAVE_CRASH": "Slams into the foe with water. The user is hurt too.",
    "BOOMBURST": "A destructive, explosive sound hits all around.",
    "FIRST_IMPRESSION": "A strong first strike. Works only on its first turn.",
    "AQUA_CUTTER": "Fires a blade of water. High critical-hit ratio.",
    "HEADLONG_RUSH": "A full-body charge. Lowers its own DEF and SP. DEF.",
    "RAGING_FURY": "Rampages with fire for 2 to 3 turns, then is confused.",
    "BARB_BARRAGE": "Toxic barbs. Twice as hard if the foe is poisoned.",
    "BITTER_MALICE": "Spine-chilling resentment. Lowers the foe's ATTACK.",
    "SPIN_OUT": "Spins furiously. Harshly lowers its own SPEED.",
    "LIGHT_OF_RUIN": "Fires a ruinous beam. The user is badly hurt too.",
    "MIND_BLOWN": "Blows up its own head. The user loses half its HP.",
    "WICKED_BLOW": "A blow from the dark style. Always a critical hit.",
    "PSYSHIELD_BASH": "Rams the foe with psychic power. Raises DEFENSE.",
    "CHLOROBLAST": "A huge blast of sunlight. The user loses half its HP.",
    "MOUNTAIN_GALE": "Hurls giant chunks of ice. It may cause flinching.",
    "LUMINA_CRASH": "A mind-bending light. Harshly lowers SP. DEF.",
    "JET_PUNCH": "A punch as fast as a jet of water. It strikes first.",
    "KOWTOW_CLEAVE": "Kowtows, then slashes the foe. It never misses.",
    "FLOWER_TRICK": "Throws a rigged bouquet. Always a critical hit.",
    "TORCH_SONG": "Sings a song of flames. Raises the user's SP. ATK.",
    "AQUA_STEP": "Dance-like water steps. Raises the user's SPEED.",
    "COLLISION_COURSE": "Transforms and crashes in. Stronger if super effective.",
    "ELECTRO_DRIFT": "Races in with electricity. Stronger if super effective.",
    "HYPER_DRILL": "Spins a sharp part of its body like a drill.",
    "TWIN_BEAM": "Fires mystical beams from its eyes. Hits twice.",
    "ARMOR_CANNON": "Fires its armor. Lowers its own DEF and SP. DEF.",
    "BITTER_BLADE": "Slashes with bitter fire. Heals half the damage.",
    "BLOOD_MOON": "Fires a beam from the blood-red full moon.",
    "THUNDERCLAP": "A fast jolt. Only works if the foe is about to attack.",
    "MIGHTY_CLEAVE": "Cleaves the foe with the light from its head.",
    "TACHYON_CUTTER": "Launches two particle blades. Hits twice.",
    "MALIGNANT_CHAIN": "Wraps the foe in a toxic chain. It may badly poison.",
}

# Moves whose effect Gen 3 lacks but whose PokeAPI `meta` describes it completely (stat changes,
# a status chance, flinch, drain/recoil, healing): src/move_effects.lua runs that description.
# A status move gets effect byte CUSTOM_EFFECT (unused by the cart, mapped to that handler);
# an attack is a plain hit (effect 0) and its extra runs after the hit.
CUSTOM_EFFECT = 250
GENERIC_CATEGORIES = {"net-good-stats", "damage-raise", "damage-lower", "damage-ailment", "heal", "damage-heal"}
# in those categories, but with a condition or mechanic the description leaves out
GENERIC_EXCLUDE = {
    "aromatic-mist", "decorate", "magnetic-flux", "gear-up",          # a partner only
    "captivate", "venom-drench", "rototiller", "stuff-cheeks",         # conditions
    "parting-shot", "throat-chop",                                     # switching, silencing
    "geomancy", "freeze-shock", "ice-burn",                            # a charging turn
    "clangorous-soul", "no-retreat",                                   # HP cost, trapping itself
}
STAT_KEY = {"attack": "attack", "defense": "defense", "special-attack": "spAtk",
            "special-defense": "spDef", "speed": "speed", "accuracy": "accuracy", "evasion": "evasion"}
AILMENT = {"burn": "BURN", "freeze": "FREEZE", "paralysis": "PARALYSIS", "poison": "POISON",
           "sleep": "SLEEP", "confusion": "CONFUSION"}
SELF_TARGETS = {"user", "user-and-allies", "users-field"}


def generic_extra(m: dict[str, Any]) -> dict[str, Any] | None:
    """The extra effect src/move_effects.lua runs, from PokeAPI's meta; None if it can't."""
    if m["name"] in GENERIC_EXCLUDE:
        return None
    meta = m.get("meta") or {}
    cat = (meta.get("category") or {}).get("name")
    if cat not in GENERIC_CATEGORIES:
        return None
    changes = {}
    for sc in m.get("stat_changes") or []:
        key = STAT_KEY.get(sc["stat"]["name"])
        if not key:
            return None
        changes[key] = sc["change"]
    ail = (meta.get("ailment") or {}).get("name", "none")
    if ail != "none" and ail not in AILMENT:
        return None
    extra: dict[str, Any] = {"kind": "hit" if (m["power"] or 0) > 0 else "status"}
    selfish = cat == "damage-raise" or m["target"]["name"] in SELF_TARGETS
    if changes:
        extra["self" if selfish else "foe"] = changes
        extra["chance"] = meta.get("stat_chance") or 100
    if ail != "none":
        extra["ailment"] = AILMENT[ail]
        extra["ailmentChance"] = meta.get("ailment_chance") or 100
    if meta.get("flinch_chance"):
        extra["flinch"] = meta["flinch_chance"]
    if meta.get("drain"):
        extra["drain"] = meta["drain"]
    if meta.get("healing"):
        extra["heal"] = meta["healing"]
        extra["healTarget"] = "self" if m["target"]["name"] in SELF_TARGETS else "foe"
    if m["name"] == "shore-up":
        extra["sandHeal"] = 67
    if len(extra) == 1:
        return None
    return extra


# Moves set by hand (src/move_rules.lua for `rule`): `like` runs on that cart move's effect,
# `rule` names a rule src/move_rules.lua carries out on top of a plain hit, `extra` is a
# description for src/move_effects.lua (as generic_extra makes). Today's power, accuracy, PP,
# priority, type and target still come from PokeAPI.
MANUAL: dict[str, dict[str, Any]] = {
    # an existing Gen 3 effect
    "boomburst": {"effect": 0}, "petal-blizzard": {"effect": 0}, "jet-punch": {"effect": 0},
    "hyper-drill": {"effect": 0}, "mighty-cleave": {"effect": 0}, "hydro-steam": {"effect": 0},
    "psyblade": {"effect": 0}, "order-up": {"effect": 0}, "blood-moon": {"effect": 0},
    "grass-knot": {"like": "LOW KICK", "power": 1}, "natures-madness": {"like": "SUPER FANG", "power": 1},
    "ruination": {"like": "SUPER FANG", "power": 1}, "snowscape": {"like": "HAIL"},
    "aqua-cutter": {"like": "SLASH"}, "ivy-cudgel": {"like": "SLASH"}, "wave-crash": {"like": "DOUBLE-EDGE"},
    "raging-bull": {"like": "BRICK BREAK"}, "kowtow-cleave": {"like": "SWIFT"}, "raging-fury": {"like": "OUTRAGE"},
    "twin-beam": {"like": "DOUBLE KICK"}, "tachyon-cutter": {"like": "DOUBLE KICK"},
    # power and stat rules
    **{k: {"rule": k.upper().replace("-", "_")} for k in (
        "assurance", "hex", "venoshock", "brine", "acrobatics", "payback", "retaliate", "stored-power",
        "power-trip", "punishment", "heavy-slam", "heat-crash", "gyro-ball", "electro-ball", "wring-out",
        "crush-grip", "wake-up-slap", "bolt-beak", "fishious-rend", "foul-play", "psyshock", "secret-sword",
        "body-press", "sacred-sword", "darkest-lariat", "chip-away", "echoed-voice", "trump-card",
        "frost-breath", "storm-throw", "wicked-blow", "flower-trick", "sucker-punch", "first-impression",
        "last-resort", "clear-smog", "fell-stinger", "final-gambit", "sparkling-aria",
        "chloroblast", "mind-blown", "electro-drift", "collision-course")},
    # power worked out in battle: 1 here, as the cart's own Flail and Low Kick
    **{k: {"rule": k.upper().replace("-", "_"), "power": 1} for k in (
        "punishment", "heavy-slam", "heat-crash", "gyro-ball", "electro-ball", "wring-out",
        "crush-grip", "trump-card", "final-gambit")},
    "thunderclap": {"rule": "SUCKER_PUNCH"},
    # the field, switching and the rest (src/move_field.lua, src/move_rules.lua)
    **{k: {"rule": k.upper().replace("-", "_")} for k in (
        "u-turn", "volt-switch", "flip-turn", "parting-shot", "dragon-tail", "circle-throw",
        "stealth-rock", "toxic-spikes", "sticky-web", "defog", "tailwind", "trick-room",
        "misty-terrain", "grassy-terrain", "electric-terrain", "psychic-terrain",
        "terrain-pulse", "rising-voltage", "expanding-force", "steel-roller", "ice-spinner", "aqua-ring",
        "stomping-tantrum", "rage-fist", "last-respects", "burn-up", "double-shock",
        "revelation-dance", "flying-press", "synchronoise", "fusion-flare", "fusion-bolt", "glaive-rush",
        "gigaton-hammer", "fickle-beam", "laser-focus", "dire-claw", "take-heart")},
    "metal-burst": {"rule": "METAL_BURST", "power": 1}, "comeuppance": {"rule": "METAL_BURST", "power": 1},
    # batch B: protection, ability / type changes, trapping, stats, the field, switching, items
    **{k: {"rule": k.upper().replace("-", "_")} for k in (
        "spiky-shield", "kings-shield", "baneful-bunker", "obstruct", "silk-trap", "burning-bulwark",
        "feint", "hyperspace-hole", "phantom-force", "shadow-force", "geomancy",
        "worry-seed", "entrainment", "simple-beam", "gastro-acid", "core-enforcer", "doodle",
        "soak", "magic-powder", "reflect-type", "trick-or-treat", "forests-curse", "tar-shot",
        "electrify", "ion-deluge", "plasma-fists",
        "jaw-lock", "thousand-waves", "spirit-shackle", "anchor-shot", "octolock", "salt-cure",
        "heal-block", "throat-chop", "eerie-spell", "psycho-shift", "magnet-rise", "miracle-eye",
        "power-split", "guard-split", "power-swap", "guard-swap", "heart-swap", "speed-swap",
        "power-trick", "topsy-turvy", "spectral-thief", "strength-sap", "venom-drench", "captivate",
        "acupressure", "clangorous-soul", "no-retreat", "fillet-away", "gear-up", "magnetic-flux",
        "rototiller", "flower-shield", "decorate", "aromatic-mist",
        "gravity", "smack-down", "thousand-arrows", "wonder-room", "magic-room", "fairy-lock",
        "aurora-veil", "lucky-chant", "court-change", "mortal-spin", "ceaseless-edge", "stone-axe",
        "wide-guard", "quick-guard", "crafty-shield",
        "healing-wish", "lunar-dance", "shed-tail", "chilly-reception", "revival-blessing", "purify",
        "jungle-healing", "lunar-blessing", "pollen-puff",
        "bug-bite", "pluck", "incinerate", "belch", "stuff-cheeks", "powder", "shell-trap")},
    "acupressure": {"rule": "ACUPRESSURE", "target": "user"},
    "fling": {"rule": "FLING", "power": 1}, "natural-gift": {"rule": "NATURAL_GIFT", "power": 1},
    "beak-blast": {"effect": 0},
    "jungle-healing": {"rule": "JUNGLE_HEALING", "target": "user"},
    "lunar-blessing": {"rule": "JUNGLE_HEALING", "target": "user"},
    "gear-up": {"rule": "GEAR_UP", "target": "user"}, "magnetic-flux": {"rule": "MAGNETIC_FLUX", "target": "user"},
    "rototiller": {"rule": "ROTOTILLER", "target": "user"}, "flower-shield": {"rule": "FLOWER_SHIELD", "target": "user"},
    "aromatic-mist": {"rule": "AROMATIC_MIST", "target": "ally"}, "decorate": {"rule": "DECORATE", "target": "ally"},
    "wide-guard": {"rule": "WIDE_GUARD", "target": "user"}, "quick-guard": {"rule": "QUICK_GUARD", "target": "user"},
    "crafty-shield": {"rule": "CRAFTY_SHIELD", "target": "user"},
    "court-change": {"rule": "COURT_CHANGE", "target": "user"}, "gravity": {"rule": "GRAVITY", "target": "user"},
    "wonder-room": {"rule": "WONDER_ROOM", "target": "user"}, "magic-room": {"rule": "MAGIC_ROOM", "target": "user"},
    "fairy-lock": {"rule": "FAIRY_LOCK", "target": "user"}, "ion-deluge": {"rule": "ION_DELUGE", "target": "user"},
    "lucky-chant": {"rule": "LUCKY_CHANT", "target": "user"}, "aurora-veil": {"rule": "AURORA_VEIL", "target": "user"},
    "revival-blessing": {"rule": "REVIVAL_BLESSING", "target": "user"},
    "surging-strikes": {"rule": "SURGING_STRIKES", "hits": 3},
    "water-shuriken": {"hits": True}, "triple-dive": {"hits": 3}, "dragon-darts": {"hits": 2},
    "population-bomb": {"hits": 10},
    "scale-shot": {"hits": True, "extra": {"kind": "hit", "self": {"speed": 1, "defense": -1}, "chance": 100}},
    **{k: {"effect": 0} for k in (
        "sunsteel-strike", "moongeist-beam", "dynamax-cannon", "tera-starstorm", "techno-blast",
        "judgment", "multi-attack", "snipe-shot", "round", "flame-burst")},
    "freeze-shock": {"like": "SKY ATTACK", "extra": {"kind": "hit", "ailment": "PARALYSIS", "ailmentChance": 30}},
    "ice-burn": {"like": "SKY ATTACK", "extra": {"kind": "hit", "ailment": "BURN", "ailmentChance": 30}},
    "electro-shot": {"like": "SKY ATTACK", "extra": {"kind": "hit", "self": {"spAtk": 1}, "chance": 100}},
    "axe-kick": {"like": "HI JUMP KICK", "extra": {"kind": "hit", "ailment": "CONFUSION", "ailmentChance": 30}},
    "esper-wing": {"like": "SLASH", "extra": {"kind": "hit", "self": {"speed": 1}, "chance": 100}},
    "triple-arrows": {"like": "SLASH", "extra": {"kind": "hit", "foe": {"defense": -1}, "chance": 50, "flinch": 30}},
    "shell-smash": {"extra": {"kind": "status", "self": {"attack": 2, "spAtk": 2, "speed": 2, "defense": -1, "spDef": -1}, "chance": 100}},
    "take-heart": {"rule": "TAKE_HEART", "target": "user",
                   "extra": {"kind": "status", "self": {"spAtk": 1, "spDef": 1}, "chance": 100}},
    "syrup-bomb": {"extra": {"kind": "hit", "foe": {"speed": -1}, "chance": 100}},
    "bleakwind-storm": {"extra": {"kind": "hit", "foe": {"speed": -1}, "chance": 30}},
    "springtide-storm": {"extra": {"kind": "hit", "foe": {"attack": -1}, "chance": 30}},
    "wildbolt-storm": {"extra": {"kind": "hit", "ailment": "PARALYSIS", "ailmentChance": 20}},
    "sandsear-storm": {"extra": {"kind": "hit", "ailment": "BURN", "ailmentChance": 20}},
    "infernal-parade": {"rule": "HEX", "extra": {"kind": "hit", "ailment": "BURN", "ailmentChance": 30}},
    "barb-barrage": {"rule": "VENOSHOCK", "extra": {"kind": "hit", "ailment": "POISON", "ailmentChance": 50}},
    # a description (src/move_effects.lua)
    "head-smash": {"extra": {"kind": "hit", "drain": -50}},
    "light-of-ruin": {"extra": {"kind": "hit", "drain": -50}},
    "bitter-blade": {"extra": {"kind": "hit", "drain": 50}},
    "matcha-gotcha": {"extra": {"kind": "hit", "drain": 50, "ailment": "BURN", "ailmentChance": 20}},
    "spin-out": {"extra": {"kind": "hit", "self": {"speed": -2}, "chance": 100}},
    "armor-cannon": {"extra": {"kind": "hit", "self": {"defense": -1, "spDef": -1}, "chance": 100}},
    "headlong-rush": {"extra": {"kind": "hit", "self": {"defense": -1, "spDef": -1}, "chance": 100}},
    "make-it-rain": {"extra": {"kind": "hit", "self": {"spAtk": -1}, "chance": 100}},
    "mystical-power": {"extra": {"kind": "hit", "self": {"spAtk": 1}, "chance": 100}},
    "torch-song": {"extra": {"kind": "hit", "self": {"spAtk": 1}, "chance": 100}},
    "aqua-step": {"extra": {"kind": "hit", "self": {"speed": 1}, "chance": 100}},
    "psyshield-bash": {"extra": {"kind": "hit", "self": {"defense": 1}, "chance": 100}},
    "bitter-malice": {"extra": {"kind": "hit", "foe": {"attack": -1}, "chance": 100}},
    "lumina-crash": {"extra": {"kind": "hit", "foe": {"spDef": -2}, "chance": 100}},
    "mountain-gale": {"extra": {"kind": "hit", "flinch": 30}},
    "malignant-chain": {"extra": {"kind": "hit", "ailment": "TOXIC", "ailmentChance": 50}},
    "shelter": {"extra": {"kind": "status", "self": {"defense": 2}, "chance": 100}},
    "tidy-up": {"extra": {"kind": "status", "self": {"attack": 1, "speed": 1}, "chance": 100}},
    "victory-dance": {"extra": {"kind": "status", "self": {"attack": 1, "defense": 1, "speed": 1}, "chance": 100}},
    "spicy-extract": {"extra": {"kind": "status", "foe": {"attack": 2, "defense": -2}, "chance": 100}},
}


# PokeAPI contest_type -> the cart's contest category (pokeemerald CONTEST_CATEGORY_*)
CONTEST_CATEGORY = {"cool": 0, "beauty": 1, "cute": 2, "smart": 3, "tough": 4}


def en(entries: list[dict[str, Any]], key: str) -> str | None:
    for e in entries:
        if e["language"]["name"] == "en":
            return e[key]
    return None


def effect_text(move: dict[str, Any]) -> str | None:
    t = en(move.get("effect_entries", []), "short_effect")
    return t.strip() if t else None


def url_id(url: str) -> int:
    return int(url.rstrip("/").rsplit("/", 1)[1])


def majority(pairs: dict[Any, collections.Counter]) -> dict[Any, int]:
    return {k: c.most_common(1)[0][0] for k, c in pairs.items()}


def parse_contest(path: Path) -> dict[int, dict[str, int]]:
    """id -> {category, effect} from an imported cart's pokemon/contest_moves.lua."""
    src = path.read_text(encoding="utf-8")
    body = src[src.find("  moves = {"):]
    out = {}
    for m in re.finditer(r"\[(\d+)\] = \{\s*category = (\d+),.*?effect = (\d+),", body, re.S):
        out[int(m.group(1))] = {"category": int(m.group(2)), "effect": int(m.group(3))}
    return out


def showdown(cache: Path) -> dict[str, Any]:
    path = cache / "showdown_moves.json"
    if not path.exists():
        req = urllib.request.Request(SHOWDOWN, headers={"User-Agent": "national_dex_gen3-builder/1.0"})
        path.write_bytes(urllib.request.urlopen(req, timeout=60).read())
    return json.loads(path.read_text(encoding="utf-8"))


def sd_key(name: str) -> str:
    return re.sub(r"[^a-z0-9]", "", name.lower())


def wrap(text: str, cols: int, rows: int) -> str | None:
    words = text.split()
    lines: list[str] = []
    cur = ""
    for w in words:
        if len(w) > cols:
            return None
        if not cur:
            cur = w
        elif len(cur) + 1 + len(w) <= cols:
            cur += " " + w
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return "\n".join(lines) if 0 < len(lines) <= rows else None


def flavor_candidates(move: dict[str, Any]) -> list[str]:
    seen, out = set(), []
    for e in reversed(move.get("flavor_text_entries", [])):
        if e["language"]["name"] != "en":
            continue
        t = re.sub(r"\s+", " ", e["flavor_text"].replace("\u00ad", "")).strip()
        if t not in seen:
            seen.add(t)
            out.append(t)
    return out


def describe(move: dict[str, Any], cols: int, rows: int) -> str | None:
    """The newest English flavor text that fits, else the first sentence of one that does."""
    texts = flavor_candidates(move)
    for t in texts:
        w = wrap(t, cols, rows)
        if w:
            return w
    for t in sorted(texts, key=len):
        # not after an abbreviation ("Sp. Atk", "etc."), which would cut the text short
        first = re.split(r"(?<!Sp\.)(?<!etc\.)(?<=[.!])\s", t)[0]
        w = wrap(first, cols, rows)
        if w:
            return w
    return None


def text_for(rid: str, move: dict[str, Any], cols: int, rows: int) -> str | None:
    """The hand-written text if there is one, else an official one that fits; Gen 3 spells it
    POKeMON (with the accent)."""
    t = wrap(DESCRIPTIONS[rid], cols, rows) if rid in DESCRIPTIONS else describe(move, cols, rows)
    return t.replace("Pokémon", "POKéMON") if t else None


def display_name(move: dict[str, Any]) -> str:
    name = (en(move["names"], "name") or move["name"]).upper().replace("\u2019", "'")
    return NAME_OVERRIDES.get(name, name)


def engine_id(move: dict[str, Any]) -> str:
    return bs.engine_id(move["name"])


def used_moves(api: bs.API) -> dict[int, int]:
    """Newer move id -> how many species and forms learn it (level-up or egg)."""
    use: collections.Counter = collections.Counter()

    def mons():
        for dex in range(bs.FIRST_DEX, bs.LAST_DEX + 1):
            sp = api.get(f"/pokemon-species/{dex}")
            yield api.get(next(v for v in sp["varieties"] if v["is_default"])["pokemon"]["url"])
        for fid, base, _form, slug in form_list.FORMS:
            try:
                yield api.get(f"/pokemon/{slug}")
            except Exception:
                continue

    for pokemon in mons():
        ids = {mid for _, mid in bs.modern_learnset(pokemon)}
        for move in pokemon["moves"]:
            for d in move["version_group_details"]:
                if d["move_learn_method"]["name"] == "egg":
                    ids.add(url_id(move["move"]["url"]))
        for mid in ids:
            if mid > bs.MAX_MOVE_ID:
                use[mid] += 1
    return dict(use)


def existing_indices(path: Path) -> dict[str, int]:
    if not path.exists():
        return {}
    src = path.read_text(encoding="utf-8")
    return {m.group(1): int(m.group(2)) for m in re.finditer(r'id = "(\w+)", index = (\d+)', src)}


def build(api: bs.API, cart_dir: Path, contest_path: Path, cache: Path, out: Path) -> tuple[list[dict], list]:
    cart = move_map.parse_cart(cart_dir)
    contest = parse_contest(contest_path)
    sd = showdown(cache)
    effect_pairs: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    target_pairs: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    ceffect_pairs: dict[int, collections.Counter] = collections.defaultdict(collections.Counter)
    for i in range(1, bs.MAX_MOVE_ID + 1):
        m = api.get(f"/move/{i}")
        effect_pairs[effect_text(m)][cart[i]["effect"]] += 1
        target_pairs[m["target"]["name"]][cart[i]["target"]] += 1
        if m.get("contest_effect") and i in contest:
            ceffect_pairs[url_id(m["contest_effect"]["url"])][contest[i]["effect"]] += 1
    effect_of, target_of, ceffect_of = majority(effect_pairs), majority(target_pairs), majority(ceffect_pairs)
    cart_effect_by_name = {c["name"]: c["effect"] for c in cart.values()}
    # an effect's cart moves are all attacks, all status moves, or a mix
    damaging: dict[int, set[bool]] = collections.defaultdict(set)
    for i in range(1, bs.MAX_MOVE_ID + 1):
        damaging[cart[i]["effect"]].add(cart[i]["power"] > 0)

    # the closest cart move (tools/move_map.py's scoring): its animation is borrowed
    use_ids = sorted(used_moves(api))
    api_moves = {i: api.get(f"/move/{i}") for i in range(1, bs.MAX_MOVE_ID + 1)}
    api_moves.update({i: api.get(f"/move/{i}") for i in use_ids})
    mapper = move_map.MoveMapper(cart, api_moves, bs.MAX_MOVE_ID)

    keep = existing_indices(out)
    next_index = max([FIRST_INDEX - 1, *keep.values()]) + 1
    rows, skipped = [], []
    use = used_moves(api)
    for mid in sorted(use, key=lambda k: (-use[k], k)):
        m = api.get(f"/move/{mid}")
        text = effect_text(m)
        extra, rule = None, None
        effect = effect_of.get(text)
        manual = MANUAL.get(m["name"])
        if manual:
            extra, rule = manual.get("extra"), manual.get("rule")
            if "like" in manual:
                effect = cart_effect_by_name[manual["like"]]
            elif "effect" in manual:
                effect = manual["effect"]
            else:
                effect = CUSTOM_EFFECT if ((extra and extra["kind"] == "status")
                                           or (rule and not (m["power"] or 0))) else 0
        power = (manual or {}).get("power", m["power"] or 0)
        hits = (manual or {}).get("hits")
        if effect is not None and effect != CUSTOM_EFFECT and (power > 0) not in damaging[effect]:
            # an attack must map onto an attacking effect, a status move onto a status one
            # (Thousand Waves shares Mean Look's text, but Mean Look's effect deals no damage)
            effect = None
        if effect is None and not manual:
            extra = generic_extra(m)
            if extra:
                effect = CUSTOM_EFFECT if extra["kind"] == "status" else 0
        target_name = (manual or {}).get("target", m["target"]["name"])   # PokeAPI's "all-allies" etc.
        if effect is None or target_name not in target_of:
            skipped.append((use[mid], m["name"], text))
            continue
        s = sd.get(sd_key(m["name"]), {})
        f = s.get("flags", {})
        flags = ((1 if f.get("contact") else 0) | (2 if f.get("protect") else 0)
                 | (4 if f.get("reflectable") else 0) | (8 if f.get("snatch") else 0)
                 | (16 if f.get("mirror") else 0)
                 | (32 if power > 0 and not (s.get("secondary") or s.get("secondaries")) else 0))
        mtype = m["type"]["name"].upper()
        rid = engine_id(m)
        name = display_name(m)
        row = {
            "id": rid, "index": keep.get(rid, 0), "api": mid, "name": name,
            "full": (en(m["names"], "name") or m["name"]).replace("’", "'"),
            "type": mtype, "power": power, "accuracy": m["accuracy"] or 0, "pp": m["pp"] or 5,
            "effect": effect, "secondaryChance": 0 if extra else (m.get("effect_chance") or 0),
            "extra": extra, "rule": rule, "hits": hits,
            "target": target_of[target_name], "priority": m["priority"] or 0, "flags": flags,
            "frlg": text_for(rid, m, FRLG_COLS, FRLG_ROWS), "rse": text_for(rid, m, RSE_COLS, RSE_ROWS),
            "contest": {
                "category": CONTEST_CATEGORY.get((m.get("contest_type") or {}).get("name"), 0),
                "effect": ceffect_of.get(url_id(m["contest_effect"]["url"]), 0) if m.get("contest_effect") else 0,
            },
            "look": (mapper.ranked(mid) or [1])[0],
            "uses": use[mid],
        }
        if not row["index"]:
            row["index"] = next_index
            next_index += 1
        rows.append(row)
    rows.sort(key=lambda r: r["index"])
    return rows, skipped


def lua_value(v: Any) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{k} = {lua_value(x)}" for k, x in v.items()) + " }"
    if isinstance(v, str):
        return lua_str(v)
    return str(v)


def lua_str(s: str | None) -> str:
    if s is None:
        return "nil"
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def write(rows: list[dict], path: Path) -> None:
    lines = [
        "-- Generated by tools/build_moves.py. Do not edit by hand.",
        "-- Moves newer than Gen 3 that work like a Gen 3 move (the cart's own effect ids), at",
        "-- append-only indices from 355 (saved in Pokemon's moves). type FAIRY is registered as",
        "-- NORMAL and turned Fairy by src/types.lua. frlg/rse: the summary text for each box.",
        "-- look: the cart move whose battle animation the move borrows.",
        "return {",
    ]
    for r in rows:
        c = r["contest"]
        lines.append(
            f'  {{ id = "{r["id"]}", index = {r["index"]}, api = {r["api"]}, name = {lua_str(r["name"])}, '
            f'full = {lua_str(r["full"])}, '
            f'type = "{r["type"]}", power = {r["power"]}, accuracy = {r["accuracy"]}, pp = {r["pp"]}, '
            f'effect = {r["effect"]}, secondaryChance = {r["secondaryChance"]}, target = {r["target"]}, '
            f'priority = {r["priority"]}, flags = {r["flags"]}, look = {r["look"]}, '
            f'contest = {{ category = {c["category"]}, effect = {c["effect"]} }},'
            + (f' extra = {lua_value(r["extra"])},' if r.get("extra") else '')
            + (f' rule = "{r["rule"]}",' if r.get("rule") else '')
            + (f' hits = {lua_value(r["hits"])},' if r.get("hits") else '') + '\n'
            f'    frlg = {lua_str(r["frlg"])},\n    rse = {lua_str(r["rse"])} }},')
    lines.append("}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    gen1 = ROOT.parent / "gen1recomp"
    p.add_argument("--cache", type=Path, default=ROOT / "tools" / ".cache")
    p.add_argument("--cart", type=Path, default=gen1 / "firered" / "data" / "generated" / "gba" / "pokemon")
    p.add_argument("--contest", type=Path,
                   default=gen1 / "emerald" / "data" / "generated" / "gba" / "pokemon" / "contest_moves.lua")
    p.add_argument("--out", type=Path, default=ROOT / "data" / "moves.lua")
    args = p.parse_args()
    rows, skipped = build(bs.API(args.cache), args.cart, args.contest, args.cache, args.out)
    problems = [r for r in rows if len(r["name"]) > NAME_LIMIT or not r["frlg"] or not r["rse"]]
    for r in problems:
        why = []
        if len(r["name"]) > NAME_LIMIT:
            why.append(f"name {r['name']!r} is {len(r['name'])} letters")
        if not r["frlg"]:
            why.append("no FRLG text fits")
        if not r["rse"]:
            why.append("no RSE text fits")
        print(f"  FIX {r['id']}: {'; '.join(why)}")
    write(rows, args.out)
    report = args.cache / "moves_new.txt"
    report.write_text("\n".join(f"{n:4} {name}: {text}" for n, name, text in sorted(skipped, reverse=True)),
                      encoding="utf-8")
    real = sum(r["uses"] for r in rows)
    print(f"{len(rows)} real moves ({real} species/form uses) -> {args.out}; "
          f"{len(skipped)} keep a substitute (list: {report})")


if __name__ == "__main__":
    main()
