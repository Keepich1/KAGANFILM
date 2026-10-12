"""Общий рисованный атлас Коканда: assets/textures/kokand/atlas.png (2048×2048, RGBA).

Один атлас на все постройки и укрепления города (ТЗ 11.5: один материал на объект).
Каждая область рисуется отдельно (paint.Canvas) и вклеивается с полями: у
повторяющихся по оси областей поле — продолжение узора (бесшовный повтор без
шва на мип-картах), у остальных — растянутый край.

Области, которые повторяются по стене, имеют мировой размер (TILE): модели режут
грани по границам плиток (gen_kokand_kit.face), поэтому узор идёт без шва и
одинаков у соседних звеньев стены (период по X делит шаг звеньев 3,2 м).

Альфа нужна только вырезам (знамя, колосья, хлопок, навес); в остальных местах 1.

    REGIONS["brick"] → (x0, y0, x1, y1) в пикселях
    uv("brick")      → (u0, v0, u1, v1) для Mesh.map_uv
"""
from __future__ import annotations

import math
import os

import numpy as np
from PIL import Image

import gen_kokand_brush as B
from paint import Canvas, fbm, value_noise
from palette import KOKAND, MATERIAL, rgb8

SIZE = 2048
PAD = 8

# ---------------------------------------------------------------- цвета Коканда
EMERALD = KOKAND["main"]        # #2f8f74
EMERALD_L = KOKAND["light"]     # #7fe8c8
EMERALD_D = KOKAND["dark"]      # #17463a
GOLD = KOKAND["gold"]           # #c9a24a
GOLD_D = KOKAND["gold_dark"]    # #7d5a22
GOLD_L = "#f0d48a"
TURQ = KOKAND["tile"]           # #2aa39a
TURQ_D = KOKAND["tile_deep"]    # #145f63
TURQ_L = "#6fd6c4"
COBALT = "#1f3f6e"
COBALT_D = "#142a4c"
CREAM = "#efe6cf"
BRICK = ["#a2643f", "#9a5a38", "#ad7048", "#b47a50", "#8e5234", "#a66c46", "#985c3c", "#b0764e"]
BRICK_RARE = ["#bf9266", "#6e3e2a", "#c08060", "#7a4a34"]
MORTAR = ["#9e8e72", "#928268", "#a89a7e", "#8a7a62"]
CLAY = ["#b89470", "#ae8a66", "#c29e78", "#a6835e"]
PAKHSA = ["#a88a62", "#9c7e58", "#b4966c", "#937552"]
STRAW = ["#d8c08a", "#c4a870", "#8a6a44", "#e2cc98"]
WALNUT = ["#5a3b24", "#4a2f1f", "#684530", "#3f281a"]
WALNUT_GRAIN = ["#2e1c12", "#7a5338", "#4a2e1e"]

# ---------------------------------------------------------------- мировые размеры плиток, м
# (область атласа целиком = столько метров; модели режут грани по этим границам)
TILE = {
    "brick": (3.2, 1.6),      # 8 кирпичей × 10 рядов
    "pakhsa": (3.2, 2.4),     # 3 слоя по 0,8 м
    "clay": (4.0, 4.0),
    "roof": (4.0, 4.0),
    "plinth": (3.2, None),    # по высоте — весь цоколь
    "tileband": (3.2, None),
    "band2": (3.2, None),
    "earth": (4.0, 4.0),
    "rubble": (3.0, 3.0),
    "furrows": (4.0, 4.0),    # 8 борозд по 0,5 м (вдоль v)
    "canopy_green": (4.0, 4.0),
    "canopy_gold": (4.0, 4.0),
    "planks": (2.0, 2.0),
    "hay": (2.0, 2.0),
    "stones": (1.2, 1.2),
    "ceiling": (2.0, 2.0),
}
FURROW_ROWS = 8               # борозд на плитку «furrows»/«canopy_*» (шаг 0,5 м)

# Портал (пештак) урды: рисунок и модель совпадают (метры, начало — низ середины)
PORTAL = {"w": 7.2, "h": 9.6, "aw": 1.75, "hs": 4.4, "ha": 6.9, "border": 0.42, "frame": 0.62}


