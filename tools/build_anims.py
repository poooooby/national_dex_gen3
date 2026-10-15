#!/usr/bin/env python3
"""Battle animations for the newer moves, from RHH's pokeemerald-expansion.

Based off RHH's pokeemerald-expansion (https://github.com/rh-hideout/pokeemerald-expansion/).
Its battle animation scripts (data/battle_anim_scripts.s) are written in the decomp's script
language, which is what the engine's animation player runs (as decoded rows, the shape
src/import/gba/battle_anim_extract.lua gives a cart's own scripts). This expands the script of
each move in data/moves.lua (expansion's macros, constants and conditionals) into those rows and
keeps it only when every piece it uses is one the engine and an imported Gen 3 cart already have:
the same sprite templates, graphics tags, visual tasks and opcodes. No graphics are copied.

Ids that differ between carts stay names and are resolved in the running game by src/anims.lua:
a sound effect (in an se field: "SE_M_BARRIER"; in a task argument: "SE:SE_M_BARRIER") and a
graphics tag in a task argument ("TAG:MOON"). A script using anything else (an expansion-only
template, task, opcode, background, or a move, type or species id) is left out, and that move
keeps the cart animation data/moves.lua names in `look`.

    python tools/build_anims.py [--expansion ../pokeemerald-expansion] [--engine ../gen1recomp]

The engine's inventory comes from tools/anim_known.lua, run with luajit from the engine root
(the imported carts are read there). Writes data/anims.lua; the report lists what each left-out
move is missing (tools/.cache/anims_report.txt).
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# the cart's 27 battle backgrounds (BG_DARK .. BG_SOLAR_BEAM_CONTESTS) keep their numbers in
# expansion; anything after is one Gen 3 doesn't have
LAST_CART_BG = 26
BATTLERS = {0: "attacker", 1: "target", 2: "atk_partner", 3: "def_partner"}


class Blocked(Exception):
    """The script uses something the engine or the carts don't have."""


class Sym:
    """A name resolved in the running game (a sound effect, a graphics tag)."""

    def __init__(self, kind: str, name: str):
        self.kind, self.name = kind, name

    def __repr__(self) -> str:
        return f"{self.kind}:{self.name}"


# ---------------------------------------------------------------- C constants

def strip_c_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


class Constants:
    def __init__(self, exp: Path):
        self.raw: dict[str, str] = {}
        self.cache: dict[str, int | Sym] = {}
        files = []
        for sub in ("include/constants", "include/config", "include/gba"):
            files += sorted((exp / sub).glob("*.h"))
        for path in files:
            text = strip_c_comments(path.read_text(encoding="utf-8", errors="replace"))
            text = re.sub(r"\\\n", " ", text)
            for m in re.finditer(r"^[ \t]*#define[ \t]+(\w+)(?![\w(])[ \t]*(.*)$", text, flags=re.M):
                self.raw.setdefault(m.group(1), m.group(2).strip())
            for m in re.finditer(r"\benum\b[^{;()]*\{(.*?)\}", text, flags=re.S):
                prev = "-1"
                for entry in m.group(1).split(","):
                    entry = entry.strip()
                    if not entry:
                        continue
                    name, _, value = entry.partition("=")
                    name = name.strip()
                    if not re.fullmatch(r"\w+", name):
                        continue
                    expr = value.strip() if value.strip() else f"({prev}) + 1"
                    self.raw.setdefault(name, expr)
                    prev = name

    def value(self, name: str, depth: int = 0) -> int | Sym:
        if name in self.cache:
            return self.cache[name]
        if name.startswith("SE_") and name in self.raw:
            return Sym("SE", name)
        if name.startswith("ANIM_TAG_") and name in self.raw:
            return Sym("TAG", name[len("ANIM_TAG_"):])
        for prefix in ("MOVE_", "SPECIES_", "ITEM_", "TYPE_", "ABILITY_"):
            if name.startswith(prefix):
                raise Blocked(f"id {name}")
        if name not in self.raw or depth > 40:
            raise Blocked(f"constant {name}")
        v = self.eval(self.raw[name], depth + 1)
        self.cache[name] = v
        return v

    def eval(self, expr: str, depth: int = 0) -> int | Sym:
        expr = expr.strip()
        if not expr:
            raise Blocked("empty expression")
        syms: list[Sym] = []

        def ident(m: re.Match) -> str:
            name = m.group(0)
            if name in ("RGB", "and", "or", "not"):
                return name
            v = self.value(name, depth)
            if isinstance(v, Sym):
                syms.append(v)
                return "0"
            return f"({v})"

        py = re.sub(r"\b(0[xX][0-9a-fA-F]+|\d+)[uUlL]*\b", lambda m: m.group(1), expr)
        py = py.replace("&&", " and ").replace("||", " or ")
        py = re.sub(r"!(?!=)", " not ", py)
        py = re.sub(r"(?<![/])/(?![/])", "//", py)
        py = re.sub(r"\b[A-Za-z_]\w*\b", ident, py)
        if syms:
            if re.fullmatch(r"\(?\s*0\s*\)?", py.strip()) and len(syms) == 1:
                return syms[0]
            raise Blocked(f"arithmetic on {syms[0]}")
        try:
            v = eval(py, {"__builtins__": {}}, {"RGB": lambda r, g, b: r | (g << 5) | (b << 10)})
        except Exception as e:  # noqa: BLE001 - anything we can't evaluate blocks the script
            raise Blocked(f"expression {expr!r} ({e})")
        if isinstance(v, bool):
            v = int(v)
        if not isinstance(v, int):
            raise Blocked(f"expression {expr!r}")
        return v


