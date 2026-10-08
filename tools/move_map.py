"""
Substitutes for the moves Gen 3 does not have.

The Gen 3 battle engine implements every move through the cart's own move
table (354 moves); a mod cannot add a move with a brand-new effect. So a
newer move in a species' modern level-up list is replaced by the closest Gen 3
move instead, which keeps the learnset the same length as in the modern games.

"Closest" is scored from real data: the cart's own move table
(type/power/accuracy/pp/priority, from an imported ROM) for the candidate, and
PokeAPI (type, power, accuracy, priority, damage class, effect category) for
both sides. Type is by far the strongest term, so a Water move is replaced by a
Water move, a Dark move by a Dark move, and so on; Gen 3 already decides
physical/special by type, so matching type also matches the move's class.
Fairy does not exist in Gen 3, so a Fairy move is treated as Normal, the same
as a pure-Fairy species.
"""

from __future__ import annotations

import math
import re
from pathlib import Path
from typing import Any

# The cart's type numbering (include/constants/pokemon.h): 9 is ???.
CART_TYPE = {
    "normal": 0, "fighting": 1, "flying": 2, "poison": 3, "ground": 4,
    "rock": 5, "bug": 6, "ghost": 7, "steel": 8, "fire": 10, "water": 11,
    "grass": 12, "electric": 13, "psychic": 14, "ice": 15, "dragon": 16,
    "dark": 17,
}
TYPE_NAME = {v: k for k, v in CART_TYPE.items()}

# Moves that make poor substitutes: one-hit KOs, moves with no battle use or
# a field-only use, and moves that copy or break the battle.
EXCLUDED = {
    "GUILLOTINE", "HORN DRILL", "FISSURE", "SHEER COLD", "STRUGGLE", "SKETCH",
    "MIMIC", "TRANSFORM", "SPLASH", "FLASH", "TELEPORT", "SWEET SCENT",
    "ROAR", "WHIRLWIND", "SUBSTITUTE", "METRONOME", "ASSIST", "MIRROR MOVE",
    "SLEEP TALK", "NATURE POWER", "SECRET POWER", "FOCUS PUNCH", "COUNTER",
    "MIRROR COAT", "BIDE", "SNATCH", "ENDEAVOR", "SUPERPOWER",
    # the user faints, or the hit lands turns later: not a stand-in for a move
    # that does neither
    "SELFDESTRUCT", "EXPLOSION", "MEMENTO", "DOOM DESIRE", "FUTURE SIGHT",
    "DESTINY BOND", "GRUDGE", "PERISH SONG", "HEALING WISH",
}


def parse_cart(pokemon_dir: Path) -> dict[int, dict[str, Any]]:
    """id -> {name, type (cart id), power, accuracy, pp, priority, effect} from
    an imported cart's pokemon/battle_moves.lua and move_names.lua."""
    names = {int(i): n for i, n in re.findall(
        r'\[(\d+)\]\s*=\s*"([^"]*)"', (pokemon_dir / "move_names.lua").read_text(encoding="utf-8"))}
    moves: dict[int, dict[str, Any]] = {}
    row = re.compile(r"\[(\d+)\]\s*=\s*\{([^}]*)\}")
    for m in row.finditer((pokemon_dir / "battle_moves.lua").read_text(encoding="utf-8")):
        fields = {k: int(v) for k, v in re.findall(r"(\w+)\s*=\s*(-?\d+)", m.group(2))}
        mid = int(m.group(1))
        if mid and "type" in fields:
            moves[mid] = dict(fields, name=names.get(mid, str(mid)))
    return moves


def _api_type(move: dict[str, Any]) -> int:
    name = move["type"]["name"]
    return CART_TYPE.get(name, CART_TYPE["normal"])   # fairy -> normal


def _meta(move: dict[str, Any]) -> tuple[str, str]:
    meta = move.get("meta") or {}
    return ((meta.get("category") or {}).get("name", ""),
            (meta.get("ailment") or {}).get("name", "none"))


def _power(value: int | None) -> int:
    return value if value and value > 1 else 0     # 0/1/None: variable or none


