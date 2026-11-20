#!/usr/bin/env python3
"""Battle animations from the Gen 9 Move Animation Project (a Pokémon Essentials v21.1 pack,
https://eeveeexpo.com/resources/1480/; credited in CREDITS.md).

The pack's Data/PkmnAnimations.rxdata holds Essentials animations: frames of "cels" (a 192 x 192
pattern from the animation's sheet in Graphics/Animations, placed relative to the user, the
target, the line between them, or the screen), plus timings (sounds, background and foreground
pictures and colours). This converts, into data the mod's "NdxEss" visual task plays
(src/ess_anims.lua), the pack's animation of every move it names: WoobleDex's newer moves and the
Gen 1-3 moves the carts have (CART_KEEPS aside), their charging turn for two-turn moves, and the
"Common:" animations that are the same as a cart's status, weather and trap ones (COMMONS):

  data/ess_anims.lua       the index: sheets, backgrounds, sounds, moves and common animations
  data/ess/<MOVE>.lua      a move's frames and timings (its OppMove version and charging turn too),
                           loaded when it plays
  assets/ess/cels_N.png    the atlas: every cel the moves use, scaled to the Gen 3 battle (SCALE)
                           and trimmed, on pages up to 1024 square, 256 colours each
  assets/ess/bgs_N.png     background and foreground pictures, scaled to the 240 x 160 screen, on
                           pages up to 1024 square, 256 colours each
  assets/ess/se/*.ogg      the pack's sounds that have no close Gen 3 match (mono, 22 kHz)

A sound is a Gen 3 cart sound when it is the pack's recording of a Gen 1-3 move's sound
("PRSFX- Thunder Punch2" -> the second sound in Thunder Punch's script, from pokeemerald-expansion's
data/battle_anim_scripts.s); every other sound is the pack's own, converted with ffmpeg.

    python tools/build_ess_anims.py [--pack <Gen 9 Move Animation Project>] [--no-sounds]

SKIP lists the moves that keep their current animation, with why; BORROW gives a move the pack
has no animation for another move's. tests/drivers/ess_anims_probe.lua and tools/ess_gallery.py
make a review page from the real game.
"""
from __future__ import annotations

import argparse
import colorsys
import json
import math
import os
import re
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ess_marshal as M  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PACK = ROOT.parent / "1SpriteReferences" / "Gen 9 Move Animation Project"
EXPANSION = ROOT.parent / "pokeemerald-expansion"

# Essentials' battle (512 x 384) to Gen 3's (240 x 160): the user -> target line is 286 px there,
# (72,80) -> (176,40) = 111 px here, and Essentials draws battlers at twice a 96 px sprite (64 here)
SCALE = 0.375
# atlas pages: no side over 1024 (well inside the 2048 every Android GPU takes), so each page's 256
# colours cover fewer, more alike pictures
CEL_PAGE = 1024
BG_PAGE = 1024
CEL = 192
CELS_PER_ROW = 5
CELL = round(CEL * SCALE)

# moves that keep their current animation: MOVE -> why
SKIP: dict[str, str] = {
}
# Gen 3 moves whose cart animation does something the pack's can't
CART_KEEPS: dict[str, str] = {
    "CURSE": "the cart picks the Ghost or the other Curse by the turn number it is given",
    "BIDE": "the cart picks storing or unleashing by the turn",
    "TRANSFORM": "the cart's animation gives the user the target's picture for the rest of the battle",
    "SUBSTITUTE": "the cart's animation turns the user into the doll",
}
# a newer move the pack has no animation for -> the move whose animation it plays (a cart move
# only ever plays the one the pack names it by)
BORROW: dict[str, str] = {
    "IVY_CUDGEL": "WOOD_HAMMER",   # a club swung with Grass power
}
# two-turn moves: "charge" plays the pack's charging animation on the first turn; "hide" keeps the
# cart's first turn (it hides the user: Fly, Dig, Dive, Bounce) and shows the user again on the second
TWO_TURN_CART = {"RAZOR_WIND": "charge", "SOLAR_BEAM": "charge", "SKULL_BASH": "charge",
                 "SKY_ATTACK": "charge", "FLY": "hide", "DIG": "hide", "DIVE": "hide", "BOUNCE": "hide"}