def arch_curve(aw, hs, ha, n=12):
    """Стрельчатая арка (два центра): точки от (−aw, hs) через вершину (0, ha) к (aw, hs)."""
    rise = ha - hs
    c = (rise * rise - aw * aw) / (2 * aw)
    R = aw + c
    a_top = math.atan2(rise, -c)                 # угол вершины для левой дуги с центром (c, hs)
    t = np.linspace(math.pi, a_top, n // 2 + 1)
    left = np.column_stack([c + R * np.cos(t), hs + R * np.sin(t)])
    left[-1] = (0.0, ha)
    right = left[::-1].copy()
    right[:, 0] *= -1
    return np.vstack([left, right[1:]])


# ---------------------------------------------------------------- раскладка
# имя: (ширина, высота, повтор: "x" | "y" | "xy" | None); места считает упаковщик (skyline)
SPECS = [
    ("brick", 768, 384, "xy"),
    ("dome_tile", 640, 352, "x"),
    ("roof", 448, 448, "xy"),
    ("clay", 448, 448, "xy"),
    ("portal", 384, 512, None),
    ("pakhsa", 512, 384, "xy"),
    ("door", 224, 448, None),
    ("column", 128, 512, "x"),
    ("walnut", 96, 512, "y"),
    ("wood", 96, 512, "y"),
    ("bark", 64, 512, "y"),
    ("pole", 48, 512, "y"),
    ("banner", 320, 224, None),
    ("gate", 320, 384, None),
    ("furrows", 320, 320, "xy"),
    ("water", 96, 384, "y"),
    ("rope", 32, 256, "y"),
    ("canopy_green", 192, 192, "xy"),
    ("canopy_gold", 192, 192, "xy"),
    ("rubble", 192, 192, "xy"),
    ("planks", 192, 192, "xy"),
    ("earth", 192, 192, "xy"),
    ("plinth", 768, 192, "x"),
    ("wheat_green", 256, 192, None),
    ("wheat_gold", 256, 192, None),
    ("cotton", 256, 192, None),
    ("panjara", 192, 192, None),
    ("ceiling", 192, 192, "xy"),
    ("hay", 192, 192, "xy"),
    ("tileband", 768, 128, "x"),
    ("band2", 768, 128, "x"),
    ("sacks", 256, 128, "x"),
    ("stones", 128, 128, "xy"),
    ("iron", 128, 128, None),
    ("bronze", 128, 128, "x"),
    ("awning", 256, 128, None),
    ("carpet", 192, 128, None),
    ("logend", 96, 96, None),
    ("embers", 96, 96, None),
    ("pottery", 128, 96, "x"),
]


def _pack(specs):
    """Упаковка «по линии горизонта»: каждый прямоугольник (с полями) — в самое низкое место."""
    sky = [(0, SIZE, 0)]   # (x, ширина, высота занятого)
    out = {}
    specs = sorted(specs, key=lambda s: (-s[2], -s[1]))
    for name, w, h, rep in specs:
        W, H = w + 2 * PAD, h + 2 * PAD
        best = None
        for i in range(len(sky)):
            x = sky[i][0]
            if x + W > SIZE:
                break
            # высота над отрезком [x, x+W)
            y, j, need = 0, i, W
            while need > 0 and j < len(sky):
                y = max(y, sky[j][2])
                need -= sky[j][1] if j > i else sky[j][1]
                j += 1
            if need > 0:
                continue
            if y + H > SIZE:
                continue
            if best is None or y < best[1] or (y == best[1] and x < best[0]):
                best = (x, y)
        if best is None:
            raise RuntimeError(f"атлас: нет места для {name} {w}×{h}")
        x, y = best
        out[name] = (x + PAD, y + PAD, w, h, rep)
        # обновить горизонт
        new = []
        for sx, sw, sh in sky:
            a0, a1 = sx, sx + sw
            if a1 <= x or a0 >= x + W:
                new.append((sx, sw, sh))
                continue
            if a0 < x:
                new.append((a0, x - a0, sh))
            if a1 > x + W:
                new.append((x + W, a1 - x - W, sh))
        new.append((x, W, y + H))
        new.sort()
        # слить соседей одной высоты
        merged = []
        for s in new:
            if merged and merged[-1][2] == s[2] and merged[-1][0] + merged[-1][1] == s[0]:
                merged[-1] = (merged[-1][0], merged[-1][1] + s[1], s[2])
            else:
                merged.append(s)
        sky = merged
    return out


LAYOUT = _pack(SPECS)
REGIONS = {k: (x, y, x + w, y + h) for k, (x, y, w, h, _) in LAYOUT.items()}


def uv(name, inset=0.0):
    """Прямоугольник области в UV (u0, v0, u1, v1); inset — отступ внутрь в пикселях."""
    x0, y0, x1, y1 = REGIONS[name]
    return ((x0 + inset) / SIZE, (y0 + inset) / SIZE, (x1 - inset) / SIZE, (y1 - inset) / SIZE)


# ================================================================ стены

def paint_brick(w, h):
    """Обожжённый кирпич (ТЗ 11.3): тёплый, перевязка в полкирпича, светлые кромки и тень в швах."""
    c = Canvas(w, h, base=MORTAR[0], seed=11)
    c.underpaint(MORTAR, cell=40, seed=11)
    c.strokes(int(w * h / 300), MORTAR + ["#9c8a68"], length=(6, 16), width=(2, 4), angle=0, angle_jitter=90,
              alpha=(0.2, 0.4), bristles=1)
    rs = np.random.default_rng(12)
    tones = BRICK * 3 + BRICK_RARE
    B.bricks(c, 10, 8, tones, MORTAR, seed=13, chip=0.22, relief=0.8, light="#d8a070")
    # крупные пятна тона (обжиг неровный), копоть и выцветание пятнами
    n = B.noise(c, 90, seed=14)
    B.tint_ramp(c, n, "#c8a088", "#ffffff", 0.18)
    n2 = B.noise(c, 160, seed=15)
    B.multiply(c, 0.93 + 0.12 * n2)
    # общий слой мазков поверх кладки: связывает кирпичи в одну живописную поверхность
    c.strokes(int(w * h / 900), BRICK + ["#c8a080", "#8a5a40"], length=(30, 90), width=(10, 22), angle=0,
              angle_jitter=12, alpha=(0.05, 0.12), bristles=5, curve=0.2)
    # потёки: редкие вертикальные следы дождя
    c.strokes(28, ["#8a6a50", "#c8aa86"], length=(40, 120), width=(4, 9), angle=90, angle_jitter=4,
              alpha=(0.05, 0.12), bristles=3, curve=0.05)
    del rs
    c.grain(0.03)
    return c.image()


def paint_plinth(w, h):
    """Каменный цоколь: крупные скруглённые блоки в два ряда, тёплый серый камень."""
    c = Canvas(w, h, base="#5e564a", seed=21)
    c.underpaint(["#5e564a", "#544c42", "#665e50"], cell=40, seed=21)
    B.stones(c, 2, ["#7a7264", "#6e685c", "#857a66", "#746a58", "#8a7e68", "#625c52"], None, seed=22)
    n = B.noise(c, 80, seed=23)
    B.multiply(c, 0.92 + 0.14 * n)
    # верх цоколя — фаска светлее, низ темнее (земля, сырость)
    f = B.vgrad(c, [(0, 1.12), (10, 1.04), (h * 0.5, 1.0), (h - 24, 0.88), (h, 0.7)])
    B.multiply(c, f)
    c.strokes(int(w * 0.2), ["#6a5a44", "#5a4c3a", "#7a6a50"], length=(8, 24), width=(3, 7), angle=-90,
              angle_jitter=25, alpha=(0.1, 0.25), region=(0, h - 34, w, h), bristles=2)
    c.grain(0.03)
    return c.image()


def _kant(c: Canvas, y, width=7.0, seed=0, edge_above=True):
    """Золотой кант: тёмная обводка, золото, светлый блик по верхней кромке."""
    B.hline(c, y, width + 3.0, GOLD_D, seed=seed, wobble=0.3)
    B.hline(c, y, width, GOLD, seed=seed + 1, wobble=0.3)
    B.hline(c, y - width * 0.25, width * 0.3, GOLD_L, seed=seed + 2, alpha=0.8, wobble=0.3)


def paint_tileband(w, h):
    """Бирюзовый изразцовый пояс с золотым кантом (ТЗ 11.3): восьмиконечные звёзды и кресты
    по квадратным плиткам глазури. 8 звёзд на 3,2 м (шаг 0,4 м — делит шаг звеньев)."""
    c = Canvas(w, h, base=TURQ, seed=31)
    c.underpaint([TURQ, "#259488", "#30ad9e", EMERALD, "#2b9c8c"], cell=24, octaves=2, seed=31)
    y0, y1 = 13, h - 13
    # плитки: сетка 16 × 2, каждая чуть своего тона
    rs = np.random.default_rng(32)
    n_x, n_y = 16, 2
    tw, th = w / n_x, (y1 - y0) / n_y
    for i in range(n_x):
        for j in range(n_y):
            col = [TURQ, "#259488", "#2fae9f", "#27998c", EMERALD][rs.integers(5)]
            c.rect(i * tw + 1, y0 + j * th + 1, (i + 1) * tw - 1, y0 + (j + 1) * th - 1, col, 0.5)
    for i in range(n_x + 1):
        B.vline(c, i * tw, 1.6, TURQ_D, seed=i, alpha=0.7, y0=y0, y1=y1, wobble=0.2)
    B.hline(c, (y0 + y1) / 2, 1.6, TURQ_D, seed=3, alpha=0.6, wobble=0.2)
    cy = (y0 + y1) / 2
    period = w / 8
    for i in range(8):
        cx = (i + 0.5) * period
        star = B.star_points(cx, cy, 40, 24, 8, rot=math.pi / 8)
        c.polygon([(p[0] + 1.5, p[1] + 2) for p in star], TURQ_D, 0.6, wobble=0.2)
        c.polygon(star, CREAM, 1.0, wobble=0.3)
        c.line(star + [star[0]], 2.4, GOLD_D, 1.0, wobble=0.2, seed=i)
        inner = B.star_points(cx, cy, 22, 13, 8, rot=math.pi / 8)
        c.polygon(inner, EMERALD_D, 1.0, wobble=0.2)
        c.polygon(B.star_points(cx, cy, 10, 6, 8), GOLD, 1.0, wobble=0.2)
        # между звёздами — крест из ромбов (кобальт с золотом)
        x2 = i * period
        for dx, dy in ((0, -22), (0, 22), (-20, 0), (20, 0)):
            B.diamond(c, x2 + dx * 0.55, cy + dy * 0.55, 6, 9 if dx == 0 else 6, COBALT, GOLD_D, 1.2)
        B.diamond(c, x2, cy, 7, 7, GOLD, None)
    glaze_mask = B.rows(c, y0, y1, feather=1)
    B.glaze(c, glaze_mask, seed=33, strength=0.28)
    # свет: глазурь у верхней кромки светлее, низ темнее
    f = B.vgrad(c, [(0, 1.0), (y0, 1.12), (h * 0.5, 1.0), (y1, 0.86), (h, 0.8)])
    B.multiply(c, f)
    _kant(c, 6.5, 7.0, seed=1)
    _kant(c, h - 6.5, 7.0, seed=4)
    return c.image()


def paint_band2(w, h):
    """Надпись-фриз урды: белая вязь по кобальту, бирюзовые полоски, золотой кант."""
    c = Canvas(w, h, base=COBALT, seed=41)
    c.underpaint([COBALT, "#22467a", "#1b3866", "#264c80"], cell=24, octaves=2, seed=41)
    y0, y1 = 14, h - 14
    for y in (y0 + 5, y1 - 5):
        B.hline(c, y, 5, TURQ, seed=int(y), wobble=0.3)
    # «вязь»: высокие вертикали (алифы) и плавные петли — стилизованная надпись
    rs = np.random.default_rng(42)
    base_y = y1 - 22
    x = 6
    k = 0
    while x < w - 10:
        kind = rs.integers(4)
        col = "#f4efe2"
        if kind == 0:   # алиф — высокая вертикаль
            c.line([(x, base_y), (x + 1, y0 + 18)], 5.0, col, 1.0, wobble=0.3, seed=k)
            x += 14
        elif kind == 1:  # петля
            pts = [(x, base_y), (x + 10, base_y + 6), (x + 22, base_y), (x + 18, base_y - 12), (x + 8, base_y - 10),
                   (x + 6, base_y)]
            c.line(pts, 4.2, col, 1.0, wobble=0.3, seed=k)
            x += 28
        elif kind == 2:  # длинная горизонталь с хвостом
            pts = [(x, base_y - 4), (x + 30, base_y + 2), (x + 44, base_y - 2), (x + 48, base_y - 16)]
            c.line(pts, 4.2, col, 1.0, wobble=0.3, seed=k)
            x += 52
        else:            # точки и короткий штрих
            c.ellipse(x + 4, base_y - 30, 3.2, 3.2, col)
            c.ellipse(x + 12, base_y - 34, 3.2, 3.2, col)
            c.line([(x, base_y - 8), (x + 16, base_y - 14)], 4.0, col, 1.0, wobble=0.3, seed=k)
            x += 22
        k += 1
    # ислими на заднем плане: бирюзовые завитки
    n = 12
    for i in range(n):
        p = B.s_path(w / n, (y1 - y0) / 2 * 0.6, turns=1.1) + np.array([(i + 0.5) * w / n, (y0 + y1) / 2])
        c.line(p, 2.0, TURQ, 0.45, wobble=0.2, seed=100 + i)
    B.glaze(c, B.rows(c, y0, y1, 1), seed=43, strength=0.2)
    f = B.vgrad(c, [(0, 1.0), (y0, 1.12), (h * 0.5, 1.0), (y1, 0.86), (h, 0.8)])
    B.multiply(c, f)
    _kant(c, 6.5, 7.0, seed=7)
    _kant(c, h - 6.5, 7.0, seed=9)
    return c.image()


def paint_pakhsa(w, h):
    """Пахса (битая глина): слои по 0,8 м, каждый чуть нависает — тень под ним, светлый
    верх слоя; потёки дождя, трещины, дырки от опалубки, солома."""
    c = Canvas(w, h, base=PAKHSA[0], seed=51)
    B.clay(c, PAKHSA, STRAW, seed=51, trowel=False, density=0.8)
    layers = 3
    lh = h / layers
    rs = np.random.default_rng(52)
    for j in range(layers):
        y0 = j * lh
        # нарисованная лепка слоя: верх светлее (выпуклость к небу), низ темнее
        band = B.rows(c, y0, y0 + lh, feather=1)
        f = B.vgrad(c, [(y0, 1.12), (y0 + lh * 0.2, 1.05), (y0 + lh * 0.7, 0.97), (y0 + lh - 6, 0.86), (y0 + lh, 0.8)])
        B.multiply(c, 1 + (f - 1) * band)
        # шов слоя: тёмная линия-тень, над ней светлый край
        seam = y0 + lh
        pts = [(x, seam - 2 + 2.5 * math.sin(x / w * 2 * math.pi * 3 + j)) for x in np.linspace(0, w, 24)]
        c.line(pts, 7.0, "#6a5440", 0.35, wobble=2.0, seed=j)
        c.line([(p[0], p[1] - 5) for p in pts], 3.0, "#c8ac84", 0.25, wobble=2.0, seed=j + 10)
        # дырки от жердей опалубки вдоль шва
        for k in range(4):
            x = (k + 0.5) * w / 4 + rs.uniform(-20, 20)
            c.ellipse(x, seam - 9, 5, 4, "#3e2e20", 0.85)
            c.ellipse(x - 1, seam - 11, 3, 1.5, "#c8aa80", 0.5)
    # потёки дождя: вертикальные светлые и тёмные полосы
    c.strokes(60, ["#8a6e4c", "#c4a67a", "#7a6044"], length=(40, 140), width=(3, 9), angle=90, angle_jitter=5,
              alpha=(0.08, 0.22), bristles=3, curve=0.08)
    B.cracks(c, 14, "#4e3a28", seed=53, length=(20, 50))
    c.strokes(90, ["#7a6a58", "#a09080", "#5e5040"], length=(2, 5), width=(2, 4), angle=0, angle_jitter=180,
              alpha=(0.4, 0.8), bristles=0)   # камешки
    c.grain(0.035)
    return c.image()


def paint_clay(w, h):
    """Глиняная штукатурка (сомон сувоқ) домов: мазки мастерка, солома, редкие трещины."""
    c = Canvas(w, h, base=CLAY[0], seed=61)
    B.clay(c, CLAY, STRAW, seed=61, trowel=True)
    B.cracks(c, 8, "#5e4630", seed=62, length=(16, 44), width=1.2)
    n = B.noise(c, 120, seed=63)
    B.multiply(c, 0.94 + 0.1 * n)
    return c.image()


def paint_roof(w, h):
    """Плоская глиняная крыша сверху: замазка дугами мастерка, кочки травы, трещины, сырые пятна."""
    c = Canvas(w, h, base="#8e7454", seed=71)
    B.clay(c, ["#8e7454", "#84694a", "#9a7e5a", "#7a6044"], ["#c4a870", "#6a5236", "#d0b480"], seed=71,
           trowel=True, density=1.2)
    n = B.noise(c, 100, seed=72)
    B.tint_ramp(c, n, "#6a6a5a", "#ffffff", 0.25)   # сырые пятна холоднее
    B.cracks(c, 10, "#4a3824", seed=73, length=(20, 60), width=1.3)
    rs = np.random.default_rng(74)
    for _ in range(9):   # кочки травы на крыше (весной на глине прорастает)
        x, y = rs.uniform(0, w), rs.uniform(0, h)
        c.strokes(26, ["#6a7040", "#58602e", "#7e8048", "#4a5226"], length=(4, 11), width=(1.5, 3), angle=-90,
                  angle_jitter=50, alpha=(0.5, 0.9), bristles=0, curve=0.3,
                  region=(x - 9, y - 7, x + 9, y + 7))
    c.grain(0.03)
    return c.image()


def paint_earth(w, h):
    """Утоптанная земля двора: охра и пыль, следы, соломинки."""
    c = Canvas(w, h, base="#7a6448", seed=81)
    B.clay(c, ["#7a6448", "#6e5a40", "#86704f", "#5e4c36"], ["#a88a5a", "#4e3e2c"], seed=81, trowel=False)
    c.strokes(500, ["#8a7454", "#5a4832", "#9a8460"], length=(8, 20), width=(4, 8), angle=0, angle_jitter=180,
              alpha=(0.12, 0.3), bristles=3, curve=0.4)
    c.strokes(60, ["#b89a5e", "#a08446"], length=(5, 12), width=(1, 2), angle=0, angle_jitter=180,
              alpha=(0.4, 0.7), bristles=0)
    return c.image()


def paint_rubble(w, h):
    """Обломки сверху: битый кирпич, комья глины, пыль (руины, пролом стены)."""
    c = Canvas(w, h, base="#7e6650", seed=91)
    B.clay(c, ["#7e6650", "#6e5844", "#8a7058", "#5e4a38"], ["#a88a5a", "#4e3e2c"], seed=91, trowel=False)
    rs = np.random.default_rng(92)
    for i in range(170):
        x, y = rs.uniform(0, w), rs.uniform(0, h)
        s = rs.uniform(5, 14)
        a = rs.uniform(0, math.pi)
        col = (BRICK + ["#8a7a62", "#a08a6a", "#6a5a48"])[rs.integers(len(BRICK) + 3)]
        pts = [(x + math.cos(a + k * 1.7 + rs.uniform(-0.3, 0.3)) * s * rs.uniform(0.6, 1.0),
                y + math.sin(a + k * 1.7 + rs.uniform(-0.3, 0.3)) * s * rs.uniform(0.4, 0.8)) for k in range(4)]
        c.polygon([(p[0] + 2, p[1] + 2.5) for p in pts], "#2e2218", 0.5, wobble=0.5)
        c.polygon(pts, col, 1.0, wobble=0.6)
        c.line([pts[0], pts[1]], 1.4, "#f0c896", 0.35, wobble=0.3, seed=i)
    c.strokes(300, ["#9a8468", "#6a5640"], length=(6, 18), width=(3, 7), angle=0, angle_jitter=180,
              alpha=(0.1, 0.3), bristles=2, curve=0.4)
    return c.image()


# ================================================================ купол и портал

def paint_dome_tile(w, h):
    """Бирюзовый глазурованный купол: y=0 — вершина, y=h — низ у барабана. По x повторяется.
    Рёбра долей, ряды плиток, у вершины — золото навершия, у низа — пояс надписи."""
    c = Canvas(w, h, base=TURQ, seed=101)
    c.underpaint([TURQ, "#2fae9f", "#259488", "#36b8a6", EMERALD], cell=36, octaves=3, seed=101)
    gores = 8
    gw = w / gores
    rs = np.random.default_rng(102)
    # ряды плиток (смещение через ряд), каждая плитка своего тона
    rows_n = 16
    rh = (h - 70) / rows_n
    for j in range(rows_n):
        y = 18 + j * rh
        n_t = 32
        tw = w / n_t
        off = (j % 2) * tw / 2
        for i in range(-1, n_t + 1):
            col = [TURQ, "#2aa89c", "#31b3a2", "#25968a", "#3abda9", EMERALD][rs.integers(6)]
            c.rect(i * tw + off + 1, y + 1, (i + 1) * tw + off - 1, y + rh - 1, col, 0.55)
        B.hline(c, y, 1.4, TURQ_D, seed=j, alpha=0.55, wobble=0.3)
    # рёбра долей: тёмная тень, золотисто-светлая кромка
    for g in range(gores + 1):
        x = g * gw
        B.vline(c, x + 2.5, 5, TURQ_D, seed=g, alpha=0.8, wobble=0.4)
        B.vline(c, x, 3.0, "#bfe8d8", seed=g + 20, alpha=0.7, wobble=0.4)
    # каждая доля — выпуклая: середина светлее
    x = np.linspace(0, 1, w * c.ss)
    prof = 0.86 + 0.22 * np.sin(np.pi * ((x * gores) % 1.0)) ** 1.2
    B.multiply(c, np.repeat(prof[None, :], h * c.ss, axis=0))
    # вершина: золотое кольцо навершия
    gold = Canvas(w, h, base=GOLD, seed=103)
    gold.underpaint([GOLD, "#b48c3a", "#d8b45c", GOLD_D], cell=20, seed=103)
    B.paste_masked(c, gold, B.rows(c, -10, 16, 1.5))
    B.hline(c, 17, 3, GOLD_D, seed=5)
    # низ: пояс надписи (белое по кобальту) с золотым кантом
    y0, y1 = h - 52, h - 8
    band = Canvas(w, h, base=COBALT, seed=104)
    band.underpaint([COBALT, "#22467a", "#1b3866"], cell=20, seed=104)
    B.paste_masked(c, band, B.rows(c, y0, y1, 1.0))
    for i in range(16):
        x0 = i * w / 16
        c.line([(x0 + 6, y1 - 8), (x0 + 7, y0 + 8)], 3.4, CREAM, 1.0, wobble=0.3, seed=i)
        c.line([(x0 + 12, y1 - 10), (x0 + 24, y1 - 6), (x0 + 34, y1 - 12), (x0 + 30, y1 - 22)], 3.0, CREAM, 1.0,
               wobble=0.3, seed=i + 40)
    _kant(c, y0 - 2, 5.0, seed=11)
    _kant(c, y1 + 2, 5.0, seed=12)
    B.glaze(c, B.rows(c, 18, y0 - 6, 2), seed=105, strength=0.32, angle=-80)
    f = B.vgrad(c, [(0, 1.1), (h * 0.4, 1.04), (h * 0.85, 0.95), (h, 0.85)])
    B.multiply(c, f)
    return c.image()


def _portal_px(x, y, w, h):
    """Метры портала → пиксели области (x от середины, y от низа)."""
    P = PORTAL
    return (x / P["w"] + 0.5) * w, (1 - y / P["h"]) * h


def paint_portal(w, h):
    """Пештак урды: рамка-изразец со звёздами, золотой кант, кобальтовые паруса с ислими над
    стрельчатой аркой, белая надпись поверху, у низа — каменная панель. Проём арки
    вырезан геометрией (arch_curve(PORTAL))."""
    P = PORTAL
    c = Canvas(w, h, base=COBALT, seed=111, tile=False)
    c.underpaint([COBALT, "#22467a", "#1b3866", "#264c80"], cell=40, seed=111)
    px = lambda x, y: _portal_px(x, y, w, h)
    ppm = w / P["w"]
    # внешняя рамка: бирюзовая полоса со звёздами по всему пештаку
    fr = P["frame"] * ppm
    turq = Canvas(w, h, base=TURQ, seed=112, tile=False)
    turq.underpaint([TURQ, "#259488", "#30ad9e", EMERALD], cell=20, seed=112)
    yy, xx = np.mgrid[0:h * c.ss, 0:w * c.ss] / c.ss
    d_edge = np.minimum.reduce([xx, w - xx, yy])
    frame_mask = np.clip((fr - d_edge) / 1.0, 0, 1) * (yy < h - 1.25 * ppm)
    B.paste_masked(c, turq, frame_mask)
    # звёзды по рамке
    step = fr * 1.25
    for s in np.arange(step / 2, h - 1.3 * ppm, step):
        for x in (fr / 2, w - fr / 2):
            st = B.star_points(x, s, fr * 0.36, fr * 0.2, 8, rot=math.pi / 8)
            c.polygon(st, CREAM, 1.0, wobble=0.2)
            c.line(st + [st[0]], 1.6, GOLD_D, 1.0, wobble=0.2)
            c.polygon(B.star_points(x, s, fr * 0.15, fr * 0.09, 8), GOLD, 1.0, wobble=0.2)
    for s in np.arange(fr * 1.5, w - fr, step):
        st = B.star_points(s, fr / 2, fr * 0.36, fr * 0.2, 8, rot=math.pi / 8)
        c.polygon(st, CREAM, 1.0, wobble=0.2)
        c.line(st + [st[0]], 1.6, GOLD_D, 1.0, wobble=0.2)
        c.polygon(B.star_points(s, fr / 2, fr * 0.15, fr * 0.09, 8), GOLD, 1.0, wobble=0.2)
    for x in (fr, w - fr):
        c.line([(x, fr if x else 0), (x, h - 1.25 * ppm)], 4, GOLD, 1.0, wobble=0.3)
    c.line([(fr, fr), (w - fr, fr)], 4, GOLD, 1.0, wobble=0.3)
    # надпись поверху (под рамкой)
    ins_y0, ins_y1 = fr + 6, fr + 0.95 * ppm
    for i in range(14):
        x0 = fr + 8 + i * (w - 2 * fr - 16) / 14
        c.line([(x0, ins_y1 - 6), (x0 + 1, ins_y0 + 6)], 4.0, CREAM, 1.0, wobble=0.3, seed=i)
        c.line([(x0 + 5, ins_y1 - 8), (x0 + 14, ins_y1 - 3), (x0 + 22, ins_y1 - 9), (x0 + 18, ins_y1 - 18)], 3.4,
               CREAM, 1.0, wobble=0.3, seed=i + 30)
    B.hline(c, ins_y1 + 5, 4, GOLD, seed=3, x0=fr, x1=w - fr)
    # паруса: ислими (бирюза и белое)
    arch = arch_curve(P["aw"] + P["border"], P["hs"], P["ha"] + P["border"], 24)
    ap = np.array([px(*p) for p in arch])
    top_y = ins_y1 + 10
    for side in (-1, 1):
        cx = w / 2 + side * (w / 2 - fr) * 0.55
        cy = (top_y + px(0, P["hs"] + 0.6)[1]) / 2
        for k in range(3):
            p = B.s_path(70, 26, 1.2)
            ang = math.radians(side * 30 + k * 60)
            R = np.array([[math.cos(ang), -math.sin(ang)], [math.sin(ang), math.cos(ang)]])
            q = p @ R.T * (0.8 + 0.15 * k) + np.array([cx, cy])
            c.line(q, 4.0, TURQ_L, 0.95, wobble=0.3, seed=k + side * 5)
            c.line(q, 1.6, CREAM, 0.9, wobble=0.3, seed=k + side * 7)
        for k in range(6):
            a = k * math.pi / 3
            B.leaf(c, cx + math.cos(a) * 30, cy + math.sin(a) * 30, 22, 9, math.degrees(a), CREAM, 0.95)
        c.polygon(B.star_points(cx, cy, 16, 9, 8), GOLD, 1.0, wobble=0.2)
    # обводка арки: широкая бирюзовая лента с золотым кантом и «плетёнкой»
    inner = arch_curve(P["aw"], P["hs"], P["ha"], 24)
    ip = np.array([px(*p) for p in inner])
    bw = P["border"] * ppm
    mid = (ap + ip) / 2
    c.line(mid, bw, TURQ, 1.0, wobble=0.3)
    c.line(mid, bw * 0.45, EMERALD_D, 0.8, wobble=0.3)
    for t in range(0, len(mid), 2):
        c.ellipse(mid[t][0], mid[t][1], bw * 0.18, bw * 0.18, GOLD, 1.0)
    c.line(ap, 4.5, GOLD, 1.0, wobble=0.3)
    c.line(ip, 4.5, GOLD, 1.0, wobble=0.3)
    # опоры арки до пят: изразцовые панели с узкой нишей
    for side in (-1, 1):
        x0, x1 = sorted((px(side * (P["aw"] + P["border"]), 0)[0], px(side * (P["w"] / 2 - P["frame"]), 0)[0]))
        y0, y1 = px(0, P["hs"])[1], px(0, 1.25)[1]
        c.rect(x0 + 6, y0 + 6, x1 - 6, y1 - 6, TURQ_D, 1.0)
        nx0, nx1 = x0 + (x1 - x0) * 0.25, x1 - (x1 - x0) * 0.25
        c.rect(nx0, y0 + 30, nx1, y1 - 14, COBALT_D, 1.0)
        c.line([(nx0, y1 - 14), (nx0, y0 + 40), ((nx0 + nx1) / 2, y0 + 22), (nx1, y0 + 40), (nx1, y1 - 14)], 3,
               GOLD, 1.0, wobble=0.3)
        for k in range(4):
            st = B.star_points((nx0 + nx1) / 2, y0 + 60 + k * (y1 - y0 - 90) / 4, 9, 5, 8)
            c.polygon(st, TURQ_L, 1.0, wobble=0.2)
        c.line([(x0 + 6, y0 + 6), (x1 - 6, y0 + 6), (x1 - 6, y1 - 6), (x0 + 6, y1 - 6), (x0 + 6, y0 + 6)], 3, GOLD,
               1.0, wobble=0.3)
    # низ: каменная панель (мрамор/камень)
    ys = px(0, 1.25)[1]
    stone = Canvas(w, h, base="#a49a86", seed=113, tile=False)
    stone.underpaint(["#a49a86", "#958b78", "#b0a690"], cell=30, seed=113)
    stone.strokes(400, ["#c4baa4", "#8a806e"], length=(10, 30), width=(3, 7), angle=-20, angle_jitter=30,
                  alpha=(0.2, 0.4), bristles=2)
    B.paste_masked(c, stone, B.rows(c, ys, h + 10, 1.0))
    B.hline(c, ys, 5, GOLD_D, seed=8)
    for x in np.linspace(0, w, 6):
        c.line([(x, ys + 4), (x, h)], 2, "#6e6656", 0.7, wobble=0.3)
    B.glaze(c, (np.asarray(B.rows(c, 0, ys, 1)) > 0.5).astype(float), seed=114, strength=0.22)
    f = B.vgrad(c, [(0, 1.08), (h * 0.5, 1.0), (h, 0.82)])
    B.multiply(c, f)
    return c.image()


# ================================================================ дерево

def paint_walnut(w, h):
    c = Canvas(w, h, base=MATERIAL["walnut"], seed=121)
    B.wood(c, WALNUT, WALNUT_GRAIN, vertical=True, seed=121, knots=4)
    return c.image()


def paint_wood(w, h):
    """Светлое тополиное дерево: балки, жерди, лестницы, рамы."""
    c = Canvas(w, h, base=MATERIAL["wood_light"], seed=125)
    B.wood(c, ["#9a7a52", "#8a6c48", "#a9895e", "#7c6040"], ["#5e4630", "#b89a6e", "#6e5438"], vertical=True,
           seed=125, knots=5)
    return c.image()


def paint_bark(w, h):
    c = Canvas(w, h, base="#5e4c3a", seed=127)
    B.wood(c, ["#5e4c3a", "#4e3e30", "#6c5a44", "#3e3226"], ["#2e241a", "#7e6a50", "#45372a"], vertical=True,
           seed=127, knots=6, density=1.4)
    c.strokes(160, ["#2a2018", "#3a2e22"], length=(10, 30), width=(1.5, 3), angle=90, angle_jitter=8,
              alpha=(0.4, 0.8), bristles=0)
    return c.image()


def paint_pole(w, h):
    c = Canvas(w, h, base="#8a6e4c", seed=129)
    B.wood(c, ["#8a6e4c", "#7a6040", "#987a56", "#6e563a"], ["#4a3a2a", "#a88a62", "#56442e"], vertical=True,
           seed=129, knots=3)
    x = np.linspace(0, 1, w * c.ss)
    prof = 0.8 + 0.3 * np.sin(np.pi * x) ** 1.5
    B.multiply(c, np.repeat(prof[None, :], h * c.ss, axis=0))
    return c.image()


def paint_rope(w, h):
    c = Canvas(w, h, base="#8f7550", seed=131)
    c.underpaint(["#8f7550", "#857049", "#9a8058"], cell=16, seed=131)
    step = 10
    for y in np.arange(-step, h + step, step):
        c.line([(0, y), (w, y + step * 0.9)], 4, "#6e5a3e", 0.7, wobble=0.3, seed=int(y) + 3)
        c.line([(0, y + 3), (w, y + 3 + step * 0.9)], 2, "#c2a77a", 0.6, wobble=0.3, seed=int(y) + 5)
    x = np.linspace(0, 1, w * c.ss)
    prof = 0.62 + 0.55 * np.sin(np.pi * x) ** 0.8
    B.multiply(c, np.repeat(prof[None, :], h * c.ss, axis=0))
    return c.image()


def paint_planks(w, h):
    """Доски (настилы лесов, ворота склада): 4 доски на 2 м, щели, гвозди."""
    c = Canvas(w, h, base="#86684a", seed=133)
    B.wood(c, ["#86684a", "#76593e", "#94785a", "#6a5038"], ["#4e3a28", "#a88a66", "#5a4430"], vertical=False,
           seed=133, knots=4)
    for y in np.arange(0, h, h / 4):
        c.line([(-4, y), (w + 4, y)], 3.2, "#2e2018", 0.9, wobble=0.6, seed=int(y))
        c.line([(-4, y + 3), (w + 4, y + 3)], 1.4, "#b89a76", 0.6, wobble=0.6, seed=int(y) + 1)
        for x in (w * 0.2, w * 0.7):
            c.ellipse(x, y + h / 8, 2.4, 2.4, "#2a201a", 0.9)
    return c.image()


def paint_logend(w, h):
    c = Canvas(w, h, base="#b08a5e", seed=135, tile=False)
    c.underpaint(["#b08a5e", "#a07a50", "#c09a6a"], cell=16, seed=135)
    for r in np.arange(4, w / 2 - 6, 4.5):
        pts = [(w / 2 + r * math.cos(a), h / 2 + r * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 40)]
        c.line(pts, 1.2, "#7a5a3a", 0.55, wobble=0.5, seed=int(r))
    pts = [(w / 2 + (w / 2 - 4) * math.cos(a), h / 2 + (h / 2 - 4) * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 50)]
    c.line(pts, 7, "#4a3a2a", 1.0, wobble=0.6)
    return c.image()


def _girih_panel(c: Canvas, x0, y0, x1, y1, groove, light, body, field, step=None, seed=0):
    """Резная панель с решёткой восьмиконечных звёзд (резьба: тень паза, светлая кромка)."""
    c.rect(x0 - 2, y0 - 2, x1 + 2, y1 + 2, groove, 0.9)
    c.rect(x0, y0, x1, y1, field, 1.0)
    w, h = x1 - x0, y1 - y0
    step = step or min(w, h) / 2
    nx = max(1, int(round(w / step)))
    ny = max(1, int(round(h / step)))
    sx, sy = w / nx, h / ny

    def motif(color, dx, dy):
        for i in range(nx):
            for j in range(ny):
                cx, cy = x0 + (i + 0.5) * sx + dx, y0 + (j + 0.5) * sy + dy
                st = B.star_points(cx, cy, min(sx, sy) * 0.42, min(sx, sy) * 0.26, 8, rot=math.pi / 8)
                c.line(st + [st[0]], max(1.4, min(sx, sy) * 0.07), color, 1.0, wobble=0.2, seed=seed + i * 7 + j)
        for i in range(nx + 1):
            for j in range(ny + 1):
                B.diamond(c, x0 + i * sx + dx, y0 + j * sy + dy, sx * 0.12, sy * 0.12, color)
    B.emboss(motif, light, groove, body, off=1.2)


def paint_door(w, h):
    """Резная ореховая дверь (две створки): гирих-панели, верхняя панель со звездой, латунные кольца."""
    c = Canvas(w, h, base=WALNUT[0], seed=141, tile=False)
    B.wood(c, ["#6a4a2e", "#5a3b24", "#76533a", "#4e3420"], WALNUT_GRAIN, vertical=True, seed=141, knots=2)
    mid = w / 2
    groove, light, body = "#1e120a", "#d8a868", "#8a6040"
    for leaf in (0, 1):
        x0 = leaf * mid + 8
        x1 = x0 + mid - 16
        f = h / 512
        panels = [(12, 92 * f, 1), (106 * f, 330 * f, 2), (344 * f, 430 * f, 1), (444 * f, h - 12, 1)]
        for k, (py0, py1, kind) in enumerate(panels):
            _girih_panel(c, x0 + 6, py0, x1 - 6, py1, groove, light, body, "#4a2e1c",
                         step=(x1 - x0 - 12) / (1 if kind == 1 else 2), seed=k * 13 + leaf)
        # кольцо-колотушка
        cx, cy = (x1 - 10) if leaf == 0 else (x0 + 10), h * 0.58
        c.ellipse(cx + 1, cy + 1, 9, 9, "#120a06", 0.6)
        pts = [(cx + 8 * math.cos(a), cy + 8 * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 30)]
        c.line(pts, 3.4, "#c99a48", 1.0, wobble=0.2)
        c.ellipse(cx, cy - 8, 3.6, 3.6, "#e8c070", 1.0)
    c.rect(mid - 2.5, 0, mid + 2.5, h, "#140a05", 0.95)
    f = B.vgrad(c, [(0, 1.08), (h * 0.5, 1.0), (h, 0.76)])
    B.tint_ramp(c, f, "#2a1e22", "#ffffff", 1.0)
    return c.image()


def paint_gate(w, h):
    """Створка больших ворот: вертикальные доски ореха, железные полосы, ряды кованых гвоздей
    с латунными шляпками, кольцо. Вторая створка — то же зеркально (UV)."""
    c = Canvas(w, h, base="#5e3e26", seed=151, tile=False)
    B.wood(c, ["#5e3e26", "#4e3220", "#6a4630", "#553823"], ["#2e1c12", "#7a5338", "#3a2418"], vertical=True,
           seed=151, knots=3)
    n = 6
    for i in range(1, n):
        x = i * w / n
        c.line([(x, 0), (x, h)], 3.2, "#1e120a", 0.9, wobble=0.5, seed=i)
        c.line([(x + 3, 0), (x + 3, h)], 1.4, "#a87a50", 0.5, wobble=0.5, seed=i + 9)
    for y in (h * 0.12, h * 0.5, h * 0.88):
        c.rect(0, y - 11, w, y + 11, "#2e2a28", 1.0)
        c.strokes(30, ["#4a4440", "#1e1a18", "#6a4a34"], length=(10, 30), width=(3, 6), angle=0, angle_jitter=4,
                  alpha=(0.3, 0.6), bristles=2, region=(0, y - 10, w, y + 10))
        B.hline(c, y - 10, 1.6, "#8a8078", seed=int(y), alpha=0.6)
        for x in np.linspace(14, w - 14, 9):
            c.ellipse(x + 1.5, y + 1.5, 6, 6, "#0e0a08", 0.7)
            c.ellipse(x, y, 5.2, 5.2, "#b88a3e", 1.0)
            c.ellipse(x - 1.6, y - 1.6, 2, 2, "#f6dc96", 1.0)
    for yy in np.linspace(h * 0.2, h * 0.8, 5):
        for xx in np.linspace(w * 0.15, w * 0.85, 4):
            c.ellipse(xx + 1, yy + 1, 3.6, 3.6, "#0e0a08", 0.6)
            c.ellipse(xx, yy, 3, 3, "#9a7a3e", 1.0)
    cx, cy = w * 0.86, h * 0.6
    pts = [(cx + 16 * math.cos(a), cy + 16 * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 36)]
    c.line([(p[0] + 2, p[1] + 2) for p in pts], 5, "#0e0a08", 0.6, wobble=0.2)
    c.line(pts, 4.4, "#c99a48", 1.0, wobble=0.2)
    c.rect(0, 0, 8, h, "#2a1a10", 0.8)
    f = B.vgrad(c, [(0, 1.06), (h * 0.5, 1.0), (h, 0.78)])
    B.tint_ramp(c, f, "#2a1e22", "#ffffff", 1.0)
    return c.image()


def paint_column(w, h):
    """Резная ореховая колонна-устун (по x — вокруг ствола, повтор): сверху капитель со
    сталактитами, ствол с резными поясами, снизу пузатая база с лепестками."""
    c = Canvas(w, h, base="#6a4a2e", seed=161)
    B.wood(c, ["#6a4a2e", "#5a3b24", "#76533a", "#4e3420"], WALNUT_GRAIN, vertical=True, seed=161, knots=2)
    groove, light, body = "#1e120a", "#e0b070", "#9a7048"
    cap = 80
    base0 = h - 120

    def capital(color, dx, dy):
        for r in range(3):
            y = 10 + r * 22
            n = 4 + r
            for i in range(n):
                x0 = i * w / n
                pts = [(x0 + dx, y + 20 + dy), (x0 + dx, y + 8 + dy), (x0 + w / n / 2 + dx, y + dy),
                       (x0 + w / n + dx, y + 8 + dy), (x0 + w / n + dx, y + 20 + dy)]
                c.line(pts, 2.2, color, 1.0, wobble=0.2, seed=r * 10 + i)

    B.emboss(capital, light, groove, body, off=1.2)
    for y in (cap, base0):
        B.hline(c, y, 4, groove, seed=int(y))
        B.hline(c, y - 3, 1.6, light, seed=int(y) + 1, alpha=0.7)
    # пояса резьбы на стволе: зигзаг и ромбы
    for yb in (cap + 50, (cap + base0) / 2, base0 - 50):
        def belt(color, dx, dy, yb=yb):
            pts = [(x + dx, yb + (8 if i % 2 else -8) + dy) for i, x in enumerate(np.linspace(-8, w + 8, 11))]
            c.line(pts, 2.4, color, 1.0, wobble=0.2, seed=int(yb))
            for i in range(5):
                B.diamond(c, (i + 0.5) * w / 5 + dx, yb + dy, 5, 6, color)
        B.emboss(belt, light, groove, body, off=1.0)
    # каннелюры между поясами
    for i in range(8):
        x = (i + 0.5) * w / 8
        c.line([(x, cap + 70), (x, base0 - 70)], 2.0, groove, 0.45, wobble=0.4, seed=i)
        c.line([(x - 2, cap + 70), (x - 2, base0 - 70)], 1.0, light, 0.3, wobble=0.4, seed=i + 20)

    # база: лепестки
    def petals(color, dx, dy):
        for i in range(6):
            x0 = i * w / 6
            pts = [(x0 + dx, h - 10 + dy), (x0 + w / 12 + dx, base0 + 20 + dy), (x0 + w / 6 + dx, h - 10 + dy)]
            c.line(pts, 2.6, color, 1.0, wobble=0.2, seed=i + 40)
    B.emboss(petals, light, groove, body, off=1.2)
    x = np.linspace(0, 1, w * c.ss)
    return c.image()


def paint_panjara(w, h):
    """Резная деревянная решётка окна (панжара): гирих из звёзд, тёмные прорези."""
    c = Canvas(w, h, base="#1a120c", seed=171, tile=False)
    c.underpaint(["#1a120c", "#24180e", "#140e08"], cell=30, seed=171)
    # рама
    c.rect(0, 0, w, 12, "#5a3b24", 1.0)
    c.rect(0, h - 12, w, h, "#5a3b24", 1.0)
    c.rect(0, 0, 12, h, "#5a3b24", 1.0)
    c.rect(w - 12, 0, w, h, "#5a3b24", 1.0)
    n = 3
    s = (w - 24) / n
    for i in range(n + 1):
        for j in range(n + 1):
            cx, cy = 12 + i * s, 12 + j * s
            st = B.star_points(cx, cy, s * 0.5, s * 0.3, 8, rot=math.pi / 8)
            c.line(st + [st[0]], 6, "#6a4a30", 1.0, wobble=0.2)
            c.line(st + [st[0]], 2, "#b08058", 0.6, wobble=0.2)
    for i in range(n):
        for j in range(n):
            cx, cy = 12 + (i + 0.5) * s, 12 + (j + 0.5) * s
            B.diamond(c, cx, cy, s * 0.22, s * 0.22, "#6a4a30", "#b08058", 1.5)
    f = B.vgrad(c, [(0, 1.1), (h, 0.85)])
    B.multiply(c, f)
    return c.image()


def paint_ceiling(w, h):
    """Расписной потолок айвана: круглые балки-васса и расписные дощечки между ними."""
    c = Canvas(w, h, base="#6a2a1e", seed=181)
    c.underpaint(["#6a2a1e", "#7a3424", "#5e2418"], cell=24, seed=181)
    n = 6
    bw = w / n
    for i in range(n):
        x = i * bw
        # доска между балками: красное поле, зелёные и золотые цветы
        for k in range(4):
            cy = (k + 0.5) * h / 4
            cx = x + bw / 2
            for a in range(6):
                ang = a * math.pi / 3
                B.leaf(c, cx + math.cos(ang) * 6, cy + math.sin(ang) * 6, 10, 5, math.degrees(ang), "#3a8a5a", 1.0)
            c.ellipse(cx, cy, 4, 4, GOLD, 1.0)
        # балка
        c.rect(x - 7, 0, x + 7, h, "#4a3020", 1.0)
        c.line([(x - 3, 0), (x - 3, h)], 2.4, "#9a7048", 0.7, wobble=0.4)
        c.line([(x + 6, 0), (x + 6, h)], 2.4, "#24160c", 0.7, wobble=0.4)
    return c.image()


# ================================================================ поле и вода

def paint_furrows(w, h):
    """Вспаханное поле: борозды вдоль v (8 на плитку, шаг 0,5 м); гребень освещён слева
    (солнце с запада), в бороздах — сырость и местами вода от полива."""
    c = Canvas(w, h, base="#5a4430", seed=191)
    c.underpaint(["#5a4430", "#4e3a28", "#664e36", "#544030"], cell=48, seed=191)
    period = w / FURROW_ROWS
    x = np.linspace(0, 1, w * c.ss) * FURROW_ROWS % 1.0
    ridge = 0.78 + 0.34 * np.clip(np.sin(np.pi * x) * 1.1, 0, 1) ** 0.8
    lit = 1.0 + 0.16 * np.clip(np.cos(np.pi * x * 2 + 0.6), -1, 1) * (x < 0.5)
    B.multiply(c, np.repeat((ridge * lit)[None, :], h * c.ss, axis=0))
    rs = np.random.default_rng(192)
    for i in range(FURROW_ROWS):
        x0 = i * period
        # комья на гребне
        c.strokes(70, ["#7a6044", "#6a523a", "#4a3826", "#8a6e4e"], length=(4, 12), width=(3, 7), angle=90,
                  angle_jitter=40, alpha=(0.3, 0.7), bristles=2, region=(x0 + period * 0.2, 0, x0 + period * 0.75, h))
        # дно борозды: тёмная сырость, местами блики воды
        c.strokes(40, ["#3a2c20", "#2e241a"], length=(20, 60), width=(3, 6), angle=90, angle_jitter=3,
                  alpha=(0.3, 0.6), bristles=1, region=(x0 - 3, 0, x0 + 3, h))
        if i % 2 == 0:
            for _ in range(4):
                y = rs.uniform(0, h)
                c.line([(x0 + rs.uniform(-1, 1), y), (x0 + rs.uniform(-1, 1), y + rs.uniform(20, 60))], 2.4,
                       "#6a7a80", 0.28, wobble=0.6, seed=int(y))
    c.grain(0.04)
    return c.image()


def _canopy(c: Canvas, cols, soil, density, length, width, seed):
    period = c.w / FURROW_ROWS
    for i in range(FURROW_ROWS):
        x0 = i * period
        c.strokes(int(density), cols, length=length, width=width, angle=-90, angle_jitter=35, alpha=(0.45, 0.9),
                  bristles=2, curve=0.3, region=(x0 + period * 0.2, 0, x0 + period * 0.95, c.h))
        c.strokes(int(density * 0.2), soil, length=(10, 30), width=(2, 4), angle=90, angle_jitter=3,
                  alpha=(0.3, 0.6), bristles=1, region=(x0 - 2, 0, x0 + 3, c.h))


def paint_canopy_green(w, h):
    """Молодые всходы сверху: зелёные ряды, между ними — земля борозд."""
    c = Canvas(w, h, base="#4e3a28", seed=201)
    c.underpaint(["#4e3a28", "#5a4430", "#46341f"], cell=40, seed=201)
    _canopy(c, ["#5e7a34", "#4a6a2a", "#7a9442", "#3e5a24", "#6a8a3a"], ["#3a2c20"], 900, (6, 16), (2, 4.5), 202)
    c.grain(0.03)
    return c.image()


def paint_canopy_gold(w, h):
    """Спелая пшеница сверху: плотные золотые колосья рядами, тени между рядами."""
    c = Canvas(w, h, base="#7a5e2a", seed=211)
    c.underpaint(["#7a5e2a", "#8a6c30", "#6a5022"], cell=40, seed=211)
    _canopy(c, ["#d8b45c", "#c8a048", "#e8c870", "#b08a3a", "#f0d888"], ["#4a3a1e"], 1400, (6, 16), (2.5, 5), 212)
    c.strokes(400, ["#f4e0a0", "#e0c070"], length=(3, 7), width=(1.2, 2.4), angle=-60, angle_jitter=40,
              alpha=(0.4, 0.8), bristles=0)
    c.grain(0.03)
    return c.image()


def _with_alpha(img: Image.Image, alpha) -> Image.Image:
    a = np.asarray(alpha, dtype=np.float64)
    out = np.dstack([np.asarray(img.convert("RGB")), (np.clip(a, 0, 1) * 255).astype(np.uint8)])
    return Image.fromarray(out, "RGBA")


def _alpha_canvas(w, h, seed):
    """Холст и маска альфы (рисуем мазки и в цвет, и в маску одинаково)."""
    c = Canvas(w, h, base="#000000", seed=seed, tile=False)
    m = Canvas(w, h, base="#000000", seed=seed, tile=False)
    return c, m


def _stalk(c, m, pts, width, col):
    c.line(pts, width, col, 1.0, wobble=0.2)
    m.line(pts, width, "#ffffff", 1.0, wobble=0.2)


def _ear(c, m, x, y, ang, L, col, awns):
    d = np.array([math.cos(ang), math.sin(ang)])
    n = np.array([-d[1], d[0]])
    for k in range(6):
        t = k / 5
        p = np.array([x, y]) + d * L * t
        for s in (-1, 1):
            q = p + n * s * 2.4 * (1 - 0.5 * t)
            c.ellipse(q[0], q[1], 2.6, 3.2, col, 1.0)
            m.ellipse(q[0], q[1], 2.6, 3.2, "#ffffff", 1.0)
            if awns:
                e = q + (d * 0.8 + n * s * 0.6) * 9
                c.line([q, e], 0.9, "#f0dca0", 0.9, wobble=0.1)
                m.line([q, e], 0.9, "#ffffff", 0.9, wobble=0.1)


def paint_wheat(w, h, ripe=True):
    """Карточка колосьев (вырез по альфе): стебли от низа, сверху колос с остями.
    Молодая — короче, без колоса, широкие листья."""
    c, m = _alpha_canvas(w, h, 221 + ripe)
    rs = np.random.default_rng(222 + ripe)
    n = 90 if ripe else 110
    for i in range(n):
        x = rs.uniform(4, w - 4)
        top = rs.uniform(h * 0.05, h * 0.3) if ripe else rs.uniform(h * 0.35, h * 0.7)
        lean = rs.normal(0, 10)
        pts = [(x, h), (x + lean * 0.3, (h + top) / 2), (x + lean, top)]
        if ripe:
            col = ["#c8a048", "#b08a3a", "#d8b45c", "#a07a30"][rs.integers(4)]
            _stalk(c, m, pts, 1.6, col)
            ang = math.atan2(top - (h + top) / 2, lean * 0.7) + math.pi
            ang = -math.pi / 2 + math.radians(lean * 1.5) + rs.normal(0, 0.15)
            _ear(c, m, x + lean, top, ang, 22, ["#e0bc60", "#d0a848", "#f0d07a"][rs.integers(3)], True)
        else:
            col = ["#5e7a34", "#4a6a2a", "#7a9442", "#6a8a3a"][rs.integers(4)]
            _stalk(c, m, pts, 2.6, col)
            # лист вбок
            lx = x + lean * 0.4 + rs.choice([-1, 1]) * rs.uniform(10, 22)
            ly = (h + top) / 2 + rs.uniform(-10, 10)
            _stalk(c, m, [(x + lean * 0.3, (h + top) / 2 + 10), ((x + lx) / 2, ly - 8), (lx, ly)], 2.2, col)
    # свет: верх светлее, низ в тени (к земле густо)
    img = np.asarray(c.image(), dtype=np.float64)
    y = np.linspace(0, 1, h)[:, None, None]
    img *= 0.55 + 0.55 * (1 - y) ** 0.7
    a = np.asarray(m.image().convert("L"), dtype=np.float64) / 255
    return _with_alpha(Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)), a)


