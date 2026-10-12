"""Общий рисованный атлас кыпчаков: assets/textures/kipchak/atlas.png (2048×2048, RGBA).

Один атлас на все постройки и предметы лагеря (ТЗ 11.5: один материал на объект).
Каждая область рисуется отдельно (paint.Canvas) и вклеивается с полями: у
повторяющихся по оси областей поле — продолжение узора (бесшовный повтор без
шва при мип-картах), у остальных — растянутый край.

Альфа нужна только вырезам (вымпел, навес, пятно земли); в остальных местах 1.

    REGIONS["wall_boz"]      → (x0, y0, x1, y1) в пикселях
    uv("wall_boz")           → (u0, v0, u1, v1) для Mesh.map_uv
"""
from __future__ import annotations

import math
import os

import numpy as np
from PIL import Image

import gen_camp_brush as B
from paint import Canvas, fbm, spiral_points, value_noise
from palette import KIPCHAK, MATERIAL, rgb8

SIZE = 2048
PAD = 8

# Параметры верёвочной сетки купола — общие с gen_camp_yurt.py (нарисованная и
# смоделированная сетки совпадают): корней на одну плитку купола, сдвиг верёвки
# от низа купола к тюндюку в долях плитки.
NET_ROOTS_PER_TILE = 4
NET_TWIST = 0.375
_NET_SINB = 0.75      # синус полуугла конуса купола (боз үй)
_NET_RATIO = 0.264    # радиус у тюндюка / радиус низа купола
_NET_TILE = math.pi / 2


def net_curve(j, fam, n=12, t_end=0.985):
    """Верёвка сетки как прямая на развёртке конуса (натянутая верёвка):
    → (u в долях плитки, t 0..1 от низа купола к тюндюку). j — номер корня, fam ±1 — направление."""
    dphi = fam * NET_TWIST * _NET_TILE * _NET_SINB
    a = np.array([1.0, 0.0])
    b = _NET_RATIO * np.array([math.cos(dphi), math.sin(dphi)])
    lam = np.linspace(0, 1, n)[:, None]
    p = a + lam * (b - a)
    rho = np.linalg.norm(p, axis=1)
    phi = np.arctan2(p[:, 1], p[:, 0])
    t = (1 - rho) / (1 - _NET_RATIO) * t_end
    u = j / NET_ROOTS_PER_TILE + phi / _NET_SINB / _NET_TILE
    return u, t

# Цвета
FELT = ["#e7e3d8", "#dcd6c6", "#efebe1", "#d3ccba"]
FELT_FIBRE = ["#f7f4ec", "#c9c0aa", "#e4ddcc", "#bcb39d"]
BROWN = "#5b3a22"
BROWN_DARK = "#3f2416"
CINNABAR = KIPCHAK["main"]
CARMINE = KIPCHAK["carmine"]
CIN_LIGHT = KIPCHAK["light"]
CIN_DARK = KIPCHAK["dark"]
ROPE = "#8f7550"
ROPE_LIGHT = "#c2a77a"
ROPE_SHADOW = "#5a4a3a"

# ---------------------------------------------------------------- раскладка
# имя: (x0, y0, w, h, повтор: "x" | "y" | "xy" | None)
LAYOUT = {
    "wall_boz": (8, 8, 1008, 384, "x"),
    "wall_ordo": (1032, 8, 1008, 384, "x"),
    "dome": (8, 408, 1008, 512, "x"),
    "eave_boz": (1032, 408, 1008, 128, "x"),
    "eave_ordo": (1032, 552, 1008, 128, "x"),
    "wattle": (1032, 696, 512, 224, "x"),
    "koshma": (1560, 696, 256, 224, "x"),
    "rope": (1832, 696, 64, 224, "y"),
    "pole": (1912, 696, 128, 224, "y"),
    "door": (8, 936, 256, 512, None),
    "frame": (280, 936, 128, 512, "y"),
    "walnut": (424, 936, 256, 512, "y"),
    "wood": (696, 936, 256, 512, "y"),
    "shield": (968, 936, 320, 320, None),
    "tassel": (1304, 936, 128, 320, "x"),
    "pennant": (1448, 936, 592, 224, None),
    "awning": (1448, 1176, 592, 272, None),
    "brass": (968, 1272, 128, 176, None),
    "tunduk_hole": (1112, 1272, 112, 112, None),
    "embers": (1240, 1272, 192, 176, None),
    "earth": (8, 1464, 512, 512, None),
    "hay": (536, 1464, 256, 256, "xy"),
    "stones": (808, 1464, 256, 256, "xy"),
    "iron": (1080, 1464, 256, 256, None),
    "planks": (1352, 1464, 256, 256, "xy"),
    "lattice": (1624, 1464, 256, 256, "xy"),
    "saddlecloth": (536, 1736, 256, 256, None),
    "felt_grey": (808, 1736, 256, 256, "xy"),
    "leather": (1080, 1736, 128, 128, "xy"),
    "logend": (1224, 1736, 128, 128, None),
    "koshma_end": (1368, 1736, 128, 128, None),
    "felt_white": (1512, 1736, 256, 256, "xy"),
    "hair": (1784, 1736, 128, 256, "x"),
    "bark": (1928, 1736, 112, 256, "y"),
    "trough_in": (1080, 1880, 128, 112, None),
}

REGIONS = {k: (x, y, x + w, y + h) for k, (x, y, w, h, _) in LAYOUT.items()}


def uv(name, inset=0.0):
    """Прямоугольник области в UV (u0, v0, u1, v1); inset — отступ внутрь в пикселях."""
    x0, y0, x1, y1 = REGIONS[name]
    return ((x0 + inset) / SIZE, (y0 + inset) / SIZE, (x1 - inset) / SIZE, (y1 - inset) / SIZE)


# ---------------------------------------------------------------- области

def paint_wall_boz(w, h):
    c = Canvas(w, h, base=FELT[0], seed=11)
    B.felt(c, FELT, FELT_FIBRE, seed=11, direction=0, dir_jitter=22)
    _lattice_relief(c, 56, seed=12)
    # пояса (ТЗ 11.3): коричневые завитки между тонкими линиями, ромбы
    B.curl_belt(c, 30, 84, 14, BROWN, 4.6, BROWN_DARK, 2.4, seed=3, double=True)
    B.rhomb_belt(c, 166, 206, 18, CINNABAR, BROWN_DARK, "#f1e8d2", BROWN_DARK, 2.2, seed=5)
    B.curl_belt(c, 272, 312, 18, BROWN, 3.6, BROWN_DARK, 2.0, seed=7)
    # верёвки поверх стены (тянут войлок к решётке)
    for y, s in ((128, 21),):
        B.rope_line(c, [(x, y + 1.5 * math.sin(x / w * 2 * math.pi * 3)) for x in np.linspace(0, w, 25)],
                    5.0, ROPE, ROPE_LIGHT, ROPE_SHADOW, seed=s, shadow_off=(0, 3))
    _wall_light(c, eave=18, dust_from=320)
    return c.image()


