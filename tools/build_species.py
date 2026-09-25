#!/usr/bin/env python3
"""
Build national_dex_gen3's species payload from PokéAPI.

Writes data/species/NNN.lua shards: one record per National Dex species
#387-1025 (default variety only), shaped for Pokémon FireRed's species
registry in gen1recomp, plus data/species/index.lua listing the shards.

Only what FireRed can express is kept:
  * types: FAIRY does not exist in Gen 3; it is dropped (a pure Fairy type
    becomes NORMAL, the pre-Gen 6 convention);
  * learnset: level-up moves from the newest main-series version group that
    has any, restricted to move ids 1-354 (the moves FireRed has), shipped as
    move NUMBERS -- the mod resolves them to FireRed's own move names from the
    running game's move registry;
  * abilities: PokéAPI ability ids 1-76 (Gen 3's own numbering), as numbers;
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

BASE_URL = "https://pokeapi.co/api/v2"
ROOT = Path(__file__).resolve().parent.parent
FIRST_DEX, LAST_DEX = 387, 1025
SLOT_OFFSET = 64          # FireRed slot = dex + 64 (451..1089), above every ROM slot
SHARD_SIZE = 80
MAX_MOVE_ID = 354         # FireRed's move table
MAX_ABILITY_ID = 76       # Gen 3's abilities

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
    """PokéAPI species slug -> the registry id style FireRed uses
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
    names = [t["type"]["name"] for t in sorted(pokemon["types"], key=lambda t: t["slot"])]
    kept = [n.upper() for n in names if n in GEN3_TYPES]
    return kept or ["NORMAL"]


def learnset_for(pokemon: dict[str, Any]) -> list[list[int]]:
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
            kept = sorted({(lvl, mid) for lvl, mid in rows if mid <= MAX_MOVE_ID})
            return [[lvl, mid] for lvl, mid in kept]
    return []


def moves_by_method(pokemon: dict[str, Any], methods: set[str]) -> list[int]:
    """Move ids (FireRed's 1-354 only) the species learns by any of `methods`
    in any main-series game -- a FireRed TM, HM or tutor is compatible when
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


def abilities_for(pokemon: dict[str, Any]) -> list[int]:
    ids = []
    for entry in sorted(pokemon["abilities"], key=lambda a: a["slot"]):
        if entry.get("is_hidden"):
            continue
        ability_id = id_from_url(entry["ability"]["url"])
        if ability_id <= MAX_ABILITY_ID and ability_id not in ids:
            ids.append(ability_id)
    return ids[:2]


def evolution_steps(chain: dict[str, Any]) -> dict[int, list[dict[str, Any]]]:
    """dex -> steps FROM that species, in the FireRed-expressible subset."""
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


def build(api: API, workers: int) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
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
    # Leafeon, Magneton -> Magnezone, ... (only methods FireRed can express)
    crossgen = [dict(step, source=source)
                for source, rows in sorted(steps.items()) if source < FIRST_DEX
                for step in rows if step["target"] >= FIRST_DEX]

    records = []
    for item in fetched:
        species, pokemon, dex = item["species"], item["pokemon"], item["dex"]
        stats = {s["stat"]["name"]: s["base_stat"] for s in pokemon["stats"]}
        genus = english(species.get("genera", []), "genus") or ""
        records.append({
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
            "learnset": learnset_for(pokemon),
            # taught (machine or tutor) and egg moves, FireRed's moves only;
            # the mod maps `teach` onto FireRed's own TMs, HMs and tutors
            "teach": moves_by_method(pokemon, {"machine", "tutor"}),
            "eggMoves": moves_by_method(pokemon, {"egg"}),
            "evolutions": steps.get(dex, []),
            "legendary": bool(species.get("is_legendary")),
            "mythical": bool(species.get("is_mythical")),
            "dexEntry": {
                "kind": re.sub(r"\s*Pok[eé]mon$", "", genus).upper(),
                "height": pokemon.get("height") or 0,   # decimetres, as FireRed
                "weight": pokemon.get("weight") or 0,   # hectograms, as FireRed
            },
        })
    return records, crossgen


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


def write(records: list[dict[str, Any]], crossgen: list[dict[str, Any]], out_dir: Path) -> None:
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
        header + "-- Evolutions from FireRed's own species into #387-1025.\n"
        + "return {\n" + body + (",\n" if body else "") + "}\n", encoding="utf-8")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--cache", type=Path, default=ROOT / "tools" / ".cache")
    p.add_argument("--out", type=Path, default=ROOT / "data" / "species")
    p.add_argument("--workers", type=int, default=12)
    p.add_argument("--refresh", action="store_true")
    args = p.parse_args()
    records, crossgen = build(API(args.cache, args.refresh), args.workers)
    write(records, crossgen, args.out)
    moves = sum(len(r["learnset"]) for r in records)
    teach = sum(len(r["teach"]) for r in records)
    eggs = sum(len(r["eggMoves"]) for r in records)
    evos = sum(len(r["evolutions"]) for r in records)
    print(f"{len(records)} species, {moves} learnset rows, {teach} teachable, "
          f"{eggs} egg moves, {evos} evolution steps, {len(crossgen)} from the "
          f"cart's species -> {args.out}")


if __name__ == "__main__":
    main()
