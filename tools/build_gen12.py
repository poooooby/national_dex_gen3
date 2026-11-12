#!/usr/bin/env python3
"""
Build WoobleDex's Gen 1 / Gen 2 payload (data/gen12/) from PokéAPI and the imported carts.

Red/Blue/Yellow have species #1-151 and moves #1-165; Gold/Silver/Crystal #1-251 and
#1-251. Everything past that comes from here, generation-neutral, and src/gen12/ shapes it
for the running game:

  species/NNN.lua   #152-1025: modern typing (Fairy, and Dark/Steel on Gen 1), stats, growth,
                    breeding, the Pokédex entry reflowed for the Gen 1/2 box (18 columns,
                    3 lines, 2 pages; kinds and names at most 10 characters), the evolutions,
                    and the moves by NATIONAL move number: the newest level-up list in full,
                    the moves #1-251 any game teaches it by machine or tutor, its egg moves.
                    `proxy` is the cart species (per generation) whose party icon and cry it
                    borrows when no art or cry mod supplies one.
  forms.lua         the 128 forms of tools/form_list.py, same shape (+ baseSpecies, form, baseDex).
  crossgen.lua      evolutions FROM a species #1-251 into a newer one (Eevee -> Espeon on Red,
                    Onix -> Steelix, Eevee -> Leafeon on Gold, ...); the mod keeps the ones
                    whose source is in the running cart and whose target is not.
  moves.lua         each move number past #165 that some list names: modern type / power /
                    accuracy / pp / priority, and per generation either the cart effect it runs
                    on (`gen1`, `gen2`: a real move there) or a ranked list of the cart moves that
                    stand in for it (`subs`, the closest first; the mod takes the first one the
                    species does not already learn, as tools/build_species.py does for Gen 3).
  cart.lua          the cart's own species and moves whose modern typing differs (retyped there).

The effect a newer move runs on comes from its Gen 3 effect (the cart move table, and
data/moves.lua for #355+, rules and extras left out): a cart move with that same Gen 3 effect
is looked up in Red / Gold, and its effect there is the one used (with the Gen 3 chance; on
Red the variant whose chance is closest). No such cart move: the newer move is substituted.

Usage (needs the carts imported under the gen1recomp checkout and luajit on PATH):
    python tools/build_gen12.py
    python tools/build_gen12.py --engine ../gen1recomp --cache tools/.cache
"""

from __future__ import annotations

import argparse
import collections
import concurrent.futures
import json
import re
import subprocess
from pathlib import Path
from typing import Any

import build_species as bs
import form_list
import move_map

ROOT = Path(__file__).resolve().parent.parent
FIRST_DEX, LAST_DEX = 152, 1025
SHARD_SIZE = 80
SUBS = 8                       # ranked stand-ins kept per newer move and generation

GENS = {
    1: {"cart": "red", "dex": 151, "moves": 165},
    2: {"cart": "gold", "dex": 251, "moves": 251},
}

COLUMNS, LINES, PAGES = 18, 3, 2      # the Gen 1/2 Pokédex text box
NAME_MAX = 10

# Species names over 10 characters (NAME_MAX), shortened by hand. National Dex number -> name.
NAMES = {
    662: "FLETCHINDR", 740: "CRABOMINBL", 806: "BLACEPHALN", 822: "CORVISQUIR",
    823: "CORVKNIGHT", 847: "BARRASKWDA", 851: "CENTSKORCH", 855: "POLTEGEIST",
    874: "STONJORNER", 902: "BASCULGION", 908: "MEOWSCARDA", 931: "SQUAWKBILY",
    941: "KILOWATREL", 947: "BRMBLGHAST", 982: "DUDNSPARCE", 985: "SCREAMTAIL",
    986: "BRUTBONNET", 987: "FLUTTRMANE", 988: "SLTHERWING", 989: "SANDYSHOCK",
    990: "IRONTREADS", 991: "IRONBUNDLE", 993: "IRONJUGULS", 995: "IRONTHORNS",
    1005: "ROARNGMOON", 1006: "IRONVALINT", 1009: "WALKNGWAKE", 1010: "IRONLEAVES",
    1012: "POLCHGEIST", 1016: "FEZANDIPTI", 1020: "GOUGNGFIRE", 1021: "RAGINGBOLT",
    1022: "IRONBOULDR",
}

