#!/usr/bin/env python3
"""
Build national_dex_gen3's species payload from PokéAPI.

Writes data/species/NNN.lua shards: one record per National Dex species
#387-1025 (default variety only), shaped for the Gen 3 species registry
in gen1recomp (FireRed, LeafGreen, Ruby, Sapphire, Emerald all share it),
plus data/species/index.lua listing the shards.

Only what Gen 3 can express is kept:
  * types: the Gen V typing where PokéAPI records one (Togekiss was
    Normal/Flying); FAIRY does not exist in Gen 3, so it is otherwise dropped
    (a pure Fairy type becomes NORMAL, the pre-Gen 6 convention);
  * learnset: level-up moves from the newest main-series version group that
    has any, at full length: a move Gen 3 lacks is replaced by the closest
    one it has (tools/move_map.py), restricted to move ids 1-354, shipped as
    move NUMBERS -- the mod resolves them to the running game's own move
    names from its move registry;
  * abilities: the cart's own ability ids, as numbers -- newer abilities are
    mapped to the closest one it has (tools/ability_map.py), since the Gen 3
    battle engine cannot take a new ability from a mod;
  * evolutions: level-up with a minimum level, item use, trade and friendship
    steps between species #1-1025, targets as dex numbers.

Requirements: Python 3.10+, `pip install requests`.

Usage:
    python tools/build_species.py                 # cache in tools/.cache
    python tools/build_species.py --cache DIR     # reuse another PokéAPI cache
    python tools/build_species.py --refresh       # ignore cached responses
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import threading
import time
from pathlib import Path
from typing import Any

import requests

import ability_map
import form_list
import move_map

BASE_URL = "https://pokeapi.co/api/v2"
ROOT = Path(__file__).resolve().parent.parent
FIRST_DEX, LAST_DEX = 387, 1025
SLOT_OFFSET = 64          # Gen 3 slot = dex + 64 (451..1089), above every ROM slot
SHARD_SIZE = 80
MAX_MOVE_ID = 354         # Gen 3's move table

# Newest first. Legends: Arceus is left out: its move system is its own.
VERSION_GROUPS = [
    "scarlet-violet", "sword-shield", "brilliant-diamond-and-shining-pearl",
    "ultra-sun-ultra-moon", "sun-moon", "omega-ruby-alpha-sapphire", "x-y",
    "black-2-white-2", "black-white", "heartgold-soulsilver", "platinum",
    "diamond-pearl",
]

GROWTH_RATES = {
    "slow": "SLOW", "medium": "MEDIUM_FAST", "fast": "FAST",
    "medium-slow": "MEDIUM_SLOW", "slow-then-very-fast": "ERRATIC",
    "fast-then-very-slow": "FLUCTUATING",
}

GEN3_TYPES = {
    "normal", "fighting", "flying", "poison", "ground", "rock", "bug", "ghost",
    "steel", "fire", "water", "grass", "electric", "psychic", "ice", "dragon",
    "dark",
}


class API:
    """Tiny cached PokéAPI client (one JSON file per URL, atomic writes,
    one in-flight fetch per URL)."""

    def __init__(self, cache_dir: Path, refresh: bool = False):
        self.cache_dir = cache_dir
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.refresh = refresh
        self.session = requests.Session()
        self.session.headers["User-Agent"] = "national_dex_gen3-builder/1.0"
        self._locks: dict[str, threading.Lock] = {}
        self._guard = threading.Lock()

    def get(self, path_or_url: str) -> dict[str, Any]:
        url = path_or_url if path_or_url.startswith("http") else BASE_URL + path_or_url
        with self._guard:
            lock = self._locks.setdefault(url, threading.Lock())
        with lock:
            path = self.cache_dir / (hashlib.sha256(url.encode()).hexdigest() + ".json")
            if path.exists() and not self.refresh:
                return json.loads(path.read_text(encoding="utf-8"))
            last = None
            for attempt in range(5):
                try:
                    r = self.session.get(url, timeout=30)
                except requests.RequestException as exc:
                    last = exc
                    time.sleep(1.5 * (attempt + 1))
                    continue
                if r.status_code == 429 or r.status_code >= 500:
                    last = f"HTTP {r.status_code}"
                    time.sleep(1.5 * (attempt + 1))
                    continue
                if r.status_code >= 400:
                    raise RuntimeError(f"GET {url}: HTTP {r.status_code}")
                data = r.json()
                tmp = path.with_suffix(".tmp")
                tmp.write_text(json.dumps(data), encoding="utf-8")
                os.replace(tmp, path)
                return data
            raise RuntimeError(f"GET {url}: {last}")


def id_from_url(url: str) -> int:
    return int(url.rstrip("/").rsplit("/", 1)[1])


def engine_id(name: str) -> str:
    """PokéAPI species slug -> the registry id style Gen 3 games use
    (MR_MIME, HO_OH, NIDORAN_F): upper case, separators as underscores."""
    s = name.replace("♀", "-f").replace("♂", "-m")
    s = re.sub(r"[.'’:]", "", s)
    s = re.sub(r"[^A-Za-z0-9]+", "_", s)
    return s.strip("_").upper()


def english(entries: list[dict[str, Any]], key: str) -> str | None:
    for entry in entries:
        if entry.get("language", {}).get("name") == "en":
            return entry.get(key)
    return None


def gender_ratio(rate: int | None) -> int:
    # PokéAPI: eighths female, -1 genderless. Gen 3: 255 genderless,
    # 254 always female, 0 always male, otherwise a threshold out of 256.
    if rate is None or rate < 0:
        return 255
    if rate == 0:
        return 0
    if rate >= 8:
        return 254
    return rate * 32 - 1


def types_for(pokemon: dict[str, Any]) -> list[str]:
    """The species' Gen 3-era typing. PokéAPI's `types` are today's; where a
    species' typing changed afterwards (Fairy was added in Gen 6) `past_types`
    records the earlier one, so Togekiss stays Normal/Flying rather than
    losing its Fairy half and becoming pure Flying. A Gen 6+ Fairy has no
    earlier typing: its Fairy half is simply dropped (pure Fairy -> Normal)."""
    current = pokemon["types"]
    for past in pokemon.get("past_types") or []:
        if past["generation"]["name"] == "generation-v":
            current = past["types"]
    names = [t["type"]["name"] for t in sorted(current, key=lambda t: t["slot"])]
    kept = [n.upper() for n in names if n in GEN3_TYPES]
    return kept or ["NORMAL"]


def modern_learnset(pokemon: dict[str, Any]) -> list[tuple[int, int]]:
    """(level, move id) for the newest main-series game that lists any
    level-up moves, every move included."""
    by_group: dict[str, list[tuple[int, int]]] = {}
    for move in pokemon["moves"]:
        move_id = id_from_url(move["move"]["url"])
        for detail in move["version_group_details"]:
            if detail["move_learn_method"]["name"] != "level-up":
                continue
            group = detail["version_group"]["name"]
            by_group.setdefault(group, []).append((max(1, detail["level_learned_at"]), move_id))
    for group in VERSION_GROUPS:
        rows = by_group.get(group)
        if rows:
            return sorted(set(rows))
    return []


def learnset_for(pokemon: dict[str, Any], mapper: "move_map.MoveMapper") -> list[list[int]]:
    """The modern level-up list at its full length: Gen 3 moves as they are,
    every newer move replaced by the closest Gen 3 move the species does not
    already learn (tools/move_map.py), at the same level."""
    rows = modern_learnset(pokemon)
    taken = {mid for _, mid in rows if mid <= MAX_MOVE_ID}
    out = []
    for level, mid in rows:
        if mid > MAX_MOVE_ID:
            mid = mapper.substitute(mid, taken)
            taken.add(mid)
        out.append([level, mid])
    return sorted(out, key=lambda r: r[0])


def moves_by_method(pokemon: dict[str, Any], methods: set[str]) -> list[int]:
    """Move ids (Gen 3's 1-354 only) the species learns by any of `methods`
    in any main-series game -- a Gen 3 TM, HM or tutor is compatible when
    some game teaches the species that move that way."""
    found = set()
    for move in pokemon["moves"]:
        move_id = id_from_url(move["move"]["url"])
        if move_id > MAX_MOVE_ID:
            continue
        for detail in move["version_group_details"]:
            if detail["move_learn_method"]["name"] in methods:
                found.add(move_id)
                break
    return sorted(found)


# Every ability the species use, for the mapping report: slug -> (PokéAPI id,
# hidden?, species names). Filled by abilities_for.
SEEN_ABILITIES: dict[str, dict[str, Any]] = {}


def abilities_for(pokemon: dict[str, Any]) -> list[int]:
    """Cart ability ids (tools/ability_map.py): each non-hidden slot mapped to
    the closest Gen 3 ability, de-duplicated, at most two. A species whose
    regular abilities all map to nothing falls back to its hidden one."""
    entries = sorted(pokemon["abilities"], key=lambda a: a["slot"])
    for entry in entries:
        slug = entry["ability"]["name"]
        row = SEEN_ABILITIES.setdefault(
            slug, {"id": id_from_url(entry["ability"]["url"]), "hidden": True, "species": []})
        row["hidden"] = row["hidden"] and bool(entry.get("is_hidden"))
        row["species"].append(pokemon.get("name", "?"))

    def mapped(hidden: bool) -> list[int]:
        out: list[int] = []
        for entry in entries:
            if bool(entry.get("is_hidden")) != hidden:
                continue
            cart = ability_map.cart_id(id_from_url(entry["ability"]["url"]),
                                       entry["ability"]["name"])
            if cart and cart not in out:
                out.append(cart)
        return out

    return (mapped(False) or mapped(True))[:2]


def evolution_steps(chain: dict[str, Any]) -> dict[int, list[dict[str, Any]]]:
    """dex -> steps FROM that species, in the Gen 3-expressible subset."""
    steps: dict[int, list[dict[str, Any]]] = {}

    def walk(node: dict[str, Any]) -> None:
        source = id_from_url(node["species"]["url"])
        for child in node["evolves_to"]:
            target = id_from_url(child["species"]["url"])
            # the default (canonical) method first, then per-game variants
            details = sorted(child["evolution_details"],
                             key=lambda d: 0 if d.get("is_default") else 1)
            for detail in details:
                trigger = detail["trigger"]["name"]
                others = {k: v for k, v in detail.items()
                          if v not in (None, False, "", 0) and k not in (
                              "trigger", "min_level", "item", "min_happiness",
                              "time_of_day", "held_item", "gender",
                              "version_group", "is_default")}
                step = None
                if trigger == "level-up" and detail.get("min_level") and not others:
                    step = {"method": "EVO_LEVEL", "level": detail["min_level"]}
                elif trigger == "level-up" and detail.get("min_happiness") and not others:
                    time_of_day = detail.get("time_of_day") or ""
                    method = {"day": "EVO_FRIENDSHIP_DAY",
                              "night": "EVO_FRIENDSHIP_NIGHT"}.get(time_of_day, "EVO_FRIENDSHIP")
                    step = {"method": method}
                elif trigger == "use-item" and detail.get("item") and not others:
                    step = {"method": "EVO_ITEM", "item": detail["item"]["name"]}
                elif trigger == "trade" and not others:
                    held = detail.get("held_item")
                    step = ({"method": "EVO_TRADE_ITEM", "item": held["name"]} if held
                            else {"method": "EVO_TRADE"})
                if step and 1 <= target <= LAST_DEX:
                    step["target"] = target
                    steps.setdefault(source, []).append(step)
                    break
            walk(child)

    walk(chain["chain"])
    return steps


def build_mapper(api: API, fetched: list[dict[str, Any]], cart_dir: Path,
                 workers: int) -> "move_map.MoveMapper":
    """PokéAPI data for the 1-354 candidates and every newer move in a learnset."""
    used = {mid for item in fetched for _, mid in modern_learnset(item["pokemon"])
            if mid > MAX_MOVE_ID}
    ids = sorted(set(range(1, MAX_MOVE_ID + 1)) | used)
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
        api_moves = dict(zip(ids, ex.map(lambda i: api.get(f"/move/{i}"), ids)))
    return move_map.MoveMapper(move_map.parse_cart(cart_dir), api_moves, MAX_MOVE_ID)


def build(api: API, workers: int, cart_dir: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]], "move_map.MoveMapper", list[dict[str, Any]]]:
    def fetch(dex: int) -> dict[str, Any]:
        species = api.get(f"/pokemon-species/{dex}")
        default = next(v for v in species["varieties"] if v["is_default"])
        pokemon = api.get(default["pokemon"]["url"])
        chain = api.get(species["evolution_chain"]["url"]) if species.get("evolution_chain") else None
        return {"dex": dex, "species": species, "pokemon": pokemon, "chain": chain}

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
        fetched = list(ex.map(fetch, range(FIRST_DEX, LAST_DEX + 1)))

    steps: dict[int, list[dict[str, Any]]] = {}
    for item in fetched:
        if item["chain"]:
            for source, rows in evolution_steps(item["chain"]).items():
                steps.setdefault(source, rows)
    # steps FROM the cart's own species (#1-386) INTO new ones: Eevee ->
    # Leafeon, Magneton -> Magnezone, ... (only methods Gen 3 can express)
    crossgen = [dict(step, source=source)
                for source, rows in sorted(steps.items()) if source < FIRST_DEX
                for step in rows if step["target"] >= FIRST_DEX]

    form_items = fetch_forms(api, fetched, workers)
    mapper = build_mapper(api, fetched + form_items, cart_dir, workers)
    records = [species_record(item["species"], item["pokemon"], item["dex"], mapper,
                              steps.get(item["dex"], []))
               for item in fetched]
    forms = [form_record(item, mapper) for item in form_items]
    return records, crossgen, mapper, forms


def species_record(species: dict[str, Any], pokemon: dict[str, Any], dex: int,
                   mapper: "move_map.MoveMapper", evolutions: list[dict[str, Any]]) -> dict[str, Any]:
    """One species (or one form of it: `pokemon` is that variety's data)."""
    stats = {s["stat"]["name"]: s["base_stat"] for s in pokemon["stats"]}
    genus = english(species.get("genera", []), "genus") or ""
    return {
        "id": engine_id(species["name"]),
        "name": (english(species.get("names", []), "name") or species["name"]).upper(),
        "dex": dex,
        "slot": dex + SLOT_OFFSET,
        "generation": species["generation"]["name"],
        "types": types_for(pokemon),
        "baseStats": {
            "hp": stats["hp"], "attack": stats["attack"], "defense": stats["defense"],
            "speed": stats["speed"], "specialAttack": stats["special-attack"],
            "specialDefense": stats["special-defense"],
        },
        "catchRate": species.get("capture_rate") or 45,
        "baseExp": min(255, pokemon.get("base_experience") or 64),
        "growthRate": GROWTH_RATES.get(species["growth_rate"]["name"], "MEDIUM_FAST"),
        "genderRatio": gender_ratio(species.get("gender_rate")),
        "eggCycles": min(255, species.get("hatch_counter") or 20),
        "friendship": min(255, species.get("base_happiness") if species.get("base_happiness") is not None else 70),
        "abilities": abilities_for(pokemon),
        "learnset": learnset_for(pokemon, mapper),
        # taught (machine or tutor) and egg moves, Gen 3's moves only;
        # the mod maps `teach` onto the running game's own TMs, HMs and tutors
        "teach": moves_by_method(pokemon, {"machine", "tutor"}),
        "eggMoves": moves_by_method(pokemon, {"egg"}),
        "evolutions": evolutions,
        "legendary": bool(species.get("is_legendary")),
        "mythical": bool(species.get("is_mythical")),
        "dexEntry": {
            "kind": re.sub(r"\s*Pok[eé]mon$", "", genus).upper(),
            "height": pokemon.get("height") or 0,   # decimetres, as Gen 3 stores it
            "weight": pokemon.get("weight") or 0,   # hectograms, as Gen 3 stores it
        },
    }


def fetch_forms(api: API, fetched: list[dict[str, Any]], workers: int) -> list[dict[str, Any]]:
    """PokéAPI data for each form in tools/form_list.py: its base species'
    data (catch rate, growth, ...) and the form's own variety (stats, types,
    abilities, moves)."""
    by_id = {engine_id(item["species"]["name"]): item for item in fetched}

    def fetch(entry: tuple[int, tuple]) -> dict[str, Any]:
        index, (fid, base, form, slug) = entry
        base_item = by_id[base]
        variety = next(v for v in base_item["species"]["varieties"] if v["pokemon"]["name"] == slug)
        return {"id": fid, "base": base, "form": form, "slot": form_list.FIRST_FORM_SLOT + index,
                "dex": base_item["dex"], "species": base_item["species"],
                "pokemon": api.get(variety["pokemon"]["url"])}

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
        return list(ex.map(fetch, enumerate(form_list.FORMS)))


def form_record(item: dict[str, Any], mapper: "move_map.MoveMapper") -> dict[str, Any]:
    """A form is a species record of its own, in a slot above the base range.
    It keeps its base species' name and dex number (what a player sees), gets
    no Pokédex entry of its own (that is keyed by dex and would overwrite the
    base's), and points back at its base."""
    evolutions = []
    for src, dst, method, arg in form_list.FORM_EVOLUTIONS:
        if src != item["id"]:
            continue
        step: dict[str, Any] = {"method": method, "targetForm": dst}
        if method == "EVO_LEVEL":
            step["level"] = arg
        elif method == "EVO_ITEM":
            step["item"] = arg
        evolutions.append(step)
    rec = species_record(item["species"], item["pokemon"], item["dex"], mapper, evolutions)
    rec.update({
        "id": item["id"], "slot": item["slot"], "baseSpecies": item["base"],
        "form": item["form"], "baseDex": item["dex"],
    })
    del rec["dexEntry"]
    return rec


def lua(value: Any, indent: str = "") -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "{ " + ", ".join(lua(v, indent) for v in value) + " }"
    if isinstance(value, dict):
        parts = []
        for k, v in value.items():
            key = k if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k) else f"[{json.dumps(k)}]"
            parts.append(f"{key} = {lua(v, indent)}")
        return "{ " + ", ".join(parts) + " }"
    raise TypeError(type(value))


def write(records: list[dict[str, Any]], crossgen: list[dict[str, Any]], out_dir: Path,
          forms: list[dict[str, Any]] | None = None) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    for old in out_dir.glob("*.lua"):  # includes crossgen.lua
        old.unlink()
    header = ("-- Generated by tools/build_species.py from PokéAPI. Do not edit by hand;\n"
              "-- rerun the tool instead.\n")
    shards = []
    for n, start in enumerate(range(0, len(records), SHARD_SIZE), 1):
        name = f"{n:03d}.lua"
        shards.append(name)
        body = ",\n".join("  " + lua(r) for r in records[start:start + SHARD_SIZE])
        (out_dir / name).write_text(header + "return {\n" + body + ",\n}\n", encoding="utf-8")
    index = header + "return { version = 1, count = %d, shards = %s }\n" % (
        len(records), lua(shards))
    (out_dir / "index.lua").write_text(index, encoding="utf-8")
    body = ",\n".join("  " + lua(step) for step in crossgen)
    (out_dir / "crossgen.lua").write_text(
        header + "-- Evolutions from the cart's own species into #387-1025.\n"
        + "return {\n" + body + (",\n" if body else "") + "}\n", encoding="utf-8")
    fbody = ",\n".join("  " + lua(r) for r in (forms or []))
    (out_dir / "forms.lua").write_text(
        header + "-- Alternate forms (tools/form_list.py), each in a slot of its own above the\n"
        "-- base species range. Append-only: a slot is stored in player saves.\n"
        + "return {\n" + fbody + (",\n" if fbody else "") + "}\n", encoding="utf-8")


def ability_report(records: list[dict[str, Any]]) -> None:
    """What the ability mapping left over: abilities with no cart equivalent
    mapped yet, and how many species end up with none."""
    unmapped = {slug: row for slug, row in SEEN_ABILITIES.items()
                if ability_map.cart_id(row["id"], slug) is None}
    bare = [r["id"] for r in records if not r["abilities"]]
    print(f"abilities: {len(SEEN_ABILITIES)} seen, {len(unmapped)} unmapped; "
          f"{len(bare)} of {len(records)} species end up with none")
    for slug, row in sorted(unmapped.items(), key=lambda kv: kv[1]["id"]):
        names = sorted(set(row["species"]))
        print(f"  {row['id']:>3} {slug}{' (hidden only)' if row['hidden'] else ''}: "
              f"{len(names)} species, e.g. {', '.join(names[:3])}")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--cache", type=Path, default=ROOT / "tools" / ".cache")
    p.add_argument("--out", type=Path, default=ROOT / "data" / "species")
    p.add_argument("--workers", type=int, default=12)
    p.add_argument("--cart", type=Path, default=ROOT.parent / "gen1recomp" / "firered" / "data"
                   / "generated" / "gba" / "pokemon",
                   help="an imported cart's pokemon/ folder (battle_moves.lua, move_names.lua): "
                        "the Gen 3 move stats newer moves are matched against")
    p.add_argument("--refresh", action="store_true")
    args = p.parse_args()
    records, crossgen, mapper, forms = build(API(args.cache, args.refresh), args.workers, args.cart)
    write(records, crossgen, args.out, forms)
    ability_report(records)
    report = args.cache / "move_substitutions.txt"
    report.write_text(mapper.report(), encoding="utf-8")
    print(chr(10).join(mapper.report().splitlines()[:3]))
    print(f"(full list: {report})")
    moves = sum(len(r["learnset"]) for r in records)
    teach = sum(len(r["teach"]) for r in records)
    eggs = sum(len(r["eggMoves"]) for r in records)
    evos = sum(len(r["evolutions"]) for r in records)
    print(f"{len(records)} species, {moves} learnset rows, {teach} teachable, "
          f"{eggs} egg moves, {evos} evolution steps, {len(crossgen)} from the "
          f"cart's species -> {args.out}")


if __name__ == "__main__":
    main()
