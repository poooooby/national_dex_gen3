"""Draw the placeholder battle pictures the Gen 1/2 path gives a species no sprite mod draws:
a grey ball with a "?" (front) and the same ball from behind (back), in the four shades the
carts' own pictures use (white, light grey, dark grey, black) on a transparent white ground, so
each game tints it exactly as it tints its own pictures.

    python tools/build_placeholder.py        -> assets/gen12/front.png      56x56 (frontSize 7)
                                                assets/gen12/back_gen1.png  32x32 (Red's backs)
                                                assets/gen12/back_gen2.png  48x48 (Gold's backs)

Our own drawing (the owner's call, 2026-11-11): no species art is shipped.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "gen12"

CLEAR = (255, 255, 255, 0)
WHITE = (255, 255, 255, 255)
LIGHT = (170, 170, 170, 255)
DARK = (85, 85, 85, 255)
BLACK = (0, 0, 0, 255)

QUESTION = [
    ".###.",
    "#...#",
    "....#",
    "...#.",
    "..#..",
    ".....",
    "..#..",
]


def ball(size: int, radius: float, cy: float, mark: bool) -> Image.Image:
    img = Image.new("RGBA", (size, size), CLEAR)
    px = img.load()
    cx = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if d <= radius - 1:
                # light from the upper left: a dark crescent low on the right, a white glint
                shade = ((x - cx + radius * 0.35) ** 2 + (y - cy + radius * 0.35) ** 2) ** 0.5
                px[x, y] = DARK if shade > radius * 1.05 else LIGHT
            elif d <= radius:
                px[x, y] = BLACK
    gx, gy = int(cx - radius * 0.5), int(cy - radius * 0.55)
    for dx, dy in ((0, 0), (1, 0), (0, 1)):
        px[gx + dx, gy + dy] = WHITE
    if mark:
        scale = max(1, round(radius / 7.5))
        w, h = len(QUESTION[0]) * scale, len(QUESTION) * scale
        ox, oy = round(cx - (w - 1) / 2), round(cy - (h - 1) / 2)
        for row, line in enumerate(QUESTION):
            for col, ch in enumerate(line):
                if ch == "#":
                    for sy in range(scale):
                        for sx in range(scale):
                            px[ox + col * scale + sx, oy + row * scale + sy] = BLACK
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    ball(56, 22, 31, True).save(OUT / "front.png")
    # backs sit on the bottom edge (the player's Pokemon is cut off by the text box)
    ball(32, 14, 18, False).save(OUT / "back_gen1.png")
    ball(48, 21, 27, False).save(OUT / "back_gen2.png")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