# ---------------------------------------------------------------- gas macros

def split_args(text: str) -> list[str]:
    out, depth, cur = [], 0, ""
    for ch in text:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


class Macro:
    def __init__(self, name: str, params: list[tuple[str, str | None, str]], body: list[str]):
        self.name, self.params, self.body = name, params, body

    @property
    def primitive(self) -> bool:
        """A command (its body is the bytes), not a macro built from other commands."""
        return any(line.startswith(".byte") for line in self.body)

    def bind(self, args: list[str]) -> dict[str, str]:
        # gas also takes arguments separated by spaces ("playsewithpan SE_M_X SOUND_PAN_TARGET")
        if len(args) < len(self.params) and any(re.search(r"\w\s+[\w(-]", a) and "=" not in a for a in args):
            spaced: list[str] = []
            for a in args:
                spaced += a.split() if "=" not in a and "(" not in a else [a]
            args = spaced
        bound: dict[str, str] = {}
        pos = 0
        for a in args:
            m = re.match(r"^(\w+)\s*=(?!=)\s*(.*)$", a)
            if m and any(p[0] == m.group(1) for p in self.params):
                bound[m.group(1)] = m.group(2)
                continue
            if pos < len(self.params) and self.params[pos][2] == "vararg":
                bound[self.params[pos][0]] = ", ".join(x for x in [bound.get(self.params[pos][0], ""), a] if x)
                continue
            while pos < len(self.params) and self.params[pos][0] in bound:
                pos += 1
            if pos >= len(self.params):
                raise Blocked(f"too many arguments to {self.name}")
            bound[self.params[pos][0]] = a
            if self.params[pos][2] != "vararg":
                pos += 1
        for name, default, kind in self.params:
            if name not in bound:
                if kind == "req":
                    raise Blocked(f"{self.name} needs {name}")
                bound[name] = default or ""
        return bound


def load_macros(path: Path) -> dict[str, Macro]:
    macros: dict[str, Macro] = {}
    cur = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("@")[0].strip()
        m = re.match(r"\.macro\s+(\w+)\s*(.*)$", line)
        if m:
            params = []
            for p in split_args(m.group(2)) if "," in m.group(2) else m.group(2).split():
                p = p.strip()
                pm = re.match(r"(\w+)\s*(?::(req|vararg))?\s*(?:=\s*(.*))?$", p)
                if pm:
                    params.append((pm.group(1), pm.group(3), pm.group(2) or ""))
            cur = Macro(m.group(1), params, [])
            macros[cur.name] = cur
            continue
        if line.startswith(".endm"):
            cur = None
            continue
        if cur is not None and line:
            cur.body.append(line)
    return macros


# ---------------------------------------------------------------- scripts