def paint_wall_ordo(w, h):
    c = Canvas(w, h, base=FELT[0], seed=21)
    B.felt(c, FELT, FELT_FIBRE, seed=21, direction=0, dir_jitter=22)
    _lattice_relief(c, 44, seed=22)
    # широкий киноварный пояс с белыми «кочкор мүйүз» (как пояс интерфейса кыпчаков)
    y0, y1 = 28, 104
    band = B.rows(c, y0, y1, feather=1.5)
    cb = Canvas(w, h, base=CINNABAR, seed=23)
    B.felt(cb, [CINNABAR, "#a33429", "#bb4436", "#9c2f27"], ["#c4503f", "#8a2a22", "#b23c30"], seed=23, density=0.6)
    _paste_masked(c, cb, band)
    n = 10
    for i in range(n):
        x = (i + 0.5) * w / n
        B.horn(c, x, (y0 + y1) / 2 + 4, 52, "#f1e6cf", 5.0, seed=40 + i)
        B.diamond(c, i * w / n, (y0 + y1) / 2, 7, 10, "#f1e6cf")
    for y in (y0 - 1, y1 + 1):
        B.hline(c, y, 3.2, BROWN_DARK, seed=y)
    B.hline(c, y0 - 7, 1.8, "#c9a24a", seed=3)  # охристый кант
    B.hline(c, y1 + 7, 1.8, "#c9a24a", seed=4)
    B.curl_belt(c, 126, 160, 20, BROWN, 3.2, BROWN_DARK, 1.8, seed=27)
    B.rhomb_belt(c, 214, 252, 22, CARMINE, BROWN_DARK, "#f1e8d2", BROWN_DARK, 2.0, seed=25)
    B.curl_belt(c, 296, 330, 20, BROWN, 3.2, BROWN_DARK, 1.8, seed=29)
    B.rope_line(c, [(x, 186 + 1.5 * math.sin(x / w * 2 * math.pi * 3)) for x in np.linspace(0, w, 25)],
                5.0, ROPE, ROPE_LIGHT, ROPE_SHADOW, seed=31, shadow_off=(0, 3))
    _wall_light(c, eave=14, dust_from=340)
    return c.image()


def _lattice_relief(c: Canvas, step, seed=0):
    """Решётка-кереге сквозь войлок: еле заметные косые гребни."""
    rs = np.random.default_rng(seed)
    n = int(round(c.w / step))
    step = c.w / n
    for i in range(-n, 2 * n):
        for d in (-1, 1):
            x0 = i * step
            pts = [(x0, -4), (x0 + d * (c.h + 8) * 0.9, c.h + 4)]
            c.line(pts, rs.uniform(3, 5), "#f7f2e4", 0.10, wobble=1.5, seed=seed + i * 2 + (d > 0))


def _wall_light(c: Canvas, eave=16, dust_from=320):
    """Нарисованный свет стены: тень под свесом, пыльный тёмный низ, коричневая кайма."""
    H = c.h
    f = B.vgrad(c, [(0, 0.5), (eave * 0.5, 0.64), (eave, 0.8), (eave * 2.5, 0.92), (eave * 4.5, 1.0),
                    (dust_from - 40, 1.0), (dust_from, 0.95), (H - 22, 0.8), (H, 0.66)])
    n = B.noise(c, 40, seed=c.seed + 3)
    f = f * (0.96 + 0.08 * n)
    B.tint_ramp(c, f, "#2a2238", "#ffffff", 1.0)
    # пыль у земли: тёплые грязные мазки
    c.strokes(int(c.w * 0.5), ["#9c8565", "#86704f", "#b29b78"], length=(8, 26), width=(3, 8),
              angle=-90, angle_jitter=25, alpha=(0.08, 0.25), region=(0, H - 46, c.w, H), bristles=2)
    B.hline(c, H - 6, 6, "#5e4630", seed=5)


def _paste_masked(c: Canvas, other: Canvas, mask):
    a = np.asarray(c.img, dtype=np.float64)
    b = np.asarray(other.img, dtype=np.float64)
    m = np.asarray(mask, dtype=np.float64)[..., None]
    c._blend(a * (1 - m) + b * m)


def paint_dome(w, h):
    """Купол: войлок, к тюндюку темнее (копоть), нарисованная ромбическая сетка верёвок.
    y=0 — у тюндюка, y=h — низ купола; по x одна плитка (повторяется)."""
    c = Canvas(w, h, base=FELT[1], seed=31)
    tones = ["#e3ddcf", "#d6cfbd", "#ebe6da", "#cdc5b1"]
    B.felt(c, tones, FELT_FIBRE, seed=31, density=0.9, direction=90, dir_jitter=14)
    # швы кусков войлока (үзүк): горизонтальная кромка со стёжкой
    for ys, s in ((h * 0.42, 3), (h * 0.78, 4)):
        pts = [(x, ys + 3 * math.sin(x / w * 2 * math.pi * 2 + s)) for x in np.linspace(0, w, 30)]
        c.line([(p[0], p[1] + 4) for p in pts], 7, "#b3a587", 0.35, wobble=1.0, seed=s)
        c.line(pts, 2.0, "#9d8c6c", 0.8, wobble=0.6, seed=s + 1)
    # копоть и тон: темнее к тюндюку, светлее посередине
    f = B.vgrad(c, [(0, 0.5), (h * 0.12, 0.72), (h * 0.3, 0.92), (h * 0.55, 1.02), (h, 0.96)])
    n = B.noise(c, 60, seed=33)
    soot = np.clip(1 - B.vgrad(c, [(0, 1), (h * 0.35, 0.0), (h, 0)]) * (0.6 + 0.6 * n), 0, 1)
    B.tint_ramp(c, f * (0.85 + 0.15 * soot), "#3a2c26", "#ffffff", 1.0)
    # нарисованная сетка верёвок (совпадает с моделью)
    m = NET_ROOTS_PER_TILE
    for fam in (-1, 1):
        for j in range(m):
            u, t = net_curve(j, fam, 14, t_end=1.0)
            pts = np.column_stack([u * w, (1 - t) * h])
            # верёвка одним мазком: к тюндюку тоньше (сжатие развёртки) — рисуем двумя кусками
            half = len(pts) // 2
            B.rope_line(c, pts[half:], 7.0, ROPE, ROPE_LIGHT, ROPE_SHADOW, seed=100 + j * 3 + fam,
                        shadow_off=(0, 4.0))
            B.rope_line(c, pts[:half + 1], 4.5, ROPE, ROPE_LIGHT, ROPE_SHADOW, seed=200 + j * 3 + fam,
                        shadow_off=(0, 3.0))
    return c.image()