# Pokédex kinds over 10 characters with the space dropped still too long, shortened by hand
# (a two-word kind that fits without its space is written that way: SANDCASTLE, LANDSPIRIT).
KINDS = {
    "APPLE NECTAR": "APPLE SAP", "BASH BUFFALO": "BUFFALO", "BLAST TURTLE": "BLASTTURTL",
    "BLOOM SICKLE": "BLOOMSCKLE", "BONE VULTURE": "VULTURE", "COTTON BLOOM": "COTTONBLOM",
    "COTTON CANDY": "COTTNCANDY", "CRYSTALLIZING": "CRYSTALIZE", "DESTRUCTION": "DESTROYER",
    "ELECTRIFIED": "ELECTRIFY", "ELESQUIRREL": "ELESQUIRRL", "FANG SCORPION": "FANGSCORPN",
    "FIRE WARRIOR": "FIREWARIOR", "FLY SCORPION": "FLYSCORPIN", "FRIGATEBIRD": "FRIGATE",
    "GLOOMDWELLER": "GLOOMDWELR", "GRASSHOPPER": "HOPPER", "HEAVYWEIGHT": "HEAVYWEGHT",
    "ILLUMINATING": "GLOWING", "ILLUSION FOX": "ILLUSONFOX", "INTERTWINING": "ENTWINING",
    "INTIMIDATION": "INTIMIDATE", "MEGA FIRE PIG": "MEGAFIRPIG", "MULTIPLYING": "MULTIPLY",
    "OGRE SCORPION": "OGRESCORPN", "OVERTURNING": "OVERTURN", "PROTOTURTLE": "PROTOTURTL",
    "SCATTERDUST": "SCATTERDST", "SEA CUCUMBER": "SEACUCUMBR", "SECRET AGENT": "AGENT",
    "SICKLE GRASS": "SICKLEGRAS", "SINGLE BLOOM": "ONE BLOOM", "SKY SQUIRREL": "SKYSQUIRRL",
    "SPICY PEPPER": "PEPPER", "STORM PETREL": "PETREL", "SUBJUGATION": "SUBJUGATOR",
    "SYNCHRONIZE": "SYNCHRO", "THUNDERBOLT": "THUNDERBLT", "THUNDERCLAP": "THUNDERCLP",
    "TINY RACCOON": "RACCOON", "TINY SWALLOW": "SWALLOW", "TOXIC LIZARD": "TOXICLIZRD",
    "WATER BUBBLE": "BUBBLE", "WATER LIZARD": "WATERLIZRD", "BIG-HEARTED": "BIGHEARTED",
    "LEAF-WRAPPED": "LEAFWRAPPD", "PITCH-BLACK": "PITCHBLACK", "THORN MONKEY": "THORNMONKY",
    "GRASS MONKEY": "GRASSMONKY", "TOXIC MONKEY": "TOXICMONKY", "ROGUE MONKEY": "ROGUEMONKY",
    "MARTIAL ARTS": "MARTIALART",
}

EGG_GROUPS = {
    "monster": "EGG_MONSTER", "water1": "EGG_WATER_1", "bug": "EGG_BUG", "flying": "EGG_FLYING",
    "ground": "EGG_GROUND", "fairy": "EGG_FAIRY", "plant": "EGG_PLANT",
    "humanshape": "EGG_HUMANSHAPE", "water3": "EGG_WATER_3", "mineral": "EGG_MINERAL",
    "indeterminate": "EGG_INDETERMINATE", "water2": "EGG_WATER_2", "ditto": "EGG_DITTO",
    "dragon": "EGG_DRAGON", "no-eggs": "EGG_NONE",
}

# Evolutions PokéAPI gives a condition tools/build_species.py leaves out, that Gen 1/2 need:
# Tyrogue (a Gold species, new on Red) by its Attack vs Defense, and Wurmple's two
# cocoons, one each by a stable 1-in-2 pick.
EXTRA_EVOLUTIONS = {
    236: [{"method": "EVO_STAT", "level": 20, "comparison": "ATK_GT_DEF", "target": 106},
          {"method": "EVO_STAT", "level": 20, "comparison": "ATK_LT_DEF", "target": 107},
          {"method": "EVO_STAT", "level": 20, "comparison": "ATK_EQ_DEF", "target": 237}],
    265: [{"method": "EVO_LEVEL", "level": 7, "target": 266, "when": {"pick": [0, 2]}},
          {"method": "EVO_LEVEL", "level": 7, "target": 268, "when": {"pick": [1, 2]}}],
}

# tools/form_list.py's CONDITIONAL_CROSSGEN names, for "knows", a Gen 3 move the cart's
# species can learn there (Rock Tomb for Rollout ...). Gen 1/2 get the real move.
REAL_KNOWS = {463: [205], 473: [246], 465: [246], 469: [246], 424: [458], 981: [888], 982: [887]}

# A cart effect whose damage or behaviour hangs on the move's own id: never lent to a new move.
EFFECT_DENY = {"SPECIAL_DAMAGE_EFFECT", "EFFECT_STATIC_DAMAGE"}

# Gen 2 move order keys off the effect (src/battle/gen2/Battle.lua Battle.PRIORITY): a newer move
# runs on an effect only if that gives it the same sign of priority it has.
GEN2_PRIORITY = {"EFFECT_PRIORITY_HIT": 1, "EFFECT_PROTECT": 3, "EFFECT_ENDURE": 3,
                 "EFFECT_COUNTER": -1, "EFFECT_MIRROR_COAT": -1, "EFFECT_FORCE_SWITCH": -1}

GEN3_HIGH_CRITICAL = 43        # Gen 3's EFFECT_HIGH_CRITICAL: a plain hit with the crit flag

# Never a stand-in, beside tools/move_map.py's EXCLUDED: a copy move, and a signature sleep
# move that would turn every Dark status move into a 50% sleep.
STAND_IN_EXCLUDED = {"COPYCAT", "DARK VOID"}


def sign(x: int) -> int:
    return (x > 0) - (x < 0)


# ---------------------------------------------------------------- carts

def lua_json_file(path: Path) -> Any:
    out = subprocess.run(["luajit", str(ROOT / "tools" / "gen12_cart.lua"), "--lua", str(path)],
                         capture_output=True, text=True, encoding="utf-8", check=True)
    return json.loads(out.stdout)


def lua_json(engine: Path, *args: str) -> Any:
    out = subprocess.run(["luajit", str(ROOT / "tools" / "gen12_cart.lua"), *args],
                         cwd=engine, capture_output=True, text=True, encoding="utf-8", check=True)
    return json.loads(out.stdout)


def type_name(t: str) -> str:
    return {"PSYCHIC_TYPE": "PSYCHIC"}.get(t, t)


