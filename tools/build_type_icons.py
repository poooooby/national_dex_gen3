#!/usr/bin/env python3
"""Draw the FAIRY type icon (original art; Gen 3 has no Fairy type) in the two sizes the
Gen 3 screens use, laid out like the cart's own so it sits level with them:

    assets/types/fairy_frlg.png  32x12  FireRed/LeafGreen badge: a flat plate with its four
                                        corners cut, the name on rows 2-8
    assets/types/fairy_rse.png   32x16  Ruby/Sapphire/Emerald icon: clear top and bottom rows,
                                        a light top edge and a dark bottom edge, the name on
                                        rows 4-10

The name is white, one pixel wide, with a dark shadow right and below, centred. The letter
shapes are drawn here; nothing is taken from a ROM.

    python tools/build_type_icons.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "types"

# 7-row capitals ('#' lit), our own shapes
GLYPHS = {
    "F": ["####", "#...", "#...", "###.", "#...", "#...", "#..."],
    "A": [".##.", "#..#", "#..#", "####", "#..#", "#..#", "#..#"],
    "I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
    "R": ["###.", "#..#", "#..#", "###.", "#.#.", "#..#", "#..#"],
    "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
}

BODY = (228, 124, 180, 255)      # fairy pink
LIGHT = (248, 200, 226, 255)     # RSE top edge
DARK = (156, 76, 120, 255)       # RSE bottom edge
TEXT = (255, 255, 255, 255)
SHADOW_FRLG = (66, 66, 66, 255)
SHADOW_RSE = (132, 123, 115, 255)
CLEAR = (0, 0, 0, 0)


def text_width(word: str) -> int:
    return sum(len(GLYPHS[c][0]) for c in word) + (len(word) - 1)


def letters(img: Image.Image, word: str, top: int, shadow: tuple) -> None:
    px = img.load()
    w = img.size[0]
    lit = set()
    x = (w - (text_width(word) + 1)) // 2
    for c in word:
        for gy, row in enumerate(GLYPHS[c]):
            for gx, cell in enumerate(row):
                if cell == "#":
                    lit.add((x + gx, top + gy))
        x += len(GLYPHS[c][0]) + 1
    for (lx, ly) in lit:
        for dx, dy in ((1, 0), (0, 1), (1, 1)):
            if (lx + dx, ly + dy) not in lit:
                px[lx + dx, ly + dy] = shadow
    for (lx, ly) in lit:
        px[lx, ly] = TEXT


def frlg() -> Image.Image:
    w, h = 32, 12
    img = Image.new("RGBA", (w, h), BODY)
    px = img.load()
    for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        px[x, y] = CLEAR
    letters(img, "FAIRY", 2, SHADOW_FRLG)
    return img


def rse() -> Image.Image:
    w, h = 32, 16
    img = Image.new("RGBA", (w, h), CLEAR)
    px = img.load()
    for y in range(1, 15):
        for x in range(w):
            px[x, y] = BODY
    for x in range(1, w - 1):
        px[x, 1] = LIGHT
        px[x, 14] = DARK
    px[0, 1] = px[w - 1, 1] = CLEAR
    px[0, 14] = px[w - 1, 14] = CLEAR
    px[0, 2] = px[w - 1, 2] = LIGHT
    px[0, 13] = px[w - 1, 13] = DARK
    letters(img, "FAIRY", 4, SHADOW_RSE)
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    frlg().save(OUT / "fairy_frlg.png")
    rse().save(OUT / "fairy_rse.png")
    print(f"wrote {OUT / 'fairy_frlg.png'} and {OUT / 'fairy_rse.png'}")


if __name__ == "__main__":
    main()