def paint_cotton(w, h):
    """Кусты хлопка: тёмно-зелёные листья, белые коробочки (вырез по альфе)."""
    c, m = _alpha_canvas(w, h, 231)
    rs = np.random.default_rng(232)
    for i in range(10):
        cx = (i + 0.5) * w / 10 + rs.uniform(-6, 6)
        top = rs.uniform(h * 0.15, h * 0.35)
        _stalk(c, m, [(cx, h), (cx + rs.uniform(-4, 4), top + 20)], 2.4, "#4a3a22")
        for k in range(14):
            x = cx + rs.normal(0, 13)
            y = rs.uniform(top, h * 0.85)
            col = ["#3e5a2a", "#4a6a30", "#2e4a22", "#5a7a38"][rs.integers(4)]
            B.leaf(c, x, y, rs.uniform(12, 18), rs.uniform(8, 12), rs.uniform(-160, -20), col)
            B.leaf(m, x, y, rs.uniform(12, 18), rs.uniform(8, 12), rs.uniform(-160, -20), "#ffffff")
        for k in range(6):
            x = cx + rs.normal(0, 11)
            y = rs.uniform(top, h * 0.7)
            r = rs.uniform(3.5, 5.5)
            c.ellipse(x + 1, y + 1, r, r, "#8a8270", 1.0)
            c.ellipse(x, y, r, r, "#f4f0e4", 1.0)
            m.ellipse(x, y, r + 1, r + 1, "#ffffff", 1.0)
    img = np.asarray(c.image(), dtype=np.float64)
    y = np.linspace(0, 1, h)[:, None, None]
    img *= 0.6 + 0.5 * (1 - y) ** 0.7
    a = np.asarray(m.image().convert("L"), dtype=np.float64) / 255
    return _with_alpha(Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)), a)