def load_carts(engine: Path) -> dict[int, dict[str, Any]]:
    carts = {}
    for gen, g in GENS.items():
        raw = lua_json(engine, f"{g['cart']}/data/generated")
        carts[gen] = {
            "moves": {m["n"]: m for m in raw["moves"]},
            "species": {s["dex"]: s for s in raw["species"]},
            "icons": {int(k): v for k, v in raw["icons"].items()},
            "matchups": [tuple(row) for row in raw["matchups"]],
            "items": raw["items"],
        }
    return carts


# ---------------------------------------------------------------- Pokédex text

def kind_for(genus: str) -> str:
    kind = re.sub(r"\s*Pok[eé]mon$", "", genus).upper()
    if len(kind) <= NAME_MAX:
        return kind
    if kind in KINDS:
        return KINDS[kind]
    joined = re.sub(r"[ -]", "", kind)
    if len(joined) <= NAME_MAX:
        return joined
    raise SystemExit(f"kind {kind!r} is over {NAME_MAX} characters: add it to KINDS")


def wrap(text: str) -> list[str]:
    """18-column lines; a word longer than a line breaks after a hyphen, else anywhere."""
    words = []
    for word in text.split(" "):
        while len(word) > COLUMNS:
            cut = word.rfind("-", 0, COLUMNS) + 1 or COLUMNS
            words.append(word[:cut])
            word = word[cut:]
        words.append(word)
    lines, line = [], ""
    for word in words:
        if line and len(line) + (0 if line.endswith("-") else 1) + len(word) > COLUMNS:
            lines.append(line)
            line = word
        else:
            line = line + word if line.endswith("-") else f"{line} {word}".strip()
    return lines + ([line] if line else [])


def dex_pages(species: dict[str, Any]) -> list[str]:
    """The Pokédex text as up to two pages of three 18-column lines (newline-joined): the newest
    English entry that fits (tools/build_species.py's FLAVOR_VERSIONS order), else the shortest
    one cut at a sentence end."""
    found = {}
    for entry in species.get("flavor_text_entries", []):
        if entry.get("language", {}).get("name") == "en":
            found[entry["version"]["name"]] = bs._flavor_clean(entry["flavor_text"])
    if not found:
        return [""]
    room = LINES * PAGES
    order = [v for v in bs.FLAVOR_VERSIONS if v in found] + [v for v in found if v not in bs.FLAVOR_VERSIONS]
    lines = next((wrap(found[v]) for v in order if len(wrap(found[v])) <= room), None)
    if lines is None:
        text = min(found.values(), key=len)
        while len(wrap(text)) > room:
            cut = text.rfind(". ", 0, len(text) - 2)
            if cut < 0:
                text = " ".join(wrap(text)[:room])
                break
            text = text[:cut + 1]
        lines = wrap(text)[:room]
    return ["\n".join(lines[i:i + LINES]) for i in range(0, len(lines), LINES)]


def display_name(species: dict[str, Any], dex: int) -> str:
    name = (bs.english(species.get("names", []), "name") or species["name"]).upper()
    name = name.replace("É", "é")
    if dex in NAMES:
        return NAMES[dex]
    if len(name) > NAME_MAX:
        raise SystemExit(f"#{dex} {name} is over {NAME_MAX} characters: add it to NAMES")
    return name


# ---------------------------------------------------------------- moves of a species

def modern_types(pokemon: dict[str, Any]) -> list[str]:
    return [t["type"]["name"].upper() for t in sorted(pokemon["types"], key=lambda t: t["slot"])]


def taught(pokemon: dict[str, Any]) -> list[int]:
    """Moves #1-251 (the only ones a Gen 1/2 TM, HM or tutor teaches) any game teaches it."""
    found = set()
    for move in pokemon["moves"]:
        mid = bs.id_from_url(move["move"]["url"])
        if mid <= 251 and any(d["move_learn_method"]["name"] in ("machine", "tutor")
                              for d in move["version_group_details"]):
            found.add(mid)
    return sorted(found)


def egg(pokemon: dict[str, Any]) -> list[int]:
    found = set()
    for move in pokemon["moves"]:
        if any(d["move_learn_method"]["name"] == "egg" for d in move["version_group_details"]):
            found.add(bs.id_from_url(move["move"]["url"]))
    return sorted(found)


# ---------------------------------------------------------------- evolutions

def gen3_move_numbers() -> dict[int, int]:
    """This mod's Gen 3 move index (355+) -> National move number, for `knows` lists."""
    return {index: api for api, index in bs.real_moves().items()}


def national_knows(steps: list[dict[str, Any]], index_to_api: dict[int, int]) -> list[dict[str, Any]]:
    out = []
    for step in steps:
        step = json.loads(json.dumps(step))
        when = step.get("when")
        if when and "knows" in when:
            when["knows"] = [index_to_api.get(m, m) for m in when["knows"]]
        out.append(step)
    return out


# ---------------------------------------------------------------- the build

def fetch_all(api: bs.API, workers: int) -> list[dict[str, Any]]:
    def fetch(dex: int) -> dict[str, Any]:
        species = api.get(f"/pokemon-species/{dex}")
        default = next(v for v in species["varieties"] if v["is_default"])
        pokemon = api.get(default["pokemon"]["url"])
        chain = api.get(species["evolution_chain"]["url"]) if species.get("evolution_chain") else None
        return {"dex": dex, "species": species, "pokemon": pokemon, "chain": chain}

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
        return list(ex.map(fetch, range(1, LAST_DEX + 1)))


