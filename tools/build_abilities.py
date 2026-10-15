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
    "protosynthesis": "In harsh sunlight its highest stat goes up: 1.3x for ATTACK, DEFENSE, SP. ATK or SP. DEF, 1.5x for SPEED. Gen 3 has no Booster Energy, so sunlight is the only trigger.",
    "healer": "No effect here. In the newer games it may cure a battle partner's status problem; this game does not use it, even in double battles.",
    "telepathy": "No effect here. In the newer games it avoids a battle partner's attacks; this game does not use it, even in double battles.",
    "honey-gather": "No effect here. In the newer games it may pick up Honey after battle, an item Gen 3 does not have.",
    "quark-drive": "On Electric Terrain its highest stat goes up: 1.3x for ATTACK, DEFENSE, SP. ATK or SP. DEF, 1.5x for SPEED. Gen 3 has no Booster Energy, so the terrain is the only trigger.",
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
