#!/usr/bin/env python3
"""
Build national_dex_gen3's Pokedex art: assets/dex/dex_<n>.png + data/dex_atlas_index.lua.

The Gen 3 Pokedex has no art for #387-1025, and with a battle-sprite mod installed every dex
picture is a battle animation frame. This packs the front sprites of pokeemerald-expansion
(not shipped; --expansion points at a local checkout) into 64x64 cells: every National Dex
species #1-1025 and every alternate form this mod registers (data/species/forms.lua), each
with its two animation frames where the sprite has two (anim_front.png is two 64x64 frames
stacked), one where it has one (front.png). src/dex_art.lua reads them.

The expansion's own tables say which picture and palette a species uses:
  src/data/graphics/pokemon.h     gMonFrontPic_<Name> / gMonPalette_<Name> -> file
  include/constants/pokedex.h     NATIONAL_DEX_<NAME>, in National Dex order
A species' <Name> is its id in CamelCase (NIDORAN_F -> NidoranF). A default form carries a
suffix there (UNOWN -> UnownA, OGERPON_WELLSPRING_MASK -> OgerponWellspring), so a name with
no exact symbol takes the first symbol that starts with it, else the longest symbol it starts
with. OVERRIDES covers the rest. The GBA-style alternatives (*_gba.png / *_gba.pal) are skipped.

Usage:
    python tools/build_dex_atlas.py --expansion <pokeemerald-expansion checkout>
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
CELL = 64
SHEET = 2048
PER_ROW = SHEET // CELL
PER_SHEET = PER_ROW * PER_ROW

# id -> (front pic name, palette name), where the rule above picks the wrong one
OVERRIDES = {
    # Alcremie is a sweet (the picture) in a cream (the palette); the base species is
    # Strawberry Vanilla Cream
    "ALCREMIE": ("AlcremieStrawberry", "AlcremieStrawberryVanillaCream"),
    "ALCREMIE_RUBY_CREAM": ("AlcremieStrawberry", "AlcremieStrawberryRubyCream"),
    "ALCREMIE_MATCHA_CREAM": ("AlcremieStrawberry", "AlcremieStrawberryMatchaCream"),
    "ALCREMIE_MINT_CREAM": ("AlcremieStrawberry", "AlcremieStrawberryMintCream"),
    "ALCREMIE_LEMON_CREAM": ("AlcremieStrawberry", "AlcremieStrawberryLemonCream"),
    "ALCREMIE_SALTED_CREAM": ("AlcremieStrawberry", "AlcremieStrawberrySaltedCream"),
    "ALCREMIE_RUBY_SWIRL": ("AlcremieStrawberry", "AlcremieStrawberryRubySwirl"),
    "ALCREMIE_CARAMEL_SWIRL": ("AlcremieStrawberry", "AlcremieStrawberryCaramelSwirl"),
    "ALCREMIE_RAINBOW_SWIRL": ("AlcremieStrawberry", "AlcremieStrawberryRainbowSwirl"),
}

DEF = re.compile(r'(gMonFrontPic|gMonPalette)_(\w+)\[\]\s*=\s*INCGFX_U(?:32|16)\("([^"]+)"')


def camel(ident: str) -> str:
    return "".join(part[:1].upper() + part[1:].lower() for part in ident.split("_") if part)


def read_symbols(expansion: Path):
    """name -> path for front pics and palettes, in file order, GBA-style ones skipped."""
    pics, pals = {}, {}
    text = (expansion / "src/data/graphics/pokemon.h").read_text(encoding="utf-8", errors="replace")
    for kind, name, path in DEF.findall(text):
        if "_gba." in path or path.endswith("_gba.pal"):
            continue
        table = pics if kind == "gMonFrontPic" else pals
        table.setdefault(name, path)
    return pics, pals


def resolve(name: str, table: dict) -> str | None:
    if name in table:
        return name
    low = name.lower()
    for key in table:                                   # file order: the default form first
        if key.lower().startswith(low):
            return key
    best = None
    for key in table:
        if low.startswith(key.lower()) and (best is None or len(key) > len(best)):
            best = key
    return best


def national_ids(expansion: Path) -> list[str]:
    text = (expansion / "include/constants/pokedex.h").read_text(encoding="utf-8", errors="replace")
    ids = []
    for m in re.finditer(r"^\s*NATIONAL_DEX_(\w+),", text, re.M):
        if m.group(1) == "NONE":
            continue
        ids.append(m.group(1))
        if m.group(1) == "PECHARUNT":
            break
    return ids


def form_ids() -> list[str]:
    text = (ROOT / "data/species/forms.lua").read_text(encoding="utf-8")
    return re.findall(r'\{ id = "([A-Z0-9_]+)"', text)


def read_pal(path: Path) -> list[tuple[int, int, int, int]]:
    lines = path.read_text(encoding="utf-8", errors="replace").split()
    # JASC-PAL / 0100 / <count> / r g b ...
    count = int(lines[2])
    vals = [int(v) for v in lines[3:3 + count * 3]]
    cols = [(vals[i], vals[i + 1], vals[i + 2], 255) for i in range(0, len(vals), 3)]
    if cols:
        cols[0] = (0, 0, 0, 0)                         # index 0 is transparent
    return cols


def frames_of(png: Path, pal: list) -> list[Image.Image]:
    im = Image.open(png)
    if im.mode != "P":
        raise ValueError(f"{png} is not an indexed PNG")
    w, h = im.size
    idx = im.tobytes()
    out = []
    for f in range(max(1, h // CELL)):
        cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        px = cell.load()
        for y in range(CELL):
            for x in range(min(w, CELL)):
                i = idx[(f * CELL + y) * w + x]
                if i and i < len(pal):
                    px[x, y] = pal[i]
        out.append(cell)
    return out[:2]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("--expansion", required=True, type=Path)
    args = ap.parse_args()
    exp = args.expansion
    pics, pals = read_symbols(exp)

    wanted = [(dex, ident) for dex, ident in enumerate(national_ids(exp), start=1)]
    forms = form_ids()
    entries, missing = [], []
    for key, ident in [(d, i) for d, i in wanted] + [(f, f) for f in forms]:
        pic_name, pal_name = OVERRIDES.get(ident, (None, None))
        pic_name = pic_name or resolve(camel(ident), pics)
        pal_name = pal_name or resolve(camel(ident), pals) or (pic_name and resolve(pic_name, pals))
        if not pic_name or not pal_name or pic_name not in pics or pal_name not in pals:
            missing.append(f"{key} ({ident}): pic={pic_name} pal={pal_name}")
            continue
        try:
            cells = frames_of(exp / pics[pic_name], read_pal(exp / pals[pal_name]))
        except (OSError, ValueError) as err:
            missing.append(f"{key} ({ident}): {err}")
            continue
        entries.append((key, ident, pic_name, cells))

    total = sum(len(c) for _, _, _, c in entries)
    sheets = [Image.new("RGBA", (SHEET, SHEET), (0, 0, 0, 0))
              for _ in range((total + PER_SHEET - 1) // PER_SHEET)]
    out_dir = ROOT / "assets/dex"
    out_dir.mkdir(parents=True, exist_ok=True)
    lines = []
    n = 0
    for key, ident, pic_name, cells in entries:
        sheet, cell = divmod(n, PER_SHEET)
        if cell + len(cells) > PER_SHEET:              # keep an entry's frames on one sheet
            n = (sheet + 1) * PER_SHEET
            sheet, cell = divmod(n, PER_SHEET)
            if sheet >= len(sheets):
                sheets.append(Image.new("RGBA", (SHEET, SHEET), (0, 0, 0, 0)))
        for i, im in enumerate(cells):
            row, col = divmod(cell + i, PER_ROW)
            sheets[sheet].paste(im, (col * CELL, row * CELL))
        n += len(cells)
        k = f"[{key}]" if isinstance(key, int) else f'["{key}"]'
        lines.append(f"    {k} = {{ sheet = {sheet}, cell = {cell}, frames = {len(cells)} }},"
                     f" -- {ident} ({pic_name})")
    for i, im in enumerate(sheets):
        im.save(out_dir / f"dex_{i}.png", optimize=True)
    header = [
        "-- Generated by tools/build_dex_atlas.py from pokeemerald-expansion's front sprites. Do",
        "-- not edit by hand; rerun the tool instead.",
        "-- [national dex number] (a species' default look) or [\"FORM_ID\"] (a form this mod",
        "-- registers) -> its cells in assets/dex/dex_<sheet>.png: `frames` 64x64 cells from",
        f"-- `cell` on, {PER_ROW} to a row of a {SHEET}x{SHEET} sheet.",
        "return {",
        f"  cell = {CELL}, perRow = {PER_ROW}, sheets = {len(sheets)},",
        "  entries = {",
    ]
    (ROOT / "data/dex_atlas_index.lua").write_text("\n".join(header + lines + ["  },", "}", ""]),
                                                   encoding="utf-8")
    two = sum(1 for _, _, _, c in entries if len(c) == 2)
    print(f"{len(entries)} entries ({two} with two frames, {len(entries) - two} with one), "
          f"{len(sheets)} sheet(s)")
    for m in missing:
        print("MISSING", m)
    base_missing = [m for m in missing if m.split(" ", 1)[0].isdigit()]
    return 1 if base_missing else 0


if __name__ == "__main__":
    sys.exit(main())