def load_scripts(path: Path) -> tuple[list[str], dict[str, int], list[list[str]]]:
    """Labels in file order, label -> index, and each label's lines (up to the next label)."""
    order: list[str] = []
    lines: list[list[str]] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("@")[0].rstrip()
        if not line.strip() or line.strip().startswith("#") or line.strip().startswith(".include"):
            continue
        m = re.match(r"^(\w+)::?\s*$", line)
        if m:
            order.append(m.group(1))
            lines.append([])
            continue
        if order:
            lines[-1].append(line.strip())
    return order, {name: i for i, name in enumerate(order)}, lines


class Converter:
    def __init__(self, exp: Path, known: dict[str, set[str]]):
        self.c = Constants(exp)
        self.macros = load_macros(exp / "asm/macros/battle_anim_script.inc")
        self.order, self.index, self.lines = load_scripts(exp / "data/battle_anim_scripts.s")
        self.known = known
        self.uniq = 0

    # an argument: a number (s16 like the cart's), or a Sym
    def arg(self, text: str) -> int | Sym:
        v = self.c.eval(text)
        if isinstance(v, Sym):
            return v
        v &= 0xFFFF
        return v - 0x10000 if v >= 0x8000 else v

    def num(self, text: str) -> int:
        v = self.c.eval(text)
        if isinstance(v, Sym):
            raise Blocked(f"{v} where a number is needed")
        return v

    def se(self, text: str) -> str:
        v = self.c.eval(text)
        if not isinstance(v, Sym) or v.kind != "SE":
            raise Blocked(f"sound {text}")
        return v.name

    def pan(self, text: str) -> int:
        v = self.num(text) & 0xFF
        return v - 0x100 if v >= 0x80 else v

    def battler(self, text: str) -> str:
        v = self.num(text)
        if v not in BATTLERS:
            raise Blocked(f"battler {text}")
        return BATTLERS[v]

    def bg(self, text: str) -> int:
        v = self.num(text)
        if v > LAST_CART_BG:
            raise Blocked(f"background {text}")
        return v

    def label(self, text: str) -> str:
        name = text.strip()
        if name not in self.index:
            raise Blocked(f"label {name}")
        self.refs.append(name)
        return name

    def args(self, text: str) -> list:
        return [self.arg(a) for a in split_args(text)] if text.strip() else []

    def primitive(self, name: str, b: dict[str, str]) -> dict:
        p = lambda k: b[k]  # noqa: E731
        if name == "createsprite":
            t = p("template")
            if t not in self.known["T"]:
                raise Blocked(f"template {t}")
            return {"op": "createsprite", "template": t,
                    "animBattler": "target" if self.num(p("anim_battler")) == 1 else "attacker",
                    "subpriority": self.num(p("subpriority_offset")) & 0x7F, "args": self.args(p("argv"))}
        if name in ("createvisualtask", "createsoundtask"):
            t = p("addr")
            if t not in self.known["K"] and t.replace("AnimTask_", "") not in self.known["K"]:
                raise Blocked(f"task {t}")
            row = {"op": name, "task": t, "args": self.args(p("argv"))}
            if name == "createvisualtask":
                row["priority"] = self.num(p("priority"))
            return row
        if name == "unloadspritegfx":
            v = self.c.eval(p("tag"))
            if not isinstance(v, Sym) or v.kind != "TAG":
                raise Blocked(f"tag {p('tag')}")
            if v.name not in self.known["G"]:
                raise Blocked(f"graphics {v.name}")
            return {"op": "unloadspritegfx", "tag": v.name}
        simple = {"waitforvisualfinish", "end", "return", "blendoff", "restorebg", "waitbgfadeout",
                  "waitbgfadein", "waitsound", "stopsound", "nop", "nop2", "splitbgprio_all"}
        if name in simple:
            return {"op": "nop" if name == "nop2" else name}
        if name == "delay":
            return {"op": "delay", "frames": self.num(p("frames")) & 0xFF}
        if name == "playse":
            return {"op": "playse", "se": self.se(p("se"))}
        if name in ("monbg", "clearmonbg", "monbg_static", "clearmonbg_static", "splitbgprio",
                    "invisible", "visible"):
            return {"op": name, "battler": self.battler(p("battler"))}
        if name == "splitbgprio_foes":
            return {"op": "splitbgprio", "battler": self.battler(p("battler")), "mode": "foes"}
        if name == "setalpha":
            return {"op": "setalpha", "eva": self.num(p("eva")), "evb": self.num(p("evb"))}
        if name in ("call", "goto"):
            return {"op": name, "label": self.label(p("ptr"))}
        if name == "setarg":
            return {"op": "setarg", "argId": self.num(p("argId")), "value": self.arg(p("value"))}
        if name == "choosetwoturnanim":
            return {"op": name, "label1": self.label(p("ptr1")), "label2": self.label(p("ptr2"))}
        if name == "jumpifmoveturn":
            return {"op": name, "turn": self.num(p("value")), "label": self.label(p("ptr"))}
        if name == "jumpargeq":
            return {"op": name, "argId": self.num(p("argId")), "value": self.arg(p("value")),
                    "label": self.label(p("ptr"))}
        if name == "jumpifcontest":
            return {"op": name, "label": self.label(p("ptr"))}
        if name in ("fadetobg", "changebg"):
            return {"op": name, "bg": self.bg(p("bg"))}
        if name == "fadetobgfromset":
            return {"op": name, "bg1": self.bg(p("bgOpponent")), "bg2": self.bg(p("bgPlayer")),
                    "bg3": self.bg(p("bgContest"))}
        if name == "playsewithpan":
            return {"op": name, "se": self.se(p("se")), "pan": self.pan(p("pan"))}
        if name == "setpan":
            return {"op": name, "pan": self.pan(p("pan"))}
        if name in ("panse", "panse_adjustnone", "panse_adjustall"):
            row = {"op": "panse", "se": self.se(p("se")), "pan": self.pan(p("currentPan")),
                   "targetPan": self.pan(p("targetPan")), "step": self.pan(p("incrementPan")),
                   "wait": self.num(p("delay"))}
            if name != "panse":
                row["mode"] = name[len("panse_"):]
            return row
        if name == "loopsewithpan":
            return {"op": name, "se": self.se(p("se")), "pan": self.pan(p("pan")),
                    "wait": self.num(p("wait")), "times": self.num(p("times"))}
        if name == "waitplaysewithpan":
            return {"op": name, "se": self.se(p("se")), "pan": self.pan(p("pan")), "wait": self.num(p("wait"))}
        if name == "setbldcnt":
            return {"op": name, "value": self.num(p("bldcnt"))}
        raise Blocked(f"opcode {name}")

    def run_line(self, line: str, out: list, stack: list, depth: int = 0) -> None:
        """One script or macro-body line: conditionals, a macro (expanded) or a primitive."""
        if depth > 12:
            raise Blocked("macro depth")
        head, _, rest = line.partition(" ")
        head = head.strip()
        rest = rest.strip()
        active = all(s[0] for s in stack)
        if head in (".if", ".ifb", ".ifnb"):
            if not active:
                stack.append([False, True])
                return
            if head == ".if":
                cond = bool(self.num(rest))
            elif head == ".ifb":
                cond = rest == ""
            else:
                cond = rest != ""
            stack.append([cond, cond])
            return
        if head == ".else":
            top = stack[-1]
            top[0] = (not top[1]) and all(s[0] for s in stack[:-1])
            top[1] = True
            return
        if head == ".endif":
            stack.pop()
            return
        if not active or head.startswith(".L") or head.endswith(":"):
            return
        if head.startswith("."):
            raise Blocked(f"directive {head}")
        macro = self.macros.get(head)
        if macro is None:
            raise Blocked(f"opcode {head}")
        bound = macro.bind(split_args(rest) if rest else [])
        if macro.primitive:
            out.append(self.primitive(head, bound))
            return
        self.uniq += 1
        names = sorted(bound, key=len, reverse=True)
        inner: list = []
        for body in macro.body:
            text = body.replace("\\@", str(self.uniq)).replace("\\()", "")
            for n in names:
                text = re.sub(r"\\" + n + r"(?!\w)", bound[n].replace("\\", r"\\"), text)
            self.run_line(text, out, inner, depth + 1)

    def convert_label(self, label: str) -> list:
        """A label's rows, falling through into the next label until end/return/goto."""
        out: list = []
        i = self.index[label]
        stack: list = []
        while i < len(self.order):
            for line in self.lines[i]:
                self.run_line(line, out, stack)
                if out and out[-1]["op"] in ("end", "return", "goto") and not stack:
                    return out
            i += 1
        raise Blocked(f"{label} runs off the end")

    def convert_move(self, entry: str) -> dict[str, list]:
        """Every label the move's script reaches: { label = rows }.

        The engine (like the cart) keeps one return address, and expansion's subroutines call
        others. So a subroutine without jumps is inlined where it is called; one that branches
        (a background chosen by side) stays a real call, and nothing it reaches may call again."""
        self.refs = [entry]
        done: dict[str, list] = {}
        while self.refs:
            lab = self.refs.pop()
            if lab not in done:
                done[lab] = self.convert_label(lab)

        JUMPS = ("return", "end", "goto", "jumpargeq", "jumpifmoveturn", "jumpifcontest", "choosetwoturnanim")
        flat: dict[str, list] = {}

        def expand(lab: str, depth: int = 0) -> list:
            if lab in flat:
                return flat[lab]
            if depth > 8:
                raise Blocked("calls nested too deep")
            out = []
            for row in done[lab]:
                if row["op"] == "call":
                    body = expand(row["label"], depth + 1)
                    if body and body[-1]["op"] == "return" and not any(
                            r["op"] in JUMPS or r["op"] == "call" for r in body[:-1]):
                        out += body[:-1]
                        continue
                out.append(row)
            flat[lab] = out
            return out

        for lab in list(done):
            expand(lab)

        def reach(start: list[str], follow_calls: bool) -> set[str]:
            seen, todo = set(), list(start)
            while todo:
                lab = todo.pop()
                if lab in seen:
                    continue
                seen.add(lab)
                for row in flat[lab]:
                    if row["op"] == "call" and not follow_calls:
                        continue
                    for k in ("label", "label1", "label2"):
                        if k in row:
                            todo.append(row[k])
            return seen

        keep = reach([entry], True)
        called = [row["label"] for lab in keep for row in flat[lab] if row["op"] == "call"]
        for lab in reach(called, False):
            if any(row["op"] == "call" for row in flat[lab]):
                raise Blocked(f"subroutine {lab} calls another")
        return {lab: flat[lab] for lab in keep}