def _rope_var(c: Canvas, pts, widths, seed=0):
    for i in range(len(pts) - 1):
        seg = pts[i:i + 2]
        wd = float(widths[i])
        B.rope_line(c, seg, wd, ROPE, ROPE_LIGHT, ROPE_SHADOW, seed=seed * 31 + i, shadow_off=(0, wd * 0.6))


def paint_eave(w, h, rich=False):
    """Свес купола (плечо): войлок, внизу кромка с тёмным шнуром; у ордо — киноварная кайма."""
    c = Canvas(w, h, base=FELT[1], seed=41 + rich)
    B.felt(c, ["#e3ddcf", "#d6cfbd", "#ebe6da", "#cdc5b1"], FELT_FIBRE, seed=41 + rich, direction=90, dir_jitter=14)
    if rich:
        y0, y1 = h - 58, h - 10
        cb = Canvas(w, h, base=CINNABAR, seed=44)
        B.felt(cb, [CINNABAR, "#a33429", "#bb4436"], ["#c4503f", "#8a2a22"], seed=44, density=0.6)
        _paste_masked(c, cb, B.rows(c, y0, y1, feather=1.2))
        n = 24
        for i in range(n):
            x = (i + 0.5) * w / n
            B.s_scroll(c, x - w / n / 2, (y0 + y1) / 2, w / n, (y1 - y0) / 2 * 0.8, "#f1e6cf", 3.4, seed=60 + i)
        B.hline(c, y0 - 1, 2.6, BROWN_DARK, seed=1)
        B.hline(c, y0 - 6, 1.6, "#c9a24a", seed=2)
    # верёвки сетки спускаются по плечу к стене парами
    m = NET_ROOTS_PER_TILE
    for j in range(m):
        x = j / m * w
        for dx in (-5, 5):
            B.rope_line(c, [(x + dx, 0), (x + dx * 0.6, h * 0.5), (x + dx * 0.3, h - 8)], 6.0, ROPE, ROPE_LIGHT,
                        ROPE_SHADOW, seed=70 + j * 2 + (dx > 0), shadow_off=(2, 2))
    f = B.vgrad(c, [(0, 0.98), (h * 0.6, 1.0), (h - 12, 0.86), (h, 0.6)])
    B.tint_ramp(c, f, "#2e2433", "#ffffff", 1.0)
    B.hline(c, h - 5, 5.0, "#4a3020", seed=9)  # шнур по кромке
    return c.image()


def paint_door(w, h):
    """Дверь (эшик): две крашеные створки (киноварь по дереву), резные филёнки с охрой,
    резной бордюр, латунные гвозди. Свет нарисован: верх светлее, низ темнее."""
    c = Canvas(w, h, base="#6e2e1e", seed=51, tile=False)
    B.wood(c, ["#6e2e1e", "#5e261a", "#7c3824", "#652a1c"], ["#4a1a12", "#8a4430", "#5a2216"], vertical=True,
           seed=51, knots=1)
    mid = w / 2
    gold, gold_l, groove = "#d49a48", "#f2d08c", "#2a0e08"
    for leaf in (0, 1):
        x0 = leaf * mid + 9
        x1 = x0 + mid - 18
        # резной бордюр по краю створки: бегущий завиток
        n = 9
        period = (h - 16) / n

        def border(color, dx, dy, x0=x0, x1=x1, n=n, period=period):
            for xx in (x0 + 4, x1 - 4):
                for i in range(n):
                    p = B.s_path(period, 4.2, turns=1.1)
                    p = np.column_stack([p[:, 1], p[:, 0]]) + np.array([xx + dx, 8 + (i + 0.5) * period + dy])
                    c.line(p, 1.8, color, 1.0, wobble=0.2, seed=i)
        B.emboss(c, border, gold_l, groove, gold, off=1.0)
        px0, px1 = x0 + 13, x1 - 13
        panels = [(16, 132), (150, 352), (370, 496)]
        for k, (py0, py1) in enumerate(panels):
            c.rect(px0 - 3, py0 - 3, px1 + 3, py1 + 3, groove, 0.9)
            c.rect(px0 - 3, py0 - 3, px1 + 3, py0 - 1, "#c07a50", 0.8)
            c.rect(px0 - 3, py0 - 3, px0 - 1, py1 + 3, "#a8653e", 0.7)
            c.rect(px0, py0, px1, py1, "#4e1a12" if k == 1 else "#5a2216", 0.95)
            c.strokes(30, ["#6a281a", "#3e140e"], length=(10, 30), width=(2, 5), angle=90, angle_jitter=6,
                      alpha=(0.2, 0.4), bristles=2, region=(px0, py0, px1, py1))
            cx, cy = (px0 + px1) / 2, (py0 + py1) / 2

            def motif(color, dx, dy, cx=cx, cy=cy, k=k, px0=px0, px1=px1, py0=py0, py1=py1):
                if k == 1:
                    B.horn(c, cx + dx, cy + 18 + dy, (px1 - px0) * 0.82, color, 4.4, seed=7)
                    B.horn(c, cx + dx, cy - 52 + dy, (px1 - px0) * 0.56, color, 3.4, flip=True, seed=8)
                else:
                    B.diamond(c, cx + dx, cy + dy, (px1 - px0) * 0.32, (py1 - py0) * 0.34, color)
                    B.diamond(c, cx + dx, cy + dy, (px1 - px0) * 0.15, (py1 - py0) * 0.16, CINNABAR)
            B.emboss(c, motif, gold_l, groove, gold, off=1.8)
        for yy in (10, 141, 361, 503):
            for xx in (x0 + 5, (x0 + x1) / 2, x1 - 5):
                c.ellipse(xx + 0.8, yy + 0.8, 3.4, 3.4, "#1a0a06", 0.8)
                c.ellipse(xx, yy, 2.8, 2.8, "#c99a48", 1.0)
                c.ellipse(xx - 0.8, yy - 0.8, 1.2, 1.2, "#fff0b8", 1.0)
    c.rect(mid - 2, 0, mid + 2, h, "#1a0805", 0.95)
    f = B.vgrad(c, [(0, 1.1), (h * 0.45, 1.0), (h, 0.74)])
    B.tint_ramp(c, f, "#2a1e22", "#ffffff", 1.0)
    return c.image()


def paint_frame(w, h):
    """Резной косяк: орех, бегущий завиток в пазу, киноварь в глубине резьбы."""
    c = Canvas(w, h, base=MATERIAL["walnut"], seed=61)
    B.wood(c, ["#5e3e26", "#4e3220", "#6a4630"], ["#3a2418", "#74503a"], vertical=True, seed=61, knots=1)
    # канавки по краям
    for x in (10, w - 10):
        c.line([(x, 0), (x, h)], 3, "#24150e", 0.9, wobble=0.4)
        c.line([(x - 2, 0), (x - 2, h)], 1.4, "#a87a50", 0.7, wobble=0.4)
    # углублённое поле с киноварью и резной завиток поверх
    c.rect(18, 0, w - 18, h, "#6e2219", 0.85)
    n = 4
    period = h / n

    def motif(color, dx, dy):
        for i in range(n):
            p = B.s_path(period, (w - 40) / 2, turns=1.25)
            p = np.column_stack([p[:, 1], p[:, 0]]) + np.array([w / 2 + dx, (i + 0.5) * period + dy])
            c.line(p, 7.0, color, 1.0, wobble=0.3, seed=i)
    B.emboss(c, motif, "#e8c48c", "#1e100a", "#b0804e", off=2.2)
    return c.image()


