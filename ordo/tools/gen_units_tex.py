"""Рисованные атласы юнитов (ТЗ 11.1): kokand_units.png, kipchak_units.png, animals.png.

Одна «рука» с остальными текстурами (tools/paint.py): подмалёвок, мазки по форме
складок, нарисованный свет сверху и тень снизу, золотой кант, орнамент.
Атлас стороны — один материал на юнита (ТЗ 11.5), конь нарисован в каждом атласе.

Разметка: сетка 512 px. Области с вариантами (масть коня coat0..3, шапки hat0..3,
шерсть овец wool0..3) идут через 512 px (variant_du = 0.25): шейдер толпы сдвигает
UV на вариант по w экземпляра (маска COLOR.b).
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image

from gen_units_kit import Atlas
from paint import Canvas, fbm, ram_horn, rhomb, spiral_points
from palette import KIPCHAK, KOKAND, MATERIAL, rgb8

VARIANT_DU = 0.25

_COMMON = {
    "coat0": (0, 0, 512, 512), "coat1": (512, 0, 512, 512), "coat2": (1024, 0, 512, 512), "coat3": (1536, 0, 512, 512),
    "hat0": (0, 512, 512, 256), "hat1": (512, 512, 512, 256), "hat2": (1024, 512, 512, 256), "hat3": (1536, 512, 512, 256),
    "skin": (0, 768, 512, 256), "leather": (512, 768, 512, 256), "metal": (1024, 768, 512, 256), "wood": (1536, 768, 512, 256),
    "torso": (0, 1024, 512, 512), "skirt": (512, 1024, 512, 512), "sleeve": (1024, 1024, 512, 256),
    "trousers": (1024, 1280, 512, 256), "torso2": (1536, 1024, 512, 512),
    "banner": (0, 1536, 512, 512), "caparison": (512, 1536, 512, 512),
}
KOKAND_ATLAS = Atlas("kokand_units", 2048, 2048, dict(_COMMON, **{
    "skirt2": (1024, 1536, 256, 256), "sleeve2": (1280, 1536, 256, 256),
    "shirt": (1024, 1792, 256, 256), "saddlecloth": (1280, 1792, 256, 256),
    "sash": (1536, 1536, 256, 128), "flask": (1536, 1664, 256, 128),
    "saddle": (1792, 1536, 256, 256), "plume": (1536, 1792, 256, 256), "finial": (1792, 1792, 256, 256),
}))
KIPCHAK_ATLAS = Atlas("kipchak_units", 2048, 2048, dict(_COMMON, **{
    "work_torso": (1024, 1536, 256, 256), "work_skirt": (1280, 1536, 256, 256),
    "fur": (1024, 1792, 256, 256), "cloak": (1280, 1792, 256, 256),
    "shield": (1536, 1536, 256, 256), "sash": (1792, 1536, 256, 128), "saddle": (1792, 1664, 256, 128),
    "pennon": (1536, 1792, 256, 256), "plume": (1792, 1792, 256, 128), "tug": (1792, 1920, 256, 128),
}))
ANIMALS_ATLAS = Atlas("animals", 2048, 1024, {
    "coat0": (0, 0, 512, 512), "coat1": (512, 0, 512, 512), "coat2": (1024, 0, 512, 512), "coat3": (1536, 0, 512, 512),
    "wool0": (0, 512, 512, 512), "wool1": (512, 512, 512, 512), "wool2": (1024, 512, 512, 512), "wool3": (1536, 512, 512, 512),
})

# Доли внутри ячейки коня (512×512): тело, шея, голова, ноги, грива/хвост, копыта
HORSE_SUB = {"body": (0, 0, 1, 0.46), "neck": (0, 0.46, 0.5, 0.64), "head": (0.5, 0.46, 1, 0.64),
             "legs": (0, 0.64, 1, 0.82), "hair": (0, 0.82, 0.5, 1), "hoof": (0.5, 0.82, 0.75, 1),
             "eye": (0.75, 0.82, 1, 1)}
# Доли внутри ячейки овцы: тело, голова, ноги, хвост
SHEEP_SUB = {"body": (0, 0, 1, 0.5), "head": (0, 0.5, 0.5, 0.75), "legs": (0.5, 0.5, 1, 0.75),
             "tail": (0, 0.75, 0.5, 1), "face": (0.5, 0.75, 1, 1)}
# Доли внутри полосы металла и дерева
METAL_SUB = {"gold": (0, 0, 0.25, 1), "steel": (0.25, 0, 0.5, 1), "iron": (0.5, 0, 0.75, 1), "brass": (0.75, 0, 1, 1)}
WOOD_SUB = {"walnut": (0, 0, 0.5, 1), "shaft": (0.5, 0, 1, 1)}
SKIN_SUB = {"head": (0, 0, 0.5, 1), "hand": (0.5, 0, 0.75, 1), "hair": (0.75, 0, 1, 1)}
LEATHER_SUB = {"boot": (0, 0, 0.5, 1), "belt": (0.5, 0, 0.75, 1), "felt": (0.75, 0, 1, 1)}


# ---------------------------------------------------------------- инструменты

def _mix(a, b, t):
    a, b = np.array(rgb8(a), float), np.array(rgb8(b), float)
    c = a * (1 - t) + b * t
    return "#%02x%02x%02x" % tuple(int(np.clip(v, 0, 255)) for v in c)


def _shade(c, k):
    a = np.array(rgb8(c), float) * k
    return "#%02x%02x%02x" % tuple(int(np.clip(v, 0, 255)) for v in a)


def region(img: Image.Image, atlas: Atlas, name, painter, seed=0, ss=2, tile=True, base="#808080"):
    x, y, w, h = atlas.regions[name]
    c = Canvas(w, h, base=base, ss=ss, tile=tile, seed=seed)
    painter(c, w, h)
    img.paste(c.image(), (x, y))


def vgrad(c: Canvas, top_k=1.12, bottom_k=0.78):
    """Нарисованный свет: верх светлее, низ темнее (множитель по высоте)."""
    arr = np.asarray(c.img, dtype=np.float64)
    t = np.linspace(0, 1, arr.shape[0])[:, None, None]
    c._blend(arr * (top_k + (bottom_k - top_k) * t))


def folds(c: Canvas, w, h, dark, light, n=40, vertical=True, length=(0.35, 0.9), width=(6, 16), alpha=(0.18, 0.4),
          flare=0.0, region=None):
    """Складки ткани: длинные мазки тени и света вдоль ткани."""
    x0, y0, x1, y1 = region or (0, 0, w, h)
    rs = c.rs
    for i in range(n):
        x = rs.uniform(x0, x1)
        L = rs.uniform(*length) * (y1 - y0)
        yc = rs.uniform(y0 + L * 0.3, y1 - L * 0.2)
        wd = rs.uniform(*width) * (1 + flare * (yc - y0) / max(y1 - y0, 1))
        col = dark if i % 2 == 0 else light
        ang = 90 + rs.normal(0, 4) if vertical else rs.normal(0, 5)
        c._stroke(x, yc, math.radians(ang), L, wd, np.array(rgb8(col), float), rs.uniform(*alpha),
                  rs.normal(0, 0.15), 3, 0.35)


def trim(c: Canvas, pts, color, width, edge=None, alpha=1.0, seed=0):
    """Кант: полоса цвета и тонкая тёмная кромка."""
    c.line(pts, width, color, alpha, wobble=0.4, seed=seed)
    if edge:
        p = np.asarray(pts, float)
        c.line(p + [0, width * 0.55], max(1.2, width * 0.18), edge, alpha * 0.8, wobble=0.3, seed=seed + 1)
        c.line(p - [0, width * 0.55], max(1.2, width * 0.18), edge, alpha * 0.8, wobble=0.3, seed=seed + 2)


def vtrim(c: Canvas, x, h, color, width, edge=None, seed=0):
    trim(c, [(x, -4), (x, h + 4)], color, width, None, seed=seed)
    if edge:
        for s in (-1, 1):
            c.line([(x + s * width * 0.55, -4), (x + s * width * 0.55, h + 4)], max(1.2, width * 0.18), edge, 0.8,
                   wobble=0.3, seed=seed + 3 + s)


def dots_band(c: Canvas, y, w, color, r=2.2, step=14, alpha=0.9):
    for x in np.arange(step / 2, w, step):
        c.ellipse(x, y, r, r, color, alpha)


# ---------------------------------------------------------------- ткани

def kaftan_torso(main, dark, light, trimc, inner, emb=None, seed=0):
    """Торс кафтана: u — вокруг (0 спина, 0.5 перёд), картинка вверх = плечи."""
    def p(c: Canvas, w, h):
        c.underpaint([_shade(main, 0.88), main, _mix(main, light, 0.18)], cell=48, seed=seed)
        # складки: на груди диагонально от плеч к поясу, на спине вертикально
        for i in range(70):
            x = c.rs.uniform(0, w)
            side = 1 if x > w * 0.5 else -1
            ang = 90 + side * 18 * (1 - abs(x / w - 0.5) * 2) + c.rs.normal(0, 6)
            col = _shade(main, 0.72) if i % 2 else _mix(main, light, 0.35)
            c._stroke(x, c.rs.uniform(h * 0.25, h * 0.85), math.radians(ang), c.rs.uniform(0.25, 0.6) * h,
                      c.rs.uniform(6, 14), np.array(rgb8(col), float), c.rs.uniform(0.15, 0.35), c.rs.normal(0, 0.2), 3, 0.4)
        c.strokes(500, [_shade(main, 0.9), _mix(main, light, 0.25), main], length=(10, 26), width=(3, 7),
                  angle=90, angle_jitter=25, alpha=(0.15, 0.35))
        vgrad(c, 1.18, 0.7)
        # свет на груди и плечах (рисованный)
        c.strokes(120, [_mix(main, light, 0.55)], length=(14, 30), width=(4, 9), angle=0, angle_jitter=30,
                  alpha=(0.1, 0.25), region=(w * 0.25, 0, w * 0.75, h * 0.35))
        # передний разрез: полоса нижней рубахи и золотой кант по краям
        xc = w * 0.5
        c.rect(xc - 9, 0, xc + 9, h, inner, 0.95)
        c.strokes(40, [_shade(inner, 0.85), _shade(inner, 1.05)], length=(10, 24), width=(2, 4), angle=90,
                  alpha=(0.3, 0.5), region=(xc - 9, 0, xc + 9, h))
        for s in (-1, 1):
            vtrim(c, xc + s * 12, h, trimc, 6, _shade(trimc, 0.45), seed=seed + s)
        # ворот: золотой пояс у шеи
        trim(c, [(-4, h * 0.06), (w + 4, h * 0.06)], trimc, 10, _shade(trimc, 0.45), seed=seed + 5)
        if emb:
            for yy in np.linspace(h * 0.18, h * 0.8, 6):
                for s in (-1, 1):
                    c.ellipse(xc + s * 26, yy, 4.5, 4.5, emb, 0.9)
                    c.ellipse(xc + s * 26, yy, 2, 2, _shade(emb, 0.5), 0.9)
        c.grain(0.025)
    return p


def kaftan_skirt(main, dark, light, trimc, seed=0, hem=True, ornament=None):
    """Подол: u — по полукругу (0 = передний край), картинка вниз = к подолу."""
    def p(c: Canvas, w, h):
        c.underpaint([_shade(main, 0.85), main, _mix(main, light, 0.12)], cell=40, seed=seed)
        # тяжёлые вертикальные складки, к подолу шире
        for i in range(56):
            x = (i + c.rs.uniform(-0.3, 0.3)) / 56 * w
            col = _shade(main, 0.62) if i % 2 else _mix(main, light, 0.38)
            L = c.rs.uniform(0.55, 1.0) * h
            c._stroke(x, h - L * 0.5 + c.rs.uniform(0, h * 0.1), math.radians(90 + c.rs.normal(0, 3)), L,
                      c.rs.uniform(7, 15), np.array(rgb8(col), float), c.rs.uniform(0.2, 0.42), c.rs.normal(0, 0.1), 3, -0.6)
        c.strokes(400, [_shade(main, 0.9), main], length=(14, 34), width=(3, 7), angle=90, angle_jitter=8,
                  alpha=(0.12, 0.3))
        vgrad(c, 1.1, 0.62)
        if hem:
            trim(c, [(-4, h - 16), (w + 4, h - 16)], trimc, 12, _shade(trimc, 0.45), seed=seed + 1)
            if ornament:
                for x in np.arange(18, w, 36):
                    rhomb(c, x, h - 38, 7, 9, ornament, 0.85)
        vtrim(c, 7, h, trimc, 7, _shade(trimc, 0.45), seed=seed + 2)
        c.grain(0.025)
    return p


def sleeve(main, light, trimc, seed=0, h_frac=1.0):
    """Рукав: u — вокруг, v — от плеча (верх) к запястью (низ, с обшлагом)."""
    def p(c: Canvas, w, h):
        c.underpaint([_shade(main, 0.86), main, _mix(main, light, 0.15)], cell=36, seed=seed)
        # поперечные складки на сгибе
        c.strokes(160, [_shade(main, 0.68), _mix(main, light, 0.35)], length=(18, 46), width=(4, 9), angle=0,
                  angle_jitter=18, alpha=(0.18, 0.38))
        c.strokes(240, [main, _shade(main, 0.9)], length=(10, 24), width=(3, 6), angle=90, angle_jitter=20,
                  alpha=(0.12, 0.3))
        vgrad(c, 1.1, 0.8)
        trim(c, [(-4, h - 14), (w + 4, h - 14)], trimc, 12, _shade(trimc, 0.45), seed=seed + 1)
        c.grain(0.025)
    return p


def plain_cloth(main, light, dark=None, seed=0, vertical=True, stripes=None, grad=(1.08, 0.75)):
    def p(c: Canvas, w, h):
        c.underpaint([_shade(main, 0.85), main, _mix(main, light, 0.15)], cell=40, seed=seed)
        folds(c, w, h, dark or _shade(main, 0.65), _mix(main, light, 0.35), n=36, vertical=vertical)
        c.strokes(300, [main, _shade(main, 0.9), _mix(main, light, 0.2)], length=(10, 26), width=(3, 6),
                  angle=90 if vertical else 0, angle_jitter=15, alpha=(0.12, 0.3))
        if stripes:
            for i, (col, frac, wd) in enumerate(stripes):
                if vertical:
                    vtrim(c, frac * w, h, col, wd, seed=seed + i)
                else:
                    trim(c, [(-4, frac * h), (w + 4, frac * h)], col, wd, seed=seed + i)
        vgrad(c, *grad)
        c.grain(0.025)
    return p


# ---------------------------------------------------------------- шапки

def turban(cloth, shade, stripe=None, cap="#2f8f74", cap_trim="#c9a24a", seed=0):
    """Чалма вокруг высокой шапки (кулах): верх ячейки — шапка, ниже — витки ткани."""
    def p(c: Canvas, w, h):
        cap_h = h * 0.34
        # кулах
        c.rect(0, 0, w, cap_h, cap)
        c.strokes(200, [_shade(cap, 0.8), _mix(cap, "#ffffff", 0.2)], length=(12, 30), width=(3, 7), angle=90,
                  angle_jitter=10, alpha=(0.2, 0.45), region=(0, 0, w, cap_h))
        for x in np.arange(0, w, w / 8):
            c.line([(x, 0), (x, cap_h)], 2.0, _shade(cap, 0.55), 0.7, seed=int(x))
        trim(c, [(-4, cap_h - 6), (w + 4, cap_h - 6)], cap_trim, 7, _shade(cap_trim, 0.5), seed=seed)
        # витки чалмы: диагональные полосы ткани
        y0 = cap_h
        c.rect(0, y0, w, h, cloth)
        n = 9
        for i in range(n):
            yy = y0 + (i + 0.5) / n * (h - y0)
            pts = [(x, yy + 10 * math.sin(x / w * 2 * math.pi * 2 + i)) for x in np.linspace(-4, w + 4, 24)]
            c.line(pts, (h - y0) / n * 0.85, _mix(cloth, shade, 0.15 if i % 2 else 0.0), 0.9, wobble=1.0, seed=seed + i)
            c.line([(x, y + (h - y0) / n * 0.38) for x, y in pts], 2.2, shade, 0.55, wobble=0.8, seed=seed + 20 + i)
            if stripe:
                c.line([(x, y - 3) for x, y in pts], 3.0, stripe, 0.85, wobble=0.6, seed=seed + 40 + i)
        c.strokes(220, [_mix(cloth, "#ffffff", 0.4), shade], length=(10, 26), width=(3, 6), angle=-8,
                  angle_jitter=8, alpha=(0.12, 0.3), region=(0, y0, w, h))
        vgrad(c, 1.12, 0.78)
        c.grain(0.02)
    return p


def kalpak(felt, felt_shade, brim, brim_light, seed=0, tassel="#b0392f"):
    """Белый войлочный калпак: верх — тулья с прострочкой, низ — отворот."""
    def p(c: Canvas, w, h):
        c.underpaint([felt_shade, felt, _mix(felt, "#ffffff", 0.3)], cell=30, seed=seed)
        c.strokes(500, [felt, _shade(felt, 0.92), _mix(felt, "#ffffff", 0.4)], length=(8, 20), width=(3, 6),
                  angle=90, angle_jitter=40, alpha=(0.15, 0.35))
        # швы клиньев
        for x in np.arange(w / 8, w, w / 4):
            c.line([(x, 0), (x, h * 0.78)], 2.4, _shade(felt_shade, 0.7), 0.75, wobble=0.6, seed=int(x))
            c.line([(x + 3, 0), (x + 3, h * 0.78)], 1.4, _mix(felt, "#ffffff", 0.5), 0.6, seed=int(x) + 1)
        # отворот (чёрный бархат)
        by = h * 0.8
        c.rect(0, by, w, h, brim)
        c.strokes(120, [brim_light, _shade(brim, 0.7)], length=(10, 24), width=(3, 6), angle=0, angle_jitter=8,
                  alpha=(0.2, 0.45), region=(0, by, w, h))
        c.line([(-4, by), (w + 4, by)], 2.5, _mix(brim_light, "#ffffff", 0.3), 0.8, seed=seed)
        # кисточка на макушке
        c.rect(0, 0, w, 10, tassel)
        vgrad(c, 1.12, 0.8)
        c.grain(0.02)
    return p


# ---------------------------------------------------------------- кожа, металл, дерево

def skin_region(skin, skin_dark, hair, beard=True, seed=0):
    def p(c: Canvas, w, h):
        hw = int(w * 0.5)
        c.underpaint([skin_dark, skin, _mix(skin, "#ffd6b0", 0.25)], cell=26, seed=seed)
        c.strokes(500, [skin, _shade(skin, 0.9), _mix(skin, "#ffcfa8", 0.3)], length=(6, 16), width=(3, 6),
                  angle=90, angle_jitter=40, alpha=(0.15, 0.35))
        # лицо в центре головы (u 0.5): глаза, брови, нос, усы и борода
        fx = hw * 0.5
        # затылок и волосы под шапкой: края по u
        for x0, x1 in ((0, hw * 0.24), (hw * 0.76, hw)):
            c.rect(x0, 0, x1, h * 0.55, hair, 0.92)
        c.rect(0, 0, hw, h * 0.16, hair, 0.9)
        ey = h * 0.42
        for s in (-1, 1):
            c.ellipse(fx + s * hw * 0.085, ey, hw * 0.06, h * 0.045, _shade(skin_dark, 0.85), 0.55)  # глазницы
            c.line([(fx + s * hw * 0.04, ey - h * 0.06), (fx + s * hw * 0.13, ey - h * 0.075)], 4.5, hair, 0.95,
                   seed=seed + s)  # брови
            c.line([(fx + s * hw * 0.05, ey), (fx + s * hw * 0.11, ey)], 3.2, "#1d1410", 0.95, seed=seed + 2 + s)  # глаза
            c.ellipse(fx + s * hw * 0.12, h * 0.56, hw * 0.05, h * 0.04, "#c86a50", 0.25)  # румянец
        c.line([(fx, ey + h * 0.01), (fx + 2, h * 0.58)], 6, _shade(skin_dark, 0.9), 0.5, seed=seed + 7)  # нос (тень)
        c.line([(fx - 3, ey + h * 0.01), (fx - 1, h * 0.56)], 3, _mix(skin, "#ffe0c0", 0.5), 0.6, seed=seed + 8)
        if beard:
            c.line([(fx - hw * 0.1, h * 0.66), (fx, h * 0.62), (fx + hw * 0.1, h * 0.66)], 5, hair, 0.95,
                   seed=seed + 9)  # усы
            c.polygon([(fx - hw * 0.12, h * 0.72), (fx + hw * 0.12, h * 0.72), (fx + hw * 0.05, h * 0.95),
                       (fx - hw * 0.05, h * 0.95)], hair, 0.92)  # борода
        else:
            c.line([(fx - hw * 0.08, h * 0.66), (fx + hw * 0.08, h * 0.66)], 3, _shade(skin_dark, 0.8), 0.7,
                   seed=seed + 9)
        c.line([(fx - hw * 0.05, h * 0.7), (fx + hw * 0.05, h * 0.7)], 2.5, "#5a2a22", 0.7, seed=seed + 10)
        # кисти: костяшки и тень
        c.strokes(80, [_shade(skin, 0.8)], length=(6, 12), width=(2, 4), angle=0, alpha=(0.2, 0.4),
                  region=(hw, 0, int(w * 0.75), h))
        # волосы/мех (тёмная полоса справа)
        c.rect(int(w * 0.75), 0, w, h, hair)
        c.strokes(200, [_mix(hair, "#ffffff", 0.15), _shade(hair, 0.7)], length=(10, 24), width=(2, 4), angle=90,
                  alpha=(0.3, 0.6), region=(int(w * 0.75), 0, w, h))
        vgrad(c, 1.1, 0.82)
        c.grain(0.02)
    return p


def leather_region(boot, belt, felt, seed=0):
    def p(c: Canvas, w, h):
        c.underpaint([_shade(boot, 0.8), boot, _mix(boot, "#c08a5a", 0.2)], cell=30, seed=seed)
        c.strokes(300, [_mix(boot, "#e0b080", 0.35), _shade(boot, 0.7)], length=(10, 30), width=(3, 7), angle=90,
                  angle_jitter=14, alpha=(0.2, 0.45), region=(0, 0, w * 0.5, h))
        # голенище: блик сверху вниз, отворот
        for x in np.arange(10, w * 0.5, 40):
            c.line([(x, 0), (x + 2, h)], 5, _mix(boot, "#f0c090", 0.4), 0.35, seed=int(x))
        trim(c, [(-4, 10), (w * 0.5, 10)], _shade(boot, 0.6), 8, seed=seed)
        c.rect(w * 0.5, 0, w * 0.75, h, belt)
        c.strokes(120, [_mix(belt, "#e0b080", 0.3), _shade(belt, 0.7)], length=(10, 24), width=(2, 5), angle=0,
                  alpha=(0.25, 0.5), region=(w * 0.5, 0, w * 0.75, h))
        c.rect(w * 0.75, 0, w, h, felt)
        c.strokes(160, [_mix(felt, "#ffffff", 0.2), _shade(felt, 0.8)], length=(8, 18), width=(3, 6), angle=90,
                  angle_jitter=50, alpha=(0.2, 0.4), region=(w * 0.75, 0, w, h))
        vgrad(c, 1.15, 0.7)
        c.grain(0.02)
    return p


def metal_region(seed=0):
    def p(c: Canvas, w, h):
        q = w // 4
        cols = [("#c9a24a", "#7d5a22", "#ffe39a"), ("#9aa1a8", "#4d535a", "#e8eef2"),
                ("#5d6066", "#2c2f34", "#a8acb2"), ("#b58a3c", "#6e4a1e", "#f0c878")]
        for i, (m, d, l) in enumerate(cols):
            x0, x1 = i * q, (i + 1) * q
            c.rect(x0, 0, x1, h, m)
            c.strokes(120, [d, m], length=(16, 40), width=(4, 10), angle=90, angle_jitter=10, alpha=(0.3, 0.55),
                      region=(x0, 0, x1, h))
            # нарисованный блик: светлые штрихи
            c.strokes(40, [l], length=(10, 30), width=(2, 5), angle=90, angle_jitter=6, alpha=(0.5, 0.85),
                      region=(x0 + q * 0.3, 0, x0 + q * 0.6, h))
            if i == 0:  # золото: гравировка завитками
                for yy in np.arange(20, h, 48):
                    c.line(spiral_points(x0 + q * 0.5, yy, 12, 1.3), 2, d, 0.6, seed=int(yy))
        vgrad(c, 1.15, 0.75)
    return p


def wood_region(seed=0):
    def p(c: Canvas, w, h):
        hw = w // 2
        c.rect(0, 0, hw, h, "#5a3b24")
        c.strokes(260, ["#38231a", "#7a5232", "#6a4428"], length=(30, 90), width=(3, 8), angle=90, angle_jitter=4,
                  alpha=(0.3, 0.6), region=(0, 0, hw, h))
        # золотые накладки ложа
        for yy in (h * 0.2, h * 0.45, h * 0.7):
            trim(c, [(-2, yy), (hw + 2, yy)], "#c9a24a", 7, "#7d5a22", seed=int(yy))
        c.rect(hw, 0, w, h, "#9a7a52")
        c.strokes(220, ["#6e5638", "#b8986a", "#8a6a44"], length=(30, 90), width=(3, 7), angle=90, angle_jitter=3,
                  alpha=(0.3, 0.6), region=(hw, 0, w, h))
        vgrad(c, 1.1, 0.85)
        c.grain(0.02)
    return p


# ---------------------------------------------------------------- знамёна, попоны, щиты

def banner_kokand(seed=0):
    def p(c: Canvas, w, h):
        main, light, dark, gold = KOKAND["main"], KOKAND["light"], KOKAND["dark"], KOKAND["gold"]
        c.underpaint([_shade(main, 0.85), main, _mix(main, light, 0.25)], cell=48, seed=seed)
        c.strokes(500, [_mix(main, light, 0.3), _shade(main, 0.8)], length=(20, 50), width=(5, 12), angle=10,
                  angle_jitter=15, alpha=(0.15, 0.35))
        # поле: зелёная середина, золотая кайма, полумесяц и «надпись»
        m = 34
        c.rect(m, m, w - m, h - m, _mix(main, "#1f6e52", 0.5), 0.55)
        for s in range(2):
            pts = [(m - 10 + s * 6, m - 10 + s * 6), (w - m + 10 - s * 6, m - 10 + s * 6),
                   (w - m + 10 - s * 6, h - m + 10 - s * 6), (m - 10 + s * 6, h - m + 10 - s * 6)]
            c.line(pts + [pts[0]], 9 - s * 4, gold if s == 0 else _shade(gold, 0.6), 0.95, seed=seed + s)
        # полумесяц
        cx, cy, r = w * 0.5, h * 0.36, w * 0.17
        c.ellipse(cx, cy, r, r, gold, 0.95)
        c.ellipse(cx + r * 0.38, cy - r * 0.1, r * 0.82, r * 0.82, _mix(main, "#1f6e52", 0.5), 1.0)
        # звезда
        sx, sy = cx + r * 0.75, cy - r * 0.15
        pts = []
        for i in range(10):
            a = i * math.pi / 5 - math.pi / 2
            rr = r * 0.28 if i % 2 == 0 else r * 0.11
            pts.append((sx + rr * math.cos(a), sy + rr * math.sin(a)))
        c.polygon(pts, gold, 0.95)
        # строки «надписи» — золотые завитки
        for row, yy in enumerate((h * 0.66, h * 0.78)):
            x = m + 20
            while x < w - m - 30:
                L = c.rs.uniform(18, 46)
                pts = [(x + t * L, yy + 6 * math.sin(t * 6 + row) - (10 if t > 0.8 else 0)) for t in np.linspace(0, 1, 8)]
                c.line(pts, 4.5, gold, 0.9, seed=int(x))
                x += L + c.rs.uniform(8, 16)
        vgrad(c, 1.1, 0.8)
        c.grain(0.02)
    return p


def banner_kipchak(seed=0):
    def p(c: Canvas, w, h):
        main, light, dark = KIPCHAK["main"], KIPCHAK["light"], KIPCHAK["dark"]
        white = KIPCHAK["felt"]
        c.underpaint([_shade(main, 0.85), main, _mix(main, light, 0.2)], cell=48, seed=seed)
        c.strokes(500, [_mix(main, light, 0.3), _shade(main, 0.75)], length=(20, 50), width=(5, 12), angle=10,
                  angle_jitter=15, alpha=(0.15, 0.35))
        # белая кайма с волнистым краем
        m = 30
        for y in (m, h - m):
            pts = [(x, y + 6 * math.sin(x / 18)) for x in np.linspace(-4, w + 4, 40)]
            c.line(pts, 12, white, 0.95, seed=int(y))
            c.line([(x, yy + 9) for x, yy in pts], 2.5, dark, 0.8, seed=int(y) + 1)
        # «кочкор мүйүз» — бараньи рога
        ram_horn(c, w * 0.5, h * 0.5, w * 0.42, white, 13, 0.97, seed=seed)
        ram_horn(c, w * 0.5, h * 0.5, w * 0.42, _shade(main, 0.55), 3.5, 0.5, seed=seed + 1)
        for x in (w * 0.18, w * 0.82):
            rhomb(c, x, h * 0.2, 14, 20, white, 0.9)
            rhomb(c, x, h * 0.8, 14, 20, white, 0.9)
        vgrad(c, 1.1, 0.8)
        c.grain(0.02)
    return p


def caparison(main, light, dark, orn, trimc, seed=0, kind="kipchak"):
    """Попона: u — от левого подола через спину к правому, v — от хвоста к груди."""
    def p(c: Canvas, w, h):
        c.underpaint([_shade(main, 0.85), main, _mix(main, light, 0.15)], cell=44, seed=seed)
        c.strokes(500, [_mix(main, light, 0.25), _shade(main, 0.75), main], length=(16, 40), width=(4, 10),
                  angle=0, angle_jitter=20, alpha=(0.15, 0.35))
        # свет на спине (u≈0.5), тень к подолам
        x = np.linspace(0, 1, c.w * c.ss)
        k = 0.72 + 0.4 * np.exp(-((x - 0.5) / 0.22) ** 2)
        arr = np.asarray(c.img, dtype=np.float64)
        c._blend(arr * k[None, :, None])
        # орнаментальная полоса вдоль подолов (u≈0.08 и 0.92) и бахрома по краю
        for side in (0, 1):
            bx = w * (0.075 if side == 0 else 0.925)
            c.rect(bx - 22, 0, bx + 22, h, _shade(main, 0.7), 0.9)
            for yy in np.arange(26, h, 52):
                if kind == "kipchak":
                    ram_horn(c, bx, yy, 34, orn, 4.5, 0.95, seed=int(yy) + side)
                else:
                    rhomb(c, bx, yy, 12, 18, orn, 0.95, outline=_shade(orn, 0.6), width=2)
            for s in (-1, 1):
                c.line([(bx + s * 24, -4), (bx + s * 24, h + 4)], 4, trimc, 0.95, seed=side * 3 + s)
            # бахрома
            ex = 0 if side == 0 else w
            for yy in np.arange(0, h, 7):
                c.line([(ex, yy), (ex + (8 if side == 0 else -8), yy + 2)], 3, trimc, 0.8, seed=int(yy))
        # тиснение по центру
        if kind == "kipchak":
            for yy in np.arange(60, h, 140):
                rhomb(c, w * 0.5, yy, 26, 34, _shade(main, 0.7), 0.6)
        else:
            for yy in np.arange(60, h, 120):
                c.ellipse(w * 0.5, yy, 18, 18, trimc, 0.7)
        c.grain(0.025)
    return p


def shield_kipchak(seed=0):
    """Плетёный щит-калкан: спираль из красной и светлой нити, железный умбон (развёртка сверху)."""
    def p(c: Canvas, w, h):
        cx, cy = w / 2, h / 2
        c.rect(0, 0, w, h, "#d9c7a0")
        cols = [KIPCHAK["main"], "#e6dcc4", KIPCHAK["dark"], "#e6dcc4"]
        for i in range(26):
            r = w * 0.49 * (1 - i / 27)
            pts = [(cx + r * math.cos(a), cy + r * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 64)]
            c.line(pts, w * 0.49 / 27 * 1.1, cols[(i // 3) % 4], 0.95, wobble=0.5, seed=i)
        for a in np.linspace(0, 2 * math.pi, 8, endpoint=False):
            ram_horn(c, cx + w * 0.3 * math.cos(a), cy + w * 0.3 * math.sin(a), 22, "#f4ead2", 3, 0.9, seed=int(a * 10))
        c.ellipse(cx, cy, w * 0.13, h * 0.13, "#5d6066")
        c.ellipse(cx - w * 0.03, cy - h * 0.03, w * 0.05, h * 0.05, "#c8ccd0", 0.8)
        c.line([(cx + w * 0.49 * math.cos(a), cy + w * 0.49 * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 64)],
               6, "#3a2a1c", 0.95, seed=seed)
        c.grain(0.02)
    return p


def pennon(main, white, seed=0):
    def p(c: Canvas, w, h):
        c.rect(0, 0, w, h, main)
        c.strokes(160, [_shade(main, 0.8), _mix(main, "#ffffff", 0.2)], length=(14, 30), width=(4, 8), angle=0,
                  alpha=(0.2, 0.4))
        c.rect(0, h * 0.42, w, h * 0.58, white, 0.95)
        c.grain(0.02)
    return p


def hair_strip(col, light, seed=0):
    def p(c: Canvas, w, h):
        c.rect(0, 0, w, h, col)
        c.strokes(400, [light, _shade(col, 0.7), col], length=(16, 40), width=(2, 4), angle=90, angle_jitter=6,
                  alpha=(0.3, 0.6))
        vgrad(c, 1.1, 0.8)
    return p


def fur(col, light, seed=0):
    def p(c: Canvas, w, h):
        c.underpaint([_shade(col, 0.7), col, light], cell=20, seed=seed)
        c.strokes(900, [light, _shade(col, 0.6), col], length=(6, 14), width=(2, 4), angle=90, angle_jitter=35,
                  alpha=(0.3, 0.7))
        vgrad(c, 1.15, 0.75)
    return p


def lamellar(plate, plate_dark, lace, seed=0):
    """Ламеллярный доспех: ряды пластин, красная шнуровка."""
    def p(c: Canvas, w, h):
        c.rect(0, 0, w, h, _shade(plate_dark, 0.8))
        rows, cols = 9, 26
        ph, pw = h / rows, w / cols
        for r in range(rows):
            off = (r % 2) * pw * 0.5
            for k in range(cols + 1):
                x = k * pw + off - pw * 0.5
                y = r * ph
                col = _mix(plate, "#ffffff", c.rs.uniform(0, 0.15)) if c.rs.random() > 0.3 else plate
                c.polygon([(x + 2, y + 3), (x + pw - 2, y + 3), (x + pw - 2, y + ph - 8), (x + pw / 2, y + ph - 2),
                           (x + 2, y + ph - 8)], col, 0.97, wobble=0.6)
                c.line([(x + pw * 0.3, y + 6), (x + pw * 0.3, y + ph * 0.7)], 2, "#f0f2f4", 0.35, seed=r * 50 + k)
            c.line([(-4, r * ph + ph * 0.5), (w + 4, r * ph + ph * 0.5)], 3.5, lace, 0.9, wobble=0.8, seed=r)
        # кайма киноварью по низу и вороту
        trim(c, [(-4, h - 10), (w + 4, h - 10)], KIPCHAK["main"], 14, KIPCHAK["dark"], seed=seed)
        trim(c, [(-4, 8), (w + 4, 8)], KIPCHAK["main"], 12, KIPCHAK["dark"], seed=seed + 1)
        vgrad(c, 1.2, 0.72)
    return p


# ---------------------------------------------------------------- кони и овцы

HORSE_COATS = [
    # (тело, тень, свет, грива/хвост, ноги-низ, копыто, отметины, «яблоки»)
    ("#6b3f26", "#3e2214", "#a8683c", "#1e1612", "#221a16", "#3a3530", None, False),   # гнедой
    ("#8a4a26", "#55291a", "#c8804a", "#7a3a1c", "#8a4a26", "#4a4038", "#efe6d6", False),  # рыжий (белые носочки)
    ("#a7a39a", "#6e6c68", "#e4e0d8", "#d8d4cc", "#6a6660", "#4a4440", None, True),     # серый в яблоках
    ("#2c2420", "#14100e", "#5a4a40", "#141010", "#181412", "#2a2622", None, False),    # вороной
]


def horse_cell(coat, seed=0):
    body, dark, light, hair, legc, hoof, sock, dapple = coat

    def p(c: Canvas, w, h):
        def sub(name):
            f = HORSE_SUB[name]
            return (f[0] * w, f[1] * h, f[2] * w, f[3] * h)

        # тело: u вокруг (0 верх, 0.25 правый бок, 0.5 живот, 0.75 левый бок), v (картинка вверх) — к груди
        x0, y0, x1, y1 = sub("body")
        c.rect(x0, y0, x1, y1, body)
        c.underpaint([dark, body, _mix(body, light, 0.35)], cell=40, seed=seed,
                     mask=_rect_mask(c, x0, y0, x1, y1))
        xs = np.linspace(0, 1, c.w * c.ss)
        lit = 0.62 + 0.55 * np.cos(xs * 2 * np.pi) ** 2 * (np.cos(xs * 2 * np.pi) > 0)  # спина светлее
        lit += 0.18 * np.exp(-((xs - 0.25) / 0.1) ** 2) + 0.18 * np.exp(-((xs - 0.75) / 0.1) ** 2)  # округлость боков
        arr = np.asarray(c.img, dtype=np.float64)
        yy0, yy1 = int(y0 * c.ss), int(y1 * c.ss)
        arr[yy0:yy1] = arr[yy0:yy1] * lit[None, :, None]
        c._blend(arr)
        # лепка мышц: светлые мазки на крупе и плече, тень за лопаткой
        for vy, k in ((0.82, 1.0), (0.18, 1.0)):
            for ux in (0.25, 0.75):
                c.strokes(40, [_mix(body, light, 0.6)], length=(20, 40), width=(6, 12), angle=90, angle_jitter=40,
                          alpha=(0.15, 0.3), region=(ux * w - 40, y0 + (1 - vy) * (y1 - y0) - 30,
                                                     ux * w + 40, y0 + (1 - vy) * (y1 - y0) + 30))
        c.strokes(500, [body, _mix(body, light, 0.25), _shade(body, 0.85)], length=(10, 26), width=(3, 6),
                  angle=90, angle_jitter=12, alpha=(0.12, 0.3), region=(x0, y0, x1, y1))
        if dapple:
            for i in range(90):
                cx, cy = c.rs.uniform(x0, x1), c.rs.uniform(y0, y1)
                r = c.rs.uniform(5, 10)
                c.ellipse(cx, cy, r, r * 0.8, _mix(body, "#ffffff", 0.45), 0.45)
                c.ellipse(cx, cy, r * 1.4, r * 1.2, _shade(body, 0.85), 0.25)
        # шея: u вокруг (0 гребень), v к голове; грива по гребню
        for nm in ("neck", "head"):
            x0, y0, x1, y1 = sub(nm)
            c.rect(x0, y0, x1, y1, body)
            c.strokes(160, [_mix(body, light, 0.3), _shade(body, 0.8)], length=(10, 24), width=(3, 6), angle=90,
                      angle_jitter=20, alpha=(0.2, 0.4), region=(x0, y0, x1, y1))
            # свет сверху (u≈0, 1) и тень снизу (u≈0.5)
            for fx, a in ((0.5, 0.45),):
                c.rect(x0 + (x1 - x0) * 0.32, y0, x0 + (x1 - x0) * 0.68, y1, dark, a)
        x0, y0, x1, y1 = sub("neck")
        for fx in (0.0, 1.0):
            c.rect(x0 + (x1 - x0) * (fx - 0.1), y0, x0 + (x1 - x0) * (fx + 0.1), y1, hair, 0.95)
        x0, y0, x1, y1 = sub("head")
        # морда темнее к носу (низ картинки — морда), глаза по бокам, проточина
        c.rect(x0, y1 - (y1 - y0) * 0.25, x1, y1, _shade(body, 0.55), 0.6)
        for fx in (0.25, 0.75):
            c.ellipse(x0 + (x1 - x0) * fx, y0 + (y1 - y0) * 0.3, 6, 5, "#120c0a", 0.95)
            c.ellipse(x0 + (x1 - x0) * fx - 1, y0 + (y1 - y0) * 0.3 - 1, 2, 2, "#e8e0d8", 0.8)
        if sock:
            c.line([(x0 + (x1 - x0) * 0.0 + 4, y0), (x0 + 6, y1)], 10, sock, 0.9, seed=seed)
            c.line([(x1 - 4, y0), (x1 - 6, y1)], 10, sock, 0.9, seed=seed + 1)
        # ноги: u вокруг, v (картинка вверх) — вверх ноги; низ ног темнее (отметины)
        x0, y0, x1, y1 = sub("legs")
        c.rect(x0, y0, x1, y1, body)
        c.strokes(200, [_mix(body, light, 0.3), _shade(body, 0.8)], length=(10, 26), width=(3, 6), angle=90,
                  alpha=(0.2, 0.4), region=(x0, y0, x1, y1))
        yb = y0 + (y1 - y0) * 0.55
        c.rect(x0, yb, x1, y1, legc, 0.95)
        if sock:
            c.rect(x0, y0 + (y1 - y0) * 0.75, x1, y1, sock, 0.95)
        # грива и хвост
        x0, y0, x1, y1 = sub("hair")
        c.rect(x0, y0, x1, y1, hair)
        c.strokes(300, [_mix(hair, "#ffffff", 0.2), _shade(hair, 0.6), hair], length=(20, 50), width=(2, 4),
                  angle=90, angle_jitter=6, alpha=(0.35, 0.7), region=(x0, y0, x1, y1))
        x0, y0, x1, y1 = sub("hoof")
        c.rect(x0, y0, x1, y1, hoof)
        c.strokes(60, [_mix(hoof, "#ffffff", 0.15)], length=(10, 20), width=(2, 4), angle=90, alpha=(0.3, 0.5),
                  region=(x0, y0, x1, y1))
        x0, y0, x1, y1 = sub("eye")
        c.rect(x0, y0, x1, y1, "#3a2a20")
        c.grain(0.02)
    return p


def _rect_mask(c: Canvas, x0, y0, x1, y1):
    m = np.zeros((c.h * c.ss, c.w * c.ss))
    m[int(y0 * c.ss):int(y1 * c.ss), int(x0 * c.ss):int(x1 * c.ss)] = 1
    return m


WOOL = [("#e8dfcc", "#b5a78c", "#fff6e6", "#2a221c"), ("#d9c8a6", "#a08c68", "#f4e6c8", "#e8dccb"),
        ("#9a7652", "#5e4430", "#c49a70", "#3a2a20"), ("#4a3a30", "#2a1f1a", "#6e5a4a", "#e0d6c8")]


def sheep_cell(wool, seed=0):
    base, dark, light, face = wool

    def p(c: Canvas, w, h):
        def sub(name):
            f = SHEEP_SUB[name]
            return (f[0] * w, f[1] * h, f[2] * w, f[3] * h)
        x0, y0, x1, y1 = sub("body")
        c.rect(x0, y0, x1, y1, base)
        # кудрявая шерсть: короткие закрученные мазки
        for i in range(1400):
            x, y = c.rs.uniform(x0, x1), c.rs.uniform(y0, y1)
            pts = spiral_points(x, y, c.rs.uniform(3, 7), turns=0.8, start=c.rs.uniform(0, 6.28), n=8)
            c.line(pts, c.rs.uniform(1.5, 3.5), [light, dark, base][i % 3], c.rs.uniform(0.25, 0.6), wobble=0.2,
                   seed=i)
        xs = np.linspace(0, 1, c.w * c.ss)
        lit = 0.7 + 0.45 * np.clip(np.cos(xs * 2 * np.pi), 0, 1)
        arr = np.asarray(c.img, dtype=np.float64)
        yy0, yy1 = int(y0 * c.ss), int(y1 * c.ss)
        arr[yy0:yy1] = arr[yy0:yy1] * lit[None, :, None]
        c._blend(arr)
        for nm in ("head", "face"):
            x0, y0, x1, y1 = sub(nm)
            c.rect(x0, y0, x1, y1, face)
            c.strokes(100, [_mix(face, "#ffffff", 0.2), _shade(face, 0.7)], length=(8, 18), width=(2, 4), angle=90,
                      alpha=(0.2, 0.4), region=(x0, y0, x1, y1))
        x0, y0, x1, y1 = sub("head")
        for fx in (0.25, 0.75):
            c.ellipse(x0 + (x1 - x0) * fx, y0 + (y1 - y0) * 0.35, 4, 3, "#120c0a", 0.95)
        x0, y0, x1, y1 = sub("legs")
        c.rect(x0, y0, x1, y1, _mix(face, "#5a4a3a", 0.3))
        c.rect(x0, y0 + (y1 - y0) * 0.85, x1, y1, "#2a221c")
        x0, y0, x1, y1 = sub("tail")
        c.rect(x0, y0, x1, y1, base)
        c.strokes(200, [light, dark], length=(6, 14), width=(2, 4), angle=90, angle_jitter=60, alpha=(0.3, 0.5),
                  region=(x0, y0, x1, y1))
        c.grain(0.02)
    return p


# ---------------------------------------------------------------- сборка атласов

def build_kokand(path):
    A = KOKAND_ATLAS
    img = Image.new("RGB", (A.w, A.h), (40, 40, 40))
    main, dark, light, gold = KOKAND["main"], KOKAND["dark"], KOKAND["light"], KOKAND["gold"]
    for i, coat in enumerate(HORSE_COATS):
        region(img, A, f"coat{i}", horse_cell(coat, seed=10 + i), seed=10 + i)
    # чалмы: белая, белая в бирюзовую полоску, кремовая, белая в золотую полоску
    hats = [("#f2eee4", "#b8b0a0", None, "#1f6e5a"), ("#f0ece2", "#b0a898", "#2aa39a", "#8e1f2f"),
            ("#e8dcc0", "#a8987a", None, "#17463a"), ("#f4f0e8", "#b4ac9c", "#c9a24a", "#2f8f74")]
    for i, (cl, sh, st, cap) in enumerate(hats):
        region(img, A, f"hat{i}", turban(cl, sh, st, cap, gold, seed=20 + i), seed=20 + i)
    region(img, A, "skin", skin_region(MATERIAL["skin"], MATERIAL["skin_dark"], "#1e1612", True, seed=30), seed=30)
    region(img, A, "leather", leather_region("#3a2418", "#6e4428", "#c9b48a", seed=31), seed=31)
    region(img, A, "metal", metal_region(32), seed=32)
    region(img, A, "wood", wood_region(33), seed=33)
    region(img, A, "torso", kaftan_torso(main, dark, light, gold, "#e9e0c8", emb=gold, seed=40), seed=40)
    region(img, A, "skirt", kaftan_skirt(main, dark, light, gold, seed=41), seed=41)
    region(img, A, "sleeve", sleeve(main, light, gold, seed=42), seed=42)
    region(img, A, "trousers", plain_cloth("#3a3f52", "#6a7088", seed=43), seed=43)
    # офицерский кафтан: глубокий изумруд с густым золотом
    off_main = "#1f7a5c"
    region(img, A, "torso2", kaftan_torso(off_main, dark, light, gold, "#c9a24a", emb="#ffe39a", seed=44), seed=44)
    region(img, A, "skirt2", kaftan_skirt(off_main, dark, light, gold, seed=45, ornament=gold), seed=45)
    region(img, A, "sleeve2", sleeve(off_main, light, gold, seed=46), seed=46)
    region(img, A, "shirt", plain_cloth("#e9e0c8", "#ffffff", seed=47), seed=47)
    region(img, A, "saddlecloth", caparison(main, light, dark, gold, gold, seed=48, kind="kokand"), seed=48)
    region(img, A, "banner", banner_kokand(49), seed=49)
    region(img, A, "caparison", caparison(main, light, dark, gold, gold, seed=50, kind="kokand"), seed=50)
    region(img, A, "sash", plain_cloth("#e9e0c8", "#ffffff", seed=51, vertical=False,
                                       stripes=[("#2aa39a", 0.25, 10), ("#c9a24a", 0.5, 6), ("#2aa39a", 0.75, 10)]),
           seed=51)
    region(img, A, "flask", plain_cloth("#b58a3c", "#f0c878", seed=52), seed=52)
    region(img, A, "saddle", leather_region("#4a2c1c", "#c9a24a", "#2f8f74", seed=53), seed=53)
    region(img, A, "plume", hair_strip("#f4f0e8", "#ffffff", seed=54), seed=54)
    region(img, A, "finial", metal_region(55), seed=55)
    img.save(path, optimize=True)
    return img


def build_kipchak(path):
    A = KIPCHAK_ATLAS
    img = Image.new("RGB", (A.w, A.h), (40, 40, 40))
    main, dark, light = KIPCHAK["main"], KIPCHAK["dark"], KIPCHAK["light"]
    felt, felt_sh = KIPCHAK["felt"], KIPCHAK["felt_shadow"]
    for i, coat in enumerate(HORSE_COATS):
        region(img, A, f"coat{i}", horse_cell(coat, seed=110 + i), seed=110 + i)
    kal = [(felt, felt_sh, "#1a1614", "#4a4440"), ("#efe8d6", "#bdb094", "#4a2a1c", "#7a5038"),
           ("#e2d4b4", "#a89878", "#1a1614", "#4a4440"), ("#f2ece0", "#c0b49a", "#5a1712", "#8e3a2a")]
    for i, (f, fs, b, bl) in enumerate(kal):
        region(img, A, f"hat{i}", kalpak(f, fs, b, bl, seed=120 + i), seed=120 + i)
    region(img, A, "skin", skin_region("#b07a58", "#7e4e38", "#16100c", True, seed=130), seed=130)
    region(img, A, "leather", leather_region("#2e1c14", "#5a3420", "#e6dcc4", seed=131), seed=131)
    region(img, A, "metal", metal_region(132), seed=132)
    region(img, A, "wood", wood_region(133), seed=133)
    region(img, A, "torso", kaftan_torso(main, dark, light, "#e6dcc4", "#e6dcc4", seed=140), seed=140)
    region(img, A, "skirt", kaftan_skirt(main, dark, light, "#e6dcc4", seed=141, ornament="#1a1614"), seed=141)
    region(img, A, "sleeve", sleeve(main, light, "#e6dcc4", seed=142), seed=142)
    region(img, A, "trousers", plain_cloth("#3a2a22", "#6a5040", seed=143), seed=143)
    region(img, A, "torso2", lamellar("#8a9098", "#3a3e44", main, seed=144), seed=144)
    region(img, A, "banner", banner_kipchak(149), seed=149)
    region(img, A, "caparison", caparison(main, light, dark, "#efe6d2", "#e6dcc4", seed=150, kind="kipchak"), seed=150)
    # малчы: приглушённая шерсть, красный акцент по кромке
    region(img, A, "work_torso", kaftan_torso("#7a6a52", "#4a3e30", "#b0a080", main, "#c9b48a", seed=151), seed=151)
    region(img, A, "work_skirt", kaftan_skirt("#7a6a52", "#4a3e30", "#b0a080", main, seed=152), seed=152)
    region(img, A, "fur", fur("#5a3a22", "#a07a50", seed=153), seed=153)
    region(img, A, "cloak", caparison("#8e1f2f", "#d0505a", "#4a0f18", "#c9a24a", "#c9a24a", seed=154, kind="kipchak"),
           seed=154)
    region(img, A, "shield", shield_kipchak(155), seed=155, tile=False)
    region(img, A, "sash", plain_cloth("#8e1f2f", "#d05060", seed=156, vertical=False,
                                       stripes=[("#e6dcc4", 0.3, 5), ("#e6dcc4", 0.7, 5)]), seed=156)
    region(img, A, "saddle", leather_region("#3a2216", "#b58a3c", main, seed=157), seed=157)
    region(img, A, "pennon", pennon(main, "#f2ece0", seed=158), seed=158)
    region(img, A, "plume", hair_strip("#f2ece0", "#ffffff", seed=159), seed=159)
    region(img, A, "tug", hair_strip("#efe8dc", "#ffffff", seed=160), seed=160)
    img.save(path, optimize=True)
    return img


def build_animals(path):
    A = ANIMALS_ATLAS
    img = Image.new("RGB", (A.w, A.h), (40, 40, 40))
    for i, coat in enumerate(HORSE_COATS):
        region(img, A, f"coat{i}", horse_cell(coat, seed=210 + i), seed=210 + i)
    for i, wl in enumerate(WOOL):
        region(img, A, f"wool{i}", sheep_cell(wl, seed=220 + i), seed=220 + i)
    img.save(path, optimize=True)
    return img