# ---------------------------------------------------------------- closest cart animation

# what an animation is made of: its sprites, tasks, backgrounds, sounds and graphics
FEATURE = re.compile(r"\b(g\w*Template\w*|AnimTask_\w+|SoundTask_\w+|BG_\w+|SE_\w+|ANIM_TAG_\w+)\b")


def features(conv: Converter, entry: str) -> set[str]:
    """Every piece the script uses (macros expanded by text, calls and gotos followed)."""
    def text_of(line: str, depth: int = 0) -> str:
        head = line.split(None, 1)[0] if line.split() else ""
        m = conv.macros.get(head)
        if m is None or m.primitive or depth > 4:
            return line
        return line + "\n" + "\n".join(text_of(b, depth + 1) for b in m.body)

    feats: set[str] = set()
    seen: set[str] = set()
    todo = [entry]
    while todo and len(seen) < 40:
        lab = todo.pop()
        if lab in seen or lab not in conv.index:
            continue
        seen.add(lab)
        i = conv.index[lab]
        stop = False
        while i < len(conv.order) and not stop:
            for line in conv.lines[i]:
                feats |= set(FEATURE.findall(text_of(line)))
                parts = line.split(None, 1)
                for ident in re.findall(r"\b\w+\b", parts[1] if len(parts) > 1 else ""):
                    if ident in conv.index and ident != lab:
                        todo.append(ident)
                if parts and parts[0] in ("end", "return", "goto"):
                    stop = True
                    break
            i += 1
    return feats


