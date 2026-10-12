"""Кисти лагеря кыпчаков: войлок, дерево, кожа, металл, орнамент «кочкор мүйүз».

Всё рисуется на paint.Canvas — одна «рука» с остальными текстурами проекта.
Свет и тень частично нарисованы прямо в цвете (ТЗ 11.1): низ темнее,
верхние кромки светлее, тень под верёвками и под свесом купола.

Координаты — пиксели холста (0,0 — левый верхний угол).
"""
from __future__ import annotations

import math

import numpy as np

from paint import Canvas, fbm, spiral_points
from palette import rgb8


# ---------------------------------------------------------------- общее

def multiply(c: Canvas, factor):
    """Умножает холст на множитель: число, массив (H,W) или (H,W,3) в разрешении холста или итоговом."""
    base = np.asarray(c.img, dtype=np.float64)
    f = np.asarray(factor, dtype=np.float64)
    H, W = base.shape[:2]
    if f.ndim >= 2 and f.shape[:2] != (H, W):
        from PIL import Image
        if f.ndim == 2:
            f = np.asarray(Image.fromarray(f.astype(np.float32), "F").resize((W, H), Image.BILINEAR))
        else:
            f = np.stack([np.asarray(Image.fromarray(f[..., k].astype(np.float32), "F").resize((W, H), Image.BILINEAR))
                          for k in range(f.shape[2])], -1)
    if f.ndim == 2:
        f = f[..., None]
    c._blend(base * f)
    return c


def tint_ramp(c: Canvas, t, dark: str, light: str, strength=1.0):
    """Нарисованный свет: t (H,W) 0..1 → множитель от цвета dark к цвету light."""
    a = np.array(rgb8(dark), float) / 255
    b = np.array(rgb8(light), float) / 255
    t = np.clip(np.asarray(t, float), 0, 1)[..., None]
    f = a * (1 - t) + b * t
    f = 1 - strength + strength * f
    return multiply(c, f)


def rows(c: Canvas, y0, y1, feather=6.0, final=True):
    """Маска полосы по высоте (0..1) в разрешении холста; y в пикселях итоговой текстуры."""
    H = c.h * c.ss
    y = (np.arange(H) + 0.5) / c.ss
    m = np.clip((y - y0) / feather + 0.5, 0, 1) * np.clip((y1 - y) / feather + 0.5, 0, 1)
    return np.repeat(m[:, None], c.w * c.ss, axis=1)


def vgrad(c: Canvas, stops):
    """Профиль по высоте из опорных точек [(y_пикс, значение), ...] → массив (H,W)."""
    H = c.h * c.ss
    y = (np.arange(H) + 0.5) / c.ss
    ys, vs = zip(*stops)
    v = np.interp(y, ys, vs)
    return np.repeat(v[:, None], c.w * c.ss, axis=1)


def noise(c: Canvas, cell, seed, octaves=3):
    return fbm(c.w * c.ss, c.h * c.ss, cell * c.ss, octaves, seed=seed, tile=c.tile)


# ---------------------------------------------------------------- материалы

