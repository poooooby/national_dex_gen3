#!/usr/bin/env python3
"""
Pack tools/build_fx.mjs's rendered frames into one grayscale atlas (assets/fx/atlas.png).

build_fx.mjs renders each sheet's frames in grays (a pixelfx palette as an even gray ramp), trims them
to the box they all draw in and writes them as one strip per sheet, plus a manifest. This scales each
frame if the sheet asks (down smoothly, up pixel for pixel), applies the alpha cut again after a
resize, trims each frame to what it draws, shelf-packs every frame of every sheet into one image and
saves it as gray + alpha. src/fx_anims.lua colours it at draw time through a ramp (a gradient map).

Usage (build_fx.mjs runs it): python tools/fx_atlas.py <manifest.json> <atlas.png> <out.json>
manifest: { "sheets": [ { name, file, w, h, cols, n, fw, fh, cut } ] }
out:      { "w", "h", "sheets": { name: [ [x, y, w, h, ox, oy], ... one per frame ] } }
          (x, y, w, h: the frame's rect in the atlas; ox, oy: where that rect sits in the frame;
          an empty frame is all zeros)
"""

from __future__ import annotations

import json
import sys

from PIL import Image

PAD = 1          # between rects, so a turned or scaled frame never samples its neighbour
MAX_SIDE = 4096  # the largest texture every LOVE target takes
LEVELS = 16      # grays (and alphas) kept: the ramp blends between its 8 steps, and fewer levels pack smaller


def step(v: int) -> int:
    return round(v * (LEVELS - 1) / 255) * 255 // (LEVELS - 1)


def frames_of(sheet: dict) -> list[Image.Image]:
    strip = Image.open(sheet["file"]).convert("RGBA")
    w, h, cols, n = sheet["w"], sheet["h"], sheet["cols"], sheet["n"]
    fw, fh, cut = sheet["fw"], sheet["fh"], sheet["cut"]
    out = []
    for i in range(n):
        x, y = (i % cols) * w, (i // cols) * h
        fr = strip.crop((x, y, x + w, y + h))
        if (fw, fh) != (w, h):
            if fw > w:
                fr = fr.resize((fw, fh), Image.NEAREST)
            else:
                fr = fr.convert("RGBa").resize((fw, fh), Image.LANCZOS).convert("RGBA")
            fr.putalpha(fr.getchannel("A").point(lambda v: 0 if v < cut else v))
        gray = fr.convert("L").point(step)
        la = Image.merge("LA", (gray, fr.getchannel("A").point(step)))
        out.append(la)
    return out


def pack(rects: list[tuple[int, int]], width: int) -> tuple[list[tuple[int, int]], int]:
    """Shelf-pack (w, h) rects, tallest first, into rows `width` wide. Returns positions and height."""
    order = sorted(range(len(rects)), key=lambda i: (-rects[i][1], -rects[i][0]))
    pos: list[tuple[int, int]] = [(0, 0)] * len(rects)
    x = y = shelf = 0
    for i in order:
        w, h = rects[i]
        if w == 0:
            continue
        if x + w > width:
            x, y, shelf = 0, y + shelf + PAD, 0
        pos[i] = (x, y)
        x += w + PAD
        shelf = max(shelf, h)
    return pos, y + shelf


def main() -> int:
    manifest_path, atlas_path, out_path = sys.argv[1:4]
    manifest = json.load(open(manifest_path, encoding="utf-8"))
    crops = []   # (sheet name, frame index, cropped image, ox, oy)
    for sheet in manifest["sheets"]:
        for i, fr in enumerate(frames_of(sheet)):
            box = fr.getchannel("A").getbbox()
            if box is None:
                crops.append((sheet["name"], i, None, 0, 0))
            else:
                crops.append((sheet["name"], i, fr.crop(box), box[0], box[1]))
    sizes = [(c[2].width, c[2].height) if c[2] else (0, 0) for c in crops]
    best = None
    for width in (512, 1024, 2048, 4096):
        if max(w for w, _ in sizes) > width:
            continue
        pos, height = pack(sizes, width)
        if height <= MAX_SIDE and (best is None or width * height < best[0] * best[1]):
            best = (width, height, pos)
    if best is None:
        print("the frames do not fit in one 4096 x 4096 atlas", file=sys.stderr)
        return 1
    width, height, pos = best
    atlas = Image.new("LA", (width, height), (0, 0))
    out = {"w": width, "h": height, "sheets": {}}
    for (name, i, img, ox, oy), (x, y) in zip(crops, pos):
        rows = out["sheets"].setdefault(name, [])
        if img is None:
            rows.append([0, 0, 0, 0, 0, 0])
            continue
        atlas.paste(img, (x, y))
        rows.append([x, y, img.width, img.height, ox, oy])
    atlas.save(atlas_path, optimize=True)
    json.dump(out, open(out_path, "w", encoding="utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
