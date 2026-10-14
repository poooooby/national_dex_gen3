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
    "fluffy": ("FLUFFY", "Halves contact damage."),
    "solid-rock": ("SOLID ROCK", "Dulls super-effective hits."),
    "prism-armor": ("PRISM ARMOR", "Dulls super-effective hits."),
    "filter": ("FILTER", "Dulls super-effective hits."),
    "tinted-lens": ("TINTED LENS", "Boosts resisted moves."),
    "regenerator": ("REGENERATOR", "Recovers HP on switch-out."),
    "snow-warning": ("SNOW WARNING", "Summons hail in battle."),
    "ice-body": ("ICE BODY", "Slight HP recovery in hail."),
    "snow-cloak": ("SNOW CLOAK", "Ups evasion in hail."),
    "justified": ("JUSTIFIED", "Ups ATTACK if hit by DARK."),
    "rattled": ("RATTLED", "Ups SPEED when frightened."),
    "stamina": ("STAMINA", "Ups DEFENSE when hit."),
    "weak-armor": ("WEAK ARMOR", "Hits drop DEF and up SPEED."),
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
    "rivalry": ("RIVALRY", "Stronger vs same gender."),
    "bulletproof": ("BULLETPROOF", "Blocks ball and bomb moves."),
    "sweet-veil": ("SWEET VEIL", "Prevents sleep."),
    "flower-veil": ("FLOWER VEIL", "Guards GRASS types' stats."),
    "protosynthesis": ("PROTOSYNTH.", "Sun ups its best stat."),
    # no effect in a single battle, as in the games where they appear
    "healer": ("HEALER", "May heal a partner's ills."),
    "telepathy": ("TELEPATHY", "Dodges a partner's attacks."),
    "honey-gather": ("HONEY GATHER", "May gather HONEY."),
    "quark-drive": ("QUARK DRIVE", "Electric field ups a stat."),
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
        aid = keep.get(slug)
        if aid is None:
            aid, nxt = nxt, nxt + 1
        defs.append({"id": aid, "slug": slug, "key": bs.engine_id(slug), "name": name, "text": text})
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
        "-- { PokeAPI slug, Gen 3 fallback id (0 none) }.",
        "return {",
        "  defs = {",
    ]
    for d in data["defs"]:
        lines.append(f'    {{ id = {d["id"]}, slug = "{d["slug"]}", key = "{d["key"]}", '
                     f'name = "{d["name"]}", text = "{d["text"]}" }},')
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