class MoveMapper:
    """cart: parse_cart(); api_moves: id -> PokeAPI move JSON for every id used
    (the 1-354 candidates and each newer move to be replaced)."""

    def __init__(self, cart: dict[int, dict[str, Any]], api_moves: dict[int, dict[str, Any]],
                 max_cart_id: int = 354):
        self.max = max_cart_id
        self.cart = cart
        self.api = api_moves
        self.pool = [mid for mid in sorted(cart)
                     if mid <= max_cart_id and cart[mid]["name"] not in EXCLUDED
                     and mid in api_moves]
        self._rank: dict[int, list[int]] = {}
        self.log: list[tuple[int, int, float]] = []

    def score(self, new: dict[str, Any], cand_id: int) -> float:
        c = self.cart[cand_id]
        cand = self.api[cand_id]
        new_damaging = new["damage_class"]["name"] != "status"
        cand_damaging = c["power"] > 0 and cand["damage_class"]["name"] != "status"
        s = 0.0
        # damaging vs status: the move's whole job
        if new_damaging != cand_damaging:
            s += 400
        # type: decides everything for an attack; barely matters for a status
        # move, whose effect does not depend on its type
        if TYPE_NAME.get(c["type"]) != TYPE_NAME.get(_api_type(new)):
            s += 150 if new_damaging else 45
        n_cat, n_ail = _meta(new)
        c_cat, c_ail = _meta(cand)
        # effect category: a status move lives or dies by it, but for two
        # attacks "damage" vs "damage + a side effect" is a small difference
        both_attacks = new_damaging and cand_damaging
        if n_cat != c_cat:
            s += 8 if both_attacks else 30
        elif n_ail != c_ail:
            s += 4 if both_attacks else 15
        if new_damaging and cand_damaging:
            np_, cp = _power(new.get("power")), c["power"] if c["power"] > 1 else 0
            if np_ and cp:
                s += abs(math.log(cp / np_)) * 25
            else:
                s += 10                               # one side is variable-power
        na = new.get("accuracy") or 100
        ca = c["accuracy"] or 100
        s += abs(na - ca) / 8
        if (new.get("priority") or 0) != c["priority"]:
            s += 25
        s += abs((new.get("pp") or 15) - c["pp"]) / 20
        return s

    def ranked(self, new_id: int) -> list[int]:
        """Candidates for a newer move, best first (ties by id, so stable)."""
        if new_id not in self._rank:
            new = self.api[new_id]
            self._rank[new_id] = sorted(self.pool, key=lambda m: (self.score(new, m), m))
        return self._rank[new_id]

    def substitute(self, new_id: int, taken: set[int]) -> int:
        """The best Gen 3 move for `new_id` not already in `taken`."""
        for cand in self.ranked(new_id):
            if cand not in taken:
                self.log.append((new_id, cand, self.score(self.api[new_id], cand)))
                return cand
        raise RuntimeError(f"no substitute left for move {new_id}")

    # -- reporting
    def _same_type(self, new_id: int, cand: int) -> bool:
        return TYPE_NAME.get(self.cart[cand]["type"]) == TYPE_NAME.get(_api_type(self.api[new_id]))

    def report(self) -> str:
        by_new: dict[int, dict[int, int]] = {}
        for new_id, cand, _ in self.log:
            by_new.setdefault(new_id, {})[cand] = by_new.get(new_id, {}).get(cand, 0) + 1
        attacks = [(n, c) for n, c, _ in self.log if self.api[n]["damage_class"]["name"] != "status"]
        status = [(n, c) for n, c, _ in self.log if self.api[n]["damage_class"]["name"] == "status"]
        kept_a = sum(1 for n, c in attacks if self._same_type(n, c))
        kept_s = sum(1 for n, c in status if self._same_type(n, c))
        lines = [
            f"{len(self.log)} substitutions across {len(by_new)} newer moves",
            f"attacks: {len(attacks)}, {kept_a} ({kept_a * 100 // max(1, len(attacks))}%) keep the move's type "
            f"(Fairy counted as Normal)",
            f"status moves: {len(status)}, {kept_s} keep the type (a status move's type does not change its effect)",
            "",
            "ATTACKS THAT CHANGED TYPE (no Gen 3 candidate fit better):",
        ]
        for new_id in sorted(by_new):
            new = self.api[new_id]
            if new["damage_class"]["name"] == "status":
                continue
            for cand, n in by_new[new_id].items():
                if not self._same_type(new_id, cand):
                    lines.append(f"  {new['name']} ({new['type']['name']}) -> "
                                 f"{self.cart[cand]['name']} ({TYPE_NAME.get(self.cart[cand]['type'])}) x{n}")
        lines += ["", "ALL SUBSTITUTIONS:"]
        for new_id in sorted(by_new):
            new = self.api[new_id]
            picks = ", ".join(f"{self.cart[c]['name']} x{n}"
                              for c, n in sorted(by_new[new_id].items(), key=lambda kv: -kv[1]))
            lines.append(f"{new['name']} ({new['type']['name']}, "
                         f"{new['damage_class']['name']}, pow {new.get('power')}) -> {picks}")
        return chr(10).join(lines)