# a newer move on a cart's two-turn effect (data/moves.lua `effect`)
TWO_TURN_EFFECTS = {39: "charge", 75: "charge", 145: "charge", 151: "charge", 155: "hide"}
# the cart's own table animations -> the pack's "Common:" one; TURN_TRAP by the trapping move the
# cart's GetTrappedMoveAnimId task finds (its argument 0)
COMMONS = {
    "status": {"STATUS_PSN": "Poison", "STATUS_CONFUSION": "Confusion", "STATUS_BRN": "Burn",
               "STATUS_INFATUATION": "Attract", "STATUS_SLP": "Sleep", "STATUS_PRZ": "Paralysis",
               "STATUS_FRZ": "Frozen", "STATUS_CURSED": "Curse"},
    "general": {"RAIN_CONTINUES": "Rain", "SUN_CONTINUES": "Sun", "SANDSTORM_CONTINUES": "Sandstorm",
                "HAIL_CONTINUES": "Hail", "LEECH_SEED_DRAIN": "LeechSeed", "FOCUS_PUNCH_SETUP": "FocusPunch"},
    "special": {"LVL_UP": "LevelUp"},
}
# (0 is Bind or Wrap alike: the cart's own plays, so neither borrows the other's)
TRAP = {1: "FireSpin", 2: "Whirlpool", 3: "Clamp", 4: "SandTomb"}

# the cel array (AnimFrame in Essentials' BattleAnimationPlayer)
X, Y, ZOOMX, ANGLE, MIRROR, BLEND, VISIBLE, PATTERN, OPACITY = range(9)
ZOOMY, CR, CG, CB, CA, TR, TG, TB, TGRAY = 11, 12, 13, 14, 15, 16, 17, 18, 19
PRIORITY, FOCUS = 25, 26
# what data/ess/*.lua keeps of a cel, in this order; trailing defaults are left off
FIELDS = [PATTERN, X, Y, FOCUS, ZOOMX, ZOOMY, ANGLE, OPACITY, BLEND, MIRROR, PRIORITY,
          CR, CG, CB, CA, TR, TG, TB, TGRAY]
DEFAULTS = [None, None, None, None, 100, 100, 0, 255, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0]


def slug(name: str) -> str:
    base = re.sub(r"\.(png|wav|ogg|mp3)$", "", name, flags=re.I)
    out = re.sub(r"[^a-z0-9]+", "_", base.lower()).strip("_")
    return out or "x" + base.encode("utf-8").hex()   # "!.png"


def find_file(folder: Path, name: str, exts) -> Path | None:
    """The pack names files with and without extensions, in any case."""
    if not name:
        return None
    want = name.lower()
    index = find_file.cache.get(folder)
    if index is None:
        index = {p.name.lower(): p for p in folder.iterdir()} if folder.is_dir() else {}
        find_file.cache[folder] = index
    base = re.sub(r"\.(png|wav|ogg|mp3)$", "", want)
    # as named, with an extension, then the pack's usual prefixes ("Overheat1.ogg" is
    # "PRSFX- Overheat1.wav"; the foe's "X Opp BG" falls back to "X BG")
    for cand in (base, "prsfx- " + base, base.replace(" opp ", " ")):
        if cand + want[len(base):] in index:
            return index[cand + want[len(base):]]
        for e in exts:
            if cand + e.lower() in index:
                return index[cand + e.lower()]
    # by letters and digits alone ("Sketch and Lick" is "PRAS- Sketch + Lick")
    loose = re.sub(r"[^a-z0-9]", "", base.replace(" and ", ""))
    for name, path in index.items():
        if loose and re.sub(r"[^a-z0-9]", "", re.sub(r"\.(png|wav|ogg|mp3)$", "", name)) in (loose, "prsfx" + loose, "pras" + loose):
            return path
    return None


find_file.cache = {}


def key(k: str) -> str:
    return k if re.match(r"^[A-Za-z_]\w*$", k) else "[%s]" % json.dumps(k)


def lua(v, indent="") -> str:
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, np.integer)):
        return str(int(v))
    if isinstance(v, float):
        return ("%.4f" % v).rstrip("0").rstrip(".")
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, (list, tuple)):
        return "{" + ", ".join(lua(x) for x in v) + "}"
    if isinstance(v, dict):
        parts = []
        for k in v:
            key = k if re.match(r"^[A-Za-z_]\w*$", str(k)) else "[%s]" % lua(k)
            parts.append("%s = %s" % (key, lua(v[k])))
        return "{ " + ", ".join(parts) + " }"
    raise TypeError(type(v))


# ---------- the moves -------------------------------------------------------------------------