def paint_water(w, h):
    """Вода арыка: мутная бирюза, вдоль течения (v) блики неба и тёплые отсветы заката."""
    c = Canvas(w, h, base="#2e4a50", seed=241)
    c.underpaint(["#2e4a50", "#34545a", "#264046", "#3a5a5e"], cell=24, seed=241)
    c.strokes(90, ["#5a7a80", "#7a9aa0", "#c8a080", "#e0b48a"], length=(20, 60), width=(1.5, 3.5), angle=90,
              angle_jitter=4, alpha=(0.2, 0.55), bristles=1, curve=0.1)
    x = np.linspace(0, 1, w * c.ss)
    prof = 0.75 + 0.3 * np.sin(np.pi * x)
    B.multiply(c, np.repeat(prof[None, :], h * c.ss, axis=0))
    return c.image()


# ================================================================ мелочи

def paint_hay(w, h):
    c = Canvas(w, h, base="#a88a4a", seed=251)
    c.underpaint(["#a88a4a", "#8e7238", "#c2a462", "#6e5628"], cell=32, seed=251)
    c.strokes(1600, ["#d6b870", "#b89850", "#8a6c34", "#e8cc86", "#6a5228"], length=(12, 34), width=(1.4, 3.0),
              angle=0, angle_jitter=180, alpha=(0.4, 0.85), bristles=1, curve=0.15, taper=0.3)
    c.grain(0.04)
    return c.image()