def paint_walnut(w, h):
    c = Canvas(w, h, base=MATERIAL["walnut"], seed=71)
    B.wood(c, ["#5a3b24", "#4a2f1f", "#684530", "#3f281a"], ["#2e1c12", "#7a5338", "#4a2e1e"], vertical=True,
           seed=71, knots=4)
    return c.image()


def paint_wood(w, h):
    """Светлое выветренное дерево: жерди, арба, колода, решётка."""
    c = Canvas(w, h, base=MATERIAL["wood_light"], seed=81)
    B.wood(c, ["#9a7a52", "#8a6c48", "#a9895e", "#7c6040"], ["#5e4630", "#b89a6e", "#6e5438"], vertical=True,
           seed=81, knots=5)
    return c.image()


def paint_pole(w, h):
    """Древко и жерди: тонкая кора тополя/ивы, продольные волокна, лёгкий блик."""
    c = Canvas(w, h, base="#7a6448", seed=91)
    B.wood(c, ["#7a6448", "#6a5640", "#86704f", "#5e4c38"], ["#4a3a2a", "#9a8460", "#56442e"], vertical=True,
           seed=91, knots=3)
    x = np.linspace(0, 1, w * c.ss)
    prof = 0.82 + 0.3 * np.sin(np.pi * x) ** 1.5  # нарисованная округлость
    B.multiply(c, np.repeat(prof[None, :], h * c.ss, axis=0))
    return c.image()


def paint_bark(w, h):
    c = Canvas(w, h, base="#5e4c3a", seed=95)
    B.wood(c, ["#5e4c3a", "#4e3e30", "#6c5a44", "#3e3226"], ["#2e241a", "#7e6a50", "#45372a"], vertical=True,
           seed=95, knots=6, density=1.4)
    c.strokes(160, ["#2a2018", "#3a2e22"], length=(10, 30), width=(1.5, 3), angle=90, angle_jitter=8,
              alpha=(0.4, 0.8), bristles=0)
    return c.image()


def paint_rope(w, h):
    """Верёвка: поперёк — объём (светлая середина), вдоль — косые витки."""
    c = Canvas(w, h, base=ROPE, seed=101)
    c.underpaint([ROPE, "#857049", "#9a8058"], cell=32, seed=101)
    step = 14
    for y in np.arange(-step, h + step, step):
        c.line([(0, y), (w, y + step * 0.9)], 5, "#6e5a3e", 0.7, wobble=0.3, seed=int(y) + 3)
        c.line([(0, y + 4), (w, y + 4 + step * 0.9)], 2.5, ROPE_LIGHT, 0.6, wobble=0.3, seed=int(y) + 5)
    x = np.linspace(0, 1, w * c.ss)
    prof = 0.62 + 0.55 * np.sin(np.pi * x) ** 0.8
    B.multiply(c, np.repeat(prof[None, :], h * c.ss, axis=0))
    return c.image()


def paint_koshma(w, h):
    """Свёрнутая кошма (шырдак): по x — вокруг рулона (повтор), по y — вдоль рулона.
    Киноварные и кремовые рога с тёмным шнуром."""
    c = Canvas(w, h, base=FELT[0], seed=111)
    B.felt(c, FELT, FELT_FIBRE, seed=111)
    # киноварное поле посередине длины, кремовые края
    y0, y1 = 34, h - 34
    cb = Canvas(w, h, base=CINNABAR, seed=112)
    B.felt(cb, [CINNABAR, "#a33429", "#bb4436"], ["#c4503f", "#8a2a22"], seed=112, density=0.6)
    _paste_masked(c, cb, B.rows(c, y0, y1, feather=1.2))
    for i in range(3):
        cy = y0 + (i + 0.5) * (y1 - y0) / 3
        for k in range(2):
            cx = (k + 0.5) * w / 2
            B.horn(c, cx, cy + 6, 48, "#efe2c8", 5.0, rot=90 if k else -90, seed=i * 2 + k)
            B.horn(c, cx, cy + 6, 48, BROWN_DARK, 1.6, rot=90 if k else -90, seed=i * 2 + k + 50)
    for y in (y0, y1):
        B.hline(c, y, 3.0, BROWN_DARK, seed=y)
        B.hline(c, y + (6 if y == y0 else -6), 2.0, "#c9a24a", seed=y + 1)
    for y in (12, h - 12):
        B.hline(c, y, 2.4, BROWN, seed=y + 2)
    return c.image()


def paint_koshma_end(w, h):
    """Торец свёрнутой кошмы: спираль слоёв войлока."""
    c = Canvas(w, h, base="#cfc2a4", seed=121, tile=False)
    B.felt(c, ["#d8ccb0", "#c6b896", "#e0d5bc"], FELT_FIBRE, seed=121, patches=False)
    sp = spiral_points(w / 2, h / 2, w * 0.47, turns=4.5, start=0, direction=1, n=240)
    c.line(sp, 3.0, "#7a6648", 0.85, wobble=0.5, seed=4)
    sp2 = spiral_points(w / 2 + 2, h / 2 + 1, w * 0.47, turns=4.5, start=0.6, direction=1, n=240)
    c.line(sp2, 1.6, CINNABAR, 0.6, wobble=0.5, seed=5)
    c.ellipse(w / 2, h / 2, 5, 5, "#4a3a2a", 0.9)
    return c.image()


def paint_felt_grey(w, h):
    c = Canvas(w, h, base="#a69a86", seed=131)
    B.felt(c, ["#a69a86", "#968a76", "#b2a690", "#8c806c"], ["#c2b6a0", "#7e7262", "#a09480"], seed=131)
    for y in (40, 170):
        B.hline(c, y, 3.0, "#6a5240", seed=y)
    return c.image()


def paint_felt_white(w, h):
    c = Canvas(w, h, base=FELT[0], seed=135)
    B.felt(c, FELT, FELT_FIBRE, seed=135)
    return c.image()