def chain_graph(fetched: list[dict[str, Any]]) -> dict[int, set[int]]:
    """dex -> the dex numbers one evolution step away (either direction)."""
    graph: dict[int, set[int]] = collections.defaultdict(set)

    def walk(node: dict[str, Any]) -> None:
        src = bs.id_from_url(node["species"]["url"])
        graph[src]
        for child in node["evolves_to"]:
            dst = bs.id_from_url(child["species"]["url"])
            graph[src].add(dst)
            graph[dst].add(src)
            walk(child)

    seen = set()
    for item in fetched:
        chain = item["chain"]
        if chain and chain["id"] not in seen:
            seen.add(chain["id"])
            walk(chain["chain"])
    return graph


def stat_total(pokemon: dict[str, Any]) -> int:
    return sum(s["base_stat"] for s in pokemon["stats"])


def pick_proxy(dex: int, by_dex: dict[int, dict[str, Any]], graph: dict[int, set[int]],
               cart_max: int) -> int:
    """The cart species a newer one borrows its party icon and cry from: the nearest relative
    in its evolution family the cart has, else one of the same body shape and type."""
    frontier, seen = [dex], {dex}
    while frontier:
        near = sorted(d for d in frontier if d <= cart_max and d != dex)
        if near:
            return near[0]
        frontier = sorted({n for d in frontier for n in graph.get(d, ()) if n not in seen})
        seen.update(frontier)
    me = by_dex[dex]
    shape = (me["species"].get("shape") or {}).get("name")
    types = modern_types(me["pokemon"])
    total = stat_total(me["pokemon"])

    def score(c: int) -> tuple:
        other = by_dex[c]
        ctypes = modern_types(other["pokemon"])
        return ((other["species"].get("shape") or {}).get("name") != shape,
                ctypes[0] != types[0], not set(ctypes) & set(types),
                abs(stat_total(other["pokemon"]) - total), c)

    return min(range(1, cart_max + 1), key=score)


def species_record(item: dict[str, Any], pokemon: dict[str, Any], evolutions: list[dict[str, Any]],
                   proxies: dict[str, str], by_dex: dict[int, dict[str, Any]]) -> dict[str, Any]:
    species, dex = item["species"], item["dex"]
    stats = {s["stat"]["name"]: s["base_stat"] for s in pokemon["stats"]}
    name = display_name(species, dex)
    full = (bs.english(species.get("names", []), "name") or species["name"]).upper()
    rec: dict[str, Any] = {
        "id": bs.engine_id(species["name"]),
        "name": name,
    }
    if full.replace("É", "é") != name:
        rec["fullName"] = full
    rec.update({
        "dex": dex,
        "slot": dex + bs.SLOT_OFFSET,
        "types": modern_types(pokemon),
        "baseStats": {
            "hp": stats["hp"], "attack": stats["attack"], "defense": stats["defense"],
            "speed": stats["speed"], "specialAttack": stats["special-attack"],
            "specialDefense": stats["special-defense"],
        },
        "catchRate": species.get("capture_rate") or 45,
        "baseExp": min(255, pokemon.get("base_experience") or 64),
        "growthRate": bs.GROWTH_RATES.get(species["growth_rate"]["name"], "MEDIUM_FAST"),
        "genderRatio": bs.gender_ratio(species.get("gender_rate")),
        "eggCycles": min(255, species.get("hatch_counter") or 20),
        "eggGroups": [EGG_GROUPS[g["name"]] for g in species.get("egg_groups", [])] or ["EGG_NONE"],
        "friendship": min(255, species["base_happiness"] if species.get("base_happiness") is not None else 70),
        "legendary": bool(species.get("is_legendary")),
        "mythical": bool(species.get("is_mythical")),
        "learnset": [list(r) for r in bs.modern_learnset(pokemon)],
        "teach": taught(pokemon),
        "eggMoves": egg(pokemon),
        "evolutions": evolutions,
        "dexEntry": {
            "kind": kind_for(bs.english(species.get("genera", []), "genus") or ""),
            "height": pokemon.get("height") or 0,      # decimetres
            "weight": pokemon.get("weight") or 0,      # hectograms
            "text": dex_pages(species),
        },
        "proxy": proxies,
    })
    return rec


