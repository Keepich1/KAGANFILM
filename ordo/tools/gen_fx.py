"""Рисованные спрайты эффектов боя (ТЗ 11.1: «пороховой дым и пожары как рисованные 2D-эффекты,
как в «Аркейне»; пыль из-под конницы; частицы: пух ковыля, пепел, искры»).

    python3 tools/gen_fx.py          # из папки ordo/, пишет assets/textures/fx/*.png

Дым и пыль — не размытые пятна, а «клубы» из долей (как цветная капуста): у каждой доли своя
выпуклость, поэтому шейдер освещает их солнцем ступенями (2–3 тона) с чёткой нарисованной
границей. Каналы атласа дыма/пыли (данные, не цвет):
    R, G — нормаль клуба (x вправо, y вверх), 0..1
    B    — мазки кисти по контуру долей (ломают границу света и края)
    A    — «плотность»: шейдер режет её порогом → чёткий край; порог растёт с возрастом → клуб тает
Вспышка выстрела, пух ковыля, пепел — обычные цветные спрайты с альфой.
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
from paint import fbm, value_noise  # noqa: E402

OUT = "assets/textures/fx"


# ---------------------------------------------------------------- клуб дыма

def _lobes(rs, n_main, flat, spread, scallops):
    """Доли клуба: (cx, cy, r) в долях клетки. Основная масса внизу, клубы тянутся вверх."""
    lobes = [(0.5 + rs.normal(0, 0.02), 0.6, rs.uniform(0.2, 0.25) * spread)]
    for i in range(n_main):
        # вверх и в стороны: клуб растёт кверху
        a = rs.uniform(-math.pi * 0.92, -math.pi * 0.08) if rs.random() < 0.8 else rs.uniform(0.1, math.pi - 0.1)
        d = rs.uniform(0.12, 0.2) * spread
        r = rs.uniform(0.1, 0.17) * spread
        lobes.append((0.5 + math.cos(a) * d * 1.2, 0.58 + math.sin(a) * d * flat, r))
    # крупные «гребешки» по верхнему краю
    base = list(lobes)
    for i in range(scallops):
        cx, cy, r = base[rs.integers(len(base))]
        a = rs.uniform(-math.pi * 0.95, -math.pi * 0.05)
        rr = rs.uniform(0.055, 0.09) * spread
        lobes.append((cx + math.cos(a) * (r - rr * 0.2), cy + math.sin(a) * (r - rr * 0.2) * flat, rr))
    return lobes


def billow_cell(seed, S=256, flat=1.0, spread=1.0, n_main=5, scallops=5, warp=0.03, wisp=0.0):
    """Один клуб: возвращает (h, w, 4) float — нормаль xy, мазки, плотность."""
    rs = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64) / S
    # лёгкое искривление координат: край не циркульный
    wx = (fbm(S, S, cell=S / 3, octaves=3, seed=seed * 7 + 1, tile=False) - 0.5) * 2 * warp
    wy = (fbm(S, S, cell=S / 3, octaves=3, seed=seed * 7 + 2, tile=False) - 0.5) * 2 * warp
    X, Y = xx + wx, yy + wy
    lobes = _lobes(rs, n_main, flat, spread, scallops)
    h = np.zeros((S, S))
    nl = np.zeros((S, S, 3))
    nl[..., 2] = 1
    for cx, cy, r in lobes:
        dx = (X - cx) / r
        dy = (Y - cy) / (r * flat)
        d2 = dx * dx + dy * dy
        cap = np.sqrt(np.clip(1 - d2, 0, None))
        k = cap * rs.uniform(0.85, 1.0) * r / 0.25 + (cap > 0) * 0.02
        win = k > h
        h = np.where(win, k, h)
        # нормаль сферы доли (y вверх: в картинке y растёт вниз)
        nl[win] = np.stack([dx, -dy, cap], -1)[win]
    # общая выпуклость всего клуба: свет ложится на клуб целиком, доли — вторым планом
    m = h > 0
    cyc = (yy[m]).mean() if m.any() else 0.55
    cxc = (xx[m]).mean() if m.any() else 0.5
    R = max(0.2, np.sqrt(m.mean() / math.pi)) * 1.05
    gx_, gy_ = (X - cxc) / R, (Y - cyc) / (R * flat)
    gz = np.sqrt(np.clip(1 - gx_ ** 2 - gy_ ** 2, 0.04, None))
    ng = np.stack([gx_, -gy_, gz], -1)
    ng /= np.linalg.norm(ng, axis=-1, keepdims=True)
    n = nl * 0.62 + ng * 0.38
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    # смягчить складки на 1–2 пикселя (край мазка, не ступенька пикселя)
    for c in range(3):
        n[..., c] = np.asarray(Image.fromarray(((n[..., c] * 0.5 + 0.5) * 255).astype(np.uint8))
                               .filter(ImageFilter.GaussianBlur(1.3)), dtype=np.float64) / 255 * 2 - 1
    n /= np.linalg.norm(n, axis=-1, keepdims=True) + 1e-9
    hn = h / max(h.max(), 1e-6)
    # плотность: высота × мягкий шум (тает неровно, «съедается» с краёв и в тонких местах)
    noise = fbm(S, S, cell=S / 5, octaves=4, seed=seed * 7 + 3, tile=False)
    dens = np.clip(0.18 + hn * 1.1, 0, 1) * (0.7 + 0.3 * noise)
    if wisp > 0:
        # верх пыли — рваный, прозрачнее
        dens *= 1 - wisp * np.clip((0.62 - yy) / 0.5, 0, 1) * (0.6 + 0.4 * noise)
    dens[h <= 0] = 0
    strokes = _contour_strokes(seed, S, hn)
    out = np.zeros((S, S, 4))
    out[..., 0] = n[..., 0] * 0.5 + 0.5
    out[..., 1] = n[..., 1] * 0.5 + 0.5
    out[..., 2] = strokes
    out[..., 3] = dens
    return out


def _contour_strokes(seed, S, h):
    """Мазки кисти: короткие дуги вдоль линий уровня клуба (как рука по форме)."""
    rs = np.random.default_rng(seed + 991)
    im = Image.new("L", (S * 2, S * 2), 128)
    dr = ImageDraw.Draw(im)
    gy, gx = np.gradient(h)
    for _ in range(int(S * 1.6)):
        x, y = rs.uniform(0, S), rs.uniform(0, S)
        if h[int(y), int(x)] <= 0.02:
            continue
        # направление — поперёк градиента (вдоль контура)
        a = math.atan2(gy[int(y), int(x)], gx[int(y), int(x)]) + math.pi / 2 + rs.normal(0, 0.25)
        L = rs.uniform(S * 0.03, S * 0.09)
        w = rs.uniform(1.5, 4.0)
        v = int(np.clip(128 + rs.normal(0, 55), 20, 235))
        pts = []
        bend = rs.normal(0, 0.25)
        for t in np.linspace(-0.5, 0.5, 6):
            px = x + math.cos(a) * t * L - math.sin(a) * bend * L * (t * t - 0.25)
            py = y + math.sin(a) * t * L + math.cos(a) * bend * L * (t * t - 0.25)
            pts.append((px * 2, py * 2))
        dr.line(pts, fill=v, width=int(w * 2))
    im = im.filter(ImageFilter.GaussianBlur(1.0)).resize((S, S), Image.LANCZOS)
    return np.asarray(im, dtype=np.float64) / 255


def atlas(cells, cols, rows):
    S = cells[0].shape[0]
    out = np.zeros((rows * S, cols * S, 4))
    for i, c in enumerate(cells):
        r, k = divmod(i, cols)
        out[r * S:(r + 1) * S, k * S:(k + 1) * S] = c
    return out


def save_rgba(arr, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(path, optimize=True)
    print("  ", path, arr.shape[1], "x", arr.shape[0])


# ---------------------------------------------------------------- вспышка выстрела

def flash_cell(seed, S=128):
    """Вспышка: язык пламени вдоль ствола (+x), слои — оранжевый, жёлтый, белое ядро. Чёткие края."""
    rs = np.random.default_rng(seed)
    ss = 4
    W = S * ss
    layers = [((255, 120, 40), 1.0, 0.95), ((255, 196, 90), 0.72, 1.0), ((255, 246, 214), 0.4, 1.0)]
    im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    cx, cy = W * 0.22, W * 0.5
    spikes = []
    n = rs.integers(6, 9)
    for i in range(n):
        a = rs.normal(0, 0.55) if i > 1 else rs.normal(0, 0.12)
        L = rs.uniform(0.35, 0.75) * W if abs(a) < 0.5 else rs.uniform(0.15, 0.3) * W
        spikes.append((a, L, rs.uniform(0.05, 0.1) * W))
    for color, k, alpha in layers:
        lay = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        d = ImageDraw.Draw(lay)
        r0 = W * 0.09 * k + W * 0.02
        d.ellipse([cx - r0, cy - r0 * 0.9, cx + r0 * 1.3, cy + r0 * 0.9], fill=color + (int(alpha * 255),))
        for a, L, w in spikes:
            tip = (cx + math.cos(a) * L * k, cy + math.sin(a) * L * k)
            nx, ny = -math.sin(a), math.cos(a)
            ww = w * k
            d.polygon([(cx + nx * ww, cy + ny * ww), tip, (cx - nx * ww, cy - ny * ww)], fill=color + (int(alpha * 255),))
        im = Image.alpha_composite(im, lay)
    im = im.filter(ImageFilter.GaussianBlur(ss * 0.6)).resize((S, S), Image.LANCZOS)
    return np.asarray(im, dtype=np.float64) / 255


# ---------------------------------------------------------------- пух ковыля, пепел

def fluff_cell(seed, S=64):
    """Пух ковыля: тонкое ость-перо, изогнутое, с волосками."""
    rs = np.random.default_rng(seed)
    ss = 4
    W = S * ss
    im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    a0 = rs.uniform(-0.6, 0.6)
    pts = []
    for t in np.linspace(0, 1, 24):
        a = a0 + 0.9 * t * t
        pts.append((W * 0.15 + t * W * 0.7 * math.cos(a), W * 0.5 + t * W * 0.7 * math.sin(a) * 0.6))
    d.line(pts, fill=(246, 240, 225, 255), width=ss)
    for i, (x, y) in enumerate(pts[3:]):
        for side in (-1, 1):
            L = W * (0.05 + 0.1 * math.sin(math.pi * (i + 3) / len(pts)))
            a = a0 + side * rs.uniform(0.9, 1.3)
            d.line([(x, y), (x + math.cos(a) * L, y + math.sin(a) * L)], fill=(250, 246, 235, 150), width=max(1, ss // 2))
    im = im.resize((S, S), Image.LANCZOS)
    return np.asarray(im, dtype=np.float64) / 255


def ash_cell(seed, S=64):
    """Хлопья пепла: неровный многоугольник, тёмно-серый с тёплой кромкой."""
    rs = np.random.default_rng(seed)
    ss = 4
    W = S * ss
    im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    k = rs.integers(5, 8)
    ang = np.sort(rs.uniform(0, 2 * math.pi, k))
    pts = [(W / 2 + math.cos(a) * W * rs.uniform(0.18, 0.42), W / 2 + math.sin(a) * W * rs.uniform(0.12, 0.3)) for a in ang]
    d.polygon(pts, fill=(150, 112, 88, 255))
    inner = [(W / 2 + (x - W / 2) * 0.72, W / 2 + (y - W / 2) * 0.72) for x, y in pts]
    d.polygon(inner, fill=(70, 66, 66, 255))
    im = im.resize((S, S), Image.LANCZOS)
    return np.asarray(im, dtype=np.float64) / 255


def main():
    print("Эффекты боя:")
    # дым: 16 клубов разной формы (4×4)
    smoke = [billow_cell(100 + i, flat=0.92, spread=1.0 + 0.08 * (i % 3), n_main=4 + i % 3,
                         scallops=6 + (i * 3) % 5) for i in range(16)]
    save_rgba(atlas(smoke, 4, 4), f"{OUT}/smoke_billow.png")
    # пыль: приплюснутые рваные клубы (4×2)
    dust = [billow_cell(300 + i, flat=0.62, spread=1.12, n_main=6, scallops=8, warp=0.05, wisp=0.75)
            for i in range(8)]
    save_rgba(atlas(dust, 4, 2), f"{OUT}/dust_puff.png")
    save_rgba(atlas([flash_cell(500 + i) for i in range(4)], 2, 2), f"{OUT}/muzzle_flash.png")
    save_rgba(atlas([fluff_cell(700 + i) for i in range(4)], 2, 2), f"{OUT}/fluff.png")
    save_rgba(atlas([ash_cell(800 + i) for i in range(4)], 2, 2), f"{OUT}/ash.png")


if __name__ == "__main__":
    main()