def paint_sacks(w, h):
    """Мешковина: по x — вокруг мешка (повтор), по y — от горловины (верх) к дну."""
    c = Canvas(w, h, base="#b09a72", seed=261)
    c.underpaint(["#b09a72", "#a08a64", "#bea882", "#98825c"], cell=24, seed=261)
    for y in np.arange(0, h, 3):
        c.line([(0, y), (w, y)], 1.0, "#8a7452", 0.25, wobble=0.4, seed=int(y))
    for x in np.arange(0, w, 3):
        c.line([(x, 0), (x, h)], 1.0, "#c8b48e", 0.18, wobble=0.4, seed=int(x) + 500)
    for x in (w * 0.25, w * 0.75):   # шов
        c.line([(x, 0), (x, h)], 2.0, "#6e5a3a", 0.8, wobble=0.6)
        for y in np.arange(4, h, 8):
            c.line([(x - 3, y), (x + 3, y + 3)], 1.2, "#e0d0a8", 0.8, wobble=0.1)
    # горловина: перехват верёвкой и складки
    c.rect(0, 0, w, 16, "#9a845e", 0.7)
    B.hline(c, 18, 4, "#6e5a3e", seed=3)
    for x in np.arange(0, w, 10):
        c.line([(x, 0), (x + 3, 16)], 2, "#7a6646", 0.5, wobble=0.3)
    f = B.vgrad(c, [(0, 0.9), (24, 1.08), (h * 0.6, 1.0), (h, 0.8)])
    B.multiply(c, f)
    # мука на мешке
    c.strokes(30, ["#e8e0cc"], length=(6, 16), width=(3, 7), angle=0, angle_jitter=180, alpha=(0.1, 0.3))
    return c.image()