def paint_shield(w, h):
    """Круглый кожаный щит: тёмный обод, киноварное кольцо с белыми рогами, заклёпки."""
    c = Canvas(w, h, base="#5a3420", seed=141, tile=False)
    B.leather(c, ["#6a3e24", "#5a3420", "#7a4a2c", "#4e2c1a"], seed=141)
    cx, cy, R = w / 2, h / 2, w / 2 - 6
    yy, xx = np.mgrid[0:h * c.ss, 0:w * c.ss] / c.ss
    r = np.hypot(xx - cx, yy - cy) / R
    ring = np.clip((r - 0.5) / 0.02, 0, 1) * np.clip((0.8 - r) / 0.02, 0, 1)
    cb = Canvas(w, h, base=CINNABAR, seed=142, tile=False)
    B.felt(cb, [CINNABAR, "#a33429", "#bb4436"], ["#c4503f", "#8a2a22"], seed=142, density=0.5)
    _paste_masked(c, cb, ring)
    for k in range(6):
        a = k / 6 * 2 * math.pi
        px, py = cx + math.sin(a) * R * 0.65, cy - math.cos(a) * R * 0.65
        B.horn(c, px, py, R * 0.26, "#f0e4cc", 3.6, rot=math.degrees(a), seed=k)
    for rr, col, wd in ((0.5, BROWN_DARK, 3), (0.8, BROWN_DARK, 3), (0.97, "#2a170e", 10)):
        pts = [(cx + math.sin(a) * R * rr, cy - math.cos(a) * R * rr) for a in np.linspace(0, 2 * math.pi, 90)]
        c.line(pts, wd, col, 1.0, wobble=0.4)
    for k in range(16):
        a = k / 16 * 2 * math.pi
        px, py = cx + math.sin(a) * R * 0.89, cy - math.cos(a) * R * 0.89
        c.ellipse(px + 1, py + 1, 4.5, 4.5, "#1e120a", 0.7)
        c.ellipse(px, py, 3.6, 3.6, "#c99a48", 1.0)
        c.ellipse(px - 1, py - 1, 1.6, 1.6, "#f5dc9c", 1.0)
    # нарисованный свет: верх-лево светлее
    t = np.clip(0.5 - ((xx - cx) + (yy - cy)) / (2.2 * R), 0, 1)
    B.tint_ramp(c, t * (r < 1.02), "#5e4a52", "#fff4e0", 0.5)
    return c.image()


def paint_tassel(w, h):
    """Кисть из конского волоса: сверху киноварная обмотка, ниже тёмные пряди."""
    c = Canvas(w, h, base="#2a1c16", seed=151)
    c.underpaint(["#2a1c16", "#3a2820", "#1e1410", "#4a3426"], cell=24, seed=151)
    c.strokes(900, ["#4a362a", "#1a120e", "#6a5040", "#2e201a"], length=(40, 120), width=(1.2, 2.6), angle=90,
              angle_jitter=4, alpha=(0.4, 0.8), bristles=0, curve=0.1, region=(0, 70, w, h))
    cb = Canvas(w, h, base=CINNABAR, seed=152)
    B.felt(cb, [CINNABAR, "#a33429", "#c24a3a"], ["#d05a48", "#8a2a22"], seed=152, density=0.5)
    _paste_masked(c, cb, B.rows(c, 0, 72, feather=1.0))
    for y in (8, 26, 44, 64):
        B.hline(c, y, 2.6, "#f0d8a0" if y in (26, 44) else CIN_DARK, seed=y)
    f = B.vgrad(c, [(0, 1.05), (70, 0.95), (80, 0.7), (130, 1.0), (h, 0.8)])
    B.tint_ramp(c, f, "#201820", "#ffffff", 1.0)
    return c.image()


def paint_hair(w, h):
    """Волос для хвоста туга (светлее, рыжеватый)."""
    c = Canvas(w, h, base="#3a2a20", seed=155)
    c.underpaint(["#3a2a20", "#4e3828", "#2a1e18"], cell=24, seed=155)
    c.strokes(800, ["#6a5040", "#2a1e18", "#8a6a50", "#4a362a"], length=(40, 140), width=(1.2, 2.4), angle=90,
              angle_jitter=3, alpha=(0.4, 0.8), bristles=0, curve=0.1)
    return c.image()


def _pennant_shape(s, q):
    """Форма вымпела в долях: s — от древка (0) к концу (1), q — сверху (0) вниз (1).
    Верх почти прямой, низ сужается к острому концу и идёт волнами («языками»)."""
    top = 0.03 + 0.30 * s ** 1.6
    base = 0.97 - 0.62 * s ** 0.95
    tongues = 0.085 * (1 - 0.55 * s) * (0.5 + 0.5 * np.cos(2 * np.pi * (s * 4.5 + 0.1))) ** 1.5
    bot = base + tongues
    tip = np.clip((s - 0.93) / 0.07, 0, 1)
    mid = (top + bot) / 2
    top = top * (1 - tip) + mid * tip
    bot = bot * (1 - tip) + mid * tip
    return top, bot


def paint_pennant(w, h):
    """Вымпел туга: киноварь с белой волнистой каймой, белый знак у древка, складки."""
    c = Canvas(w, h, base=CINNABAR, seed=161, tile=False)
    B.felt(c, [CINNABAR, "#a83429", "#bc4234", "#9a2e26"], ["#c85040", "#8a2a22", "#b23c30"], seed=161, density=0.5,
           patches=False)
    H, W = h * c.ss, w * c.ss
    yy, xx = np.mgrid[0:H, 0:W] / c.ss
    s, q = xx / w, yy / h
    top, bot = _pennant_shape(s, q)
    # складки: вертикальные полосы света и тени (ткань волнуется)
    fold = 0.86 + 0.18 * np.sin(s * 2 * np.pi * 5.5 + 0.8) * (0.4 + 0.6 * s)
    B.multiply(c, fold)
    # белая волнистая кайма по низу и по концу, тонкая — по верху
    d_bot = (bot - q) * h
    d_top = (q - top) * h
    inside = (d_bot > 0) & (d_top > 0)
    border = inside & ((d_bot < 9) | (d_top < 4))
    img = np.asarray(c.img, dtype=np.float64)
    white = np.array(rgb8("#f2e8d4"), float)
    n = value_noise(W, H, 6, seed=3, tile=False)[..., None]
    img = np.where(border[..., None], white * (0.92 + 0.1 * n), img)
    dark = inside & (((d_bot >= 9) & (d_bot < 11.5)) | ((d_top >= 4) & (d_top < 5.5)))
    img = np.where(dark[..., None], np.array(rgb8(CIN_DARK), float), img)
    # рукав у древка
    sleeve = inside & (xx < 14)
    img = np.where(sleeve[..., None], img * 0.62, img)
    c._blend(img)
    B.horn(c, 62, h * 0.48, 66, "#f2e8d4", 6.0, seed=9)
    B.diamond(c, 128, h * 0.43, 9, 13, "#f2e8d4")
    alpha = ((d_bot > -0.5) & (d_top > -0.5)).astype(float)
    alpha = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS), float) / 255
    return _with_alpha(c.image(), alpha)