# reviewed by eye: the closest-by-pieces pick that still looks wrong (Lava Plume as Growth,
# Acupressure as Thunder Shock); these keep data/moves.lua's look unless HAND names one
REJECT = {"LAVA_PLUME", "SMART_STRIKE", "PUNISHMENT", "DRAGON_DARTS", "BELCH", "FLOWER_TRICK", "PLUCK",
          "STONE_EDGE", "DRAGON_RUSH", "SACRED_SWORD", "SECRET_SWORD", "GRASSY_TERRAIN", "ELECTRIC_TERRAIN",
          "ACUPRESSURE", "MAGNETIC_FLUX", "HEAL_BLOCK", "CONFIDE", "ATTACK_ORDER"}
# picked by hand (expansion's MOVE_ names, Gen 3 numbers): Psychic status moves the type/power
# scorer gave Rest, which shows the user falling asleep
HAND = {"PSYCHIC_TERRAIN": "CONFUSION", "GRAVITY": "CONFUSION", "TAKE_HEART": "CALM_MIND",
        "LUNAR_BLESSING": "MOONLIGHT", "POWER_SPLIT": "SKILL_SWAP", "GUARD_SPLIT": "SKILL_SWAP",
        "POWER_SWAP": "SKILL_SWAP", "GUARD_SWAP": "SKILL_SWAP", "SPEED_SWAP": "SKILL_SWAP",
        "HEART_SWAP": "SKILL_SWAP", "POWER_TRICK": "SKILL_SWAP"}


