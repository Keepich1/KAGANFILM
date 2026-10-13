"""Кисти Коканда: обожжённый кирпич, пахса, глиняная штукатурка, изразец, резной орех.

Та же «рука», что у лагеря кыпчаков (paint.Canvas: подмалёвок, мазки, линии от руки),
свет и тень частично нарисованы прямо в цвете (ТЗ 11.1): верхняя кромка кирпича
светлее, под ним тень в шве, у изразца — блик глазури мазком.

Координаты — пиксели холста (0,0 — левый верхний угол). Общие помощники
(multiply, tint_ramp, rows, vgrad, wood, hline, diamond, emboss) повторяют
кисти лагеря (gen_camp_brush.py), чтобы генератор Коканда не зависел от чужих файлов.
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image

from paint import Canvas, fbm, spiral_points
from palette import rgb8


# ---------------------------------------------------------------- общее

def multiply(c: Canvas, factor):
    """Умножает холст на множитель: число, массив (H,W) или (H,W,3) в разрешении холста или итоговом."""
    base = np.asarray(c.img, dtype=np.float64)
    f = np.asarray(factor, dtype=np.float64)
    H, W = base.shape[:2]
    if f.ndim >= 2 and f.shape[:2] != (H, W):
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


def rows(c: Canvas, y0, y1, feather=6.0):
    """Маска полосы по высоте (0..1) в разрешении холста; y в пикселях итоговой текстуры."""
    H = c.h * c.ss
    y = (np.arange(H) + 0.5) / c.ss
    m = np.clip((y - y0) / feather + 0.5, 0, 1) * np.clip((y1 - y) / feather + 0.5, 0, 1)
    return np.repeat(m[:, None], c.w * c.ss, axis=1)


def cols(c: Canvas, x0, x1, feather=6.0):
    W = c.w * c.ss
    x = (np.arange(W) + 0.5) / c.ss
    m = np.clip((x - x0) / feather + 0.5, 0, 1) * np.clip((x1 - x) / feather + 0.5, 0, 1)
    return np.repeat(m[None, :], c.h * c.ss, axis=0)


def vgrad(c: Canvas, stops):
    """Профиль по высоте из опорных точек [(y_пикс, значение), ...] → массив (H,W)."""
    H = c.h * c.ss
    y = (np.arange(H) + 0.5) / c.ss
    ys, vs = zip(*stops)
    v = np.interp(y, ys, vs)
    return np.repeat(v[:, None], c.w * c.ss, axis=1)


def hgrad(c: Canvas, stops):
    W = c.w * c.ss
    x = (np.arange(W) + 0.5) / c.ss
    xs, vs = zip(*stops)
    v = np.interp(x, xs, vs)
    return np.repeat(v[None, :], c.h * c.ss, axis=0)


def noise(c: Canvas, cell, seed, octaves=3):
    return fbm(c.w * c.ss, c.h * c.ss, cell * c.ss, octaves, seed=seed, tile=c.tile)


def paste_masked(c: Canvas, other: Canvas, mask):
    a = np.asarray(c.img, dtype=np.float64)
    b = np.asarray(other.img, dtype=np.float64)
    m = np.asarray(mask, dtype=np.float64)[..., None]
    c._blend(a * (1 - m) + b * m)


def shift(hex_color, k):
    r, g, b = rgb8(hex_color)
    return "#%02x%02x%02x" % tuple(int(np.clip(v * k, 0, 255)) for v in (r, g, b))


def mix(a, b, t):
    ra, rb = np.array(rgb8(a), float), np.array(rgb8(b), float)
    v = ra * (1 - t) + rb * t
    return "#%02x%02x%02x" % tuple(int(np.clip(x, 0, 255)) for x in v)


def hline(c: Canvas, y, width, color, seed=0, alpha=1.0, x0=None, x1=None, wobble=0.5):
    n = 9
    xs = np.linspace(c.w * -0.02 if x0 is None else x0, c.w * 1.02 if x1 is None else x1, n)
    c.line(np.column_stack([xs, np.full(n, y)]), width, color, alpha, wobble=wobble, width_jitter=0.2, seed=seed)


def vline(c: Canvas, x, width, color, seed=0, alpha=1.0, y0=None, y1=None, wobble=0.5):
    n = 9
    ys = np.linspace(c.h * -0.02 if y0 is None else y0, c.h * 1.02 if y1 is None else y1, n)
    c.line(np.column_stack([np.full(n, x), ys]), width, color, alpha, wobble=wobble, width_jitter=0.2, seed=seed)


def diamond(c: Canvas, cx, cy, rx, ry, color, outline=None, width=2.0, alpha=1.0):
    pts = [(cx, cy - ry), (cx + rx, cy), (cx, cy + ry), (cx - rx, cy)]
    c.polygon(pts, color, alpha, wobble=0.3)
    if outline:
        c.line(pts + [pts[0]], width, outline, alpha, wobble=0.25)


def emboss(draw_fn, light, dark, body, off=1.6):
    """«Резьба»: тень паза снизу-справа, светлая кромка сверху-слева, тело мотива.
    draw_fn(color, dx, dy) рисует мотив со сдвигом."""
    draw_fn(dark, off, off)
    draw_fn(light, -off * 0.6, -off * 0.6)
    draw_fn(body, 0.0, 0.0)


def star_points(cx, cy, r_out, r_in, n=8, rot=0.0):
    """Звезда из n лучей (восьмиконечная — гирих Коканда)."""
    pts = []
    for k in range(2 * n):
        a = rot + math.pi * k / n - math.pi / 2
        r = r_out if k % 2 == 0 else r_in
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def s_path(period, amp, turns=1.3):
    """S-завиток (ислими): верхняя спираль слева, перемычка, нижняя — симметрично."""
    r = min(period * 0.2, amp * 0.55)
    ca = np.array([-period * 0.25, -(amp - r)])
    n = 40
    t = np.linspace(0, 1, n)
    phi = -turns * 2 * math.pi * (1 - t)
    rad = r * (0.12 + 0.88 * t)
    half = np.column_stack([ca[0] + rad * np.cos(phi), ca[1] + rad * np.sin(phi)])
    e = half[-1]
    m = np.array([0.0, 0.0])
    s = np.linspace(0, 1, 10)[1:, None]
    h00, h10, h01, h11 = 2 * s**3 - 3 * s**2 + 1, s**3 - 2 * s**2 + s, -2 * s**3 + 3 * s**2, s**3 - s**2
    k = np.linalg.norm(m - e) * 1.2
    bridge = h00 * e + h10 * np.array([0, k]) + h01 * m + h11 * np.array([k * 0.7, k * 0.4])
    first = np.vstack([half, bridge])
    second = -first[::-1][1:]
    return np.vstack([first, second])


def leaf(c: Canvas, cx, cy, length, width, angle, color, alpha=1.0):
    """Листок-«бодом» (миндалина) для ислими."""
    a = math.radians(angle)
    d = np.array([math.cos(a), math.sin(a)])
    n = np.array([-d[1], d[0]])
    t = np.linspace(-0.5, 0.5, 9)
    w = width * np.sin(np.pi * (t + 0.5)) ** 0.8 * 0.5
    left = [(cx + d[0] * tt * length + n[0] * ww, cy + d[1] * tt * length + n[1] * ww) for tt, ww in zip(t, w)]
    right = [(cx + d[0] * tt * length - n[0] * ww, cy + d[1] * tt * length - n[1] * ww) for tt, ww in zip(t, w)]
    c.polygon(left + right[::-1], color, alpha, wobble=0.2)


# ---------------------------------------------------------------- материалы

def wood(c: Canvas, tones, grain_cols, vertical=True, density=1.0, seed=0, knots=3):
    """Дерево: волокна вдоль (вертикально или горизонтально), сучки."""
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


def mottle(c: Canvas, cell, strength=0.07, levels=3, seed=0, soft=1.5):
    """Пятна «плоскостями»: шум, разбитый на 2–3 тона с мягким краем — как подмалёвок кистью."""
    n = fbm(c.w * c.ss, c.h * c.ss, cell * c.ss, 3, seed=seed, tile=c.tile)
    q = np.round(n * (levels - 1)) / (levels - 1)
    from PIL import ImageFilter
    qi = Image.fromarray((q * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(soft * c.ss))
    q = np.asarray(qi, dtype=np.float64) / 255
    return multiply(c, 1.0 + strength * (q - 0.5) * 2)


def clay(c: Canvas, tones, flecks, seed=0, trowel=True, density=1.0):
    """Глина: спокойная подмалёвка, широкие мазки мастерка дугами, соломинки, мелкие камешки."""
    area = c.w * c.h
    c.underpaint(tones, cell=max(32, min(c.w, c.h) // 3), octaves=3, seed=seed)
    mottle(c, max(24, min(c.w, c.h) // 4), 0.07, 3, seed=seed + 1)
    if trowel:
        light = [shift(t, 1.07) for t in tones[:2]]
        dark = [shift(t, 0.92) for t in tones[:2]]
        rs = np.random.default_rng(seed + 3)
        c.strokes(int(area / 1600 * density), light + dark, length=(40, 110), width=(14, 30),
                  angle=lambda x, y: 20 * math.sin(x / 60 + y / 90) + rs.normal(0, 10), angle_jitter=25,
                  alpha=(0.16, 0.32), bristles=6, curve=0.45, value_jitter=0.02, taper=0.5)
    c.strokes(int(area / 700 * density), list(tones), length=(16, 40), width=(5, 10), angle=0, angle_jitter=90,
              alpha=(0.12, 0.25), bristles=3, curve=0.35, value_jitter=0.03)
    # соломинки в глине
    c.strokes(int(area / 900 * density), list(flecks), length=(5, 12), width=(1.0, 1.8), angle=0,
              angle_jitter=180, alpha=(0.35, 0.7), bristles=0, curve=0.15, taper=0.2)
    c.grain(0.035, cell=1.3)
    return c


def cracks(c: Canvas, n, color, seed=0, length=(20, 60), width=1.4, alpha=0.55, region=None):
    """Тонкие трещины: ломаные, ветвятся, светлая кромка сверху."""
    rs = np.random.default_rng(seed)
    x0, y0, x1, y1 = region or (0, 0, c.w, c.h)
    for i in range(n):
        x, y = rs.uniform(x0, x1), rs.uniform(y0, y1)
        a = rs.uniform(0, 2 * math.pi)
        L = rs.uniform(*length)
        pts = [(x, y)]
        for k in range(5):
            a += rs.normal(0, 0.6)
            x += math.cos(a) * L / 5
            y += math.sin(a) * L / 5
            pts.append((x, y))
        c.line(pts, width, color, alpha, wobble=0.3, seed=seed * 31 + i)
        c.line([(p[0] - 0.8, p[1] - 0.9) for p in pts], width * 0.6, "#e8d8b8", alpha * 0.35, wobble=0.3,
               seed=seed * 37 + i)
        if rs.random() < 0.5:
            j = rs.integers(1, 4)
            b = a + rs.choice([-1, 1]) * rs.uniform(0.6, 1.2)
            bx, by = pts[j]
            c.line([(bx, by), (bx + math.cos(b) * L * 0.3, by + math.sin(b) * L * 0.3)], width * 0.7, color,
                   alpha * 0.8, wobble=0.3, seed=seed * 41 + i)


def glaze(c: Canvas, mask, seed=0, strength=0.22, angle=-60):
    """Блик глазури: светлые короткие мазки по маске (изразец блестит, но не пластик)."""
    rs = np.random.default_rng(seed)
    m = np.asarray(mask, float)
    H, W = m.shape
    n = int(c.w * c.h / 1400)
    del angle
    for _ in range(n):
        x, y = rs.uniform(0, c.w), rs.uniform(0, c.h)
        if m[min(int(y * c.ss), H - 1), min(int(x * c.ss), W - 1)] < 0.5:
            continue
        # мягкое пятно блеска: широкий светлый овал и маленький блик внутри
        rx, ry = rs.uniform(5, 12), rs.uniform(3, 7)
        c.ellipse(x, y, rx, ry, "#dffff2", rs.uniform(0.03, strength * 0.3))
        if rs.random() < 0.3:
            c.ellipse(x - rx * 0.3, y - ry * 0.3, rx * 0.25, ry * 0.25, "#f6fffa", rs.uniform(0.1, strength))


def bricks(c: Canvas, courses, per_course, tones, mortar, seed=0, chip=0.18, relief=1.0, light="#f0c08a",
           shadow="#3a2014", offset_frac=0.5):
    """Обожжённый кирпич перевязкой «в полкирпича»: каждый кирпич — отдельный мазок с
    отбитыми углами, светлой верхней кромкой и тенью в шве под ним (свет нарисован)."""
    rs = np.random.default_rng(seed)
    ch = c.h / courses
    bw = c.w / per_course
    jm = max(2.0, ch * 0.13)       # толщина шва
    for j in range(courses):
        y0 = j * ch
        off = (j % 2) * bw * offset_frac
        for i in range(-1, per_course + 1):
            x0 = i * bw + off
            # кирпич: многоугольник с отбитыми углами
            l, r = x0 + jm / 2, x0 + bw - jm / 2
            t, b = y0 + jm / 2, y0 + ch - jm / 2
            k = chip * min(bw, ch)
            pts = [(l + rs.uniform(0, k), t), (r - rs.uniform(0, k), t + rs.uniform(-0.6, 0.6)),
                   (r, t + rs.uniform(0, k)), (r + rs.uniform(-0.6, 0.6), b - rs.uniform(0, k)),
                   (r - rs.uniform(0, k), b), (l + rs.uniform(0, k), b + rs.uniform(-0.6, 0.6)),
                   (l, b - rs.uniform(0, k)), (l + rs.uniform(-0.6, 0.6), t + rs.uniform(0, k))]
            col = tones[rs.integers(len(tones))]
            col = shift(col, rs.uniform(0.9, 1.08))
            # тень в шве под кирпичом и справа (кирпич чуть выступает)
            c.polygon([(p[0] + 1.2 * relief, p[1] + 1.6 * relief) for p in pts], shadow, 0.45, wobble=0.3)
            c.polygon(pts, col, 1.0, wobble=0.4)
            # мазки по кирпичу вдоль постели
            c.strokes(3, [shift(col, 1.08), shift(col, 0.9)], length=(bw * 0.25, bw * 0.6), width=(ch * 0.15, ch * 0.3),
                      angle=0, angle_jitter=6, alpha=(0.25, 0.5), bristles=2, curve=0.1,
                      region=(l + 2, t + 2, r - 2, b - 2))
            # светлая верхняя кромка (солнце сверху), тёмная нижняя
            c.line([(l + k * 0.6, t + 1.0), (r - k * 0.6, t + 1.0)], max(1.0, ch * 0.08), light, 0.35 * relief,
                   wobble=0.3, seed=int(x0 * 7 + y0))
            c.line([(l + k * 0.6, b - 0.8), (r - k * 0.6, b - 0.8)], max(1.0, ch * 0.07), shift(col, 0.65),
                   0.5 * relief, wobble=0.3, seed=int(x0 * 11 + y0))
    return c


def stones(c: Canvas, n_rows, tones, mortar, seed=0, light="#e8dcc0", shadow="#24201c", size=(0.7, 1.4)):
    """Тёсаный камень цоколя: крупные скруглённые блоки рядами, швы, свет сверху."""
    rs = np.random.default_rng(seed)
    rh = c.h / n_rows
    for j in range(n_rows):
        y0 = j * rh
        x = rs.uniform(-rh, 0)
        while x < c.w + rh:
            w = rh * rs.uniform(*size)
            m = rh * 0.07
            l, r, t, b = x + m, x + w - m, y0 + m + rs.uniform(0, rh * 0.05), y0 + rh - m - rs.uniform(0, rh * 0.05)
            k = min(w, rh) * 0.28
            pts = []
            for cx, cy, a0 in ((r - k, t + k, -90), (r - k, b - k, 0), (l + k, b - k, 90), (l + k, t + k, 180)):
                for s in range(4):
                    a = math.radians(a0 + s * 30)
                    kk = k * rs.uniform(0.75, 1.15)
                    pts.append((cx + kk * math.cos(a), cy + kk * math.sin(a)))
            col = shift(tones[rs.integers(len(tones))], rs.uniform(0.88, 1.1))
            c.polygon([(p[0] + 2, p[1] + 3) for p in pts], shadow, 0.5, wobble=0.6)
            c.polygon(pts, col, 1.0, wobble=0.8)
            c.strokes(int(w * rh / 160) + 3, [shift(col, 1.1), shift(col, 0.86), shift(col, 0.95)],
                      length=(w * 0.15, w * 0.45), width=(rh * 0.08, rh * 0.2), angle=-25, angle_jitter=40,
                      alpha=(0.2, 0.45), bristles=3, curve=0.3, region=(l + 3, t + 3, r - 3, b - 3))
            # свет сверху-слева: светлая дуга по верхней кромке
            top = [p for p in pts if p[1] < (t + b) / 2]
            if len(top) > 2:
                top = sorted(top, key=lambda p: p[0])
                c.line([(p[0], p[1] + 1.5) for p in top], max(1.2, rh * 0.03), light, 0.1, wobble=0.4,
                       seed=int(x * 3 + y0))
            x += w
    return c
