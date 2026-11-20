#!/usr/bin/env python3
"""A review page for the Gen 9 Move Animation Project animations, from tests/drivers/ess_anims_probe.lua's
shots: one GIF per move and side.

    python tools/ess_gallery.py <SHOT_DIR> [--out <dir>]   (default: tools/.cache/ess_gallery)

Writes <out>/index.html and <out>/gif/*.gif. Each shot is the game's window; the battle (its top
two thirds) is kept and halved.
"""
from __future__ import annotations

import argparse
import html
import re
from collections import defaultdict
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("shots", type=Path)
    ap.add_argument("--out", type=Path, default=ROOT / "tools" / ".cache" / "ess_gallery")
    ap.add_argument("--every", type=int, default=6, help="SHOT_EVERY the driver ran with (frames)")
    args = ap.parse_args()
    groups = defaultdict(list)
    for p in sorted(args.shots.glob("*.png")):
        m = re.match(r"^(.+)_([pe])_(\d+)\.png$", p.name)
        if m:
            groups[(m.group(1), m.group(2))].append(p)
    gif = args.out / "gif"
    gif.mkdir(parents=True, exist_ok=True)
    moves = sorted({k[0] for k in groups})
    names = {}
    src = (ROOT / "data" / "moves.lua").read_text(encoding="utf-8")
    for i, full in re.findall(r'id = "(\w+)",.*?full = "([^"]+)"', src):
        names[i] = full
    for (move, side), files in groups.items():
        frames = []
        for f in files:
            im = Image.open(f).convert("RGB")
            w, h = im.size
            im = im.crop((0, 0, w, int(h * 0.73))).resize((w // 2, int(h * 0.73) // 2), Image.NEAREST)
            frames.append(im.convert("P", palette=Image.ADAPTIVE, colors=128))
        frames[0].save(gif / f"{move}_{side}.gif", save_all=True, append_images=frames[1:],
                       duration=max(20, round(args.every * 1000 / 60)), loop=0, optimize=True)
    rows = []
    for move in moves:
        cells = []
        for side, label in (("p", "player uses it"), ("e", "foe uses it")):
            if (move, side) in groups:
                cells.append(f'<figure><img src="gif/{move}_{side}.gif" loading="lazy" alt="{html.escape(move)} {label}">'
                             f"<figcaption>{label}</figcaption></figure>")
        rows.append(f'<section id="{move}"><h2>{html.escape(names.get(move, move))} <small>{move}</small></h2>'
                    f'<div class="row">{"".join(cells)}</div></section>')
    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Gen 9 move animations</title>
<style>
:root {{ --bg: #f4f4f1; --fg: #1d1d1b; --muted: #6b6b66; --card: #ffffff; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg: #161615; --fg: #ececea; --muted: #9a9a94; --card: #22221f; }} }}
body {{ background: var(--bg); color: var(--fg); font: 15px/1.4 system-ui, sans-serif; margin: 0; padding: 16px; }}
h1 {{ font-size: 20px; }} h2 {{ font-size: 16px; margin: 0 0 6px; }} small {{ color: var(--muted); font-weight: 400; }}
section {{ background: var(--card); border-radius: 8px; padding: 10px 12px; margin: 0 0 12px; }}
.row {{ display: flex; flex-wrap: wrap; gap: 10px; }}
figure {{ margin: 0; }} img {{ max-width: 100%; image-rendering: pixelated; display: block; }}
figcaption {{ color: var(--muted); font-size: 13px; }}
</style></head><body>
<h1>Gen 9 Move Animation Project on Gen 3 ({len(moves)} moves)</h1>
{"".join(rows)}
</body></html>"""
    (args.out / "index.html").write_text(page, encoding="utf-8")
    print("%d moves -> %s" % (len(moves), args.out / "index.html"))


if __name__ == "__main__":
    main()
