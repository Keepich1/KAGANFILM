"""Мир среза: рельеф, карты почв и травы, расстановка деревьев и камней.

Кусок Ферганской долины 1024 × 1024 м, центр в (0, 0), +X — восток, −Z — север
(CONTRACT §2–3). Всё детерминировано (seed), запуск из ordo/:

    python3 tools/gen_world.py            # всё: рельеф, карты, расстановка, текстуры, модели
    python3 tools/gen_world.py height     # только рельеф, карты и расстановка
    python3 tools/gen_world.py tex        # только рисованные текстуры земли (gen_world_tex.py)
    python3 tools/gen_world.py models     # только деревья, камни, трава (gen_world_models.py)
    python3 tools/gen_world.py preview    # картинка-схема карты в renders/world/

Что пишется в assets/world/:
    height.bin   высоты float32 (little-endian), строки по z (север → юг), 513 × 513, шаг 2 м
    far.bin      дальнее кольцо гор, float32, 161 × 161, шаг 32 м (±2560 м)
    height.json  заголовок: размеры, шаг, мин/макс, уровень воды, русло реки, брод, метки
    scatter.json деревья, камни, пятна тумана (x, y, z, поворот°, масштаб[, вариант])
и в assets/textures/world/:
    splat.png    1024²: R сухая охра, G вытоптанная земля, B камень, A песок и галька
    grass.png    512²:  R густота травы, G высота травы, B доля ковыля, A сырость у воды
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)

SEED = 1707            # год основания Кокандского ханства… почти
HALF = 512.0           # половина стороны карты, м
SPACING = 2.0          # шаг сетки высот, м
N = int(2 * HALF / SPACING) + 1        # 513 точек на сторону
FAR_HALF = 2560.0      # дальнее кольцо гор, м
FAR_SPACING = 32.0
FAR_N = int(2 * FAR_HALF / FAR_SPACING) + 1   # 161
WATER_LEVEL = -4.0     # уровень воды в реке, м

# Метки карты (CONTRACT §3)
CAMP = (-60.0, 20.0)
KOROO = (-115.0, 65.0)
JYLKY = (-25.0, 90.0)
MEADOW = (90.0, 0.0)
MEADOW_HALF = 80.0
FORD_X = 20.0


# =====================================================================
# Шум в мировых координатах (градиентный, без сетки картинки)
# =====================================================================

def _hash(ix, iz, seed):
    h = (ix.astype(np.int64) * 374761393 + iz.astype(np.int64) * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return (h ^ (h >> 16)) & 0xFFFFFFFF


def perlin(x, z, seed=0):
    """Градиентный шум ≈ −1..1 по координатам (в клетках)."""
    x = np.asarray(x, dtype=np.float64)
    z = np.asarray(z, dtype=np.float64)
    x0, z0 = np.floor(x), np.floor(z)
    fx, fz = x - x0, z - z0
    ix, iz = x0.astype(np.int64), z0.astype(np.int64)

    def grad(i, k, dx, dz):
        a = _hash(i, k, seed).astype(np.float64) / 4294967295.0 * 2 * np.pi
        return np.cos(a) * dx + np.sin(a) * dz

    n00 = grad(ix, iz, fx, fz)
    n10 = grad(ix + 1, iz, fx - 1, fz)
    n01 = grad(ix, iz + 1, fx, fz - 1)
    n11 = grad(ix + 1, iz + 1, fx - 1, fz - 1)
    u = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
    v = fz * fz * fz * (fz * (fz * 6 - 15) + 10)
    return 1.41 * ((n00 * (1 - u) + n10 * u) * (1 - v) + (n01 * (1 - u) + n11 * u) * v)


def fbm(x, z, scale, octaves=4, gain=0.5, seed=0):
    """Фрактальный шум ≈ −1..1; scale — размер крупной детали, м."""
    acc, amp, tot, f = 0.0, 1.0, 0.0, 1.0 / scale
    for o in range(octaves):
        acc = acc + amp * perlin(x * f + 17.3 * o, z * f - 9.1 * o, seed + 31 * o)
        tot += amp
        amp *= gain
        f *= 2.03
    return acc / tot


def ridged(x, z, scale, octaves=5, gain=0.5, seed=0):
    """Гребни 0..1 — для острых хребтов."""
    acc, amp, tot, f, w = 0.0, 1.0, 0.0, 1.0 / scale, 1.0
    for o in range(octaves):
        n = 1.0 - np.abs(perlin(x * f + 5.7 * o, z * f + 3.1 * o, seed + 53 * o))
        n = n * n * w
        w = np.clip(n * 1.6, 0, 1)
        acc = acc + amp * n
        tot += amp
        amp *= gain
        f *= 2.1
    return acc / tot


def smoothstep(a, b, x):
    t = np.clip((np.asarray(x, dtype=np.float64) - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


# =====================================================================
# Река
# =====================================================================

def river_z(x):
    """Ось реки: дуга на севере, выгнута к югу посередине (z ≈ −158…−215)."""
    x = np.asarray(x, dtype=np.float64)
    return -165.0 - 45.0 * (x / 512.0) ** 2 + 8.0 * np.sin(x / 70.0 + 1.0)


def river_polyline(step=8.0):
    xs = np.arange(-HALF - 80, HALF + 80 + 1e-6, step)
    return np.column_stack([xs, river_z(xs)])


def river_halfwidth(x):
    x = np.asarray(x, dtype=np.float64)
    w = 11.0 + 3.5 * np.sin(x / 130.0 + 0.7) + 2.0 * np.sin(x / 47.0)
    return w + 4.5 * np.exp(-((x - FORD_X) / 45.0) ** 2)   # у брода река разливается шире


def river_distance(x, z):
    """Расстояние до оси реки (по ломаной) и абсцисса ближайшей точки."""
    pl = river_polyline(6.0)
    x = np.asarray(x, dtype=np.float64)
    z = np.asarray(z, dtype=np.float64)
    best = np.full(x.shape, np.inf)
    bx = np.zeros(x.shape)
    a, b = pl[:-1], pl[1:]
    # перебор отрезков только около реки — быстрее по окну по x
    for i in range(len(a)):
        ax, az = a[i]
        dx, dz = b[i] - a[i]
        L2 = dx * dx + dz * dz
        t = np.clip(((x - ax) * dx + (z - az) * dz) / L2, 0, 1)
        px, pz = ax + t * dx, az + t * dz
        d = np.hypot(x - px, z - pz)
        m = d < best
        best = np.where(m, d, best)
        bx = np.where(m, px, bx)
    return best, bx


# =====================================================================
# Рельеф
# =====================================================================

def mountain_amp(theta):
    """Высота краевых гор по направлению (θ = atan2(z, x), север = −90°).
    Север и северо-запад — самые высокие, запад ниже (там садится солнце)."""
    d = np.degrees(theta)

    def bump(center, width, amp):
        dd = (d - center + 180) % 360 - 180
        return amp * np.exp(-(dd / width) ** 2)

    return (70.0
            + bump(-90, 45, 95)      # север
            + bump(-135, 30, 85)     # северо-запад
            + bump(-60, 30, 40)      # северо-восток
            + bump(160, 25, -30)     # запад-юго-запад: седловина под закатом
            + bump(90, 40, 25)       # юг
            + bump(10, 40, 15))      # восток


def heights(X, Z, far=False):
    """Высота земли, м. X, Z — массивы мировых координат."""
    # нормированное «скруглённо-квадратное» расстояние до края (≈1 на краю карты),
    # фронт гор изрезан шумом: отроги заходят внутрь, долины — наружу
    p = 5.0
    r0 = ((np.abs(X) / HALF) ** p + (np.abs(Z) / HALF) ** p) ** (1.0 / p)
    warp = 0.16 * fbm(X, Z, 240, 3, seed=SEED + 7) + 0.05 * fbm(X, Z, 70, 2, seed=SEED + 8)
    r = r0 + warp
    theta = np.arctan2(Z, X)

    # --- холмистая степь: пологие увалы, к краям выше
    hills = 11.0 * fbm(X, Z, 230, 4, seed=SEED + 1) + 3.5 * fbm(X, Z, 75, 3, seed=SEED + 2)
    hills += 6.0 * ridged(X, Z, 180, 3, seed=SEED + 3) - 2.5
    base = 1.0 + hills * (0.35 + 0.65 * smoothstep(0.15, 0.6, r))

    # --- горы по краям (крутые, почти непроходимые)
    amp = mountain_amp(theta)
    rid = ridged(X, Z, 210, 5, seed=SEED + 4)
    rid2 = ridged(X, Z, 85, 4, seed=SEED + 5)
    rise = smoothstep(0.62, 1.08, r)
    mount = amp * (rise ** 1.5) * (0.35 + 0.85 * rid + 0.3 * rid2)
    # предгорья: длинные отроги, уходящие к долине
    spurs = ridged(X, Z, 320, 3, seed=SEED + 6)
    mount += 28.0 * smoothstep(0.42, 0.85, r) * spurs ** 2
    if far:
        # за краем горы продолжаются и поднимаются, затем выходят на плато
        out = smoothstep(1.0, 2.6, r0)
        # хребты вытянуты вдоль края карты: на севере и юге — с запада на восток и т. д.
        ns = smoothstep(-0.25, 0.25, (np.abs(Z) - np.abs(X)) / (np.abs(Z) + np.abs(X) + 1.0))
        rid_ns = ridged(X * 0.45, Z, 700, 3, seed=SEED + 14)
        rid_we = ridged(X, Z * 0.45, 700, 3, seed=SEED + 15)
        rid3 = lerp(rid_we, rid_ns, ns)
        far_m = amp * out * (0.2 + 1.2 * rid3 ** 1.2) * 0.3
        mount = mount + far_m * (1.0 - 0.4 * smoothstep(3.2, 5.0, r0))
    # долина реки прорезает горы на западе и востоке
    dz = np.abs(Z - river_z(np.clip(X, -900, 900)))
    gorge = np.exp(-(dz / 85.0) ** 2) * smoothstep(0.45, 0.95, np.abs(X) / HALF)
    mount = mount * (1.0 - 0.9 * gorge)
    h = base + mount

    # --- пологий уклон к реке и пойма
    dr, _ = river_distance(np.clip(X, -HALF - 70, HALF + 70), Z) if not far else (dz, None)
    flood = WATER_LEVEL + 0.9 + 0.03 * np.maximum(dr - 18.0, 0) + 0.4 * fbm(X, Z, 30, 2, seed=SEED + 12)
    h = lerp(flood, h, smoothstep(22.0, 150.0, dr))

    # --- впадины для тумана (низины)
    for (cx, cz, rad, depth) in HOLLOWS:
        h = h - depth * np.exp(-(((X - cx) ** 2 + (Z - cz) ** 2) / (rad * rad)))

    # --- ровные места: лагерь (плато), загоны, поле боя
    def disc_w(c, r0_, r1_):
        d = np.hypot(X - c[0], Z - c[1])
        return 1.0 - smoothstep(r0_, r1_, d)

    # поле боя: ровный луг с лёгким уклоном к западу-северо-западу (к солнцу)
    mx = np.abs(X - MEADOW[0]) - MEADOW_HALF
    mz = np.abs(Z - MEADOW[1]) - MEADOW_HALF
    md = np.hypot(np.maximum(mx, 0), np.maximum(mz, 0)) + np.minimum(np.maximum(mx, mz), 0)
    w_meadow = 1.0 - smoothstep(-6.0, 60.0, md)
    meadow_h = 0.0 + 0.012 * (X - MEADOW[0]) + 0.004 * Z + 0.25 * fbm(X, Z, 60, 2, seed=SEED + 9)
    h = lerp(h, meadow_h, w_meadow)

    # лагерь: плато чуть выше луга, с мягким куполом для стока воды
    camp_h = 0.9 + 0.35 * (1.0 - np.clip(np.hypot(X - CAMP[0], Z - CAMP[1]) / 80.0, 0, 1)) \
        + 0.15 * fbm(X, Z, 40, 2, seed=SEED + 10)
    w_camp = np.maximum.reduce([disc_w(CAMP, 62, 120), disc_w(KOROO, 24, 62), disc_w(JYLKY, 26, 64)])
    h = lerp(h, camp_h, w_camp)

    # --- русло: срезаем землю (min), у брода мелко
    if not far:
        dr, bx = river_distance(np.clip(X, -HALF - 70, HALF + 70), Z)
        hw = river_halfwidth(bx)
        ford = np.exp(-((bx - FORD_X) / 22.0) ** 2)
        depth = lerp(1.7, 0.32, ford)
        t = np.clip(dr / hw, 0, 1)
        bed = WATER_LEVEL - depth * (1.0 - t * t) ** 0.7 - 0.08
        # галечные отмели и неровное дно
        bed += 0.25 * fbm(X, Z, 14, 2, seed=SEED + 11) * (1.0 - 0.6 * ford)
        bank = WATER_LEVEL - 0.08 + 0.12 * np.maximum(dr - hw, 0) + 0.2 * np.maximum(dr - hw - 4, 0)
        channel = np.where(dr < hw, bed, bank)
        h = np.minimum(h, channel)
    else:
        bed = WATER_LEVEL - 1.2 + 0.1 * np.maximum(dz - 14.0, 0) + 0.02 * np.maximum(dz - 120.0, 0) ** 2
        h = np.minimum(h, bed)

    return h


# низины для тумана: (x, z, радиус, глубина)
HOLLOWS = [(205.0, 150.0, 55.0, 3.2), (-235.0, -70.0, 60.0, 3.0), (255.0, -110.0, 45.0, 2.4),
           (-190.0, 175.0, 50.0, 2.6)]


def grid_coords(n, spacing, half):
    xs = -half + spacing * np.arange(n)
    return np.meshgrid(xs, xs)      # X[j, i] = x_i, Z[j, i] = z_j


def normals(H, spacing):
    gz, gx = np.gradient(H, spacing)
    n = np.dstack([-gx, np.ones_like(H), -gz])
    return n / np.linalg.norm(n, axis=2, keepdims=True)


def bilinear(H, x, z, spacing=SPACING, half=HALF):
    n = H.shape[0]
    fx = np.clip((np.asarray(x) + half) / spacing, 0, n - 1.001)
    fz = np.clip((np.asarray(z) + half) / spacing, 0, n - 1.001)
    i, j = np.floor(fx).astype(int), np.floor(fz).astype(int)
    u, v = fx - i, fz - j
    return (H[j, i] * (1 - u) * (1 - v) + H[j, i + 1] * u * (1 - v)
            + H[j + 1, i] * (1 - u) * v + H[j + 1, i + 1] * u * v)


# =====================================================================
# Карты почв и травы
# =====================================================================

def seg_dist(X, Z, a, b):
    ax, az = a
    dx, dz = b[0] - ax, b[1] - az
    L2 = dx * dx + dz * dz
    t = np.clip(((X - ax) * dx + (Z - az) * dz) / L2, 0, 1)
    return np.hypot(X - (ax + t * dx), Z - (az + t * dz))


def path_dist(X, Z, pts):
    d = np.full(X.shape, np.inf)
    for a, b in zip(pts[:-1], pts[1:]):
        d = np.minimum(d, seg_dist(X, Z, a, b))
    return d


# тропы: лагерь → брод, лагерь → луг, лагерь → загоны, вдоль лагеря
PATHS = [
    [(-60, 20), (-45, -20), (-15, -70), (5, -115), (FORD_X, -150)],
    [(-60, 20), (-20, 15), (10, 8)],
    [(-60, 20), (-90, 45), KOROO],
    [(-60, 20), (-42, 58), JYLKY],
    [KOROO, (-150, 100), (-210, 160)],                # выгон отары на холмы
    [(FORD_X, -165), (35, -215), (55, -280)],          # дорога за бродом
]


def ground_maps(X, Z, H, Nrm):
    """Возвращает словарь карт 0..1 на сетке X, Z."""
    slope = 1.0 - Nrm[..., 1]           # 0 — ровно, ~0.29 — 45°
    sdeg = np.degrees(np.arccos(np.clip(Nrm[..., 1], -1, 1)))
    n1 = fbm(X, Z, 45, 3, seed=SEED + 21) * 0.5 + 0.5
    n2 = fbm(X, Z, 12, 2, seed=SEED + 22) * 0.5 + 0.5
    n3 = fbm(X, Z, 120, 3, seed=SEED + 23) * 0.5 + 0.5
    dr, _ = river_distance(np.clip(X, -HALF - 70, HALF + 70), Z)
    above_water = H - WATER_LEVEL

    # камень — на крутых склонах и в горах
    rock = smoothstep(26.0, 38.0, sdeg + (n2 - 0.5) * 10)
    p = 6.0
    r = ((np.abs(X) / HALF) ** p + (np.abs(Z) / HALF) ** p) ** (1.0 / p)
    rock = np.maximum(rock, smoothstep(0.86, 1.0, r) * smoothstep(0.35, 0.75, n1) * smoothstep(12, 22, sdeg))

    # песок и галька — у воды, на отмелях брода
    sand = 1.0 - smoothstep(0.35, 1.3 + n2 * 0.8, above_water)
    sand *= 1.0 - smoothstep(30.0, 42.0, dr)
    ford = np.exp(-(((X - FORD_X) / 40.0) ** 2 + ((Z - river_z(FORD_X)) / 30.0) ** 2))
    sand = np.maximum(sand, ford * 0.85 * (1 - smoothstep(0.3, 1.6, above_water)))

    # вытоптанная земля — лагерь, загоны, тропы
    dc = np.hypot(X - CAMP[0], Z - CAMP[1])
    jag = (n2 - 0.5) * 14 + (n1 - 0.5) * 18
    earth = 1.0 - smoothstep(38.0, 62.0, dc + jag)
    earth = earth * (0.55 + 0.45 * smoothstep(8.0, 30.0, dc))        # у ставки — утоптано, но не сплошь
    earth = np.maximum(earth, 1.0 - smoothstep(10.0, 22.0, np.hypot(X - KOROO[0], Z - KOROO[1]) + jag * 0.5))
    earth = np.maximum(earth, 0.85 * (1.0 - smoothstep(9.0, 24.0, np.hypot(X - JYLKY[0], Z - JYLKY[1]) + jag * 0.5)))
    for k, pts in enumerate(PATHS):
        d = path_dist(X, Z, pts)
        wob = fbm(X, Z, 25, 2, seed=SEED + 40 + k) * 1.5
        width = 2.2 + 0.8 * n2
        earth = np.maximum(earth, 0.85 * (1.0 - smoothstep(width * 0.5, width * 1.6, d + wob)))
    earth *= 1.0 - smoothstep(0.0, 0.3, -above_water)    # не под водой

    # сухая охра — на солнечных склонах (юг и запад), на макушках холмов, пятнами
    sunny = np.clip(-Nrm[..., 0] * 0.8 + Nrm[..., 2] * 0.5, 0, 1)   # склоны к западу и югу
    dry = smoothstep(0.5, 0.85, n3 * 0.7 + n1 * 0.3) * 0.6 + sunny * 1.5
    dry *= smoothstep(30.0, 120.0, dr)                    # у реки сочнее
    dry = np.clip(dry, 0, 1) * (1 - rock)
    # на лугу — немного охры пятнами (выгоревшая трава)
    mx = np.maximum(np.abs(X - MEADOW[0]) - MEADOW_HALF, np.abs(Z - MEADOW[1]) - MEADOW_HALF)
    in_meadow = 1.0 - smoothstep(-10.0, 25.0, mx)
    dry = lerp(dry, 0.35 * smoothstep(0.5, 0.75, n1), in_meadow * 0.7)

    # снег на вершинах (в основном дальний фон, но и на краевых пиках)
    snow = smoothstep(150.0, 185.0, H + (n1 - 0.5) * 30) * (1.0 - smoothstep(30.0, 45.0, sdeg))

    # трава: густота, высота, ковыль, сырость
    dens = 0.9 * (1 - rock) * (1 - sand) * (1 - earth * 0.9) * (1 - snow)
    dens *= 0.75 + 0.25 * n2
    dens *= 1.0 - smoothstep(0.85, 1.05, r) * 0.7          # в горах трава реже
    dens *= smoothstep(-0.2, 0.25, above_water)
    tall = 0.35 + 0.65 * smoothstep(0.3, 0.8, n1)            # по краям выше
    tall = lerp(tall, 0.12 + 0.12 * n2, in_meadow)            # на поле боя трава низкая
    tall = lerp(tall, 0.9, (1 - smoothstep(6.0, 35.0, dr)) * (1 - sand))   # у реки — высокий тростник
    # ковыль — на сухих холмах и по краям луга, на поле и у воды — нет
    kovyl = smoothstep(0.35, 0.7, n3 * 0.6 + dry * 0.5) * smoothstep(25.0, 70.0, dr)
    kovyl *= 1.0 - in_meadow * 0.85
    kovyl *= 1.0 - smoothstep(0.0, 1.0, earth * 1.5)
    edge_meadow = smoothstep(-25.0, 0.0, mx) * (1 - smoothstep(0.0, 30.0, mx))
    kovyl = np.maximum(kovyl, edge_meadow * 0.75 * smoothstep(0.3, 0.6, n1))
    wet = 1.0 - smoothstep(0.0, 1.4, above_water)

    return {"dry": dry, "earth": earth, "rock": np.maximum(rock, snow * 0.0), "sand": sand,
            "snow": snow, "dens": np.clip(dens, 0, 1), "tall": np.clip(tall, 0, 1),
            "kovyl": np.clip(kovyl, 0, 1), "wet": np.clip(wet, 0, 1)}


def to_png(path, chans, size):
    """Каналы-данные в RGBA PNG. Каждый канал уменьшается отдельно: у PIL RGBA-уменьшение
    умножает цвет на альфу, а альфа здесь — данные (сырость, песок), не прозрачность."""
    bands = []
    for c in chans:
        b = Image.fromarray((np.clip(c, 0, 1) * 255 + 0.5).astype(np.uint8), "L")
        if b.size != (size, size):
            b = b.resize((size, size), Image.BILINEAR)
        bands.append(b)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.merge("RGBA", bands).save(path, optimize=True)


# =====================================================================
# Расстановка: деревья, камни, пятна тумана
# =====================================================================

def scatter(H, Nrm, maps_lo):
    """Детерминированная расстановка. maps_lo — карты на сетке высот (513²)."""
    rs = np.random.default_rng(SEED + 100)
    out = {"poplar": [], "willow": [], "juniper": [], "elm": [], "rock": []}

    def h_at(x, z):
        return float(bilinear(H, x, z))

    def slope_at(x, z):
        i = int(np.clip(round((x + HALF) / SPACING), 0, N - 1))
        j = int(np.clip(round((z + HALF) / SPACING), 0, N - 1))
        return float(np.degrees(np.arccos(Nrm[j, i, 1])))

    def in_meadow(x, z, m=8.0):
        return abs(x - MEADOW[0]) < MEADOW_HALF + m and abs(z - MEADOW[1]) < MEADOW_HALF + m

    def near(x, z, c, r):
        return math.hypot(x - c[0], z - c[1]) < r

    def on_path(x, z, w=4.0):
        X, Z = np.array([x]), np.array([z])
        return any(path_dist(X, Z, p)[0] < w for p in PATHS)

    def blocked(x, z):
        return (in_meadow(x, z) or near(x, z, CAMP, 72) or near(x, z, KOROO, 26)
                or near(x, z, JYLKY, 28) or on_path(x, z))

    placed = []

    def free(x, z, r):
        return all(math.hypot(x - px, z - pz) > r + pr for px, pz, pr in placed)

    def add(kind, x, z, scale, r, extra=None):
        y = h_at(x, z)
        rot = float(rs.uniform(0, 360))
        item = [round(x, 2), round(y, 3), round(z, 2), round(rot, 1), round(scale, 3)]
        if extra is not None:
            item.append(extra)
        out[kind].append(item)
        placed.append((x, z, r))

    # --- тополя (терек): ряды вдоль южного берега и вдоль арыка к лагерю
    for x in np.arange(-470, 480, 9.0):
        zc = float(river_z(x))
        for side, off in ((1, 26.0), (-1, 30.0)):
            if rs.random() < (0.55 if side > 0 else 0.35):
                xx = x + rs.normal(0, 2.0)
                zz = zc + side * (off + rs.normal(0, 4.0))
                if abs(xx - FORD_X) < 22 or blocked(xx, zz):
                    continue
                if h_at(xx, zz) < WATER_LEVEL + 0.35 or slope_at(xx, zz) > 18:
                    continue
                if free(xx, zz, 3.0):
                    add("poplar", xx, zz, float(rs.uniform(0.85, 1.2)), 2.5)
    # аллея тополей вдоль арыка (канала) с запада к лагерю — характерно для Ферганы
    for t in np.linspace(0, 1, 26):
        x = lerp(-330.0, -135.0, t)
        z = lerp(-40.0, -12.0, t) + 6 * math.sin(t * 5)
        for side in (-1, 1):
            xx, zz = x + rs.normal(0, 0.8), z + side * 5.5 + rs.normal(0, 0.8)
            if not blocked(xx, zz) and free(xx, zz, 2.6) and rs.random() < 0.85:
                add("poplar", xx, zz, float(rs.uniform(0.9, 1.25)), 2.4)

    # --- ивы (тал): у самой воды, наклонены к реке
    for x in np.arange(-480, 480, 6.0):
        zc = float(river_z(x))
        hw = float(river_halfwidth(x))
        for side in (1, -1):
            if rs.random() < 0.42:
                xx = x + rs.normal(0, 2.0)
                zz = zc + side * (hw + rs.uniform(3.0, 9.0))
                if abs(xx - FORD_X) < 18 or blocked(xx, zz):
                    continue
                y = h_at(xx, zz)
                if y < WATER_LEVEL + 0.15 or y > WATER_LEVEL + 3.5:
                    continue
                if free(xx, zz, 3.5):
                    add("willow", xx, zz, float(rs.uniform(0.8, 1.2)), 4.0, extra=side)

    # --- арча (можжевельник): на склонах предгорий, группами
    for _ in range(9000):
        x, z = rs.uniform(-HALF + 10, HALF - 10, 2)
        p = 6.0
        r = ((abs(x) / HALF) ** p + (abs(z) / HALF) ** p) ** (1 / p)
        if r < 0.62 or blocked(x, z):
            continue
        s = slope_at(x, z)
        y = h_at(x, z)
        if not (8 < s < 34) or y > 150:
            continue
        clump = 0.5 + 0.5 * fbm(np.array([x]), np.array([z]), 60, 2, seed=SEED + 60)[0]
        if rs.random() > clump ** 2.5 * 0.5:
            continue
        if free(x, z, 2.2):
            add("juniper", x, z, float(rs.uniform(0.7, 1.3)), 2.2)
        if len(out["juniper"]) > 260:
            break

    # --- карагачи у лагеря (тень для коней и стариков)
    for (x, z) in [(-140.0, -10.0), (-150.0, 2.0), (-128.0, 118.0), (10.0, 72.0), (-95.0, -55.0)]:
        if free(x, z, 4.0):
            add("elm", x, z, float(rs.uniform(0.9, 1.15)), 5.0)

    # --- камни и валуны: на холмах и склонах, у гор, по берегам; не на поле и не в лагере
    for _ in range(40000):
        x, z = rs.uniform(-HALF + 4, HALF - 4, 2)
        if blocked(x, z):
            continue
        s = slope_at(x, z)
        y = h_at(x, z)
        p = 6.0
        r = ((abs(x) / HALF) ** p + (abs(z) / HALF) ** p) ** (1 / p)
        want = 0.02 + smoothstep(6, 22, s) * 0.5 + smoothstep(0.7, 0.95, r) * 0.35
        if y < WATER_LEVEL + 0.2:
            want *= 0.2
        if rs.random() > want:
            continue
        big = rs.random() < 0.18
        scale = float(rs.uniform(1.4, 3.2) if big else rs.uniform(0.35, 1.1))
        if free(x, z, scale * 0.8):
            add("rock", x, z, scale, scale * 0.8, extra=int(rs.integers(0, 4)))
        if len(out["rock"]) > 900:
            break

    # --- пятна тумана: русло и низины (x, y, z, rx, rz, высота слоя)
    fog = []
    for x in np.arange(-460, 470, 70.0):
        z = float(river_z(x))
        fog.append([round(float(x), 1), round(WATER_LEVEL - 1.0, 2), round(z, 1), 55.0, 60.0, 7.0])
    for (cx, cz, rad, depth) in HOLLOWS:
        fog.append([cx, round(h_at(cx, cz) - 0.5, 2), cz, rad * 1.1, rad * 1.1, 5.0])
    out["fog"] = fog
    return out


# =====================================================================
# Сборка
# =====================================================================

def build(preview_only=False):
    X, Z = grid_coords(N, SPACING, HALF)
    print("рельеф 513²…")
    H = heights(X, Z).astype(np.float32)
    Xf, Zf = grid_coords(FAR_N, FAR_SPACING, FAR_HALF)
    Hf = heights(Xf, Zf, far=True)
    # внутри карты дальнее кольцо повторяет основной рельеф (для стыка)
    inside = (np.abs(Xf) <= HALF) & (np.abs(Zf) <= HALF)
    # сгладить острые «пирамиды» сетки 32 м (размытие 3 × 3 вне карты)
    pad = np.pad(Hf, 1, mode="edge")
    blur = sum(pad[1 + dj:1 + dj + FAR_N, 1 + di:1 + di + FAR_N] * w
               for dj, di, w in [(0, 0, 0.4), (-1, 0, 0.1), (1, 0, 0.1), (0, -1, 0.1), (0, 1, 0.1),
                                 (-1, -1, 0.05), (1, 1, 0.05), (-1, 1, 0.05), (1, -1, 0.05)])
    Hf = np.where(inside, bilinear(H, np.clip(Xf, -HALF, HALF), np.clip(Zf, -HALF, HALF)), blur).astype(np.float32)
    Nrm = normals(H.astype(np.float64), SPACING)

    # карты почв 1024² (1 м на пиксель, центры пикселей)
    print("карты почв…")
    px = -HALF + (np.arange(1024) + 0.5)
    Xs, Zs = np.meshgrid(px, px)
    Hs = bilinear(H.astype(np.float64), Xs, Zs)
    Ns = np.dstack([bilinear(Nrm[..., k], Xs, Zs) for k in range(3)])
    Ns /= np.linalg.norm(Ns, axis=2, keepdims=True)
    maps = ground_maps(Xs, Zs, Hs, Ns)

    if preview_only:
        return H, Hf, maps, None

    out_world = os.path.join(ROOT, "assets/world")
    out_tex = os.path.join(ROOT, "assets/textures/world")
    os.makedirs(out_world, exist_ok=True)
    H.astype("<f4").tofile(os.path.join(out_world, "height.bin"))
    Hf.astype("<f4").tofile(os.path.join(out_world, "far.bin"))
    to_png(os.path.join(out_tex, "splat.png"), [maps["dry"], maps["earth"], np.maximum(maps["rock"], maps["snow"]),
                                               maps["sand"]], 1024)
    to_png(os.path.join(out_tex, "grass.png"), [maps["dens"], maps["tall"], maps["kovyl"], maps["wet"]], 512)

    print("расстановка…")
    # карты на сетке высот для расстановки
    sc = scatter(H.astype(np.float64), Nrm, None)
    with open(os.path.join(out_world, "scatter.json"), "w", encoding="utf-8") as f:
        json.dump(sc, f, ensure_ascii=False, separators=(",", ":"))

    head = {
        "size": N, "spacing": SPACING, "origin": [-HALF, -HALF],
        "min": round(float(H.min()), 3), "max": round(float(H.max()), 3),
        "far_size": FAR_N, "far_spacing": FAR_SPACING, "far_origin": [-FAR_HALF, -FAR_HALF],
        "far_min": round(float(Hf.min()), 3), "far_max": round(float(Hf.max()), 3),
        "water_level": WATER_LEVEL,
        "river": [[round(float(x), 1), round(float(z), 2), round(float(river_halfwidth(x)), 2)]
                  for x, z in river_polyline(16.0)],
        "ford": [FORD_X, round(float(river_z(FORD_X)), 2)],
        "markers": {
            "camp": [CAMP[0], round(float(bilinear(H, *CAMP)), 3), CAMP[1]],
            "koroo": [KOROO[0], round(float(bilinear(H, *KOROO)), 3), KOROO[1]],
            "jylky": [JYLKY[0], round(float(bilinear(H, *JYLKY)), 3), JYLKY[1]],
            "meadow": [MEADOW[0], round(float(bilinear(H, *MEADOW)), 3), MEADOW[1]],
            "ford": [FORD_X, round(float(bilinear(H, FORD_X, float(river_z(FORD_X)))), 3),
                     round(float(river_z(FORD_X)), 2)],
        },
        "paths": [[list(map(float, p)) for p in pts] for pts in PATHS],
        "files": {"height": "height.bin", "far": "far.bin", "format": "float32 little-endian, rows by z"},
    }
    with open(os.path.join(out_world, "height.json"), "w", encoding="utf-8") as f:
        json.dump(head, f, ensure_ascii=False, indent=1)
    print(f"высоты {H.min():.1f}…{H.max():.1f} м, дальнее кольцо {Hf.min():.1f}…{Hf.max():.1f} м")
    print({k: len(v) for k, v in sc.items()})
    return H, Hf, maps, sc


def preview(H, maps, sc=None):
    """Схема карты: отмывка рельефа + цвета почв + деревья (для проверки глазами)."""
    Nrm = normals(H.astype(np.float64), SPACING)
    sun = np.array([-0.5, 0.75, -0.45])
    sun /= np.linalg.norm(sun)
    shade = np.clip(Nrm @ sun, 0, 1) * 0.9 + 0.2
    img = np.zeros((N, N, 3))
    g = np.array([0.39, 0.38, 0.22])
    def up(m):
        return np.asarray(Image.fromarray((m * 255).astype(np.uint8)).resize((N, N), Image.BILINEAR)) / 255.0
    col = g[None, None] * np.ones((N, N, 1))
    for key, c in (("dry", (0.54, 0.45, 0.28)), ("earth", (0.37, 0.29, 0.2)), ("sand", (0.7, 0.6, 0.43)),
                   ("rock", (0.48, 0.45, 0.4)), ("snow", (0.9, 0.9, 0.92))):
        m = up(maps[key])[..., None]
        col = col * (1 - m) + np.array(c)[None, None] * m
    img = col * shade[..., None]
    water = H < WATER_LEVEL
    img[water] = img[water] * 0.3 + np.array([0.15, 0.3, 0.4]) * 0.7
    im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    if sc:
        from PIL import ImageDraw
        d = ImageDraw.Draw(im)
        cols = {"poplar": (40, 90, 30), "willow": (90, 140, 90), "juniper": (20, 50, 40), "elm": (60, 110, 20),
                "rock": (150, 150, 150)}
        for k, c in cols.items():
            for it in sc[k]:
                i, j = (it[0] + HALF) / SPACING, (it[2] + HALF) / SPACING
                r = 1.5 if k != "rock" else 0.8
                d.ellipse([i - r, j - r, i + r, j + r], fill=c)
    path = os.path.join(ROOT, "renders/world/map_preview.png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.resize((1026, 1026), Image.NEAREST).save(path)
    print("схема:", path)


def main(argv):
    what = argv[1] if len(argv) > 1 else "all"
    if what in ("all", "height", "preview"):
        H, Hf, maps, sc = build(preview_only=(what == "preview"))
        preview(H, maps, sc)
    if what in ("all", "tex"):
        import gen_world_tex
        gen_world_tex.main()
    if what in ("all", "models"):
        import gen_world_models
        gen_world_models.main()


if __name__ == "__main__":
    main(sys.argv)