def paint_awning(w, h):
    """Навес ордо: верх (до 0.52 высоты) — киноварная крыша со складками провиса,
    низ — подзор: кремовая кайма с киноварными рогами, тёмный шнур, фестоны по краю (альфа)."""
    c = Canvas(w, h, base=CINNABAR, seed=171, tile=False)
    B.felt(c, [CINNABAR, "#a83429", "#bc4234", "#9a2e26"], ["#c85040", "#8a2a22"], seed=171, density=0.6,
           direction=90, dir_jitter=10)
    H, W = h * c.ss, w * c.ss
    yy, xx = np.mgrid[0:H, 0:W] / c.ss
    s, q = xx / w, yy / h
    # складки крыши: полосы света и тени вдоль ската
    roof = q < 0.52
    fold = np.where(roof, 0.88 + 0.14 * np.sin(s * 2 * np.pi * 8) * (0.3 + q), 1.0)
    B.multiply(c, fold * np.where(roof, np.interp(q, [0, 0.1, 0.52], [0.72, 1.0, 0.95]), 1.0))
    y0, y1 = h * 0.6, h * 0.86
    cb = Canvas(w, h, base=FELT[0], seed=172, tile=False)
    B.felt(cb, FELT, FELT_FIBRE, seed=172, density=0.6)
    _paste_masked(c, cb, B.rows(c, y0, y1, feather=1.0))
    n = 9
    for i in range(n):
        B.horn(c, (i + 0.5) * w / n, (y0 + y1) / 2 + 3, (y1 - y0) * 0.8, CINNABAR, 4.6, flip=True, seed=i)
    for y in (y0, y1):
        B.hline(c, y, 2.8, BROWN_DARK, seed=int(y))
    B.hline(c, h * 0.53, 4.0, BROWN_DARK, seed=3)   # шнур по краю крыши
    B.hline(c, h * 0.555, 2.0, "#c9a24a", seed=4)
    # фестоны: полукруглые языки по нижнему краю
    edge = 0.92 + 0.07 * np.abs(np.sin(np.pi * s * 9)) ** 0.6
    d = (edge - q) * h
    img = np.asarray(c.img, dtype=np.float64)
    img = np.where(((d > 0) & (d < 4))[..., None], np.array(rgb8(BROWN_DARK), float), img)
    c._blend(img)
    B.multiply(c, np.where(q > 0.86, 0.85, 1.0))
    alpha = (d > -0.5).astype(float)
    alpha = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS), float) / 255
    return _with_alpha(c.image(), alpha)


def paint_brass(w, h):
    c = Canvas(w, h, base=MATERIAL["brass"], seed=181, tile=False)
    c.underpaint(["#b58a3c", "#9a7230", "#d0a858", "#7d5a22"], cell=24, seed=181)
    c.strokes(200, ["#f0d08a", "#7d5a22", "#e2bc6a"], length=(10, 30), width=(2, 5), angle=60, angle_jitter=20,
              alpha=(0.2, 0.5), bristles=2)
    return c.image()


def paint_tunduk_hole(w, h):
    c = Canvas(w, h, base="#2a1c18", seed=185, tile=False)
    c.underpaint(["#2a1c18", "#3a2620", "#20160f"], cell=30, seed=185)
    yy, xx = np.mgrid[0:h * c.ss, 0:w * c.ss] / c.ss
    r = np.hypot(xx - w / 2, yy - h / 2) / (w / 2)
    B.multiply(c, np.clip(1.25 - 0.6 * r, 0.5, 1.2))
    return c.image()


def paint_embers(w, h):
    """Угли: тёмный пепел и светящиеся трещины (используется и как свечение)."""
    c = Canvas(w, h, base="#2a1a14", seed=191, tile=False)
    c.underpaint(["#2a1a14", "#3e2418", "#1c120e", "#4a3024"], cell=20, seed=191)
    c.strokes(140, ["#ff8a2c", "#ffb04a", "#e0501c"], length=(6, 20), width=(2, 5), angle=0, angle_jitter=180,
              alpha=(0.6, 1.0), bristles=1, curve=0.6)
    c.strokes(60, ["#fff0a0", "#ffd070"], length=(3, 8), width=(1.5, 3), angle=0, angle_jitter=180,
              alpha=(0.7, 1.0), bristles=0)
    c.strokes(120, ["#5a5048", "#3a302a", "#7a6a5a"], length=(6, 16), width=(3, 7), angle=0, angle_jitter=180,
              alpha=(0.4, 0.8), bristles=2)
    return c.image()


def paint_earth(w, h):
    """Вытоптанная земля загона: пятно с рваным краем (альфа), следы копыт, солома."""
    c = Canvas(w, h, base="#4e3e2c", seed=201, tile=False)
    c.underpaint(["#4e3e2c", "#43352a", "#5a4832", "#3a2e22", "#62503a"], cell=70, seed=201)
    c.strokes(1400, ["#5e4c36", "#40322a", "#6e5a40", "#382c22"], length=(10, 30), width=(4, 10), angle=0,
              angle_jitter=180, alpha=(0.15, 0.4), bristles=3, curve=0.4)
    rs = np.random.default_rng(202)
    for _ in range(260):  # следы копыт: тёмные полумесяцы с светлым краем
        x, y = rs.uniform(30, w - 30), rs.uniform(30, h - 30)
        a = rs.uniform(0, 360)
        pts = [(x + 4 * math.cos(math.radians(a + t)), y + 4 * math.sin(math.radians(a + t))) for t in range(-70, 71, 20)]
        c.line(pts, 2.2, "#3a2a1c", 0.7, wobble=0.2, seed=int(x * 7 + y))
        c.line([(p[0] - 1, p[1] - 1) for p in pts], 1.0, "#a08660", 0.5, wobble=0.2, seed=int(x + y * 3))
    c.strokes(220, ["#a88a4a", "#8a7040", "#b89a5a"], length=(6, 16), width=(1.2, 2.2), angle=0, angle_jitter=180,
              alpha=(0.4, 0.8), bristles=0, curve=0.2)
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot((xx - w / 2) / (w / 2), (yy - h / 2) / (h / 2))
    n = fbm(w, h, 48, 4, seed=203, tile=False)
    edge = 0.78 + 0.26 * (n - 0.5)
    alpha = np.clip((edge - r) / 0.05, 0, 1)
    # к краю светлее и пыльнее
    img = np.asarray(c.image(), dtype=np.float64)
    k = np.clip((r - 0.45) / 0.4, 0, 1)[..., None]
    img = img * (1 - 0.3 * k) + np.array(rgb8("#6a5a40"), float) * 0.3 * k
    return _with_alpha(Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)), alpha)


def paint_hay(w, h):
    c = Canvas(w, h, base="#a88a4a", seed=211)
    c.underpaint(["#a88a4a", "#8e7238", "#c2a462", "#6e5628"], cell=40, seed=211)
    c.strokes(2600, ["#d6b870", "#b89850", "#8a6c34", "#e8cc86", "#6a5228"], length=(14, 40), width=(1.4, 3.2),
              angle=0, angle_jitter=180, alpha=(0.4, 0.85), bristles=1, curve=0.15, taper=0.3)
    c.grain(0.04)
    return c.image()