def closest_looks(conv: Converter, exp: Path, entries: dict[str, str], moves: list[str],
                  looks: dict[str, int], scripted: set[str]) -> tuple[dict[str, int], list[str]]:
    """For a move without a script of its own: the cart move whose expansion animation shares the
    most with the move's (rare pieces count more than a hit splat), when clearly closer than the
    `look` data/moves.lua picked by type and power."""
    import math
    text = (exp / "include/constants/moves.h").read_text(encoding="utf-8")
    cart = {}
    for name, num in re.findall(r"\bMOVE_(\w+)\s*=\s*(\d+)\s*,", text):
        if 1 <= int(num) <= 354:
            cart.setdefault(int(num), name)
    norm = lambda x: re.sub(r"[^a-z0-9]", "", x.lower())  # noqa: E731
    corpus = {}
    for num, name in cart.items():
        lab = entries.get(norm(name))
        if lab:
            corpus[num] = features(conv, lab)
    df = Counter(f for fs in corpus.values() for f in fs)
    idf = {f: math.log(len(corpus) / (1 + n)) + 0.1 for f, n in df.items()}

    def score(a: set[str], b: set[str]) -> float:
        inter = sum(idf.get(f, 3.0) for f in a & b)
        union = sum(idf.get(f, 3.0) for f in a | b)
        return inter / union if union else 0.0

    out, notes = {}, []
    for mid in moves:
        lab = entries.get(norm(mid))
        if mid in scripted or not lab:
            continue
        mine = features(conv, lab)
        best, best_s = None, 0.0
        for num, fs in corpus.items():
            sc = score(mine, fs)
            if sc > best_s:
                best, best_s = num, sc
        cur = looks.get(mid)
        cur_s = score(mine, corpus.get(cur, set()))
        if mid in HAND:
            num = next(n for n, name in cart.items() if name == HAND[mid])
            out[mid] = num
            notes.append(f"  {mid}: {cart.get(cur, cur)} -> {HAND[mid]} (by hand)")
        elif mid not in REJECT and best and best != cur and best_s >= 0.3 and best_s >= cur_s + 0.1:
            out[mid] = best
            notes.append(f"  {mid}: {cart.get(cur, cur)} ({cur_s:.2f}) -> {cart[best]} ({best_s:.2f})")
    return out, notes


# ---------------------------------------------------------------- output

def lua(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, Sym):
        return f'"{v.kind}:{v.name}"'
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, list):
        return "{ " + ", ".join(lua(x) for x in v) + " }"
    if isinstance(v, dict):
        order = ["op"] + sorted(k for k in v if k != "op")
        return "{ " + ", ".join(f"{k} = {lua(v[k])}" for k in order if k in v) + " }"
    raise TypeError(type(v))


def known_pieces(engine: Path) -> dict[str, set[str]]:
    out = subprocess.run(["luajit", str(ROOT / "tools/anim_known.lua")], cwd=engine,
                         capture_output=True, text=True, check=True).stdout
    known: dict[str, set[str]] = defaultdict(set)
    for line in out.splitlines():
        kind, _, name = line.partition(" ")
        if name:
            known[kind].add(name)
    if not known["T"]:
        sys.exit("no imported Gen 3 cart found under " + str(engine))
    return known


