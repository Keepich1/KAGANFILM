"""Рисованные эффекты лагеря: клубы дыма, языки пламени, тропы и вытоптанная земля.

    smoke_puff.png    512×512, 2×2 кадра — клубы в 2–3 тона (свет сверху-слева, тень снизу)
    flame.png         256×256, 2×2 кадра — языки пламени (для аддитивного смешивания)
    path_decal.png    256×1024 — пыльная тропа с рваными краями (Decal вдоль длины)
    trample_decal.png 512×512 — вытоптанное пятно вокруг ставки и костров

Не гауссовы пятна: каждый клуб — набор мазков-кругов с плоскими тонами, как в «Аркейне».
"""
from __future__ import annotations

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from paint import Canvas, fbm, value_noise
from palette import rgb8


def _soft(mask, radius):
    im = Image.fromarray((np.clip(mask, 0, 1) * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(radius))
    return np.asarray(im, dtype=np.float64) / 255


def smoke_frame(size, seed):
    """Один клуб дыма: неровная гроздь мелких комков, вытянутая вверх; тоны ступенями
    (свет сверху-слева, тень снизу), край рваный и мягкий — не шар и не гауссово пятно."""
    rs = np.random.default_rng(seed)
    S = size * 2
    yy, xx = np.mgrid[0:S, 0:S] / 2.0
    mask = np.zeros((S, S))
    shade = np.zeros((S, S))
    n = rs.integers(11, 16)
    for i in range(n):
        t = rs.uniform(-1, 1)
        cx = size / 2 + rs.normal(0, 0.12) * size + t * 0.06 * size
        cy = size / 2 + t * 0.26 * size
        r = rs.uniform(0.09, 0.17) * size * (1.1 - 0.3 * abs(t))
        dist = np.hypot(xx - cx, yy - cy) / r
        inside = dist < 1
        mask = np.maximum(mask, np.clip(1.3 - dist, 0, 1))
        lx, ly = (xx - cx) / r, (yy - cy) / r
        lit = np.clip(0.55 - 0.5 * (lx * 0.6 + ly * 0.8), 0, 1)
        shade = np.where(inside, np.maximum(shade, lit), shade)
    n_noise = value_noise(S, S, 18, seed=seed + 5, tile=False)
    t = np.clip(shade + (n_noise - 0.5) * 0.3, 0, 1)
    tone = np.where(t > 0.6, 1.0, np.where(t > 0.3, 0.84, 0.68))
    tone = _soft(tone, 2.0)
    edge_noise = fbm(S, S, 16, 3, seed=seed + 9, tile=False)
    m = _soft(np.clip(mask, 0, 1), 10) - (edge_noise - 0.5) * 0.55
    alpha = np.clip((m - 0.18) / 0.5, 0, 1) ** 1.4
    alpha *= 0.65 + 0.35 * value_noise(S, S, 26, seed=seed + 11, tile=False)
    rgb = np.stack([tone * 238, tone * 234, tone * 236], -1)
    img = Image.fromarray(np.dstack([rgb, alpha * 255]).astype(np.uint8), "RGBA")
    return img.resize((size, size), Image.LANCZOS)


def flame_frame(size, seed):
    """Язык пламени: капля, вытянутая вверх, с 2–3 отростками; жёлтое ядро, оранжевый, красный край."""
    rs = np.random.default_rng(seed)
    S = size * 2
    yy, xx = np.mgrid[0:S, 0:S] / 2.0
    f = np.zeros((S, S))
    tongues = [(0.5, 0.0, 1.0)] + [(0.5 + rs.uniform(-0.2, 0.2), rs.uniform(-0.14, 0.14), rs.uniform(0.45, 0.75))
                                   for _ in range(2)]
    for cx, sway, hgt in tongues:
        y = yy / size  # 0 сверху, 1 снизу
        top = 1.0 - 0.92 * hgt
        prog = np.clip((y - top) / (0.95 - top), 0, 1)  # 0 на кончике, 1 у основания
        width = 0.3 * np.sqrt(prog) * (1.2 - 0.45 * prog) * (0.6 + 0.4 * hgt)
        center = cx + sway * (1 - prog) ** 2
        d = np.abs(xx / size - center) / np.maximum(width, 1e-3)
        f = np.maximum(f, np.clip(1 - d, 0, 1) * (prog > 0) * np.clip((0.97 - y) / 0.08, 0, 1))
    f = _soft(f, 2.0)
    n = value_noise(S, S, 14, seed=seed + 3, tile=False)
    f = np.clip(f * (0.85 + 0.3 * n), 0, 1)
    core = np.clip((f - 0.55) / 0.25, 0, 1)
    mid = np.clip((f - 0.2) / 0.3, 0, 1)
    col = (np.array(rgb8("#b0301a"), float)[None, None] * (1 - mid[..., None])
           + np.array(rgb8("#ff8a2c"), float)[None, None] * mid[..., None])
    col = col * (1 - core[..., None]) + np.array(rgb8("#fff2b0"), float)[None, None] * core[..., None]
    alpha = np.clip(f * 1.6, 0, 1)
    # для аддитивного смешивания — цвет уже умножен на альфу
    rgb = col * alpha[..., None]
    img = Image.fromarray(np.dstack([rgb, alpha * 255]).astype(np.uint8), "RGBA")
    return img.resize((size, size), Image.LANCZOS)


def sheet(frame_fn, frame_size, seeds):
    out = Image.new("RGBA", (frame_size * 2, frame_size * 2), (0, 0, 0, 0))
    for k, s in enumerate(seeds):
        out.paste(frame_fn(frame_size, s), ((k % 2) * frame_size, (k // 2) * frame_size))
    return out


def path_decal(w, h, seed=0):
    """Пыльная тропа вдоль длины (y): светлая охра, колеи и следы, рваные края."""
    c = Canvas(w, h, base="#8a7350", seed=seed, tile=False)
    c.underpaint(["#8a7350", "#7a6446", "#9a825c", "#6e5a40"], cell=48, seed=seed)
    c.strokes(int(w * h / 300), ["#a08860", "#6a5640", "#b29a70", "#5e4c38"], length=(20, 60), width=(4, 10),
              angle=90, angle_jitter=12, alpha=(0.2, 0.45), bristles=3, curve=0.1)
    yy, xx = np.mgrid[0:h, 0:w]
    u = (xx + 0.5) / w
    n = fbm(w, h, 40, 4, seed=seed + 3, tile=False)
    half = 0.36 + 0.12 * (n - 0.5) + 0.05 * np.sin(yy / h * 2 * math.pi * 3 + seed)
    d = np.abs(u - 0.5)
    alpha = np.clip((half - d) / 0.08, 0, 1)
    ends = np.clip(np.minimum(yy, h - yy) / (h * 0.06), 0, 1)
    alpha *= ends * (0.75 + 0.25 * n)
    # колеи: две тёмные полосы
    img = np.asarray(c.image(), dtype=np.float64)
    for cx in (0.38, 0.62):
        rut = np.exp(-((u - cx - 0.02 * np.sin(yy / 90.0 + cx * 9)) / 0.025) ** 2)
        img *= (1 - 0.25 * rut)[..., None]
    return Image.fromarray(np.dstack([np.clip(img, 0, 255), alpha * 255 * 0.85]).astype(np.uint8), "RGBA")


def trample_decal(size, seed=0):
    """Вытоптанное пятно: пыль и примятая трава, края рваные."""
    c = Canvas(size, size, base="#7e6a4a", seed=seed, tile=False)
    c.underpaint(["#7e6a4a", "#6e5c40", "#8e7854", "#64563e"], cell=64, seed=seed)
    c.strokes(int(size * size / 260), ["#9a8460", "#5e4e38", "#a89068", "#6a5a40"], length=(12, 40),
              width=(4, 12), angle=0, angle_jitter=180, alpha=(0.2, 0.45), bristles=3, curve=0.3)
    yy, xx = np.mgrid[0:size, 0:size]
    r = np.hypot(xx - size / 2, yy - size / 2) / (size / 2)
    n = fbm(size, size, 60, 4, seed=seed + 2, tile=False)
    edge = 0.8 + 0.3 * (n - 0.5)
    alpha = np.clip((edge - r) / 0.2, 0, 1) * (0.7 + 0.3 * n)
    img = np.asarray(c.image(), dtype=np.float64)
    return Image.fromarray(np.dstack([img, alpha * 255 * 0.8]).astype(np.uint8), "RGBA")


def spark(size=32):
    """Искра: мягкая светящаяся точка, вытянутая вверх (для аддитивного смешивания)."""
    yy, xx = np.mgrid[0:size, 0:size] + 0.5
    d = np.hypot((xx - size / 2) / (size * 0.22), (yy - size / 2) / (size * 0.4))
    a = np.clip(1 - d, 0, 1) ** 1.5
    core = np.clip(1 - d * 1.8, 0, 1)
    rgb = np.stack([255 * a, (170 + 85 * core) * a, (80 + 150 * core) * a], -1)
    return Image.fromarray(np.dstack([rgb, a * 255]).astype(np.uint8), "RGBA")


def build_all(out_dir):
    from gen_camp import texture_import
    os.makedirs(out_dir, exist_ok=True)
    items = {
        "smoke_puff.png": sheet(smoke_frame, 256, [11, 23, 37, 41]),
        "flame.png": sheet(flame_frame, 128, [5, 6, 7, 8]),
        "path_decal.png": path_decal(256, 1024, seed=3),
        "trample_decal.png": trample_decal(512, seed=4),
        "spark.png": spark(32),
    }
    for name, img in items.items():
        p = os.path.join(out_dir, name)
        img.save(p, optimize=True)
        texture_import(p, mipmaps=True, vram=False)
        print("  ", name, img.size)
