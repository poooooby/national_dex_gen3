#!/usr/bin/env python3
"""Generate data/abilities.lua: real abilities newer than Gen 3.

The Gen 3 battle engine names a battler's ability through the adapter's `abilityOf` and acts
on it in its own functions (src/core/game3/battle/abilities.lua and the damage, hit and engine
code). src/abilities.lua gives each ability below an id from 78 (after the cart's 77), a name
and a summary text, and its effect through wraps of those functions and the battle hooks.
Every other newer ability keeps the closest Gen 3 ability (tools/ability_map.py), and so does
any of these that fails to install.

  defs     IMPLEMENTED, in order: ids are append-only (a Pokemon's ability is saved by number)
  species  each species' regular ability slots (1, 2), in order: the PokeAPI slug and the
           Gen 3 fallback id (0: none), by National number
  forms    the same for each form in tools/form_list.py, by form id

    python tools/build_abilities.py
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path
from typing import Any

import ability_map
import build_species as bs
import form_list

ROOT = Path(__file__).resolve().parent.parent
FIRST_ID = 78
NAME_LIMIT, TEXT_LIMIT = 12, 27

# slug -> (name in the game, summary text). Append only. Our own words, in the Gen 3 manner.
IMPLEMENTED: dict[str, tuple[str, str]] = {
    "technician": ("TECHNICIAN", "Powers up weak moves."),
    "strong-jaw": ("STRONG JAW", "Powers up biting moves."),
    "iron-fist": ("IRON FIST", "Powers up punching moves."),
    "tough-claws": ("TOUGH CLAWS", "Powers up contact moves."),
    "reckless": ("RECKLESS", "Powers up recoil moves."),
    "sand-force": ("SAND FORCE", "Powers up moves in sand."),
    "heatproof": ("HEATPROOF", "Halves FIRE-type damage."),
    "adaptability": ("ADAPTABILITY", "Powers up same-type moves."),
    "sniper": ("SNIPER", "Powers up critical hits."),
    "super-luck": ("SUPER LUCK", "Raises critical-hit ratio."),
    "multiscale": ("MULTISCALE", "Less damage at full HP."),
    "fluffy": ("FLUFFY", "Contact halved; FIRE x2."),
    "solid-rock": ("SOLID ROCK", "Dulls super-effective hits."),
    "prism-armor": ("PRISM ARMOR", "Dulls super-effective hits."),
    "filter": ("FILTER", "Dulls super-effective hits."),
    "tinted-lens": ("TINTED LENS", "Boosts resisted moves."),
    "regenerator": ("REGENERATOR", "Recovers HP on switch-out."),
    "snow-warning": ("SNOW WARNING", "Summons hail in battle."),
    "ice-body": ("ICE BODY", "Slight HP recovery in hail."),
    "snow-cloak": ("SNOW CLOAK", "Ups evasion in hail."),
    "justified": ("JUSTIFIED", "Ups ATTACK if hit by DARK."),
    "rattled": ("RATTLED", "BUG/GHOST/DARK hits up SPD."),
    "stamina": ("STAMINA", "Ups DEFENSE when hit."),
    "weak-armor": ("WEAK ARMOR", "Physical hits: -DEF, +SPEED"),
    "iron-barbs": ("IRON BARBS", "Hurts the foe on contact."),
    "aftermath": ("AFTERMATH", "Hurts the foe as it faints."),
    "poison-touch": ("POISON TOUCH", "May poison on contact."),
    "sap-sipper": ("SAP SIPPER", "GRASS moves raise ATTACK."),
    "motor-drive": ("MOTOR DRIVE", "ELECTRIC moves raise SPEED."),
    "storm-drain": ("STORM DRAIN", "WATER moves raise SP. ATK."),
    "dry-skin": ("DRY SKIN", "Likes water, hates fire."),
    "hydration": ("HYDRATION", "Heals status in rain."),
    "leaf-guard": ("LEAF GUARD", "No status problems in sun."),
    "defiant": ("DEFIANT", "Stat cuts raise ATTACK."),
    "competitive": ("COMPETITIVE", "Stat cuts raise SP. ATK."),
    "big-pecks": ("BIG PECKS", "Prevents DEFENSE reduction."),
    "prankster": ("PRANKSTER", "Status moves go first."),
    "sand-rush": ("SAND RUSH", "Ups SPEED in a sandstorm."),
    "slush-rush": ("SLUSH RUSH", "Ups SPEED in hail."),
    "moxie": ("MOXIE", "KOs raise ATTACK."),
    "beast-boost": ("BEAST BOOST", "KOs raise its best stat."),
    "frisk": ("FRISK", "Checks the foe's held item."),
    "anticipation": ("ANTICIPATION", "Senses the foe's danger."),
    "rivalry": ("RIVALRY", "Same gender up, other down"),
    "bulletproof": ("BULLETPROOF", "Blocks ball and bomb moves."),
    "sweet-veil": ("SWEET VEIL", "Prevents sleep."),
    "flower-veil": ("FLOWER VEIL", "Guards GRASS types' stats."),
    "protosynthesis": ("PROTOSYNTH.", "Sun ups its best stat."),
    # no effect here: they act on a battle partner or after battle (Gen 3 has no HONEY)
    "healer": ("HEALER", "No effect in this game."),
    "telepathy": ("TELEPATHY", "No effect in this game."),
    "honey-gather": ("HONEY GATHER", "No effect in this game."),
    "quark-drive": ("QUARK DRIVE", "Electric field ups a stat."),
    # src/abilities_more.lua
    "gluttony": ("GLUTTONY", "Eats pinch berries early."),
    "mold-breaker": ("MOLD BREAKER", "Moves ignore abilities."),
    "sheer-force": ("SHEER FORCE", "Ups power, drops effects."),
    "unburden": ("UNBURDEN", "Ups SPEED if item is lost."),
    "infiltrator": ("INFILTRATOR", "Passes through barriers."),
    "klutz": ("KLUTZ", "Can't use held items."),
    "overcoat": ("OVERCOAT", "Blocks weather and powder."),
    "unnerve": ("UNNERVE", "Foes can't eat berries."),
    "unaware": ("UNAWARE", "Ignores stat changes."),
    "steadfast": ("STEADFAST", "Flinching ups SPEED."),
    "cheek-pouch": ("CHEEK POUCH", "Berries also restore HP."),
    "magic-guard": ("MAGIC GUARD", "Only hurt by attacks."),
    "dancer": ("DANCER", "Copies dance moves."),
    "tangled-feet": ("TANGLED FEET", "Evades more if confused."),
    "cursed-body": ("CURSED BODY", "May disable a move."),
    "skill-link": ("SKILL LINK", "Multi-hit moves hit 5x."),
    "steam-engine": ("STEAM ENGINE", "FIRE/WATER hits up SPEED."),
    "ripen": ("RIPEN", "Doubles berry effects."),
    "purifying-salt": ("PURIFY SALT", "No status; halves GHOST."),
    "thermal-exchange": ("THERMAL EXCH", "FIRE hits up ATK; no burn."),
    "toxic-chain": ("TOXIC CHAIN", "May badly poison foes."),
    "anger-point": ("ANGER POINT", "Crits max out ATTACK."),
    "simple": ("SIMPLE", "Stat changes are doubled."),
    "download": ("DOWNLOAD", "Ups ATK or SP.ATK on entry."),
    "forewarn": ("FOREWARN", "Reveals the foe's top move."),
    "mummy": ("MUMMY", "Spreads on contact."),
    "defeatist": ("DEFEATIST", "Weak at half HP or less."),
    "turboblaze": ("TURBOBLAZE", "Moves ignore abilities."),
    "teravolt": ("TERAVOLT", "Moves ignore abilities."),
    "fur-coat": ("FUR COAT", "Halves physical damage."),
    "no-guard": ("NO GUARD", "All moves hit both ways."),
    "contrary": ("CONTRARY", "Stat changes are reversed."),
    "mega-launcher": ("MEGALAUNCHER", "Powers up pulse moves."),
    "refrigerate": ("REFRIGERATE", "NORMAL moves become ICE."),
    "aura-break": ("AURA BREAK", "Reverses the auras."),
    "magician": ("MAGICIAN", "Steals items it hits."),
    "stakeout": ("STAKEOUT", "Hits newcomers harder."),
    "merciless": ("MERCILESS", "Always crits poisoned foes."),
    "water-bubble": ("WATER BUBBLE", "Ups WATER; halves FIRE."),
    "corrosion": ("CORROSION", "Poisons any type."),
    "water-compaction": ("WATERCOMPACT", "WATER hits up DEFENSE."),
    "berserk": ("BERSERK", "Ups SP.ATK at half HP."),
    "cotton-down": ("COTTON DOWN", "Hits lower foes' SPEED."),
    "sand-spit": ("SAND SPIT", "Hits whip up a sandstorm."),
    "screen-cleaner": ("SCREEN CLEAN", "Clears screens on entry."),
    "wandering-spirit": ("WANDERSPIRIT", "Swaps abilities on contact."),
    "intrepid-sword": ("INTREPID SWD", "Ups ATTACK on entry."),
    "dauntless-shield": ("DAUNTLESS SH", "Ups DEFENSE on entry."),
    "unseen-fist": ("UNSEEN FIST", "Contact hits pass Protect."),
    "wind-power": ("WIND POWER", "Wind moves charge it."),
    "wind-rider": ("WIND RIDER", "Wind moves up ATTACK."),
    "mycelium-might": ("MYCELIUM MGT", "Status moves go last."),
    "gooey": ("GOOEY", "Contact lowers SPEED."),
    "toxic-debris": ("TOXIC DEBRIS", "Physical hits lay spikes."),
    "supersweet-syrup": ("SWEET SYRUP", "Lowers foe's evasion."),
    "tangling-hair": ("TANGLINGHAIR", "Contact lowers SPEED."),
    "pastel-veil": ("PASTEL VEIL", "Prevents poisoning."),
    "flower-gift": ("FLOWER GIFT", "Powers up in sunshine."),
    "sharpness": ("SHARPNESS", "Powers up slicing moves."),
    "slow-start": ("SLOW START", "Slow for five turns."),
    "bad-dreams": ("BAD DREAMS", "Hurts sleeping foes."),
    "multitype": ("MULTITYPE", "Type follows its Plate."),
    "victory-star": ("VICTORY STAR", "Ups accuracy."),
    "wonder-skin": ("WONDER SKIN", "Dodges status moves."),
    "stance-change": ("STANCECHANGE", "Changes form to attack."),
    "fairy-aura": ("FAIRY AURA", "Powers up FAIRY moves."),
    "dark-aura": ("DARK AURA", "Powers up DARK moves."),
    "schooling": ("SCHOOLING", "Forms a school when strong."),
    "queenly-majesty": ("QUEENLY MJST", "Blocks priority moves."),
    "triage": ("TRIAGE", "Healing moves go first."),
    "wimp-out": ("WIMP OUT", "Flees at half HP."),
    "emergency-exit": ("EMERGENCY EX", "Flees at half HP."),
    "innards-out": ("INNARDS OUT", "Hurts the foe as it faints."),
    "shields-down": ("SHIELDS DOWN", "Shell breaks at half HP."),
    "comatose": ("COMATOSE", "Always drowsing."),
    "disguise": ("DISGUISE", "Fakes the first hit."),
    "dazzling": ("DAZZLING", "Blocks priority moves."),
    "steelworker": ("STEELWORKER", "Powers up STEEL moves."),
    "electric-surge": ("ELEC. SURGE", "Electric Terrain on entry."),
    "psychic-surge": ("PSY. SURGE", "Psychic Terrain on entry."),
    "grassy-surge": ("GRASSY SURGE", "Grassy Terrain on entry."),
    "misty-surge": ("MISTY SURGE", "Misty Terrain on entry."),
    "full-metal-body": ("FULLMETAL BD", "Prevents stat reduction."),
    "shadow-shield": ("SHADOWSHIELD", "Less damage at full HP."),
    "soul-heart": ("SOUL-HEART", "Faints raise SP. ATK."),
    "gulp-missile": ("GULP MISSILE", "Spits prey when hit."),
    "punk-rock": ("PUNK ROCK", "Loud moves up, taken down."),
    "ice-face": ("ICE FACE", "Blocks one physical hit."),
    "hunger-switch": ("HUNGER SWTCH", "Changes mode each turn."),
    "light-metal": ("LIGHT METAL", "Halves its weight."),
    "heavy-metal": ("HEAVY METAL", "Doubles its weight."),
    "transistor": ("TRANSISTOR", "Powers up ELECTRIC moves."),
    "dragons-maw": ("DRAGON'S MAW", "Powers up DRAGON moves."),
    "chilling-neigh": ("CHILL. NEIGH", "KOs raise ATTACK."),
    "grim-neigh": ("GRIM NEIGH", "KOs raise SP. ATK."),
    "aroma-veil": ("AROMA VEIL", "Blocks mental attacks."),
    "lingering-aroma": ("LINGER AROMA", "Spreads on contact."),
    "well-baked-body": ("WELL-BAKED", "FIRE moves raise DEFENSE."),
    "seed-sower": ("SEED SOWER", "Hits make the field grassy."),
    "electromorphosis": ("ELECTROMORPH", "Hits charge it."),
    "guard-dog": ("GUARD DOG", "Intimidate ups ATTACK."),
    "pickpocket": ("PICKPOCKET", "Steals items on contact."),
    "anger-shell": ("ANGER SHELL", "Riled up at half HP."),
    "opportunist": ("OPPORTUNIST", "Copies foes' stat rises."),
    "zero-to-hero": ("ZERO TO HERO", "Becomes a hero on return."),
    "earth-eater": ("EARTH EATER", "GROUND moves restore HP."),
    "scrappy": ("SCRAPPY", "Hits GHOST; no Intimidate."),
    "cud-chew": ("CUD CHEW", "Eats a berry twice."),
    "armor-tail": ("ARMOR TAIL", "Blocks priority moves."),
    "supreme-overlord": ("SUPREME LORD", "Fallen allies up power."),
    "good-as-gold": ("GOOD AS GOLD", "Immune to status moves."),
    "tablets-of-ruin": ("RUIN TABLETS", "Weakens others' ATTACK."),
    "sword-of-ruin": ("RUIN SWORD", "Weakens others' DEFENSE."),
    "vessel-of-ruin": ("RUIN VESSEL", "Weakens others' SP. ATK."),
    "beads-of-ruin": ("RUIN BEADS", "Weakens others' SP. DEF."),
    "orichalcum-pulse": ("ORICHALCUM", "Sunshine ups its ATTACK."),
    "hadron-engine": ("HADRON ENG.", "Electricity ups SP. ATK."),
    "poison-puppeteer": ("PUPPETEER", "Its poison also confuses."),
    "as-one-glastrier": ("AS ONE", "Unnerve plus Chilling Neigh"),
    "as-one-spectrier": ("AS ONE", "Unnerve plus Grim Neigh."),
    "gorilla-tactics": ("GORILLA TACT", "Ups ATK; locks its move."),
    "surge-surfer": ("SURGE SURFER", "Fast on Electric Terrain."),
    "quick-draw": ("QUICK DRAW", "Sometimes moves first."),
    "mimicry": ("MIMICRY", "Type follows the terrain."),
    "minds-eye": ("MIND'S EYE", "Hits GHOST; keen aim."),
    "neutralizing-gas": ("NEUTRAL. GAS", "Nullifies other abilities."),
}


# slug -> the full effect as it works HERE, for the player docs (docs/abilities.md): every
# number, and anything that differs from the newer games. Keep it in step with src/abilities.lua.
# Gen 3 sorts physical/special by the move's TYPE, not by the move.
DETAILS: dict[str, str] = {
    "technician": "Moves with 60 power or less get 1.5x power.",
    "strong-jaw": "Biting moves get 1.5x power: Bite, Crunch, Hyper Fang, Poison Fang, Fire Fang, Ice Fang, Thunder Fang, Psychic Fangs, Jaw Lock, Fishious Rend.",
    "iron-fist": "Punching moves get 1.2x power (Mach Punch, Fire/Ice/Thunder Punch, Drain Punch, Bullet Punch, Sky Uppercut, Meteor Mash and the rest).",
    "tough-claws": "Moves that make contact get 1.3x power.",
    "reckless": "Recoil moves get 1.2x power (Double-Edge, Take Down, Submission, Volt Tackle, Brave Bird, Flare Blitz, Wood Hammer, Head Smash, Wild Charge, Head Charge, Wave Crash), and so do Jump Kick and High Jump Kick.",
    "sand-force": "In a sandstorm, Rock, Ground and Steel moves get 1.3x power. It does not block sandstorm damage here; only the types and Sand Veil that Gen 3 already spares are safe.",
    "heatproof": "Fire moves deal half damage to it. Burn damage is not halved here.",
    "adaptability": "Moves of its own type deal 2x instead of the usual 1.5x.",
    "sniper": "Its critical hits deal a further 1.5x (3x in all, since a Gen 3 critical hit is 2x).",
    "super-luck": "Its moves land critical hits more often: one stage up, as if every move had a high critical-hit ratio.",
    "multiscale": "At full HP it takes half damage.",
    "fluffy": "Moves that make contact deal half damage to it, but Fire moves deal double. A Fire move that makes contact (Fire Punch, Flare Blitz) deals normal damage.",
    "solid-rock": "Super-effective moves deal 3/4 damage to it.",
    "prism-armor": "Super-effective moves deal 3/4 damage to it.",
    "filter": "Super-effective moves deal 3/4 damage to it.",
    "tinted-lens": "Its not-very-effective moves deal double damage.",
    "regenerator": "Restores 1/3 of its max HP when it switches out (not when it faints).",
    "snow-warning": "Starts hail when it enters battle. The hail lasts until other weather replaces it, like Drizzle and Drought in Gen 3.",
    "ice-body": "Restores 1/16 of its max HP at the end of each turn in hail. Hail damage itself only spares Ice types here.",
    "snow-cloak": "In hail, moves aimed at it are 20% less accurate. Hail damage itself only spares Ice types here.",
    "justified": "Its ATTACK rises one stage when a Dark move hits it.",
    "rattled": "Its SPEED rises one stage when a Bug, Ghost or Dark move hits it.",
    "stamina": "Its DEFENSE rises one stage every time a damaging move hits it.",
    "weak-armor": "When a physical move hits it, its DEFENSE falls one stage and its SPEED rises two.",
    "iron-barbs": "A foe that hits it with a contact move loses 1/8 of its max HP.",
    "aftermath": "If it faints from a contact move, the attacker loses 1/4 of its max HP.",
    "poison-touch": "Its contact moves have a 30% chance to poison the target.",
    "sap-sipper": "Grass moves have no effect on it and raise its ATTACK one stage instead.",
    "motor-drive": "Electric moves have no effect on it and raise its SPEED one stage instead.",
    "storm-drain": "Water moves have no effect on it and raise its SP. ATK one stage instead.",
    "dry-skin": "Water moves have no effect on it and restore 1/4 of its max HP instead. Fire moves deal 1.25x damage to it. In rain it restores 1/8 of its max HP each turn; in harsh sunlight it loses 1/8 each turn.",
    "hydration": "In rain, it is cured of a status problem (burn, poison, paralysis, sleep, freeze) at the end of the turn.",
    "leaf-guard": "In harsh sunlight, status moves can't give it a status problem. A damaging move's added effect (a burn from Flamethrower) still can.",
    "defiant": "When a foe lowers one of its stats, its ATTACK rises two stages.",
    "competitive": "When a foe lowers one of its stats, its SP. ATK rises two stages.",
    "big-pecks": "Foes can't lower its DEFENSE.",
    "prankster": "Its status moves get +1 priority, so they usually go first. Dark types are not immune to them here.",
    "sand-rush": "Its SPEED doubles in a sandstorm. It does not block sandstorm damage here.",
    "slush-rush": "Its SPEED doubles in hail.",
    "moxie": "Its ATTACK rises one stage when it knocks out a foe with a move.",
    "beast-boost": "When it knocks out a foe with a move, its highest stat (not counting HP) rises one stage.",
    "frisk": "On entering battle it reveals the foe's held item.",
    "anticipation": "On entering battle it shudders if the foe knows a damaging move that is super effective against it.",
    "rivalry": "1.25x power against a foe of the same gender, 0.75x against the other gender. No change if either is genderless.",
    "bulletproof": "Ball and bomb moves have no effect on it: Barrage, Egg Bomb, Shadow Ball, Sludge Bomb, Zap Cannon, Octazooka, Mist Ball, Ice Ball, Bullet Seed, Weather Ball, Energy Ball, Focus Blast, Gyro Ball, Seed Bomb, Mud Bomb, Magnet Bomb, Rock Wrecker, Aura Sphere, Acid Spray, Searing Shot, Electro Ball, Pollen Puff, Beak Blast, Pyro Ball.",
    "sweet-veil": "It can't be put to sleep by a move.",
    "flower-veil": "If it is a Grass type, foes can't lower its stats and status moves can't give it a status problem.",
    "protosynthesis": "In harsh sunlight, or once it uses a held Booster Energy, its highest stat goes up: 1.3x for ATTACK, DEFENSE, SP. ATK or SP. DEF, 1.5x for SPEED.",
    "healer": "No effect here. In the newer games it may cure a battle partner's status problem; this game does not use it, even in double battles.",
    "telepathy": "No effect here. In the newer games it avoids a battle partner's attacks; this game does not use it, even in double battles.",
    "honey-gather": "No effect here. In the newer games it may pick up Honey after battle, an item Gen 3 does not have.",
    "quark-drive": "On Electric Terrain, or once it uses a held Booster Energy, its highest stat goes up: 1.3x for ATTACK, DEFENSE, SP. ATK or SP. DEF, 1.5x for SPEED.",
    "gluttony": "It eats a berry meant for 1/4 HP or less (Liechi, Ganlon, Salac, Petaya, Apicot, Lansat, Starf, Micle, Custap) at half HP instead.",
    "mold-breaker": "While its move hits, the target's ability has no effect (Levitate, Wonder Guard, Volt Absorb, Flash Fire, Sturdy, Thick Fat...). Abilities that react once the hit is over, such as Rough Skin, still work.",
    "sheer-force": "Moves with an added effect (a chance to burn, freeze, flinch, poison, lower a stat or raise its own) get 1.3x power and lose that effect.",
    "unburden": "Once its held item is used up or taken, its SPEED doubles until it switches out.",
    "infiltrator": "Its moves ignore the foe's Reflect, Light Screen, Aurora Veil and Substitute.",
    "klutz": "Its held item has no effect in battle (Leftovers, berries, Choice Band, Life Orb...).",
    "overcoat": "Sandstorm and hail don't hurt it, and powder and spore moves (Sleep Powder, Stun Spore, Poison Powder, Spore, Cotton Spore, Rage Powder, Magic Powder) have no effect on it.",
    "unnerve": "While it is in battle, the foe can't eat its held berry.",
    "unaware": "When it attacks, the target's DEFENSE, SP. DEF and evasion changes don't count; when it is attacked, the attacker's ATTACK, SP. ATK and accuracy changes don't count.",
    "steadfast": "Its SPEED rises one stage each time it flinches.",
    "cheek-pouch": "Eating a berry also restores 1/3 of its max HP.",
    "magic-guard": "It takes damage only from attacks: no poison, burn, sandstorm, hail, Leech Seed, Nightmare, Curse, Spikes, Stealth Rock, recoil, crash, Rough Skin, Iron Barbs, Life Orb or Rocky Helmet damage. Its own Substitute, Belly Drum, confusion and Destiny Bond still cost HP.",
    "dancer": "When another Pokemon uses a dance move (Swords Dance, Dragon Dance, Quiver Dance, Petal Dance, Teeter Dance, Feather Dance, Fiery Dance, Lunar Dance, Victory Dance...), it dances the same move right after.",
    "tangled-feet": "While it is confused, moves aimed at it are half as accurate.",
    "cursed-body": "When a move hits it, that move is disabled 30% of the time, for 4 turns.",
    "skill-link": "Moves that strike 2 to 5 times always strike 5 times.",
    "steam-engine": "When a Fire or Water move hits it, its SPEED rises six stages.",
    "ripen": "Berries it eats work twice: twice the HP, twice the stat rise.",
    "purifying-salt": "It can't get a status problem, and Ghost moves deal half damage to it.",
    "thermal-exchange": "When a Fire move hits it, its ATTACK rises one stage. It can't be burned.",
    "toxic-chain": "Its damaging moves badly poison the target 30% of the time.",
    "anger-point": "When a critical hit lands on it, its ATTACK rises to the maximum.",
    "simple": "Every stat change on it counts double.",
    "download": "On entering battle, its SP. ATK rises one stage if the foe's SP. DEF is lower than its DEFENSE, otherwise its ATTACK does.",
    "forewarn": "On entering battle it names the foe's most powerful move.",
    "mummy": "A foe that makes contact with it gets Mummy as its ability until it switches out.",
    "defeatist": "At half HP or less its ATTACK and SP. ATK are halved.",
    "turboblaze": "As Mold Breaker: while its move hits, the target's ability has no effect.",
    "teravolt": "As Mold Breaker: while its move hits, the target's ability has no effect.",
    "fur-coat": "Physical moves deal half damage to it. Gen 3 sorts moves by type: Normal, Fighting, Flying, Poison, Ground, Rock, Bug, Ghost and Steel moves are physical.",
    "no-guard": "Its moves and the moves aimed at it never miss, even against a Pokemon in the air or underground.",
    "contrary": "Every stat change on it goes the other way: Growl raises its ATTACK, Overheat raises its SP. ATK.",
    "mega-launcher": "Pulse and aura moves get 1.5x power: Water Pulse, Dark Pulse, Dragon Pulse, Aura Sphere, Origin Pulse, Terrain Pulse.",
    "refrigerate": "Its Normal moves become Ice moves with 1.2x power.",
    "aura-break": "While it is in battle, Fairy Aura and Dark Aura weaken Fairy and Dark moves to 3/4 instead of boosting them.",
    "magician": "When its move hits a foe and it holds nothing, it takes the foe's held item.",
    "stakeout": "Its moves deal double damage to a foe that switched in this turn.",
    "merciless": "Its moves are always critical hits against a poisoned foe.",
    "water-bubble": "Its Water moves deal double damage, Fire moves deal half damage to it, and it can't be burned.",
    "corrosion": "It can poison Steel and Poison types, with poison moves and with its moves' added effects.",
    "water-compaction": "When a Water move hits it, its DEFENSE rises two stages.",
    "berserk": "When a hit drops it to half HP or less, its SP. ATK rises one stage.",
    "cotton-down": "When a move hits it, the attacker's SPEED falls one stage.",
    "sand-spit": "When a move hits it, a sandstorm starts for 5 turns.",
    "screen-cleaner": "On entering battle it removes Reflect, Light Screen and Aurora Veil from both sides.",
    "wandering-spirit": "A foe that makes contact with it swaps abilities with it until they switch out.",
    "intrepid-sword": "Its ATTACK rises one stage the first time it enters each battle.",
    "dauntless-shield": "Its DEFENSE rises one stage the first time it enters each battle.",
    "unseen-fist": "Its moves that make contact hit through Protect and Detect.",
    "wind-power": "When a wind move hits it, its next Electric move deals double damage, as after Charge.",
    "wind-rider": "Wind moves have no effect on it and raise its ATTACK one stage instead (Gust, Twister, Air Cutter, Hurricane, Bleakwind Storm...).",
    "mycelium-might": "Its status moves go after the foe's moves of the same priority, and they ignore the target's ability.",
    "gooey": "A foe that makes contact with it has its SPEED lowered one stage.",
    "toxic-debris": "When a physical move hits it, poison spikes are scattered around the attacker's feet (Toxic Spikes, up to two layers).",
    "supersweet-syrup": "The first time it enters each battle, the foe's evasiveness falls one stage.",
    "tangling-hair": "A foe that makes contact with it has its SPEED lowered one stage.",
    "pastel-veil": "It can't be poisoned.",
    "flower-gift": "In harsh sunlight its ATTACK and SP. DEF are 1.5x.",
    "sharpness": "Slicing moves get 1.5x power: Cut, Slash, Razor Leaf, Leaf Blade, Night Slash, X-Scissor, Air Slash, Psycho Cut, Sacred Sword, Aqua Cutter and the rest.",
    "slow-start": "For its first five turns in battle its ATTACK and SPEED are halved.",
    "bad-dreams": "A sleeping foe loses 1/8 of its max HP at the end of each turn.",
    "multitype": "Its type is the type of the Plate it holds; without one it is a Normal type.",
    "victory-star": "Its moves are 1.1x as accurate.",
    "wonder-skin": "Status moves aimed at it are at most 50% accurate.",
    "stance-change": "Aegislash takes its Blade Forme (ATTACK 140, DEFENSE 50, SP. ATK 140, SP. DEF 50) when it uses a damaging move, and its Shield Forme again when it uses King's Shield. Its picture does not change.",
    "fairy-aura": "While it is in battle, every Pokemon's Fairy moves get 1.33x power.",
    "dark-aura": "While it is in battle, every Pokemon's Dark moves get 1.33x power.",
    "schooling": "From level 20, Wishiwashi forms a school while above 1/4 HP: ATTACK 140, DEFENSE 130, SP. ATK 140, SP. DEF 135, SPEED 30. Its picture does not change.",
    "queenly-majesty": "Foes' moves with raised priority (Quick Attack, Extreme Speed, Prankster's moves...) fail against it.",
    "triage": "Its healing moves get +3 priority (Recover, Roost, Drain Punch, Giga Drain, Draining Kiss...).",
    "wimp-out": "When a hit drops it to half HP or less, it switches out; a wild one runs away.",
    "emergency-exit": "When a hit drops it to half HP or less, it switches out; a wild one runs away.",
    "innards-out": "When it faints from a hit, the attacker loses as much HP as it had left before the hit.",
    "shields-down": "Above half HP Minior is in Meteor Form and can't get a status problem. At half HP or less it is in Core Form: ATTACK and SP. ATK 100, DEFENSE and SP. DEF 60, SPEED 120. Its picture does not change.",
    "comatose": "It can't get a status problem.",
    "disguise": "The first damaging hit on it does no damage: its disguise breaks instead and it loses 1/8 of its max HP.",
    "dazzling": "Foes' moves with raised priority (Quick Attack, Extreme Speed, Prankster's moves...) fail against it.",
    "steelworker": "Its Steel moves get 1.5x power.",
    "electric-surge": "It covers the field in Electric Terrain for 5 turns when it enters battle.",
    "psychic-surge": "It covers the field in Psychic Terrain for 5 turns when it enters battle.",
    "grassy-surge": "It covers the field in Grassy Terrain for 5 turns when it enters battle.",
    "misty-surge": "It covers the field in Misty Terrain for 5 turns when it enters battle.",
    "full-metal-body": "Foes can't lower its stats, Intimidate included, and no ability can set this one aside.",
    "shadow-shield": "At full HP it takes half damage, and no ability can set this one aside.",
    "soul-heart": "Its SP. ATK rises one stage whenever another Pokemon faints.",
    "gulp-missile": "After Surf or Dive, Cramorant holds prey; the next time a move hits it, the attacker loses 1/4 of its max HP and its DEFENSE falls one stage. Its picture does not change.",
    "punk-rock": "Its sound moves get 1.3x power, and sound moves deal half damage to it.",
    "ice-face": "Eiscue's ice face takes the first physical hit for no damage, then breaks: DEFENSE 70, SP. DEF 50, SPEED 130 after. Hail rebuilds it. Its picture does not change.",
    "hunger-switch": "Morpeko switches between Full Belly and Hangry Mode at the end of every turn; in Hangry Mode Aura Wheel is a Dark move.",
    "light-metal": "Its weight is halved for Low Kick, Grass Knot, Heavy Slam and Heat Crash.",
    "heavy-metal": "Its weight is doubled for Low Kick, Grass Knot, Heavy Slam and Heat Crash.",
    "transistor": "Its Electric moves get 1.3x power.",
    "dragons-maw": "Its Dragon moves get 1.5x power.",
    "chilling-neigh": "Its ATTACK rises one stage when it knocks out a foe with a move.",
    "grim-neigh": "Its SP. ATK rises one stage when it knocks out a foe with a move.",
    "aroma-veil": "Taunt, Torment, Encore, Disable, Heal Block and Attract have no effect on it.",
    "lingering-aroma": "A foe that makes contact with it gets Lingering Aroma as its ability until it switches out.",
    "well-baked-body": "Fire moves have no effect on it and raise its DEFENSE two stages instead.",
    "seed-sower": "When a move hits it, Grassy Terrain covers the field for 5 turns.",
    "electromorphosis": "When a move hits it, its next Electric move deals double damage, as after Charge.",
    "guard-dog": "Intimidate raises its ATTACK instead of lowering it.",
    "pickpocket": "When a contact move hits it and it holds nothing, it takes the attacker's held item.",
    "anger-shell": "When a hit drops it to half HP or less, its ATTACK, SP. ATK and SPEED rise one stage and its DEFENSE and SP. DEF fall one stage.",
    "opportunist": "When a foe's stats rise, its own rise the same way.",
    "zero-to-hero": "After Palafin switches out once, it comes back in its Hero Form: ATTACK 160, DEFENSE 97, SP. ATK 106, SP. DEF 87. Its picture does not change.",
    "earth-eater": "Ground moves have no effect on it and restore 1/4 of its max HP instead.",
    "scrappy": "Its Normal and Fighting moves hit Ghost types, and Intimidate does not affect it.",
    "cud-chew": "At the end of the turn after it eats a berry, it eats it again.",
    "armor-tail": "Foes' moves with raised priority (Quick Attack, Extreme Speed, Prankster's moves...) fail against it.",
    "supreme-overlord": "Its moves get 10% more power for each fainted Pokemon in its party, up to 50%.",
    "good-as-gold": "Status moves a foe aims at it have no effect.",
    "tablets-of-ruin": "While it is in battle, every other Pokemon's ATTACK is 0.75x.",
    "sword-of-ruin": "While it is in battle, every other Pokemon's DEFENSE is 0.75x.",
    "vessel-of-ruin": "While it is in battle, every other Pokemon's SP. ATK is 0.75x.",
    "beads-of-ruin": "While it is in battle, every other Pokemon's SP. DEF is 0.75x.",
    "orichalcum-pulse": "It turns the sunlight harsh when it enters battle, and its ATTACK is 1.33x in harsh sunlight.",
    "hadron-engine": "It covers the field in Electric Terrain when it enters battle, and its SP. ATK is 1.33x on Electric Terrain.",
    "poison-puppeteer": "A foe it poisons is also confused.",
    "as-one-glastrier": "The foe can't eat its held berry, and its ATTACK rises one stage when it knocks out a foe with a move.",
    "as-one-spectrier": "The foe can't eat its held berry, and its SP. ATK rises one stage when it knocks out a foe with a move.",
    "gorilla-tactics": "Its ATTACK is 1.5x, but it can only use the first move it picks until it switches out.",
    "surge-surfer": "Its SPEED doubles on Electric Terrain.",
    "quick-draw": "30% of the time it moves first among moves of the same priority.",
    "mimicry": "On a terrain it becomes that terrain's type (Electric, Grass, Fairy or Psychic); without one it is its own type again.",
    "minds-eye": "Its Normal and Fighting moves hit Ghost types, its accuracy can't be lowered, and it ignores the target's evasiveness.",
    "neutralizing-gas": "While it is in battle, every other Pokemon's ability has no effect.",
}


def url_id(url: str) -> int:
    return int(url.rstrip("/").rsplit("/", 1)[1])


def slots_of(pokemon: dict[str, Any]) -> list[tuple[str, int]]:
    """Regular (non-hidden) ability slots, in order: (slug, Gen 3 fallback id or 0)."""
    out = []
    for a in sorted(pokemon["abilities"], key=lambda a: a["slot"]):
        if a.get("is_hidden"):
            continue
        slug = a["ability"]["name"]
        out.append((slug, ability_map.cart_id(url_id(a["ability"]["url"]), slug) or 0))
    return out[:2]


def existing_ids(path: Path) -> dict[str, int]:
    if not path.exists():
        return {}
    src = path.read_text(encoding="utf-8")
    return {m.group(2): int(m.group(1)) for m in re.finditer(r'id = (\d+), slug = "([\w-]+)"', src)}


def build(api: bs.API, out: Path) -> dict[str, Any]:
    keep = existing_ids(out)
    nxt = max([FIRST_ID - 1, *keep.values()]) + 1
    defs = []
    for slug, (name, text) in IMPLEMENTED.items():
        assert len(name) <= NAME_LIMIT, f"{slug}: name {name!r} over {NAME_LIMIT}"
        assert len(text) <= TEXT_LIMIT, f"{slug}: text {text!r} over {TEXT_LIMIT}"
        assert slug in DETAILS and '"' not in DETAILS[slug], f"{slug}: no DETAILS entry (or a quote in it)"
        aid = keep.get(slug)
        if aid is None:
            aid, nxt = nxt, nxt + 1
        defs.append({"id": aid, "slug": slug, "key": bs.engine_id(slug), "name": name, "text": text,
                     "detail": DETAILS[slug]})
    species = {}
    for dex in range(bs.FIRST_DEX, bs.LAST_DEX + 1):
        sp = api.get(f"/pokemon-species/{dex}")
        species[dex] = slots_of(api.get(next(v for v in sp["varieties"] if v["is_default"])["pokemon"]["url"]))
    forms = {}
    for fid, _base, _form, slug in form_list.FORMS:
        try:
            forms[fid] = slots_of(api.get(f"/pokemon/{slug}"))
        except Exception:
            continue
    return {"defs": sorted(defs, key=lambda d: d["id"]), "species": species, "forms": forms}


def lua_slots(slots: list[tuple[str, int]]) -> str:
    return "{ " + ", ".join(f'{{ "{s}", {c} }}' for s, c in slots) + " }"


def write(data: dict[str, Any], path: Path) -> None:
    lines = [
        "-- Generated by tools/build_abilities.py. Do not edit by hand.",
        "-- defs: abilities newer than Gen 3 that src/abilities.lua gives a real effect (ids are",
        "-- append-only: saved in Pokemon). species/forms: regular ability slots in order, each",
        "-- { PokeAPI slug, Gen 3 fallback id (0 none) }. detail: the full effect (docs/abilities.md).",
        "return {",
        "  defs = {",
    ]
    for d in data["defs"]:
        lines.append(f'    {{ id = {d["id"]}, slug = "{d["slug"]}", key = "{d["key"]}", '
                     f'name = "{d["name"]}", text = "{d["text"]}",\n'
                     f'      detail = "{d["detail"]}" }},')
    lines.append("  },")
    lines.append("  species = {")
    for dex in sorted(data["species"]):
        lines.append(f"    [{dex}] = {lua_slots(data['species'][dex])},")
    lines.append("  },")
    lines.append("  forms = {")
    for fid in sorted(data["forms"]):
        lines.append(f"    {fid} = {lua_slots(data['forms'][fid])},")
    lines.append("  },")
    lines.append("}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--cache", type=Path, default=ROOT / "tools" / ".cache")
    p.add_argument("--out", type=Path, default=ROOT / "data" / "abilities.lua")
    args = p.parse_args()
    data = build(bs.API(args.cache), args.out)
    write(data, args.out)
    impl = {d["slug"] for d in data["defs"]}
    uses = sum(1 for slots in list(data["species"].values()) + list(data["forms"].values())
               for s, _ in slots if s in impl)
    print(f"{len(data['defs'])} abilities, used in {uses} species/form slots -> {args.out}")


if __name__ == "__main__":
    main()