def mottle(c: Canvas, cell, strength=0.07, levels=3, seed=0, soft=1.5):
    """Пятна шерсти «плоскостями»: шум, разбитый на 2–3 тона с мягким краем —
    как подмалёвок кистью, а не фотошум."""
    n = fbm(c.w * c.ss, c.h * c.ss, cell * c.ss, 3, seed=seed, tile=c.tile)
    q = np.round(n * (levels - 1)) / (levels - 1)
    from PIL import Image, ImageFilter
    qi = Image.fromarray((q * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(soft * c.ss))
    q = np.asarray(qi, dtype=np.float64) / 255
    return multiply(c, 1.0 + strength * (q - 0.5) * 2)


def felt(c: Canvas, tones, fibres, density=1.0, cell=None, seed=0, patches=True, direction=0.0, dir_jitter=30.0):
    """Войлок: спокойная подмалёвка, пятна шерсти плоскостями, крупные мазки кисти по форме
    (direction, градусы), короткие спутанные волокна поверх."""
    area = c.w * c.h
    c.underpaint(tones, cell=cell or max(24, min(c.w, c.h) // 2), octaves=2, seed=seed)
    mottle(c, max(20, min(c.w, c.h) // 5), 0.06, 3, seed=seed + 1)
    if patches:
        light = [_shift(t, 1.06) for t in tones[:2]]
        dark = [_shift(t, 0.91) for t in tones[:2]]
        c.strokes(int(area / 2000 * density), light + dark, length=(36, 96), width=(12, 26), angle=direction,
                  angle_jitter=dir_jitter, alpha=(0.22, 0.42), bristles=7, curve=0.18, value_jitter=0.02, taper=0.45)
        c.strokes(int(area / 1300 * density), list(tones) + list(fibres[:2]), length=(18, 44), width=(5, 11),
                  angle=direction, angle_jitter=dir_jitter * 1.4, alpha=(0.14, 0.32), bristles=4, curve=0.3,
                  value_jitter=0.03)
    c.strokes(int(area / 110 * density), list(fibres), length=(3, 9), width=(0.9, 1.6), angle=0,
              angle_jitter=180, alpha=(0.1, 0.24), bristles=0, curve=0.9, taper=0.3, value_jitter=0.05)
    c.grain(0.03, cell=1.2)
    return c


def _shift(hex_color, k):
    r, g, b = rgb8(hex_color)
    return "#%02x%02x%02x" % tuple(int(np.clip(v * k, 0, 255)) for v in (r, g, b))


def wood(c: Canvas, tones, grain_cols, vertical=True, density=1.0, seed=0, knots=3):
    """Дерево: волокна вдоль (вертикально или горизонтально), сучки, тёмные щели."""
    area = c.w * c.h
    ang = 90 if vertical else 0
    c.underpaint(tones, cell=max(16, min(c.w, c.h) // 3), octaves=3, seed=seed)
    c.strokes(int(area / 120 * density), list(grain_cols), length=(30, 90), width=(1.5, 4.0), angle=ang,
              angle_jitter=4, alpha=(0.2, 0.55), bristles=2, curve=0.08, taper=0.4)
    c.strokes(int(area / 400 * density), list(tones), length=(40, 120), width=(6, 14), angle=ang,
              angle_jitter=3, alpha=(0.1, 0.25), bristles=4, curve=0.05)
    rs = np.random.default_rng(seed + 9)
    for _ in range(knots):
        x, y = rs.uniform(0, c.w), rs.uniform(0, c.h)
        rx, ry = (rs.uniform(3, 6), rs.uniform(8, 14)) if vertical else (rs.uniform(8, 14), rs.uniform(3, 6))
        c.ellipse(x, y, rx, ry, grain_cols[0], 0.6)
        c.ellipse(x, y, rx * 0.45, ry * 0.45, tones[0], 0.7)
    c.grain(0.03)
    return c


def leather(c: Canvas, tones, seed=0):
    area = c.w * c.h
    c.underpaint(tones, cell=max(16, min(c.w, c.h) // 3), octaves=3, seed=seed)
    c.strokes(int(area / 180), list(tones), length=(10, 30), width=(4, 10), angle=0, angle_jitter=180,
              alpha=(0.15, 0.35), bristles=3, curve=0.4)
    c.grain(0.04)
    return c


# ---------------------------------------------------------------- орнамент

def _xf(pts, cx, cy, size, rot=0.0, flip=False):
    p = np.asarray(pts, float) * size
    if flip:
        p[:, 1] = -p[:, 1]
    if rot:
        a = math.radians(rot)
        R = np.array([[math.cos(a), -math.sin(a)], [math.sin(a), math.cos(a)]])
        p = p @ R.T
    return p + np.array([cx, cy])


def horn_paths():
    """Мотив «кочкор мүйүз» в единичных координатах (центр 0,0, y вниз):
    ствол снизу вверх и два рога, расходящихся и закрученных вниз-наружу."""
    paths = [np.array([[0.0, 0.5], [0.0, -0.02]])]
    for d in (-1, 1):
        arc = np.array([[0.0, -0.02], [d * 0.12, -0.3], [d * 0.32, -0.42], [d * 0.5, -0.34]])
        sp = spiral_points(d * 0.47, -0.08, 0.26, turns=1.15, start=-math.pi / 2 - d * 0.35,
                           direction=d, n=36)
        paths.append(np.vstack([arc, sp[1:]]))
    return paths


def horn(c: Canvas, cx, cy, size, color, width, rot=0.0, flip=False, alpha=1.0, seed=0):
    for i, p in enumerate(horn_paths()):
        c.line(_xf(p, cx, cy, size, rot, flip), width, color, alpha, wobble=0.35, seed=seed * 3 + i)


def s_path(period, amp, turns=1.3):
    """S-завиток в единицах пикселей относительно центра звена: верхняя спираль слева
    (по часовой из центра наружу), плавная S-перемычка, нижняя — симметрично."""
    r = min(period * 0.2, amp * 0.55)
    ca = np.array([-period * 0.25, -(amp - r)])
    n = 40
    t = np.linspace(0, 1, n)
    phi = -turns * 2 * math.pi * (1 - t)          # заканчивается на φ=0 (справа), движение вниз
    rad = r * (0.12 + 0.88 * t)
    half = np.column_stack([ca[0] + rad * np.cos(phi), ca[1] + rad * np.sin(phi)])
    # перемычка: кривая Эрмита от правого края спирали к центру звена
    e = half[-1]
    m = np.array([0.0, 0.0])
    s = np.linspace(0, 1, 10)[1:, None]
    h00, h10, h01, h11 = 2 * s**3 - 3 * s**2 + 1, s**3 - 2 * s**2 + s, -2 * s**3 + 3 * s**2, s**3 - s**2
    k = np.linalg.norm(m - e) * 1.2
    bridge = h00 * e + h10 * np.array([0, k]) + h01 * m + h11 * np.array([k * 0.7, k * 0.4])
    first = np.vstack([half, bridge])
    second = -first[::-1][1:]
    return np.vstack([first, second])


def s_scroll(c: Canvas, x0, cy, period, amp, color, width, seed=0, turns=1.3):
    """Одно звено бегущего завитка (S с двумя спиралями) — основа пояса «коричневых завитков»."""
    p = s_path(period, amp, turns) + np.array([x0 + period * 0.5, cy])
    c.line(p, width, color, 1.0, wobble=0.3, seed=seed)


def curl_belt(c: Canvas, y0, y1, count, color, width, line_col, line_w, seed=0, lines=True, double=False):
    """Пояс коричневых завитков между тонкими линиями (ТЗ 11.3). count — звеньев по ширине (для бесшовности)."""
    period = c.w / count
    cy, amp = (y0 + y1) / 2, (y1 - y0) / 2 * 0.86
    for i in range(count):
        s_scroll(c, i * period, cy, period, amp, color, width, seed=seed + i)
        # маленький ромбик-заполнитель между звеньями
        x = i * period + period * 0.5
        diamond(c, x, cy, amp * 0.16, amp * 0.22, color, None)
    if lines:
        for y in ((y0 - line_w * 1.2, y1 + line_w * 1.2) if not double else
                  (y0 - line_w * 1.2, y0 - line_w * 3.6, y1 + line_w * 1.2, y1 + line_w * 3.6)):
            hline(c, y, line_w, line_col, seed=seed + int(y))


def hline(c: Canvas, y, width, color, seed=0, alpha=1.0):
    n = 9
    xs = np.linspace(0, c.w, n)
    c.line(np.column_stack([xs, np.full(n, y)]), width, color, alpha, wobble=0.5, width_jitter=0.2, seed=seed)


def diamond(c: Canvas, cx, cy, rx, ry, color, outline=None, width=2.0, alpha=1.0):
    pts = [(cx, cy - ry), (cx + rx, cy), (cx, cy + ry), (cx - rx, cy)]
    c.polygon(pts, color, alpha, wobble=0.3)
    if outline:
        c.line(pts + [pts[0]], width, outline, alpha, wobble=0.25)


def rhomb_belt(c: Canvas, y0, y1, count, fill, outline, dot, line_col, line_w, seed=0):
    """Цепь ромбов между тонкими линиями: заливка, обводка, светлая точка в центре."""
    period = c.w / count
    cy, ry = (y0 + y1) / 2, (y1 - y0) / 2 * 0.86
    rx = min(period * 0.36, ry * 0.8)
    for i in range(count):
        x = (i + 0.5) * period
        diamond(c, x, cy, rx, ry, fill, outline, width=max(1.5, line_w * 0.8))
        diamond(c, x, cy, rx * 0.32, ry * 0.32, dot)
        # треугольнички между ромбами — сверху и снизу
        xm = i * period
        c.polygon([(xm - rx * 0.35, y0), (xm + rx * 0.35, y0), (xm, y0 + ry * 0.5)], outline, 1.0, 0.2)
        c.polygon([(xm - rx * 0.35, y1), (xm + rx * 0.35, y1), (xm, y1 - ry * 0.5)], outline, 1.0, 0.2)
    for y in (y0 - line_w * 1.3, y1 + line_w * 1.3):
        hline(c, y, line_w, line_col, seed=seed + int(y))


def rope_line(c: Canvas, pts, width, rope_col, light_col, shadow_col, seed=0, shadow_off=(0.0, 0.0)):
    """Нарисованная верёвка: мягкая тень, тело, косые витки, светлый блик сверху."""
    pts = np.asarray(pts, float)
    sh = pts + np.array(shadow_off)
    c.line(sh, width * 1.9, shadow_col, 0.35, wobble=0.6, seed=seed)
    c.line(sh, width * 1.3, shadow_col, 0.45, wobble=0.6, seed=seed + 1)
    c.line(pts, width, rope_col, 1.0, wobble=0.4, seed=seed + 2)
    # витки: короткие косые штрихи вдоль верёвки
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    L = seg.sum()
    cum = np.r_[0, np.cumsum(seg)]
    step = max(width * 0.9, 2.0)
    for s in np.arange(step * 0.5, L, step):
        i = min(np.searchsorted(cum, s) - 1, len(seg) - 1)
        i = max(i, 0)
        t = (s - cum[i]) / max(seg[i], 1e-9)
        p = pts[i] * (1 - t) + pts[i + 1] * t
        d = (pts[i + 1] - pts[i]) / max(seg[i], 1e-9)
        n = np.array([-d[1], d[0]])
        a = p + n * width * 0.42 - d * width * 0.25
        b = p - n * width * 0.42 + d * width * 0.25
        c.line([a, b], max(1.0, width * 0.22), shadow_col, 0.55, wobble=0.1, seed=seed + int(s))
    c.line(pts - np.array([0, width * 0.18]), max(1.0, width * 0.28), light_col, 0.55, wobble=0.3, seed=seed + 3)


def emboss(c: Canvas, draw_fn, light, dark, body, off=1.6):
    """«Резьба»: тень паза снизу-справа, светлая кромка сверху-слева, тело мотива.
    draw_fn(color, dx, dy) рисует мотив со сдвигом."""
    draw_fn(dark, off, off)
    draw_fn(light, -off * 0.6, -off * 0.6)
    draw_fn(body, 0.0, 0.0)