def paint_stones(w, h):
    c = Canvas(w, h, base="#7a7466", seed=221)
    c.underpaint(["#7a7466", "#6a6458", "#8a8272", "#5a564c", "#8a7a5e"], cell=40, seed=221)
    c.strokes(700, ["#9a9282", "#5a564c", "#857c6a", "#6e6a5e"], length=(8, 24), width=(4, 10), angle=-30,
              angle_jitter=60, alpha=(0.2, 0.5), bristles=3, curve=0.3)
    c.strokes(90, ["#8a8a52", "#a0985a"], length=(4, 9), width=(3, 6), angle=0, angle_jitter=180,
              alpha=(0.3, 0.6), bristles=0)  # лишайник
    c.grain(0.04)
    return c.image()


def paint_iron(w, h):
    """Казан: чёрный чугун с копотью, медная полоса у края (верх области), блики мазком."""
    c = Canvas(w, h, base="#2e2a28", seed=231, tile=False)
    c.underpaint(["#2e2a28", "#3a3430", "#24201e", "#463c34"], cell=40, seed=231)
    c.strokes(500, ["#4a423c", "#1c1816", "#5a4a3e"], length=(10, 30), width=(4, 10), angle=0, angle_jitter=180,
              alpha=(0.2, 0.5), bristles=3)
    cb = Canvas(w, h, base=MATERIAL["copper"], seed=232, tile=False)
    cb.underpaint(["#a3552c", "#8a4422", "#c06a38", "#7a3a1c"], cell=24, seed=232)
    cb.strokes(200, ["#e09060", "#6a3018"], length=(10, 30), width=(2, 5), angle=0, angle_jitter=10,
               alpha=(0.3, 0.6), bristles=2)
    _paste_masked(c, cb, B.rows(c, 0, 40, feather=1.5))
    B.hline(c, 41, 2.5, "#1a1412", seed=1)
    c.strokes(40, ["#a8a098", "#c8bca8"], length=(14, 40), width=(2, 4), angle=0, angle_jitter=6,
              alpha=(0.25, 0.5), bristles=1, region=(0, 50, w, 120))
    f = B.vgrad(c, [(0, 1.1), (60, 1.0), (h, 0.55)])
    B.tint_ramp(c, f, "#1a1418", "#ffffff", 1.0)
    return c.image()


def paint_planks(w, h):
    c = Canvas(w, h, base="#86684a", seed=241)
    B.wood(c, ["#86684a", "#76593e", "#94785a", "#6a5038"], ["#4e3a28", "#a88a66", "#5a4430"], vertical=False,
           seed=241, knots=4)
    for y in np.arange(0, h, h / 4):
        c.line([(0, y), (w, y)], 3.2, "#2e2018", 0.9, wobble=0.6, seed=int(y))
        c.line([(0, y + 3), (w, y + 3)], 1.4, "#b89a76", 0.6, wobble=0.6, seed=int(y) + 1)
        for x in (w * 0.2, w * 0.7):
            c.ellipse(x, y + h / 8, 2.6, 2.6, "#2a201a", 0.9)
    return c.image()


def paint_lattice(w, h):
    """Сложенная решётка-кереге: косые красноватые планки на тёмном, ремешки в узлах."""
    c = Canvas(w, h, base="#2a1e18", seed=251)
    c.underpaint(["#2a1e18", "#3a2a20", "#221812"], cell=40, seed=251)
    n = 4
    step = w / n
    for d in (-1, 1):
        for i in range(-n, 2 * n):
            x0 = i * step
            pts = [(x0, -8), (x0 + d * (h + 16), h + 8)]
            c.line([(p[0] + 2, p[1] + 2) for p in pts], 13, "#140c08", 0.7, wobble=0.6, seed=i * 3 + d)
            c.line(pts, 11, "#a0603c" if d > 0 else "#94583a", 1.0, wobble=0.6, seed=i * 5 + d)
            c.line([(p[0] - 2, p[1]) for p in pts], 2.5, "#d09060", 0.6, wobble=0.6, seed=i * 7 + d)
    for i in range(n):
        for j in range(n):
            x, y = (i + 0.5) * step, (j + 0.5) * step
            c.ellipse(x, y, 5, 5, "#3a2418", 1.0)
            c.ellipse(x - 1, y - 1, 2.4, 2.4, "#8a6a4a", 1.0)
    return c.image()


def paint_saddlecloth(w, h):
    """Чепрак: киноварный войлок, кремовая кайма с завитками, тёмная бахрома-шнур."""
    c = Canvas(w, h, base=CINNABAR, seed=261, tile=False)
    B.felt(c, [CINNABAR, "#a33429", "#bb4436"], ["#c4503f", "#8a2a22"], seed=261, density=0.7)
    m = 26
    yy, xx = np.mgrid[0:h * c.ss, 0:w * c.ss] / c.ss
    d = np.minimum.reduce([xx, yy, w - xx, h - yy])
    band = np.clip((d - 6) / 1.0, 0, 1) * np.clip((m - d) / 1.0, 0, 1)
    cb = Canvas(w, h, base=FELT[0], seed=262, tile=False)
    B.felt(cb, FELT, FELT_FIBRE, seed=262, density=0.6)
    _paste_masked(c, cb, band)
    B.horn(c, w / 2, h / 2 + 10, 110, "#f0e2c8", 7, seed=3)
    B.horn(c, w / 2, h / 2 + 10, 110, BROWN_DARK, 2.0, seed=4)
    for k in range(10):
        x = (k + 0.5) * w / 10
        B.diamond(c, x, 16, 5, 7, CIN_DARK)
        B.diamond(c, x, h - 16, 5, 7, CIN_DARK)
    return c.image()


def paint_leather(w, h):
    c = Canvas(w, h, base=MATERIAL["leather"], seed=271)
    B.leather(c, ["#6e4428", "#5e3820", "#7e5232", "#4e2e1a"], seed=271)
    return c.image()


def paint_logend(w, h):
    c = Canvas(w, h, base="#b08a5e", seed=281, tile=False)
    c.underpaint(["#b08a5e", "#a07a50", "#c09a6a"], cell=20, seed=281)
    for r in np.arange(4, w / 2 - 8, 5.5):
        pts = [(w / 2 + r * math.cos(a), h / 2 + r * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 40)]
        c.line(pts, 1.4, "#7a5a3a", 0.55, wobble=0.6, seed=int(r))
    rs = np.random.default_rng(282)
    for _ in range(5):
        a = rs.uniform(0, 2 * math.pi)
        c.line([(w / 2, h / 2), (w / 2 + math.cos(a) * w * 0.4, h / 2 + math.sin(a) * w * 0.4)], 2.0, "#3a2818",
               0.8, wobble=0.8)
    pts = [(w / 2 + (w / 2 - 5) * math.cos(a), h / 2 + (h / 2 - 5) * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 50)]
    c.line(pts, 9, "#4a3a2a", 1.0, wobble=0.8)
    return c.image()