def build(api: bs.API, workers: int, engine: Path) -> dict[str, Any]:
    carts = load_carts(engine)
    fetched = fetch_all(api, workers)
    by_dex = {item["dex"]: item for item in fetched}
    graph = chain_graph(fetched)
    index_to_api = gen3_move_numbers()

    steps: dict[int, list[dict[str, Any]]] = {}
    for item in fetched:
        if item["chain"]:
            for source, rows in bs.evolution_steps(item["chain"]).items():
                steps.setdefault(source, rows)

    def conditional_crossgen() -> list[dict[str, Any]]:
        out = []
        for step in form_list.CONDITIONAL_CROSSGEN:
            step = dict(step)
            if step["target"] in REAL_KNOWS and "when" in step and "knows" in step["when"]:
                step["when"] = dict(step["when"], knows=REAL_KNOWS[step["target"]])
            out.append(step)
        return out

    def evolutions_of(dex: int) -> list[dict[str, Any]]:
        rows = list(EXTRA_EVOLUTIONS.get(dex) or form_list.CONDITIONAL_EVOLUTIONS.get(dex)
                    or steps.get(dex, []))
        # a Gold species is new on Red: its conditional steps into newer species (Sneasel ->
        # Weavile) are its own there, beside crossgen.lua's copy for Gold
        rows += [{k: v for k, v in step.items() if k != "source"}
                 for step in conditional_crossgen() if step["source"] == dex]
        return national_knows(rows, index_to_api)

    def proxies_for(dex: int, every: bool = False) -> dict[str, str]:
        """gen key -> the cart's own id (Gold spells some its way: FARFETCH_D, MR__MIME) of the
        species a newer one borrows from; `every` also for a species the cart has (a form's base)."""
        return {f"gen{g}": carts[g]["species"][dex if dex <= c["dex"] else
                                             pick_proxy(dex, by_dex, graph, c["dex"])]["id"]
                for g, c in GENS.items() if every or dex > c["dex"]}

    records = [species_record(by_dex[d], by_dex[d]["pokemon"], evolutions_of(d), proxies_for(d), by_dex)
               for d in range(FIRST_DEX, LAST_DEX + 1)]

    # evolutions FROM the cart species (#1-251) into newer ones
    crossgen = [dict(step, source=src) for src, rows in sorted(steps.items()) if src <= 251
                for step in rows if step["target"] >= FIRST_DEX and src not in EXTRA_EVOLUTIONS]
    crossgen = national_knows(crossgen + conditional_crossgen(), index_to_api)

    forms = []
    for item in bs.fetch_forms(api, fetched, workers):
        evos: list[dict[str, Any]] = []
        for src, dst, method, arg in form_list.FORM_EVOLUTIONS:
            if src != item["id"]:
                continue
            step: dict[str, Any] = {"method": method, "targetForm": dst}
            if method == "EVO_LEVEL":
                step["level"] = arg
            elif method == "EVO_ITEM":
                step["item"] = arg
            evos.append(step)
        evos += form_list.FORM_CONDITIONAL_EVOLUTIONS.get(item["id"], [])
        rec = species_record({"species": item["species"], "dex": item["dex"]}, item["pokemon"],
                             national_knows(evos, index_to_api), proxies_for(item["dex"], True), by_dex)
        rec.update({"id": item["id"], "slot": item["slot"], "baseSpecies": item["base"],
                    "form": item["form"], "baseDex": item["dex"]})
        rec["weight"] = rec["dexEntry"]["weight"]
        del rec["dexEntry"]
        forms.append(rec)

    moves, report = build_moves(api, workers, carts, records + forms, engine)
    cart = cart_retypes(api, carts, by_dex)
    items = build_items(api, carts, records + forms, crossgen)
    # each species' party icon on each game: its proxy's (Red an icon kind, Gold an ICON_ sheet)
    for g in GENS:
        dex_of = {s["id"]: dex for dex, s in carts[g]["species"].items()}
        for r in records + forms:
            proxy = r["proxy"].get(f"gen{g}")
            kind = proxy and carts[g]["icons"].get(dex_of.get(proxy))
            if kind:
                r.setdefault("icon", {})[f"gen{g}"] = kind
    return {"records": records, "forms": forms, "crossgen": crossgen, "moves": moves,
            "cart": cart, "items": items, "report": report}


# ---------------------------------------------------------------- evolution items

# Names past the carts' 12 columns
ITEM_NAMES = {
    "auspicious-armor": "AUSPCS ARMOR", "malicious-armor": "MALCS ARMOR",
    "masterpiece-teacup": "MASTER CUP", "unremarkable-teacup": "PLAIN CUP",
    "scroll-of-darkness": "DARK SCROLL", "scroll-of-waters": "WATER SCROLL",
    "strawberry-sweet": "STRAWBRY SWT", "galarica-cuff": "GALARICACUFF",
    "galarica-wreath": "GALARICA WRT", "black-augurite": "BLK AUGURITE",
    "deep-sea-scale": "DEEPSEASCALE", "deep-sea-tooth": "DEEPSEATOOTH",
    "up-grade": "UP-GRADE", "leaders-crest": "LEADERS CRST", "thunder-stone": "THUNDERSTONE", "whipped-dream": "WHIPPEDDREAM",
}
ITEM_NAME_MAX = 12
DEFAULT_PRICE = 2100            # what the Gen 3 path charges for a stone