def paint_stones(w, h):
    c = Canvas(w, h, base="#7a7466", seed=271)
    c.underpaint(["#7a7466", "#6a6458", "#8a8272", "#5a564c", "#8a7a5e"], cell=24, seed=271)
    c.strokes(260, ["#9a9282", "#5a564c", "#857c6a", "#6e6a5e"], length=(6, 18), width=(3, 8), angle=-30,
              angle_jitter=60, alpha=(0.2, 0.5), bristles=3, curve=0.3)
    c.grain(0.04)
    return c.image()


def paint_iron(w, h):
    """Чугун и железо: ядра, полосы, обручи; копоть и ржавчина мазками."""
    c = Canvas(w, h, base="#2e2a28", seed=281, tile=False)
    c.underpaint(["#2e2a28", "#3a3430", "#24201e", "#463c34"], cell=24, seed=281)
    c.strokes(220, ["#4a423c", "#1c1816", "#5a4a3e", "#6a4a34"], length=(8, 20), width=(3, 7), angle=0,
              angle_jitter=180, alpha=(0.2, 0.5), bristles=3)
    c.strokes(24, ["#a8a098", "#c8bca8"], length=(10, 26), width=(2, 4), angle=-30, angle_jitter=10,
              alpha=(0.2, 0.45), bristles=1, region=(0, 0, w, h * 0.4))
    return c.image()