def paint_trough_in(w, h):
    """Вода/тёмное нутро колоды: тёмно-синяя вода с бликом неба."""
    c = Canvas(w, h, base="#2a3a48", seed=291, tile=False)
    c.underpaint(["#2a3a48", "#34485a", "#223040", "#5a6a7a"], cell=30, seed=291)
    c.strokes(30, ["#8aa0b0", "#c0a080"], length=(20, 50), width=(2, 4), angle=0, angle_jitter=5,
              alpha=(0.3, 0.6), bristles=1)
    return c.image()


def paint_wattle(w, h):
    """Плетень: горизонтальные прутья переплетаются вокруг кольев (повтор по x)."""
    c = Canvas(w, h, base="#2e2418", seed=301)
    c.underpaint(["#2e2418", "#3a2e20", "#241c14"], cell=32, seed=301)
    stakes = 8
    sx = w / stakes
    rows_n = 13
    ry = h / rows_n
    rs = np.random.default_rng(302)
    for j in range(rows_n):
        y = (j + 0.5) * ry
        for i in range(stakes):
            x0 = i * sx
            up = (i + j) % 2
            pts = [(x0 - 2, y + (ry * 0.18 if up else -ry * 0.18)), (x0 + sx * 0.5, y + (-ry * 0.12 if up else ry * 0.12)),
                   (x0 + sx + 2, y + (ry * 0.18 if up else -ry * 0.18))]
            col = ["#8a7250", "#7a6444", "#9a8058", "#6e583c"][rs.integers(4)]
            c.line([(p[0] + 1, p[1] + 3) for p in pts], ry * 0.75, "#1e160e", 0.6, wobble=0.6, seed=i * 31 + j)
            c.line(pts, ry * 0.7, col, 1.0, wobble=0.8, seed=i * 37 + j)
            c.line([(p[0], p[1] - ry * 0.18) for p in pts], ry * 0.18, "#b8a07a", 0.55, wobble=0.6, seed=i * 41 + j)
    for i in range(stakes):  # колья
        x = i * sx
        c.line([(x + 3, 0), (x + 3, h)], 11, "#1a140e", 0.6, wobble=0.6, seed=i)
        c.line([(x, 0), (x, h)], 9, "#5e4a34", 1.0, wobble=0.8, seed=i + 50)
        c.line([(x - 2, 0), (x - 2, h)], 2.5, "#8a7454", 0.6, wobble=0.8, seed=i + 60)
    f = B.vgrad(c, [(0, 1.1), (h * 0.5, 1.0), (h, 0.7)])
    B.tint_ramp(c, f, "#2a2430", "#ffffff", 1.0)
    return c.image()


PAINTERS = {
    "wall_boz": paint_wall_boz, "wall_ordo": paint_wall_ordo, "dome": paint_dome,
    "eave_boz": lambda w, h: paint_eave(w, h, False), "eave_ordo": lambda w, h: paint_eave(w, h, True),
    "wattle": paint_wattle, "koshma": paint_koshma, "rope": paint_rope, "pole": paint_pole,
    "door": paint_door, "frame": paint_frame, "walnut": paint_walnut, "wood": paint_wood,
    "shield": paint_shield, "tassel": paint_tassel, "pennant": paint_pennant, "awning": paint_awning,
    "brass": paint_brass, "tunduk_hole": paint_tunduk_hole, "embers": paint_embers, "earth": paint_earth,
    "hay": paint_hay, "stones": paint_stones, "iron": paint_iron, "planks": paint_planks,
    "lattice": paint_lattice, "saddlecloth": paint_saddlecloth, "felt_grey": paint_felt_grey,
    "leather": paint_leather, "logend": paint_logend, "koshma_end": paint_koshma_end,
    "felt_white": paint_felt_white, "hair": paint_hair, "bark": paint_bark, "trough_in": paint_trough_in,
}


# ---------------------------------------------------------------- сборка

def _with_alpha(img: Image.Image, alpha) -> Image.Image:
    a = np.asarray(alpha, dtype=np.float64)
    out = np.dstack([np.asarray(img.convert("RGB")), (np.clip(a, 0, 1) * 255).astype(np.uint8)])
    return Image.fromarray(out, "RGBA")


def _bleed(rgba: np.ndarray) -> np.ndarray:
    """Цвет под прозрачными пикселями — от ближайших непрозрачных (без тёмной каймы на мипах)."""
    rgb = rgba[..., :3].astype(np.float64)
    a = rgba[..., 3] > 8
    if a.all() or not a.any():
        return rgba
    acc, wsum = rgb * a[..., None], a.astype(np.float64)
    known = a.copy()
    for _ in range(24):
        if known.all():
            break
        s_acc = np.zeros_like(acc)
        s_w = np.zeros_like(wsum)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            s_acc += np.roll(np.roll(acc, dy, 0), dx, 1)
            s_w += np.roll(np.roll(wsum, dy, 0), dx, 1)
        new = (~known) & (s_w > 0)
        acc[new] = s_acc[new] / s_w[new][:, None]
        wsum[new] = 1.0
        known |= new
    out = rgba.copy()
    out[..., :3] = np.clip(acc, 0, 255).astype(np.uint8)
    return out


def build(out_path, only=None, verbose=True):
    """Рисует все области и собирает атлас. only — список имён (для быстрой отладки)."""
    atlas = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    atlas[..., :3] = rgb8("#6a5a48")
    atlas[..., 3] = 255
    for name, (x, y, w, h, rep) in LAYOUT.items():
        if only and name not in only:
            continue
        img = PAINTERS[name](w, h)
        arr = np.asarray(img.convert("RGBA"))
        if arr.shape[:2] != (h, w):
            arr = np.asarray(Image.fromarray(arr).resize((w, h), Image.LANCZOS))
        arr = _bleed(arr)
        # поля: повтор узора или растянутый край
        mode_x = "wrap" if rep in ("x", "xy") else "edge"
        mode_y = "wrap" if rep in ("y", "xy") else "edge"
        padded = np.pad(arr, ((0, 0), (PAD, PAD), (0, 0)), mode=mode_x)
        padded = np.pad(padded, ((PAD, PAD), (0, 0), (0, 0)), mode=mode_y)
        ys, xs = y - PAD, x - PAD
        y0c, x0c = max(ys, 0), max(xs, 0)
        y1c, x1c = min(ys + h + 2 * PAD, SIZE), min(xs + w + 2 * PAD, SIZE)
        atlas[y0c:y1c, x0c:x1c] = padded[y0c - ys:y1c - ys, x0c - xs:x1c - xs]
        if verbose:
            print(f"  атлас: {name:12s} {w}×{h}")
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    Image.fromarray(atlas, "RGBA").save(out_path, optimize=True)
    return out_path
