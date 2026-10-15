#!/usr/bin/env python3
"""New TMs for the newer moves (TM51 on): every move that is a TM in Scarlet/Violet or
Sword/Shield and a real move here (data/moves.lua).

Each TM is an item at index 1100+ (append-only: the index is saved in the player's bag), in
the TM Case, numbered after Gen 3's 50 (TM51...). Which Pokemon can learn it: every species and
form (National #1-1025 and tools/form_list.py's forms) that learns the move as a TM in any
main-series game (PokeAPI "machine"). Price by power: up to 60 and the variable ones 2000 /
3000 (status, up to 90) / 5500 (up to 120) / 7500 (more).

    python tools/build_tms.py           # PokeAPI responses cached in tools/.cache

Writes data/tms.lua. ORDER below is append-only: a new TM goes at the end.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_moves as BM  # noqa: E402
import build_species as BS  # noqa: E402
import form_list  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
FIRST_INDEX = 1100
FIRST_NUMBER = 51
GROUPS = ("scarlet-violet", "sword-shield")

# Append-only (a TM's index and number come from its place here). First built 2026-10-15 from
# every SV/SwSh TM that is a real move here, in Scarlet/Violet's TM order (TM51 is the lowest SV
# number, Fire Fang's TM08), then the Sword/Shield-only ones (their TMs, then their TRs).
ORDER = [
    "FIRE_FANG", "THUNDER_FANG", "ICE_FANG", "ACID_SPRAY", "ACROBATICS", "STRUGGLE_BUG",
    "DISARMING_VOICE", "CHARGE_BEAM", "BULLDOZE", "HEX", "SNARL", "DRAINING_KISS", "FLAME_CHARGE",
    "LOW_SWEEP", "STORED_POWER", "FLING", "DRAGON_TAIL", "VENOSHOCK", "AVALANCHE", "VOLT_SWITCH",
    "SNOWSCAPE", "SMART_STRIKE", "PSYSHOCK", "ZEN_HEADBUTT", "U_TURN", "SHADOW_CLAW", "FOUL_PLAY",
    "PSYCHIC_FANGS", "AIR_SLASH", "SEED_BOMB", "ELECTRO_BALL", "DRAIN_PUNCH", "DAZZLING_GLEAM",
    "GRASS_KNOT", "POISON_JAB", "STOMPING_TANTRUM", "BODY_PRESS", "TOXIC_SPIKES", "FLASH_CANNON",
    "DARK_PULSE", "EERIE_IMPULSE", "IRON_HEAD", "POWER_GEM", "GUNK_SHOT", "X_SCISSOR", "DRILL_RUN",
    "LIQUIDATION", "AURA_SPHERE", "TAILWIND", "DRAGON_PULSE", "STEALTH_ROCK", "ENERGY_BALL",
    "HEAVY_SLAM", "ICE_SPINNER", "PLAY_ROUGH", "POLLEN_PUFF", "EARTH_POWER", "ELECTRIC_TERRAIN",
    "GRASSY_TERRAIN", "PSYCHIC_TERRAIN", "MISTY_TERRAIN", "NASTY_PLOT", "WILD_CHARGE",
    "STONE_EDGE", "PHANTOM_FORCE", "GIGA_IMPACT", "FOCUS_BLAST", "LEAF_STORM", "HURRICANE",
    "TRICK_ROOM", "BUG_BUZZ", "BRAVE_BIRD", "FLARE_BLITZ", "CLOSE_COMBAT", "GRAVITY", "SMACK_DOWN",
    "GYRO_BALL", "BUG_BITE", "VACUUM_WAVE", "LUNGE", "HIGH_HORSEPOWER", "SCALD", "HEAT_CRASH",
    "SOLAR_BLADE", "FLIP_TURN", "DUAL_WINGBEAT", "SCALE_SHOT", "PETAL_BLIZZARD", "ELECTROWEB",
    "SLUDGE_WAVE", "EXPANDING_FORCE", "SKITTER_SMACK", "THROAT_CHOP", "BREAKING_SWIPE", "BRINE",
    "PAYBACK", "ASSURANCE", "POWER_SWAP", "GUARD_SWAP", "SPEED_SWAP", "PSYCHO_CUT", "WONDER_ROOM",
    "MAGIC_ROOM", "CROSS_POISON", "ROUND", "RETALIATE", "RAZOR_SHELL", "TAIL_SLAP",
    "MYSTICAL_FIRE", "BRUTAL_SWING", "POWER_WHIP", "WORK_UP", "VENOM_DRENCH", "DARKEST_LARIAT",
]


# the Bag / TM Case description box: the cart's TM texts are about 19 letters a line, three
# lines on Ruby/Sapphire/Emerald and four on FireRed/LeafGreen
DESC = {"rse": (19, 3), "frlg": (19, 4)}
# hand-written where no official text fits the box
TEXT = {
    "DARK_PULSE": "A horrible aura of ill intent. It may cause flinching.",
    "FLIP_TURN": "Hits, then switches out for a party Pokémon.",
    "U_TURN": "Hits, then switches out for a party Pokémon.",
    "VOLT_SWITCH": "Hits, then switches out for a party Pokémon.",
    "STOMPING_TANTRUM": "Driven by anger. Doubles if the last move failed.",
    "TOXIC_SPIKES": "Lays poison spikes that poison foes switching in.",
}


def item_text(mid: str, move_texts: list[str], api_move: dict, cols: int, rows: int) -> str:
    """TEXT's, else the move's own text (data/moves.lua) re-wrapped to the item box, else an
    official one that fits, else the first sentence of one."""
    cands = ([TEXT[mid]] if mid in TEXT else []) + [t for t in move_texts if t] + BM.flavor_candidates(api_move)
    for t in cands:
        w = BM.wrap(t, cols, rows)
        if w:
            return w
    for t in sorted(cands, key=len):
        w = BM.wrap(re.split(r"(?<!Sp\.)(?<=[.!])\s", t)[0], cols, rows)
        if w:
            return w
    MISSING.append(f"{mid} ({cols}x{rows}): {move_texts[0] if move_texts else ''}")
    return "?"


MISSING: list[str] = []


def price(power) -> int:
    if not power or power <= 60:
        return 2000 if power else 3000
    if power <= 90:
        return 3000
    if power <= 120:
        return 5500
    return 7500


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cache", type=Path, default=ROOT / "tools" / ".cache")
    ap.add_argument("--out", type=Path, default=ROOT / "data" / "tms.lua")
    ap.add_argument("--workers", type=int, default=8)
    a = ap.parse_args()
    api = BS.API(a.cache)

    src = (ROOT / "data/moves.lua").read_text(encoding="utf-8")
    texts = {}
    for m in re.finditer(r'id = "(\w+)".*?frlg = "((?:[^"\\]|\\.)*)",\s*rse = "((?:[^"\\]|\\.)*)"', src, flags=re.S):
        flat = lambda t: re.sub(r"\s+", " ", t.replace("\\n", " ")).replace("POKéMON", "Pokémon").strip()  # noqa: E731
        texts[m.group(1)] = [flat(m.group(2)), flat(m.group(3))]
    rows = {m.group(1): (int(m.group(2)), int(m.group(3)))
            for m in re.finditer(r'id = "(\w+)", index = (\d+), api = (\d+)', src)}
    for mid in ORDER:
        if mid not in rows:
            sys.exit(f"{mid} is not a real move in data/moves.lua")

    with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as ex:
        moves = dict(zip(ORDER, ex.map(lambda m: api.get(f"/move/{rows[m][1]}"), ORDER)))
    missing = [m for m in ORDER if not any(x["version_group"]["name"] in GROUPS for x in moves[m].get("machines", []))]
    if missing:
        print("note: not a SV/SwSh TM any more:", ", ".join(missing))

    def species(dex: int):
        sp = api.get(f"/pokemon-species/{dex}")
        default = next(v for v in sp["varieties"] if v["is_default"])
        return dex, api.get(default["pokemon"]["url"])

    with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as ex:
        pokes = dict(ex.map(species, range(1, 1026)))
        forms = dict(ex.map(lambda f: (f[0], api.get(f"/pokemon/{f[3]}")), form_list.FORMS))

    def learners(pokemon) -> set[int]:
        out = set()
        for m in pokemon["moves"]:
            if any(d["move_learn_method"]["name"] == "machine" for d in m["version_group_details"]):
                out.add(BS.id_from_url(m["move"]["url"]))
        return out

    by_dex = {dex: learners(p) for dex, p in pokes.items()}
    by_form = {fid: learners(p) for fid, p in forms.items()}

    L = [
        "-- Generated by tools/build_tms.py. Do not edit by hand.",
        "-- New TMs (TM51 on) for the newer moves: item index (append-only, saved in the bag), TM",
        "-- number, the move (data/moves.lua id), price, and who can learn it: National numbers and",
        "-- form ids that learn the move as a TM in a main-series game (src/tms.lua).",
        "return {",
    ]
    total = 0
    for i, mid in enumerate(ORDER):
        api_id = rows[mid][1]
        dexes = sorted(d for d, s in by_dex.items() if api_id in s)
        fids = sorted(f for f, s in by_form.items() if api_id in s)
        total += len(dexes) + len(fids)
        number = FIRST_NUMBER + i
        desc = {k: item_text(mid, texts.get(mid, []), moves[mid], c, r).replace("Pokémon", "POKéMON").replace("\n", "\\n")
                for k, (c, r) in DESC.items()}
        L.append(f'  {{ id = "TM{number}", number = {number}, index = {FIRST_INDEX + i}, move = "{mid}", '
                 f'price = {price(moves[mid]["power"])},')
        L.append(f'    frlg = "{desc["frlg"]}", rse = "{desc["rse"]}",')
        L.append("    dex = { " + ", ".join(map(str, dexes)) + " },")
        L.append("    forms = { " + ", ".join(f'"{f}"' for f in fids) + " } },")
    L += ["}", ""]
    if MISSING:
        sys.exit("no text fits the item box (add it to TEXT):\n  " + "\n  ".join(MISSING))
    a.out.write_text("\n".join(L), encoding="utf-8", newline="\n")
    print(f"{len(ORDER)} TMs (TM{FIRST_NUMBER}-TM{FIRST_NUMBER + len(ORDER) - 1}, items "
          f"{FIRST_INDEX}-{FIRST_INDEX + len(ORDER) - 1}), {total} species/form compatibilities -> {a.out}")


if __name__ == "__main__":
    main()
