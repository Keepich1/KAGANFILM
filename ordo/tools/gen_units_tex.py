"""Рисованные атласы юнитов (ТЗ 11.1, 11.2): kokand_units.png, kipchak_units.png, animals.png.

Одна «рука» с остальными текстурами (tools/paint.py): подмалёвок, мазки по форме складок,
нарисованный свет сверху (тёплый) и тень снизу (холодная), кант, орнамент.
Атлас стороны — один материал на юнита (ТЗ 11.5), конь нарисован в каждом атласе.

Цвета (ТЗ 11.2 — цвет стороны 20–30 % силуэта):
    Коканд — халаты природных красок (икат-адрас, полосатая алача, индиго, охра, ореховый
             коричневый); бирюза и изумруд — камзул сарбоза поверх халата, кулах чалмы, кушак,
             знамя, у деҳқона — дўппи, кушак, обшлага и кайма;
    кыпчаки — некрашеные войлок, шерсть, кожа, овчина и киноварь в акцентах: плащ-накидка,
             попона, вымпел, кушак, отворот калпака, обшлага и кайма халата.
Красный — только у кыпчаков, бирюза — только у Коканда: стороны не путаются и с RTS-камеры.

Разметка (2048²). Полосы вариантов идут через 512 px по u (variant_du = 0.25): шейдер толпы
сдвигает UV на вариант по w экземпляра (COLOR.b = 1 — масть коня и одежда, 0.5 — голова):
    y    0– 512  coat0..3                 масть коня (тело, шея, голова, ноги, грива, хвост, копыта)
    y  512– 768  hat0..3 | face0..3       шапка 256² и лицо 256² — четыре «человека»
    y  768–1280  torso/skirt/sleeve/trousers/sash/shirt 0..3 — четыре халата одной стороны
    y 1280–2048  постоянные области: знамя, попона, кожа, металл, дерево, офицерский кафтан
                 (у кыпчаков — ламеллярный доспех), щит, плащ, кисти рук, сёдла, вымпел …
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image

from gen_units_kit import Atlas
from paint import Canvas, ram_horn, rhomb, spiral_points
from palette import KIPCHAK, KOKAND, MATERIAL, rgb8

VARIANT_DU = 0.25


def _layout():
    L = {}
    for k in range(4):
        x = 512 * k
        L[f"coat{k}"] = (x, 0, 512, 512)
        L[f"hat{k}"] = (x, 512, 256, 256)
        L[f"face{k}"] = (x + 256, 512, 256, 256)
        L[f"torso{k}"] = (x, 768, 256, 256)
        L[f"skirt{k}"] = (x + 256, 768, 256, 256)
        L[f"sleeve{k}"] = (x, 1024, 256, 128)
        L[f"trousers{k}"] = (x, 1152, 256, 128)
        L[f"sash{k}"] = (x + 256, 1024, 256, 128)
        L[f"shirt{k}"] = (x + 256, 1152, 256, 128)
    L.update({
        "banner": (0, 1280, 512, 512), "caparison": (512, 1280, 512, 512),
        "leather": (1024, 1280, 512, 256), "metal": (1024, 1536, 512, 128), "wood": (1024, 1664, 512, 128),
        "torsoX": (1536, 1280, 512, 256), "skirtX": (1536, 1536, 256, 256), "sleeveX": (1792, 1536, 256, 128),
        "mail": (1792, 1664, 256, 128),
        "shield": (0, 1792, 256, 256), "cloak": (256, 1792, 256, 256),
        "hand": (512, 1792, 128, 128), "flask": (640, 1792, 128, 128), "plume": (512, 1920, 256, 128),
        "saddle": (768, 1792, 256, 128), "pennon": (768, 1920, 256, 128),
        "fur": (1024, 1792, 256, 128), "tug": (1024, 1920, 256, 128),
        "saddlecloth": (1280, 1792, 512, 256), "hatx": (1792, 1792, 256, 256),
    })
    return L


KOKAND_ATLAS = Atlas("kokand_units", 2048, 2048, _layout())
KIPCHAK_ATLAS = Atlas("kipchak_units", 2048, 2048, _layout())
ANIMALS_ATLAS = Atlas("animals", 2048, 1024, {
    "coat0": (0, 0, 512, 512), "coat1": (512, 0, 512, 512), "coat2": (1024, 0, 512, 512), "coat3": (1536, 0, 512, 512),
    "wool0": (0, 512, 512, 512), "wool1": (512, 512, 512, 512), "wool2": (1024, 512, 512, 512), "wool3": (1536, 512, 512, 512),
})

# Доли внутри ячейки коня (512×512)
HORSE_SUB = {"body": (0, 0, 1, 0.44), "neck": (0, 0.44, 0.5, 0.62), "head": (0.5, 0.44, 1, 0.62),
             "legs": (0, 0.62, 1, 0.8), "mane": (0, 0.8, 0.5, 1), "tail": (0.5, 0.8, 0.8, 1),
             "hoof": (0.8, 0.8, 1, 0.9), "ear": (0.8, 0.9, 1, 1)}
# Доли внутри ячейки овцы: тело, голова, ноги, хвост
SHEEP_SUB = {"body": (0, 0, 1, 0.5), "head": (0, 0.5, 0.5, 0.75), "legs": (0.5, 0.5, 1, 0.75),
             "tail": (0, 0.75, 0.5, 1), "face": (0.5, 0.75, 1, 1)}
# Доли внутри полос металла, дерева, кожи
METAL_SUB = {"gold": (0, 0, 0.25, 1), "steel": (0.25, 0, 0.5, 1), "iron": (0.5, 0, 0.75, 1), "brass": (0.75, 0, 1, 1)}
WOOD_SUB = {"walnut": (0, 0, 0.5, 1), "shaft": (0.5, 0, 1, 1)}
LEATHER_SUB = {"boot": (0, 0, 0.5, 1), "belt": (0.5, 0, 0.75, 1), "felt": (0.75, 0, 1, 1)}
# Голова (ячейка face): цилиндрическая развёртка вокруг центра головы, u = 0.5 — лицо,
# v — высота от HEAD_Y[0] (низ подбородка) до HEAD_Y[1] (темя), метры от центра головы.
HEAD_Y = (-0.135, 0.125)
# Шапка (ячейка hat, доли по v сверху вниз): верх (кулах / тулья) и низ (витки чалмы / отворот)
HAT_SPLIT = 0.32


# ---------------------------------------------------------------- цвет

def _mix(a, b, t):
    a, b = np.array(rgb8(a), float), np.array(rgb8(b), float)
    c = a * (1 - t) + b * t
    return "#%02x%02x%02x" % tuple(int(np.clip(v, 0, 255)) for v in c)


def _shade(c, k):
    a = np.array(rgb8(c), float) * k
    return "#%02x%02x%02x" % tuple(int(np.clip(v, 0, 255)) for v in a)


def _arr(c):
    return np.array(rgb8(c), float)


# ---------------------------------------------------------------- общие приёмы

def region(img: Image.Image, atlas: Atlas, name, painter, seed=0, ss=2, tile=True, base="#808080"):
    x, y, w, h = atlas.regions[name]
    c = Canvas(w, h, base=base, ss=ss, tile=tile, seed=seed)
    painter(c, w, h)
    img.paste(c.image(), (x, y))


def vgrad(c: Canvas, top_k=1.12, bottom_k=0.78, y0=0.0, y1=1.0):
    """Нарисованный свет: верх светлее, низ темнее (множитель по высоте, доли y0..y1 области)."""
    arr = np.asarray(c.img, dtype=np.float64)
    H = arr.shape[0]
    t = np.clip((np.linspace(0, 1, H) - y0) / max(y1 - y0, 1e-6), 0, 1)[:, None, None]
    c._blend(arr * (top_k + (bottom_k - top_k) * t))


def blob(c: Canvas, cx, cy, rx, ry, color, alpha=0.5, power=2.0):
    """Мягкое пятно цвета (растушёвка без края): гауссов спад от центра (cx, cy) с радиусами rx, ry."""
    arr = np.asarray(c.img, dtype=np.float64)
    H, W = arr.shape[:2]
    ss = c.ss
    yy = (np.arange(H)[:, None] + 0.5) / ss
    xx = (np.arange(W)[None, :] + 0.5) / ss
    d = ((xx - cx) / max(rx, 1e-6)) ** 2 + ((yy - cy) / max(ry, 1e-6)) ** 2
    m = alpha * np.exp(-0.5 * d ** (power / 2.0) * 2.2)
    col = _arr(color)[None, None, :]
    c._blend(arr * (1 - m[..., None]) + col * m[..., None])


def hgrad(c: Canvas, fn):
    """Лепка по u (вокруг формы): множитель fn(u) 0..1 → k."""
    arr = np.asarray(c.img, dtype=np.float64)
    u = np.linspace(0, 1, arr.shape[1])
    c._blend(arr * np.asarray(fn(u))[None, :, None])


def temperature(c: Canvas, w, h, warm="#ffb070", cool="#3a5a8a", n=200, alpha=(0.05, 0.14), split=0.45):
    """Свет и тень цветом: тёплые мазки сверху (низкое солнце), холодные снизу (небо в тени)."""
    c.strokes(n, [warm, _mix(warm, "#ffe0b0", 0.4)], length=(w * 0.05, w * 0.15), width=(w * 0.015, w * 0.04),
              angle=90, angle_jitter=25, alpha=alpha, region=(0, 0, w, h * split))
    c.strokes(n, [cool, _mix(cool, "#203048", 0.4)], length=(w * 0.05, w * 0.15), width=(w * 0.015, w * 0.04),
              angle=90, angle_jitter=25, alpha=alpha, region=(0, h * (1 - split), w, h))


def folds(c: Canvas, w, h, dark, light, n=40, vertical=True, length=(0.35, 0.9), width=(0.025, 0.06),
          alpha=(0.18, 0.4), flare=0.0, region=None, ang=None):
    """Складки ткани: длинные мазки тени и света вдоль ткани (ширина — доля w)."""
    x0, y0, x1, y1 = region or (0, 0, w, h)
    rs = c.rs
    for i in range(n):
        x = rs.uniform(x0, x1)
        L = rs.uniform(*length) * (y1 - y0)
        yc = rs.uniform(y0 + L * 0.3, y1 - L * 0.2)
        wd = rs.uniform(*width) * w * (1 + flare * (yc - y0) / max(y1 - y0, 1))
        col = dark if i % 2 == 0 else light
        a = ang(x / w) if ang else (90 + rs.normal(0, 4) if vertical else rs.normal(0, 5))
        c._stroke(x, yc, math.radians(a), L, wd, _arr(col), rs.uniform(*alpha), rs.normal(0, 0.15), 1, 0.35)


def trim(c: Canvas, pts, color, width, edge=None, alpha=1.0, seed=0):
    """Кант: полоса цвета и тонкая тёмная кромка."""
    c.line(pts, width, color, alpha, wobble=0.4, seed=seed)
    if edge:
        p = np.asarray(pts, float)
        c.line(p + [0, width * 0.55], max(1.0, width * 0.18), edge, alpha * 0.8, wobble=0.3, seed=seed + 1)
        c.line(p - [0, width * 0.55], max(1.0, width * 0.18), edge, alpha * 0.8, wobble=0.3, seed=seed + 2)


def vtrim(c: Canvas, x, h, color, width, edge=None, seed=0, y0=-4, y1=None):
    y1 = h + 4 if y1 is None else y1
    c.line([(x, y0), (x, y1)], width, color, 1.0, wobble=0.4, seed=seed)
    if edge:
        for s in (-1, 1):
            c.line([(x + s * width * 0.55, y0), (x + s * width * 0.55, y1)], max(1.0, width * 0.18), edge, 0.8,
                   wobble=0.3, seed=seed + 3 + s)


def stitch_band(c: Canvas, y, w, color, step=7.0, r=1.2, alpha=0.85):
    for x in np.arange(step / 2, w, step):
        c.ellipse(x, y, r, r * 0.8, color, alpha)


def feather_columns(c: Canvas, amp=3.0, group=2.0, seed=0, alpha_mask=None):
    """Икат: нити основы окрашены до тканья, края узора «рвутся» по вертикали —
    каждый столбик пикселей сдвигается вверх-вниз на свою долю (бесшовно по v)."""
    arr = np.asarray(c.img, dtype=np.float64).copy()
    H, W = arr.shape[:2]
    rs = np.random.default_rng(seed)
    g = max(1, int(group * c.ss))
    n = W // g + 1
    offs = np.round(rs.normal(0, amp * c.ss, n)).astype(int)
    out = arr.copy()
    for i in range(n):
        x0, x1 = i * g, min((i + 1) * g, W)
        if x0 >= W:
            break
        out[:, x0:x1] = np.roll(arr[:, x0:x1], offs[i], axis=0)
    c._blend(out)


def cloth_ground(c: Canvas, w, h, main, light, dark, seed=0, cell=0.12):
    c.underpaint([_shade(main, 0.88), main, _mix(main, light, 0.16)], cell=max(8, int(w * cell)), seed=seed)
    c.strokes(int(w * 1.1), [main, _shade(main, 0.9), _mix(main, light, 0.2)], length=(w * 0.03, w * 0.09),
              width=(w * 0.01, w * 0.025), angle=90, angle_jitter=14, alpha=(0.12, 0.3))


# ---------------------------------------------------------------- ткани: узоры

def ikat_motifs(c: Canvas, w, h, ground, motif, inner, outline=None, cols=6, period=0.34, seed=0, kind="diamond"):
    """Адрас (икат): столбцы ромбов, «гребешков» и стрел, края узора рваные (feather_columns)."""
    c.rect(0, 0, w, h, ground)
    rs = np.random.default_rng(seed)
    cw = w / cols
    ph = h * period
    for i in range(cols):
        cx = (i + 0.5) * cw
        off = (i % 2) * ph * 0.5
        y = -ph + off
        while y < h + ph:
            if kind == "diamond":
                dw, dh = cw * 0.42, ph * 0.42
                pts = [(cx, y - dh), (cx + dw, y), (cx, y + dh), (cx - dw, y)]
                c.polygon(pts, motif, 0.97, wobble=0.4, seed=int(rs.integers(1 << 20)))
                pts = [(cx, y - dh * 0.5), (cx + dw * 0.45, y), (cx, y + dh * 0.5), (cx - dw * 0.45, y)]
                c.polygon(pts, inner, 0.97, wobble=0.3, seed=int(rs.integers(1 << 20)))
                if outline:
                    c.ellipse(cx, y, cw * 0.06, ph * 0.05, outline, 0.9)
                # «гребешки» между ромбами
                for s in (-1, 1):
                    c.polygon([(cx + s * cw * 0.5, y + ph * 0.5 - ph * 0.12), (cx + s * cw * 0.34, y + ph * 0.5),
                               (cx + s * cw * 0.5, y + ph * 0.5 + ph * 0.12)], inner, 0.9, wobble=0.3)
            elif kind == "arrow":
                aw, ah = cw * 0.4, ph * 0.3
                for k in range(2):
                    yy = y + k * ah * 0.9
                    c.polygon([(cx - aw, yy + ah * 0.5), (cx, yy - ah * 0.2), (cx + aw, yy + ah * 0.5),
                               (cx + aw * 0.6, yy + ah * 0.62), (cx, yy + ah * 0.2), (cx - aw * 0.6, yy + ah * 0.62)],
                              motif if k == 0 else inner, 0.95, wobble=0.4)
            else:  # «бодом» — капля-миндаль
                c.ellipse(cx, y, cw * 0.3, ph * 0.3, motif, 0.95)
                c.ellipse(cx + cw * 0.08, y - ph * 0.06, cw * 0.14, ph * 0.14, inner, 0.95)
            y += ph
        # тонкие полосы между столбцами
        c.line([(i * cw, -4), (i * cw, h + 4)], max(1.2, cw * 0.06), inner, 0.85, wobble=0.5, seed=seed + i)
    feather_columns(c, amp=h * 0.012, group=w * 0.008, seed=seed)


def stripes_alacha(c: Canvas, w, h, ground, bands, seed=0, repeat=4):
    """Алача: узкие продольные полосы (u — поперёк полос)."""
    c.rect(0, 0, w, h, ground)
    rw = w / repeat
    for r in range(repeat):
        for col, frac, width in bands:
            x = r * rw + frac * rw
            c.line([(x, -4), (x, h + 4)], max(1.0, width * w / 256), col, 0.95, wobble=0.35, seed=seed + r * 7)


def plain_weave(c: Canvas, w, h, main, light, dark, seed=0, pin=None, pin_step=0.06):
    cloth_ground(c, w, h, main, light, dark, seed)
    if pin:
        for x in np.arange(pin_step * w * 0.5, w, pin_step * w):
            c.line([(x, -4), (x, h + 4)], max(1.0, w / 256), pin, 0.55, wobble=0.4, seed=int(x))


def felt_ground(c: Canvas, w, h, felt, shade, light="#ffffff", seed=0):
    """Войлок: мягкие пятна, короткие разнонаправленные мазки, без продольной нити."""
    c.underpaint([shade, felt, _mix(felt, light, 0.25)], cell=max(8, int(w * 0.08)), seed=seed)
    c.strokes(int(w * 2.2), [felt, _shade(felt, 0.92), _mix(felt, light, 0.3)], length=(w * 0.02, w * 0.06),
              width=(w * 0.01, w * 0.025), angle=0, angle_jitter=90, alpha=(0.12, 0.3))


def finish_cloth(c: Canvas, w, h, base, seed=0, light_mix=0.45, fold_n=34, vertical=True, top=1.14, bottom=0.72,
                 dust=None, ang=None):
    """Отделка ткани: складки тенью и светом, тёплый верх и холодный низ, пыль у подола."""
    folds(c, w, h, _shade(base, 0.58), _mix(base, "#fff4dc", light_mix), n=fold_n, vertical=vertical, ang=ang)
    temperature(c, w, h, n=int(w * 0.6))
    vgrad(c, top, bottom)
    if dust:
        c.strokes(int(w * 0.6), [dust, _shade(dust, 0.85)], length=(w * 0.04, w * 0.12), width=(w * 0.02, w * 0.045),
                  angle=90, angle_jitter=30, alpha=(0.06, 0.16), region=(0, h * 0.72, w, h))
    c.grain(0.03)


# ---------------------------------------------------------------- халаты (развёртки — см. gen_units)

def robe_torso(cloth, base, trimc, edge, lining=None, collar=None, seed=0, open_front=True, emb=None, placket=None,
               placket_w=0.055, placket_orn=None):
    """Торс халата: u вокруг (0.5 — перёд), картинка вверх — плечи.
    cloth(c, w, h) — узор ткани; base — его средний цвет (для складок и света).
    placket — широкая полоса цвета стороны по краю запаха и вороту (войлочная аппликация у кыпчаков,
    вышитая планка-яқа у деҳқона): крупное пятно стороны на груди, видное спереди (ТЗ 11.2)."""
    def p(c: Canvas, w, h):
        cloth(c, w, h)
        xc = w * 0.5

        def ang(u):  # складки: на груди наискось от плеч к поясу, на спине отвесно
            side = 1 if u > 0.5 else -1
            return 90 + side * 22 * max(0.0, 1 - abs(u - 0.5) * 4)
        folds(c, w, h, _shade(base, 0.55), _mix(base, "#fff4dc", 0.32), n=46, ang=ang, length=(0.25, 0.6))
        # поперечные складки у пояса (халат подпоясан)
        c.strokes(int(w * 0.35), [_shade(base, 0.55), _mix(base, "#fff4dc", 0.35)], length=(w * 0.05, w * 0.12),
                  width=(w * 0.012, w * 0.025), angle=0, angle_jitter=12, alpha=(0.2, 0.4),
                  region=(0, h * 0.86, w, h))
        temperature(c, w, h, n=int(w * 0.7))
        vgrad(c, 1.16, 0.74)
        # свет на груди и лопатках, тень под мышками (u ≈ 0.25 / 0.75 у верха)
        c.strokes(int(w * 0.3), [_mix(base, "#ffe6c0", 0.5)], length=(w * 0.04, w * 0.1), width=(w * 0.015, w * 0.035),
                  angle=0, angle_jitter=30, alpha=(0.08, 0.2), region=(w * 0.3, h * 0.08, w * 0.7, h * 0.4))
        for ux in (0.25, 0.75):
            c.ellipse(w * ux, h * 0.28, w * 0.06, h * 0.12, _shade(base, 0.45), 0.35)
        if open_front:
            # запах: левая пола поверх правой, тонкая полоса подклада/рубахи и кант по краю
            if lining:
                c.polygon([(xc - w * 0.02, 0), (xc + w * 0.035, 0), (xc + w * 0.012, h), (xc - w * 0.01, h)],
                          lining, 0.95, wobble=0.4)
            if placket:
                pw = w * placket_w
                for s, x0 in ((1, xc + w * 0.035), (-1, xc - w * 0.02)):
                    pts = [(x0, -4), (x0 + s * pw * 1.15, -4), (x0 + s * pw, h + 4), (x0, h + 4)]
                    c.polygon(pts, placket, 0.97, wobble=0.3, seed=seed + 70 + s)
                    c.strokes(int(w * 0.12), [_shade(placket, 0.75), _mix(placket, "#ffffff", 0.22)],
                              length=(h * 0.04, h * 0.1), width=(w * 0.004, w * 0.01), angle=90, angle_jitter=10,
                              alpha=(0.2, 0.4), region=(min(x0, x0 + s * pw), 0, max(x0, x0 + s * pw), h))
                    if placket_orn:
                        for yy in np.arange(h * 0.16, h * 0.92, h * 0.19):
                            ram_horn(c, x0 + s * pw * 0.52, yy, pw * 0.42, placket_orn, max(1.2, w * 0.004), 0.85,
                                     seed=int(yy) + s)
                    c.line([(x0 + s * pw * 1.15, -4), (x0 + s * pw, h + 4)], max(1.2, w * 0.005), edge, 0.7,
                           wobble=0.3, seed=seed + 74 + s)
            for s, k in ((1, 1.0), (-1, 0.55)):
                vtrim(c, xc + s * w * 0.035 * k, h, trimc, max(2.0, w * 0.026), edge, seed=seed + s)
            # тень от наложенной полы
            c.line([(xc + w * 0.055, -4), (xc + w * 0.05, h + 4)], max(1.5, w * 0.02), _shade(base, 0.45), 0.5,
                   wobble=0.5, seed=seed + 3)
        if emb:
            for yy in np.linspace(h * 0.2, h * 0.75, 5):
                for s in (-1, 1):
                    c.ellipse(xc + s * w * 0.075, yy, w * 0.012, w * 0.012, emb, 0.9)
        # ворот-стойка
        trim(c, [(-4, h * 0.035), (w + 4, h * 0.035)], collar or placket or trimc, max(3.0, h * (0.085 if placket else 0.06)),
             edge, seed=seed + 5)
        c.grain(0.03)
    return p


def vest_torso(cloth, base, vest, braid, edge, lining=None, seed=0):
    """Камзул без рукавов поверх халата (сарбоз Коканда): u вокруг (0.5 — перёд), верх — ворот.
    Камзул — цвет стороны (бирюза, изумруд), стёганый, с золотым галуном по краю и петлями-застёжками;
    в треугольном вырезе на груди виден халат природной краски (икат, алача) и ворот рубахи.
    Большое сплошное пятно цвета стороны на плечах и спине читается с камеры RTS (ТЗ 11.2)."""
    def p(c: Canvas, w, h):
        cloth(c, w, h)                                         # халат под камзулом (виден в вырезе)
        folds(c, w, h, _shade(base, 0.55), _mix(base, "#fff4dc", 0.32), n=20, length=(0.25, 0.6))
        xc, vy = w * 0.5, h * 0.5                              # низ выреза — середина груди
        top_w = w * 0.085
        left = [(-6, -6), (xc - top_w, -6), (xc - w * 0.012, vy), (xc - w * 0.004, h + 6), (-6, h + 6)]
        right = [(xc + top_w, -6), (w + 6, -6), (w + 6, h + 6), (xc + w * 0.004, h + 6), (xc + w * 0.012, vy)]
        vl, vd = _mix(vest, "#ffffff", 0.22), _shade(vest, 0.62)
        for k, poly in enumerate((left, right)):
            c.polygon(poly, vest, 1.0, wobble=0.25, seed=seed + k)
        # бархатистый ворс: мазки поперёк стёжки, свет на груди и лопатках
        c.strokes(int(w * 1.2), [vest, vl, vd], length=(w * 0.02, w * 0.06), width=(w * 0.01, w * 0.025),
                  angle=90, angle_jitter=18, alpha=(0.12, 0.3))
        # стёжка: продольные строчки (на камзуле — не по вырезу)
        for x in np.arange(w * 0.03, w, w / 18):
            if abs(x - xc) < top_w + w * 0.02:
                continue
            c.line([(x, h * 0.04), (x + w * 0.004, h)], max(1.0, w * 0.006), vd, 0.55, wobble=0.5, seed=int(x) + seed)
        # объём: под мышками и по бокам глубже, перёд и спина светлее
        hgrad(c, lambda u: 0.8 + 0.26 * np.cos((u - 0.5) * 4 * np.pi) ** 2)
        for ux in (0.25, 0.75):
            blob(c, w * ux, h * 0.35, w * 0.07, h * 0.22, vd, 0.45)
        blob(c, xc, h * 0.3, w * 0.12, h * 0.16, vl, 0.25)
        temperature(c, w, h, n=int(w * 0.5))
        vgrad(c, 1.14, 0.78)
        # галун по вырезу и по низу, застёжки-петли спереди
        for s_ in (-1, 1):
            c.line([(xc + s_ * top_w, -4), (xc + s_ * w * 0.012, vy), (xc + s_ * w * 0.004, h + 4)], max(2.0, w * 0.018),
                   braid, 0.95, wobble=0.3, seed=seed + 10 + s_)
            c.line([(xc + s_ * (top_w + w * 0.012), -4), (xc + s_ * w * 0.024, vy)], max(1.0, w * 0.006), edge, 0.6,
                   wobble=0.3, seed=seed + 12 + s_)
        for yy in np.linspace(vy + h * 0.06, h * 0.93, 4):
            c.line([(xc - w * 0.03, yy), (xc + w * 0.03, yy)], max(1.5, h * 0.016), braid, 0.9, wobble=0.2, seed=int(yy))
            c.ellipse(xc, yy, w * 0.008, h * 0.012, _shade(braid, 0.6), 0.9)
        trim(c, [(-4, h - h * 0.025), (w + 4, h - h * 0.025)], braid, max(2.0, h * 0.03), edge, seed=seed + 20)
        # пройма: галун дугой у плеча (сверху у u = 0.25 / 0.75 рукав уходит под плечо камзула)
        for ux in (0.25, 0.75):
            pts = [(w * ux + w * 0.07 * math.sin(t), h * (0.04 + 0.34 * (1 - math.cos(t)) / 2)) for t in np.linspace(-1.6, 1.6, 9)]
            c.line(pts, max(1.5, w * 0.008), braid, 0.6, wobble=0.3, seed=seed + int(ux * 100))
        # ворот рубахи и халата в вырезе
        if lining:
            c.polygon([(xc - top_w * 0.55, -4), (xc + top_w * 0.55, -4), (xc, h * 0.2)], lining, 0.9, wobble=0.3)
        trim(c, [(xc - top_w, h * 0.03), (xc + top_w, h * 0.03)], braid, max(2.0, h * 0.04), edge, seed=seed + 30)
        c.grain(0.03)
    return p


def robe_skirt(cloth, base, trimc, edge, seed=0, hem_w=0.05, dust="#8a7458", ornament=None, band=None, band_w=0.1,
               band_trim=None):
    """Подол: u — по полукругу (0 — передний край), картинка вниз — к подолу.
    band — широкая кайма цвета стороны по низу (доля band_w высоты; у сарбозов — бирюза,
    в модели её кольца помечены цветом стороны, gen_units.human_legs hem_side)."""
    def p(c: Canvas, w, h):
        _robe_skirt_body(c, w, h)
        if band:
            y0 = h * (1 - band_w)
            c.rect(-4, y0, w + 4, h + 4, band)
            c.strokes(int(w * 0.3), [_shade(band, 0.75), _mix(band, "#ffffff", 0.25)], length=(w * 0.04, w * 0.1),
                      width=(h * 0.006, h * 0.016), angle=0, angle_jitter=10, alpha=(0.25, 0.5), region=(0, y0, w, h))
            for x in np.arange(w * 0.04, w, w * 0.08):                      # складки и на кайме
                c.line([(x, y0), (x + w * 0.01, h)], max(1.5, w * 0.012), _shade(band, 0.55), 0.45, seed=int(x))
            trim(c, [(-4, y0), (w + 4, y0)], band_trim or trimc, max(2.0, h * 0.014), edge, seed=seed + 7)
            vgrad(c, 1.0, 0.85, 1 - band_w, 1.0)
            c.strokes(int(w * 0.3), [dust], length=(w * 0.04, w * 0.1), width=(w * 0.02, w * 0.04), angle=90,
                      angle_jitter=30, alpha=(0.05, 0.12), region=(0, h * (1 - band_w * 0.5), w, h))

    def _robe_skirt_body(c, w, h):
        cloth(c, w, h)
        for i in range(30):  # тяжёлые складки, к подолу шире
            x = (i + c.rs.uniform(-0.3, 0.3)) / 30 * w
            col = _shade(base, 0.5) if i % 2 else _mix(base, "#fff4dc", 0.4)
            L = c.rs.uniform(0.5, 1.0) * h
            c._stroke(x, h - L * 0.5 + c.rs.uniform(0, h * 0.1), math.radians(90 + c.rs.normal(0, 3)), L,
                      c.rs.uniform(0.03, 0.06) * w, _arr(col), c.rs.uniform(0.25, 0.48), c.rs.normal(0, 0.1), 1, -0.6)
        # широкие мягкие тени глубоких складок поверх узора: икат «ломается» в складках и не выглядит обоями
        for i in range(12):
            x = (i + 0.5 + c.rs.uniform(-0.25, 0.25)) / 12 * w
            L = c.rs.uniform(0.55, 1.0) * h
            c._stroke(x, h - L * 0.5, math.radians(90 + c.rs.normal(0, 2)), L, c.rs.uniform(0.05, 0.085) * w,
                      _arr(_shade(base, 0.42)), c.rs.uniform(0.16, 0.28), c.rs.normal(0, 0.08), 1, -0.4)
        temperature(c, w, h, split=0.4, n=int(w * 0.6))
        vgrad(c, 1.08, 0.62)
        c.strokes(int(w * 0.7), [dust, _shade(dust, 0.85)], length=(w * 0.04, w * 0.12), width=(w * 0.02, w * 0.045),
                  angle=90, angle_jitter=30, alpha=(0.06, 0.16), region=(0, h * 0.7, w, h))
        trim(c, [(-4, h * (1 - hem_w)), (w + 4, h * (1 - hem_w))], trimc, max(3.0, h * hem_w * 1.3), edge, seed=seed + 1)
        if ornament:
            for x in np.arange(w * 0.06, w, w * 0.12):
                rhomb(c, x, h * (1 - hem_w * 2.6), w * 0.025, h * 0.03, ornament, 0.9)
        vtrim(c, w * 0.012, h, trimc, max(2.0, w * 0.026), edge, seed=seed + 2)   # передний край полы
        c.grain(0.03)
    return p


def robe_sleeve(cloth, base, cuff, cuff_edge, seed=0, cuff_w=0.13):
    """Рукав: u вокруг, v — от плеча (верх) к запястью (низ, обшлаг). Верхняя половина — плечо,
    нижняя — предплечье: складки на сгибе локтя (середина)."""
    def p(c: Canvas, w, h):
        cloth(c, w, h)
        c.strokes(int(w * 0.5), [_shade(base, 0.55), _mix(base, "#fff4dc", 0.4)], length=(w * 0.08, w * 0.2),
                  width=(w * 0.02, w * 0.04), angle=0, angle_jitter=20, alpha=(0.22, 0.42),
                  region=(0, h * 0.38, w, h * 0.66))
        folds(c, w, h, _shade(base, 0.6), _mix(base, "#fff4dc", 0.35), n=18, length=(0.2, 0.45))
        # лепка: внутренняя сторона рукава (u ≈ 0 и 1 — к телу) темнее
        hgrad(c, lambda u: 0.8 + 0.28 * np.sin(u * np.pi) ** 0.8)
        temperature(c, w, h, n=int(w * 0.4))
        vgrad(c, 1.12, 0.84)
        y = h * (1 - cuff_w * 0.55)
        c.rect(0, h * (1 - cuff_w), w, h, cuff)
        c.strokes(int(w * 0.2), [_shade(cuff, 0.8), _mix(cuff, "#ffffff", 0.25)], length=(w * 0.04, w * 0.1),
                  width=(w * 0.01, w * 0.02), angle=0, angle_jitter=10, alpha=(0.2, 0.4), region=(0, h * (1 - cuff_w), w, h))
        c.line([(-4, h * (1 - cuff_w)), (w + 4, h * (1 - cuff_w))], max(1.5, h * 0.022), cuff_edge, 0.9, seed=seed)
        stitch_band(c, y, w, _mix(cuff_edge, "#ffffff", 0.5), step=w * 0.05, r=max(1.0, h * 0.01))
        c.grain(0.03)
    return p


def trousers(main, light, stripe=None, seed=0):
    def p(c: Canvas, w, h):
        cloth_ground(c, w, h, main, light, _shade(main, 0.6), seed)
        if stripe:
            for x in np.arange(w * 0.04, w, w * 0.085):
                c.line([(x, -4), (x, h + 4)], max(1.0, w / 300), stripe, 0.6, wobble=0.4, seed=int(x))
        folds(c, w, h, _shade(main, 0.55), _mix(main, light, 0.4), n=20)
        c.strokes(int(w * 0.3), [_shade(main, 0.5)], length=(w * 0.05, w * 0.12), width=(w * 0.01, w * 0.03),
                  angle=0, angle_jitter=20, alpha=(0.2, 0.35), region=(0, h * 0.6, w, h))
        vgrad(c, 1.05, 0.7)
        c.grain(0.03)
    return p


def sash(main, light, bands, seed=0):
    """Кушак (цвет стороны): u — вокруг пояса, v — поперёк; полосы и бахрома внизу области."""
    def p(c: Canvas, w, h):
        cloth_ground(c, w, h, main, light, _shade(main, 0.6), seed)
        for col, frac, wd in bands:
            c.line([(-4, frac * h), (w + 4, frac * h)], max(1.2, wd * h), col, 0.95, wobble=0.5, seed=seed + int(frac * 99))
        # складки поперёк: кушак намотан в несколько оборотов
        c.strokes(int(w * 0.5), [_shade(main, 0.55), _mix(main, "#ffffff", 0.3)], length=(w * 0.03, w * 0.08),
                  width=(h * 0.03, h * 0.07), angle=0, angle_jitter=8, alpha=(0.25, 0.45))
        for yy in (h * 0.33, h * 0.66):
            c.line([(-4, yy), (w + 4, yy + 2)], max(1.2, h * 0.025), _shade(main, 0.45), 0.6, wobble=0.6, seed=int(yy))
        vgrad(c, 1.15, 0.8)
        c.grain(0.025)
    return p


# ---------------------------------------------------------------- головы и лица

FACE_DEG = 45.0   # лицо (±45° от носа) занимает половину ширины ячейки: вдвое больше пикселей на черты


def head_u(deg):
    """Угол вокруг головы (0 — нос, + к левому боку юнита, ±180 — затылок) → u ячейки лица.
    Развёртка неравномерная: перёд ±FACE_DEG — u 0.25..0.75, бока и затылок — остальное."""
    d = np.asarray(deg, dtype=np.float64)
    a = np.abs(d)
    u = np.where(a <= FACE_DEG, a / FACE_DEG * 0.25, 0.25 + (a - FACE_DEG) / (180.0 - FACE_DEG) * 0.25)
    return 0.5 + np.sign(d) * u


def head_y(y, h):
    """Высота над центром головы (м) → строка ячейки лица."""
    return (HEAD_Y[1] - y) / (HEAD_Y[1] - HEAD_Y[0]) * h


def head_x(deg, w):
    """Угол вокруг головы (0 — лицо, + к левому боку юнита) → столбец ячейки лица."""
    return float(head_u(deg)) * w


def face(skin, hair, beard="full", eyes="round", age=0.0, brow=None, seed=0, stubble=None, hair_back=True):
    """Лицо на развёртке головы (head_u: перёд ±45° — половина ячейки; v — высота HEAD_Y).
    Живопись крупными массами, как в «Аркейне»: светлые лоб, скулы и спинка носа, тёплая глубокая
    тень глазниц под тяжёлым надбровьем, тень под носом и скулой, холодные виски и шея.
    Брови — густые мазки, глаза — тёмные миндалины в тени с бликом, борода и усы — масса волоса.
    Издали лицо читается тремя пятнами: светлый лоб и скулы, тёмная полоса глаз, тёмная борода.
    beard: full | short | goatee | moustache | droop | none; eyes: round | narrow; age 0..1 — седина."""
    def p(c: Canvas, w, h):
        Y = lambda y: head_y(y, h)  # noqa: E731
        X = lambda a: head_x(a, w)  # noqa: E731
        D = w * 0.25 / FACE_DEG     # пикселей на градус спереди
        M = h / (HEAD_Y[1] - HEAD_Y[0])   # пикселей на метр по высоте
        hairc = _mix(hair, "#cfc9bf", 0.6 * age)
        browc = brow or _mix(hairc, "#140c08", 0.35)
        skin_l = _mix(skin, "#ffdcbc", 0.36)
        skin_d = _mix(skin, "#4a2418", 0.4)
        warm_d = _mix(skin, "#5a1e14", 0.52)       # тёплая тень (глазницы, под носом)
        cool = _mix(skin, "#45506e", 0.42)         # холодная тень (виски, шея)
        c.underpaint([_shade(skin, 0.9), skin, _mix(skin, skin_l, 0.5)], cell=max(8, w // 14), seed=seed)
        c.strokes(int(w * 1.2), [skin, _shade(skin, 0.92), _mix(skin, skin_l, 0.45)], length=(h * 0.02, h * 0.05),
                  width=(w * 0.008, w * 0.016), angle=90, angle_jitter=30, alpha=(0.1, 0.25))
        # лепка: перёд светлее, бока и затылок в тени
        hgrad(c, lambda u: 0.72 + 0.32 * np.exp(-((u - 0.5) / 0.2) ** 2))
        blob(c, X(0), Y(-0.15), w * 0.7, h * 0.05, _mix(skin_d, cool, 0.4), 0.75)          # шея под подбородком
        # светлые массы: лоб, скулы, спинка носа, подбородок
        blob(c, X(0), Y(0.048), 26 * D, 0.03 * M, skin_l, 0.6)
        for s in (-1, 1):
            blob(c, X(s * 22), Y(-0.03), 9 * D, 0.016 * M, skin_l, 0.55)                    # скула
            blob(c, X(s * 26), Y(-0.056), 8 * D, 0.016 * M, _mix(skin, "#c05a44", 0.32), 0.35)  # обветренные щёки
            blob(c, X(s * 40), Y(-0.06), 8 * D, 0.03 * M, cool, 0.45)                        # впалая щека
            blob(c, X(s * 44), Y(0.02), 7 * D, 0.03 * M, cool, 0.4)                          # висок
        blob(c, X(0), Y(-0.11), 9 * D, 0.012 * M, skin_l, 0.35)
        # надбровье и глазницы: широкая тёплая тень под бровями, у переносицы глубже
        blob(c, X(0), Y(0.0), 34 * D, 0.013 * M, _shade(warm_d, 0.9), 0.85)
        for s in (-1, 1):
            blob(c, X(s * 9), Y(0.003), 6 * D, 0.012 * M, _shade(warm_d, 0.7), 0.6)
            blob(c, X(s * 20), Y(-0.013), 9 * D, 0.006 * M, skin_l, 0.25)                    # свет на скуле под глазом
        # уши
        for s in (-1, 1):
            ex = X(s * 82)
            c.ellipse(ex, Y(-0.012), w * 0.016, h * 0.05, _mix(skin, "#d08a6a", 0.2), 0.95)
            c.ellipse(ex + s * w * 0.003, Y(-0.012), w * 0.008, h * 0.03, skin_d, 0.75)
        # волосы на затылке и висках (бритые под шапкой — короткая тёмная щетина)
        if hair_back:
            hb = stubble or hairc
            for s in (-1, 1):
                c.polygon([(X(s * 180), Y(0.13)), (X(s * 62), Y(0.13)), (X(s * 60), Y(0.05)), (X(s * 70), Y(0.0)),
                           (X(s * 96), Y(-0.045)), (X(s * 180), Y(-0.07))], hb, 0.6, wobble=1.0, seed=seed + 3 + s)
            for x0, x1 in ((0, X(-66)), (X(66), w)):
                c.strokes(int(w * 0.4), [_mix(hb, skin, 0.4), _shade(hb, 0.8)], length=(h * 0.01, h * 0.03),
                          width=(w * 0.003, w * 0.008), angle=90, angle_jitter=25, alpha=(0.2, 0.45),
                          region=(x0, Y(0.12), x1, Y(-0.06)))
        # глаза: миндалина в тени, тёмная радужка, тяжёлое верхнее веко, блик
        narrow = eyes == "narrow"
        for s in (-1, 1):
            ex, ey = X(s * 19), Y(-0.002)
            ew, eh = 7.5 * D, (0.0052 if narrow else 0.0068) * M
            c.polygon([(ex - ew, ey + eh * 0.2), (ex - ew * 0.3, ey - eh), (ex + ew * 0.5, ey - eh * 0.9),
                       (ex + ew, ey - eh * 0.1 if narrow else ey), (ex + ew * 0.3, ey + eh), (ex - ew * 0.4, ey + eh)],
                      _mix("#d8c8b4", warm_d, 0.55), 0.85, wobble=0.1)
            c.ellipse(ex - s * ew * 0.1, ey, ew * 0.42, eh * 1.05, "#1a100a", 0.95)
            c.line([(ex - ew * 1.15, ey), (ex - ew * 0.3, ey - eh * 1.35), (ex + ew * 0.5, ey - eh * 1.3),
                    (ex + ew * 1.15, ey - (eh * 0.6 if narrow else eh * 0.2))], max(1.6, eh * 0.75), "#160c06", 0.92,
                   wobble=0.1, seed=seed + 10 + s)
            if narrow:   # эпикантус: складка века у переносицы
                c.line([(ex - s * ew * 1.2, ey + eh * 0.3), (ex - s * ew * 0.6, ey - eh * 0.7)], max(1.0, eh * 0.4),
                       warm_d, 0.6, seed=seed + 12 + s)
            c.ellipse(ex - s * ew * 0.28, ey - eh * 0.35, max(0.8, ew * 0.12), max(0.8, eh * 0.28), "#f4ece0", 0.85)
            # брови: густой мазок от переносицы вверх-наружу и вниз к виску
            bw = 0.0062 * M
            c.line([(X(s * 5), Y(0.014)), (X(s * 13), Y(0.02))], bw * 1.25, browc, 0.95, wobble=0.2, seed=seed + 20 + s)
            c.line([(X(s * 12), Y(0.02)), (X(s * 22), Y(0.022)), (X(s * 31), Y(0.013))], bw, browc, 0.9,
                   wobble=0.2, seed=seed + 22 + s)
            if age > 0.3:   # морщины у глаз
                for k in range(2):
                    c.line([(X(s * 28), Y(-0.004 - k * 0.006)), (X(s * 35), Y(-0.009 - k * 0.009))], max(1.0, h * 0.004),
                           skin_d, 0.5 * age, seed=seed + 30 + k * 2 + s)
        # нос: свет на спинке, тень с одного бока, глубокая тень под кончиком, ноздри
        c.line([(X(-1.0), Y(0.006)), (X(-1.5), Y(-0.038))], 2.6 * D, skin_l, 0.4, seed=seed + 40)
        c.line([(X(5.0), Y(0.004)), (X(7.0), Y(-0.042))], 3.2 * D, warm_d, 0.4, seed=seed + 41)
        blob(c, X(0), Y(-0.052), 7 * D, 0.006 * M, warm_d, 0.75)
        blob(c, X(-0.5), Y(-0.043), 3 * D, 0.007 * M, _mix(skin, "#d07058", 0.4), 0.5)   # кончик теплее
        for s in (-1, 1):
            c.ellipse(X(s * 4.5), Y(-0.049), 1.6 * D, 0.003 * M, "#2a1410", 0.75)
            c.line([(X(s * 9), Y(-0.04)), (X(s * 15), Y(-0.07))], max(1.2, 1.6 * D), skin_d, 0.45,
                   seed=seed + 42 + s)                                                          # носогубная складка
        if age > 0.3:   # морщины на лбу
            for k in range(3):
                c.line([(X(-16), Y(0.04 + k * 0.009)), (X(16), Y(0.041 + k * 0.009))], max(1.0, h * 0.004),
                       skin_d, 0.35 * age, wobble=0.8, seed=seed + 50 + k)
        # рот: тёмная щель, тень под нижней губой
        my = Y(-0.072)
        c.line([(X(-10), my + 1), (X(0), my), (X(10), my + 1)], max(1.4, 0.0042 * M), "#3a140c", 0.9, seed=seed + 60)
        c.line([(X(-6), my + 0.007 * M), (X(6), my + 0.007 * M)], max(1.2, 0.0045 * M), _mix(skin, "#b05a48", 0.35),
               0.55, seed=seed + 61)
        blob(c, X(0), my + 0.014 * M, 7 * D, 0.004 * M, skin_d, 0.4)
        # борода и усы — масса волоса: тёмная основа, мазки прядей вниз, мягкий край
        hs = [_mix(hairc, "#ffffff", 0.18), _shade(hairc, 0.7), hairc, _mix(hairc, skin, 0.3)]
        if beard in ("full", "short"):
            low = -0.135 if beard == "full" else -0.12
            side_top = -0.02 if beard == "full" else -0.04
            pts = [(X(-84), Y(side_top)), (X(-62), Y(-0.05)), (X(-40), Y(-0.066)), (X(-20), Y(-0.08)), (X(-8), Y(-0.083)),
                   (X(8), Y(-0.083)), (X(20), Y(-0.08)), (X(40), Y(-0.066)), (X(62), Y(-0.05)), (X(84), Y(side_top)),
                   (X(80), Y(low)), (X(-80), Y(low))]
            c.polygon(pts, _shade(hairc, 0.9), 0.92, wobble=0.8, seed=seed + 70)
            c.strokes(int(w * 1.3), hs, length=(h * 0.015, h * 0.045), width=(w * 0.004, w * 0.01), angle=90,
                      angle_jitter=18, alpha=(0.35, 0.7), region=(X(-82), Y(-0.05), X(82), Y(low)))
            for xa in np.linspace(-70, 70, 11):    # мягкий край бороды на щеках
                ya = np.interp(abs(xa), [0, 8, 20, 40, 62, 84], [-0.083, -0.083, -0.08, -0.066, -0.05, side_top])
                blob(c, X(xa), Y(ya + 0.004), 6 * D, h * 0.012, _mix(hairc, skin, 0.55), 0.35)
            c.ellipse(X(0), Y(-0.078), 4 * D, h * 0.006, _mix(skin, "#b05a48", 0.3), 0.6)   # губа видна
        if beard == "goatee":
            c.polygon([(X(-12), Y(-0.082)), (X(12), Y(-0.082)), (X(9), Y(-0.125)), (X(0), Y(-0.136)), (X(-9), Y(-0.125))],
                      hairc, 0.92, wobble=0.5)
            c.strokes(int(w * 0.3), hs, length=(h * 0.015, h * 0.035), width=(w * 0.004, w * 0.009), angle=90,
                      angle_jitter=10, alpha=(0.35, 0.65), region=(X(-11), Y(-0.082), X(11), Y(-0.13)))
        if beard in ("full", "short", "goatee", "moustache", "droop"):
            drop = 0.1 if beard == "droop" else 0.08
            for s in (-1, 1):
                c.polygon([(X(s * 1), Y(-0.055)), (X(s * 11), Y(-0.056)), (X(s * 18), Y(-drop + 0.006)),
                           (X(s * 19), Y(-drop)), (X(s * 12), Y(-0.067)), (X(s * 1), Y(-0.063))],
                          _shade(hairc, 0.85), 0.95, wobble=0.3, seed=seed + 80 + s)
                c.line([(X(s * 2), Y(-0.057)), (X(s * 13), Y(-0.061))], max(1.0, 1.4 * D), _mix(hairc, "#ffffff", 0.2),
                       0.5, seed=seed + 82 + s)
        if beard == "none" and stubble:
            c.polygon([(X(-60), Y(-0.05)), (X(-22), Y(-0.082)), (X(22), Y(-0.082)), (X(60), Y(-0.05)), (X(54), Y(-0.12)),
                       (X(-54), Y(-0.12))], _mix(skin, stubble, 0.35), 0.5, wobble=0.8)
        vgrad(c, 1.05, 0.86)
        c.grain(0.02)
    return p


def hands(skin, seed=0):
    """Кулак: u вокруг (0.5 — тыльная сторона с костяшками), v — от запястья (верх) к пальцам."""
    def p(c: Canvas, w, h):
        skin_l = _mix(skin, "#ffd8b4", 0.3)
        skin_d = _mix(skin, "#5a3428", 0.4)
        c.underpaint([_shade(skin, 0.9), skin, skin_l], cell=16, seed=seed)
        hgrad(c, lambda u: 0.78 + 0.3 * np.exp(-((u - 0.5) / 0.22) ** 2))
        for k in range(4):  # пальцы, сжатые в кулак: тёмные щели между ними
            x = w * (0.32 + k * 0.12)
            c.line([(x, h * 0.55), (x, h)], max(1.0, w * 0.018), skin_d, 0.7, seed=seed + k)
            c.ellipse(x + w * 0.06, h * 0.6, w * 0.035, h * 0.03, skin_l, 0.7)          # костяшки
        c.rect(0, 0, w, h * 0.12, skin_d, 0.5)                                         # запястье в тени рукава
        vgrad(c, 0.9, 1.05)
        c.grain(0.02)
    return p


# ---------------------------------------------------------------- шапки (ячейка hat 256²; верх — HAT_SPLIT)

def turban(cloth, shade, stripe=None, cap="#2f8f74", cap_trim="#c9a24a", band=None, seed=0):
    """Чалма вокруг высокого кулаха: верх ячейки — кулах (цвет стороны), ниже — витки ткани
    наискось, глубокие тени между витками, конец ткани с полосами (нижний край ячейки)."""
    def p(c: Canvas, w, h):
        ch = h * HAT_SPLIT
        c.rect(0, 0, w, ch, cap)
        c.strokes(int(w * 0.8), [_shade(cap, 0.8), _mix(cap, "#ffffff", 0.2)], length=(h * 0.04, h * 0.1),
                  width=(w * 0.01, w * 0.025), angle=90, angle_jitter=10, alpha=(0.2, 0.45), region=(0, 0, w, ch))
        for x in np.arange(0, w, w / 8):   # стёганые клинья кулаха и золотая строчка
            c.line([(x, 0), (x, ch)], max(1.0, w * 0.008), _shade(cap, 0.5), 0.7, seed=int(x))
            c.line([(x + w / 16, ch * 0.15), (x + w / 16, ch * 0.9)], max(1.0, w * 0.005), cap_trim, 0.55, seed=int(x) + 1)
        trim(c, [(-4, ch - h * 0.025), (w + 4, ch - h * 0.025)], cap_trim, max(2.0, h * 0.03), _shade(cap_trim, 0.5),
             seed=seed)
        vgrad(c, 1.15, 0.85, 0.0, HAT_SPLIT)
        # витки чалмы
        y0 = ch
        c.rect(0, y0, w, h, cloth)
        n = 7
        bh = (h - y0) / n
        for i in range(n):
            yy = y0 + (i + 0.5) * bh
            pts = [(x, yy + bh * 0.55 * math.sin(x / w * 2 * math.pi + i * 1.7)) for x in np.linspace(-4, w + 4, 28)]
            col = _mix(cloth, shade, 0.1 if i % 2 else 0.0)
            c.line(pts, bh * 0.92, col, 0.95, wobble=1.0, seed=seed + i)
            c.line([(x, y + bh * 0.42) for x, y in pts], max(1.5, bh * 0.2), _shade(shade, 0.85), 0.6, wobble=0.8,
                   seed=seed + 20 + i)                                         # тень под витком
            c.line([(x, y - bh * 0.3) for x, y in pts], max(1.0, bh * 0.12), _mix(cloth, "#ffffff", 0.6), 0.55,
                   wobble=0.6, seed=seed + 30 + i)                             # свет на витке
            if stripe and i % 2 == 0:
                c.line([(x, y - bh * 0.05) for x, y in pts], max(1.0, bh * 0.1), stripe, 0.8, wobble=0.6, seed=seed + 40 + i)
        if band:   # лента цвета стороны: нижний виток (шейдер подсвечивает его как цвет стороны)
            pts = [(x, h - bh * 0.75 + bh * 0.25 * math.sin(x / w * 2 * math.pi)) for x in np.linspace(-4, w + 4, 28)]
            c.line(pts, bh * 1.25, band, 0.97, wobble=0.5, seed=seed + 60)
            c.line([(x, y - bh * 0.5) for x, y in pts], max(1.0, bh * 0.14), cap_trim, 0.85, wobble=0.4, seed=seed + 61)
            c.line([(x, y + bh * 0.2) for x, y in pts], max(1.0, bh * 0.2), _shade(band, 0.6), 0.5, wobble=0.4,
                   seed=seed + 62)
        c.strokes(int(w * 0.6), [_mix(cloth, "#ffffff", 0.4), shade], length=(w * 0.03, w * 0.08),
                  width=(w * 0.008, w * 0.02), angle=-8, angle_jitter=8, alpha=(0.1, 0.25), region=(0, y0, w, h))
        vgrad(c, 1.1, 0.82, HAT_SPLIT, 1.0)
        c.grain(0.02)
    return p


def kalpak(felt, felt_shade, brim, brim_light, seed=0, tassel="#b0392f", emb=None):
    """Войлочный калпак: верх — тулья с клиньями и прострочкой, низ — отворот (бархат),
    кисточка на макушке (самый верх ячейки)."""
    def p(c: Canvas, w, h):
        felt_ground(c, w, h, felt, felt_shade, seed=seed)
        by = h * 0.74
        for k in range(4):   # швы клиньев с вышитой строчкой
            x = (k + 0.5) * w / 4
            c.line([(x, h * 0.05), (x, by)], max(1.5, w * 0.009), _shade(felt_shade, 0.7), 0.8, wobble=0.6, seed=seed + k)
            c.line([(x + w * 0.012, h * 0.05), (x + w * 0.012, by)], max(1.0, w * 0.005), _mix(felt, "#ffffff", 0.5), 0.6,
                   seed=seed + 10 + k)
            if emb:
                for yy in np.linspace(h * 0.12, by * 0.95, 6):
                    c.ellipse(x - w * 0.012, yy, w * 0.006, w * 0.006, emb, 0.8)
        # тень и свет по клиньям
        hgrad(c, lambda u: 0.88 + 0.16 * np.cos(u * 8 * np.pi) ** 2)
        c.rect(0, by, w, h, brim)
        c.strokes(int(w * 0.4), [brim_light, _shade(brim, 0.7)], length=(w * 0.04, w * 0.1), width=(h * 0.01, h * 0.025),
                  angle=0, angle_jitter=8, alpha=(0.2, 0.45), region=(0, by, w, h))
        c.line([(-4, by), (w + 4, by)], max(1.5, h * 0.012), _mix(brim_light, "#ffffff", 0.3), 0.8, seed=seed)
        c.line([(-4, by + h * 0.02), (w + 4, by + h * 0.02)], max(1.5, h * 0.02), _shade(felt_shade, 0.5), 0.55,
               seed=seed + 1)                                                 # тень отворота на тулье
        for x in np.arange(w * 0.06, w, w * 0.125):
            c.line([(x, by + h * 0.05), (x + w * 0.02, h - h * 0.04)], max(1.0, w * 0.006), brim_light, 0.6, seed=int(x))
        c.rect(0, 0, w, h * 0.05, tassel)
        vgrad(c, 1.12, 0.84)
        c.grain(0.02)
    return p


def helmet(steel, gold, tassel, seed=0):
    """Шлем (ячейка hatx): тулья — сталь с золочёным налобным венцом и рёбрами,
    верх ячейки — кисть цвета стороны, низ — бармица (кольчуга)."""
    def p(c: Canvas, w, h):
        c.rect(0, 0, w, h, steel)
        c.strokes(int(w * 0.6), [_shade(steel, 0.7), _mix(steel, "#ffffff", 0.3)], length=(h * 0.08, h * 0.2),
                  width=(w * 0.01, w * 0.03), angle=90, angle_jitter=8, alpha=(0.25, 0.5), region=(0, h * 0.1, w, h * 0.62))
        for x in np.arange(0, w, w / 6):   # рёбра-накладки с заклёпками
            c.line([(x, h * 0.1), (x, h * 0.6)], max(2.0, w * 0.02), gold, 0.9, seed=int(x))
            for yy in np.linspace(h * 0.15, h * 0.55, 4):
                c.ellipse(x, yy, w * 0.008, w * 0.008, _mix(gold, "#ffffff", 0.4), 0.9)
        hgrad(c, lambda u: 0.8 + 0.35 * np.abs(np.sin(u * 3 * np.pi)) ** 3)   # блик по граням
        trim(c, [(-4, h * 0.58), (w + 4, h * 0.58)], gold, max(3.0, h * 0.05), _shade(gold, 0.45), seed=seed)
        for x in np.arange(w * 0.04, w, w * 0.08):
            c.ellipse(x, h * 0.58, w * 0.01, w * 0.01, _shade(gold, 0.6), 0.8)
        # бармица: ряды колец
        y0 = h * 0.64
        c.rect(0, y0, w, h, _shade(steel, 0.55))
        for r, yy in enumerate(np.arange(y0 + 3, h, h * 0.03)):
            for x in np.arange((r % 2) * w * 0.015, w, w * 0.03):
                c.ellipse(x, yy, w * 0.012, h * 0.011, _mix(steel, "#ffffff", 0.15), 0.85)
                c.ellipse(x, yy, w * 0.006, h * 0.005, _shade(steel, 0.35), 0.9)
        vgrad(c, 1.0, 0.65, 0.64, 1.0)
        c.rect(0, 0, w, h * 0.1, tassel)
        c.strokes(int(w * 0.3), [_mix(tassel, "#ffffff", 0.2), _shade(tassel, 0.6)], length=(h * 0.02, h * 0.05),
                  width=(w * 0.005, w * 0.012), angle=90, angle_jitter=6, alpha=(0.4, 0.7), region=(0, 0, w, h * 0.1))
        c.grain(0.02)
    return p


def doppi_hat(base, pattern, edge, seed=0):
    """Чустская дўппи (ячейка hat): верх — четыре грани с «қалампир», низ — околыш."""
    def p(c: Canvas, w, h):
        c.underpaint([base, _shade(base, 1.25), _shade(base, 0.85)], cell=max(8, w // 10), seed=seed)
        rim = h * 0.78
        c.rect(0, rim, w, h, edge)
        for k in range(8):
            c.ellipse((k + 0.5) * w / 8, (rim + h) / 2, w * 0.014, h * 0.01, base, 0.85)
        for k in range(4):
            cx = (k + 0.5) * w / 4
            s = h / 256
            pts = [(cx - 10 * s, rim - 8 * s), (cx - 12 * s, rim - 40 * s), (cx - 2 * s, rim - 70 * s),
                   (cx + 9 * s, rim - 90 * s), (cx + 4 * s, rim - 66 * s), (cx + 10 * s, rim - 36 * s), (cx + 4 * s, rim - 8 * s)]
            c.polygon(pts, pattern, 0.95, wobble=0.6, seed=seed + k)
            c.line([(cx - 4 * s, rim - 16 * s), (cx - 2 * s, rim - 50 * s), (cx + 4 * s, rim - 72 * s)], 2.4 * s, base, 0.8,
                   wobble=0.4, seed=seed + 9 + k)
            c.ellipse(cx, rim - 118 * s, 7 * s, 6 * s, pattern, 0.9)
            c.line([(k * w / 4, 0), (k * w / 4, rim)], max(1.2, w * 0.01), _shade(pattern, 0.9), 0.7, wobble=0.5,
                   seed=seed + 20 + k)
        vgrad(c, 1.15, 0.8)
        c.grain(0.02)
    return p


# ---------------------------------------------------------------- кожа, металл, дерево

def leather_region(boot, belt, felt, seed=0):
    def p(c: Canvas, w, h):
        c.underpaint([_shade(boot, 0.8), boot, _mix(boot, "#c08a5a", 0.2)], cell=30, seed=seed)
        c.strokes(300, [_mix(boot, "#e0b080", 0.35), _shade(boot, 0.7)], length=(10, 30), width=(3, 7), angle=90,
                  angle_jitter=14, alpha=(0.2, 0.45), region=(0, 0, w * 0.5, h))
        # голенище: блик вдоль, складки у щиколотки, отворот сверху
        for x in np.arange(10, w * 0.5, 40):
            c.line([(x, 0), (x + 2, h)], 5, _mix(boot, "#f0c090", 0.4), 0.35, seed=int(x))
        c.strokes(80, [_shade(boot, 0.55)], length=(10, 24), width=(2, 4), angle=0, angle_jitter=15, alpha=(0.3, 0.5),
                  region=(0, h * 0.62, w * 0.5, h * 0.85))
        trim(c, [(-4, 10), (w * 0.5, 10)], _shade(boot, 0.6), 8, seed=seed)
        c.rect(w * 0.5, 0, w * 0.75, h, belt)
        c.strokes(120, [_mix(belt, "#e0b080", 0.3), _shade(belt, 0.7)], length=(10, 24), width=(2, 5), angle=0,
                  alpha=(0.25, 0.5), region=(w * 0.5, 0, w * 0.75, h))
        for yy in np.arange(h * 0.1, h, h * 0.2):   # бляхи пояса
            c.ellipse(w * 0.625, yy, 5, 5, "#b58a3c", 0.9)
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
            c.strokes(100, [d, m], length=(h * 0.15, h * 0.4), width=(4, 10), angle=90, angle_jitter=10, alpha=(0.3, 0.55),
                      region=(x0, 0, x1, h))
            c.strokes(30, [l], length=(h * 0.1, h * 0.3), width=(2, 5), angle=90, angle_jitter=6, alpha=(0.5, 0.85),
                      region=(x0 + q * 0.3, 0, x0 + q * 0.6, h))
            if i == 0:
                for yy in np.arange(16, h, 40):
                    c.line(spiral_points(x0 + q * 0.5, yy, 10, 1.3), 2, d, 0.6, seed=int(yy))
        vgrad(c, 1.15, 0.75)
    return p


def wood_region(seed=0):
    def p(c: Canvas, w, h):
        hw = w // 2
        c.rect(0, 0, hw, h, "#5a3b24")
        c.strokes(200, ["#38231a", "#7a5232", "#6a4428"], length=(h * 0.3, h * 0.8), width=(3, 7), angle=90,
                  angle_jitter=4, alpha=(0.3, 0.6), region=(0, 0, hw, h))
        for yy in (h * 0.2, h * 0.45, h * 0.7):
            trim(c, [(-2, yy), (hw + 2, yy)], "#c9a24a", 6, "#7d5a22", seed=int(yy))
        c.rect(hw, 0, w, h, "#9a7a52")
        c.strokes(180, ["#6e5638", "#b8986a", "#8a6a44"], length=(h * 0.3, h * 0.8), width=(3, 6), angle=90,
                  angle_jitter=3, alpha=(0.3, 0.6), region=(hw, 0, w, h))
        vgrad(c, 1.1, 0.85)
        c.grain(0.02)
    return p


# ---------------------------------------------------------------- знамёна, попоны, щиты, плащи

def banner_kokand(seed=0):
    def p(c: Canvas, w, h):
        main, light, gold = KOKAND["main"], KOKAND["light"], KOKAND["gold"]
        c.underpaint([_shade(main, 0.85), main, _mix(main, light, 0.25)], cell=48, seed=seed)
        c.strokes(500, [_mix(main, light, 0.3), _shade(main, 0.8)], length=(20, 50), width=(5, 12), angle=10,
                  angle_jitter=15, alpha=(0.15, 0.35))
        m = 34
        c.rect(m, m, w - m, h - m, _mix(main, "#1f6e52", 0.5), 0.55)
        for s in range(2):
            pts = [(m - 10 + s * 6, m - 10 + s * 6), (w - m + 10 - s * 6, m - 10 + s * 6),
                   (w - m + 10 - s * 6, h - m + 10 - s * 6), (m - 10 + s * 6, h - m + 10 - s * 6)]
            c.line(pts + [pts[0]], 9 - s * 4, gold if s == 0 else _shade(gold, 0.6), 0.95, seed=seed + s)
        cx, cy, r = w * 0.5, h * 0.36, w * 0.17
        c.ellipse(cx, cy, r, r, gold, 0.95)
        c.ellipse(cx + r * 0.38, cy - r * 0.1, r * 0.82, r * 0.82, _mix(main, "#1f6e52", 0.5), 1.0)
        sx, sy = cx + r * 0.75, cy - r * 0.15
        pts = []
        for i in range(10):
            a = i * math.pi / 5 - math.pi / 2
            rr = r * 0.28 if i % 2 == 0 else r * 0.11
            pts.append((sx + rr * math.cos(a), sy + rr * math.sin(a)))
        c.polygon(pts, gold, 0.95)
        for row, yy in enumerate((h * 0.66, h * 0.78)):
            x = m + 20
            while x < w - m - 30:
                L = c.rs.uniform(18, 46)
                pts = [(x + t * L, yy + 6 * math.sin(t * 6 + row) - (10 if t > 0.8 else 0)) for t in np.linspace(0, 1, 8)]
                c.line(pts, 4.5, gold, 0.9, seed=int(x))
                x += L + c.rs.uniform(8, 16)
        # складки полотна: длинные тени и свет поперёк ветра
        folds(c, w, h, _shade(main, 0.6), _mix(main, "#ffffff", 0.35), n=14, vertical=True, alpha=(0.1, 0.22))
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
        m = 30
        for y in (m, h - m):
            pts = [(x, y + 6 * math.sin(x / 18)) for x in np.linspace(-4, w + 4, 40)]
            c.line(pts, 12, white, 0.95, seed=int(y))
            c.line([(x, yy + 9) for x, yy in pts], 2.5, dark, 0.8, seed=int(y) + 1)
        ram_horn(c, w * 0.5, h * 0.5, w * 0.42, white, 13, 0.97, seed=seed)
        ram_horn(c, w * 0.5, h * 0.5, w * 0.42, _shade(main, 0.55), 3.5, 0.5, seed=seed + 1)
        for x in (w * 0.18, w * 0.82):
            rhomb(c, x, h * 0.2, 14, 20, white, 0.9)
            rhomb(c, x, h * 0.8, 14, 20, white, 0.9)
        folds(c, w, h, _shade(main, 0.6), _mix(main, "#ffffff", 0.3), n=14, vertical=True, alpha=(0.1, 0.22))
        vgrad(c, 1.1, 0.8)
        c.grain(0.02)
    return p


def caparison(main, light, dark, orn, trimc, seed=0, kind="kipchak", field=None, field_w=0.16):
    """Попона: u — от левого подола через спину к правому, v — от хвоста к груди.
    field — цвет полосы вдоль хребта (у кыпчаков — некрашеный войлок под седлом, доля field_w
    ширины), бока — цвет стороны: сверху, с камеры RTS, конь читается киноварью (ТЗ 11.2)."""
    def p(c: Canvas, w, h):
        c.underpaint([_shade(main, 0.85), main, _mix(main, light, 0.15)], cell=44, seed=seed)
        c.strokes(500, [_mix(main, light, 0.25), _shade(main, 0.75), main], length=(16, 40), width=(4, 10),
                  angle=0, angle_jitter=20, alpha=(0.15, 0.35))
        if field:
            f0, f1 = 0.5 - field_w / 2, 0.5 + field_w / 2
            c.rect(w * f0, 0, w * f1, h, field, 0.95)
            c.strokes(120, [_mix(field, "#ffffff", 0.2), _shade(field, 0.85)], length=(8, 20), width=(3, 6), angle=0,
                      angle_jitter=80, alpha=(0.15, 0.35), region=(w * f0, 0, w * f1, h))
            for s in (f0, f1):
                c.line([(w * s, -4), (w * s, h + 4)], 5, trimc, 0.95, wobble=0.6, seed=int(s * 10))
            for yy in np.arange(30, h, 60):     # белые «кочкор мүйүз» по бокам полосы — аппликация войлоком
                for s in (f0 - 0.07, f1 + 0.07):
                    ram_horn(c, w * s, yy, 22, orn, 3.5, 0.85, seed=int(yy * 3 + s * 100))
        x = np.linspace(0, 1, c.w * c.ss)
        k = 0.72 + 0.4 * np.exp(-((x - 0.5) / 0.22) ** 2)
        arr = np.asarray(c.img, dtype=np.float64)
        c._blend(arr * k[None, :, None])
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
            ex = 0 if side == 0 else w
            for yy in np.arange(0, h, 7):
                c.line([(ex, yy), (ex + (10 if side == 0 else -10), yy + 2)], 3, trimc, 0.85, seed=int(yy))
        if kind != "kipchak" and not field:
            for yy in np.arange(60, h, 120):
                c.ellipse(w * 0.5, yy, 18, 18, trimc, 0.7)
        c.grain(0.025)
    return p


def shield_kipchak(seed=0):
    """Плетёный щит-калкан: спираль из ивового прута (золотистая лоза, тёмные стежки обмотки),
    две полосы крашеной нити — киноварь у края и кармин у умбона с белыми «кочкор мүйүз»,
    кожаный обод, железный умбон с заклёпками (развёртка сверху). Лоза — основа, красное — акцент."""
    def p(c: Canvas, w, h):
        cx, cy = w / 2, h / 2
        R = w * 0.49
        cane, cane_d, cane_l = "#b8925a", "#7a5a32", "#e2c48a"
        c.rect(0, 0, w, h, cane)
        rings = 30
        for i in range(rings):
            r = R * (1 - i / (rings + 1))
            pts = [(cx + r * math.cos(a), cy + r * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 72)]
            col = _mix(cane, cane_l if i % 2 else cane_d, 0.35 + 0.15 * ((i * 7) % 3))
            c.line(pts, R / (rings + 1) * 1.05, col, 0.9, wobble=0.6, seed=seed + i)
            c.line(pts, max(1.0, R / (rings + 1) * 0.18), cane_d, 0.55, wobble=0.5, seed=seed + 50 + i)   # шов между прутьями
        # обмотка: короткие радиальные стежки по всему щиту
        rs = np.random.default_rng(seed)
        for _ in range(420):
            a = rs.uniform(0, 2 * math.pi)
            r = rs.uniform(0.18, 0.97) * R
            dr = R / (rings + 1) * 0.6
            c.line([(cx + (r - dr) * math.cos(a), cy + (r - dr) * math.sin(a)),
                    (cx + (r + dr) * math.cos(a + 0.02), cy + (r + dr) * math.sin(a + 0.02))],
                   max(1.0, w * 0.006), _shade(cane_d, 0.8), 0.35, wobble=0.2)
        # полосы крашеной нити
        for r0, r1, col in ((0.64, 0.93, KIPCHAK["main"]), (0.3, 0.4, KIPCHAK["carmine"])):
            for r in np.linspace(r0 * R, r1 * R, 4):
                pts = [(cx + r * math.cos(a), cy + r * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 72)]
                c.line(pts, (r1 - r0) * R / 3.2, col, 0.92, wobble=0.5, seed=int(r))
        for a in np.linspace(0, 2 * math.pi, 9, endpoint=False):
            ram_horn(c, cx + R * 0.785 * math.cos(a), cy + R * 0.785 * math.sin(a), w * 0.07, "#efe2c4",
                     max(2.0, w * 0.011), 0.9, seed=int(a * 10))
        # кожаный обод и умбон с заклёпками
        c.line([(cx + R * math.cos(a), cy + R * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 72)],
               max(3.0, w * 0.03), "#3a2418", 0.95, seed=seed)
        c.ellipse(cx, cy, w * 0.12, h * 0.12, "#4e5056")
        c.ellipse(cx, cy, w * 0.1, h * 0.1, "#6a6e74")
        c.ellipse(cx - w * 0.03, cy - h * 0.03, w * 0.04, h * 0.04, "#c8ccd0", 0.75)
        for a in np.linspace(0, 2 * math.pi, 6, endpoint=False):
            c.ellipse(cx + w * 0.155 * math.cos(a), cy + w * 0.155 * math.sin(a), w * 0.012, w * 0.012, "#8a8e94", 0.95)
        # нарисованный свет сверху-слева
        yy, xx = np.mgrid[0:c.h * c.ss, 0:c.w * c.ss] / (c.w * c.ss)
        k = 1.14 - 0.38 * np.clip((xx + yy) * 0.6 - 0.2, 0, 1)
        c._blend(np.asarray(c.img, dtype=np.float64) * k[..., None])
        c.grain(0.025)
    return p


def cape(main, light, dark, orn, seed=0):
    """Накидка-жамчы (цвет стороны): u — по плечам от левого края через спину к правому,
    v — от ворота (верх) к подолу; войлочная аппликация «кочкор мүйүз» по краю."""
    def p(c: Canvas, w, h):
        felt_ground(c, w, h, main, _shade(main, 0.8), light, seed=seed)
        folds(c, w, h, _shade(main, 0.55), _mix(main, light, 0.35), n=22, flare=0.5)
        temperature(c, w, h, n=int(w * 0.5))
        vgrad(c, 1.18, 0.7)
        c.rect(0, h - h * 0.12, w, h, dark, 0.9)
        for x in np.arange(w * 0.06, w, w * 0.16):
            ram_horn(c, x, h - h * 0.07, h * 0.08, orn, max(1.5, w * 0.008), 0.95, seed=int(x))
        c.line([(-4, h - h * 0.125), (w + 4, h - h * 0.125)], max(1.5, h * 0.012), orn, 0.9, seed=seed)
        trim(c, [(-4, h * 0.03), (w + 4, h * 0.03)], dark, max(3.0, h * 0.05), seed=seed + 2)
        c.grain(0.025)
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


def lamellar(plate, plate_dark, lace, edge, seed=0, rows=6, cols=22, top_trim=True):
    """Ламеллярный доспех: ряды пластин внахлёст (каждый ряд сверху бросает тень на следующий),
    кожаная шнуровка, блик по левой кромке и закруглённый низ пластины. Пластины крупные —
    чтобы доспех читался как доспех и с камеры боя, а не как вязаная сетка."""
    def p(c: Canvas, w, h):
        c.rect(0, 0, w, h, _shade(plate_dark, 0.7))
        y_top = h * 0.08 if top_trim else 0
        y_bot = h - h * 0.07
        ph = (y_bot - y_top) / rows
        pw = w / cols
        # снизу вверх: верхний ряд ложится поверх нижнего
        for r in reversed(range(rows)):
            y = y_top + r * ph
            off = (r % 2) * pw * 0.5
            # тень этого ряда на нижнем (под закруглёнными краями пластин)
            c.line([(-4, y + ph * 1.24), (w + 4, y + ph * 1.24)], max(2.0, ph * 0.22), _shade(plate_dark, 0.4), 0.6,
                   wobble=0.4, seed=r * 13)
            for k in range(-1, cols + 1):
                x = k * pw + off
                t = c.rs.uniform(-0.06, 0.16)
                col = _mix(plate, "#ffffff", t) if t >= 0 else _shade(plate, 1 + t)
                if c.rs.random() < 0.18:   # потемневшая, в ржавчине
                    col = _mix(col, "#7a5a40", 0.3)
                body = [(x + 1.5, y), (x + pw - 1.5, y), (x + pw - 1.5, y + ph * 1.12), (x + pw * 0.5, y + ph * 1.3),
                        (x + 1.5, y + ph * 1.12)]
                c.polygon(body, col, 1.0, wobble=0.25)
                # блик по левой кромке, тень по правой — пластина выпуклая
                c.line([(x + pw * 0.24, y + ph * 0.12), (x + pw * 0.26, y + ph * 1.05)], max(1.2, pw * 0.18),
                       _mix(col, "#ffffff", 0.55), 0.55, seed=r * 97 + k)
                c.line([(x + pw * 0.86, y + ph * 0.1), (x + pw * 0.84, y + ph * 1.1)], max(1.2, pw * 0.16),
                       _shade(col, 0.55), 0.6, seed=r * 89 + k)
                c.ellipse(x + pw * 0.5, y + ph * 0.55, pw * 0.07, pw * 0.07, _shade(lace, 0.7), 0.9)   # отверстие
            # шнуровка по видимой части ряда (верх закрыт верхним рядом)
            c.line([(-4, y + ph * 0.55), (w + 4, y + ph * 0.55)], max(1.5, ph * 0.08), lace, 0.85, wobble=0.5, seed=r * 7)
        hgrad(c, lambda u: 0.8 + 0.32 * np.exp(-((u - 0.5) / 0.28) ** 2))
        if top_trim:
            trim(c, [(-4, h * 0.04), (w + 4, h * 0.04)], edge, max(3.0, h * 0.07), _shade(edge, 0.5), seed=seed + 1)
        trim(c, [(-4, h - h * 0.035), (w + 4, h - h * 0.035)], edge, max(3.0, h * 0.06), _shade(edge, 0.5), seed=seed)
        vgrad(c, 1.15, 0.75)
    return p


def mail(steel, seed=0):
    def p(c: Canvas, w, h):
        c.rect(0, 0, w, h, _shade(steel, 0.5))
        for r, yy in enumerate(np.arange(2, h, 5.0)):
            for x in np.arange((r % 2) * 2.5, w, 5.0):
                c.ellipse(x, yy, 2.4, 2.2, _mix(steel, "#ffffff", 0.12), 0.85)
                c.ellipse(x, yy, 1.1, 1.0, _shade(steel, 0.35), 0.9)
        vgrad(c, 1.1, 0.7)
    return p


def saddle_region(leather, metal, cloth, seed=0):
    def p(c: Canvas, w, h):
        c.underpaint([_shade(leather, 0.8), leather, _mix(leather, "#c08a5a", 0.2)], cell=20, seed=seed)
        c.strokes(200, [_mix(leather, "#e0b080", 0.3), _shade(leather, 0.7)], length=(10, 24), width=(2, 5), angle=0,
                  alpha=(0.2, 0.45))
        trim(c, [(-4, h * 0.15), (w + 4, h * 0.15)], metal, 6, _shade(metal, 0.5), seed=seed)
        trim(c, [(-4, h * 0.85), (w + 4, h * 0.85)], cloth, 8, _shade(cloth, 0.5), seed=seed + 1)
        for x in np.arange(10, w, 24):
            c.ellipse(x, h * 0.15, 3, 3, _mix(metal, "#ffffff", 0.3), 0.9)
        vgrad(c, 1.15, 0.75)
        c.grain(0.02)
    return p


# ---------------------------------------------------------------- кони и овцы

HORSE_COATS = [
    # (тело, тень, свет, грива/хвост, ноги-низ, копыто, отметины, «яблоки», ремень спины)
    ("#6b3f26", "#3e2214", "#a8683c", "#1e1612", "#221a16", "#3a3530", None, False, False),     # гнедой
    ("#8a4a26", "#55291a", "#c8804a", "#6e3418", "#8a4a26", "#4a4038", "#efe6d6", False, False),  # рыжий с отметинами
    ("#aaa298", "#6e6a64", "#e6e0d6", "#d4c8b4", "#5e5650", "#4a4440", None, True, False),       # серый в яблоках
    ("#b08f5a", "#6e5634", "#dcc08a", "#2a1f18", "#2a201a", "#3a3530", None, False, True),        # саврасый (буланый)
]


def _shade_rect(c: Canvas, rect, fn):
    """Нарисованная лепка формы: умножает область на fn(u, v) (u, v — 0..1 внутри области)."""
    x0, y0, x1, y1 = [int(round(t * c.ss)) for t in rect]
    arr = np.asarray(c.img, dtype=np.float64).copy()
    u = np.linspace(0, 1, x1 - x0)[None, :]
    v = np.linspace(0, 1, y1 - y0)[:, None]
    k = np.broadcast_to(fn(u, v), (y1 - y0, x1 - x0))
    arr[y0:y1, x0:x1] *= k[..., None]
    c._blend(arr)


def _bump(x, c, w):
    return np.exp(-((x - c) / w) ** 2)


def _rect_mask(c: Canvas, x0, y0, x1, y1):
    m = np.zeros((c.h * c.ss, c.w * c.ss))
    m[int(y0 * c.ss):int(y1 * c.ss), int(x0 * c.ss):int(x1 * c.ss)] = 1
    return m


def horse_cell(coat, seed=0, tack=None):
    """Масть коня (ячейка 512²). tack — (ремни, металл, кисть) для узды у верховых коней атласа стороны."""
    body, dark, light, hair, legc, hoof, sock, dapple, dorsal = coat

    def p(c: Canvas, w, h):
        def sub(name):
            f = HORSE_SUB[name]
            return (f[0] * w, f[1] * h, f[2] * w, f[3] * h)

        # тело: u вокруг (0 хребет, 0.25 правый бок, 0.5 живот, 0.75 левый), картинка вверх — к груди
        r = sub("body")
        x0, y0, x1, y1 = r
        c.rect(x0, y0, x1, y1, body)
        c.underpaint([_shade(body, 0.92), body, _mix(body, light, 0.12)], cell=56, seed=seed,
                     mask=_rect_mask(c, x0, y0, x1, y1))
        c.strokes(700, [body, _mix(body, light, 0.3), _shade(body, 0.8)], length=(14, 34), width=(3, 7),
                  angle=90, angle_jitter=10, alpha=(0.12, 0.32), region=r)

        def form(u, v):   # светлая спина, тёмный живот, мышцы плеча (v≈0.8) и крупа (v≈0.2), рёбра
            top = np.cos(u * 2 * np.pi)
            k = 0.78 + 0.32 * np.clip(top, 0, 1) - 0.32 * np.clip(-top, 0, 1) ** 0.7
            side = _bump(u, 0.25, 0.1) + _bump(u, 0.75, 0.1)
            mus = (_bump(v, 0.17, 0.1) + _bump(v, 0.82, 0.08)) * side
            k = k + 0.24 * mus - 0.12 * _bump(v, 0.66, 0.04) * side - 0.08 * _bump(v, 0.3, 0.03) * side
            k = k - 0.05 * (np.sin(v * 70) > 0.6) * _bump(v, 0.5, 0.1) * side    # рёбра едва
            return k
        _shade_rect(c, r, form)
        if dapple:
            for i in range(110):
                cx, cy = c.rs.uniform(x0, x1), c.rs.uniform(y0, y1)
                rr = c.rs.uniform(5, 11)
                c.ellipse(cx, cy, rr * 1.35, rr * 1.15, _shade(body, 0.86), 0.22)
                c.ellipse(cx, cy, rr, rr * 0.8, _mix(body, "#ffffff", 0.4), 0.4)
        if dorsal:   # ремень по хребту у саврасых
            for xx in (x0, x1):
                c.rect(xx - 5, y0, xx + 5, y1, hair, 0.75)
        # шея: u вокруг (0 гребень, 0.5 горло), картинка вниз — к голове
        r = sub("neck")
        x0, y0, x1, y1 = r
        c.rect(x0, y0, x1, y1, body)
        c.strokes(200, [_mix(body, light, 0.25), _shade(body, 0.85)], length=(12, 28), width=(3, 6), angle=90,
                  angle_jitter=20, alpha=(0.15, 0.35), region=r)
        _shade_rect(c, r, lambda u, v: 0.8 + 0.3 * np.cos(u * 2 * np.pi) + 0.08 * (1 - v)
                    + 0.12 * (_bump(u, 0.3, 0.06) + _bump(u, 0.7, 0.06)) - 0.1 * _bump(u, 0.5, 0.08))
        for fx in (0.0, 1.0):   # корни гривы по гребню
            c.rect(x0 + (x1 - x0) * (fx - 0.06), y0, x0 + (x1 - x0) * (fx + 0.06), y1, hair, 0.95)
        # голова: u вокруг (0 лоб, 0.25 правая щека, 0.5 нижняя челюсть), картинка вниз — к морде
        r = sub("head")
        x0, y0, x1, y1 = r
        hw, hh = x1 - x0, y1 - y0
        c.rect(x0, y0, x1, y1, body)
        c.strokes(160, [_mix(body, light, 0.25), _shade(body, 0.85)], length=(10, 22), width=(3, 5), angle=90,
                  angle_jitter=25, alpha=(0.15, 0.35), region=r)

        def hform(u, v):  # лоб и переносица светлее, ганаши (щёки) круглые, морда темнее
            k = 0.82 + 0.22 * np.cos(u * 2 * np.pi)
            k = k + 0.16 * (_bump(u, 0.3, 0.08) + _bump(u, 0.7, 0.08)) * _bump(v, 0.28, 0.14)
            k = k - 0.06 * (_bump(u, 0.22, 0.03) + _bump(u, 0.78, 0.03)) * (v > 0.45)
            return k * (1.04 - 0.45 * np.clip(v - 0.7, 0, 1) / 0.3)
        _shade_rect(c, r, hform)
        c.rect(x0, y1 - hh * 0.16, x1, y1, _mix(body, "#2a1e18", 0.55), 0.7)        # морда темнее
        for fx in (0.22, 0.78):
            ex, ey = x0 + hw * fx, y0 + hh * 0.2
            c.ellipse(ex, ey + 3, 11, 7, _shade(body, 0.55), 0.55)                   # надглазье
            c.ellipse(ex, ey, 6.5, 4.8, "#120c0a", 0.95)
            c.ellipse(ex - 1.5, ey - 1.5, 1.8, 1.5, "#e8e0d8", 0.85)
            nx = x0 + hw * (0.36 if fx < 0.5 else 0.64)
            c.ellipse(nx, y0 + hh * 0.9, 6, 4, "#0e0a08", 0.85)                       # ноздри
            c.ellipse(nx, y0 + hh * 0.9 - 3, 7, 3, _mix(body, light, 0.3), 0.4)
        c.line([(x0 + hw * 0.4, y1 - 3), (x0 + hw * 0.6, y1 - 3)], 3, "#140e0a", 0.8)   # рот
        if sock:   # проточина
            c.line([(x0 + 3, y0 + hh * 0.15), (x0 + 4, y1)], 9, sock, 0.9, seed=seed)
            c.line([(x1 - 3, y0 + hh * 0.15), (x1 - 4, y1)], 9, sock, 0.9, seed=seed + 1)
        if tack:
            strap, metal, tassel = tack
            c.line([(x0, y0 + hh * 0.13), (x0 + hw * 0.35, y0 + hh * 0.13)], 5, strap, 0.95)      # налобный
            c.line([(x0 + hw * 0.65, y0 + hh * 0.13), (x1, y0 + hh * 0.13)], 5, strap, 0.95)
            c.line([(x0 + hw * 0.6, y0 + hh * 0.13), (x0 + hw * 0.65, y0 + hh * 0.13)], 5, tassel, 0.95)
            c.line([(x0, y0 + hh * 0.72), (x1, y0 + hh * 0.72)], 5, strap, 0.95)                   # капсюль
            for fx in (0.3, 0.7):
                c.line([(x0 + hw * fx, y0), (x0 + hw * fx, y0 + hh * 0.72)], 4.5, strap, 0.95)    # нащёчные
                c.ellipse(x0 + hw * fx, y0 + hh * 0.72, 4, 4, metal, 0.95)
            c.ellipse(x0 + hw * 0.5, y0 + hh * 0.5, 7, 9, tassel, 0.95)                         # кисть под горлом
        # ноги: верх — масть, низ (пясть, бабки) темнее или отметины; суставы — тень
        r = sub("legs")
        x0, y0, x1, y1 = r
        c.rect(x0, y0, x1, y1, body)
        c.strokes(220, [_mix(body, light, 0.25), _shade(body, 0.8)], length=(10, 26), width=(3, 6), angle=90,
                  alpha=(0.2, 0.4), region=r)
        yb = y0 + (y1 - y0) * 0.55
        c.rect(x0, yb, x1, y1, legc, 0.92)
        c.strokes(80, [_mix(legc, "#ffffff", 0.12), _shade(legc, 0.7)], length=(10, 20), width=(2, 4), angle=90,
                  alpha=(0.25, 0.5), region=(x0, yb, x1, y1))
        if sock:
            c.rect(x0, y0 + (y1 - y0) * 0.8, x1, y1, sock, 0.95)
        _shade_rect(c, r, lambda u, v: (0.84 + 0.2 * np.cos(u * 2 * np.pi) - 0.1 * v) * (1 - 0.18 * _bump(v, 0.5, 0.04)
                                                                                          - 0.15 * _bump(v, 0.82, 0.04)))
        # грива и хвост — карты: верх — корни, низ — концы прядей
        for nm in ("mane", "tail"):
            r = sub(nm)
            x0, y0, x1, y1 = r
            c.rect(x0, y0, x1, y1, _shade(hair, 0.8))
            c.strokes(420 if nm == "mane" else 300, [_mix(hair, "#ffffff", 0.25), _shade(hair, 0.55), hair,
                                                     _mix(hair, light, 0.3)],
                      length=((y1 - y0) * 0.3, (y1 - y0) * 0.9), width=(1.5, 3.5), angle=90, angle_jitter=7,
                      alpha=(0.35, 0.75), region=r, curve=0.35)
            _shade_rect(c, r, lambda u, v: 0.75 + 0.35 * np.sin(np.clip(v, 0, 1) * np.pi * 0.8 + 0.3))
        r = sub("hoof")
        c.rect(*r, hoof)
        c.strokes(60, [_mix(hoof, "#ffffff", 0.15), _shade(hoof, 0.6)], length=(8, 16), width=(2, 4), angle=90,
                  alpha=(0.3, 0.5), region=r)
        r = sub("ear")
        c.rect(*r, body)
        c.rect(r[0] + (r[2] - r[0]) * 0.35, r[1], r[0] + (r[2] - r[0]) * 0.65, r[3], _shade(body, 0.5), 0.8)
        c.grain(0.018)
    return p


WOOL = [("#e8dfcc", "#b5a78c", "#fff6e6", "#2a221c"), ("#d9c8a6", "#a08c68", "#f4e6c8", "#e8dccb"),
        ("#9a7652", "#5e4430", "#c49a70", "#3a2a20"), ("#4a3a30", "#2a1f1a", "#6e5a4a", "#e0d6c8")]


def sheep_cell(wool, seed=0):
    base, dark, light, face_c = wool

    def p(c: Canvas, w, h):
        def sub(name):
            f = SHEEP_SUB[name]
            return (f[0] * w, f[1] * h, f[2] * w, f[3] * h)
        x0, y0, x1, y1 = sub("body")
        c.rect(x0, y0, x1, y1, base)
        for i in range(1400):
            x, y = c.rs.uniform(x0, x1), c.rs.uniform(y0, y1)
            pts = spiral_points(x, y, c.rs.uniform(3, 7), turns=0.8, start=c.rs.uniform(0, 6.28), n=8)
            c.line(pts, c.rs.uniform(1.5, 3.5), [light, dark, base][i % 3], c.rs.uniform(0.25, 0.6), wobble=0.2, seed=i)
        xs = np.linspace(0, 1, c.w * c.ss)
        lit = 0.7 + 0.45 * np.clip(np.cos(xs * 2 * np.pi), 0, 1)
        arr = np.asarray(c.img, dtype=np.float64)
        yy0, yy1 = int(y0 * c.ss), int(y1 * c.ss)
        arr[yy0:yy1] = arr[yy0:yy1] * lit[None, :, None]
        c._blend(arr)
        for nm in ("head", "face"):
            x0, y0, x1, y1 = sub(nm)
            c.rect(x0, y0, x1, y1, face_c)
            c.strokes(100, [_mix(face_c, "#ffffff", 0.2), _shade(face_c, 0.7)], length=(8, 18), width=(2, 4), angle=90,
                      alpha=(0.2, 0.4), region=(x0, y0, x1, y1))
        x0, y0, x1, y1 = sub("head")
        for fx in (0.25, 0.75):
            c.ellipse(x0 + (x1 - x0) * fx, y0 + (y1 - y0) * 0.35, 4, 3, "#120c0a", 0.95)
        x0, y0, x1, y1 = sub("legs")
        c.rect(x0, y0, x1, y1, _mix(face_c, "#5a4a3a", 0.3))
        c.rect(x0, y0 + (y1 - y0) * 0.85, x1, y1, "#2a221c")
        x0, y0, x1, y1 = sub("tail")
        c.rect(x0, y0, x1, y1, base)
        c.strokes(200, [light, dark], length=(6, 14), width=(2, 4), angle=90, angle_jitter=60, alpha=(0.3, 0.5),
                  region=(x0, y0, x1, y1))
        c.grain(0.02)
    return p


# ---------------------------------------------------------------- халаты сторон

def kokand_robes():
    """Четыре халата сарбозов: природные краски (индиго, охра, ореховый, марена — только искрой).
    Цвет стороны (ТЗ 11.2, ~25–30 % силуэта) — камзул без рукавов поверх халата (бирюза, изумруд,
    золотой галун), кушак и кулах чалмы; рукава и полы халата — икат и алача."""
    gold, turq, emer = KOKAND["gold"], KOKAND["tile"], KOKAND["main"]
    deep = KOKAND["tile_deep"]
    R = []
    # 0 — икат-адрас: индиго с кремом и охрой
    R.append(dict(
        base="#3a4468",
        cloth=lambda c, w, h: ikat_motifs(c, w, h, "#323c62", "#d6c48e", "#b58a3a", outline="#6e2a24", cols=5, seed=301),
        cuff="#2a2c48", trim=turq, edge=deep, lining="#e9e0c8", vest=turq,
        trousers=("#2a2a3e", "#565878", None), sash=(turq, "#7fe8c8", [(gold, 0.3, 0.05), (deep, 0.6, 0.08), (gold, 0.85, 0.05)])))
    # 1 — алача: коричневые и охристые полосы
    R.append(dict(
        base="#6a4a30",
        cloth=lambda c, w, h: stripes_alacha(c, w, h, "#6a4a30", [("#c49a4a", 0.1, 4), ("#2e2420", 0.22, 2),
                                                                   ("#d8c8a0", 0.3, 1.5), ("#8a5a30", 0.5, 6),
                                                                   ("#2e2420", 0.66, 2), ("#c49a4a", 0.8, 3)], seed=302),
        cuff="#3a2a1e", trim=emer, edge=KOKAND["dark"], lining="#e2d8bc", vest=emer,
        trousers=("#3a2c22", "#6a5444", "#8a6a40"), sash=(emer, "#7fe8c8", [("#e9e0c8", 0.25, 0.06), ("#e9e0c8", 0.75, 0.06)])))
    # 2 — индиго гладкий с тёмной полоской
    R.append(dict(
        base="#2f3a5e",
        cloth=lambda c, w, h: plain_weave(c, w, h, "#2f3a5e", "#6a78a8", "#1a2038", seed=303, pin="#1c2240", pin_step=0.05),
        cuff="#1c2240", trim=gold, edge="#5a4418", lining="#d8ccb0", vest="#2c9a8e",
        trousers=("#3a3226", "#6a5a44", None), sash=(turq, "#7fe8c8", [(gold, 0.5, 0.12)])))
    # 3 — охра (испарак) с ореховыми стрелами-«ёлочкой»
    R.append(dict(
        base="#a8843e",
        cloth=lambda c, w, h: ikat_motifs(c, w, h, "#a8843e", "#4e3220", "#e2cfa0", outline="#7a2e22", cols=7,
                                          period=0.26, seed=304, kind="arrow"),
        cuff="#5a3a22", trim=emer, edge=KOKAND["dark"], lining="#e9e0c8", vest="#2a8a6c",
        trousers=("#2c2c40", "#5a5a78", None), sash=(emer, "#7fe8c8", [(gold, 0.2, 0.05), (gold, 0.8, 0.05),
                                                                     ("#e9e0c8", 0.5, 0.04)])))
    return R


def kipchak_robes():
    """Четыре халата кыпчаков: верблюжья шерсть, тёмно-бурая шерсть, серый войлок, овчина;
    киноварь и кармин — в обшлагах, кайме подола и канте полы (цвет стороны, ТЗ 11.2), остальное —
    некрашеные войлок, шерсть и кожа."""
    main, carmine = KIPCHAK["main"], KIPCHAK["carmine"]
    felt = KIPCHAK["felt"]
    cinn = "#b8402e"    # киноварь чуть теплее палитры: на буром и сером войлоке не уходит в кармин
    R = []
    R.append(dict(base="#9a7a52",
                  cloth=lambda c, w, h: felt_ground(c, w, h, "#9a7a52", "#7a5e3c", "#e6d2a8", seed=401),
                  cuff=main, trim=main, edge="#3a2a1e", lining="#e6dcc4", band=main, band_trim=felt,
                  placket=main, placket_orn=felt,
                  trousers=("#3a2a22", "#6a5040", None), sash=(main, "#ffa597", [(felt, 0.3, 0.06), (felt, 0.7, 0.06)])))
    R.append(dict(base="#4e3828",
                  cloth=lambda c, w, h: plain_weave(c, w, h, "#4e3828", "#8a6a50", "#2e2018", seed=402),
                  cuff=cinn, trim=felt, edge="#2a1e16", lining="#d8ccb0", band=cinn, band_trim=felt,
                  placket=cinn, placket_orn=felt,
                  trousers=("#2a2420", "#5a4a40", None), sash=(carmine, "#d05060", [("#1a1614", 0.5, 0.1)])))
    R.append(dict(base="#7c766a",
                  cloth=lambda c, w, h: felt_ground(c, w, h, "#7c766a", "#5a564c", "#d8d2c4", seed=403),
                  cuff=carmine, trim=main, edge="#2a2622", lining="#e6dcc4", band=carmine, band_trim=felt,
                  placket=cinn, placket_orn=felt,
                  trousers=("#3a2a22", "#6a5040", None), sash=(main, "#ffa597", [("#1a1614", 0.25, 0.05),
                                                                               ("#1a1614", 0.75, 0.05)])))
    R.append(dict(base="#b0905e",
                  cloth=lambda c, w, h: felt_ground(c, w, h, "#b0905e", "#8a6a40", "#efdcb4", seed=404),
                  cuff=main, trim=carmine, edge="#7a5a38", lining="#efe6d2", band=main, band_trim=felt,
                  placket=main, placket_orn=felt,
                  trousers=("#4a3626", "#7a5e44", None), sash=(main, "#ffa597", [(felt, 0.5, 0.08)])))
    return R


def paint_robes(img, A, robes, seed0):
    for k, R in enumerate(robes):
        base, cloth = R["base"], R["cloth"]
        if R.get("vest"):
            region(img, A, f"torso{k}", vest_torso(cloth, base, R["vest"], R.get("braid", KOKAND["gold"]), R["edge"],
                                                   R["lining"], seed=seed0 + k), seed=seed0 + k)
        else:
            region(img, A, f"torso{k}", robe_torso(cloth, base, R["trim"], R["edge"], R["lining"], seed=seed0 + k,
                                                   placket=R.get("placket"), placket_orn=R.get("placket_orn")),
                   seed=seed0 + k)
        region(img, A, f"skirt{k}", robe_skirt(cloth, base, R["trim"], R["edge"], seed=seed0 + 10 + k, band=R.get("band"),
                                               band_trim=R.get("band_trim", KOKAND["gold"])), seed=seed0 + 10 + k)
        region(img, A, f"sleeve{k}", robe_sleeve(cloth, base, R["cuff"], R["edge"], seed=seed0 + 20 + k),
               seed=seed0 + 20 + k)
        tm, tl, ts = R["trousers"]
        region(img, A, f"trousers{k}", trousers(tm, tl, ts, seed=seed0 + 30 + k), seed=seed0 + 30 + k)
        sm, sl, sb = R["sash"]
        region(img, A, f"sash{k}", sash(sm, sl, sb, seed=seed0 + 40 + k), seed=seed0 + 40 + k)
        region(img, A, f"shirt{k}", lambda c, w, h, L=R["lining"]: plain_weave(c, w, h, L, "#ffffff", _shade(L, 0.7),
                                                                              seed=seed0 + 50), seed=seed0 + 50 + k)


# ---------------------------------------------------------------- сборка атласов

def build_kokand(path):
    A = KOKAND_ATLAS
    img = Image.new("RGB", (A.w, A.h), (40, 40, 40))
    main, dark, light, gold = KOKAND["main"], KOKAND["dark"], KOKAND["light"], KOKAND["gold"]
    turq = KOKAND["tile"]
    tack = ("#2a1a12", gold, turq)
    for i, coat in enumerate(HORSE_COATS):
        region(img, A, f"coat{i}", horse_cell(coat, seed=10 + i, tack=tack), seed=10 + i)
    # чалмы: слоновая кость; кулах — бирюза или изумруд (цвет стороны виден сверху)
    hats = [("#e6dfcf", "#a39a87", None, turq), ("#e3dccc", "#a19884", turq, main),
            ("#d9ccb0", "#9b8b6f", None, main), ("#e8e2d4", "#a69c8a", gold, turq)]
    for i, (cl, sh, st, cap) in enumerate(hats):
        region(img, A, f"hat{i}", turban(cl, sh, st, cap, gold, band=cap, seed=20 + i), seed=20 + i)
    skins = [("#b98466", "#1e1612", "full", 0.0), ("#a8724f", "#241a14", "short", 0.15),
             ("#c08c6c", "#2a2420", "full", 0.85), ("#b07a58", "#1a1210", "moustache", 0.0)]
    for i, (sk, hr, bd, age) in enumerate(skins):
        region(img, A, f"face{i}", face(sk, hr, bd, "round", age, seed=60 + i, stubble="#2a2420"), seed=60 + i)
    region(img, A, "hand", hands(MATERIAL["skin"], seed=69), seed=69)
    paint_robes(img, A, kokand_robes(), 300)
    region(img, A, "leather", leather_region("#3a2418", "#6e4428", "#c9b48a", seed=31), seed=31)
    region(img, A, "metal", metal_region(32), seed=32)
    region(img, A, "wood", wood_region(33), seed=33)
    # юзбоши: шёлковый адрас (охра, слива, крем) с изумрудным кантом и золотом
    adras = lambda c, w, h: ikat_motifs(c, w, h, "#d8b04a", "#5a2a5a", "#e9e0c8", outline="#2a6a4a", cols=7,  # noqa: E731
                                        period=0.28, seed=44)
    region(img, A, "torsoX", robe_torso(adras, "#b08a48", main, KOKAND["dark"], "#e9e0c8", emb=gold, seed=44), seed=44)
    region(img, A, "skirtX", robe_skirt(adras, "#b08a48", main, KOKAND["dark"], seed=45, ornament=gold), seed=45)
    region(img, A, "sleeveX", robe_sleeve(adras, "#b08a48", main, KOKAND["dark"], seed=46), seed=46)
    region(img, A, "hatx", turban("#f2ede2", "#aaa290", gold, main, gold, seed=47), seed=47)
    region(img, A, "saddlecloth", caparison(turq, light, dark, gold, gold, seed=48, kind="kokand"), seed=48)
    region(img, A, "banner", banner_kokand(49), seed=49)
    region(img, A, "caparison", caparison(main, light, dark, gold, gold, seed=50, kind="kokand"), seed=50)
    region(img, A, "flask", plain_weave_painter("#b58a3c", "#f0c878", 52), seed=52)
    region(img, A, "saddle", saddle_region("#4a2c1c", gold, turq, seed=53), seed=53)
    region(img, A, "plume", hair_strip("#f4f0e8", "#ffffff", seed=54), seed=54)
    region(img, A, "shield", shield_kipchak(55), seed=55, tile=False)
    region(img, A, "cloak", cape(turq, light, dark, gold, seed=56), seed=56)
    region(img, A, "pennon", pennon(turq, "#f2ece0", seed=57), seed=57)
    region(img, A, "fur", fur("#5a3a22", "#a07a50", seed=58), seed=58)
    region(img, A, "tug", hair_strip("#efe8dc", "#ffffff", seed=59), seed=59)
    region(img, A, "mail", mail("#9aa1a8", seed=60), seed=60)
    img.save(path, optimize=True)
    return img


def plain_weave_painter(main, light, seed):
    return lambda c, w, h: (plain_weave(c, w, h, main, light, _shade(main, 0.7), seed=seed), vgrad(c, 1.1, 0.8))


def build_kipchak(path):
    A = KIPCHAK_ATLAS
    img = Image.new("RGB", (A.w, A.h), (40, 40, 40))
    main, dark, light = KIPCHAK["main"], KIPCHAK["dark"], KIPCHAK["light"]
    felt, felt_sh = KIPCHAK["felt"], KIPCHAK["felt_shadow"]
    tack = ("#2a1a12", "#9aa1a8", main)
    for i, coat in enumerate(HORSE_COATS):
        region(img, A, f"coat{i}", horse_cell(coat, seed=110 + i, tack=tack), seed=110 + i)
    # белый войлок, отворот — киноварь и кармин (цвет стороны: виден сверху и сбоку, как кулах у Коканда)
    kal = [(felt, felt_sh, main, "#e0706a", None), ("#efe8d6", "#bdb094", KIPCHAK["carmine"], "#c05060", "#1a1614"),
           ("#e2d4b4", "#a89878", "#a8322a", "#d86a5a", "#1a1614"), ("#f2ece0", "#c0b49a", "#9a2a26", "#c8584a", None)]
    for i, (f, fs, b, bl, emb) in enumerate(kal):
        region(img, A, f"hat{i}", kalpak(f, fs, b, bl, seed=120 + i, tassel=main, emb=emb), seed=120 + i)
    skins = [("#b07a58", "#16100c", "goatee", 0.1), ("#a87050", "#1a1410", "droop", 0.3),
             ("#b8845e", "#1e1612", "none", 0.0), ("#a06a4c", "#2a2420", "short", 0.8)]
    for i, (sk, hr, bd, age) in enumerate(skins):
        region(img, A, f"face{i}", face(sk, hr, bd, "narrow", age, seed=160 + i, stubble="#2a2018"), seed=160 + i)
    region(img, A, "hand", hands("#b07a58", seed=169), seed=169)
    paint_robes(img, A, kipchak_robes(), 400)
    region(img, A, "leather", leather_region("#2e1c14", "#5a3420", "#e6dcc4", seed=131), seed=131)
    region(img, A, "metal", metal_region(132), seed=132)
    region(img, A, "wood", wood_region(133), seed=133)
    # ламеллярный доспех: сталь с бурой кожаной шнуровкой, кант киноварью
    region(img, A, "torsoX", lamellar("#8a9098", "#3a3e44", "#4a2a1a", main, seed=144), seed=144)
    region(img, A, "skirtX", lamellar("#8a9098", "#3a3e44", "#4a2a1a", main, seed=145, rows=3, cols=12, top_trim=False),
           seed=145)
    region(img, A, "sleeveX", lamellar("#8a9098", "#3a3e44", "#4a2a1a", main, seed=146, rows=3, cols=10), seed=146)
    region(img, A, "hatx", helmet("#8a9098", "#b58a3c", main, seed=147), seed=147)
    region(img, A, "banner", banner_kipchak(149), seed=149)
    region(img, A, "caparison", caparison(main, light, dark, "#efe6d2", "#e6dcc4", seed=150, kind="kipchak",
                                          field="#d8ccb0", field_w=0.16), seed=150)
    region(img, A, "saddlecloth", caparison("#8e1f2f", "#d0505a", "#4a0f18", "#c9a24a", "#c9a24a", seed=154,
                                            kind="kipchak"), seed=154)
    region(img, A, "cloak", cape(main, light, dark, felt, seed=151), seed=151)
    region(img, A, "fur", fur("#5a3a22", "#a07a50", seed=153), seed=153)
    region(img, A, "shield", shield_kipchak(155), seed=155, tile=False)
    region(img, A, "flask", plain_weave_painter("#6e4428", "#a87a50", 156), seed=156)
    region(img, A, "saddle", saddle_region("#3a2216", "#b58a3c", main, seed=157), seed=157)
    region(img, A, "pennon", pennon(main, "#f2ece0", seed=158), seed=158)
    region(img, A, "plume", hair_strip("#f2ece0", "#ffffff", seed=159), seed=159)
    region(img, A, "tug", hair_strip("#efe8dc", "#ffffff", seed=160), seed=160)
    region(img, A, "mail", mail("#9aa1a8", seed=161), seed=161)
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
