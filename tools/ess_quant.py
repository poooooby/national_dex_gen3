"""256-colour quantizing for RGBA atlas pages (tools/build_ess_anims.py).

Pillow's octree alone bands soft gradients (a background's vignette, a glow's falloff). This
refines its palette with k-means over the pixels actually drawn (colours weighted by alpha, so
faint edges don't take palette slots from what shows), then gives every pixel its nearest entry.
Fully transparent pixels share entry 0. Returns a "P" image whose palette carries alpha (tRNS).
"""
from __future__ import annotations

import numpy as np
from PIL import Image


def _nearest(pts: np.ndarray, centers: np.ndarray, chunk: int = 65536) -> np.ndarray:
    out = np.empty(len(pts), dtype=np.int32)
    cc = (centers ** 2).sum(1)
    for i in range(0, len(pts), chunk):
        p = pts[i:i + chunk]
        d = cc[None, :] - 2 * p @ centers.T
        out[i:i + chunk] = d.argmin(1)
    return out


def quantize(img: Image.Image, colors: int = 256, iters: int = 10, sample: int = 250_000,
             seed: int = 1) -> Image.Image:
    rgba = np.asarray(img.convert("RGBA")).astype(np.float32) / 255
    h, w = rgba.shape[:2]
    flat = rgba.reshape(-1, 4)
    drawn = flat[:, 3] > 0
    # premultiplied colour + alpha: how a pixel looks once blended
    feat = np.concatenate([flat[:, :3] * flat[:, 3:4], flat[:, 3:4]], 1)
    pts = feat[drawn]
    k = colors - 1                       # entry 0 is transparent
    index = np.zeros(h * w, dtype=np.uint8)
    if len(pts) == 0:
        pal = np.zeros((colors, 4), dtype=np.float32)
    else:
        rng = np.random.default_rng(seed)
        samp = pts if len(pts) <= sample else pts[rng.choice(len(pts), sample, replace=False)]
        # start from the octree's palette of the drawn pixels
        seedimg = Image.fromarray((rgba[drawn.reshape(h, w)] * 255).astype(np.uint8).reshape(1, -1, 4), "RGBA")
        oq = seedimg.quantize(min(k, max(1, len(np.unique(samp, axis=0)))), method=Image.Quantize.FASTOCTREE)
        opal = np.asarray(oq.getpalette(rawmode="RGBA")[:4 * k], dtype=np.float32).reshape(-1, 4) / 255
        centers = np.concatenate([opal[:, :3] * opal[:, 3:4], opal[:, 3:4]], 1)
        if len(centers) < k:
            extra = samp[rng.choice(len(samp), k - len(centers))]
            centers = np.concatenate([centers, extra], 0)
        for _ in range(iters):
            lab = _nearest(samp, centers)
            sums = np.zeros_like(centers)
            np.add.at(sums, lab, samp)
            cnt = np.bincount(lab, minlength=k).astype(np.float32)
            used = cnt > 0
            centers[used] = sums[used] / cnt[used, None]
            # an empty entry takes the worst-served sample
            if (~used).any():
                d = ((samp - centers[lab]) ** 2).sum(1)
                worst = np.argsort(-d)[: int((~used).sum())]
                centers[~used] = samp[worst]
        index[drawn] = _nearest(pts, centers).astype(np.uint8) + 1
        a = np.clip(centers[:, 3:4], 1e-6, 1)
        pal = np.concatenate([np.zeros((1, 4), np.float32),
                              np.concatenate([np.clip(centers[:, :3] / a, 0, 1), centers[:, 3:4]], 1)], 0)
    out = Image.fromarray(index.reshape(h, w), "P")
    p8 = (np.clip(pal, 0, 1) * 255 + 0.5).astype(np.uint8)
    out.putpalette(p8[:, :3].reshape(-1).tolist())
    out.info["transparency"] = bytes(p8[:, 3].tolist())
    return out