def normalize(s: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", s.upper().replace("É", "E"))


def build_items(api: bs.API, carts: dict[int, dict[str, Any]], records: list[dict[str, Any]],
                crossgen: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Every item an evolution names (`item`: a stone, or a trade item) or wants held
    (`when.hold`): its engine id, a name that fits, a price, how it is used (stone: used on
    the Pokemon; trade: held through a trade; hold: held while it levels up) and, per
    generation, the cart's own id when that cart already has it."""
    kinds: dict[str, str] = {}
    steps = [s for r in records for s in r["evolutions"]] + crossgen
    for step in steps:
        if step.get("item"):
            kinds.setdefault(step["item"], "trade" if step["method"] == "EVO_TRADE_ITEM" else "stone")
        hold = (step.get("when") or {}).get("hold")
        for slug in ([hold] if isinstance(hold, str) else hold or []):
            kinds.setdefault(slug, "hold")
    gen3 = {row["slug"]: row for row in lua_json_file(ROOT / "data" / "items.lua")}
    out, too_long = [], []
    for slug in sorted(kinds):
        a = api.get(f"/item/{slug}")
        mine = gen3.get(slug)
        name = ITEM_NAMES.get(slug) or (mine and mine["name"]) or (bs.english(a.get("names", []), "name") or slug).upper()
        name = name.replace("’", "'")
        if len(name) > ITEM_NAME_MAX:
            too_long.append(f"{slug}: {name}")
        price = (mine and mine.get("price")) or a.get("cost") or DEFAULT_PRICE
        row = {"slug": slug, "id": bs.engine_id(slug), "name": name, "price": price,
               "kind": kinds[slug], "carts": {}}
        for gen in GENS:
            for it in carts[gen]["items"]:
                if normalize(it["id"]) == normalize(slug) or normalize(it["name"]) == normalize(slug):
                    row["carts"][f"gen{gen}"] = it["id"]
                    break
        out.append(row)
    if too_long:
        raise SystemExit("item names past 12 columns (add them to ITEM_NAMES): " + ", ".join(too_long))
    return out


# ---------------------------------------------------------------- moves

def gen3_effects(engine: Path) -> tuple[dict[int, dict[str, Any]], dict[int, dict[str, Any]]]:
    """(FireRed's move table #1-354, this mod's Gen 3 real moves #355+ by National number)."""
    fr = move_map.parse_cart(engine / "firered" / "data" / "generated" / "gba" / "pokemon")
    real = {}
    for row in lua_json(engine, "--lua", str(ROOT / "data" / "moves.lua")):
        if row.get("rule") or row.get("extra"):
            continue          # runs on this mod's own Gen 3 code: nothing on Gen 1/2 to lend
        real[row["api"]] = row
    return fr, real


def gen3_looks(engine: Path) -> dict[int, int]:
    """National move number -> the cart move whose animation the Gen 3 path borrows for it
    (data/anims.lua `looks` first, then data/moves.lua `look`, as src/anims.lua resolves them)."""
    rows = lua_json(engine, "--lua", str(ROOT / "data" / "moves.lua"))
    looks = lua_json(engine, "--lua", str(ROOT / "data" / "anims.lua")).get("looks", {})
    out = {}
    for row in rows:
        look = looks.get(row["id"], row.get("look"))
        if look:
            out[row["api"]] = look
    return out


def cart_effect(gen: int, e3: int, chance: int, fr: dict[int, dict[str, Any]],
                cart_moves: dict[int, dict[str, Any]]) -> str | None:
    """The effect, on that generation's cart, of its moves that run on Gen 3 effect e3: the most
    common one (Gold), or the one whose chance is closest (Red, whose variants are by chance)."""
    reps = [n for n, m in fr.items() if m.get("effect") == e3 and n in cart_moves]
    if not reps:
        return None
    # the family most of those moves run on (Red's variants by chance -- PARALYZE_SIDE_EFFECT1
    # at 10%, ..._2 at 30% -- are one family), then the variant whose Gen 3 chance is closest.
    # Majority first: a move whose effect changed since (Dizzy Punch confuses from Gen 3 on,
    # not on Red) must not decide for the others.
    family = lambda n: re.sub(r"\d+$", "", cart_moves[n]["effect"])
    count = collections.Counter(family(n) for n in reps)
    top = max(count, key=lambda e: (count[e], e != "NO_ADDITIONAL_EFFECT", e))
    best = min((n for n in reps if family(n) == top),
               key=lambda n: (abs(fr[n].get("secondaryChance", 0) - chance), n))
    effect = cart_moves[best]["effect"]
    return None if effect in EFFECT_DENY else effect


def build_moves(api: bs.API, workers: int, carts: dict[int, dict[str, Any]],
                records: list[dict[str, Any]], engine: Path) -> tuple[list[dict[str, Any]], str]:
    used = set()
    for r in records:
        used.update(m for _, m in r["learnset"])
        used.update(r["eggMoves"])
        used.update(r["teach"])
        for step in r["evolutions"]:
            used.update((step.get("when") or {}).get("knows", []))
    wanted = sorted(n for n in used if n > GENS[1]["moves"])
    ids = sorted(set(range(1, 252)) | set(wanted))
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
        api_moves = dict(zip(ids, ex.map(lambda i: api.get(f"/move/{i}"), ids)))
    fr, real3 = gen3_effects(engine)

    gold = carts[2]["moves"]
    out = []
    for n in wanted:
        a = api_moves[n]
        damaging = a["damage_class"]["name"] != "status"
        if n <= 251:
            m = gold[n]
            rec = {"n": n, "id": m["id"], "name": m["name"]}
        elif n <= 354:
            rec = {"n": n, "id": bs.engine_id(a["name"]), "name": fr[n]["name"]}
        elif n in real3:
            rec = {"n": n, "id": real3[n]["id"], "name": real3[n]["name"]}
        else:
            # no Gen 3 effect to lend it: a stand-in everywhere, so the name is never shown
            rec = {"n": n, "id": bs.engine_id(a["name"]), "name": a_name(a).upper()[:12]}
        rec.update({"type": a["type"]["name"].upper(), "power": a.get("power") or 0,
                    "accuracy": a.get("accuracy") or (100 if damaging else 0), "pp": a.get("pp") or 10,
                    "priority": a.get("priority") or 0})
        # the move's Gen 3 effect and chance, where Gen 3 has one
        e3 = chance = None
        if n <= 354:
            e3, chance = fr[n]["effect"], fr[n].get("secondaryChance", 0)
        elif n in real3:
            e3, chance = real3[n]["effect"], real3[n].get("secondaryChance", 0)
        if e3 == GEN3_HIGH_CRITICAL:
            rec["highCrit"] = True
        usable = e3 is not None and not (damaging and not a.get("power"))
        for gen, g in GENS.items():
            if n <= g["moves"]:
                continue                       # the cart's own move there
            effect = None
            if usable:
                effect = cart_effect(gen, 0 if e3 == GEN3_HIGH_CRITICAL else e3, chance or 0, fr,
                                     carts[gen]["moves"])
                if effect == "EFFECT_NORMAL_HIT" and gen == 2 and rec["priority"] > 0:
                    effect = "EFFECT_PRIORITY_HIT"      # Bullet Punch, Aqua Jet: Quick Attack's
                if effect and gen == 2 and sign(GEN2_PRIORITY.get(effect, 0)) != sign(rec["priority"]):
                    effect = None
            if effect:
                row = {"effect": effect}
                if gen == 2 and chance:
                    row["chance"] = chance
                rec[f"gen{gen}"] = row
        out.append(rec)

    # stand-ins: the closest move the game has -- its cart's own, or a newer one that runs
    # natively there (on Red, Steel Wing falls to Iron Head, not to a Normal move)
    by_n = {r["n"]: r for r in out}
    for gen, g in GENS.items():
        pool = {}
        for n, m in carts[gen]["moves"].items():
            pool[n] = {"name": m["name"], "power": m["power"], "accuracy": m["accuracy"],
                       "pp": m["pp"], "priority": api_moves[n].get("priority") or 0,
                       "type": move_map._api_type(api_moves[n], fairy=True)}
        for r in out:
            if f"gen{gen}" in r:
                pool[r["n"]] = {"name": r["name"], "power": r["power"], "accuracy": r["accuracy"],
                                "pp": r["pp"], "priority": r["priority"],
                                "type": move_map._api_type(api_moves[r["n"]], fairy=True)}
        pool = {n: m for n, m in pool.items() if m["name"] not in STAND_IN_EXCLUDED}
        mapper = move_map.MoveMapper(pool, api_moves, max(pool), fairy=True)
        for r in out:
            if r["n"] > g["moves"] and f"gen{gen}" not in r:
                r.setdefault("subs", {})[f"gen{gen}"] = mapper.ranked(r["n"])[:SUBS]

    # the look: the cart move whose battle animation (and, on Red, sound) a real move borrows.
    # The Gen 3 path's pick where that cart has it (cart moves chosen by animation-script
    # similarity), else the closest cart move by type, class and power.
    looks3 = gen3_looks(engine)
    for gen, g in GENS.items():
        cart = carts[gen]["moves"]
        pool = {n: {"name": m["name"], "power": m["power"], "accuracy": m["accuracy"], "pp": m["pp"],
                    "priority": api_moves[n].get("priority") or 0,
                    "type": move_map._api_type(api_moves[n], fairy=True)} for n, m in cart.items()}
        mapper = move_map.MoveMapper(pool, api_moves, max(pool), fairy=True)
        for r in out:
            if f"gen{gen}" in r:
                look = looks3.get(r["n"])
                if look not in cart:
                    look = mapper.ranked(r["n"])[0]
                r.setdefault("look", {})[f"gen{gen}"] = cart[look]["id"]

    # the report: what each generation runs as a real move, and what stands in for the rest
    lines = []
    for gen in GENS:
        real = [r for r in out if f"gen{gen}" in r]
        subbed = [r for r in out if f"gen{gen}" in r.get("subs", {})]
        lines.append(f"Gen {gen}: {len(real)} newer moves run on a cart effect, {len(subbed)} stand-ins")
    for gen in GENS:
        lines += ["", f"GEN {gen} REAL MOVES:"]
        lines += [f"  #{r['n']} {r['name']} ({r['type']}) -> {r[f'gen{gen}']['effect']}"
                  for r in out if f"gen{gen}" in r]
        lines += ["", f"GEN {gen} STAND-INS (best three; * = a newer move that runs natively there):"]
        cart = carts[gen]["moves"]
        name = lambda c: cart[c]["name"] if c in cart else by_n[c]["name"] + "*"
        lines += [f"  #{r['n']} {a_name(api_moves[r['n']])} ({r['type']}) -> "
                  + ", ".join(name(c) for c in r["subs"][f"gen{gen}"][:3])
                  for r in out if f"gen{gen}" in r.get("subs", {})]
    return out, "\n".join(lines) + "\n"


def a_name(move: dict[str, Any]) -> str:
    return bs.english(move.get("names", []), "name") or move["name"]


def cart_retypes(api: bs.API, carts: dict[int, dict[str, Any]],
                 by_dex: dict[int, dict[str, Any]]) -> dict[str, Any]:
    """The cart's own species and moves whose modern typing differs from the cart's."""
    out: dict[str, Any] = {}
    for gen in GENS:
        species, moves = {}, {}
        for dex, s in carts[gen]["species"].items():
            modern = modern_types(by_dex[dex]["pokemon"])
            if set(modern) != {type_name(t) for t in s["types"]}:
                species[s["id"]] = modern
        for n, m in carts[gen]["moves"].items():
            modern = api.get(f"/move/{n}")["type"]["name"].upper()
            if m["type"] == "CURSE_TYPE" or modern == "SHADOW":
                continue
            if modern != type_name(m["type"]):
                moves[m["id"]] = modern
        out[f"gen{gen}"] = {"species": species, "moves": moves, **chart_changes(api, carts, gen)}
    return out


# Types each game lacks: Red has neither Dark nor Steel, and no cart has Fairy.
NEW_TYPES = {1: ["DARK", "STEEL", "FAIRY"], 2: ["FAIRY"]}
MODERN_TYPES = ("dark", "steel", "fairy")      # every row that touches one is today's chart
RELATIONS = (("double_damage_to", 20, False), ("half_damage_to", 5, False), ("no_damage_to", 0, False),
             ("double_damage_from", 20, True), ("half_damage_from", 5, True), ("no_damage_from", 0, True))


def modern_rows(api: bs.API) -> dict[tuple[str, str], int]:
    """(attacker, defender) -> tenths for every non-neutral pair that involves Dark, Steel
    or Fairy, from PokéAPI's current damage relations."""
    rows: dict[tuple[str, str], int] = {}
    for t in MODERN_TYPES:
        rel = api.get(f"/type/{t}")["damage_relations"]
        for key, mult, incoming in RELATIONS:
            for other in rel[key]:
                pair = (other["name"].upper(), t.upper()) if incoming else (t.upper(), other["name"].upper())
                rows[pair] = mult
    return rows


def chart_changes(api: bs.API, carts: dict[int, dict[str, Any]], gen: int) -> dict[str, Any]:
    """The types the game gains and the matchup rows to add or take out so every pair
    involving Dark, Steel or Fairy reads as today's chart. Type names are the modern
    spellings (PSYCHIC); the mod turns them into the cart's ids. The cart's other rows
    (Gen 1's Ghost vs Psychic, Bug vs Poison...) stay as the game has them."""
    modern = modern_rows(api)
    cart_rows = {(type_name(a), type_name(d)): m for a, d, m in carts[gen]["matchups"]}
    cart_types = {t for pair in cart_rows for t in pair}
    new = NEW_TYPES[gen]
    present = cart_types | set(new)
    add = sorted([a, d, m] for (a, d), m in modern.items()
                 if (a in new or d in new) and a in present and d in present)
    remove, change = [], []
    for (a, d), m in sorted(cart_rows.items()):
        if a.lower() in MODERN_TYPES or d.lower() in MODERN_TYPES:
            if (a, d) not in modern:
                remove.append(f"{a}>{d}")
            elif modern[(a, d)] != m:
                change.append([a, d, modern[(a, d)]])
    for (a, d), m in sorted(modern.items()):
        if a in cart_types and d in cart_types and (a, d) not in cart_rows:
            add.append([a, d, m])
    return {"types": new, "add": sorted(add), "change": change, "remove": remove}


# ---------------------------------------------------------------- writing

HEADER = ("-- Generated by tools/build_gen12.py from PokéAPI and the imported carts. Do not edit\n"
          "-- by hand; rerun the tool instead.\n")


def write(result: dict[str, Any], out: Path) -> None:
    (out / "species").mkdir(parents=True, exist_ok=True)
    for old in list(out.glob("*.lua")) + list((out / "species").glob("*.lua")):
        old.unlink()
    lua = bs.lua
    shards = []
    records = result["records"]
    for n, start in enumerate(range(0, len(records), SHARD_SIZE), 1):
        name = f"{n:03d}.lua"
        shards.append(name)
        body = ",\n".join("  " + lua(r) for r in records[start:start + SHARD_SIZE])
        (out / "species" / name).write_text(HEADER + "return {\n" + body + ",\n}\n", encoding="utf-8")
    (out / "species" / "index.lua").write_text(
        HEADER + "return { version = 1, first = %d, count = %d, shards = %s }\n"
        % (FIRST_DEX, len(records), lua(shards)), encoding="utf-8")

    def listing(name: str, comment: str, rows: list[Any]) -> None:
        body = ",\n".join("  " + lua(r) for r in rows)
        (out / name).write_text(HEADER + comment + "return {\n" + body + (",\n" if body else "") + "}\n",
                                encoding="utf-8")

    listing("forms.lua", "-- The alternate forms (tools/form_list.py); slot is the Gen 3 slot, the stable key.\n",
            result["forms"])
    listing("crossgen.lua", "-- Evolutions from species #1-251 into newer ones (dex numbers).\n",
            result["crossgen"])
    listing("moves.lua", "-- Moves past #165 the species name, by National move number (n).\n",
            result["moves"])
    listing("items.lua", "-- The items evolutions use (stone: used on the Pokemon; trade: held through a trade;\n"
            "-- hold: held while it levels up), and per generation the cart's own id where it has one.\n",
            result["items"])
    (out / "cart.lua").write_text(
        HEADER + "-- Per generation: the cart's own species and moves whose modern typing differs, the\n"
        "-- types the game gains, and the matchup rows to add ({ attacker, defender, tenths }) or\n"
        "-- remove (\"ATTACKER>DEFENDER\") so every pair with Dark, Steel or Fairy is today's chart.\n"
        + "return " + lua(result["cart"]) + "\n", encoding="utf-8")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--cache", type=Path, default=ROOT / "tools" / ".cache")
    p.add_argument("--out", type=Path, default=ROOT / "data" / "gen12")
    p.add_argument("--engine", type=Path, default=ROOT.parent / "gen1recomp",
                   help="the gen1recomp checkout, with red, gold and firered imported")
    p.add_argument("--workers", type=int, default=12)
    p.add_argument("--refresh", action="store_true")
    args = p.parse_args()
    result = build(bs.API(args.cache, args.refresh), args.workers, args.engine.resolve())
    write(result, args.out)
    report = args.cache / "gen12_moves.txt"
    report.write_text(result["report"], encoding="utf-8")
    print("\n".join(result["report"].splitlines()[:2]))
    print(f"(full list: {report})")
    cart = result["cart"]
    print(f"{len(result['records'])} species, {len(result['forms'])} forms, "
          f"{len(result['crossgen'])} cross-generation evolutions, {len(result['moves'])} moves; "
          f"retyped: Gen 1 {len(cart['gen1']['species'])} species / {len(cart['gen1']['moves'])} moves, "
          f"Gen 2 {len(cart['gen2']['species'])} / {len(cart['gen2']['moves'])} -> {args.out}")


if __name__ == "__main__":
    main()