def main() -> None:
    gen1 = ROOT.parent / "gen1recomp"
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--expansion", type=Path, default=ROOT.parent / "pokeemerald-expansion")
    ap.add_argument("--engine", type=Path, default=gen1)
    ap.add_argument("--out", type=Path, default=ROOT / "data" / "anims.lua")
    ap.add_argument("--report", type=Path, default=ROOT / "tools" / ".cache" / "anims_report.txt")
    a = ap.parse_args()

    known = known_pieces(a.engine)
    conv = Converter(a.expansion, known)
    version = ".".join(conv.c.raw.get(f"EXPANSION_VERSION_{k}", "?") for k in ("MAJOR", "MINOR", "PATCH"))
    norm = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())  # noqa: E731
    entries = {norm(lab[len("gBattleAnimMove_"):]): lab for lab in conv.order if lab.startswith("gBattleAnimMove_")}

    moves, looks = [], {}
    for line in (ROOT / "data/moves.lua").read_text(encoding="utf-8").splitlines():
        m = re.match(r'\s*\{ id = "(\w+)".*?\blook = (\d+)', line)
        if m:
            moves.append(m.group(1))
            looks[m.group(1)] = int(m.group(2))

    kept: dict[str, str] = {}
    labels: dict[str, list] = {}
    why: dict[str, str] = {}
    for mid in moves:
        entry = entries.get(norm(mid))
        if not entry:
            why[mid] = "no script in expansion"
            continue
        try:
            got = conv.convert_move(entry)
        except Blocked as e:
            why[mid] = str(e)
            continue
        kept[mid] = entry
        labels.update(got)

    better, notes = closest_looks(conv, a.expansion, entries, moves, looks, set(kept))

    L = [
        "-- Generated by tools/build_anims.py. Do not edit by hand.",
        f"-- Battle animations for the newer moves. Based off RHH's pokeemerald-expansion {version}",
        "-- https://github.com/rh-hideout/pokeemerald-expansion/ : its animation scripts, as the rows",
        "-- the engine's animation player runs. Only scripts built from pieces Gen 3 carts already have",
        "-- (templates, graphics, tasks); src/anims.lua resolves \"SE:\" sounds and \"TAG:\" graphics",
        "-- in the running game. A move not listed keeps the cart animation named in data/moves.lua.",
        "return {",
        f'  source = "pokeemerald-expansion {version}",',
        "  moves = {",
    ]
    for mid in moves:
        if mid in kept:
            L.append(f'    {mid} = "{kept[mid]}",')
    L += ["  },", "  -- no script of its own: the cart move whose animation is closest to expansion's",
          "  looks = {"]
    for mid in moves:
        if mid in better:
            L.append(f"    {mid} = {better[mid]},")
    L += ["  },", "  labels = {"]
    for lab in sorted(labels):
        L.append(f'    ["{lab}"] = {{')
        for row in labels[lab]:
            L.append("      " + lua(row) + ",")
        L.append("    },")
    L += ["  },", "}", ""]
    a.out.write_text("\n".join(L), encoding="utf-8", newline="\n")

    a.report.parent.mkdir(parents=True, exist_ok=True)
    reasons = Counter(re.sub(r" .*", "", w) for w in why.values())
    pieces = Counter(why.values())
    R = [f"{len(kept)} of {len(moves)} moves use expansion's animation; the rest keep their cart look.",
         "", "left out, by reason:"] + [f"  {n:4d}  {r}" for r, n in reasons.most_common()]
    R += ["", "most common missing pieces:"] + [f"  {n:4d}  {p}" for p, n in pieces.most_common(40)]
    R += ["", f"closer cart animation for {len(better)} of the rest (old look -> new, similarity):"] + notes
    R += ["", "per move:"] + [f"  {m}: {w}" for m, w in sorted(why.items())]
    a.report.write_text("\n".join(R) + "\n", encoding="utf-8")
    print(f"{len(kept)} of {len(moves)} moves use expansion's animation ({len(labels)} scripts) -> {a.out}")
    print(f"left out: {dict(reasons.most_common())} (report: {a.report})")
    print(f"a closer cart animation for {len(better)} of the others")


if __name__ == "__main__":
    main()