def paint_bronze(w, h):
    """Бронза пушки: по x — вокруг ствола (повтор), по y — от казны к дулу; патина и кольца."""
    c = Canvas(w, h, base="#8a6a34", seed=291)
    c.underpaint(["#8a6a34", "#7a5a2a", "#9a7a40", "#6a4e24"], cell=24, seed=291)
    c.strokes(120, ["#c8a058", "#5a4420", "#4a6a50"], length=(10, 30), width=(2, 5), angle=90, angle_jitter=10,
              alpha=(0.2, 0.5), bristles=2)
    for y in (12, 40, 74, h - 16):
        B.hline(c, y, 6, "#5a4420", seed=int(y))
        B.hline(c, y - 3, 2, "#e0bc70", seed=int(y) + 1, alpha=0.8)
    x = np.linspace(0, 1, w * c.ss)
    prof = 0.75 + 0.4 * np.sin(np.pi * x) ** 1.2
    B.multiply(c, np.repeat(prof[None, :], h * c.ss, axis=0))
    return c.image()


def paint_banner(w, h):
    """Знамя Коканда: изумрудное полотно, золотой полумесяц со звездой, золотая кайма,
    свободный край — языками (вырез по альфе). x — от древка (0) к краю, y — сверху вниз."""
    c = Canvas(w, h, base=EMERALD, seed=301, tile=False)
    c.underpaint([EMERALD, "#2a8068", "#35987c", "#267660"], cell=40, seed=301)
    c.strokes(260, ["#3aa080", "#226a56", "#2f8f74"], length=(30, 80), width=(8, 16), angle=0, angle_jitter=15,
              alpha=(0.15, 0.3), bristles=5)
    H, W = h * c.ss, w * c.ss
    yy, xx = np.mgrid[0:H, 0:W] / c.ss
    s, q = xx / w, yy / h
    # свободный край: три языка
    tongue = 0.86 + 0.12 * np.abs(np.sin(np.pi * q * 3)) ** 0.7
    inside = s < tongue
    fold = 0.86 + 0.16 * np.sin(s * 2 * np.pi * 3.5 + 0.6) * (0.3 + 0.7 * s)
    B.multiply(c, fold)
    # кайма золотом по контуру
    d_edge = np.minimum.reduce([q * h, (1 - q) * h, (tongue - s) * w])
    img = np.asarray(c.img, dtype=np.float64)
    border = inside & (d_edge < 10) & (xx > 18)
    img = np.where(border[..., None], np.array(rgb8(GOLD), float) * (0.9 + 0.2 * value_noise(W, H, 6, seed=3, tile=False))[..., None], img)
    dark = inside & (d_edge >= 10) & (d_edge < 12.5) & (xx > 18)
    img = np.where(dark[..., None], np.array(rgb8(EMERALD_D), float), img)
    sleeve = xx < 18
    img = np.where(sleeve[..., None], img * 0.62, img)
    c._blend(img)
    # полумесяц со звездой
    cx, cy, R = w * 0.42, h * 0.46, h * 0.26
    c.ellipse(cx, cy, R, R, GOLD, 1.0)
    c.ellipse(cx + R * 0.36, cy - R * 0.12, R * 0.82, R * 0.82, EMERALD, 1.0)
    st = B.star_points(cx + R * 0.95, cy - R * 0.1, R * 0.32, R * 0.14, 5)
    c.polygon(st, GOLD, 1.0, wobble=0.2)
    for y in (h * 0.8,):
        pts = [(x, y + 6 * math.sin(x / 14)) for x in np.linspace(30, w * 0.8, 30)]
        c.line(pts, 3, GOLD, 0.9, wobble=0.3)
    alpha = (inside | sleeve).astype(float)
    alpha = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS), float) / 255
    return _with_alpha(c.image(), alpha)