def read_moves():
    """WoobleDex's newer moves {id: effect}, and the carts' {name: number} (pokeemerald-expansion's
    move constants 1-354, the numbers every Gen 3 cart uses)."""
    src = (ROOT / "data" / "moves.lua").read_text(encoding="utf-8")
    new = {i: int(e) for i, e in re.findall(r'id = "(\w+)", index = \d+,.*?effect = (\d+),', src)}
    read_moves.on_user = {i for i, t in re.findall(r'id = "(\w+)", index = \d+,.*?target = (\d+),', src) if int(t) == 16}
    cart = {}
    text = (EXPANSION / "include" / "constants" / "moves.h").read_text(encoding="utf-8")
    for name, num in re.findall(r"^\s*MOVE_(\w+) = (\d+),", text, re.M):
        if 1 <= int(num) <= 354:
            cart[name] = int(num)
    return new, cart


def norm(name: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", name.upper())


def is_real(an) -> bool:
    """Not a placeholder: more than one frame, and something to see."""
    frames = an.get("array") or []
    if len(frames) <= 1:
        return False
    if any(t.get("timingType") in (1, 3) for t in an.get("timing") or []):
        return True
    graphic = bool(an.get("graphic"))
    for f in frames:
        for i, c in enumerate(f or []):
            if not c:
                continue
            if c[PATTERN] >= 0 and graphic and c[VISIBLE] == 1 and c[OPACITY] > 0:
                return True
            if c[PATTERN] < 0 and i < 2:
                home = (128, 224) if c[PATTERN] == -1 else (384, 96)
                if (c[X], c[Y]) != home or c[OPACITY] < 255 or (c[CA] or 0) > 0 or c[ZOOMX] != 100:
                    return True
    return False


def select(anims, names):
    """{MOVE: {move, opp, charge, charge_opp: animation}} for each name the pack animates, plus
    {C_<NAME>: {move}} for the COMMONS / TRAP ones."""
    by = {norm(n): n for n in names}
    chosen: dict[str, dict] = {}
    common = {norm(n): n for t in COMMONS.values() for n in t.values()} | {norm(n): n for n in TRAP.values()}

    def put(name, kind, an):
        if kind not in chosen.get(name, {}) and is_real(an):
            chosen.setdefault(name, {})[kind] = an

    for an in anims:
        name = an.get("name") or ""
        m = re.match(r"^(Opp)?Move:\s*(.*)$", name)
        if m:
            move = by.get(norm(m.group(2)))
            if move and move not in SKIP:
                put(move, "opp" if m.group(1) else "move", an)
            continue
        m = re.match(r"^(?:Common:)?\s*(Opp\s*)?(.+?)\s+charging(\s+opp)?\s*$", name, re.I)
        if m:
            move = by.get(norm(m.group(2)))
            if move:
                put(move, "charge_opp" if (m.group(1) or m.group(3)) else "charge", an)
            continue
        m = re.match(r"^Common:(.*)$", name)
        if m and norm(m.group(1)) in common:
            put("C_" + common[norm(m.group(1))].upper(), "move", an)
    for move, src in BORROW.items():
        if move in by.values() and move not in chosen and src in chosen:
            chosen[move] = {k: v for k, v in chosen[src].items() if k in ("move", "opp")}
    return {k: v for k, v in sorted(chosen.items()) if "move" in v}


# ---------- sounds ----------------------------------------------------------------------------

def cart_sounds():
    """Gen 1-3 moves' sounds, in script order: "THUNDER_PUNCH" -> ["SE_M_THUNDER_WAVE", ...]."""
    out = {}
    moves_h = EXPANSION / "include" / "constants" / "moves.h"
    scripts = EXPANSION / "data" / "battle_anim_scripts.s"
    if not (moves_h.exists() and scripts.exists()):
        print("warning: no pokeemerald-expansion at %s; every sound is the pack's" % EXPANSION)
        return out
    old = {}
    for name, num in re.findall(r"^\s*MOVE_(\w+) = (\d+),", moves_h.read_text(encoding="utf-8"), re.M):
        if 1 <= int(num) <= 354:
            old["".join(w.capitalize() for w in name.split("_"))] = name
    cur = None
    for line in scripts.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^gBattleAnimMove_(\w+)::", line)
        if m:
            cur = old.get(m.group(1))
            if cur:
                out[cur] = []
            continue
        if cur and re.match(r"^\S", line):
            cur = None
        if cur:
            for se in re.findall(r"\b(SE_[A-Z0-9_]+)\b", line):
                out[cur].append(se)
    return {k: v for k, v in out.items() if v}


def cart_match(name: str, carts) -> str | None:
    base = re.sub(r"\.(wav|ogg|mp3)$", "", name, flags=re.I)
    m = re.match(r"^PRSFX-\s*(.+?)\s*(\d*)$", base)
    if not m:
        return None
    move = re.sub(r"[^A-Z0-9]+", "_", m.group(1).upper()).strip("_")
    ses = carts.get(move)
    if not ses:
        return None
    n = int(m.group(2)) if m.group(2) else 1
    return ses[n - 1] if 0 < n <= len(ses) else ses[0]


# ---------- the art ---------------------------------------------------------------------------

def hue_shift(img: Image.Image, hue: int) -> Image.Image:
    if not hue:
        return img
    a = np.asarray(img.convert("RGBA")).astype(np.float32) / 255
    rgb = a[..., :3]
    mx, mn = rgb.max(-1), rgb.min(-1)
    h = np.zeros_like(mx)
    d = np.where(mx - mn == 0, 1, mx - mn)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    h = np.where(mx == r, (g - b) / d % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6
    h = np.where(mx - mn == 0, 0, h)
    s = np.where(mx == 0, 0, (mx - mn) / np.where(mx == 0, 1, mx))
    v = mx
    h = (h + hue / 360.0) % 1
    i = np.floor(h * 6).astype(int) % 6
    f = h * 6 - np.floor(h * 6)
    p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    choices = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]
    out = np.zeros_like(rgb)
    for k, (cr, cg, cb) in enumerate(choices):
        sel = i == k
        out[..., 0] = np.where(sel, cr, out[..., 0])
        out[..., 1] = np.where(sel, cg, out[..., 1])
        out[..., 2] = np.where(sel, cb, out[..., 2])
    a[..., :3] = out
    return Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGBA")


# a thin stroke shrunk to 37% fades to a few faint pixels: the cel is averaged with its colours
# weighted by their alpha (no dark fringes), then its alpha is raised by ALPHA_BOOST
ALPHA_BOOST = 1.4


def shrink(img: Image.Image, w: int, h: int | None = None) -> Image.Image:
    h = h or w
    a = np.asarray(img.convert("RGBA")).astype(np.float32) / 255
    pm = np.concatenate([a[..., :3] * a[..., 3:4], a[..., 3:4]], -1)
    small = np.asarray(Image.fromarray((pm * 255 + 0.5).astype(np.uint8), "RGBA").resize((w, h), Image.BOX))
    small = small.astype(np.float32) / 255
    al = small[..., 3:4]
    rgb = np.where(al > 0, small[..., :3] / np.maximum(al, 1e-6), 0)
    al = np.clip(al * ALPHA_BOOST, 0, 1)
    out = np.concatenate([np.clip(rgb, 0, 1), al], -1)
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA")


class Sheets:
    """Each sheet's patterns that the chosen moves use, scaled and packed in a grid."""

    def __init__(self, pack: Path):
        self.dir = pack / "Graphics" / "Animations"
        self.sheets: dict[str, dict] = {}   # key -> {file, hue, used: {pattern: cel or None}}
        self.images: dict[str, Image.Image] = {}

    def key(self, graphic: str, hue: int) -> str | None:
        path = find_file(self.dir, graphic, (".png",))
        if not path:
            return None
        k = slug(path.name) + ("_h%d" % hue if hue else "")
        if k not in self.sheets:
            self.sheets[k] = {"path": path, "hue": hue, "used": {}}
        return k

    def image(self, k):
        if k not in self.images:
            s = self.sheets[k]
            self.images[k] = hue_shift(Image.open(s["path"]).convert("RGBA"), s["hue"])
        return self.images[k]

    def cel(self, k, pattern):
        """The new index of a pattern, or None when it draws nothing."""
        used = self.sheets[k]["used"]
        if pattern not in used:
            img = self.image(k)
            x, y = (pattern % CELS_PER_ROW) * CEL, (pattern // CELS_PER_ROW) * CEL
            crop = img.crop((x, y, x + CEL, y + CEL))   # off the sheet: transparent
            if crop.getbbox() is None or crop.getchannel("A").getbbox() is None:
                used[pattern] = None
            else:
                used[pattern] = crop
        return pattern if used[pattern] is not None else None

    def cels(self):
        """-> {key: {map: pattern -> n, cels: [(image trimmed to what it draws, ox, oy)]}}: each used
        pattern shrunk to CELL, numbered in pattern order; (ox, oy) is where the trimmed image sat."""
        index = {}
        for k in sorted(self.sheets):
            used = {p: c for p, c in sorted(self.sheets[k]["used"].items()) if c is not None}
            if not used:
                continue
            mapping, cels = {}, []
            for n, (p, crop) in enumerate(used.items()):
                small = shrink(crop, CELL)
                bb = small.getchannel("A").getbbox() or (0, 0, 1, 1)
                cels.append((small.crop(bb), bb[0], bb[1]))
                mapping[p] = n
            index[k] = {"map": mapping, "cels": cels}
        return index


# ---------- the atlas -------------------------------------------------------------------------

PAD = 1   # transparent pixels between pictures


def pack_pages(items, limit):
    """Shelf-packs [(key, image)] in the order given into pages no larger than limit x limit.
    -> pages [(width, height)], places {key: (page, x, y)}"""
    pages, places = [], {}
    x = y = shelf = 0
    used_w = 0
    page = -1

    def new_page():
        nonlocal page, x, y, shelf, used_w
        if page >= 0:
            pages.append((used_w, y + shelf))
        page += 1
        x = y = shelf = used_w = 0

    new_page()
    for key, img in items:
        w, h = img.size
        if w > limit or h > limit:
            raise ValueError("%s is %dx%d, larger than a page" % (key, w, h))
        if x + w > limit:
            x, y, shelf = 0, y + shelf + PAD, 0
        if y + h > limit:
            new_page()
        places[key] = (page, x, y)
        x += w + PAD
        shelf = max(shelf, h)
        used_w = max(used_w, x - PAD)
    pages.append((used_w, y + shelf))
    return pages, places


def write_pages(prefix, items, places, sizes, out: Path):
    """Pastes each page, quantizes it to 256 colours (tools/ess_quant.py), saves <prefix>_<n>.png."""
    import ess_quant
    files = []
    for n, (w, h) in enumerate(sizes):
        page = Image.new("RGBA", (max(1, w), max(1, h)), (0, 0, 0, 0))
        for key, img in items:
            pg, x, y = places[key]
            if pg == n:
                page.paste(img, (x, y))
        name = "%s_%d.png" % (prefix, n + 1)
        ess_quant.quantize(page, 256).save(out / name, optimize=True)
        files.append({"file": "assets/ess/" + name, "w": page.width, "h": page.height})
    return files


# ---------- conversion ------------------------------------------------------------------------

def color_of(t):
    return [t.get(k) for k in ("colorRed", "colorGreen", "colorBlue", "colorAlpha")]


def convert(an, sheets: Sheets, bgs: dict, sounds: dict, carts, pack: Path, stats):
    graphic = an.get("graphic") or ""
    hue = int(an.get("hue") or 0)
    key = sheets.key(graphic, hue) if graphic else None
    if graphic and not key:
        stats["missing_sheet"].add(graphic)
    frames = []
    for f in an.get("array") or []:
        cels = []
        for slot, c in enumerate(f or []):
            if not c:
                continue
            p = c[PATTERN]
            if p >= 0:
                if slot < 2 or not key or c[VISIBLE] != 1 or c[OPACITY] <= 0:
                    continue
                if sheets.cel(key, p) is None:
                    continue
            elif slot >= 2:
                # a copy of a battler's picture in a free slot (afterimages, a user thrown about):
                # -3 the user's, -4 the target's
                if c[VISIBLE] != 1 or c[OPACITY] <= 0:
                    continue
                p = -3 if p == -1 else -4
            v = [c[i] if c[i] is not None else 0 for i in FIELDS]
            v[0] = p
            if p < 0 and c[VISIBLE] != 1:
                v[7] = 0
            if v[10] not in (0, 1, 2, 3):
                v[10] = 1
            while len(v) > 4 and v[-1] == DEFAULTS[len(v) - 1]:
                v.pop()
            cels.append(v)
        frames.append(cels)
    timing = []
    for t in sorted(an.get("timing") or [], key=lambda t: t.get("frame") or 0):
        tt = t.get("timingType")
        row = {"f": int(t.get("frame") or 0), "t": tt}
        if tt == 0:
            name = t.get("name") or ""
            if not name:
                row["se"] = "CRY"
            else:
                se = cart_match(name, carts)
                if se:
                    row["se"] = se
                    stats["cart_se"] += 1
                else:
                    path = find_file(pack / "Audio" / "SE" / "Anim", name, (".wav", ".ogg", ".mp3", ".WAV"))
                    if not path:
                        stats["missing_se"].add(name)
                        continue
                    vol, pitch = int(t.get("volume") or 100), int(t.get("pitch") or 100)
                    sid = "NDX_ESS_" + slug(path.name).upper()
                    if vol != 100 or pitch != 100:
                        sid += "_V%d_P%d" % (vol, pitch)
                    sounds[sid] = (path, vol, pitch)
                    row["se"] = sid
                    stats["pack_se"] += 1
        elif tt in (1, 3):
            name = t.get("name") or ""
            if name:
                path = find_file(pack / "Graphics" / "Animations", name, (".png",))
                if not path:
                    stats["missing_bg"].add(name)
                    continue
                bk = slug(path.name)
                bgs[bk] = path
                row["bg"] = bk
            row["x"], row["y"] = t.get("bgX") or 0, t.get("bgY") or 0
            row["o"] = t.get("opacity") or 0
            row["c"] = [x or 0 for x in color_of(t)]
        elif tt in (2, 4):
            row["d"] = int(t.get("duration") or 0)
            if t.get("bgX") is not None:
                row["x"] = t.get("bgX")
            if t.get("bgY") is not None:
                row["y"] = t.get("bgY")
            if t.get("opacity") is not None:
                row["o"] = t.get("opacity")
            c = color_of(t)
            if any(x is not None for x in c):
                row["c"] = [-1 if x is None else x for x in c]
        else:
            continue
        timing.append(row)
    return {"sheet": key, "frames": frames, "timing": timing}


def remap(anim, index):
    """Patterns -> the packed grid's indices."""
    k = anim["sheet"]
    mapping = index.get(k, {}).get("map", {}) if k else {}
    for f in anim["frames"]:
        for c in f:
            if c[0] >= 0:
                c[0] = mapping[c[0]]
    if k and k not in index:
        anim["sheet"] = None


def write_move(path: Path, move: str, d: dict, source: str):
    lines = ["-- Generated by tools/build_ess_anims.py from %s. Do not edit by hand." % source,
             "-- %s: frames (each a list of cels: pattern, x, y, focus, zoom x, zoom y, angle, opacity," % move,
             "-- blend, mirror, priority, colour r g b a, tone r g b gray; pattern -1 / -2 the user / the target,",
             "-- -3 / -4 a copy of the user's / the target's picture) and timings, as src/ess_anims.lua plays them.",
             "return {"]
    for kind in ("move", "opp", "charge", "charge_opp"):
        a = d.get(kind)
        if not a:
            continue
        lines.append("  %s = {" % kind)
        lines.append("    sheet = %s," % lua(a["sheet"]))
        lines.append("    frames = {")
        for f in a["frames"]:
            lines.append("      {" + ", ".join(lua(c) for c in f) + "},")
        lines.append("    },")
        lines.append("    timing = {")
        for t in a["timing"]:
            lines.append("      " + lua(t) + ",")
        lines.append("    },")
        lines.append("  },")
    lines.append("}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def convert_sound(src: Path, out: Path, vol: int, pitch: int):
    filters = []
    if pitch != 100:
        filters += ["asetrate=44100*%s" % (pitch / 100), "aresample=44100"]
    if vol != 100:
        filters.append("volume=%s" % (vol / 100))
    cmd = ["ffmpeg", "-y", "-v", "error", "-i", str(src)]
    if filters:
        cmd += ["-af", ",".join(filters)]
    cmd += ["-ac", "1", "-ar", "22050", "-c:a", "libvorbis", "-q:a", "2", str(out)]
    subprocess.run(cmd, check=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pack", type=Path, default=Path(os.environ.get("ESS_PACK") or DEFAULT_PACK))
    ap.add_argument("--no-sounds", action="store_true", help="keep the sound files already built")
    args = ap.parse_args()
    pack = args.pack
    source = "Gen 9 Move Animation Project (Pokémon Essentials v21.1)"

    anims = M.load((pack / "Data" / "PkmnAnimations.rxdata").read_bytes()).get("array")
    new, cart = read_moves()
    names = set(new) | {n for n in cart if n not in CART_KEEPS}
    chosen = select(anims, names)
    carts = cart_sounds()

    sheets = Sheets(pack)
    bgs: dict[str, Path] = {}
    sounds: dict[str, tuple] = {}
    stats = {"cart_se": 0, "pack_se": 0, "missing_sheet": set(), "missing_se": set(), "missing_bg": set()}
    converted = {}
    for move, d in chosen.items():
        converted[move] = {k: convert(an, sheets, bgs, sounds, carts, pack, stats) for k, an in d.items()}

    assets = ROOT / "assets" / "ess"
    assets.mkdir(parents=True, exist_ok=True)
    shutil.rmtree(assets / "bg", ignore_errors=True)
    for p in assets.glob("*.png"):
        p.unlink()
    index = sheets.cels()
    for d in converted.values():
        for a in d.values():
            remap(a, index)

    # the atlas: a page's 256 colours serve best when its pictures are alike, so the sheets go by
    # hue, a page's worth at a time (each page's cels tallest first), on pages up to CEL_PAGE square;
    # the backgrounds (the 512 x 384 screen onto 240 x 160) the same on their own pages up to BG_PAGE
    def hue(img):
        a = np.asarray(img.convert("RGBA")).astype(np.float32) / 255
        w = a[..., 3].sum() or 1
        r, g, b = [(a[..., i] * a[..., 3]).sum() / w for i in range(3)]
        h, sat, v = colorsys.rgb_to_hsv(r, g, b)
        return (0 if sat > 0.15 else 1, h, v)   # the grays and whites after the colours

    def grouped(items_by_hue, limit):
        """Packs [(key, image)] (already by hue) onto pages filled one at a time: each takes the
        next pictures while they still fit on one page (tallest first) -> sizes, places."""
        sizes, places = [], {}
        rest = list(items_by_hue)
        while rest:
            lo, hi = 1, len(rest)          # the most of `rest` that fits one page
            while lo < hi:
                mid = (lo + hi + 1) // 2
                group = sorted(rest[:mid], key=lambda it: (-it[1].height, -it[1].width))
                if len(pack_pages(group, limit)[0]) == 1:
                    lo = mid
                else:
                    hi = mid - 1
            group = sorted(rest[:lo], key=lambda it: (-it[1].height, -it[1].width))
            gs, gp = pack_pages(group, limit)
            for key, (pg, x, y) in gp.items():
                places[key] = (len(sizes) + pg, x, y)
            sizes.extend(gs)
            rest = rest[lo:]
        return sizes, places

    sheet_order = sorted(index, key=lambda k: hue(max((c[0] for c in index[k]["cels"]), key=lambda i: i.width * i.height)))
    cel_items = [((k, n), img) for k in sheet_order for n, (img, _, _) in enumerate(index[k]["cels"])]
    cel_sizes, cel_places = grouped(cel_items, CEL_PAGE)
    cel_pages = write_pages("cels", cel_items, cel_places, cel_sizes, assets)

    bg_items = []
    for k, path in sorted(bgs.items()):
        img = Image.open(path).convert("RGBA")
        w, h = max(1, round(img.width * 240 / 512)), max(1, round(img.height * 160 / 384))
        bg_items.append((k, img.resize((w, h), Image.LANCZOS)))

    bg_items.sort(key=lambda it: hue(it[1]))
    bg_sizes, bg_places = grouped(bg_items, BG_PAGE)
    bg_pages = write_pages("bgs", bg_items, bg_places, bg_sizes, assets)

    pages = cel_pages + bg_pages
    bg_index = {}
    for k, img in bg_items:
        pg, x, y = bg_places[k]
        bg_index[k] = {"page": len(cel_pages) + pg + 1, "x": x, "y": y, "w": img.width, "h": img.height}

    # sounds
    se_dir = assets / "se"
    if not args.no_sounds:
        shutil.rmtree(se_dir, ignore_errors=True)
    se_dir.mkdir(parents=True, exist_ok=True)
    se_index = {}
    for sid, (path, vol, pitch) in sorted(sounds.items()):
        out = se_dir / (sid.lower() + ".ogg")
        if not out.exists():
            convert_sound(path, out, vol, pitch)
        se_index[sid] = "assets/ess/se/%s.ogg" % sid.lower()

    # the moves
    move_dir = ROOT / "data" / "ess"
    shutil.rmtree(move_dir, ignore_errors=True)
    move_dir.mkdir(parents=True)
    for move, d in converted.items():
        write_move(move_dir / (move + ".lua"), move, d, source)

    lines = [
        "-- Generated by tools/build_ess_anims.py. Do not edit by hand.",
        "-- Battle animations from the Gen 9 Move Animation Project for Pokémon Essentials",
        "-- (https://eeveeexpo.com/resources/1480/; the Gen 8 and Gen 9 Animation Projects and their",
        "-- contributors, with BellBlitzKing's sound effects; see CREDITS.md), for every move it names (the",
        "-- newer ones and the carts' own) and the cart's status, weather and trap animations it has.",
        "-- src/ess_anims.lua plays them through its visual task NdxEss; data/ess/<NAME>.lua holds each",
        "-- one's frames.",
        "return {",
        "  source = %s," % lua(source),
        "  built = %s," % lua(date.today().isoformat()),
        "  scale = %s," % lua(SCALE),
        "  -- the atlas pages (256 colours each); a sheet's cels are rects on them: page, x, y, w, h and",
        "  -- where the rect sits in its cell (ox, oy), 7 numbers a cel; a background is one rect",
        "  pages = {",
    ]
    for pg in pages:
        lines.append("    { file = %s, w = %d, h = %d }," % (lua(pg["file"]), pg["w"], pg["h"]))
    lines.append("  },")
    lines.append("  sheets = {")
    for k, s in index.items():
        r = []
        for n, (img, ox, oy) in enumerate(s["cels"]):
            pg, x, y = cel_places[(k, n)]
            r += [pg + 1, x, y, img.width, img.height, ox, oy]
        lines.append("    %s = { cell = %d, count = %d, r = %s }," % (key(k), CELL, len(s["cels"]), lua(r)))
    lines.append("  },")
    lines.append("  bgs = {")
    for k, b in bg_index.items():
        lines.append("    %s = { page = %d, x = %d, y = %d, w = %d, h = %d }," % (
            key(k), b["page"], b["x"], b["y"], b["w"], b["h"]))
    lines.append("  },")
    lines.append("  sounds = {")
    for sid, f in se_index.items():
        lines.append("    %s = %s," % (sid, lua(f)))
    lines.append("  },")
    lines.append("  -- move -> its frame counts (opp: the foe's version; charge: the charging turn), the cart's")
    lines.append("  -- number for a Gen 1-3 move, and how a two-turn move plays (turns)")
    lines.append("  moves = {")
    for move, d in converted.items():
        if move.startswith("C_"):
            continue
        row = {"frames": len(d["move"]["frames"])}
        if "opp" in d:
            row["opp"] = len(d["opp"]["frames"])
        if "charge" in d:
            row["charge"] = len(d["charge"]["frames"])
        if move in cart:
            row["num"] = cart[move]
        turns = TWO_TURN_CART.get(move) if move in cart else TWO_TURN_EFFECTS.get(new.get(move))
        if turns:
            row["turns"] = turns
        if move in BORROW:
            row["from"] = BORROW[move]
        if move in read_moves.on_user:
            row["user"] = True   # a newer move on its user (the carts' own say so in their move data)
        lines.append("    %s = %s," % (move, lua(row)))
    lines.append("  },")
    lines.append("  -- the cart's table animations (Anim.tableScript kind, name) -> a data/ess file")
    lines.append("  commons = {")
    for kind, table in COMMONS.items():
        rows = {k: "C_" + v.upper() for k, v in table.items() if "C_" + v.upper() in converted}
        lines.append("    %s = %s," % (kind, lua(rows)))
    lines.append("  },")
    lines.append("  -- TURN_TRAP by the cart task's argument 0")
    lines.append("  trap = { %s }," % ", ".join("[%d] = %s" % (k, lua("C_" + v.upper())) for k, v in TRAP.items()
                                               if "C_" + v.upper() in converted))
    lines.append("}")
    (ROOT / "data" / "ess_anims.lua").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")

    def size(p):
        return sum(f.stat().st_size for f in Path(p).rglob("*") if f.is_file())
    moves = [m for m in converted if not m.startswith("C_")]
    print("moves: %d newer, %d of the carts' (%d with a foe's version, %d with a charging turn), common: %d" % (
        sum(1 for m in moves if m in new), sum(1 for m in moves if m in cart),
        sum(1 for m in moves if "opp" in converted[m]), sum(1 for m in moves if "charge" in converted[m]),
        len(converted) - len(moves)))
    print("sheets: %d, backgrounds: %d, on %d atlas pages (%s; %.1f MB), pack sounds: %d (%.1f MB), cart sounds used: %d" % (
        len(index), len(bg_index), len(pages), ", ".join("%dx%d" % (pg["w"], pg["h"]) for pg in pages),
        size(assets) / 1e6 - size(se_dir) / 1e6, len(se_index), size(se_dir) / 1e6, stats["cart_se"]))
    print("data/ess: %.1f MB" % (size(move_dir) / 1e6))
    for k in ("missing_sheet", "missing_se", "missing_bg"):
        if stats[k]:
            print("%s: %s" % (k, sorted(stats[k])))
    print("newer moves without one: %s" % [m for m in new if m not in converted])
    print("cart moves without one: %s" % [m for m in cart if m not in converted])
    for kind, table in COMMONS.items():
        miss = [k for k, v in table.items() if "C_" + v.upper() not in converted]
        if miss:
            print("%s without one: %s" % (kind, miss))


if __name__ == "__main__":
    main()