def paint_awning(w, h):
    """Навес базара: полосатая ткань (изумруд, кремовая, мареновая), фестоны по низу (альфа)."""
    c = Canvas(w, h, base=CREAM, seed=311, tile=False)
    cols_ = [EMERALD, CREAM, "#9a3a2a", CREAM]
    n = 12
    for i in range(n):
        c.rect(i * w / n, 0, (i + 1) * w / n, h, cols_[i % 4], 1.0)
    c.strokes(300, ["#ffffff", "#000000"], length=(20, 60), width=(6, 12), angle=90, angle_jitter=10,
              alpha=(0.04, 0.1), bristles=3)
    H, W = h * c.ss, w * c.ss
    yy, xx = np.mgrid[0:H, 0:W] / c.ss
    edge = 0.84 + 0.14 * np.abs(np.sin(np.pi * xx / w * 12)) ** 0.6
    alpha = (yy / h < edge).astype(float)
    B.multiply(c, B.vgrad(c, [(0, 1.05), (h, 0.85)]))
    alpha = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS), float) / 255
    return _with_alpha(c.image(), alpha)


def paint_carpet(w, h):
    """Ковёр на базаре: мареновое поле, тёмно-синий медальон, кайма с ромбами."""
    c = Canvas(w, h, base="#8a2a22", seed=321, tile=False)
    c.underpaint(["#8a2a22", "#9a3428", "#7a221c"], cell=24, seed=321)
    c.rect(8, 8, w - 8, h - 8, "#2a2a4a", 1.0)
    c.rect(18, 18, w - 18, h - 18, "#8a2a22", 1.0)
    for i in range(12):
        B.diamond(c, 13 + i * (w - 26) / 11, 13, 4, 4, CREAM)
        B.diamond(c, 13 + i * (w - 26) / 11, h - 13, 4, 4, CREAM)
    B.diamond(c, w / 2, h / 2, w * 0.25, h * 0.32, "#1f2f5a", GOLD, 2)
    B.diamond(c, w / 2, h / 2, w * 0.1, h * 0.13, GOLD)
    c.strokes(200, ["#000000", "#ffffff"], length=(4, 10), width=(2, 4), angle=0, angle_jitter=90,
              alpha=(0.03, 0.08), bristles=1)
    return c.image()


def paint_pottery(w, h):
    """Глазурованная керамика (ляган, кувшины): по x — вокруг, по y — сверху вниз."""
    c = Canvas(w, h, base="#c08a5a", seed=331)
    c.underpaint(["#c08a5a", "#b07a4e", "#cc9866"], cell=16, seed=331)
    c.rect(0, 0, w, h * 0.45, TURQ, 1.0)
    for i in range(8):
        B.leaf(c, (i + 0.5) * w / 8, h * 0.22, 12, 6, -90, CREAM)
    B.hline(c, h * 0.45, 3, COBALT, seed=1)
    x = np.linspace(0, 1, w * c.ss)
    prof = 0.75 + 0.4 * np.sin(np.pi * x)
    B.multiply(c, np.repeat(prof[None, :], h * c.ss, axis=0))
    return c.image()


def paint_embers(w, h):
    """Жар печи (горн пушечного двора, печь для кирпича): светится без освещения."""
    c = Canvas(w, h, base="#3a1a0e", seed=341, tile=False)
    c.underpaint(["#3a1a0e", "#5a2a14", "#2a120a"], cell=16, seed=341)
    c.strokes(80, ["#ff8a2c", "#ffb04a", "#e0501c"], length=(6, 16), width=(2, 5), angle=0, angle_jitter=180,
              alpha=(0.6, 1.0), bristles=1, curve=0.6)
    c.strokes(30, ["#fff0a0", "#ffd070"], length=(3, 8), width=(1.5, 3), angle=0, angle_jitter=180,
              alpha=(0.7, 1.0), bristles=0)
    return c.image()


PAINTERS = {
    "brick": paint_brick, "plinth": paint_plinth, "tileband": paint_tileband, "band2": paint_band2,
    "pakhsa": paint_pakhsa, "clay": paint_clay, "roof": paint_roof, "earth": paint_earth, "rubble": paint_rubble,
    "dome_tile": paint_dome_tile, "portal": paint_portal, "walnut": paint_walnut, "wood": paint_wood,
    "bark": paint_bark, "pole": paint_pole, "rope": paint_rope, "planks": paint_planks, "logend": paint_logend,
    "door": paint_door, "gate": paint_gate, "column": paint_column, "panjara": paint_panjara,
    "ceiling": paint_ceiling, "furrows": paint_furrows, "canopy_green": paint_canopy_green,
    "canopy_gold": paint_canopy_gold, "wheat_green": lambda w, h: paint_wheat(w, h, False),
    "wheat_gold": lambda w, h: paint_wheat(w, h, True), "cotton": paint_cotton, "water": paint_water,
    "hay": paint_hay, "sacks": paint_sacks, "stones": paint_stones, "iron": paint_iron, "bronze": paint_bronze,
    "banner": paint_banner, "awning": paint_awning, "carpet": paint_carpet, "pottery": paint_pottery,
    "embers": paint_embers,
}


# ---------------------------------------------------------------- сборка

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


# ---------------------------------------------------------------- декали земли (отдельные текстуры)

def paint_ground_decal(w=512, h=512, seed=401):
    """Утоптанная земля под двором/улицей города: охра и пыль, следы колёс и ног, соломинки;
    рваный мягкий край по альфе (Decal кладёт её на землю мира)."""
    c = Canvas(w, h, base="#7c6648", seed=seed, tile=False)
    B.clay(c, ["#7c6648", "#706044", "#8a7452", "#66543c"], ["#a88a5a", "#4e3e2c", "#b89a68"], seed=seed,
           trowel=False, density=0.8)
    c.strokes(900, ["#8a7454", "#5e4c36", "#9a8460", "#6e5a40"], length=(10, 30), width=(4, 10), angle=0,
              angle_jitter=180, alpha=(0.1, 0.28), bristles=3, curve=0.4)
    rs = np.random.default_rng(seed + 1)
    for _ in range(120):   # следы
        x, y = rs.uniform(20, w - 20), rs.uniform(20, h - 20)
        a = rs.uniform(0, 360)
        pts = [(x + 3.5 * math.cos(math.radians(a + t)), y + 3.5 * math.sin(math.radians(a + t))) for t in range(-70, 71, 35)]
        c.line(pts, 1.8, "#4a3a28", 0.5, wobble=0.2, seed=int(x * 7 + y))
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot((xx - w / 2) / (w / 2), (yy - h / 2) / (h / 2))
    n = fbm(w, h, 48, 4, seed=seed + 2, tile=False)
    edge = 0.8 + 0.28 * (n - 0.5)
    alpha = np.clip((edge - r) / 0.12, 0, 1) * 0.92
    return _with_alpha(c.image(), alpha)


def paint_street_decal(w=256, h=1024, seed=411):
    """Улица/дорога: полоса утоптанной земли с колеями арб, края рваные (повтор по длине)."""
    c = Canvas(w, h, base="#7a6446", seed=seed, tile=False)
    B.clay(c, ["#7a6446", "#6c5a40", "#887050", "#5e4c36"], ["#a88a5a", "#4e3e2c"], seed=seed, trowel=False,
           density=0.8)
    for x in (w * 0.36, w * 0.64):   # колеи
        c.strokes(140, ["#4e3e2c", "#5a4832", "#3e3022"], length=(30, 90), width=(5, 9), angle=90, angle_jitter=3,
                  alpha=(0.2, 0.45), bristles=2, region=(x - 7, 0, x + 7, h))
        c.strokes(60, ["#a08a62"], length=(20, 60), width=(2, 3), angle=90, angle_jitter=3, alpha=(0.2, 0.4),
                  bristles=0, region=(x - 10, 0, x - 6, h))
    yy, xx = np.mgrid[0:h, 0:w]
    n = fbm(w, h, 40, 4, seed=seed + 2, tile=False)
    d = np.abs(xx - w / 2) / (w / 2) + (n - 0.5) * 0.35
    alpha = np.clip((0.86 - d) / 0.14, 0, 1)
    alpha *= np.clip(np.minimum(yy, h - 1 - yy) / 60.0, 0, 1)
    return _with_alpha(c.image(), alpha * 0.9)


DECALS = {"ground_decal.png": paint_ground_decal, "street_decal.png": paint_street_decal}


def build_decals(out_dir, verbose=True):
    paths = []
    for name, fn in DECALS.items():
        img = fn()
        arr = _bleed(np.asarray(img.convert("RGBA")).copy())
        path = os.path.join(out_dir, name)
        Image.fromarray(arr, "RGBA").save(path, optimize=True)
        paths.append(path)
        if verbose:
            print("  декаль:", name, img.size)
    return paths


def build(out_path, only=None, verbose=True):
    """Рисует все области и собирает атлас. only — список имён (для отладки: остальные из старого атласа)."""
    if only and os.path.exists(out_path):
        atlas = np.asarray(Image.open(out_path).convert("RGBA")).copy()
    else:
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
        mode_x = "wrap" if rep in ("x", "xy") else "edge"
        mode_y = "wrap" if rep in ("y", "xy") else "edge"
        padded = np.pad(arr, ((0, 0), (PAD, PAD), (0, 0)), mode=mode_x)
        padded = np.pad(padded, ((PAD, PAD), (0, 0), (0, 0)), mode=mode_y)
        ys, xs = y - PAD, x - PAD
        y0c, x0c = max(ys, 0), max(xs, 0)
        y1c, x1c = min(ys + h + 2 * PAD, SIZE), min(xs + w + 2 * PAD, SIZE)
        atlas[y0c:y1c, x0c:x1c] = padded[y0c - ys:y1c - ys, x0c - xs:x1c - xs]
        if verbose:
            print(f"  атлас: {name:13s} {w}×{h} @ ({x}, {y})")
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    Image.fromarray(atlas, "RGBA").save(out_path, optimize=True)
    return out_path


if __name__ == "__main__":
    for k, v in LAYOUT.items():
        print(k, v)
